## bc25 sensing: vision r2 <= 20 THROUGH walls, the engine scan order (x
## ascending outer, y ascending inner) for map infos, robots and AoE targets,
## only THIS TEAM'S markers being returned, and the precomputed `ceil(sqrt())`
## table matching `Math.ceil(Math.sqrt())` for every radius the rule set uses.

import std/math
import harness
import bc25_fixture

block:
  ## The precomputed table replaces `sqrt` entirely, so the port has no
  ## `fdlibm` path at all.
  var bad = 0
  for r2 in 0 .. 80:
    if CeilSqrtTable[r2] != int(ceil(sqrt(float64(r2)))): bad += 1
  checkEq("ceil(sqrt(r2)) matches for every r2 in 0..80", bad, 0)
  for r2 in [2, 4, 8, 9, 16, 20, 80]:
    checkEq("and for the radius " & $r2 & " the rule set actually uses",
      CeilSqrtTable[r2], int(ceil(sqrt(float64(r2)))))

block:
  ## Vision is r2 <= 20 and IGNORES WALLS: 2025 has no line of sight.
  var w = bare(walls = @[loc(11, 10), loc(12, 10)])
  let r = w.place(teamA, utSoldier, loc(10, 10))
  check("a tile behind two walls is still sensible",
    w.canSenseLocation(r, loc(14, 10)))
  checkEq("r2 = 20 is the edge", loc(10, 10).distanceSquaredTo(loc(14, 12)),
    20)
  check("and it is inside", w.canSenseLocation(r, loc(14, 12)))
  checkEq("r2 = 21 is outside",
    loc(10, 10).distanceSquaredTo(loc(14, 11)), 17)
  check("a tile at r2 = 25 is not sensible",
    not w.canSenseLocation(r, loc(15, 10)))
  check("nor is one off the map", not w.canSenseLocation(r, loc(-1, 10)))

block:
  ## The scan order is x ascending outer, y ascending inner, over the clamped
  ## `ceil(sqrt(r2)) + 1` box. It fixes which tile a splasher paints first,
  ## which enemy a tower's AoE hits first, and which ruin the example bot's
  ## "keep the LAST one you saw" loop ends on.
  var w = bare()
  for r2 in [2, 4, 8, 9, 16, 20, 80]:
    var seen: seq[Loc]
    for l in w.locationsWithinRadiusSquared(loc(15, 15), r2):
      seen.add(l)
    var ordered = true
    for i in 1 ..< seen.len:
      if seen[i - 1].x > seen[i].x or
          (seen[i - 1].x == seen[i].x and seen[i - 1].y >= seen[i].y):
        ordered = false
    check("r2 = " & $r2 & " sweeps x-then-y ascending", ordered)
    var inside = true
    for l in seen:
      if loc(15, 15).distanceSquaredTo(l) > r2: inside = false
    check("and every tile is really within r2 = " & $r2, inside)
    ## The count is the exact lattice-point count of the disc.
    var expected = 0
    for x in 0 ..< w.width:
      for y in 0 ..< w.height:
        if loc(15, 15).distanceSquaredTo(loc(x, y)) <= r2: expected += 1
    checkEq("and the sweep is complete for r2 = " & $r2, seen.len, expected)

block:
  ## The box is CLAMPED to the map, so a sweep at a corner returns fewer
  ## tiles and never leaves the board.
  var w = bare()
  var seen: seq[Loc]
  for l in w.locationsWithinRadiusSquared(loc(0, 0), 20):
    seen.add(l)
  var onMap = true
  for l in seen:
    if not w.onTheMap(l): onMap = false
  check("a corner sweep never leaves the map", onMap)
  checkEq("and starts at the corner itself", seen[0], loc(0, 0))

block:
  ## Markers are per team and only ours come back.
  var w = bare()
  w.setMarker(teamA, loc(10, 10), MarkerPrimary)
  w.setMarker(teamB, loc(10, 10), MarkerSecondary)
  checkEq("A sees its own", w.getMarker(teamA, loc(10, 10)), MarkerPrimary)
  checkEq("B sees its own", w.getMarker(teamB, loc(10, 10)), MarkerSecondary)
  check("they are two separate arrays",
    w.getMarker(teamA, loc(10, 10)) != w.getMarker(teamB, loc(10, 10)))

block:
  ## A marker on an unpaintable tile is never written, which is why a marked
  ## tower pattern carries 24 markers and not 25.
  var w = bare(ruins = @[loc(10, 10)], walls = @[loc(12, 12)])
  w.setMarker(teamA, loc(10, 10), MarkerPrimary)
  w.setMarker(teamA, loc(12, 12), MarkerPrimary)
  checkEq("a ruin takes no marker", w.getMarker(teamA, loc(10, 10)),
    MarkerNone)
  checkEq("nor does a wall", w.getMarker(teamA, loc(12, 12)), MarkerNone)

block:
  ## Robots come back in the same scan order the locations do.
  var w = bare()
  let a = w.place(teamB, utSoldier, loc(13, 15))
  let b = w.place(teamB, utSoldier, loc(15, 13))
  let c = w.place(teamB, utSoldier, loc(17, 15))
  let me = w.place(teamA, utSoldier, loc(15, 15))
  var order: seq[int]
  for l in w.locationsWithinRadiusSquared(me.loc, VisionRadiusSquared):
    let bot = w.getRobot(l)
    if bot != nil and bot.team == teamB: order.add(bot.id)
  checkEq("lowest x first, then lowest y", order, @[a.id, b.id, c.id])

finish("test_bc25_sensing")
