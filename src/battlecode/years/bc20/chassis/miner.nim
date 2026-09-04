## The miner: mine, refine, and — for the ONE elected builder — put up the
## team's buildings in the doctrine's own order.
##
## The builder is the lowest-id living miner, so the election is stable, free
## and needs no signalling. It builds, in this order and only when the team
## pool can afford it without stalling miner production:
##   1 Design School at Chebyshev 2 from the HQ, on the side away from the water
##   `net_gun_ring` Net Guns, also at Chebyshev 2 (a net gun ON the HQ ring
##       would be buried by our own wall — see docs/RULES-BC20.md)
##   1 Fulfillment Center
##   `vaporator_budget` Vaporators inside the lattice
##   a second Design School after round 600
##
## Behaviour, not code, from `StoneT2000/Battlecode2020` (AGPL-3.0; see NOTICE).

import kit, pathing, signals, lattice

const
  BuildReserve = 70          ## never spend the last miner out of the pool
  SoupTipThreshold = 200

proc electBuilder(w: World, side: Side) =
  if side.builderId >= 0 and side.builderId in w.robotsById:
    let existing = w.robotsById[side.builderId]
    if existing.kind == rtMiner and existing.team == side.team:
      return
  var best = high(int)
  for id, r in w.robotsById:
    if r.team == side.team and r.kind == rtMiner and id < best:
      best = id
  side.builderId = if best == high(int): -1 else: best

proc nextBuilding(w: World, side: Side): (bool, RobotKind) =
  let d = side.doctrine
  if w.alive(side, rtDesignSchool) < 1: return (true, rtDesignSchool)
  if w.alive(side, rtNetGun) < d.netGunRing: return (true, rtNetGun)
  if w.alive(side, rtFulfillmentCenter) < 1: return (true, rtFulfillmentCenter)
  ## One Refinery once the near seam is worked out: a miner that has to walk
  ## the whole way back to the HQ spends most of the match in transit, and a
  ## starved pool is what stops the Design School making landscapers.
  if w.currentRound >= 250 and w.alive(side, rtRefinery) < 1:
    return (true, rtRefinery)
  if w.alive(side, rtVaporator) < d.vaporatorBudget: return (true, rtVaporator)
  if w.currentRound >= 600 and w.alive(side, rtDesignSchool) < 2:
    return (true, rtDesignSchool)
  (false, rtMiner)

proc buildSiteScore(w: World, side: Side, kind: RobotKind, l: Loc): int =
  ## Buildings go at Chebyshev 2 from the HQ: close enough to defend, far
  ## enough that the HQ wall does not bury them.
  if not side.hasHq: return low(int)
  let ring = chebyshev(l, side.hqLoc)
  if ring < 2: return low(int)
  ## High ground first: a building cannot be raised (dirt dropped on a
  ## building buries it), so the elevation it is founded on is the elevation it
  ## drowns at.
  var score = 100 - abs(ring - 2) * 20 + w.getDirt(l) * 12
  if w.willFloodNextRound(l): score -= 500
  if kind == rtVaporator and not l.isLatticeTile(): score -= 10
  score

proc tryBuild(w: World, side: Side, r: Robot, kind: RobotKind): bool =
  ## The FIRST Design School is survival, not economy: it is bought with the
  ## last credit in the pool. Everything after it leaves the miners a reserve.
  let reserve =
    if kind == rtDesignSchool and w.alive(side, rtDesignSchool) == 0: 0
    else: BuildReserve
  if w.stats.soup[ord(side.team)] < RobotSpecs[kind].cost + reserve:
    return false
  var bestDir = dCenter
  var bestScore = low(int)
  for d in MoveDirs:
    if not r.spend(1): break
    if not w.canBuildRobot(r, kind, d): continue
    let score = w.buildSiteScore(side, kind, r.loc + d)
    if score > bestScore:
      bestScore = score
      bestDir = d
  if bestDir == dCenter or bestScore == low(int): return false
  if w.buildRobot(r, kind, bestDir) < 0: return false
  w.firstBuild(side, kind)
  true

proc nearestRefinery(w: World, r: Robot, side: Side): (bool, Loc) =
  ## The HQ always refines; a refinery is a bonus. The HQ location is known
  ## from the round-1 broadcast, so a miner never has to search for it.
  var best = loc(0, 0)
  var bestD = high(int)
  var found = false
  if side.hasHq:
    best = side.hqLoc
    bestD = r.loc.distanceSquaredTo(side.hqLoc)
    found = true
  for l in w.sensed(r):
    let occupant = w.getRobot(l)
    if occupant == nil: continue
    if occupant.team != side.team: continue
    if not occupant.kind.canRefine(): continue
    let d = r.loc.distanceSquaredTo(l)
    if d < bestD:
      bestD = d
      best = l
      found = true
  (found, best)

proc nearestSoup(w: World, r: Robot, side: Side): (bool, Loc) =
  var best = loc(0, 0)
  var bestD = high(int)
  var found = false
  for l in w.sensed(r):
    if w.getSoup(l) <= 0: continue
    ## A FLOODED soup tile is still mineable: `assertCanMineSoup` checks only
    ## that the tile is on the map and carries soup, and a miner mines from an
    ## ADJACENT tile. Skipping flooded soup left the whole `WateredDown` seam
    ## — every soup tile within ten of the HQ is under water there — invisible,
    ## and a team that mines nothing builds nothing and drowns on schedule.
    let d = r.loc.distanceSquaredTo(l)
    if d < bestD:
      bestD = d
      best = l
      found = true
  if found: return (true, best)
  ## Nothing in sight: the seam this miner worked last, then the chain.
  let brain = side.brainFor(r)
  if brain.hasSoupTip:
    if w.getSoup(brain.soupTip) > 0:
      return (true, brain.soupTip)
    brain.hasSoupTip = false
  for tip in side.soupTips:
    if not r.spend(1): break
    let d = r.loc.distanceSquaredTo(tip)
    if d < bestD:
      bestD = d
      best = tip
      found = true
  (found, best)

proc runMiner*(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)
  brain.turnCount += 1
  w.readBlocks(side, r)
  w.noteEnemyHq(side)
  if w.fleeWater(side, r): return
  if r.dead: return

  w.electBuilder(side)
  if r.id == side.builderId:
    let (wanted, kind) = w.nextBuilding(side)
    if wanted and isReady(r):
      if w.tryBuild(side, r, kind):
        return

  let spec = RobotSpecs[rtMiner]
  let full = r.soupCarrying >= spec.soupLimit
  let (haveSoup, soupAt) = w.nearestSoup(r, side)

  if full or (r.soupCarrying > 0 and not haveSoup):
    let (haveRefinery, refineryAt) = w.nearestRefinery(r, side)
    if haveRefinery:
      if r.loc.isAdjacentTo(refineryAt):
        let d = fromDelta(refineryAt.x - r.loc.x, refineryAt.y - r.loc.y)
        if w.canDepositSoup(r, d):
          w.depositSoup(r, d, r.soupCarrying)
          return
      w.stepToward(side, r, refineryAt)
      return

  if haveSoup:
    if r.loc.isAdjacentTo(soupAt) or r.loc == soupAt:
      let d = fromDelta(soupAt.x - r.loc.x, soupAt.y - r.loc.y)
      if w.canMineSoup(r, d):
        w.mineSoup(r, d)
        brain.soupTip = soupAt
        brain.hasSoupTip = w.getSoup(soupAt) > 0
        if not brain.announcedSoup and w.getSoup(soupAt) >= SoupTipThreshold:
          brain.announcedSoup = true
          w.broadcast(side, r, SigAnnounceSoup, soupAt.x, soupAt.y)
        return
    w.stepToward(side, r, soupAt)
    return

  ## Nothing in sight and nothing on the chain: EXPLORE. A soup pool is 66
  ## tiles on 1024 on some maps, and a miner that only ever looks inside its
  ## own 113-tile window and then walks home mines nothing at all for the whole
  ## game — which is how a team ends up with no design school, no landscapers
  ## and a drowned HQ. The target is a pure function of the robot's own RNG, so
  ## the search stays deterministic.
  if not brain.hasTarget or r.loc == brain.target or
      w.isFlooded(brain.target) or brain.turnCount mod 60 == 0:
    brain.target = loc(int(brain.rng.nextDouble() * float(w.width)),
                       int(brain.rng.nextDouble() * float(w.height)))
    if not w.onTheMap(brain.target):
      brain.target = side.hqLoc
    brain.hasTarget = true
  w.stepToward(side, r, brain.target)
