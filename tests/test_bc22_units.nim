## The seven-type table, every per-level value, and the single `addHealth`.
##
## §Tests item 2. The whole table is checked against `data/bc22/tables.json`,
## which `tools/JavaBc22Tables.java` generated FROM THE JAR'S OWN CLASSES under
## the CI JDK 8 — so this shard compares the port to the engine, not to a
## transcription of the engine.

import std/[json, os, strutils]
import harness
import bc22_fixture

let tables = parseJson(readFile(dataRoot() / "bc22" / "tables.json"))

proc tableRow(name: string, kind: RobotType): JsonNode =
  tables[name][($kind)]

# --- the constructor table --------------------------------------------------
block:
  checkEq("SPEC_VERSION matches the jar", SpecVersion,
    tables["spec_version"].getStr())
  for kind in RobotType:
    let row = tables["robot_types"][$kind]
    let spec = RobotSpecs[kind]
    checkEq($kind & " lead cost", spec.buildCostLead, row[0].getInt())
    checkEq($kind & " gold cost", spec.buildCostGold, row[1].getInt())
    checkEq($kind & " action cooldown", spec.actionCooldown, row[2].getInt())
    checkEq($kind & " movement cooldown", spec.movementCooldown,
      row[3].getInt())
    checkEq($kind & " health", spec.health, row[4].getInt())
    checkEq($kind & " damage", spec.damage, row[5].getInt())
    checkEq($kind & " action r2", spec.actionRadiusSquared, row[6].getInt())
    checkEq($kind & " vision r2", spec.visionRadiusSquared, row[7].getInt())
    checkEq($kind & " bytecode limit", spec.bytecodeLimit, row[8].getInt())

# --- every per-level derived value ------------------------------------------
block:
  for kind in RobotType:
    for level in 1 .. 3:
      let i = level - 1
      checkEq($kind & " maxHealth " & $level, maxHealthOf(kind, level),
        tableRow("max_health", kind)[i].getInt())
      checkEq($kind & " damage " & $level, damageOf(kind, level),
        tableRow("damage", kind)[i].getInt())
      checkEq($kind & " healing " & $level, healingOf(kind, level),
        tableRow("healing", kind)[i].getInt())
      checkEq($kind & " leadMutateCost " & $level, leadMutateCost(kind, level),
        tableRow("lead_mutate_cost", kind)[i].getInt())
      checkEq($kind & " goldMutateCost " & $level, goldMutateCost(kind, level),
        tableRow("gold_mutate_cost", kind)[i].getInt())
      checkEq($kind & " leadWorth " & $level, leadWorth(kind, level),
        tableRow("lead_worth", kind)[i].getInt())
      checkEq($kind & " goldWorth " & $level, goldWorth(kind, level),
        tableRow("gold_worth", kind)[i].getInt())
      checkEq($kind & " leadDropped " & $level, leadDropped(kind, level),
        tableRow("lead_dropped", kind)[i].getInt())
      checkEq($kind & " goldDropped " & $level, goldDropped(kind, level),
        tableRow("gold_dropped", kind)[i].getInt())

# --- the 49 type-pair predicates --------------------------------------------
block:
  var buildable = 0
  var repairable = 0
  var mutatable = 0
  for a in RobotType:
    for b in RobotType:
      if canBuildType(a, b): inc buildable
      if canRepairType(a, b): inc repairable
      if canMutateType(a, b): inc mutatable
  checkEq("exactly six (builder, built) pairs build", buildable, 6)
  check("an ARCHON builds a MINER", canBuildType(rtArchon, rtMiner))
  check("and a SAGE", canBuildType(rtArchon, rtSage))
  check("but not a LABORATORY", not canBuildType(rtArchon, rtLaboratory))
  check("a BUILDER builds a LABORATORY",
    canBuildType(rtBuilder, rtLaboratory))
  check("and a WATCHTOWER", canBuildType(rtBuilder, rtWatchtower))
  check("nothing builds an ARCHON",
    not canBuildType(rtArchon, rtArchon) and
    not canBuildType(rtBuilder, rtArchon))
  checkEq("an archon repairs the four droids and a builder the three buildings",
    repairable, 4 + 3)
  checkEq("only a builder mutates, and only a building", mutatable, 3)
  check("a WATCHTOWER attacks", canAttackType(rtWatchtower))
  check("a SOLDIER attacks", canAttackType(rtSoldier))
  check("a SAGE attacks", canAttackType(rtSage))
  check("a MINER does not", not canAttackType(rtMiner))
  check("only a SAGE envisions", canEnvisionType(rtSage))
  check("only a MINER mines", canMineType(rtMiner))
  check("only a LABORATORY transmutes", canTransmuteType(rtLaboratory))
  checkEq("three types are buildings",
    (var n = 0; (for k in RobotType: (if k.isBuilding(): inc n)); n), 3)

# --- attacks ----------------------------------------------------------------
block:
  var w = bare()
  let s = w.place(teamA, rtSoldier, loc(10, 10))
  let victim = w.place(teamB, rtMiner, loc(13, 12))
  checkEq("13,12 is r2 = 13 from 10,10",
    loc(10, 10).distanceSquaredTo(loc(13, 12)), 13)
  check("a soldier reaches exactly r2 <= 13", w.canAttack(s, loc(13, 12)))
  w.doAttack(s, loc(13, 12))
  checkEq("and deals 3", victim.health, maxHealthOf(rtMiner, 1) - 3)
  check("an attack on an EMPTY square is illegal",
    not w.canAttack(s, loc(11, 11)))
  discard w.place(teamA, rtMiner, loc(9, 10))
  check("and an attack on an ALLY is illegal", not w.canAttack(s, loc(9, 10)))

block:
  ## A SAGE deals 45 at r2 <= 25 INCLUDING at a robot it cannot see... except
  ## that a sage's vision is 34, so the honest statement of "no vision test" is
  ## a SOLDIER, whose action radius 13 is inside its vision 20 — so the test is
  ## made against the rule itself: `canAttack` never consults
  ## `canSenseLocation`.
  var w = bare()
  let sage = w.place(teamA, rtSage, loc(10, 10))
  let victim = w.place(teamB, rtSoldier, loc(13, 14))
  checkEq("13,14 is r2 = 25", loc(10, 10).distanceSquaredTo(loc(13, 14)), 25)
  check("a sage reaches it", w.canAttack(sage, loc(13, 14)))
  w.doAttack(sage, loc(13, 14))
  checkEq("and 45 damage takes a 50-HP soldier to 5", victim.health, 5)
  checkEq("paying 200 cooldown", sage.actionCooldown, 200)

# --- addHealth --------------------------------------------------------------
block:
  var w = bare()
  let arch = w.place(teamA, rtArchon, loc(10, 10))
  w.addHealth(arch, -100)
  checkEq("addHealth subtracts", arch.health, 500)
  w.addHealth(arch, 1000)
  checkEq("and caps at max", arch.health, 600)

block:
  ## A PROTOTYPE promoted to TURRET by the repair that fills it: 15 builder
  ## repairs for a watchtower (120 -> 150) and 10 for a laboratory (80 -> 100).
  var w = bare()
  let b = w.place(teamA, rtBuilder, loc(10, 10))
  let tower = w.place(teamA, rtWatchtower, loc(11, 10))
  checkEq("a watchtower prototype starts at 120", tower.health, 120)
  var repairs = 0
  while tower.mode == rmPrototype and repairs < 40:
    b.actionCooldown = 0
    w.doRepair(b, loc(11, 10))
    inc repairs
  checkEq("fifteen builder repairs finish a watchtower", repairs, 15)
  checkEq("and it is a TURRET", tower.mode, rmTurret)

block:
  var w = bare()
  let b = w.place(teamA, rtBuilder, loc(10, 10))
  let lab = w.place(teamA, rtLaboratory, loc(11, 10))
  checkEq("a laboratory prototype starts at 80", lab.health, 80)
  var repairs = 0
  while lab.mode == rmPrototype and repairs < 40:
    b.actionCooldown = 0
    w.doRepair(b, loc(11, 10))
    inc repairs
  checkEq("ten builder repairs finish a laboratory", repairs, 10)

block:
  ## `checkArchonDeath` is honoured: a fury-shaped kill does NOT fire
  ## `ANNIHILATION` from inside `destroyRobot`.
  var w = bare()
  let arch = w.place(teamA, rtArchon, loc(10, 10))
  w.addHealth(arch, -10000, false)
  check("the archon is gone", not arch.alive)
  check("and no winner was set", not w.hasWinner)

block:
  var w = bare()
  let arch = w.place(teamA, rtArchon, loc(10, 10))
  discard w.place(teamB, rtArchon, loc(20, 10))
  ## `bare()` already seats one archon a side from the map, so this team has
  ## two; kill both.
  for _, r in w.robotsById:
    discard
  w.addHealth(arch, -10000)
  check("with another archon alive, no winner yet", not w.hasWinner)

# --- the reclaim drop, which STACKS -----------------------------------------
block:
  var w = bare()
  let arch = w.place(teamA, rtArchon, loc(10, 10))
  let before = w.getGold(loc(10, 10))
  w.destroyRobot(arch.id)
  checkEq("a level-1 archon drops 20 gold where it stood",
    w.getGold(loc(10, 10)) - before, 20)
  checkEq("and 0 lead", w.getLead(loc(10, 10)), 0)
  let arch3 = w.place(teamA, rtArchon, loc(10, 10))
  arch3.level = 3
  w.destroyRobot(arch3.id)
  checkEq("a level-3 archon drops 36 more gold, STACKED",
    w.getGold(loc(10, 10)), 20 + 36)
  checkEq("and 60 lead", w.getLead(loc(10, 10)), 60)

finish("test_bc22_units")
