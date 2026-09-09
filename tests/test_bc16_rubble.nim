## Shard 3 of the note's list — **the rubble economy**, this year's terrain.
##
## `< 100` passable and `>= 100` not, EXCEPT for a SCOUT, a FASTZOMBIE and a
## BIGZOMBIE which pass anything; `>= 50` doubles BOTH the movement and the
## cooldown charge and `< 50` doubles neither; `clearRubble` is
## `max(0, 0.95r - 10)`; and every UNINFECTED corpse adds its own max health
## to its square — a third of it when a TURRET landed the killing blow.

import std/[math]
import harness
import bc16_fixture

# --- the two thresholds ----------------------------------------------------
block:
  checkEq("RUBBLE_OBSTRUCTION_THRESH is 100", RubbleObstructionThresh, 100.0)
  checkEq("RUBBLE_SLOW_THRESH is 50", RubbleSlowThresh, 50.0)
  for k in [rtSoldier, rtGuard, rtViper, rtArchon, rtTurret, rtTtm,
            rtStandardzombie, rtRangedzombie]:
    check($k & " is blocked at exactly 100", rubbleBlocks(100.0, k))
    check("and passes at 99.99999", not rubbleBlocks(99.99999, k))
  for k in [rtScout, rtFastzombie, rtBigzombie]:
    check($k & " IGNORES RUBBLE and passes 10^6",
      not rubbleBlocks(1_000_000.0, k))
    check("and is never slowed", not rubbleSlows(1_000_000.0, k))
  for k in [rtSoldier, rtGuard, rtViper, rtArchon]:
    check($k & " is slowed at exactly 50", rubbleSlows(50.0, k))
    check("and not at 49.99999", not rubbleSlows(49.99999, k))

# --- the double charge hits BOTH counters ---------------------------------
block:
  ## `factor3 = 2.0` multiplies BOTH `setWeaponDelayUpTo(cooldownDelay *
  ## factor3)` AND `coreDelay += movementDelay * factor1 * factor3`.
  let w = bare(rubble = @[(loc(11, 10), 60.0), (loc(11, 12), 49.0)])
  let a = w.put(rtSoldier, loc(10, 10), teamA)
  discard w.doMove(a, dEast)
  checkEq("stepping onto rubble 60 doubles the core charge: 2 * 2 = 4",
    a.d.core, 4.0)
  checkEq("and doubles the cooldown charge: 1 * 2 = 2", a.d.weapon, 2.0)
  let b = w.put(rtSoldier, loc(10, 12), teamA)
  discard w.doMove(b, dEast)
  checkEq("stepping onto rubble 49 doubles neither: core 2", b.d.core, 2.0)
  checkEq("and weapon 1", b.d.weapon, 1.0)

# --- the clear formula, with the note's vectors ----------------------------
block:
  checkEq("100 -> 85", rubbleAfterClear(100.0), 85.0)
  checkEq("10 -> 0 (0.95*10 - 10 is negative, and max(0, ...) floors it)",
    rubbleAfterClear(10.0), 0.0)
  checkEq("0 -> 0", rubbleAfterClear(0.0), 0.0)
  checkEq("1 000 000 -> 949 990", rubbleAfterClear(1_000_000.0), 949990.0)
  checkEq("1000 -> 940", rubbleAfterClear(1000.0), 940.0)
  ## **A NOTE CORRECTION, measured.** The design note says "14 clears take a
  ## 100 to 0 and 55 take a 1000". The arithmetic says **8** and **35**:
  ## `0.95r - 10` is a contraction with a FLAT 10 subtracted every action, so
  ## it converges far faster than the 5 % term alone suggests
  ## (100 -> 85 -> 70.75 -> 57.2125 -> 44.35 -> 32.13 -> 20.52 -> 9.50 -> 0).
  ## The note's numbers came from the percentage term alone. Recorded in
  ## `docs/RULES-BC16.md` section "Corrections to the design note"; the RULE
  ## is unchanged and is the engine's.
  var r = 100.0
  var actions = 0
  while r > 0.0 and actions < 200:
    r = rubbleAfterClear(r)
    inc actions
  checkEq("EIGHT actions take a 100 to 0 (the note said fourteen)",
    actions, 8)
  r = 1000.0
  actions = 0
  while r > 0.0 and actions < 500:
    r = rubbleAfterClear(r)
    inc actions
  checkEq("and THIRTY-FIVE take a 1000 (the note said fifty-five)",
    actions, 35)

block:
  ## A square at EXACTLY 0 is a legal no-op that costs nothing — a rule, not
  ## a refusal (`RobotControllerImpl:459-461` returns before charging).
  let w = bare(rubble = @[(loc(11, 10), 100.0)])
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  discard w.doClearRubble(s, dEast)
  checkEq("one clear takes 100 to 85", w.getRubble(loc(11, 10)), 85.0)
  checkEq("and the tenths counter records 15.0 of rubble cleared",
    w.stats.rubbleClearedTenths[0], 150)
  checkEq("and the square is now PASSABLE, so squares_opened is 1",
    w.stats.squaresOpened[0], 1)
  check("a TURRET cannot clear at all",
    not w.canClearRubble(w.put(rtTurret, loc(20, 20), teamA), dEast))
  check("and neither can a TTM",
    not w.canClearRubble(w.put(rtTtm, loc(22, 20), teamA), dEast))

# --- the corpse deposit ----------------------------------------------------
block:
  ## An UNINFECTED death raises the square's rubble by the dead robot's OWN
  ## maximum health.
  let w = bare()
  let g = w.put(rtGuard, loc(10, 10), teamA)
  checkEq("the square starts clear", w.getRubble(loc(10, 10)), 0.0)
  w.changeHealthLevel(g, -1000.0, dcNormal)
  checkEq("a GUARD's corpse adds its own 145", w.getRubble(loc(10, 10)),
    145.0)

block:
  let w = bare()
  let a = w.put(rtArchon, loc(12, 12), teamA)
  w.changeHealthLevel(a, -5000.0, dcNormal)
  checkEq("an ARCHON's corpse adds 1000", w.getRubble(loc(12, 12)), 1000.0)

block:
  ## A BIGZOMBIE's corpse is its own OUTBREAK-SCALED max health: 500 at level
  ## 0 and 1500 at level 9.
  let w = bare()
  let z0 = w.put(rtBigzombie, loc(5, 5), teamZombie)
  w.changeHealthLevel(z0, -5000.0, dcNormal)
  checkEq("a level-0 BIGZOMBIE's corpse adds 500", w.getRubble(loc(5, 5)),
    500.0)
  w.currentRound = 2700
  let z9 = w.put(rtBigzombie, loc(7, 7), teamZombie)
  checkEq("a level-9 BIGZOMBIE spawns at 1500 HP", z9.maxHealth, 1500.0)
  w.changeHealthLevel(z9, -5000.0, dcNormal)
  checkEq("and its corpse adds 1500", w.getRubble(loc(7, 7)), 1500.0)

block:
  ## A TURRET kill cuts the deposit to a third:
  ## `145 * (1.0/3.0) = 48.33333333333333` (MEASURED against the JVM — the
  ## design note's `...336` was one ulp out, see `tests/test_bc16_arith.nim`).
  let w = bare()
  let g = w.put(rtGuard, loc(10, 10), teamA)
  w.changeHealthLevel(g, -1000.0, dcTurret)
  checkEq("a TURRET kill deposits one third of the max health",
    w.getRubble(loc(10, 10)), 48.33333333333333)
  checkEq("rubbleFactorFor(dcTurret) is the double 1/3 rounds to",
    rubbleFactorFor(dcTurret), 0.3333333333333333)
  checkEq("and 1.0 otherwise", rubbleFactorFor(dcNormal), 1.0)

block:
  ## AN INFECTED CORPSE ADDS NOTHING. The two effects are exclusive: you
  ## either get a wall or you get an enemy zombie, never both. That single
  ## `if` is the reason `infection_policy` is a real knob.
  let w = bare()
  let g = w.put(rtGuard, loc(10, 10), teamA)
  g.inf.setInfected(rtStandardzombie)
  check("the guard is infected", g.inf.isInfected())
  w.changeHealthLevel(g, -1000.0, dcNormal)
  checkEq("an INFECTED corpse leaves NO rubble", w.getRubble(loc(10, 10)),
    0.0)
  let z = w.getRobot(loc(10, 10))
  check("and a zombie stands up on its square instead", z != nil)
  checkEq("of the right type", z.kind, rtStandardzombie)
  checkEq("on the horde's team", z.team, teamZombie)

block:
  ## An ACTIVATION death skips BOTH the deposit and the conversion.
  let w = bare()
  let a = w.at(3, 15)
  let n = w.put(rtSoldier, loc(4, 15), teamNeutral)
  n.inf.setInfected(rtStandardzombie)
  check("even an INFECTED neutral", n.inf.isInfected())
  discard w.doActivate(a, n.loc)
  checkEq("activation leaves no rubble", w.getRubble(loc(4, 15)), 0.0)
  let after = w.getRobot(loc(4, 15))
  check("and the square carries OUR soldier, not a zombie",
    after != nil and after.team == teamA and after.kind == rtSoldier)

# --- the rubble the map itself carries ------------------------------------
block:
  ## The port stores rubble as `SquareArray.Double` does: a flat `float64`
  ## array indexed `y*width + x`, so the two checksums line up.
  let w = bare(rubble = @[(loc(3, 7), 123.5)])
  checkEq("rubble is indexed y*width + x", w.rubble[7 * TestWidth + 3],
    123.5)
  checkEq("and getRubble reads the same cell", w.getRubble(loc(3, 7)), 123.5)
  checkEq("off the map reads 0", w.getRubble(loc(-1, 0)), 0.0)

finish("test_bc16_rubble")
