## The Battlecode 2017 "Robotic Wildlife Fund" world: continuous float32
## state, the exec-order array, the two id generators, the trove key sets, the
## broadcast arrays and every counter the score, the endcard and the parity
## trace read.
##
## A behaviour port of `world/GameWorld.java` (472 lines),
## `world/ObjectInfo.java` (519), `world/InternalRobot.java` (326),
## `world/InternalTree.java` (209), `world/InternalBullet.java` (226),
## `world/LiveMap.java`, `world/TeamInfo.java` and `world/IDGenerator.java` at
## commit `165d8a8e`. The port is the authority at run time; the Java engine
## survives only as the `parity-oracle-bc17` CI job (docs/PARITY.md §bc17).
##
## **SEVEN THINGS IN HERE LOOK LIKE DETAILS AND ARE NOT:**
##
## * **The exec order is an ARRAY and that is all it is** (D4).
##   `ObjectInfo.dynamicBodyExecOrder` is a plain `TIntArrayList`: robots
##   APPENDED on spawn (`:254`), a bullet INSERTED at `indexOf(parent)` --
##   immediately BEFORE the robot that fired it (`:268-269`) -- and removal
##   **BY VALUE** (`TIntArrayList.remove(int)` removes a value, not an index;
##   measured). `eachDynamicBodyByExecOrder` SNAPSHOTS with `toArray()` before
##   iterating and skips any id that no longer exists (`:132-155`), so a body
##   spawned during round R does not act until R+1 and a body destroyed during
##   round R is silently skipped.
## * **The trove key sets carry the OBSERVABLE iteration order** (D1). The
##   float32 tree-income sum and the `previousBroadcasters` array both depend
##   on it; see `trove.nim`.
## * **There are TWO id generators, both seeded with the MAP seed, and the
##   bullet one has a TWO-BLOCK HEAD START** (D3): `new IDGenerator(seed)`
##   already allocated a block from 10 000 in its constructor, and
##   `setStart(MAX_ROBOT_ID + 1)` allocates a second from 32 001 -- so 2 x 4095
##   Fisher-Yates draws happen before the first bullet id, and that first block
##   is 32 002 .. 36 097. **No draw happens per spawn**: the id stream is a
##   pure function of the seed and the spawn COUNT.
## * **`MAX_ROBOT_ID` IS NOT ENFORCED BY THE ENGINE** and the robot pool really
##   does overrun the bullet pool after five blocks (`ObjectInfo.java:137-138`
##   names the hazard in a comment). This port adds ONE guard the engine lacks
##   (V3): a `hire`/`build` that would issue an id above 32 000 is REFUSED and
##   counted, because "degrade, never hang" outranks fidelity to a collision.
## * **Bullet supply is a `float32` that is never clamped at zero** and victory
##   points are an `int`. `adjustBulletSupply` is a bare `+=`.
## * **The bullet income is switched off above 200 bullets**:
##   `max(0, 2 - 0.01 * supply)` is EXACTLY ZERO at any supply >= 200 and both
##   teams start at 300, so a 2 999-round game with no player action ends with
##   exactly 300.000000000 on both sides (measured on the real engine).
## * **`GameWorld.rand` is constructed and NEVER READ.** The engine builds a
##   third `new Random(gameMap.getSeed())` at `:62` and no gameplay path reads
##   it -- `grep -n rand GameWorld.java` finds the declaration and the
##   assignment and nothing else. It is deliberately NOT ported: inventing a
##   stream is worse than omitting one (D3).

import std/[strutils, tables]
import ../../sim_types
import ../../rng
import constants, units, geom, trove, index

export constants, units, geom, trove, index, tables

type
  Team* = enum
    ## `common/Team.java`: A = 0, B = 1, NEUTRAL = 2, and the ordinal is the
    ## index of every per-team array in the engine.
    tA = "A"
    tB = "B"
    tNeutral = "N"

  Robot* = ref object
    ## `world/InternalRobot.java`, minus the bytecode counters (V1) and the
    ## replay-only `healthChanged` flag.
    id*: int
    team*: Team
    kind*: RobotType
    loc*: Loc
    health*: float32
    roundsAlive*: int
    attackCount*, moveCount*, repairCount*, waterCount*, shakeCount*: int
    buildCooldownTurns*: int
    alive*: bool
    ## The `DecisionOps` budget (V1). `ops` is this turn's allowance and
    ## `opsUsed` what the chassis has spent; the SIM enforces it, not the bot.
    ops*, opsUsed*: int
    ## Chassis-private memory. It lives on the robot because the engine gives
    ## each bot one closure per robot and nothing else; NO RULE READS ANY OF
    ## IT, and the parity trace does not print it.
    role*: int
    task*: int
    taskLoc*: Loc
    homeLoc*: Loc
    slot*: int
    claimed*: bool
    lastBroadcast*: int
    stuck*: int
    wallTurns*: int
    step*: int
    weakRng*: JavaRandom
      ## `examplefuncsplayer17`'s per-robot `java.util.Random(rc.getID())`,
      ## which the one committed patch hunk puts in place of the stock bot's
      ## FOUR `Math.random()` calls. Tier A" is therefore also a test of
      ## `src/battlecode/rng.nim`.
    weakRngReady*: bool

  Tree* = ref object
    ## `world/InternalTree.java`.
    id*: int
    team*: Team
    loc*: Loc
    radius*: float32
    health*: float32
    maxHealth*: float32
    containedBullets*: int
    containedRobot*: int          ## a `RobotType` ordinal, or -1 for none
    roundsAlive*: int
    alive*: bool

  Bullet* = ref object
    ## `world/InternalBullet.java`. A radius-zero point with a direction and a
    ## speed; the damage it carries is the FIRER's `attackPower`, frozen at
    ## spawn.
    id*: int
    team*: Team
    loc*: Loc
    dir*: Dir
    speed*: float32
    damage*: float32
    roundsAlive*: int
    alive*: bool

  Broadcaster* = object
    ## One row of `previousBroadcasters`, i.e. the `RobotInfo` snapshot
    ## `senseBroadcastingRobotLocations()` hands EVERY chassis of BOTH teams.
    id*: int
    team*: Team
    loc*: Loc

  MapBody* = object
    ## One initial body from a committed `data/maps/bc17/<Name>.json`, in the
    ## file's own id-ascending order -- which is `LiveMap`'s constructor's sort
    ## (`LiveMap.java:67`) and therefore the opening exec order.
    isRobot*: bool
    id*: int
    team*: Team
    kind*: RobotType              ## robots only
    loc*: Loc
    radius*: float32              ## trees only
    health*: float32              ## trees only, = 200 x radius
    containedBullets*: int
    containedRobot*: int

  MapSpec* = object
    name*: string
    mapSeed*: int
    rect*: MapRect
    rounds*: int
    bodies*: seq[MapBody]
    ## Derived census, computed once at load and reported in the map card and
    ## the results document.
    archonsPerSide*: int
    neutralTrees*: int
    treesWithBullets*: int
    treesWithRobots*: int
    separationMinTenths*: int
    separationMaxTenths*: int

  TeamStats* = object
    ## Every counter the results document, the endcard and the knob-teeth
    ## gate read, indexed by TEAM ordinal (0 A, 1 B). Float quantities are
    ## accumulated as float32 and reported in TENTHS as integers -- the
    ## convention bc16 established, which this year needs more than any other
    ## because a raw float32 in a JSON results document is a formatter
    ## argument waiting to happen.
    archonsStart*: array[2, int]
    archonsLost*: array[2, int]
    gardenersBuilt*: array[2, int]
    gardenersLost*: array[2, int]
    lumberjacksBuilt*: array[2, int]
    soldiersBuilt*: array[2, int]
    tanksBuilt*: array[2, int]
    scoutsBuilt*: array[2, int]
    unitsBuilt*: array[2, int]
    unitsLost*: array[2, int]
    treesPlanted*: array[2, int]
    treesLost*: array[2, int]
    waterActions*: array[2, int]
    shakeActions*: array[2, int]
    chopActions*: array[2, int]
    neutralTreesFelled*: array[2, int]
    robotsReleasedFromTrees*: array[2, int]
    bulletsFired*: array[2, int]
    singleShots*: array[2, int]
    triadShots*: array[2, int]
    pentadShots*: array[2, int]
    attacks*: array[2, int]
    strikeActions*: array[2, int]
    bodyAttacks*: array[2, int]
    kills*: array[2, int]
    moves*: array[2, int]
    broadcasts*: array[2, int]
    donations*: array[2, int]
    buildsRefused*: array[2, int]
    refusedActions*: array[2, int]
    decisionOpsPeak*: array[2, int]
    ## float32 accumulators
    bulletsFromTrees*: array[2, float32]
    bulletsShaken*: array[2, float32]
    bulletsDonated*: array[2, float32]
    bulletsSpentOnUnits*: array[2, float32]
    bulletsSpentOnTrees*: array[2, float32]
    bulletsSpentOnShots*: array[2, float32]
    bulletsTrickled*: array[2, float32]
    damageDealt*: array[2, float32]
    damageTaken*: array[2, float32]
    friendlyFireDamage*: array[2, float32]
    ownTreesDamaged*: array[2, float32]
    ## Telemetry the gates read and no rule does.
    tanksBuiltBy600*: array[2, int]
    lumberjacksBuiltBy600*: array[2, int]
    scoutsBuiltBy600*: array[2, int]
    enemyGardenersKilled*: array[2, int]
    enemyTreesFelled*: array[2, int]
    treesAliveAt1500*: array[2, int]
    matureTreesBy600*: array[2, int]
    archonsAliveAt2000*: array[2, int]
    roundsBelowOneBullet*: array[2, int]
    fighterDistanceSum*: array[2, int]
    fighterDistanceSamples*: array[2, int]
    treePairDistanceSum*: array[2, int]
    treePairDistanceSamples*: array[2, int]
    treesLostToStrike*: array[2, int]
    peakBulletsInFlight*: int
    lostThisRound*: array[2, int]

  World* = ref object
    map*: MapSpec
    rect*: MapRect
    maxRounds*: int
    currentRound*: int            ## 1-BASED: `processBeginningOfRound`
                                  ## pre-increments, so the first played round
                                  ## is 1 and the last is `maxRounds - 1`
    running*: bool
    robots*: Table[int, Robot]
    trees*: Table[int, Tree]
    bullets*: Table[int, Bullet]
    robotKeys*: TroveIntMap       ## `gameRobotsByID`'s observable order
    treeKeys*: TroveIntMap        ## `gameTreesByID`'s -- the income sum's
    bulletKeys*: TroveIntMap      ## `gameBulletsByID`'s
    execOrder*: seq[int]          ## `dynamicBodyExecOrder`
    robotIndex*: Index
    treeIndex*: Index
    bulletIndex*: Index
    robotCount*: array[3, int]    ## `ObjectInfo.robotCount`, by team ordinal
    treeCount*: array[3, int]     ## `ObjectInfo.treeCount` -- a PLAIN COUNTER
                                  ## with no notion of "active", so a 10-HP
                                  ## sapling counts as much as a mature tree
    bulletSupply*: array[3, float32]
    victoryPoints*: array[3, int]
    broadcastArray*: array[2, seq[int]]
    teamMemory*: array[2, array[32, int64]]
      ## V4: inert. Every game in this coworld is independent, so a chassis
      ## may write it and reads back zeros, and `orchard` never touches it.
    currentBroadcasters*: TroveIntMap
    broadcasterInfo*: Table[int, Broadcaster]
    previousBroadcasters*: seq[Broadcaster]
    idGen*: IdGenerator
    bulletIdGen*: IdGenerator
    robotIdsIssued*: int
    bulletIdsIssued*: int
    winner*: Team
    hasWinner*: bool
    domination*: int              ## `Bc17RungNames` ordinal
    tiebreakRound*: int
    stats*: TeamStats
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    beatCount*: array[24, int]
    hashChain*: uint64
    firstActionSeen*: array[2, bool]
    unitMilestoneSeen*: array[2, array[RobotType, bool]]
    treeBeats*: array[2, int]
    treeLostBeats*: array[2, int]
    donationBeats*: array[2, int]
    shakeBeats*: array[2, int]
    strikeBeats*: array[2, int]
    chopRevealBeats*: array[2, int]
    volleyBeats*: array[2, int]
    farmOnlineSeen*: array[2, array[3, bool]]
    famineSeen*: array[2, bool]
    preTrickleSupply*: array[2, float32]
      ## The bullet supply at the END OF SPENDING, i.e. BEFORE
      ## `processEndOfRound` credits the archon trickle. The famine beat and
      ## `rounds_below_one_bullet` are read off THIS and not off the live
      ## supply, because the trickle is `max(0, 2 - 0.01 x supply)` and is
      ## therefore EXACTLY 2.0 at a supply of zero -- a side that spends to
      ## its last bullet is back above two before the round ends, so a check
      ## on the live supply can never fire.
    firedThisRound*: array[2, int]
    lastShotShape*: array[2, ShotShape]
    ## The last enacted action, flattened for the parity trace. TELEMETRY
    ## ONLY -- no rule reads any of it, and the Java driver recovers the same
    ## fields the same way.
    lastActionKind*: array[2, int]
    lastAction*: Table[int, tuple[act: int, tgt: int, x, y, arg: float32]]
    brokenChassis*: bool
      ## Set by `-d:bc17BrokenChassis`: the NEGATIVE CONTROL for the
      ## economic-survival gate. Gardeners plant but never water, nobody ever
      ## donates, and `bullet_reserve` is ignored.

const
  Bc17ActionNames* = ["nothing", "move", "fire_single", "fire_triad",
                      "fire_pentad", "strike", "chop", "shake", "water",
                      "plant", "hire", "build", "broadcast", "donate",
                      "disintegrate", "body_attack"]
  ActNothing* = 0
  ActMove* = 1
  ActFireSingle* = 2
  ActFireTriad* = 3
  ActFirePentad* = 4
  ActStrike* = 5
  ActChop* = 6
  ActShake* = 7
  ActWater* = 8
  ActPlant* = 9
  ActHire* = 10
  ActBuild* = 11
  ActBroadcast* = 12
  ActDonate* = 13
  ActDisintegrate* = 14
  ActBodyAttack* = 15

  Bc17RungNames* = ["-", "victory_points_reached", "all_robots_destroyed",
                    "more_victory_points", "more_bullet_trees",
                    "more_bullet_worth", "highest_id"]
  RungNone* = 0
  RungVictoryPoints* = 1
  RungDestroyed* = 2
  RungMoreVictoryPoints* = 3
  RungMoreBulletTrees* = 4
  RungMoreBulletWorth* = 5
  RungHighestId* = 6

  ## Beat slots, and the per-GAME bound on each -- exactly the design note's
  ## own event table. `tests/test_bc17_replay.nim` asserts every one of them
  ## against a real match, so a pathological game cannot produce a 20 MB
  ## replay. The whole worst case is `11 + 3 x 232 = 707` entries.
  BeatGameStart* = 0
  BeatFirstAction* = 1
  BeatUnitMilestone* = 2
  BeatTreePlanted* = 3
  BeatTreeLost* = 4
  BeatFarmOnline* = 5
  BeatGardenerLost* = 6
  BeatArchonLost* = 7
  BeatDonation* = 8
  BeatShake* = 9
  BeatChopReveal* = 10
  BeatStrike* = 11
  BeatVolley* = 12
  BeatRout* = 13
  BeatDuel* = 14
  BeatFamine* = 15
  BeatTiebreak* = 16
  BeatGameEnd* = 17

  BeatBounds* = [1, 2, 10, 24, 24, 6, 16, 6, 24, 20, 12, 20, 20, 20, 20, 2,
                 1, 2, 0, 0, 0, 0, 0, 0]

func opponent*(t: Team): Team =
  case t
  of tA: tB
  of tB: tA
  of tNeutral: tNeutral

func teamOf*(slot: int, sideAslot: int): Team =
  ## Which engine-side team a SEAT plays. Sides alternate per game.
  if slot == sideAslot: tA else: tB

# ---------------------------------------------------------------------------
#  Events, beats and the hash chain
# ---------------------------------------------------------------------------

proc emit*(w: World, kind: string, a = 0, b = 0, c = 0, s = "") =
  w.events.add((round: w.currentRound, kind: kind, a: a, b: b, c: c, s: s))

proc beat*(w: World, slot: int, kind: string, a = 0, b = 0, c = 0,
           s = ""): bool {.discardable.} =
  if w.beatCount[slot] >= BeatBounds[slot]: return false
  w.beatCount[slot] += 1
  w.emit(kind, a, b, c, s)
  true

proc mixHash*(w: World, v: int) =
  w.hashChain = (w.hashChain xor uint64(v and 0xFFFFFFFF)) *
    0x100000001B3'u64

proc mixHashU*(w: World, v: uint64) =
  ## The same step for a value that is ALREADY 64 bits. `int` is 32 bits under
  ## wasm32, so masking into an `int` first raises `RangeDefect` in the browser
  ## while the native suite stays green (the bc22 lesson).
  w.hashChain = (w.hashChain xor (v and 0xFFFFFFFF'u64)) * 0x100000001B3'u64

proc mixHashBits*(w: World, v: float32) =
  ## **Folding the RAW IEEE-754 BITS of a float32 rather than a rounded value
  ## is a bc17-specific decision and the cheapest possible tripwire for a
  ## float divergence**: one wrong ulp in the tree-income sum shows up on the
  ## round it happens instead of as a mystery 400 rounds later.
  w.mixHashU(uint64(cast[uint32](v)))

func fnv1a64*(values: openArray[int]): uint64 =
  ## The fold every parity-trace checksum line uses, on both sides of the
  ## oracle: ONE WHOLE INT PER ITERATION, masked to 32 bits, byte for byte
  ## what `Bc17Trace.java`'s `fnv` does in Java. Deliberately NOT the
  ## canonical byte-wise FNV-1a: the value is compared across the two
  ## implementations, so the fold is WIRE FORMAT.
  result = 0xcbf29ce484222325'u64
  for v in values:
    result = (result xor uint64(uint32(v))) * 0x100000001B3'u64

func fnv1a64Bits*(values: openArray[uint32]): uint64 =
  result = 0xcbf29ce484222325'u64
  for v in values:
    result = (result xor uint64(v)) * 0x100000001B3'u64

# ---------------------------------------------------------------------------
#  Censuses
# ---------------------------------------------------------------------------

func robotsAlive*(w: World, t: Team): int = w.robotCount[ord(t)]
func treesAlive*(w: World, t: Team): int = w.treeCount[ord(t)]

func unitCount*(w: World, t: Team, kind: RobotType): int =
  for id, r in w.robots:
    if r.team == t and r.kind == kind: inc result

func matureTrees*(w: World, t: Team): int =
  for id, tr in w.trees:
    if tr.team == t and tr.roundsAlive > TreeGrowthRounds: inc result

func bulletWorth*(w: World, t: Team): float32 =
  ## Tiebreak rung 3's own expression (`GameWorld.java:293-312`): the supply
  ## plus `type.bulletCost` over every live robot of the team -- **and an
  ## ARCHON's `bulletCost` is `-1`, so each surviving archon SUBTRACTS a
  ## bullet**. The sum is float32 but every addend is an exact small
  ## integer-valued float, so the order of `robots()` is NOT observable here
  ## (stated so nobody ports it).
  result = w.bulletSupply[ord(t)]
  for id, r in w.robots:
    if r.team == t:
      result = result + bulletCostF(r.kind)

func archonSeparationMin*(spec: MapSpec): float = float(spec.separationMinTenths) / 10.0
func archonSeparationMax*(spec: MapSpec): float = float(spec.separationMaxTenths) / 10.0

# ---------------------------------------------------------------------------
#  The two id generators (D3)
# ---------------------------------------------------------------------------

proc setStart(gen: var IdGenerator, startingId: int) =
  ## `IDGenerator.setStart` + `allocateNextBlock`, written here rather than in
  ## `src/battlecode/rng.nim` so that year-neutral file stays untouched: the
  ## bullet generator needs a SECOND allocation from the SAME `Random` stream,
  ## and both allocations' 4 095 Fisher-Yates draws are load-bearing.
  gen.nextIdBlock = startingId
  gen.cursor = 0
  for i in 0 ..< IdBlockSize:
    gen.reserved[i] = int32(startingId + i + 1)
  for i in countdown(IdBlockSize - 1, 1):
    let index = int(gen.random.nextInt(i + 1))
    let a = gen.reserved[index]
    gen.reserved[index] = gen.reserved[i]
    gen.reserved[i] = a
  gen.nextIdBlock += IdBlockSize

proc peekRobotId*(w: World): int =
  ## The id the NEXT robot spawn would take, without consuming it -- the V3
  ## guard's input. `nextID()` is a pure array read plus a cursor bump, so
  ## peeking costs nothing and consumes no draw.
  int(w.idGen.reserved[w.idGen.cursor])

func idPoolWouldOverrun*(w: World): bool =
  ## **V3, the one guard the engine lacks.** `IDGenerator` never checks
  ## `MAX_ROBOT_ID`: after five blocks the robot ids reach 30 481..34 576 and
  ## overlap the bullet space that starts at 32 002, and `ObjectInfo`'s own
  ## comment (`:137-138`) names the hazard -- *"This can produce bugs if a
  ## bullet and a robot can have the same ID"*. Reaching it needs about
  ## 22 000 robots, i.e. about 2.2 M bullets, while the richest played map's
  ## tree income over 2 999 rounds is under 1.5 M -- so the floor is not
  ## reached in practice and the guard exists because "degrade, never hang"
  ## outranks fidelity to a collision.
  int(w.idGen.reserved[w.idGen.cursor]) > maxRobotId

# ---------------------------------------------------------------------------
#  Spawning and destroying
# ---------------------------------------------------------------------------

proc addToIndexRobot(w: World, r: Robot) =
  w.robotIndex.add(int32(r.id), r.loc, bodyRadius(r.kind))

proc spawnRobotWithId*(w: World, id: int, kind: RobotType, l: Loc,
                       team: Team): Robot {.discardable.} =
  ## `GameWorld.spawnRobot(ID, type, location, team)` +
  ## `ObjectInfo.spawnRobot`: the counters, the trove key set, the exec-order
  ## APPEND and the spatial index, in the engine's own order.
  result = Robot(id: id, team: team, kind: kind, loc: l,
                 health: startingHealth(kind), roundsAlive: 0, alive: true,
                 homeLoc: l, taskLoc: l, slot: -1, lastBroadcast: -99,
                 step: -1)
  w.robots[id] = result
  w.robotKeys.put(id)
  w.execOrder.add(id)
  w.robotCount[ord(team)] += 1
  w.addToIndexRobot(result)

proc spawnRobot*(w: World, kind: RobotType, l: Loc, team: Team): Robot
    {.discardable.} =
  let id = w.idGen.nextId()
  inc w.robotIdsIssued
  w.spawnRobotWithId(id, kind, l, team)

proc spawnTreeWithId*(w: World, id: int, team: Team, radius: float32, l: Loc,
                      containedBullets: int, containedRobot: int): Tree
    {.discardable.} =
  ## `GameWorld.spawnTree` + `ObjectInfo.spawnTree`. A NEUTRAL tree's health
  ## is `200 x radius`; a team's bullet tree is born at `0.2f * 50 = 10` with
  ## `maxHealth = 50` (`InternalTree.java:264-270`). **Trees are NOT in the
  ## exec order** -- they are updated by their own phase.
  let health =
    if team == tNeutral: neutralTreeHealthRate * radius
    else: plantedUnitStartingHealthFraction * bulletTreeMaxHealth
  let maxHealth =
    if team == tNeutral: neutralTreeHealthRate * radius
    else: bulletTreeMaxHealth
  result = Tree(id: id, team: team, loc: l, radius: radius, health: health,
                maxHealth: maxHealth, containedBullets: containedBullets,
                containedRobot: containedRobot, roundsAlive: 0, alive: true)
  w.trees[id] = result
  w.treeKeys.put(id)
  w.treeCount[ord(team)] += 1
  w.treeIndex.add(int32(id), l, radius)

proc spawnTree*(w: World, team: Team, radius: float32, l: Loc,
                containedBullets: int, containedRobot: int): Tree
    {.discardable.} =
  let id = w.idGen.nextId()
  inc w.robotIdsIssued
  w.spawnTreeWithId(id, team, radius, l, containedBullets, containedRobot)

proc setWinner*(w: World, t: Team, rung: int) =
  ## `GameWorld.setWinner`, and it has NO GUARD: a later call overwrites an
  ## earlier one, which is exactly what happens when both sides' win
  ## conditions fire in the same round. Reproduced literally.
  w.winner = t
  w.hasWinner = true
  w.domination = rung

proc setWinnerIfDestruction*(w: World) =
  ## `:231-237`. **Trees are not robots**, so a side whose last ROBOT dies
  ## loses even with forty trees standing. Team A is tested first.
  if w.robotCount[ord(tA)] == 0:
    w.setWinner(tB, RungDestroyed)
  elif w.robotCount[ord(tB)] == 0:
    w.setWinner(tA, RungDestroyed)

proc setWinnerIfVictoryPoints*(w: World) =
  ## `:239-245`, called from `donate` and therefore MID-ROUND. Team A is
  ## tested first, so a simultaneous crossing is impossible (donations are
  ## sequential anyway).
  if w.victoryPoints[ord(tA)] >= victoryPointsToWin:
    w.setWinner(tA, RungVictoryPoints)
  elif w.victoryPoints[ord(tB)] >= victoryPointsToWin:
    w.setWinner(tB, RungVictoryPoints)

proc noteRobotLoss(w: World, r: Robot) =
  let t = ord(r.team)
  w.stats.unitsLost[t] += 1
  w.stats.lostThisRound[t] += 1
  case r.kind
  of rtArchon:
    w.stats.archonsLost[t] += 1
    discard w.beat(BeatArchonLost, "archon_lost", t,
                   int(r.loc.x * 10) * 100000 + int(r.loc.y * 10),
                   w.robotCount[t] - 0, "bullet")
  of rtGardener:
    w.stats.gardenersLost[t] += 1
    discard w.beat(BeatGardenerLost, "gardener_lost", t,
                   int(r.loc.x * 10) * 100000 + int(r.loc.y * 10),
                   w.unitCount(r.team, rtGardener) - 1)
  else: discard

proc destroyRobot*(w: World, id: int) =
  ## `GameWorld.destroyRobot` -> `ObjectInfo.destroyRobot` +
  ## `setWinnerIfDestruction`. Removal from the exec order is BY VALUE.
  if not w.robots.hasKey(id): return
  let r = w.robots[id]
  w.noteRobotLoss(r)
  r.alive = false
  w.robotCount[ord(r.team)] -= 1
  w.robots.del(id)
  w.robotKeys.remove(id)
  var i = 0
  while i < w.execOrder.len:
    if w.execOrder[i] == id:
      w.execOrder.delete(i)
      break
    inc i
  w.robotIndex.remove(int32(id))
  w.setWinnerIfDestruction()

proc destroyBullet*(w: World, id: int) =
  if not w.bullets.hasKey(id): return
  w.bullets[id].alive = false
  w.bullets.del(id)
  w.bulletKeys.remove(id)
  var i = 0
  while i < w.execOrder.len:
    if w.execOrder[i] == id:
      w.execOrder.delete(i)
      break
    inc i
  w.bulletIndex.remove(int32(id))

proc damageRobot*(w: World, r: Robot, damage: float32,
                  byTeam = tNeutral) =
  ## `InternalRobot.damageRobot` (`:227-231`): `health = max(health - damage,
  ## 0)` in float32, then **`killRobotIfDead()` on an exact `health == 0`
  ## compare**. The `byTeam` argument is TELEMETRY ONLY -- the engine's method
  ## takes no attacker at all -- and is what lets the results document
  ## separate friendly fire from damage dealt.
  if not r.alive: return
  let before = r.health
  r.health = max(r.health - damage, 0'f32)
  let dealt = before - r.health
  if byTeam != tNeutral:
    w.stats.damageDealt[ord(byTeam)] =
      w.stats.damageDealt[ord(byTeam)] + dealt
    if r.team == byTeam:
      w.stats.friendlyFireDamage[ord(byTeam)] =
        w.stats.friendlyFireDamage[ord(byTeam)] + dealt
  if r.team != tNeutral:
    w.stats.damageTaken[ord(r.team)] =
      w.stats.damageTaken[ord(r.team)] + dealt
  if r.health == 0'f32:
    if byTeam != tNeutral and byTeam != r.team:
      w.stats.kills[ord(byTeam)] += 1
      if r.kind == rtGardener:
        w.stats.enemyGardenersKilled[ord(byTeam)] += 1
    w.destroyRobot(r.id)

proc repairRobot*(w: World, r: Robot, healAmount: float32) =
  ## `InternalRobot.repairRobot` (`:219-225`):
  ## `health = min(health + healAmount, type.maxHealth)` in float32, then a
  ## REDUNDANT second clamp the engine writes anyway.
  r.health = min(r.health + healAmount, maxHealthF(r.kind))
  if r.health > maxHealthF(r.kind):
    r.health = maxHealthF(r.kind)

proc setRobotLocation*(w: World, r: Robot, l: Loc) =
  ## `InternalRobot.setLocation` -> `ObjectInfo.moveRobot`.
  w.robotIndex.move(int32(r.id), l)
  r.loc = l

proc setBulletLocation*(w: World, b: Bullet, l: Loc) =
  w.bulletIndex.move(int32(b.id), l)
  b.loc = l

# ---------------------------------------------------------------------------
#  Bullet supply, victory points and broadcasting
# ---------------------------------------------------------------------------

proc adjustBulletSupply*(w: World, t: Team, amount: float32) =
  ## `TeamInfo.adjustBulletSupply`: a bare float32 `+=` with NO CLAMP.
  w.bulletSupply[ord(t)] = w.bulletSupply[ord(t)] + amount

proc adjustVictoryPoints*(w: World, t: Team, amount: int) =
  w.victoryPoints[ord(t)] += amount

func bulletSupplyOf*(w: World, t: Team): float32 = w.bulletSupply[ord(t)]

func victoryPointCost*(w: World): float32 =
  ## `RobotControllerImpl.getVictoryPointCost` (`:1173`):
  ## `VP_BASE_COST + VP_INCREASE_PER_ROUND * getRoundNum()`, all float32 --
  ## 7.5 on round 1 and 19.995833 on round 2 999.
  vpBaseCost + vpIncreasePerRound * float32(w.currentRound)

proc addBroadcaster*(w: World, r: Robot) =
  ## `GameWorld.addBroadcaster`: into the trove map KEYED BY ROBOT ID, so
  ## repeats in one turn overwrite one entry.
  w.currentBroadcasters.put(r.id)
  w.broadcasterInfo[r.id] = Broadcaster(id: r.id, team: r.team, loc: r.loc)

proc updateBroadcastData*(w: World) =
  ## `GameWorld.updateBroadCastData` (`:454-459`):
  ## `previousBroadcasters = currentBroadcasters.values(new RobotInfo[size])`
  ## -- **trove order, high slot to low** -- then `clear()`, **which RETAINS
  ## the table's capacity** (D1). This array is what
  ## `senseBroadcastingRobotLocations()` hands a chassis, FOR BOTH TEAMS, so
  ## its order is observable to the bot and therefore to the game.
  w.previousBroadcasters = @[]
  for id in w.currentBroadcasters.valuesDescending:
    if w.broadcasterInfo.hasKey(id):
      w.previousBroadcasters.add(w.broadcasterInfo[id])
  w.currentBroadcasters.clear()
  w.broadcasterInfo.clear()

# ---------------------------------------------------------------------------
#  Construction
# ---------------------------------------------------------------------------

proc newWorld*(spec: MapSpec, maxRounds: int): World =
  ## `new GameWorld(gm, cp, oldTeamMemory, matchMaker)`: the two id
  ## generators (both from the MAP seed, the bullet one with its two-block
  ## head start), the trove key sets, the 300-bullet start, and then the
  ## initial bodies IN THE MAP FILE'S ID ORDER -- which is `LiveMap`'s own
  ## sort and therefore the opening exec order.
  result = World(
    map: spec, rect: spec.rect, maxRounds: maxRounds,
    currentRound: 0, running: true,
    robots: initTable[int, Robot](),
    trees: initTable[int, Tree](),
    bullets: initTable[int, Bullet](),
    robotKeys: initTroveIntMap(),
    treeKeys: initTroveIntMap(),
    bulletKeys: initTroveIntMap(),
    currentBroadcasters: initTroveIntMap(),
    broadcasterInfo: initTable[int, Broadcaster](),
    lastAction: initTable[int, tuple[act: int, tgt: int,
                                     x, y, arg: float32]](),
    robotIndex: initIndex(spec.rect),
    treeIndex: initIndex(spec.rect),
    bulletIndex: initIndex(spec.rect),
    winner: tA, hasWinner: false, domination: RungNone,
    tiebreakRound: maxRounds,
    hashChain: 0xcbf29ce484222325'u64)
  result.broadcastArray[0] = newSeq[int](broadcastMaxChannels)
  result.broadcastArray[1] = newSeq[int](broadcastMaxChannels)
  result.idGen = initIdGenerator(spec.mapSeed)
  result.bulletIdGen = initIdGenerator(spec.mapSeed)
  result.bulletIdGen.setStart(maxRobotId + 1)
  result.adjustBulletSupply(tA, bulletsInitialAmount)
  result.adjustBulletSupply(tB, bulletsInitialAmount)
  when defined(bc17BrokenChassis):
    result.brokenChassis = true
  for body in spec.bodies:
    if body.isRobot:
      discard result.spawnRobotWithId(body.id, body.kind, body.loc, body.team)
    else:
      discard result.spawnTreeWithId(body.id, body.team, body.radius,
                                     body.loc, body.containedBullets,
                                     body.containedRobot)
  for t in 0 .. 1:
    result.stats.archonsStart[t] = result.unitCount(Team(t), rtArchon)

# ---------------------------------------------------------------------------
#  Checksums for the parity trace and the hash chain
# ---------------------------------------------------------------------------

proc execOrderFold*(w: World): uint64 = fnv1a64(w.execOrder)

proc robotBodyFold*(w: World): uint64 =
  ## `(id, bits(x), bits(y), bits(health))` over every live robot **in EXEC
  ## ORDER**, which is what makes an ordering bug visible on the round it
  ## happens rather than 400 rounds later.
  var vals: seq[uint32]
  for id in w.execOrder:
    if w.robots.hasKey(id):
      let r = w.robots[id]
      vals.add(uint32(r.id))
      vals.add(cast[uint32](r.loc.x))
      vals.add(cast[uint32](r.loc.y))
      vals.add(cast[uint32](r.health))
  fnv1a64Bits(vals)

proc treeBodyFold*(w: World): uint64 =
  ## The same fold over every live tree **in TROVE ORDER** (D1).
  var vals: seq[uint32]
  for id in w.treeKeys.valuesDescending:
    if w.trees.hasKey(id):
      let tr = w.trees[id]
      vals.add(uint32(tr.id))
      vals.add(cast[uint32](tr.loc.x))
      vals.add(cast[uint32](tr.loc.y))
      vals.add(cast[uint32](tr.health))
  fnv1a64Bits(vals)

proc bulletBodyFold*(w: World): uint64 =
  var vals: seq[uint32]
  for id in w.execOrder:
    if w.bullets.hasKey(id):
      let b = w.bullets[id]
      vals.add(uint32(b.id))
      vals.add(cast[uint32](b.loc.x))
      vals.add(cast[uint32](b.loc.y))
      vals.add(cast[uint32](b.dir.radians))
  fnv1a64Bits(vals)

proc broadcasterFold*(w: World): uint64 =
  ## `previousBroadcasters` IN ITS OWN ORDER, so a trove bug surfaces on the
  ## round it happens (D1's second observable).
  var vals: seq[uint32]
  for b in w.previousBroadcasters:
    vals.add(uint32(b.id))
    vals.add(cast[uint32](b.loc.x))
    vals.add(cast[uint32](b.loc.y))
  fnv1a64Bits(vals)

func hashChainHexOf*(w: World): string = toHex(w.hashChain)
