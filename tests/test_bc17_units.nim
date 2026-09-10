## §Tests item 1 -- the six-row unit table.
##
## `src/battlecode/years/bc17/constants.nim` is GENERATED from the pinned
## oracle jar by JVM reflection over `common/RobotType`, so this shard is not
## re-typing the table: it is asserting that the generated table still says
## what the 2017 rulebook says, and that the two `-1`s in it are RULES and not
## sentinels a later edit may "clean up".

import harness
import bc17_fixture
import battlecode/years/bc17/[constants, units]

# --- the ordinal is load-bearing --------------------------------------------
block:
  ## The ordinal is the flatbuffer `BodyType` ordinal, the `Bc17UnitNames`
  ## index and the atlas cell index, so a reordering is a wire break.
  checkEq("RobotType.values() order", @[ord(rtArchon), ord(rtGardener),
    ord(rtLumberjack), ord(rtSoldier), ord(rtTank), ord(rtScout)],
    @[0, 1, 2, 3, 4, 5])
  checkEq("and the names match it", @(units.Bc17UnitNames),
    @["archon", "gardener", "lumberjack", "soldier", "tank", "scout"])
  for t in RobotType:
    checkEq("unitName(" & $t & ") is its lowercase name", unitName(t),
      units.Bc17UnitNames[ord(t)])

# --- the table, row by row --------------------------------------------------
block:
  ## `(maxHealth, bulletCost, bodyRadius, strideRadius, sensorRadius,
  ##   bulletSightRadius, bulletSpeed, attackPower, buildCooldownTurns)`
  const want = [
    (400, -1, 2.0'f32, 0.5'f32, 10.0'f32, 15.0'f32, -1.0'f32, -1.0'f32, 0),
    (40, 100, 1.0'f32, 0.5'f32, 7.0'f32, 10.0'f32, -1.0'f32, -1.0'f32, 10),
    (50, 100, 1.0'f32, 0.75'f32, 7.0'f32, 10.0'f32, -1.0'f32, 2.0'f32, 10),
    (50, 100, 1.0'f32, 0.8'f32, 7.0'f32, 10.0'f32, 2.0'f32, 2.0'f32, 10),
    (200, 300, 2.0'f32, 0.5'f32, 7.0'f32, 10.0'f32, 4.0'f32, 5.0'f32, 10),
    (10, 80, 1.0'f32, 1.25'f32, 14.0'f32, 20.0'f32, 1.5'f32, 0.5'f32, 10),
  ]
  for t in RobotType:
    let w = want[ord(t)]
    let s = RobotSpecs[t]
    let n = $t
    checkEq(n & " maxHealth", s.maxHealth, w[0])
    checkEq(n & " bulletCost", s.bulletCost, w[1])
    checkEq(n & " bodyRadius", bodyRadius(t), w[2])
    checkEq(n & " strideRadius", strideRadius(t), w[3])
    checkEq(n & " sensorRadius", sensorRadius(t), w[4])
    checkEq(n & " bulletSightRadius", bulletSightRadius(t), w[5])
    checkEq(n & " bulletSpeed", bulletSpeed(t), w[6])
    checkEq(n & " attackPower", attackPower(t), w[7])
    checkEq(n & " buildCooldownTurns", buildCooldownTurns(t), w[8])
    checkEq(n & " maxHealthF is the int widened", maxHealthF(t),
      float32(s.maxHealth))
    checkEq(n & " bulletCostF is the int widened", bulletCostF(t),
      float32(s.bulletCost))

# --- the two minus-ones are rules -------------------------------------------
block:
  checkEq("ARCHON.bulletCost is -1 -- a live archon SUBTRACTS a bullet from " &
    "its own team on tiebreak rung 3", RobotSpecs[rtArchon].bulletCost, -1)
  checkEq("ARCHON.attackPower is -1", attackPower(rtArchon), -1'f32)
  checkEq("GARDENER.attackPower is -1", attackPower(rtGardener), -1'f32)
  check("so canAttack is FALSE for an ARCHON", not canAttack(rtArchon))
  check("and FALSE for a GARDENER", not canAttack(rtGardener))
  for t in [rtLumberjack, rtSoldier, rtTank, rtScout]:
    check("canAttack(" & $t & ")", canAttack(t))

# --- who makes whom ---------------------------------------------------------
block:
  check("only an ARCHON hires", canHire(rtArchon))
  for t in [rtGardener, rtLumberjack, rtSoldier, rtTank, rtScout]:
    check("canHire(" & $t & ") is false", not canHire(t))
  check("only a GARDENER builds", canBuild(rtGardener))
  for t in [rtArchon, rtLumberjack, rtSoldier, rtTank, rtScout]:
    check("canBuild(" & $t & ") is false", not canBuild(t))
  check("a GARDENER is the one hireable type", isHireable(rtGardener))
  for t in [rtArchon, rtLumberjack, rtSoldier, rtTank, rtScout]:
    check("isHireable(" & $t & ") is false", not isHireable(t))
  for t in [rtLumberjack, rtSoldier, rtTank, rtScout]:
    check("isBuildable(" & $t & ")", isBuildable(t))
  check("an ARCHON is not buildable", not isBuildable(rtArchon))
  check("and neither is a GARDENER", not isBuildable(rtGardener))
  checkEq("spawnSource(ARCHON) is the engine's null", -1,
    RobotSpecs[rtArchon].spawnSource)

# --- getStartingHealth ------------------------------------------------------
block:
  ## `maxHealth` for the two support types, `0.2f * maxHealth` for the four
  ## fighters -- which is why a fighter spends its first twenty turns healing.
  checkEq("an ARCHON is born at full health", startingHealth(rtArchon),
    400'f32)
  checkEq("a GARDENER is born at 40.0", startingHealth(rtGardener), 40'f32)
  checkEq("a SOLDIER is born at exactly 10.0", startingHealth(rtSoldier),
    10'f32)
  checkEq("a LUMBERJACK at 10.0", startingHealth(rtLumberjack), 10'f32)
  checkEq("a TANK at 40.0", startingHealth(rtTank), 40'f32)
  checkEq("a SCOUT at 2.0", startingHealth(rtScout), 2'f32)
  for t in [rtLumberjack, rtSoldier, rtTank, rtScout]:
    ## Built from RUNTIME values: Nim folds a `const` float32 product in
    ## float64, so `0.2'f32 * 50'f32` written as a constant is NOT the
    ## runtime product. Every float32 expectation in this year is built the
    ## way the sim builds it.
    var frac = plantedUnitStartingHealthFraction
    var mh = maxHealthF(t)
    checkEq($t & " is 0.2f * maxHealth as the ENGINE computes it",
      startingHealth(t), frac * mh)

# --- the shot shapes --------------------------------------------------------
block:
  checkEq("a single shot costs 1", shotCost(ssSingle), singleShotCost)
  checkEq("a triad costs 4", shotCost(ssTriad), triadShotCost)
  checkEq("a pentad costs 6", shotCost(ssPentad), pentadShotCost)
  checkEq("a single fires one bullet", shotCount(ssSingle), 1)
  checkEq("a triad three", shotCount(ssTriad), 3)
  checkEq("a pentad five", shotCount(ssPentad), 5)
  checkEq("the triad spread is 20 degrees", shotSpreadDegrees(ssTriad),
    triadSpreadDegrees)
  checkEq("the pentad spread is 15", shotSpreadDegrees(ssPentad),
    pentadSpreadDegrees)
  for shape in ShotShape:
    for t in [rtArchon, rtGardener, rtLumberjack]:
      check($t & " may not fire a " & $shape, not canFire(t, shape))
  check("a SCOUT may fire a single shot", canFire(rtScout, ssSingle))
  check("but NOT a triad", not canFire(rtScout, ssTriad))
  check("and NOT a pentad", not canFire(rtScout, ssPentad))
  for t in [rtSoldier, rtTank]:
    for shape in ShotShape:
      check($t & " may fire a " & $shape, canFire(t, shape))

# --- the decision budget ----------------------------------------------------
block:
  checkEq("an archon gets 3000 DecisionOps", opsFor(rtArchon), ArchonOps)
  for t in [rtGardener, rtLumberjack, rtSoldier, rtTank, rtScout]:
    checkEq($t & " gets 1500", opsFor(t), UnitOps)
  checkEq("ArchonOps is bytecodeLimit/10", ArchonOps,
    RobotSpecs[rtArchon].bytecodeLimit div 10)
  for t in [rtGardener, rtLumberjack, rtSoldier, rtTank, rtScout]:
    checkEq($t & "'s limit is 15000", RobotSpecs[t].bytecodeLimit, 15000)
  checkEq("a dormant robot gets none", DormantOps, 0)
  checkEq("dormancy is twenty rounds", DormancyRounds, 20)

# --- repair -----------------------------------------------------------------
block:
  for t in [rtLumberjack, rtSoldier, rtTank, rtScout]:
    var mh = maxHealthF(t)
    var rate = 0.04'f32
    checkEq($t & " heals 0.04f * maxHealth a dormant turn",
      repairPerDormantTurn(t), rate * mh)
  ## Twenty of those from the starting fifth is exactly full health -- which
  ## is the whole shape of the dormancy rule.
  var acc = startingHealth(rtSoldier)
  for i in 0 ..< 20: acc = acc + repairPerDormantTurn(rtSoldier)
  checkEq("twenty dormant turns take a SOLDIER from 10 to exactly 50",
    acc, maxHealthF(rtSoldier))

finish("test_bc17_units")
