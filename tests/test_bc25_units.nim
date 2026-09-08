## bc25 units: soldier paint/attack legality and effect at r2 <= 9, the
## splasher's TWO radii in engine scan order, the mopper's "bare, not ours"
## rule and its six swing offsets, and `addPaint` / `addHealth` clamping.

import harness
import bc25_fixture

# --- soldier ---------------------------------------------------------------
block:
  var w = bare(walls = @[loc(13, 10)])
  let r = w.place(teamA, utSoldier, loc(10, 10))
  check("a wall is never a legal soldier target",
    not w.canAttackSoldier(r, loc(13, 10)))
  check("r2 = 9 is in range", w.canAttackSoldier(r, loc(13, 11)) or
    loc(10, 10).distanceSquaredTo(loc(13, 11)) > 9)
  check("r2 = 10 is out", not w.canAttackSoldier(r, loc(11, 13)))
  r.paint = 4
  check("and four paint is not enough", not w.canAttackSoldier(r, loc(11, 10)))

block:
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  w.setPaint(loc(11, 10), primaryPaint(teamB))
  w.doAttackRobot(r, loc(11, 10))
  checkEq("a soldier can NEVER paint over enemy paint",
    w.getPaint(loc(11, 10)), primaryPaint(teamB))
  checkEq("but the 5 paint and the cooldown were still spent", r.paint,
    UnitSpecs[utSoldier].paintCapacity - 5)

block:
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  let victim = w.place(teamB, utSoldier, loc(11, 10))
  let hp = victim.health
  w.doAttackRobot(r, loc(11, 10))
  checkEq("a soldier never damages a ROBOT", victim.health, hp)
  checkEq("and the tile UNDER it is painted instead, because the engine's " &
    "tower branch is the only one a robot skips",
    w.getPaint(loc(11, 10)), primaryPaint(teamA))

block:
  var w = bare(ruins = @[loc(12, 10)])
  let r = w.place(teamA, utSoldier, loc(10, 10))
  let tower = w.place(teamB, utLevelOneMoneyTower, loc(12, 10))
  let hp = tower.health
  w.doAttackRobot(r, loc(12, 10))
  checkEq("a soldier hits an enemy tower for exactly 50",
    tower.health, hp - UnitSpecs[utSoldier].attackStrength)

# --- splasher --------------------------------------------------------------
block:
  var w = bare()
  let r = w.place(teamA, utSplasher, loc(10, 10))
  ## Enemy paint at r2 = 2 (inside the overpaint window) and at r2 = 4
  ## (inside the blast but outside the window).
  w.setPaint(loc(11, 11), primaryPaint(teamB))    ## r2 = 2 from (10,10)
  w.setPaint(loc(12, 10), primaryPaint(teamB))    ## r2 = 4
  w.setPaint(loc(9, 9), PaintNone)
  w.doAttackRobot(r, loc(10, 10))
  checkEq("enemy paint INSIDE r2 <= 2 is overpainted",
    w.getPaint(loc(11, 11)), primaryPaint(teamA))
  checkEq("enemy paint outside it is NOT",
    w.getPaint(loc(12, 10)), primaryPaint(teamB))
  checkEq("a bare tile inside the blast IS painted",
    w.getPaint(loc(9, 9)), primaryPaint(teamA))
  checkEq("and 50 paint was spent", r.paint,
    UnitSpecs[utSplasher].paintCapacity - 50)

block:
  var w = bare(ruins = @[loc(11, 10), loc(9, 10)])
  let r = w.place(teamA, utSplasher, loc(10, 12))
  let t1 = w.place(teamB, utLevelOneMoneyTower, loc(11, 10))
  let t2 = w.place(teamB, utLevelOneMoneyTower, loc(9, 10))
  let hp1 = t1.health
  let hp2 = t2.health
  w.doAttackRobot(r, loc(10, 11))
  checkEq("one splash damages the first tower for 100",
    t1.health, hp1 - UnitSpecs[utSplasher].aoeAttackStrength)
  checkEq("and the second one too", t2.health,
    hp2 - UnitSpecs[utSplasher].aoeAttackStrength)

block:
  ## ENGINE SCAN ORDER: x ascending outer, y ascending inner.
  var w = bare()
  var seen: seq[Loc]
  for l in w.locationsWithinRadiusSquared(loc(10, 10), 4):
    seen.add(l)
  checkEq("the first tile of an r2 <= 4 sweep is the lowest x then lowest y",
    seen[0], loc(8, 10))
  var sorted = true
  for i in 1 ..< seen.len:
    if seen[i - 1].x > seen[i].x or
        (seen[i - 1].x == seen[i].x and seen[i - 1].y > seen[i].y):
      sorted = false
  check("and the whole sweep is x-then-y ascending", sorted)

# --- mopper ----------------------------------------------------------------
block:
  var w = bare(ruins = @[loc(11, 10)], walls = @[loc(9, 10)])
  let r = w.place(teamA, utMopper, loc(10, 10))
  check("a mopper may not attack a ruin",
    not w.canAttackMopper(r, loc(11, 10)))
  check("nor a wall", not w.canAttackMopper(r, loc(9, 10)))

block:
  var w = bare()
  let r = w.place(teamA, utMopper, loc(10, 10))
  let victim = w.place(teamB, utSoldier, loc(11, 10))
  w.setPaint(loc(11, 10), primaryPaint(teamB))
  r.paint = 50
  victim.paint = 100
  w.doAttackRobot(r, loc(11, 10))
  checkEq("the enemy robot loses 10 paint", victim.paint, 90)
  checkEq("the mopper gains 5", r.paint, 55)
  checkEq("and the tile becomes BARE, not ours",
    w.getPaint(loc(11, 10)), PaintNone)

block:
  var w = bare(ruins = @[loc(11, 10)])
  let r = w.place(teamA, utMopper, loc(10, 10))
  let tower = w.place(teamB, utLevelOneMoneyTower, loc(11, 10))
  let p = tower.paint
  ## The tile is a ruin, so the mop is refused outright.
  w.doAttackRobot(r, loc(11, 10))
  checkEq("a mopper cannot strip a TOWER", tower.paint, p)

block:
  ## The six offsets, all four cardinals, with off-map skipping and towers
  ## immune.
  for i, d in CardinalDirs:
    var w = bare()
    let r = w.place(teamA, utMopper, loc(15, 15))
    var victims: seq[Robot]
    for k in 0 .. 5:
      let l = loc(15 + MopSwingDx[i][k], 15 + MopSwingDy[i][k])
      victims.add(w.place(teamB, utSoldier, l))
    for v in victims: v.paint = 100
    w.doMopSwing(r, d)
    var stripped = 0
    for v in victims:
      if v.paint == 100 - MopperSwingPaintDepletion: stripped += 1
    checkEq("all six offsets of " & $d & " were hit", stripped, 6)

block:
  var w = bare(ruins = @[loc(16, 15)])
  let r = w.place(teamA, utMopper, loc(15, 15))
  let tower = w.place(teamB, utLevelOneMoneyTower, loc(16, 15))
  let p = tower.paint
  w.doMopSwing(r, dEast)
  checkEq("a mop swing never touches a tower", tower.paint, p)

block:
  var w = bare()
  let r = w.place(teamA, utMopper, loc(0, 0))
  check("a swing off the edge of the map is refused",
    not w.canMopSwing(r, dSouth))
  check("but a legal one is allowed", w.canMopSwing(r, dNorth))

# --- clamping --------------------------------------------------------------
block:
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.addPaint(10_000)
  checkEq("addPaint caps at capacity", r.paint,
    UnitSpecs[utSoldier].paintCapacity)
  r.addPaint(-10_000)
  checkEq("and floors at zero", r.paint, 0)
  w.addHealth(r, 10_000)
  checkEq("addHealth caps at the type's own maximum", r.health,
    UnitSpecs[utSoldier].health)
  w.addHealth(r, -10_000)
  check("and a unit at or below zero is destroyed immediately", not r.alive)
  check("and is gone from the world", not w.existsRobot(r.id))

finish("test_bc25_units")
