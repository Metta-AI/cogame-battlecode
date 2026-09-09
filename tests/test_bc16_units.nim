## Shard 2 of the note's list — **the twelve-row `RobotType` table and all
## eight derived predicates**, every cell compared against the JVM's own
## values in `data/bc16/tables.json` rather than against a hand-typed copy.
##
## The ORDINAL ORDER is load-bearing and is asserted first: `ZombieCount`
## sorts by it and `spawnAllPossible`'s no-`break` type loop reads it, so a
## re-ordered enum is a rules change.

import std/[json, os, strutils]
import harness
import bc16_fixture

let tables = parseJson(readFile("data" / "bc16" / "tables.json"))

proc jvmName(k: RobotType): string = ($k).toUpperAscii()

# --- the ordinal order -----------------------------------------------------
block:
  const want = ["ZOMBIEDEN", "STANDARDZOMBIE", "RANGEDZOMBIE", "FASTZOMBIE",
                "BIGZOMBIE", "ARCHON", "SCOUT", "SOLDIER", "GUARD", "VIPER",
                "TURRET", "TTM"]
  var got: seq[string]
  for k in RobotType: got.add(jvmName(k))
  checkEq("RobotType is the engine's values() order, ordinal for ordinal",
    got, @want)
  checkEq("and there are exactly twelve", got.len, 12)
  for i, name in want:
    checkEq("ordinal " & $i & " is " & name, jvmName(typeOfOrdinal(i)), name)

# --- the seventeen constructor fields, cell by cell ------------------------
block:
  var mismatches: seq[string]
  for k in RobotType:
    let row = tables["robot_types"][jvmName(k)]
    let s = RobotSpecs[k]
    if s.isBuilding != row[0].getBool(): mismatches.add($k & ".isBuilding")
    if s.isZombie != row[1].getBool(): mismatches.add($k & ".isZombie")
    if s.infectTurns != row[2].getInt(): mismatches.add($k & ".infectTurns")
    let source = (if s.spawnSource < 0: "-"
                  else: jvmName(typeOfOrdinal(s.spawnSource)))
    if source != row[3].getStr(): mismatches.add($k & ".spawnSource")
    if s.partCost != row[4].getInt(): mismatches.add($k & ".partCost")
    if s.buildTurns != row[5].getInt(): mismatches.add($k & ".buildTurns")
    if s.maxHealth != row[6].getFloat(): mismatches.add($k & ".maxHealth")
    if s.attackPower != row[7].getFloat(): mismatches.add($k & ".attackPower")
    if s.attackRadiusSquared != row[8].getInt():
      mismatches.add($k & ".attackRadiusSquared")
    if s.movementDelay != row[9].getFloat():
      mismatches.add($k & ".movementDelay")
    if s.attackDelay != row[10].getFloat():
      mismatches.add($k & ".attackDelay")
    if s.cooldownDelay != row[11].getFloat():
      mismatches.add($k & ".cooldownDelay")
    if s.sensorRadiusSquared != row[12].getInt():
      mismatches.add($k & ".sensorRadiusSquared")
    if s.bytecodeLimit != row[13].getInt():
      mismatches.add($k & ".bytecodeLimit")
    let into = (if s.turnsInto < 0: "-"
                else: jvmName(typeOfOrdinal(s.turnsInto)))
    if into != row[14].getStr(): mismatches.add($k & ".turnsInto")
    if s.ignoresRubble != row[15].getBool():
      mismatches.add($k & ".ignoresRubble")
  checkEq("all 16 compared fields x 12 types match the JVM (" &
    $mismatches.join(", ") & ")", mismatches.len, 0)

# --- the eight derived predicates, all twelve types ------------------------
block:
  var mismatches: seq[string]
  for k in RobotType:
    let row = tables["predicates"][jvmName(k)]
    if canAttack(k) != row[0].getBool(): mismatches.add($k & ".canAttack")
    if canInfect(k) != row[1].getBool(): mismatches.add($k & ".canInfect")
    if isInfectable(k) != row[2].getBool():
      mismatches.add($k & ".isInfectable")
    if canMoveType(k) != row[3].getBool(): mismatches.add($k & ".canMove")
    if canBuildType(k) != row[4].getBool(): mismatches.add($k & ".canBuild")
    if canMessageSignal(k) != row[5].getBool():
      mismatches.add($k & ".canMessageSignal")
    if isBuildable(k) != row[6].getBool(): mismatches.add($k & ".isBuildable")
    if canClearRubble(k) != row[7].getBool():
      mismatches.add($k & ".canClearRubble")
  checkEq("all 8 predicates x 12 types match the JVM (" &
    $mismatches.join(", ") & ")", mismatches.len, 0)

  ## The individual facts the note names, spelled out so a reviewer can read
  ## them without the table.
  for k in [rtArchon, rtScout, rtTtm, rtZombieden]:
    check($k & " CANNOT attack", not canAttack(k))
  for k in [rtViper, rtStandardzombie, rtRangedzombie, rtFastzombie,
            rtBigzombie]:
    check($k & " CAN infect", canInfect(k))
  for k in PlayerTypes:
    check("every player unit is infectable, archons included: " & $k,
      isInfectable(k))
  for k in [rtZombieden, rtStandardzombie, rtRangedzombie, rtFastzombie,
            rtBigzombie]:
    check($k & " is NOT infectable", not isInfectable(k))
  check("a ZOMBIEDEN cannot move", not canMoveType(rtZombieden))
  check("and neither can a TURRET", not canMoveType(rtTurret))
  check("but a TTM can", canMoveType(rtTtm))
  check("ARCHON and ZOMBIEDEN are the only builders",
    canBuildType(rtArchon) and canBuildType(rtZombieden))
  check("ARCHON and SCOUT are the only message senders",
    canMessageSignal(rtArchon) and canMessageSignal(rtScout))
  for k in [rtSoldier, rtGuard, rtViper, rtTurret, rtTtm]:
    check($k & " cannot send a message signal", not canMessageSignal(k))
  check("A TTM IS NOT BUILDABLE — its spawnSource is TURRET, so it is only " &
    "reachable by packing", not isBuildable(rtTtm))
  for k in BuildableByArchon:
    check($k & " is buildable by an archon", isBuildable(k))
  check("an ARCHON cannot be built at all", not isBuildable(rtArchon))
  check("a TURRET cannot clear rubble", not canClearRubble(rtTurret))
  check("and neither can a TTM", not canClearRubble(rtTtm))
  check("but a SCOUT can", canClearRubble(rtScout))

# --- turnsInto, the whole graph -------------------------------------------
block:
  checkEq("an ARCHON turns into a BIGZOMBIE", turnsInto(rtArchon),
    rtBigzombie)
  checkEq("a SCOUT into a FASTZOMBIE", turnsInto(rtScout), rtFastzombie)
  checkEq("a SOLDIER into a STANDARDZOMBIE", turnsInto(rtSoldier),
    rtStandardzombie)
  checkEq("a GUARD into a STANDARDZOMBIE", turnsInto(rtGuard),
    rtStandardzombie)
  checkEq("a VIPER into a RANGEDZOMBIE", turnsInto(rtViper), rtRangedzombie)
  checkEq("a TURRET into a RANGEDZOMBIE", turnsInto(rtTurret),
    rtRangedzombie)
  checkEq("a TTM into a RANGEDZOMBIE", turnsInto(rtTtm), rtRangedzombie)
  for k in [rtZombieden, rtStandardzombie, rtRangedzombie, rtFastzombie,
            rtBigzombie]:
    check($k & " has no turnsInto", not hasTurnsInto(k))

# --- the outbreak ladder, and the arithmetic the survival finding turns on -
block:
  checkEq("a level-9 BIGZOMBIE is 1500 HP", maxHealthOf(rtBigzombie, 2700),
    1500.0)
  checkEq("and 75 damage", attackPowerOf(rtBigzombie, 2700), 75.0)
  checkEq("a level-0 BIGZOMBIE is 500 HP", maxHealthOf(rtBigzombie, 0),
    500.0)
  checkEq("and 25 damage", attackPowerOf(rtBigzombie, 0), 25.0)
  ## The 2016 combat arithmetic in one line each, which is why an unbroken den
  ## field beats a faction (docs/RULES-BC16.md section Divergences item 16).
  checkEq("a GUARD deals 3.0 a round to a zombie (1.5 x 2 at attackDelay 1)",
    RobotSpecs[rtGuard].attackPower * 2.0 /
      RobotSpecs[rtGuard].attackDelay, 3.0)
  checkEq("a SOLDIER deals 2.0 a round (4 at attackDelay 2)",
    RobotSpecs[rtSoldier].attackPower / RobotSpecs[rtSoldier].attackDelay,
    2.0)
  check("and a TURRET 4.33 a round (13 at attackDelay 3)",
    abs(RobotSpecs[rtTurret].attackPower /
        RobotSpecs[rtTurret].attackDelay - 4.333333333333333) < 1e-12)

# --- the guard block, played through the real world ------------------------
block:
  let w = bare()
  let g = w.put(rtGuard, loc(10, 10), teamA)
  let z = w.put(rtBigzombie, loc(11, 10), teamZombie)
  let before = g.health
  discard w.doAttack(z, g.loc)
  checkEq("a BIGZOMBIE's 25 on a GUARD lands as 21", before - g.health, 21.0)

block:
  let w = bare()
  let g = w.put(rtGuard, loc(10, 10), teamA)
  let z = w.put(rtStandardzombie, loc(11, 10), teamZombie)
  let before = g.health
  discard w.doAttack(z, g.loc)
  checkEq("a STANDARDZOMBIE's 2.5 on a GUARD lands as 2.5 (10 or below is " &
    "unreduced)", before - g.health, 2.5)

block:
  let w = bare()
  let g = w.put(rtGuard, loc(10, 10), teamA)
  let t = w.put(rtTurret, loc(13, 12), teamB)
  let before = g.health
  discard w.doAttack(t, g.loc)
  checkEq("a TURRET's 13 on a GUARD lands as 9", before - g.health, 9.0)

block:
  let w = bare()
  let g = w.put(rtGuard, loc(10, 10), teamA)
  let z = w.put(rtStandardzombie, loc(11, 10), teamZombie)
  let before = z.health
  discard w.doAttack(g, z.loc)
  checkEq("a GUARD deals 3.0 to a zombie", before - z.health, 3.0)
  let e = w.put(rtSoldier, loc(9, 10), teamB)
  let beforeE = e.health
  ## The guard's attackDelay is 1.0 and readiness is STRICTLY `< 1`, so it is
  ## not ready again until a `decrementDelays`. That is the rule, not a
  ## nuisance — assert it, then let the round tick.
  check("the guard is NOT ready again at weapon delay exactly 1.0",
    not w.doAttack(g, e.loc))
  g.d.decrementDelays()
  check("and IS after one decrement", w.doAttack(g, e.loc))
  checkEq("and 1.5 to a player unit", beforeE - e.health, 1.5)

# --- the TURRET's minimum range -------------------------------------------
block:
  let w = bare()
  let t = w.put(rtTurret, loc(10, 10), teamA)
  check("a turret refuses r2 5 (2,1 away)",
    not w.canAttackLocation(t, loc(12, 11)))
  checkEq("which really is r2 5", loc(10, 10).distanceSquaredTo(loc(12, 11)),
    5)
  check("and accepts exactly r2 6", w.canAttackLocation(t, loc(12, 11 + 1)))
  checkEq("which really is r2 8", loc(10, 10).distanceSquaredTo(loc(12, 12)),
    8)
  ## The exact boundary: (1, 2) is r2 5 and refused; a square at r2 exactly 6
  ## does not exist on an integer lattice from (0,0) — the smallest above 5 is
  ## (1, 2) -> 5 then (0, 3) -> 9 / (2, 2) -> 8. So the boundary is asserted on
  ## the PREDICATE, over every square in the 12x12 neighbourhood.
  var refused = 0
  var accepted = 0
  for dx in -8 .. 8:
    for dy in -8 .. 8:
      let l = loc(10 + dx, 10 + dy)
      if not w.onTheMap(l): continue
      let d2 = t.loc.distanceSquaredTo(l)
      let ok = w.canAttackLocation(t, l)
      if d2 < 6 or d2 > 40:
        if ok: inc refused
      else:
        if ok: inc accepted else: inc refused
  checkEq("no square inside r2 6 or beyond r2 40 is attackable, and every " &
    "square between them is", refused, 0)
  check("and the accepted set is not empty", accepted > 0)
  check("r2 40 exactly is accepted", w.canAttackLocation(t, loc(10 + 6, 10 + 2)))
  checkEq("which really is r2 40",
    loc(10, 10).distanceSquaredTo(loc(16, 12)), 40)
  check("r2 41 is not", not w.canAttackLocation(t, loc(10 + 5, 10 + 4)))
  checkEq("which really is r2 41",
    loc(10, 10).distanceSquaredTo(loc(15, 14)), 41)

# --- an attack on an EMPTY square and on an ALLY are both LEGAL ------------
block:
  ## `attackLocation` has NO team check, NO vision test and NO target test.
  ## Both cost full delay. The chassis must never use friendly fire — that is
  ## `tests/test_bc16_baselines.nim`'s job — but the RULE permits it.
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  let refusedBefore = w.refusedActions
  check("an attack on an EMPTY square is legal", w.doAttack(s, loc(12, 12)))
  checkEq("and costs the full weapon delay", s.d.weapon, 2.0)
  checkEq("and is not a refusal", w.refusedActions, refusedBefore)
  let ally = w.put(rtSoldier, loc(9, 10), teamA)
  s.d.weapon = 0.0
  let before = ally.health
  check("an attack on an ALLY is legal — friendly fire IS legal in 2016",
    w.doAttack(s, ally.loc))
  checkEq("and it really hurts", before - ally.health, 4.0)

# --- an attack needs no vision --------------------------------------------
block:
  let w = bare()
  let t = w.put(rtTurret, loc(10, 10), teamA)
  let e = w.put(rtSoldier, loc(16, 12), teamB)
  checkEq("the target is at r2 40, inside reach", t.loc.distanceSquaredTo(
    e.loc), 40)
  check("and inside the turret's sight r2 24? no", not w.canSense(t, e.loc))
  check("but the attack is legal anyway — 2016 needs no vision to shoot",
    w.doAttack(t, e.loc))

finish("test_bc16_units")
