# Battlecode 2020 "Soup": rules, knobs and deliberate divergences

The `bc20` variant is a **behaviour port** of MIT Battlecode 2020 "Soup" to the
same deterministic Nim sim `bc26` runs in, compiled twice from one source tree:
natively into `/bin/battlecode` and to wasm into the static replay bundle. The
2020 Java engine exists **only** in the `parity-oracle` CI job. No JDK, no JRE
and no upstream Java source exists in any image this repository builds.

Sources, all read at commit `7618f6be7d12da39f2e6e25801e578f1fecfbd86` (the last
2020 state of `github.com/battlecode/battlecode20`):
`specs/specs.md`, `common/GameConstants.java`, `common/RobotType.java`,
`common/Transaction.java`, `common/Direction.java`, `common/MapLocation.java`,
`world/GameWorld.java`, `world/InternalRobot.java`, `world/ObjectInfo.java`,
`world/TeamInfo.java`, `world/RobotControllerImpl.java`, `world/IDGenerator.java`,
`world/control/CowControlProvider.java`, `schema/battlecode.fbs`.

## The game in one paragraph

Two teams on a symmetric 32×32–48×48 grid. **The water rises every round** and
floods outward one ring per round from every already-flooded tile whose
neighbour sits below the level; anything that is not a delivery drone dies on a
flooding tile. Miners mine SOUP and refine it at the HQ or a refinery. Design
schools build landscapers that dig and dump dirt. Fulfillment centers build
delivery drones that pick up any unit — including enemy landscapers — and drop
them in the water. Vaporators print soup and scrub pollution; net guns shoot
drones. The only global channel is a blockchain: seven ints a message, seven
messages a round, paid for in soup, and **both teams read every block**.

**An HQ cannot be raised.** Dirt dropped on a building goes onto the *building*
(and buries it at 50 for an HQ, 15 for everything else), never onto its tile. The
only thing that keeps an HQ dry is a ring of eight adjacent tiles the water can
never cross. That is what `wall_hq_round` buys, and it is why never walling
drowns you on a schedule.

## The round loop — the numbered resolution rules

`rules.nim`'s `runRound` mirrors `GameWorld.runRound` /
`processBeginningOfRound` / `updateDynamicBodies` / `processEndOfRound` step for
step. **Re-ordering any of them is a rules change and bumps `GameVersion`.**

1. `currentRound += 1`; both teams' pools gain `BASE_INCOME_PER_ROUND = 1`.
2. Every non-blocked robot runs `processBeginningOfRound` — a no-op in 2020,
   kept as a named step because the hash chain and the parity trace are taken
   around it.
3. Iterate the dynamic bodies in **spawn order** (`ObjectInfo.eachDynamicBodyByExecOrder`
   — append on spawn, remove on death), **not** id order. Map bodies are
   appended in file order.
4. **A blocked robot takes no turn.** A unit held by a delivery drone does not
   run its beginning-of-turn, does not act, and its cooldown does **not** decay.
   It *does* still get `resetPollutionForRobot` if its type can pollute.
5. Beginning of turn: `cooldownTurns = max(0, cooldownTurns − 1)` and the
   robot's `DecisionOps` budget is reset.
6. Run the controller. A robot may act only while `cooldownTurns < 1`; every
   action adds `type.actionCooldown × cooldownCoefficient(pollution here)`.
   The legal actions and their exact preconditions are in `world.nim`, one proc
   per action, each named for its `RobotControllerImpl` original.
7. End of turn, in `InternalRobot.processEndOfTurn`'s own order: clear this
   robot's previous local pollution; refine (HQ/Refinery, ≤ 20 into the pool);
   vaporate (+2 unconditionally); cows always pollute; then install a fresh
   local effect. **A refinery's local +500 therefore lasts exactly one round.**
8. End of round: mint the block (≤ 7 transactions); raise the water; flood
   exactly one ring; check the end-of-match ladder.
9. Append this round's state hash.

## The end ladder, in the engine's own order

| `end_reason` | engine origin | meaning |
|---|---|---|
| `hq_destroyed` | `HQ_DESTROYED` | exactly one HQ was buried under 50 dirt or drowned |
| `quantity` | `QUANTITY_OVER_QUALITY` | round cap or a double HQ loss; more living robots wins |
| `quality` | `QUALITY_OVER_QUANTITY` | equal robots; greater net worth wins |
| `broadcasts` | `GOSSIP_GIRL` | equal worth; more **minted** transactions wins |
| `highest_id` | `HIGHBORN` | equal broadcasts; the highest living robot id wins |
| `coin_flip` | `WON_BY_DUBIOUS_REASONS` | neither team has a living robot |
| `abandoned` | — | our `perGameBudgetSeconds` / `matchBudgetSeconds` guard fired |

`roundLimitReached` is the engine's own `currentRound >= rounds − 1`, so a
1500-round cap plays **1499**. The off-by-one is the engine's and is reproduced.

## Scoring

```
hq[t]        = 1 if team t's HQ is alive at the final round else 0
survival[t]  = f32(hq[t])    / f32(max(1, hq[A] + hq[B]))
units[t]     = living robots of t, BUILDINGS INCLUDED   (the QUANTITY rung)
worth[t]     = team soup pool + sum of type.cost over living non-neutral robots
                                                        (the QUALITY rung)
points[t]    = int(60*survival[t] + 25*unit_share[t] + 15*net_worth_share[t])
results.scores[t] = 100 * (games t won) + mean(points[t] over games played)
```

Every share is narrowed through **float32** and the sum is **truncated**, for
recorder/re-deriver agreement: the same arithmetic runs natively on x86-64 and
in wasm32 and must produce the same integer.

## The doctrine sheet — ten knobs, and **no `chassis` key**

The chassis is **not** an LLM-selectable knob. It comes from `PLAYER_SCRIPTED`
for a scripted seat and is the fixed champion chassis for an LLM seat. A
submitted `chassis` is recorded as an **unknown field** and never honoured;
`tests/test_bc20_sheet.nim` asserts exactly that.

| field | type / values | default | site |
|---|---|---|---|
| `opening` | `rush` \| `lattice` \| `passive_lattice` \| `turtle` | `passive_lattice` | `chassis/boc.nim` `applyOpening` |
| `terraform_start_round` | int 1…1500 | 300 | `chassis/landscaper.nim` `chooseMode` |
| `lattice_radius` | int 2…12 | 6 | `chassis/lattice.nim` `latticeNeedsWork` |
| `landscaper_count_curve` | `lean` \| `steady` \| `swarm` | `steady` | `knobs.nim` `landscaperTarget` |
| `miner_count_curve` | `lean` \| `steady` \| `swarm` | `steady` | `knobs.nim` `minerTarget` |
| `vaporator_budget` | int 0…6 | 2 | `chassis/miner.nim` `nextBuilding` |
| `drone_role` | `harass` \| `wall` \| `buster` \| `carry_landscapers` | `harass` | `chassis/drone.nim` `runDrone` |
| `net_gun_ring` | int 0…6 | 2 | `chassis/miner.nim` `nextBuilding` |
| `rush_trigger` | int 0…1500 (**0 = never**) | 0 | `chassis/landscaper.nim` `chooseMode` |
| `wall_hq_round` | int 0…1500 (**0 = never**) | 250 | `chassis/kit.nim` `effectiveWallRound` |

`landscaper_count_curve` targets `4 + round/220` scaled 0.6 / 1.0 / 1.7, capped
40; `miner_count_curve` targets `6 + round/300` scaled the same way, capped 25.

## §Divergences

Every one of these is deliberate and is the reason the parity oracle compares
*outcomes and state* rather than bytecodes.

1. **No bytecode instrumentation.** `RobotType.bytecodeLimit` has no meaning
   outside the JVM instrumenter. It is replaced by a fixed per-robot
   `DecisionOps` budget at **one tenth** of the Java limit (HQ 2000; miner,
   landscaper, drone 1000; net gun 700; other buildings 500; cow 0), charged
   one credit per tile sensed, robot examined, BFS node expanded, direction
   evaluated and block read, **enforced by the sim, not by the bot**. When the
   budget reaches zero the robot's turn ends where it stands: there is **no
   mid-turn resumption**, which is the one place this differs from the JVM.
2. **`setWinnerArbitrary`'s `Math.random()`** — wall-clock seeded, therefore not
   reproducible — is replaced by a draw from the world RNG. Reachable only when
   neither team has a single living robot.
3. **`Math.exp`/`Math.sin` in the water level** are HotSpot intrinsics that are
   not bit-identical to any libm this port would link. `getWaterLevel` depends
   only on the round number, so `tools/JavaWaterLevels.java` emits every value
   as a float32 **bit pattern** into `data/bc20/water_levels.json` under the CI
   JDK; the file is committed and the `parity-oracle` job regenerates and
   byte-diffs it as a BLOCKING step. The generator also cross-checks `Math`
   against `StrictMath` on the whole domain.
4. **A 1500-round cap** in place of the map's 10 000, applied through the
   engine's own `currentRound >= rounds − 1`. Elevation 6 floods at round 1413
   and 7 at 1546, so by 1500 every HQ has either been terraformed above the
   water or has drowned: the game is *decided* by the cap, not merely stopped.
5. **No indicator dots or lines, no profiler, no crossplay, no `.bc20` output.**
6. **The `deadline` wall-clock stop** is a coworld concept, not an engine one.
   It is recorded as ONE load-bearing record (`plan.abandon_after[g]`) and
   applied by the same proc on record and on playback.
7. **Both chassis are behaviour ports** parameterised by the doctrine sheet.
   `bowl-of-chowder` is Bowl of Chowder's *ideas* rewritten in Nim;
   `examplefuncsplayer` is ported statement for statement and may not gain
   behaviour, because it is one side of the differential oracle.
8. **18 of the 52 official maps** are converted. `CowFarm` and
   `DidAMonkeyMakeThis` are excluded on purpose: both carry tiles at
   `Integer.MAX_VALUE/2` elevation, which is legal but makes the elevation
   shading meaningless and the timing untypical.
9. **The transaction pool is drained by a stable sort**, not by a binary heap.
   `Transaction.compareTo` is a total order except for two transactions that
   agree on cost, on the 32-bit random id **and** on all seven ints; the sorted
   extraction is deterministic where `PriorityQueue.poll` is unspecified.
10. **`maptestsmall` carries soup on all 1024 tiles.** It is kept anyway,
    because it is the map the parity oracle and the fast smoke run on; the
    anomaly is noted here rather than hidden.
11. **`Infinity` has no tile at `MIN_WATER_ELEVATION`** (its floor is −12) and
    its HQs start at elevation 0, so `tests/test_bc20_maps.nim` asserts the
    `MIN_WATER_ELEVATION` guarantee for the other seventeen and records
    `Infinity`'s real floor. The 2020 spec asserts the guarantee; this map does
    not honour it, and the port follows the file rather than the prose.
12. **The chassis walls before `wall_hq_round` when the map demands it.** The
    knob says *when* to start; the map says when it is too late. On
    `maptestsmall` the HQ ring sits at elevation 1 and floods at round 256, so
    a doctrine that says "wall at 300" has already lost. `effectiveWallRound`
    takes `min(wall_hq_round, ringFloodRound − 200)`. `wall_hq_round = 0` still
    means **never**, which is what gives the knob its teeth.
13. **The HQ wall bar is evaluated at the last round the game can reach**
    (`waterLevel(max(round + 400, maxRounds)) + 2`) rather than at
    `round + 400`. A moving bar declared the wall closed at round 76 on a map
    whose ring already sat at elevation 4 and then let the same ring drown at
    round 932.
14. **The map symmetry is recomputed on every NEUTRAL spawn**, not on every
    spawn. `TeamControlProvider` delegates `robotSpawned` **by team**, and only
    the cow provider recomputes; cows exist only at map load, so the value is
    fixed for the match. The port reproduces the delegation, not the prose.
15. **The Fulfillment Center has no `NEED_DRONES` branch.** The design note has
    it build "whenever the roster is under `4 + round/300` (capped 14) and the
    pool can pay, and always when `NEED_DRONES` is on the chain". Only the
    first half is implemented: no role in this chassis ever broadcasts
    `NEED_DRONES`, so the second branch would guard a signal that never
    arrives. `SigNeedDrones = 5` keeps its code point — renumbering the signal
    table would change the meaning of every message in every recorded match —
    and is marked reserved in `chassis/signals.nim`.
16. **The builder-miner's order carries a Refinery, and its net guns stand off
    the HQ ring.** The design note's order is: Design School → `net_gun_ring`
    Net Guns *on the HQ ring* → Fulfillment Center → Vaporators → a second
    Design School after round 600. What `chassis/miner.nim` builds is Design
    School → **Refinery** → Net Guns → Fulfillment Center → Vaporators → second
    Design School, with every building at Chebyshev 2 from the own HQ and the
    Refinery at Chebyshev 4. Both moves are forced by rules the note's order
    fights:
    * a **walled** HQ sits eight elevation steps above the ground outside its
      ring and `MAX_DIRT_DIFFERENCE` is 3, so once the wall closes a miner can
      no longer climb to the HQ to deposit. Without a second drop-off the
      economy stops at exactly the moment the wall succeeds. The Refinery also
      refines its own 20 a round;
    * **dirt dropped on a building buries it** (rule 6.6), and the HQ ring is
      precisely what the landscapers raise. A net gun on the ring is buried by
      its own team's wall, so the ring is the one place it may not stand.

## Where the archetypes come from

The four openings — rush, lattice, passive lattice, turtle — are the year's
published metagame, taken from Stone Tao's postmortem
(<https://stonet2000.github.io/battlecode/2020/>) and from the spec, not from
any bot's source. `IvanGeffner/battlecode2020` declares **no licence** and is
cited here only as the public record of what the winning archetypes were: it is
not vendored, not ported, not compiled and not read into any file in this
repository.
