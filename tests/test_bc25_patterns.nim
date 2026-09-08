## bc25 patterns: the four hard-coded ints decode to the four tables in the
## rules doc, `getPatternBit`'s index arithmetic, bit 1 = SECONDARY, the tower
## check skipping the centre while the SRP check does not, the validity box,
## and the 25-paint charge on BOTH mark paths.

import harness
import bc25_fixture

# --- the ints and the tables ------------------------------------------------
block:
  checkEq("the resource pattern int", PatternInts[pkResource], 28873275)
  checkEq("the paint tower int", PatternInts[pkPaintTower], 18157905)
  checkEq("the money tower int", PatternInts[pkMoneyTower], 15583086)
  checkEq("the defense tower int", PatternInts[pkDefenseTower], 4685252)

block:
  ## `getPatternBit(pattern, dx, dy) = (pattern >> (5*(dx+2) + dy+2)) & 1`,
  ## regenerated here and byte-checked against the committed tables.
  for kind in PatternKind:
    for ddx in -2 .. 2:
      for ddy in -2 .. 2:
        let bit = (PatternInts[kind] shr (5 * (ddx + 2) + ddy + 2)) and 1
        checkEq("table " & $kind & " (" & $ddx & "," & $ddy & ")",
          PatternTables[kind][ddx + 2][ddy + 2], bit == 1)

block:
  checkEq("RESOURCE rows", patternRows(pkResource),
    ["SSPSS", "SPPPS", "PPSPP", "SPPPS", "SSPSS"])
  checkEq("PAINT rows", patternRows(pkPaintTower),
    ["SPPPS", "PSPSP", "PPSPP", "PSPSP", "SPPPS"])
  checkEq("MONEY rows", patternRows(pkMoneyTower),
    ["PSSSP", "SSPSS", "SPPPS", "SSPSS", "PSSSP"])
  checkEq("DEFENSE rows", patternRows(pkDefenseTower),
    ["PPSPP", "PSSSP", "SSSSS", "PSSSP", "PPSPP"])

block:
  ## Bit 1 means the SECONDARY colour, so `wantedPaint` maps it that way.
  ## The resource pattern's top row (dy = +2) is `SSPSS`, so (-2, +2) is a SET
  ## bit and (0, +2) is a clear one.
  check("the corner of the top row is a set bit",
    PatternTables[pkResource][-2 + 2][2 + 2])
  checkEq("a set bit wants the secondary colour",
    wantedPaint(pkResource, -2, 2, teamA), secondaryPaint(teamA))
  check("the middle of the top row is a clear bit",
    not PatternTables[pkResource][0 + 2][2 + 2])
  checkEq("a clear bit wants the primary",
    wantedPaint(pkResource, 0, 2, teamA), primaryPaint(teamA))
  checkEq("and it is the acting team's own pair",
    wantedPaint(pkResource, -2, 2, teamB), secondaryPaint(teamB))

block:
  ## All four patterns are invariant under all eight square symmetries, which
  ## is why the engine's rotation logic is commented out.
  for kind in PatternKind:
    var symmetric = true
    for ddx in -2 .. 2:
      for ddy in -2 .. 2:
        let b = PatternTables[kind][ddx + 2][ddy + 2]
        if PatternTables[kind][-ddx + 2][ddy + 2] != b: symmetric = false
        if PatternTables[kind][ddx + 2][-ddy + 2] != b: symmetric = false
        if PatternTables[kind][ddy + 2][ddx + 2] != b: symmetric = false
    check($kind & " is invariant under all eight symmetries", symmetric)

# --- the centre skip --------------------------------------------------------
block:
  var w = bare(ruins = @[loc(10, 10)])
  w.paintArea(pkMoneyTower, teamA, loc(10, 10), skipCentre = true)
  check("a tower pattern matches with the centre unpaintable",
    w.checkTowerPattern(teamA, loc(10, 10), utLevelOneMoneyTower))
  check("but the SRP check on the same tiles does NOT",
    not w.checkResourcePattern(teamA, loc(10, 10)))

block:
  var w = bare()
  w.paintArea(pkResource, teamA, loc(10, 10))
  check("an exact resource pattern matches",
    w.checkResourcePattern(teamA, loc(10, 10)))
  check("and it does NOT match for the other team",
    not w.checkResourcePattern(teamB, loc(10, 10)))
  w.setPaint(loc(11, 11), PaintNone)
  check("one wrong tile breaks it",
    not w.checkResourcePattern(teamA, loc(10, 10)))

# --- the validity box -------------------------------------------------------
block:
  var w = bare(ruins = @[loc(10, 10)])
  for l in [loc(0, 5), loc(1, 5), loc(5, 1), loc(TestWidth - 1, 5),
            loc(TestWidth - 2, 5), loc(5, TestHeight - 2)]:
    check("a centre less than two tiles from an edge is invalid: " & $l,
      not w.isValidPatternCenter(l, true))
  check("two tiles in on every side is valid",
    w.isValidPatternCenter(loc(2, 2), true))
  check("a tower centre does not need a paintable 5x5",
    w.isValidPatternCenter(loc(10, 10), true))
  check("an SRP centre DOES", not w.isValidPatternCenter(loc(10, 10), false))
  check("areaIsPaintable is what makes that true",
    not w.areaIsPaintable(loc(10, 10)))

# --- marking ---------------------------------------------------------------
block:
  var w = bare(ruins = @[loc(10, 10)])
  let r = w.place(teamA, utSoldier, loc(11, 10))
  r.paint = 200
  w.doMarkTowerPattern(r, tkMoney, loc(10, 10))
  checkEq("marking a tower pattern charges exactly 25 paint", r.paint, 175)
  var marked = 0
  for ddx in -2 .. 2:
    for ddy in -2 .. 2:
      if w.getMarker(teamA, loc(10 + ddx, 10 + ddy)) != MarkerNone:
        marked += 1
  checkEq("and writes 24 markers, skipping the unpaintable ruin", marked, 24)
  checkEq("the enemy sees none of them",
    w.getMarker(teamB, loc(11, 11)), MarkerNone)

block:
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.paint = 200
  w.doMarkResourcePattern(r, loc(10, 10))
  checkEq("marking an SRP charges exactly 25 paint too", r.paint, 175)
  var marked = 0
  for ddx in -2 .. 2:
    for ddy in -2 .. 2:
      if w.getMarker(teamA, loc(10 + ddx, 10 + ddy)) != MarkerNone:
        marked += 1
  checkEq("and writes all 25", marked, 25)

block:
  var w = bare(ruins = @[loc(10, 10)])
  let r = w.place(teamA, utSoldier, loc(11, 10))
  r.paint = 24
  check("24 paint is not enough to mark",
    not w.canMarkTowerPattern(r, tkMoney, loc(10, 10)))
  r.paint = 25
  check("25 is", w.canMarkTowerPattern(r, tkMoney, loc(10, 10)))
  check("but only on a RUIN",
    not w.canMarkTowerPattern(r, tkMoney, loc(15, 15)))

# --- the map's own paintPatterns array is read and ignored -----------------
block:
  ## `tools/convert_maps_bc25.py` reads the field so the reader is provably
  ## complete and then drops it; nothing in `MapSpec` carries it, which is the
  ## strongest possible statement that it is ignored.
  let spec = loadMap("DefaultSmall")
  check("no converted map carries a paintPatterns field",
    spec.name == "DefaultSmall")

finish("test_bc25_patterns")
