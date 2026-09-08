## bc23's vision: r2 <= 34 for a headquarters and an amplifier, r2 <= 20 for
## everyone else, COLLAPSING TO r2 <= 4 whenever the sensing robot's tile OR
## the sensed tile is a cloud — both directions, which is what makes a cloud a
## hiding place. Plus the engine's `ceil(sqrt(r2)) + 1` scan box and the
## precomputed table behind it, and the fact that AN ATTACK NEEDS NO VISION.

import std/math
import harness
import bc23_fixture

# --- the precomputed ceil(sqrt) table -------------------------------------
block:
  for r2 in 0 .. 34:
    checkEq("ceil(sqrt(" & $r2 & "))", CeilSqrtTable[r2],
      int(ceil(sqrt(float64(r2)))))
  for r2 in [4, 9, 13, 15, 16, 20, 34]:
    checkEq("the reachable radius " & $r2, CeilSqrtTable[r2],
      int(ceil(sqrt(float64(r2)))))
  checkEq("the table covers every reachable radius", CeilSqrtTable.len, 35)

# --- the per-type radii ---------------------------------------------------
block:
  var w = bare()
  let hq = w.robotsById[2]
  let amp = w.place(teamA, rtAmplifier, loc(15, 15))
  let car = w.place(teamA, rtCarrier, loc(15, 25))
  checkEq("a headquarters sees r2 <= 34",
    RobotSpecs[rtHeadquarters].visionRadiusSquared, 34)
  checkEq("an amplifier sees r2 <= 34",
    RobotSpecs[rtAmplifier].visionRadiusSquared, 34)
  checkEq("a carrier sees r2 <= 20", RobotSpecs[rtCarrier].visionRadiusSquared,
    20)
  checkEq("and so does a launcher",
    RobotSpecs[rtLauncher].visionRadiusSquared, 20)
  check("the amplifier sees r2 = 34", w.canSenseLocation(amp, loc(18, 18)))
  checkEq("(which really is 34)", loc(15, 15).distanceSquaredTo(loc(18, 18)),
    18)
  check("the amplifier sees a tile at r2 = 34",
    w.canSenseLocation(amp, loc(20, 18)))
  checkEq("(that one is 34)", loc(15, 15).distanceSquaredTo(loc(20, 18)), 34)
  check("but not r2 = 36", not w.canSenseLocation(amp, loc(21, 15)))
  check("a carrier sees r2 = 20", w.canSenseLocation(car, loc(19, 27)))
  checkEq("(that is 20)", loc(15, 25).distanceSquaredTo(loc(19, 27)), 20)
  check("and not r2 = 25", not w.canSenseLocation(car, loc(20, 25)))
  discard hq

# --- THE CLOUD COLLAPSE, BOTH DIRECTIONS ----------------------------------
block:
  var w = bare(clouds = @[loc(15, 15), loc(25, 25)])
  let inCloud = w.place(teamA, rtLauncher, loc(15, 15))
  let outside = w.place(teamA, rtLauncher, loc(10, 10))
  let hidden = w.place(teamB, rtCarrier, loc(25, 25))
  check("a robot IN a cloud sees only r2 <= 4",
    w.canSenseLocation(inCloud, loc(17, 15)))
  check("and nothing at r2 = 9", not w.canSenseLocation(inCloud, loc(18, 15)))
  checkEq("(which is 9)", loc(15, 15).distanceSquaredTo(loc(18, 15)), 9)
  ## Looking INTO a cloud collapses too, which is what hides `hidden`.
  let watcher = w.place(teamA, rtLauncher, loc(23, 25))
  checkEq("the watcher is at r2 = 4", watcher.loc.distanceSquaredTo(
    hidden.loc), 4)
  check("so it can just see the cloud tile",
    w.canSenseLocation(watcher, hidden.loc))
  let watcher2 = w.place(teamA, rtLauncher, loc(22, 25))
  checkEq("a second watcher is at r2 = 9",
    watcher2.loc.distanceSquaredTo(hidden.loc), 9)
  check("and CANNOT see into the cloud, even though 9 <= 20",
    not w.canSenseLocation(watcher2, hidden.loc))
  checkEq("the clear line is unaffected",
    int(w.canSenseLocation(outside, loc(13, 12))), 1)

# --- an attack needs NO vision -------------------------------------------
block:
  var w = bare(clouds = @[loc(10, 10)])
  let l = w.place(teamA, rtLauncher, loc(6, 10))
  let hidden = w.place(teamB, rtCarrier, loc(10, 10))
  checkEq("the target is at r2 = 16", l.loc.distanceSquaredTo(hidden.loc), 16)
  check("and it cannot be SEEN", not w.canSenseLocation(l, hidden.loc))
  check("but it CAN be attacked — this is how launchers fight through clouds",
    w.canAttack(l, hidden.loc))

# --- the scan order and the ceil+1 box ------------------------------------
block:
  var w = bare()
  var tiles: seq[Loc]
  for l in w.locationsWithinRadiusSquared(loc(15, 15), 4):
    tiles.add(l)
  ## x ascending outer, y ascending inner.
  var ordered = true
  for i in 1 ..< tiles.len:
    if tiles[i].x < tiles[i - 1].x: ordered = false
    elif tiles[i].x == tiles[i - 1].x and tiles[i].y <= tiles[i - 1].y:
      ordered = false
  check("the scan is x ascending outer, y ascending inner", ordered)
  checkEq("r2 <= 4 around a centre is 13 tiles", tiles.len, 13)
  checkEq("the first tile is the lowest x then the lowest y", tiles[0],
    loc(13, 15))
  var all = 0
  for l in w.locationsWithinRadiusSquared(loc(15, 15), 34): all += 1
  checkEq("r2 <= 34 is 109 tiles", all, 109)
  ## The box is clamped to the map, so a corner sees fewer.
  var corner = 0
  for l in w.locationsWithinRadiusSquared(loc(0, 0), 20): corner += 1
  checkEq("a corner sweep is clamped to the map", corner, 22)

# --- senseNearbyRobots honours the cloud collapse -------------------------
block:
  var w = bare(clouds = @[loc(20, 15)])
  let seeker = w.place(teamA, rtLauncher, loc(17, 15))
  discard w.place(teamB, rtCarrier, loc(20, 15))
  discard w.place(teamB, rtCarrier, loc(18, 15))
  var seen = 0
  for r in w.senseNearbyRobots(seeker, 20, ord(teamB)): seen += 1
  checkEq("only the one outside the cloud is sensed", seen, 1)

finish("test_bc23_sensing")
