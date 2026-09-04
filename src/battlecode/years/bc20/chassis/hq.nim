## The HQ: build miners on the curve, shoot drones, and open the round-1
## broadcast.
##
## Behaviour, not code, from `StoneT2000/Battlecode2020` (AGPL-3.0; see NOTICE).

import kit, signals

proc bestBuildDir(w: World, side: Side, r: Robot, kind: RobotKind): Dir =
  ## Prefer the direction AWAY from the nearest flooded tile, so a fresh miner
  ## is not spawned onto ground the water takes next.
  var bestDir = dCenter
  var bestScore = low(int)
  for d in MoveDirs:
    if not r.spend(1): break
    if not w.canBuildRobot(r, kind, d): continue
    let candidate = r.loc + d
    var score = w.getDirt(candidate) * 4
    if w.willFloodNextRound(candidate): score -= 100
    if side.hasEnemyHq:
      ## Miners come out on the side facing the map, not into a corner.
      score -= chebyshev(candidate, side.enemyHqLoc) div 8
    if score > bestScore:
      bestScore = score
      bestDir = d
  bestDir

proc shootNearestDrone*(w: World, side: Side, r: Robot): bool
    {.discardable.} =
  ## Both the HQ and a net gun have this; the HQ runs it BEFORE building.
  if not isReady(r): return false
  var bestId = -1
  var bestD = high(int)
  var bestCarrying = false
  for l in w.locationsWithinRadiusSquared(r.loc, NetGunShootRadiusSquared):
    if not r.spend(1): break
    let target = w.getRobot(l)
    if target == nil: continue
    if target.kind != rtDeliveryDrone: continue
    if target.team == r.team or target.team == teamNeutral: continue
    let d = r.loc.distanceSquaredTo(l)
    ## A drone that is CARRYING something is the one to take down first: the
    ## unit it is holding dies with it if it is over water.
    if (target.holdingUnit and not bestCarrying) or
        (target.holdingUnit == bestCarrying and d < bestD):
      bestD = d
      bestId = target.id
      bestCarrying = target.holdingUnit
  if bestId < 0: return false
  if not w.canShootUnit(r, bestId): return false
  w.shootUnit(r, bestId)
  true

proc runHq*(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)
  brain.turnCount += 1
  w.noteHq(side)
  w.noteEnemyHq(side)

  if brain.turnCount == 1:
    w.broadcast(side, r, SigHqLocation, r.loc.x, r.loc.y)
  if side.doctrine.wallHqRound > 0 and
      w.currentRound == w.effectiveWallRound(side):
    w.broadcast(side, r, SigWallIn, r.loc.x, r.loc.y)
  if side.doctrine.rushTrigger > 0 and
      w.currentRound == side.doctrine.rushTrigger:
    w.broadcast(side, r, SigRushNow, side.enemyHqLoc.x, side.enemyHqLoc.y)

  ## A half-buried HQ shouts about it and stops spending.
  if r.dirtCarrying >= RobotSpecs[rtHq].dirtLimit div 2:
    w.broadcast(side, r, SigHqUnderAttack, r.dirtCarrying)
    discard w.shootNearestDrone(side, r)
    return

  discard w.shootNearestDrone(side, r)
  if not isReady(r): return
  if w.alive(side, rtMiner) >= side.doctrine.minerTarget(w.currentRound):
    return
  ## RESERVE for the first Design School. Six miners at 70 is 420 soup and the
  ## pool starts at 200, so an HQ that spends every credit on miners never lets
  ## the builder afford a school — and a team with no landscapers cannot wall,
  ## and an HQ that cannot wall drowns on the schedule. Three miners is enough
  ## to earn the 150 back.
  let reserve =
    if w.alive(side, rtDesignSchool) < 1 and w.alive(side, rtMiner) >= 3:
      RobotSpecs[rtDesignSchool].cost
    else: 0
  if w.stats.soup[ord(side.team)] < RobotSpecs[rtMiner].cost + reserve: return
  let d = w.bestBuildDir(side, r, rtMiner)
  if d == dCenter: return
  if w.buildRobot(r, rtMiner, d) >= 0:
    w.firstBuild(side, rtMiner)
