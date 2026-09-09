## Shard 10 of the note's list — **free neutral activation**, which is this
## year's cheapest unit and, on 22 of the 98 official maps, a whole extra
## tiebreak rung.
##
## ARCHON only; `d2 <= ARCHON_ACTIVATION_RANGE = 2` (so the eight neighbours
## and the archon's own square, since a diagonal is r2 2); the target must
## exist and must be **NEUTRAL**; core ready. The neutral is removed with
## **no rubble and no zombie**, an identical type is spawned on the
## activator's team with **`buildDelay 0`, immediately active**, and the cost
## is **weapon up-to 0, core +2**.

import harness
import bc16_fixture

# --- ARCHON only, r2 <= 2, NEUTRAL only, core ready -----------------------
block:
  let w = bare()
  let a = w.at(3, 15)
  discard w.put(rtSoldier, loc(4, 15), teamNeutral)
  checkEq("ARCHON_ACTIVATION_RANGE is 2", ArchonActivationRange, 2)
  check("an archon can activate an adjacent neutral",
    w.canActivate(a, loc(4, 15)))
  for k in [rtSoldier, rtGuard, rtScout, rtViper, rtTurret, rtTtm]:
    let r = w.put(k, loc(3, 17), teamA)
    check("a " & $k & " cannot activate", not w.canActivate(r, loc(4, 15)))
    w.visitDeathSignal(r, dcActivation)

block:
  ## r2 <= 2 is the eight neighbours (a diagonal is r2 2) and nothing else.
  let w = bare(robots = @[(x: 15, y: 15, kind: ord(rtArchon),
                           team: ord(teamA))])
  let a = w.at(15, 15)
  var reachable = 0
  for dx in -2 .. 2:
    for dy in -2 .. 2:
      if dx == 0 and dy == 0: continue
      let l = loc(15 + dx, 15 + dy)
      let n = w.put(rtSoldier, l, teamNeutral)
      if w.canActivate(a, l): inc reachable
      w.visitDeathSignal(n, dcActivation)
  checkEq("exactly the eight neighbours are in range", reachable, 8)
  checkEq("a diagonal really is r2 2",
    loc(15, 15).distanceSquaredTo(loc(16, 16)), 2)
  checkEq("and a knight's move is r2 5",
    loc(15, 15).distanceSquaredTo(loc(16, 17)), 5)

block:
  let w = bare()
  let a = w.at(3, 15)
  check("an EMPTY square cannot be activated", not w.canActivate(a, loc(4, 15)))
  discard w.put(rtSoldier, loc(4, 15), teamA)
  check("and neither can our OWN robot", not w.canActivate(a, loc(4, 15)))
  discard w.put(rtSoldier, loc(3, 14), teamB)
  check("nor an ENEMY robot", not w.canActivate(a, loc(3, 14)))
  discard w.put(rtStandardzombie, loc(3, 16), teamZombie)
  check("nor a ZOMBIE", not w.canActivate(a, loc(3, 16)))

block:
  let w = bare()
  let a = w.at(3, 15)
  discard w.put(rtSoldier, loc(4, 15), teamNeutral)
  a.d.core = 3.0
  check("a core-loaded archon cannot activate",
    not w.canActivate(a, loc(4, 15)))
  a.d.core = 0.0
  check("and a ready one can", w.canActivate(a, loc(4, 15)))

# --- the effect ------------------------------------------------------------
block:
  let w = bare()
  let a = w.at(3, 15)
  let n = w.put(rtGuard, loc(4, 15), teamNeutral)
  let neutralsBefore = w.robotCountOf(teamNeutral)
  let before = w.teamParts(teamA)
  a.d.weapon = 5.0
  check("the activation lands", w.doActivate(a, loc(4, 15)))
  checkEq("it costs ZERO parts", w.teamParts(teamA), before)
  checkEq("weapon up-to 0, so a loaded weapon is untouched", a.d.weapon, 5.0)
  checkEq("and core += the archon's movementDelay 2", a.d.core, 2.0)
  let fresh = w.getRobot(loc(4, 15))
  check("an identical type stands on the square", fresh != nil)
  checkEq("of the same type", fresh.kind, rtGuard)
  checkEq("on the activator's team", fresh.team, teamA)
  checkEq("with buildDelay 0", fresh.buildDelay, 0)
  check("and therefore IMMEDIATELY ACTIVE", fresh.isActive())
  check("it is a different robot", fresh.id != n.id)
  checkEq("the neutral roster shrank", w.robotCountOf(teamNeutral),
    neutralsBefore - 1)
  checkEq("no rubble was left", w.getRubble(loc(4, 15)), 0.0)
  checkEq("the counter ticked", w.stats.neutralsActivated[0], 1)
  checkEq("and it was not an archon", w.stats.neutralArchonsActivated[0], 0)

block:
  ## A NEUTRAL ARCHON raises `getRobotTypeCount(team, ARCHON)` and therefore
  ## the FIRST tiebreak rung. Measured: 22 of the 98 official maps carry one.
  let w = bare()
  let a = w.at(3, 15)
  discard w.put(rtArchon, loc(4, 15), teamNeutral)
  checkEq("A starts with one archon", w.archonsAlive(teamA), 1)
  discard w.doActivate(a, loc(4, 15))
  checkEq("and has TWO after activating a neutral archon",
    w.archonsAlive(teamA), 2)
  checkEq("and the dedicated counter ticks",
    w.stats.neutralArchonsActivated[0], 1)
  checkEq("which is the first rung of the ladder",
    w.archonsAlive(teamA) - w.archonsAlive(teamB), 1)

block:
  ## A neutral TURRET arrives in TURRET form, not TTM.
  let w = bare()
  let a = w.at(3, 15)
  discard w.put(rtTurret, loc(4, 15), teamNeutral)
  discard w.doActivate(a, loc(4, 15))
  checkEq("a neutral TURRET arrives as a TURRET", w.getRobot(loc(4, 15)).kind,
    rtTurret)
  checkEq("and it is worth its full 130 in the parts ladder",
    w.partsWorth(teamA), 300 + 130)

block:
  ## The activation kill uses cause ACTIVATION, which skips BOTH the rubble
  ## deposit AND the infection conversion — even for an infected neutral.
  let w = bare()
  let a = w.at(3, 15)
  let n = w.put(rtViper, loc(4, 15), teamNeutral)
  n.inf.setInfected(rtViper)
  discard w.doActivate(a, loc(4, 15))
  checkEq("no rubble", w.getRubble(loc(4, 15)), 0.0)
  let fresh = w.getRobot(loc(4, 15))
  check("and OUR viper, not a RANGEDZOMBIE",
    fresh != nil and fresh.team == teamA and fresh.kind == rtViper)
  checkEq("and the fresh robot is not infected", fresh.inf.infectedTurns(), 0)
  checkEq("and it did NOT count as a robot lost by anyone",
    w.stats.robotsTurned[0] + w.stats.robotsTurned[1], 0)

block:
  ## The horde eats what a faction did not activate in time (rule 5.5h) — the
  ## other half of why `neutral_activation` is a knob.
  ## An explicit roster: `getNearestPlayerControlled` is the whole zombie
  ## targeting rule, so the ONLY player robot on the board has to be the one
  ## this block put there.
  let w = bare(robots = @[
    (x: 25, y: 25, kind: ord(rtSoldier), team: ord(teamA))])
  let n = w.put(rtSoldier, loc(6, 6), teamNeutral)
  let z = w.put(rtStandardzombie, loc(5, 5), teamZombie)
  w.rubble[6 * TestWidth + 5] = 500.0
  w.rubble[5 * TestWidth + 6] = 500.0
  w.processZombie(z)
  check("the horde ate it", n.health < 60.0)

finish("test_bc16_activation")
