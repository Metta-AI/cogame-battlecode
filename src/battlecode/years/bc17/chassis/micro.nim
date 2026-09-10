## `micro.nim` -- the bullet-threat set, the dodge and the shot shape.
##
## **`willCollideWithMe` IS A PORT OF THE AGPL-3.0 SCAFFOLD BOT'S OWN TEST**
## (`battlecode-scaffold-2017/src/examplefuncsplayer/RobotPlayer.java:253-277`)
## and `NOTICE` names it: the perpendicular distance from the robot's centre
## to the bullet's line of travel, compared against the body radius. Nothing
## else in this file comes from anywhere but the engine source.
##
## **THE SHOT SHAPE IS ARITHMETIC, NOT TASTE.** A triad is 4 bullets for three
## shots at +-20 degrees and a pentad is 6 for five at +-15, against 1 for a
## single. So volume beats aim against a clump and misses five times against
## one dodging scout: `orchard` fires a pentad only when at least three bodies
## lie within +-15 degrees and the stock is above `bullet_reserve + 6`, a
## triad when at least two lie within +-20, and a single otherwise. **A SCOUT
## MAY FIRE ONLY SINGLES** (the engine's own gate).

import std/math
import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit, econ

export kit

func willCollideWithMe*(r: Robot, b: Bullet): bool =
  ## The licensed test, verbatim in structure: reject anything travelling
  ## away from us, then compare the perpendicular distance from our centre to
  ## the bullet's line against our body radius.
  let propagationDir = b.dir
  let bulletLoc = b.loc
  if r.loc == bulletLoc: return true
  let directionToRobot = directionTo(bulletLoc, r.loc)
  let distToRobot = distanceTo(bulletLoc, r.loc)
  let theta = radiansBetween(propagationDir, directionToRobot)
  if abs(theta) > float32(PI) / 2'f32: return false
  let perpendicularDist = abs(distToRobot * float32(sin(float64(theta))))
  perpendicularDist <= bodyRadius(r.kind)

proc threatSet*(w: World, r: Robot): seq[int] =
  ## Every sensed bullet whose next two rounds of flight cross this body.
  ## One credit per bullet tested.
  for id in w.senseBullets(r, -1'f32):
    let b = w.bullets.getOrDefault(id)
    if b == nil: continue
    if not r.chargeFor(1): break
    if r.willCollideWithMe(b):
      result.add(id)

proc dodge*(w: World, r: Robot, threats: seq[int]): bool {.discardable.} =
  ## Pick the legal move that clears the most threats while staying on the
  ## board. A soldier strides 0.8 and a soldier's bullet crosses 2 a round, so
  ## a shot CAN be walked out of -- which is why this exists at all.
  if threats.len == 0 or r.hasMoved(): return false
  var bestDir = -1
  var bestHits = threats.len + 1
  for i, angle in [0'f32, 45'f32, 90'f32, 135'f32, 180'f32, 225'f32,
                   270'f32, 315'f32]:
    if not r.chargeFor(1): break
    let d = dirRads(0'f32).rotateLeftDegrees(angle)
    if not w.canMove(r, d): continue
    let after = addDist(r.loc, d, strideRadius(r.kind))
    var hits = 0
    for id in threats:
      let b = w.bullets.getOrDefault(id)
      if b == nil: continue
      let probe = Robot(id: r.id, kind: r.kind, loc: after, team: r.team)
      if probe.willCollideWithMe(b): inc hits
    if hits < bestHits:
      bestHits = hits
      bestDir = i
  if bestDir < 0 or bestHits >= threats.len: return false
  let d = dirRads(0'f32).rotateLeftDegrees(float32(bestDir) * 45'f32)
  w.move(r, d)

proc chooseShape*(w: World, s: Side, r: Robot, target: Loc,
                  enemies: seq[int]): ShotShape =
  ## Count the sensed enemies inside the cone, then pick the cheapest shape
  ## that covers them. Charged one credit per enemy scored.
  result = ssSingle
  if r.kind == rtScout:
    return ssSingle
  let aim = directionTo(r.loc, target)
  var inFifteen = 0
  var inTwenty = 0
  for id in enemies:
    let other = w.robots.getOrDefault(id)
    if other == nil: continue
    if not r.chargeFor(1): break
    let d = directionTo(r.loc, other.loc)
    let off = abs(radiansBetween(aim, d)) * 180'f32 / float32(PI)
    if off <= 15'f32: inc inFifteen
    if off <= 20'f32: inc inTwenty
  let stock = w.bulletSupplyOf(s.team)
  if inFifteen >= 3 and stock > w.bulletGate(s) + pentadShotCost:
    return ssPentad
  if inTwenty >= 2 and stock > w.bulletGate(s) + triadShotCost:
    return ssTriad
  result = ssSingle

proc engage*(w: World, s: Side, r: Robot, enemies: seq[int]): bool
    {.discardable.} =
  ## Fire at the NEAREST sensed enemy -- `senseNearbyRobots` hands the
  ## chassis its candidates in ascending distance (D2), so `enemies[0]` IS
  ## the nearest -- with the shape the cone deserves.
  if enemies.len == 0 or r.hasAttacked(): return false
  if not canAttack(r.kind) or r.kind == rtLumberjack: return false
  let target = w.robots.getOrDefault(enemies[0])
  if target == nil: return false
  let shape = w.chooseShape(s, r, target.loc, enemies)
  if not w.canFireShot(r, shape): return false
  ## Never spend the reserve on a shot unless the reserve is already gone.
  if w.bulletSupplyOf(s.team) - shotCost(shape) < w.bulletGate(s) and
      shape != ssSingle:
    if not w.canFireShot(r, ssSingle): return false
    return w.fireShot(r, ssSingle, directionTo(r.loc, target.loc))
  w.fireShot(r, shape, directionTo(r.loc, target.loc))
