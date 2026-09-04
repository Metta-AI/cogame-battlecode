## The Delivery Drone: four roles, selected by the `drone_role` knob.
##
##   harass             hunt enemy units inside `r² <= 3` and drop them on the
##                      nearest flooded tile
##   wall               hold a ring at Chebyshev 4 from the enemy HQ, blocking
##                      ground movement
##   buster             hunt enemy drones sitting in a wall by baiting them
##                      over our own net guns, and ferry a landscaper to the
##                      enemy HQ
##   carry_landscapers  ferry our own landscapers over impassable elevation
##                      onto the lattice
##
## Every role avoids tiles within `r² <= 15` of a known enemy Net Gun or enemy
## HQ unless it is carrying a landscaper to the enemy HQ, and a carried unit is
## always dropped on the nearest flooded tile that is not adjacent to a
## friendly building.
##
## Behaviour, not code, from `StoneT2000/Battlecode2020` (AGPL-3.0; see NOTICE).

import kit, pathing, signals

proc underGunFire(w: World, side: Side, r: Robot, l: Loc): bool =
  ## A cheap, bounded threat test: the drone only knows about guns it can see.
  for seen in w.sensed(r):
    let occupant = w.getRobot(seen)
    if occupant == nil: continue
    if occupant.team == side.team or occupant.team == teamNeutral: continue
    if occupant.kind notin {rtNetGun, rtHq}: continue
    if l.distanceSquaredTo(seen) <= NetGunShootRadiusSquared: return true
  false

proc nearestWaterTile(w: World, side: Side, r: Robot): (bool, Loc) =
  var best = loc(0, 0)
  var bestD = high(int)
  var found = false
  for l in w.sensed(r):
    if not w.isFlooded(l): continue
    if w.isLocationOccupied(l): continue
    if side.hasHq and chebyshev(l, side.hqLoc) <= 2: continue
    let d = r.loc.distanceSquaredTo(l)
    if d < bestD:
      bestD = d
      best = l
      found = true
  (found, best)

proc pickupTarget(w: World, side: Side, r: Robot,
                  wantOwn: bool): (bool, int, Loc) =
  var bestId = -1
  var bestLoc = loc(0, 0)
  var bestD = high(int)
  for l in w.locationsWithinRadiusSquared(r.loc,
      DeliveryDronePickupRadiusSquared):
    if not r.spend(1): break
    let target = w.getRobot(l)
    if target == nil: continue
    if not target.kind.canBePickedUp(): continue
    if target.blocked: continue
    let mine = target.team == side.team
    if wantOwn:
      if not mine or target.kind != rtLandscaper: continue
    else:
      if mine or target.team == teamNeutral: continue
    let d = r.loc.distanceSquaredTo(l)
    if d < bestD:
      bestD = d
      bestId = target.id
      bestLoc = l
  (bestId >= 0, bestId, bestLoc)

proc dropCargo(w: World, side: Side, r: Robot, intoWater: bool): bool =
  if not r.holdingUnit: return false
  if intoWater:
    for d in MoveDirs:
      if not r.spend(1): break
      let l = r.loc + d
      if not w.isFlooded(l): continue
      if not w.canDropUnit(r, d): continue
      w.dropUnit(r, d)
      return true
    return false
  for d in MoveDirs:
    if not r.spend(1): break
    let l = r.loc + d
    if w.isFlooded(l): continue
    if not w.canDropUnit(r, d): continue
    w.dropUnit(r, d)
    return true
  false

proc huntEnemies(w: World, side: Side, r: Robot): bool =
  ## Look for something to lift anywhere in sight and close on it; the pickup
  ## itself only fires inside `r² <= 3`.
  var best = loc(0, 0)
  var bestD = high(int)
  var found = false
  for l in w.sensed(r):
    let target = w.getRobot(l)
    if target == nil: continue
    if target.team == side.team or target.team == teamNeutral: continue
    if not target.kind.canBePickedUp(): continue
    if target.blocked: continue
    let d = r.loc.distanceSquaredTo(l)
    if d < bestD:
      bestD = d
      best = l
      found = true
  if not found: return false
  w.stepToward(side, r, best)

proc runHarass(w: World, side: Side, r: Robot) =
  if r.holdingUnit:
    let (haveWater, water) = w.nearestWaterTile(side, r)
    if haveWater and r.loc.isAdjacentTo(water):
      if w.dropCargo(side, r, intoWater = true): return
    if haveWater:
      w.stepToward(side, r, water)
      return
    if side.hasEnemyHq:
      w.stepToward(side, r, side.enemyHqLoc)
    return
  let (havePickup, id, _) = w.pickupTarget(side, r, wantOwn = false)
  if havePickup and w.canPickUpUnit(r, id):
    w.pickUpUnit(r, id)
    return
  if w.huntEnemies(side, r): return
  if side.hasEnemyHq and not w.underGunFire(side, r, r.loc):
    w.stepToward(side, r, side.enemyHqLoc)

proc runWallRole(w: World, side: Side, r: Robot) =
  ## A ring at Chebyshev 4 from the enemy HQ. The station is a pure function of
  ## the robot id, so the ring fills evenly without any signalling.
  if not side.hasEnemyHq:
    w.runHarass(side, r)
    return
  if r.holdingUnit:
    discard w.dropCargo(side, r, intoWater = true)
    return
  let slot = r.id mod 8
  let d = MoveDirs[slot]
  let station = loc(side.enemyHqLoc.x + d.dx * 4, side.enemyHqLoc.y + d.dy * 4)
  if r.loc == station:
    let (havePickup, id, _) = w.pickupTarget(side, r, wantOwn = false)
    if havePickup and w.canPickUpUnit(r, id):
      w.pickUpUnit(r, id)
    return
  if not w.onTheMap(station):
    w.runHarass(side, r)
    return
  w.stepToward(side, r, station)

proc runBuster(w: World, side: Side, r: Robot) =
  ## Ferry a landscaper to the enemy HQ, and bait enemy drones back over our
  ## own guns when we are empty.
  if r.holdingUnit:
    if side.hasEnemyHq and chebyshev(r.loc, side.enemyHqLoc) <= 2:
      if w.dropCargo(side, r, intoWater = false): return
    if side.hasEnemyHq:
      w.stepToward(side, r, side.enemyHqLoc)
      return
    discard w.dropCargo(side, r, intoWater = false)
    return
  let (haveOwn, ownId, _) = w.pickupTarget(side, r, wantOwn = true)
  if haveOwn and w.canPickUpUnit(r, ownId):
    w.pickUpUnit(r, ownId)
    return
  let (haveEnemy, enemyId, _) = w.pickupTarget(side, r, wantOwn = false)
  if haveEnemy and w.canPickUpUnit(r, enemyId):
    w.pickUpUnit(r, enemyId)
    return
  if side.hasHq and w.underGunFire(side, r, r.loc):
    ## Bait: fall back over our own guns rather than trade with theirs.
    w.stepToward(side, r, side.hqLoc)
    return
  if side.hasHq and w.alive(side, rtLandscaper) > 0:
    w.stepToward(side, r, side.hqLoc)

proc runCarryLandscapers(w: World, side: Side, r: Robot) =
  if r.holdingUnit:
    if side.hasHq and chebyshev(r.loc, side.hqLoc) <=
        side.doctrine.latticeRadius:
      if w.dropCargo(side, r, intoWater = false): return
    if side.hasHq:
      w.stepToward(side, r, side.hqLoc)
      return
    discard w.dropCargo(side, r, intoWater = false)
    return
  let (haveOwn, ownId, at) = w.pickupTarget(side, r, wantOwn = true)
  if haveOwn and w.canPickUpUnit(r, ownId):
    ## Only ferry a landscaper that is actually stuck — one standing outside
    ## the lattice or on ground the flood takes next round.
    let stuck = w.willFloodNextRound(at) or
      (side.hasHq and chebyshev(at, side.hqLoc) > side.doctrine.latticeRadius)
    if stuck:
      w.pickUpUnit(r, ownId)
      return
  if side.hasHq:
    w.stepToward(side, r, side.hqLoc)

proc runDrone*(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)
  brain.turnCount += 1
  w.readBlocks(side, r)
  w.noteEnemyHq(side)
  if not isReady(r): return
  case side.doctrine.droneRole
  of drHarass: w.runHarass(side, r)
  of drWall: w.runWallRole(side, r)
  of drBuster: w.runBuster(side, r)
  of drCarryLandscapers: w.runCarryLandscapers(side, r)
