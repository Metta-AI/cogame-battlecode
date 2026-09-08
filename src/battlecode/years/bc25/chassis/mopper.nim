## `mopper.nim` — `turnPlan()`: refill an ally, erase enemy paint, or strip
## enemy robots.
##
## The mopper turn plan is behaviour-ported from `ecoArcGaming/battlecode25`
## `java/src/v3/` (AGPL-3.0, branch `newMopper`, head `8f17e87`, the Novice
## 2nd-place bot): refill first, then the swing-versus-single scoring.
##
## A mopper is the only unit that can HAND PAINT TO AN ALLY, and it is the
## only unit that can turn an enemy tile BARE (a soldier can never paint over
## enemy paint and a splasher only inside r2 <= 2 of its centre). So the knob
## `mop_enemy_paint` is a real fork:
##
##   0     pure harassment and paint logistics
##   100   a coverage weapon
##
## and refilling an ally below `paint_reserve_floor` ALWAYS pre-empts both,
## independently of the knob — that is the anti-inert floor for this unit.

import kit, econ

export kit, econ

proc refillAlly*(w: World, side: Side, r: Robot): bool =
  ## The one thing only a mopper can do. A POSITIVE transfer is legal only
  ## from a mopper, so this branch has no competitor in the whole chassis.
  if r.paint <= 20: return false
  if not r.isActionReady(): return false
  var pick: Robot = nil
  var worst = high(int)
  for l in w.locationsWithinRadiusSquared(r.loc, PaintTransferRadiusSquared):
    if not r.spend(1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team != side.team or bot.id == r.id: continue
    if not bot.kind.isRobotType(): continue
    let pct = paintPercentage(bot.paint, bot.kind)
    if pct >= side.doctrine.paintReserveFloor: continue
    if pct < worst:
      worst = pct
      pick = bot
  if pick == nil: return false
  let want = min(r.paint - 10,
                 UnitSpecs[pick.kind].paintCapacity - pick.paint)
  if want <= 0: return false
  if not w.canTransferPaint(r, pick.loc, want): return false
  w.doTransferPaint(r, pick.loc, want)
  true

proc bestSwing*(w: World, side: Side, r: Robot): Dir =
  ## The cardinal whose six offsets cover the most enemy ROBOTS. The swing
  ## hits six tiles for 5 paint each, so two enemies is already better than
  ## one single mop — which takes 10 and gives us 5.
  result = dCenter
  var best = 0
  for i, d in CardinalDirs:
    if not w.canMopSwing(r, d): continue
    if not r.spend(2): break
    var count = 0
    for k in 0 .. 5:
      let l = loc(r.loc.x + MopSwingDx[i][k], r.loc.y + MopSwingDy[i][k])
      if not w.onTheMap(l): continue
      let bot = w.getRobot(l)
      if bot != nil and bot.kind.isRobotType() and bot.team != side.team:
        count += 1
    if count > best:
      best = count
      result = d

proc bestMopTile*(w: World, side: Side, r: Robot): Loc =
  ## The enemy tile within r2 <= 2 that most reduces the enemy's connected
  ## frontier — approximated, cheaply and deterministically, by the count of
  ## enemy-painted neighbours it is holding together. A tile carrying an enemy
  ## ROBOT wins outright: mopping it takes 10 of their paint and gives us 5.
  result = loc(-1, -1)
  var best = low(int)
  for l in w.locationsWithinRadiusSquared(
      r.loc, UnitSpecs[utMopper].actionRadiusSquared):
    if not r.spend(1): break
    if not w.canAttackRobot(r, l): continue
    let colour = w.getPaint(l)
    let bot = w.getRobot(l)
    var score = low(int)
    if bot != nil and bot.kind.isRobotType() and bot.team != side.team:
      score = 1000
    elif hasPaintTeam(colour) and teamFromPaint(colour) != side.team:
      score = 0
      for d in MoveDirs:
        let n = l + d
        if w.onTheMap(n) and hasPaintTeam(w.getPaint(n)) and
            teamFromPaint(w.getPaint(n)) != side.team:
          score += 1
    if score == low(int): continue
    if score > best:
      best = score
      result = l

proc turnPlan*(w: World, side: Side, r: Robot): bool {.discardable.} =
  ## The `mop_enemy_paint` split. The share is read against a per-robot
  ## deterministic phase (the robot's own id and round), never a random draw,
  ## so two identical clans on the same seed mop the same tiles.
  if refillAlly(w, side, r): return true
  if not r.isActionReady(): return false
  let phase = (r.id * 7 + w.currentRound) mod 100
  let preferPaint = phase < side.doctrine.mopEnemyPaint
  let swing = bestSwing(w, side, r)
  let tile = bestMopTile(w, side, r)
  let tileHasRobot =
    tile.x >= 0 and w.getRobot(tile) != nil and
    w.getRobot(tile).team != side.team

  if preferPaint and tile.x >= 0 and not tileHasRobot:
    w.doAttackRobot(r, tile)
    return true
  if swing != dCenter:
    w.doMopSwing(r, swing)
    return true
  if tile.x >= 0:
    w.doAttackRobot(r, tile)
    return true
  false

proc runMopper*(w: World, side: Side, r: Robot) =
  if needsRefill(side, r):
    let towerLoc = nearestFriendlyTower(w, side, r, needPaint = true)
    if towerLoc.x >= 0:
      if r.loc.distanceSquaredTo(towerLoc) <= PaintTransferRadiusSquared:
        let want = min(UnitSpecs[r.kind].paintCapacity - r.paint,
                       w.getRobot(towerLoc).paint)
        if want > 0 and w.canTransferPaint(r, towerLoc, -want):
          w.doTransferPaint(r, towerLoc, -want)
      else:
        w.stepToward(side, r, towerLoc)
      return
  if turnPlan(w, side, r): return
  ## Nothing in reach: walk toward the enemy's colour, which is where the work
  ## is, and try again next turn.
  var target = frontierFor(w, side)
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not r.spend(1): break
    let colour = w.getPaint(l)
    if hasPaintTeam(colour) and teamFromPaint(colour) != side.team:
      target = l
      break
  w.stepToward(side, r, target)
