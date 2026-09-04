## The Battlecode 2026 world: state, geometry and every legality rule.
##
## This is a behaviour-for-behaviour port of `battlecode/world/GameWorld.java`,
## `world/InternalRobot.java` and `world/RobotControllerImpl.java` at tag
## `engine.1.2.5`, together with the pieces of `common/MapLocation.java` and
## `world/LiveMap.java` the rules depend on. The port is the authority at
## runtime; the Java engine survives only as the `parity-oracle` CI job
## (docs/PARITY.md).
##
## Three things in here look like details and are not:
##
## * **Iteration order.** `allLocationsInCone` reverses its x/y sweep by
##   chirality exactly as the engine does, because `senseNearbyRobots` returns
##   robots in that order and the cat target loop keeps the LAST rat it sees.
## * **Chirality.** Every multi-tile robot's part list, every cone and every
##   BFS direction is mirrored for chirality 1. A mirrored cone that is not
##   mirrored is a silent, match-long divergence.
## * **Cooldown arithmetic.** The carry multiplier is `(int)1.5 == 1` in Java
##   — an integer cast of a double constant, so carrying costs nothing extra
##   on movement and turning. Ported as written, not as intended.

import std/[algorithm, math, tables]

export tables
import ../../rng
import constants

type
  Team* = enum
    teamA = 0
    teamB = 1
    teamNeutral = 2

  Dir* = enum
    ## Ordinals match `common/Direction.java`, which `opposite`, `rotateLeft`
    ## and `rotateRight` do modular arithmetic on.
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
    symRotational = 0
    symHorizontal = 1
    symVertical = 2

  Loc* = object
    x*, y*: int

  CatState* = enum
    csExplore
    csAttack

  DominationFactor* = enum
    dfNone
    dfKillAllRatKings = "kill_all_rat_kings"
    dfMorePoints = "more_points"
    dfMoreCheese = "more_cheese"
    dfMoreRobotsAlive = "more_robots_alive"
    dfDubious = "won_by_dubious_reasons"

  InitialBody* = object
    id*: int
    team*: Team
    unit*: UnitType
    loc*: Loc
    dir*: Dir
    chirality*: int

  MapSpec* = object
    ## One converted `.map26`, as `data/maps/bc26/<name>.json` carries it.
    name*: string
    width*, height*: int
    symmetry*: Symmetry
    randomSeed*: int
    walls*: seq[bool]
    dirt*: seq[bool]
    cheese*: seq[int]
    cheeseMines*: seq[int]          ## tile indices
    catWaypointIds*: seq[int]
    catWaypointVecs*: seq[seq[int]] ## tile indices, per cat id
    initialBodies*: seq[InitialBody]

  Message* = object
    content*: int
    senderId*: int
    round*: int
    source*: Loc

  Trap* = ref object
    id*: int
    kind*: TrapType
    loc*: Loc
    team*: Team

  CheeseMine* = ref object
    loc*: Loc
    lastSpawnRound*: int
    pair*: CheeseMine

  Robot* = ref object
    id*: int
    team*: Team
    unit*: UnitType
    loc*: Loc
    dir*: Dir
    chirality*: int
    health*: int
    cheese*: int
    roundsAlive*: int
    actionCooldown*: int
    movementCooldown*: int
    turningCooldown*: int
    turnsSinceThrownOrDropped*: int
    lastGrabberId*: int
    carrying*: Robot
    grabbedBy*: Robot
    thrownDir*: Dir
    isThrown*: bool
    remainingThrowDuration*: int
    remainingCarriedDuration*: int
    inbox*: seq[Message]
    sentMessages*: int
    sleepTimeRemaining*: int
    ## cat state
    currentWaypoint*: int
    previousWaypoint*: int
    catState*: CatState
    catWaypoints*: seq[Loc]
    catTargetLoc*: Loc
    hasCatTarget*: bool
    catTurns*: int
    catTargetId*: int
    catTargetLocValid*: bool
    catTurnsStuck*: int
    ## the DecisionOps budget that replaces the JVM bytecode limit
    opsLeft*: int
    dead*: bool

  TeamInfo* = object
    globalCheese*: array[2, int]
    dirtCounts*: array[2, int]
    cheeseCollected*: array[2, int]
    cheeseTransferred*: array[2, int]
    numBabyRats*: array[2, int]
    numRatKings*: array[2, int]
    damageToCats*: array[2, int]
    damageSuffered*: array[2, int]
    points*: array[2, int]
    ratsBuilt*: array[2, int]
    kingsBuilt*: array[2, int]
    trapsPlaced*: array[2, int]
    dirtPlaced*: array[2, int]

  World* = ref object
    map*: MapSpec
    width*, height*: int
    currentRound*: int
    running*: bool
    isCooperation*: bool
    backstabRound*: int
    backstabber*: Team
    hasBackstabber*: bool
    backstabTrigger*: string
    idGen*: IdGenerator
    rand*: JavaRandom
    catRand*: JavaRandom
      ## `InternalRobot.rand`, a Java STATIC seeded 1092 and therefore shared
      ## by every cat in the process. Per-world here so two worlds in one
      ## process cannot bleed into each other; seeded identically.
    walls*: seq[bool]
    dirt*: seq[bool]
    cheeseAmounts*: seq[int]
    occupant*: seq[Robot]
    flying*: seq[Robot]
    trapAt*: array[2, seq[Trap]]
    trapTriggers*: seq[seq[Trap]]
    trapCounts*: array[TrapType, array[2, int]]
    cheeseMineAt*: seq[CheeseMine]
    cheeseMines*: seq[CheeseMine]
    robotsById*: Table[int, Robot]
    execOrder*: seq[int]
    teamInfo*: TeamInfo
    numCats*: int
    sharedArray*: array[2, array[64, int]]
    hasRunCheeseMines*: bool
    hasTraveled*: seq[int]
    winner*: Team
    hasWinner*: bool
    domination*: DominationFactor
    bfsCache*: Table[int, seq[int8]]
      ## Lazy `bfsFromTarget`: key = target tile index * 2 + chirality. The
      ## engine precomputes all of them up front (a 60x60 map is 26 MB and
      ## 830 M operations); the result is a pure function of the WALL layout,
      ## which never changes, so computing a target's map on first use is
      ## identical and pays only for the handful of targets cats ask about.
    maxRounds*: int
    ## Replay/telemetry sinks — never read by a rule.
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    hashChain*: uint64

const
  NonCenterDirs* = [dWest, dNorthwest, dNorth, dNortheast,
                    dEast, dSoutheast, dSouth, dSouthwest]
    ## `InternalRobot.processEndOfTurn`'s own array, in its own order: the
    ## cat's random-direction draws index into THIS, not into `Dir`.
  BfsNeighbourDirs* = [dNorth, dEast, dSouth, dWest,
                       dNortheast, dSoutheast, dSouthwest, dNorthwest]
    ## `GameWorld.bfsFromTarget`'s neighbour sweep order.
  AllDirs* = [dNorth, dNortheast, dEast, dSoutheast,
              dSouth, dSouthwest, dWest, dNorthwest, dCenter]

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

func fromDelta*(dx, dy: int): Dir =
  for d in AllDirs:
    if d.dx == dx and d.dy == dy:
      return d
  dCenter

func loc*(x, y: int): Loc = Loc(x: x, y: y)
func `+`*(a: Loc, d: Dir): Loc = loc(a.x + d.dx, a.y + d.dy)
func translate*(a: Loc, dx, dy: int): Loc = loc(a.x + dx, a.y + dy)
func `==`*(a, b: Loc): bool = a.x == b.x and a.y == b.y

func distanceSquaredTo*(a, b: Loc): int =
  let dx = a.x - b.x
  let dy = a.y - b.y
  dx * dx + dy * dy

func bottomLeftDistanceSquaredTo*(a, b: Loc): float32 =
  ## `MapLocation.bottomLeftDistanceSquaredTo` — computed in double, narrowed
  ## to float on return, exactly as Java does.
  let dx = float64(a.x) + 0.5 - float64(b.x)
  let dy = float64(a.y) + 0.5 - float64(b.y)
  float32(dx * dx + dy * dy)

func isAdjacentTo*(a, b: Loc): bool =
  abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1

func directionTo*(a, b: Loc): Dir =
  ## `MapLocation.directionTo`. The 2.414 constant is the engine's own.
  let dx = float64(b.x - a.x)
  let dy = float64(b.y - a.y)
  if abs(dx) >= 2.414 * abs(dy):
    if dx > 0: dEast
    elif dx < 0: dWest
    else: dCenter
  elif abs(dy) >= 2.414 * abs(dx):
    if dy > 0: dNorth else: dSouth
  else:
    if dy > 0:
      if dx > 0: dNortheast else: dNorthwest
    else:
      if dx > 0: dSoutheast else: dSouthwest

func isWithinDistanceSquared*(
  a, b: Loc, distanceSquared: int, facing: Dir, theta: float64,
  useBottomLeft = false
): bool =
  ## `MapLocation.isWithinDistanceSquared(loc, d2, dir, theta, useBottomLeft)`.
  ## The `1e-3` slack on the half-angle is the engine's, and it is what makes
  ## the 45-degree diagonal boundary robust to the last bit of `acos`.
  if a == b:
    return true
  const adjustment = 1e-3
  let isValidDistance =
    if useBottomLeft: a.bottomLeftDistanceSquaredTo(b) <= float32(distanceSquared)
    else: a.distanceSquaredTo(b) <= distanceSquared
  var isValidAngle = true
  if facing != dCenter:
    let
      dx = float64(b.x) - (if useBottomLeft: float64(a.x) + 0.5 else: float64(a.x))
      dy = float64(b.y) - (if useBottomLeft: float64(a.y) + 0.5 else: float64(a.y))
      fdx = float64(facing.dx)
      fdy = float64(facing.dy)
      cosSim = (fdx * dx + fdy * dy) /
        sqrt((dx * dx + dy * dy) * (fdx * fdx + fdy * fdy))
      halfAngle = radToDeg(abs(arccos(clamp(cosSim, -1.0, 1.0))))
    isValidAngle = halfAngle - adjustment <= theta / 2
  isValidDistance and isValidAngle

# ---------------------------------------------------------------------------
#  Map access
# ---------------------------------------------------------------------------

func idx*(w: World, l: Loc): int = l.x + l.y * w.width
func indexToLoc*(w: World, i: int): Loc = loc(i mod w.width, i div w.width)
func onTheMap*(w: World, l: Loc): bool =
  l.x >= 0 and l.y >= 0 and l.x < w.width and l.y < w.height

func symmetricX*(w: World, x: int): int =
  case w.map.symmetry
  of symHorizontal: x
  else: w.width - 1 - x

func symmetricY*(w: World, y: int): int =
  case w.map.symmetry
  of symVertical: y
  else: w.height - 1 - y

func symmetryLocation*(w: World, l: Loc): Loc =
  loc(w.symmetricX(l.x), w.symmetricY(l.y))

func flipDirBySymmetry*(w: World, d: Dir): Dir =
  var dx = d.dx
  var dy = d.dy
  case w.map.symmetry
  of symHorizontal: dy = -dy
  of symVertical: dx = -dx
  of symRotational:
    dx = -dx
    dy = -dy
  fromDelta(dx, dy)

func getWall*(w: World, l: Loc): bool =
  if not w.onTheMap(l): true else: w.walls[w.idx(l)]

func getDirt*(w: World, l: Loc): bool =
  if not w.onTheMap(l): false else: w.dirt[w.idx(l)]

func getRobot*(w: World, l: Loc): Robot =
  if not w.onTheMap(l): nil else: w.occupant[w.idx(l)]

func getFlyingRobot*(w: World, l: Loc): Robot =
  if not w.onTheMap(l): nil else: w.flying[w.idx(l)]

func isPassable*(w: World, l: Loc): bool =
  if not w.onTheMap(l): return false
  let i = w.idx(l)
  not (w.walls[i] or w.dirt[i] or w.flying[i] != nil)

func getCheeseAmount*(w: World, l: Loc): int =
  if not w.onTheMap(l): 0 else: w.cheeseAmounts[w.idx(l)]

proc addCheese*(w: World, l: Loc, amount: int) =
  w.cheeseAmounts[w.idx(l)] += amount

func hasCheeseMine*(w: World, l: Loc): bool =
  w.onTheMap(l) and w.cheeseMineAt[w.idx(l)] != nil

proc setDirt*(w: World, l: Loc, val: bool) =
  if w.onTheMap(l):
    w.dirt[w.idx(l)] = val

func hasTrap*(w: World, l: Loc, team: Team): bool =
  w.onTheMap(l) and w.trapAt[ord(team)][w.idx(l)] != nil

func getTrap*(w: World, l: Loc, team: Team): Trap =
  if not w.onTheMap(l): nil else: w.trapAt[ord(team)][w.idx(l)]

func hasRatTrap*(w: World, l: Loc, team: Team): bool =
  let t = w.getTrap(l, team)
  t != nil and t.kind == ttRatTrap

func hasCatTrap*(w: World, l: Loc, team: Team): bool =
  let t = w.getTrap(l, team)
  t != nil and t.kind == ttCatTrap

func trapCount*(w: World, kind: TrapType, team: Team): int =
  w.trapCounts[kind][ord(team)]

func opponent*(t: Team): Team =
  case t
  of teamA: teamB
  of teamB: teamA
  of teamNeutral: teamNeutral

# ---------------------------------------------------------------------------
#  Robot geometry
# ---------------------------------------------------------------------------

func usesBottomLeft*(u: UnitType): bool = UnitSpecs[u].size mod 2 == 0

proc allRatLocations*(w: World, r: Robot): seq[Loc] =
  ## `InternalRobot.getAllRatLocations` — note `y - j`, and the chirality
  ## reversal of the two coordinate lists.
  let size = UnitSpecs[r.unit].size
  var xs, ys: seq[int]
  for i in -((size - 1) div 2) .. (size div 2):
    xs.add(i)
  for j in -((size - 1) div 2) .. (size div 2):
    ys.add(j)
  if r.chirality == 1:
    case w.map.symmetry
    of symHorizontal: ys.reverse()
    of symVertical: xs.reverse()
    of symRotational:
      xs.reverse()
      ys.reverse()
  result = newSeqOfCap[Loc](size * size)
  for i in xs:
    for j in ys:
      result.add(loc(r.loc.x + i, r.loc.y - j))

func catCornerByChirality*(w: World, r: Robot): Loc =
  ## `InternalRobot.getCatCornerByChirality`.
  if r.chirality == 0:
    r.loc
  else:
    case w.map.symmetry
    of symVertical: r.loc + dEast
    of symHorizontal: r.loc + dNorth
    of symRotational: r.loc + dNortheast

proc allCatLocations*(w: World, r: Robot): seq[Loc] =
  ## `InternalRobot.getAllCatLocationsByChirality` — a four-step walk around
  ## the 2x2, whose ORDER is what `canPounce` tries corners in.
  var startingCorner = w.catCornerByChirality(r)
  var rotateDir =
    if r.chirality == 0: dNorth
    else:
      case w.map.symmetry
      of symVertical: dNorth
      of symHorizontal: dSouth
      of symRotational: dWest
  result = newSeq[Loc](4)
  for i in 0 ..< 4:
    result[i] = startingCorner
    startingCorner = startingCorner + rotateDir
    if r.chirality == 0:
      rotateDir = rotateDir.rotateRight().rotateRight()
    else:
      rotateDir = rotateDir.rotateLeft().rotateLeft()

proc allPartLocations*(w: World, r: Robot): seq[Loc] =
  if r.unit == utCat: w.allCatLocations(r) else: w.allRatLocations(r)

func visionRadiusSquared*(r: Robot): int =
  UnitSpecs[r.unit].visionConeRadiusSquared

func visionConeAngle*(r: Robot): int = UnitSpecs[r.unit].visionConeAngle

func canSenseLocation*(r: Robot, toSense: Loc): bool =
  r.loc.isWithinDistanceSquared(toSense, r.visionRadiusSquared, r.dir,
    float64(r.visionConeAngle), r.unit.usesBottomLeft)

func canActCooldown*(r: Robot): bool = r.actionCooldown < CooldownLimit
func canMoveCooldown*(r: Robot): bool = r.movementCooldown < CooldownLimit
func canTurnCooldown*(r: Robot): bool = r.turningCooldown < CooldownLimit
func isCarryingRobot*(r: Robot): bool = r.carrying != nil
func isGrabbedByRobot*(r: Robot): bool = r.grabbedBy != nil

# ---------------------------------------------------------------------------
#  Location enumeration (ORDER IS WIRE FORMAT for sensing)
# ---------------------------------------------------------------------------

proc allLocationsInCone*(
  w: World, center: Loc, lookDirection: Dir, angle: float64,
  radiusSquared: int, chirality: int
): seq[Loc] =
  ## `GameWorld.getAllLocationsWithinConeRadiusSquaredWithoutMap`. The x/y
  ## sweep is REVERSED by chirality and symmetry, and everything that senses
  ## inherits that order.
  let ceiledRadius = int(ceil(sqrt(float64(radiusSquared)))) + 1
  let
    minX = max(center.x - ceiledRadius, 0)
    minY = max(center.y - ceiledRadius, 0)
    maxX = min(center.x + ceiledRadius, w.width - 1)
    maxY = min(center.y + ceiledRadius, w.height - 1)
  var xs, ys: seq[int]
  for x in minX .. maxX: xs.add(x)
  for y in minY .. maxY: ys.add(y)
  if chirality == 1:
    case w.map.symmetry
    of symHorizontal: ys.reverse()
    of symVertical: xs.reverse()
    of symRotational:
      xs.reverse()
      ys.reverse()
  for x in xs:
    for y in ys:
      let l = loc(x, y)
      if center.isWithinDistanceSquared(l, radiusSquared, lookDirection, angle):
        result.add(l)

proc allLocationsWithinRadiusSquared*(
  w: World, center: Loc, radiusSquared, chirality: int
): seq[Loc] =
  w.allLocationsInCone(center, dCenter, 360.0, radiusSquared, chirality)

# ---------------------------------------------------------------------------
#  BFS (lazily materialised per target; a pure function of the wall layout)
# ---------------------------------------------------------------------------

proc buildBfs(w: World, target: Loc, chirality: int): seq[int8] =
  ## `GameWorld.bfsFromTarget` for one target. Entry `i` is the direction a
  ## robot at tile `i` should step to approach `target`, or -1 for
  ## unreachable. `dCenter` marks the target itself.
  let n = w.width * w.height
  result = newSeq[int8](n)
  for i in 0 ..< n:
    result[i] = -1
  var queue = @[target]
  var head = 0
  result[w.idx(target)] = int8(ord(dCenter))
  let dirsFromCenterLoc =
    if chirality == 0: [dCenter, dNorth, dNortheast, dEast]
    else: [w.flipDirBySymmetry(dCenter), w.flipDirBySymmetry(dNorth),
           w.flipDirBySymmetry(dNortheast), w.flipDirBySymmetry(dEast)]
  while head < queue.len:
    let nextLoc = queue[head]
    inc head
    for d in BfsNeighbourDirs:
      let useDir = if chirality == 1: w.flipDirBySymmetry(d) else: d
      let neighbor = nextLoc + useDir
      if w.onTheMap(neighbor) and result[w.idx(neighbor)] >= 0:
        continue
      var validPath = true
      for dirFromCenter in dirsFromCenterLoc:
        let neighborCorner = neighbor + dirFromCenter
        if not w.onTheMap(neighborCorner) or w.getWall(neighborCorner):
          validPath = false
          break
      if validPath:
        result[w.idx(neighbor)] = int8(ord(useDir.opposite()))
        queue.add(neighbor)

proc getBfsDir*(w: World, fromLoc, toLoc: Loc, chirality: int): Dir =
  ## `GameWorld.getBfsDir`. Returns `dCenter` where the engine returns null —
  ## every call site treats null and CENTER identically.
  if not w.onTheMap(fromLoc) or not w.onTheMap(toLoc):
    return dCenter
  let key = w.idx(toLoc) * 2 + chirality
  if key notin w.bfsCache:
    w.bfsCache[key] = w.buildBfs(toLoc, chirality)
  let v = w.bfsCache[key][w.idx(fromLoc)]
  if v < 0: dCenter else: Dir(v)

# ---------------------------------------------------------------------------
#  Robot bookkeeping
# ---------------------------------------------------------------------------

proc addRobotAt(w: World, l: Loc, r: Robot) =
  if w.onTheMap(l): w.occupant[w.idx(l)] = r

proc removeRobotAt(w: World, l: Loc) =
  if w.onTheMap(l): w.occupant[w.idx(l)] = nil

proc addFlyingAt(w: World, l: Loc, r: Robot) =
  if w.onTheMap(l): w.flying[w.idx(l)] = r

proc removeFlyingAt(w: World, l: Loc) =
  if w.onTheMap(l): w.flying[w.idx(l)] = nil

iterator liveRobots*(w: World): Robot =
  ## Every live body in SPAWN ORDER (`ObjectInfo.dynamicBodyExecOrder`). The
  ## only sanctioned way to walk the roster: a `Table` iteration order is an
  ## implementation detail and a sim that depends on one is not deterministic
  ## in the sense the hash chain claims.
  ## Mutation-safe: a body destroyed inside the loop shifts the list left,
  ## so the cursor only advances when the entry it just yielded is still
  ## where it was.
  var i = 0
  while i < w.execOrder.len:
    let id = w.execOrder[i]
    let r = w.robotsById.getOrDefault(id)
    if r != nil:
      yield r
    if i < w.execOrder.len and w.execOrder[i] == id:
      inc i

proc emit*(w: World, kind: string, a = 0, b = 0, c = 0, s = "") =
  w.events.add((round: w.currentRound, kind: kind, a: a, b: b, c: c, s: s))

proc mixHash*(w: World, v: int) =
  ## The per-round hash chain (`coworld-ctf`'s `gameHash` discipline). The
  ## viewer re-derives every round and compares, exposing `bc_mismatch_round`.
  w.hashChain = (w.hashChain xor uint64(v and 0xFFFFFFFF)) *
    0x100000001B3'u64

proc backstab*(w: World, by: Team, trigger: string) =
  if w.isCooperation:
    w.isCooperation = false
    w.backstabRound = w.currentRound
    w.backstabber = by
    w.hasBackstabber = true
    w.backstabTrigger = trigger
    w.emit("backstab", ord(by), w.currentRound, 0, trigger)

func roundsSinceBackstab*(w: World): int =
  if w.isCooperation: 0 else: w.currentRound - w.backstabRound

func catTrapsAllowed*(w: World, team: Team): bool =
  w.isCooperation or (w.roundsSinceBackstab() <= CatTrapRoundsAfterBackstab and
    w.backstabber != team)

proc setWinner*(w: World, t: Team, d: DominationFactor) =
  w.winner = t
  w.hasWinner = true
  w.domination = d

# --- the tiebreak ladder ---------------------------------------------------

proc setWinnerIfMorePoints*(w: World): bool =
  ## `GameWorld.setWinnerIfMorePoints`. The shares are narrowed through
  ## FLOAT32 before the weighted sum and the sum is TRUNCATED by the `(int)`
  ## cast — both pinned by `tests/test_scoring.nim`.
  let
    catWeight = if w.isCooperation: 0.5 else: 0.3
    kingWeight = if w.isCooperation: 0.3 else: 0.5
    cheeseWeight = 0.2
    totalKings = w.teamInfo.numRatKings[0] + w.teamInfo.numRatKings[1]
    totalCheese = w.teamInfo.cheeseTransferred[0] + w.teamInfo.cheeseTransferred[1]
    totalCatDamage = w.teamInfo.damageToCats[0] + w.teamInfo.damageToCats[1]
  var pts: array[2, int]
  for t in 0 .. 1:
    let
      pKings = if totalKings != 0:
        float32(w.teamInfo.numRatKings[t]) / float32(totalKings) else: 0.0'f32
      pCheese = if totalCheese != 0:
        float32(w.teamInfo.cheeseTransferred[t]) / float32(totalCheese) else: 0.0'f32
      pCat = if totalCatDamage != 0:
        float32(w.teamInfo.damageToCats[t]) / float32(totalCatDamage) else: 0.0'f32
    pts[t] = int(catWeight * 100.0 * float64(pCat) +
      kingWeight * 100.0 * float64(pKings) +
      cheeseWeight * 100.0 * float64(pCheese))
    w.teamInfo.points[t] += pts[t]
  if pts[0] > pts[1]:
    w.setWinner(teamA, dfMorePoints)
    return true
  elif pts[0] < pts[1]:
    w.setWinner(teamB, dfMorePoints)
    return true
  false

proc gamePoints*(w: World): array[2, int] =
  ## The same arithmetic as `setWinnerIfMorePoints`, WITHOUT the side effects.
  ## `cooperation_at_end` comes from the live cooperation flag the engine
  ## scored with, never from the win type: a kill-all-kings win after a
  ## backstab still records `RATKING_DESTROYED`.
  let
    catWeight = if w.isCooperation: 0.5 else: 0.3
    kingWeight = if w.isCooperation: 0.3 else: 0.5
    totalKings = w.teamInfo.numRatKings[0] + w.teamInfo.numRatKings[1]
    totalCheese = w.teamInfo.cheeseTransferred[0] + w.teamInfo.cheeseTransferred[1]
    totalCatDamage = w.teamInfo.damageToCats[0] + w.teamInfo.damageToCats[1]
  for t in 0 .. 1:
    let
      pKings = if totalKings != 0:
        float32(w.teamInfo.numRatKings[t]) / float32(totalKings) else: 0.0'f32
      pCheese = if totalCheese != 0:
        float32(w.teamInfo.cheeseTransferred[t]) / float32(totalCheese) else: 0.0'f32
      pCat = if totalCatDamage != 0:
        float32(w.teamInfo.damageToCats[t]) / float32(totalCatDamage) else: 0.0'f32
    result[t] = int(catWeight * 100.0 * float64(pCat) +
      kingWeight * 100.0 * float64(pKings) +
      0.2 * 100.0 * float64(pCheese))

proc setWinnerIfMoreCheese*(w: World): bool =
  if w.teamInfo.globalCheese[0] > w.teamInfo.globalCheese[1]:
    w.setWinner(teamA, dfMoreCheese)
    true
  elif w.teamInfo.globalCheese[1] > w.teamInfo.globalCheese[0]:
    w.setWinner(teamB, dfMoreCheese)
    true
  else:
    false

proc setWinnerIfMoreRatsAlive*(w: World): bool =
  let
    a = w.teamInfo.numBabyRats[0] + w.teamInfo.numRatKings[0]
    b = w.teamInfo.numBabyRats[1] + w.teamInfo.numRatKings[1]
  if a > b:
    w.setWinner(teamA, dfMoreRobotsAlive)
    true
  elif b > a:
    w.setWinner(teamB, dfMoreRobotsAlive)
    true
  else:
    false

proc setWinnerArbitrary*(w: World) =
  ## The engine calls `Math.random()` here. A world RNG draw replaces it so
  ## the match stays reproducible; it is reachable only on an exact three-way
  ## tie and is listed in docs/RULES.md §Divergences.
  w.setWinner(if w.rand.nextDouble() < 0.5: teamA else: teamB, dfDubious)

proc setWinnerIfKilledAllRatKings*(w: World): bool =
  if w.teamInfo.numRatKings[0] == 0:
    w.setWinner(teamB, dfKillAllRatKings)
    true
  elif w.teamInfo.numRatKings[1] == 0:
    w.setWinner(teamA, dfKillAllRatKings)
    true
  else:
    false

proc setWinnerIfAllCatsDead*(w: World): bool =
  if w.numCats == 0 and w.isCooperation:
    if w.setWinnerIfMorePoints(): return true
    if w.setWinnerIfMoreCheese(): return true
    if w.setWinnerIfMoreRatsAlive(): return true
    w.setWinnerArbitrary()
    return true
  false

proc checkWin(w: World) =
  ## `GameWorld.checkWin`, including its own "both teams' kings died in the
  ## same round" re-entry.
  if w.hasWinner and w.domination == dfKillAllRatKings and
      w.setWinnerIfKilledAllRatKings():
    if w.setWinnerIfMorePoints(): return
    if w.setWinnerIfMoreCheese(): return
    if w.setWinnerIfMoreRatsAlive(): return
    w.setWinnerArbitrary()
  if w.hasWinner:
    return
  if w.setWinnerIfKilledAllRatKings():
    return
  discard w.setWinnerIfAllCatsDead()

proc destroyRobot*(w: World, id: int)
proc getDropped*(w: World, r: Robot, l: Loc)
proc processTrapsAtLocation*(w: World, r: Robot, l: Loc)

proc addHealth*(w: World, r: Robot, amount: int) =
  r.health += amount
  if amount < 0 and r.unit != utCat:
    w.teamInfo.damageSuffered[ord(r.team)] += -amount
  r.health = min(r.health, UnitSpecs[r.unit].health)
  if r.health <= 0:
    w.destroyRobot(r.id)

proc addRobotCheese*(w: World, r: Robot, amount: int) =
  ## `InternalRobot.addCheese`. A king's cheese IS the team's; a rat spends
  ## its raw stash first and only then draws on the team pool.
  if r.unit == utRatKing:
    w.teamInfo.globalCheese[ord(r.team)] += amount
    return
  if r.cheese + amount >= 0:
    r.cheese += amount
  else:
    let rest = amount + r.cheese
    r.cheese = 0
    w.teamInfo.globalCheese[ord(r.team)] += rest

proc destroyRobot*(w: World, id: int) =
  var r: Robot
  if not w.robotsById.pop(id, r):
    return
  r.dead = true
  let team = r.team
  if r.unit == utBabyRat:
    w.teamInfo.numBabyRats[ord(team)] -= 1
  elif r.unit == utRatKing:
    w.teamInfo.numRatKings[ord(team)] -= 1
  elif r.unit == utCat:
    w.numCats -= 1
  for l in w.allPartLocations(r):
    if w.onTheMap(l):
      if w.occupant[w.idx(l)] == r: w.occupant[w.idx(l)] = nil
      if w.flying[w.idx(l)] == r: w.flying[w.idx(l)] = nil
  if r.isCarryingRobot:
    let carried = r.carrying
    r.carrying = nil
    w.getDropped(carried, r.loc)
  if r.isGrabbedByRobot:
    let carrier = r.grabbedBy
    r.grabbedBy = nil
    if carrier != nil and carrier.carrying == r:
      carrier.carrying = nil
  if r.cheese > 0:
    w.addCheese(r.loc, r.cheese)
  let i = w.execOrder.find(id)
  if i >= 0: w.execOrder.delete(i)
  w.emit("died", id, ord(team), ord(r.unit))
  if r.unit == utRatKing and w.teamInfo.numRatKings[ord(team)] == 0:
    w.checkWin()
  elif w.isCooperation and r.unit == utCat and w.numCats == 0:
    w.checkWin()

proc spawnRobot*(w: World, id: int, unit: UnitType, l: Loc, dir: Dir,
                 chirality: int, team: Team): int {.discardable.} =
  var d = dir
  if d == dCenter:
    let mapCenter = loc((w.width - 1) div 2, (w.height - 1) div 2)
    d = l.directionTo(mapCenter)
  let r = Robot(
    id: id, team: team, unit: unit, loc: l, dir: d, chirality: chirality,
    health: UnitSpecs[unit].health,
    actionCooldown: CooldownLimit,
    movementCooldown: CooldownLimit,
    turningCooldown: CooldownLimit,
    turnsSinceThrownOrDropped: GameMaxNumberOfRounds,
    lastGrabberId: -1,
    thrownDir: dCenter,
    catState: csExplore,
    catTargetId: -1
  )
  if unit == utCat:
    for wpIdx in w.map.catWaypointVecs[w.map.catWaypointIds.find(id)]:
      r.catWaypoints.add(w.indexToLoc(wpIdx))
    if r.catWaypoints.len > 0:
      r.catTargetLoc = r.catWaypoints[0]
      r.catTargetLocValid = true
  for pl in w.allPartLocations(r):
    w.addRobotAt(pl, r)
  w.robotsById[id] = r
  w.execOrder.add(id)
  if unit == utBabyRat:
    w.teamInfo.numBabyRats[ord(team)] += 1
  elif unit == utRatKing:
    w.teamInfo.numRatKings[ord(team)] += 1
  elif unit == utCat:
    w.numCats += 1
  id

proc spawnRobot*(w: World, unit: UnitType, l: Loc, dir: Dir,
                 chirality: int, team: Team): int {.discardable.} =
  w.spawnRobot(w.idGen.nextId(), unit, l, dir, chirality, team)

# ---------------------------------------------------------------------------
#  Traps
# ---------------------------------------------------------------------------

proc placeTrap*(w: World, l: Loc, trap: Trap) =
  w.trapAt[ord(trap.team)][w.idx(l)] = trap
  for adj in w.allLocationsWithinRadiusSquared(
      l, TrapSpecs[trap.kind].triggerRadiusSquared, 0):
    w.trapTriggers[w.idx(adj)].add(trap)
  w.trapCounts[trap.kind][ord(trap.team)] += 1
  w.teamInfo.trapsPlaced[ord(trap.team)] += 1

proc removeTrap*(w: World, l: Loc, team: Team) =
  let trap = w.trapAt[ord(team)][w.idx(l)]
  if trap == nil: return
  w.trapCounts[trap.kind][ord(team)] -= 1
  w.trapAt[ord(team)][w.idx(l)] = nil
  for adj in w.allLocationsWithinRadiusSquared(
      l, TrapSpecs[trap.kind].triggerRadiusSquared, 0):
    let i = w.trapTriggers[w.idx(adj)].find(trap)
    if i >= 0: w.trapTriggers[w.idx(adj)].delete(i)

proc triggerTrap*(w: World, trap: Trap, r: Robot) =
  r.movementCooldown = TrapSpecs[trap.kind].stunTime
  if trap.kind == ttCatTrap and r.unit == utCat and r.health > 0:
    w.teamInfo.damageToCats[ord(trap.team)] +=
      min(TrapSpecs[trap.kind].damage, r.health)
  if trap.kind != ttCatTrap:
    w.backstab(r.team.opponent(), "trap")
  w.emit("trap_trigger", trap.id, ord(r.team), ord(trap.kind))
  w.removeTrap(trap.loc, trap.team)
  w.addHealth(r, -TrapSpecs[trap.kind].damage)

proc processTrapsAtLocation*(w: World, r: Robot, l: Loc) =
  if not w.onTheMap(l): return
  var j = w.trapTriggers[w.idx(l)].len - 1
  while j >= 0:
    if j >= w.trapTriggers[w.idx(l)].len:
      dec j
      continue
    let trap = w.trapTriggers[w.idx(l)][j]
    let wrongTrapType =
      ((r.unit == utBabyRat or r.unit == utRatKing) and trap.kind == ttCatTrap) or
      (r.unit == utCat and trap.kind == ttRatTrap)
    if trap.team != r.team and not wrongTrapType:
      w.triggerTrap(trap, r)
    dec j

# ---------------------------------------------------------------------------
#  Cooldowns
# ---------------------------------------------------------------------------

proc addActionCooldown*(w: World, r: Robot, amount: int) =
  ## `(int)CARRY_COOLDOWN_MULTIPLIER` is 1 in Java — the cast happens BEFORE
  ## the multiply, so carrying costs nothing extra here. Ported as written.
  var cooldownUp = amount * (if r.carrying != nil: int(CarryCooldownMultiplier) else: 1)
  if r.unit == utBabyRat:
    cooldownUp = int(float64(cooldownUp) *
      (1.0 + float64(r.cheese) * CheeseCooldownPenalty))
  r.actionCooldown += cooldownUp

proc addMovementCooldown*(w: World, r: Robot, d: Dir) =
  var movementCooldown = UnitSpecs[r.unit].movementCooldown
  if r.unit == utBabyRat and r.dir != d:
    movementCooldown = MoveStrafeCooldown
  movementCooldown *= (if r.carrying != nil: int(CarryCooldownMultiplier) else: 1)
  if r.unit == utBabyRat:
    movementCooldown = int(float64(movementCooldown) *
      (1.0 + float64(r.cheese) * CheeseCooldownPenalty))
  r.movementCooldown += movementCooldown

proc addTurningCooldown*(w: World, r: Robot) =
  r.turningCooldown += TurningCooldown *
    (if r.carrying != nil: int(CarryCooldownMultiplier) else: 1)

# ---------------------------------------------------------------------------
#  Sensing
# ---------------------------------------------------------------------------

proc senseNearbyRobots*(w: World, r: Robot, radiusSquared = -1,
                        team = teamNeutral, filterTeam = false): seq[Robot] =
  ## `RobotControllerImpl.senseNearbyRobots`, order preserved.
  let actual =
    if radiusSquared == -1: r.visionRadiusSquared
    else: min(radiusSquared, r.visionRadiusSquared)
  var seen: seq[int]
  for l in w.allLocationsWithinRadiusSquared(r.loc, actual, r.chirality):
    let other = w.getRobot(l)
    if other == nil: continue
    if filterTeam and other.team != team: continue
    if other.id in seen: continue
    if other.id == r.id: continue
    var canSensePart = false
    for part in w.allPartLocations(other):
      if r.canSenseLocation(part) and
          r.loc.isWithinDistanceSquared(part, actual, dCenter, 360.0):
        canSensePart = true
        break
    if not canSensePart: continue
    result.add(other)
    seen.add(other.id)

# ---------------------------------------------------------------------------
#  Actions
# ---------------------------------------------------------------------------

proc canActLocation*(w: World, r: Robot, l: Loc, maxRadiusSquared: float32): bool =
  if not w.onTheMap(l): return false
  if not r.canSenseLocation(l): return false
  let distance =
    if r.unit.usesBottomLeft: r.loc.bottomLeftDistanceSquaredTo(l)
    else: float32(r.loc.distanceSquaredTo(l))
  distance <= maxRadiusSquared

proc canMove*(w: World, r: Robot, d: Dir): bool =
  if not r.canMoveCooldown or r.isThrown or r.isGrabbedByRobot: return false
  for cur in w.allPartLocations(r):
    let l = cur + d
    if not w.onTheMap(l): return false
    let occupying = w.getRobot(l)
    if occupying != nil and occupying.id != r.id and
        not (occupying.unit == utBabyRat and r.unit == utCat):
      return false
    if not w.isPassable(l): return false
  true

proc translateLocation(w: World, r: Robot, dx, dy: int) =
  let beforeLocs = w.allPartLocations(r)
  for pl in beforeLocs:
    w.removeRobotAt(pl)
  for pl in beforeLocs:
    w.addRobotAt(pl.translate(dx, dy), r)
  r.loc = r.loc.translate(dx, dy)
  if r.unit != utCat and r.isCarryingRobot:
    r.carrying.loc = r.loc

proc move*(w: World, r: Robot, d: Dir) =
  ## `RobotControllerImpl.move`. Caller must have checked `canMove`.
  let curLocs = w.allPartLocations(r)
  for cur in curLocs:
    let newLoc = cur + d
    let crushed = w.getRobot(newLoc)
    if crushed != nil and crushed.id != r.id and r.unit == utCat and
        crushed.unit == utBabyRat:
      if crushed.isCarryingRobot:
        let carried = crushed.carrying
        w.addHealth(carried, -carried.health)
      w.addHealth(crushed, -crushed.health)
  if r.dead: return
  w.translateLocation(r, d.dx, d.dy)
  for cur in curLocs:
    w.processTrapsAtLocation(r, cur + d)
    if r.dead: return
  w.addMovementCooldown(r, d)

proc canTurn*(w: World, r: Robot): bool =
  r.canTurnCooldown and not r.isThrown and not r.isGrabbedByRobot

proc turn*(w: World, r: Robot, d: Dir) =
  if d == dCenter: return
  r.dir = d
  w.addTurningCooldown(r)

proc bite(w: World, r: Robot, l: Loc, cheeseConsumed: int) =
  let distSq = r.loc.distanceSquaredTo(l)
  let limit = if r.unit == utRatKing: RatKingAttackDistanceSquared
              else: AttackDistanceSquared
  if distSq == 0 or distSq > limit: return
  if r.loc.directionTo(l) == dCenter: return
  if r.dir == dCenter: return
  let target = w.getRobot(l)
  if target == nil: return
  if r.team == target.team: return
  var damage = RatBiteDamage
  if cheeseConsumed > 0:
    w.addRobotCheese(r, -cheeseConsumed)
    damage += int(ceil(sqrt(float64(cheeseConsumed))))
  w.emit("bite", r.id, target.id, damage)
  if target.unit == utCat:
    w.teamInfo.damageToCats[ord(r.team)] += min(damage, target.health)
  let targetWasCat = target.unit == utCat
  w.addHealth(target, -damage)
  if not targetWasCat:
    w.backstab(r.team, "bite")

proc scratch(w: World, r: Robot, l: Loc) =
  let target = w.getRobot(l)
  if target == nil: return
  if r.team == target.team: return
  w.addHealth(target, -CatScratchDamage)
  w.emit("scratch", r.id, target.id, CatScratchDamage)

proc attackAt*(w: World, r: Robot, l: Loc, cheese = -1) =
  case r.unit
  of utBabyRat, utRatKing: w.bite(r, l, cheese)
  of utCat: w.scratch(r, l)

proc canAttack*(w: World, r: Robot, l: Loc, cheeseConsumed = 0): bool =
  if not r.canActCooldown or r.isThrown or r.isGrabbedByRobot: return false
  if not w.canActLocation(r, l, float32(r.visionRadiusSquared)): return false
  if not w.isPassable(l): return false
  let target = w.getRobot(l)
  if target == nil: return false
  if target.team == r.team: return false
  if r.unit == utCat:
    return true
  let distSq = r.loc.distanceSquaredTo(l)
  let limit = if r.unit == utRatKing: RatKingAttackDistanceSquared
              else: AttackDistanceSquared
  if distSq == 0 or distSq > limit: return false
  if r.cheese + w.teamInfo.globalCheese[ord(r.team)] < cheeseConsumed: return false
  if cheeseConsumed < 0: return false
  true

proc attack*(w: World, r: Robot, l: Loc, cheese = 0) =
  w.addActionCooldown(r, UnitSpecs[r.unit].actionCooldown)
  w.attackAt(r, l, if cheese == 0: -1 else: cheese)

proc canRemoveDirt*(w: World, r: Robot, l: Loc): bool =
  if not r.canActCooldown or r.isThrown or r.isGrabbedByRobot: return false
  let radius =
    if r.unit == utRatKing: float32(RatKingBuildDistanceSquared)
    elif r.unit == utCat: CatBuildDistanceSquared
    else: float32(BuildDistanceSquared)
  if not w.canActLocation(r, l, radius): return false
  if (r.unit == utBabyRat or r.unit == utRatKing) and
      r.cheese + w.teamInfo.globalCheese[ord(r.team)] < DigDirtCheeseCost:
    return false
  w.getDirt(l)

proc removeDirt*(w: World, r: Robot, l: Loc) =
  w.setDirt(l, false)
  if r.team != teamNeutral:
    w.teamInfo.dirtCounts[ord(r.team)] += 1
  if r.unit == utBabyRat or r.unit == utRatKing:
    w.addRobotCheese(r, -DigDirtCheeseCost)
  w.addActionCooldown(r, DigCooldown)
  w.emit("remove_dirt", w.idx(l))

proc canPlaceDirt*(w: World, r: Robot, l: Loc): bool =
  if not r.canActCooldown or r.isThrown or r.isGrabbedByRobot: return false
  let radius =
    if r.unit == utRatKing: float32(RatKingBuildDistanceSquared)
    elif r.unit == utCat: CatBuildDistanceSquared
    else: float32(BuildDistanceSquared)
  if not w.canActLocation(r, l, radius): return false
  if r.team == teamNeutral or w.teamInfo.dirtCounts[ord(r.team)] <= 0: return false
  if w.getWall(l): return false
  if w.getRobot(l) != nil: return false
  if w.getDirt(l): return false
  if w.hasCheeseMine(l): return false
  true

proc placeDirt*(w: World, r: Robot, l: Loc) =
  w.setDirt(l, true)
  w.teamInfo.dirtCounts[ord(r.team)] -= 1
  w.teamInfo.dirtPlaced[ord(r.team)] += 1
  w.addRobotCheese(r, -PlaceDirtCheeseCost)
  w.addActionCooldown(r, DigCooldown)
  w.emit("place_dirt", w.idx(l))

proc canPlaceTrap*(w: World, r: Robot, l: Loc, kind: TrapType): bool =
  if not r.canActCooldown or r.isThrown or r.isGrabbedByRobot: return false
  let radius = if r.unit == utRatKing: float32(RatKingBuildDistanceSquared)
               else: float32(BuildDistanceSquared)
  if not w.canActLocation(r, l, radius): return false
  if kind == ttCatTrap and not w.catTrapsAllowed(r.team): return false
  if not w.isPassable(l): return false
  if w.getRobot(l) != nil: return false
  if w.hasTrap(l, r.team): return false
  if w.trapCount(kind, r.team) >= TrapSpecs[kind].maxCount: return false
  if r.cheese + w.teamInfo.globalCheese[ord(r.team)] < TrapSpecs[kind].buildCost:
    return false
  if w.hasCheeseMine(l): return false
  true

proc buildTrap*(w: World, r: Robot, l: Loc, kind: TrapType) =
  w.addActionCooldown(r, TrapSpecs[kind].actionCooldown)
  w.addRobotCheese(r, -TrapSpecs[kind].buildCost)
  let trapId = w.idGen.nextId()
  w.placeTrap(l, Trap(id: trapId, kind: kind, loc: l, team: r.team))
  w.emit("place_trap", trapId, w.idx(l), ord(kind))

proc canPickUpCheese*(w: World, r: Robot, l: Loc): bool =
  if not w.canActLocation(r, l, float32(CheesePickUpRadiusSquared)): return false
  if w.getCheeseAmount(l) <= 0: return false
  if r.unit != utBabyRat and r.unit != utRatKing: return false
  if r.isThrown: return false
  true

proc pickUpCheese*(w: World, r: Robot, l: Loc) =
  let amount = w.getCheeseAmount(l)
  w.addCheese(l, -amount)
  w.addRobotCheese(r, amount)
  w.teamInfo.cheeseCollected[ord(r.team)] += amount
  w.emit("pickup_cheese", w.idx(l), amount)
  if r.unit == utRatKing:
    w.teamInfo.cheeseTransferred[ord(r.team)] += amount

proc currentRatCost*(w: World, team: Team): int =
  BuildRobotBaseCost + BuildRobotCostIncrease *
    (w.teamInfo.numBabyRats[ord(team)] div NumRobotsForCostIncrease)

proc canBuildRat*(w: World, r: Robot, l: Loc): bool =
  if not w.canActLocation(r, l, float32(BuildRobotRadiusSquared)): return false
  if not r.canActCooldown or r.isThrown or r.isGrabbedByRobot: return false
  if r.unit != utRatKing: return false
  if w.teamInfo.globalCheese[ord(r.team)] < w.currentRatCost(r.team): return false
  if w.getRobot(l) != nil: return false
  if not w.isPassable(l): return false
  true

proc buildRat*(w: World, r: Robot, l: Loc) =
  let cost = w.currentRatCost(r.team)
  w.addRobotCheese(r, -cost)
  w.addActionCooldown(r, BuildRobotCooldown)
  w.spawnRobot(utBabyRat, l, r.dir, r.chirality, r.team)
  w.teamInfo.ratsBuilt[ord(r.team)] += 1
  let spawned = w.getRobot(l)
  if spawned != nil:
    w.emit("spawn", spawned.id, w.idx(l), ord(r.team))

proc canTransferCheese*(w: World, r: Robot, l: Loc, amount: int): bool =
  if not w.canActLocation(r, l, float32(CheeseTransferRadiusSquared)): return false
  if not r.canActCooldown or r.isThrown or r.isGrabbedByRobot: return false
  let target = w.getRobot(l)
  if target == nil: return false
  if l == r.loc: return false
  if amount == 0: return false
  if target.team != r.team: return false
  if r.unit != utBabyRat: return false
  if target.unit != utRatKing: return false
  if amount < 0: return false
  if amount > r.cheese: return false
  true

proc transferCheese*(w: World, r: Robot, l: Loc, amount: int) =
  w.addRobotCheese(r, -amount)
  w.teamInfo.globalCheese[ord(r.team)] += amount
  w.teamInfo.cheeseTransferred[ord(r.team)] += amount
  w.addActionCooldown(r, CheeseTransferCooldown)
  w.emit("transfer_cheese", r.id, amount)

# --- ratnap / throw --------------------------------------------------------

proc getDropped*(w: World, r: Robot, l: Loc) =
  ## `InternalRobot.getDropped`. The engine THROWS when the tile is unusable;
  ## a dropped rat with nowhere to go is a sim invariant break, so the caller
  ## checks first and this degrades to "dropped on the carrier's tile".
  r.turnsSinceThrownOrDropped = 0
  r.grabbedBy = nil
  r.remainingCarriedDuration = 0
  r.loc = l
  if r.health > 0:
    w.addRobotAt(r.loc, r)
    w.processTrapsAtLocation(r, r.loc)
  else:
    w.destroyRobot(r.id)

proc hitGround(w: World, r: Robot) =
  r.turnsSinceThrownOrDropped = 0
  r.thrownDir = dCenter
  r.isThrown = false
  r.remainingThrowDuration = 0
  w.addHealth(r, -ThrowDamage)
  w.removeFlyingAt(r.loc)
  if r.health > 0:
    w.addRobotAt(r.loc, r)
    w.processTrapsAtLocation(r, r.loc)
  else:
    w.destroyRobot(r.id)
  if r.dead: return
  r.movementCooldown += HitGroundCooldown
  r.actionCooldown += HitGroundCooldown
  r.turningCooldown += HitGroundCooldown

proc hitTarget(w: World, r: Robot, isSecondMove: bool) =
  let damage = ThrowDamage + ThrowDamagePerTile *
    (TilesFlownPerTurn * r.remainingThrowDuration + (if isSecondMove: 0 else: 1))
  let ahead = r.loc + r.thrownDir
  let blocker = w.getRobot(ahead)
  if blocker != nil:
    w.addHealth(blocker, -damage)
  else:
    let flyer = w.getFlyingRobot(ahead)
    if flyer != nil:
      flyer.remainingThrowDuration = 1
  r.thrownDir = dCenter
  r.isThrown = false
  r.remainingThrowDuration = 0
  w.addHealth(r, -damage)
  w.removeFlyingAt(r.loc)
  if r.health > 0:
    w.addRobotAt(r.loc, r)
    w.processTrapsAtLocation(r, r.loc)
  else:
    w.destroyRobot(r.id)
  if r.dead: return
  r.movementCooldown += HitTargetCooldown
  r.actionCooldown += HitTargetCooldown
  r.turningCooldown += HitTargetCooldown

proc travelFlying*(w: World, r: Robot, isSecondMove: bool) =
  if not r.isThrown or r.health == 0: return
  let newLoc = r.loc + r.thrownDir
  if not w.onTheMap(newLoc):
    w.hitGround(r)
    return
  let there = w.getRobot(newLoc)
  if there != nil and there.unit == utCat:
    ## Cat feeding: the rat dies and the cat sleeps.
    w.removeFlyingAt(r.loc)
    w.emit("cat_fed", there.id, r.id, ord(r.team))
    w.addHealth(r, -r.health)
    there.sleepTimeRemaining = CatSleepTime
    return
  elif there != nil or not w.isPassable(newLoc):
    w.hitTarget(r, isSecondMove)
    return
  else:
    w.removeFlyingAt(r.loc)
    w.addFlyingAt(newLoc, r)
  r.loc = newLoc

proc getGrabbed(w: World, r: Robot, grabber: Robot) =
  r.turnsSinceThrownOrDropped = 0
  r.grabbedBy = grabber
  r.lastGrabberId = grabber.id
  w.removeRobotAt(r.loc)
  if r.isCarryingRobot:
    let carried = r.carrying
    r.carrying = nil
    w.getDropped(carried, r.loc)
  r.loc = grabber.loc
  r.remainingCarriedDuration = MaxCarryDuration

proc canCarryRat*(w: World, r: Robot, l: Loc): bool =
  if not w.canActLocation(r, l, 2.0'f32): return false
  if not r.canActCooldown or r.isThrown or r.isGrabbedByRobot: return false
  if r.unit != utBabyRat: return false
  if r.isCarryingRobot: return false
  if not l.isAdjacentTo(r.loc) and r.loc != l: return false
  if not r.canSenseLocation(l): return false
  let target = w.getRobot(l)
  if target == nil: return false
  if target.unit != utBabyRat: return false
  if target.isThrown: return false
  if target.id == r.id: return false
  if target.team != r.team and target.lastGrabberId == r.id and
      target.turnsSinceThrownOrDropped < SameRobotCarryCooldownTurns:
    return false
  if not target.canSenseLocation(r.loc): return true
  if r.team == target.team: return true
  if target.health + HealthGrabThreshold < r.health: return true
  false

proc carryRat*(w: World, r: Robot, l: Loc) =
  let target = w.getRobot(l)
  r.carrying = target
  w.getGrabbed(target, r)
  w.emit("ratnap", r.id, target.id, ord(r.team))
  if target.team != r.team:
    w.backstab(r.team, "ratnap")
  w.addActionCooldown(r, ThrowRatCooldown)

proc canThrowRat*(w: World, r: Robot): bool =
  if not r.canActCooldown or r.isThrown or r.isGrabbedByRobot: return false
  if r.unit != utBabyRat: return false
  if not r.isCarryingRobot: return false
  let nextLoc = r.loc + r.dir
  if not w.onTheMap(nextLoc): return false
  if not w.isPassable(nextLoc) or w.getRobot(nextLoc) != nil: return false
  true

proc throwRat*(w: World, r: Robot) =
  w.addActionCooldown(r, ThrowRatCooldown)
  let victim = r.carrying
  victim.turnsSinceThrownOrDropped = 0
  victim.grabbedBy = nil
  victim.remainingCarriedDuration = 0
  victim.thrownDir = r.dir
  victim.isThrown = true
  victim.remainingThrowDuration = 4
  w.hasTraveled.add(victim.id)
  w.emit("throw", r.id, victim.id, ord(r.team))
  if victim.team != r.team:
    w.backstab(r.team, "throw")
  r.carrying = nil
  w.travelFlying(victim, false)
  w.travelFlying(victim, true)

proc canBecomeRatKing*(w: World, r: Robot): bool =
  if not r.canActCooldown or r.isThrown or r.isGrabbedByRobot: return false
  if w.teamInfo.globalCheese[ord(r.team)] < RatKingUpgradeCheeseCost: return false
  let numRatKings = w.teamInfo.numRatKings[ord(r.team)]
  if numRatKings >= MaxNumberOfRatKings: return false
  if numRatKings >= MaxNumberOfRatKingsAfterCutoff and
      w.currentRound > RatKingCutoffRound: return false
  var numAllyRats = 0
  for d in AllDirs:
    let cur = r.loc + d
    if not w.onTheMap(cur): return false
    let curRobot = w.getRobot(cur)
    if curRobot != nil and curRobot.team == r.team and curRobot.unit == utBabyRat:
      inc numAllyRats
    if curRobot != nil and curRobot.unit != utBabyRat: return false
    if not w.isPassable(cur): return false
  numAllyRats >= 7

proc becomeRatKing*(w: World, r: Robot) =
  var health = 0
  for d in AllDirs:
    let cur = r.loc + d
    let currentRobot = w.getRobot(cur)
    if currentRobot != nil and r.team == currentRobot.team:
      health += currentRobot.health
    if currentRobot != nil and d != dCenter:
      w.teamInfo.globalCheese[ord(r.team)] += currentRobot.cheese
      w.addRobotCheese(currentRobot, -currentRobot.cheese)
      if currentRobot.isCarryingRobot:
        let carried = currentRobot.carrying
        w.teamInfo.globalCheese[ord(r.team)] += carried.cheese
        w.addRobotCheese(carried, -carried.cheese)
        w.addHealth(carried, -carried.health)
      w.addHealth(currentRobot, -currentRobot.health)
    w.addRobotAt(cur, r)
  if r.isCarryingRobot:
    let carried = r.carrying
    w.addHealth(carried, -carried.health)
  w.teamInfo.globalCheese[ord(r.team)] -= RatKingUpgradeCheeseCost
  health = min(health, UnitSpecs[utRatKing].health)
  w.teamInfo.globalCheese[ord(r.team)] += r.cheese
  w.addRobotCheese(r, -r.cheese)
  w.teamInfo.numBabyRats[ord(r.team)] -= 1
  r.unit = utRatKing
  r.health = health
  for d in AllDirs:
    if d != dCenter:
      w.processTrapsAtLocation(r, r.loc + d)
      if r.dead: return
  w.emit("king_built", r.id, ord(r.team), w.teamInfo.numRatKings[ord(r.team)] + 1)
  w.teamInfo.numRatKings[ord(r.team)] += 1
  w.teamInfo.kingsBuilt[ord(r.team)] += 1

# --- comms -----------------------------------------------------------------

proc squeak*(w: World, r: Robot, content: int): bool =
  if r.sentMessages >= MaxMessagesSentRobot: return false
  let message = Message(content: content, senderId: r.id,
    round: w.currentRound, source: r.loc)
  var squeaked: seq[int]
  for l in w.allLocationsWithinRadiusSquared(r.loc, SqueakRadiusSquared, 0):
    let other = w.getRobot(l)
    if other != nil and other.id != r.id and other.id notin squeaked and
        (other.unit == utCat or other.team == r.team):
      other.inbox.add(message)
      squeaked.add(other.id)
  inc r.sentMessages
  w.emit("squeak", r.id, w.idx(r.loc), content)
  true

proc writeSharedArray*(w: World, r: Robot, index, value: int) =
  if r.unit != utRatKing: return
  if index < 0 or index >= SharedArraySize: return
  if value < 0 or value > CommArrayMaxValue: return
  w.sharedArray[ord(r.team)][index] = value

proc readSharedArray*(w: World, r: Robot, index: int): int =
  if index < 0 or index >= SharedArraySize: return 0
  w.sharedArray[ord(r.team)][index]

# --- cheese mines ----------------------------------------------------------

func generationProbability*(mine: CheeseMine, currentRound: int): float64 =
  ## `CheeseMine.generationProbability`. The base is `1 - 0.01f` widened from
  ## a Java FLOAT, so it is 0.9900000095367432, not 0.99 — which decides
  ## whether a long-quiet mine fires on a given round.
  let roundsSinceLastSpawn = currentRound - mine.lastSpawnRound
  1.0 - pow(1.0 - float64(CheeseMineSpawnProbability), float64(roundsSinceLastSpawn))

proc spawnCheese(w: World, mine: CheeseMine) =
  let spawn = w.rand.nextFloat() < float32(mine.generationProbability(w.currentRound))
  if not spawn: return
  let dx = int(w.rand.nextInt(-SqCheeseSpawnRadius, SqCheeseSpawnRadius))
  let dy = int(w.rand.nextInt(-SqCheeseSpawnRadius, SqCheeseSpawnRadius))
  var ogSpawnLoc = mine.loc
  var pairedSpawnLoc = mine.pair.loc
  let pairedMine = mine.pair
  for invalidSpawns in 0 ..< 5:
    let pairDx = if w.map.symmetry == symVertical: dx else: -dx
    let pairDy = if w.map.symmetry == symHorizontal: dy else: -dy
    let cheeseX = mine.loc.x + dx
    let cheeseY = mine.loc.y + dy
    let pairedX = pairedMine.loc.x + pairDx
    let pairedY = pairedMine.loc.y + pairDy
    if cheeseX >= 0 and cheeseX < w.width and cheeseY >= 0 and cheeseY < w.height and
        pairedX >= 0 and pairedX < w.width and pairedY >= 0 and pairedY < w.height and
        not w.getWall(loc(cheeseX, cheeseY)) and
        not w.getWall(loc(pairedX, pairedY)):
      ogSpawnLoc = loc(cheeseX, cheeseY)
      pairedSpawnLoc = loc(pairedX, pairedY)
      break
  mine.lastSpawnRound = w.currentRound
  pairedMine.lastSpawnRound = w.currentRound
  w.addCheese(ogSpawnLoc, CheeseSpawnAmount)
  w.addCheese(pairedSpawnLoc, CheeseSpawnAmount)

proc runCheeseMines*(w: World) =
  if w.hasRunCheeseMines: return
  for mine in w.cheeseMines:
    w.spawnCheese(mine)
  w.hasRunCheeseMines = true

# ---------------------------------------------------------------------------
#  Turn scaffolding
# ---------------------------------------------------------------------------

proc processBeginningOfRound*(w: World) =
  inc w.currentRound
  for id in w.execOrder:
    let r = w.robotsById.getOrDefault(id)
    if r == nil: continue
    ## `cleanMessages`: drop anything older than MESSAGE_ROUND_DURATION.
    while r.inbox.len > 0 and
        r.inbox[0].round <= w.currentRound - MessageRoundDuration:
      r.inbox.delete(0)

proc swapGrabber(w: World, r: Robot) =
  let grabber = r.grabbedBy
  let dropLoc = grabber.loc
  r.carrying = grabber
  grabber.grabbedBy = r
  r.grabbedBy = nil
  grabber.carrying = nil
  grabber.loc = dropLoc
  r.loc = dropLoc
  w.removeRobotAt(dropLoc)
  w.addRobotAt(dropLoc, r)
  grabber.remainingCarriedDuration = MaxCarryDuration

proc processBeginningOfTurn*(w: World, r: Robot) =
  r.sentMessages = 0
  ## The FIRST body of the round runs every cheese mine — cheese therefore
  ## spawns inside the first robot's turn, not at round start.
  w.runCheeseMines()

  if r.unit == utBabyRat and r.isGrabbedByRobot:
    if r.grabbedBy.health <= 0:
      w.getDropped(r, r.grabbedBy.loc)
    elif r.remainingCarriedDuration == 0:
      let dropLoc = r.grabbedBy.loc + r.dir
      if w.onTheMap(dropLoc) and w.isPassable(dropLoc) and
          w.getRobot(dropLoc) == nil:
        let grabber = r.grabbedBy
        w.getDropped(r, dropLoc)
        grabber.carrying = nil
      else:
        w.swapGrabber(r)
    else:
      r.loc = r.grabbedBy.loc
      r.remainingCarriedDuration -= 1

  if r.unit == utBabyRat and r.isThrown:
    r.remainingThrowDuration -= 1
    if r.remainingThrowDuration == 0:
      w.hitGround(r)
    else:
      if r.id notin w.hasTraveled:
        w.travelFlying(r, false)
        w.travelFlying(r, true)
      if not r.dead and r.remainingThrowDuration == 1:
        w.hitGround(r)

  if r.dead: return
  let isSleepingCat = r.unit == utCat and r.sleepTimeRemaining > 0
  if not r.isGrabbedByRobot and not r.isThrown and not isSleepingCat:
    r.actionCooldown = max(0, r.actionCooldown - CooldownsPerTurn)
    r.turningCooldown = max(0, r.turningCooldown - CooldownsPerTurn)
    r.movementCooldown = max(0, r.movementCooldown - CooldownsPerTurn)
  r.opsLeft =
    case r.unit
    of utBabyRat: DecisionOpsBabyRat
    of utRatKing: DecisionOpsRatKing
    of utCat: DecisionOpsCat

func timeLimitReached*(w: World): bool = w.currentRound >= w.maxRounds

proc checkEndOfMatch*(w: World) =
  if w.timeLimitReached() and not w.hasWinner:
    if w.setWinnerIfMorePoints(): return
    if w.setWinnerIfMoreCheese(): return
    if w.setWinnerIfMoreRatsAlive(): return
    w.setWinnerArbitrary()

proc processEndOfRound*(w: World) =
  w.hasRunCheeseMines = false
  ## The seven per-team round stats the design note lists. Dirt and the two
  ## trap counts were missing until GV02: a re-derivation that diverged only
  ## in dirt carried or in traps standing reproduced the chain exactly and
  ## reported no mismatch.
  for t in 0 .. 1:
    w.mixHash(w.teamInfo.cheeseTransferred[t])
    w.mixHash(w.teamInfo.damageToCats[t])
    w.mixHash(w.teamInfo.numRatKings[t] + 10 * w.teamInfo.globalCheese[t])
    w.mixHash(w.teamInfo.numBabyRats[t])
    w.mixHash(w.teamInfo.dirtCounts[t] + 1000 * w.teamInfo.dirtPlaced[t])
    w.mixHash(w.trapCounts[ttRatTrap][t])
    w.mixHash(w.trapCounts[ttCatTrap][t])
  w.hasTraveled.setLen(0)
  w.checkEndOfMatch()
  if w.hasWinner:
    w.running = false

# ---------------------------------------------------------------------------
#  Construction
# ---------------------------------------------------------------------------

proc newWorld*(spec: MapSpec, maxRounds: int): World =
  let n = spec.width * spec.height
  result = World(
    map: spec,
    width: spec.width,
    height: spec.height,
    currentRound: 0,
    running: true,
    isCooperation: true,
    backstabRound: -1,
    backstabber: teamNeutral,
    idGen: initIdGenerator(spec.randomSeed),
    rand: initJavaRandom(spec.randomSeed),
    catRand: initJavaRandom(1092),
    walls: spec.walls,
    dirt: spec.dirt,
    cheeseAmounts: spec.cheese,
    occupant: newSeq[Robot](n),
    flying: newSeq[Robot](n),
    trapTriggers: newSeq[seq[Trap]](n),
    cheeseMineAt: newSeq[CheeseMine](n),
    robotsById: initTable[int, Robot](),
    maxRounds: maxRounds,
    hashChain: 0xCBF29CE484222325'u64
  )
  result.trapAt[0] = newSeq[Trap](n)
  result.trapAt[1] = newSeq[Trap](n)
  result.teamInfo.globalCheese[0] = InitialTeamCheese
  result.teamInfo.globalCheese[1] = InitialTeamCheese
  for i in spec.cheeseMines:
    let mine = CheeseMine(loc: result.indexToLoc(i), lastSpawnRound: 0)
    result.cheeseMines.add(mine)
    result.cheeseMineAt[i] = mine
  for mine in result.cheeseMines:
    let symLoc = result.symmetryLocation(mine.loc)
    mine.pair = result.cheeseMineAt[result.idx(symLoc)]
    if mine.pair == nil:
      ## A map whose mines are not symmetry-paired would crash the spawn path;
      ## pair it with itself so the sim degrades instead of faulting.
      mine.pair = mine
  ## Initial bodies spawn in ID order (`LiveMap` sorts them in its
  ## constructor), which is also their `dynamicBodyExecOrder`.
  var bodies = spec.initialBodies
  bodies.sort(proc (a, b: InitialBody): int = cmp(a.id, b.id))
  for body in bodies:
    result.spawnRobot(body.id, body.unit, body.loc, body.dir,
      body.chirality, body.team)
