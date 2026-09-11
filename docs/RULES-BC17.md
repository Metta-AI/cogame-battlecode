# Battlecode 2017 "Robotic Wildlife Fund" — the `bc17` year module

Variant `bc17`, `game_config.year = "bc17"`. Two cogs each write ONE sealed
JSON doctrine of eleven knobs; the deterministic Nim sim then plays a
best-of-three match on the `mixed` pool, **2 999 rounds a game, in continuous
float32 space**, while both cogs watch.

Ported from `github.com/battlecode/battlecode-server-2017` at commit
`165d8a8ef24f03e13a101bb8bc9f5b32dcb33c6c` (root `COPYING` = AGPL-3.0, the
same licence this repository carries) with `specs-1.6.2.html` as the
human-readable spec. **Where the spec and the engine disagree, THE ENGINE
WINS**, and all six disagreements are tabled below. The oracle artefact is
`org.battlecode:battlecode:2017.1.6.2`, pinned by url, version, sha256
(`9254e892…7bff9`), byte size (14 576 275) and `GameConstants.SPEC_VERSION`
("1.0") in `tools/oracle/bc17/jar.lock`. **No JDK, no JRE, no Java and no
Node exists in any image stage**; the engine is a CI-time and build-time
artefact only, and `tools/convert_maps_bc17.py` reads the map flatbuffers out
of the jar in pure Python with no JVM at all.

## The year in one paragraph

Each faction starts with one to three ARCHONS and **300 bullets**. An archon
(400 HP, radius 2, cannot be built, cannot shoot) hires GARDENERS for 100; a
gardener is the only unit that can **plant a bullet tree** (50) or **water**
one (+5), and it builds the four fighters — SOLDIER (100, 50 HP, bullet speed
2, 2 damage), TANK (300, 200 HP, speed 4, **5 damage**, and a body attack that
eats trees), SCOUT (80, **10 HP**, stride **1.25**, 0.5 damage, and **the only
body that may overlap a tree**) and LUMBERJACK (100, 50 HP, no bullets at all,
`chop` for 5 to one tree and `strike` for 2 to **everything** within distance
2 **with no team check**). Bullets are the only resource and there are three
ways to get one: trees (`health × 1/50` a round once mature, −0.5 a round
always), **shaking** neutral trees, and the trickle — `max(0, 2 − 0.01 ×
supply)`, which is **EXACTLY ZERO at 200 bullets or more**, and both sides
start at 300. Winning is a purchase: `donate` converts bullets into victory
points at `7.5 + round × 12.5/3000` each, and **1 000 points ends the game the
instant the donation lands**. Losing your last robot loses it the same way.
Otherwise round 2 999 decides it on a four-rung ladder.

## The round loop — the step list IS the rules

Re-ordering any of it is a rules change and bumps `GameVersion`.

1. `processBeginningOfRound`: `currentRound += 1`; `previousBroadcasters =
   currentBroadcasters.values(...)` **in trove order** and then `clear()`
   **with the capacity retained** (D1); the two `healthChanged = false` sweeps,
   which have **no state effect at all**.
2. `updateDynamicBodies`: `dynamicBodyExecOrder.toArray()` **snapshotted
   before the loop**, then per id a robot turn or a bullet update, skipping any
   id that no longer exists. **A body spawned this round does not act this
   round.**
3. A robot's turn: `processBeginningOfTurn` (the five counters to zero, the
   build cooldown down one, and **`repairRobot(0.04 × maxHealth)` while
   `roundsAlive < 20 && isBuildable`**), then the chassis — **but only if
   `canExecuteCode()`**, i.e. `health > 0 && (isBuildable() ? roundsAlive >= 20
   : true)`, so **a built fighter does NOTHING AT ALL for twenty turns** while
   it heals 4 % a turn — then `roundsAlive += 1` if it is still alive.
4. A bullet's update: `bulletFinish = start.add(dir, speed)`, a **fresh**
   `toFinish = start.directionTo(finish)`, the tree candidates within
   `10 + d/2` of the segment's midpoint and the robot candidates within
   `2 + d/2`, the **strict** minimum `hitDist` in each, and then: nothing hit →
   move or die off the map; a tree strictly closer → the tree takes the damage;
   otherwise the robot does. **A tree/robot tie goes to the ROBOT.** No team
   check, no exclusion of the firer.
5. `updateTrees`: `totalTreeSupply[team] += tree.updateTree()` — **a float32
   sum in trove order** (D1) — then A's credit and then B's. `updateTree` is
   NEUTRAL → 0; `roundsAlive <= 80` → grow 0.5 and return **0**; else
   `income = health × 1/50` and then the 0.5 decay, **which can kill the
   tree**.
6. `processEndOfRound`: the replay-only sweeps plus each TREE's
   `roundsAlive++`; the bullet income for A then B; and at `currentRound >=
   rounds − 1` with no winner, the ladder. **`running = false` only here**, so
   a game decided mid-round still plays out its income, its decay and its
   deaths — and a later `setWinner` in the same round OVERWRITES the earlier
   one.

## The four-rung ladder, and the two immediate wins

| rung | condition | `DominationFactor` | `end_reason` |
|---|---|---|---|
| — | a donation takes a side to ≥ 1 000 VP (fires mid-round) | `PHILANTROPIED` | `victory_points_reached` |
| — | a side's **last robot** dies (trees do not count) | `DESTROYED` | `all_robots_destroyed` |
| 1 | more victory points | `PWNED` | `more_victory_points` |
| 2 | more own trees, **sapling or mature** | `OWNED` | `more_bullet_trees` |
| 3 | more `bullets + Σ type.bulletCost`, **archons −1 each** | `BARELY_BEAT` | `more_bullet_worth` |
| 4 | the team of the **highest robot id of any type** | `WON_BY_DUBIOUS_REASONS` | `highest_id` |

**There is no coin flip and no RNG anywhere on this path.** Our own
`abandoned` is the wall-clock guard.

## Where the docs are wrong — six disagreements, the engine wins every one

1. §16 says maps run 1 500–3 000 rounds; `GameMapIO.Serial.deserialize:235`
   sets `rounds = GAME_DEFAULT_ROUNDS` and never reads the file — **3 000 on
   all seventy maps**, so every game is 2 999 played rounds.
2. §16 says tiebreak 4 is the highest **archon** id; the engine loops over
   **every robot**.
3. §16 says tiebreak 3 is bullets plus robot cost; **`ARCHON.bulletCost` is
   `−1`**, so each surviving archon SUBTRACTS a bullet.
4. §16 says tiebreak 2 counts **active** bullet trees; `getTreeCount` is a
   plain counter — a 10-HP sapling counts as much as a mature tree.
5. §10 says a tree matures over **80** turns; the branch is `roundsAlive <=
   80`, i.e. **81** turns, and it returns 0 income for all of them.
6. §22 says the tree phase's ordering "is not important to the outcome of a
   match". **The sentence is false**: the sum is float32 over trove hash order
   and it lands in the supply that `donate`'s integer floor reads.

## Divergences — every rule this port does NOT reproduce, with its reason

* **V1 — bytecode metering is not ported.** The engine gives each robot a
  per-turn bytecode limit (ARCHON 30 000, everything else 15 000), pauses the
  thread when it runs out and RESUMES IT MID-COMPUTATION next round. This port
  charges a fixed **`DecisionOps`** budget instead — **`ArchonOps` 3 000,
  `UnitOps` 1 500, `DormantOps` 0**, one tenth of the engine's own limits at
  the repo's standing convention — and the robot's turn **ends where it
  stands** rather than resuming. **THE DIVERGENCE IS WEAKER HERE THAN IN ANY
  OTHER YEAR: in 2017 the bytecode count has ZERO effect on any rule.**
  `bytecodesUsed` is replay telemetry and `prevBytecodesUsed` is written and
  never read by any gameplay path, so the only thing the limit decides is *how
  much the chassis got to think*. One credit is charged for each body examined
  in a candidate query, grid cell scanned, farm slot scored, direction
  evaluated in the `tryMove` probe, bullet tested by `willCollideWithMe`,
  target scored, channel read and tree scored for watering or chopping; the
  budget is checked **before** each primitive and never inside one, so a
  primitive's *result* is never a function of the remaining budget.
  `results.games[].decision_ops_peak` records the measured maximum per game
  and it is far below the cap for both shipped chassis.
  **`DormantOps = 0` is NOT the divergence — it is the RULE**
  (`getBytecodeLimit()` returns 0 unless `canExecuteCode()`).
* **V2 — the flatbuffer layer, the server and the client have no port.** No
  `.bc17` bytes exist anywhere on either side; the map READER is reproduced at
  build time by `tools/convert_maps_bc17.py` (pure Python, no JVM) and the
  replay is this repository's own self-sufficient UTF-8 JSON, re-derived by the
  wasm sim. `setIndicatorDot`/`setIndicatorLine` are debug-only and are not
  ported.
* **V3 — the robot id pool cannot collide with the bullet id pool.**
  `IDGenerator` never checks `MAX_ROBOT_ID`: after five blocks the robot ids
  reach 30 481–34 576 and overlap the bullet space that starts at 32 002, and
  `ObjectInfo`'s own comment names the hazard. This port reproduces the
  generator exactly and adds **one guard the engine lacks**: a `hire`, `build`
  or `plant` that would issue an id above **32 000** is REFUSED and counted in
  `builds_refused` and `refused_actions`. (All three verbs are covered because
  all three draw from the same generator.) Derived ceiling: ≈ 22 000 robots,
  which the richest played map's income cannot fund.
* **V4 — team memory is inert.** Every game in this coworld is independent, so
  the 32-long array is kept, readable as zeros, and `orchard` never touches it.
* **V5 — `runRound`'s blanket `catch (Exception)`** ends the engine's game with
  no winner; this port reports `results.reason = fault`, `scores = [0, 0]` and
  a partial replay. Both engine paths that reach it are unreachable here.
* **V6 — `resign()` is unreachable**, `Clock.getBytecodeNum`/`getBytecodesLeft`
  are replaced by the `DecisionOps` counters, and the fdlibm **Payne–Hanek**
  branch of `__ieee754_rem_pio2` is **not implemented** because
  `Direction.radians` is always in (−π, π]; `fdlibmSin`/`fdlibmCos` raise a
  `Defect` outside `[−4, 4]` rather than guessing.

## Determinism

* **D1 — `gnu.trove` iteration order is REPRODUCED, not replaced**, because it
  is observable in exactly two places: the float32 tree-income sum, and the
  `previousBroadcasters` array `senseBroadcastingRobotLocations()` hands
  **both** teams. `years/bc17/trove.nim` is its own copy (not bc22's) because
  bc17's `forEachValue` walks a table that `destroyTree` mutates and a removal
  that triggers auto-compaction leaves the walk on the PRE-compaction arrays,
  and because bc17 needs a `clear()` that RETAINS the capacity.
* **D2 — the `net.sf.jsi` R-tree is NOT ported; the candidate order is
  normalised to `(distanceSquared, id)` ascending on BOTH sides.** jsi's
  exact-tie order is an artefact of node layout and heapify and is not stable
  even against itself in one process, so there is nothing faithful to
  reproduce; the engine side takes the same enumeration through
  `rtree_order.patch`.
* **D3 — `java.util.Random`, two instances, both seeded with the MAP seed,
  drawn only at block allocation.** The bullet generator has a **two-block head
  start** (its constructor allocates from 10 001 and `setStart` again from
  32 001, so 2 × 4 095 shuffle draws precede its first id, which is 32 002 …
  36 097). **No draw happens per spawn.** `GameWorld.rand` — a third
  `Random(mapSeed)` the engine constructs and **never reads** — is deliberately
  NOT ported.
* **D4 — the exec order is an ARRAY and that is all it is**: append on robot
  spawn, insert at `indexOf(parent)` on bullet spawn, removal **by value**, and
  a snapshot before every sweep.
* **D5 — every engine-visible quantity is `float32`**, and the port's types say
  so; victory points, rounds, ids, counters and channel values are `int`.

## The float ledger (F1–F5)

The whole transcendental surface of the 2017 gameplay tree is
**`{sqrt, atan2, sin, cos}`** — 26 `Math.` call sites, **no `pow`, no `exp`, no
`log`, no `hypot` and no `Math.random` anywhere**. Every gameplay class is
`strictfp`, so IEEE-754 `+ − × ÷` and comparison are exactly specified in both
widths and every algebraic expression is bit-exact by construction **provided
the widths and the order match** — which is why Java's promotion is replicated
PER EXPRESSION (`geom.nim`, `ballistics.nim`) and why
`tests/test_bc17_widths.nim` pins one named vector per shape. `sqrt` is
correctly rounded and needs no port; `sin`, `cos` and `atan2` are ported from
**fdlibm 5.3** into `src/battlecode/fdlibm.nim` (four new procs, no existing
proc touched) and pinned against the JVM's own `StrictMath` by
`data/bc17/fdlibm_vectors.json`: **440 boundary rows value for value and
eleven expression-shape digests over two million samples, all reproduced BIT
FOR BIT.**

Two float facts found in phase 20 and asserted rather than "fixed":

* **`Direction.reduce` is not exactly range-preserving at the wrap boundary.**
  For `rads = 3 × (float)π` the float64 quotient is 1.0000000079, `ceil` gives
  **2**, and the method subtracts two full circles — the result is one ulp
  BELOW `−(float)π`, just outside the `(−π, π]` the class's own comment claims.
  `tests/test_bc17_geom.nim` pins it.
* **Nim folds a `const` float32 expression in float64.** `0.04'f32 * 10'f32`
  written as a literal is 0.40000001; the runtime float32 multiply the engine
  does is 0.39999998. Every float32 expectation in the bc17 shards is therefore
  built from runtime values, and `tests/test_bc17_units.nim` asserts the trap
  itself so nobody re-introduces it.

## The doctrine sheet — eleven knobs, no `chassis` key

`opening` (`tree_farm` | `tank_rush` | `lumberjack_swarm` | `scout_squat`),
`gardener_count` (1…8), `farm_layout` (`hex` | `line` | `ring`),
`soldier_tank_ratio` (0…100), `lumberjack_share` (0…100), `scout_harass`
(0…100), `vp_donate_policy` (`never` | `when_ahead` | `rush_1000` |
`endgame_dump`), `shake_neutral_trees` (`never` | `opportunistic` |
`dedicated`), `chop_policy` (`never` | `clear_path` | `harvest`),
`bullet_reserve` (0…2000) and `defend_radius` (1…40). An unknown key, a wrong
type or an out-of-range value takes that field's default — the six integer
knobs **clamp** instead — and every repair AND EVERY ABSENT KEY is recorded in
`sheet_defaults_applied`. **A submitted `chassis` is recorded in
`sheet_unknown_fields` and never honoured.**

**`bullet_reserve`'s default of 200 is a measured number, not a taste**: the
trickle is exactly zero at 200 bullets and above, so a faction sitting on 200
earns nothing from it while a faction at 100 earns 1 a round. It is the one
knob whose default encodes the year's biggest surprise.

## The two chassis

* **`orchard`** — the strong chassis and the champions' chassis, in
  `chassis/{kit,econ,archon,gardener,farm,military,micro,lumberjack,scout,donate,comms,orchard}.nim`.
  Written from the engine source, the 1.6.2 spec and the four archetypes the
  run's own idea names. **No 2017 competitor bot was cloned, fetched or read**
  — all three named upstreams carry no licence anywhere. Two behaviours are
  ports of the **AGPL-3.0** scaffold player and `NOTICE` credits both: `kit.nim`'s
  seven-direction `tryMove` probe and `micro.nim`'s `willCollideWithMe`.
  **The unconditional floor, at every knob setting:** ≥ 1 gardener per archon
  (and a second funded through the reserve), a first tree by round 60, ≥ 3 trees
  alive when affordable, ≥ 2 fighters per gardener, water the lowest-health own
  tree in reach, **never a `strike()` whose own-HP cost exceeds the enemy's**,
  never a TANK onto its own tree, and never a donation below `bullet_reserve`
  unless the policy is `rush_1000`.
* **`examplefuncsplayer17`** — the deliberately weak floor and the parity
  oracle's other side: a statement-for-statement port of the AGPL-3.0
  scaffold's `RobotPlayer.java` with the one committed determinism hunk (a
  per-robot `java.util.Random(rc.getID())` in place of three `Math.random()`
  calls, **with the `&&` short-circuit draw order preserved**). **It may not
  gain behaviour**: it never plants, waters, shakes, chops or donates, and TANK
  and SCOUT have no `case` in its switch at all — so `run()` returns and the
  robot dies.

## Playback pacing, measured

**`docker-smoke` prints `sim_seconds / rounds` and this section records the
measured value.** On CI run **34536659753** the bc17 smoke episode — seed 5,
`HouseDivided` (30×30, one archon a side, 41 neutral trees), 899 rounds of
`orchard` against `examplefuncsplayer17` — printed

```
bc17 smoke: sim_seconds=0.113 rounds=899 wall=0.213s
```

i.e. **0.126 ms a round**, against the design note's estimate of 3–12 ms and
its 15 ms/round trigger. The trigger is the one that matters: *if the measured
value exceeds 15 ms/round, the fix is to lower the smoke episode's `maxRounds`
rather than the soak*, because the soak must still outlast the replay (the
ecos 2026-08-23 scar), and 900 rounds at 25 fps is ~36 s of playback against a
15 s soak. At 0.126 ms/round there is nothing to lower.

The heavier boards cost more and are measured too, in `tests/test_bc17_perf.nim`:
a full 2 999-round game on `Chess` (64×64, 924 neutral trees — the board that
maximises the per-bullet candidate count) is **4.1 s in release, 1.4 ms a
round**, and `LineOfFire` (100×30, 1 228 trees) is 4.9 s. The committed gate is
60 s, fourteen times the measurement, because a shared CI runner is not a
sandbox.

**Why bc17 still takes the heavy viewer probe.** The per-round cost is small;
the ROUND COUNT is not. A bc17 game is **2 999 rounds** — the joint longest in
this repository, with bc16 — and the Worker re-simulates from the start of the
game on every seek, so a 100 % seek replays the whole of it. `ci.yml`'s
`wasm-viewer` job therefore runs the bc17 replay at **`--timeout 120 --soak
15`**, joining bc16/bc22/bc23/bc24/bc25, and the phase-60 check-8 dispatch for
bc17 uses **`settle=20000 soak=15`**. Decided from this measurement rather
than discovered at phase 60, and cited from `ci.yml:5256` and `:5519`.

## Scoring

```
share(x, y)  = if x + y == 0: 0.5 else x / (x + y)          # float32
points[t]    = int(64 × share(vp) + 24 × share(trees) + 12 × share(worth))
results.scores[t] = 200 × (games won) + mean(points over games played)
```

The three terms are the engine's own three deciding rungs in its own priority
order; rung 4 is deliberately not a term. `worth` uses the engine's exact
expression (**the archon's −1 included**) and is clamped at 0 **for the score
only, never for the ladder**. The weights are super-increasing, but **`points`
alone can favour the loser** — a 501-to-499 VP margin is 0.128 of a point
against 36 available below — which is why bc17 pays the **200** win bonus and
why the `end_reason` is computed from the engine's exact comparisons and not
from `points`.

## Divergence in the doctrine sheet's own words

The knob table's own doc comments and `plainWords17()` are the spectator-facing
statement of all of the above; `docs/PARITY.md` §bc17 carries the parity
status, the measured numbers and the ledger.
