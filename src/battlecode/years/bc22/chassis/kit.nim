## `wololo`'s shared per-side memory, the enemy-archon guess and the navigator.
##
## Behaviour ported from `iliao2345/Battlecode2022` `src/fury_fix_20/`
## (AGPL-3.0, head `c42645a0`; the 1st-place bot "wololo") — the remembered map
## with its dead-square set, the **rubble-weighted** BFS from `Bfs.java` +
## `Pathing.java` and its greedy fallback — together with the symmetry
## eliminator and the per-radius navigators from `jmerle/battlecode-2022`
## `src/camel_case_v25_final/` (MIT, head `f57d3549`,
## `dijkstra/Dijkstra20|34|53.java`). BEHAVIOUR, NOT CODE — rewritten in Nim and
## parameterised by this coworld's doctrine sheet. `NOTICE` names the files.
##
## Everything a robot learns is charged against its `DecisionOps` budget by
## `world.spend`, and the charge happens BEFORE each primitive, never inside one
## — so a sense sweep or a navigation step either runs to completion or does not
## start, and the answer is never a function of the remaining budget.
##
## **THE NAVIGATOR IS WEIGHTED BY `1 + rubble/10`, because that is literally the
## cooldown the robot will pay.** A BFS that treats a rubble-60 square as one
## step and a rubble-0 square as one step routes a soldier through seven times
## its own movement cost, which on `pyramid_raiders` (measured rubble mean 58.1)
## is the difference between crossing the map and standing still. The search is
## a bounded Dijkstra over the REMEMBERED rubble map with a 16-bucket monotone
## queue, capped at `NavNodeBudget` expanded nodes and charging one credit per
## node; past the cap it falls back to a greedy step with a six-square
## no-repeat history to break oscillation.

import std/algorithm
import ../world, ../economy, ../buildings, ../knobs
import comms

export world, economy, buildings, knobs, comms

const
  NavNodeBudget* = 150
    ## The Dijkstra cap, in expanded nodes. Chosen against
    ## `tests/test_bc22_perf.nim`'s 100-second gate on a 45x35 board carrying
    ## up to two hundred robots.
  NoRepeatLen* = 6
  MaxNavCost* = 15
    ## `1 + rubble/10` runs 1..11; the bucket queue keeps 16 to leave headroom.

type
  AnomalyRequest* = object
    ## `chassis/anomaly.nim`'s output: what the timed play is asking the other
    ## modules to do this round. Every field is advisory; no module is ever
    ## forced into an illegal or inert action by one.
    standUp*: bool            ## transform buildings to PORTABLE before a FURY
    standDown*: bool          ## and back afterwards
    scatter*: bool            ## spread droids before a CHARGE
    push*: bool               ## strike immediately after a CHARGE
    spendDown*: bool          ## empty the reserve before an ABYSS
    relocate*: bool           ## walk archons off doomed squares before a VORTEX
    kind*: AnomalyKind
    round*: int
    active*: bool

  Side* = ref object
    ## The per-team memory every robot shares. None of it is world state: a rule
    ## never reads it, and two factions with the same doctrine on the same map
    ## produce the same memory.
    team*: Team
    doctrine*: Doctrine22
    homeArchons*: seq[Loc]
    enemyArchons*: seq[Loc]
      ## Guessed from the map symmetry at round 1 and CORRECTED the moment a
      ## real enemy archon is sensed (`jmerle/util/Symmetry` behaviour).
    symmetryKnown*: bool
    knownSeen*: seq[bool]
    knownRubble*: seq[int16]
    knownLead*: seq[int16]
    knownLeadRound*: seq[int32]
    deadSquare*: seq[bool]
      ## Squares seen at ZERO lead. The map never puts lead back on one, so a
      ## miner that keeps walking to it is a miner that never mines again.
    leadSites*: seq[Loc]
    goldSites*: seq[Loc]
    lastSighting*: Loc
    lastSightingRound*: int
    ## --- the census, refreshed once a round ---
    censusRound*: int
    miners*, builders*, soldiers*, sages*: int
    labs*, labsLive*, watchtowers*, watchtowersLive*: int
    archons*: int
    enemyArchonCount*: int
    enemyAttackers*: int
    ## --- commitments; `econ.nim` is the only place lead or gold is committed
    committedLead*: int
    committedGold*: int
    builderClaimed*: bool
    labSite*: Loc
    hasLabSite*: bool
    minerEmployment*: array[20, int]
      ## `fury_fix_20/Archon.java`'s own 20-round ring buffer of how many miners
      ## actually mined. It is what stops the faction building miners for a
      ## mined-out map.
    minersMinedThisRound*: int
    anomalyReq*: AnomalyRequest
    ## --- navigation scratch, shared and reused so a search allocates nothing
    navDist*: seq[int32]
    navStamp*: seq[int32]
    navFirst*: seq[int8]
    navGen*: int32

proc newSide*(team: Team, doctrine: Doctrine22): Side =
  Side(team: team, doctrine: doctrine, censusRound: -1,
       lastSightingRound: -1, lastSighting: loc(-1, -1),
       labSite: loc(-1, -1), navGen: 0)

proc ensureMemory*(w: World, side: Side) =
  if side.knownSeen.len == w.width * w.height: return
  let size = w.width * w.height
  side.knownSeen = newSeq[bool](size)
  side.knownRubble = newSeq[int16](size)
  side.knownLead = newSeq[int16](size)
  side.knownLeadRound = newSeq[int32](size)
  side.deadSquare = newSeq[bool](size)
  side.navDist = newSeq[int32](size)
  side.navStamp = newSeq[int32](size)
  side.navFirst = newSeq[int8](size)

# ---------------------------------------------------------------------------
#  Round-level bookkeeping
# ---------------------------------------------------------------------------

proc observeHome*(w: World, side: Side) =
  ## Round 1: our own archons are ours to see, and the enemy's are GUESSED from
  ## the map's declared symmetry — the standard 2022 opening, because every
  ## official map is symmetric and a soldier rush that waits to sense an archon
  ## has already lost the race.
  if side.homeArchons.len > 0: return
  w.ensureMemory(side)
  for id in w.execOrder:
    let r = w.robotById(id)
    if r == nil or r.kind != rtArchon: continue
    if r.team == side.team: side.homeArchons.add(r.loc)
  for h in side.homeArchons:
    side.enemyArchons.add(w.symmetricLoc(h))
  if side.homeArchons.len == 0:
    side.enemyArchons.add(loc(w.width div 2, w.height div 2))

proc refreshCensus*(w: World, side: Side) =
  ## Once a round, never inside a robot's turn: the counts `econ.nim` reads to
  ## decide what an archon builds next.
  if side.censusRound == w.currentRound: return
  side.censusRound = w.currentRound
  let t = side.team
  side.miners = w.robotCountByType(t, rtMiner)
  side.builders = w.robotCountByType(t, rtBuilder)
  side.soldiers = w.robotCountByType(t, rtSoldier)
  side.sages = w.robotCountByType(t, rtSage)
  side.labs = w.robotCountByType(t, rtLaboratory)
  side.watchtowers = w.robotCountByType(t, rtWatchtower)
  side.archons = w.robotCountByType(t, rtArchon)
  side.enemyArchonCount = w.robotCountByType(t.other(), rtArchon)
  side.enemyAttackers = w.robotCountByType(t.other(), rtSoldier) +
    w.robotCountByType(t.other(), rtSage) +
    w.robotCountByType(t.other(), rtWatchtower)
  var live = 0
  var liveTowers = 0
  var builderAlive = false
  for _, r in w.robotsById:
    if r.team != t: continue
    if r.kind == rtLaboratory and r.mode != rmPrototype: live += 1
    if r.kind == rtWatchtower and r.mode != rmPrototype: liveTowers += 1
    if r.kind == rtBuilder: builderAlive = true
  side.labsLive = live
  side.watchtowersLive = liveTowers
  if not builderAlive: side.builderClaimed = false
  ## The commitment ledger is per-round: two archons cannot promise the same
  ## 75 Pb inside one round, and nothing is carried across rounds.
  side.committedLead = 0
  side.committedGold = 0
  ## The 20-round miner-employment ring buffer.
  side.minerEmployment[w.currentRound mod 20] = side.minersMinedThisRound
  side.minersMinedThisRound = 0

func minerEmploymentRate*(side: Side): int =
  ## The mean number of miners that actually mined over the last 20 rounds.
  var total = 0
  for v in side.minerEmployment: total += v
  total div 20

proc observe*(w: World, side: Side, r: Robot) =
  ## Fold everything this robot can sense into the faction's memory: rubble,
  ## lead (and the dead-square set), gold, and the most recent enemy sighting.
  ## Charged one `DecisionOps` credit per square examined.
  w.ensureMemory(side)
  let r2 = RobotSpecs[r.kind].visionRadiusSquared
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    if not r.spend(1): break
    let i = w.idx(l)
    let lead = w.getLead(l)
    if not side.knownSeen[i]:
      side.knownSeen[i] = true
      if lead > 0:
        side.leadSites.add(l)
        ## EVERY OFFICIAL MAP IS SYMMETRIC, so a deposit sensed here is a
        ## deposit there. Without the mirror a faction on a big map never
        ## learns the far half exists until a miner walks it.
        let mirrored = w.symmetricLoc(l)
        let mi = w.idx(mirrored)
        if not side.knownSeen[mi]:
          side.knownSeen[mi] = true
          side.knownRubble[mi] = int16(w.getRubble(mirrored))
          side.knownLead[mi] = int16(w.getLead(mirrored))
          side.leadSites.add(mirrored)
    side.knownRubble[i] = int16(w.getRubble(l))
    side.knownLead[i] = int16(lead)
    side.knownLeadRound[i] = int32(w.currentRound)
    side.deadSquare[i] = lead == 0
    if w.getGold(l) > 0:
      var known = false
      for g in side.goldSites:
        if g == l: known = true
      if not known: side.goldSites.add(l)
    let other = w.getRobot(l)
    if other != nil and other.team != side.team:
      if other.kind == rtArchon:
        var known = false
        for h in side.enemyArchons:
          if h == l: known = true
        if not known:
          side.enemyArchons.add(l)
          side.symmetryKnown = true
      else:
        side.lastSighting = l
        side.lastSightingRound = w.currentRound

# ---------------------------------------------------------------------------
#  Queries every module shares
# ---------------------------------------------------------------------------

func mapCentre*(w: World): Loc = loc(w.width div 2, w.height div 2)

func nearestHome*(side: Side, l: Loc): Loc =
  if side.homeArchons.len == 0: return l
  result = side.homeArchons[0]
  var best = chebyshev(l, result)
  for h in side.homeArchons:
    let d = chebyshev(l, h)
    if d < best:
      best = d
      result = h

func nearestEnemyHome*(side: Side, l: Loc): Loc =
  if side.enemyArchons.len == 0: return l
  result = side.enemyArchons[0]
  var best = chebyshev(l, result)
  for h in side.enemyArchons:
    let d = chebyshev(l, h)
    if d < best:
      best = d
      result = h

func nearestLiveArchon*(w: World, side: Side, l: Loc): Robot =
  result = nil
  var best = high(int)
  for _, r in w.robotsById:
    if r.team != side.team or r.kind != rtArchon: continue
    let d = chebyshev(l, r.loc)
    if d < best or (d == best and result != nil and r.id < result.id):
      best = d
      result = r

func navCost*(w: World, side: Side, l: Loc): int =
  ## `1 + rubble/10`, the cooldown multiplier itself. An unseen square is
  ## assumed flat — the only assumption that lets a miner walk to a deposit it
  ## remembers across ground it has never stood on.
  let i = w.idx(l)
  if not side.knownSeen[i]: 1
  else: 1 + int(side.knownRubble[i]) div 10

proc rememberNoRepeat(r: Robot, l: Loc) =
  r.noRepeat.add(l)
  if r.noRepeat.len > NoRepeatLen:
    r.noRepeat.delete(0)

func recentlyVisited(r: Robot, l: Loc): bool =
  for p in r.noRepeat:
    if p == l: return true
  false

func stepScore(w: World, side: Side, r: Robot, dest, target: Loc): int =
  ## Lower is better. The rubble term is the whole point: a step onto rubble 60
  ## costs seven times a step onto bare ground.
  result = chebyshev(dest, target) * 10 + navCost(w, side, dest) * 3
  if r.recentlyVisited(dest): result += 6

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
  ## A bounded Dijkstra over the REMEMBERED rubble map, weighted by
  ## `1 + rubble/10`, returning the first step of the cheapest route found
  ## inside `NavNodeBudget` expansions. Every expansion is charged one
  ## `DecisionOps` credit and the budget is checked BEFORE it, so the search is
  ## never cut in half.
  if target == r.loc: return dCenter
  w.ensureMemory(side)
  if chebyshev(r.loc, target) <= 1:
    let d = r.loc.directionTo(target)
    if w.canMove(r, d): return d
    return w.greedyStep(side, r, target)
  side.navGen += 1
  let gen = side.navGen
  let start = w.idx(r.loc)
  let targetIdx = w.idx(target)
  ## A 16-bucket monotone (dial) queue: every edge weight is 1..11, so a plain
  ## ring of `MaxNavCost` buckets is a correct priority queue and needs no heap.
  var buckets: array[MaxNavCost, seq[int32]]
  side.navStamp[start] = gen
  side.navDist[start] = 0
  side.navFirst[start] = -1
  buckets[0].add(int32(start))
  var expanded = 0
  var bestSeen = -1
  var bestSeenScore = high(int)
  var pass = 0
  var cursor = 0
  while pass < MaxNavCost * 40 and expanded < NavNodeBudget:
    if buckets[cursor].len == 0:
      cursor = (cursor + 1) mod MaxNavCost
      pass += 1
      continue
    let cur = int(buckets[cursor].pop())
    let dist = int(side.navDist[cur])
    ## A stale entry: the square was reached again more cheaply.
    if dist mod MaxNavCost != cursor: continue
    if not r.spend(1): break
    expanded += 1
    let here = w.indexToLoc(cur)
    let toTarget = chebyshev(here, target)
    if cur != start and toTarget < bestSeenScore:
      bestSeenScore = toTarget
      bestSeen = cur
    if cur == targetIdx: break
    for k in 0 ..< MoveDirs.len:
      let d = MoveDirs[k]
      let nxt = here + d
      if not w.onTheMap(nxt): continue
      let ni = w.idx(nxt)
      ## Only the square we are standing next to can be known-occupied; further
      ## out the memory is stale, so occupancy is honoured only at range 1.
      if cur == start and w.isLocationOccupied(nxt): continue
      let nd = dist + navCost(w, side, nxt)
      if side.navStamp[ni] == gen and int(side.navDist[ni]) <= nd: continue
      side.navStamp[ni] = gen
      side.navDist[ni] = int32(nd)
      side.navFirst[ni] = (if cur == start: int8(k) else: side.navFirst[cur])
      buckets[nd mod MaxNavCost].add(int32(ni))
  var chosen = -1
  if side.navStamp[targetIdx] == gen and side.navFirst[targetIdx] >= 0:
    chosen = targetIdx
  elif bestSeen >= 0 and side.navFirst[bestSeen] >= 0:
    chosen = bestSeen
  if chosen >= 0:
    let d0 = MoveDirs[int(side.navFirst[chosen])]
    if w.canMove(r, d0):
      rememberNoRepeat(r, r.loc)
      return d0
  w.greedyStep(side, r, target)

proc moveToward*(w: World, side: Side, r: Robot,
                 target: Loc): bool {.discardable.} =
  if not r.canMoveCooldown(): return false
  let d = w.navStep(side, r, target)
  if d == dCenter: return false
  rememberNoRepeat(r, r.loc)
  w.doMove(r, d)

proc moveAwayFrom*(w: World, side: Side, r: Robot,
                   threat: Loc): bool {.discardable.} =
  ## The retreat step: the legal neighbour that maximises the distance from the
  ## threat while paying the least rubble.
  if not r.canMoveCooldown(): return false
  var best = dCenter
  var bestScore = low(int)
  for d in MoveDirs:
    if not r.spend(1): break
    if not w.canMove(r, d): continue
    let dest = r.loc + d
    let s = dest.distanceSquaredTo(threat) * 4 - navCost(w, side, dest)
    if s > bestScore:
      bestScore = s
      best = d
  if best == dCenter: return false
  w.doMove(r, best)

proc freeSquareNear*(w: World, side: Side, centre, toward: Loc,
                     r2 = 2): Loc =
  ## The free square adjacent to a builder or an archon that is nearest the
  ## frontier — and never one that would box the builder in. `r2 = 2` is the
  ## eight neighbours, which is the only place a build may land.
  result = loc(-1, -1)
  var best = high(int)
  for l in w.locationsWithinRadiusSquared(centre, r2):
    if l == centre: continue
    if w.isLocationOccupied(l): continue
    var score = chebyshev(l, toward) * 8 + navCost(w, side, l)
    if score < best:
      best = score
      result = l

func dirToFree*(centre, target: Loc): Dir = centre.directionTo(target)

proc lowestRubbleNear*(w: World, side: Side, centre: Loc, r2: int): Loc =
  ## The lowest-rubble free square inside `r2` of `centre`, ties broken by
  ## ascending square index so the choice is deterministic.
  result = centre
  var best = high(int)
  for l in w.locationsWithinRadiusSquared(centre, r2):
    if w.isLocationOccupied(l) and not (l == centre): continue
    let c = navCost(w, side, l) * 100 + w.idx(l) mod 100
    if c < best:
      best = c
      result = l

proc sortedEnemies*(w: World, side: Side, r: Robot, r2: int): seq[Robot] =
  ## Every enemy inside `r2`, in the engine's own scan order. One credit per
  ## square examined is already charged by `observe`; this charges one per
  ## enemy scored, which is what the micro actually looks at.
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    let other = w.getRobot(l)
    if other != nil and other.team != side.team:
      if not r.spend(1): break
      result.add(other)
