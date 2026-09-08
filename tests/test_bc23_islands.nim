## bc23's sky islands: the truncating occupancy formula at every triple, the
## health move and the neutralisation, the healing sweep, `placeAnchor`
## legality and the override that increments NEITHER counter, the mid-turn
## conquest check, and THE ENGINE QUIRK that a STANDARD anchor placed over our
## own ACCELERATING one leaves its -0.15 boost registered for ever.

import harness
import bc23_fixture

# --- the occupancy formula at every (owner, enemy, area) triple -------------
block:
  var negatives = 0
  for area in 1 .. 20:
    for own in 0 .. area:
      for enemy in 0 .. area - own:
        let got = occupancyDiff(own, enemy, area)
        let want = (100 * (own - enemy)) div area
        checkEq("diff " & $own & "/" & $enemy & "/" & $area, got, want)
        if got < 0: negatives += 1
  check("negative diffs really occur", negatives > 0)
  ## Java integer division TRUNCATES TOWARD ZERO, which Nim's `div` matches
  ## for a negative numerator: -150 div 4 is -37, not -38.
  checkEq("truncation toward zero", occupancyDiff(0, 6, 4), -150)
  checkEq("and on a non-exact quotient", occupancyDiff(1, 4, 7), -42)
  checkEq("Nim's div agrees with Java's", (100 * (1 - 4)) div 7, -42)

# --- the health move, the cap and the neutralisation ------------------------
block:
  var w = bare(islands = @[(l: loc(10, 10), id: 1), (l: loc(11, 10), id: 1)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  c.addAnchor(anStandard)
  check("the placement is legal", w.doPlaceAnchor(c))
  checkEq("the island is ours", w.islands[0].owner, 1)
  checkEq("at FULL health", w.islands[0].health, 250)
  checkEq("the counters moved", w.stats.totalAnchorsPlaced[0], 1)
  checkEq("both of them", w.stats.currentAnchorsPlaced[0], 1)
  ## One of ours on a two-tile island: diff = (100 * (1 - 0)) / 2 = 50, and
  ## the health is already at the cap.
  w.currentRound = 5
  w.islandAdvanceTurn(0)
  checkEq("the health is capped at the total", w.islands[0].health, 250)
  ## Take our robot off and put one of theirs on.
  w.destroyRobot(c.id)
  let e = w.place(teamB, rtLauncher, loc(10, 10))
  w.islands[0].health = 60
  w.islandAdvanceTurn(0)
  checkEq("an enemy on half the island costs 50", w.islands[0].health, 10)
  w.islandAdvanceTurn(0)
  check("and at zero the island goes NEUTRAL", w.islands[0].owner == 0)
  checkEq("the anchor is gone", ord(w.islands[0].anchor), ord(anNone))
  checkEq("the current counter decremented", w.stats.currentAnchorsPlaced[0],
    0)
  checkEq("but the TOTAL ever placed did not",
    w.stats.totalAnchorsPlaced[0], 1)
  checkEq("and the loss is recorded", w.stats.islandsLost[0], 1)
  discard e

# --- healing every round, r2 <= 4 of ANY island tile ------------------------
block:
  var w = bare(islands = @[(l: loc(10, 10), id: 1)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  c.addAnchor(anStandard)
  discard w.doPlaceAnchor(c)
  let wounded = w.place(teamA, rtLauncher, loc(12, 10))
  wounded.health = 100
  let far = w.place(teamA, rtLauncher, loc(13, 10))
  far.health = 100
  let enemy = w.place(teamB, rtLauncher, loc(10, 12))
  enemy.health = 100
  checkEq("the wounded ally is at r2 = 4", wounded.loc.distanceSquaredTo(
    loc(10, 10)), 4)
  checkEq("the far ally is at r2 = 9", far.loc.distanceSquaredTo(
    loc(10, 10)), 9)
  w.currentRound = 7
  w.islandAdvanceTurn(0)
  checkEq("a standard anchor heals 4 inside r2 <= 4", wounded.health, 104)
  checkEq("and nothing outside it", far.health, 100)
  checkEq("and never the enemy", enemy.health, 100)
  checkEq("the heal is recorded", w.stats.anchorHeals[0], 4)

block:
  ## A JUST-NEUTRALISED island heals nobody: `getLocsAffected()` is empty once
  ## the anchor is gone, which is why the engine's own `anchorPlanted`
  ## dereference cannot fault.
  var w = bare(islands = @[(l: loc(10, 10), id: 1)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  c.addAnchor(anStandard)
  discard w.doPlaceAnchor(c)
  w.destroyRobot(c.id)
  let e = w.place(teamB, rtLauncher, loc(10, 10))
  let ally = w.place(teamA, rtLauncher, loc(11, 10))
  ally.health = 100
  w.islands[0].health = 50
  w.currentRound = 1
  w.islandAdvanceTurn(0)
  checkEq("the island went neutral", w.islands[0].owner, 0)
  checkEq("and healed nobody on the way out", ally.health, 100)
  discard e

# --- placeAnchor legality ---------------------------------------------------
block:
  var w = bare(islands = @[(l: loc(10, 10), id: 1)])
  let mine = w.place(teamA, rtCarrier, loc(10, 10))
  mine.addAnchor(anStandard)
  check("a NEUTRAL island accepts an anchor",
    w.islands[0].canPlaceAnchor(teamA))
  discard w.doPlaceAnchor(mine)
  check("OUR OWN island accepts another", w.islands[0].canPlaceAnchor(teamA))
  check("the ENEMY's does not", not w.islands[0].canPlaceAnchor(teamB))
  ## An OVERRIDE of our own anchor restores full health and increments
  ## NEITHER counter.
  w.islands[0].health = 30
  mine.addAnchor(anStandard)
  mine.actionCooldown = 0
  check("the override is legal", w.doPlaceAnchor(mine))
  checkEq("the health is restored in full", w.islands[0].health, 250)
  checkEq("the total counter did NOT move", w.stats.totalAnchorsPlaced[0], 1)
  checkEq("and neither did the current one",
    w.stats.currentAnchorsPlaced[0], 1)
  checkEq("nor islands_captured", w.stats.islandsCaptured[0], 1)

# --- the mid-turn conquest check ------------------------------------------
block:
  ## Four islands, so `islandsToWin` is 3. The third placement fires CONQUEST
  ## the instant it happens, mid-turn, and the round is not stopped by it.
  var w = bare(islands = @[(l: loc(5, 5), id: 1), (l: loc(6, 6), id: 2),
                           (l: loc(7, 7), id: 3), (l: loc(8, 8), id: 4)])
  checkEq("four islands need three", islandsToWin(4), 3)
  for i, at in [loc(5, 5), loc(6, 6), loc(7, 7)]:
    let c = w.place(teamA, rtCarrier, at)
    c.addAnchor(anStandard)
    check("placement " & $i, w.doPlaceAnchor(c))
    if i < 2:
      check("no winner yet at " & $i, not w.hasWinner)
  check("the third placement wins", w.hasWinner)
  checkEq("by conquest", ord(w.domination), ord(dfConquest))
  check("and `running` is still true — the round finishes", w.running)

# --- the STANDARD-over-ACCELERATING boost quirk ----------------------------
block:
  ## `Island.advanceTurn`'s removal path only fires for an anchor that is
  ## STILL `ACCELERATING`, so replacing our own accelerating anchor with a
  ## standard one leaves the -0.15 registered on those tiles FOR EVER.
  ## Engine behaviour, ported literally (docs/RULES-BC23.md, Divergences 15).
  var w = bare(islands = @[(l: loc(10, 10), id: 1)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  c.addAnchor(anAccelerating)
  check("the accelerating placement is legal", w.doPlaceAnchor(c))
  checkEq("its boost is registered",
    w.cooldownMultiplier(loc(10, 10), teamA), 85)
  c.addAnchor(anStandard)
  c.actionCooldown = 0
  check("the override with a STANDARD anchor is legal", w.doPlaceAnchor(c))
  checkEq("the anchor is now standard", ord(w.islands[0].anchor),
    ord(anStandard))
  checkEq("AND THE -0.15 IS STILL THERE — the engine's own quirk",
    w.cooldownMultiplier(loc(10, 10), teamA), 85)
  ## Grinding the standard anchor to zero does NOT remove it either, because
  ## the removal path tests the CURRENT anchor type.
  w.destroyRobot(c.id)
  discard w.place(teamB, rtLauncher, loc(10, 10))
  w.islands[0].health = 1
  w.currentRound = 1
  w.islandAdvanceTurn(0)
  checkEq("the island is neutral", w.islands[0].owner, 0)
  checkEq("and the boost is STILL registered",
    w.cooldownMultiplier(loc(10, 10), teamA), 85)

# --- minDistTo and the pip readout ---------------------------------------
block:
  var w = bare(islands = @[(l: loc(10, 10), id: 1), (l: loc(20, 20), id: 1)])
  checkEq("minDistTo is the SQUARED distance to the nearest tile",
    w.islands[0].minDistTo(loc(12, 10)), 4)
  checkEq("across every tile of the island",
    w.islands[0].minDistTo(loc(21, 20)), 1)
  checkEq("a neutral island has no pips", w.islands[0].healthPips(), 0)

finish("test_bc23_islands")
