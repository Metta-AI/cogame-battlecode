# Battlecode 2019 "Crusade" — the `bc19` year module

`game_config.year = "bc19"` selects this rule set. It is a **behaviour port of
`battlecode/battlecode19` at commit
`80cf1cc535ec5a30559274aa1b49807ad4859925`** (GPL-3.0), written in Nim from
reading `coldbrew/`; no JavaScript is vendored and no JavaScript runtime
exists in any image this repository builds. The 2019 engine survives only as
the `parity-oracle-bc19` CI job and as `tools/gen_maps_bc19.mjs`, which runs
at build time.

**THE 2019 SPEC EXISTS ONLY AS `coldbrew/specs.json` PLUS
`app/src/views/docs.js`**, and where the two disagree **the engine wins**. All
seven disagreements are tabled below.

---

## The game in one paragraph

Two orders of robots on a **square, procedurally generated, mirror-symmetric**
grid between **32×32 and 64×64**. Each order starts with **1 to 3 CASTLES**
(200 HP, cannot be built), **100 karbonite** and **500 fuel**. Castles and
churches build **PILGRIMS** (the only unit that can mine and the only one that
can build a **CHURCH**), **CRUSADERS**, **PROPHETS** and **PREACHERS**. Every
action burns fuel from the global store and **the only passive income in the
game is a flat 25 fuel per team per round** — karbonite has none at all.
**Destroy the enemy's last castle and you win on the spot**; otherwise the
game runs to round 1000 and is decided on castles, then on the total health of
all live units, then on a coin flip.

## The unit table — verbatim from `coldbrew/specs.json`

| # | unit | build K | build F | K cap | F cap | speed r² | fuel/r² | HP | vision r² | dmg | attack r² | attack fuel | spread r² |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | `CASTLE` | cannot be built | — | `null` | `null` | 0 | `null` | 200 | 100 | 10 | 1…64 | 10 | 0 |
| 1 | `CHURCH` | 50 | 200 | `null` | `null` | 0 | `null` | 100 | 100 | 0 | **`0` — a SCALAR** | 0 | 0 |
| 2 | `PILGRIM` | 10 | 50 | 20 | 100 | 4 | 1 | 10 | 100 | `null` | `null` | `null` | `null` |
| 3 | `CRUSADER` | 15 | 50 | 20 | 100 | **9** | 1 | 40 | 49 | 10 | 1…16 | 10 | 0 |
| 4 | `PROPHET` | 25 | 50 | 20 | 100 | 4 | 2 | 20 | 64 | 10 | **16…64** | 25 | 0 |
| 5 | `PREACHER` | 30 | 50 | 20 | 100 | 4 | **3** | 60 | 16 | 20 | 1…16 | 15 | **3** |

The table is **generated** into `src/battlecode/years/bc19/constants.nim` by
`tools/gen_year_constants.py --year bc19` and byte-diffed in CI, so it is
provably the engine's and provably not hand-typed.

## The round loop — and the step list IS the rules

Re-ordering any of it is a rules change and bumps `GameVersion`.

1. **The driver loop** (`runtime.js:58-76`), repeated until it stops:
   1. drain the init queue — in this port every robot is handed its side's
      chassis at the moment it is created;
   2. **evaluate `isOver()` — BEFORE EVERY SINGLE TURN, not at the end of a
      round.** Two consequences: a game that ends by castle annihilation stops
      **immediately after the killing robot's turn** and the rest of that
      round's robots do not act; and **round 1000 consists of exactly ONE
      robot turn** (measured: 999 full rounds plus one turn, 6 994 turns on
      `seed-0043`);
   3. if not over, `enactTurn()`.
2. **`enactTurn`** (`game.js:746-788`): if `robin >= robots.len`, `robin = 0`,
   `round += 1` and **+25 fuel to each team**; `robot.turn += 1`; the chess
   clock is credited (V1); the chassis runs and **an exception is swallowed**;
   a **fresh** `ActionRecord` is validated (rule 4) and then enacted (rule 6).
3. **The observation** (`getGameStateDump`, `:667-736`): the vision shadow,
   the `visible` roster after a five-step field-stripping ladder, and the
   three maps **only on `turn == 1`**.
4. **Validation** (`processAction`, `:804-930`), in the engine's own order:
   the signal first (which computes the `temp_fuel` every later affordability
   test reads), then castle talk, then the six-name action whitelist, then
   `trade` and `mine` which **return before the `dx`/`dy` gate**, then the
   gate, then `build` / `give` / `move` / `attack`. **A validation failure
   leaves the record with whatever was already set**, so an illegal `move`
   still performs the signal that was validated before it.
5. **`isOver`** (`:537-614`): one census pass then a seven-rung ladder.
6. **`record.enact`** (`action_record.js:319-339`): `robin += 1` FIRST, then
   the three broadcast fields (**all three default to 0, so a robot that
   broadcasts nothing silently clears last turn's broadcast**), then the
   signal's fuel **charged once per turn for the final radius only**, then
   the action.
7. **Death** (`_deleteRobot`, `:933-943`): the shadow square is cleared, the
   robot is spliced out of the array, and **`robin` is decremented when the
   removed index was below it**. Ids are never returned to the pool.

## The end ladder

| rung | condition | engine `win_condition` | our `end_reason` |
|---|---|---|---|
| 1 | both sides failed to initialise | 4 | **unreachable here (V6)** |
| 2 | one side failed to initialise | 3 | **unreachable here (V6)** |
| 3 | one side has no castles, the other does | 0 | `castles_destroyed` |
| 4 | neither side has a castle | 2 | `coin_flip` |
| 5 | round 1000, castle counts differ | 0 | `more_castles` |
| 6 | round 1000, castles level, health differs | 1 | `more_unit_health` |
| 7 | round 1000, castles and health level | **1 — see below** | `coin_flip` |

**The `win_condition = 1` overwrite is reproduced literally.** At
`game.js:604` the engine executes `this.win_condition = 1;` **unconditionally**
at the end of the round-1000 else block, after the inner branch has already
set 2 for the coin-flip case. So a round-1000 all-square game is *recorded by
the engine* as "greater health" while the winner really is a coin flip. The
port keeps **both**: `results.games[].win_condition` carries the engine's own
integer and `end_reason` carries the finer-grained truth.

## Scoring

```
share(x, y)  = if x + y == 0: 0.5'f32 else: f32(x) / f32(x + y)
points[t]    = int(64 * share(castles)  + 24 * share(unit health)
                 + 12 * share(karbonite + fuel div 5 + Σ build K))
scores[t]    = 200 * (games won) + mean(points over games played)
```

`fuel div 5` is the **engine's own exchange rate**: one `mine` action buys 2
karbonite or 10 fuel. The weights are super-increasing, but **`points` alone
can favour the loser** — a one-castle margin on a 3-vs-2 board is 12.8 points
against 36 available below — which is why the win bonus is 200 and not 100.

## The doctrine sheet — eleven knobs, and NO `chassis` key

Their types, ranges, defaults and notes are generated from
`src/battlecode/years/bc19/knobs.nim` into the prompt, so a knob cannot exist
in the sim and be missing from the brief. A submitted `chassis` key is
recorded in `sheet_unknown_fields` and never honoured.

| knob | values | default | what it actually decides |
|---|---|---|---|
| `opening` | `turtle` \| `preacher_rush` \| `pilgrim_eco` | `pilgrim_eco` | the first 300 rounds' budget split and posture. `pilgrim_eco` buys miners and takes the late game; `preacher_rush` buys PREACHERs before round 300 and walks them at the enemy; `turtle` buys PROPHETs and parks them on the lattice. |
| `pilgrim_curve` | 0…24 | 9 | the pilgrim census target per structure, capped by the number of depots the order can actually reach — a target above the depot count buys miners that stand still. **0 still builds one pilgrim per structure**: the floor that keeps 0 from starving. |
| `church_expansion` | `never` \| `mid` \| `early` | `mid` | when a PILGRIM spends 50 karbonite / 200 fuel raising a CHURCH. A church is a second build queue and a second deposit point, and it is 100 HP standing on its own in the field — the exposure is part of the price. |
| `fuel_reserve` | 0…2000 | 300 | **the fuel floor below which the order stops making WAR, not the floor below which it stops making MONEY.** Fuel is what everything in this year is priced in and a PILGRIM is the only thing that makes it — +10 a turn for 1, against a flat 25 a round for the whole order. Gate the economy behind the reserve and the order deadlocks *at* the reserve: it cannot afford the miner that would lift it over the line, and it stands on a full karbonite bank until round 1000 (measured, literal reading, `seed-0043` and `seed-0048`: **3 280 karbonite banked, four military units, zero damage**). So the reserve gates **military builds, attacks and military movement**; `mine`, `move` and economy builds are funded whenever the order can pay. Raising it buys survival and sells aggression, which is exactly the trade the knob test asserts: **rounds at zero fuel down, attacks down.** |
| `unit_mix` | 0…100 | 45 | the PROPHET share of the military karbonite budget. A prophet outranges everything (r² 16…64) and cannot shoot close; a crusader is the only fast unit (SPEED 9). Turning this up trades tempo for reach. |
| `preacher_share` | 0…100 | 20 | the PREACHER share **of the remainder**, so the crusader share is `(100 − unit_mix) × (100 − preacher_share) / 100`. A preacher's blast is nine squares with **no team check and no attacker exclusion**, so this knob buys splash kills and pays for them in friendly fire. |
| `church_saber_round` | 0…1000 | 0 | the round from which a pilgrim may raise a church **in the enemy's half**. 0 never does it. It is a raid on the enemy's depots that also hands them a 100-HP target. |
| `symmetry_wall` | `off` \| `screen` \| `wall` | `screen` | what the order builds on the mirror line, which **both sides know from round 1**. `wall` closes the midline — and closes it against your own miners too, which is why the knob test asserts your own pilgrims' mean walk length goes **up**. |
| `castle_talk_use` | `position` \| `census` \| `full` | `census` | what the free, 8-bit, unlimited-range, castle-only channel carries, and therefore **whether two structures can avoid making the same decision twice in one round**. `position` sends the two opening coordinate bytes and then nothing: the structures are blind to each other and both queue the same unit. `census` adds the rotating `0b0 \| unit:3 \| bucket:4` digit, so a structure counts this round's queue as already built and takes a *different* job — measured on `seed-0043`, duplicate builds **177 → 6** across the sweep. `full` adds `0b01 \| alert:6` under-attack flags on the turns they fire. **The unconditional economy floor is never divided**: three castles that all need a miner on round 1 all build one, whatever this knob says (measured with the floor divided: one side built **eight units and mined forty karbonite in a thousand rounds**). |
| `defend_radius` | 1…400 | 100 | the r² inside which an own structure's neighbourhood is answered. Low sends the army out and gets your pilgrims farmed for reclaim; high keeps it home and lets the enemy mine in peace. |
| `trade_policy` | `never` \| `mirror` \| `offer_fuel` \| `offer_karbonite` | `mirror` | this year's largest unexploited mechanic. A CASTLE may propose `(karbonite, fuel)`; when both orders' standing offers match element-wise the swap executes and both offers clear. **A matching pair that is not payable clears both offers and then throws**, so a policy that offers what it cannot pay burns its own standing offer for nothing. |

**The anti-inert rule.** No setting of any knob, and no combination of
settings, may produce an inert or self-starving order. `saber` always keeps at
least one pilgrim on a karbonite depot and one on a fuel depot, builds a
military unit whenever karbonite and fuel allow and the census is below its
target, never fewer than two military per structure, answers any enemy inside
`defend_radius` of a structure, **never fires a PREACHER when the blast would
kill more of its own units than the enemy's**, and **never `give`s to an enemy
structure**.

## Where the docs are wrong — seven disagreements, and the engine wins

| # | the docs say | the engine does |
|---|---|---|
| 1 | a broadcast of squared radius X² costs X fuel (`docs.js:164`) | `ceil(sqrt(signal_radius))` — the docs' own worked example agrees with the engine while the prose does not |
| 2 | ids are 32-bit and 1…4096 (`docs.js:145,240`) | drawn from **1…4095** without replacement from a pool that is **never refilled**, by a rejection loop that **hangs forever** at exhaustion |
| 3 | the round-1000 tiebreak is "more total health" (`docs.js:138`) | sums `robot.health` over **every** live unit of the team, not just its castles |
| 4 | the third rung is a distinct coin-flip outcome | `win_condition = 1` is assigned **unconditionally** afterwards |
| 5 | giving over capacity loses the excess "to the void" (`docs.js:260`) | the amount is **reduced first** and only the reduced amount is deducted — **nothing is lost** |
| 6 | each `signal` call costs fuel (`docs.js:267`) | the fuel is charged **once**, for the last radius only |
| 7 | attack is for crusaders, prophets and preachers (`docs.js:261`) | **a CHURCH attack is ACCEPTED** as a legal 0-damage 0-fuel action that consumes the turn |

## Divergences — every rule this port does NOT reproduce, with its reason

1. **V1 — the wall-clock chess clock is not ported.** `robot.time` starts at
   `CHESS_INITIAL = 100` ms, gains `CHESS_EXTRA = 20` ms a turn and loses the
   turn's measured `wallClock()` elapsed; a robot below zero is frozen. **It
   is driven by the wall clock and is therefore not reproducible even between
   two runs of the engine itself.** It is replaced by a `DecisionOps` clock at
   a fixed 20 ops per millisecond: `ChessInitialOps = 2000`,
   `ChessExtraOps = 400`, `TurnMaxOps = 4000`, and **`TurnChargeOps = 400`, an
   exact constant deliberately equal to the refill**. The theorem: because the
   per-turn charge equals the per-turn refill, `chessOps` is **invariant at
   2000 for every robot for its whole life**, so no robot is ever frozen and
   the engine's `robot.time < 0` branch is unreachable here.
   **Why the charge may not be the chassis's real op count**: the freeze rule
   is an *engine* rule, so deriving its input from the chassis's own work
   would make the chassis's implementation a rules input — a one-line
   refactor of `saber`'s navigator would change what a round resolves to.
   `TurnMaxOps` is separately a real compute cap: checked **before** each
   primitive and never inside one, read by no rule, and measured at a peak of
   **461 of 4000** in a real mirror game.
2. **V2 — the `visible`-array shuffle is not ported.** `getGameStateDump`
   shuffles it with the **global, unseeded `Math.random()`**
   (`game.js:717-722`). Measured: **five distinct orders in six identical
   runs** of seed 1. The port presents `visible` in **ascending robot `id`**
   and `tools/oracle/bc19/visible_order.patch` puts the same order on the
   **engine** side, so the normalisation is symmetric.
3. **V3 — maps are generated at BUILD time and committed.** `regions.sort`
   (`game.js:153`) passes a **one-argument, sign-constant comparator**, so the
   result is V8-implementation-defined (measured: a plain reversal in 42 of 42
   multi-region cases, keeping a non-largest region in 40 of them); and **13
   of the first 400 seeds produce unplayable boards** with 2–4 passable
   squares and zero castles. `tools/gen_maps_bc19.mjs` runs the pinned engine
   under the pinned Node, curates for playability, and commits the board
   **together with the 624-word MT19937 state immediately after `makeMap()`
   returns**, so the runtime draws castle ids from exactly the state the
   engine would have.
4. **V4 — the id pool cannot hang.** The engine's rejection loop never
   terminates once all 4 095 ids are spent. The port reproduces the loop
   exactly and adds **one guard the engine lacks**: at `ids.len >= 4095` a
   `build` is **refused** instead of looped. Degrade, never hang.
5. **V5 — no `.bc19` byte replay, no `vis.js`, no `vm2`, no transpilers, no
   `logs`/`error` channels.** The log channels carry `wallClock()` timestamps
   and nothing a score or a spectator reads.
6. **V6 — win conditions 3 and 4 are unreachable** and `record.timeout()` /
   `enactTimeout` are dead code upstream. Recorded as *unreachable here*
   rather than *absent upstream*.
7. **V7 — `robot.time` is in neither the observation nor the trace**: it is
   wall-clock derived, so exposing it would make a prompt and a parity trace
   non-reproducible.
8. **V8 — `MAX_MEMORY` has no port**: the check is commented out in the engine
   itself (`vm.js:15-22`).
9. **The seven docs-vs-engine disagreements above**, each resolved in the
   engine's favour.
10. **The three `null`/scalar coercions are real rules.** A CHURCH's
    `ATTACK_RADIUS` is the scalar `0`, so a church attack is a legal
    zero-damage zero-fuel action that consumes the turn; a PILGRIM's is
    `null`, so `null[1]` throws and a pilgrim attack is a **validation
    failure**; and a CASTLE's and a CHURCH's capacities are `null` with
    `Math.min(n, null) === 0`, so **a structure that lands a kill reclaims
    exactly nothing**.
11. **The two committed hunks of the example bot's patch.** The stock bot
    draws its direction from the wall-clock-seeded global RNG (so it is not
    reproducible even against itself) and gates its castle build on
    `this.me.team == 1` (so **RED never builds anything at all**). Both are
    patched, in CI only. A baseline that is completely inert on one of the two
    sides cannot be scored, cannot fill a league and makes the survival gate
    meaningless.
12. **The `deadline` wall-clock stop** is a coworld concept and not an engine
    one, recorded as one load-bearing record (`plan.abandonAfter[g]`) applied
    by the same proc on record and on playback.
13. **Both chassis are ours.** `saber` is a behaviour port of the GPL-3.0
    `m-schier/battlecode-2019-wololo`; `examplefuncsplayer19` is a
    statement-for-statement port of the engine repository's own example bot
    and **may not gain behaviour**, because it is one side of the
    differential oracle.
14. **`fuel_reserve` GATES THE WAR, NOT THE ECONOMY.** The design note
    describes it as "the global fuel floor below which the order funds only
    `mine` and `move`". Implemented literally, that **deadlocks** an order at
    exactly the reserve: a PILGRIM is the thing that *makes* fuel (+10 a turn
    for 1, against a flat 25 a round for the whole order), so gating the
    economy behind the reserve means the order cannot afford the miner that
    would lift it over the line. Measured in phase 20 with the literal
    reading on `seed-0043` and `seed-0048`: **3 280 karbonite banked, four
    military units, zero damage, for a thousand rounds.** The gate therefore
    applies to **military builds, attacks and military movement**, and
    economy builds are funded whenever the order can pay. The knob's two
    asserted teeth are unchanged: rounds at zero fuel down, attacks down.
15. **The score's `fuel div 5` exchange rate** is derived from
    `KARBONITE_YIELD` and `FUEL_YIELD`, and the *winner* is decided on the
    engine's exact integer comparisons while *points* are decided on float32
    shares — so the two can disagree on a razor-thin margin. Stated
    explicitly, tested explicitly, and not a bug.
16. **`castle_separation_min` and `castle_separation_max` are the only two
    non-integer numbers bc19 reports.** They are Euclidean distances between
    two squares and there is no integer reading of them, so they are printed
    to one decimal. Every other bc19 statistic is an exact integer, because
    the 2019 rule set has no float state at all — and the two exceptions
    are **derived board descriptions, not simulation state**: nothing reads
    them back, no rule branches on them and no parity trace line carries
    them, which is why the comparator still needs no float allowlist.
17. **CASTLE TALK IS EMIT-ONLY IN THIS PORT.** Every unit sends its byte
    every turn and the layouts are the design note's own field widths
    (`0b10 | x:6`, `0b11 | y:6`, `0b0 | unit:3 | bucket:4`,
    `0b01 | alert:6`) — but the port never DECODES one, so those four
    layouts are deliberately not a partition (a census digit whose unit
    ordinal has bit 2 set sits in the alert tag's space). A castle's
    knowledge of its own team comes from the per-team `Side` controller
    instead, which is exactly what the engine's own rule makes equivalent:
    a castle reads the castle talk of **every** own-team unit on the board
    at **any** range (`game.js:708-710`), so anything one own-team unit
    knows, every own-team castle knows in the same round. What the knob
    still decides is real and measured: whether the digit is *sent*, and
    therefore whether the structures divide their build queue (see the knob
    table).

## Playback pacing, measured

A whole 1000-round `saber` mirror game costs **0.03–0.10 s** in `-d:release`
on the four maps measured in phase 20 — the lightest year module in this
repository, and an order of magnitude inside the design note's own 0.6–2.5 s
estimate. bc19 therefore takes the **standard** viewer probe
(`--timeout 90 --soak 10`, `settle=700 soak=10` at phase 60) and joins
bc26/bc20/bc21 rather than the heavy set. The `docker-smoke` step prints
`sim_seconds / rounds` on every run; **if the measured value ever exceeds
3 ms/round, bc19 moves to the heavy set and this paragraph is the record of
why.**
