## Shared bc20 chassis scaffolding: the team's doctrine, per-robot memory, and
## the DECISION BUDGET that replaces the engine's JVM bytecode limit.
##
## The engine meters a robot's turn in bytecodes through an instrumenting class
## loader. There is no JVM here, so every primitive step a bot takes — a tile
## sensed, a robot examined, a BFS node expanded, a direction evaluated, a
## block read — is charged against `Robot.opsLeft` instead, and the robot ends
## its turn WHERE IT STANDS when the budget runs out (no mid-turn resumption).
## Bounded, machine-independent, deterministic, and a deliberate divergence
## (docs/RULES-BC20.md §Divergences).
##
## The budget is ENFORCED BY THE SIM, not by the bot: every loop below runs
## through `spend`, and `tests/test_bc20_baselines.nim` asserts that no robot
## ever exceeds it.

import std/tables
import ../../../rng
import ../knobs, ../world, ../flood

export knobs, world, flood, rng, tables

type
  Brain* = ref object
    ## One robot's private memory, keyed by robot id so it follows the robot
    ## for its whole life. In Battlecode each robot gets its own class loader,
    ## so a bot's `static` fields are per robot — reproduced here.
    rng*: JavaRandom
    turnCount*: int
    role*: int              ## per-unit role slot (wall index, drone station…)
    hasRole*: bool
    hasTarget*: bool
    target*: Loc
    hasSoupTip*: bool
    soupTip*: Loc
    announcedSoup*: bool
    mode*: int              ## landscaper: 0 wall, 1 terraform, 2 attack
    history*: seq[Loc]      ## the 6-tile no-repeat window that breaks oscillation

  Side* = ref object
    team*: Team
    doctrine*: Doctrine20
    brains*: Table[int, Brain]
    hqLoc*: Loc
    hasHq*: bool
    enemyHqLoc*: Loc
    hasEnemyHq*: bool
    builderId*: int
    wallClosed*: bool
    wallClosedRound*: int
    rushLaunched*: bool
    rushUnits*: int
    soupTips*: seq[Loc]
    firstBuilt*: array[RobotKind, bool]
    nextBlockToRead*: int
    wallRoundCache*: int

proc newSide*(team: Team, doctrine: Doctrine20): Side =
  Side(team: team, doctrine: doctrine, brains: initTable[int, Brain](),
       builderId: -1, wallClosedRound: -1, nextBlockToRead: 1,
       wallRoundCache: -1)

proc brainFor*(side: Side, r: Robot): Brain =
  if r.id notin side.brains:
    ## Seeded from the robot id, so a robot's private stream is a pure
    ## function of the map seed (which decides ids) and nothing else.
    side.brains[r.id] = Brain(rng: initJavaRandom(r.id))
  side.brains[r.id]

proc spend*(r: Robot, ops: int): bool {.discardable.} =
  ## Charge `ops` decision credits. False once the robot is out of budget;
  ## every loop in the chassis checks it and stops.
  if r.opsLeft <= 0: return false
  r.opsLeft -= ops
  r.opsLeft > 0

func other*(team: Team): Team =
  if team == teamA: teamB else: teamA

func alive*(w: World, side: Side, kind: RobotKind): int =
  w.typeCount[ord(side.team)][kind]

proc ownHq*(w: World, side: Side): Robot =
  let id = w.hqId[ord(side.team)]
  if id >= 0 and id in w.robotsById: w.robotsById[id] else: nil

proc noteHq*(w: World, side: Side) =
  let hq = w.ownHq(side)
  if hq != nil:
    side.hqLoc = hq.loc
    side.hasHq = true

proc symmetricLoc*(w: World, l: Loc): Loc =
  ## The map is symmetric, so the enemy HQ is at the mirror of ours. The
  ## chassis uses the symmetry the SIM recomputed, never the map file's.
  case w.symmetry
  of symVertical: loc(w.width - 1 - l.x, l.y)
  of symHorizontal: loc(l.x, w.height - 1 - l.y)
  of symRotational: loc(w.width - 1 - l.x, w.height - 1 - l.y)

proc noteEnemyHq*(w: World, side: Side) =
  if side.hasEnemyHq: return
  if not side.hasHq: return
  side.enemyHqLoc = w.symmetricLoc(side.hqLoc)
  side.hasEnemyHq = true

proc wallTarget*(w: World, side: Side): int =
  ## `landscaper.nim` mode (a): the bar every one of the 8 tiles adjacent to
  ## the own HQ must clear. The note's `waterLevel(round + 400) + 2` is a
  ## MOVING bar, and a moving bar declares the wall closed at round 76 on a map
  ## whose ring already sits at elevation 4 and then lets the same ring drown
  ## at round 932. The bar used here is the same expression evaluated at the
  ## LAST round the game can reach, so a wall is built once, to a height the
  ## water never gets to, and stays closed.
  int(waterLevelAt(min(WaterTableMaxRound,
                       max(w.currentRound + 400, w.maxRounds)))) + 2

proc ringTiles*(w: World, centre: Loc): seq[Loc] =
  for d in MoveDirs:
    let l = centre + d
    if w.onTheMap(l): result.add(l)

proc effectiveWallRound*(w: World, side: Side): int =
  ## `wall_hq_round` says WHEN to start walling; the map says when it is too
  ## late. An HQ is a building, so dirt dropped on its tile buries it rather
  ## than raising it: the only thing that keeps an HQ dry is a ring of eight
  ## tiles the water can never cross. On a low map (`maptestsmall`'s ring sits
  ## at elevation 1 and floods at round 256) a doctrine that says "wall at 300"
  ## has already lost, so the chassis starts 200 rounds before the ring's own
  ## flood round when that is EARLIER than the knob.
  ##
  ## `wall_hq_round = 0` still means NEVER, which is what gives the knob its
  ## teeth: never walling drowns the HQ, exactly as the sheet documents.
  if side.doctrine.wallHqRound == 0: return 0
  if side.wallRoundCache >= 0: return side.wallRoundCache
  if not side.hasHq: return side.doctrine.wallHqRound
  var minElev = high(int)
  for l in w.ringTiles(side.hqLoc):
    minElev = min(minElev, w.map.elevation[w.idx(l)])
  if minElev == high(int) or minElev < 0:
    side.wallRoundCache = side.doctrine.wallHqRound
  else:
    side.wallRoundCache = min(side.doctrine.wallHqRound,
      max(1, roundWaterReaches(minElev) - 200))
  side.wallRoundCache

proc latticeTarget*(side: Side, round: int): int =
  ## `lattice.nim`: every non-wall tile inside `lattice_radius` is raised to
  ## `waterLevel(round + 250) + 1`.
  int(waterLevelAt(min(WaterTableMaxRound, round + 250))) + 1

proc willFloodNextRound*(w: World, l: Loc): bool =
  ## A tile a ground unit must not be standing on when the flood arrives.
  if not w.onTheMap(l): return false
  if w.isFlooded(l): return true
  float32(w.getDirt(l)) < waterLevelAt(w.currentRound + 1)

iterator sensed*(w: World, r: Robot): Loc =
  ## Every tile this robot can see this turn, charged one credit each.
  let r2 = w.currentSensorRadiusSquared(r)
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    if r.opsLeft <= 0: break
    r.opsLeft -= 1
    yield l

proc firstBuild*(w: World, side: Side, kind: RobotKind) =
  ## `first_build` is emitted once per team per unit kind — the beat the
  ## scrubber draws.
  if side.firstBuilt[kind]: return
  side.firstBuilt[kind] = true
  w.emit("first_build", ord(side.team), ord(kind), w.currentRound)
