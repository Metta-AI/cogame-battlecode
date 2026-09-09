## The Battlecode 2016 "Zombie Invasion" world: state, geometry and every
## legality rule a ROBOT can reach.
##
## A behaviour-for-behaviour port of `world/GameWorld.java` (1051 lines),
## `world/InternalRobot.java` (473) and `world/RobotControllerImpl.java` (886)
## at commit `11a0b09f26a70da19f33a61ebec4ceaf6e161aa3`, together with the
## pieces of `common/MapLocation.java` and `common/Direction.java` the rules
## depend on. The port is the authority at run time; the Java engine survives
## only as the `parity-oracle-bc16` CI job (docs/PARITY.md).
##
## `units.nim`, `delays.nim` and `health.nim` are pure and are imported BY this
## file; `zombies.nim`, `economy.nim` and `signals.nim` import it.
##
## **NINE THINGS IN HERE LOOK LIKE DETAILS AND ARE NOT:**
##
## * **The exec order is INSERTION order** and it is the only robot collection
##   the engine ever iterates. `gameObjectsByID` is a `LinkedHashMap`
##   (`GameWorld.java:72`), so `runRound`'s snapshot (`:158`), `allObjects()`
##   (`:239`) — which `senseNearbyRobots` and `senseHostileRobots` read —
##   `getAllGameObjects()` (`:243`) — which rung 3 of the end ladder reads —
##   `getAllRobotsWithinRadiusSq` for `r2 >= 16` (`:400`) and
##   `getNearestPlayerControlled` (`:421`) are all the SAME order: the map
##   file's initial robots in FILE order, then every spawn in spawn order, with
##   removal on death leaving the survivors' relative order intact. THERE IS
##   NO TROVE, NO `net.sf.jsi`, NO `EnumMap` ITERATION AND NO HASH-ORDERED
##   ROBOT SWEEP ANYWHERE IN THE 2016 ROUND LOOP (D2), so this port needs no
##   hash-map port of any kind at run time and keeps one `seq[int]` with
##   append-on-spawn and BY-VALUE removal on death, plus a `Table[int, Robot]`
##   for lookup that is NEVER ITERATED.
## * **`currentRound` starts at -1** (`:69`), so the first round played is
##   round 0 and the last is 2999. Every round number in the trace, the replay
##   and the viewer clock is 0-based, exactly as the engine's is.
## * **Rounds are 0-based AND the outbreak scaling is fixed at spawn.** A
##   robot's `maxHealth` and `attackPower` are computed once, in the
##   constructor, from `currentRound` (`InternalRobot.java:68-70`).
## * **`isActive()` is `!type.isBuildable() || roundsAlive >= buildDelay`**
##   (`:179`) and `getBytecodeLimit()` returns 0 when a robot cannot execute
##   code (`:197`), so a SOLDIER built this round is a live, targetable,
##   blocking, damageable robot that DOES NOTHING for 12 turns. Here it gets a
##   `DecisionOps` budget of 0 and its controller is not run.
## * **An attack needs no vision, no target and no team check.**
##   `attackLocation` tests the radius (and `d2 >= 6` for a TURRET) and
##   nothing else; the signal collects `getAllRobotsWithinRadiusSq(loc, 0)` —
##   SPLASH RADIUS ZERO, so exactly the one robot on that square or none. AN
##   ATTACK ON AN EMPTY SQUARE IS LEGAL AND COSTS FULL DELAY, AND SO IS
##   FRIENDLY FIRE.
## * **`changeHealthLevel` is the single mutation point for health** and it is
##   re-entrant: an attack, a repair, the viper infection tick and the den's
##   proximity damage all come through it, and it calls the death path at
##   `<= 0`.
## * **`DESTROYED` fires MID-TURN** inside the death path and `running` stays
##   true until the end of the round, so every robot after the killer in the
##   exec order still takes its turn. The second `setWinner` is GUARDED by
##   `winner == null` (`:882`), so if both factions lose their last archon in
##   the same round THE FIRST ONE TO LOSE IT LOSES.
## * **An archon takes every part on any square it spawns on or moves onto**,
##   all of it, and nothing else in the game collects parts.
## * **A ZOMBIEDEN skips the pathability test when it builds** (`:702-704`) and
##   its `canBuild` is only `isEmpty(loc)` (`:662-664`), so a den spawns onto
##   rubble no player unit could stand on.

import std/tables
import ../../sim_types, ../../rng
import units, delays, health

export units, delays, health, rng, tables

type
  DenSpec* = object
    ## One den's pre-split share of the public schedule, computed at BUILD
    ## time by `tools/convert_maps_bc16.py` (D3) together with the two
    ## memoised constants `ZombieControlProvider` caches per location.
    x*, y*: int
    spawnDir*: int
    chirality*: int
    schedule*: seq[tuple[round: int, counts: array[4, int]]]

  MapSpec* = object
    ## One converted 2016 `.xml`, as `data/maps/bc16/<name>.json` carries it.
    ## Coordinates are ORIGIN-RELATIVE (V3).
    name*: string
    width*, height*: int
    randomSeed*: int
    rounds*: int
    symmetry*: Symmetry
    symmetriesFound*: seq[Symmetry]
    rubble*: seq[float64]        ## `y * width + x`, as `SquareArray.Double` is
    parts*: seq[float64]
    initialRobots*: seq[tuple[x, y, kind, team: int]]
      ## IN FILE ORDER, because that order IS the opening exec order.
    schedule*: seq[tuple[round: int, counts: array[4, int]]]
      ## The WHOLE-MAP schedule, which `getZombieSpawnSchedule()` exposes free
      ## to every robot of both factions.
    dens*: seq[DenSpec]

  Signal* = object
    ## `common/Signal.java`: a basic signal carries the sender's location, id
    ## and team; a message signal adds two 32-bit ints.
    x*, y*, senderId*: int
    team*: Team
    hasMessage*: bool
    m1*, m2*: int

  Robot* = ref object
    id*: int
    team*: Team
    kind*: RobotType
    loc*: Loc
    health*: float64
    maxHealth*: float64
      ## Fixed at spawn from `type.maxHealth(currentRound)` — outbreak-scaled
      ## for a zombie and never recomputed.
    attackPower*: float64
    d*: Delays
    inf*: Infection
    roundsAlive*: int
    buildDelay*: int
    repairCount*: int
    basicSignalCount*: int
    messageSignalCount*: int
    signalQueue*: seq[Signal]
    denQueue*: array[4, int]
      ## `ZombieControlProvider.denQueues[id]`, by `ZombieSpawnTypes` index.
    denIndex*: int               ## index into `map.dens`, or -1
    alive*: bool
    disintegrated*: bool
    opsLeft*: int
    opsUsed*: int
    ## --- chassis-side memory, never read by a rule ---
    greenhornRng*: JavaRandom
      ## `new java.util.Random(2016)` PER ROBOT: static fields are per robot
      ## under the instrumenter, so `greenhorn` needs no determinism patch.
    noRepeat*: seq[Loc]
    task*: int
    taskLoc*: Loc
    hasTask*: bool
    quarantineUntil*: int

  TeamStats* = object
    ## The per-game counters `results.games[]` reports, plus the two the
    ## engine really keeps (the stockpiles live in `World.resources`).
    ## Everything here is telemetry and is NEVER READ BY A RULE.
    archonsStart*: array[2, int]
    archonsLost*: array[2, int]
    archonHealthEndTenths*: array[2, int]
    partsCollectedTenths*: array[2, int]
    partsIncomeTenths*: array[2, int]
    partsSpentTenths*: array[2, int]
    unitsBuilt*: array[2, int]
    scoutsBuilt*: array[2, int]
    soldiersBuilt*: array[2, int]
    guardsBuilt*: array[2, int]
    vipersBuilt*: array[2, int]
    turretsBuilt*: array[2, int]
    turretPacks*: array[2, int]
    robotsLost*: array[2, int]
    robotsTurned*: array[2, int]
    neutralsActivated*: array[2, int]
    neutralArchonsActivated*: array[2, int]
    densDestroyed*: array[2, int]
    denDamageDealt*: array[2, int]
    damageDealt*: array[2, int]
    zombieDamageDealt*: array[2, int]
    zombieDamageTaken*: array[2, int]
    enemyDamageDealt*: array[2, int]
    enemyDamageTaken*: array[2, int]
    infectionsSuffered*: array[2, int]
    infectionsInflicted*: array[2, int]
    viperInfectionDamage*: array[2, int]
    repairs*: array[2, int]
    hpRepaired*: array[2, int]
    rubbleClearedTenths*: array[2, int]
    rubbleCreatedTenths*: array[2, int]
    squaresOpened*: array[2, int]
    basicSignals*: array[2, int]
    messageSignals*: array[2, int]
    archonPartsWalks*: array[2, int]
    archonsAliveAt2000*: array[2, int]
    ## --- globals ---
    zombiesSpawned*: int
    zombiesKilled*: int

  World* = ref object
    map*: MapSpec
    width*, height*: int
    currentRound*: int
    maxRounds*: int
    running*: bool
    idGen*: IdGenerator
      ## D2a — `IDGenerator(mapSeed)`, whose 4096-id blocks START AT ID 1 in
      ## 2016 (`nextIDBlock = 0`, `reservedIDs[i] = nextIDBlock + i + 1`),
      ## unlike every later year's 10 000 floor. It fixes the id of EVERY
      ## robot including the initial ones.
    rand*: JavaRandom
      ## D2b — `GameWorld.rand = new Random(mapSeed)` (`:134`), read at
      ## EXACTLY ONE SITE: `getNearestPlayerControlled`'s
      ## `rand.nextInt(closest.size())`, ONCE PER ZOMBIE TURN in which any
      ## player robot is alive, INCLUDING when there is exactly one candidate
      ## (`nextInt(1)` still consumes a `next(31)`). The highest-traffic RNG
      ## stream in any year this repo ships.
    zombieRand*: JavaRandom
      ## D2c — `ZombieControlProvider.random = new Random(mapSeed)` (`:84`),
      ## read at exactly two sites in `processZombie`.
    symmetry*: Symmetry
    rubble*: seq[float64]
    partsAt*: seq[float64]
    occupant*: seq[Robot]
    robotsById*: Table[int, Robot]
    execOrder*: seq[int]
      ## INSERTION ORDER (D2). Never sorted, never re-ordered.
    typeCount*: array[4, array[RobotType, int]]
    robotCount*: array[4, int]
    resources*: array[4, float64]
    winner*: Team
    hasWinner*: bool
    domination*: Domination
    tiebreakRung*: int
    stats*: TeamStats
    ## Replay/telemetry sinks — never read by a rule.
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    hashChain*: uint64
    beatCount*: array[24, int]
    refusedActions*: int
      ## THE LEGALITY AUDIT. Every `do*` re-checks its own `can*` and no-ops
      ## when it fails; this counts those no-ops.
      ## `tests/test_bc16_baselines.nim` plays whole games and asserts it
      ## stays ZERO for both chassis.
    opsUsedPeak*: int
    firstActionSeen*: array[2, bool]
    unitMilestoneSeen*: array[2, array[RobotType, bool]]
    lostThisRound*: array[2, int]
    attackersLostThisRound*: array[2, int]
    turnedThisRound*: seq[tuple[team: int, kind, became: RobotType, l: Loc]]
    archonLostThisRound*: seq[tuple[team: int, cause: string]]
    lastDamageSource*: array[4, string]
    brokenChassis*: bool
      ## Set by `-d:bc16BrokenChassis`: the NEGATIVE CONTROL for the
      ## economic-survival gate. Archons never build a GUARD and never repair,
      ## units ignore `infection_policy` entirely, and the faction never
      ## commits to a den.

# ---------------------------------------------------------------------------
#  Beats and events
# ---------------------------------------------------------------------------

const
  BeatEpisode* = 0
  BeatGameStart* = 1
  BeatFirstAction* = 2
  BeatUnitMilestone* = 3
  BeatZombieWave* = 4
  BeatOutbreak* = 5
  BeatDenDestroyed* = 6
  BeatNeutralActivated* = 7
  BeatInfection* = 8
  BeatTurned* = 9
  BeatArchonLost* = 10
  BeatRout* = 11
  BeatDuel* = 12
  BeatTiebreak* = 13
  BeatGameEnd* = 14

  BeatBounds* = [1, 1, 2, 10, 30, 10, 12, 20, 20, 24, 8, 20, 20, 1, 2,
                 0, 0, 0, 0, 0, 0, 0, 0, 0]
    ## Per GAME, in the design note's own event table.
    ## `tests/test_bc16_replay.nim` asserts every one of them against a real
    ## match, so a pathological game cannot produce a 20 MB replay.
    ## `zombie_wave` is 30 against a MEASURED maximum schedule length of 29
    ## (`wormy`).

  Bc16ActionClearRubble* = 0
  Bc16ActionMove* = 1
  Bc16ActionAttack* = 2
  Bc16ActionBroadcast* = 3
  Bc16ActionBroadcastMessage* = 4
  Bc16ActionBuild* = 5
  Bc16ActionActivate* = 6
  Bc16ActionRepair* = 7
  Bc16ActionPack* = 8
  Bc16ActionUnpack* = 9
  Bc16ActionDisintegrate* = 10
    ## The ordinals `years/dispatch.nim`'s `Bc16ActionNames` spells out, so
    ## `first_action.action` has a DOCUMENTED VOCABULARY (the bc23 r1-F14
    ## lesson). The field is `action`, never `kind`: a field named `kind` is
    ## flattened into the same object as the event's own `kind` key and
    ## silently overwrites it (the bc23 r1-F25 finding).

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
  w.hashChain = (w.hashChain xor (v and 0xFFFFFFFF'u64)) *
    0x100000001B3'u64

func fnv1a64*(values: openArray[int]): uint64 =
  result = 0xcbf29ce484222325'u64
  for v in values:
    result = (result xor uint64(v and 0xFFFFFFFF)) * 0x100000001B3'u64

# ---------------------------------------------------------------------------
#  Geometry
# ---------------------------------------------------------------------------

func idx*(w: World, l: Loc): int = l.x + l.y * w.width
func indexToLoc*(w: World, i: int): Loc = loc(i mod w.width, i div w.width)

func onTheMap*(w: World, l: Loc): bool =
  ## `GameMap.onTheMap`, with the origin subtracted (V3).
  l.x >= 0 and l.y >= 0 and l.x < w.width and l.y < w.height

iterator locationsWithinRadiusSquared*(w: World, center: Loc,
                                       r2: int): Loc =
  ## `MapLocation.getAllMapLocationsWithinRadiusSq` /
  ## `GameWorld.getAllMapLocationsWithinRadiusSq`, verbatim: the box is
  ## `(int) Math.sqrt(r2)` wide, X ASCENDING OUTER and Y ASCENDING INNER, and
  ## a square passes when `d2 <= r2`. That order fixes which parts square a
  ## chassis sees first.
  let radius = intSqrt(r2)
  for x in center.x - radius .. center.x + radius:
    for y in center.y - radius .. center.y + radius:
      let l = loc(x, y)
      if w.onTheMap(l) and l.distanceSquaredTo(center) <= r2:
        yield l

func symmetricLoc*(w: World, l: Loc): Loc =
  ## `Symmetry.getOpposite` at zero origin.
  case w.symmetry
  of symVertical: loc(l.x, w.height - 1 - l.y)
  of symHorizontal: loc(w.width - 1 - l.x, l.y)
  of symRotational: loc(w.width - 1 - l.x, w.height - 1 - l.y)
  of symNegativeDiagonal: loc(w.height - 1 - l.y, w.width - 1 - l.x)
  of symPositiveDiagonal: loc(l.y, l.x)
  of symNone: l

# ---------------------------------------------------------------------------
#  Terrain, occupancy and lookup
# ---------------------------------------------------------------------------

func getRubble*(w: World, l: Loc): float64 =
  ## `GameWorld.getRubble` returns 0 off the map.
  if w.onTheMap(l): w.rubble[w.idx(l)] else: 0.0

proc alterRubble*(w: World, l: Loc, amount: float64) =
  ## `GameWorld.alterRubble`: `max(0.0, amount)`, and the caller passes the
  ## whole new value.
  if w.onTheMap(l):
    w.rubble[w.idx(l)] = max(0.0, amount)

func getParts*(w: World, l: Loc): float64 =
  if w.onTheMap(l): w.partsAt[w.idx(l)] else: 0.0

func getRobot*(w: World, l: Loc): Robot =
  if w.onTheMap(l): w.occupant[w.idx(l)] else: nil

func isLocationOccupied*(w: World, l: Loc): bool = w.getRobot(l) != nil

func isEmpty*(w: World, l: Loc): bool =
  ## `GameWorld.isEmpty`: on the map AND unoccupied. Rubble is not consulted —
  ## which is exactly what lets a den spawn onto a wall.
  w.onTheMap(l) and w.getRobot(l) == nil

func robotById*(w: World, id: int): Robot =
  if w.robotsById.hasKey(id): w.robotsById[id] else: nil

func existsRobot*(w: World, id: int): bool = w.robotsById.hasKey(id)

func robotTypeCount*(w: World, t: Team, k: RobotType): int =
  w.typeCount[ord(t)][k]

func robotCountOf*(w: World, t: Team): int = w.robotCount[ord(t)]

func archonsAlive*(w: World, t: Team): int = w.typeCount[ord(t)][rtArchon]

func teamParts*(w: World, t: Team): float64 = w.resources[ord(t)]

proc adjustResources*(w: World, t: Team, amount: float64) =
  ## `GameWorld.adjustResources`. The engine clamps NOTHING; a spend that
  ## would take a stockpile negative is a legality bug in the caller, so it
  ## raises here and the server turns it into `results.reason = fault`.
  if w.resources[ord(t)] + amount < 0.0:
    raise newException(BattlecodeError, "bc16: invalid parts change")
  w.resources[ord(t)] += amount

func isActive*(r: Robot): bool =
  ## `InternalRobot.isActive`.
  (not isBuildable(r.kind)) or r.roundsAlive >= r.buildDelay

func canExecuteCode*(r: Robot): bool = r.health > 0.0 and r.isActive()

func canSense*(w: World, r: Robot, l: Loc): bool =
  ## `InternalRobot.canSense`: `sensorRadiusSquared == -1` means the WHOLE
  ## MAP — every zombie and every den, always.
  let s = r.kind.sightRadiusSquared()
  if s == -1: true
  else: r.loc.distanceSquaredTo(l) <= s

func canAttackSquare*(w: World, r: Robot, l: Loc): bool =
  ## `GameWorld.canAttackSquare`: inside the attack radius, and for a TURRET
  ## ALSO at or beyond `TURRET_MINIMUM_RANGE = 6`. NO on-the-map test and NO
  ## vision test.
  let d = r.loc.distanceSquaredTo(l)
  let radius = r.kind.attackRadiusSquared()
  if r.kind == rtTurret:
    d <= radius and d >= TurretMinimumRange
  else:
    d <= radius

func canMoveTo*(w: World, l: Loc, k: RobotType): bool =
  ## `GameWorld.canMove(loc, type)`: on the map, rubble under 100 unless the
  ## type ignores rubble, and UNOCCUPIED.
  w.onTheMap(l) and (not rubbleBlocks(w.getRubble(l), k)) and
    w.getRobot(l) == nil

# ---------------------------------------------------------------------------
#  DecisionOps — the budget that replaces the JVM bytecode limit (V2)
# ---------------------------------------------------------------------------

proc spend*(r: Robot, n: int): bool {.discardable.} =
  ## Charged BEFORE each primitive and never inside one, so a primitive's
  ## RESULT is never a function of the remaining budget — only whether the
  ## chassis got to ask. When the budget runs out the robot's turn ends where
  ## it stands; it is not resumed mid-computation next turn, which is the one
  ## place this differs from the JVM. NO RULE READS IT (V1).
  if r.opsLeft < n: return false
  r.opsLeft -= n
  r.opsUsed += n
  true

# ---------------------------------------------------------------------------
#  Sensing — every one of these walks the INSERTION-ORDERED exec list
# ---------------------------------------------------------------------------

iterator allRobots*(w: World): Robot =
  ## `allObjects()` / `getAllGameObjects()`: `gameObjectsByID.values()` in
  ## LinkedHashMap insertion order.
  for id in w.execOrder:
    if w.robotsById.hasKey(id):
      yield w.robotsById[id]

iterator senseNearbyRobots*(w: World, r: Robot, r2: int): Robot =
  ## `senseNearbyRobots(center, radiusSquared, team)` with a null team: walk
  ## `allObjects()`, keep what this robot CAN SENSE, drop itself, apply the
  ## radius when `radiusSquared >= 0`. RETURNS IN INSERTION ORDER, which is
  ## what fixes which enemy a chassis sees first.
  let useRadius = r2 >= 0
  for id in w.execOrder:
    if not w.robotsById.hasKey(id): continue
    let o = w.robotsById[id]
    if o.id == r.id: continue
    if not w.canSense(r, o.loc): continue
    if useRadius and o.loc.distanceSquaredTo(r.loc) > r2: continue
    yield o

iterator senseHostileRobots*(w: World, r: Robot, r2: int): Robot =
  ## `senseHostileRobots`: the same walk, keeping the ENEMY TEAM **and**
  ## `Team.ZOMBIE`.
  let useRadius = r2 >= 0
  let enemy = r.team.opponent()
  for id in w.execOrder:
    if not w.robotsById.hasKey(id): continue
    let o = w.robotsById[id]
    if o.id == r.id: continue
    if not w.canSense(r, o.loc): continue
    if useRadius and o.loc.distanceSquaredTo(r.loc) > r2: continue
    if o.team == enemy or o.team == teamZombie:
      yield o

func senseRubble*(w: World, r: Robot, l: Loc): float64 =
  ## `senseRubble` returns **-1** out of range rather than throwing.
  if w.canSense(r, l): w.getRubble(l) else: -1.0

func senseParts*(w: World, r: Robot, l: Loc): float64 =
  if w.canSense(r, l): w.getParts(l) else: -1.0

func initialArchonLocations*(w: World, t: Team): seq[Loc] =
  ## `getInitialArchonLocations(t)`, sorted by `MapLocation.compareTo` and
  ## PUBLIC FROM ROUND 0 to every robot of either faction.
  for b in w.map.initialRobots:
    if b.kind == ord(rtArchon) and b.team == ord(t):
      result.add(loc(b.x, b.y))
  ## Insertion sort on the engine's own comparator — the roster is at most 4
  ## entries a side.
  for i in 1 ..< result.len:
    let v = result[i]
    var j = i - 1
    while j >= 0 and compareLoc(result[j], v) > 0:
      result[j + 1] = result[j]
      dec j
    result[j + 1] = v

proc getNearestPlayerControlled*(w: World, l: Loc): Robot =
  ## `GameWorld.getNearestPlayerControlled` (`:418-440`), and D2b lives here.
  ##
  ## Walk `gameObjectsByID.values()` in INSERTION ORDER, keep only
  ## `team.isPlayer()` (A or B — never NEUTRAL, never ZOMBIE), track the
  ## minimum `d2`, COLLECT EVERY LOCATION AT THAT MINIMUM, then return the
  ## robot at `closest.get(rand.nextInt(closest.size()))`. THE DRAW HAPPENS ON
  ## EVERY CALL, including when there is exactly one candidate, because
  ## `java.util.Random.nextInt(1)` still consumes a `next(31)`. Getting that
  ## condition wrong by one draw desynchronises the whole game.
  var distSq = high(int)
  var closest: seq[Loc]
  for id in w.execOrder:
    if not w.robotsById.hasKey(id): continue
    let robot = w.robotsById[id]
    if not robot.team.isPlayer(): continue
    let newDistSq = robot.loc.distanceSquaredTo(l)
    if newDistSq < distSq:
      closest = @[robot.loc]
      distSq = newDistSq
    elif newDistSq == distSq:
      closest.add(robot.loc)
  if closest.len == 0:
    return nil
  let pick = int(w.rand.nextInt(closest.len))
  w.getRobot(closest[pick])

# ---------------------------------------------------------------------------
#  Spawning, death and the ONE health mutation point
# ---------------------------------------------------------------------------

proc placeRobot(w: World, r: Robot) = w.occupant[w.idx(r.loc)] = r
proc clearTile(w: World, l: Loc) = w.occupant[w.idx(l)] = nil

proc denSpecIndexAt(w: World, l: Loc): int =
  result = -1
  for i in 0 ..< w.map.dens.len:
    if w.map.dens[i].x == l.x and w.map.dens[i].y == l.y:
      return i

proc setWinner*(w: World, t: Team, d: Domination) =
  ## `GameWorld.setWinner`. `running` is NOT cleared here — the engine's own
  ## line is commented out — so the round plays out.
  w.winner = t
  w.hasWinner = true
  w.domination = d

proc takePartsAt*(w: World, r: Robot): float64 {.discardable.} =
  ## `GameWorld.takeParts`: zero the square and credit the WHOLE amount to
  ## the archon's team. Called from exactly two places — an archon SPAWNING on
  ## a parts square and an archon MOVING onto one — and for no other type.
  if not w.onTheMap(r.loc): return 0.0
  let before = w.partsAt[w.idx(r.loc)]
  w.partsAt[w.idx(r.loc)] = 0.0
  if before > 0.0:
    w.adjustResources(r.team, before)
    if r.team.isPlayer():
      w.stats.partsCollectedTenths[ord(r.team)] += int(before * 10.0)
      w.stats.archonPartsWalks[ord(r.team)] += 1
  before

proc spawnRobot*(w: World, kind: RobotType, l: Loc, t: Team,
                 buildDelay: int): Robot {.discardable.} =
  ## `GameWorld.spawnRobot` -> `visitSpawnSignal` -> `InternalRobot`'s
  ## constructor, in the engine's own order: take the next id, build the
  ## robot at `type.maxHealth(currentRound)` with BOTH DELAYS AT ZERO and
  ## `roundsAlive = 0`, bump the counts, append to the insertion order, place
  ## it, and — for a PLAYER archon only — take the parts on the square.
  let id = w.idGen.nextId()
  var r = Robot(id: id, team: t, kind: kind, loc: l,
                maxHealth: maxHealthOf(kind, w.currentRound),
                attackPower: attackPowerOf(kind, w.currentRound),
                d: initDelays(), roundsAlive: 0, buildDelay: buildDelay,
                alive: true, denIndex: -1,
                opsLeft: budgetFor(kind), taskLoc: loc(-1, -1))
  r.health = r.maxHealth
  r.greenhornRng = initJavaRandom(2016)
  if kind == rtZombieden:
    r.denIndex = w.denSpecIndexAt(l)
  w.robotsById[id] = r
  w.execOrder.add(id)
  w.typeCount[ord(t)][kind] += 1
  w.robotCount[ord(t)] += 1
  w.placeRobot(r)
  if kind == rtArchon and t.isPlayer():
    w.takePartsAt(r)
  if t == teamZombie and kind != rtZombieden:
    w.stats.zombiesSpawned += 1
  r

proc visitDeathSignal*(w: World, r: Robot, cause: DeathCause,
                       killer: Team = teamNeutral) =
  ## `GameWorld.visitDeathSignal` (`:857-903`), in exactly this order:
  ##   (0) return immediately if `!running` — after the game ends deaths stop
  ##       being processed;
  ##   (a) decrement the type and robot counts, then: a PLAYER ARCHON whose
  ##       team now has ZERO archons and no winner set -> `setWinner(opponent,
  ##       DESTROYED)`, MID-TURN, with `running` still true;
  ##   (b) unless the cause is ACTIVATION and unless the robot is infected ->
  ##       `rubble += rubbleFactor * maxHealth`;
  ##   (c) remove from the id map, the exec order (BY VALUE) and the location
  ##       index;
  ##   (d) if the robot WAS infected and the cause is not ACTIVATION -> spawn
  ##       `turnsInto` on `Team.ZOMBIE` at the same square with
  ##       `maxHealth(currentRound)` — i.e. OUTBREAK-SCALED AT THE ROUND IT
  ##       TURNS, not the round it was built.
  if not w.running: return
  if not w.robotsById.hasKey(r.id): return
  let t = r.team
  let kind = r.kind
  let l = r.loc

  w.typeCount[ord(t)][kind] -= 1
  w.robotCount[ord(t)] -= 1

  if kind == rtArchon and t.isPlayer():
    if w.typeCount[ord(t)][rtArchon] == 0 and not w.hasWinner:
      w.setWinner(t.opponent(), dfDestroyed)

  let consequence = deathConsequence(kind, r.maxHealth, cause, r.inf.isInfected())
  if consequence.rubbleAdded > 0.0:
    w.alterRubble(l, w.getRubble(l) + consequence.rubbleAdded)
    if t.isPlayer():
      w.stats.rubbleCreatedTenths[ord(t)] += int(consequence.rubbleAdded * 10.0)

  for k in 0 ..< w.execOrder.len:
    if w.execOrder[k] == r.id:
      w.execOrder.delete(k)
      break
  w.robotsById.del(r.id)
  if w.getRobot(l) == r:
    w.clearTile(l)
  r.alive = false

  if t.isPlayer():
    w.stats.robotsLost[ord(t)] += 1
    w.lostThisRound[ord(t)] += 1
    if canAttack(kind): w.attackersLostThisRound[ord(t)] += 1
    if kind == rtArchon:
      w.stats.archonsLost[ord(t)] += 1
      w.archonLostThisRound.add((team: ord(t),
                                 cause: w.lastDamageSource[ord(t)]))
  elif t == teamZombie and kind != rtZombieden:
    w.stats.zombiesKilled += 1

  if consequence.becomesZombie:
    w.spawnRobot(consequence.zombieType, l, teamZombie, 0)
    if t.isPlayer():
      w.stats.robotsTurned[ord(t)] += 1
      w.turnedThisRound.add((team: ord(t), kind: kind,
                             became: consequence.zombieType, l: l))

proc changeHealthLevel*(w: World, r: Robot, amount: float64,
                        source: DeathCause = dcNormal) =
  ## `InternalRobot.changeHealthLevel` (`:278-293`) — THE SINGLE MUTATION
  ## POINT FOR HEALTH, and re-entrant: an attack, a repair, the viper
  ## infection tick and the den's proximity damage all come through here.
  ## Cap at `maxHealth`, then destroy at `<= 0` with the TURRET flag carried
  ## through to the rubble factor.
  if not r.alive: return
  r.health += amount
  r.health = cappedHealth(r.health, r.maxHealth)
  if isDead(r.health):
    w.visitDeathSignal(r, source)

proc takeDamage*(w: World, r: Robot, amount: float64,
                 attacker: RobotType, isTyped = true) =
  ## `InternalRobot.takeDamage(baseAmount, attackerType)`. The death cause is
  ## TURRET only when a TURRET landed the killing blow; every other attacker
  ## and the untyped `takeDamage(double)` (the den's proximity damage and the
  ## viper tick) pass `null`, which is the normal cause.
  let cause = if isTyped and attacker == rtTurret: dcTurret else: dcNormal
  w.changeHealthLevel(r, -amount, cause)

# ---------------------------------------------------------------------------
#  The actions of rule 3.2, in the engine's own order of definition
# ---------------------------------------------------------------------------

proc noteFirstAction*(w: World, r: Robot, action: int) =
  if not r.team.isPlayer(): return
  let t = ord(r.team)
  if w.firstActionSeen[t]: return
  w.firstActionSeen[t] = true
  discard w.beat(BeatFirstAction, "first_action", t, action)

func canClearRubble*(w: World, r: Robot, d: Dir): bool =
  ## `clearRubble`'s own assertions: core ready, the type can clear (NOT a
  ## TURRET, NOT a TTM), the direction is not OMNI/NONE, and the target is on
  ## the map. A square at EXACTLY 0 rubble returns silently and COSTS NOTHING,
  ## which is a legal call and not a refusal — `doClearRubble` reproduces that
  ## rather than counting it as an illegal order.
  if not r.d.isCoreReady(): return false
  if not canClearRubble(r.kind): return false
  if d == dOmni or d == dNone: return false
  w.onTheMap(r.loc + d)

proc doClearRubble*(w: World, r: Robot, d: Dir): bool {.discardable.} =
  if not w.canClearRubble(r, d):
    w.refusedActions += 1
    return false
  let target = r.loc + d
  let before = w.getRubble(target)
  if before == 0.0:
    ## `RobotControllerImpl.clearRubble:459-461` — returns before charging.
    return true
  w.alterRubble(target, rubbleAfterClear(before))
  let after = w.getRubble(target)
  if r.team.isPlayer():
    w.stats.rubbleClearedTenths[ord(r.team)] += int((before - after) * 10.0)
    if before >= RubbleObstructionThresh and after < RubbleObstructionThresh:
      w.stats.squaresOpened[ord(r.team)] += 1
  r.d.activateCoreAction(RobotSpecs[r.kind].cooldownDelay,
                         RobotSpecs[r.kind].movementDelay)
  w.noteFirstAction(r, Bc16ActionClearRubble)
  true

func canMove*(w: World, r: Robot, d: Dir): bool =
  ## `RobotControllerImpl.canMove`: the type can move (NOT a ZOMBIEDEN, NOT a
  ## TURRET), the direction is a real one, and the destination is pathable.
  ## NOTE: `canMove` does NOT test core readiness — `move()` asserts it
  ## separately, and the zombie AI calls `canMove` after its own readiness
  ## check, so the two are kept apart here exactly as the engine keeps them.
  if not canMoveType(r.kind): return false
  if d == dOmni or d == dNone: return false
  w.canMoveTo(r.loc + d, r.kind)

proc doMove*(w: World, r: Robot, d: Dir): bool {.discardable.} =
  ## `RobotControllerImpl.move`: core-ready, movable, valid direction,
  ## pathable; then `factor1` (diagonal, 1.4) and `factor3` (destination
  ## rubble >= 50 and the mover does not ignore rubble, 2.0); the robot moves
  ## and, IF IT IS AN ARCHON, takes every part on the destination; then
  ## `setWeaponDelayUpTo(cooldownDelay * factor3)` and
  ## `coreDelay += movementDelay * factor1 * factor3`.
  ##
  ## THE DIAGONAL MULTIPLIER HITS THE CORE DELAY ONLY: a soldier stepping
  ## diagonally onto rubble 60 pays core 5.6 and weapon 2.0.
  if not r.d.isCoreReady() or not w.canMove(r, d):
    w.refusedActions += 1
    return false
  let dest = r.loc + d
  let factor1 = moveFactor1(d)
  let factor3 = moveFactor3(w.getRubble(dest), r.kind)
  w.clearTile(r.loc)
  r.loc = dest
  w.placeRobot(r)
  if r.kind == rtArchon and r.team.isPlayer():
    w.takePartsAt(r)
  r.d.setWeaponDelayUpTo(RobotSpecs[r.kind].cooldownDelay * factor3)
  r.d.addCoreDelay(RobotSpecs[r.kind].movementDelay * factor1 * factor3)
  w.noteFirstAction(r, Bc16ActionMove)
  true

func canAttackLocation*(w: World, r: Robot, l: Loc): bool =
  ## `canAttackLocation`: the type can attack and the square is inside the
  ## radius (and outside r2 6 for a TURRET). NO readiness test, NO vision
  ## test, NO on-the-map test and NO target test — all four absences are the
  ## engine's.
  canAttack(r.kind) and w.canAttackSquare(r, l)

proc doAttack*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  ## `attackLocation` -> `visitAttackSignal` FIRST, then
  ## `activateAttack(attackDelay, cooldownDelay)`.
  ##
  ## The signal collects `getAllRobotsWithinRadiusSq(loc, 0)` — SPLASH RADIUS
  ## ZERO — so exactly the one robot on that square or none, and then:
  ## GUARD attacker vs zombie -> `rate = 2.0`; attacker `canInfect()` and
  ## target `isInfectable()` -> INFECTED; `damage = attackPower * rate`, and a
  ## GUARD target hit for more than 10.0 takes `damage - 4.0`; a ZOMBIEDEN
  ## brought to `<= 0` pays the attacker's team 200 parts.
  if not r.d.isWeaponReady() or not w.canAttackLocation(r, l):
    w.refusedActions += 1
    return false
  let target = w.getRobot(l)
  if target != nil:
    let rate = guardRate(r.kind, target.kind)
    if canInfect(r.kind) and isInfectable(target.kind):
      ## The engine re-sets the counter on EVERY hit; the telemetry counts a
      ## NEW infection only, so `infections_suffered` is a count of units
      ## infected and not of bites landed.
      let wasInfected = target.inf.isInfected()
      target.inf.setInfected(r.kind)
      if not wasInfected:
        if target.team.isPlayer():
          w.stats.infectionsSuffered[ord(target.team)] += 1
        if r.team.isPlayer():
          w.stats.infectionsInflicted[ord(r.team)] += 1
        if target.team.isPlayer():
          discard w.beat(BeatInfection, "infection", ord(target.team),
                         ord(target.kind),
                         (if r.kind == rtViper: 0 else: 1),
                         $target.inf.infectedTurns())
    let raw = r.attackPower * rate
    let dealt = damageToTarget(raw, target.kind)
    let before = target.health
    if target.team.isPlayer():
      w.lastDamageSource[ord(target.team)] =
        (if r.team == teamZombie: (if r.kind == rtZombieden: "den_proximity"
                                   else: "zombie")
         else: "enemy")
    w.takeDamage(target, dealt, r.kind)
    let after = if target.alive: target.health else: 0.0
    let done = max(0.0, before - after)
    if r.team.isPlayer():
      let t = ord(r.team)
      w.stats.damageDealt[t] += int(done)
      if target.team == teamZombie:
        w.stats.zombieDamageDealt[t] += int(done)
        if target.kind == rtZombieden:
          w.stats.denDamageDealt[t] += int(done)
      elif target.team.isPlayer() and target.team != r.team:
        w.stats.enemyDamageDealt[t] += int(done)
    if target.team.isPlayer():
      let t = ord(target.team)
      if r.team == teamZombie: w.stats.zombieDamageTaken[t] += int(done)
      elif r.team.isPlayer() and r.team != target.team:
        w.stats.enemyDamageTaken[t] += int(done)
    ## The den bounty: `target.getHealthLevel() <= 0.0` AFTER the damage.
    if target.kind == rtZombieden and target.health <= 0.0:
      w.adjustResources(r.team, DenPartReward)
      if r.team.isPlayer():
        w.stats.densDestroyed[ord(r.team)] += 1
        var densLeft = 0
        for team in [teamZombie]:
          densLeft += w.robotTypeCount(team, rtZombieden)
        var queueDeleted = 0
        if target.denIndex >= 0:
          for row in w.map.dens[target.denIndex].schedule:
            if row.round > w.currentRound:
              for c in row.counts: queueDeleted += c
        discard w.beat(BeatDenDestroyed, "den_destroyed", ord(r.team),
                       l.x * 100 + l.y, densLeft,
                       $int(DenPartReward) & ":" & $queueDeleted)
  r.d.activateAttack(RobotSpecs[r.kind].attackDelay,
                     RobotSpecs[r.kind].cooldownDelay)
  w.noteFirstAction(r, Bc16ActionAttack)
  true

func canBuild*(w: World, r: Robot, d: Dir, kind: RobotType): bool =
  ## `RobotControllerImpl.canBuild`: for a ZOMBIEDEN it is ONLY
  ## `isEmpty(loc)`; for an ARCHON it is pathability for the NEW type plus the
  ## build requirements (the builder can build, the type is buildable, the
  ## team can afford it, and `spawnSource == builder type`).
  let l = r.loc + d
  if d == dOmni or d == dNone: return false
  if r.kind == rtZombieden:
    return w.isEmpty(l)
  if not canBuildType(r.kind): return false
  if not isBuildable(kind): return false
  if RobotSpecs[kind].spawnSource != ord(r.kind): return false
  if float64(kind.partCost()) > w.teamParts(r.team): return false
  w.canMoveTo(l, kind)

proc doBuild*(w: World, r: Robot, d: Dir, kind: RobotType): bool
    {.discardable.} =
  ## `build` -> `visitBuildSignal` (deduct `partCost`, spawn with
  ## `buildDelay = buildTurns`) and THEN
  ## `activateCoreAction(buildTurns, buildTurns)` — so an archon building a
  ## VIPER is frozen 30 of its own turns.
  if not r.d.isCoreReady() or not w.canBuild(r, d, kind):
    w.refusedActions += 1
    return false
  let l = r.loc + d
  let delay = kind.buildTurns()
  w.adjustResources(r.team, -float64(kind.partCost()))
  if r.team.isPlayer():
    w.stats.partsSpentTenths[ord(r.team)] += kind.partCost() * 10
  let spawned = w.spawnRobot(kind, l, r.team, delay)
  if r.team.isPlayer():
    let t = ord(r.team)
    if r.kind == rtArchon:
      w.stats.unitsBuilt[t] += 1
      case kind
      of rtScout: w.stats.scoutsBuilt[t] += 1
      of rtSoldier: w.stats.soldiersBuilt[t] += 1
      of rtGuard: w.stats.guardsBuilt[t] += 1
      of rtViper: w.stats.vipersBuilt[t] += 1
      of rtTurret: w.stats.turretsBuilt[t] += 1
      else: discard
      if not w.unitMilestoneSeen[t][kind]:
        w.unitMilestoneSeen[t][kind] = true
        discard w.beat(BeatUnitMilestone, "unit_milestone", t, ord(kind),
                       w.robotTypeCount(r.team, kind))
  r.d.activateCoreAction(float64(delay), float64(delay))
  w.noteFirstAction(r, Bc16ActionBuild)
  discard spawned
  true

func canActivate*(w: World, r: Robot, l: Loc): bool =
  ## `activate`: ARCHON only, `d2 <= ARCHON_ACTIVATION_RANGE = 2`, a robot is
  ## there, its team is NEUTRAL, and the core is ready.
  if r.kind != rtArchon: return false
  if r.loc.distanceSquaredTo(l) > ArchonActivationRange: return false
  let target = w.getRobot(l)
  if target == nil: return false
  if target.team != teamNeutral: return false
  r.d.isCoreReady()

proc doActivate*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  ## `visitActivationSignal`: kill the neutral with cause ACTIVATION — which
  ## skips BOTH the rubble deposit and the infection conversion — and spawn
  ## the SAME TYPE on the activator's team with `buildDelay 0`, immediately
  ## active. Cost: `setWeaponDelayUpTo(0)` and `coreDelay += movementDelay`
  ## (an archon's 2).
  if not w.canActivate(r, l):
    w.refusedActions += 1
    return false
  let target = w.getRobot(l)
  let kind = target.kind
  w.visitDeathSignal(target, dcActivation)
  w.spawnRobot(kind, l, r.team, 0)
  if r.team.isPlayer():
    let t = ord(r.team)
    w.stats.neutralsActivated[t] += 1
    if kind == rtArchon: w.stats.neutralArchonsActivated[t] += 1
    discard w.beat(BeatNeutralActivated, "neutral_activated", t, ord(kind),
                   l.x * 100 + l.y, $w.stats.neutralsActivated[t])
  r.d.activateCoreAction(0.0, RobotSpecs[r.kind].movementDelay)
  w.noteFirstAction(r, Bc16ActionActivate)
  true

func canRepair*(w: World, r: Robot, l: Loc): bool =
  ## `repair`: ARCHON only; `canAttackSquare(self, loc)`, i.e. r2 <= 24; a
  ## robot is there; it is on YOUR team; it is NOT an ARCHON; and
  ## `repairCount < 1`. NO READINESS TEST OF EITHER KIND.
  if r.kind != rtArchon: return false
  if not w.canAttackSquare(r, l): return false
  let target = w.getRobot(l)
  if target == nil: return false
  if target.team != r.team: return false
  if target.kind == rtArchon: return false
  r.repairCount < 1

proc doRepair*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  ## `InternalRobot.repair`: `repairCount++` and `changeHealthLevel(+1.0,
  ## ARCHON)`. COSTS NO DELAY OF EITHER KIND — it never goes through
  ## `activateCoreAction` — and it is the ONLY healing in the game.
  if not w.canRepair(r, l):
    w.refusedActions += 1
    return false
  let target = w.getRobot(l)
  let before = target.health
  r.repairCount += 1
  w.changeHealthLevel(target, ArchonRepairAmount, dcNormal)
  if r.team.isPlayer():
    let t = ord(r.team)
    w.stats.repairs[t] += 1
    w.stats.hpRepaired[t] += int(max(0.0, target.health - before))
  w.noteFirstAction(r, Bc16ActionRepair)
  true

proc doTransform*(w: World, r: Robot): bool {.discardable.} =
  ## `pack()` / `unpack()` -> `InternalRobot.transform`: swap the type, adjust
  ## the per-type counts, and add `TURRET_TRANSFORM_DELAY = 10.0` TO BOTH
  ## COUNTERS. THERE IS NO READINESS CHECK AT ALL, and `partCost` is not
  ## charged again.
  if r.kind != rtTurret and r.kind != rtTtm:
    w.refusedActions += 1
    return false
  let newKind = if r.kind == rtTurret: rtTtm else: rtTurret
  w.typeCount[ord(r.team)][r.kind] -= 1
  w.typeCount[ord(r.team)][newKind] += 1
  let wasTurret = r.kind == rtTurret
  r.kind = newKind
  r.d.transformDelay()
  if r.team.isPlayer() and wasTurret:
    w.stats.turretPacks[ord(r.team)] += 1
  w.noteFirstAction(r, if wasTurret: Bc16ActionPack else: Bc16ActionUnpack)
  true

proc doDisintegrate*(w: World, r: Robot) =
  ## `disintegrate()` throws `RobotDeathException`; the sandbox terminates and
  ## `runRound` (`:178-181`) calls `suicide()` AFTER `processEndOfTurn`, as an
  ## ordinary `DeathSignal` — so a robot that disintegrates WHILE INFECTED
  ## still becomes an enemy zombie, and leaves rubble otherwise.
  r.disintegrated = true
  w.noteFirstAction(r, Bc16ActionDisintegrate)

# ---------------------------------------------------------------------------
#  Aggregates the end ladder, the score and the hash chain read
# ---------------------------------------------------------------------------

func archonHealthTotal*(w: World, t: Team): float64 =
  for id in w.execOrder:
    if w.robotsById.hasKey(id):
      let r = w.robotsById[id]
      if r.team == t and r.kind == rtArchon: result += r.health

func partsWorth*(w: World, t: Team): int =
  ## `int(parts) + sum(partCost)` over that team's live robots — the
  ## per-team reading of rung 3, for the score and the readouts.
  result = int(w.resources[ord(t)])
  for id in w.execOrder:
    if w.robotsById.hasKey(id):
      let r = w.robotsById[id]
      if r.team == t: result += r.kind.partCost()

func partsNetWorthDiff*(w: World): float64 =
  ## Rung 3 EXACTLY as `processEndOfRound` computes it (`:641-665`): the
  ## accumulator is SEEDED with the parts difference and then walks every live
  ## robot of either team ONCE, in insertion order, adding A's `partCost` and
  ## subtracting B's. Neutrals and zombies belong to neither team and
  ## contribute nothing; a den and a zombie cost 0 anyway.
  result = w.resources[ord(teamA)] - w.resources[ord(teamB)]
  for id in w.execOrder:
    if w.robotsById.hasKey(id):
      let r = w.robotsById[id]
      if r.team == teamA: result += float64(r.kind.partCost())
      elif r.team == teamB: result -= float64(r.kind.partCost())

func highestArchonId*(w: World, t: Team): int =
  ## `highestAArchonID` / `highestBArchonID`, which are 0 when that team has
  ## no archon — and rung 4's `else` branch awards B, so a 0-vs-0 tie goes to
  ## B.
  for id in w.execOrder:
    if w.robotsById.hasKey(id):
      let r = w.robotsById[id]
      if r.team == t and r.kind == rtArchon: result = max(result, r.id)

func zombieCountByType*(w: World, k: RobotType): int =
  w.typeCount[ord(teamZombie)][k]

func densStanding*(w: World): int = w.typeCount[ord(teamZombie)][rtZombieden]

func neutralsStanding*(w: World): int = w.robotCount[ord(teamNeutral)]

func totalHealthTenths*(w: World, t: Team): int =
  var total = 0.0
  for id in w.execOrder:
    if w.robotsById.hasKey(id):
      let r = w.robotsById[id]
      if r.team == t: total += r.health
  int(total * 10.0)

func infectedCount*(w: World, t: Team): int =
  for id in w.execOrder:
    if w.robotsById.hasKey(id):
      let r = w.robotsById[id]
      if r.team == t and r.inf.isInfected(): result += 1

func impassableSquares*(w: World): int =
  for v in w.rubble:
    if v >= RubbleObstructionThresh: result += 1

func partsOnMap*(w: World): float64 =
  for v in w.partsAt: result += v

func rubbleChecksum*(w: World): uint64 =
  ## y ascending outer, x ascending inner — i.e. the array's own index order,
  ## which is `SquareArray.Double`'s `y * width + x` (D5). Folded in TENTHS so
  ## the value is an integer on both sides of the parity diff.
  var flat = newSeq[int](w.rubble.len)
  for i, v in w.rubble: flat[i] = int(v * 10.0)
  fnv1a64(flat)

func partsChecksum*(w: World): uint64 =
  var flat = newSeq[int](w.partsAt.len)
  for i, v in w.partsAt: flat[i] = int(v * 10.0)
  fnv1a64(flat)

func execOrderChecksum*(w: World): uint64 = fnv1a64(w.execOrder)

# ---------------------------------------------------------------------------
#  Construction
# ---------------------------------------------------------------------------

proc newWorld*(spec: MapSpec, maxRounds: int): World =
  ## `GameWorld`'s constructor, in its own order: `currentRound = -1`, the
  ## `IDGenerator` seeded from the map, BOTH TEAMS credited
  ## `PARTS_INITIAL_AMOUNT = 300.0` ONCE EACH, the rubble and parts arrays
  ## copied out of the map, then the initial robots spawned IN FILE ORDER, and
  ## finally `rand = new Random(mapSeed)`.
  ##
  ## The initial robots are NOT sorted by id (unlike 2022): ids come from the
  ## `IDGenerator` and are shuffled, while the ORDER is the file's.
  let size = spec.width * spec.height
  result = World(map: spec, width: spec.width, height: spec.height,
                 currentRound: -1, maxRounds: maxRounds, running: true,
                 symmetry: spec.symmetry,
                 rubble: spec.rubble, partsAt: spec.parts,
                 occupant: newSeq[Robot](size),
                 robotsById: initTable[int, Robot](),
                 hashChain: 0xcbf29ce484222325'u64,
                 winner: teamA, domination: dfNone, tiebreakRung: 0)
  result.idGen = initIdGenerator(spec.randomSeed, 0)
  when defined(bc16BrokenChassis):
    result.brokenChassis = true
  result.adjustResources(teamA, PartsInitialAmount)
  result.adjustResources(teamB, PartsInitialAmount)
  for b in spec.initialRobots:
    result.spawnRobot(RobotType(b.kind), loc(b.x, b.y), Team(b.team), 0)
  result.rand = initJavaRandom(spec.randomSeed)
  result.zombieRand = initJavaRandom(spec.randomSeed)
  for t in 0 .. 1:
    result.stats.archonsStart[t] = result.typeCount[t][rtArchon]
