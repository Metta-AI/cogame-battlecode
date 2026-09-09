## Shard 9 of the note's list — **signals**, and the one place this year is
## harder than the others: **there is no shared array in 2016**, and EVERY
## SIGNAL IS HEARD BY THE ENEMY TOO.
##
## 5 basic and 20 message signals a turn, reset in `processBeginningOfTurn`;
## message signals from ARCHON and SCOUT only; a negative radius refused; the
## broadcast reaching EVERY ROBOT OF EVERY TEAM within `r2` EXCEPT the sender;
## the FIFO queue capped at 1000 with the OLDEST dropped; `readSignal` popping
## the head and `emptySignalQueue` draining in order; and the delay charge
## `0.05 + 0.03 * max(0, r2/sightR2 - 2)` added to BOTH counters.

import harness
import bc16_fixture

# --- the per-turn caps -----------------------------------------------------
block:
  checkEq("BASIC_SIGNALS_PER_TURN is 5", BasicSignalsPerTurn, 5)
  checkEq("MESSAGE_SIGNALS_PER_TURN is 20", MessageSignalsPerTurn, 20)
  checkEq("SIGNAL_QUEUE_MAX_SIZE is 1000", SignalQueueMaxSize, 1000)
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  for i in 0 ..< 5:
    check("basic signal " & $i & " is allowed", w.doBroadcast(s, 4))
  check("the sixth is refused", not w.doBroadcast(s, 4))
  checkEq("and the counter says five", s.basicSignalCount, 5)
  checkEq("and the team's telemetry too", w.stats.basicSignals[0], 5)
  ## `processBeginningOfTurn` resets it — play a round and check.
  let sheets = defaultSheets()
  let sides = newSides16(sheets, 0)
  runRound(w, sides, [ckBulwark, ckBulwark])
  check("and the count is reset at the start of the next turn",
    s.basicSignalCount < 5)

block:
  let w = bare()
  let a = w.at(3, 15)
  for i in 0 ..< 20:
    check("message signal " & $i & " is allowed",
      w.doBroadcastMessage(a, i, i * 2, 4))
  check("the twenty-first is refused", not w.doBroadcastMessage(a, 0, 0, 4))
  checkEq("and the telemetry says twenty", w.stats.messageSignals[0], 20)

# --- message signals from ARCHON and SCOUT ONLY ---------------------------
block:
  let w = bare()
  for k in [rtSoldier, rtGuard, rtViper, rtTurret, rtTtm]:
    let r = w.put(k, loc(10, 10 + ord(k)), teamA)
    check("a " & $k & " cannot send a message signal",
      not w.doBroadcastMessage(r, 1, 2, 4))
    check("but CAN send a basic one", w.doBroadcast(r, 4))
  let sc = w.put(rtScout, loc(20, 20), teamA)
  check("a SCOUT can send a message signal",
    w.doBroadcastMessage(sc, 1, 2, 4))

# --- a negative radius is refused -----------------------------------------
block:
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  let before = w.refusedActions
  check("a negative radius is refused", not w.doBroadcast(s, -1))
  checkEq("and it IS counted as a refusal", w.refusedActions, before + 1)
  check("zero is fine", w.doBroadcast(s, 0))

# --- the broadcast reaches EVERY TEAM, except the sender ------------------
block:
  let w = bare(robots = @[])
  let sender = w.put(rtSoldier, loc(15, 15), teamA)
  let friend = w.put(rtSoldier, loc(16, 15), teamA)
  let enemy = w.put(rtSoldier, loc(14, 15), teamB)
  let neutral = w.put(rtGuard, loc(15, 16), teamNeutral)
  let zombie = w.put(rtStandardzombie, loc(15, 14), teamZombie)
  let far = w.put(rtSoldier, loc(25, 25), teamB)
  discard w.doBroadcast(sender, 4)
  checkEq("a friend hears it", friend.signalQueue.len, 1)
  checkEq("THE ENEMY HEARS EVERY ONE", enemy.signalQueue.len, 1)
  checkEq("a NEUTRAL hears it", neutral.signalQueue.len, 1)
  checkEq("and so does the horde", zombie.signalQueue.len, 1)
  checkEq("the sender does NOT hear its own", sender.signalQueue.len, 0)
  checkEq("and a robot outside the radius hears nothing",
    far.signalQueue.len, 0)
  checkEq("the signal carries the sender's location", friend.signalQueue[0].x,
    15)
  checkEq("its id", friend.signalQueue[0].senderId, sender.id)
  checkEq("and its team", friend.signalQueue[0].team, teamA)
  check("and a basic signal carries no message",
    not friend.signalQueue[0].hasMessage)

block:
  let w = bare(robots = @[])
  let a = w.put(rtArchon, loc(15, 15), teamA)
  let hearer = w.put(rtSoldier, loc(16, 15), teamB)
  discard w.doBroadcastMessage(a, 0x1234, 0x5678, 4)
  checkEq("a message signal carries two 32-bit ints",
    hearer.signalQueue[0].m1, 0x1234)
  checkEq("and the second", hearer.signalQueue[0].m2, 0x5678)
  check("and is flagged as a message", hearer.signalQueue[0].hasMessage)

# --- the FIFO queue: 1000, OLDEST dropped ---------------------------------
block:
  let w = bare()
  let r = w.put(rtSoldier, loc(10, 10), teamA)
  for i in 0 ..< 1200:
    r.receiveSignal(Signal(x: i, y: 0, senderId: i, team: teamA))
  checkEq("the queue is capped at 1000", r.signalQueue.len, 1000)
  checkEq("and it is the OLDEST that were dropped — the head is #200",
    r.signalQueue[0].senderId, 200)
  checkEq("and the tail is the newest", r.signalQueue[^1].senderId, 1199)
  let head = r.readSignal()
  check("readSignal pops the head", head.ok)
  checkEq("which is #200", head.signal.senderId, 200)
  checkEq("and the queue shrinks", r.signalQueue.len, 999)
  let drained = r.emptySignalQueue()
  checkEq("emptySignalQueue drains the rest in order", drained.len, 999)
  checkEq("head first", drained[0].senderId, 201)
  checkEq("tail last", drained[^1].senderId, 1199)
  checkEq("and the queue is empty", r.signalQueue.len, 0)
  check("and readSignal on an empty queue is a clean miss",
    not r.readSignal().ok)

# --- the delay charge, on BOTH counters -----------------------------------
block:
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  ## r2 = 2 x sightR2 -> the flat base 0.05.
  discard w.doBroadcast(s, 48)
  checkEq("a broadcast at twice the sight radius costs a flat 0.05 on the " &
    "core", s.d.core, 0.05)
  checkEq("and 0.05 on the weapon too", s.d.weapon, 0.05)
  let t = w.put(rtSoldier, loc(12, 10), teamA)
  ## r2 = 3 x sightR2 -> 0.05 + 0.03 * 1 = 0.08.
  discard w.doBroadcast(t, 72)
  checkEq("and at three times it costs 0.08", t.d.core, 0.08)
  checkEq("on both counters", t.d.weapon, 0.08)
  let u = w.put(rtSoldier, loc(14, 10), teamA)
  discard w.doBroadcast(u, 4)
  checkEq("well inside twice the radius it is still the flat base",
    u.d.core, 0.05)
  checkEq("BROADCAST_BASE_DELAY_INCREASE is 0.05",
    BroadcastBaseDelayIncrease, 0.05)
  checkEq("BROADCAST_ADDITIONAL_DELAY_INCREASE is 0.03",
    BroadcastAdditionalDelayIncrease, 0.03)

block:
  ## The charge is an ADD, so it stacks over five broadcasts in one turn.
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  for i in 0 ..< 5: discard w.doBroadcast(s, 48)
  checkEq("five flat broadcasts cost 0.25 on the core",
    s.d.core, 0.05 * 5.0)
  check("and the robot is STILL core-ready — a broadcast is cheap",
    s.d.isCoreReady())

# --- a broadcast does NOT require readiness -------------------------------
block:
  ## `broadcastSignal` has no readiness test at all: a broadcast COSTS delay,
  ## it does not require the absence of it.
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  s.d.core = 9.0
  s.d.weapon = 9.0
  check("a fully loaded robot can still broadcast", w.doBroadcast(s, 4))

finish("test_bc16_signals")
