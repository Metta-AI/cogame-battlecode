## The Battlecode 2025 "Chromatic Conflict" world: state, geometry and every
## legality rule a ROBOT can reach.
##
## A behaviour-for-behaviour port of `battlecode/world/GameWorld.java`,
## `world/InternalRobot.java`, `world/RobotControllerImpl.java`,
## `world/TeamInfo.java`, `world/ObjectInfo.java` and `world/LiveMap.java` at
## commit `28975a487c1a30ed2b5bed644fe6ecd2c3dd1482`, together with the pieces
## of `common/MapLocation.java` and `common/Direction.java` the rules depend
## on. The port is the authority at runtime; the Java engine survives only as
## the `parity-oracle-bc25` CI job (docs/PARITY.md).
##
## Tower actions live in `towers.nim` and messages in `comms.nim`; both import
## this file. `patterns.nim`, `paint.nim` and `units.nim` are pure and are
## imported BY it. Six things in here look like details and are not:
##
## * **The exec order is DYNAMIC and mutated BY VALUE.** `ObjectInfo`'s
##   `dynamicBodyExecOrder` is a plain append-ordered `TIntArrayList`; a unit
##   built is appended, a unit destroyed is removed from wherever it sits and
##   everything after it shifts forward. The sweep iterates a SNAPSHOT taken
##   before it starts, so a unit built this round does not take a turn this
##   round, and a unit destroyed mid-sweep is skipped by the `existsRobot`
##   guard.
## * **A paint win fires MID-ACTION.** `TeamInfo.addPaintedSquares` runs
##   `checkWin` on EVERY tile recolour, so a team can cross 70 % in the middle
##   of a splasher's AoE loop. `running` is only cleared at the end of the
##   round, so every unit after the winner still takes its turn.
## * **`totalPaintedSquares` is a LIVE count, not a cumulative one.**
##   `setPaint` decrements the old owner and increments the new one, and it is
##   a NO-OP on an unpaintable tile. Mopping a tile bare lowers a clan's count;
##   painting a wall does nothing at all. The field is called `livePainted`
##   here because the engine's own name (`getNumberOfPaintedSquares`) reads as
##   a total and is not one.
## * **The cooldown is charged from the PRE-COST stash on an attack and from
##   the POST-TRANSFER stash on a paint transfer.** Both orders are the
##   engine's (`RobotControllerImpl.attack` charges before `robot.attack`
##   deducts; `transferPaint` moves the paint and charges after). Both are
##   ported literally.
## * **The end-of-turn crowding penalty counts TOWERS.** The engine's
##   `getAllRobotsWithinRadiusSquared(loc, 2, team)` returns every allied
##   UNIT, so a robot standing next to its own paint tower pays for it. That is
##   not what the spec's prose says (docs/RULES-BC25.md §Divergences item 3 of
##   the prose list).
## * **`getAllLocationsWithinRadiusSquared`'s scan order is load-bearing**: x
##   ascending outer, y ascending inner over the clamped `ceil(sqrt(r2)) + 1`
##   box. It fixes which tile a splasher paints first — and therefore which
##   recolour crosses 70 % — which enemy a tower's AoE hits first, and the
##   order `senseNearbyMapInfos` returns, which the example bot's "keep the
##   LAST ruin you saw" loop depends on.

import std/[strutils, tables]
import ../../sim_types, ../../rng
import constants, units, paint, patterns

export constants, units, paint, patterns, rng, tables

type
  Message* = object
    ## `world/Message.java`: a 32-bit word, the sender's id and the round it
    ## was sent. Readable for `MESSAGE_ROUND_DURATION = 5` rounds.
    bytes*: int
    senderId*: int
    round*: int

  MapSpec* = object
    ## One converted `.map25`, as `data/maps/bc25/<name>.json` carries it.
    name*: string
    width*, height*: int
    randomSeed*: int
    symmetry*: Symmetry
    walls*: seq[bool]
    ruins*: seq[Loc]
      ## The FILE's own ruin list. It does NOT contain the four starting-tower
      ## tiles; `GameWorld`'s constructor adds those to `allRuins` itself and
      ## `newWorld` reproduces that.
    paint*: seq[tuple[x, y, colour: int]]
    initialBodies*: seq[tuple[id, x, y, team, kind: int]]
      ## The map's `InitialBodyTable`, in FILE order. `LiveMap`'s constructor
      ## SORTS this by ascending id before the world ever sees it
      ## (`LiveMap.java:105`), so `newWorld` sorts too — the design note's
      ## claim that file order is the initial exec order is wrong and the
      ## engine wins (docs/RULES-BC25.md §Divergences item 15).

  Robot* = ref object
    id*: int
    team*: Team
    kind*: UnitType
    loc*: Loc
    health*: int
    paint*: int
    roundsAlive*: int
    actionCooldown*: int
    movementCooldown*: int
    sentMessages*: int
    towerSingleAttacked*: bool
    towerAreaAttacked*: bool
    alive*: bool
    inbox*: seq[Message]
    opsLeft*: int          ## the DecisionOps budget replacing the JVM limit
    opsUsed*: int
    ## --- chassis-side memory, never read by a rule ---
    scaffoldRng*: JavaRandom
      ## `static final Random rng = new Random(6147)`. Static fields are PER
      ## ROBOT under the instrumenter, so every unit gets its own stream and
      ## the example bot needs no determinism patch.
    scaffoldTurns*: int
    noRepeat*: seq[Loc]
    claimed*: Loc
    claimedKind*: TowerKind
    hasClaim*: bool
    refilling*: bool
    srpCentre*: Loc
    hasSrpTask*: bool

  TeamStats* = object
    ## `TeamInfo` plus the per-game counters `results.games[]` reports. The
    ## engine keeps only money, live painted squares and the tower count;
    ## everything else is telemetry and is never read by a rule.
    money*: array[2, int]
    livePainted*: array[2, int]
    towers*: array[2, int]
    ## --- telemetry ---
    chipsEarned*: array[2, int]
    chipsSpent*: array[2, int]
    chipsSpentOnTowers*: array[2, int]
    chipsAt1000*: array[2, int]
    chipsEarnedBy1500*: array[2, int]
    paintMined*: array[2, int]
    paintSpent*: array[2, int]
    paintTransferred*: array[2, int]
    tilesPainted*: array[2, int]
    tilesPaintedBySplashers*: array[2, int]
    tilesMopped*: array[2, int]
    tilesOverpainted*: array[2, int]
    peakCoverage*: array[2, int]
    robotsBuilt*: array[2, int]
    robotsBuiltBy400*: array[2, int]
    soldiersBuilt*: array[2, int]
    splashersBuilt*: array[2, int]
    moppersBuilt*: array[2, int]
    robotsLost*: array[2, int]
    robotRounds*: array[2, int]
    robotRoundsStarved*: array[2, int]
    towersBuilt*: array[2, int]
    towersBuiltBy400*: array[2, int]
    towersUpgraded*: array[2, int]
    towersLost*: array[2, int]
    defenseTowersBuilt*: array[2, int]
    defenseBuffRounds*: array[2, int]
      ## The clan's tower-damage ledger SUMMED OVER ROUNDS -- i.e. how much
      ## extra single-target damage every allied tower actually carried, and
      ## for how long. It is the quantity `defense_tower_chokes` literally
      ## buys (+5 a level-one defense tower, +7 at level two, +9 at level
      ## three) and it is never read by a rule.
    paintTowersAt1000*: array[2, int]
    claimDistanceSum*: array[2, int]
    claimDistanceCount*: array[2, int]
    srpCompleted*: array[2, int]
    srpBroken*: array[2, int]
    srpRoundsActive*: array[2, int]
    splashAttacks*: array[2, int]
    mopSwings*: array[2, int]
    towerDamageDealt*: array[2, int]
      ## Damage OUR units dealt to enemy TOWERS.
    robotDamageDealt*: array[2, int]
      ## Damage OUR towers dealt to enemy units.
    killsByTowers*: array[2, int]
    messagesSent*: array[2, int]
    markersPlaced*: array[2, int]
    roundsWithAnySrp*: int

  World* = ref object
    map*: MapSpec
    width*, height*: int
    currentRound*: int
    maxRounds*: int
    running*: bool
    idGen*: IdGenerator
    rand*: JavaRandom
      ## `GameWorld.rand` is constructed from the map seed and NEVER READ by
      ## the 2025 engine. It is constructed here for one purpose only:
      ## replacing `setWinnerArbitrary`'s wall-clock `Math.random()` with a
      ## reproducible draw (docs/RULES-BC25.md §Divergences item 2).
    symmetry*: Symmetry
    areaWithoutWalls*: int
    trulyPaintable*: int
      ## `width * height - walls - ruins`: the tiles that can ACTUALLY hold
      ## paint. Never used by a rule; the viewer prints it beside
      ## `areaWithoutWalls` so the 70 % gap is visible.
    walls*: seq[bool]
    ruinAt*: seq[bool]
    allRuins*: seq[Loc]
    colours*: seq[int8]
    markers*: array[2, seq[int8]]
    towersByLoc*: seq[int8]        ## 0 none, 1 team A, 2 team B
    occupant*: seq[Robot]
    robotsById*: Table[int, Robot]
    execOrder*: seq[int]
    srpCentres*: seq[Loc]          ## LIST ORDER IS LOAD-BEARING
    srpTeamByLoc*: seq[int8]       ## 0 neutral, 1 team A, 2 team B
    srpLifetimes*: seq[int32]
    damageIncrease*: array[2, int]
    unitCount*: array[2, int]
    stats*: TeamStats
    winner*: Team
    hasWinner*: bool
    domination*: Domination
    ## Replay/telemetry sinks — never read by a rule.
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    hashChain*: uint64
    beatCount*: array[16, int]
    refusedActions*: int
      ## THE LEGALITY AUDIT. Every `do*` re-checks its own `can*` and no-ops
      ## when it fails; this counts those no-ops. A chassis that emits an
      ## illegal order is a chassis whose orders were never checked, so
      ## `tests/test_bc25_baselines.nim` plays whole games and asserts this
      ## stays ZERO.
    opsUsedPeak*: int
    firstActionSeen*: array[2, bool]
    coverageDecile*: array[2, int]
    starvedThisRound*: array[2, int]
    lostThisRound*: array[2, int]

# ---------------------------------------------------------------------------
#  Beats
# ---------------------------------------------------------------------------

const
  BeatGameStart* = 0
  BeatFirstAction* = 1
  BeatTowerBuilt* = 2
  BeatTowerUpgraded* = 3
  BeatTowerLost* = 4
  BeatSrpCompleted* = 5
  BeatSrpActive* = 6
  BeatSrpBroken* = 7
  BeatCoverage* = 8
  BeatStarved* = 9
  BeatRout* = 10

  BeatBounds* = [1, 4, 50, 50, 50, 20, 20, 20, 14, 20, 20, 0, 0, 0, 0, 0]
    ## Per GAME, in the order above and in the design note's own event table.
    ## `tests/test_bc25_replay.nim` asserts every one of them against a real
    ## match, so a pathological game cannot produce a 20 MB replay.

const
  Bc25ActionMove* = 0
  Bc25ActionPaint* = 1
  Bc25ActionSplash* = 2
  Bc25ActionMop* = 3
  Bc25ActionMopSwing* = 4
  Bc25ActionTransfer* = 5
  Bc25ActionWithdraw* = 6
  Bc25ActionBuildRobot* = 7
  Bc25ActionMark* = 8
  Bc25ActionMarkTowerPattern* = 9
  Bc25ActionMarkSrp* = 10
  Bc25ActionCompleteTowerPattern* = 11
  Bc25ActionCompleteSrp* = 12
  Bc25ActionUpgradeTower* = 13
  Bc25ActionTowerAttack* = 14
  Bc25ActionTowerAoe* = 15
  Bc25ActionMessage* = 16
  Bc25ActionBroadcast* = 17
  Bc25ActionDisintegrate* = 18
    ## The ordinals `years/dispatch.nim`'s `Bc25ActionNames` spells out, so
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
  ## The same step for a value that is ALREADY a 64-bit hash. It exists
  ## because `mixHash(int(h and 0xFFFFFFFF'u64))` is a 64-bit-only
  ## expression: `int` is 32 bits under wasm32, the masked value runs to
  ## 4294967295, and the conversion raises RangeDefect the moment the browser
  ## re-derives round 1 -- while the native test suite, on amd64, is green.
  ## Folding the mask in here keeps the mixed value bit-identical on both
  ## widths, so no committed hash chain moves.
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
  ## ascending outer, y ascending inner, over the clamped
  ## `ceil(sqrt(r2)) + 1` box. `ceil(sqrt())` comes from the precomputed
  ## table in `units.nim`, so the port has no `sqrt` and no `fdlibm` path.
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

func symmetricLoc*(w: World, l: Loc): Loc =
  case w.symmetry
  of symVertical: loc(w.width - 1 - l.x, l.y)
  of symHorizontal: loc(l.x, w.height - 1 - l.y)
  of symRotation: loc(w.width - 1 - l.x, w.height - 1 - l.y)

# ---------------------------------------------------------------------------
#  Terrain
# ---------------------------------------------------------------------------

func getWall*(w: World, l: Loc): bool = w.walls[w.idx(l)]
func hasRuin*(w: World, l: Loc): bool = w.ruinAt[w.idx(l)]

func isPassable*(w: World, l: Loc): bool =
  let i = w.idx(l)
  passableTile(w.walls[i], w.ruinAt[i])

func isPaintable*(w: World, l: Loc): bool = w.isPassable(l)

func getPaint*(w: World, l: Loc): int = int(w.colours[w.idx(l)])

func getMarker*(w: World, t: Team, l: Loc): int =
  int(w.markers[ord(t)][w.idx(l)])

func hasTower*(w: World, l: Loc): bool = w.towersByLoc[w.idx(l)] != 0
func towerTeamAt*(w: World, l: Loc): int = int(w.towersByLoc[w.idx(l)])

func getRobot*(w: World, l: Loc): Robot =
  if w.onTheMap(l): w.occupant[w.idx(l)] else: nil

func isLocationOccupied*(w: World, l: Loc): bool = w.getRobot(l) != nil

func robotById*(w: World, id: int): Robot =
  if w.robotsById.hasKey(id): w.robotsById[id] else: nil

func existsRobot*(w: World, id: int): bool = w.robotsById.hasKey(id)

func canSenseLocation*(w: World, r: Robot, l: Loc): bool =
  w.onTheMap(l) and r.loc.distanceSquaredTo(l) <= VisionRadiusSquared

# ---------------------------------------------------------------------------
#  DecisionOps — the budget that replaces the JVM bytecode limit
# ---------------------------------------------------------------------------

func budgetFor*(k: UnitType): int =
  if k.isRobotType(): DecisionOpsRobot else: DecisionOpsTower

proc spend*(r: Robot, n: int): bool {.discardable.} =
  ## Charged BEFORE each primitive and never inside one, so a primitive's
  ## RESULT is never a function of the remaining budget — only whether the
  ## chassis got to ask. When the budget runs out the unit's turn ends where
  ## it stands; it is not resumed mid-computation next turn, which is the one
  ## place this differs from the JVM (docs/RULES-BC25.md §Divergences item 1).
  if r.opsLeft < n: return false
  r.opsLeft -= n
  r.opsUsed += n
  true

# ---------------------------------------------------------------------------
#  Money and paint
# ---------------------------------------------------------------------------

func getMoney*(w: World, t: Team): int = w.stats.money[ord(t)]

proc addMoney*(w: World, t: Team, amount: int) =
  ## `TeamInfo.addMoney`, which THROWS rather than clamping when a spend would
  ## take a team negative. Every caller checks first; a raise here means a
  ## legality bug, not a game state, and the server turns it into
  ## `results.reason = fault`.
  if w.stats.money[ord(t)] + amount < 0:
    raise newException(BattlecodeError, "bc25: invalid chip change")
  w.stats.money[ord(t)] += amount
  if amount > 0:
    w.stats.chipsEarned[ord(t)] += amount
    if w.currentRound <= 1500:
      w.stats.chipsEarnedBy1500[ord(t)] += amount
  else:
    w.stats.chipsSpent[ord(t)] -= amount

proc addPaint*(r: Robot, amount: int) =
  ## `InternalRobot.addPaint`: clamped at 0 below and at the type's capacity
  ## above. Never raises — a robot that would overdraw simply hits 0, which is
  ## exactly the state the 20 HP a turn punishes.
  let next = r.paint + amount
  if next > UnitSpecs[r.kind].paintCapacity:
    r.paint = UnitSpecs[r.kind].paintCapacity
  elif next < 0:
    r.paint = 0
  else:
    r.paint = next

func paintInUnits*(w: World, t: Team): int =
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == t: result += r.paint

# ---------------------------------------------------------------------------
#  Paint, the live count and the mid-action win
# ---------------------------------------------------------------------------

proc setWinner*(w: World, t: Team, d: Domination) =
  w.winner = t
  w.hasWinner = true
  w.domination = d

proc addPaintedSquares(w: World, num: int, t: Team) =
  ## `TeamInfo.addPaintedSquares`: the win check runs on EVERY recolour, so a
  ## team can cross 70 % in the middle of a splasher's AoE loop. `running` is
  ## only cleared at step 6d.
  w.stats.livePainted[ord(t)] += num
  if w.stats.livePainted[ord(t)] >= tilesToWin(w.areaWithoutWalls):
    if not w.hasWinner:
      w.setWinner(t, dfPaintEnoughArea)

proc setPaint*(w: World, l: Loc, colour: int) =
  ## `GameWorld.setPaint`: a NO-OP on an unpaintable tile, and the live count
  ## moves one from the old owner to the new one.
  if not w.isPaintable(l): return
  let i = w.idx(l)
  let old = int(w.colours[i])
  if hasPaintTeam(old):
    w.addPaintedSquares(-1, teamFromPaint(old))
  if hasPaintTeam(colour):
    w.addPaintedSquares(1, teamFromPaint(colour))
  w.colours[i] = int8(colour)

proc setMarker*(w: World, t: Team, l: Loc, marker: int) =
  ## `GameWorld.setMarker`: a NO-OP on an unpaintable tile, which is why a
  ## marked tower pattern never carries a marker on the ruin at its centre.
  if not w.isPaintable(l): return
  w.markers[ord(t)][w.idx(l)] = int8(marker)
  if marker != 0: w.stats.markersPlaced[ord(t)] += 1

proc connectedByPaint*(w: World, t: Team, robotLoc, towerLoc: Loc,
                       actor: Robot = nil): bool =
  ## `GameWorld.connectedByPaint`, verbatim: a 4-neighbour BFS over tiles of
  ## THIS team's colour that refuses to start at all if the robot is not
  ## standing on team paint.
  ##
  ## It is the one unbounded primitive in the rule set, so the port charges it
  ## ONE `DecisionOps` credit per node expanded when an actor is supplied.
  ## That makes the chassis pay for its own chatter and bounds it
  ## structurally; the charge is telemetry on the BFS, never a stopping
  ## condition, so the answer is the engine's answer either way.
  if not paintIsTeam(w.getPaint(robotLoc), t): return false
  var queue = @[robotLoc]
  var head = 0
  var seen = newSeq[bool](w.width * w.height)
  const Ddx = [1, 0, -1, 0]
  const Ddy = [0, 1, 0, -1]
  while head < queue.len:
    let cur = queue[head]
    head += 1
    if cur == towerLoc: return true
    if not w.onTheMap(cur): continue
    let i = w.idx(cur)
    if seen[i]: continue
    if not paintIsTeam(int(w.colours[i]), t): continue
    seen[i] = true
    if actor != nil: discard actor.spend(1)
    for k in 0 .. 3:
      queue.add(loc(cur.x + Ddx[k], cur.y + Ddy[k]))
  false

# ---------------------------------------------------------------------------
#  Patterns against the board
# ---------------------------------------------------------------------------

func areaIsPaintable*(w: World, centre: Loc): bool =
  ## `GameWorld.areaIsPaintable`: no wall and no ruin anywhere in the 5x5.
  for ddx in LoOffset .. HiOffset:
    for ddy in LoOffset .. HiOffset:
      let l = centre.translate(ddx, ddy)
      if not w.onTheMap(l): return false
      if not w.isPaintable(l): return false
  true

func isValidPatternCenter*(w: World, l: Loc, isTower: bool): bool =
  ## `GameWorld.isValidPatternCenter`: two tiles from every edge, and — for a
  ## RESOURCE pattern only — all 25 tiles paintable.
  centreIsInsideBox(l, w.width, w.height) and (isTower or w.areaIsPaintable(l))

proc checkPattern*(w: World, kind: PatternKind, t: Team, centre: Loc,
                   isTowerPattern: bool, actor: Robot = nil): bool =
  ## `GameWorld.checkPattern`: every tile of the 5x5 must carry exactly the
  ## colour the pattern bit names, in THIS team's primary/secondary. The tower
  ## variant skips the centre tile; the SRP variant does not.
  for ddx in LoOffset .. HiOffset:
    for ddy in LoOffset .. HiOffset:
      if ddx == 0 and ddy == 0 and isTowerPattern: continue
      if actor != nil: discard actor.spend(1)
      let l = centre.translate(ddx, ddy)
      if not w.onTheMap(l): return false
      if w.getPaint(l) != wantedPaint(kind, ddx, ddy, t): return false
  true

proc checkTowerPattern*(w: World, t: Team, centre: Loc, towerType: UnitType,
                        actor: Robot = nil): bool =
  w.checkPattern(patternKindFor(towerType), t, centre, true, actor)

proc checkResourcePattern*(w: World, t: Team, centre: Loc,
                           actor: Robot = nil): bool =
  w.checkPattern(pkResource, t, centre, false, actor)

proc markPattern*(w: World, kind: PatternKind, t: Team, centre: Loc) =
  ## `GameWorld.markPattern`: all 25 tiles, `bit + 1` — so 1 means "paint me
  ## primary" and 2 means "paint me secondary", the same alphabet the marker
  ## array uses. Unpaintable tiles silently take no marker.
  for ddx in LoOffset .. HiOffset:
    for ddy in LoOffset .. HiOffset:
      let l = centre.translate(ddx, ddy)
      if not w.onTheMap(l): continue
      let bit = if PatternTables[kind][ddx + Half][ddy + Half]: 1 else: 0
      w.setMarker(t, l, bit + 1)

# ---------------------------------------------------------------------------
#  The Special Resource Pattern registry
# ---------------------------------------------------------------------------

func numActiveResourcePatterns*(w: World, t: Team): int =
  ## `GameWorld.getNumResourcePatterns`: a centre counts only once its
  ## lifetime has reached `RESOURCE_PATTERN_ACTIVE_DELAY = 50`.
  for centre in w.srpCentres:
    let i = w.idx(centre)
    if int(w.srpTeamByLoc[i]) == ord(t) + 1 and
        int(w.srpLifetimes[i]) >= ResourcePatternActiveDelay:
      result += 1

func extraResourcesFromPatterns*(w: World, t: Team): int =
  w.numActiveResourcePatterns(t) * ExtraResourcesFromPattern

func hasResourcePatternCenter*(w: World, l: Loc, t: Team): bool =
  int(w.srpTeamByLoc[w.idx(l)]) == ord(t) + 1

proc updateResourcePatterns*(w: World) =
  ## Rule 1b. `GameWorld.updateResourcePatterns`: walk `resourcePatternCenters`
  ## IN LIST ORDER; a centre whose pattern is broken is dropped and its
  ## lifetime RESET TO 0, a centre that still matches stays and has its
  ## lifetime incremented. Repainting a broken pattern therefore restarts the
  ## whole fifty-round clock.
  var kept: seq[Loc]
  for centre in w.srpCentres:
    let i = w.idx(centre)
    let team = Team(int(w.srpTeamByLoc[i]) - 1)
    let stillActive = w.checkResourcePattern(team, centre)
    if not stillActive:
      w.srpTeamByLoc[i] = 0
      let age = int(w.srpLifetimes[i])
      w.srpLifetimes[i] = 0
      w.stats.srpBroken[ord(team)] += 1
      discard w.beat(BeatSrpBroken, "srp_broken", ord(team),
        centre.x * 100 + centre.y, age)
    else:
      kept.add(centre)
      w.srpLifetimes[i] = int32(int(w.srpLifetimes[i]) + 1)
      if int(w.srpLifetimes[i]) == ResourcePatternActiveDelay:
        discard w.beat(BeatSrpActive, "srp_active", ord(team),
          centre.x * 100 + centre.y,
          w.numActiveResourcePatterns(team) * ExtraResourcesFromPattern)
  w.srpCentres = kept
  var any = false
  for t in [teamA, teamB]:
    let active = w.numActiveResourcePatterns(t)
    if active > 0:
      any = true
      w.stats.srpRoundsActive[ord(t)] += active
  if any: w.stats.roundsWithAnySrp += 1

# ---------------------------------------------------------------------------
#  Spawning and destruction
# ---------------------------------------------------------------------------

proc addRobotAt(w: World, l: Loc, r: Robot) = w.occupant[w.idx(l)] = r
proc removeRobotAt(w: World, l: Loc) = w.occupant[w.idx(l)] = nil

proc spawnRobotWithId*(w: World, id: int, kind: UnitType, l: Loc,
                       t: Team): Robot {.discardable.} =
  ## `GameWorld.spawnRobot(ID, type, location, team)`, in its own order: the
  ## unit is created and registered, a TOWER gets 500 paint and bumps the team
  ## tower count, a ROBOT is filled to `INITIAL_ROBOT_PAINT_PERCENTAGE` of its
  ## capacity, a level-one defense tower adds +5 to the team's tower damage,
  ## and the live-unit counter goes up.
  let r = Robot(
    id: id, team: t, kind: kind, loc: l,
    health: UnitSpecs[kind].health,
    paint: 0,
    actionCooldown: UnitSpecs[kind].actionCooldown,
    movementCooldown: CooldownLimit,
    alive: true,
    opsLeft: budgetFor(kind),
    scaffoldRng: initJavaRandom(6147),
    claimedKind: tkPaint)
  w.addRobotAt(l, r)
  w.robotsById[id] = r
  w.execOrder.add(id)
  if kind.isTowerType():
    w.stats.towers[ord(t)] += 1
    r.addPaint(InitialTowerPaintAmount)
  else:
    r.addPaint(javaRound(float64(UnitSpecs[kind].paintCapacity) *
      float64(InitialRobotPaintPercentage) / 100.0))
  w.damageIncrease[ord(t)] += defenseBuffOnSpawn(kind)
  w.unitCount[ord(t)] += 1
  r

proc spawnRobot*(w: World, kind: UnitType, l: Loc, t: Team): Robot
    {.discardable.} =
  w.spawnRobotWithId(w.idGen.nextId(), kind, l, t)

proc destroyRobot*(w: World, id: int) =
  ## `GameWorld.destroyRobot`: the tile is cleared, a tower's registration and
  ## its damage buff come off, the exec order loses the entry BY VALUE, and —
  ## the instant the live-unit counter reaches zero — THE OPPONENT WINS with
  ## `DESTROY_ALL_UNITS`, set mid-sweep.
  if not w.robotsById.hasKey(id): return
  let r = w.robotsById[id]
  let t = ord(r.team)
  if r.kind.isTowerType():
    w.towersByLoc[w.idx(r.loc)] = 0
    w.stats.towers[t] -= 1
    w.stats.towersLost[t] += 1
    discard w.beat(BeatTowerLost, "tower_lost", t, ord(towerKindOf(r.kind)),
      r.loc.x * 100 + r.loc.y)
  else:
    w.stats.robotsLost[t] += 1
    w.lostThisRound[t] += 1
  w.damageIncrease[t] -= defenseBuffOnDestroy(r.kind)
  w.removeRobotAt(r.loc)
  r.alive = false
  w.robotsById.del(id)
  let at = w.execOrder.find(id)
  if at >= 0: w.execOrder.delete(at)
  w.unitCount[t] -= 1
  if w.unitCount[t] == 0:
    w.setWinner(r.team.other(), dfDestroyAllUnits)

proc addHealth*(w: World, r: Robot, amount: int) =
  ## `InternalRobot.addHealth`: capped at the type's own maximum above, and a
  ## unit at or below zero is DESTROYED IMMEDIATELY, mid-action.
  if not r.alive: return
  r.health += amount
  r.health = min(r.health, UnitSpecs[r.kind].health)
  if r.health <= 0:
    w.destroyRobot(r.id)

proc noteFirstAction*(w: World, r: Robot, kind: int) =
  let t = ord(r.team)
  if w.firstActionSeen[t]: return
  w.firstActionSeen[t] = true
  discard w.beat(BeatFirstAction, "first_action", t, kind, w.currentRound)

# ---------------------------------------------------------------------------
#  Rule 4 — the legal ROBOT actions, with their exact preconditions
# ---------------------------------------------------------------------------

func canActLocation*(w: World, r: Robot, l: Loc, maxR2: int): bool =
  ## `RobotControllerImpl.assertCanActLocation`: on the map and within `r2` of
  ## the actor. Every ranged action in the rule set is gated on exactly this.
  r.loc.distanceSquaredTo(l) <= maxR2 and w.onTheMap(l)

func isActionReady*(r: Robot): bool =
  r.actionCooldown < CooldownLimit and
    not (r.paint == 0 and r.kind.isRobotType())

func isMovementReady*(r: Robot): bool =
  r.movementCooldown < CooldownLimit and
    not (r.paint == 0 and r.kind.isRobotType())

proc addActionCooldownTurns*(r: Robot, add: int) =
  r.actionCooldown += cooldownSurcharge(add, r.paint, r.kind)

proc addMovementCooldownTurns*(r: Robot) =
  r.movementCooldown += cooldownSurcharge(MovementCooldown, r.paint, r.kind)

# --- 4.1 move ---------------------------------------------------------------

func canMove*(w: World, r: Robot, d: Dir): bool =
  if not r.isMovementReady(): return false
  if d == dCenter: return false
  if r.kind.isTowerType(): return false
  let l = r.loc + d
  if not w.onTheMap(l): return false
  if w.isLocationOccupied(l): return false
  w.isPassable(l)

proc doMove*(w: World, r: Robot, d: Dir) =
  ## `RobotControllerImpl.move`: the robot moves and THEN the cooldown is
  ## charged, so the low-paint surcharge is read from the POST-MOVE stash.
  if not w.canMove(r, d):
    w.refusedActions += 1
    return
  let next = r.loc + d
  w.removeRobotAt(r.loc)
  w.addRobotAt(next, r)
  r.loc = next
  r.addMovementCooldownTurns()
  w.noteFirstAction(r, Bc25ActionMove)

# --- 4.2 soldier attack / paint --------------------------------------------

func canAttackSoldier*(w: World, r: Robot, l: Loc): bool =
  if not r.isActionReady(): return false
  if not w.canActLocation(r, l, UnitSpecs[utSoldier].actionRadiusSquared):
    return false
  if r.paint < UnitSpecs[utSoldier].attackCost: return false
  not w.getWall(l)

func canAttackSplasher*(w: World, r: Robot, l: Loc): bool =
  if not r.isActionReady(): return false
  if not w.canActLocation(r, l, UnitSpecs[utSplasher].actionRadiusSquared):
    return false
  r.paint >= UnitSpecs[utSplasher].attackCost

func canAttackMopper*(w: World, r: Robot, l: Loc): bool =
  if not r.isActionReady(): return false
  if not w.canActLocation(r, l, UnitSpecs[utMopper].actionRadiusSquared):
    return false
  if r.paint < UnitSpecs[utMopper].attackCost: return false
  w.isPassable(l)

func canAttackRobot*(w: World, r: Robot, l: Loc): bool =
  case r.kind
  of utSoldier: w.canAttackSoldier(r, l)
  of utSplasher: w.canAttackSplasher(r, l)
  of utMopper: w.canAttackMopper(r, l)
  else: false

proc soldierAttack(w: World, r: Robot, l: Loc, secondary: bool) =
  ## `InternalRobot.soldierAttack`, in its own order: the paint cost comes off
  ## FIRST, then either the tower takes 50 or the tile is painted. A soldier
  ## can never paint over enemy paint and can never damage a robot.
  let colour = paintFor(r.team, secondary)
  r.addPaint(-UnitSpecs[utSoldier].attackCost)
  w.stats.paintSpent[ord(r.team)] += UnitSpecs[utSoldier].attackCost
  let target = w.getRobot(l)
  if target != nil and target.kind.isTowerType():
    if target.team != r.team:
      let dealt = min(UnitSpecs[utSoldier].attackStrength, target.health)
      w.stats.towerDamageDealt[ord(r.team)] += dealt
      w.addHealth(target, -UnitSpecs[utSoldier].attackStrength)
  else:
    let existing = w.getPaint(l)
    if w.isPaintable(l) and
        (existing == PaintNone or paintIsTeam(existing, r.team)):
      if existing == PaintNone: w.stats.tilesPainted[ord(r.team)] += 1
      w.setPaint(l, colour)
  w.noteFirstAction(r, Bc25ActionPaint)

proc splasherAttack(w: World, r: Robot, l: Loc, secondary: bool) =
  ## `InternalRobot.splasherAttack`: every tile within r2 <= 4 of the centre,
  ## IN ENGINE SCAN ORDER. A tile carrying enemy paint is repainted only when
  ## it is also within r2 <= 2 — which is the only way a clan takes ground
  ## back at scale. There is no `else` between the tower damage and the paint,
  ## so one splash can both break a tower and recolour its tile.
  let colour = paintFor(r.team, secondary)
  r.addPaint(-UnitSpecs[utSplasher].attackCost)
  w.stats.paintSpent[ord(r.team)] += UnitSpecs[utSplasher].attackCost
  w.stats.splashAttacks[ord(r.team)] += 1
  for newLoc in w.locationsWithinRadiusSquared(
      l, SplasherAttackAoeRadiusSquared):
    let target = w.getRobot(newLoc)
    if target != nil and target.kind.isTowerType() and target.team != r.team:
      let dealt = min(UnitSpecs[utSplasher].aoeAttackStrength, target.health)
      w.stats.towerDamageDealt[ord(r.team)] += dealt
      w.addHealth(target, -UnitSpecs[utSplasher].aoeAttackStrength)
    if not w.isPaintable(newLoc): continue
    let existing = w.getPaint(newLoc)
    if existing == PaintNone or paintIsTeam(existing, r.team):
      if existing == PaintNone:
        w.stats.tilesPainted[ord(r.team)] += 1
        w.stats.tilesPaintedBySplashers[ord(r.team)] += 1
      w.setPaint(newLoc, colour)
    elif l.isWithinDistanceSquared(newLoc,
        SplasherAttackEnemyPaintRadiusSquared):
      w.stats.tilesOverpainted[ord(r.team)] += 1
      w.stats.tilesPaintedBySplashers[ord(r.team)] += 1
      w.setPaint(newLoc, colour)
  w.noteFirstAction(r, Bc25ActionSplash)

proc mopperAttack(w: World, r: Robot, l: Loc, secondary: bool) =
  ## `InternalRobot.mopperAttack`: an enemy ROBOT on the tile loses 10 paint
  ## and the mopper gains 5; either way a tile that does not carry OUR paint
  ## becomes BARE, not ours.
  let colour = paintFor(r.team, secondary)
  r.addPaint(-UnitSpecs[utMopper].attackCost)
  let target = w.getRobot(l)
  if target != nil and target.kind.isRobotType() and target.team != r.team:
    target.addPaint(-MopperAttackPaintDepletion)
    r.addPaint(MopperAttackPaintAddition)
  if w.isPaintable(l) and
      not (hasPaintTeam(w.getPaint(l)) and
           teamFromPaint(w.getPaint(l)) == teamFromPaint(colour)):
    if hasPaintTeam(w.getPaint(l)):
      w.stats.tilesMopped[ord(r.team)] += 1
    w.setPaint(l, PaintNone)
  w.noteFirstAction(r, Bc25ActionMop)

proc doAttackRobot*(w: World, r: Robot, l: Loc, secondary = false) =
  ## `RobotControllerImpl.attack`: the cooldown is charged BEFORE
  ## `robot.attack` deducts the attack's paint cost, so the surcharge is read
  ## from the PRE-COST stash.
  if not w.canAttackRobot(r, l):
    w.refusedActions += 1
    return
  r.addActionCooldownTurns(UnitSpecs[r.kind].actionCooldown)
  case r.kind
  of utSoldier: w.soldierAttack(r, l, secondary)
  of utSplasher: w.splasherAttack(r, l, secondary)
  of utMopper: w.mopperAttack(r, l, secondary)
  else: discard

# --- 4.5 mop swing ----------------------------------------------------------

func canMopSwing*(w: World, r: Robot, d: Dir): bool =
  if not r.isActionReady(): return false
  if r.kind != utMopper: return false
  if d != dNorth and d != dSouth and d != dEast and d != dWest: return false
  w.onTheMap(r.loc + d)

proc doMopSwing*(w: World, r: Robot, d: Dir) =
  ## `InternalRobot.mopSwing`: the six offsets of that direction — three tiles
  ## one step away and three two steps away — and every ENEMY ROBOT (never a
  ## tower) standing there loses 5 paint. Off-map offsets are skipped and
  ## nothing is repainted.
  if not w.canMopSwing(r, d):
    w.refusedActions += 1
    return
  r.addActionCooldownTurns(AttackMopperSwingCooldown)
  let dirIdx = (if d == dNorth: 0 elif d == dSouth: 1 elif d == dEast: 2
                else: 3)
  for i in 0 .. 5:
    let l = loc(r.loc.x + MopSwingDx[dirIdx][i],
                r.loc.y + MopSwingDy[dirIdx][i])
    if not w.onTheMap(l): continue
    let target = w.getRobot(l)
    if target != nil and target.kind.isRobotType() and target.team != r.team:
      target.addPaint(-MopperSwingPaintDepletion)
  w.stats.mopSwings[ord(r.team)] += 1
  w.noteFirstAction(r, Bc25ActionMopSwing)

# --- 4.8 mark / unmark ------------------------------------------------------

func canMark*(w: World, r: Robot, l: Loc): bool =
  if not r.kind.isRobotType(): return false
  if not w.canActLocation(r, l, MarkRadiusSquared): return false
  w.isPaintable(l)

proc doMark*(w: World, r: Robot, l: Loc, secondary = false) =
  ## NO COOLDOWN AND NO PAINT COST. `setMarker` charges nothing, so the spec's
  ## "1 paint" for a bare `mark()` is prose the engine does not implement
  ## (docs/RULES-BC25.md §Divergences, prose item 4).
  if not w.canMark(r, l):
    w.refusedActions += 1
    return
  w.setMarker(r.team, l, if secondary: MarkerSecondary else: MarkerPrimary)
  w.noteFirstAction(r, Bc25ActionMark)

func canRemoveMark*(w: World, r: Robot, l: Loc): bool =
  if not r.kind.isRobotType(): return false
  if not w.canActLocation(r, l, MarkRadiusSquared): return false
  w.getMarker(r.team, l) != 0

proc doRemoveMark*(w: World, r: Robot, l: Loc) =
  if not w.canRemoveMark(r, l):
    w.refusedActions += 1
    return
  w.setMarker(r.team, l, MarkerNone)

# --- 4.9 mark a pattern -----------------------------------------------------

func canMarkTowerPattern*(w: World, r: Robot, kind: TowerKind,
                          l: Loc): bool =
  if not r.kind.isRobotType(): return false
  if not w.canActLocation(r, l, BuildTowerRadiusSquared): return false
  if not w.hasRuin(l): return false
  if not w.isValidPatternCenter(l, true): return false
  r.paint >= MarkPatternPaintCost

proc doMarkTowerPattern*(w: World, r: Robot, kind: TowerKind, l: Loc) =
  if not w.canMarkTowerPattern(r, kind, l):
    w.refusedActions += 1
    return
  r.addPaint(-MarkPatternPaintCost)
  w.stats.paintSpent[ord(r.team)] += MarkPatternPaintCost
  w.markPattern(patternKindFor(kind), r.team, l)
  w.noteFirstAction(r, Bc25ActionMarkTowerPattern)

func canMarkResourcePattern*(w: World, r: Robot, l: Loc): bool =
  if not r.kind.isRobotType(): return false
  if not w.canActLocation(r, l, ResourcePatternRadiusSquared): return false
  if not w.isValidPatternCenter(l, false): return false
  r.paint >= MarkPatternPaintCost

proc doMarkResourcePattern*(w: World, r: Robot, l: Loc) =
  if not w.canMarkResourcePattern(r, l):
    w.refusedActions += 1
    return
  r.addPaint(-MarkPatternPaintCost)
  w.stats.paintSpent[ord(r.team)] += MarkPatternPaintCost
  w.markPattern(pkResource, r.team, l)
  w.noteFirstAction(r, Bc25ActionMarkSrp)

# --- 4.10 complete an SRP ---------------------------------------------------

proc canCompleteResourcePattern*(w: World, r: Robot, l: Loc,
                                 charge: Robot = nil): bool =
  if not r.kind.isRobotType(): return false
  if not w.canActLocation(r, l, ResourcePatternRadiusSquared): return false
  if w.getMoney(r.team) < CompleteResourcePatternCost: return false
  if w.hasResourcePatternCenter(l, r.team): return false
  if not w.isValidPatternCenter(l, false): return false
  w.checkResourcePattern(r.team, l, charge)

proc doCompleteResourcePattern*(w: World, r: Robot, l: Loc) =
  ## `GameWorld.completeResourcePattern`: the centre is registered with
  ## LIFETIME 0 and the team pays 200 chips. It starts paying at lifetime
  ## >= 50, which `updateResourcePatterns` reaches at the top of the fiftieth
  ## round after this one.
  if not w.canCompleteResourcePattern(r, l):
    w.refusedActions += 1
    return
  let i = w.idx(l)
  if w.srpTeamByLoc[i] == 0:
    w.srpCentres.add(l)
  w.srpTeamByLoc[i] = int8(ord(r.team) + 1)
  w.srpLifetimes[i] = 0
  w.addMoney(r.team, -CompleteResourcePatternCost)
  w.stats.srpCompleted[ord(r.team)] += 1
  discard w.beat(BeatSrpCompleted, "srp_completed", ord(r.team),
    l.x * 100 + l.y, w.srpCentres.len)
  w.noteFirstAction(r, Bc25ActionCompleteSrp)

# --- 4.12 transfer / withdraw paint -----------------------------------------

func canTransferPaint*(w: World, r: Robot, l: Loc, amount: int): bool =
  if not w.canActLocation(r, l, PaintTransferRadiusSquared): return false
  if not r.isActionReady(): return false
  let target = w.getRobot(l)
  if target == nil: return false
  if l == r.loc: return false
  if amount == 0: return false
  if target.team != r.team: return false
  if r.kind.isTowerType(): return false
  if amount > 0 and r.kind != utMopper: return false
  if target.kind.isRobotType() and amount < 0: return false
  if -1 * amount > target.paint: return false
  amount <= r.paint

proc doTransferPaint*(w: World, r: Robot, l: Loc, amount: int) =
  ## `RobotControllerImpl.transferPaint`: the paint MOVES FIRST and the +10
  ## cooldown is charged after, so the surcharge is read from the
  ## POST-TRANSFER stash. That is the opposite order from an attack, and both
  ## are the engine's.
  if not w.canTransferPaint(r, l, amount):
    w.refusedActions += 1
    return
  let target = w.getRobot(l)
  r.addPaint(-amount)
  target.addPaint(amount)
  r.addActionCooldownTurns(PaintTransferCooldown)
  if amount > 0: w.stats.paintTransferred[ord(r.team)] += amount
  w.noteFirstAction(r,
    if amount > 0: Bc25ActionTransfer else: Bc25ActionWithdraw)

# --- 4.15 disintegrate ------------------------------------------------------

proc doDisintegrate*(w: World, r: Robot) =
  ## `RobotControllerImpl.disintegrate` throws `RobotDeathException`, which
  ## `updateRobot` turns into a `destroyRobot`. Free, no range, no cooldown.
  w.noteFirstAction(r, Bc25ActionDisintegrate)
  w.destroyRobot(r.id)

# ---------------------------------------------------------------------------
#  Turn scaffolding
# ---------------------------------------------------------------------------

proc processBeginningOfTurn*(w: World, r: Robot) =
  ## Rule 3, `InternalRobot.processBeginningOfTurn`.
  r.sentMessages = 0
  r.towerSingleAttacked = false
  r.towerAreaAttacked = false
  r.actionCooldown = max(0, r.actionCooldown - CooldownsPerTurn)
  r.movementCooldown = max(0, r.movementCooldown - CooldownsPerTurn)
  w.opsUsedPeak = max(w.opsUsedPeak, r.opsUsed)
  r.opsLeft = budgetFor(r.kind)
  r.opsUsed = 0

proc processEndOfTurn*(w: World, r: Robot) =
  ## Rule 5, `InternalRobot.processEndOfTurn`, for a ROBOT only, in the
  ## engine's own order: the territory bill, then the crowding bill, then the
  ## 20 HP for standing at exactly zero paint, then `roundsAlive += 1`.
  ##
  ## THE CROWDING COUNT INCLUDES TOWERS.
  if not r.alive: return
  if r.kind.isRobotType():
    let t = ord(r.team)
    w.stats.robotRounds[t] += 1
    let here = w.getPaint(r.loc)
    let mopperMultiplier =
      if r.kind == utMopper: MopperPaintPenaltyMultiplier else: 1
    var allies = 0
    for l in w.locationsWithinRadiusSquared(r.loc, 2):
      let bot = w.getRobot(l)
      if bot != nil and bot.team == r.team and bot.id != r.id:
        allies += 1
    if not hasPaintTeam(here):
      r.addPaint(-PenaltyNeutralTerritory * mopperMultiplier)
      r.addPaint(-allies)
    elif teamFromPaint(here) == r.team.other():
      r.addPaint(-PenaltyEnemyTerritory * mopperMultiplier)
      r.addPaint(-2 * allies)
    else:
      r.addPaint(-allies)
    if r.paint == 0:
      w.stats.robotRoundsStarved[t] += 1
      w.starvedThisRound[t] += 1
      w.addHealth(r, -NoPaintDamage)
  if r.alive:
    r.roundsAlive += 1

# ---------------------------------------------------------------------------
#  Construction
# ---------------------------------------------------------------------------

proc newWorld*(spec: MapSpec, maxRounds: int): World =
  let n = spec.width * spec.height
  var walls = 0
  for v in spec.walls:
    if v: walls += 1
  result = World(
    map: spec,
    width: spec.width,
    height: spec.height,
    currentRound: 0,
    maxRounds: maxRounds,
    running: true,
    idGen: initIdGenerator(spec.randomSeed),
    rand: initJavaRandom(spec.randomSeed),
    symmetry: spec.symmetry,
    areaWithoutWalls: n - walls,
    walls: spec.walls,
    ruinAt: newSeq[bool](n),
    colours: newSeq[int8](n),
    towersByLoc: newSeq[int8](n),
    occupant: newSeq[Robot](n),
    robotsById: initTable[int, Robot](),
    srpTeamByLoc: newSeq[int8](n),
    srpLifetimes: newSeq[int32](n),
    winner: teamA,
    domination: dfNone,
    hashChain: 0xCBF29CE484222325'u64)
  result.markers[0] = newSeq[int8](n)
  result.markers[1] = newSeq[int8](n)

  result.stats.money[0] = InitialTeamMoney
  result.stats.money[1] = InitialTeamMoney

  ## `GameWorld`'s constructor walks the ruin array into `allRuins` in
  ## ASCENDING TILE INDEX order.
  for r in spec.ruins:
    result.ruinAt[r.x + r.y * spec.width] = true
  for i in 0 ..< n:
    if result.ruinAt[i]: result.allRuins.add(result.indexToLoc(i))

  ## The map's own pre-painted tiles, through `setPaint` so the live count is
  ## right from round 0. Walls and ruins silently take nothing.
  for p in spec.paint:
    result.setPaint(loc(p.x, p.y), p.colour)

  ## The four starting towers. `LiveMap` sorts `initialBodies` by ASCENDING
  ## ID before the world sees them, and that sorted order is the initial exec
  ## order. Each is spawned at LEVEL ONE and immediately upgraded to LEVEL
  ## TWO, which carries no damage (they are undamaged) and leaves the 500
  ## paint alone.
  var bodies = spec.initialBodies
  for i in 1 ..< bodies.len:
    var j = i
    while j > 0 and bodies[j - 1].id > bodies[j].id:
      swap(bodies[j - 1], bodies[j])
      dec j
  for b in bodies:
    let team = if b.team == 1: teamA else: teamB
    let kind = if b.kind == 1: utLevelOnePaintTower else: utLevelOneMoneyTower
    let at = loc(b.x, b.y)
    let robot = result.spawnRobotWithId(b.id, kind, at, team)
    result.towersByLoc[result.idx(at)] = int8(ord(team) + 1)
    if not result.ruinAt[result.idx(at)]:
      result.ruinAt[result.idx(at)] = true
      result.allRuins.add(at)
    let newType = kind.nextLevel()
    robot.health = upgradedHealth(kind, newType, robot.health)
    robot.kind = newType
    result.damageIncrease[ord(team)] += defenseBuffOnUpgrade(newType)

  ## `trulyPaintable` is derived AFTER the towers have added their ruins, so
  ## it is the count of tiles that can ever hold paint at round 0.
  var ruins = 0
  for v in result.ruinAt:
    if v: ruins += 1
  result.trulyPaintable = n - walls - ruins

func mapDigest*(w: World): string =
  ## A stable identity for the loaded map, folded into the replay so a viewer
  ## cannot re-derive a match against a different terrain file.
  var h = 0xCBF29CE484222325'u64
  for i in 0 ..< w.walls.len:
    var v = 0
    if w.map.walls[i]: v = v or 1
    if w.ruinAt[i]: v = v or 2
    v = v or (int(w.colours[i]) shl 2)
    h = (h xor uint64(v)) * 0x100000001B3'u64
  toHex(h)
