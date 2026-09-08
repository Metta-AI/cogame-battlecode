## bc25 end-of-turn: the territory bill (1 / 2 / 0, DOUBLED for a mopper), the
## crowding bill counting allied units INCLUDING TOWERS, the 20 HP for standing
## at exactly zero paint, and the fact that a robot killed by that 20 HP is
## removed inside its own end-of-turn.

import harness
import bc25_fixture

block:
  ## Territory: bare costs 1, enemy costs 2, our own costs nothing.
  for (colour, cost) in [(PaintNone, 1), (3, 2), (1, 0)]:
    var w = bare()
    let r = w.place(teamA, utSoldier, loc(10, 10))
    if colour != PaintNone: w.setPaint(loc(10, 10), colour)
    r.paint = 100
    w.processEndOfTurn(r)
    checkEq("a soldier on colour " & $colour & " pays " & $cost,
      100 - r.paint, cost)

block:
  ## A MOPPER pays double on bare and on enemy ground, and still nothing on
  ## its own.
  for (colour, cost) in [(PaintNone, 2), (3, 4), (1, 0)]:
    var w = bare()
    let r = w.place(teamA, utMopper, loc(10, 10))
    if colour != PaintNone: w.setPaint(loc(10, 10), colour)
    r.paint = 100
    w.processEndOfTurn(r)
    checkEq("a mopper on colour " & $colour & " pays " & $cost,
      100 - r.paint, cost)

block:
  ## THE CROWDING BILL COUNTS TOWERS. A robot standing next to its own paint
  ## tower pays for it, which is not what the spec's prose says.
  var w = bare()
  w.setPaint(loc(10, 10), primaryPaint(teamA))
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.paint = 100
  w.processEndOfTurn(r)
  checkEq("alone on our own paint: free", r.paint, 100)
  discard w.place(teamA, utLevelOneMoneyTower, loc(11, 10))
  r.paint = 100
  w.processEndOfTurn(r)
  checkEq("one allied TOWER within r2 <= 2 costs 1", r.paint, 99)
  discard w.place(teamA, utSoldier, loc(9, 10))
  r.paint = 100
  w.processEndOfTurn(r)
  checkEq("a tower and an allied robot cost 2", r.paint, 98)
  discard w.place(teamB, utSoldier, loc(10, 11))
  r.paint = 100
  w.processEndOfTurn(r)
  checkEq("an ENEMY robot beside us costs nothing", r.paint, 98)

block:
  ## On ENEMY ground the crowding term is doubled as well.
  var w = bare()
  w.setPaint(loc(10, 10), primaryPaint(teamB))
  let r = w.place(teamA, utSoldier, loc(10, 10))
  discard w.place(teamA, utSoldier, loc(11, 10))
  discard w.place(teamA, utSoldier, loc(9, 10))
  r.paint = 100
  w.processEndOfTurn(r)
  checkEq("2 for the territory plus 2 x 2 for the crowd", r.paint, 94)

block:
  ## Exactly 0 paint costs 20 HP THAT SAME TURN.
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.paint = 1
  let hp = r.health
  w.processEndOfTurn(r)
  checkEq("the bare tile took the last point", r.paint, 0)
  checkEq("and zero paint cost 20 HP", r.health, hp - NoPaintDamage)
  check("the robot cannot move at zero paint", not r.isMovementReady())
  check("nor act", not r.isActionReady())

block:
  ## A robot killed by the 20 HP is removed INSIDE its own end-of-turn.
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.paint = 0
  r.health = 20
  let id = r.id
  w.processEndOfTurn(r)
  check("it is gone", not w.existsRobot(id))
  check("its tile is clear", w.getRobot(loc(10, 10)) == nil)
  checkEq("and the exec order lost the entry", w.execOrder.find(id), -1)

block:
  ## A TOWER pays no end-of-turn bill at all, at any paint level, on any
  ## colour.
  var w = bare()
  w.setPaint(loc(10, 12), primaryPaint(teamB))
  let t = w.place(teamA, utLevelOneMoneyTower, loc(10, 12))
  t.paint = 100
  let hp = t.health
  w.processEndOfTurn(t)
  checkEq("a tower's stash is untouched", t.paint, 100)
  t.paint = 0
  w.processEndOfTurn(t)
  checkEq("and a tower at zero paint takes no damage", t.health, hp)

block:
  ## A robot at zero paint may still DISINTEGRATE: it is free, has no range
  ## and charges no cooldown.
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.paint = 0
  let id = r.id
  w.doDisintegrate(r)
  check("disintegration always works", not w.existsRobot(id))

finish("test_bc25_penalties")
