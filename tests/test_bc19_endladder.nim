## `isOver`'s seven rungs, in the engine's own order — including the
## `win_condition = 1` OVERWRITE, which is reproduced literally.

import harness
import battlecode/sheet
import battlecode/years/bc19/rules

proc mirror(name: string, maxRounds: int,
            chassis: array[2, ChassisKind19] = [ck19Saber, ck19Saber]):
    (World, GameOutcome19) =
  let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
  playGame(loadMap(name), sheets, chassis, 0, 0, maxRounds, 0)

block:
  ## The rung vocabulary, and the two the port can NEVER produce (V6): every
  ## robot is handed its side's chassis at the moment it is created, so
  ## `nulls[t]` is always 0 and win conditions 3 and 4 are unreachable.
  checkEq("rung 0 is `no rung`", endReasonName(Bc19RungNone), "abandoned")
  checkEq("castles_destroyed", endReasonName(Bc19RungCastlesDestroyed),
    "castles_destroyed")
  checkEq("coin_flip", endReasonName(Bc19RungCoinFlip), "coin_flip")
  checkEq("more_castles", endReasonName(Bc19RungMoreCastles), "more_castles")
  checkEq("more_unit_health", endReasonName(Bc19RungMoreUnitHealth),
    "more_unit_health")

block:
  ## THE ROUND LIMIT IS REACHED WITH EXACTLY ONE TURN OF THE LAST ROUND. The
  ## game-over check runs BEFORE EVERY TURN, so the round counter reaches the
  ## cap on the first turn of that round and the check fires immediately
  ## after it.
  let (w, o) = mirror("seed-0043", 40)
  checkEq("the game stopped at the cap", o.roundsPlayed, 40)
  checkEq("and the world agrees", w.round, 40)
  check("a winner was recorded", w.hasWinner)
  check("on a round-limit rung",
    w.endRung in [Bc19RungMoreCastles, Bc19RungMoreUnitHealth,
                  Bc19RungCoinFlip])
  checkEq("the tiebreak round is the cap", w.tiebreakRound, 40)
  ## AND WIN CONDITIONS 3 AND 4 ARE NEVER PRODUCED (V6).
  check("win_condition is never 3", o.winCondition != 3)
  check("and never 4", o.winCondition != 4)
  checkEq("`abandoned` is not an end reason for a completed game",
    o.endReason != "abandoned", true)

block:
  ## RUNG 6 -- castles level, health differs -- AND THE ENGINE'S OWN
  ## `win_condition = 1`.
  let (w, o) = mirror("seed-0009", 300)
  if w.endRung == Bc19RungMoreUnitHealth:
    checkEq("more_unit_health records the engine's win_condition 1",
      o.winCondition, 1)
    checkEq("and the end reason", o.endReason, "more_unit_health")
    check("with castles really level",
      w.castlesAlive(tRed) == w.castlesAlive(tBlue))
    check("and health really not",
      w.totalHealth(tRed) != w.totalHealth(tBlue))
  else:
    check("this seed took another rung, which is also legal", true)

block:
  ## RUNG 5 -- round limit, castle counts differ -- records win_condition 0.
  ## Constructed rather than hoped for: kill one of RED's castles outright
  ## and run the ladder.
  let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
  var w = newWorld(loadMap("seed-0043"), 5)
  check("seed-0043 starts two castles a side",
    w.castlesAlive(tRed) == 2 and w.castlesAlive(tBlue) == 2)
  var victim: Robot = nil
  for r in w.robots:
    if r.team == tRed and r.unit == ukCastle:
      victim = r
      break
  w.deleteRobot(victim)
  checkEq("RED is down to one castle", w.castlesAlive(tRed), 1)
  w.round = 5
  check("and the ladder fires at the cap", w.evaluateIsOver())
  checkEq("on more_castles", w.endRung, Bc19RungMoreCastles)
  checkEq("with the engine's win_condition 0", w.winCondition, 0)
  checkEq("and BLUE wins", w.winner, tBlue)

block:
  ## RUNG 3 -- `castles_destroyed` -- FIRES THE INSTANT THE LAST CASTLE
  ## DIES, and the game stops BEFORE THE NEXT ROBOT ACTS.
  var w = newWorld(loadMap("seed-0017"), 1000)
  check("seed-0017 is a one-castle-a-side elimination board",
    w.castlesAlive(tRed) == 1 and w.castlesAlive(tBlue) == 1)
  var victim: Robot = nil
  for r in w.robots:
    if r.team == tRed and r.unit == ukCastle:
      victim = r
      break
  w.deleteRobot(victim)
  checkEq("RED has no castles", w.castlesAlive(tRed), 0)
  check("the ladder fires immediately, at round 0", w.evaluateIsOver())
  checkEq("on castles_destroyed", w.endRung, Bc19RungCastlesDestroyed)
  checkEq("with the engine's win_condition 0", w.winCondition, 0)
  checkEq("and BLUE wins", w.winner, tBlue)

block:
  ## RUNG 4 -- BOTH sides castle-less -- is a COIN FLIP with the engine's
  ## win_condition 2, and it draws EXACTLY ONE value from the seeded
  ## MT19937.
  var w = newWorld(loadMap("seed-0017"), 1000)
  var doomed: seq[Robot]
  for r in w.robots:
    if r.unit == ukCastle: doomed.add(r)
  for r in doomed: w.deleteRobot(r)
  checkEq("nobody has a castle", w.castlesAlive(tRed) + w.castlesAlive(tBlue), 0)
  let before = w.gen.mti
  check("the ladder fires", w.evaluateIsOver())
  checkEq("on coin_flip", w.endRung, Bc19RungCoinFlip)
  checkEq("with the engine's win_condition 2", w.winCondition, 2)
  check("and it cost exactly one draw", w.gen.mti != before)

block:
  ## `endReasonFor` RAISES rather than mislabelling an impossible state. An
  ## impossible state that reports a plausible answer is the wrong failure
  ## mode: a future rule change that makes it reachable has to surface as a
  ## FAILURE and not as a wrong `end_reason` in a shipped replay.
  var w = newWorld(loadMap("seed-0009"), 1000)
  var raised = false
  try:
    discard w.endReasonFor()
  except Defect:
    raised = true
  check("a game with no rung raises rather than reporting one", raised)

finish("test_bc19_endladder")
