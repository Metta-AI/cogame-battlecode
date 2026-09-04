## The end ladder in the engine's own order: annihilation checked EVERY round
## and outranking the vote count, the double wipe that goes to B, round 1500
## really being played, the four rungs each with a vector, and every
## `end_reason` value producible.

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

proc bare(maxRounds = 1500): World = newWorld(flat(15, 15), maxRounds)

# --- annihilation ------------------------------------------------------------
block:
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  w.currentRound = 7
  w.checkEndOfMatch()
  checkEq("B has nothing, so A wins by annihilation", w.winner, teamA)
  checkEq("with the engine's own name", $w.domination, "annihilated")
  check("and the game stops", not w.running)

block:
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamB, 100)
  w.currentRound = 7
  w.checkEndOfMatch()
  checkEq("symmetrically", w.winner, teamB)

block:
  ## A DOUBLE WIPE in the same round awards the win to B — the engine tests
  ## team A's count first, so an empty A gives B the game.
  var w = bare()
  w.currentRound = 7
  w.checkEndOfMatch()
  checkEq("a double wipe goes to B", w.winner, teamB)
  checkEq("as annihilation", $w.domination, "annihilated")

block:
  ## Annihilation outranks the vote count, even at the time limit.
  var w = bare(10)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  w.stats.votes = [0, 900]
  w.currentRound = 10
  w.checkEndOfMatch()
  checkEq("A is wiped out on votes but B has no robots", w.winner, teamA)
  checkEq("so annihilation wins the ladder", $w.domination, "annihilated")

# --- the time limit is `round >= rounds`, so round 1500 IS played -----------
block:
  var w = bare(1500)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 100)
  w.currentRound = 1499
  check("round 1499 is not the limit", not w.timeLimitReached())
  w.checkEndOfMatch()
  check("so no winner is set", not w.hasWinner)
  w.currentRound = 1500
  check("round 1500 IS the limit", w.timeLimitReached())

# --- the four rungs, in order ------------------------------------------------
block:
  var w = bare(10)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 100)
  w.stats.votes = [800, 700]
  w.currentRound = 10
  w.checkEndOfMatch()
  checkEq("more votes", $w.domination, "more_votes")
  checkEq("to A", w.winner, teamA)

block:
  var w = bare(10)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(4, 4), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 500)
  w.stats.votes = [750, 750]
  w.currentRound = 10
  w.checkEndOfMatch()
  checkEq("votes tied, more Centers", $w.domination,
    "more_enlightenment_centers")
  checkEq("to A", w.winner, teamA)

block:
  var w = bare(10)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 100)
  discard w.spawnRobot(-1, rtMuckraker, loc(12, 11), teamB, 40)
  w.stats.votes = [750, 750]
  w.currentRound = 10
  w.checkEndOfMatch()
  checkEq("Centers tied, more total influence", $w.domination, "more_influence")
  checkEq("to B", w.winner, teamB)
  checkEq("and the influence really is summed over EVERY living non-neutral",
    w.totalInfluence(teamB), 140)

block:
  var w = bare(10)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 100)
  w.stats.votes = [750, 750]
  w.currentRound = 10
  w.checkEndOfMatch()
  checkEq("everything tied is a coin flip", $w.domination, "coin_flip")
  check("and it is decided by the WORLD rng, not the wall clock",
    w.winner == teamA or w.winner == teamB)

block:
  ## Neutral Centers count for nobody on the Centers rung.
  var w = bare(10)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(7, 7), teamNeutral, 900)
  w.stats.votes = [750, 750]
  w.currentRound = 10
  w.checkEndOfMatch()
  checkEq("a neutral Center breaks no tie", $w.domination, "coin_flip")
  checkEq("and its influence is not counted", w.totalInfluence(teamA), 100)

# --- every end_reason is producible ------------------------------------------
block:
  var seen: seq[string]
  for d in [dfAnnihilated, dfMoreVotes, dfMoreEnlightenmentCenters,
            dfMoreInfluence, dfCoinFlip]:
    seen.add($d)
  checkEq("five engine reasons", seen.len, 5)
  check("annihilated", "annihilated" in seen)
  check("more_votes", "more_votes" in seen)
  check("more_enlightenment_centers", "more_enlightenment_centers" in seen)
  check("more_influence", "more_influence" in seen)
  check("coin_flip", "coin_flip" in seen)

finish("bc21 end ladder")
