## Shared bc21 chassis scaffolding: the team's doctrine, per-robot memory, the
## team's shared map knowledge, and the DECISION BUDGET that replaces the
## engine's JVM bytecode limit.
##
## The engine meters a robot's turn in bytecodes through an instrumenting class
## loader. There is no JVM here, so every primitive step a bot takes — a tile
## sensed, a tile detected, a robot examined, a BFS node expanded, a direction
## evaluated, a flag read, an empower radius scored — is charged against
## `Robot.opsLeft` instead, and the robot ends its turn WHERE IT STANDS when
## the budget runs out (no mid-turn resumption). Bounded, machine-independent,
## deterministic, and a deliberate divergence
## (docs/RULES-BC21.md §Divergences item 1).
##
## The budget is ENFORCED BY THE SIM, not by the bot: every loop below runs
## through `spend`, and `tests/test_bc21_baselines.nim` asserts that no robot
## ever exceeds it.

import std/tables
import ../../../rng
import ../knobs, ../world, ../empower
import flags

export knobs, world, empower, flags, rng, tables

type
  Brain* = ref object
    ## One robot's private memory, keyed by robot id so it follows the robot
    ## for its whole life. In Battlecode each robot gets its own class loader,
    ## so a bot's `static` fields are per robot — reproduced here.
    rng*: JavaRandom
    turnCount*: int
    scoutDir*: int
    isScout*: bool
    hasTarget*: bool
    target*: Loc
    history*: seq[Loc]      ## the 6-tile no-repeat window that breaks oscillation

  CenterNote* = object
    loc*: Loc
    influence*: int         ## last known; -1 when unknown
    hostile*: bool          ## true for an enemy Center, false for a neutral one
    round*: int

  Side* = ref object
    team*: Team
    doctrine*: Doctrine21
    brains*: Table[int, Brain]
    ownCenters*: seq[Loc]
    knownCenters*: seq[CenterNote]
      ## Neutral and enemy Centers this team has sensed or been told about.
    slandererSightings*: seq[tuple[loc: Loc, round: int]]
    ladder*: Table[int, int]      ## per-Center bid ladder value
    lastVotes*: int
    firstBuilt*: array[RobotKind, bool]
    opened*: int                  ## how many opening builds have been made
    scoutsSent*: int
    nextScoutDir*: int
    defenders*: seq[int]
      ## Politicians the Center built as DEFENCE. They hold the ring around
      ## their home rather than walking off with the invasion — the D2 rule
      ## that stops a knob setting producing a Center nobody guards.

proc newSide*(team: Team, doctrine: Doctrine21): Side =
  Side(team: team, doctrine: doctrine, brains: initTable[int, Brain](),
       ladder: initTable[int, int]())

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

func alive*(w: World, side: Side, kind: RobotKind): int =
  w.typeCount[ord(side.team)][kind]

proc markDefender*(side: Side, id: int) =
  if side.defenders.len >= 64: side.defenders.delete(0)
  side.defenders.add(id)

proc isDefender*(side: Side, id: int): bool =
  for d in side.defenders:
    if d == id: return true
  false

proc firstBuild*(w: World, side: Side, kind: RobotKind) =
  ## `first_build` is emitted once per team per unit kind — the beat the
  ## scrubber draws.
  if side.firstBuilt[kind]: return
  side.firstBuilt[kind] = true
  discard w.beat(BeatFirstBuild, "first_build", ord(side.team), ord(kind),
    w.currentRound)

# ---------------------------------------------------------------------------
#  Shared map knowledge
# ---------------------------------------------------------------------------

proc noteCenter*(side: Side, l: Loc, influence: int, hostile: bool,
                 round: int) =
  for i in 0 ..< side.knownCenters.len:
    if side.knownCenters[i].loc == l:
      if influence >= 0: side.knownCenters[i].influence = influence
      side.knownCenters[i].hostile = hostile
      side.knownCenters[i].round = round
      return
  if side.knownCenters.len >= 24: return
  side.knownCenters.add(CenterNote(loc: l, influence: influence,
                                   hostile: hostile, round: round))

proc forgetCenter*(side: Side, l: Loc) =
  for i in 0 ..< side.knownCenters.len:
    if side.knownCenters[i].loc == l:
      side.knownCenters.delete(i)
      return

proc noteSlanderer*(side: Side, l: Loc, round: int) =
  for i in 0 ..< side.slandererSightings.len:
    if side.slandererSightings[i].loc == l:
      side.slandererSightings[i].round = round
      return
  if side.slandererSightings.len >= 16:
    side.slandererSightings.delete(0)
  side.slandererSightings.add((loc: l, round: round))

proc refreshOwnCenters*(w: World, side: Side) =
  side.ownCenters.setLen(0)
  for _, r in w.robotsById:
    if r.kind == rtEnlightenmentCenter and r.team == side.team:
      side.ownCenters.add(r.loc)

proc nearestOwnCenter*(side: Side, from0: Loc): Loc =
  var best = from0
  var bestD = high(int)
  for l in side.ownCenters:
    let d = from0.distanceSquaredTo(l)
    if d < bestD:
      bestD = d
      best = l
  best

proc nearestHostileCenter*(side: Side, from0: Loc): tuple[ok: bool, at: Loc] =
  ## The nearest known ENEMY Center — never a neutral one. A muckraker hunting
  ## slanderers wants the enemy's ring, and `bestTarget` under
  ## `neutral_centers_first` would send it to a neutral Center instead.
  var bestD = high(int)
  for note in side.knownCenters:
    if not note.hostile: continue
    let d = from0.distanceSquaredTo(note.loc)
    if d < bestD:
      bestD = d
      result.ok = true
      result.at = note.loc

proc mirrorTarget*(w: World, side: Side, from0: Loc): Loc =
  ## With no known enemy Center, the map's symmetry axis points at one: the
  ## mirror of an own Center is always an enemy Center on a symmetric map.
  if side.ownCenters.len == 0: return w.symmetricLoc(from0)
  w.symmetricLoc(side.nearestOwnCenter(from0))

# ---------------------------------------------------------------------------
#  Sensing, charged against the budget
# ---------------------------------------------------------------------------

iterator sensedTiles*(w: World, r: Robot): Loc =
  ## Every tile this robot can SENSE this turn, charged one credit each.
  for l in w.locationsWithinRadiusSquared(r.loc,
      RobotSpecs[r.kind].sensorRadiusSquared):
    if r.opsLeft <= 0: break
    r.opsLeft -= 1
    yield l

iterator sensedTilesWithin*(w: World, r: Robot, r2: int): Loc =
  let limit = min(r2, RobotSpecs[r.kind].sensorRadiusSquared)
  for l in w.locationsWithinRadiusSquared(r.loc, limit):
    if r.opsLeft <= 0: break
    r.opsLeft -= 1
    yield l

proc observe*(w: World, side: Side, r: Robot) =
  ## The one sensing pass every role starts with: update the team's shared maps
  ## from what THIS robot can legitimately see, respecting the fog
  ## (politicians and slanderers see a slanderer as a politician).
  for l in w.sensedTiles(r):
    let bot = w.getRobot(l)
    if bot == nil: continue
    if bot.kind == rtEnlightenmentCenter:
      if bot.team == side.team:
        side.forgetCenter(l)
      else:
        side.noteCenter(l, bot.influence, bot.team.isPlayer(), w.currentRound)
    elif bot.team != side.team:
      if sensedKind(r.kind, bot.kind) == rtSlanderer:
        side.noteSlanderer(l, w.currentRound)
