## bc25 cooldowns: the two counters, the ten-per-turn decay, the strictly-under
## -ten legality test with its ZERO-PAINT clause, the low-paint surcharge over
## its whole finite domain, the fact that TOWERS NEVER PAY IT, and the two
## opposite charge orders (an attack charges from the PRE-COST stash, a paint
## transfer from the POST-TRANSFER one).

import harness
import bc25_fixture

# --- the decay -------------------------------------------------------------
block:
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.actionCooldown = 25
  r.movementCooldown = 14
  w.processBeginningOfTurn(r)
  checkEq("action decays by exactly 10", r.actionCooldown, 15)
  checkEq("movement decays by exactly 10", r.movementCooldown, 4)
  for _ in 0 .. 3:
    w.processBeginningOfTurn(r)
  checkEq("action floors at 0", r.actionCooldown, 0)
  checkEq("movement floors at 0", r.movementCooldown, 0)

block:
  var w = bare()
  let r = w.spawnRobot(utSoldier, loc(10, 10), teamA)
  checkEq("a fresh soldier starts at its type's own action cooldown",
    r.actionCooldown, UnitSpecs[utSoldier].actionCooldown)
  checkEq("and at the movement cooldown LIMIT", r.movementCooldown,
    CooldownLimit)
  check("so it can neither act", not r.isActionReady())
  check("nor move on the turn it is built", not r.isMovementReady())

# --- readiness is STRICTLY under ten, AND needs paint -----------------------
block:
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.actionCooldown = 9
  check("nine is ready", r.isActionReady())
  r.actionCooldown = 10
  check("ten is not", not r.isActionReady())
  r.actionCooldown = 0
  r.paint = 0
  check("and a robot at ZERO paint is never action-ready",
    not r.isActionReady())
  check("nor movement-ready", not r.isMovementReady())
  let t = w.place(teamA, utLevelOneMoneyTower, loc(12, 12))
  t.paint = 0
  t.actionCooldown = 0
  check("but a TOWER at zero paint still is", t.isActionReady())

# --- the surcharge, over its whole finite domain ---------------------------
block:
  ## `round(add * (100 - 2*pct) / 100.0)` with the int*int product taken
  ## BEFORE the divide, for every base cooldown the rule set uses and every
  ## (paint, capacity) pair of the three robot types.
  var checked = 0
  var boundary = 0
  for kind in RobotTypes:
    let cap = UnitSpecs[kind].paintCapacity
    for paint in 0 .. cap:
      let pct = paintPercentage(paint, kind)
      for add in [10, 20, 30, 50]:
        let got = cooldownSurcharge(add, paint, kind)
        let want =
          if pct >= IncreasedCooldownThreshold: add
          else: add + javaRound(float64(add * (100 - 2 * pct)) / 100.0)
        if got != want:
          checkEq("surcharge " & $kind & " p=" & $paint & " add=" & $add,
            got, want)
        checked += 1
      if pct == IncreasedCooldownThreshold:
        boundary += 1
        checkEq("at exactly 50 % there is NO surcharge",
          cooldownSurcharge(10, paint, kind), 10)
  check("the whole (paint, capacity, base) domain was walked",
    checked == 4 * ((UnitSpecs[utSoldier].paintCapacity + 1) +
                    (UnitSpecs[utSplasher].paintCapacity + 1) +
                    (UnitSpecs[utMopper].paintCapacity + 1)))
  check("and the 50 % boundary really occurs", boundary > 0)

block:
  ## TOWERS NEVER PAY IT, at any paint level.
  for kind in [utLevelOnePaintTower, utLevelTwoMoneyTower,
               utLevelThreeDefenseTower]:
    for paint in [0, 1, 250, 999, 1000]:
      checkEq("a tower pays the base cooldown only (" & $kind & ")",
        cooldownSurcharge(10, paint, kind), 10)

block:
  ## One worked value, so a regression is readable: a soldier at 40/200 is
  ## 20 %, so a base-10 attack costs 10 + round(10*60/100) = 16.
  checkEq("soldier at 20 % pays 16 for a base-10 action",
    cooldownSurcharge(10, 40, utSoldier), 16)
  checkEq("and 80 for a base-50 splash at 20 % capacity",
    cooldownSurcharge(50, 60, utSplasher), 80)

# --- a tower's attack costs NO cooldown at all -----------------------------
block:
  var w = bare()
  let tower = w.place(teamA, utLevelOneDefenseTower, loc(10, 10))
  let victim = w.place(teamB, utSoldier, loc(11, 10))
  tower.actionCooldown = 0
  w.doTowerAttackSingle(tower, victim.loc)
  checkEq("a tower's single shot charges no cooldown", tower.actionCooldown, 0)
  w.doTowerAttackArea(tower)
  checkEq("nor does its area shot", tower.actionCooldown, 0)
  check("but each fires only once a turn",
    not w.canTowerAttackSingle(tower, victim.loc) and
    not w.canTowerAttackArea(tower))

block:
  var w = bare()
  let tower = w.place(teamA, utLevelTwoPaintTower, loc(10, 10))
  tower.actionCooldown = 0
  tower.paint = 1000
  w.doBuildRobot(tower, utSoldier, loc(11, 10))
  checkEq("but buildRobot charges the tower a flat +10",
    tower.actionCooldown, BuildRobotCooldown)

# --- the two opposite charge orders ----------------------------------------
block:
  ## `RobotControllerImpl.attack` charges BEFORE `robot.attack` deducts the
  ## attack's paint cost, so the surcharge reads the PRE-COST stash. A soldier
  ## at exactly 100/200 is 50 % and pays nothing; if the 5 came off first it
  ## would be 95/200 = 48 % and pay 10 + round(10*4/100) = 10, so the two
  ## orders differ by a measurable amount only just below the boundary.
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  r.paint = 98            ## 49 % -> a surcharge of 10 + round(10*2/100) = 10
  w.doAttackRobot(r, loc(10, 10))
  checkEq("the attack charged from the pre-cost stash",
    r.actionCooldown, cooldownSurcharge(10, 98, utSoldier))
  checkEq("and the paint came off after", r.paint, 93)

block:
  ## `transferPaint` moves the paint FIRST and charges after, so the surcharge
  ## reads the POST-transfer stash — the opposite order, and both are the
  ## engine's.
  var w = bare()
  let tower = w.place(teamA, utLevelTwoPaintTower, loc(10, 10))
  let r = w.place(teamA, utSoldier, loc(11, 10))
  tower.paint = 1000
  r.paint = 10
  w.doTransferPaint(r, tower.loc, -150)
  checkEq("the robot drank", r.paint, 160)
  checkEq("the tower paid", tower.paint, 850)
  checkEq("and the cooldown was charged from the POST-transfer stash",
    r.actionCooldown, cooldownSurcharge(PaintTransferCooldown, 160, utSoldier))

finish("test_bc25_cooldown")
