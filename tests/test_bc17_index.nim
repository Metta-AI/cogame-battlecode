## §Tests item 12 -- the spatial index, and the candidate ORDER (D2).
##
## The engine's `ObjectInfo` answers every proximity query out of a JTS
## R-tree, whose enumeration order is an implementation detail of a third
## library. This port answers them out of a uniform grid, and the two orders
## are NOT the same -- so the port normalises to
## `(distanceSquaredTo(center), id)` ascending and
## `tools/oracle/bc17/rtree_order.patch` makes the ENGINE side enumerate the
## same way. The normalisation is symmetric; neither trace is massaged alone.
##
## What this shard proves is the half that lives in the sandbox: the grid
## returns EXACTLY the set a brute-force scan does (so the acceleration
## structure adds and drops nothing), and the normalised order is the one the
## chassis-visible arrays are built from.

import std/[algorithm, random]
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom, index, units, world, maps,
                              actions]

let rect = MapRect(origin: loc(0, 0), width: 100, height: 100)

# --- the grid returns exactly the brute-force set ---------------------------
block:
  ## 10 000 random configurations. Any disagreement -- a candidate the grid
  ## missed or one it invented -- is a divergence the trace would only find
  ## a thousand rounds later.
  var rnd = initRand(20170212)
  var idx = initIndex(rect)
  var bodies: seq[tuple[id: int32, l: Loc, r: float32]]
  for i in 0 ..< 400:
    let l = loc(float32(rnd.rand(0.0 .. 100.0)),
                float32(rnd.rand(0.0 .. 100.0)))
    let r = float32(rnd.rand(0.5 .. 10.0))
    idx.add(int32(i + 1), l, r)
    bodies.add((int32(i + 1), l, r))
  var setMismatch = 0
  var orderMismatch = 0
  for q in 0 ..< 10000:
    let center = loc(float32(rnd.rand(-5.0 .. 105.0)),
                     float32(rnd.rand(-5.0 .. 105.0)))
    let radius = float32(rnd.rand(0.0 .. 20.0))
    var brute: seq[tuple[d: float32, id: int32]]
    for b in bodies:
      if isWithinDistance(b.l, center, b.r + radius):
        brute.add((distanceSquaredTo(b.l, center), b.id))
    brute.sort(proc (a, b: tuple[d: float32, id: int32]): int =
      if a.d < b.d: -1
      elif a.d > b.d: 1
      elif a.id < b.id: -1
      elif a.id > b.id: 1
      else: 0)
    var wantIds: seq[int32]
    for r in brute: wantIds.add(r.id)
    let got = idx.sortedCandidates(center, radius)
    if got.len != wantIds.len: inc setMismatch
    elif got != wantIds: inc orderMismatch
  checkEq("the grid returns exactly ObjectInfo's filtered SET over 10 000 " &
    "random configurations", setMismatch, 0)
  checkEq("in exactly the normative (distanceSquared, id) order",
    orderMismatch, 0)

# --- the point form has no body-radius term ---------------------------------
block:
  ## `getAllBulletsWithinRadius` passes the radius straight through with NO
  ## procedure-side filter, so the cut IS the rule -- a different query from
  ## the body one, and the port keeps them apart.
  var idx = initIndex(rect)
  idx.add(1'i32, loc(10, 0), 5'f32)
  let bodyHits = idx.sortedCandidates(loc(0, 0), 6'f32)
  checkEq("a radius-5 body 10 away is INSIDE a radius-6 body query",
    bodyHits, @[1'i32])
  let pointHits = idx.sortedCandidates(loc(0, 0), 6'f32, pointOnly = true)
  checkEq("and OUTSIDE the point query at the same radius",
    pointHits.len, 0)
  checkEq("which reaches it only at radius 10",
    idx.sortedCandidates(loc(0, 0), 10'f32, pointOnly = true), @[1'i32])

# --- the tie-break is the id ------------------------------------------------
block:
  var idx = initIndex(rect)
  ## Three bodies at exactly the same distance, added in DESCENDING id order
  ## so insertion order cannot be mistaken for the answer.
  idx.add(30'i32, loc(50, 53), 1'f32)
  idx.add(20'i32, loc(53, 50), 1'f32)
  idx.add(10'i32, loc(47, 50), 1'f32)
  checkEq("a distance tie is broken by ASCENDING id, not by insertion",
    idx.sortedCandidates(loc(50, 50), 10'f32), @[10'i32, 20'i32, 30'i32])

# --- firstContaining ---------------------------------------------------------
block:
  ## `getTreeAtLocation`/`getRobotAtLocation` return the FIRST candidate whose
  ## circle contains the point, in enumeration order -- so the port's answer
  ## is the `(distSq, id)`-minimal one. At most one body can contain a point
  ## unless a SCOUT is standing on a tree, which is the case that makes this
  ## observable at all.
  var idx = initIndex(rect)
  checkEq("an empty index contains nothing", idx.firstContaining(loc(1, 1)),
    -1'i32)
  idx.add(7'i32, loc(20, 20), 2'f32)
  checkEq("a point inside the disc finds it", idx.firstContaining(loc(21, 20)),
    7'i32)
  checkEq("the boundary is INCLUSIVE", idx.firstContaining(loc(22, 20)),
    7'i32)
  check("one ulp beyond is not",
    idx.firstContaining(loc(cast[float32](cast[uint32](22'f32) + 1'u32),
                            20)) == -1'i32)
  ## The SCOUT-on-a-tree overlap: the nearer centre wins.
  idx.add(9'i32, loc(20.5, 20), 1'f32)
  checkEq("with two overlapping bodies the NEARER centre is returned",
    idx.firstContaining(loc(20.6, 20)), 9'i32)

# --- countWithin has no order and says so -----------------------------------
block:
  var idx = initIndex(rect)
  for i in 0 ..< 5: idx.add(int32(i + 1), loc(float32(10 + i), 10), 1'f32)
  checkEq("countWithin is a length test", idx.countWithin(loc(12, 10), 2'f32),
    idx.sortedCandidates(loc(12, 10), 2'f32).len)
  check("and it is not zero here", idx.countWithin(loc(12, 10), 2'f32) > 0)

# --- move and remove keep the grid honest -----------------------------------
block:
  var idx = initIndex(rect)
  idx.add(1'i32, loc(5, 5), 1'f32)
  check("the body is found where it was added",
    idx.sortedCandidates(loc(5, 5), 0'f32) == @[1'i32])
  idx.move(1'i32, loc(95, 95))
  checkEq("after a move it is gone from the old cell",
    idx.sortedCandidates(loc(5, 5), 0'f32).len, 0)
  checkEq("and present in the new one",
    idx.sortedCandidates(loc(95, 95), 0'f32), @[1'i32])
  checkEq("its stored circle moved too", idx.circleOf(1'i32).loc, loc(95, 95))
  idx.remove(1'i32)
  check("and a removed body is gone", not idx.contains(1'i32))
  checkEq("from the query too", idx.sortedCandidates(loc(95, 95), 5'f32).len,
    0)

# --- the sight radii ---------------------------------------------------------
block:
  ## 14 / 7 / 10 body sight and 20 / 10 / 15 bullet sight, INCLUSIVE at the
  ## boundary -- `canSenseLocation` is `isWithinDistance`, which is `<=`.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  ## `Alone`'s origin is NOT (0, 0) -- a 2017 map carries a float origin and
  ## every coordinate in play is absolute, so the shard places its bodies
  ## relative to it rather than assuming a zeroed board.
  let o = w.rect.origin
  proc at(dx, dy: float32): Loc = loc(o.x + dx, o.y + dy)
  let scout = w.spawnRobot(rtScout, at(50, 50), tA)
  check("a SCOUT senses a body at exactly 14.0",
    scout.canSenseLocation(at(64, 50)))
  check("and not a hundredth beyond",
    not scout.canSenseLocation(at(64.01, 50)))
  check("its bullet sight reaches exactly 20.0",
    scout.canSenseBulletLocation(at(70, 50)))
  check("and not beyond", not scout.canSenseBulletLocation(at(70.01, 50)))
  let soldier = w.spawnRobot(rtSoldier, at(20, 20), tA)
  check("a SOLDIER senses to exactly 7.0",
    soldier.canSenseLocation(at(27, 20)))
  check("and no further", not soldier.canSenseLocation(at(27.01, 20)))
  let archon = w.spawnRobot(rtArchon, at(80, 20), tA)
  check("an ARCHON senses to exactly 10.0",
    archon.canSenseLocation(at(90, 20)))
  check("and its bullet sight to 15.0",
    archon.canSenseBulletLocation(at(95, 20)))
  check("canSensePartOfCircle reaches further than canSenseAllOfCircle",
    soldier.canSensePartOfCircle(at(28, 20), 2'f32) and
      not soldier.canSenseAllOfCircle(at(28, 20), 2'f32))

# --- senseNearbyRobots is ASCENDING BY DISTANCE -----------------------------
block:
  ## Fully order-dependent (D2 (iv)): `examplefuncsplayer17` fires at
  ## `robots[0]` and that must be the NEAREST enemy on both sides of the
  ## oracle. This is why the normalisation is an ordering and not merely a
  ## tie-break.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  proc at(dx, dy: float32): Loc = loc(o.x + dx, o.y + dy)
  let me = w.spawnRobot(rtSoldier, at(50, 50), tA)
  let far = w.spawnRobot(rtSoldier, at(56, 50), tB)
  let near = w.spawnRobot(rtSoldier, at(53, 50), tB)
  let mid = w.spawnRobot(rtSoldier, at(50, 54.5), tB)
  let seen = w.senseNearbyRobots(me, sensorRadius(rtSoldier), ord(tB))
  checkEq("all three enemies are in sight", seen.len, 3)
  checkEq("and robots[0] is the NEAREST, not the first spawned",
    seen[0], near.id)
  checkEq("then the middle one", seen[1], mid.id)
  checkEq("then the far one", seen[2], far.id)
  check("which is neither spawn order nor id order",
    seen != @[far.id, near.id, mid.id] and
      seen != sorted(@[far.id, near.id, mid.id]))
  let all = w.senseNearbyRobots(me, sensorRadius(rtSoldier))
  checkEq("an unfiltered query returns the same three, never the sensor " &
    "itself", all.len, 3)

finish("test_bc17_index")
