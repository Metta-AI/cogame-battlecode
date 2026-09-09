## Shard 21 of the note's list — **the float64 fidelity shard**, and the one
## that reads the whole finite arithmetic domain out of the JDK-generated
## `data/bc16/tables.json`.
##
## 2016 is a FLOAT64 year where 2022 was an integer one: health, damage,
## delays, rubble, parts and every multiplier are `double`. IEEE-754 binary64
## add/subtract/multiply/divide/compare are exactly specified and identical on
## x86-64 SSE2 and on wasm32, so a port that reproduces each expression IN THE
## ENGINE'S OWN ORDER AND PARENTHESISATION is bit-exact by construction. This
## shard is what says so: every named product is asserted as a bit-exact
## float64 literal, and every tabled function is compared against the JVM's own
## values cell by cell.
##
## `data/bc16/tables.json` is regenerated under the CI JDK 8 by
## `tools/JavaBc16Tables.java` out of the released jar's own classes and
## byte-diffed by the `parity-oracle-bc16` job, so the numbers on the right of
## every comparison here are the ENGINE's and not this repository's.
##
## THREE CORRECTIONS TO THE DESIGN NOTE, each MEASURED against the JVM in this
## sandbox with a Temurin 8 and the pinned oracle jar, each recorded in
## `docs/RULES-BC16.md` section "Corrections to the design note". In all three
## the PORT was already right and the note's prose was wrong, which is what
## having a real oracle is for:
##
##  1. `2.0 - 0.01 * 137` is **`0.6299999999999999`**, not `0.63`. `0.01` is
##     not representable, `0.01 * 137` rounds a hair above `1.37`, and the
##     JVM's own `parts_income[137]` says the same.
##  2. `60 * 1.1` is **`66.0`**, not `66.00000000000001` -- verified in Java
##     both as a constant expression and at run time.
##  3. `145 * (1.0/3.0)` is **`48.33333333333333`**, not `48.333333333333336`
##     -- one ulp out in the note, verified the same two ways.
##
## And one the note did not state and the lattice settles: `directionTo(self)`
## is **OMNI (ordinal 9)**, not NONE.

import std/[json, math, os, strutils]
import harness
import bc16_fixture

let tables = parseJson(readFile("data" / "bc16" / "tables.json"))

# --- the named products, bit for bit ---------------------------------------
block:
  checkEq("2 * 1.4 = 2.8", 2.0 * 1.4, 2.8)
  checkEq("2 * 1.4 * 2 = 5.6", 2.0 * 1.4 * 2.0, 5.6)
  checkEq("1.4 * 1.4 = 1.9599999999999997", 1.4 * 1.4, 1.9599999999999997)
  checkEq("60 * 1.1 = 66.0 (the note said 66.00000000000001; the JVM says\n    66.0)", 60.0 * 1.1, 66.0)
  checkEq("145 * (1.0/3.0) = 48.33333333333333 (the note said ...36)",
    145.0 * (1.0 / 3.0), 48.33333333333333)
  checkEq("100 * 0.95 - 10 = 85", (100.0 * 0.95) - 10.0, 85.0)
  checkEq("2.0 - 0.01 * 137 = 0.6299999999999999 (NOT 0.63)",
    2.0 - 0.01 * 137.0, 0.6299999999999999)
  check("and 0.63 is a DIFFERENT double", (2.0 - 0.01 * 137.0) != 0.63)
  checkEq("the JVM agrees, from its own table",
    tables["parts_income"][137].getFloat(), 2.0 - 0.01 * 137.0)
  checkEq("RUBBLE_FROM_TURRET_FACTOR is the double 1.0/3.0 rounds to",
    RubbleFromTurretFactor, 0.3333333333333333)

# --- the outbreak ladder ---------------------------------------------------
block:
  let mult = tables["outbreak_multiplier"]
  for level in 0 .. 12:
    checkEq("outbreak multiplier at level " & $level,
      outbreakMultiplier(level * 300), mult[level].getFloat())
  checkEq("level 9 is the last a 3000-round game reaches",
    outbreakLevel(2999), 9)
  checkEq("and round 3000 would be level 10", outbreakLevel(3000), 10)
  checkEq("round 0 is level 0", outbreakLevel(0), 0)
  checkEq("round 299 is still level 0", outbreakLevel(299), 0)
  checkEq("round 300 is level 1", outbreakLevel(300), 1)
  ## A level-9 BIGZOMBIE is 1500 HP and 75 damage — the arithmetic the design
  ## note's survival finding turns on.
  checkEq("a level-9 BIGZOMBIE has 1500 HP",
    maxHealthOf(rtBigzombie, 2700), 1500.0)
  checkEq("and 75 damage", attackPowerOf(rtBigzombie, 2700), 75.0)

block:
  ## Every type at every level, against the JVM's own `maxHealth(round)` and
  ## `attackPower(round)` — including that a PLAYER unit never scales.
  var mismatches = 0
  for k in RobotType:
    let name = ($k).toUpperAscii()
    let hp = tables["outbreak_health"][name]
    let atk = tables["outbreak_attack"][name]
    for level in 0 .. 12:
      if maxHealthOf(k, level * 300) != hp[level].getFloat(): inc mismatches
      if attackPowerOf(k, level * 300) != atk[level].getFloat():
        inc mismatches
  checkEq("the whole outbreak lattice matches the JVM, 12 types x 13 levels",
    mismatches, 0)
  checkEq("a SOLDIER at level 9 still deals 4 — player units never scale",
    attackPowerOf(rtSoldier, 2700), 4.0)
  checkEq("and still has 60 HP", maxHealthOf(rtSoldier, 2700), 60.0)

# --- (int) Math.sqrt(r2) for r2 0..10 000 ----------------------------------
block:
  let want = tables["int_sqrt"]
  checkEq("the table covers r2 0..10 000", want.len, 10001)
  var mismatches = 0
  for r2 in 0 .. 10000:
    if intSqrt(r2) != want[r2].getInt(): inc mismatches
  checkEq("every one of the 10 001 floor-sqrt values matches the JVM",
    mismatches, 0)
  ## No `sqrt` on any runtime path: the port's own table is a compile-time
  ## `const`, so this is a comparison of two tables and not of two algorithms.
  checkEq("and the reachable radii are exact", intSqrt(53), 7)
  checkEq("r2 40 (the turret's reach)", intSqrt(40), 6)
  checkEq("r2 6 (the turret's minimum)", intSqrt(6), 2)

# --- the directionTo lattice, dx, dy in -80..80 ----------------------------
block:
  let want = tables["direction_to"]
  checkEq("the lattice is 161 x 161 = 25 921 pairs", want.len, 25921)
  var mismatches = 0
  var i = 0
  for dy in -80 .. 80:
    for dx in -80 .. 80:
      let got = ord(loc(0, 0).directionTo(loc(dx, dy)))
      if got != want[i].getInt(): inc mismatches
      inc i
  checkEq("every one of the 25 921 directionTo cells matches the JVM",
    mismatches, 0)
  checkEq("directionTo(self) is OMNI (ordinal 9), measured off the JVM",
    ord(loc(5, 5).directionTo(loc(5, 5))), 9)
  ## 2016's NORTH is (0, -1): the y axis grows SOUTHWARD, which is the
  ## opposite of bc22's port and is why this year has its own `Dir`.
  checkEq("straight up is NORTH", loc(5, 5).directionTo(loc(5, 4)), dNorth)
  checkEq("straight down is SOUTH", loc(5, 5).directionTo(loc(5, 6)), dSouth)
  checkEq("and the 2.414 threshold puts (1, -3) at NORTH",
    loc(0, 0).directionTo(loc(1, -3)), dNorth)
  checkEq("while (2, -3) crosses it to NORTHEAST",
    loc(0, 0).directionTo(loc(2, -3)), dNortheast)

# --- the rubble clear map --------------------------------------------------
block:
  let want = tables["rubble_clear"]
  var mismatches = 0
  for r in 0 .. 1000:
    if rubbleAfterClear(float64(r)) != want[r].getFloat(): inc mismatches
  checkEq("max(0, 0.95r - 10) matches the JVM for r 0..1000", mismatches, 0)
  for key, value in tables["rubble_clear_decades"]:
    checkEq("and at the decade " & key,
      rubbleAfterClear(parseFloat(key)), value.getFloat())

# --- the parts income curve ------------------------------------------------
block:
  let want = tables["parts_income"]
  checkEq("the curve covers 0..400 robots", want.len, 401)
  var mismatches = 0
  let w = bare()
  for n in 0 .. 400:
    let got = max(0.0, ArchonPartIncome - PartIncomeUnitPenalty * float64(n))
    if got != want[n].getFloat(): inc mismatches
  checkEq("max(0, 2 - 0.01n) matches the JVM for every n 0..400", mismatches,
    0)
  checkEq("income is EXACTLY zero at 200 robots", want[200].getFloat(), 0.0)
  check("and it never goes negative", want[400].getFloat() == 0.0)
  discard w

# --- the guard reduction and the guard multiplier --------------------------
block:
  for key, value in tables["guard_reduction"]:
    let raw = parseFloat(key)
    checkEq("guard reduction at raw " & key,
      damageToTarget(raw, rtGuard), value.getFloat())
  checkEq("a guard hit for 2.5 takes 2.5", damageToTarget(2.5, rtGuard), 2.5)
  checkEq("a guard hit for exactly 10 takes 10 (STRICTLY greater)",
    damageToTarget(10.0, rtGuard), 10.0)
  checkEq("a guard hit for 13 takes 9", damageToTarget(13.0, rtGuard), 9.0)
  checkEq("a guard hit for 25 takes 21", damageToTarget(25.0, rtGuard), 21.0)
  checkEq("a SOLDIER hit for 25 takes all 25",
    damageToTarget(25.0, rtSoldier), 25.0)
  checkEq("a GUARD attacking a zombie doubles",
    guardRate(rtGuard, rtStandardzombie), 2.0)
  checkEq("and against a player unit does not",
    guardRate(rtGuard, rtSoldier), 1.0)
  checkEq("a SOLDIER attacking a zombie does not double",
    guardRate(rtSoldier, rtStandardzombie), 1.0)
  checkEq("so a guard deals 3.0 to a zombie",
    RobotSpecs[rtGuard].attackPower * guardRate(rtGuard, rtBigzombie), 3.0)
  checkEq("and 1.5 to a player unit",
    RobotSpecs[rtGuard].attackPower * guardRate(rtGuard, rtSoldier), 1.5)

# --- the signal delay formula ----------------------------------------------
block:
  checkEq("a broadcast at r2 = 2 x sightR2 costs the flat 0.05",
    broadcastDelayIncrease(48, 24), 0.05)
  checkEq("at r2 = 3 x sightR2 it costs 0.08",
    broadcastDelayIncrease(72, 24), 0.08)
  checkEq("and inside twice the sight radius it is still the flat base",
    broadcastDelayIncrease(4, 24), 0.05)

# --- the move factors ------------------------------------------------------
block:
  checkEq("the diagonal multiplier is 1.4", DiagonalDelayMultiplier, 1.4)
  checkEq("moveFactor1 is 1.4 on a diagonal", moveFactor1(dNortheast), 1.4)
  checkEq("and 1.0 orthogonally", moveFactor1(dNorth), 1.0)
  checkEq("moveFactor3 doubles at exactly rubble 50",
    moveFactor3(50.0, rtSoldier), 2.0)
  checkEq("and does not at 49.999999", moveFactor3(49.999999, rtSoldier),
    1.0)
  checkEq("a SCOUT ignores rubble entirely", moveFactor3(999999.0, rtScout),
    1.0)

finish("test_bc16_arith")
