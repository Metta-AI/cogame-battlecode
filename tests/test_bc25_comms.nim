## bc25 messages: robot<->tower ONLY, the r2 <= 20 range, the paint-connectivity
## BFS refusing to start off our own paint, the 1/20 per-turn caps, the
## five-round buffer expiry, `broadcastMessage` needing no paint at all, and
## the chassis's own 32-bit word round-tripping for every kind.

import harness
import bc25_fixture

proc paintLine(w: World, team: Team, x0, x1, y: int) =
  for x in x0 .. x1: w.setPaint(loc(x, y), primaryPaint(team))

block:
  ## robot -> tower, connected by paint.
  var w = bare(ruins = @[loc(14, 10)])
  let tower = w.place(teamA, utLevelOneMoneyTower, loc(14, 10))
  let r = w.place(teamA, utSoldier, loc(10, 10))
  w.paintLine(teamA, 10, 13, 10)
  check("a connected robot may send", w.canSendMessage(r, tower.loc))
  w.doSendMessage(r, tower.loc, 4242)
  checkEq("the tower received it", tower.inbox.len, 1)
  checkEq("with the sender's id", tower.inbox[0].senderId, r.id)
  checkEq("and the word", tower.inbox[0].bytes, 4242)
  check("but only ONE a turn", not w.canSendMessage(r, tower.loc))

block:
  ## The BFS refuses to START when the robot is not standing on team paint.
  var w = bare(ruins = @[loc(14, 10)])
  let tower = w.place(teamA, utLevelOneMoneyTower, loc(14, 10))
  let r = w.place(teamA, utSoldier, loc(10, 10))
  w.paintLine(teamA, 11, 13, 10)
  check("an unpainted tile under the sender refuses the send",
    not w.canSendMessage(r, tower.loc))
  w.setPaint(loc(10, 10), primaryPaint(teamA))
  check("painting it lets the send through", w.canSendMessage(r, tower.loc))
  w.setPaint(loc(12, 10), PaintNone)
  check("and one gap in the path refuses it again",
    not w.canSendMessage(r, tower.loc))

block:
  ## The BFS is FOUR-NEIGHBOUR: a diagonal-only path is not connected.
  var w = bare(ruins = @[loc(13, 13)])
  let tower = w.place(teamA, utLevelOneMoneyTower, loc(13, 13))
  let r = w.place(teamA, utSoldier, loc(10, 10))
  for i in 0 .. 3: w.setPaint(loc(10 + i, 10 + i), primaryPaint(teamA))
  check("a diagonal chain is not connected by paint",
    not w.connectedByPaint(teamA, r.loc, tower.loc))

block:
  ## robot <-> robot and tower <-> tower are both refused.
  var w = bare(ruins = @[loc(14, 10), loc(16, 10)])
  let t1 = w.place(teamA, utLevelOneMoneyTower, loc(14, 10))
  let t2 = w.place(teamA, utLevelOneMoneyTower, loc(16, 10))
  let a = w.place(teamA, utSoldier, loc(10, 10))
  let b = w.place(teamA, utSoldier, loc(11, 10))
  w.paintLine(teamA, 10, 13, 10)
  check("robot to robot is refused", not w.canSendMessage(a, b.loc))
  check("tower to tower is refused", not w.canSendMessage(t1, t2.loc))
  check("but a tower may BROADCAST", w.canBroadcastMessage(t1))
  w.doBroadcastMessage(t1, 7)
  checkEq("and the other tower hears it across an unpainted gap",
    t2.inbox.len, 1)
  checkEq("counting as ONE message", t1.sentMessages, 1)

block:
  ## The enemy never receives.
  var w = bare(ruins = @[loc(14, 10)])
  let tower = w.place(teamB, utLevelOneMoneyTower, loc(14, 10))
  let r = w.place(teamA, utSoldier, loc(10, 10))
  w.paintLine(teamA, 10, 13, 10)
  check("an enemy tower is never a legal target",
    not w.canSendMessage(r, tower.loc))

block:
  ## Range: r2 <= 20.
  var w = bare(ruins = @[loc(15, 10)])
  let tower = w.place(teamA, utLevelOneMoneyTower, loc(15, 10))
  let r = w.place(teamA, utSoldier, loc(10, 10))
  w.paintLine(teamA, 10, 14, 10)
  checkEq("the distance is 25", r.loc.distanceSquaredTo(tower.loc), 25)
  check("which is out of the message radius",
    not w.canSendMessage(r, tower.loc))

block:
  ## A tower may send twenty a turn.
  var w = bare(ruins = @[loc(14, 10)])
  let tower = w.place(teamA, utLevelOneMoneyTower, loc(14, 10))
  let r = w.place(teamA, utSoldier, loc(12, 10))
  w.paintLine(teamA, 12, 13, 10)
  for i in 1 .. MaxMessagesSentTower:
    check("tower message " & $i & " is allowed",
      w.canSendMessage(tower, r.loc))
    w.doSendMessage(tower, r.loc, i)
  check("the twenty-first is not", not w.canSendMessage(tower, r.loc))

block:
  ## The buffer expires at the start of a round, five rounds on.
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  w.currentRound = 100
  r.inbox.add(Message(bytes: 1, senderId: 9, round: 100))
  w.currentRound = 104
  w.cleanMessages(r)
  checkEq("four rounds on it is still there", r.inbox.len, 1)
  w.currentRound = 105
  w.cleanMessages(r)
  checkEq("five rounds on it is gone", r.inbox.len, 0)

block:
  ## `readMessages(round)` filters, `readMessages()` does not.
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.inbox.add(Message(bytes: 1, senderId: 9, round: 10))
  r.inbox.add(Message(bytes: 2, senderId: 9, round: 11))
  checkEq("everything", readMessages(r).len, 2)
  checkEq("one round", readMessages(r, 11).len, 1)

block:
  ## The chassis's 32-bit word round-trips for every kind.
  for kind in MessageKind:
    for (x, y, r8, payload) in [(0, 0, 0, 0), (63, 63, 255, 511),
                                (17, 42, 200, 300)]:
      let word = packWord(kind, x, y, r8, payload)
      let back = unpackWord(word)
      checkEq("kind " & $kind, back.kind, kind)
      checkEq("x", back.x, x)
      checkEq("y", back.y, y)
      checkEq("round8", back.round8, r8)
      checkEq("payload", back.payload, payload)

finish("test_bc25_comms")
