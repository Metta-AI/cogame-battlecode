## `lemonade`'s shared per-side memory, the symmetry guess and the navigator.
##
## Behaviour ported from `awesomelemonade/Battlecode2023` `src/finalBot/`
## (AGPL-3.0, head `2e231f31`, the 1st-place bot "Producing Perfection") — the
## remembered map, the chunk-checkpoint navigator and the current- and
## cloud-aware stepping tiebreaks — together with the symmetry eliminator from
## `jmerle/battlecode-2023` `src/camel_case_v30_final/util/Symmetry.java`
## (MIT, head `e776fcb2`). BEHAVIOUR, NOT CODE — rewritten in Nim and
## parameterised by this coworld's doctrine sheet. `NOTICE` names the files.
##
## Everything a robot learns is charged against its `DecisionOps` budget by
## `world.spend`, and the charge happens BEFORE each primitive, never inside
## one — so a sense sweep or a navigation step either runs to completion or
## does not start, and the answer is never a function of the remaining budget.
##
## THE NAVIGATOR IS A BOUNDED BFS with a greedy fallback. bc23 puts up to 160
## robots on the board for 2000 rounds, so the BFS is capped at
## `NavNodeBudget` expanded nodes over the REMEMBERED passability map and
## charges one `DecisionOps` credit per node; past the cap it falls back to a
## greedy step with a six-tile no-repeat history to break oscillation. Two
## bc23-specific tiebreaks ride on top of both:
##
## * **prefer a current that pushes you toward the target** — a free square of
##   movement that costs no cooldown at all;
## * **avoid a cloud unless the destination is a cloud** — a cloud costs 20 %
##   on every cooldown and collapses vision to r² ≤ 4 in both directions.

import std/[algorithm, tables]
import ../world, ../comms, ../knobs

export world, comms, knobs

const
  ElixirRunners* = 4
    ## How many carriers the elixir programme claims. Three of a fleet of
    ## twenty or more keeps the build queue fed while still pouring 600 kg
    ## into a well inside a few hundred rounds.
  NavNodeBudget* = 160
    ## The BFS cap, in expanded nodes. Chosen against
    ## `tests/test_bc23_perf.nim`'s 100-second gate on a 60x30 board.
  NoRepeatLen* = 6

type
  Side* = ref object
    ## The per-team memory every robot shares. None of it is world state: a
    ## rule never reads it, and two factions with the same doctrine on the
    ## same map produce the same memory.
    team*: Team
    doctrine*: Doctrine23
    homeHqs*: seq[Loc]
    enemyHqs*: seq[Loc]
      ## Guessed from the map symmetry at round 1 and CORRECTED the moment a
      ## real enemy headquarters is sensed (`jmerle/util/Symmetry` behaviour:
      ## three candidate reflections, eliminated as tiles are sensed).
    symmetryKnown*: bool
    knownWall*: seq[bool]
    knownSeen*: seq[bool]
    knownWells*: seq[Loc]
    knownWellSet*: seq[bool]
    knownIslands*: seq[int]        ## island INDICES, ascending
    knownIslandSet*: seq[bool]
    lastSighting*: Loc
    lastSightingRound*: int
    ## --- the census, refreshed once a round ---
    censusRound*: int
    carriers*, launchers*, amplifiers*, destabilizers*, boosters*: int
    enemyLaunchers*: int
    hqCount*: int
    ## --- commitments; `econ.nim` is the only place a resource is committed ---
    anchorClaims*: Table[int, int]  ## island index -> carrier id
    ferryClaim*: int                ## the carrier id currently ferrying, or -1
    anchorScheduled*: bool
    elixirTarget*: Loc
    hasElixirTarget*: bool
    elixirPoured*: int
    elixirRunners*: seq[int]
      ## The carrier ids currently running the elixir programme. A CLAIMED
      ## ROLE and not an id-modulo test: measured, `id mod 3 == 0` left the
      ## faction with ZERO runners by round 800 (the ids come out of the
      ## engine's shuffled 4096-blocks, and the surviving population is not
      ## uniform in them), and the 600 kg transformation stalled at 446.
    strikeCentre*: Loc
    strikeRound*: int
    regroupUntil*: int
    lastLauncherCount*: int
    ## --- navigation scratch, shared and reused so a BFS allocates nothing ---
    navStamp*: seq[int32]
    navFirst*: seq[int8]
    navGen*: int32
    navQueue*: seq[int32]

proc newSide*(team: Team, doctrine: Doctrine23): Side =
  Side(team: team, doctrine: doctrine,
       anchorClaims: initTable[int, int](),
       ferryClaim: -1, censusRound: -1, lastSightingRound: -1,
       lastSighting: loc(-1, -1), elixirTarget: loc(-1, -1),
       strikeCentre: loc(-1, -1), strikeRound: -1, regroupUntil: -1,
       navGen: 0)

proc ensureMemory*(w: World, side: Side) =
  if side.knownWall.len == w.width * w.height: return
  let size = w.width * w.height
  side.knownWall = newSeq[bool](size)
  side.knownSeen = newSeq[bool](size)
  side.knownWellSet = newSeq[bool](size)
  side.knownIslandSet = newSeq[bool](max(1, w.islands.len))
  side.navStamp = newSeq[int32](size)
  side.navFirst = newSeq[int8](size)
  side.navQueue = newSeq[int32](size)

# ---------------------------------------------------------------------------
#  Round-level bookkeeping
# ---------------------------------------------------------------------------

proc observeHome*(w: World, side: Side) =
  ## Round 1: our own headquarters are ours to see, and the enemy's are
  ## GUESSED from the map's declared symmetry — the standard 2023 opening,
  ## because every official map is symmetric and a launcher rush that waits to
  ## sense a headquarters has already lost the duel.
  if side.homeHqs.len > 0: return
  w.ensureMemory(side)
  for id in w.headquarters[ord(side.team)]:
    if w.existsRobot(id):
      side.homeHqs.add(w.robotsById[id].loc)
  for h in side.homeHqs:
    side.enemyHqs.add(w.symmetricLoc(h))
  side.hqCount = side.homeHqs.len
  if side.homeHqs.len == 0:
    side.enemyHqs.add(loc(w.width div 2, w.height div 2))

proc refreshCensus*(w: World, side: Side) =
  ## Once a round, never inside a robot's turn: the counts `econ.nim` reads to
  ## decide what a headquarters builds next.
  if side.censusRound == w.currentRound: return
  side.censusRound = w.currentRound
  side.lastLauncherCount = side.launchers
  side.carriers = w.robotCountByType(side.team, rtCarrier)
  side.launchers = w.robotCountByType(side.team, rtLauncher)
  side.amplifiers = w.robotCountByType(side.team, rtAmplifier)
  side.destabilizers = w.robotCountByType(side.team, rtDestabilizer)
  side.boosters = w.robotCountByType(side.team, rtBooster)
  side.enemyLaunchers = w.robotCountByType(side.team.other(), rtLauncher)
  side.hqCount = max(1, side.homeHqs.len)
  ## Drop a claim whose carrier is gone, so an anchor is never stranded.
  var dead: seq[int]
  for islandIdx, carrierId in side.anchorClaims:
    if not w.existsRobot(carrierId): dead.add(islandIdx)
  for islandIdx in dead: side.anchorClaims.del(islandIdx)
  if side.ferryClaim >= 0 and not w.existsRobot(side.ferryClaim):
    side.ferryClaim = -1
  ## The elixir role: drop the dead, then top up from the live carriers in
  ## ascending id so the choice is deterministic.
  var alive: seq[int]
  for id in side.elixirRunners:
    if w.existsRobot(id) and w.robotsById[id].kind == rtCarrier:
      alive.add(id)
  side.elixirRunners = alive
  if side.elixirRunners.len < ElixirRunners:
    var candidates: seq[int]
    for id in w.execOrder:
      let r = w.robotsById[id]
      if r.team != side.team or r.kind != rtCarrier: continue
      if id == side.ferryClaim: continue
      if id in side.elixirRunners: continue
      candidates.add(id)
    candidates.sort()
    for id in candidates:
      if side.elixirRunners.len >= ElixirRunners: break
      side.elixirRunners.add(id)

proc observe*(w: World, side: Side, r: Robot) =
  ## Fold everything this robot can sense into the faction's memory: static
  ## terrain (passability), wells, islands, and the most recent enemy
  ## sighting. Charged one `DecisionOps` credit per tile examined.
  w.ensureMemory(side)
  let r2 = RobotSpecs[r.kind].visionRadiusSquared
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    if not r.spend(1): break
    if not w.canSenseLocation(r, l): continue
    let i = w.idx(l)
    if not side.knownSeen[i]:
      side.knownSeen[i] = true
      side.knownWall[i] = w.getWall(l)
      if w.isWell(l):
        side.knownWellSet[i] = true
        side.knownWells.add(l)
        ## EVERY OFFICIAL MAP IS SYMMETRIC, so a well sensed here is a well
        ## there. `jmerle/util/Symmetry` behaviour: the mirror is the guess a
        ## faction plays on until a sensed tile contradicts it. Without it a
        ## faction on a heavily clouded map (`Spin` is 54 % cloud, and vision
        ## collapses to r2<=4 inside one) never learns a second well at all.
        let mirrored = w.symmetricLoc(l)
        let mi = w.idx(mirrored)
        if not side.knownWellSet[mi]:
          side.knownWellSet[mi] = true
          side.knownWells.add(mirrored)
    let islandIdx = w.islandAt(l)
    if islandIdx >= 0 and not side.knownIslandSet[islandIdx]:
      side.knownIslandSet[islandIdx] = true
      side.knownIslands.add(islandIdx)
    let other = w.getRobot(l)
    if other != nil and other.team != side.team:
      if other.kind == rtHeadquarters:
        ## A REAL sighting beats the symmetry guess.
        var known = false
        for h in side.enemyHqs:
          if h == l: known = true
        if not known:
          side.enemyHqs.add(l)
          side.symmetryKnown = true
      else:
        side.lastSighting = l
        side.lastSightingRound = w.currentRound

# ---------------------------------------------------------------------------
#  Queries every module shares
# ---------------------------------------------------------------------------

func mapCentre*(w: World): Loc = loc(w.width div 2, w.height div 2)

func nearestHome*(side: Side, l: Loc): Loc =
  if side.homeHqs.len == 0: return l
  result = side.homeHqs[0]
  var best = chebyshev(l, result)
  for h in side.homeHqs:
    let d = chebyshev(l, h)
    if d < best:
      best = d
      result = h

func nearestEnemyHome*(side: Side, l: Loc): Loc =
  if side.enemyHqs.len == 0: return l
  result = side.enemyHqs[0]
  var best = chebyshev(l, result)
  for h in side.enemyHqs:
    let d = chebyshev(l, h)
    if d < best:
      best = d
      result = h

func believedPassable*(w: World, side: Side, l: Loc): bool =
  if not w.onTheMap(l): return false
  let i = w.idx(l)
  ## An UNSEEN tile is assumed passable — the only assumption that lets a
  ## carrier walk to a well it remembers across ground it has never stood on.
  (not side.knownSeen[i]) or (not side.knownWall[i])

proc rememberNoRepeat(r: Robot, l: Loc) =
  r.noRepeat.add(l)
  if r.noRepeat.len > NoRepeatLen:
    r.noRepeat.delete(0)

func recentlyVisited(r: Robot, l: Loc): bool =
  for p in r.noRepeat:
    if p == l: return true
  false

func stepScore(w: World, side: Side, r: Robot, dest, target: Loc): int =
  ## Lower is better. The two bc23 tiebreaks live here.
  result = chebyshev(dest, target) * 8
  if w.getCurrent(dest) != dCenter:
    let after = dest + w.getCurrent(dest)
    if w.onTheMap(after) and chebyshev(after, target) < chebyshev(dest, target):
      ## A current pushing us the right way is a free square of movement.
      result -= 6
    else:
      result += 4
  if w.getCloud(dest) and not w.getCloud(target):
    result += 3
  if r.recentlyVisited(dest):
    result += 5

proc greedyStep*(w: World, side: Side, r: Robot, target: Loc): Dir =
  ## The fallback: score the eight neighbours and take the best legal one.
  result = dCenter
  var best = high(int)
  for d in MoveDirs:
    if not r.spend(1): break
    if not w.canMove(r, d): continue
    let dest = r.loc + d
    let s = w.stepScore(side, r, dest, target)
    if s < best:
      best = s
      result = d

proc navStep*(w: World, side: Side, r: Robot, target: Loc): Dir =
  ## A bounded BFS over the REMEMBERED passability map, returning the first
  ## step of the shortest route it found inside `NavNodeBudget` nodes. Every
  ## node expanded is charged one `DecisionOps` credit, and the budget is
  ## checked BEFORE the expansion, so the BFS is never cut in half.
  if target == r.loc: return dCenter
  w.ensureMemory(side)
  if chebyshev(r.loc, target) <= 1:
    let d = r.loc.directionTo(target)
    if w.canMove(r, d): return d
    return w.greedyStep(side, r, target)
  side.navGen += 1
  let gen = side.navGen
  var head = 0
  var tail = 0
  let start = w.idx(r.loc)
  side.navStamp[start] = gen
  side.navFirst[start] = -1
  side.navQueue[tail] = int32(start)
  tail += 1
  var expanded = 0
  let targetIdx = w.idx(target)
  while head < tail and expanded < NavNodeBudget:
    if not r.spend(1): break
    let cur = int(side.navQueue[head])
    head += 1
    expanded += 1
    let here = w.indexToLoc(cur)
    for k in 0 ..< MoveDirs.len:
      let d = MoveDirs[k]
      let nxt = here + d
      if not w.onTheMap(nxt): continue
      let ni = w.idx(nxt)
      if side.navStamp[ni] == gen: continue
      if not w.believedPassable(side, nxt): continue
      ## Only the tile we are standing next to can be known-occupied; further
      ## out the memory is stale, so occupancy is only honoured at range 1.
      if cur == start and w.isLocationOccupied(nxt): continue
      side.navStamp[ni] = gen
      side.navFirst[ni] = (if cur == start: int8(k) else: side.navFirst[cur])
      if ni == targetIdx:
        let d0 = MoveDirs[int(side.navFirst[ni])]
        if w.canMove(r, d0):
          rememberNoRepeat(r, r.loc)
          return d0
        return w.greedyStep(side, r, target)
      if tail < side.navQueue.len:
        side.navQueue[tail] = int32(ni)
        tail += 1
  ## The BFS did not reach the target inside its budget: take the reachable
  ## tile it did find that is closest to the target, else fall back to greedy.
  var bestIdx = -1
  var bestScore = high(int)
  for k in 0 ..< tail:
    let i = int(side.navQueue[k])
    if i == start: continue
    let d = chebyshev(w.indexToLoc(i), target)
    if d < bestScore:
      bestScore = d
      bestIdx = i
  if bestIdx >= 0 and side.navFirst[bestIdx] >= 0:
    let d0 = MoveDirs[int(side.navFirst[bestIdx])]
    if w.canMove(r, d0):
      rememberNoRepeat(r, r.loc)
      return d0
  w.greedyStep(side, r, target)

proc moveToward*(w: World, side: Side, r: Robot,
                 target: Loc): bool {.discardable.} =
  if not r.isMovementReady(): return false
  let d = w.navStep(side, r, target)
  if d == dCenter: return false
  rememberNoRepeat(r, r.loc)
  w.doMove(r, d)

proc freeTileNear*(w: World, side: Side, centre, toward: Loc): Loc =
  ## The free, passable tile within a headquarters' build radius that is
  ## nearest the frontier — never a well (a robot standing on a well blocks
  ## nothing, but a robot BUILT on one boxes the mining lane) and never a tile
  ## that would box the headquarters in.
  result = loc(-1, -1)
  var best = high(int)
  for l in w.locationsWithinRadiusSquared(centre, DistanceSquaredFromHeadquarter):
    if w.isLocationOccupied(l) or not w.isPassable(l): continue
    var score = chebyshev(l, toward) * 4
    if w.isWell(l): score += 6
    if w.getCloud(l): score += 2
    if score < best:
      best = score
      result = l
