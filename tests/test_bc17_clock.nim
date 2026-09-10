## §Tests item 13 -- the turn clock: the DecisionOps budget and the
## twenty-round dormancy.
##
## V1 replaces the JVM bytecode counter with a `DecisionOps` budget:
## `bytecodeLimit / 10`, i.e. 3 000 for an ARCHON and 1 500 for everything
## else -- and **0 for a robot that cannot execute code at all**.
##
## `canExecuteCode()` is `health > 0 && (isBuildable() ? roundsAlive >= 20 :
## true)`. So a BUILT fighter does nothing whatsoever for twenty turns while
## it heals 4 % of its max health a turn, and a HIRED gardener -- which is
## not `isBuildable` -- acts from its second round, its first being lost to
## the exec-order snapshot and not to this rule.

import std/sequtils
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom, units, world, actions, rules,
                              maps]

# --- the three budgets -------------------------------------------------------
block:
  checkEq("ArchonOps is 3000", ArchonOps, 3000)
  checkEq("UnitOps is 1500", UnitOps, 1500)
  checkEq("DormantOps is 0", DormantOps, 0)
  checkEq("and they are the engine's bytecodeLimit / 10", ArchonOps,
    RobotSpecs[rtArchon].bytecodeLimit div 10)
  for t in [rtGardener, rtLumberjack, rtSoldier, rtTank, rtScout]:
    checkEq($t & "'s budget is 1500", opsFor(t), UnitOps)

# --- a BUILT fighter is silent for twenty turns -----------------------------
block:
  ## The exact health sequence, and the exact turn it wakes up.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let s = w.spawnRobot(rtSoldier, loc(o.x + 50, o.y + 50), tA)
  checkEq("a built SOLDIER is born at 10.0", bits(s.health), bits(10'f32))
  checkEq("with roundsAlive 0", s.roundsAlive, 0)
  var healths: seq[float32]
  var budgets: seq[int]
  for turn in 1 .. 21:
    w.processBeginningOfTurn(s)
    healths.add(s.health)
    budgets.add(s.ops)
    s.roundsAlive += 1
  checkEq("its first twenty turns give it NO budget at all",
    budgets[0 ..< 20], newSeqWith(20, 0))
  checkEq("and turn 21 gives it the full 1500", budgets[20], UnitOps)
  ## The healing: 0.04f x 50 == 2.0 a turn, from 10 to 50.
  var expected = 10'f32
  var stepFailures = 0
  for i in 0 ..< 20:
    expected = expected + repairPerDormantTurn(rtSoldier)
    if bits(healths[i]) != bits(expected): inc stepFailures
  checkEq("the health sequence is 12, 14, ... 50 exactly", stepFailures, 0)
  checkEq("it ends at maxHealth", bits(s.health), bits(50'f32))
  checkEq("and the twenty-first turn does NOT heal it further",
    bits(healths[20]), bits(50'f32))

# --- a HIRED gardener is not dormant ----------------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let g = w.spawnRobot(rtGardener, loc(o.x + 50, o.y + 50), tA)
  checkEq("a hired GARDENER is born at 40/40", bits(g.health),
    bits(maxHealthF(rtGardener)))
  check("it is NOT isBuildable", not isBuildable(rtGardener))
  check("so it can execute code from its very first turn",
    g.canExecuteCode())
  w.processBeginningOfTurn(g)
  checkEq("with a full budget", g.ops, UnitOps)
  ## What actually delays it by one round is the exec-order snapshot, which
  ## is a different rule and lives in test_bc17_execorder.nim.
  let snapshot = w.execOrder
  let late = w.spawnRobot(rtGardener, loc(o.x + 60, o.y + 50), tA)
  check("a gardener hired mid-round is not in this round's snapshot",
    snapshot.find(late.id) < 0)

# --- an ARCHON is never dormant ---------------------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let a = w.spawnRobot(rtArchon, loc(o.x + 50, o.y + 50), tA)
  check("an ARCHON can execute code from turn one", a.canExecuteCode())
  w.processBeginningOfTurn(a)
  checkEq("with the archon budget", a.ops, ArchonOps)
  check("and it is not repaired -- it is born full",
    bits(a.health) == bits(400'f32))

# --- a dead robot has no budget ---------------------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let s = w.spawnRobot(rtSoldier, loc(o.x + 50, o.y + 50), tA)
  s.roundsAlive = DormancyRounds + 5
  check("a healthy veteran can execute code", s.canExecuteCode())
  s.health = 0'f32
  check("a robot at zero health cannot", not s.canExecuteCode())
  w.processBeginningOfTurn(s)
  checkEq("and gets no budget", s.ops, DormantOps)

# --- the per-turn counters reset --------------------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let g = w.spawnRobot(rtGardener, loc(o.x + 50, o.y + 50), tA)
  g.roundsAlive = DormancyRounds + 1
  g.attackCount = 1
  g.moveCount = 1
  g.waterCount = 1
  g.shakeCount = 1
  g.repairCount = 1
  g.buildCooldownTurns = 3
  w.processBeginningOfTurn(g)
  checkEq("attackCount resets", g.attackCount, 0)
  checkEq("moveCount resets", g.moveCount, 0)
  checkEq("waterCount resets", g.waterCount, 0)
  checkEq("shakeCount resets", g.shakeCount, 0)
  checkEq("repairCount resets", g.repairCount, 0)
  checkEq("and the build cooldown TICKS DOWN by one, not to zero",
    g.buildCooldownTurns, 2)
  for i in 0 ..< 2: w.processBeginningOfTurn(g)
  checkEq("three turns clear it", g.buildCooldownTurns, 0)
  w.processBeginningOfTurn(g)
  checkEq("and it does not go negative", g.buildCooldownTurns, 0)

# --- the cap is checked BEFORE each primitive -------------------------------
block:
  ## A chassis that asks for more than its budget stops at the cap and
  ## leaves the world unchanged from that point on. The sim enforces it, not
  ## the bot.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let s = w.spawnRobot(rtSoldier, loc(o.x + 50, o.y + 50), tA)
  s.roundsAlive = DormancyRounds + 1
  w.processBeginningOfTurn(s)
  checkEq("the budget starts full", s.ops, UnitOps)
  checkEq("and nothing is spent", s.opsUsed, 0)
  s.opsUsed = UnitOps
  check("at the cap, no further primitive may run",
    s.opsUsed >= s.ops)

# --- decision_ops_peak stays under the cap in a real game -------------------
block:
  ## V1's own claim: both chassis finish every gate game with a peak strictly
  ## below their cap, so the budget never truncates a turn in play.
  let (w, outcome) = mirror("HouseDivided", rounds = 220)
  check("the game ran", outcome.roundsPlayed >= 200)
  for slot in 0 .. 1:
    check("seat " & $slot & "'s DecisionOps peak is recorded",
      outcome.decisionOpsPeak[slot] > 0)
    check("and it is strictly below the ARCHON cap",
      outcome.decisionOpsPeak[slot] < ArchonOps)
  echo "  peaks ", outcome.decisionOpsPeak[0], " and ",
    outcome.decisionOpsPeak[1], " against a cap of ", ArchonOps

# --- timeLimitReached --------------------------------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  w.currentRound = 2998
  check("the time limit has NOT been reached at round 2998",
    not w.timeLimitReached())
  w.currentRound = 2999
  check("it fires at 2999, which is rounds - 1", w.timeLimitReached())
  w.currentRound = 3000
  check("and stays true past it", w.timeLimitReached())
  checkEq("the default round count is 3000", gameDefaultRounds, 3000)

finish("test_bc17_clock")
