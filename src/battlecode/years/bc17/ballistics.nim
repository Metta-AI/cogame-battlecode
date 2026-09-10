## Ballistics: `updateBullet` and `calcHitDist`.
##
## **THE SINGLE MOST WIDTH-SENSITIVE FILE IN THIS REPOSITORY.** It is a port
## of `world/InternalBullet.java:98-204` at commit `165d8a8e`, and the two
## lines seven apart in `calcHitDist` that have OPPOSITE shapes are the
## easiest way to break bc17 parity:
##
##     perpDist  = (float) Math.abs(distToTarget * Math.sin(radiansBetween));
##                 // the product is formed in FLOAT64 and narrowed ONCE
##     hitDist   = distToTarget * (float) Math.cos(radiansBetween);
##                 // the cosine is narrowed FIRST and the multiply is FLOAT32
##
## `tests/test_bc17_widths.nim` pins one named vector per row of the F3 width
## table so a port that swaps those two fails a unit test rather than a
## 2 999-round trace diff.
##
## **THE THREE PER-BULLET INVARIANTS ARE HOISTED OUT OF THE CANDIDATE LOOP**
## (`toFinish`, `maxDist` and `distToFinish`), because each is a deterministic
## function of the bullet alone and the hoist is therefore bit-identical BY
## CONSTRUCTION -- the engine recomputes all three inside `calcHitDist` for
## every candidate, and on `Chess` that is 87 candidates a bullet. The
## identity is not assumed: `tests/test_bc17_ballistics.nim` asserts the
## hoisted and unhoisted forms agree bit for bit on 10^6 random
## configurations.
##
## **THE STRICT-MINIMUM LOOPS DO NOT SORT.** The engine keeps a candidate iff
## `hitDist < best && hitDist >= 0`, walking its own enumeration order, so the
## winner is the FIRST candidate achieving the minimum -- which, under the
## normalised `(distanceSquared, id)` enumeration of `index.nim` (D2), is
## exactly the lexicographic minimum of `(hitDist, distSq, id)`. Computing
## that in one allocation-free pass is the same answer, not an approximation.

import std/math
import ../../sim_types
import ../../fdlibm
import ../../rng
import constants, units, geom, world, trees

export world

const FloatMax* = 3.4028234663852886e+38'f32
  ## `Float.MAX_VALUE`, the sentinel both `hitTreeDist` and `hitRobotDist`
  ## start at. It is load-bearing exactly once: when a tree was hit and a
  ## robot was not, `hitTreeDist < hitRobotDist` must be true.

func calcHitDist*(bulletStart, bulletFinish: Loc, maxDist: float32,
                  toFinish: Dir, targetCenter: Loc,
                  targetRadius: float32): float32 =
  ## `InternalBullet.calcHitDist` (`:162-204`), with `maxDist` and `toFinish`
  ## hoisted. Returns `-1` for "no hit".
  ##
  ## `toTarget == null` -- i.e. the bullet is exactly on the target's centre --
  ## **returns 0, an immediate hit**; a null `toFinish` throws in the engine
  ## and is unreachable here (a bullet's speed is at least 1.5, so
  ## `bulletStart != bulletFinish`), which `updateBullet` asserts.
  let distToTarget = distanceTo(bulletStart, targetCenter)
  if bulletStart == targetCenter:
    return 0'f32
  let toTarget = directionTo(bulletStart, targetCenter)
  let between = radiansBetween(toFinish, toTarget)
  ## The product in FLOAT64, `Math.abs` on the double, narrowed once.
  let perpDist = float32(abs(float64(distToTarget) *
                             fdlibmSin(float64(between))))
  if perpDist > targetRadius:
    return -1'f32
  ## The two products and the subtraction in FLOAT32, only the sqrt widened.
  let halfChordDist = float32(sqrt(float64(
    targetRadius * targetRadius - perpDist * perpDist)))
  ## The cosine narrowed FIRST, the multiply in FLOAT32.
  var hitDist = distToTarget * float32(fdlibmCos(float64(between)))
  if hitDist < 0'f32:
    hitDist = hitDist + halfChordDist
    hitDist = (if hitDist >= 0'f32: 0'f32 else: hitDist)
  else:
    hitDist = hitDist - halfChordDist
    hitDist = (if hitDist < 0'f32: 0'f32 else: hitDist)
  if hitDist < 0'f32 or hitDist > maxDist:
    return -1'f32
  hitDist

proc updateBullet*(w: World, b: Bullet) =
  ## `InternalBullet.updateBullet` (`:98-156`) -- the continuous-space core.
  ##
  ## The candidate discs are the engine's own:
  ## `getAllTreesWithinRadius(checkCenter, NEUTRAL_TREE_MAX_RADIUS +
  ## distToFinish/2)` and `getAllRobotsWithinRadius(checkCenter,
  ## MAX_ROBOT_RADIUS + distToFinish/2)`, whose procedure-side filters are
  ## `dist <= body.radius + radius`.
  ##
  ## **NO TEAM CHECK AND NO EXCLUSION OF THE FIRING ROBOT**: a bullet hits its
  ## own side, and a robot that fires and then walks onto its own bullet is hit
  ## by it.
  if not b.alive: return
  let bulletStart = b.loc
  let bulletFinish = addDist(bulletStart, b.dir, b.speed)
  if bulletStart == bulletFinish:
    ## The engine throws `RuntimeException("bulletStart and bulletFinish are
    ## the same.")` here, which `runRound`'s blanket catch turns into a game
    ## that ends with no winner (V5). Unreachable: the slowest bullet in the
    ## year crosses 1.5 units a round.
    raise newException(BattlecodeError,
      "bc17: a bullet did not move (speed " & $b.speed & ") -- the engine " &
      "throws here and ends the game with no winner (V5)")
  let toFinish = directionTo(bulletStart, bulletFinish)
  let distToFinish = distanceTo(bulletStart, bulletFinish)
  let checkCenter = addDist(bulletStart, toFinish, distToFinish / 2'f32)

  ## Closest hit tree, by the engine's strict minimum.
  var hitTree = -1
  var hitTreeDist = FloatMax
  var treeKeyD = 0'f32
  for c in w.treeIndex.withinRadius(checkCenter,
                                    neutralTreeMaxRadius +
                                      distToFinish / 2'f32):
    let hd = calcHitDist(bulletStart, bulletFinish, distToFinish, toFinish,
                         c.loc, c.radius)
    if hd < 0'f32: continue
    let kd = distanceSquaredTo(c.loc, checkCenter)
    if hitTree < 0 or hd < hitTreeDist or
        (hd == hitTreeDist and (kd < treeKeyD or
          (kd == treeKeyD and int(c.id) < hitTree))):
      hitTree = int(c.id)
      hitTreeDist = hd
      treeKeyD = kd

  ## Closest hit robot, likewise.
  var hitRobot = -1
  var hitRobotDist = FloatMax
  var robotKeyD = 0'f32
  for c in w.robotIndex.withinRadius(checkCenter,
                                     maxRobotRadius + distToFinish / 2'f32):
    let hd = calcHitDist(bulletStart, bulletFinish, distToFinish, toFinish,
                         c.loc, c.radius)
    if hd < 0'f32: continue
    let kd = distanceSquaredTo(c.loc, checkCenter)
    if hitRobot < 0 or hd < hitRobotDist or
        (hd == hitRobotDist and (kd < robotKeyD or
          (kd == robotKeyD and int(c.id) < hitRobot))):
      hitRobot = int(c.id)
      hitRobotDist = hd
      robotKeyD = kd

  if hitRobot < 0 and hitTree < 0:
    ## `onTheMap(bulletFinish)` is a POINT test, INCLUSIVE on all four edges.
    if not w.rect.onTheMap(bulletFinish):
      w.destroyBullet(b.id)
    else:
      w.setBulletLocation(b, bulletFinish)
  elif hitTreeDist < hitRobotDist and hitTree >= 0:
    ## **A tree/robot tie at the same `hitDist` goes to the ROBOT** -- the `<`
    ## fails.
    ##
    ## The bullet's damage and team are copied out BEFORE `destroyBullet`
    ## drops the world's last reference to it: under `--mm:arc` a `ref`
    ## parameter is borrowed, not counted, so reading `b.damage` after the
    ## table entry is gone is a use-after-free -- and it presented as an
    ## `IndexDefect` on `ord(b.team)` rather than as a crash.
    let damage = b.damage
    let team = b.team
    let tr = w.trees[hitTree]
    w.destroyBullet(b.id)
    w.damageTree(tr, damage, team, false, "bullet")
  elif hitRobot >= 0:
    let damage = b.damage
    let team = b.team
    let r = w.robots[hitRobot]
    w.destroyBullet(b.id)
    w.damageRobot(r, damage, team)
  else:
    raise newException(BattlecodeError,
      "bc17: closest hit object was null -- the engine's own " &
      "\"This should never happen\" branch (V5)")

proc spawnBullet*(w: World, team: Team, speed, damage: float32, l: Loc,
                  dir: Dir, parentId: int): int {.discardable.} =
  ## `GameWorld.spawnBullet` (`:363-391`): the id, then **a collision check at
  ## the muzzle** -- `getRobotAtLocation(loc)` FIRST, then
  ## `getTreeAtLocation(loc)` -- and if either is occupied the bullet damages
  ## it and NEVER ENTERS THE WORLD. Both lookups return the FIRST candidate in
  ## the normalised enumeration order (D2).
  ##
  ## The exec-order insert is `indexOf(parent)`, i.e. immediately BEFORE the
  ## robot that fired it, so a bullet first moves on the round AFTER it is
  ## fired and always just before its parent's next turn.
  let id = w.bulletIdGen.nextId()
  inc w.bulletIdsIssued
  result = id
  let botId = w.robotIndex.firstContaining(l)
  let treeId = w.treeIndex.firstContaining(l)
  if botId >= 0:
    w.damageRobot(w.robots[int(botId)], damage, team)
    return
  if treeId >= 0:
    w.damageTree(w.trees[int(treeId)], damage, team, false, "bullet")
    return
  let b = Bullet(id: id, team: team, loc: l, dir: dir, speed: speed,
                 damage: damage, roundsAlive: 0, alive: true)
  w.bullets[id] = b
  w.bulletKeys.put(id)
  var at = w.execOrder.len
  for i in 0 ..< w.execOrder.len:
    if w.execOrder[i] == parentId:
      at = i
      break
  w.execOrder.insert(id, at)
  w.bulletIndex.add(int32(id), l, 0'f32)
  if w.bullets.len > w.stats.peakBulletsInFlight:
    w.stats.peakBulletsInFlight = w.bullets.len
