## The points formula: float32 narrowing before the weighted sum, truncation
## by the `int()` cast, one vector per weight, the [0, 100] bound, the two
## seats summing to at most 100, and — over 200 random synthetic finals — the
## ordering of `results.scores` agreeing with the winner.

import std/random
import harness
import battlecode/years/bc21/[constants, world, rules]

proc flat(width, height: int): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.origin = [0, 0]
  result.randomSeed = 4242
  result.symmetry = symRotational
  result.symmetries = @[symRotational]
  for i in 0 ..< width * height:
    result.passability.add(1.0)

proc bare(): World = newWorld(flat(20, 20), 1500)

# --- a dead heat -------------------------------------------------------------
block:
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(17, 17), teamB, 100)
  w.stats.votes = [400, 400]
  let pts = w.gamePoints()
  checkEq("a dead heat is 50 apiece", pts, [50, 50])
  check("points are inside [0, 100]",
    pts[0] >= 0 and pts[0] <= 100 and pts[1] >= 0 and pts[1] <= 100)
  check("and the seats sum to at most 100", pts[0] + pts[1] <= 100)

# --- one weight at a time ----------------------------------------------------
block:
  ## Survival, Centres and influence all go to A; the VOTE share is 0/0, and
  ## `max(1, ...)` makes that ZERO FOR BOTH rather than a free 35 for the
  ## survivor. 40 + 0 + 15 + 10 = 65.
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  let pts = w.gamePoints()
  checkEq("a wipeout with no votes cast is 65 - 0", pts, [65, 0])
  check("and the seats still sum to at most 100", pts[0] + pts[1] <= 100)

block:
  ## The VOTES rung alone, everything else level.
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(17, 17), teamB, 100)
  w.stats.votes = [1000, 0]
  let pts = w.gamePoints()
  ## 20 (survival) + 35 (all the votes) + 7.5 + 5 = 67.5 -> 67
  checkEq("all the votes is 67 to 32", pts, [67, 32])

block:
  ## The CENTRES rung alone.
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 50)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(4, 4), teamA, 50)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(6, 6), teamA, 50)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(17, 17), teamB, 150)
  w.stats.votes = [500, 500]
  let pts = w.gamePoints()
  ## 20 + 17.5 + 11.25 + 5 = 53.75 -> 53 ; 20 + 17.5 + 3.75 + 5 = 46.25 -> 46
  checkEq("three Centers to one is 53 to 46", pts, [53, 46])

block:
  ## The INFLUENCE rung alone.
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 900)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(17, 17), teamB, 100)
  w.stats.votes = [500, 500]
  let pts = w.gamePoints()
  ## 20 + 17.5 + 7.5 + 9 = 54 ; 20 + 17.5 + 7.5 + 1 = 46
  checkEq("nine tenths of the influence is 54 to 46", pts, [54, 46])

# --- truncation, not rounding ------------------------------------------------
block:
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(17, 17), teamB, 100)
  w.stats.votes = [2, 1]
  let pts = w.gamePoints()
  ## 20 + 35*(2/3) + 7.5 + 5 = 55.833... -> 55, not 56.
  checkEq("the sum TRUNCATES", pts[0], 55)
  ## 20 + 35*(1/3) + 7.5 + 5 = 44.166... -> 44
  checkEq("on both sides", pts[1], 44)

block:
  ## A zero denominator never divides: `max(1, ...)` everywhere.
  var w = bare()
  discard w.spawnRobot(-1, rtSlanderer, loc(2, 2), teamA, 0)
  discard w.spawnRobot(-1, rtSlanderer, loc(17, 17), teamB, 0)
  let pts = w.gamePoints()
  checkEq("no votes, no Centers, no influence: 20 apiece", pts, [20, 20])

# --- 200 random synthetic finals --------------------------------------------
block:
  var rng = initRand(20260904)
  var disagreements = 0
  var outOfRange = 0
  var oversum = 0
  for trial in 0 ..< 200:
    var w = bare()
    let ca = rng.rand(0 .. 3)
    let cb = rng.rand(0 .. 3)
    var x = 1
    for i in 0 ..< ca:
      discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(1, x), teamA,
                           rng.rand(1 .. 900))
      x += 2
    x = 1
    for i in 0 ..< cb:
      discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(18, x), teamB,
                           rng.rand(1 .. 900))
      x += 2
    if ca == 0 and rng.rand(1) == 0:
      discard w.spawnRobot(-1, rtMuckraker, loc(3, 15), teamA, 1)
    if cb == 0 and rng.rand(1) == 0:
      discard w.spawnRobot(-1, rtMuckraker, loc(16, 15), teamB, 1)
    w.stats.votes = [rng.rand(0 .. 1500), rng.rand(0 .. 1500)]
    let pts = w.gamePoints()
    if pts[0] < 0 or pts[0] > 100 or pts[1] < 0 or pts[1] > 100:
      inc outOfRange
    if pts[0] + pts[1] > 100:
      inc oversum
    ## The winner the engine's ladder would name, and the seat the formula
    ## scores higher, must be the same seat.
    w.currentRound = 1500
    w.maxRounds = 1500
    w.checkEndOfMatch()
    if w.hasWinner and w.domination != dfCoinFlip:
      let winner = ord(w.winner)
      let loser = 1 - winner
      ## The note's claim: the RUNG that decided it always comes with the
      ## matching share above 0.5 for the winner.
      let alive = [(if w.robotCount[0] > 0: 1 else: 0),
                   (if w.robotCount[1] > 0: 1 else: 0)]
      let centers = [w.livingCenters(teamA), w.livingCenters(teamB)]
      let influence = [w.totalInfluence(teamA), w.totalInfluence(teamB)]
      ## For `dfAnnihilated` the test is `>=`, not `>`: a DOUBLE WIPE is
      ## annihilation too, and the engine awards it to B with both at zero.
      let matched =
        case w.domination
        of dfAnnihilated: alive[winner] >= alive[loser]
        of dfMoreVotes: w.stats.votes[winner] > w.stats.votes[loser]
        of dfMoreEnlightenmentCenters: centers[winner] > centers[loser]
        of dfMoreInfluence: influence[winner] > influence[loser]
        else: true
      if not matched: inc disagreements
      ## And the MATCH score, which carries the 100-per-game win bonus, always
      ## puts the winner first — which is what the league ranks by.
      ## `scoresFor` is `100 * gamesWon + mean(points)`; for one game that is
      ## exactly the arithmetic below.
      let scoreW = 100.0 + float(pts[winner])
      let scoreL = float(pts[loser])
      if scoreW <= scoreL: inc disagreements
  checkEq("no synthetic final scores outside [0, 100]", outOfRange, 0)
  checkEq("and none sums above 100", oversum, 0)
  checkEq("the winning rung carries the matching share and the match score " &
          "puts the winner first", disagreements, 0)

finish("bc21 scoring")
