## The Battlecode 2020 "Soup" world: state, geometry and every legality rule.
##
## A behaviour-for-behaviour port of `battlecode/world/GameWorld.java`,
## `world/InternalRobot.java`, `world/ObjectInfo.java`, `world/TeamInfo.java`
## and `world/RobotControllerImpl.java` at commit
## `7618f6be7d12da39f2e6e25801e578f1fecfbd86` (the last 2020 state), together
## with the pieces of `common/MapLocation.java` and `common/Direction.java` the
## rules depend on. The port is the authority at runtime; the Java engine
## survives only as the `parity-oracle` CI job (docs/PARITY.md).
##
## Four things in here look like details and are not:
##
## * **Exec order is SPAWN order, not id order.** `ObjectInfo.eachDynamicBodyByExecOrder`
##   walks `dynamicBodyExecOrder`, an append-on-spawn / remove-on-death list.
## * **`float32` everywhere the engine says `float`.** `cooldownTurns`, the
##   water level and both pollution coefficients are Java `float`s; widening
##   them to `float64` changes which round a robot becomes ready.
## * **Blocked robots.** A unit held by a delivery drone takes no turn and its
##   cooldown does NOT decay — but it still has its pollution effect reset.
## * **The transaction-id RNG is a Java `static` that the engine re-seeds with
##   the map seed inside `new RobotControllerImpl(...)`** — i.e. on EVERY
##   spawn, including the two HQs and every cow at map load. That quirk decides
##   the minting order among equal-fee transactions and is reproduced exactly.

import std/[math, tables]

export tables
import ../../rng
import constants, pollution, blockchain

export constants, pollution, blockchain

type
  Team* = enum
    teamA = 0
    teamB = 1
    teamNeutral = 2

  Dir* = enum
    ## Ordinals match `common/Direction.java`. `allDirections()` is
    ## `values()`, so it INCLUDES `CENTER` — which matters in `floodfill`,
    ## where the centre tile is re-examined (and always skipped, being already
    ## flooded).
    dNorth = 0
    dNortheast
    dEast
    dSoutheast
    dSouth
    dSouthwest
    dWest
    dNorthwest
    dCenter

  Symmetry* = enum
    ## `CowControlProvider.MapSymmetry`, in the engine's own candidate order.
    ## `vertical` flips x, `horizontal` flips y, `rotational` flips both.
    symVertical = 0
    symHorizontal = 1
    symRotational = 2

  Loc* = object
    x*, y*: int

  Domination* = enum
    dfNone
    dfHqDestroyed = "hq_destroyed"
    dfQuantity = "quantity"
    dfQuality = "quality"
    dfBroadcasts = "broadcasts"
    dfHighestId = "highest_id"
    dfCoinFlip = "coin_flip"

  InitialBody* = object
    id*: int
    team*: Team
    kind*: RobotKind
    loc*: Loc

  MapSpec* = object
    ## One converted `.map20`, as `data/maps/bc20/<name>.json` carries it.
    name*: string
    width*, height*: int
    symmetry*: Symmetry
    randomSeed*: int
    initialWater*: int
    elevation*: seq[int]     ## the `dirt` int array
    water*: seq[bool]
    pollution*: seq[int]
      ## The map's own pollution array. `GameWorld` reads it into a field and
      ## then never consults it: `getPollution` is derived entirely from the
      ## global level and the local effect registry. Carried for fidelity.
    soup*: seq[int]
    initialBodies*: seq[InitialBody]

  Robot* = ref object
    id*: int
    team*: Team
    kind*: RobotKind
    loc*: Loc
    roundsAlive*: int
    soupCarrying*: int
    dirtCarrying*: int
    cooldownTurns*: float32
    holdingUnit*: bool
    heldId*: int
    blocked*: bool
      ## Held by a delivery drone: no turn, no cooldown decay.
    opsLeft*: int
      ## The DecisionOps budget that replaces the JVM bytecode limit.
    dead*: bool

  LocalPollutionEffect* = object
    loc*: Loc
    radiusSquared*: int
    additive*: int
    multiplicative*: float32

  TeamStats* = object
    ## `TeamInfo` plus the per-game counters `results.games[]` reports. The
    ## engine keeps only the first three; everything else is telemetry and is
    ## never read by a rule.
    soup*: array[2, int]
    destroyedHq*: array[2, bool]
    blockchainsSent*: array[2, int]
    soupMined*: array[2, int]
    soupRefined*: array[2, int]
    dirtMoved*: array[2, int]
    unitsBuilt*: array[2, int]
    minersBuilt*: array[2, int]
    landscapersBuilt*: array[2, int]
    dronesBuilt*: array[2, int]
    vaporatorsBuilt*: array[2, int]
    netGunsBuilt*: array[2, int]
    designSchoolsBuilt*: array[2, int]
    fulfillmentBuilt*: array[2, int]
    refineriesBuilt*: array[2, int]
    dronePickups*: array[2, int]
    droneWaterDrops*: array[2, int]
    netGunKills*: array[2, int]
    transactionsSent*: array[2, int]
    blockchainSoupSpent*: array[2, int]

  World* = ref object
    map*: MapSpec
    width*, height*: int
    currentRound*: int
    maxRounds*: int
    running*: bool
    idGen*: IdGenerator
    rand*: JavaRandom
      ## `GameWorld.rand`, seeded from the map's own `randomSeed`. Replaces
      ## `setWinnerArbitrary`'s `Math.random()` (docs/RULES-BC20.md §Divergences).
    txRand*: JavaRandom
      ## `RobotControllerImpl.random`, a Java `private static Random` that the
      ## constructor assigns `new Random(gameWorld.getMapSeed())` — so it is
      ## RE-SEEDED ON EVERY SPAWN. Per-world here so two worlds in one process
      ## cannot bleed into each other; re-seeded identically.
    cowRand*: Table[int, JavaRandom]
    symmetry*: Symmetry
    elevation*: seq[int]
    soup*: seq[int]
    initialSoup*: seq[int]
    flooded*: seq[bool]
    floodedCount*: int
    localAdditive*: seq[int]
    localMultiplicative*: seq[float32]
    localPollutions*: Table[int, LocalPollutionEffect]
    globalPollution*: int
    globalPollutionPeak*: int
    waterLevel*: float32
    occupant*: seq[Robot]
    robotsById*: Table[int, Robot]
    execOrder*: seq[int]
    robotCount*: array[3, int]
    typeCount*: array[3, array[RobotKind, int]]
      ## `ObjectInfo.robotTypeCount`. The chassis reads it every turn; deriving
      ## it by walking `robotsById` per robot turn is O(n^2) per round and
      ## costs the perf gate.
    stats*: TeamStats
    txPool*: seq[Transaction]
    blockchain*: seq[seq[Transaction]]
    hqId*: array[2, int]
    hqLostRound*: array[2, int]
    hqLostCause*: array[2, string]
    winner*: Team
    hasWinner*: bool
    domination*: Domination
    ## Replay/telemetry sinks — never read by a rule.
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    hashChain*: uint64

const
  AllDirs* = [dNorth, dNortheast, dEast, dSoutheast,
              dSouth, dSouthwest, dWest, dNorthwest, dCenter]
    ## `Direction.allDirections()` == `Direction.values()`, CENTER included.
  MoveDirs* = [dNorth, dNortheast, dEast, dSoutheast,
               dSouth, dSouthwest, dWest, dNorthwest]
    ## `CowControlProvider.DIRECTIONS`, and the eight a unit can move in.

# ---------------------------------------------------------------------------
#  Geometry
# ---------------------------------------------------------------------------

func dx*(d: Dir): int =
  case d
  of dNorth, dSouth, dCenter: 0
  of dNortheast, dEast, dSoutheast: 1
  of dSouthwest, dWest, dNorthwest: -1

func dy*(d: Dir): int =
  case d
  of dEast, dWest, dCenter: 0
  of dNorth, dNortheast, dNorthwest: 1
  of dSoutheast, dSouth, dSouthwest: -1

func opposite*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 4) mod 8)

func rotateLeft*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 7) mod 8)

func rotateRight*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 1) mod 8)

func loc*(x, y: int): Loc = Loc(x: x, y: y)

func fromDelta*(dx, dy: int): Dir =
  for d in AllDirs:
    if d.dx == dx and d.dy == dy:
      return d
  dCenter
func `+`*(a: Loc, d: Dir): Loc = loc(a.x + d.dx, a.y + d.dy)
func `==`*(a, b: Loc): bool = a.x == b.x and a.y == b.y

func distanceSquaredTo*(a, b: Loc): int =
  let ddx = a.x - b.x
  let ddy = a.y - b.y
  ddx * ddx + ddy * ddy

func isWithinDistanceSquared*(a, b: Loc, r2: int): bool =
  a.distanceSquaredTo(b) <= r2

func isAdjacentTo*(a, b: Loc): bool =
  abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1

func chebyshev*(a, b: Loc): int =
  max(abs(a.x - b.x), abs(a.y - b.y))

func directionTo*(a, b: Loc): Dir =
  ## `MapLocation.directionTo`, ported with the engine's own 2.414 fan.
  let ddx = float64(b.x - a.x)
  let ddy = float64(b.y - a.y)
  if abs(ddx) >= 2.414 * abs(ddy):
    if ddx > 0: return dEast
    if ddx < 0: return dWest
    return dCenter
  elif abs(ddy) >= 2.414 * abs(ddx):
    if ddy > 0: return dNorth
    return dSouth
  elif ddx > 0:
    return (if ddy > 0: dNortheast else: dSoutheast)
  elif ddx < 0:
    return (if ddy > 0: dNorthwest else: dSouthwest)
  dCenter

func idx*(w: World, l: Loc): int = l.x + l.y * w.width
func indexToLoc*(w: World, i: int): Loc = loc(i mod w.width, i div w.width)
func onTheMap*(w: World, l: Loc): bool =
  l.x >= 0 and l.y >= 0 and l.x < w.width and l.y < w.height

iterator locationsWithinRadiusSquared*(w: World, center: Loc,
                                       r2: int): Loc =
  ## `GameWorld.getAllLocationsWithinRadiusSquared`, in its own x-then-y
  ## order, with the engine's `ceil(sqrt(r2)) + 1` window.
  let ceiled = int(ceil(sqrt(float64(max(0, r2))))) + 1
  let minX = max(center.x - ceiled, 0)
  let minY = max(center.y - ceiled, 0)
  let maxX = min(center.x + ceiled, w.width - 1)
  let maxY = min(center.y + ceiled, w.height - 1)
  for x in minX .. maxX:
    for y in minY .. maxY:
      let l = loc(x, y)
      if center.isWithinDistanceSquared(l, r2):
        yield l

# ---------------------------------------------------------------------------
#  Telemetry
# ---------------------------------------------------------------------------

proc emit*(w: World, kind: string, a = 0, b = 0, c = 0, s = "") =
  w.events.add((round: w.currentRound, kind: kind, a: a, b: b, c: c, s: s))

proc mixHash*(w: World, v: int) =
  ## The per-round hash chain (`coworld-ctf`'s `gameHash` discipline). The
  ## viewer re-derives every round and compares, exposing `bc_mismatch_round`.
  w.hashChain = (w.hashChain xor uint64(v and 0xFFFFFFFF)) *
    0x100000001B3'u64

# ---------------------------------------------------------------------------
#  Soup, dirt, water, pollution
# ---------------------------------------------------------------------------

func getSoup*(w: World, l: Loc): int =
  if w.onTheMap(l): w.soup[w.idx(l)] else: 0

proc removeSoup*(w: World, l: Loc, amount: int) =
  if w.onTheMap(l):
    let i = w.idx(l)
    w.soup[i] = max(0, w.soup[i] - amount)

func getDirt*(w: World, l: Loc): int =
  ## The engine calls the elevation "dirt". Off-map reads are 0, which is what
  ## the symmetry detector and every range check rely on.
  if w.onTheMap(l): w.elevation[w.idx(l)] else: 0

func getDirtDifference*(w: World, a, b: Loc): int =
  abs(w.getDirt(a) - w.getDirt(b))

func getPollution*(w: World, l: Loc): int =
  if not w.onTheMap(l): return 0
  let i = w.idx(l)
  javaRoundF32(float32(float32(w.globalPollution + w.localAdditive[i]) *
                       w.localMultiplicative[i]))

proc addGlobalPollution*(w: World, amount: int) =
  w.globalPollution = max(w.globalPollution + amount, 0)
  w.globalPollutionPeak = max(w.globalPollutionPeak, w.globalPollution)

proc addLocalPollution*(w: World, robotId: int, l: Loc, r2, additive: int,
                        multiplicative: float32) =
  w.localPollutions[robotId] = LocalPollutionEffect(
    loc: l, radiusSquared: r2, additive: additive,
    multiplicative: multiplicative)
  for affected in w.locationsWithinRadiusSquared(l, r2):
    let i = w.idx(affected)
    w.localAdditive[i] += additive
    w.localMultiplicative[i] = w.localMultiplicative[i] * multiplicative

proc resetPollutionForRobot*(w: World, robotId: int) =
  if robotId notin w.localPollutions:
    return
  let e = w.localPollutions[robotId]
  for affected in w.locationsWithinRadiusSquared(e.loc, e.radiusSquared):
    let i = w.idx(affected)
    w.localAdditive[i] -= e.additive
    w.localMultiplicative[i] = w.localMultiplicative[i] / e.multiplicative
  w.localPollutions.del(robotId)

func isFlooded*(w: World, l: Loc): bool =
  if w.onTheMap(l): w.flooded[w.idx(l)] else: false

func getRobot*(w: World, l: Loc): Robot =
  if w.onTheMap(l): w.occupant[w.idx(l)] else: nil

proc destroyRobot*(w: World, id: int)

proc setFloodStatus*(w: World, i: int, newStatus: bool) =
  if w.flooded[i] == newStatus:
    return
  w.flooded[i] = newStatus
  w.floodedCount += (if newStatus: 1 else: -1)
  let victim = w.occupant[i]
  if newStatus and victim != nil and victim.kind != rtDeliveryDrone:
    w.destroyRobot(victim.id)

proc tryResurface*(w: World, l: Loc) =
  ## `GameWorld.tryResurface`: `dirt[idx] >= waterLevel` un-floods the tile,
  ## the moment a deposit lifts it above the water. `int >= float` widens the
  ## elevation to `float`, exactly as Java does.
  let i = w.idx(l)
  if float32(w.elevation[i]) >= w.waterLevel:
    w.setFloodStatus(i, false)

# ---------------------------------------------------------------------------
#  Robot bookkeeping
# ---------------------------------------------------------------------------

func isBuilding*(kind: RobotKind): bool =
  kind in {rtHq, rtRefinery, rtVaporator, rtDesignSchool,
           rtFulfillmentCenter, rtNetGun}

func canRefine*(kind: RobotKind): bool = kind in {rtHq, rtRefinery}
func canAffectPollution*(kind: RobotKind): bool =
  kind in {rtHq, rtRefinery, rtVaporator, rtCow}
func canMoveKind*(kind: RobotKind): bool =
  kind in {rtMiner, rtLandscaper, rtDeliveryDrone, rtCow}
func canFly*(kind: RobotKind): bool = kind == rtDeliveryDrone
func canDig*(kind: RobotKind): bool = kind == rtLandscaper
func canMine*(kind: RobotKind): bool = kind == rtMiner
func canShootKind*(kind: RobotKind): bool = kind in {rtNetGun, rtHq}
func canBeShot*(kind: RobotKind): bool = kind == rtDeliveryDrone
func canBePickedUp*(kind: RobotKind): bool =
  kind in {rtMiner, rtLandscaper, rtCow}
func canPickUpUnits*(kind: RobotKind): bool = kind == rtDeliveryDrone

func canBuildKind*(builder, target: RobotKind): bool =
  ## `RobotType.canBuild` == `this == type.spawnSource`.
  case target
  of rtMiner: builder == rtHq
  of rtRefinery, rtVaporator, rtDesignSchool, rtFulfillmentCenter, rtNetGun:
    builder == rtMiner
  of rtLandscaper: builder == rtDesignSchool
  of rtDeliveryDrone: builder == rtFulfillmentCenter
  else: false

func spec*(r: Robot): RobotSpec = RobotSpecs[r.kind]

func currentSensorRadiusSquared*(w: World, r: Robot): int =
  javaRoundF32(float32(float32(RobotSpecs[r.kind].sensorRadiusSquared) *
                       sensorCoefficient(w.getPollution(r.loc))))

func canSenseLocation*(w: World, r: Robot, l: Loc): bool =
  r.loc.distanceSquaredTo(l) <= w.currentSensorRadiusSquared(r)

func isReady*(r: Robot): bool = r.cooldownTurns < 1.0'f32

proc addCooldownTurns*(w: World, r: Robot) =
  r.cooldownTurns = r.cooldownTurns +
    RobotSpecs[r.kind].actionCooldown * cooldownCoefficient(w.getPollution(r.loc))

proc addRobotAt(w: World, l: Loc, r: Robot) =
  w.occupant[w.idx(l)] = r

proc removeRobotAt(w: World, l: Loc) =
  w.occupant[w.idx(l)] = nil

proc addDirt*(w: World, l: Loc, amount: int)

proc addDirtCarrying*(w: World, r: Robot, amount: int) =
  ## `InternalRobot.addDirtCarrying`: a BUILDING whose accumulated dirt reaches
  ## its `dirtLimit` (HQ 50, every other building 15) is destroyed on the spot.
  r.dirtCarrying += amount
  if r.kind.isBuilding() and r.dirtCarrying >= RobotSpecs[r.kind].dirtLimit:
    if r.kind == rtHq and r.team != teamNeutral:
      w.hqLostCause[ord(r.team)] = "buried"
    w.destroyRobot(r.id)

proc removeDirt*(w: World, l: Loc) =
  ## `GameWorld.removeDirt`: dirt comes off a DIRTY BUILDING if one stands
  ## there, otherwise off the ground. There is no `tryResurface` here — digging
  ## a tile down never un-floods it.
  if not w.onTheMap(l): return
  let target = w.getRobot(l)
  if target != nil and target.kind.isBuilding() and target.dirtCarrying > 0:
    target.dirtCarrying = max(0, target.dirtCarrying - 1)
  else:
    w.elevation[w.idx(l)] -= 1

proc addDirt*(w: World, l: Loc, amount: int) =
  ## `GameWorld.addDirt`: onto a BUILDING if one stands there, otherwise onto
  ## the ground, and then `tryResurface`.
  if not w.onTheMap(l): return
  let target = w.getRobot(l)
  if target != nil and target.kind.isBuilding():
    w.addDirtCarrying(target, amount)
  else:
    w.elevation[w.idx(l)] += amount
    w.tryResurface(l)

# ---------------------------------------------------------------------------
#  Spawning and destruction
# ---------------------------------------------------------------------------

proc recomputeSymmetry*(w: World): Symmetry =
  ## `CowControlProvider.getSymmetry`, ported literally: candidates in the
  ## order [vertical, horizontal, rotational], each eliminated by the first
  ## tile where soup, elevation or robot TYPE disagrees under that transform,
  ## first survivor wins, `rotational` when none survives.
  var possible = @[symVertical, symHorizontal, symRotational]

  proc symX(w: World, x: int, s: Symmetry): int =
    if s == symHorizontal: x else: w.width - 1 - x
  proc symY(w: World, y: int, s: Symmetry): int =
    if s == symVertical: y else: w.height - 1 - y

  for x in 0 ..< w.width:
    for y in 0 ..< w.height:
      let here = loc(x, y)
      let bot = w.getRobot(here)
      for i in countdown(possible.high, 0):
        if i > possible.high: continue
        let s = possible[i]
        let there = loc(w.symX(x, s), w.symY(y, s))
        var drop = false
        if w.getSoup(here) != w.getSoup(there): drop = true
        if w.getDirt(here) != w.getDirt(there): drop = true
        let other = w.getRobot(there)
        if bot != nil or other != nil:
          if bot == nil or other == nil or bot.kind != other.kind:
            drop = true
        if drop:
          possible.delete(i)
      if possible.len <= 1: break
    if possible.len <= 1: break
  if possible.len > 0: possible[0] else: symRotational

proc spawnRobot*(w: World, id: int, kind: RobotKind, l: Loc,
                 team: Team): int {.discardable.} =
  ## `GameWorld.spawnRobot`. Three side effects are load-bearing:
  ##  * the new body is APPENDED to the exec order;
  ##  * `new RobotControllerImpl(...)` re-seeds the static transaction RNG with
  ##    the map seed;
  ##  * `controlProvider.robotSpawned` recomputes the map symmetry — but only
  ##    for the NEUTRAL provider (`TeamControlProvider` delegates by team), so
  ##    only a COW spawn moves it. Cows only exist at map load, which is why the
  ##    symmetry is fixed for the whole match.
  w.txRand = initJavaRandom(w.map.randomSeed)
  let r = Robot(id: id, team: team, kind: kind, loc: l, heldId: -1)
  w.robotsById[id] = r
  w.execOrder.add(id)
  w.robotCount[ord(team)] += 1
  w.typeCount[ord(team)][kind] += 1
  w.addRobotAt(l, r)
  if kind == rtHq and team != teamNeutral:
    w.hqId[ord(team)] = id
  if team == teamNeutral:
    w.symmetry = w.recomputeSymmetry()
  id

proc spawnRobot*(w: World, kind: RobotKind, l: Loc,
                 team: Team): int {.discardable.} =
  w.spawnRobot(w.idGen.nextId(), kind, l, team)

proc dropHeldUnit*(w: World, drone: Robot, target: Loc)

proc destroyRobot*(w: World, id: int) =
  ## `GameWorld.destroyRobot`, in its own order: off the grid, HQ flag, drop a
  ## carried unit at the drone's own tile, spill carried dirt, clear pollution.
  var r: Robot
  if not w.robotsById.pop(id, r):
    return
  r.dead = true
  w.removeRobotAt(r.loc)
  if r.kind == rtHq and r.team != teamNeutral:
    w.stats.destroyedHq[ord(r.team)] = true
    if w.hqLostRound[ord(r.team)] < 0:
      w.hqLostRound[ord(r.team)] = w.currentRound
      if w.hqLostCause[ord(r.team)] == "none":
        w.hqLostCause[ord(r.team)] = "drowned"
  if r.kind.canPickUpUnits() and r.holdingUnit:
    w.dropHeldUnit(r, r.loc)
  if r.dirtCarrying > 0:
    w.addDirt(r.loc, r.dirtCarrying)
  if r.kind.canAffectPollution():
    w.resetPollutionForRobot(id)
  w.robotCount[ord(r.team)] -= 1
  w.typeCount[ord(r.team)][r.kind] -= 1
  let i = w.execOrder.find(id)
  if i >= 0: w.execOrder.delete(i)
  w.emit("died", id, ord(r.team), ord(r.kind))

# ---------------------------------------------------------------------------
#  Rule 6 — the legal actions, with their exact preconditions
# ---------------------------------------------------------------------------

func isLocationOccupied*(w: World, l: Loc): bool =
  w.getRobot(l) != nil

proc canMove*(w: World, r: Robot, d: Dir): bool =
  let target = r.loc + d
  if not r.kind.canMoveKind(): return false
  if not r.loc.isAdjacentTo(target): return false
  if not w.onTheMap(target): return false
  if w.isLocationOccupied(target): return false
  if w.getDirtDifference(r.loc, target) > MaxDirtDifference and
      not r.kind.canFly(): return false
  isReady(r)

proc movePickedUpUnit(w: World, drone: Robot, center: Loc) =
  if drone.heldId in w.robotsById:
    w.robotsById[drone.heldId].loc = center

proc move*(w: World, r: Robot, d: Dir) =
  ## `RobotControllerImpl.move`. The engine checks the destination for flooding
  ## AFTER the legality assert and disintegrates the mover — a non-flying unit
  ## that walks into water dies instead of moving.
  let center = r.loc + d
  if not w.canMove(r, d): return
  if w.isFlooded(center) and not r.kind.canFly():
    w.destroyRobot(r.id)
    return
  w.addCooldownTurns(r)
  w.removeRobotAt(r.loc)
  w.addRobotAt(center, r)
  r.loc = center
  if r.holdingUnit:
    w.movePickedUpUnit(r, center)

proc canBuildRobot*(w: World, r: Robot, kind: RobotKind, d: Dir): bool =
  let spawnLoc = r.loc + d
  if not r.kind.canBuildKind(kind): return false
  if r.team == teamNeutral: return false
  if w.stats.soup[ord(r.team)] < RobotSpecs[kind].cost: return false
  if not w.onTheMap(spawnLoc): return false
  if w.isLocationOccupied(spawnLoc): return false
  if w.isFlooded(spawnLoc) and kind != rtDeliveryDrone: return false
  if kind != rtDeliveryDrone and
      w.getDirtDifference(r.loc, spawnLoc) > MaxDirtDifference: return false
  isReady(r)

proc countBuilt(w: World, team: Team, kind: RobotKind) =
  let t = ord(team)
  w.stats.unitsBuilt[t] += 1
  case kind
  of rtMiner: w.stats.minersBuilt[t] += 1
  of rtLandscaper: w.stats.landscapersBuilt[t] += 1
  of rtDeliveryDrone: w.stats.dronesBuilt[t] += 1
  of rtVaporator: w.stats.vaporatorsBuilt[t] += 1
  of rtNetGun: w.stats.netGunsBuilt[t] += 1
  of rtDesignSchool: w.stats.designSchoolsBuilt[t] += 1
  of rtFulfillmentCenter: w.stats.fulfillmentBuilt[t] += 1
  of rtRefinery: w.stats.refineriesBuilt[t] += 1
  else: discard

proc buildRobot*(w: World, r: Robot, kind: RobotKind, d: Dir): int
    {.discardable.} =
  if not w.canBuildRobot(r, kind, d): return -1
  w.addCooldownTurns(r)
  w.stats.soup[ord(r.team)] -= RobotSpecs[kind].cost
  let id = w.spawnRobot(kind, r.loc + d, r.team)
  w.robotsById[id].cooldownTurns = float32(InitialCooldownTurns)
  w.countBuilt(r.team, kind)
  w.emit("built", id, ord(r.team), ord(kind))
  id

proc canMineSoup*(w: World, r: Robot, d: Dir): bool =
  let center = r.loc + d
  if not r.kind.canMine(): return false
  if r.soupCarrying >= RobotSpecs[r.kind].soupLimit: return false
  if not w.onTheMap(center): return false
  if w.getSoup(center) <= 0: return false
  isReady(r)

proc mineSoup*(w: World, r: Robot, d: Dir) =
  if not w.canMineSoup(r, d): return
  w.addCooldownTurns(r)
  let mineLoc = r.loc + d
  let mined = min(SoupMiningRate,
    min(w.getSoup(mineLoc), RobotSpecs[r.kind].soupLimit - r.soupCarrying))
  w.removeSoup(mineLoc, mined)
  r.soupCarrying += mined
  w.stats.soupMined[ord(r.team)] += mined

proc canDepositSoup*(w: World, r: Robot, d: Dir): bool =
  let center = r.loc + d
  if r.kind != rtMiner: return false
  if r.soupCarrying <= 0: return false
  if not w.onTheMap(center): return false
  let adjacent = w.getRobot(center)
  if adjacent == nil or not adjacent.kind.canRefine(): return false
  isReady(r)

proc depositSoup*(w: World, r: Robot, d: Dir, amount: int) =
  if not w.canDepositSoup(r, d): return
  let give = min(amount, r.soupCarrying)
  w.addCooldownTurns(r)
  r.soupCarrying = (if give > r.soupCarrying: 0 else: r.soupCarrying - give)
  w.getRobot(r.loc + d).soupCarrying += give

proc canDigDirt*(w: World, r: Robot, d: Dir): bool =
  let center = r.loc + d
  if not r.kind.canDig(): return false
  if r.dirtCarrying >= RobotSpecs[r.kind].dirtLimit: return false
  if not w.onTheMap(center): return false
  let adjacent = w.getRobot(center)
  if adjacent != nil and adjacent.kind.isBuilding() and
      adjacent.dirtCarrying <= 0: return false
  isReady(r)

proc digDirt*(w: World, r: Robot, d: Dir) =
  if not w.canDigDirt(r, d): return
  w.addCooldownTurns(r)
  w.removeDirt(r.loc + d)
  w.addDirtCarrying(r, 1)
  w.stats.dirtMoved[ord(r.team)] += 1

proc canDepositDirt*(w: World, r: Robot, d: Dir): bool =
  let center = r.loc + d
  if r.kind != rtLandscaper: return false
  if r.dirtCarrying < 1: return false
  if not w.onTheMap(center): return false
  isReady(r)

proc depositDirt*(w: World, r: Robot, d: Dir) =
  if not w.canDepositDirt(r, d): return
  w.addCooldownTurns(r)
  r.dirtCarrying = max(0, r.dirtCarrying - 1)
  w.addDirt(r.loc + d, 1)
  w.stats.dirtMoved[ord(r.team)] += 1

proc canPickUpUnit*(w: World, r: Robot, id: int): bool =
  if not r.kind.canPickUpUnits(): return false
  if r.holdingUnit: return false
  if id notin w.robotsById: return false
  let target = w.robotsById[id]
  if not target.kind.canBePickedUp(): return false
  if not target.loc.isWithinDistanceSquared(r.loc,
      DeliveryDronePickupRadiusSquared): return false
  if target.blocked: return false
  isReady(r)

proc pickUpUnit*(w: World, r: Robot, id: int) =
  if not w.canPickUpUnit(r, id): return
  let target = w.robotsById[id]
  target.blocked = true
  w.removeRobotAt(target.loc)
  r.holdingUnit = true
  r.heldId = id
  target.loc = r.loc
  w.addCooldownTurns(r)
  w.stats.dronePickups[ord(r.team)] += 1
  w.emit("pickup", r.id, ord(r.team), id)

proc canDropUnit*(w: World, r: Robot, d: Dir): bool =
  let center = r.loc + d
  if not r.kind.canPickUpUnits(): return false
  if not r.holdingUnit: return false
  if not w.onTheMap(center): return false
  if w.isLocationOccupied(center): return false
  isReady(r)

proc dropHeldUnit*(w: World, drone: Robot, target: Loc) =
  ## `dropUnit(dir, checkConditions=false)`: the unconditional drop a dying
  ## drone performs onto its own tile. A non-drone dropped into water is
  ## destroyed immediately.
  let id = drone.heldId
  if id notin w.robotsById:
    drone.holdingUnit = false
    drone.heldId = -1
    return
  let dropped = w.robotsById[id]
  dropped.blocked = false
  dropped.loc = target
  drone.holdingUnit = false
  drone.heldId = -1
  w.addRobotAt(target, dropped)
  if w.isFlooded(target):
    if dropped.team != drone.team and drone.team != teamNeutral:
      w.stats.droneWaterDrops[ord(drone.team)] += 1
    w.emit("drone_water_drop", drone.id, ord(drone.team), ord(dropped.kind),
      $ord(dropped.team))
    w.destroyRobot(id)

proc dropUnit*(w: World, r: Robot, d: Dir) =
  if not w.canDropUnit(r, d): return
  let target = r.loc + d
  let id = r.heldId
  let dropped = w.robotsById.getOrDefault(id)
  dropped.blocked = false
  dropped.loc = target
  r.holdingUnit = false
  r.heldId = -1
  w.addRobotAt(target, dropped)
  w.addCooldownTurns(r)
  if w.isFlooded(target):
    if dropped.team != r.team and r.team != teamNeutral:
      w.stats.droneWaterDrops[ord(r.team)] += 1
    w.emit("drone_water_drop", r.id, ord(r.team), ord(dropped.kind),
      $ord(dropped.team))
    w.destroyRobot(id)

proc canShootUnit*(w: World, r: Robot, id: int): bool =
  if not r.kind.canShootKind(): return false
  if id notin w.robotsById: return false
  let target = w.robotsById[id]
  if not target.kind.canBeShot(): return false
  if not target.loc.isWithinDistanceSquared(r.loc,
      NetGunShootRadiusSquared): return false
  isReady(r)

proc shootUnit*(w: World, r: Robot, id: int) =
  if not w.canShootUnit(r, id): return
  w.destroyRobot(id)
  w.addCooldownTurns(r)
  if r.team != teamNeutral:
    w.stats.netGunKills[ord(r.team)] += 1
  w.emit("net_gun_kill", r.id, ord(r.team), id)

proc canSubmitTransaction*(w: World, r: Robot, cost: int): bool =
  ## NOT an action: no cooldown, no `isReady` check. `message.length == 7` is
  ## a type invariant here.
  if r.team == teamNeutral: return false
  if w.stats.soup[ord(r.team)] < cost: return false
  cost > 0

proc submitTransaction*(w: World, r: Robot,
                        message: array[TransactionLength, int], cost: int) =
  if not canSubmitTransaction(w, r, cost): return
  let t = ord(r.team)
  w.stats.soup[t] -= cost
  w.stats.blockchainSoupSpent[t] += cost
  w.stats.transactionsSent[t] += 1
  let id = w.txRand.nextInt()
  w.txPool.add(newTransaction(cost, message, id, t))

proc getBlock*(w: World, roundNumber: int): seq[Transaction] =
  if roundNumber <= 0 or roundNumber >= w.currentRound: return @[]
  if roundNumber - 1 >= w.blockchain.len: return @[]
  w.blockchain[roundNumber - 1]

# ---------------------------------------------------------------------------
#  The end-of-match ladder, in the engine's own order
# ---------------------------------------------------------------------------

proc setWinner*(w: World, t: Team, d: Domination) =
  w.winner = t
  w.hasWinner = true
  w.domination = d

func netWorth*(w: World, team: Team): int =
  result = w.stats.soup[ord(team)]
  for _, r in w.robotsById:
    if r.team == team:
      result += RobotSpecs[r.kind].cost

func livingUnits*(w: World, team: Team): int = w.robotCount[ord(team)]

proc setWinnerIfHqDestroyed*(w: World): bool =
  let a = w.stats.destroyedHq[0]
  let b = w.stats.destroyedHq[1]
  if a and not b:
    w.setWinner(teamB, dfHqDestroyed); true
  elif b and not a:
    w.setWinner(teamA, dfHqDestroyed); true
  else: false

proc setWinnerIfQuantity*(w: World): bool =
  let a = w.robotCount[0]
  let b = w.robotCount[1]
  if b > a: w.setWinner(teamB, dfQuantity); true
  elif a > b: w.setWinner(teamA, dfQuantity); true
  else: false

proc setWinnerIfQuality*(w: World): bool =
  let a = w.netWorth(teamA)
  let b = w.netWorth(teamB)
  if a > b: w.setWinner(teamA, dfQuality); true
  elif b > a: w.setWinner(teamB, dfQuality); true
  else: false

proc setWinnerIfMoreBroadcasts*(w: World): bool =
  let a = w.stats.blockchainsSent[0]
  let b = w.stats.blockchainsSent[1]
  if a > b: w.setWinner(teamA, dfBroadcasts); true
  elif b > a: w.setWinner(teamB, dfBroadcasts); true
  else: false

proc setWinnerHighestRobotId*(w: World): bool =
  var best = -1
  var bestTeam = teamNeutral
  for id, r in w.robotsById:
    if r.team != teamNeutral and id > best:
      best = id
      bestTeam = r.team
  if best < 0: return false
  w.setWinner(bestTeam, dfHighestId)
  true

proc setWinnerArbitrary*(w: World) =
  ## `setWinnerArbitrary` uses `Math.random()`, which is wall-clock seeded and
  ## therefore not reproducible. A draw from the WORLD RNG replaces it — a
  ## documented divergence, reachable only when neither team has a single
  ## living robot (docs/RULES-BC20.md §Divergences).
  w.setWinner((if w.rand.nextDouble() < 0.5: teamA else: teamB), dfCoinFlip)

func timeLimitReached*(w: World): bool =
  ## `GameWorld.timeLimitReached` is `currentRound >= rounds - 1`, so a
  ## 1500-round cap plays 1499. The off-by-one is the engine's.
  w.currentRound >= w.maxRounds - 1

proc checkEndOfMatch*(w: World) =
  if not (w.timeLimitReached() or w.stats.destroyedHq[0] or
          w.stats.destroyedHq[1]):
    return
  if w.hasWinner: return
  if w.setWinnerIfHqDestroyed(): return
  if w.setWinnerIfQuantity(): return
  if w.setWinnerIfQuality(): return
  if w.setWinnerIfMoreBroadcasts(): return
  if w.setWinnerHighestRobotId(): return
  w.setWinnerArbitrary()

proc gamePoints*(w: World): array[2, int] =
  ## `points[t] = int(60*hq_survival + 25*unit_share + 15*net_worth_share)`.
  ##
  ## Every share is narrowed through FLOAT32 before the weighted sum and the
  ## sum is TRUNCATED by the `int()` cast — not for fidelity to Java (this
  ## formula is ours) but for recorder/re-deriver agreement: the same
  ## arithmetic runs natively on x86-64 and in wasm32 and must produce the same
  ## integer. `units` counts BUILDINGS TOO and `worth` includes the team pool,
  ## because those are exactly what the engine's `quantity` and `quality`
  ## rungs compare.
  var hq: array[2, int]
  for t in 0 .. 1:
    hq[t] = if w.stats.destroyedHq[t]: 0 else: 1
  let hqTotal = max(1, hq[0] + hq[1])
  let units = [w.livingUnits(teamA), w.livingUnits(teamB)]
  let unitTotal = max(1, units[0] + units[1])
  let worth = [w.netWorth(teamA), w.netWorth(teamB)]
  let worthTotal = max(1, worth[0] + worth[1])
  for t in 0 .. 1:
    let survival = float32(hq[t]) / float32(hqTotal)
    let shareU = float32(units[t]) / float32(unitTotal)
    let shareW = float32(worth[t]) / float32(worthTotal)
    result[t] = int(60.0'f32 * survival + 25.0'f32 * shareU +
                    15.0'f32 * shareW)

# ---------------------------------------------------------------------------
#  Turn scaffolding and construction
# ---------------------------------------------------------------------------

proc processBeginningOfRound*(w: World) =
  ## Rule 1 and rule 2. `InternalRobot.processBeginningOfRound` is a no-op in
  ## 2020; it is kept as a named step because the hash chain and the parity
  ## trace are taken around it.
  inc w.currentRound
  w.stats.soup[0] += BaseIncomePerRound
  w.stats.soup[1] += BaseIncomePerRound

proc processBeginningOfTurn*(w: World, r: Robot) =
  ## Rule 5. The cooldown decays and the DecisionOps budget is reset.
  if r.cooldownTurns > 0:
    r.cooldownTurns = max(0.0'f32, r.cooldownTurns - 1.0'f32)
  r.opsLeft = RobotSpecs[r.kind].decisionOps

proc processEndOfTurn*(w: World, r: Robot) =
  ## Rule 7, in `InternalRobot.processEndOfTurn`'s own order. A refinery's
  ## local +500 is installed HERE and removed at 7.1 of its own next turn, so
  ## it lasts exactly one round.
  if r.kind.canAffectPollution():
    w.resetPollutionForRobot(r.id)
  var shouldPollute = false
  if r.kind.canRefine() and r.soupCarrying > 0:
    let produced = min(r.soupCarrying, RobotSpecs[r.kind].maxSoupProduced)
    r.soupCarrying -= produced
    w.stats.soup[ord(r.team)] += produced
    w.stats.soupRefined[ord(r.team)] += produced
    shouldPollute = true
  if r.kind == rtVaporator:
    w.stats.soup[ord(r.team)] += RobotSpecs[r.kind].maxSoupProduced
    shouldPollute = true
  if r.kind == rtCow:
    shouldPollute = true
  if r.kind.canAffectPollution() and shouldPollute:
    w.addGlobalPollution(RobotSpecs[r.kind].globalPollutionAmount)
    w.addLocalPollution(r.id, r.loc, RobotSpecs[r.kind].pollutionRadiusSquared,
      RobotSpecs[r.kind].localPollutionAdditiveEffect,
      RobotSpecs[r.kind].localPollutionMultiplicativeEffect)
  r.roundsAlive += 1

proc processBlockchain*(w: World) =
  ## Rule 8.1. `blockchainsSent` counts MINTED transactions, not submitted
  ## ones — the `broadcasts` rung of the tiebreak ladder reads it.
  let block0 = mintBlock(w.txPool, NumberOfTransactionsPerBlock)
  for t in block0:
    w.stats.blockchainsSent[t.team] += 1
  w.blockchain.add(block0)

proc newWorld*(spec: MapSpec, maxRounds: int): World =
  let n = spec.width * spec.height
  result = World(
    map: spec,
    width: spec.width,
    height: spec.height,
    currentRound: 0,
    maxRounds: maxRounds,
    running: true,
    idGen: initIdGenerator(spec.randomSeed),
    rand: initJavaRandom(spec.randomSeed),
    txRand: initJavaRandom(spec.randomSeed),
    cowRand: initTable[int, JavaRandom](),
    symmetry: symRotational,
    elevation: spec.elevation,
    soup: spec.soup,
    initialSoup: spec.soup,
    flooded: spec.water,
    localAdditive: newSeq[int](n),
    localMultiplicative: newSeq[float32](n),
    localPollutions: initTable[int, LocalPollutionEffect](),
    globalPollution: 0,
    waterLevel: float32(spec.initialWater),
    occupant: newSeq[Robot](n),
    robotsById: initTable[int, Robot](),
    winner: teamNeutral,
    domination: dfNone,
    hashChain: 0xCBF29CE484222325'u64
  )
  for i in 0 ..< n:
    result.localMultiplicative[i] = 1.0'f32
    if result.flooded[i]: result.floodedCount += 1
  result.stats.soup[0] = InitialSoup
  result.stats.soup[1] = InitialSoup
  result.hqId = [-1, -1]
  result.hqLostRound = [-1, -1]
  result.hqLostCause = ["none", "none"]
  ## `CowControlProvider.matchStarted` computes the symmetry BEFORE any body
  ## exists; each cow spawn then recomputes it over the populated world.
  result.symmetry = result.recomputeSymmetry()
  for body in spec.initialBodies:
    result.spawnRobot(body.id, body.kind, body.loc, body.team)
