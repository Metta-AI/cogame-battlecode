## bc23's six-type table, the launcher's blind 20, the carrier's
## weight-driven throw, and `addHealth` — including the fact that A
## HEADQUARTERS IS IMMUNE and that a destroyed carrier's cargo comes off the
## TEAM total.

import harness
import bc23_fixture

# --- the whole RobotType table, verbatim -----------------------------------
block:
  checkEq("HEADQUARTERS action cd", RobotSpecs[rtHeadquarters].actionCooldown, 2)
  checkEq("HEADQUARTERS cannot move",
    RobotSpecs[rtHeadquarters].movementCooldown, -1)
  checkEq("HEADQUARTERS nominal hp", RobotSpecs[rtHeadquarters].health, 1)
  checkEq("HEADQUARTERS aura damage", RobotSpecs[rtHeadquarters].damage, 4)
  checkEq("HEADQUARTERS action r2",
    RobotSpecs[rtHeadquarters].actionRadiusSquared, 9)
  checkEq("HEADQUARTERS vision r2",
    RobotSpecs[rtHeadquarters].visionRadiusSquared, 34)
  checkEq("CARRIER adamantium", RobotSpecs[rtCarrier].buildCostAdamantium, 50)
  checkEq("CARRIER hp", RobotSpecs[rtCarrier].health, 150)
  checkEq("CARRIER action r2", RobotSpecs[rtCarrier].actionRadiusSquared, 9)
  checkEq("LAUNCHER mana", RobotSpecs[rtLauncher].buildCostMana, 45)
  checkEq("LAUNCHER hp", RobotSpecs[rtLauncher].health, 200)
  checkEq("LAUNCHER damage", RobotSpecs[rtLauncher].damage, 20)
  checkEq("LAUNCHER action r2", RobotSpecs[rtLauncher].actionRadiusSquared, 16)
  checkEq("LAUNCHER move cd", RobotSpecs[rtLauncher].movementCooldown, 20)
  checkEq("DESTABILIZER elixir", RobotSpecs[rtDestabilizer].buildCostElixir,
    200)
  checkEq("DESTABILIZER hp", RobotSpecs[rtDestabilizer].health, 300)
  checkEq("DESTABILIZER damage", RobotSpecs[rtDestabilizer].damage, 50)
  checkEq("DESTABILIZER action r2",
    RobotSpecs[rtDestabilizer].actionRadiusSquared, 13)
  checkEq("BOOSTER elixir", RobotSpecs[rtBooster].buildCostElixir, 150)
  checkEq("BOOSTER hp", RobotSpecs[rtBooster].health, 400)
  checkEq("BOOSTER action cd", RobotSpecs[rtBooster].actionCooldown, 140)
  checkEq("BOOSTER has no action radius",
    RobotSpecs[rtBooster].actionRadiusSquared, -1)
  checkEq("AMPLIFIER adamantium", RobotSpecs[rtAmplifier].buildCostAdamantium,
    30)
  checkEq("AMPLIFIER mana", RobotSpecs[rtAmplifier].buildCostMana, 15)
  checkEq("AMPLIFIER hp", RobotSpecs[rtAmplifier].health, 120)
  checkEq("AMPLIFIER has no action cooldown",
    RobotSpecs[rtAmplifier].actionCooldown, -1)
  checkEq("AMPLIFIER vision r2", RobotSpecs[rtAmplifier].visionRadiusSquared,
    34)
  check("only a carrier and a launcher can attack",
    canAttackType(rtCarrier) and canAttackType(rtLauncher) and
    not canAttackType(rtAmplifier) and not canAttackType(rtBooster) and
    not canAttackType(rtDestabilizer) and
    not canAttackType(rtHeadquarters))
  checkEq("the two anchors", AnchorSpecs[anStandard].totalHealth, 250)
  checkEq("accelerating anchor health", AnchorSpecs[anAccelerating].totalHealth,
    750)
  checkEq("standard anchor adamantium",
    AnchorSpecs[anStandard].adamantiumCost, 80)
  checkEq("standard anchor mana", AnchorSpecs[anStandard].manaCost, 80)
  checkEq("accelerating anchor elixir",
    AnchorSpecs[anAccelerating].elixirCost, 300)
  checkEq("standard heal", AnchorSpecs[anStandard].healingAmount, 4)
  checkEq("accelerating heal", AnchorSpecs[anAccelerating].healingAmount, 6)
  checkEq("both heal EVERY round", AnchorSpecs[anStandard].healingFrequency, 1)

# --- a launcher's 20 at r2 <= 16, INCLUDING at a robot it cannot see --------
block:
  ## The target sits four tiles east (r2 = 16, the exact edge) and BOTH ends
  ## of the sightline are clouds, so vision collapses to r2 <= 4 and the
  ## launcher cannot see it at all. The attack still lands: `assertCanAttack`
  ## has no vision precondition.
  var w = bare(clouds = @[loc(10, 10), loc(14, 10)])
  let l = w.place(teamA, rtLauncher, loc(10, 10))
  let victim = w.place(teamB, rtCarrier, loc(14, 10))
  checkEq("the target is at exactly r2 = 16",
    l.loc.distanceSquaredTo(victim.loc), 16)
  check("and it CANNOT be seen", not w.canSenseLocation(l, victim.loc))
  check("but it can be attacked", w.canAttack(l, victim.loc))
  check("the attack lands", w.doAttack(l, victim.loc))
  checkEq("for exactly 20", victim.health, 130)
  let far = w.place(teamB, rtCarrier, loc(15, 10))
  check("r2 = 25 is out of range", not w.canAttack(l, far.loc))

# --- the carrier's throw at every weight, and the emptying ------------------
block:
  for weight in 0 .. 40:
    checkEq("throw damage at weight " & $weight, carrierThrowDamage(weight),
      int(float32(1.25) * float32(weight)))
  checkEq("weight 4 throws for 5", carrierThrowDamage(4), 5)
  checkEq("weight 20 throws for 25", carrierThrowDamage(20), 25)
  checkEq("a FULL carrier throws for 50", carrierThrowDamage(40), 50)

block:
  var w = bare()
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  let victim = w.place(teamB, rtLauncher, loc(12, 10))
  w.addResourceAmount(c, resAdamantium, 20)
  w.addResourceAmount(c, resMana, 20)
  checkEq("the team total carries the cargo",
    w.teamResource(teamA, resAdamantium), 20)
  checkEq("the carrier weighs 40", c.weight, 40)
  check("the throw lands", w.doAttack(c, victim.loc))
  checkEq("for floor(1.25 * 40) = 50", victim.health, 150)
  checkEq("the carrier is empty", c.weight, 0)
  checkEq("and the resources came off the TEAM total",
    w.teamResource(teamA, resAdamantium), 0)
  checkEq("both of them", w.teamResource(teamA, resMana), 0)

block:
  ## A MISS empties it too.
  var w = bare()
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  w.addResourceAmount(c, resAdamantium, 12)
  c.addAnchor(anStandard)
  check("the throw at an empty tile is legal", w.canAttack(c, loc(12, 10)))
  check("and it happens", w.doAttack(c, loc(12, 10)))
  checkEq("the cargo is gone anyway", c.adamantium, 0)
  checkEq("the anchor is DESTROYED too", c.totalAnchors, 0)
  checkEq("and the team total lost the cargo",
    w.teamResource(teamA, resAdamantium), 0)

block:
  ## An attack on a HEADQUARTERS, an ALLY or an EMPTY tile deals nothing —
  ## and a carrier still empties itself.
  var w = bare()
  let c = w.place(teamA, rtCarrier, loc(4, 15))
  w.addResourceAmount(c, resAdamantium, 8)
  let ally = w.place(teamA, rtLauncher, loc(5, 15))
  check("attacking an ally is legal", w.doAttack(c, ally.loc))
  checkEq("the ally takes nothing", ally.health, 200)
  checkEq("the carrier is empty regardless", c.adamantium, 0)
  let l = w.place(teamB, rtLauncher, loc(26, 14))
  let hq = w.robotsById[2]
  check("a launcher can target an enemy headquarters",
    w.canAttack(l, loc(26, 15)))
  discard w.doAttack(l, loc(26, 15))
  checkEq("but a headquarters is IMMUNE", w.robotsById[3].health, 1)
  checkEq("and so is ours", hq.health, 1)

# --- addHealth ------------------------------------------------------------
block:
  var w = bare()
  let r = w.place(teamA, rtLauncher, loc(10, 10))
  w.addHealth(r, -50)
  checkEq("damage lands", r.health, 150)
  w.addHealth(r, 500)
  checkEq("healing caps at the type maximum", r.health, 200)
  w.addHealth(r, -200)
  check("and zero destroys it", not w.existsRobot(r.id))
  checkEq("the loss is counted", w.stats.robotsLost[0], 1)

block:
  ## Destruction refunds nothing AND removes the cargo from the team total.
  var w = bare()
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  w.addResourceAmount(c, resMana, 30)
  checkEq("the team holds the cargo", w.teamResource(teamA, resMana), 30)
  w.destroyRobot(c.id)
  checkEq("and loses it on destruction", w.teamResource(teamA, resMana), 0)
  checkEq("the tile is free", int(w.getRobot(loc(10, 10)) == nil), 1)

finish("test_bc23_units")
