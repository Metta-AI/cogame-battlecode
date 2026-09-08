## bc25 paint: the 0..4 colour alphabet, `setPaint`'s LIVE count, its no-op on
## an unpaintable tile, and the mid-action 70 % win check firing the instant
## the count crosses `ceil(0.70 * areaWithoutWalls)` and not one tile earlier.

import harness
import bc25_fixture

# --- the alphabet ----------------------------------------------------------
block:
  checkEq("bare is 0", PaintNone, 0)
  checkEq("A primary is 1", primaryPaint(teamA), 1)
  checkEq("A secondary is 2", secondaryPaint(teamA), 2)
  checkEq("B primary is 3", primaryPaint(teamB), 3)
  checkEq("B secondary is 4", secondaryPaint(teamB), 4)
  check("0 belongs to neither team", not hasPaintTeam(0))
  check("5 belongs to neither team", not hasPaintTeam(5))
  for p in [1, 2]:
    checkEq("teamFromPaint " & $p, teamFromPaint(p), teamA)
  for p in [3, 4]:
    checkEq("teamFromPaint " & $p, teamFromPaint(p), teamB)
  check("1 and 3 are primary", isPrimaryPaint(1) and isPrimaryPaint(3))
  check("2 and 4 are not", not isPrimaryPaint(2) and not isPrimaryPaint(4))

# --- setPaint is a NO-OP on walls and ruins --------------------------------
block:
  var w = bare(ruins = @[loc(10, 10)], walls = @[loc(12, 12)])
  let before = w.stats.livePainted
  w.setPaint(loc(12, 12), primaryPaint(teamA))
  checkEq("painting a wall does nothing to the tile",
    w.getPaint(loc(12, 12)), PaintNone)
  w.setPaint(loc(10, 10), primaryPaint(teamA))
  checkEq("painting a ruin does nothing to the tile",
    w.getPaint(loc(10, 10)), PaintNone)
  checkEq("and nothing to the live count", w.stats.livePainted, before)
  check("because paintable IS passable in 2025",
    not w.isPaintable(loc(10, 10)) and not w.isPassable(loc(10, 10)))

# --- the live count moves, it does not accumulate --------------------------
block:
  var w = bare()
  let base = w.stats.livePainted
  w.setPaint(loc(5, 5), primaryPaint(teamA))
  checkEq("A gains one", w.stats.livePainted[0], base[0] + 1)
  w.setPaint(loc(5, 5), secondaryPaint(teamA))
  checkEq("re-painting our own tile our other colour is net zero",
    w.stats.livePainted[0], base[0] + 1)
  w.setPaint(loc(5, 5), primaryPaint(teamB))
  checkEq("painting over the enemy takes one from them",
    w.stats.livePainted[0], base[0])
  checkEq("and gives it to us", w.stats.livePainted[1], base[1] + 1)
  w.setPaint(loc(5, 5), PaintNone)
  checkEq("mopping it bare takes one from them",
    w.stats.livePainted[1], base[1])
  checkEq("and gives it to nobody", w.stats.livePainted[0], base[0])

# --- the 70 % denominator, and the exact threshold -------------------------
block:
  ## The DefaultSmall arithmetic the note pins: 400 tiles, 28 walls, so the
  ## denominator is 372 and the threshold is 261 out of the 360 tiles that can
  ## actually hold paint -- 72.5 % of real paintable area.
  let spec = loadMap("DefaultSmall")
  let w = newWorld(spec, 2000)
  checkEq("areaWithoutWalls counts ruins", w.areaWithoutWalls, 372)
  checkEq("trulyPaintable does not", w.trulyPaintable, 360)
  checkEq("so the threshold is 261 tiles", tilesToWin(w.areaWithoutWalls), 261)
  check("which is more than 70 % of the paintable area",
    261 * 100 div 360 > 70)

block:
  ## The win fires the instant the count crosses, and NOT ONE TILE EARLIER.
  var w = bare()
  let target = tilesToWin(w.areaWithoutWalls)
  var painted = w.stats.livePainted[0]
  var x = 0
  var y = 0
  while painted < target - 1:
    if not w.hasTower(loc(x, y)) and w.isPaintable(loc(x, y)) and
        w.getPaint(loc(x, y)) == PaintNone:
      w.setPaint(loc(x, y), primaryPaint(teamA))
      painted += 1
    x += 1
    if x >= w.width:
      x = 0
      y += 1
    if y >= w.height: break
  checkEq("one tile short of the threshold", w.stats.livePainted[0],
    target - 1)
  check("and NO winner is set", not w.hasWinner)
  ## The next tile crosses it.
  block last:
    for yy in 0 ..< w.height:
      for xx in 0 ..< w.width:
        let l = loc(xx, yy)
        if w.isPaintable(l) and w.getPaint(l) == PaintNone:
          w.setPaint(l, primaryPaint(teamA))
          break last
  checkEq("the crossing tile takes us to the threshold",
    w.stats.livePainted[0], target)
  check("and the winner is set MID-ACTION", w.hasWinner)
  checkEq("with PAINT_ENOUGH_AREA", w.domination, dfPaintEnoughArea)
  check("but `running` is untouched until the end of the round", w.running)

finish("test_bc25_paint")
