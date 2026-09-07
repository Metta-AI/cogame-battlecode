## bc24's end conditions: `capture` on the third flag mid-round with the rest
## of the exec sweep still played, `timeLimitReached` at `round >= 2000` so
## round 2000 IS played, the ladder in the engine's own order with a vector
## each, a `coin_flip` seeded from the WORLD RNG, and the proof that
## `MORE_FLAGS_PICKED` and `RESIGNATION` are unreachable.

import harness
import bc24_fixture
import battlecode/years/bc24/rules
import battlecode/sheet

let sheets = [defaultSheet("bc24"), defaultSheet("bc24")]

# --- the ladder, one vector a rung ------------------------------------------
block:
  var w = bare()
  w.currentRound = 2000
  w.stats.flagsCaptured = [2, 1]
  w.checkEndOfMatch()
  checkEq("more flags captured wins first", w.domination, dfMoreFlagCaptures)
  checkEq("and it is team A", w.winner, teamA)
  check("and the game stops", not w.running)

block:
  var w = bare()
  w.currentRound = 2000
  w.stats.flagsCaptured = [1, 1]
  let r = w.placeDuck(teamB, loc(20, 5))
  r.attackExp = 200
  w.checkEndOfMatch()
  checkEq("captures tied: the LEVEL SUM decides", w.domination, dfLevelSum)
  checkEq("and it is team B", w.winner, teamB)

block:
  var w = bare()
  w.currentRound = 2000
  w.stats.flagsCaptured = [0, 0]
  w.stats.crumbs = [500, 400]
  w.checkEndOfMatch()
  checkEq("levels tied: CRUMBS decide", w.domination, dfMoreBread)
  checkEq("and it is team A", w.winner, teamA)

block:
  var w = bare()
  w.currentRound = 2000
  w.stats.flagsCaptured = [0, 0]
  w.stats.crumbs = [400, 400]
  w.checkEndOfMatch()
  checkEq("everything tied: a coin flip", w.domination, dfCoinFlip)
  check("and somebody won it", w.hasWinner)

block:
  ## The coin flip is drawn from the WORLD RNG, which is seeded from the map's
  ## own `randomSeed` -- so it is reproducible, unlike the engine's
  ## `Math.random()` (docs/RULES-BC24.md §Divergences item 2).
  var first = teamA
  for run in 0 .. 1:
    var w = bare()
    w.currentRound = 2000
    w.stats.crumbs = [400, 400]
    w.checkEndOfMatch()
    if run == 0: first = w.winner
    else: checkEq("the same seed flips the same way", w.winner, first)

# --- the round limit --------------------------------------------------------
block:
  var w = bare()
  w.currentRound = 1999
  check("round 1999 is not the limit", not w.timeLimitReached())
  w.currentRound = 2000
  check("round 2000 IS the limit -- and it is PLAYED, because the check runs "
        , w.timeLimitReached())
  w.currentRound = 1999
  w.checkEndOfMatch()
  check("so nothing is decided at 1999", not w.hasWinner)

block:
  ## The whole 2000 rounds really are played out when nobody can capture. The
  ## dam column is turned into a WALL so the two halves never meet and the
  ## ladder is the only way the game can end.
  var w = bare(2000, withDam = false)
  for y in 0 ..< TestHeight:
    w.walls[DamColumn + y * TestWidth] = true
  var sides = newSides24(sheets, 0)
  let chassis = [ckExamplefuncsplayer24, ckExamplefuncsplayer24]
  var rounds = 0
  while w.running and w.currentRound < 2000:
    runRound(w, sides, chassis)
    rounds += 1
  checkEq("two thousand rounds", rounds, 2000)
  check("and the ladder decided it", w.hasWinner)

# --- capture stops the game only at the END of the round --------------------
block:
  var w = bare()
  w.postSetup()
  w.stats.flagsCaptured[0] = 2
  let f = w.ownFlags(teamB)[0]
  let a = w.placeDuck(teamA, loc(4, 3))
  w.removeFlagAt(f.loc, f)
  a.flag = f
  f.carriedBy = a.id
  f.loc = a.loc
  w.doMove(a, dWest)
  check("the winner is set the instant the third flag lands", w.hasWinner)
  checkEq("with CAPTURE", w.domination, dfCapture)
  check("but `running` is still true, so the rest of the exec order plays",
    w.running)
  let later = w.placeDuck(teamB, loc(20, 20))
  w.doMove(later, dEast)
  checkEq("and a later duck really did take its turn", later.loc,
    loc(21, 20))
  w.checkEndOfMatch()
  checkEq("the ladder does NOT re-decide a capture win", w.domination,
    dfCapture)
  check("it just stops the game", not w.running)

# --- the two dead rungs -----------------------------------------------------
block:
  ## `MORE_FLAGS_PICKED` exists in the engine's `DominationFactor` and
  ## `checkEndOfMatch` NEVER CALLS IT; `RESIGNATION` has no action a doctrine
  ## can reach. Neither is in our enum, and this is the assertion that keeps
  ## it that way.
  var names: seq[string]
  for d in Domination:
    if d != dfNone: names.add($d)
  checkEq("exactly five reachable end reasons", names,
    @["capture", "more_flag_captures", "level_sum", "more_bread", "coin_flip"])
  var w = bare()
  w.currentRound = 2000
  w.stats.flagsCaptured = [0, 0]
  w.stats.flagsPickedUp = [9, 0]
  w.stats.crumbs = [400, 400]
  w.checkEndOfMatch()
  checkEq("nine pickups to nil does NOT decide the game", w.domination,
    dfCoinFlip)

finish("bc24 end ladder")
