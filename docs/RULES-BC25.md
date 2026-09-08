# Battlecode 2025 "Chromatic Conflict" — the `bc25` year module

The rules this repository plays under `game_config.year = "bc25"`, the ten
doctrine knobs, and every place the port deliberately differs from the engine
or from the published spec.

**Everything here was read from `github.com/battlecode/battlecode25` at commit
`28975a487c1a30ed2b5bed644fe6ecd2c3dd1482`** (`master`, last commit
2025-01-26). The port is the authority at runtime; the Java engine exists only
as the `parity-oracle-bc25` CI job, only as the published
`battlecode25-java-3.1.0.jar`, and **in no image this repository builds**.

---

## The game in one paragraph

Two clans of robot bunnies paint a symmetric grid between 20×20 and 60×60. The
score *is* the colour of the map: the first clan to hold **70 % of
`width × height − walls`** wins on the spot, a clan that loses every robot
**and** every tower loses on the spot, and otherwise round **2000** decides it
on **area painted** first. Paint is also the fuel — below 50 % of capacity a
robot's cooldowns lengthen, and at zero it cannot move, cannot act and bleeds
**20 HP a turn**.

---

## The round loop

Six steps. **The step list is the rules**: a re-ordering is a rules change and
bumps `GameVersion`. It mirrors `GameWorld.runRound` /
`processBeginningOfRound` / `updateDynamicBodies` / `processEndOfRound`.

1. **Beginning of round.** `currentRound += 1`; then
   `updateResourcePatterns()` walks `resourcePatternCenters` **in list order**
   — a centre whose pattern is broken is dropped and its lifetime **reset to
   0**, a centre that still matches has its lifetime **incremented**; then
   every unit runs `processBeginningOfRound`: messages older than
   `MESSAGE_ROUND_DURATION = 5` rounds are dropped, and **towers mine**. A
   paint tower adds `paintPerTurn + 3 × (active SRPs of its team)` to **its
   own stash** (capped at 1000); a money tower adds the same shape to the
   **team chip pool**. The SRP bonus is **per mining tower**, not per team.
2. **Turn order.** `ObjectInfo.dynamicBodyExecOrder` is a plain
   append-ordered list with **by-value removal**. A unit built is appended; a
   unit destroyed is removed from wherever it sits and everything after it
   shifts forward. The sweep iterates a **snapshot taken before it starts**,
   so a unit built this round takes no turn this round, and a unit destroyed
   mid-sweep is skipped by the `existsRobot` guard.
3. **Beginning of turn.** `sentMessagesCount = 0`; both tower attack flags
   clear; `actionCooldown = max(0, actionCooldown − 10)`;
   `movementCooldown = max(0, movementCooldown − 10)`; the `DecisionOps`
   budget resets to **1 750** (robots) or **2 000** (towers).
4. **Run the controller.** The legal actions and their exact preconditions are
   in `src/battlecode/years/bc25/world.nim` (robots), `towers.nim` (towers)
   and `comms.nim` (messages), each `can*` beside its `do*`.
5. **End of turn**, for a **robot** only, in this order: the territory bill
   (bare `−1`, enemy `−2`, own `0`, all **doubled for a mopper**); the
   crowding bill (`−n` on bare or own ground, `−2n` on enemy ground, where `n`
   is the allied **units** within r² ≤ 2 **including towers**); then `−20 HP`
   if the stash is now exactly 0; then `roundsAlive += 1`.
6. **End of round.** The coverage per mille
   `round(painted × 1000.0 / areaWithoutWalls)`, the money snapshot, then the
   end ladder, then the state hash.

### Four subtleties, each with its own test

- **A paint win fires mid-action and does not stop the round.**
  `TeamInfo.addPaintedSquares` runs `checkWin` on **every tile recolour**, so a
  clan can cross 70 % inside a splasher's AoE loop; `running` is only cleared
  at step 6, so every unit after the winner still takes its turn.
  (`tests/test_bc25_endladder.nim`)
- **`totalPaintedSquares` is a LIVE count.** `setPaint` moves one from the old
  owner to the new one and is a **no-op on an unpaintable tile**, so mopping a
  tile bare lowers a clan's count and painting a wall does nothing. The port's
  field is called `livePainted`. (`tests/test_bc25_paint.nim`)
- **The exec-order list is mutated by value.**
  (`tests/test_bc25_execorder.nim`)
- **The crowding penalty counts towers.** (`tests/test_bc25_penalties.nim`)

---

## The four 5×5 patterns

The engine **ignores** the `paintPatterns` array the map file carries and uses
four hard-coded ints. `getPatternBit(pattern, dx, dy)` is
`(pattern >> (5 × (dx + 2) + dy + 2)) & 1`; **bit 1 is the SECONDARY colour**.
With `dy = +2` on top and `dx = −2` on the left:

| `RESOURCE` 28873275 | `PAINT` 18157905 | `MONEY` 15583086 | `DEFENSE` 4685252 |
|---|---|---|---|
| `SSPSS` | `SPPPS` | `PSSSP` | `PPSPP` |
| `SPPPS` | `PSPSP` | `SSPSS` | `PSSSP` |
| `PPSPP` | `PPSPP` | `SPPPS` | `SSSSS` |
| `SPPPS` | `PSPSP` | `SSPSS` | `PSSSP` |
| `SSPSS` | `SPPPS` | `PSSSP` | `PPSPP` |

All four are invariant under all eight square symmetries, which is why the
engine's rotation logic is commented out. **The tower check skips the centre
tile**; the SRP check does not, and additionally demands that all 25 tiles are
paintable.

Colour encoding is the engine's: `0` bare, `1` A-primary, `2` A-secondary,
`3` B-primary, `4` B-secondary. Markers use a separate per-team 0/1/2 alphabet
in **two arrays**, so a marker is invisible to the enemy.

---

## The ten doctrine knobs

`src/battlecode/years/bc25/knobs.nim` is the table; the brief is generated
from it, so a knob cannot exist in the sim and be missing from the prompt.

| field | values | default |
|---|---|---|
| `opening` | `paint_eco` \| `tower_rush` \| `balanced` | `balanced` |
| `unit_mix` | `{soldier, mopper, splasher}` 0…100, clamped to 30/10/10 and normalised to 100 | `{60, 25, 15}` |
| `srp_priority` | 0…100 | 35 |
| `tower_type_order` | 3 distinct of `money` \| `paint` \| `defense` | `[money, paint, defense]` |
| `ruin_claim_radius` | 4…20 | 10 |
| `defense_tower_chokes` | `never` \| `late` \| `early` | `late` |
| `paint_reserve_floor` | 10…70 | 30 |
| `mop_enemy_paint` | 0…100 | 40 |
| `splash_targets` | `towers` \| `territory` \| `mixed` | `mixed` |
| `upgrade_policy` | `never` \| `paint_first` \| `money_first` \| `defense_first` | `money_first` |

**There is no `chassis` key** (D1). A submitted one is recorded in
`sheet_unknown_fields` and ignored.

**No setting of any knob may produce an inert or self-starving clan.** The
strategy surface lives inside one competent chassis, and
`tests/test_bc25_survival.nim` (competence, with an inverted control) and
`tests/test_bc25_knobs.nim` (named, signed deltas) are what keep that true.

---

## Scoring

```
share(x, y) = if x + y == 0: 0.5'f32 else: f32(x) / f32(x + y)
points[t]   = int(55·share(area) + 20·share(towers) + 10·share(chips)
                  + 10·share(paint) + 5·share(bots))        # TRUNCATION
scores[t]   = 200·(games won) + mean(points over games played)
```

The five terms are exactly the engine's five deciding rungs in the engine's
own priority order, so a win on any rung always comes with the winner's
weighted sum strictly above the loser's. The **200**-per-game bonus (not
bc24's 100) is what makes the ordering of `results.scores` **provably** agree
with `results.wins`.

---

## Divergences

Every one of these is a place the port deliberately differs from the engine,
from the published spec, or from the design note — and each is either
unreachable in play or argued safe here.

1. **No bytecode instrumentation.** `ROBOT_BYTECODE_LIMIT = 17 500` and
   `TOWER_BYTECODE_LIMIT = 20 000` have no meaning outside the JVM
   instrumenter. They are replaced by a fixed **`DecisionOps` budget of 1 750
   (robots) and 2 000 (towers)** — one tenth of the Java limits, the same
   convention bc20, bc21 and bc24 use. The budget is checked **before** each
   primitive and never inside one, so a primitive's *result* is never a
   function of the remaining budget; when it runs out the unit's turn ends
   where it stands and is **not** resumed mid-computation next turn, which is
   the one place this differs from the JVM.
   **Measured**: over six full 2000-round games the 2025 example bot's peak
   bytecode use was **2 460–2 622, i.e. 14.1–15.0 % of 17 500**, with **zero**
   mid-turn cut-offs — so the divergence is never exercised by the oracle, and
   `parity-oracle-bc25` **fails loudly** if any unit ever exceeds 50 % of its
   limit rather than assuming it.
2. **`setWinnerArbitrary`'s `Math.random()`** is wall-clock seeded and not
   reproducible. It is replaced by a draw from a world RNG seeded from the
   map's own `randomSeed`. Reachable only when area, towers, chips, paint and
   robot counts are **all** tied at round 2000.
3. **`processBeginningOfRound` sweeps in ascending id**, where the engine
   sweeps in `ObjectInfo.eachRobot` hash order (trove `forEachValue`). Safe,
   and the argument is: the sweep only clears per-unit state, tops up a
   tower's **own** capped paint stash, and adds to a **commutative** team chip
   total. No branch in it reads another unit's state.
4. **The spec's "1 paint to mark" is not implemented by the engine.**
   `GameWorld.setMarker` charges nothing, so a bare `mark()` is free here too.
   (Divergence from the *prose*, not from the engine.)
5. **The 70 % denominator is `width × height − walls`**, which counts ruin and
   tower tiles that can never be painted. On `DefaultSmall` (20×20, 28 walls,
   12 ruins) the denominator is **372**, so the threshold is **261** tiles out
   of the **360** that are actually paintable — **72.5 %** of real paintable
   area, not 70 %. The port divides by `areaWithoutWalls`, exactly as
   `TeamInfo.addPaintedSquares` does, and the viewer shows **both** numbers.
   (Divergence from the *prose*.)
6. **`RESIGNATION` is reachable in the engine and unreachable here.**
   `RobotControllerImpl.resign()` is a real method, but a doctrine is a JSON
   sheet and neither chassis calls it; the engine's other resignation trigger,
   `MAX_TEAM_EXECUTION_TIME`, is a JVM wall-clock rule with no port. It is
   therefore absent from `end_reason` — recorded here as **unreachable here**
   rather than **absent upstream**, which is the distinction bc24's note could
   not draw.
7. **The map's `paintPatterns` array is read and then ignored**, exactly as
   `GameWorld` does ("//ignore patterns passed in with map and use hardcoded
   values"). The converter reads it so the reader is provably complete.
8. **`MAX_TURNS_WITHOUT_PAINT`, `GameWorld.rand` and
   `confirmRuinPlacements` are dead in the engine and absent here.** The first
   is marked DEPRECATED; the second is constructed from the map seed and never
   read (the port constructs it only to replace `Math.random()`, item 2); the
   third computes a validity flag and discards it.
9. **The `deadline` wall-clock stop** is a coworld concept and not an engine
   one. It is recorded as **one load-bearing record** (`plan.abandonAfter[g]`)
   and applied by the same proc on record and on playback.
10. **No indicator strings, dots, lines, timeline markers or profiler, and no
    `.bc25` output.** They are instrumentation, not rules.
11. **22 of the 75 official maps are converted.** Everything above 1 500 tiles
    is out of the played pools for wall-clock reasons (six are converted
    anyway, under `large`); `Terminal`, `box`, `catface`, `fix`, `gridworld`,
    `maze`, `shell` and `windmill` have **zero pre-painted tiles**, which is
    legal but makes the first fifty rounds identical on every doctrine; the
    remaining 45 are simply not converted in v1, and
    `tools/convert_maps_bc25.py` handles any `.map25` (CI proves it on all
    75).
12. **The released 3.1.0 jar carries `SPEC_VERSION = "1"`**, which is useless
    as a version pin, so the jar's identity is pinned by **sha256** in
    `tools/oracle/bc25/jar.lock` and Tier B cross-checks every constant
    against the jar's own classes instead.
13. **Both chassis are behaviour ports parameterised by the doctrine sheet.**
    Nothing upstream is vendored, compiled or read into any file here.
    `examplefuncsplayer25` is ported statement for statement and **may not
    gain behaviour**: it is one side of the differential oracle.
14. **The chassis and sim file layout differs from the design note's table in
    three places, and the pointers were updated with it.** `paint.nim` holds
    the pure paint alphabet and the two tile predicates, while `setPaint`'s
    live-count bookkeeping, its mid-action win check and the charged
    `connectedByPaint` BFS live in `world.nim` beside the arrays they mutate;
    `units.nim` holds the `UnitType` table and the pure cooldown arithmetic,
    while `addPaint`, `addHealth`, destruction and the end-of-turn paint bill
    live in `world.nim` for the same reason; and `towers.nim` holds the tower
    ACTIONS (mining, the two attacks, `buildRobot`, `completeTowerPattern`,
    `upgradeTower`) rather than only the tower table. `NOTICE` and
    `knobs.nim`'s header name the same paths.
15. **The design note said the map file's `InitialBodyTable` order is the
    initial exec order. It is not.** `LiveMap`'s constructor
    (`world/LiveMap.java:105`) **sorts `initialBodies` by ascending id** before
    the world ever sees them, and every 2025 map file lists them in DESCENDING
    id order — so file order and exec order are exactly reversed. `newWorld`
    sorts, because the engine wins. `tests/test_bc25_maps.nim` pins it.
16. **`transferPaint`'s self-transfer guard is a value comparison here and a
    Java reference comparison upstream.** `RobotControllerImpl` writes
    `loc == this.robot.getLocation()`, which is object identity on
    `MapLocation` and therefore almost never true; the port compares
    coordinates, which is strictly *stricter*. Unreachable in play: neither
    chassis nor the scenario bot ever transfers paint to itself, and a
    self-transfer's net effect in the engine is a cooldown and nothing else.

---

## What this year measures, for the next one

- A full 2000-round game on `DefaultLarge` (50×30) with both seats on
  `tower_rush` / `srp_priority: 100` / `defense_tower_chokes: early` is the
  worst case the port budgets for; `tests/test_bc25_perf.nim` fails CI above
  **90 s**, and the fix if it ever goes red is one config value —
  `gamesPerMatch: 3 → 1` in the `bc25` variant.
- The `docker-smoke` bc25 episode prints `sim_seconds / rounds`, and the
  `wasm-viewer` job runs `viewer_smoke.mjs` at `--timeout 120 --soak 15`
  against that episode's replay — the same pacing bc24 needed, decided here
  rather than discovered at phase 60.
