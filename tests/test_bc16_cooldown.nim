## Shard 1 of the note's list — **the delay pair, this year's whole tempo.**
##
## Both counters are FLOAT64; `decrementDelays` subtracts exactly **1.0** and
## floors each at 0.0 (V1); readiness is **strictly `< 1`**; and the set/add
## pairing is asserted PER ACTION, because getting it backwards is the easiest
## way to break bc16 and it is invisible until a parity trace diverges four
## hundred rounds later:
##
##     activateCoreAction(a, m):  setWeaponDelayUpTo(a);  addCoreDelay(m)
##     activateAttack(a, m):      addWeaponDelay(a);      setCoreDelayUpTo(m)
##
## They are OPPOSITE in both the set/add choice AND in which counter takes
## which argument.

import std/math
import harness
import bc16_fixture

# --- decrementDelays: exactly 1.0, both counters, floored separately --------
block:
  var d = initDelays()
  d.core = 5.6
  d.weapon = 2.0
  d.decrementDelays()
  checkEq("decrementDelays takes exactly 1.0 off the core", d.core, 4.6)
  checkEq("and exactly 1.0 off the weapon", d.weapon, 1.0)
  checkEq("V1 pins amountToDecrement to 1.0", PinnedDecrement, 1.0)
  d.core = 0.4
  d.weapon = 0.0
  d.decrementDelays()
  checkEq("the core floors at 0, never negative", d.core, 0.0)
  checkEq("and so does the weapon, independently", d.weapon, 0.0)
  ## The two floors are INDEPENDENT `if`s in the engine, so one counter
  ## flooring must not clamp the other.
  d.core = 0.25
  d.weapon = 7.0
  d.decrementDelays()
  check("one counter flooring leaves the other alone",
    d.core == 0.0 and d.weapon == 6.0)

# --- readiness is STRICTLY < 1 on a float64 --------------------------------
block:
  var d = initDelays()
  d.core = 1.0
  d.weapon = 1.0
  check("core delay EXACTLY 1.0 is NOT ready", not d.isCoreReady())
  check("weapon delay EXACTLY 1.0 is NOT ready", not d.isWeaponReady())
  d.core = 0.9999999999999999
  d.weapon = 0.9999999999999999
  check("and the largest double below 1 IS ready",
    d.isCoreReady() and d.isWeaponReady())
  d.core = 0.0
  check("zero is ready", d.isCoreReady())

# --- the two composite helpers are OPPOSITE --------------------------------
block:
  var a = initDelays()
  a.weapon = 7.0
  a.activateCoreAction(3.0, 2.0)
  check("activateCoreAction SETS the weapon UP TO (so 7 stays 7)",
    a.weapon == 7.0)
  checkEq("and ADDS to the core", a.core, 2.0)
  var b = initDelays()
  b.core = 7.0
  b.activateAttack(3.0, 2.0)
  checkEq("activateAttack ADDS to the weapon", b.weapon, 3.0)
  check("and SETS the core UP TO (so 7 stays 7)", b.core == 7.0)
  var c = initDelays()
  c.activateCoreAction(3.0, 2.0)
  check("set-up-to raises a lower counter", c.weapon == 3.0)

# --- per-action vectors, played through the real world ---------------------
block:
  ## A soldier's DIAGONAL step onto rubble 60 charges core 5.6 and weapon 2.0
  ## — the diagonal multiplier hits the CORE ONLY.
  let w = bare(rubble = @[(loc(11, 11), 60.0)])
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  check("the diagonal step is legal", w.doMove(s, dSoutheast))
  checkEq("a soldier's diagonal step onto rubble 60: core 2 * 1.4 * 2 = 5.6",
    s.d.core, 5.6)
  checkEq("and weapon = cooldownDelay 1 * factor3 2 = 2.0", s.d.weapon, 2.0)
  checkEq("2 * 1.4 is exactly 2.8 in float64", 2.0 * 1.4, 2.8)
  checkEq("and 2 * 1.4 * 2 is exactly 5.6", 2.0 * 1.4 * 2.0, 5.6)

block:
  ## The same step ORTHOGONALLY onto clear ground: core 2, weapon up-to 1.
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  discard w.doMove(s, dEast)
  checkEq("an orthogonal step on clear ground charges core 2", s.d.core, 2.0)
  checkEq("and weapon up-to the cooldown delay 1", s.d.weapon, 1.0)

block:
  ## A soldier's ATTACK: weapon +2 (attackDelay), core UP TO 1 (cooldown).
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  let e = w.put(rtSoldier, loc(12, 10), teamB)
  check("the attack is legal", w.doAttack(s, e.loc))
  checkEq("a soldier's attack ADDS attackDelay 2 to the weapon", s.d.weapon,
    2.0)
  checkEq("and sets the core UP TO cooldownDelay 1", s.d.core, 1.0)

block:
  ## A TURRET's attack: weapon +3, core up-to 3.
  let w = bare()
  let t = w.put(rtTurret, loc(10, 10), teamA)
  let e = w.put(rtSoldier, loc(13, 12), teamB)
  checkEq("r2 13 is inside the turret's 40 and outside its minimum 6",
    t.loc.distanceSquaredTo(e.loc), 13)
  check("the turret's attack is legal", w.doAttack(t, e.loc))
  checkEq("a turret's attack ADDS attackDelay 3", t.d.weapon, 3.0)
  checkEq("and sets the core UP TO cooldownDelay 3", t.d.core, 3.0)

block:
  ## `pack` / `unpack`: +10 on BOTH counters and NO READINESS CHECK AT ALL.
  let w = bare()
  let t = w.put(rtTurret, loc(10, 10), teamA)
  t.d.core = 4.0
  t.d.weapon = 6.0
  check("pack works with both counters loaded (no readiness check)",
    w.doTransform(t))
  checkEq("pack ADDS 10 to the core", t.d.core, 14.0)
  checkEq("and ADDS 10 to the weapon", t.d.weapon, 16.0)
  checkEq("and it is now a TTM", t.kind, rtTtm)
  check("unpack likewise needs no readiness", w.doTransform(t))
  checkEq("unpack adds another 10 to the core", t.d.core, 24.0)
  checkEq("and another 10 to the weapon", t.d.weapon, 26.0)
  checkEq("and it is a TURRET again", t.kind, rtTurret)
  checkEq("TURRET_TRANSFORM_DELAY is 10 on both", TurretTransformDelay, 10)

block:
  ## A VIPER build: weapon UP TO 30, core +30 — the archon is frozen for
  ## thirty of its own turns.
  let w = bare()
  let a = w.at(3, 15)
  check("the archon is there", a != nil and a.kind == rtArchon)
  w.adjustResources(teamA, 500.0)
  check("the viper build is legal", w.doBuild(a, dEast, rtViper))
  checkEq("a VIPER build sets the weapon UP TO buildTurns 30", a.d.weapon,
    30.0)
  checkEq("and ADDS buildTurns 30 to the core", a.d.core, 30.0)

block:
  ## `activate`: weapon UP TO 0 (i.e. unchanged) and core +2.
  let w = bare()
  let a = w.at(3, 15)
  a.d.weapon = 4.0
  discard w.put(rtSoldier, loc(4, 15), teamNeutral)
  check("the activation is legal", w.doActivate(a, loc(4, 15)))
  checkEq("activate sets the weapon UP TO 0, so 4 stays 4", a.d.weapon, 4.0)
  checkEq("and adds 2 to the core", a.d.core, 2.0)

block:
  ## `repair` costs NOTHING of either kind — it never goes through
  ## `activateCoreAction` at all, and it is the only healing in the game.
  let w = bare()
  let a = w.at(3, 15)
  let s = w.put(rtSoldier, loc(5, 15), teamA)
  s.health = 40.0
  check("the repair is legal", w.doRepair(a, s.loc))
  checkEq("repair costs no core delay", a.d.core, 0.0)
  checkEq("and no weapon delay", a.d.weapon, 0.0)
  checkEq("and heals exactly 1.0", s.health, 41.0)
  check("and it is capped at one repair a turn",
    not w.doRepair(a, s.loc))

block:
  ## `clearRubble` on a square at EXACTLY 0 does nothing AND COSTS NOTHING —
  ## `RobotControllerImpl:459-461` returns before charging. It is a LEGAL call
  ## and not a refusal.
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  let before = w.refusedActions
  check("clearing a 0 square is legal", w.doClearRubble(s, dEast))
  checkEq("and costs no core delay", s.d.core, 0.0)
  checkEq("and no weapon delay", s.d.weapon, 0.0)
  checkEq("and is not counted as a refused action", w.refusedActions, before)
  checkEq("and the square is still 0", w.getRubble(loc(11, 10)), 0.0)

block:
  ## A real clear DOES charge: weapon up-to cooldown, core += movementDelay.
  ## A SCOUT is the cheapest digger in the game at movementDelay 1.4.
  let w = bare(rubble = @[(loc(11, 10), 100.0), (loc(11, 12), 100.0)])
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  check("a real clear is legal", w.doClearRubble(s, dEast))
  checkEq("a soldier's clear charges core movementDelay 2", s.d.core, 2.0)
  checkEq("and weapon up-to cooldownDelay 1", s.d.weapon, 1.0)
  let sc = w.put(rtScout, loc(10, 12), teamA)
  check("a scout's clear is legal", w.doClearRubble(sc, dEast))
  checkEq("a scout's clear charges core 1.4 — the cheapest digger",
    sc.d.core, 1.4)

# --- decrementDelays runs for a robot that CANNOT act ----------------------
block:
  ## `processBeginningOfTurn` decrements for EVERY robot, which is why a
  ## robot's delays keep draining while it is being built.
  let w = bare()
  let v = w.put(rtViper, loc(10, 10), teamA, buildDelay = 30)
  v.d.core = 3.0
  check("a robot inside its build delay is not active", not v.isActive())
  v.d.decrementDelays()
  checkEq("but its delays still drain", v.d.core, 2.0)

# --- the engine's whole formula is KNOWN even though it is not used --------
block:
  ## V1: no rule calls `engineDecrement`. It exists so the divergence is
  ## MEASURED. Inside `limit - 8000` the engine itself produces exactly 1.0,
  ## which is the value the port pins.
  checkEq("a 10 000-limit unit at 2000 ops decrements by exactly 1.0",
    engineDecrement(10_000, 2000), 1.0)
  checkEq("an archon at 12 000 likewise", engineDecrement(20_000, 12_000),
    1.0)
  checkEq("and at zero prev-bytecodes likewise",
    engineDecrement(10_000, 0), 1.0)
  ## Above the knee it is strictly below 1 — the branch parity cannot compare.
  check("at the very top of the limit it is 1 - 0.3 = 0.7",
    abs(engineDecrement(10_000, 10_000) - 0.7) < 1e-12)
  check("and it is monotonically non-increasing in prevBytecodesUsed",
    engineDecrement(10_000, 6000) >= engineDecrement(10_000, 9000))

finish("test_bc16_cooldown")
