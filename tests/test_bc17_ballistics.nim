## §Tests item 5 -- BALLISTICS, the year's crux.
##
## Battlecode 2017 is the only year in this coworld with continuous-space
## bullets, and `InternalBullet.calcHitDist` is where a port either matches
## the engine or spends a thousand rounds slowly disagreeing with it. Two
## lines seven apart inside that one method have OPPOSITE float widths (F3),
## the minimum over candidates is STRICT so a tie keeps the first, and a
## tree/robot tie goes to the ROBOT because `hitTreeDist < hitRobotDist`
## fails.
##
## The last block is the HOIST PROPERTY: the port lifts `maxDist` and
## `toFinish` out of the candidate loop, which the engine recomputes per
## candidate. That is only safe if the two forms agree bit-for-bit, so it is
## checked on a million random configurations rather than argued.

import std/[math, random]
import harness
import bc17_fixture
import battlecode/fdlibm
import battlecode/years/bc17/[constants, geom, units, ballistics, world, maps,
                              index]

proc unhoisted(bulletStart, bulletFinish: Loc, targetCenter: Loc,
               targetRadius: float32): float32 =
  ## `calcHitDist` with NOTHING lifted -- `maxDist` and `toFinish` recomputed
  ## from the two endpoints exactly where the Java method computes them.
  let maxDist = distanceTo(bulletStart, bulletFinish)
  let toFinish = directionTo(bulletStart, bulletFinish)
  calcHitDist(bulletStart, bulletFinish, maxDist, toFinish, targetCenter,
              targetRadius)

# --- calcHitDist, vector by vector ------------------------------------------
block:
  let start = loc(0, 0)
  let finish = loc(10, 0)
  let toFinish = directionTo(start, finish)
  ## A shot straight at the centre of a radius-1 body at distance 5 hits at
  ## 5 - 1 = 4.
  checkEq("a shot at the centre of a radius-1 body 5 away hits at 4",
    bits(calcHitDist(start, finish, 10'f32, toFinish, loc(5, 0), 1'f32)),
    bits(4'f32))
  ## A GRAZE at exactly `perpDist == targetRadius` is a HIT: the rejection
  ## test is `perpDist > targetRadius`, strictly greater.
  checkEq("a graze at exactly perpDist == radius is a HIT (the test is >)",
    bits(calcHitDist(start, finish, 10'f32, toFinish, loc(5, 1), 1'f32)),
    bits(5'f32))
  let justOver = cast[float32](cast[uint32](1'f32) + 1'u32)
  checkEq("and one ulp further out is a MISS",
    calcHitDist(start, finish, 10'f32, toFinish, loc(5, justOver), 1'f32),
    -1'f32)
  ## A bullet STARTING INSIDE the circle: `hitDist` comes out negative,
  ## `+ halfChordDist` brings it to >= 0, and the branch forces 0.
  checkEq("a bullet starting inside the disc is an immediate hit",
    bits(calcHitDist(start, finish, 10'f32, toFinish, loc(0.5, 0), 1'f32)),
    bits(0'f32))
  ## A target BEHIND the bullet is rejected.
  checkEq("a target behind the bullet is rejected",
    calcHitDist(start, finish, 10'f32, toFinish, loc(-5, 0), 1'f32), -1'f32)
  ## A target beyond `maxDist` is rejected.
  checkEq("a target past maxDist is rejected",
    calcHitDist(start, finish, 3'f32, toFinish, loc(5, 0), 1'f32), -1'f32)
  check("but reachable when maxDist covers it",
    calcHitDist(start, finish, 5'f32, toFinish, loc(5, 0), 1'f32) >= 0'f32)
  ## `toTarget == null` -- the bullet is exactly ON the target's centre.
  checkEq("a bullet ON the target's centre hits at 0",
    bits(calcHitDist(start, finish, 10'f32, toFinish, loc(0, 0), 1'f32)),
    bits(0'f32))

# --- the hoist property, on a million configurations ------------------------
block:
  var rnd = initRand(20170305)
  var disagreements = 0
  var hits = 0
  var misses = 0
  for i in 0 ..< 1000000:
    let sx = float32(rnd.rand(-50.0 .. 50.0))
    let sy = float32(rnd.rand(-50.0 .. 50.0))
    let bulletStart = loc(sx, sy)
    let dir = dirRads(float32(rnd.rand(-3.14 .. 3.14)))
    let speed = float32(rnd.rand(1.5 .. 4.0))
    let bulletFinish = addDist(bulletStart, dir, speed)
    let target = loc(sx + float32(rnd.rand(-6.0 .. 6.0)),
                     sy + float32(rnd.rand(-6.0 .. 6.0)))
    let radius = float32(rnd.rand(0.5 .. 2.0))
    let a = calcHitDist(bulletStart, bulletFinish,
                        distanceTo(bulletStart, bulletFinish),
                        directionTo(bulletStart, bulletFinish), target,
                        radius)
    let b = unhoisted(bulletStart, bulletFinish, target, radius)
    if bits(a) != bits(b): inc disagreements
    if a >= 0'f32: inc hits else: inc misses
  checkEq("the hoisted and unhoisted forms agree bit-for-bit on 1 000 000 " &
    "random configurations", disagreements, 0)
  check("and the sample really did exercise both branches",
    hits > 50000 and misses > 50000)
  echo "  ", hits, " hits and ", misses, " misses in the million"

# --- the strict minimum keeps the FIRST candidate on a tie ------------------
block:
  ## Two identical trees at the same `hitDist`, straddling the line. The
  ## engine's `if (hitDist < closestDist)` is STRICT, so the first candidate
  ## in enumeration order wins -- and the port's enumeration order is the
  ## normalised `(distanceSquared, id)` one, so the answer is deterministic
  ## on both sides.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  proc at(dx, dy: float32): Loc = loc(o.x + dx, o.y + dy)
  let lo = w.spawnTree(tNeutral, 1'f32, at(50, 51), 0, -1)
  let hi = w.spawnTree(tNeutral, 1'f32, at(50, 49), 0, -1)
  let firer = w.spawnRobot(rtSoldier, at(40, 50), tA)
  let bid = w.spawnBullet(tA, 20'f32, 2'f32, at(42, 50),
                          dirRads(0), firer.id)
  let b = w.bullets[bid]
  let startHealth = (lo.health, hi.health)
  w.updateBullet(b)
  let damaged = (lo.health < startHealth[0], hi.health < startHealth[1])
  check("exactly ONE of the two tied trees was hit",
    damaged[0] != damaged[1])
  let winner = (if damaged[0]: lo.id else: hi.id)
  checkEq("and it is the (distanceSquared, id)-minimal candidate",
    winner, min(lo.id, hi.id))

# --- a tree/robot tie goes to the ROBOT -------------------------------------
block:
  ## `hitTreeDist < hitRobotDist` is strict, so an exact tie falls through to
  ## the robot branch.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  proc at(dx, dy: float32): Loc = loc(o.x + dx, o.y + dy)
  let tr = w.spawnTree(tNeutral, 1'f32, at(50, 51), 0, -1)
  let victim = w.spawnRobot(rtSoldier, at(50, 49), tB)
  let firer = w.spawnRobot(rtSoldier, at(40, 50), tA)
  let treeHealth = tr.health
  let robotHealth = victim.health
  let bid = w.spawnBullet(tA, 20'f32, 2'f32, at(42, 50), dirRads(0), firer.id)
  w.updateBullet(w.bullets[bid])
  check("the ROBOT took the damage", victim.health < robotHealth)
  checkEq("and the tree took none", bits(tr.health), bits(treeHealth))

# --- no team check and no exclusion of the firer ----------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  proc at(dx, dy: float32): Loc = loc(o.x + dx, o.y + dy)
  let friend = w.spawnRobot(rtSoldier, at(50, 50), tA)
  let firer = w.spawnRobot(rtSoldier, at(40, 50), tA)
  let before = friend.health
  let bid = w.spawnBullet(tA, 20'f32, 2'f32, at(42, 50), dirRads(0), firer.id)
  w.updateBullet(w.bullets[bid])
  check("a bullet hits its OWN TEAM -- there is no team check",
    friend.health < before)
  check("and the damage is booked as friendly fire",
    w.stats.friendlyFireDamage[ord(tA)] > 0'f32)
  ## The firer walking onto its own bullet.
  var v = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o2 = v.rect.origin
  proc at2(dx, dy: float32): Loc = loc(o2.x + dx, o2.y + dy)
  let shooter = v.spawnRobot(rtTank, at2(40, 50), tA)
  let bid2 = v.spawnBullet(tA, 20'f32, 5'f32, at2(45, 50), dirRads(FloatPi),
                           shooter.id)
  let hp = shooter.health
  v.updateBullet(v.bullets[bid2])
  check("and a robot that walks in front of its own bullet is hit by it",
    shooter.health < hp)

# --- exit through each of the four edges ------------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let w32 = w.rect.width
  let h32 = w.rect.height
  ## The firer sits in the middle of the board: a bullet spawned INSIDE a
  ## robot's own disc is eaten by the muzzle check before it can fly.
  let firer = w.spawnRobot(rtScout, loc(o.x + 20, o.y + 20), tA)
  var exits = 0
  for (l, d) in [(loc(o.x + 1, o.y + 50), FloatPi),
                 (loc(o.x + w32 - 1, o.y + 50), 0'f32),
                 (loc(o.x + 50, o.y + 1), float32(-PI / 2.0)),
                 (loc(o.x + 50, o.y + h32 - 1), float32(PI / 2.0))]:
    let bid = w.spawnBullet(tA, 4'f32, 1'f32, l, dirRads(d), firer.id)
    w.updateBullet(w.bullets[bid])
    if not w.bullets.hasKey(bid): inc exits
  checkEq("a bullet leaving through any of the four edges is destroyed",
    exits, 4)
  ## And the edge itself is INCLUSIVE: a bullet that lands exactly on it
  ## survives, because `onTheMap` is a `<=` on all four sides.
  let onEdge = w.spawnBullet(tA, 2'f32, 1'f32, loc(o.x + w32 - 2, o.y + 50),
                             dirRads(0), firer.id)
  w.updateBullet(w.bullets[onEdge])
  check("but the boundary is on the map, so one landing exactly on it lives",
    w.bullets.hasKey(onEdge))

# --- the muzzle collision ---------------------------------------------------
block:
  ## `spawnBullet` checks `getRobotAtLocation` FIRST, then
  ## `getTreeAtLocation`, and on a hit the bullet damages the body and NEVER
  ## ENTERS THE WORLD -- so it consumes an id and never appears in the exec
  ## order.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  proc at(dx, dy: float32): Loc = loc(o.x + dx, o.y + dy)
  let blocker = w.spawnRobot(rtTank, at(50, 50), tB)
  let firer = w.spawnRobot(rtSoldier, at(40, 50), tA)
  let hp = blocker.health
  let before = w.bullets.len
  let bid = w.spawnBullet(tA, 2'f32, 2'f32, at(50, 50), dirRads(0), firer.id)
  check("the muzzle collision damaged the body", blocker.health < hp)
  checkEq("and no bullet entered the world", w.bullets.len, before)
  check("though the id was consumed", not w.bullets.hasKey(bid))
  ## A tree at the muzzle, with no robot there.
  let tr = w.spawnTree(tNeutral, 2'f32, at(20, 20), 0, -1)
  let th = tr.health
  discard w.spawnBullet(tA, 2'f32, 2'f32, at(20, 20), dirRads(0), firer.id)
  check("a tree at the muzzle is damaged the same way", tr.health < th)

# --- the bullet is inserted immediately BEFORE its parent -------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  proc at(dx, dy: float32): Loc = loc(o.x + dx, o.y + dy)
  let firer = w.spawnRobot(rtSoldier, at(40, 50), tA)
  let bid = w.spawnBullet(tA, 2'f32, 2'f32, at(42, 50), dirRads(0), firer.id)
  let iB = w.execOrder.find(bid)
  let iP = w.execOrder.find(firer.id)
  check("both are in the exec order", iB >= 0 and iP >= 0)
  checkEq("and the bullet sits immediately before its parent", iB + 1, iP)

# --- Float.MAX_VALUE is load-bearing exactly once ---------------------------
block:
  checkEq("FloatMax is Float.MAX_VALUE", bits(FloatMax),
    0x7f7fffff'u32)
  check("so 'a tree was hit and a robot was not' compares true",
    1'f32 < FloatMax)

finish("test_bc17_ballistics")
