## bc25 towers: the table at all three levels, `completeTowerPattern`'s
## legality and effect, `upgradeTower`'s DAMAGE-CARRY rule, the defense-damage
## ledger on build / upgrade / destroy, the two per-turn attack flags, the
## `attackMoneyBonus` paid ONCE PER LANDING SHOT, and mining.

import harness
import bc25_fixture

# --- the table -------------------------------------------------------------
block:
  for (kind, hp) in [(tkMoney, [1000, 1500, 2000]),
                     (tkPaint, [1000, 1500, 2000]),
                     (tkDefense, [2000, 2500, 3000])]:
    var t = towerTypeFor(kind)
    for level in 0 .. 2:
      checkEq($kind & " L" & $(level + 1) & " health",
        UnitSpecs[t].health, hp[level])
      checkEq($kind & " L" & $(level + 1) & " level",
        UnitSpecs[t].level, level + 1)
      checkEq($kind & " L" & $(level + 1) & " capacity",
        UnitSpecs[t].paintCapacity, 1000)
      t = t.nextLevel()
  checkEq("money mines 20/30/40",
    [UnitSpecs[utLevelOneMoneyTower].moneyPerTurn,
     UnitSpecs[utLevelTwoMoneyTower].moneyPerTurn,
     UnitSpecs[utLevelThreeMoneyTower].moneyPerTurn], [20, 30, 40])
  checkEq("paint mines 5/10/15",
    [UnitSpecs[utLevelOnePaintTower].paintPerTurn,
     UnitSpecs[utLevelTwoPaintTower].paintPerTurn,
     UnitSpecs[utLevelThreePaintTower].paintPerTurn], [5, 10, 15])
  checkEq("defense hits for 40/50/60",
    [UnitSpecs[utLevelOneDefenseTower].attackStrength,
     UnitSpecs[utLevelTwoDefenseTower].attackStrength,
     UnitSpecs[utLevelThreeDefenseTower].attackStrength], [40, 50, 60])
  checkEq("and earns 20/30/40 a landing shot",
    [UnitSpecs[utLevelOneDefenseTower].attackMoneyBonus,
     UnitSpecs[utLevelTwoDefenseTower].attackMoneyBonus,
     UnitSpecs[utLevelThreeDefenseTower].attackMoneyBonus], [20, 30, 40])
  checkEq("a defense tower's action radius is 16, not 9",
    UnitSpecs[utLevelOneDefenseTower].actionRadiusSquared, 16)
  check("L3 cannot be upgraded",
    not utLevelThreeMoneyTower.canUpgradeType())

# --- completeTowerPattern ---------------------------------------------------
block:
  var w = bare(ruins = @[loc(10, 10)])
  let r = w.place(teamA, utSoldier, loc(11, 10))
  w.paintArea(pkMoneyTower, teamA, loc(10, 10), skipCentre = true)
  check("with the pattern exact and 2500 chips it is legal",
    w.canCompleteTowerPattern(r, tkMoney, loc(10, 10)))
  let before = w.getMoney(teamA)
  w.doCompleteTowerPattern(r, tkMoney, loc(10, 10))
  let tower = w.getRobot(loc(10, 10))
  check("a tower rose", tower != nil)
  checkEq("at level one", tower.kind, utLevelOneMoneyTower)
  checkEq("with 500 paint", tower.paint, InitialTowerPaintAmount)
  checkEq("and full health", tower.health,
    UnitSpecs[utLevelOneMoneyTower].health)
  checkEq("the team paid 1000 chips", w.getMoney(teamA), before - 1000)
  checkEq("and the tower count went up", w.stats.towers[0], 3)
  check("the same ruin cannot be built on twice",
    not w.canCompleteTowerPattern(r, tkMoney, loc(10, 10)))

block:
  var w = bare(ruins = @[loc(10, 10)])
  let r = w.place(teamA, utSoldier, loc(11, 10))
  check("a ruin with the WRONG pattern is refused",
    not w.canCompleteTowerPattern(r, tkMoney, loc(10, 10)))
  w.paintArea(pkMoneyTower, teamA, loc(10, 10), skipCentre = true)
  w.stats.money[0] = 999
  check("999 chips is not enough",
    not w.canCompleteTowerPattern(r, tkMoney, loc(10, 10)))
  w.stats.money[0] = 1000
  check("1000 is", w.canCompleteTowerPattern(r, tkMoney, loc(10, 10)))
  w.stats.towers[0] = MaxNumberOfTowers
  check("but not over the 25-tower cap",
    not w.canCompleteTowerPattern(r, tkMoney, loc(10, 10)))
  w.stats.towers[0] = 2
  discard w.place(teamB, utSoldier, loc(10, 10))
  check("nor with a robot standing on the centre",
    not w.canCompleteTowerPattern(r, tkMoney, loc(10, 10)))

block:
  var w = bare(ruins = @[loc(3, 10)])
  let r = w.place(teamA, utSoldier, loc(4, 10))
  w.paintArea(pkMoneyTower, teamA, loc(3, 10), skipCentre = true)
  check("a ruin two tiles from the edge is a valid centre",
    w.canCompleteTowerPattern(r, tkMoney, loc(3, 10)))

# --- the defense ledger -----------------------------------------------------
block:
  var w = bare(ruins = @[loc(10, 10)])
  let r = w.place(teamA, utSoldier, loc(11, 10))
  w.paintArea(pkDefenseTower, teamA, loc(10, 10), skipCentre = true)
  checkEq("the ledger starts at zero", w.damageIncrease[0], 0)
  w.doCompleteTowerPattern(r, tkDefense, loc(10, 10))
  checkEq("a level-one defense tower adds +5", w.damageIncrease[0],
    ExtraDamageFromDefenseTower)
  let tower = w.getRobot(loc(10, 10))
  w.stats.money[0] = 100_000
  w.doUpgradeTower(r, loc(10, 10))
  checkEq("L2 adds a further +2", w.damageIncrease[0], 7)
  checkEq("and the tower is level two", tower.kind, utLevelTwoDefenseTower)
  w.doUpgradeTower(r, loc(10, 10))
  checkEq("L3 adds another +2", w.damageIncrease[0], 9)
  w.destroyRobot(tower.id)
  checkEq("and destroying it takes the WHOLE accumulated buff off",
    w.damageIncrease[0], 0)

# --- the damage carry -------------------------------------------------------
block:
  var w = bare(ruins = @[loc(10, 10)])
  let r = w.place(teamA, utSoldier, loc(11, 10))
  let tower = w.place(teamA, utLevelOneMoneyTower, loc(10, 10))
  w.addHealth(tower, -300)
  checkEq("the tower is damaged", tower.health, 700)
  w.stats.money[0] = 100_000
  w.doUpgradeTower(r, loc(10, 10))
  checkEq("the upgrade CARRIES the damage: 1500 - (1000 - 700)",
    tower.health, 1200)
  checkEq("and it costs the NEXT level's price",
    w.getMoney(teamA), 100_000 - UnitSpecs[utLevelTwoMoneyTower].moneyCost)
  checkEq("upgradedHealth is the rule, spelled out",
    upgradedHealth(utLevelOneMoneyTower, utLevelTwoMoneyTower, 700), 1200)

# --- the two flags, the damage and the bonus -------------------------------
block:
  var w = bare(ruins = @[loc(10, 10)])
  let tower = w.place(teamA, utLevelOneDefenseTower, loc(10, 10))
  w.damageIncrease[0] = ExtraDamageFromDefenseTower
  let victim = w.place(teamB, utSoldier, loc(11, 10))
  let hp = victim.health
  let chips = w.getMoney(teamA)
  w.doTowerAttackSingle(tower, victim.loc)
  checkEq("single damage is attackStrength + the ledger",
    victim.health, hp - (40 + 5))
  checkEq("and a landing shot earns the bonus once",
    w.getMoney(teamA), chips + 20)
  let hp2 = victim.health
  w.doTowerAttackArea(tower)
  checkEq("the AoE buff is round(buff * 0 / 100) = +0",
    victim.health, hp2 - UnitSpecs[utLevelOneDefenseTower].aoeAttackStrength)
  checkEq("and a defense tower that lands BOTH earns TWICE",
    w.getMoney(teamA), chips + 40)

block:
  var w = bare(ruins = @[loc(10, 10)])
  let tower = w.place(teamA, utLevelOneDefenseTower, loc(10, 10))
  let chips = w.getMoney(teamA)
  w.doTowerAttackArea(tower)
  checkEq("a shot that hits nothing earns nothing", w.getMoney(teamA), chips)

# --- mining -----------------------------------------------------------------
block:
  var w = bare()
  let money = w.place(teamA, utLevelTwoMoneyTower, loc(10, 10))
  let paint = w.place(teamA, utLevelTwoPaintTower, loc(12, 10))
  paint.paint = 0
  let chips = w.getMoney(teamA)
  w.mine(money)
  checkEq("a money tower adds its moneyPerTurn to the TEAM pool",
    w.getMoney(teamA), chips + 30)
  w.mine(paint)
  checkEq("a paint tower adds its paintPerTurn to ITS OWN stash",
    paint.paint, 10)
  checkEq("and nothing to the chip pool", w.getMoney(teamA), chips + 30)
  paint.paint = 1000
  w.mine(paint)
  checkEq("a full paint tower mines nothing", paint.paint, 1000)

finish("test_bc25_towers")
