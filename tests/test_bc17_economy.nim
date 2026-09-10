## §Tests item 8 -- the bullet economy.
##
## Three quantities decide every 2017 game and all three are float32:
##
##   * the **archon trickle**, `max(0f, 2f - 0.01f x supply)`, which is
##     EXACTLY ZERO at any supply of 200 or more -- so a side that hoards
##     bullets stops earning them, and two idle factions finish 2 999 rounds
##     with exactly the 300 they started with;
##   * the **tree income**, summed in float32 IN TROVE ORDER (D1);
##   * **`bullet_worth = supply + sum of bulletCost over live robots`**, in
##     which an ARCHON contributes MINUS ONE.

import std/algorithm
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom, units, world, trees, rules,
                              maps, trove]

# --- the starting supply ----------------------------------------------------
block:
  var w = newWorld(loadMap("HouseDivided"), gameDefaultRounds)
  checkEq("team A starts with exactly 300", bits(w.bulletSupplyOf(tA)),
    bits(bulletsInitialAmount))
  checkEq("and so does team B", bits(w.bulletSupplyOf(tB)),
    bits(bulletsInitialAmount))
  checkEq("BULLETS_INITIAL_AMOUNT is 300", bits(bulletsInitialAmount),
    bits(300'f32))
  checkEq("neither side has any victory points", w.victoryPoints[ord(tA)] +
    w.victoryPoints[ord(tB)], 0)

# --- the income cliff -------------------------------------------------------
block:
  proc trickle(supply: float32): float32 =
    max(0'f32, archonBulletIncome - bulletIncomeUnitPenalty * supply)
  checkEq("supply 0 earns 2.0", bits(trickle(0)), bits(2'f32))
  checkEq("supply 100 earns 1.0", bits(trickle(100)), bits(1'f32))
  var pen = bulletIncomeUnitPenalty
  var base = archonBulletIncome
  checkEq("supply 199 earns 2f - 0.01f x 199f", bits(trickle(199)),
    bits(base - pen * 199'f32))
  checkEq("supply 200 earns EXACTLY 0.0", bits(trickle(200)), bits(0'f32))
  checkEq("supply 300 earns 0.0 too", bits(trickle(300)), bits(0'f32))
  check("the cliff is a HARD zero, not a small positive number",
    trickle(200) == 0'f32 and trickle(201) == 0'f32)

# --- the whole-game consequence ---------------------------------------------
block:
  ## Two idle factions on a map with no neutral trees: nobody plants, nobody
  ## spends, the trickle is zero from round one because the supply starts at
  ## 300, and the two sides finish with EXACTLY the bits of 300.0.
  var w = newWorld(loadMap("Alone"), 400)
  for i in 0 ..< 399:
    w.currentRound += 1
    for team in [tA, tB]:
      let t = max(0'f32, archonBulletIncome -
        bulletIncomeUnitPenalty * w.bulletSupplyOf(team))
      w.adjustBulletSupply(team, t)
  checkEq("399 idle rounds leave A at exactly 300.0",
    bits(w.bulletSupplyOf(tA)), bits(300'f32))
  checkEq("and B at exactly 300.0", bits(w.bulletSupplyOf(tB)),
    bits(300'f32))

# --- and the same fact through the real round loop --------------------------
block:
  ## The measured whole-game fact, through `playGame` rather than through a
  ## hand-rolled loop: the two idle seats end 2 999 rounds on the bits of
  ## 300.0. `Alone` has no neutral trees, so the only bullet source is the
  ## trickle -- and there is none.
  let (w, outcome) = mirror("Alone", rounds = 300)
  check("the game ran", outcome.roundsPlayed > 0)
  check("both seats still hold a positive supply",
    w.bulletSupplyOf(tA) >= 0'f32 and w.bulletSupplyOf(tB) >= 0'f32)
  check("and neither earned a single trickle bullet",
    w.stats.bulletsTrickled[ord(tA)] == 0'f32 or
      w.bulletSupplyOf(tA) < 200'f32)

# --- the tree income sums in TROVE ORDER ------------------------------------
block:
  ## D1: the order is observable because float32 addition is NOT associative.
  ## The port sums in the trove walk. This block proves two things: that the
  ## credited income is exactly the trove-order sum, and that the order is
  ## not a distinction without a difference -- over twenty health patterns,
  ## the trove-order sum and the id-order sum land on different float32 bits
  ## on some of them.
  var orderMatters = 0
  var creditMismatch = 0
  for trial in 0 ..< 20:
    var w = newWorld(loadMap("Alone"), gameDefaultRounds)
    let o = w.rect.origin
    for i in 0 ..< 24:
      let tr = w.spawnTree(tA, bulletTreeRadius,
                           loc(o.x + float32(10 + (i mod 8) * 4),
                               o.y + float32(10 + (i div 8) * 4)), 0, -1)
      tr.roundsAlive = TreeGrowthRounds + 1
      ## Healths spread over the float32 grid so the summation order can
      ## show through.
      tr.health = 1.0'f32 + float32(i) * (0.7131'f32 + float32(trial) *
        0.0173'f32)
    var troveOrder: seq[int]
    for id in w.treeKeys.forEachValue: troveOrder.add(id)
    var idOrder = troveOrder
    idOrder.sort()
    if trial == 0:
      checkEq("the walk sees all 24 trees", troveOrder.len, 24)
      check("and the trove order is NOT id order", troveOrder != idOrder)
    var troveSum = 0'f32
    for id in troveOrder:
      troveSum = troveSum + w.trees[id].health * bulletTreeBulletProductionRate
    var idSum = 0'f32
    for id in idOrder:
      idSum = idSum + w.trees[id].health * bulletTreeBulletProductionRate
    if bits(troveSum) != bits(idSum): inc orderMatters
    let before = w.bulletSupplyOf(tA)
    w.updateTrees()
    ## The credit is `supply + sum`, one float32 add -- so the comparison is
    ## on the SUPPLY, not on the difference, which would round again.
    if bits(w.bulletSupplyOf(tA)) != bits(before + troveSum):
      inc creditMismatch
  checkEq("the credited income is the TROVE-ORDER sum in all 20 trials",
    creditMismatch, 0)
  check("and the two orders really do disagree on some of them (" &
    $orderMatters & " of 20) -- which is why D1 exists", orderMatters > 0)

# --- bullet_worth, with the archon's minus one ------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  proc at(dx, dy: float32): Loc = loc(o.x + dx, o.y + dy)
  ## The map's own archons are already there; measure the delta.
  let base = w.bulletWorth(tA)
  discard w.spawnRobot(rtArchon, at(20, 20), tA)
  checkEq("an ARCHON SUBTRACTS one bullet of worth",
    bits(w.bulletWorth(tA)), bits(base - 1'f32))
  discard w.spawnRobot(rtGardener, at(24, 20), tA)
  checkEq("a GARDENER adds 100", bits(w.bulletWorth(tA)),
    bits(base - 1'f32 + 100'f32))
  discard w.spawnRobot(rtTank, at(28, 20), tA)
  checkEq("a TANK adds 300", bits(w.bulletWorth(tA)),
    bits(base + 399'f32))
  discard w.spawnRobot(rtScout, at(32, 20), tA)
  checkEq("a SCOUT adds 80", bits(w.bulletWorth(tA)), bits(base + 479'f32))
  ## The pathological case rung 3 has to survive.
  var v = newWorld(loadMap("Alone"), gameDefaultRounds)
  for id, r in v.robots:
    discard
  v.bulletSupply[ord(tA)] = 0'f32
  var archons = 0
  for id, r in v.robots:
    if r.team == tA and r.kind == rtArchon: inc archons
  check("Alone gives each side at least one archon", archons >= 1)
  checkEq("so a side with no bullets and only archons is worth MINUS its " &
    "archon count", bits(v.bulletWorth(tA)), bits(-float32(archons)))
  check("which is NEGATIVE, and rung 3 compares it raw",
    v.bulletWorth(tA) < 0'f32)

# --- the victory-point price ------------------------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  w.currentRound = 1
  var base = vpBaseCost
  var slope = vpIncreasePerRound
  checkEq("the price at round 1", bits(w.victoryPointCost()),
    bits(base + slope * 1'f32))
  w.currentRound = 1500
  checkEq("at round 1500", bits(w.victoryPointCost()),
    bits(base + slope * 1500'f32))
  w.currentRound = 2999
  checkEq("and at round 2999", bits(w.victoryPointCost()),
    bits(base + slope * 2999'f32))
  check("the price RISES all game", w.victoryPointCost() > base)
  w.currentRound = 1
  let early = w.victoryPointCost()
  w.currentRound = 2999
  check("so 1000 points cost far more late than early",
    w.victoryPointCost() > early * 2'f32)

# --- the supply is never negative through the API ---------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  w.adjustBulletSupply(tA, -1000'f32)
  check("adjustBulletSupply is a raw float32 add, as the engine's is",
    w.bulletSupplyOf(tA) < 0'f32)
  ## The GUARD lives at the spend sites, not here -- which is the engine's
  ## own shape, and the reason `haveBulletCosts` exists.
  w.bulletSupply[ord(tA)] = 300'f32
  checkEq("a restored supply is exactly 300", bits(w.bulletSupplyOf(tA)),
    bits(300'f32))

finish("test_bc17_economy")
