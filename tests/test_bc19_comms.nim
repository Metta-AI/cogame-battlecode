## THE TWO CHANNELS. bc19 is the year communication is a first-class,
## PRICED, PUBLIC resource, and the two channels could not be more different:
##
##   * the RADIO (`signal`): 16 bits, a radius in r^2 from 0 to 7938, costing
##     `ceil(sqrt(r^2))` fuel, and readable by EVERY UNIT OF BOTH TEAMS
##     inside that radius. There is no encryption and no team check. A
##     broadcast is a public announcement you pay for.
##   * CASTLE TALK: 8 bits, FREE, UNLIMITED RANGE, and readable ONLY by a
##     castle of the same team — and a castle sees the `team`, `id` and `turn`
##     of every friendly unit on the board whether or not it can see it.
##
## `game.js:831-843` (the radio's validation), `:845-849` (castle talk),
## `action_record.js:325-331` (the charge and the clear), `:651-736`
## (`getGameStateDump`'s field-stripping ladder).

import harness
import battlecode/years/bc19/rules
import battlecode/years/bc19/chassis/comms

proc board(name = "seed-0045", rounds = 1000): World =
  newWorld(loadMap(name), rounds)

proc validate(w: World, r: Robot, a: Action): (ActionRecord, bool) =
  var rec = newRecord()
  var threw = false
  r.chessOps += ChessExtraOps
  try:
    w.processAction(r, a, rec)
  except CatchableError:
    threw = true
  (rec, threw)

proc turnOf(w: World, r: Robot, a: Action): bool =
  ## Validate then enact, exactly as `enactTurn` does: the throw is swallowed
  ## and whatever the record already holds is enacted anyway.
  let (rec, threw) = w.validate(r, a)
  w.enact(r, rec)
  threw

proc castleOf(w: World, t: Team): Robot =
  for r in w.robots:
    if r.team == t and r.unit == ukCastle: return r
  nil

proc freeSquareNear(w: World, x0, y0, span: int): (int, int) =
  for dy in -span .. span:
    for dx in -span .. span:
      if dx == 0 and dy == 0: continue
      if w.isPassable(x0 + dx, y0 + dy) and w.shadowAt(x0 + dx, y0 + dy) == 0:
        return (x0 + dx, y0 + dy)
  (-1, -1)

proc seenBy(w: World, viewer: Robot, id: int): SeenRobot =
  for e in w.observationFor(viewer):
    if e.id == id: return e
  SeenRobot(id: -1)

block:
  ## THE RADIO'S BOUNDS, at every boundary.
  checkEq("COMMUNICATION_BITS is 16", CommunicationBits, 16)
  checkEq("so the value domain is 0 .. 65535", 1 shl CommunicationBits, 65536)
  checkEq("MAX_SIGNAL_RADIUS is 7938", MaxSignalRadius, 7938)
  checkEq("which is 2*(MAX_BOARD_SIZE-1)^2",
    2 * (MaxBoardSize - 1) * (MaxBoardSize - 1), 7938)
  var w = board()
  let castle = w.castleOf(tRed)
  check("a red castle exists", not castle.isNil)
  w.fuel[0] = 100000
  for (value, radius, legal) in [(0, 0, true), (65535, 0, true),
                                 (65536, 0, false), (-1, 0, false),
                                 (1, 7938, true), (1, 7939, false),
                                 (1, -1, false), (32768, 4, true)]:
    var a = newAction()
    a.signal = value
    a.signalRadius = radius
    let (rec, threw) = w.validate(castle, a)
    checkEq("signal " & $value & " radius " & $radius & " legality",
      not threw, legal)
    if legal:
      checkEq("  and the value is recorded", rec.signal, value)
      checkEq("  with its radius", rec.signalRadius, radius)

block:
  ## THE COST IS `ceil(sqrt(r^2))`, CHARGED ONCE PER TURN AND BEFORE THE
  ## ACTION'S OWN COST. The whole domain is tabled; here are the joints.
  checkEq("radius 0 is free", signalCost(0), 0)
  checkEq("radius 1 costs 1", signalCost(1), 1)
  checkEq("radius 2 costs 2", signalCost(2), 2)
  checkEq("radius 4 costs 2", signalCost(4), 2)
  checkEq("radius 5 costs 3", signalCost(5), 3)
  checkEq("radius 9 costs 3", signalCost(9), 3)
  checkEq("radius 10 costs 4", signalCost(10), 4)
  checkEq("radius 7938 costs 90", signalCost(7938), 90)
  checkEq("and 7921 = 89^2 costs exactly 89", signalCost(7921), 89)
  checkEq("while 7922 costs 90", signalCost(7922), 90)
  ## Once per turn, and before the move's cost.
  var w = board()
  let castle = w.castleOf(tRed)
  let (px, py) = freeSquareNear(w, castle.x, castle.y, 1)
  check("a free square next to the castle exists", px >= 0)
  let pil = w.createItem(px, py, tRed, ukPilgrim)
  var far = (-1, -1)
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx * dx + dy * dy != 1: continue
      if w.isPassable(pil.x + dx, pil.y + dy) and
          w.shadowAt(pil.x + dx, pil.y + dy) == 0:
        far = (dx, dy)
  check("and the pilgrim has an orthogonal step", far[0] != 0 or far[1] != 0)
  w.fuel[0] = 1000
  var a = moveAction(far[0], far[1])
  a.signal = 777
  a.signalRadius = 10               ## costs 4
  check("the move-with-broadcast is legal", not w.turnOf(pil, a))
  checkEq("the turn cost exactly 4 (radio) + 1 (move)", w.fuel[0], 1000 - 5)
  checkEq("and the radio fuel was attributed", w.stats.radioFuelSpent[0], 4)
  checkEq("with one message counted", w.stats.radioMessages[0], 1)
  checkEq("the pilgrim moved", (pil.x, pil.y), (px + far[0], py + far[1]))

block:
  ## A RADIUS-0 BROADCAST IS FREE AND IS NOT COUNTED AS A MESSAGE, because a
  ## radius of 0 reaches nobody: `d <= 0` only holds for the sender's own
  ## square.
  var w = board()
  let castle = w.castleOf(tRed)
  w.fuel[0] = 500
  var a = newAction()
  a.signal = 1234
  a.signalRadius = 0
  check("it is legal", not w.turnOf(castle, a))
  checkEq("it cost nothing", w.fuel[0], 500)
  checkEq("and was not counted", w.stats.radioMessages[0], 0)
  checkEq("but the value IS stored on the robot", castle.signal, 1234)
  checkEq("with radius 0", castle.signalRadius, 0)

block:
  ## READABLE BY EVERY UNIT OF BOTH TEAMS INSIDE THE RADIUS — id, x, y and the
  ## value, but NOT the sender's `team`.
  var w = board()
  let castle = w.castleOf(tRed)
  ## Put a listener of each team at r^2 25 from the castle, well outside
  ## nobody's vision but inside a radius-25 broadcast.
  var mates: seq[Robot]
  var listeners: seq[Robot]
  var placed = 0
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if placed >= 2: break
      if distSq(castle.x, castle.y, x, y) != 25: continue
      if not w.isPassable(x, y) or w.shadowAt(x, y) != 0: continue
      let t = if placed == 0: tRed else: tBlue
      let who = w.createItem(x, y, t, ukPreacher)
      if placed == 0: mates.add who else: listeners.add who
      inc placed
  checkEq("two listeners at r^2 25 were placed", placed, 2)
  let mate = mates[0]
  let foe = listeners[0]
  checkEq("a preacher's vision radius is only 16", visionRadiusOf(ukPreacher),
    16)
  check("so neither can SEE the castle", not mate.canSee(castle.x, castle.y))
  ## Before the broadcast: neither hears anything.
  let quietFoe = w.seenBy(foe, castle.id)
  checkEq("with no broadcast the enemy sees nothing of the castle",
    quietFoe.id, -1)
  ## Now broadcast at exactly r^2 25.
  w.fuel[0] = 1000
  var a = newAction()
  a.signal = 4095
  a.signalRadius = 25
  check("the broadcast is legal", not w.turnOf(castle, a))
  let heardFoe = w.seenBy(foe, castle.id)
  checkEq("the ENEMY hears it", heardFoe.signal, 4095)
  checkEq("with the radius", heardFoe.signalRadius, 25)
  check("and learns the sender's POSITION", heardFoe.hasPos)
  checkEq("which is the castle's", (heardFoe.x, heardFoe.y),
    (castle.x, castle.y))
  check("and the sender's id is the castle's", heardFoe.id == castle.id)
  check("but NOT the sender's TEAM", not heardFoe.hasTeam)
  check("nor its UNIT TYPE", not heardFoe.hasUnit)
  check("nor its castle talk", not heardFoe.hasCastleTalk)
  let heardMate = w.seenBy(mate, castle.id)
  checkEq("the FRIENDLY hears the same value", heardMate.signal, 4095)
  check("and is told no more about the team than the enemy is",
    not heardMate.hasTeam)
  ## One square further out is silent.
  var outside: Robot = nil
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if not outside.isNil: break
      if distSq(castle.x, castle.y, x, y) != 26: continue
      if not w.isPassable(x, y) or w.shadowAt(x, y) != 0: continue
      outside = w.createItem(x, y, tBlue, ukPreacher)
  if not outside.isNil:
    checkEq("a listener at r^2 26 hears NOTHING",
      w.seenBy(outside, castle.id).id, -1)

block:
  ## A ROBOT THAT BROADCASTS NOTHING CLEARS LAST TURN'S BROADCAST. A signal is
  ## audible from the end of the sender's turn until the end of its NEXT turn.
  var w = board()
  let castle = w.castleOf(tRed)
  var foe: Robot = nil
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if not foe.isNil: break
      if distSq(castle.x, castle.y, x, y) != 25: continue
      if not w.isPassable(x, y) or w.shadowAt(x, y) != 0: continue
      ## A PREACHER, whose vision radius is 16: at r^2 25 it cannot SEE the
      ## castle, so the radio is the only channel that reaches it.
      foe = w.createItem(x, y, tBlue, ukPreacher)
  check("a distant enemy listener exists", not foe.isNil)
  w.fuel[0] = 1000
  var loud = newAction()
  loud.signal = 999
  loud.signalRadius = 25
  discard w.turnOf(castle, loud)
  checkEq("the broadcast is audible", w.seenBy(foe, castle.id).signal, 999)
  ## The next turn the castle says nothing at all.
  discard w.turnOf(castle, newAction())
  checkEq("and the SILENT next turn CLEARS it", castle.signal, 0)
  checkEq("with the radius cleared too", castle.signalRadius, 0)
  checkEq("so the listener hears nothing", w.seenBy(foe, castle.id).id, -1)

block:
  ## AN UNAFFORDABLE BROADCAST, both sides of it.
  ##
  ## (a) At the ENGINE level it THROWS (`:838`), and because the signal step
  ##     runs FIRST the throw aborts the rest of validation: the action is
  ##     lost with it.
  var w = board()
  let castle = w.castleOf(tRed)
  let (px, py) = freeSquareNear(w, castle.x, castle.y, 1)
  let pil = w.createItem(px, py, tRed, ukPilgrim)
  w.fuel[0] = 3                      ## radius 100 costs 10
  var a = newAction()
  a.signal = 5
  a.signalRadius = 100
  a.hasAction = true
  a.kind = akMine
  let (rec, threw) = w.validate(pil, a)
  check("the unaffordable broadcast throws", threw)
  checkEq("nothing was recorded for the signal", rec.signalRadius, 0)
  checkEq("and THE ACTION WENT WITH IT", rec.action, akNothing)
  checkEq("the fuel was not touched", w.fuel[0], 3)
  ##
  ## (b) At the CHASSIS level the guard is upstream: `radioFor` costs the
  ##     radius it wants and RETURNS RADIUS 0 rather than emit something the
  ##     team cannot pay for, so the chassis never loses its action to a
  ##     broadcast.
  checkEq("signalCost(100) is 10", signalCost(100), 10)
  ## `radioFor` needs a Side; the survival and baseline shards drive the whole
  ## chassis. Here the guard's arithmetic is pinned directly: the chassis
  ## compares against `fuel - fuelGate()`, so a team at the gate broadcasts
  ## nothing at all.
  check("the chassis guard is a strict comparison against the reserve",
    signalCost(100) > 3 - 0)

block:
  ## CASTLE TALK: 8 BITS, FREE, UNLIMITED RANGE, CASTLE-ONLY READERS.
  checkEq("CASTLE_TALK_BITS is 8", CastleTalkBits, 8)
  checkEq("so the domain is 0 .. 255", 1 shl CastleTalkBits, 256)
  var w = board()
  let castle = w.castleOf(tRed)
  let (px, py) = freeSquareNear(w, castle.x, castle.y, 1)
  let pil = w.createItem(px, py, tRed, ukPilgrim)
  w.fuel[0] = 1000
  for (v, legal) in [(0, true), (255, true), (256, false), (-1, false),
                     (128, true)]:
    var a = newAction()
    a.castleTalk = v
    let (rec, threw) = w.validate(pil, a)
    checkEq("castle talk " & $v & " legality", not threw, legal)
    if legal: checkEq("  recorded", rec.castleTalk, v)
  ## Free: a castle-talk-only turn costs nothing.
  let before = w.fuel[0]
  var talk = newAction()
  talk.castleTalk = 77
  check("a castle-talk-only turn is legal and complete",
    not w.turnOf(pil, talk))
  checkEq("and costs NOTHING", w.fuel[0], before)
  checkEq("but is counted", w.stats.castleTalks[0], 1)
  checkEq("and the value is stored", pil.castleTalk, 77)
  ## UNLIMITED RANGE: read by the team's castle wherever it is.
  let seenByCastle = w.seenBy(castle, pil.id)
  check("its own castle can read it", seenByCastle.hasCastleTalk)
  checkEq("and reads the value", seenByCastle.castleTalk, 77)
  ## Move the pilgrim to the far corner: still readable.
  var farX, farY = -1
  for y in countdown(w.height - 1, 0):
    for x in countdown(w.width - 1, 0):
      if farX < 0 and w.isPassable(x, y) and w.shadowAt(x, y) == 0 and
          distSq(castle.x, castle.y, x, y) > visionRadiusOf(ukCastle):
        farX = x
        farY = y
  check("a square outside the castle's vision exists", farX >= 0)
  w.setShadow(pil.x, pil.y, 0)
  pil.x = farX
  pil.y = farY
  w.setShadow(farX, farY, pil.id)
  check("the pilgrim is now invisible to its castle",
    not castle.canSee(pil.x, pil.y))
  let stillHeard = w.seenBy(castle, pil.id)
  check("but its castle talk is STILL readable", stillHeard.hasCastleTalk)
  checkEq("with the same value", stillHeard.castleTalk, 77)

block:
  ## CASTLE TALK IS READABLE ONLY BY A CASTLE OF THE SAME TEAM. Not by a
  ## church, not by any mobile unit, and not by the enemy's castle.
  var w = board()
  let castle = w.castleOf(tRed)
  let (px, py) = freeSquareNear(w, castle.x, castle.y, 1)
  let pil = w.createItem(px, py, tRed, ukPilgrim)
  pil.castleTalk = 200
  ## A friendly CHURCH standing right next to it cannot read it.
  let (cx, cy) = freeSquareNear(w, pil.x, pil.y, 1)
  check("a square next to the pilgrim exists", cx >= 0)
  let church = w.createItem(cx, cy, tRed, ukChurch)
  check("a CHURCH cannot read castle talk",
    not w.seenBy(church, pil.id).hasCastleTalk)
  check("but it CAN see the pilgrim", w.seenBy(church, pil.id).hasUnit)
  ## A friendly mobile unit cannot either.
  let (mx, my) = freeSquareNear(w, church.x, church.y, 1)
  if mx >= 0:
    let mate = w.createItem(mx, my, tRed, ukProphet)
    check("nor a friendly PROPHET",
      not w.seenBy(mate, pil.id).hasCastleTalk)
  ## And the ENEMY's castle, which can see the whole board's own team, cannot.
  let blue = w.castleOf(tBlue)
  check("a blue castle exists", not blue.isNil)
  checkEq("the enemy castle does not even have an entry for it",
    w.seenBy(blue, pil.id).id, -1)

block:
  ## A CASTLE SEES THE `team`, `id` AND `turn` OF EVERY FRIENDLY UNIT ON THE
  ## BOARD, regardless of distance — and NOTHING about a distant enemy.
  var w = board()
  let castle = w.castleOf(tRed)
  var farX, farY = -1
  for y in countdown(w.height - 1, 0):
    for x in countdown(w.width - 1, 0):
      if farX < 0 and w.isPassable(x, y) and w.shadowAt(x, y) == 0 and
          distSq(castle.x, castle.y, x, y) > visionRadiusOf(ukCastle):
        farX = x
        farY = y
  check("a far square exists", farX >= 0)
  let mate = w.createItem(farX, farY, tRed, ukCrusader)
  mate.turn = 37
  let e = w.seenBy(castle, mate.id)
  checkEq("the castle has an entry for its distant friendly", e.id, mate.id)
  check("and knows its TEAM", e.hasTeam)
  checkEq("which is its own", e.team, tRed)
  checkEq("and its TURN counter", e.turn, 37)
  check("but NOT its position", not e.hasPos)
  check("nor its unit type", not e.hasUnit)
  checkEq("and its signal reads as absent", e.signal, -1)
  ## The same square, enemy team: no entry at all.
  var w2 = board()
  let castle2 = w2.castleOf(tRed)
  let foe = w2.createItem(farX, farY, tBlue, ukCrusader)
  checkEq("a distant ENEMY is invisible to a castle",
    w2.seenBy(castle2, foe.id).id, -1)

block:
  ## SELF is always fully visible, including the three fields
  ## `getGameStateDump` deletes for everyone else.
  var w = board()
  let castle = w.castleOf(tRed)
  castle.karbonite = 0
  castle.fuel = 0
  let me = w.seenBy(castle, castle.id)
  check("the entry is flagged self", me.isSelf)
  checkEq("with health", me.health, castle.health)
  check("and position", me.hasPos)
  check("and unit type", me.hasUnit)
  check("and team", me.hasTeam)

block:
  ## THE CHASSIS' OWN CODECS. The RADIO codec is a true bijection on its
  ## whole domain: `kind:3 | x:6 | y:6 | flag:1` is sixteen bits exactly, so
  ## every field round-trips and every value is a legal `signal`.
  for kind in 0 .. 7:
    for x in 0 .. 63:
      for y in 0 .. 63:
        for flag in 0 .. 1:
          let v = encodeRadio(kind, x, y, flag)
          check("radio value is 16-bit", v >= 0 and v < 65536)
          checkEq("kind round-trips", radioKind(v), kind)
          checkEq("x round-trips", radioX(v), x)
          checkEq("y round-trips", radioY(v), y)
          checkEq("flag round-trips", radioFlag(v), flag)
  ## CASTLE TALK's three layouts are the design note's own field widths
  ## (`0b10 | x:6`, `0b11 | y:6`, `0b0 | unit:3 | bucket:4`,
  ## `0b01 | alert:6`), and every one of them fits in the channel's eight
  ## bits. They are NOT a partition -- a census digit whose unit ordinal has
  ## bit 2 set occupies the alert tag's space -- and they do not need to be:
  ## in this port castle talk is EMIT-ONLY. A castle's knowledge of its own
  ## team comes from the per-team `Side` controller, which is exactly what
  ## the engine's own "a castle reads every own-team unit's castle talk at
  ## any range" visibility makes equivalent (docs/RULES-BC19.md).
  for axis in 0 .. 1:
    for v in 0 .. 63:
      let e = encodeCastleTalkPosition(axis, v)
      check("castle-talk position is 8-bit", e >= 0 and e < 256)
      checkEq("with the 0b1 tag", e shr 7, 1)
      checkEq("the axis bit", (e shr 6) and 1, axis)
      checkEq("and the coordinate", e and 63, v)
  for alert in 0 .. 63:
    let e = encodeCastleTalkAlert(alert)
    check("castle-talk alert is 8-bit", e >= 0 and e < 256)
    checkEq("with the 0b01 tag", e shr 6, 1)
    checkEq("and the payload", e and 63, alert)
  for unit in 0 .. 5:
    for bucket in 0 .. 15:
      let e = encodeCastleTalkCensus(unit, bucket)
      check("castle-talk census is 8-bit", e >= 0 and e < 256)
      checkEq("with the unit field", (e shr 4) and 7, unit)
      checkEq("and the bucket", e and 15, bucket)

finish("test_bc19_comms")
