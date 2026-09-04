## Shared bc24 chassis scaffolding: the team's doctrine, per-duck memory, the
## team's navigation fields and shared knowledge, and the DECISION BUDGET that
## replaces the engine's JVM bytecode limit.
##
## The engine meters a duck's turn in bytecodes through an instrumenting class
## loader. There is no JVM here, so every primitive step a bot takes — a tile
## sensed, a duck examined, a flag examined, a BFS node expanded, a direction
## evaluated, a shared-array slot read or written, a trap-placement candidate
## scored — is charged against `Robot.opsLeft` instead, and the duck ends its
## turn WHERE IT STANDS when the budget runs out (no mid-turn resumption).
## Bounded, machine-independent, deterministic, and a deliberate divergence
## (docs/RULES-BC24.md §Divergences item 1).
##
## The budget is ENFORCED BY THE SIM, not by the bot: every loop below runs
## through `spend`, and `tests/test_bc24_baselines.nim` asserts that no duck
## ever exceeds it.
##
## NOTHING IN HERE IS RANDOM. A duck's sequence id is its slot in the fixed
## exec order, its role is claimed by a deterministic least-crowded rule, and
## the navigation fields are a pure function of the terrain — so a bc24 game is
## a pure function of (map, sheets, chassis, side assignment).

import ../knobs, ../world, ../flags, ../traps

export knobs, world, flags, traps

const
  NavAnchors* = 6
    ## The six spawn-zone centres. Every long walk in this chassis is a
    ## downhill step on one of their distance fields; short walks are greedy.
  HistoryLen* = 6
    ## The no-repeat window that breaks oscillation (the note's "6-tile
    ## no-repeat history").
  FieldRefreshInterval* = 200
    ## Fields are recomputed at round 1, at round 201 (the round the dam
    ## falls) and every 200 rounds after, so digging and filling eventually
    ## show up in the routing without costing a BFS per turn.
  WaterStepCost* = 5
    ## Water is not a wall — a 30-crumb fill undoes it — so it is expensive
    ## rather than impassable in the field. The dial queue below has six
    ## buckets, which is exactly `WaterStepCost + 1`.

type
  Brain* = ref object
    ## One duck's private memory, keyed by its SEQUENCE ID so it follows the
    ## duck for the whole game. In Battlecode each robot gets its own class
    ## loader, so a bot's `static` fields are per robot — reproduced here.
    role*: int              ## 0..2 defend own flag i, 3..5 raid enemy flag i
    hasRole*: bool
    history*: array[HistoryLen, Loc]
    histLen*: int
    histPos*: int
    setupFlag*: int         ## the own flag this duck relocates in setup, or -1
    setupDone*: bool
    lastDist*: int
    stuck*: int

  FlagNote* = object
    loc*: Loc
    round*: int
    sensed*: bool           ## true = seen, false = broadcast approximation

  Side* = ref object
    team*: Team
    doctrine*: Doctrine24
    brains*: array[RobotCapacity, Brain]
    roleCount*: array[6, int]
    census*: tuple[builders, healers, attackers: int]
    ownCentres*: array[3, Loc]
    enemyCentres*: array[3, Loc]
    dist*: array[NavAnchors, seq[int32]]
      ## Distance fields to the six spawn-zone centres. Index `i*2 + (0 for A,
      ## 1 for B)` in the engine's own centre order, so `ownField(i)` and
      ## `enemyField(i)` are one add apart.
    fieldsRound*: int
    knownEnemyFlag*: array[3, FlagNote]
    distress*: array[3, int]
    chokeTiles*: seq[Loc]
    chokeMeasured*: bool
    bridgeTiles*: seq[Loc]
      ## THE FLOOR NO KNOB CAN LOWER, second clause: on a map whose two halves
      ## are separated by WATER as well as by the dam (`Rivers` and `Tunnels`
      ## in the shipped `small` pool are exactly that), no doctrine can reach
      ## the enemy at all until somebody fills a crossing. These are the water
      ## tiles on the cheapest route, and the builders fill them WHATEVER
      ## `water_dig_policy` says — because that knob is about where crumbs go,
      ## not about whether the flock can play (docs/RULES-BC24.md §Divergences
      ## item 12).
    bridgeSlot*: int
      ## Which navigation field the bridge route was traced on, so a builder
      ## walking to the crossing follows the same route rather than a greedy
      ## line into a wall.
    landReach*: seq[int32]
    trapSlot*: int          ## alternates stun/explosive under `trap_mix: mixed`
    carriers*: seq[int]     ## own duck ids currently carrying an enemy flag
    escorts*: seq[int]
      ## The `flag_carry_escort` nearest own ducks to a carrier, assigned ONCE
      ## a round in exec order so the assignment is deterministic. Ducks rally
      ## from `EscortRallyRadiusSquared`, which is well beyond a duck's own
      ## vision: the carrier's position is on the shared array, so converging
      ## on it is something the flock legitimately knows how to do.
    firstActionDone*: bool
    ## `examplefuncsplayer24`'s per-duck `static final Random rng =
    ## new Random(6147)`. Static fields are PER ROBOT under the instrumenter,
    ## and they live on the Side rather than in a global so a second game in
    ## the same process starts from a clean stream.
    scaffoldRng*: array[RobotCapacity, JavaRandom]
    scaffoldTurns*: array[RobotCapacity, int]
    ## Scratch reused across turns so a duck's turn allocates nothing.
    buckets*: array[6, seq[int32]]

const Unreachable* = int32(1_000_000)

proc newSide*(team: Team, doctrine: Doctrine24): Side =
  result = Side(team: team, doctrine: doctrine, bridgeSlot: -1)
  result.census = doctrine.census()
  for i in 0 ..< RobotCapacity:
    result.brains[i] = Brain(role: -1, setupFlag: -1, lastDist: high(int))
  for i in 0 .. 2:
    result.knownEnemyFlag[i] = FlagNote(loc: loc(-1, -1), round: -1)
  for i in 0 ..< RobotCapacity:
    result.scaffoldRng[i] = initJavaRandom(6147)

func seqIdOf*(r: Robot): int = r.execIndex div 2
  ## 0..49 inside its own team, stable for the whole game and derived from the
  ## exec order rather than from an RNG or a comms round-trip.

func brainFor*(side: Side, r: Robot): Brain = side.brains[seqIdOf(r)]

proc spend*(r: Robot, ops: int): bool {.discardable.} =
  ## Charge `ops` decision credits. False once the duck is out of budget;
  ## every loop in the chassis checks it and stops.
  if r.opsLeft <= 0: return false
  r.opsLeft -= ops
  r.opsLeft > 0

func ownFieldIndex*(side: Side, i: int): int =
  i * 2 + (if side.team == teamA: 0 else: 1)

func enemyFieldIndex*(side: Side, i: int): int =
  i * 2 + (if side.team == teamA: 1 else: 0)

# ---------------------------------------------------------------------------
#  Navigation fields
# ---------------------------------------------------------------------------

proc computeField(w: World, side: Side, slot: int, src: Loc) =
  ## A dial-queue Dijkstra over the whole board: land costs 1, water costs
  ## `WaterStepCost`, walls are impassable and the dam is impassable only while
  ## the setup phase runs. Six buckets are enough because the largest edge cost
  ## is five.
  let n = w.width * w.height
  if side.dist[slot].len != n:
    side.dist[slot] = newSeq[int32](n)
  for i in 0 ..< n: side.dist[slot][i] = Unreachable
  for b in 0 .. 5: side.buckets[b].setLen(0)
  let setup = w.isSetupPhase()
  let start = w.idx(src)
  side.dist[slot][start] = 0
  side.buckets[0].add(int32(start))
  var pending = 1
  var d = 0
  while pending > 0:
    let b = d mod 6
    while side.buckets[b].len > 0:
      let i = int(side.buckets[b][^1])
      side.buckets[b].setLen(side.buckets[b].len - 1)
      dec pending
      if int(side.dist[slot][i]) != d: continue
      let here = w.indexToLoc(i)
      for dir in MoveDirs:
        let nl = here + dir
        if not w.onTheMap(nl): continue
        let ni = w.idx(nl)
        if w.walls[ni]: continue
        if setup and w.dam[ni]: continue
        let step = if w.water[ni]: WaterStepCost else: 1
        let nd = d + step
        if nd < int(side.dist[slot][ni]):
          side.dist[slot][ni] = int32(nd)
          side.buckets[nd mod 6].add(int32(ni))
          inc pending
    inc d

proc refreshFields*(w: World, side: Side) =
  ## Called once per team per round from the round loop; it does real work
  ## only at round 1, at round 201 and every 200 rounds after.
  if side.fieldsRound != 0 and
     (w.currentRound - 1) mod FieldRefreshInterval != 0:
    return
  if side.fieldsRound == w.currentRound: return
  side.fieldsRound = w.currentRound
  for i in 0 .. 2:
    side.ownCentres[i] = w.map.spawnCenters[side.ownFieldIndex(i)]
    side.enemyCentres[i] = w.map.spawnCenters[side.enemyFieldIndex(i)]
  for slot in 0 ..< NavAnchors:
    w.computeField(side, slot, w.map.spawnCenters[slot])

func fieldAt*(side: Side, w: World, slot: int, l: Loc): int =
  if side.dist[slot].len == 0: return int(Unreachable)
  int(side.dist[slot][w.idx(l)])

# ---------------------------------------------------------------------------
#  Movement
# ---------------------------------------------------------------------------

proc noteHistory(brain: Brain, l: Loc) =
  brain.history[brain.histPos] = l
  brain.histPos = (brain.histPos + 1) mod HistoryLen
  if brain.histLen < HistoryLen: brain.histLen += 1

func inHistory(brain: Brain, l: Loc): bool =
  for i in 0 ..< brain.histLen:
    if brain.history[i] == l: return true
  false

proc greedyStep*(w: World, side: Side, r: Robot, target: Loc): bool
    {.discardable.} =
  ## The short-walk step: the legal neighbour that gets closest to `target`,
  ## with a penalty for a tile the duck has stood on in the last six moves so
  ## a concave wall cannot lock it into a two-tile shuffle.
  let brain = side.brainFor(r)
  var bestDir = dCenter
  var bestScore = high(int)
  for dir in MoveDirs:
    if not spend(r, 1): break
    if not w.canMove(r, dir): continue
    let nl = r.loc + dir
    var score = nl.distanceSquaredTo(target) * 4
    if brain.inHistory(nl): score += 4000
    if score < bestScore:
      bestScore = score
      bestDir = dir
  if bestDir == dCenter: return false
  brain.noteHistory(r.loc)
  w.doMove(r, bestDir)
  true

proc fieldStep*(w: World, side: Side, r: Robot, slot: int,
                target: Loc): bool {.discardable.} =
  ## The long-walk step: downhill on a precomputed distance field, falling
  ## back to a greedy step when the field says the duck is already there or
  ## the field has no opinion.
  if side.dist[slot].len == 0: return w.greedyStep(side, r, target)
  let brain = side.brainFor(r)
  let here = side.fieldAt(w, slot, r.loc)
  var bestDir = dCenter
  var bestScore = high(int)
  for dir in MoveDirs:
    if not spend(r, 1): break
    if not w.canMove(r, dir): continue
    let nl = r.loc + dir
    var score = side.fieldAt(w, slot, nl) * 8
    if brain.inHistory(nl): score += 4000
    if score < bestScore:
      bestScore = score
      bestDir = dir
  if bestDir == dCenter: return false
  if bestScore >= here * 8 + 4000:
    ## Every legal neighbour is uphill AND remembered: the field is not going
    ## to get this duck out, so take the greedy step instead.
    return w.greedyStep(side, r, target)
  brain.noteHistory(r.loc)
  w.doMove(r, bestDir)
  true

proc travelTo*(w: World, side: Side, r: Robot, slot: int,
               target: Loc): bool {.discardable.} =
  ## Field-guided while far, greedy once the target is inside the vision
  ## window — which is what makes the last two tiles of a raid follow the flag
  ## rather than the anchor.
  if r.loc.distanceSquaredTo(target) <= VisionRadiusSquared:
    return w.greedyStep(side, r, target)
  w.fieldStep(side, r, slot, target)

proc homeSpawnSlot*(w: World, side: Side, r: Robot): int =
  ## The own spawn centre whose field says this duck is closest to home.
  var best = side.ownFieldIndex(0)
  var bestD = high(int)
  for i in 0 .. 2:
    let slot = side.ownFieldIndex(i)
    let d = side.fieldAt(w, slot, r.loc)
    if d < bestD:
      bestD = d
      best = slot
  best

# ---------------------------------------------------------------------------
#  Roles
# ---------------------------------------------------------------------------

const EscortRallyRadiusSquared* = 400

func isEscort*(side: Side, r: Robot): bool =
  for id in side.escorts:
    if id == r.id: return true
  false

const RoleCap* = 15
  ## No more than fifteen ducks may claim the same role, so a flock cannot
  ## pile every attacker onto one flag.

proc releaseRole*(side: Side, r: Robot) =
  let brain = side.brainFor(r)
  if brain.hasRole:
    side.roleCount[brain.role] -= 1
    brain.hasRole = false
    brain.role = -1

proc claimRole*(side: Side, r: Robot, defensive: bool) =
  ## The least-crowded eligible role, ties broken toward the lowest index.
  ## Deterministic, and re-claimed when a duck respawns.
  let brain = side.brainFor(r)
  if brain.hasRole: return
  let lo = if defensive: 0 else: 3
  var best = lo
  var bestCount = high(int)
  for i in lo .. lo + 2:
    if side.roleCount[i] < bestCount:
      bestCount = side.roleCount[i]
      best = i
  if bestCount >= RoleCap:
    ## Every eligible role is full: take the lowest-index one anyway rather
    ## than standing still. A duck without a job is exactly the inert flock
    ## the LEARNINGS pin forbids.
    best = lo
  brain.role = best
  brain.hasRole = true
  side.roleCount[best] += 1

func isBuilder*(side: Side, r: Robot): bool =
  seqIdOf(r) < side.census.builders

func isHealer*(side: Side, r: Robot): bool =
  let s = seqIdOf(r)
  s >= side.census.builders and s < side.census.builders + side.census.healers

func isAttacker*(side: Side, r: Robot): bool =
  seqIdOf(r) >= side.census.builders + side.census.healers

# ---------------------------------------------------------------------------
#  Sensing, charged against the budget
# ---------------------------------------------------------------------------

iterator sensedTiles*(w: World, r: Robot): Loc =
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if r.opsLeft <= 0: break
    r.opsLeft -= 1
    yield l

iterator sensedTilesWithin*(w: World, r: Robot, r2: int): Loc =
  let limit = min(r2, VisionRadiusSquared)
  for l in w.locationsWithinRadiusSquared(r.loc, limit):
    if r.opsLeft <= 0: break
    r.opsLeft -= 1
    yield l

proc noteEnemyFlag*(side: Side, i: int, l: Loc, round: int, sensed: bool) =
  if not sensed and side.knownEnemyFlag[i].sensed and
      side.knownEnemyFlag[i].round >= round - 25:
    ## A sensed location beats a broadcast one while it is still fresh.
    return
  side.knownEnemyFlag[i] = FlagNote(loc: l, round: round, sensed: sensed)

proc observe*(w: World, side: Side, r: Robot) =
  ## The one sensing pass every role starts with: update the team's shared
  ## knowledge from what THIS duck can legitimately see. Enemy traps are
  ## invisible and are not looked for.
  var i = 0
  for f in w.allFlags:
    if f.team == side.team: continue
    if not spend(r, 1): break
    if w.canSenseLocation(r, f.loc):
      side.noteEnemyFlag(i mod 3, f.loc, w.currentRound, true)
    i += 1
  ## The broadcast list is re-read every round because it is re-rolled every
  ## hundred, and a broadcast fix never overwrites a fresh sighting.
  var j = 0
  for bl in w.broadcastFlagLocations(r):
    if not spend(r, 1): break
    side.noteEnemyFlag(j mod 3, bl, w.currentRound, false)
    j += 1

func enemyFlagIndexOf*(w: World, side: Side, f: Flag): int =
  ## Which of the three enemy flags this is, by its position in `allFlags`
  ## among that team's flags — stable, because `allFlags` is built in
  ## ascending tile-index order and only shrinks on a capture.
  var i = 0
  for other in w.allFlags:
    if other.team == side.team: continue
    if other == f: return i
    i += 1
  0

# ---------------------------------------------------------------------------
#  Nearby enemies and friends
# ---------------------------------------------------------------------------

proc nearestEnemy*(w: World, r: Robot, r2: int): Robot =
  var best: Robot = nil
  var bestKey = high(int)
  for l in w.locationsWithinRadiusSquared(r.loc, min(r2, VisionRadiusSquared)):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team == r.team: continue
    let key = r.loc.distanceSquaredTo(l)
    if key < bestKey:
      bestKey = key
      best = bot
  best

proc nearestCrumbPile*(w: World, r: Robot): tuple[ok: bool, at: Loc] =
  ## The nearest crumb pile inside the vision window. Every role walks crumbs
  ## off the floor when it has nothing better to do: crumbs are the only
  ## resource and a flock that ignores them starves itself.
  var bestD = high(int)
  for l in w.sensedTiles(r):
    if w.getCrumbAmount(l) == 0: continue
    let d = r.loc.distanceSquaredTo(l)
    if d < bestD:
      bestD = d
      result = (ok: true, at: l)

proc countNearby*(w: World, r: Robot, r2: int,
                  team: Team): int =
  for l in w.locationsWithinRadiusSquared(r.loc, min(r2, VisionRadiusSquared)):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot != nil and bot.team == team and bot.id != r.id:
      result += 1
