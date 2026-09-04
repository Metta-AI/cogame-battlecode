## Scoring: the points formula with float32 narrowing and truncation, the
## tiebreak ladder in the engine's order with a vector for each rung, the
## round-limit off-by-one, and every `end_reason` value producible.

import harness
import battlecode/years/bc20/[constants, world]

proc flat(width, height: int): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.symmetry = symRotational
  result.randomSeed = 4242
  for i in 0 ..< width * height:
    result.elevation.add(0)
    result.water.add(false)
    result.pollution.add(0)
    result.soup.add(0)

proc bare(): World = newWorld(flat(15, 15), 1500)

# --- the points formula -----------------------------------------------------
block:
  ## Both HQs alive, identical rosters: 30 + 12.5 + 7.5 = 50 apiece.
  var w = bare()
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(rtHq, loc(13, 13), teamB)
  let pts = w.gamePoints()
  checkEq("a dead heat is 50 apiece", pts, [50, 50])
  check("points are inside [0, 100]",
    pts[0] >= 0 and pts[0] <= 100 and pts[1] >= 0 and pts[1] <= 100)
  check("and the two seats sum to at most 100", pts[0] + pts[1] <= 100)

block:
  ## One HQ gone: the whole survival term and the whole unit share to the
  ## survivor. Both pools still hold their `INITIAL_SOUP`, so the NET WORTH
  ## share stays even and each side keeps 7 of the 15 — which is exactly the
  ## point of scoring the ladder continuously rather than as a win flag.
  var w = bare()
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  let hqB = w.spawnRobot(rtHq, loc(13, 13), teamB)
  w.destroyRobot(hqB)
  let pts = w.gamePoints()
  checkEq("the survivor takes survival and the unit share", pts, [92, 7])
  check("and the loser keeps only its half of the net-worth share",
    pts[1] < 15)

block:
  ## `units` counts BUILDINGS TOO — exactly the QUANTITY rung — and `worth`
  ## includes the team pool — exactly the QUALITY rung.
  var w = bare()
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(rtHq, loc(13, 13), teamB)
  discard w.spawnRobot(rtNetGun, loc(2, 1), teamA)
  checkEq("a building counts toward the unit share", w.livingUnits(teamA), 2)
  w.stats.soup[0] = 1000
  checkEq("the pool counts toward net worth", w.netWorth(teamA),
    1000 + RobotSpecs[rtNetGun].cost)
  let pts = w.gamePoints()
  check("and the richer, larger side scores higher", pts[0] > pts[1])

block:
  ## The float32 narrowing is load-bearing: the same arithmetic runs natively
  ## and in wasm32 and must produce the same integer.
  var w = bare()
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(rtHq, loc(13, 13), teamB)
  for i in 0 ..< 3: discard w.spawnRobot(rtMiner, loc(3 + i, 1), teamA)
  w.stats.soup[0] = 7
  w.stats.soup[1] = 11
  let survival = 0.5'f32
  let shareU = float32(4) / float32(5)
  let worthA = float32(7 + 3 * RobotSpecs[rtMiner].cost)
  let worthB = float32(11)
  let shareW = worthA / (worthA + worthB)
  let want = int(60.0'f32 * survival + 25.0'f32 * shareU + 15.0'f32 * shareW)
  checkEq("the formula is reproduced exactly", w.gamePoints()[0], want)

# --- the tiebreak ladder, one vector per rung -------------------------------
block:
  ## Rung 1: HQ destroyed.
  var w = bare()
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  let hqB = w.spawnRobot(rtHq, loc(13, 13), teamB)
  w.destroyRobot(hqB)
  w.checkEndOfMatch()
  checkEq("rung 1 is hq_destroyed", $w.domination, "hq_destroyed")
  checkEq("and the survivor wins", w.winner, teamA)

block:
  ## Rung 2: quantity — more robots alive, buildings included.
  var w = bare()
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(rtHq, loc(13, 13), teamB)
  discard w.spawnRobot(rtNetGun, loc(2, 1), teamA)
  w.currentRound = w.maxRounds - 1
  w.checkEndOfMatch()
  checkEq("rung 2 is quantity", $w.domination, "quantity")
  checkEq("and the larger side wins", w.winner, teamA)

block:
  ## Rung 3: quality — equal robots, greater net worth.
  var w = bare()
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(rtHq, loc(13, 13), teamB)
  w.stats.soup[1] = w.stats.soup[0] + 50
  w.currentRound = w.maxRounds - 1
  w.checkEndOfMatch()
  checkEq("rung 3 is quality", $w.domination, "quality")
  checkEq("and the richer side wins", w.winner, teamB)

block:
  ## Rung 4: broadcasts — equal worth, more MINTED transactions.
  var w = bare()
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(rtHq, loc(13, 13), teamB)
  w.stats.blockchainsSent = [3, 1]
  w.currentRound = w.maxRounds - 1
  w.checkEndOfMatch()
  checkEq("rung 4 is broadcasts", $w.domination, "broadcasts")
  checkEq("and the chattier side wins", w.winner, teamA)

block:
  ## Rung 5: the highest living non-neutral robot id.
  var w = bare()
  discard w.spawnRobot(50_000, rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(50_001, rtHq, loc(13, 13), teamB)
  discard w.spawnRobot(9, rtCow, loc(7, 7), teamNeutral)
  w.currentRound = w.maxRounds - 1
  w.checkEndOfMatch()
  checkEq("rung 5 is highest_id", $w.domination, "highest_id")
  checkEq("and the higher id wins", w.winner, teamB)

block:
  ## Rung 6: reachable only when NEITHER team has a living robot, and driven
  ## by the world RNG rather than `Math.random()`.
  var w = bare()
  discard w.spawnRobot(9, rtCow, loc(7, 7), teamNeutral)
  w.currentRound = w.maxRounds - 1
  w.checkEndOfMatch()
  checkEq("rung 6 is coin_flip", $w.domination, "coin_flip")
  check("and it is deterministic", (block:
    var again = bare()
    discard again.spawnRobot(9, rtCow, loc(7, 7), teamNeutral)
    again.currentRound = again.maxRounds - 1
    again.checkEndOfMatch()
    again.winner == w.winner))

block:
  ## `roundLimitReached` is the engine's `round >= rounds - 1`, so a
  ## 1500-round cap plays 1499.
  var w = newWorld(flat(9, 9), 1500)
  w.currentRound = 1498
  check("round 1498 has not reached the limit", not w.timeLimitReached())
  w.currentRound = 1499
  check("round 1499 has", w.timeLimitReached())

finish("test_bc20_scoring")
