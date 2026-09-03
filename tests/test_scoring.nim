## The points formula: float32 narrowing, integer TRUNCATION, both weight
## sets, zero-total shares, the packed king stat, the tiebreak ladder, and
## the rule that `cooperation_at_end` comes from the round flags.

import harness
import battlecode/[match, sim_types]
import battlecode/years/bc26/[constants, maps, rules, world]

proc worldWith(catA, catB, kingsA, kingsB, chzA, chzB: int,
               cooperation: bool): World =
  result = newWorld(loadMap("DefaultSmall"), GameMaxNumberOfRounds)
  result.isCooperation = cooperation
  result.teamInfo.damageToCats = [catA, catB]
  result.teamInfo.cheeseTransferred = [chzA, chzB]
  ## The map spawns one king a side; set the counts directly so the shard
  ## tests the arithmetic, not the spawner.
  result.teamInfo.numRatKings = [kingsA, kingsB]

# --- the harvested Java vector ---------------------------------------------
# From a real engine match on `peaceinourtime`: catDamage 4000/4000,
# cheese 1590/2940, packed king stat 17231/19732. Decode the packed value
# `kings + 10 * teamCheese` with `% 10` and `// 10`.
block:
  let packedA = 17231
  let packedB = 19732
  checkEq("packed king stat decodes team A kings", packedA mod 10, 1)
  checkEq("packed king stat decodes team B kings", packedB mod 10, 2)
  checkEq("packed king stat decodes team A cheese", packedA div 10, 1723)
  checkEq("packed king stat decodes team B cheese", packedB div 10, 1973)
  let w = worldWith(4000, 4000, packedA mod 10, packedB mod 10, 1590, 2940,
    cooperation = true)
  let pts = w.gamePoints()
  checkEq("peaceinourtime team A points", pts[0], 42)
  checkEq("peaceinourtime team B points", pts[1], 57)
  check("team B won on points", pts[1] > pts[0])

# --- truncation, not rounding ----------------------------------------------
block:
  ## 1/3 of the cat damage under cooperation is 16.666…; truncation gives 16
  ## and rounding would give 17. Cheese and kings are zeroed so only the cat
  ## term contributes.
  let w = worldWith(1, 2, 0, 0, 0, 0, cooperation = true)
  let pts = w.gamePoints()
  checkEq("truncation, not rounding (1/3)", pts[0], 16)
  checkEq("truncation, not rounding (2/3)", pts[1], 33)

# --- zero totals ------------------------------------------------------------
block:
  let w = worldWith(0, 0, 0, 0, 0, 0, cooperation = true)
  let pts = w.gamePoints()
  checkEq("zero-total shares are 0, not NaN (A)", pts[0], 0)
  checkEq("zero-total shares are 0, not NaN (B)", pts[1], 0)

# --- both weight sets -------------------------------------------------------
block:
  ## Same world, only the cooperation flag differs: 100 % of the cat damage
  ## is worth 50 in cooperation and 30 after a backstab; 100 % of the kings
  ## is worth 30 and 50.
  let coop = worldWith(100, 0, 1, 0, 0, 0, cooperation = true)
  let stab = worldWith(100, 0, 1, 0, 0, 0, cooperation = false)
  checkEq("cooperation weights 0.5 cat + 0.3 kings", coop.gamePoints()[0], 80)
  checkEq("backstab weights 0.3 cat + 0.5 kings", stab.gamePoints()[0], 80)
  let coopCat = worldWith(100, 0, 0, 0, 0, 0, cooperation = true)
  let stabCat = worldWith(100, 0, 0, 0, 0, 0, cooperation = false)
  checkEq("cat damage alone: cooperation", coopCat.gamePoints()[0], 50)
  checkEq("cat damage alone: backstab", stabCat.gamePoints()[0], 30)
  let coopKing = worldWith(0, 0, 1, 0, 0, 0, cooperation = true)
  let stabKing = worldWith(0, 0, 1, 0, 0, 0, cooperation = false)
  checkEq("kings alone: cooperation", coopKing.gamePoints()[0], 30)
  checkEq("kings alone: backstab", stabKing.gamePoints()[0], 50)

# --- float32 narrowing is observable ---------------------------------------
block:
  ## A share that is exactly representable in float64 but not in float32.
  ## 8_388_609 / 16_777_218 is 0.5 in both; 1/3 of a large total is where the
  ## widths part company, so the assertion is that the ENGINE'S width is used:
  ## the sum is computed from float32 shares widened back to float64.
  let w = worldWith(16_777_217, 33_554_431, 0, 0, 0, 0, cooperation = true)
  let f32 = float64(float32(16_777_217) / float32(16_777_217 + 33_554_431))
  let f64 = 16_777_217.0 / (16_777_217.0 + 33_554_431.0)
  check("the two widths really do differ on this vector", f32 != f64)
  checkEq("points use the float32 share", w.gamePoints()[0],
    int(0.5 * 100.0 * f32))

# --- cooperation_at_end comes from the round flags -------------------------
block:
  ## A kill-all-kings win AFTER a backstab still records `KILL_ALL_RAT_KINGS`
  ## as its domination factor. Reading the flag off the win type would score
  ## the game with the wrong weight set.
  let w = worldWith(100, 0, 1, 0, 0, 0, cooperation = false)
  w.setWinner(teamA, dfKillAllRatKings)
  checkEq("domination factor says kill-all-kings", w.domination,
    dfKillAllRatKings)
  check("the cooperation flag still says backstab", not w.isCooperation)
  checkEq("scoring uses the flag, not the win type", w.gamePoints()[0], 80)

# --- the tiebreak ladder ---------------------------------------------------
block:
  ## Points first.
  let w = worldWith(3, 1, 0, 0, 0, 0, cooperation = true)
  check("more points wins", w.setWinnerIfMorePoints())
  checkEq("and it is team A", w.winner, teamA)

block:
  ## Equal points, more cheese.
  let w = worldWith(1, 1, 0, 0, 0, 0, cooperation = true)
  check("equal points does not decide", not w.setWinnerIfMorePoints())
  w.teamInfo.globalCheese = [10, 5]
  check("more cheese decides", w.setWinnerIfMoreCheese())
  checkEq("and it is team A", w.winner, teamA)

block:
  ## Equal points and cheese, more rats alive.
  let w = worldWith(1, 1, 0, 0, 0, 0, cooperation = true)
  w.teamInfo.globalCheese = [7, 7]
  check("equal cheese does not decide", not w.setWinnerIfMoreCheese())
  w.teamInfo.numBabyRats = [1, 4]
  check("more rats alive decides", w.setWinnerIfMoreRatsAlive())
  checkEq("and it is team B", w.winner, teamB)

block:
  ## Everything equal: the seeded coin flip. It must be REPRODUCIBLE, which
  ## is the whole reason it is not Math.random().
  let a = worldWith(1, 1, 0, 0, 0, 0, cooperation = true)
  let b = worldWith(1, 1, 0, 0, 0, 0, cooperation = true)
  a.setWinnerArbitrary()
  b.setWinnerArbitrary()
  checkEq("the coin flip is reproducible", a.winner, b.winner)
  checkEq("and it is recorded as dubious", a.domination, dfDubious)

# --- the match score --------------------------------------------------------
block:
  var g0 = GameOutcome(winnerSlot: 0, points: [60, 39])
  var g1 = GameOutcome(winnerSlot: 1, points: [30, 69])
  var g2 = GameOutcome(winnerSlot: 0, points: [55, 44])
  let scores = scoresFor(@[g0, g1, g2])
  checkEq("100 per game won plus the mean of the points", scores[0],
    200.0 + (60.0 + 30.0 + 55.0) / 3.0)
  checkEq("and for the other seat", scores[1],
    100.0 + (39.0 + 69.0 + 44.0) / 3.0)
  check("higher is better", scores[0] > scores[1])
  checkEq("no games played scores zero", scoresFor(@[]), [0.0, 0.0])
  checkEq("best of three needs two wins", winsNeeded(3), 2)
  checkEq("best of one needs one win", winsNeeded(1), 1)

finish("test_scoring")
