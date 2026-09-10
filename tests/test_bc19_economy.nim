## THE bc19 ECONOMY. There is exactly ONE passive income in this game and it
## is FLAT: `TRICKLE_FUEL = 25` fuel per team per round, credited at the top
## of every round and NOT SCALED BY STRUCTURES (`game.js:751-752`). Karbonite
## has no passive income at all. Everything else is pilgrim mining, the
## reclaim on a kill and the castle barter.
##
## The two named quirks:
##
##   * `mine` AT CAPACITY still costs the 1 fuel and yields nothing — a
##     wasted turn (`action_record.js:213-225`);
##   * `give` TO A ROBOT reduces the record's own amount FIRST and deducts
##     only the reduced amount, so nothing is lost. `docs.js:260` says "the
##     excess is loss to the void" and is WRONG (docs disagreement 5).

import harness
import battlecode/years/bc19/rules

proc board(name = "seed-0043", rounds = 1000): World =
  newWorld(loadMap(name), rounds)

proc depotOf(w: World, karbonite: bool): (int, int) =
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if (if karbonite: w.hasKarbonite(x, y) else: w.hasFuel(x, y)) and
          w.isPassable(x, y) and w.shadowAt(x, y) == 0:
        return (x, y)
  (-1, -1)

proc plainOf(w: World): (int, int) =
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if w.isPassable(x, y) and w.shadowAt(x, y) == 0 and
          not w.hasKarbonite(x, y) and not w.hasFuel(x, y):
        return (x, y)
  (-1, -1)

block:
  ## THE OPENING CREDIT, once per team, and no more.
  let w = board()
  checkEq("INITIAL_KARBONITE is 100", InitialKarbonite, 100)
  checkEq("INITIAL_FUEL is 500", InitialFuel, 500)
  checkEq("red starts with 100 karbonite", w.karbonite[0], 100)
  checkEq("blue starts with 100 karbonite", w.karbonite[1], 100)
  checkEq("red starts with 500 fuel", w.fuel[0], 500)
  checkEq("blue starts with 500 fuel", w.fuel[1], 500)
  check("and the board has castles to spend it", w.robots.len >= 2)
  ## The credit is in `newWorld`, so it cannot be applied twice: a second
  ## world from the same map has the same stores, not double.
  let w2 = board()
  checkEq("a second world is not double-credited", w2.karbonite[0], 100)

block:
  ## THE TRICKLE: flat, +25 per team per round, unaffected by how many
  ## structures either side owns.
  checkEq("TRICKLE_FUEL is 25", TrickleFuel, 25)
  var w = board()
  let before = [w.fuel[0], w.fuel[1]]
  w.addTrickle()
  checkEq("red gained exactly 25", w.fuel[0] - before[0], 25)
  checkEq("blue gained exactly 25", w.fuel[1] - before[1], 25)
  checkEq("and the counter says so", w.stats.fuelTrickled[0], 25)
  ## Now with five extra churches on red's side and none on blue's.
  let anchor = w.robots[0]
  var built = 0
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if built >= 5: break
      if w.isPassable(x, y) and w.shadowAt(x, y) == 0:
        discard w.createItem(x, y, anchor.team, ukChurch)
        inc built
  checkEq("five churches were placed", built, 5)
  let mid = [w.fuel[0], w.fuel[1]]
  w.addTrickle()
  checkEq("red STILL gains exactly 25", w.fuel[0] - mid[0], 25)
  checkEq("and so does blue", w.fuel[1] - mid[1], 25)
  ## Ten rounds of trickle and nothing else.
  var w3 = board()
  for _ in 1 .. 10: w3.addTrickle()
  checkEq("ten rounds of trickle is 250 fuel", w3.fuel[0], InitialFuel + 250)
  checkEq("and no karbonite at all", w3.karbonite[0], InitialKarbonite)
  checkEq("KARBONITE has no passive income anywhere",
    w3.stats.fuelTrickled[0], 250)

block:
  ## MINING KARBONITE: +2, cap 20, for 1 fuel.
  checkEq("KARBONITE_YIELD is 2", KarboniteYield, 2)
  checkEq("MINE_FUEL_COST is 1", MineFuelCost, 1)
  checkEq("a pilgrim's karbonite capacity is 20",
    karboniteCapacityOf(ukPilgrim), 20)
  var w = board()
  let (kx, ky) = depotOf(w, true)
  check("the board has a free karbonite depot", kx >= 0)
  let pil = w.createItem(kx, ky, tRed, ukPilgrim)
  w.fuel[0] = 100
  w.enactMine(pil)
  checkEq("one mine yields 2 karbonite", pil.karbonite, 2)
  checkEq("and costs 1 team fuel", w.fuel[0], 99)
  checkEq("and is counted", w.stats.mineActions[0], 1)
  checkEq("with the karbonite credited to the mined total",
    w.stats.karboniteMined[0], 2)
  checkEq("and nothing wasted", w.stats.mineActionsWasted[0], 0)
  ## Ten mines fill it exactly.
  for _ in 1 .. 9: w.enactMine(pil)
  checkEq("ten mines fill a pilgrim to 20", pil.karbonite, 20)
  checkEq("for ten fuel", w.fuel[0], 90)
  ## The eleventh BURNS THE FUEL FOR NOTHING.
  w.enactMine(pil)
  checkEq("at capacity the pilgrim gains nothing", pil.karbonite, 20)
  checkEq("but the 1 fuel is still spent", w.fuel[0], 89)
  checkEq("and the turn is counted as WASTED",
    w.stats.mineActionsWasted[0], 1)
  checkEq("while the mined total does not move",
    w.stats.karboniteMined[0], 20)

block:
  ## MINING FUEL: +10, cap 100, for 1 fuel — a NET +9.
  checkEq("FUEL_YIELD is 10", FuelYield, 10)
  checkEq("a pilgrim's fuel capacity is 100", fuelCapacityOf(ukPilgrim), 100)
  var w = board()
  let (fx, fy) = depotOf(w, false)
  check("the board has a free fuel depot", fx >= 0)
  let pil = w.createItem(fx, fy, tRed, ukPilgrim)
  w.fuel[0] = 100
  w.enactMine(pil)
  checkEq("one mine yields 10 fuel to the PILGRIM", pil.fuel, 10)
  checkEq("and costs 1 TEAM fuel", w.fuel[0], 99)
  checkEq("counted as mined fuel", w.stats.fuelMined[0], 10)
  for _ in 1 .. 9: w.enactMine(pil)
  checkEq("ten mines fill it to 100", pil.fuel, 100)
  w.enactMine(pil)
  checkEq("at capacity it gains nothing", pil.fuel, 100)
  checkEq("and the fuel is burnt anyway", w.fuel[0], 89)
  checkEq("and the waste counted", w.stats.mineActionsWasted[0], 1)

block:
  ## KARBONITE BRANCH FIRST. The generator never puts both maps on one square
  ## (`game.js:258,269`), but the port's branch order is the engine's, so a
  ## synthetic both-maps square mines KARBONITE.
  var w = board()
  let (kx, ky) = depotOf(w, true)
  let i = w.idx(kx, ky)
  w.map.fuelMap[i] = true
  check("the synthetic square is on BOTH maps",
    w.hasKarbonite(kx, ky) and w.hasFuel(kx, ky))
  let pil = w.createItem(kx, ky, tRed, ukPilgrim)
  w.enactMine(pil)
  checkEq("the KARBONITE branch wins", pil.karbonite, 2)
  checkEq("and the fuel branch did not run", pil.fuel, 0)

block:
  ## MINE OFF A DEPOT THROWS. The engine deliberately does not check the
  ## square at validation time (rule 4.9), so this is an enact-time throw
  ## that `enactTurn` swallows: a wasted turn and NOTHING ELSE, not even the
  ## 1 fuel.
  var w = board()
  let (px, py) = plainOf(w)
  check("the board has a plain passable square", px >= 0)
  let pil = w.createItem(px, py, tRed, ukPilgrim)
  w.fuel[0] = 100
  var threw = false
  try:
    w.enactMine(pil)
  except CatchableError:
    threw = true
  check("mining off a depot throws", threw)
  checkEq("the pilgrim gained nothing", pil.karbonite + pil.fuel, 0)
  checkEq("and the fuel was NOT spent", w.fuel[0], 100)
  checkEq("and it was not counted as a mine", w.stats.mineActions[0], 0)

block:
  ## `give` TO A ROBOT: the amount is REDUCED FIRST, so nothing is lost.
  ## `docs.js:260` claims the excess is "loss to the void". It is not.
  var w = board()
  let castle = w.robots[0]
  var a, b: Robot = nil
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if a.isNil and w.isPassable(castle.x + dx, castle.y + dy) and
          w.shadowAt(castle.x + dx, castle.y + dy) == 0:
        a = w.createItem(castle.x + dx, castle.y + dy, castle.team, ukPilgrim)
  check("a giver was placed next to the castle", not a.isNil)
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if b.isNil and w.isPassable(a.x + dx, a.y + dy) and
          w.shadowAt(a.x + dx, a.y + dy) == 0:
        b = w.createItem(a.x + dx, a.y + dy, castle.team, ukPilgrim)
  check("and a receiver next to the giver", not b.isNil)
  a.karbonite = 20
  a.fuel = 100
  b.karbonite = 18
  b.fuel = 95
  ## Offer 20 karbonite into 2 spare and 100 fuel into 5 spare.
  w.enactGive(a, b.x - a.x, b.y - a.y, 20, 100)
  checkEq("the receiver filled to capacity", b.karbonite, 20)
  checkEq("for fuel too", b.fuel, 100)
  checkEq("the giver lost ONLY the 2 that arrived", a.karbonite, 18)
  checkEq("and ONLY the 5 that arrived", a.fuel, 95)
  checkEq("so the pair's karbonite is conserved", a.karbonite + b.karbonite,
    20 + 18)
  checkEq("and its fuel is conserved", a.fuel + b.fuel, 100 + 95)
  checkEq("and the give was counted", w.stats.giveActions[0], 1)
  ## A give to a FULL receiver moves nothing at all.
  w.enactGive(a, b.x - a.x, b.y - a.y, 18, 95)
  checkEq("a give to a full receiver moves no karbonite", a.karbonite, 18)
  checkEq("nor any fuel", a.fuel, 95)

block:
  ## `give` TO A STRUCTURE credits the RECEIVER'S TEAM GLOBAL — with NO TEAM
  ## CHECK, so giving to an ENEMY structure funds the enemy. It is legal and
  ## the chassis never does it.
  var w = board()
  let castle = w.robots[0]
  var pil: Robot = nil
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if pil.isNil and w.isPassable(castle.x + dx, castle.y + dy) and
          w.shadowAt(castle.x + dx, castle.y + dy) == 0:
        pil = w.createItem(castle.x + dx, castle.y + dy, castle.team,
                           ukPilgrim)
  check("a pilgrim stands next to its castle", not pil.isNil)
  pil.karbonite = 20
  pil.fuel = 100
  let ownBefore = w.karbonite[ord(castle.team)]
  w.enactGive(pil, castle.x - pil.x, castle.y - pil.y, 20, 100)
  checkEq("the whole load reached the team global",
    w.karbonite[ord(castle.team)], ownBefore + 20)
  checkEq("and it was counted as a deposit",
    w.stats.karboniteDeposited[ord(castle.team)], 20)
  checkEq("fuel too", w.stats.fuelDeposited[ord(castle.team)], 100)
  checkEq("the pilgrim is empty", pil.karbonite + pil.fuel, 0)
  ## A structure has NO capacity clamp: 20 karbonite into a castle is 20,
  ## even though `KARBONITE_CAPACITY` for a castle coerces to 0.
  checkEq("a castle's coerced karbonite capacity is 0",
    karboniteCapacityOf(ukCastle), 0)
  ## And now the enemy version, on a synthetic adjacent enemy church.
  var ex, ey = -1
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if ex < 0 and w.isPassable(pil.x + dx, pil.y + dy) and
          w.shadowAt(pil.x + dx, pil.y + dy) == 0:
        ex = pil.x + dx
        ey = pil.y + dy
  check("a free square next to the pilgrim exists", ex >= 0)
  let foe = if castle.team == tRed: tBlue else: tRed
  discard w.createItem(ex, ey, foe, ukChurch)
  pil.karbonite = 7
  pil.fuel = 40
  let foeBefore = w.karbonite[ord(foe)]
  let foeFuelBefore = w.fuel[ord(foe)]
  let ownDeposited = w.stats.karboniteDeposited[ord(castle.team)]
  w.enactGive(pil, ex - pil.x, ey - pil.y, 7, 40)
  checkEq("giving to an ENEMY structure funds the ENEMY",
    w.karbonite[ord(foe)], foeBefore + 7)
  checkEq("fuel too", w.fuel[ord(foe)], foeFuelBefore + 40)
  checkEq("and it is NOT counted as the giver's deposit",
    w.stats.karboniteDeposited[ord(castle.team)], ownDeposited)
  checkEq("the giver is still emptied", pil.karbonite + pil.fuel, 0)

block:
  ## `give` INTO AN EMPTY SQUARE throws, and nothing moves.
  var w = board()
  let castle = w.robots[0]
  var pil: Robot = nil
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if pil.isNil and w.isPassable(castle.x + dx, castle.y + dy) and
          w.shadowAt(castle.x + dx, castle.y + dy) == 0:
        pil = w.createItem(castle.x + dx, castle.y + dy, castle.team,
                           ukPilgrim)
  pil.karbonite = 9
  var free = (0, 0)
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if free == (0, 0) and w.onBoard(pil.x + dx, pil.y + dy) and
          w.shadowAt(pil.x + dx, pil.y + dy) == 0:
        free = (dx, dy)
  var threw = false
  try:
    w.enactGive(pil, free[0], free[1], 9, 0)
  except CatchableError:
    threw = true
  check("a give into an empty square throws", threw)
  checkEq("and the giver keeps its load", pil.karbonite, 9)

block:
  ## `worth` = karbonite + fuel div 5 + the build karbonite of every live
  ## unit. The exchange rate is the ENGINE'S OWN: one mine buys 2 karbonite
  ## or 10 fuel, so 1 karbonite = 5 fuel at the margin.
  var w = board()
  let castle = w.robots[0]
  let t = castle.team
  ## Strip the board to exactly one castle of `t` so the sum is countable.
  var doomed: seq[Robot]
  for r in w.robots:
    if r.id != castle.id: doomed.add r
  for r in doomed: w.deleteRobot(r)
  checkEq("one robot is left", w.robots.len, 1)
  w.karbonite[ord(t)] = 137
  w.fuel[ord(t)] = 512
  checkEq("a CASTLE contributes 0 to worth", buildKarboniteOf(ukCastle), 0)
  checkEq("worth is karbonite + fuel div 5 with a lone castle",
    w.worthOf(t), 137 + 512 div 5)
  checkEq("and the division truncates", 512 div 5, 102)
  ## Add one of each buildable unit.
  var added: seq[UnitKind]
  for u in [ukPilgrim, ukCrusader, ukProphet, ukPreacher, ukChurch]:
    for dy in -2 .. 2:
      for dx in -2 .. 2:
        if u in added: continue
        if w.isPassable(castle.x + dx, castle.y + dy) and
            w.shadowAt(castle.x + dx, castle.y + dy) == 0:
          discard w.createItem(castle.x + dx, castle.y + dy, t, u)
          added.add u
  checkEq("all five buildables were placed", added.len, 5)
  checkEq("a CHURCH contributes 50", buildKarboniteOf(ukChurch), 50)
  let sumBuild = buildKarboniteOf(ukPilgrim) + buildKarboniteOf(ukCrusader) +
                 buildKarboniteOf(ukProphet) + buildKarboniteOf(ukPreacher) +
                 buildKarboniteOf(ukChurch)
  checkEq("the five sum to 10+15+25+30+50", sumBuild, 130)
  checkEq("worth now includes every live unit's build karbonite",
    w.worthOf(t), 137 + 102 + 130)
  ## And a death removes its contribution.
  var victim: Robot = nil
  for r in w.robots:
    if r.unit == ukPreacher: victim = r
  check("the preacher is findable", not victim.isNil)
  w.deleteRobot(victim)
  checkEq("worth drops by exactly the preacher's build karbonite",
    w.worthOf(t), 137 + 102 + 130 - 30)
  ## The enemy's worth is computed off the enemy's own stores.
  let foe = if t == tRed: tBlue else: tRed
  checkEq("the enemy's worth counts none of our units",
    w.worthOf(foe), w.karbonite[ord(foe)] + w.fuel[ord(foe)] div 5)

block:
  ## `carriedKarbonite`/`carriedFuel` are the LOADS IN THE FIELD, which the
  ## deposit rate is measured against and which `worth` deliberately does NOT
  ## count (an undeposited load is not spendable).
  var w = board()
  let castle = w.robots[0]
  let t = castle.team
  var carriers: seq[Robot]
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if w.isPassable(castle.x + dx, castle.y + dy) and
          w.shadowAt(castle.x + dx, castle.y + dy) == 0:
        let p = w.createItem(castle.x + dx, castle.y + dy, t, ukPilgrim)
        p.karbonite = 3
        p.fuel = 11
        carriers.add p
  check("at least one carrier", carriers.len >= 1)
  checkEq("carried karbonite sums the field loads",
    w.carriedKarbonite(t), 3 * carriers.len)
  checkEq("carried fuel too", w.carriedFuel(t), 11 * carriers.len)
  let before = w.worthOf(t)
  carriers[0].karbonite += 17
  checkEq("and worth ignores a carried load", w.worthOf(t), before)

block:
  ## `spendKarbonite`/`spendFuel` count only POSITIVE spends, so the
  ## `spent` counters can never be inflated by a zero-cost action.
  var w = board()
  w.spendFuel(tRed, 0)
  checkEq("a zero fuel spend is not counted", w.stats.fuelSpent[0], 0)
  w.spendKarbonite(tRed, 0)
  checkEq("nor a zero karbonite spend", w.stats.karboniteSpent[0], 0)
  w.spendFuel(tRed, 7)
  checkEq("a real spend is counted", w.stats.fuelSpent[0], 7)
  checkEq("and taken from the store", w.fuel[0], InitialFuel - 7)

finish("test_bc19_economy")
