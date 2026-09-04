# Battlecode 2024 "Breadwars" — the `bc24` year module

The `bc24` variant of this coworld is a deterministic Nim port of the
Battlecode 2024 rule set, played by **doctrine**: each of the two cogs writes
one sealed JSON sheet of ten knobs at t=0 and the simulation plays the whole
best-of-three from those two sheets.

Everything below was read out of `github.com/battlecode/battlecode24` at commit
**`166c79bbf4156c866caf434062cb1f403c01695f`**, file by file, and cross-checked
against the published **`battlecode24-3.0.5.jar`**. Where the spec's prose and
the engine disagree, **the engine wins** and the disagreement is recorded here.

The Java engine exists in this repository **only** as the `parity-oracle-bc24`
CI job. There is no JDK, no JRE, no Java and no Node in any image stage.

---

## The world

Two clans of **fifty identical ducks** on a symmetric grid between 30×30 and
59×59 in the shipped set (`GameConstants` allows 20…60). One unit type, no unit
cost, no unit cap beyond the fixed fifty.

| constant | value | constant | value |
|---|---|---|---|
| `GAME_MAX_NUMBER_OF_ROUNDS` | **2000** | `SETUP_ROUNDS` | **200** |
| `ROBOT_CAPACITY` (per team) | **50** | `NUMBER_FLAGS` | **3** |
| `DEFAULT_HEALTH` | **1000** | `JAILED_ROUNDS` | **25** |
| `INITIAL_CRUMBS_AMOUNT` | **400** | `PASSIVE_CRUMBS_INCREASE` | **10** |
| `KILL_CRUMB_REWARD` | **30** | `GLOBAL_UPGRADE_ROUNDS` | **600** |
| `VISION_RADIUS_SQUARED` | **20** | `ATTACK_RADIUS_SQUARED` | **4** |
| `HEAL_RADIUS_SQUARED` | **4** | `INTERACT_RADIUS_SQUARED` | **2** |
| `COOLDOWN_LIMIT` | **10** | `COOLDOWNS_PER_TURN` | **10** |
| `MOVEMENT_COOLDOWN` | **10** | `FLAG_MOVEMENT_COOLDOWN` | **20** |
| `ATTACK_COOLDOWN` | **20** | `HEAL_COOLDOWN` | **30** |
| `DIG_COST` / `DIG_COOLDOWN` | **20 / 20** | `FILL_COST` / `FILL_COOLDOWN` | **30 / 30** |
| `PICKUP_DROP_COOLDOWN` | **10** | `FLAG_DROPPED_RESET_ROUNDS` | **4** |
| `FLAG_BROADCAST_UPDATE_INTERVAL` | **100** | `FLAG_BROADCAST_NOISE_RADIUS` | **100** |
| `MIN_FLAG_SPACING_SQUARED` | **36** | `SHARED_ARRAY_LENGTH` / max value | **64 / 65 535** |
| `BYTECODE_LIMIT` | **25 000** (replaced — §Divergences 1) | | |

`src/battlecode/years/bc24/constants.nim` is **generated** from
`common/GameConstants.java`, `common/SkillType.java`, `common/TrapType.java`
and `common/GlobalUpgrade.java` by `tools/gen_year_constants.py --year bc24`
and byte-diffed in CI.

### The three traps

| trap | cost | trigger r² | on enter | on dig/fill/build | build cooldown | visible to the enemy |
|---|---|---|---|---|---|---|
| `EXPLOSIVE` | **200** | **0** (its own tile only) | **750** damage, r² ≤ **4** | **200** damage, r² ≤ **2** | 5 | no |
| `WATER` | **100** | **2** | digs every unoccupied, passable, un-trapped, non-spawn land tile in r² ≤ **9** | — | 5 | no |
| `STUN` | **100** | **2** | **sets** enemy movement *and* action cooldowns to **40**, r² ≤ **13** | — | 5 | no |

The javadoc above `TrapType.EXPLOSIVE` says "sqrt 13 radius" and "500 damage".
**The enum's constructor arguments are the authority** and they say r² ≤ 4 and
750/200; the port and the generated table follow the arguments.

### The three global upgrades

`ATTACK` +60 base damage; `HEALING` +50 base heal; `CAPTURING` +21 rounds to
the **opponent's** dropped-flag return delay (4 → 25) **and** −8 to this team's
flag-carry movement cooldown (20 → 12). One point a team at rounds **600,
1200, 1800**; each upgrade at most once. `ACTION` is a
backwards-compatibility alias of `ATTACK`, shares its slot, and is not offered
on the doctrine surface.

### Specialisation, and THE TWO ROUNDING REGIMES

| level | attack XP | build XP | heal XP | damage | damage +ATTACK | attack cd | heal | heal +HEALING | heal cd |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 150 | 210 | 20 | 80 | 130 | 30 |
| 1 | 15 | 5 | 20 | 158 | **220** | 19 | 82 | 134 | 29 |
| 2 | 30 | 10 | 40 | 161 | 225 | 19 | 84 | 137 | 27 |
| 3 | 45 | 15 | 70 | 165 | 231 | 18 | 86 | 139 | 26 |
| 4 | 75 | 20 | 100 | 195 | 273 | 16 | 88 | 143 | 26 |
| 5 | 110 | 25 | 140 | 203 | 284 | 13 | 92 | 150 | 26 |
| 6 | 150 | 30 | 180 | 240 | 336 | 8 | 100 | 163 | 23 |

Build level scales crumbs and cooldown together: dig costs
`20, 18, 17, 16, 14, 12, 10`, an explosive `200, 180, 170, 160, 140, 120, 100`,
and the trap build cooldown falls `5, 5, 5, 4, 4, 4, 3`.

**The two regimes are load-bearing.** Read them off the engine:

* **Damage and heal are a Java `float`.** `InternalRobot.getDamage()` is
  `Math.round(base * ((float) skillEffect / 100 + 1))` — a **float32** product
  through `Math.round(float)`.
* **Every cooldown and every crumb cost is a Java `double`.**
  `attack`/`heal`/`build`/`dig`/`fill` all compute
  `(int) Math.round(C * (1 + .01 * pct))`, where `.01` is a `double` literal —
  a **float64** product through `Math.round(double)`.

They disagree, and the design note's own table has one cell wrong because of
it: at attack level 1 with the ATTACK upgrade, `210 * 1.05f` is
220.4999995 in float32 and `Math.round(float)` gives **220**, not the note's
221. A float64 product would give 221. `data/bc24/skills.json` is generated
from the released jar's own classes, byte-diffed in CI by `parity-oracle-bc24`
Tier B over the WHOLE FINITE DOMAIN, and `tests/test_bc24_levels.nim` asserts
both regimes on the values where they part.

`Math.round` under JDK 8 is not "round half away from zero": it is
`(a != <greatest value below 0.5>) ? floor(a + 0.5) : 0`, with the addition
performed **at the argument's own width**. Both carve-outs are reproduced in
`skills.nim`.

**Mastery.** `InternalRobot.incrementSkill` lets a skill gain while
`exp < experience(3)` **or** neither other skill has reached level 4. So at
level 4 in one skill the other two freeze at 3, and the mastered one climbs to
6. **Filling earns no build XP** (patch 1.1.0); digging and trap-building do.

**The jail penalty** hits the duck's **best** skill on the way into jail, ties
broken attack → build → heal, and is skipped entirely when all three
experiences are 0: attack `−1,−2,−2,−5,−5,−10,−12`; build
`−1,−2,−2,−3,−3,−4,−6`; heal `−1,−5,−5,−10,−10,−15,−18`, each clamped at 0.

---

## The round loop

`rules.nim`'s `runRound` mirrors `GameWorld.runRound` /
`processBeginningOfRound` / `updateDynamicBodies` / `processEndOfRound` step for
step. **Re-ordering any of it is a rules change and bumps `GameVersion`.**

1. **Flag broadcast re-roll, then the round counter.** *Before* the increment:
   if `currentRound % 100 == 0` — true entering rounds **1, 101, 201, …**,
   because `currentRound` is still the previous value — every flag in
   `allFlags` order gets a new `broadcastLoc = nearLocs[rand.nextInt(len)]`,
   where `nearLocs` is `getAllLocationsWithinRadiusSquared(flag.loc, 100)` in
   **engine scan order**. Then `currentRound += 1`. Then, if
   `currentRound % 600 == 0`, **both** teams gain one upgrade point. Then every
   duck's `processBeginningOfRound` (the indicator string and `diedLocation`).
2. **Round-1 endowment.** If `currentRound == 1`, each team is credited **400**
   crumbs — *inside* `runRound`, after the beginning-of-round sweep, which is
   why a duck cannot spend it on round 0.
3. **Turn order.** The **fixed exec order**: the hundred ducks created
   `A₀, B₀, A₁, B₁, …, A₄₉, B₄₉` in the world's constructor, with ids drawn
   from `IDGenerator(map.randomSeed)` in that order. Ducks are **never
   destroyed** — death is a *despawn* — so the exec order never changes for the
   whole game, and `eachDynamicBodyByExecOrder`'s skip-if-deleted branch is
   dead code in 2024. **Every duck takes a turn whether spawned or not.**
4. **Beginning of turn.** `actionCooldown`, `movementCooldown` and
   `spawnCooldown` each become `max(0, x − 10)` — for a jailed duck too — and
   the `DecisionOps` budget is reset to **2 500**.
5. **Run the controller**, under that team's chassis and doctrine.
6. **End of turn.** Every queued trap fires now, **in queue order**, each
   removing itself and de-registering over r² ≤ 2. Then `roundsAlive += 1` —
   for jailed ducks too. **Despawn** sets `spawnCooldown = 250`, applies the
   jail penalty, and drops any carried flag **on the duck's own tile**.
7. **End of round.** Both teams are credited **10** crumbs (in `runRound`,
   *before* `processEndOfRound`); if `currentRound == 200` the flag placements
   are confirmed per team independently; if the setup phase is over the
   dropped-flag return timers tick; then the end ladder, first hit wins —
   **more flags captured** → **higher sum of all skill levels over all fifty
   ducks, jailed included** → **more crumbs** → **coin flip**. A `capture` win
   set during the turn sweep is *not* re-decided here.
8. **Hash chain.** Append this round's state hash.

### Three subtleties the port reproduces literally

* **A capture win does not stop the round.** `TeamInfo.captureFlag` sets the
  winner the instant the third flag lands, but `running` is only cleared at
  step 7 — so every duck after the capturer in the exec order still takes its
  turn that round. `tests/test_bc24_endladder.nim` pins it.
* **`flag.getLoc() != flag.getStartLoc()` is a Java OBJECT IDENTITY test**, not
  a coordinate test. The port carries an explicit `locIsStartRef: bool` — set
  by the start-location writer, cleared by every pickup, drop and reset — and
  never compares coordinates. A flag dropped *exactly on its own start tile*
  therefore still runs a return timer and cannot be picked up in the round it
  was dropped.
* **`spawn()` resets neither cooldown.** The engine's two lines are commented
  out. It is harmless only because twenty-five jail turns already decayed them
  to zero; the port reproduces the engine, not the intent.

### Deliberate non-rules, verified absent from the 2024 engine

No unit type but the duck and no unit cost; no resign action a doctrine can
reach; `DominationFactor.MORE_FLAGS_PICKED` exists but `checkEndOfMatch` never
calls it, so it is a **dead rung** and is not in our enum; no terrain that
slows movement (only walls, water and the setup-phase dam block it); walls are
never destroyed and spawn zones can never be dug or covered.

---

## The doctrine sheet — ten knobs, and no `chassis` key

| field | type / values | default |
|---|---|---|
| `specialisation_split` | `attack` \| `heal` \| `build` \| `balanced` | `balanced` |
| `flag_rush_round` | int **201 … 1200** | 450 |
| `trap_budget` | int **0 … 60** (percent of crumb income) | 30 |
| `trap_placement` | `choke` \| `flag_ring` \| `spawn_ring` | `flag_ring` |
| `trap_mix` | `stun` \| `explosive` \| `mixed` | `mixed` |
| `heal_priority` | `wounded_first` \| `attackers_first` \| `carrier_first` | `wounded_first` |
| `water_dig_policy` | `none` \| `choke_dig` \| `moat` \| `fill_paths` | `choke_dig` |
| `upgrade_order` | 3 distinct of `attack` \| `heal` \| `capture` | `["attack","heal","capture"]` |
| `retreat_hp` | int **100 … 900** | 400 |
| `flag_carry_escort` | int **0 … 6** | 2 |

The census `specialisation_split` cuts: `balanced` **6 / 16 / 28**, `attack`
**4 / 10 / 36**, `heal` **5 / 24 / 21**, `build` **10 / 14 / 26**
(builders / healers / attackers). Every value keeps ≥ 3 builders, ≥ 10 healers
and ≥ 18 attackers.

**`chassis` is NOT a knob** (D1). A submitted `chassis` is recorded in
`sheet_unknown_fields` and never honoured;
`tests/test_bc24_sheet.nim` fails if anyone re-adds it.

**No setting of any knob produces an inert or self-starving flock.** Whatever
the sheet says, `gone-sharkin` always spawns every duck it can, always walks
crumbs off the floor, always keeps the census floors, always defends a flag it
senses under threat out of a reserved 100-crumb floor, always answers a sensed
enemy, always commits to an enemy flag by `flag_rush_round` (whose range
cannot express "never"), and **always opens a water crossing when the map has
no land route** (§Divergences 12). `tests/test_bc24_knobs.nim` proves each knob
has teeth and `tests/test_bc24_survival.nim` proves the floor holds, with an
inverted control behind `-d:bc24BrokenChassis` that **must** fail.

## The two chassis

* **`gone-sharkin`** — the strong published baseline and the champion chassis.
  A **behaviour** port (never code) of `chenyx512/battlecode24` `src/bot1/`
  (AGPL-3.0, `bf245ef`; the 1st-place bot), with the navigator and
  shared-array discipline of `jmerle/battlecode-2024`
  `src/camel_case_v21_final/` (AGPL-3.0, `d10ddcc`), the BFS and comms layout
  of `andli28/bc2024` `src/mainbot/` (AGPL-3.0, `4040df7`) and the
  carrier-return micro of `davidteather/battlecode_24` `src/submit6/`
  (AGPL-3.0, `d129abf`). Parameterised by the ten knobs. Credited in `NOTICE`.
* **`examplefuncsplayer24`** — the deliberately weak floor and the parity
  oracle's other side, ported **statement for statement** from
  `example-bots/src/main/examplefuncsplayer/RobotPlayer.java`. **It needs no
  determinism patch** — unlike 2021's, this bot seeds its own
  `java.util.Random(6147)` and never calls `Math.random()` — so the oracle's
  Java side is upstream's file **byte for byte**. It may not gain behaviour.

`PLAYER_SCRIPTED` resolves **per year**: on `bc24`, `awu` / `gone-sharkin` /
anything unrecognised is **`gone-sharkin`**, and `scaffold` /
`examplefuncsplayer` / `examplefuncsplayer24` / `example` is
**`examplefuncsplayer24`**. The manifest's `player[]` is unchanged at
`awu` + `scaffold`.

### The shared-array word format

64 slots, one 16-bit word each, and it is the chassis's — a doctrine cannot
redefine it: `0–2` own flag `i` as `[x:6][y:6][state:4]`, `3–5` enemy flag `i`
last known as `[x:6][y:6][age:4]`, `6–8` own-flag distress, `9` the upgrade
ledger, `10–12` spawn-zone congestion, `13–15` rally points, `16–47` a coarse
8×8 enemy-sighting grid with saturating counts, `48–63` role claims.

---

## Scoring

```
share(x, y) = if x + y == 0: 0.5'f32 else: f32(x) / f32(x + y)
points[t]   = int(60.0'f32 * share(caps[t],   caps[o])
                + 25.0'f32 * share(levels[t], levels[o])
                + 15.0'f32 * share(crumbs[t], crumbs[o]))   # TRUNCATION
results.scores[t] = 100.0 * (games t won) + mean(points[t] over games played)
```

The three terms are exactly the engine's three deciding rungs in the engine's
own priority order. Every share is narrowed through **float32** and the sum is
**truncated**, for recorder/re-deriver agreement: the same arithmetic runs
natively on x86-64 and in wasm32 and must produce the same integer. `share`
returns **0.5 on a 0–0 total**, which is the deliberate difference from bc21's
`x / max(1, total)`: a great many honest bc24 games end 0–0 on captures.

`end_reason` per game: `capture`, `more_flag_captures`, `level_sum`,
`more_bread`, `coin_flip`, and our own wall-clock `abandoned`.
`results.reason` per episode is unchanged: `complete` / `deadline` / `fault`.

---

## Maps

**22 of the 78 official maps** are converted by `tools/convert_maps_bc24.py`
and **committed**; CI re-converts and byte-diffs. `mixed` (12) is the `bc24`
variant's pool, `small` (6) is what the parity oracle and the docker smoke run
on, `large` (6) is reserved.

Every size, seed, declared symmetry, dam/water/wall count and crumb table in
the design note's own table was read out of the real `.map24` flatbuffers and
is asserted by `tests/test_bc24_maps.nim`. All 78 parse cleanly with the
converter's own vtable reader.

Two engine-side transforms are applied **once, at conversion time**:
`if (amt < 100) amt *= 10` on every resource pile, and the six
`spawnLocations` centres painted out to r² ≤ 2 discs into a per-tile spawn-zone
array. `spawn_centers` is then **re-derived** off that array exactly as
`LiveMap.getSpawnZoneCenters` does — index-ascending, A into the even slots,
including the engine's own row-wrapping neighbour test — because that order
decides flag ids and therefore the broadcast re-roll order.

**Two of the six `small` maps have no land route between the two halves.**
`Rivers` and `Tunnels` are separated by water as well as by the dam, so
nothing can reach anything until somebody fills a crossing. That is a real
property of the shipped maps, confirmed against the Java engine, and it is
what §Divergences 12 exists for.

Excluded: everything above 2 700 tiles is out of the played pools for
wall-clock reasons; `QuestionableChess` and `Racetrack` have **zero** crumb
piles, which collapses the whole build half of the game; the remaining 52 are
simply not converted in v1 and the converter handles any `.map24`.

---

## §Divergences

1. **No bytecode instrumentation.** The engine's per-duck 25 000-bytecode
   limit has no meaning outside the JVM instrumenter and is replaced by a
   fixed **2 500 `DecisionOps`** budget — one tenth, the convention bc20 and
   bc21 use. One credit for each tile sensed, duck or flag examined, BFS node
   expanded, direction evaluated, shared-array slot touched and
   trap-placement candidate scored; deducted in `chassis/kit.nim` and
   **enforced by the sim, not by the bot**. When it runs out the duck's turn
   ends where it stands: it is **not** resumed mid-computation next turn,
   which is the one place this differs from the JVM.
   **And in bc24 that divergence is provably not exercised by the oracle.**
   Measured over five full 2000-round games, the example bot's peak bytecode
   use was **297…783 of 25 000 (1.2…3.2 %)** with **zero** mid-turn cut-offs,
   and the scenario bot's **796…940 (3.2…3.8 %)**. So Tier A's bit-exact
   window is the **whole game**, and the job asserts the headroom rather than
   assuming it: it fails if any duck ever exceeds 50 % of the limit (25 % for
   the scenario bot).
   Full metering is out of scope: it needs either a Nim-level instrumenter (a
   compiler project) or a hand-annotation of every statement against
   `MethodCosts.txt`, and neither buys anything the budget does not.
2. **`setWinnerArbitrary`'s `Math.random()`** is wall-clock seeded and
   therefore not reproducible; a draw from the **world RNG** (seeded from the
   map's own `randomSeed`, exactly as the engine seeds it) replaces it.
   Reachable only when captures, level sums and crumbs are all tied at round
   2000.
3. **The three `objectInfo.eachRobot` hash-order sweeps** the engine performs
   (`processBeginningOfRound`'s clear, the end-of-round record and
   `TeamInfo.getLevelSum`) are replaced by ascending-exec-order sweeps. All
   three are order-independent: the first is per-duck idempotent, the second is
   recording, the third is an integer sum.
4. **Java object-identity flag comparisons** are reproduced by an explicit
   `locIsStartRef` boolean rather than coordinate equality (see above).
5. **`MORE_FLAGS_PICKED` and `RESIGNATION` are unreachable dead rungs** and are
   absent from our `end_reason` enum: `checkEndOfMatch` never calls the first,
   and no action a JSON doctrine can reach produces the second. `ACTION` is
   likewise not offered on the upgrade surface.
6. **The `deadline` wall-clock stop** is a coworld concept and not an engine
   one. It is recorded as ONE load-bearing record (`plan.abandonAfter[g]`) and
   applied by the same proc on record and on playback (the particle-worlds
   scar).
7. **No indicator strings, dots or lines, no profiler, no crossplay, no
   `.bc24` output.** The replay is one UTF-8 JSON document and the browser
   re-derives every frame.
8. **The spec's "30×30 to 60×60" versus `GameConstants.MAP_MIN_* = 20`.** The
   shipped set's smallest is 30×30; the converter accepts ≥ 20.
9. **The released 3.0.5 jar versus the master sources** differ only in the
   `SPEC_VERSION` string (`"3.0.5"` against `"3.0.6"`). Every gameplay
   constant is identical, and `parity-oracle-bc24` Tier B **proves** that by
   cross-checking all 53 of them against the jar's own classes.
10. **22 of the 78 official maps are converted**, with the reasons above.
11. **Both chassis are behaviour ports** parameterised by the doctrine sheet,
    never vendored code. The unlicensed XSquare / IvanGeffner repositories are
    not read, ported, compiled or referenced.
12. **The chassis always keeps a route to the enemy open.** After the dam
    falls, if no enemy spawn centre is reachable **over land**, the builders
    fill the cheapest crossing **whatever `water_dig_policy` says** — because
    that knob is about where crumbs go, not about whether the flock can play,
    and `Rivers` and `Tunnels` are water-locked maps in the shipped `small`
    pool. This is a CHASSIS rule, not a rules change: it emits ordinary `fill`
    actions that the engine would accept, and the parity oracle (which drives
    `examplefuncsplayer24` and the scenario bot, not `gone-sharkin`) is
    untouched by it.
13. **`choke_dig` digs a `r² ≤ 2` corridor around each measured choke, not a
    wider one.** An eight-radius version was tried and it walled the flock's
    OWN raiders in — precisely the self-starving setting the LEARNINGS pin
    forbids.
14. **`moat` leaves a three-tile gap** on the friendly-facing side of each
    flag's Chebyshev-2 ring, for the same reason.

---

## Measured performance

A full 2000-round game with both flocks on the all-defaults sheet costs
**0.27…0.90 s** in release Nim on one core (Yinyang 0.28 s, DefaultLarge under
the perf gate's worst-case doctrine well inside its budget) against the Java
engine's **≈ 15 s** for the same 2000 rounds. `tests/test_bc24_perf.nim`
asserts the budget in release only; a debug build runs about seven times
slower and asserting a wall clock against it would be measuring the wrong
binary. The sanctioned fix if that gate ever goes red is ONE config value,
`gamesPerMatch: 3 → 1` in the `bc24` variant, not a redesign.

The viewer's playback pacing follows from the same measurement: bc24 seeks
re-simulate from the start of the game, so the phase-60 check-8 dispatch uses
`settle=20000 soak=15` and `ci.yml`'s `wasm-viewer` job runs the bc24 replay
at `--timeout 120 --soak 15`.
