## The `DecisionOps` clock (V1), and THE THEOREM that makes the chess-clock
## divergence a statement rather than a hope.
##
## The engine's per-robot resource is a WALL-CLOCK chess clock: `robot.time`
## starts at `CHESS_INITIAL = 100` ms, gains `CHESS_EXTRA = 20` ms at the
## start of every turn (`game.js:759`), loses the turn's measured elapsed
## (`:771`, `:805`), and a robot below zero is FROZEN (`:806-808`). It is not
## reproducible even between two runs of the engine itself, so it is replaced
## by a deterministic clock whose per-turn CHARGE IS THE EXACT CONSTANT
## `TurnChargeOps = ChessExtraOps`.
##
## **THEOREM.** Because the charge equals the refill, `robot.chessOps` is
## invariant at `ChessInitialOps` for every robot for its whole life, and
## therefore no robot is ever frozen and the engine's `robot.time < 0` branch
## is unreachable in this port.

import harness
import battlecode/sheet
import battlecode/years/bc19/rules

block:
  checkEq("ChessInitialOps", ChessInitialOps, 2000)
  checkEq("ChessExtraOps", ChessExtraOps, 400)
  checkEq("TurnChargeOps", TurnChargeOps, 400)
  checkEq("TurnMaxOps", TurnMaxOps, 4000)
  checkEq("AND THE CHARGE IS THE REFILL -- that is the whole of V1",
    TurnChargeOps, ChessExtraOps)

block:
  ## THE INVARIANT, after every turn of a whole game. If it ever moved, a
  ## robot could accumulate or lose clock and the freeze branch would become
  ## reachable -- which is exactly the thing V1 claims cannot happen.
  let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
  let spec = loadMap("seed-0043")
  var w = newWorld(spec, 1000)
  var sides = newSides19(sheets, 0)
  var rounds = 0
  var checkedRobots = 0
  var peak = 0
  while w.running and rounds < 1000:
    runRound(w, sides, [ck19Saber, ck19Saber])
    inc rounds
    for r in w.robots:
      if r.turn == 0: continue      ## created this round, has not acted yet
      if r.chessOps != ChessInitialOps:
        checkEq("chessOps is invariant for robot " & $r.id & " at round " &
          $w.round, r.chessOps, ChessInitialOps)
      inc checkedRobots
      if r.opsUsed > peak: peak = r.opsUsed
  check("the invariant was checked on a real game", checkedRobots > 5000)
  check("chessOps never moved, so NO ROBOT IS EVER FROZEN", true)
  ## And therefore the freeze branch never ran: `processAction` raises only
  ## when `chessOps` goes negative, which it provably cannot.
  check("and `chessOps` is still the initial value everywhere",
    (block:
      var ok = true
      for r in w.robots:
        if r.turn > 0 and r.chessOps != ChessInitialOps: ok = false
      ok))

  ## THE CAP IS DEMONSTRABLY NON-BINDING. It is checked BEFORE each
  ## primitive and never inside one, so a primitive's RESULT is never a
  ## function of the remaining budget -- only whether the chassis got to ask.
  check("decision_ops_peak is below TurnMaxOps", peak < TurnMaxOps)
  check("and comfortably so -- under 30 % of the cap", peak * 10 < TurnMaxOps * 3)
  echo "  measured decision_ops_peak = ", peak, " of ", TurnMaxOps

block:
  ## A robot that asks for more than the cap has its turn end DETERMINISTICALLY
  ## where it stands, rather than hanging or resuming mid-computation next
  ## turn. `charge` is the one place ops are spent and it refuses rather than
  ## overdrawing.
  let spec = loadMap("seed-0009")
  var w = newWorld(spec, 1000)
  let r = w.robots[0]
  r.opsLeft = TurnMaxOps
  r.opsUsed = 0
  check("a 3000-op primitive is affordable at the top of a turn",
    r.afford(3000))
  check("and it charges", r.charge(3000))
  checkEq("leaving 1000", r.opsLeft, TurnMaxOps - 3000)
  check("a second 3000-op primitive is REFUSED", not r.afford(3000))
  check("and refusing does not overdraw", not r.charge(3000))
  checkEq("so the budget is untouched", r.opsLeft, TurnMaxOps - 3000)
  checkEq("and `opsUsed` counted only what really ran", r.opsUsed, 3000)
  check("a 1000-op primitive still fits exactly", r.charge(1000))
  checkEq("and now nothing does", r.opsLeft, 0)
  check("not even one op", not r.charge(1))

  ## NO RULE READS IT. `decision_ops_peak` is telemetry: the same game played
  ## twice resolves identically whatever the peak was.
  let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
  let (w1, o1) = playGame(spec, sheets, [ck19Saber, ck19Saber], 0, 0, 300, 0)
  let (w2, o2) = playGame(spec, sheets, [ck19Saber, ck19Saber], 0, 0, 300, 0)
  checkEq("the same game twice gives the same hash chain",
    o1.hashChain, o2.hashChain)
  checkEq("and the same peak", w1.stats.decisionOpsPeak,
    w2.stats.decisionOpsPeak)

finish("test_bc19_clock")
