## §Tests item 14 -- the four-rung end ladder, and the two ways a game can
## end early.
##
## **There is no coin flip and no RNG anywhere on any end path.** The 2017
## engine ends a game in exactly three ways: every robot on one side
## destroyed, a thousand victory points bought, or round 2 999 with the
## four-rung tiebreak. The four rungs are, in order: more victory points,
## more bullet trees, more BULLET WORTH (in which a live archon counts
## MINUS ONE), and the highest robot id of any type.
##
## Two engine facts the spec gets wrong and this shard pins:
##
##   * rung 2 counts a 10-HP sapling as much as a mature tree, because
##     `getTreeCount` is a plain counter with no notion of "active";
##   * `setWinner` has NO GUARD, so when both conditions fire in the same
##     round the LATER call overwrites the earlier one.

import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom, units, world, trees, actions,
                              rules, maps]

proc empty17(rounds = gameDefaultRounds): (World, proc (dx, dy: float32): Loc) =
  var w = newWorld(loadMap("Alone"), rounds)
  let o = w.rect.origin
  (w, proc (dx, dy: float32): Loc = loc(o.x + dx, o.y + dy))

# --- the rung names ----------------------------------------------------------
block:
  checkEq("the ladder has four rungs plus destruction and victory points",
    @(world.Bc17RungNames), @["-", "victory_points_reached", "all_robots_destroyed",
                      "more_victory_points", "more_bullet_trees",
                      "more_bullet_worth", "highest_id"])
  checkEq("and each carries the engine's own DominationFactor beside it",
    DominationNames.len, world.Bc17RungNames.len)
  checkEq("RungNone is the zero", RungNone, 0)

# --- victory_points_reached fires the instant it crosses --------------------
block:
  let (w, at) = empty17()
  let a = w.spawnRobot(rtArchon, at(50, 50), tA)
  w.currentRound = 1
  w.bulletSupply[ord(tA)] = 1000000'f32
  check("nobody has won yet", not w.hasWinner)
  discard w.donate(a, 100000'f32)
  check("the donation crossed a thousand points",
    w.victoryPoints[ord(tA)] >= victoryPointsToWin)
  check("and the winner was set INSIDE donate", w.hasWinner)
  checkEq("by the victory-point rung", w.domination, RungVictoryPoints)
  checkEq("the reason is victory_points_reached", w.endReasonFor(),
    "victory_points_reached")
  ## The round still finishes: `running` is only cleared at
  ## `processEndOfRound`.
  check("and the world is still running until the round ends", w.running)

# --- 999 points is not a win -------------------------------------------------
block:
  let (w, at) = empty17()
  w.victoryPoints[ord(tA)] = 999
  w.setWinnerIfVictoryPoints()
  check("999 points is not a win", not w.hasWinner)
  w.victoryPoints[ord(tA)] = 1000
  w.setWinnerIfVictoryPoints()
  check("1000 is -- the test is >=", w.hasWinner)
  checkEq("for team A", w.winner, tA)

# --- all_robots_destroyed, with forty trees standing ------------------------
block:
  let (w, at) = empty17()
  let a = w.spawnRobot(rtArchon, at(20, 20), tA)
  let b = w.spawnRobot(rtArchon, at(80, 80), tB)
  for i in 0 ..< 40:
    discard w.spawnTree(tB, bulletTreeRadius,
                        at(float32(30 + (i mod 10) * 4),
                           float32(40 + (i div 10) * 4)), 0, -1)
  ## `Alone` gives each side an archon of its own; clear team A down to one.
  var doomed: seq[int]
  for id, r in w.robots:
    if r.team == tA and r.id != a.id: doomed.add(id)
  for id in doomed: w.destroyRobot(id)
  check("team A has exactly one robot left", w.robotsAlive(tA) == 1)
  check("and nobody has won", not w.hasWinner)
  w.destroyRobot(a.id)
  checkEq("its death ends the game", w.domination, RungDestroyed)
  checkEq("the reason is all_robots_destroyed", w.endReasonFor(),
    "all_robots_destroyed")
  checkEq("for team B", w.winner, tB)
  checkEq("with FORTY trees still standing -- trees are not robots",
    w.treesAlive(tB), 40)

# --- the double fire: the later setWinner overwrites ------------------------
block:
  ## `setWinner` has no guard. Reproduced literally, because it is exactly
  ## what happens when both sides' conditions fire in one round.
  let (w, at) = empty17()
  w.setWinner(tA, RungDestroyed)
  checkEq("the first call sets A", w.winner, tA)
  checkEq("with its rung", w.domination, RungDestroyed)
  w.setWinner(tB, RungVictoryPoints)
  checkEq("the LATER call overwrites it", w.winner, tB)
  checkEq("rung and all", w.domination, RungVictoryPoints)

# --- the four rungs at 2999, one vector each --------------------------------
block:
  ## Rung 1: more victory points.
  let (w, at) = empty17(30)
  w.victoryPoints[ord(tA)] = 5
  w.victoryPoints[ord(tB)] = 4
  w.currentRound = 29
  w.processEndOfRound()
  checkEq("rung 1 is more_victory_points", w.endReasonFor(),
    "more_victory_points")
  checkEq("won by A", w.winner, tA)

block:
  ## Rung 2: equal points, more bullet trees -- and a SAPLING counts.
  let (w, at) = empty17(30)
  let sapling = w.spawnTree(tB, bulletTreeRadius, at(40, 40), 0, -1)
  checkEq("the sapling is at 10 HP of 50", bits(sapling.health), bits(10'f32))
  w.currentRound = 29
  w.processEndOfRound()
  checkEq("rung 2 is more_bullet_trees", w.endReasonFor(),
    "more_bullet_trees")
  checkEq("won by B on ONE ten-HP sapling", w.winner, tB)
  checkEq("because getTreeCount has no notion of active",
    w.treesAlive(tB), 1)

block:
  ## Rung 3: equal points and trees, more bullet worth -- and each surviving
  ## ARCHON SUBTRACTS one.
  let (w, at) = empty17(30)
  w.bulletSupply[ord(tA)] = 100'f32
  w.bulletSupply[ord(tB)] = 100'f32
  ## Give B a gardener: +100 of worth.
  discard w.spawnRobot(rtGardener, at(70, 70), tB)
  w.currentRound = 29
  w.processEndOfRound()
  checkEq("rung 3 is more_bullet_worth", w.endReasonFor(),
    "more_bullet_worth")
  checkEq("won by B", w.winner, tB)

block:
  ## The archon's minus one, isolated: two sides with identical supplies and
  ## trees, one with an EXTRA archon, loses rung 3.
  let (w, at) = empty17(30)
  w.bulletSupply[ord(tA)] = 100'f32
  w.bulletSupply[ord(tB)] = 100'f32
  discard w.spawnRobot(rtArchon, at(30, 30), tA)
  w.currentRound = 29
  w.processEndOfRound()
  checkEq("an EXTRA ARCHON makes a side worth LESS", w.winner, tB)
  checkEq("on rung 3", w.endReasonFor(), "more_bullet_worth")

block:
  ## Rung 4: everything equal, the highest ROBOT id of any type wins -- not
  ## the highest archon id the spec claims.
  let (w, at) = empty17(30)
  w.currentRound = 29
  var highest = low(int)
  var team = tNeutral
  for id, r in w.robots:
    if r.id > highest:
      highest = r.id
      team = r.team
  w.processEndOfRound()
  checkEq("with everything level, rung 4 decides", w.endReasonFor(),
    "highest_id")
  checkEq("and it is the team of the highest ROBOT id", w.winner, team)

# --- the ladder runs exactly once, at 2999 ----------------------------------
block:
  let (w, at) = empty17(30)
  w.victoryPoints[ord(tA)] = 3
  w.currentRound = 28
  w.processEndOfRound()
  check("the ladder does NOT run before the time limit", not w.hasWinner)
  checkEq("and no rung was recorded", w.domination, RungNone)
  w.currentRound = 29
  w.processEndOfRound()
  check("it runs at rounds - 1", w.hasWinner)
  checkEq("and stamps the round it fired on", w.tiebreakRound, 29)
  check("the world stopped running", not w.running)

# --- no gate game ever reports `fault` --------------------------------------
block:
  ## V5: `runRound`'s blanket catch is reachable in the engine and NEITHER of
  ## its two paths is reachable here. The claim is checked on real games.
  var reasons: seq[string]
  for name in ["HouseDivided", "CropCircles", "GreenHouse", "shrine"]:
    let (w, outcome) = mirror(name, rounds = 160)
    reasons.add(outcome.endReason)
    check(name & " reported a real end reason",
      outcome.endReason in world.Bc17RungNames or outcome.endReason == "abandoned")
    check(name & " did NOT report fault", outcome.endReason != "fault")
    check(name & " recorded a winner or an honest abandonment",
      outcome.winnerSlot >= 0 or outcome.aborted)
  echo "  end reasons: ", reasons

# --- endReasonFor REFUSES to mislabel ---------------------------------------
block:
  ## `RungNone` means "no winner at all", which the ladder cannot produce.
  ## Labelling it `more_victory_points` would hide a changed rule, so the
  ## port raises instead.
  let (w, at) = empty17()
  var raised = false
  try:
    discard w.endReasonFor()
  except Defect:
    raised = true
  check("a world with no rung RAISES rather than inventing a reason", raised)

finish("test_bc17_endladder")
