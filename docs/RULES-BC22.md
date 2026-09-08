# Battlecode 2022 "Mutation" — the `bc22` year module

`game_config.year = "bc22"` selects this module. It is a behaviour port of
`github.com/battlecode/battlecode22` at commit
**`6ed05b679c0822e9bbe332812ff5655812dd023e`** (`HEAD` of the default branch,
last commit 2023-01-06), and the port is the authority at runtime: the Java
engine exists only as the `parity-oracle-bc22` CI job (`docs/PARITY.md` §bc22).

Nothing about `bc26`, `bc20`, `bc21`, `bc23`, `bc24` or `bc25` changes.
`GameVersion` went **GV09 → GV10** in the commit that added this module and
`ReplayCompatibleGameVersions` was **extended** to
`["GV04","GV05","GV06","GV07","GV08","GV09","GV10"]`, never reset, so every
hosted replay of the six shipped years keeps rendering.

Layout: `src/battlecode/years/bc22/`
(`constants.nim` generated, `units.nim`, `trove.nim`, `world.nim`,
`buildings.nim`, `economy.nim`, `anomaly.nim`, `rules.nim`, `maps.nim`,
`knobs.nim`) plus `src/battlecode/years/bc22/chassis/`
(`kit.nim`, `econ.nim`, `archon.nim`, `miner.nim`, `builder.nim`,
`soldier.nim`, `micro.nim`, `lab.nim`, `gold.nim`, `anomaly.nim`, `comms.nim`,
`wololo.nim`, `scaffold22.nim`, `scenario22.nim`).

## The game in one paragraph

Two factions of robots on a symmetric grid between 20×20 and 60×60. Each starts
with **1 to 4 ARCHONS** (600 HP) and **200 lead**, and **lose your last archon
and you lose immediately**. Archons build **MINERS** (50 Pb) that dig lead and
gold out of the squares, **BUILDERS** (40 Pb) that put up **LABORATORIES**
(180 Pb — the only source of gold in the game) and **WATCHTOWERS** (150 Pb),
**SOLDIERS** (75 Pb, 3 damage, and the whole human metagame), and **SAGES**
(20 Au, 45 damage, one shot every twenty turns, and the only unit that can
*envision an anomaly*). Buildings can be **mutated** to level 2 (lead) and
level 3 (gold) and can **transform** between TURRET mode (act, do not move) and
PORTABLE mode (move, do not act) — so an archon can get up and walk. Every
square carries **rubble** (0…100) which multiplies every cooldown paid on it by
`1 + rubble/10`. **The map regenerates +5 Pb every 20 rounds on every square
that still holds at least 1 Pb**, so a miner that takes a square to zero kills
that deposit for the rest of the game. Gold enters the map only when a robot
dies (20 % of its build cost, dropped where it stood) or when a laboratory
manufactures it, at `⌊20 − 18·e^(−k·n)⌋` lead per gold in the number `n` of
friendly robots the lab can see — **two lead a gold standing alone, eleven with
forty friends nearby**. Each map ships a fixed, PUBLIC **anomaly schedule** of
roughly one event per 200 rounds: **ABYSS**, **CHARGE**, **FURY** and
**VORTEX**. At round 2000 the **SINGULARITY** consumes the weaker team on a
three-rung ladder.

## The round loop — the step list IS the rules

Re-ordering any of these is a rules change and bumps `GameVersion`.

1. **Beginning of round.** `currentRound += 1`, then every robot's
   `processBeginningOfRound`, which clears the indicator string and nothing
   else — a no-op here. **There is no round-1 special case**: both teams' 200 Pb
   and 0 Au are credited by the world's constructor, once, PER TEAM (not per
   archon), before round 1 begins.
2. **Turn order.** A SNAPSHOT of the dynamic exec order taken before the sweep,
   with an `existsRobot` guard. The list is append-on-spawn and by-value removal
   on death. The INITIAL archons are appended in ASCENDING ID, because
   `LiveMap`'s constructor sorts them — and the official maps carry archon ids
   BELOW the 10 000 `IDGenerator` floor (`maze`: 2, 3, 6, 7, 8, 9), so A and B
   alternate in the opening order.
3. **Each robot's turn.** Both cooldowns decay by 10 and floor at 0; the
   `DecisionOps` budget resets; the controller runs; `roundsAlive += 1`; a robot
   that disintegrated is destroyed at the end of its OWN turn. **Both cooldowns
   start a robot's life at ZERO**, so a droid built on round *r* takes its first
   turn on round *r+1* and can act AND move on it — the opposite of bc23, and
   why bc22 armies grow so fast.
4. **End of round, in exactly this order.**
   a. `+2` lead to team A, then `+2` to team B — **before** the anomaly.
   b. Every robot's end of round, whose body in 2022 is the comment
      `// anything` and nothing else — a genuine no-op.
   c. The scheduled anomaly, if one is due; **exactly one entry is consumed**.
   d. The map's `+5` to every square holding `> 0`, every 20 rounds — **after**
      the anomaly.
   e. Roll over the per-round team deltas.
   f. The Singularity ladder at round 2000: **more archons** →
      **greater gold net worth** → **greater lead net worth** → **coin flip**.
   g. `running = false` if a winner is set; then the state hash.

## The unit table, verbatim

| unit | Pb | Au | act cd | move cd | HP 1/2/3 | dmg 1/2/3 | heal 1/2/3 | act r² | vis r² | L2 cost | L3 cost |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ARCHON` | 0 | 100 | 10 | 24 | 600/1080/1944 | −2/−4/−6 | 2/4/6 | 20 | 34 | 300 Pb | 80 Au |
| `LABORATORY` | 180 | 0 | 10 | 24 | 100/180/324 | 0 | 0 | 0 | 53 | 150 Pb | 25 Au |
| `WATCHTOWER` | 150 | 0 | 10 | 24 | 150/270/486 | 4/8/12 | 0 | 20 | 34 | 150 Pb | 60 Au |
| `MINER` | 50 | 0 | **2** | 20 | 40 | 0 | 0 | 2 | 20 | — | — |
| `BUILDER` | 40 | 0 | 10 | 20 | 30 | −2 | 2 | 5 | 20 | — | — |
| `SOLDIER` | 75 | 0 | 10 | 16 | 50 | 3 | 0 | 13 | 20 | — | — |
| `SAGE` | 0 | 20 | 200 | 25 | 100 | 45 | 0 | 25 | 34 | — | — |

**A MINER's action cooldown of 2 against a `COOLDOWN_LIMIT` of 10 means a miner
can mine up to FIVE times in one turn on rubble-free ground** — and exactly once
on rubble 60. That is load-bearing, not a curiosity: it is why the whole lead
economy is miner-count-driven, and `tests/test_bc22_cooldown.nim` pins it.

## §Divergences

Every one of these is a deliberate, argued departure from either the published
spec's prose or the JVM, and every one has a test.

1. **No bytecode instrumentation.** The engine's per-robot bytecode limits
   (`ARCHON` 20 000, `MINER`/`SOLDIER`/`SAGE`/`WATCHTOWER` 10 000, `BUILDER`
   7 500, `LABORATORY` 5 000) have no meaning outside the JVM instrumenter and
   are replaced by a fixed **`DecisionOps` budget of 2 000 / 1 250 / 750 / 500**
   — the same convention bc20, bc21, bc23, bc24 and bc25 use, which is one
   tenth of the Java limit for the ARCHON (20 000), the BUILDER (7 500) and the
   LABORATORY (5 000). The four types on the 10 000 limit get **1 250 and not
   1 000**, deliberately: a bc22 miner's nine-square scan plus its
   mine-move-mine turn is the busiest primitive sequence in the year, and the
   round number would cut it short on the measured maps. The port is generous
   in the direction that cannot change a RULE — a chassis that is not cut off
   emits the same orders a chassis with more budget would. The budget is checked BEFORE each primitive and never inside
   one, so a primitive's RESULT is never a function of the remaining budget;
   when it runs out the robot's turn ends where it stands and is **not** resumed
   mid-computation next turn, which is the one place this differs from the JVM.
   **Measured over eight full 2000-round games, the 2022 example bot peaks at
   680–760 bytecodes — 6–7 % of its 10 000 limit, always a MINER — with ZERO
   mid-turn cut-offs**, so the divergence is provably not exercised by the
   oracle. The parity job does not assume that: it reads the `bc=` column and
   fails if any robot on any round exceeds **50 %** of its limit.
2. **`setWinnerArbitrary`'s `Math.random()`** is wall-clock seeded and therefore
   not reproducible. A draw from the world RNG (`Random(mapSeed)`) replaces it.
   Reachable only when archons, gold net worth AND lead net worth are all tied.
3. **`ObjectInfo.eachRobot` is a trove hash-order sweep, and in 2022 it needs NO
   PORT AT ALL.** It has exactly three call sites.
   `processBeginningOfRound` clears the indicator string, which this port does
   not have. `processEndOfRound` calls `InternalRobot.processEndOfRound`, whose
   body in 2022 is the comment `// anything` and nothing else. `resign()` is the
   third and is unreachable from a JSON doctrine. So — unlike bc23, where the
   argument had to be about commutativity — here there is no observable
   behaviour to order. Stated explicitly so nobody ports it "to be safe".
4. **`ObjectInfo.robotsArray()`'s trove order IS load-bearing, at exactly one
   site, and it is PORTED rather than replaced.** `robotsArray()` is trove's
   `values(V[])`, which walks the open-addressing table from the highest index
   down to 0. `setWinnerIfMoreGoldValue` and `setWinnerIfMoreLeadValue` are sums
   and are order-free; `causeChargeGlobal` is **not** — it collects every DROID
   in that order, stable-sorts descending by friendly-robots-in-vision and
   destroys the first `(int)(0.05f × n)`, so a tie at the cut is broken by the
   trove order. **Measured with a purpose-built probe over 600 rounds on three
   maps, a tie straddles the cut in 51 %, 55 % and 58 % of sampled rounds**, and
   30–40 % of the scheduled anomalies on the shipped maps are CHARGE — so a
   substituted tie-break would diverge in nearly every game at its first charge.
   `years/bc22/trove.nim` therefore reproduces trove4j **3.0.3**'s
   `TIntObjectHashMap`, INCLUDING its auto-compaction, and is **bit-exact
   against the released jar's own `gnu.trove` classes over 5 × 2000 random
   put/remove sequences**. This is a FIDELITY REQUIREMENT, not a divergence.
   The parity trace carries a per-round `H hashord=` line so Tier A compares it
   EVERY round rather than only on charge rounds.
5. **`net.sf.jsi`'s `RTree` has no port.** `ObjectInfo` adds, moves and deletes
   robot ids in a spatial index and **never queries it**: every radius query in
   the engine goes through `GameWorld.getAllRobotsWithinRadiusSquared`, which
   enumerates squares. Worth stating twice, because the dead upstream
   `net.sf.jsi` artifact is what forced bc21's 94-file shim, and here it is both
   **bundled in the jar** (so the oracle needs no shim) and **behaviourally
   dead** (so the port needs no index).
6. **`RobotControllerImpl.random` is a `static` field, reassigned in every
   controller constructor, and never read.** Not ported.
7. **Nine places where the spec's prose and the engine disagree, all resolved
   against the engine.**
   1. **A transform charges exactly ONE cooldown counter, not both.** The prose
      says "increases both of the Building's cooldowns by 100".
      `RobotControllerImpl.transform()` flips the mode FIRST and then charges
      `TRANSFORM_COOLDOWN` to the ACTION counter if the new mode is TURRET and
      to the MOVEMENT counter otherwise. The untouched counter is invisible
      because the new mode gates it, and `canTransformCooldown()` reads the
      MODE-APPROPRIATE counter — so the engine is self-consistent and the prose
      is wrong.
   2. **The rubble multiplier truncates and is evaluated in float64.**
      `(int)((1 + getRubble(location) / 10.0) * cooldown)` is a float64 divide, a
      float64 multiply and a TRUNCATION — **not** the integer form. Measured on
      the JVM over `rubble 0…100 × base ∈ {2,10,16,20,24,25,100,200}`, the two
      disagree on **22 of the 808 pairs**, always by one and always with the
      float one lower: `base 25 rubble 36 → 114` (integer form 115),
      `base 100 rubble 13 → 229`, `base 200 rubble 92 → 2039`. The whole lattice
      is tabled in `data/bc22/tables.json` with the 22 differing pairs flagged.
   3. **Where the multiplier is read.** `addActionCooldownTurns` /
      `addMovementCooldownTurns` read `this.location` at the moment they are
      called: `move()` moves the robot FIRST and charges at the DESTINATION (the
      engine's own comment says so), every other action charges at the actor's
      own unchanged square, and `mutate()` charges the BUILDER at the builder's
      square and the BUILDING's 100+100 at the building's square.
   4. **The passive lead is added BEFORE the anomaly and the map regeneration
      AFTER it.** The engine's own changelog claims the opposite;
      `processEndOfRound` does not. So an ABYSS on round *r* eats 10 % of a
      reserve that already includes that round's `+2`, and it does not touch a
      `+5` that has not happened yet.
   5. **CHARGE ranks BOTH teams' droids together, and under 20 droids it kills
      nobody.** The ranking is global, so a clumped faction donates victims
      while a spread one loses none, and `(int)(0.05f × n)` is **0 for every
      `n ≤ 19`** (measured: 19→0, 20→1, 39→1, 40→2, 59→2, 60→3). Archons,
      laboratories and watchtowers are never DROID, so CHARGE can never kill a
      building — including a PROTOTYPE one.
   6. **FURY truncates, and only touches TURRET mode.** `(int)(-1 × maxHealth ×
      0.05f)`, a float32 product truncated toward zero. Measured: a level-1
      watchtower loses **7**, not 8; a level-2 watchtower 13; a level-3 archon
      97; a level-1 archon 30; a level-1 laboratory 5. **A building in PORTABLE
      mode and a PROTOTYPE take NOTHING.** This is the year's largest
      unexploited play and `anomaly_play` is the knob that reaches it.
   7. **FURY's own elimination check skips the archon rung.** `addHealth(…,
      false)` is called with `checkArchonDeath = false`, so a fury that destroys
      archons does not fire `ANNIHILATION` from inside `destroyRobot`;
      `causeFuryUpdate` then checks both teams afterwards, and **if both are
      eliminated in the same fury it goes straight to
      `setWinnerIfMoreGoldValue → …LeadValue → setWinnerArbitrary`, skipping
      `MORE_ARCHONS`.** That is the only path by which `more_gold_net_worth`,
      `more_lead_net_worth` or `coin_flip` can fire **before** round 2000.
   8. **ABYSS truncates in float32, so a small pile is immune.** Measured: a
      square holding 1…9 Pb loses 0; 10→1, 25→2, 99→9, 100→10, 300→30. The team
      reserve loses `−⌊reserve/10⌋`.
   9. **Archon ids are below 10 000 and fix the initial turn order** — see step 2
      of the round loop.
8. **`resignation` is reachable in the engine through `rc.resign()` and
   unreachable here.** A doctrine is a JSON sheet and neither chassis calls it.
   Recorded as *unreachable here*, not *absent upstream*, and
   `tests/test_bc22_endladder.nim` asserts no chassis reaches it. It is
   therefore absent from the manifest's `end_reason` enum.
9. **The laboratory's `Math.exp` is computed through `fdlibm` and TABLED over
   its whole reachable domain.** `Math.exp` is specified to be within 1 ulp and
   is a HotSpot intrinsic, so it is allowed to differ between JVMs;
   `StrictMath.exp` is specified to be exactly the fdlibm algorithm and in
   practice HotSpot agrees with it on this domain (the bc21 argument,
   unchanged). The whole `3 × 177` `(level, n)` table is generated into
   `data/bc22/tables.json` by the jar's own classes and READ at run time, so the
   runtime path has no transcendental at all; `tests/test_bc22_economy.nim`
   regenerates it through `fdlibmExp` and asserts the two agree.
10. **The `deadline` wall-clock stop is a coworld concept and not an engine
    one.** It is recorded as ONE load-bearing record (`plan.abandonAfter[g]`)
    applied by the same proc on record and on playback.
11. **22 of the 75 official maps are converted.** Everything above 1 600 squares
    is out of the played pool for wall-clock reasons (four are converted anyway,
    under `large`); `maptestsmall` (rubble uniformly 1 and 1 016 lead squares
    totalling 49 788 — an engine test fixture, not a game) and `squer` (204 lead
    on 625 squares and no anomalies — a starvation map) are converted for
    neither pool; the remaining 53 are simply not converted in v1.
    `tools/convert_maps_bc22.py --parse-all` reads all 75 in CI, because a
    reader that only works on the maps we ship is a reader nobody can extend the
    pool with.
12. **The doctrine-sheet envelope unwrap is YEAR-NEUTRAL and the absent-key
    counting is bc22-ONLY.** `sheet.nim` now resolves a `doctrine` key and a
    single object-valued key as well as `sheet`, and records which rule fired in
    `Sheet.envelope`. Counting an ABSENT known key in `defaults_applied` is done
    in `years/bc22/knobs.nim` alone, because doing it year-neutrally would
    change what a bc26/bc20/bc21/bc23/bc24/bc25 episode records in that array.
    Neither change can reach a recording: `replay.nim` re-validates the recorded
    APPLIED sheet wrapped in `{"sheet": …}`, and an applied sheet is always a
    flat object of known keys — which is why `ReplayCompatibleGameVersions`
    extends rather than resets.
13. **Both chassis are BEHAVIOUR PORTS parameterised by the doctrine sheet**,
    never vendored code. `NOTICE` names each source file and what derives from
    it. `IvanGeffner/BC22` carries no licence and was not cloned, not read and
    contributes nothing.
14. **The chassis file layout is exactly the design note's**, and `NOTICE`,
    `knobs.nim`'s doc comments and this file all point at the same paths. No two
    modules were merged.
15. **Four shared-endcard template fixes**, which change what EVERY year's
    endcard renders: this year's nouns instead of bc26's, no clipping or
    overflow at 1280×800, no raw unrounded floats (every number goes through one
    `fmtStat`), and no empty mottos or article-plus-enum grammar. bc25's and
    bc23's phase-60 verifications both found the same defects and both handed
    them forward; this run fixes them for all years in one commit.
16. **Two chassis balance rules that are NOT in any source bot** and are this
    coworld's own, measured in phase 20 and recorded in `lab.nim`: the
    laboratory leaves an ARMY RESERVE of `soldier_sage_ratio × 2` lead, and it
    stops transmuting once the gold share of the attack budget is already at or
    over the ratio. Without them the lab drained the team below a soldier's
    75 Pb every round and the `chalice` mirror built THREE soldiers in two
    thousand rounds while making 1 588 gold — the knob having no teeth in the
    direction that matters.

## The doctrine sheet

Eleven knobs, and **no `chassis` key** (D1: a submitted `chassis` is recorded in
`sheet_unknown_fields` and never honoured). Unknown key, wrong type or
out-of-range value takes that field's default and the repair is recorded —
except the five INTEGER knobs, which **clamp**. **An ABSENT known key is also
recorded** (§Divergences item 12).

| field | type / values | default |
|---|---|---|
| `opening` | `soldier_rush` \| `miner_eco` \| `sage_spam` | `miner_eco` |
| `miner_count_curve` | `lean` \| `steady` \| `heavy` | `steady` |
| `mine_floor` | int 0…5 | 1 |
| `soldier_sage_ratio` | int 0…100 | 65 |
| `lab_round` | int 1…1800 | 300 |
| `lab_solitude` | int 0…40 | 12 |
| `gold_use` | `sages` \| `mutations` | `sages` |
| `watchtower_policy` | `never` \| `home` \| `forward` | `home` |
| `anomaly_play` | `ignore` \| `time_pushes` | `time_pushes` |
| `archon_relocate` | `never` \| `safety` \| `lead` | `safety` |
| `retreat_hp` | int 0…100 | 40 |

**THE ANTI-INERT RULE.** No setting of any knob, and no combination of
settings, may produce an inert or self-starving faction. Independently of every
knob the chassis always keeps at least **three miners per archon** digging,
builds a soldier whenever lead allows and the soldier census is under target,
spends an archon's action rather than banking it, answers an enemy attacker
sensed within r² ≤ 20 of one of its own archons, repairs a damaged droid
standing in an archon's r² ≤ 20, and **never lets its last archon enter PORTABLE
mode while an enemy attacker is sensed within eight squares**.

## Scoring

```
share(x, y) = if x + y == 0: 0.5'f32 else: f32(x) / f32(x + y)
points[t]   = int(64·share(archons) + 24·share(goldNetWorth)
                + 12·share(leadNetWorth))          # TRUNCATION, float32 shares
results.scores[t] = 200·(games t won) + mean(points[t])
```

The weights are super-increasing (`24 > 12`, `64 > 24 + 12`), so a **decisive**
margin on a higher rung dominates everything below it. **This is all that is
claimed**: a one-unit margin on a rung with large totals gives an arbitrarily
small share advantage, so `points` alone CAN favour the loser.
`results.scores` is win-dominated by construction and its ordering provably
agrees with `results.wins`; `tests/test_bc22_scoring.nim` asserts that on 500
random synthetic finals and asserts the `points`-disagreement case explicitly,
so neither is mistaken for a bug later.

## Playback pacing, measured

The bc22 wasm re-derivation is heavy enough to need the bc21 pacing treatment:
the phase-60 viewer check is dispatched with **`settle=20000 soak=15`** and
`ci.yml`'s `wasm-viewer` job runs the bc22 replay at `--timeout 120 --soak 15`.
Measured natively in phase 20, a whole 2000-round `wololo` mirror plays in
**0.3–0.9 s** on the six `small` maps and on `fisherman` (45×35) with the
heaviest doctrine, i.e. **well under 0.5 ms a round**; the browser's Worker
re-simulates from the start of the game on every seek, which is what the settle
is for.
