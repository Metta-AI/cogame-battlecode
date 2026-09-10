## `processAction`'s VALIDATION LADDER, in the engine's own order — the
## easiest thing in this year to get wrong.
##
## **EVERY "throw" ABORTS THE REST OF VALIDATION AND LEAVES THE RECORD AS IT
## STANDS.** `enactTurn` catches it and then enacts the record anyway, so an
## illegal `move` STILL PERFORMS the signal and the castle talk that were
## validated before it.
##
## **`temp_fuel` IS NOT THE TEAM'S FUEL.** The signal step computes
## `temp_fuel = fuel - ceil(sqrt(radius))` and EVERY LATER AFFORDABILITY
## TEST IN THE TURN READS IT, while the BUILD's karbonite test reads the
## real store. Reproducing that asymmetry is the difference between a
## bit-exact port and a plausible one.

import harness
import battlecode/years/bc19/rules

proc board(name = "seed-0043", rounds = 1000): World =
  newWorld(loadMap(name), rounds)

proc run(w: World, r: Robot, a: Action): (ActionRecord, bool) =
  var rec = newRecord()
  var threw = false
  r.chessOps += ChessExtraOps
  try:
    w.processAction(r, a, rec)
  except CatchableError:
    threw = true
  (rec, threw)

proc freeNear(w: World, r: Robot): (int, int) =
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if w.isPassable(r.x + dx, r.y + dy) and
          w.shadowAt(r.x + dx, r.y + dy) == 0:
        return (dx, dy)
  (0, 0)

block:
  ## A SIGNAL VALIDATED BEFORE THE ACTION, so an ILLEGAL MOVE STILL
  ## BROADCASTS.
  var w = board()
  let castle = w.robots[0]
  var a = moveAction(1, 0)            ## a CASTLE has SPEED 0
  a.signal = 4242
  a.signalRadius = 9
  a.castleTalk = 200
  let (rec, threw) = run(w, castle, a)
  check("the illegal move threw", threw)
  checkEq("but the SIGNAL still landed", rec.signal, 4242)
  checkEq("with its radius", rec.signalRadius, 9)
  checkEq("and the CASTLE TALK too", rec.castleTalk, 200)
  checkEq("while the action itself is NOTHING", rec.action, akNothing)

block:
  ## `temp_fuel` IS HANDED FROM THE SIGNAL STEP TO EVERY LATER
  ## AFFORDABILITY TEST. A signal that eats the fuel a move needed refuses
  ## the move, even though the team's real store would have covered it.
  var w = board()
  ## Give a pilgrim a square and exactly enough fuel for one r2-1 move.
  let castle = w.robots[0]
  let (dx, dy) = freeNear(w, castle)
  let pil = w.createItem(castle.x + dx, castle.y + dy, castle.team, ukPilgrim)
  w.fuel[ord(pil.team)] = 5
  var (mx, my) = (0, 0)
  for ddy in -1 .. 1:
    for ddx in -1 .. 1:
      if (ddx == 0 and ddy == 0) or (mx != 0 or my != 0): continue
      if w.isPassable(pil.x + ddx, pil.y + ddy) and
          w.shadowAt(pil.x + ddx, pil.y + ddy) == 0 and
          ddx * ddx + ddy * ddy == 1:
        mx = ddx
        my = ddy
  check("the pilgrim has a free orthogonal neighbour", mx != 0 or my != 0)
  var plain = moveAction(mx, my)
  let (rec1, threw1) = run(w, pil, plain)
  check("with 5 fuel the r2-1 move is legal", not threw1)
  checkEq("and it is a MOVE", rec1.action, akMove)
  ## Now the same move behind a broadcast whose cost eats the difference.
  var withSignal = moveAction(mx, my)
  withSignal.signal = 1
  withSignal.signalRadius = 25          ## ceil(sqrt(25)) = 5 fuel
  let (rec2, threw2) = run(w, pil, withSignal)
  check("BUT behind a 5-fuel broadcast the SAME move is refused", threw2)
  checkEq("and the broadcast still landed", rec2.signal, 1)
  checkEq("while the move did not", rec2.action, akNothing)

block:
  ## The signal's own bounds, and its cost.
  var w = board()
  let castle = w.robots[0]
  var a = newAction()
  a.signal = 1 shl CommunicationBits          ## 65536 -- one past the top
  let (_, threw) = run(w, castle, a)
  check("a 17-bit signal value is refused", threw)
  var b = newAction()
  b.signalRadius = MaxSignalRadius + 1
  let (_, threw2) = run(w, castle, b)
  check("a radius past 2*(64-1)^2 is refused", threw2)
  var c = newAction()
  c.signal = 65535
  c.signalRadius = MaxSignalRadius
  let (rec3, threw3) = run(w, castle, c)
  check("the maximum legal pair is accepted", not threw3)
  checkEq("and its radius is recorded", rec3.signalRadius, MaxSignalRadius)
  w.fuel[ord(castle.team)] = 10               ## the cost is 90
  let (_, threw4) = run(w, castle, c)
  check("but not when the team cannot pay the 90 fuel", threw4)

block:
  ## CASTLE TALK: 8 bits, FREE, and available to EVERY unit including a
  ## structure. A castle-talk-only turn is legal and complete.
  var w = board()
  let castle = w.robots[0]
  var a = newAction()
  a.castleTalk = 255
  let (rec, threw) = run(w, castle, a)
  check("255 is legal", not threw)
  checkEq("and recorded", rec.castleTalk, 255)
  checkEq("and the turn is complete with no action", rec.action, akNothing)
  var b = newAction()
  b.castleTalk = 256
  let (_, threw2) = run(w, castle, b)
  check("256 is refused", threw2)

block:
  ## `trade` and `mine` RETURN BEFORE THE dx/dy GATE — a trade needs no
  ## `dx`/`dy` at all.
  var w = board()
  let castle = w.robots[0]
  let (rec, threw) = run(w, castle, tradeAction(10, -50))
  check("a castle's trade with no dx/dy is legal", not threw)
  checkEq("and is recorded", rec.action, akTrade)
  checkEq("with its karbonite", rec.tradeK, 10)
  checkEq("and its fuel", rec.tradeF, -50)
  let (_, tooBig) = run(w, castle, tradeAction(MaxTrade, 0))
  check("|offer| must be under MAX_TRADE", tooBig)
  let (dx, dy) = freeNear(w, castle)
  let pil = w.createItem(castle.x + dx, castle.y + dy, castle.team, ukPilgrim)
  let (_, notCastle) = run(w, pil, tradeAction(1, 1))
  check("and ONLY a CASTLE can trade", notCastle)
  ## `mine` likewise returns early, and the engine does NOT check here that
  ## the pilgrim is on a depot or under capacity: both are enact-time.
  let (recM, threwM) = run(w, pil, mineAction())
  check("a pilgrim's `mine` validates with no dx/dy and no depot test",
    not threwM)
  checkEq("and is recorded", recM.action, akMine)
  let (_, castleMine) = run(w, castle, mineAction())
  check("and ONLY a PILGRIM can mine", castleMine)
  w.fuel[ord(pil.team)] = 0
  let (_, poorMine) = run(w, pil, mineAction())
  check("and it needs the 1 fuel", poorMine)

block:
  ## THE dx/dy GATE: both integers, NOT BOTH ZERO, |d| < 64, and the
  ## destination ON THE BOARD.
  var w = board()
  let castle = w.robots[0]
  let (_, zero) = run(w, castle, attackAction(0, 0))
  check("dx == dy == 0 is refused", zero)
  let (_, huge) = run(w, castle, attackAction(MaxBoardSize, 0))
  check("|dx| >= 64 is refused", huge)
  let (_, offBoard) = run(w, castle, attackAction(-castle.x - 1, 0))
  check("and a destination off the board is refused", offBoard)

block:
  ## THE BUILD GUARDS, in the engine's own order.
  var w = board()
  let castle = w.robots[0]
  let (dx, dy) = freeNear(w, castle)
  check("the castle has a free adjacent square", dx != 0 or dy != 0)
  let (recOk, threwOk) = run(w, castle, buildAction(dx, dy, ukPilgrim))
  check("an adjacent, passable, empty, affordable build is legal", not threwOk)
  checkEq("and is recorded", recOk.action, akBuild)
  checkEq("with its unit", recOk.buildUnit, ukPilgrim)
  let (_, far) = run(w, castle, buildAction(2, 0, ukPilgrim))
  check("a build two squares away is refused", far)
  let (_, castleBuild) = run(w, castle, buildAction(dx, dy, ukCastle))
  check("NOBODY MAY EVER BUILD A CASTLE", castleBuild)
  let (_, castleChurch) = run(w, castle, buildAction(dx, dy, ukChurch))
  check("and a non-pilgrim may NEVER build a CHURCH", castleChurch)
  ## Occupy the square and try again.
  let blocker = w.createItem(castle.x + dx, castle.y + dy, castle.team,
    ukPilgrim)
  let (_, occupied) = run(w, castle, buildAction(dx, dy, ukCrusader))
  check("a build onto an OCCUPIED square is refused", occupied)
  ## A pilgrim may build ONLY a church.
  let (dx2, dy2) = freeNear(w, blocker)
  if dx2 != 0 or dy2 != 0:
    let (_, pilCrusader) = run(w, blocker, buildAction(dx2, dy2, ukCrusader))
    check("A PILGRIM MAY BUILD ONLY A CHURCH", pilCrusader)
    let (recCh, threwCh) = run(w, blocker, buildAction(dx2, dy2, ukChurch))
    check("and a church is legal for it", not threwCh)
    checkEq("and recorded", recCh.buildUnit, ukChurch)
  ## Affordability: the karbonite test reads the REAL store.
  w.karbonite[ord(castle.team)] = 1
  let (dx3, dy3) = freeNear(w, castle)
  if dx3 != 0 or dy3 != 0:
    let (_, poor) = run(w, castle, buildAction(dx3, dy3, ukCrusader))
    check("and a build the team cannot afford is refused", poor)
  ## V4: THE GUARD THE ENGINE LACKS. At 4095 spent ids the build is REFUSED
  ## rather than looping forever in `createItem`'s rejection loop.
  w.karbonite[ord(castle.team)] = 1000
  w.fuel[ord(castle.team)] = 1000
  for id in 1 .. MaxId - 1:
    if not w.idIsSpent.getOrDefault(id, false):
      w.idsSpent.add(id)
      w.idIsSpent[id] = true
  check("the pool is exhausted", w.idPoolExhausted())
  let before = w.stats.buildsRefused[ord(castle.team)]
  if dx3 != 0 or dy3 != 0:
    let (_, exhausted) = run(w, castle, buildAction(dx3, dy3, ukCrusader))
    check("V4: the build is REFUSED rather than hanging", exhausted)
    checkEq("and it is counted", w.stats.buildsRefused[ord(castle.team)],
      before + 1)

block:
  ## `give`: the destination's TERRAIN is tested even though only an
  ## occupied square can receive, the amounts are 0..255, the giver must
  ## hold them, and THERE IS NO TEAM CHECK.
  var w = board()
  let castle = w.robots[0]
  let (dx, dy) = freeNear(w, castle)
  let pil = w.createItem(castle.x + dx, castle.y + dy, castle.team, ukPilgrim)
  pil.karbonite = 12
  pil.fuel = 40
  let (recOk, threwOk) = run(w, pil, giveAction(-dx, -dy, 12, 40))
  check("a give to an adjacent occupied square is legal", not threwOk)
  checkEq("and recorded", recOk.action, akGive)
  checkEq("with its karbonite", recOk.giveK, 12)
  checkEq("and its fuel", recOk.giveF, 40)
  let (_, tooMuch) = run(w, pil, giveAction(-dx, -dy, 13, 0))
  check("giving more karbonite than you hold is refused", tooMuch)
  let (_, over255) = run(w, pil, giveAction(-dx, -dy, 0, 256))
  check("and an amount over 255 is refused", over255)
  let (_, far) = run(w, pil, giveAction(2, 0, 0, 0))
  check("and a give two squares away is refused", far)
  ## An EMPTY adjacent square passes VALIDATION and throws at ENACT time --
  ## which is exactly why the record still carries GIVE.
  let (dx2, dy2) = freeNear(w, pil)
  if dx2 != 0 or dy2 != 0:
    let (recEmpty, threwEmpty) = run(w, pil, giveAction(dx2, dy2, 0, 0))
    check("a give to an EMPTY square passes validation", not threwEmpty)
    checkEq("and the record carries GIVE", recEmpty.action, akGive)

block:
  ## `move`: `r2 <= SPEED`, the destination passable and UNOCCUPIED, and
  ## affordable at `r2 * FUEL_PER_MOVE`. **THERE IS NO PATH CHECK** — a unit
  ## teleports over rock and over other units within its speed.
  var w = board()
  let castle = w.robots[0]
  let (dx, dy) = freeNear(w, castle)
  let cru = w.createItem(castle.x + dx, castle.y + dy, castle.team,
    ukCrusader)
  ## Find a free square at exactly r2 = 9, the crusader's maximum.
  var found = false
  for ddy in -3 .. 3:
    for ddx in -3 .. 3:
      if found or ddx * ddx + ddy * ddy != 9: continue
      if not w.isPassable(cru.x + ddx, cru.y + ddy): continue
      if w.shadowAt(cru.x + ddx, cru.y + ddy) != 0: continue
      let (rec, threw) = run(w, cru, moveAction(ddx, ddy))
      check("a crusader may move at exactly r2 9", not threw)
      checkEq("and it is recorded", rec.action, akMove)
      found = true
  check("the board offered an r2-9 destination", found)
  ## r2 = 10 is one past the crusader's speed.
  let (_, tooFast) = run(w, cru, moveAction(3, 1))
  check("and never at r2 10", tooFast)
  ## Onto the castle's own square: occupied.
  let (_, onto) = run(w, cru, moveAction(-dx, -dy))
  check("a move onto an occupied square is refused", onto)
  ## And a structure can never move, because r2 >= 1 > 0 == SPEED.
  let (_, castleMove) = run(w, castle, moveAction(1, 0))
  check("a CASTLE can never move", castleMove)

block:
  ## `attack`: NO vision test, NO team check, NO target-exists test, and the
  ## two D6 coercions.
  var w = board()
  let castle = w.robots[0]
  ## An attack on an EMPTY square inside range is LEGAL.
  var found = false
  for ddy in -8 .. 8:
    for ddx in -8 .. 8:
      let r2 = ddx * ddx + ddy * ddy
      if found or r2 != 64: continue
      if not w.onBoard(castle.x + ddx, castle.y + ddy): continue
      let (rec, threw) = run(w, castle, attackAction(ddx, ddy))
      check("a CASTLE attack at exactly r2 64 is legal", not threw)
      checkEq("and recorded even though the square is empty",
        rec.action, akAttack)
      found = true
  check("the board offered an r2-64 target square", found)
  let (dx, dy) = freeNear(w, castle)
  ## D6.2: a PILGRIM attack is a VALIDATION FAILURE.
  let pil = w.createItem(castle.x + dx, castle.y + dy, castle.team, ukPilgrim)
  let (recP, threwP) = run(w, pil, attackAction(1, 0))
  check("D6.2: a PILGRIM attack THROWS", threwP)
  checkEq("and no action is recorded", recP.action, akNothing)
  ## D6.1: a CHURCH attack is ACCEPTED, for 0 fuel and 0 damage, at ANY
  ## on-board range.
  let (dx2, dy2) = freeNear(w, pil)
  if dx2 != 0 or dy2 != 0:
    let church = w.createItem(pil.x + dx2, pil.y + dy2, pil.team, ukChurch)
    for r2dx in [1, 3, 5]:
      if not w.onBoard(church.x + r2dx, church.y): continue
      let (recC, threwC) = run(w, church, attackAction(r2dx, 0))
      check("D6.1: a CHURCH attack at dx=" & $r2dx & " is ACCEPTED",
        not threwC)
      checkEq("and recorded as an ATTACK", recC.action, akAttack)
    w.fuel[ord(church.team)] = 0
    if w.onBoard(church.x + 1, church.y):
      let (_, threwFree) = run(w, church, attackAction(1, 0))
      check("and it costs NOTHING, so it works at zero fuel", not threwFree)

block:
  ## An unaffordable attack is refused, and the PROPHET's MINIMUM range.
  var w = board()
  let castle = w.robots[0]
  let (dx, dy) = freeNear(w, castle)
  let pro = w.createItem(castle.x + dx, castle.y + dy, castle.team, ukProphet)
  var okAt16 = false
  var refusedAt15 = false
  for ddy in -8 .. 8:
    for ddx in -8 .. 8:
      let r2 = ddx * ddx + ddy * ddy
      if not w.onBoard(pro.x + ddx, pro.y + ddy): continue
      if r2 == 16 and not okAt16:
        let (_, threw) = run(w, pro, attackAction(ddx, ddy))
        okAt16 = not threw
      if r2 == 9 and not refusedAt15:
        let (_, threw) = run(w, pro, attackAction(ddx, ddy))
        refusedAt15 = threw
  check("a PROPHET may shoot at exactly r2 16", okAt16)
  check("and is BLIND at r2 9", refusedAt15)
  w.fuel[ord(pro.team)] = 24            ## a prophet's shot costs 25
  var refusedPoor = false
  for ddy in -8 .. 8:
    for ddx in -8 .. 8:
      if ddx * ddx + ddy * ddy != 16: continue
      if not w.onBoard(pro.x + ddx, pro.y + ddy): continue
      if not refusedPoor:
        let (_, threw) = run(w, pro, attackAction(ddx, ddy))
        refusedPoor = threw
  check("and an unaffordable shot is refused", refusedPoor)

finish("test_bc19_actions")
