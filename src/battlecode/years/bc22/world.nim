## The Battlecode 2022 "Mutation" world: state, geometry and every legality rule
## a ROBOT can reach.
##
## A behaviour-for-behaviour port of `battlecode/world/GameWorld.java` (741
## lines), `world/InternalRobot.java` (497), `world/RobotControllerImpl.java`
## (935), `world/ObjectInfo.java` (226), `world/TeamInfo.java` (129) and
## `world/LiveMap.java` at commit
## `6ed05b679c0822e9bbe332812ff5655812dd023e`, together with the pieces of
## `common/MapLocation.java` and `common/Direction.java` the rules depend on.
## The port is the authority at runtime; the Java engine survives only as the
## `parity-oracle-bc22` CI job (docs/PARITY.md).
##
## `buildings.nim`, `economy.nim` and `anomaly.nim` import this file;
## `units.nim` and `trove.nim` are pure and are imported BY it.
##
## Nine things in here look like details and are not:
##
## * **The exec order is DYNAMIC and mutated BY VALUE.** `ObjectInfo`'s
##   `dynamicBodyExecOrder` is a plain append-ordered `TIntArrayList`; a robot
##   built is appended, a robot destroyed is removed from wherever it sits and
##   everything after it shifts forward. The sweep iterates a SNAPSHOT taken
##   before it starts, so a robot built this round does not take a turn this
##   round, and a robot destroyed mid-sweep is skipped by the `existsRobot`
##   guard. The INITIAL archons are appended in ASCENDING ID, because
##   `LiveMap`'s constructor sorts them and the official maps carry ids BELOW
##   the 10 000 `IDGenerator` floor — so A and B alternate in the opening order.
## * **`ObjectInfo.robotsArray()` is a trove hash-order walk and it decides who
##   dies to a global CHARGE.** `trove.nim` reproduces it (D2); `w.trove` is
##   kept in lock step with `robotsById` by `spawnRobot` and `destroyRobot`, and
##   nothing else may touch it.
## * **Both cooldowns start a robot's life at ZERO.** `InternalRobot`'s
##   constructor sets them to 0, not to `COOLDOWN_LIMIT`, so a droid built on
##   round *r* takes its first turn on round *r+1* and can act AND move on it.
##   This is the opposite of bc23 and it is why bc22 armies grow so fast.
## * **A MINER's action cooldown is 2 against a limit of 10**, and
##   `canActCooldown` is `< 10`, so a miner mines up to FIVE times in one turn
##   on rubble-free ground and exactly once on rubble 60.
## * **The rubble multiplier is read at `this.location` when the charge is
##   made.** `move()` moves the robot FIRST and then charges at the
##   DESTINATION; every other action charges at the actor's own unchanged
##   square; `mutate()` charges the BUILDER at the builder's square and the
##   BUILDING's 100+100 at the building's square.
## * **An attack needs no vision.** `assertCanAttack` checks the action radius
##   and the map, never `canSenseLocation` — a soldier can shoot a square it
##   cannot see.
## * **`ANNIHILATION` fires MID-TURN** inside `destroyRobot`, and `running` is
##   only cleared at the end of the round, so every robot after the killer in
##   the exec order still takes its turn.
## * **`addHealth` is the single mutation point for health and it is
##   re-entrant**: it caps at max, promotes a full-health PROTOTYPE to TURRET,
##   and calls `destroyRobot` at `<= 0` — from inside a repair, an attack, a
##   mutation and every anomaly.
## * **`getAllLocationsWithinRadiusSquared`'s scan order is load-bearing**: x
##   ascending outer, y ascending inner over the clamped `ceil(sqrt(r2)) + 1`
##   box. It fixes which enemy `senseNearbyRobots` returns first (which is the
##   square the example bot's soldier attacks), the order ABYSS and FURY sweep
##   the map, and the order the sage anomalies apply.

import std/[algorithm, tables]
import ../../sim_types, ../../rng
import units, trove

export units, trove, rng, tables

type
  MapSpec* = object
    ## One converted `.map22`, as `data/maps/bc22/<name>.json` carries it.
    name*: string
    width*, height*: int
    randomSeed*: int
    symmetry*: Symmetry
    rounds*: int
    rubble*: seq[int]
    lead*: seq[int]
    anomalies*: seq[tuple[round: int, kind: AnomalyKind]]
      ## In FILE ORDER. The engine consumes them in order and asserts nothing
      ## about sortedness; measured across all 75 official maps, every schedule
      ## is already ascending in round.
    initialBodies*: seq[tuple[id, x, y, team, kind: int]]
      ## SORTED ASCENDING BY ID by the converter, because `LiveMap`'s
      ## constructor sorts by id and that order IS the initial exec order.

  Robot* = ref object
    id*: int
    team*: Team
    kind*: RobotType
    loc*: Loc
    level*: int
    mode*: RobotMode
    health*: int
    roundsAlive*: int
    actionCooldown*: int
    movementCooldown*: int
    numVisibleFriendlyRobots*: int
      ## `InternalRobot.numVisibleFriendlyRobots`, a CACHED field refreshed by
      ## `updateNumVisibleFriendlyRobots()`. The global CHARGE refreshes every
      ## droid's before sorting and then reads the cache; the laboratory's
      ## transmutation rate refreshes its own on the spot.
    alive*: bool
    disintegrated*: bool
    opsLeft*: int              ## the DecisionOps budget replacing the JVM limit
    opsUsed*: int
    ## --- chassis-side memory, never read by a rule ---
    scaffoldRng*: JavaRandom
      ## `static final Random rng = new Random(6147)`. Static fields are PER
      ## ROBOT under the instrumenter, so every unit gets its own stream and the
      ## example bot needs no determinism patch.
    noRepeat*: seq[Loc]
    homeArchon*: Loc
    hasHome*: bool
    task*: int
    taskLoc*: Loc
    hasTask*: bool
    roundsSinceShot*: int
    minedThisTurn*: bool

  TeamStats* = object
    ## `TeamInfo` plus the per-game counters `results.games[]` reports. The
    ## engine keeps only the two reserves and the shared arrays; everything else
    ## is telemetry and is never read by a rule.
    lead*: array[2, int]
    gold*: array[2, int]
    sharedArray*: array[2, array[64, int]]
    ## --- telemetry ---
    archonsStart*: array[2, int]
    archonsLost*: array[2, int]
    archonRelocations*: array[2, int]
    leadMined*: array[2, int]
    goldMined*: array[2, int]
    leadReclaimed*: array[2, int]
    goldReclaimed*: array[2, int]
    squaresMinedDry*: array[2, int]
      ## Squares this faction's miners took from >= 1 to 0. THE SIGNATURE OF THE
      ## YEAR: the map adds +5 every 20 rounds only to squares that still hold
      ## at least 1, so a square mined dry is dead for the rest of the game.
    unitsBuilt*: array[2, int]
    minersBuilt*: array[2, int]
    buildersBuilt*: array[2, int]
    soldiersBuilt*: array[2, int]
    sagesBuilt*: array[2, int]
    labsBuilt*: array[2, int]
    labsFinished*: array[2, int]
    watchtowersBuilt*: array[2, int]
    watchtowersFinished*: array[2, int]
    mutationsL2*: array[2, int]
    mutationsL3*: array[2, int]
    transmutes*: array[2, int]
    goldTransmuted*: array[2, int]
    leadSpentTransmuting*: array[2, int]
    repairs*: array[2, int]
    hpRepaired*: array[2, int]
    envisions*: array[2, int]
    damageDealt*: array[2, int]
    sageDamage*: array[2, int]
    soldierDamage*: array[2, int]
    watchtowerDamage*: array[2, int]
    arrayWrites*: array[2, int]
    transforms*: array[2, int]
    roundsWithALab*: array[2, int]
    robotsLost*: array[2, int]
    anomalyLossesCharge*: array[2, int]
    anomalyLossesFuryHp*: array[2, int]
    anomalyLossesAbyssLead*: array[2, int]
    anomaliesDodged*: array[2, int]
    archonsAliveAt1500*: array[2, int]

  World* = ref object
    map*: MapSpec
    width*, height*: int
    currentRound*: int
    maxRounds*: int
    running*: bool
    idGen*: IdGenerator
      ## `IDGenerator(map.getSeed())` — the 48-bit LCG that fixes the id of
      ## every robot ever built.
    rand*: JavaRandom
      ## `GameWorld.rand = new Random(map.getSeed())`. bc22 is the FIRST year
      ## this repo ships that actually READS it at round time: the VORTEX draw
      ## is `rand.nextInt(width == height ? 3 : 2)`. It is a SEPARATE object
      ## from `idGen.random` with its own 48-bit state, seeded from the same
      ## number — so the port keeps two independent streams rather than one.
    symmetry*: Symmetry
    rubble*: seq[int]
    leadAt*: seq[int]
    goldAt*: seq[int]
    occupant*: seq[Robot]
    robotsById*: Table[int, Robot]
    trove*: TroveIntMap
      ## `ObjectInfo.gameRobotsByID`, kept ONLY for its iteration order (D2).
    execOrder*: seq[int]
    typeCount*: array[2, array[RobotType, int]]
    archonsAlive*: array[2, int]
    anomalyCursor*: int
    stats*: TeamStats
    winner*: Team
    hasWinner*: bool
    domination*: Domination
    transmuteTable*: array[3, array[177, int]]
      ## `data/bc22/tables.json`'s `transmute_rate`, loaded by `economy.nim`.
      ## THE RUNTIME PATH HAS NO TRANSCENDENTAL AT ALL.
    ## Replay/telemetry sinks — never read by a rule.
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    hashChain*: uint64
    beatCount*: array[20, int]
    refusedActions*: int
      ## THE LEGALITY AUDIT. Every `do*` re-checks its own `can*` and no-ops
      ## when it fails; this counts those no-ops. A chassis that emits an
      ## illegal order is a chassis whose orders were never checked, so
      ## `tests/test_bc22_baselines.nim` plays whole games and asserts this
      ## stays ZERO.
    opsUsedPeak*: int
    firstActionSeen*: array[2, bool]
    firstSageSeen*: array[2, bool]
    goldMilestone*: array[2, int]
    lostThisRound*: array[2, int]
    attackersLostThisRound*: array[2, int]
    brokenChassis*: bool
      ## Set by `-d:bc22BrokenChassis`: the NEGATIVE CONTROL for the
      ## economic-survival gate (§Tests item 17). Miners ignore `mine_floor` and
      ## always mine to zero, and archons never commission a builder.

# ---------------------------------------------------------------------------
#  Beats
# ---------------------------------------------------------------------------

const
  BeatGameStart* = 0
  BeatFirstAction* = 1
  BeatLabBuilt* = 2
  BeatFirstSage* = 3
  BeatWatchtowerBuilt* = 4
  BeatMutation* = 5
  BeatGoldMilestone* = 6
  BeatAnomalyStruck* = 7
  BeatAnomalyDodged* = 8
  BeatArchonLost* = 9
  BeatArchonRelocated* = 10
  BeatRout* = 11
  BeatDuel* = 12
  BeatSingularity* = 13

  BeatBounds* = [1, 4, 12, 2, 16, 24, 20, 14, 20, 8, 16, 20, 20, 1,
                 0, 0, 0, 0, 0, 0]
    ## Per GAME, in the order above and in the design note's own event table.
    ## `tests/test_bc22_replay.nim` asserts every one of them against a real
    ## match, so a pathological game cannot produce a 20 MB replay.
    ## `anomaly_struck` is 14 against a MEASURED maximum schedule length of 13.

const
  Bc22ActionMove* = 0
  Bc22ActionBuildRobot* = 1
  Bc22ActionAttack* = 2
  Bc22ActionEnvision* = 3
  Bc22ActionRepair* = 4
  Bc22ActionMineLead* = 5
  Bc22ActionMineGold* = 6
  Bc22ActionMutate* = 7
  Bc22ActionTransmute* = 8
  Bc22ActionTransform* = 9
  Bc22ActionWriteArray* = 10
  Bc22ActionDisintegrate* = 11
    ## The ordinals `years/dispatch.nim`'s `Bc22ActionNames` spells out, so
    ## `first_action.action` has a DOCUMENTED VOCABULARY (the r1-F14 lesson).

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
  ## The same step for a value that is ALREADY a 64-bit hash. It exists because
  ## `mixHash(int(h and 0xFFFFFFFF'u64))` is a 64-bit-only expression: `int` is
  ## 32 bits under wasm32, the masked value runs to 4294967295, and the
  ## conversion raises RangeDefect the moment the browser re-derives round 1 —
  ## while the native test suite, on amd64, is green.
  w.hashChain = (w.hashChain xor (v and 0xFFFFFFFF'u64)) *
    0x100000001B3'u64

# ---------------------------------------------------------------------------
#  Geometry
# ---------------------------------------------------------------------------

func idx*(w: World, l: Loc): int = l.x + l.y * w.width
func indexToLoc*(w: World, i: int): Loc = loc(i mod w.width, i div w.width)
func onTheMap*(w: World, l: Loc): bool =
  l.x >= 0 and l.y >= 0 and l.x < w.width and l.y < w.height

iterator locationsWithinRadiusSquared*(w: World, center: Loc, r2: int): Loc =
  ## `GameWorld.getAllLocationsWithinRadiusSquaredWithoutMap`, verbatim: x
  ## ascending outer, y ascending inner, over the clamped `ceil(sqrt(r2)) + 1`
  ## box. `ceil(sqrt())` comes from the precomputed table in `units.nim`, so the
  ## port has no `sqrt` and no `fdlibm` path here.
  let clamped = max(0, min(r2, CeilSqrtTable.high))
  let ceiled = CeilSqrtTable[clamped] + 1
  let minX = max(center.x - ceiled, 0)
  let minY = max(center.y - ceiled, 0)
  let maxX = min(center.x + ceiled, w.width - 1)
  let maxY = min(center.y + ceiled, w.height - 1)
  for x in minX .. maxX:
    for y in minY .. maxY:
      let l = loc(x, y)
      if center.isWithinDistanceSquared(l, r2):
        yield l

iterator allLocations*(w: World): Loc =
  ## `getAllLocations()` is the same function with `Integer.MAX_VALUE`, so the
  ## `ceiledRadius` box clamps to the whole map and every square passes the
  ## distance test. The ORDER — x ascending outer, y ascending inner — is what
  ## ABYSS and FURY sweep in.
  for x in 0 ..< w.width:
    for y in 0 ..< w.height:
      yield loc(x, y)

func symmetricLoc*(w: World, l: Loc): Loc =
  case w.symmetry
  of symVertical: loc(l.x, w.height - 1 - l.y)
  of symHorizontal: loc(w.width - 1 - l.x, l.y)
  of symRotation: loc(w.width - 1 - l.x, w.height - 1 - l.y)

# ---------------------------------------------------------------------------
#  Terrain and occupancy
# ---------------------------------------------------------------------------

func getRubble*(w: World, l: Loc): int = w.rubble[w.idx(l)]
func getLead*(w: World, l: Loc): int = w.leadAt[w.idx(l)]
func getGold*(w: World, l: Loc): int = w.goldAt[w.idx(l)]

proc setLead*(w: World, l: Loc, amount: int) = w.leadAt[w.idx(l)] = amount
proc setGold*(w: World, l: Loc, amount: int) = w.goldAt[w.idx(l)] = amount

func getRobot*(w: World, l: Loc): Robot =
  if w.onTheMap(l): w.occupant[w.idx(l)] else: nil

func isLocationOccupied*(w: World, l: Loc): bool = w.getRobot(l) != nil

func robotById*(w: World, id: int): Robot =
  if w.robotsById.hasKey(id): w.robotsById[id] else: nil

func existsRobot*(w: World, id: int): bool = w.robotsById.hasKey(id)

func robotCountByType*(w: World, t: Team, k: RobotType): int =
  w.typeCount[ord(t)][k]

func robotsAlive*(w: World, t: Team): int =
  for k in RobotType: result += w.typeCount[ord(t)][k]

func canSenseLocation*(w: World, r: Robot, l: Loc): bool =
  ## `InternalRobot.canSenseLocation`. THERE IS NO FOG MECHANIC BEYOND THE
  ## RADIUS in this year: no clouds, no terrain occlusion.
  w.onTheMap(l) and
    r.loc.distanceSquaredTo(l) <= RobotSpecs[r.kind].visionRadiusSquared

func canActLocation*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanActLocation`: within the action radius AND on the map. No vision
  ## test — which is how a soldier shoots a square it cannot see.
  w.onTheMap(l) and
    r.loc.distanceSquaredTo(l) <= RobotSpecs[r.kind].actionRadiusSquared

func canActCooldown*(r: Robot): bool =
  r.mode.canAct and r.actionCooldown < CooldownLimit

func canMoveCooldown*(r: Robot): bool =
  r.mode.canMove and r.movementCooldown < CooldownLimit

func canTransformCooldown*(r: Robot): bool =
  ## Reads the MODE-APPROPRIATE counter, which is what makes the engine
  ## self-consistent despite `transform` charging only one of them.
  if r.mode == rmTurret: r.actionCooldown < CooldownLimit
  elif r.mode == rmPortable: r.movementCooldown < CooldownLimit
  else: false

func transformCooldownTurns*(r: Robot): int =
  if r.mode == rmTurret: r.actionCooldown
  elif r.mode == rmPortable: r.movementCooldown
  else: -1

func canMutateSelf*(r: Robot): bool =
  ## `InternalRobot.canMutate`: not a DROID, not a PROTOTYPE, not already
  ## level 3.
  if r.mode == rmDroid or r.mode == rmPrototype: return false
  if r.level == MaxLevel: return false
  true

func maxHealth*(r: Robot): int = maxHealthOf(r.kind, r.level)

# ---------------------------------------------------------------------------
#  DecisionOps — the budget that replaces the JVM bytecode limit
# ---------------------------------------------------------------------------

proc spend*(r: Robot, n: int): bool {.discardable.} =
  ## Charged BEFORE each primitive and never inside one, so a primitive's RESULT
  ## is never a function of the remaining budget — only whether the chassis got
  ## to ask. When the budget runs out the robot's turn ends where it stands; it
  ## is not resumed mid-computation next turn, which is the one place this
  ## differs from the JVM (docs/RULES-BC22.md §Divergences item 1).
  if r.opsLeft < n: return false
  r.opsLeft -= n
  r.opsUsed += n
  true

# ---------------------------------------------------------------------------
#  Team reserves
# ---------------------------------------------------------------------------

func teamLead*(w: World, t: Team): int = w.stats.lead[ord(t)]
func teamGold*(w: World, t: Team): int = w.stats.gold[ord(t)]

proc addLead*(w: World, t: Team, amount: int) =
  ## `TeamInfo.addLead`, which THROWS rather than clamping when a spend would
  ## take a team negative. Every caller checks first; a raise here means a
  ## legality bug, not a game state, and the server turns it into
  ## `results.reason = fault`.
  if w.stats.lead[ord(t)] + amount < 0:
    raise newException(BattlecodeError, "bc22: invalid lead change")
  w.stats.lead[ord(t)] += amount

proc addGold*(w: World, t: Team, amount: int) =
  if w.stats.gold[ord(t)] + amount < 0:
    raise newException(BattlecodeError, "bc22: invalid gold change")
  w.stats.gold[ord(t)] += amount

# ---------------------------------------------------------------------------
#  Cooldowns
# ---------------------------------------------------------------------------

proc addActionCooldownTurns*(w: World, r: Robot, base: int) =
  ## `InternalRobot.addActionCooldownTurns` reads `this.location` AT THE MOMENT
  ## IT IS CALLED — which for a move is the destination and for everything else
  ## the actor's own square.
  r.actionCooldown += cooldownWithMultiplier(base, w.getRubble(r.loc))

proc addMovementCooldownTurns*(w: World, r: Robot, base: int) =
  r.movementCooldown += cooldownWithMultiplier(base, w.getRubble(r.loc))

# ---------------------------------------------------------------------------
#  Spawning and destruction
# ---------------------------------------------------------------------------

proc placeRobot(w: World, r: Robot) = w.occupant[w.idx(r.loc)] = r
proc clearTile(w: World, l: Loc) = w.occupant[w.idx(l)] = nil

proc spawnRobot*(w: World, id: int, kind: RobotType, l: Loc,
                 t: Team): Robot {.discardable.} =
  ## `GameWorld.spawnRobot` + `InternalRobot`'s constructor. BOTH COOLDOWNS
  ## START AT ZERO, and a building spawns as a PROTOTYPE at
  ## `(int)(0.8f * maxHealth)`.
  var mode = startingMode(kind)
  var health = maxHealthOf(kind, 1)
  if mode == rmPrototype:
    health = prototypeHealth(health)
  var r = Robot(id: id, team: t, kind: kind, loc: l, level: 1, mode: mode,
                health: health, alive: true,
                actionCooldown: 0, movementCooldown: 0,
                opsLeft: budgetFor(kind), taskLoc: loc(-1, -1),
                homeArchon: loc(-1, -1))
  r.scaffoldRng = initJavaRandom(6147)
  w.robotsById[id] = r
  w.trove.put(id)
  w.execOrder.add(id)
  w.placeRobot(r)
  w.typeCount[ord(t)][kind] += 1
  if kind == rtArchon: w.archonsAlive[ord(t)] += 1
  r

proc setWinner*(w: World, t: Team, d: Domination) =
  w.winner = t
  w.hasWinner = true
  w.domination = d

proc destroyRobot*(w: World, id: int, checkArchonDeath = true) =
  ## `GameWorld.destroyRobot`: the tile is cleared, the RECLAIM DROP lands on
  ## the square the robot last occupied AND STACKS, the id leaves the exec order
  ## BY VALUE (the first entry equal to it, preserving the order of the
  ## survivors) and leaves the trove map, and — unless `checkArchonDeath` is
  ## false — an archon that was the team's last one fires `ANNIHILATION`
  ## IMMEDIATELY, mid-turn.
  if not w.robotsById.hasKey(id): return
  let r = w.robotsById[id]
  let t = r.team
  let kind = r.kind
  if w.getRobot(r.loc) == r:
    w.clearTile(r.loc)

  let leadDrop = leadDropped(kind, r.level)
  let goldDrop = goldDropped(kind, r.level)
  let i = w.idx(r.loc)
  w.leadAt[i] += leadDrop
  w.goldAt[i] += goldDrop
  w.stats.leadReclaimed[ord(t.other())] += leadDrop
  w.stats.goldReclaimed[ord(t.other())] += goldDrop

  for k in 0 ..< w.execOrder.len:
    if w.execOrder[k] == id:
      w.execOrder.delete(k)
      break
  w.robotsById.del(id)
  w.trove.remove(id)
  w.typeCount[ord(t)][kind] -= 1
  if kind == rtArchon: w.archonsAlive[ord(t)] -= 1
  r.alive = false
  w.stats.robotsLost[ord(t)] += 1
  w.lostThisRound[ord(t)] += 1
  if canAttackType(kind): w.attackersLostThisRound[ord(t)] += 1

  if checkArchonDeath and kind == rtArchon and
      w.robotCountByType(t, rtArchon) == 0:
    ## `setWinner` here OVERWRITES any earlier winner, exactly as the engine
    ## does: both teams can be annihilated in the same round and the SECOND
    ## death wins.
    w.setWinner(t.other(), dfAnnihilated)

proc addHealth*(w: World, r: Robot, amount: int, checkArchonDeath = true) =
  ## `InternalRobot.addHealth`, the single mutation point for health:
  ## cap at `getMaxHealth(level)`, PROMOTE A FULL-HEALTH PROTOTYPE TO TURRET,
  ## and destroy at `<= 0`. Re-entrant: a repair, an attack, a mutation and
  ## every anomaly all come through here.
  if not r.alive: return
  r.health += amount
  let cap = r.maxHealth()
  if r.health >= cap:
    r.health = cap
    if r.mode == rmPrototype:
      r.mode = rmTurret
      if r.kind == rtLaboratory:
        w.stats.labsFinished[ord(r.team)] += 1
      elif r.kind == rtWatchtower:
        w.stats.watchtowersFinished[ord(r.team)] += 1
  if r.health <= 0:
    w.destroyRobot(r.id, checkArchonDeath)

# ---------------------------------------------------------------------------
#  Sensing
# ---------------------------------------------------------------------------

proc updateNumVisibleFriendlyRobots*(w: World, r: Robot): int
    {.discardable.} =
  ## `InternalRobot.updateNumVisibleFriendlyRobots` ==
  ## `senseNearbyRobots(-1, getTeam()).length` — every friendly robot inside the
  ## robot's OWN vision radius, EXCLUDING ITSELF.
  var n = 0
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[r.kind].visionRadiusSquared):
    let other = w.getRobot(l)
    if other != nil and other.id != r.id and other.team == r.team:
      n += 1
  r.numVisibleFriendlyRobots = n
  n

iterator senseNearbyRobots*(w: World, r: Robot, r2: int): Robot =
  ## `senseNearbyRobots(radiusSquared, null)` in the engine's SCAN ORDER, which
  ## is what fixes the square the example bot's soldier attacks. `r2 == -1`
  ## means "my whole vision radius"; anything larger is clamped to it.
  let vis = RobotSpecs[r.kind].visionRadiusSquared
  let actual = if r2 == -1: vis else: min(r2, vis)
  for l in w.locationsWithinRadiusSquared(r.loc, actual):
    let other = w.getRobot(l)
    if other != nil and other.id != r.id and w.canSenseLocation(r, other.loc):
      yield other

# ---------------------------------------------------------------------------
#  The end ladder — `GameWorld`'s own methods, so `anomaly.nim` can reach them
# ---------------------------------------------------------------------------

func goldNetWorth*(w: World, t: Team): int =
  ## The team's reserve PLUS `getGoldWorth(level)` over every live robot of that
  ## team. The engine sums it over `robotsArray()`, which is order-free.
  result = w.stats.gold[ord(t)]
  for _, r in w.robotsById:
    if r.team == t: result += goldWorth(r.kind, r.level)

func leadNetWorth*(w: World, t: Team): int =
  result = w.stats.lead[ord(t)]
  for _, r in w.robotsById:
    if r.team == t: result += leadWorth(r.kind, r.level)

proc setWinnerIfMoreArchons*(w: World): bool =
  let a = w.robotCountByType(teamA, rtArchon)
  let b = w.robotCountByType(teamB, rtArchon)
  if a > b: w.setWinner(teamA, dfMoreArchons); true
  elif a < b: w.setWinner(teamB, dfMoreArchons); true
  else: false

proc setWinnerIfMoreGoldValue*(w: World): bool =
  let a = w.goldNetWorth(teamA)
  let b = w.goldNetWorth(teamB)
  if a > b: w.setWinner(teamA, dfMoreGoldNetWorth); true
  elif b > a: w.setWinner(teamB, dfMoreGoldNetWorth); true
  else: false

proc setWinnerIfMoreLeadValue*(w: World): bool =
  let a = w.leadNetWorth(teamA)
  let b = w.leadNetWorth(teamB)
  if a > b: w.setWinner(teamA, dfMoreLeadNetWorth); true
  elif b > a: w.setWinner(teamB, dfMoreLeadNetWorth); true
  else: false

proc setWinnerArbitrary*(w: World) =
  ## `setWinnerArbitrary` uses `Math.random()`, which is wall-clock seeded and
  ## therefore not reproducible. A draw from the WORLD RNG replaces it — a
  ## documented divergence (D3), reachable only when archons, gold net worth AND
  ## lead net worth are all tied (at round 2000, or inside a fury double
  ## elimination).
  w.setWinner((if w.rand.nextDouble() < 0.5: teamA else: teamB), dfCoinFlip)

# ---------------------------------------------------------------------------
#  The actions of rule 3.2, in the engine's own order of definition
# ---------------------------------------------------------------------------

proc noteFirstAction*(w: World, r: Robot, action: int) =
  let t = ord(r.team)
  if w.firstActionSeen[t]: return
  w.firstActionSeen[t] = true
  discard w.beat(BeatFirstAction, "first_action", t, action)

func canMove*(w: World, r: Robot, d: Dir): bool =
  ## `assertCanMove`: movement-ready, the destination is on the map and it is
  ## UNOCCUPIED. Rubble never blocks — it only costs.
  if not r.canMoveCooldown(): return false
  let dest = r.loc + d
  w.onTheMap(dest) and not w.isLocationOccupied(dest)

proc doMove*(w: World, r: Robot, d: Dir): bool {.discardable.} =
  ## `RobotControllerImpl.move`: THE ROBOT MOVES FIRST and the cooldown is
  ## charged AFTERWARDS, at the DESTINATION's rubble. The engine's own comment
  ## says so ("this has to happen after robot's location changed because
  ## rubble").
  if not w.canMove(r, d):
    w.refusedActions += 1
    return false
  let dest = r.loc + d
  w.clearTile(r.loc)
  r.loc = dest
  w.placeRobot(r)
  w.addMovementCooldownTurns(r, RobotSpecs[r.kind].movementCooldown)
  w.noteFirstAction(r, Bc22ActionMove)
  true

func canBuildRobot*(w: World, r: Robot, kind: RobotType, d: Dir): bool =
  if not r.canActCooldown(): return false
  if not canBuildType(r.kind, kind): return false
  if w.teamLead(r.team) < RobotSpecs[kind].buildCostLead: return false
  if w.teamGold(r.team) < RobotSpecs[kind].buildCostGold: return false
  let spawnLoc = r.loc + d
  w.onTheMap(spawnLoc) and not w.isLocationOccupied(spawnLoc)

proc doBuildRobot*(w: World, r: Robot, kind: RobotType,
                   d: Dir): bool {.discardable.} =
  ## `RobotControllerImpl.buildRobot`, in the engine's own order: charge the
  ## BUILDER's action cooldown at its OWN square, deduct both costs, then spawn
  ## at the next `IDGenerator` id.
  if not w.canBuildRobot(r, kind, d):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  w.addLead(r.team, -RobotSpecs[kind].buildCostLead)
  w.addGold(r.team, -RobotSpecs[kind].buildCostGold)
  let id = w.idGen.nextId()
  let spawned = w.spawnRobot(id, kind, r.loc + d, r.team)
  let t = ord(r.team)
  w.stats.unitsBuilt[t] += 1
  case kind
  of rtMiner: w.stats.minersBuilt[t] += 1
  of rtBuilder: w.stats.buildersBuilt[t] += 1
  of rtSoldier: w.stats.soldiersBuilt[t] += 1
  of rtSage:
    w.stats.sagesBuilt[t] += 1
    if not w.firstSageSeen[t]:
      w.firstSageSeen[t] = true
      discard w.beat(BeatFirstSage, "first_sage", t,
                     w.stats.goldTransmuted[t])
  of rtLaboratory:
    w.stats.labsBuilt[t] += 1
    discard w.beat(BeatLabBuilt, "lab_built", t,
                   spawned.loc.x * 100 + spawned.loc.y, 0)
  of rtWatchtower:
    w.stats.watchtowersBuilt[t] += 1
    discard w.beat(BeatWatchtowerBuilt, "watchtower_built", t,
                   spawned.loc.x * 100 + spawned.loc.y, 0)
  of rtArchon: discard
  w.noteFirstAction(r, Bc22ActionBuildRobot)
  true

func canAttack*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanAttack`: in the action radius AND on the map, action-ready, the
  ## type can attack, there IS a robot there and it is on the ENEMY team. NO
  ## VISION TEST.
  if not w.canActLocation(r, l): return false
  if not r.canActCooldown(): return false
  if not canAttackType(r.kind): return false
  let bot = w.getRobot(l)
  bot != nil and bot.team != r.team

proc doAttack*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  if not w.canAttack(r, l):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  let bot = w.getRobot(l)
  let dmg = damageOf(r.kind, r.level)
  let before = bot.health
  w.addHealth(bot, -dmg)
  let after = if bot.alive: bot.health else: 0
  let dealt = max(0, before - after)
  let t = ord(r.team)
  w.stats.damageDealt[t] += dealt
  case r.kind
  of rtSage: w.stats.sageDamage[t] += dealt
  of rtSoldier: w.stats.soldierDamage[t] += dealt
  of rtWatchtower: w.stats.watchtowerDamage[t] += dealt
  else: discard
  w.noteFirstAction(r, Bc22ActionAttack)
  true

func canRepair*(w: World, r: Robot, l: Loc): bool =
  if not w.canActLocation(r, l): return false
  if not r.canActCooldown(): return false
  let bot = w.getRobot(l)
  if bot == nil: return false
  if not canRepairType(r.kind, bot.kind): return false
  bot.team == r.team

proc doRepair*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  ## `RobotControllerImpl.repair`: charge, then `addHealth(+getHealing(level))`.
  ## An archon heals 2/4/6 by level; a builder heals 2 at every level. Fifteen
  ## builder repairs finish a watchtower (120 -> 150) and ten finish a
  ## laboratory (80 -> 100).
  if not w.canRepair(r, l):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  let bot = w.getRobot(l)
  let before = bot.health
  w.addHealth(bot, healingOf(r.kind, r.level))
  let t = ord(r.team)
  w.stats.repairs[t] += 1
  w.stats.hpRepaired[t] += max(0, bot.health - before)
  w.noteFirstAction(r, Bc22ActionRepair)
  true

func canWriteSharedArray*(index, value: int): bool =
  index >= 0 and index < SharedArrayLength and
    value >= 0 and value <= MaxSharedArrayValue

func readSharedArray*(w: World, t: Team, index: int): int =
  if index < 0 or index >= SharedArrayLength: 0
  else: w.stats.sharedArray[ord(t)][index]

proc writeSharedArray*(w: World, r: Robot, index,
                       value: int): bool {.discardable.} =
  ## Rule 3.2.10: ANY ROBOT, ANY TIME, NO COOLDOWN, NO RANGE TEST AND NO COST.
  ## Unlike 2023 there is no amplifier and no write window; the only price is
  ## bytecode, which this port charges as `DecisionOps`.
  if not canWriteSharedArray(index, value):
    w.refusedActions += 1
    return false
  w.stats.sharedArray[ord(r.team)][index] = value
  w.stats.arrayWrites[ord(r.team)] += 1
  w.noteFirstAction(r, Bc22ActionWriteArray)
  true

proc doDisintegrate*(w: World, r: Robot) =
  ## The controller throws `RobotDeathException`; the control provider's
  ## terminated flag makes `updateRobot` destroy the robot at the end of its OWN
  ## turn, not here.
  r.disintegrated = true
  w.noteFirstAction(r, Bc22ActionDisintegrate)

# ---------------------------------------------------------------------------
#  Checksums the hash chain and the parity trace fold
# ---------------------------------------------------------------------------

func fnvArray*(values: openArray[int]): uint64 =
  result = 0xcbf29ce484222325'u64
  for v in values:
    let x = uint64(uint32(v))
    for b in 0 .. 3:
      result = result xor ((x shr (uint64(b) * 8)) and 0xFF'u64)
      result = result * 0x100000001B3'u64

func rubbleChecksum*(w: World): uint64 =
  ## y ascending outer, x ascending inner — i.e. the array's own index order,
  ## which is what changes visibly when a VORTEX permutes it.
  fnvArray(w.rubble)

func leadChecksum*(w: World): uint64 = fnvArray(w.leadAt)
func goldChecksum*(w: World): uint64 = fnvArray(w.goldAt)

func sharedArrayChecksum*(w: World): uint64 =
  var flat: array[128, int]
  for t in 0 .. 1:
    for i in 0 ..< SharedArrayLength:
      flat[t * SharedArrayLength + i] = w.stats.sharedArray[t][i]
  fnvArray(flat)

proc hashOrderChecksum*(w: World): uint64 =
  ## THE `H hashord=` LINE. An FNV-1a 64 fold of the ids in `robotsArray()`
  ## order — the one thing that makes a trove-order bug visible on round 1
  ## instead of on round 400 (D2).
  fnvArray(w.trove.valuesArray())

func totalHealth*(w: World, t: Team): int =
  for _, r in w.robotsById:
    if r.team == t: result += r.health

func buildingLevelSum*(w: World, t: Team): int =
  for _, r in w.robotsById:
    if r.team == t and r.kind.isBuilding(): result += r.level

func modeCount*(w: World, t: Team, m: RobotMode): int =
  for _, r in w.robotsById:
    if r.team == t and r.mode == m: result += 1

func leadOnMap*(w: World): int =
  for v in w.leadAt: result += v

func leadSquares*(w: World): int =
  for v in w.leadAt:
    if v > 0: result += 1

# ---------------------------------------------------------------------------
#  Construction
# ---------------------------------------------------------------------------

proc newWorld*(spec: MapSpec, maxRounds: int): World =
  ## `GameWorld`'s constructor: the rubble and lead arrays come from the map,
  ## the gold array starts empty, the initial bodies are spawned IN THE MAP
  ## FILE'S OWN (id-ascending) ORDER, and then EACH TEAM — not each archon —
  ## is credited `INITIAL_LEAD_AMOUNT` and `INITIAL_GOLD_AMOUNT` once.
  let size = spec.width * spec.height
  result = World(map: spec, width: spec.width, height: spec.height,
                 currentRound: 0, maxRounds: maxRounds, running: true,
                 symmetry: spec.symmetry,
                 rubble: spec.rubble, leadAt: spec.lead,
                 goldAt: newSeq[int](size),
                 occupant: newSeq[Robot](size),
                 robotsById: initTable[int, Robot](),
                 trove: initTroveIntMap(),
                 hashChain: 0xcbf29ce484222325'u64,
                 winner: teamA, domination: dfNone)
  result.idGen = initIdGenerator(spec.randomSeed)
  result.rand = initJavaRandom(spec.randomSeed)
  when defined(bc22BrokenChassis):
    result.brokenChassis = true
  ## `LiveMap`'s constructor SORTS its initial bodies ASCENDING BY ID, and that
  ## order IS the initial `ObjectInfo.dynamicBodyExecOrder`. The converter
  ## already emits them sorted; the sort is repeated here because it is a RULE
  ## and not a property of the file format — and because the official maps
  ## carry archon ids BELOW the 10 000 `IDGenerator` floor, so the order is
  ## what makes A and B alternate in the opening turn order.
  var bodies = spec.initialBodies
  bodies.sort(proc (a, b: tuple[id, x, y, team, kind: int]): int =
                cmp(a.id, b.id))
  for b in bodies:
    let team = if b.team == 1: teamA else: teamB
    ## The map file's `BodyType` ordinals are the SCHEMA's, not `RobotType`'s:
    ## {MINER, BUILDER, SOLDIER, SAGE, ARCHON, LABORATORY, WATCHTOWER}.
    let kind = case b.kind
      of 0: rtMiner
      of 1: rtBuilder
      of 2: rtSoldier
      of 3: rtSage
      of 4: rtArchon
      of 5: rtLaboratory
      else: rtWatchtower
    result.spawnRobot(b.id, kind, loc(b.x, b.y), team)
  result.addLead(teamA, InitialLeadAmount)
  result.addLead(teamB, InitialLeadAmount)
  result.addGold(teamA, InitialGoldAmount)
  result.addGold(teamB, InitialGoldAmount)
  for t in 0 .. 1:
    result.stats.archonsStart[t] = result.archonsAlive[t]
