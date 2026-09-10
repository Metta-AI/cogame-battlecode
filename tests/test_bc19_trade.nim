## THE CASTLE BARTER, the one mechanic in this year that couples the two
## teams' stores directly. `action_record.js:228-247`.
##
## The sign convention is the engine's and it is easy to get backwards:
## **POSITIVE MEANS THE RESOURCE MOVES RED TO BLUE.** Red's store goes down
## by the offer and blue's up by it, for BOTH resources, whichever castle
## proposed it.
##
## Two quirks, both reproduced:
##
##   * `last_offer` starts at `[[0,0],[0,0]]`, so THE FIRST CASTLE TO OFFER
##     `(0,0)` "matches" the other side's phantom standing offer and executes
##     a zero trade;
##   * a matching pair that is NOT PAYABLE clears BOTH standing offers and
##     THEN throws, so the offers are gone and nothing moved.

import harness
import battlecode/years/bc19/rules

proc board(name = "seed-0043", rounds = 1000): World =
  newWorld(loadMap(name), rounds)

proc castleOf(w: World, t: Team): Robot =
  for r in w.robots:
    if r.team == t and r.unit == ukCastle: return r
  nil

proc validate(w: World, r: Robot, a: Action): (ActionRecord, bool) =
  var rec = newRecord()
  var threw = false
  r.chessOps += ChessExtraOps
  try:
    w.processAction(r, a, rec)
  except CatchableError:
    threw = true
  (rec, threw)

proc offer(w: World, r: Robot, k, f: int): bool =
  ## Enacts the trade directly and reports whether it threw.
  try:
    w.enactTrade(r, k, f)
    false
  except CatchableError:
    true

block:
  ## VALIDATION: CASTLE ONLY, and `trade` returns BEFORE the `dx`/`dy` gate,
  ## so it needs no direction at all.
  var w = board()
  let red = w.castleOf(tRed)
  check("a red castle exists", not red.isNil)
  let (rec, threw) = w.validate(red, tradeAction(5, -7))
  check("a castle's trade validates", not threw)
  checkEq("and is recorded as a trade", rec.action, akTrade)
  checkEq("with its karbonite offer", rec.tradeK, 5)
  checkEq("and its fuel offer", rec.tradeF, -7)
  checkEq("and NO dx/dy at all", rec.dx * rec.dx + rec.dy * rec.dy, 0)
  ## Every other unit is refused.
  var placed = 0
  for u in [ukChurch, ukPilgrim, ukCrusader, ukProphet, ukPreacher]:
    var who: Robot = nil
    for dy in -2 .. 2:
      for dx in -2 .. 2:
        if who.isNil and w.isPassable(red.x + dx, red.y + dy) and
            w.shadowAt(red.x + dx, red.y + dy) == 0:
          who = w.createItem(red.x + dx, red.y + dy, tRed, u)
    if who.isNil: continue
    inc placed
    let (_, no) = w.validate(who, tradeAction(1, 1))
    check("ONLY A CASTLE MAY TRADE: " & unitName(u) & " is refused", no)
  checkEq("all five non-castle units were tried", placed, 5)

block:
  ## `|offer| < 1024`, on BOTH resources, at the boundary.
  checkEq("MaxTrade is 1024", MaxTrade, 1024)
  var w = board()
  let red = w.castleOf(tRed)
  let (_, ok1) = w.validate(red, tradeAction(1023, -1023))
  check("1023 is legal", not ok1)
  let (_, no1) = w.validate(red, tradeAction(1024, 0))
  check("1024 karbonite is refused", no1)
  let (_, no2) = w.validate(red, tradeAction(0, 1024))
  check("1024 fuel is refused", no2)
  let (_, no3) = w.validate(red, tradeAction(-1024, 0))
  check("-1024 karbonite is refused", no3)
  let (_, no4) = w.validate(red, tradeAction(0, -1024))
  check("-1024 fuel is refused", no4)
  let (_, ok2) = w.validate(red, tradeAction(-1023, 1023))
  check("-1023 is legal", not ok2)

block:
  ## THE INITIAL `[[0,0],[0,0]]` QUIRK: the very first `(0,0)` proposal
  ## matches the phantom standing offer and EXECUTES a zero trade.
  var w = board()
  let red = w.castleOf(tRed)
  checkEq("last_offer starts at [[0,0],[0,0]]", w.lastOffer,
    [[0, 0], [0, 0]])
  let before = (w.karbonite[0], w.karbonite[1], w.fuel[0], w.fuel[1])
  check("the zero trade does not throw", not w.offer(red, 0, 0))
  checkEq("both offers were cleared", w.lastOffer, [[0, 0], [0, 0]])
  checkEq("it counted as a proposal", w.stats.tradesProposed[0], 1)
  checkEq("AND as an execution for red", w.stats.tradesExecuted[0], 1)
  checkEq("and for blue", w.stats.tradesExecuted[1], 1)
  checkEq("but nothing moved",
    (w.karbonite[0], w.karbonite[1], w.fuel[0], w.fuel[1]), before)
  checkEq("and the net is zero", w.stats.tradeKarboniteNet[0], 0)

block:
  ## AN UNMATCHED OFFER LEAVES BOTH STANDING. Red offers, blue offers
  ## something else, nothing executes and both offers are on the table.
  var w = board()
  let red = w.castleOf(tRed)
  let blue = w.castleOf(tBlue)
  check("a blue castle exists", not blue.isNil)
  let before = (w.karbonite[0], w.karbonite[1])
  check("red's offer stands", not w.offer(red, 10, 20))
  checkEq("red's slot holds it", w.lastOffer[0], [10, 20])
  checkEq("blue's slot is still the phantom", w.lastOffer[1], [0, 0])
  checkEq("nothing executed yet", w.stats.tradesExecuted[0], 0)
  check("blue's DIFFERENT offer also stands", not w.offer(blue, 11, 20))
  checkEq("and both are on the table", w.lastOffer, [[10, 20], [11, 20]])
  checkEq("still nothing executed", w.stats.tradesExecuted[0], 0)
  checkEq("and the stores did not move", (w.karbonite[0], w.karbonite[1]),
    before)
  checkEq("two proposals from red's side", w.stats.tradesProposed[0], 1)
  checkEq("and one from blue's", w.stats.tradesProposed[1], 1)

block:
  ## A MATCHING PAIR CLEARS BOTH OFFERS AND THEN EXECUTES.
  ## THE SIGN CONVENTION: positive = RED -> BLUE.
  var w = board()
  let red = w.castleOf(tRed)
  let blue = w.castleOf(tBlue)
  discard w.offer(red, 30, 40)
  checkEq("red proposed 30 karbonite / 40 fuel", w.lastOffer[0], [30, 40])
  let k0 = [w.karbonite[0], w.karbonite[1]]
  let f0 = [w.fuel[0], w.fuel[1]]
  check("blue's matching proposal executes", not w.offer(blue, 30, 40))
  checkEq("BOTH offers were cleared FIRST", w.lastOffer, [[0, 0], [0, 0]])
  checkEq("RED LOST 30 karbonite", w.karbonite[0], k0[0] - 30)
  checkEq("BLUE GAINED 30 karbonite", w.karbonite[1], k0[1] + 30)
  checkEq("RED LOST 40 fuel", w.fuel[0], f0[0] - 40)
  checkEq("BLUE GAINED 40 fuel", w.fuel[1], f0[1] + 40)
  checkEq("the net is signed from red's side",
    w.stats.tradeKarboniteNet[0], -30)
  checkEq("and mirrored on blue's", w.stats.tradeKarboniteNet[1], 30)
  checkEq("fuel too", w.stats.tradeFuelNet[0], -40)
  checkEq("and mirrored", w.stats.tradeFuelNet[1], 40)
  checkEq("both sides count the execution", w.stats.tradesExecuted, [1, 1])

block:
  ## A NEGATIVE OFFER RUNS THE OTHER WAY: blue pays red.
  var w = board()
  let red = w.castleOf(tRed)
  let blue = w.castleOf(tBlue)
  discard w.offer(blue, -25, -50)
  let k0 = [w.karbonite[0], w.karbonite[1]]
  let f0 = [w.fuel[0], w.fuel[1]]
  check("red's matching negative offer executes", not w.offer(red, -25, -50))
  checkEq("RED GAINED 25 karbonite", w.karbonite[0], k0[0] + 25)
  checkEq("BLUE LOST 25 karbonite", w.karbonite[1], k0[1] - 25)
  checkEq("RED GAINED 50 fuel", w.fuel[0], f0[0] + 50)
  checkEq("BLUE LOST 50 fuel", w.fuel[1], f0[1] - 50)

block:
  ## A MIXED OFFER: karbonite one way, fuel the other. Both legs run.
  var w = board()
  let red = w.castleOf(tRed)
  let blue = w.castleOf(tBlue)
  discard w.offer(red, 20, -100)
  let k0 = [w.karbonite[0], w.karbonite[1]]
  let f0 = [w.fuel[0], w.fuel[1]]
  check("the mixed pair executes", not w.offer(blue, 20, -100))
  checkEq("red sold 20 karbonite", w.karbonite[0], k0[0] - 20)
  checkEq("and bought 100 fuel", w.fuel[0], f0[0] + 100)
  checkEq("blue bought 20 karbonite", w.karbonite[1], k0[1] + 20)
  checkEq("and sold 100 fuel", w.fuel[1], f0[1] - 100)

block:
  ## THE REPRODUCED QUIRK: A MATCHING PAIR THAT IS NOT PAYABLE CLEARS BOTH
  ## OFFERS AND THEN THROWS. The offers are gone AND nothing moved.
  var w = board()
  let red = w.castleOf(tRed)
  let blue = w.castleOf(tBlue)
  w.karbonite[0] = 5                 ## red cannot pay 900
  discard w.offer(red, 900, 0)
  checkEq("red's unpayable offer stands", w.lastOffer[0], [900, 0])
  let k0 = [w.karbonite[0], w.karbonite[1]]
  let f0 = [w.fuel[0], w.fuel[1]]
  check("blue's matching offer THROWS", w.offer(blue, 900, 0))
  checkEq("but BOTH offers were cleared anyway", w.lastOffer,
    [[0, 0], [0, 0]])
  checkEq("red's karbonite did not move", w.karbonite[0], k0[0])
  checkEq("blue's did not either", w.karbonite[1], k0[1])
  checkEq("nor any fuel", [w.fuel[0], w.fuel[1]], f0)
  checkEq("nothing was counted as executed", w.stats.tradesExecuted, [0, 0])
  checkEq("but both proposals were counted",
    [w.stats.tradesProposed[0], w.stats.tradesProposed[1]], [1, 1])
  ## And the table is now empty, so the next `(0,0)` matches the phantom
  ## again — the quirk composes with itself.
  check("a fresh zero trade matches immediately",
    not w.offer(red, 0, 0))
  checkEq("and executes", w.stats.tradesExecuted, [1, 1])

block:
  ## PAYABILITY IS TESTED ON BOTH SIDES OF BOTH LEGS. An offer red can pay
  ## but blue cannot receive-and-pay throws too.
  var w = board()
  let red = w.castleOf(tRed)
  let blue = w.castleOf(tBlue)
  w.fuel[1] = 10                     ## blue cannot pay 400 fuel
  discard w.offer(red, 0, -400)      ## blue -> red, 400 fuel
  check("the unpayable-by-blue pair throws", w.offer(blue, 0, -400))
  checkEq("and moved nothing", w.fuel[1], 10)
  ## Exactly payable is payable.
  var w2 = board()
  let red2 = w2.castleOf(tRed)
  let blue2 = w2.castleOf(tBlue)
  w2.karbonite[0] = 60
  discard w2.offer(red2, 60, 0)
  check("an exactly-affordable trade executes", not w2.offer(blue2, 60, 0))
  checkEq("and empties red's karbonite", w2.karbonite[0], 0)

block:
  ## A CASTLE MAY REPLACE ITS OWN STANDING OFFER, and only the LAST one
  ## counts.
  var w = board()
  let red = w.castleOf(tRed)
  let blue = w.castleOf(tBlue)
  discard w.offer(red, 1, 1)
  discard w.offer(red, 2, 2)
  checkEq("only the last offer stands", w.lastOffer[0], [2, 2])
  check("the stale offer no longer matches", not w.offer(blue, 1, 1))
  checkEq("nothing executed", w.stats.tradesExecuted[0], 0)
  checkEq("and both sides now stand", w.lastOffer, [[2, 2], [1, 1]])
  check("the live offer matches", not w.offer(blue, 2, 2))
  checkEq("and executes", w.stats.tradesExecuted[0], 1)

block:
  ## TWO CASTLES OF THE SAME TEAM SHARE ONE SLOT: the second overwrites the
  ## first, because `last_offer` is indexed by TEAM, not by castle.
  var w = board("seed-0043")
  var reds: seq[Robot]
  for r in w.robots:
    if r.team == tRed and r.unit == ukCastle: reds.add r
  check("seed-0043 has at least two red castles", reds.len >= 2)
  discard w.offer(reds[0], 3, 4)
  discard w.offer(reds[1], 5, 6)
  checkEq("the team slot holds the SECOND castle's offer",
    w.lastOffer[0], [5, 6])
  checkEq("and both proposals were counted", w.stats.tradesProposed[0], 2)

block:
  ## THE BEAT: emitted on the round the pair matches, with the payability
  ## flag, and bounded.
  var w = board()
  w.round = 42
  let red = w.castleOf(tRed)
  let blue = w.castleOf(tBlue)
  discard w.offer(red, 12, 34)
  checkEq("a standing offer emits nothing", w.events.len, 0)
  discard w.offer(blue, 12, 34)
  checkEq("a match emits one beat", w.events.len, 1)
  checkEq("named trade", w.events[0].kind, "trade")
  checkEq("carrying the karbonite leg", w.events[0].a, 12)
  checkEq("and the fuel leg", w.events[0].b, 34)
  checkEq("and the payable flag", w.events[0].c, 1)
  checkEq("on the round it happened", w.events[0].round, 42)
  ## An unpayable match also beats, with the flag clear.
  w.karbonite[0] = 0
  discard w.offer(red, 999, 0)
  discard w.offer(blue, 999, 0)
  checkEq("an unpayable match beats too", w.events.len, 2)
  checkEq("with the flag clear", w.events[1].c, 0)

finish("test_bc19_trade")
