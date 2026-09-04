## The Battlecode 2021 "Campaign" world: state, geometry and every legality
## rule.
##
## A behaviour-for-behaviour port of `battlecode/world/GameWorld.java`,
## `world/InternalRobot.java`, `world/ObjectInfo.java`, `world/TeamInfo.java`
## and `world/RobotControllerImpl.java` at commit
## `ed39c1a49574db57e5463d720736220506280294` (release 2021.3.0.5), together
## with the pieces of `common/MapLocation.java` and `common/Direction.java` the
## rules depend on. The port is the authority at runtime; the Java engine
## survives only as the `parity-oracle-bc21` CI job (docs/PARITY.md).
##
## Five things in here look like details and are not:
##
## * **Exec order is SPAWN order, not id order.**
##   `ObjectInfo.eachDynamicBodyByExecOrder` walks `dynamicBodyExecOrder`, an
##   append-on-spawn / remove-by-value list, over a snapshot taken once per
##   sweep. A robot spawned or converted mid-sweep takes NO turn that round.
## * **`cooldownTurns` is a `double`, and the divisor is the tile being LEFT.**
##   `InternalRobot.addCooldownTurns` reads `getPassability(this.location)`
##   BEFORE a move happens, so a move is charged at its origin. A tile of
##   passability 0.0 yields an infinite cooldown and freezes the robot for
##   ever; that is legal, and it is reproduced.
## * **Conviction is capped at spawn conviction, influence at 1e8.** Healing
##   above `convictionCap` is LOST. An Enlightenment Center's cap is the
##   influence limit, and its conviction always equals its influence.
## * **A bid is deducted the moment it is placed** and refunded at the start of
##   the settlement sweep, so a Center that bids cannot spend the same
##   influence on a build that turn.
## * **There is no transaction-id RNG quirk this year.**
##   `RobotControllerImpl`'s static `Random` is assigned on every controller
##   construction and then NEVER READ — unlike 2020, nothing depends on it.

import std/[math, tables]

export tables
import ../../rng
import constants, economy

export constants, economy

type
  Team* = enum
    teamA = 0
    teamB = 1
    teamNeutral = 2

  Dir* = enum
    ## Ordinals match `common/Direction.java`; `allDirections()` is `values()`,
    ## so it INCLUDES `CENTER`.
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
    ## Detected by `tools/convert_maps_bc21.py`; the 2021 engine itself never
    ## uses symmetry for anything. `vertical` flips x, `horizontal` flips y,
    ## `rotational` flips both.
    symVertical = 0
    symHorizontal = 1
    symRotational = 2

  Loc* = object
    x*, y*: int

  Domination* = enum
    dfNone
    dfAnnihilated = "annihilated"
    dfMoreVotes = "more_votes"
    dfMoreEnlightenmentCenters = "more_enlightenment_centers"
    dfMoreInfluence = "more_influence"
    dfCoinFlip = "coin_flip"

  InitialBody* = object
    id*: int             ## the FILE's body id; `LiveMap` sorts on it
    team*: Team
    kind*: RobotKind
    loc*: Loc
    influence*: int

  MapSpec* = object
    ## One converted `.map21`, as `data/maps/bc21/<name>.json` carries it.
    name*: string
    width*, height*: int
    origin*: array[2, int]
      ## The map's own `minCorner`. Recorded for provenance and INERT: this
      ## sim works in 0-based coordinates (docs/RULES-BC21.md §Divergences 6).
    randomSeed*: int
    symmetry*: Symmetry
    symmetries*: seq[Symmetry]
    passability*: seq[float64]
    initialBodies*: seq[InitialBody]

  Robot* = ref object
    id*: int
    team*: Team
    kind*: RobotKind
    loc*: Loc
    influence*: int
    conviction*: int
    convictionCap*: int
    flag*: int
    bid*: int
    roundsAlive*: int
    cooldownTurns*: float64
    parentId*: int          ## -1 for a map-placed Enlightenment Center
    opsLeft*: int           ## the DecisionOps budget replacing the JVM limit
    dead*: bool

  Conversion* = object
    ## One robot queued for re-spawn on the empowering politician's team.
    ## `InternalRobot.toCreate` / `toCreateParents`.
    parentId*: int
    oldId*: int
    oldTeam*: Team
    kind*: RobotKind
    influence*: int
    conviction*: int
    loc*: Loc

  BuffBatch* = object
    expiresAt*: int
    count*: int

  TeamStats* = object
    ## `TeamInfo` plus the per-game counters `results.games[]` reports. The
    ## engine keeps only votes and buffs; everything else is telemetry and is
    ## never read by a rule.
    votes*: array[2, int]
    numBuffs*: array[2, int]
    buffsToAdd*: array[2, int]
    buffExpiries*: array[2, seq[BuffBatch]]
    buffPeak*: array[2, int]
    centersCaptured*: array[2, int]
    centersLost*: array[2, int]
    neutralsCaptured*: array[2, int]
    bidsPlaced*: array[2, int]
    bidInfluenceSpent*: array[2, int]
    topBid*: array[2, int]
    influenceSpent*: array[2, int]
    unitsBuilt*: array[2, int]
    politiciansBuilt*: array[2, int]
    slanderersBuilt*: array[2, int]
    muckrakersBuilt*: array[2, int]
    empowers*: array[2, int]
    empowerConviction*: array[2, int]
    conversions*: array[2, int]
    exposes*: array[2, int]
    camouflaged*: array[2, int]
    robotsLost*: array[2, int]
    moves*: array[2, int]
    passiveEarned*: array[2, int]
    slandererPassive*: array[2, int]
    slandererInfluence*: array[2, int]
    politicianInfluence*: array[2, int]
    muckrakerTurnsEnemyHalf*: array[2, int]
    politiciansConverted*: array[2, int]
    mixPoliticians*: array[2, int]
    mixPoliticianInfluence*: array[2, int]
      ## Telemetry for `test_bc21_knobs.nim`: the named signed deltas the
      ## knob-teeth gate asserts. Never read by a rule.
    votesTied*: int
    roundsNoBid*: int

  World* = ref object
    map*: MapSpec
    width*, height*: int
    currentRound*: int
    maxRounds*: int
    running*: bool
    idGen*: IdGenerator
    rand*: JavaRandom
      ## `GameWorld.rand`, seeded from the map's own `randomSeed`. Replaces
      ## `setWinnerArbitrary`'s `Math.random()`
      ## (docs/RULES-BC21.md §Divergences item 2).
    symmetry*: Symmetry
    homeCentroid*: array[2, Loc]
      ## The centroid of each team's INITIAL Enlightenment Centers. Used only
      ## by the "muckraker-turns in the enemy half" telemetry the knob gate
      ## reads; never by a rule.
    passability*: seq[float64]
    occupant*: seq[Robot]
    robotsById*: Table[int, Robot]
    execOrder*: seq[int]
    robotCount*: array[3, int]
    typeCount*: array[3, array[RobotKind, int]]
      ## `ObjectInfo.robotTypeCount`. The chassis reads it every turn; deriving
      ## it by walking `robotsById` per robot turn is O(n^2) per round and
      ## costs the perf gate.
    stats*: TeamStats
    conversionQueue*: seq[Conversion]
      ## `InternalRobot.toCreate`, per empowering politician. Cleared at the
      ## start of each `empower`.
    winner*: Team
    hasWinner*: bool
    domination*: Domination
    influenceClampHit*: bool
    ## Replay/telemetry sinks — never read by a rule.
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    hashChain*: uint64
    ## THE EVENT BUDGET. Every beat kind is bounded per game (§Server, player,
    ## protocol): a 1500-round match with hundreds of robots cannot be allowed
    ## to emit an event per empower, and `tests/test_bc21_replay.nim` asserts
    ## each bound. The overflow is still counted in `results`.
    beatCount*: array[8, int]
    voteLeader*: int          ## -1 nobody, 0 A, 1 B
    buffStep*: array[2, int]  ## the 5 % step each team's buff last crossed
    windowTopBid*: array[2, int]
    windowTopBidder*: array[2, int]
    windowInfluence*: array[2, int]

const
  AllDirs* = [dNorth, dNortheast, dEast, dSoutheast,
              dSouth, dSouthwest, dWest, dNorthwest, dCenter]
    ## `Direction.allDirections()` == `Direction.values()`, CENTER included.
  MoveDirs* = [dNorth, dNortheast, dEast, dSoutheast,
               dSouth, dSouthwest, dWest, dNorthwest]
    ## The eight a unit can move in, in the engine's own ordinal order.
  EmpowerRadii* = [1, 2, 4, 9]
    ## The distinct `r^2 <= 9` values a politician's empower can cover.

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

func getPassability*(w: World, l: Loc): float64 =
  if w.onTheMap(l): w.passability[w.idx(l)] else: 0.0

iterator locationsWithinRadiusSquared*(w: World, center: Loc, r2: int): Loc =
  ## `GameWorld.getAllLocationsWithinRadiusSquared`, in its own x-then-y order,
  ## with the engine's `ceil(sqrt(r2)) + 1` window. THIS ORDER IS LOAD-BEARING:
  ## it fixes the order in which empower queues its conversions, and therefore
  ## the ids they are re-spawned with.
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

func symmetricLoc*(w: World, l: Loc): Loc =
  case w.symmetry
  of symVertical: loc(w.width - 1 - l.x, l.y)
  of symHorizontal: loc(l.x, w.height - 1 - l.y)
  of symRotational: loc(w.width - 1 - l.x, w.height - 1 - l.y)

# ---------------------------------------------------------------------------
#  Telemetry
# ---------------------------------------------------------------------------

proc emit*(w: World, kind: string, a = 0, b = 0, c = 0, s = "") =
  w.events.add((round: w.currentRound, kind: kind, a: a, b: b, c: c, s: s))

const
  BeatCenterTaken* = 0
  BeatVoteLead* = 1
  BeatBidSpike* = 2
  BeatExposeWave* = 3
  BeatEmpowerBig* = 4
  BeatFirstBuild* = 5
  BeatAnnihilated* = 6

  BeatBounds* = [24, 40, 30, 20, 40, 6, 1, 0]
    ## Per GAME, in the order above. `tests/test_bc21_replay.nim` asserts every
    ## one of them against a real match.

proc beat*(w: World, slot: int, kind: string, a = 0, b = 0, c = 0,
           s = ""): bool {.discardable.} =
  ## Emit a bounded beat. False once this game has spent that kind's budget.
  if w.beatCount[slot] >= BeatBounds[slot]: return false
  w.beatCount[slot] += 1
  w.emit(kind, a, b, c, s)
  true

proc mixHash*(w: World, v: int) =
  ## The per-round hash chain (`coworld-ctf`'s `gameHash` discipline). The
  ## viewer re-derives every round and compares, exposing `bc_mismatch_round`.
  w.hashChain = (w.hashChain xor uint64(v and 0xFFFFFFFF)) *
    0x100000001B3'u64

# ---------------------------------------------------------------------------
#  Robot predicates
# ---------------------------------------------------------------------------

func canBuildKind*(builder, target: RobotKind): bool =
  ## `RobotType.canBuild` == `this == type.spawnSource`.
  builder == rtEnlightenmentCenter and target != rtEnlightenmentCenter

func canTrueSense*(kind: RobotKind): bool =
  kind == rtEnlightenmentCenter or kind == rtMuckraker

func canMoveKind*(kind: RobotKind): bool = kind != rtEnlightenmentCenter
func canEmpowerKind*(kind: RobotKind): bool = kind == rtPolitician
func canExposeKind*(kind: RobotKind): bool = kind == rtMuckraker
func canBeExposed*(kind: RobotKind): bool = kind == rtSlanderer
func canBeConverted*(kind: RobotKind): bool =
  kind == rtEnlightenmentCenter or kind == rtPolitician
func canBidKind*(kind: RobotKind): bool = kind == rtEnlightenmentCenter
func isPlayer*(team: Team): bool = team != teamNeutral
func other*(team: Team): Team =
  case team
  of teamA: teamB
  of teamB: teamA
  of teamNeutral: teamNeutral

func inEnemyHalf*(w: World, team: Team, l: Loc): bool =
  ## Closer to the ENEMY's starting capital than to your own. Telemetry only.
  if not team.isPlayer(): return false
  let mine = w.homeCentroid[ord(team)]
  let theirs = w.homeCentroid[ord(other(team))]
  l.distanceSquaredTo(theirs) < l.distanceSquaredTo(mine)

func spec*(r: Robot): RobotSpec = RobotSpecs[r.kind]

func isReady*(r: Robot): bool =
  ## `assertIsReady` throws at `cooldownTurns >= 1`, so ready is STRICTLY
  ## less than 1.
  r.cooldownTurns < 1.0

func convictionAtSpawn*(kind: RobotKind, influence: int): int =
  ## `(int) Math.ceil(this.type.convictionRatio * this.influence)`
  ## (`InternalRobot.java:67` at the pinned `battlecode21@ed39c1a4`).
  ## `convictionRatio` is a Java `float` and `influence` an `int`, so binary
  ## numeric promotion (JLS 5.6.2) makes the PRODUCT a `float`; the widening to
  ## `double` happens at the `Math.ceil` call, after the multiply. Hence the
  ## float32 product here: it is the muckraker's 0.699999988079071 that gives
  ## ceil(0.7*10) = 7 and ceil(0.7*11) = 8, and above ~3.0e6 influence the two
  ## roundings genuinely part (float64 first disagrees at 2 995 933).
  int(ceil(float64(RobotSpecs[kind].convictionRatio * float32(influence))))

func canSenseLocation*(w: World, r: Robot, l: Loc): bool =
  r.loc.distanceSquaredTo(l) <= RobotSpecs[r.kind].sensorRadiusSquared and
    w.onTheMap(l)

func canDetectLocation*(w: World, r: Robot, l: Loc): bool =
  r.loc.distanceSquaredTo(l) <= RobotSpecs[r.kind].detectionRadiusSquared and
    w.onTheMap(l)

func canActLocation*(r: Robot, l: Loc): bool =
  r.loc.distanceSquaredTo(l) <= RobotSpecs[r.kind].actionRadiusSquared

func getRobot*(w: World, l: Loc): Robot =
  if w.onTheMap(l): w.occupant[w.idx(l)] else: nil

func isLocationOccupied*(w: World, l: Loc): bool = w.getRobot(l) != nil

# ---------------------------------------------------------------------------
#  Influence, conviction, cooldown
# ---------------------------------------------------------------------------

proc addCooldownTurns*(w: World, r: Robot) =
  ## `InternalRobot.addCooldownTurns`: `actionCooldown / passability(location)`
  ## read at the robot's CURRENT tile, i.e. for a move the tile being left.
  ## A tile at passability 0.0 gives +Inf and freezes the robot for ever.
  let p = w.getPassability(r.loc)
  r.cooldownTurns = r.cooldownTurns +
    float64(RobotSpecs[r.kind].actionCooldown) / p

proc addInfluenceAndConviction*(w: World, r: Robot, amount: int) =
  ## `InternalRobot.addInfluenceAndConviction`: influence and conviction move
  ## together and the influence is clamped above at `ROBOT_INFLUENCE_LIMIT`.
  r.influence += amount
  if r.influence > RobotInfluenceLimit:
    r.influence = RobotInfluenceLimit
    w.influenceClampHit = true
  r.conviction = r.influence

proc addConviction*(r: Robot, amount: int) =
  ## `InternalRobot.addConviction`: clamped above at the robot's OWN
  ## `convictionCap` (its conviction at spawn). Healing above it is LOST.
  r.conviction += amount
  if r.conviction > r.convictionCap:
    r.conviction = r.convictionCap

# ---------------------------------------------------------------------------
#  Spawning and destruction
# ---------------------------------------------------------------------------

proc addRobotAt(w: World, l: Loc, r: Robot) = w.occupant[w.idx(l)] = r
proc removeRobotAt(w: World, l: Loc) = w.occupant[w.idx(l)] = nil

proc spawnRobotWithId*(w: World, id: int, parentId: int, kind: RobotKind,
                       l: Loc, team: Team, influence: int): int
    {.discardable.} =
  ## `GameWorld.spawnRobot`. The new body is APPENDED to the exec order, so it
  ## takes no turn in the sweep it was created during.
  let conviction = convictionAtSpawn(kind, influence)
  let r = Robot(
    id: id, team: team, kind: kind, loc: l,
    influence: influence, conviction: conviction,
    convictionCap: (if kind == rtEnlightenmentCenter: RobotInfluenceLimit
                    else: conviction),
    flag: 0, bid: 0, roundsAlive: 0, cooldownTurns: 0.0,
    parentId: parentId)
  w.robotsById[id] = r
  w.execOrder.add(id)
  w.robotCount[ord(team)] += 1
  w.typeCount[ord(team)][kind] += 1
  w.addRobotAt(l, r)
  id

proc spawnRobot*(w: World, parentId: int, kind: RobotKind, l: Loc,
                 team: Team, influence: int): int {.discardable.} =
  w.spawnRobotWithId(w.idGen.nextId(), parentId, kind, l, team, influence)

proc destroyRobot*(w: World, id: int) =
  var r: Robot
  if not w.robotsById.pop(id, r):
    return
  r.dead = true
  w.removeRobotAt(r.loc)
  w.robotCount[ord(r.team)] -= 1
  w.typeCount[ord(r.team)][r.kind] -= 1
  if r.team.isPlayer():
    w.stats.robotsLost[ord(r.team)] += 1
    if r.kind == rtEnlightenmentCenter:
      w.stats.centersLost[ord(r.team)] += 1
  let i = w.execOrder.find(id)
  if i >= 0: w.execOrder.delete(i)
  w.emit("died", id, ord(r.team), ord(r.kind))

func livingCenters*(w: World, team: Team): int =
  w.typeCount[ord(team)][rtEnlightenmentCenter]

func totalInfluence*(w: World, team: Team): int =
  ## `setWinnerIfMoreInfluence`'s rung: every living non-neutral robot.
  for _, r in w.robotsById:
    if r.team == team: result += r.influence

# ---------------------------------------------------------------------------
#  Rule 4 — the legal actions, with their exact preconditions
# ---------------------------------------------------------------------------

proc canMove*(w: World, r: Robot, d: Dir): bool =
  ## `assertCanMove`: the destination is one of the 8 adjacent tiles, on the
  ## map and unoccupied, and the robot is ready. Passability never BLOCKS a
  ## move — it only decides the cooldown.
  if not r.kind.canMoveKind(): return false
  if d == dCenter: return false
  let target = r.loc + d
  if not w.onTheMap(target): return false
  if w.isLocationOccupied(target): return false
  isReady(r)

proc move*(w: World, r: Robot, d: Dir) =
  ## `RobotControllerImpl.move`: the cooldown is charged BEFORE the move, at
  ## the tile being left.
  if not w.canMove(r, d): return
  let center = r.loc + d
  w.addCooldownTurns(r)
  w.removeRobotAt(r.loc)
  w.addRobotAt(center, r)
  r.loc = center
  if r.team.isPlayer():
    w.stats.moves[ord(r.team)] += 1

proc canBuildRobot*(w: World, r: Robot, kind: RobotKind, d: Dir,
                    influence: int): bool =
  if not r.kind.canBuildKind(kind): return false
  if influence <= 0: return false
  if influence > r.influence: return false
  if d == dCenter: return false
  let spawnLoc = r.loc + d
  if not w.onTheMap(spawnLoc): return false
  if w.isLocationOccupied(spawnLoc): return false
  isReady(r)

proc buildRobot*(w: World, r: Robot, kind: RobotKind, d: Dir,
                 influence: int): int {.discardable.} =
  ## `RobotControllerImpl.buildRobot`, in its own order: charge the cooldown,
  ## deduct the influence, spawn, then set the type's `initialCooldown` — which
  ## is why a CONVERTED robot (which never goes through here) arrives with
  ## cooldown 0.
  if not w.canBuildRobot(r, kind, d, influence): return -1
  w.addCooldownTurns(r)
  w.addInfluenceAndConviction(r, -influence)
  let id = w.spawnRobot(r.id, kind, r.loc + d, r.team, influence)
  w.robotsById[id].cooldownTurns = float64(RobotSpecs[kind].initialCooldown)
  let t = ord(r.team)
  if r.team.isPlayer():
    w.stats.unitsBuilt[t] += 1
    w.stats.influenceSpent[t] += influence
    case kind
    of rtPolitician:
      w.stats.politiciansBuilt[t] += 1
      w.stats.politicianInfluence[t] += influence
    of rtSlanderer:
      w.stats.slanderersBuilt[t] += 1
      w.stats.slandererInfluence[t] += influence
    of rtMuckraker: w.stats.muckrakersBuilt[t] += 1
    else: discard
  w.emit("built", id, ord(r.team), ord(kind))
  id

proc canBid*(r: Robot, influence: int): bool =
  ## NOT an action: no `isReady` check and no cooldown.
  if not r.kind.canBidKind(): return false
  if influence <= 0: return false
  influence <= r.influence

proc resetBid*(w: World, r: Robot) =
  ## `InternalRobot.resetBid`: the held influence comes back.
  w.addInfluenceAndConviction(r, r.bid)
  r.bid = 0

proc bid*(w: World, r: Robot, influence: int) =
  ## `InternalRobot.setBid`: the previous bid is refunded, then the new one is
  ## deducted IMMEDIATELY and held hostage until the settlement.
  if not canBid(r, influence): return
  w.resetBid(r)
  r.bid = influence
  w.addInfluenceAndConviction(r, -r.bid)
  if r.team.isPlayer():
    w.stats.bidsPlaced[ord(r.team)] += 1

proc canSetFlag*(flag: int): bool =
  flag >= MinFlagValue and flag <= MaxFlagValue

proc setFlag*(r: Robot, flag: int) =
  ## NOT an action: no `isReady` check and no cooldown.
  if not canSetFlag(flag): return
  r.flag = flag

proc canGetFlag*(w: World, r: Robot, id: int): bool =
  ## `assertCanGetFlag`: any robot's flag if the caller IS an Enlightenment
  ## Center, any Enlightenment Center's flag at any range, and otherwise only
  ## what the caller can sense — of EITHER team.
  if id notin w.robotsById: return false
  let bot = w.robotsById[id]
  if r.kind == rtEnlightenmentCenter: return true
  if bot.kind == rtEnlightenmentCenter: return true
  w.canSenseLocation(r, bot.loc)

# ---------------------------------------------------------------------------
#  Sensing
# ---------------------------------------------------------------------------

func sensedKind*(observer, observed: RobotKind): RobotKind =
  ## `InternalRobot.getRobotInfo(trueSense)`: politicians and slanderers see a
  ## SLANDERER as a POLITICIAN. Centers and muckrakers see the truth.
  if observed == rtSlanderer and not observer.canTrueSense(): rtPolitician
  else: observed

# ---------------------------------------------------------------------------
#  Turn scaffolding
# ---------------------------------------------------------------------------

proc processBeginningOfTurn*(r: Robot) =
  ## Rule 3. `if (cooldownTurns > 0) cooldownTurns = max(0, cooldownTurns - 1)`,
  ## then the DecisionOps budget is reset (this port's replacement for the JVM
  ## bytecode limit).
  if r.cooldownTurns > 0:
    r.cooldownTurns = max(0.0, r.cooldownTurns - 1.0)
  r.opsLeft = RobotSpecs[r.kind].decisionOps

proc processEndOfTurn*(r: Robot) =
  ## Rule 5.
  r.roundsAlive += 1

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
    maxRounds: maxRounds,
    running: true,
    idGen: initIdGenerator(spec.randomSeed),
    rand: initJavaRandom(spec.randomSeed),
    symmetry: spec.symmetry,   # replaced below by the team-mirroring one
    passability: spec.passability,
    occupant: newSeq[Robot](n),
    robotsById: initTable[int, Robot](),
    winner: teamNeutral,
    domination: dfNone,
    hashChain: 0xCBF29CE484222325'u64
  )
  ## WHICH SYMMETRY THE CHASSIS STEERS BY. The converter records every
  ## transform under which the passability array and the Centers agree, and
  ## deliberately does not compare TEAMS (`Corridor` is 33 wide with both
  ## Centers on the centre column, so it mirrors vertically onto itself). The
  ## chassis wants the transform that maps an OWN Center onto an ENEMY one, so
  ## the world picks the first recorded symmetry that does, falling back to the
  ## recorded display symmetry.
  block pickSymmetry:
    var aCenters, bCenters: seq[Loc]
    for body in spec.initialBodies:
      if body.kind != rtEnlightenmentCenter: continue
      if body.team == teamA: aCenters.add(body.loc)
      elif body.team == teamB: bCenters.add(body.loc)
    for candidate in spec.symmetries:
      result.symmetry = candidate
      var maps = aCenters.len > 0
      for a in aCenters:
        let mirrored = result.symmetricLoc(a)
        var found = false
        for b in bCenters:
          if b == mirrored: found = true
        if not found: maps = false
      if maps: break pickSymmetry
    result.symmetry = spec.symmetry

  ## `LiveMap`'s constructor sorts `initialBodies` by the FILE's body id and
  ## `GameWorld` spawns them in that order, each taking the next id out of the
  ## `IDGenerator` — which is what makes the port's ids match the engine's.
  var bodies = spec.initialBodies
  for i in 1 ..< bodies.len:
    var j = i
    while j > 0 and bodies[j - 1].id > bodies[j].id:
      swap(bodies[j - 1], bodies[j])
      dec j
  block centroids:
    var sx, sy, n: array[2, int]
    for body in bodies:
      if body.kind != rtEnlightenmentCenter: continue
      if not body.team.isPlayer(): continue
      let t = ord(body.team)
      sx[t] += body.loc.x
      sy[t] += body.loc.y
      n[t] += 1
    for t in 0 .. 1:
      if n[t] > 0:
        result.homeCentroid[t] = loc(sx[t] div n[t], sy[t] div n[t])

  for body in bodies:
    result.spawnRobot(-1, body.kind, body.loc, body.team, body.influence)
