## §Tests item 15 -- scoring.
##
## Two numbers come out of a bc17 game and they answer DIFFERENT questions.
##
## `points[t]` is a continuous reading of the engine's OWN tiebreak ladder,
## in its own priority order and weighted in that order: victory points 64,
## bullet trees 24, bullet worth 12. It measures the SHAPE of the game. The
## weights are super-increasing (24 > 12, 64 > 24 + 12), so a decisive margin
## on a higher rung dominates everything below it -- **and that is all it
## claims.** A 501-to-499 victory-point margin is worth 0.128 of a point
## against 36 available below it, so `points` ALONE CAN FAVOUR THE LOSER.
## This shard asserts that as an EXPECTATION, not as a bug.
##
## `results.scores` is the one that orders the match: 200 per game won plus
## the mean of the per-game points, which is win-dominated by construction.

import std/[math, random]
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom, units, world, rules, maps]
import battlecode/results

# --- share, and the 0-0 case -------------------------------------------------
block:
  checkEq("a 0-0 integer share is 0.5, not 0", bits(share(0, 0)),
    bits(0.5'f32))
  checkEq("and a 0-0 float share too", bits(shareF(0'f32, 0'f32)),
    bits(0.5'f32))
  checkEq("an even split is 0.5", bits(share(7, 7)), bits(0.5'f32))
  checkEq("a shutout is 1.0", bits(share(9, 0)), bits(1'f32))
  checkEq("and the other side gets 0.0", bits(share(0, 9)), bits(0'f32))
  checkEq("a 3-1 is 0.75", bits(share(3, 1)), bits(0.75'f32))
  checkEq("shareF divides in float32", bits(shareF(3'f32, 1'f32)),
    bits(3'f32 / 4'f32))

# --- one vector per weight ---------------------------------------------------
block:
  proc pointsOf(vpA, vpB, treeA, treeB: int, worthA, worthB: float32): int =
    int(64.0'f32 * share(vpA, vpB) + 24.0'f32 * share(treeA, treeB) +
        12.0'f32 * shareF(max(0'f32, worthA), max(0'f32, worthB)))
  checkEq("everything level is 50", pointsOf(0, 0, 0, 0, 0, 0), 50)
  checkEq("a victory-point shutout alone is 64 + 12 + 6",
    pointsOf(10, 0, 0, 0, 0, 0), 82)
  checkEq("a bullet-tree shutout alone is 32 + 24 + 6",
    pointsOf(0, 0, 10, 0, 0, 0), 62)
  checkEq("a bullet-worth shutout alone is 32 + 12 + 12",
    pointsOf(0, 0, 0, 0, 100, 0), 56)
  checkEq("losing everything is 0", pointsOf(0, 10, 0, 10, 0, 100), 0)
  checkEq("and winning everything is 100", pointsOf(10, 0, 10, 0, 100, 0),
    100)

# --- super-increasing, as arithmetic ----------------------------------------
block:
  check("24 > 12", 24 > 12)
  check("and 64 > 24 + 12", 64 > 24 + 12)
  ## So a decisive margin on rung 1 beats everything below it.
  proc pointsOf(vpA, vpB, treeA, treeB: int, worthA, worthB: float32): int =
    int(64.0'f32 * share(vpA, vpB) + 24.0'f32 * share(treeA, treeB) +
        12.0'f32 * shareF(max(0'f32, worthA), max(0'f32, worthB)))
  check("a victory-point shutout outscores a clean sweep of everything else",
    pointsOf(10, 0, 0, 10, 0, 100) > pointsOf(0, 10, 10, 0, 100, 0))

# --- the documented case where `points` favours the LOSER -------------------
block:
  ## 501 to 499 on victory points -- a WIN on rung 1 -- against a side that
  ## swept the trees and the worth.
  proc pointsOf(vpA, vpB, treeA, treeB: int, worthA, worthB: float32): int =
    int(64.0'f32 * share(vpA, vpB) + 24.0'f32 * share(treeA, treeB) +
        12.0'f32 * shareF(max(0'f32, worthA), max(0'f32, worthB)))
  let winner = pointsOf(501, 499, 0, 30, 0, 900)
  let loser = pointsOf(499, 501, 30, 0, 900, 0)
  check("the winner of the game scores FEWER points than the loser",
    winner < loser)
  echo "  the 501-499 winner scores ", winner, " and the loser ", loser
  check("which is the documented behaviour of `points`, not a bug: it " &
    "measures the SHAPE of the game", winner + loser <= 100)

# --- the negative-worth clamp is on the SCORE, never the ladder -------------
block:
  ## A side reduced to three archons and no bullets is worth -3, and a
  ## negative share is not a share -- so the score clamps at zero. The
  ## LADDER compares the raw values, so -1 still beats -3 on rung 3 while
  ## both score 0.5.
  checkEq("both clamped worths give a 0.5 share",
    bits(shareF(max(0'f32, -1'f32), max(0'f32, -3'f32))), bits(0.5'f32))
  check("but the ladder compares them raw, and -1 beats -3", -1'f32 > -3'f32)
  var w = newWorld(loadMap("Alone"), 30)
  let o = w.rect.origin
  w.bulletSupply[ord(tA)] = 0'f32
  w.bulletSupply[ord(tB)] = 0'f32
  discard w.spawnRobot(rtArchon, loc(o.x + 20, o.y + 20), tB)
  discard w.spawnRobot(rtArchon, loc(o.x + 24, o.y + 20), tB)
  check("team B is worth strictly less than team A", w.bulletWorth(tB) <
    w.bulletWorth(tA))
  check("and both are negative", w.bulletWorth(tA) < 0'f32 and
    w.bulletWorth(tB) < 0'f32)
  let pts = w.gamePoints()
  checkEq("yet their bullet-worth shares are equal at the clamp",
    pts[0], pts[1])
  w.currentRound = 29
  w.processEndOfRound()
  checkEq("while the LADDER still separates them", w.winner, tA)
  checkEq("on rung 3", w.endReasonFor(), "more_bullet_worth")

# --- points are in [0, 100] and the seats sum to <= 100 ---------------------
block:
  var rnd = initRand(20170414)
  var outOfRange = 0
  var oversum = 0
  for trial in 0 ..< 500:
    var w = newWorld(loadMap("Alone"), 30)
    w.victoryPoints[ord(tA)] = rnd.rand(0 .. 1200)
    w.victoryPoints[ord(tB)] = rnd.rand(0 .. 1200)
    w.treeCount[ord(tA)] = rnd.rand(0 .. 60)
    w.treeCount[ord(tB)] = rnd.rand(0 .. 60)
    w.bulletSupply[ord(tA)] = float32(rnd.rand(-10.0 .. 3000.0))
    w.bulletSupply[ord(tB)] = float32(rnd.rand(-10.0 .. 3000.0))
    let pts = w.gamePoints()
    for t in 0 .. 1:
      if pts[t] < 0 or pts[t] > 100: inc outOfRange
    if pts[0] + pts[1] > 100: inc oversum
  checkEq("every score over 500 random finals is in [0, 100]", outOfRange, 0)
  checkEq("and the two seats never sum above 100", oversum, 0)

# --- results.scores orders the winner above the loser -----------------------
block:
  checkEq("the bc17 win bonus is 200", winBonusFor("bc17"), 200.0)
  var rnd = initRand(20170415)
  var inversions = 0
  for trial in 0 ..< 500:
    ## A synthetic best-of-three: `wins` games to the winner, the rest to
    ## the loser, with per-game points drawn anywhere in range -- including
    ## the pathological case where the loser sweeps the points.
    let games = rnd.rand(2 .. 3)
    let winsA = (if games == 2: 2 else: rnd.rand(2 .. 3))
    var ptsA, ptsB: seq[int]
    for g in 0 ..< games:
      ptsA.add(rnd.rand(0 .. 40))
      ptsB.add(rnd.rand(60 .. 100))
    var scoreA = float(winsA) * winBonusFor("bc17")
    var scoreB = float(games - winsA) * winBonusFor("bc17")
    var meanA = 0.0
    var meanB = 0.0
    for g in 0 ..< games:
      meanA += float(ptsA[g])
      meanB += float(ptsB[g])
    scoreA += meanA / float(games)
    scoreB += meanB / float(games)
    if scoreA <= scoreB: inc inversions
  checkEq("200 a game STRICTLY dominates the points mean over 500 " &
    "synthetic finals, even when the loser sweeps every point",
    inversions, 0)
  ## The arithmetic that makes it so: one game is worth 200 and the mean is
  ## bounded by 100.
  check("one win is worth more than the whole points range",
    winBonusFor("bc17") > 100.0)

# --- a clinched two-game match still separates ------------------------------
block:
  ## 2-0 gives `400 + mean` against `0 + mean <= 100`; a 2-1 gives
  ## `400 + mean` against `200 + mean <= 300`.
  let sweepWinner = 2.0 * winBonusFor("bc17") + 0.0
  let sweepLoser = 0.0 * winBonusFor("bc17") + 100.0
  check("a 2-0 winner outscores a 2-0 loser who took every point",
    sweepWinner > sweepLoser)
  let closeWinner = 2.0 * winBonusFor("bc17") + 0.0
  let closeLoser = 1.0 * winBonusFor("bc17") + 100.0
  check("and a 2-1 winner outscores a 2-1 loser who took every point",
    closeWinner > closeLoser)

# --- gamePoints on a real game ----------------------------------------------
block:
  let (w, outcome) = mirror("HouseDivided", rounds = 200)
  check("both seats have a score", outcome.points[0] >= 0 and
    outcome.points[1] >= 0)
  check("in range", outcome.points[0] <= 100 and outcome.points[1] <= 100)
  check("summing to at most 100", outcome.points[0] + outcome.points[1] <= 100)
  ## The outcome reports BY SEAT and the world computes BY TEAM, so the
  ## comparison goes through `slotOf`.
  let byTeam = w.gamePoints()
  checkEq("team A's points landed on team A's seat",
    outcome.points[outcome.slotOf(tA)], byTeam[0])
  checkEq("and team B's on team B's", outcome.points[outcome.slotOf(tB)],
    byTeam[1])

finish("test_bc17_scoring")
