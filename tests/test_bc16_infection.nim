## Shard 4 of the note's list — **infection**, and the die-and-turn conversion
## that is this year's largest unexploited play.
##
## A VIPER hit sets `viperInfectedTurns = 20`; ANY zombie hit sets
## `zombieInfectedTurns = 10`. **The two counters are independent** and
## `isInfected()` is their OR. `processBeingInfected` runs inside
## `processEndOfTurn` and ONLY when health > 0: the viper strain deals exactly
## 2.0 (which can kill, and then the robot IS infected, so it becomes a
## zombie) and the zombie strain deals nothing. A robot that dies while
## infected leaves NO rubble and stands back up as `turnsInto` on
## `Team.ZOMBIE` at its own square with `maxHealth(currentRound)`.

import harness
import bc16_fixture

# --- the two counters are independent -------------------------------------
block:
  var inf = Infection()
  check("a fresh robot is not infected", not inf.isInfected())
  inf.setInfected(rtViper)
  checkEq("a VIPER hit sets 20 viper turns", inf.viperTurns, 20)
  checkEq("and leaves the zombie counter alone", inf.zombieTurns, 0)
  check("and it is infected", inf.isInfected())
  inf.setInfected(rtStandardzombie)
  checkEq("a zombie hit sets 10 zombie turns", inf.zombieTurns, 10)
  checkEq("and does NOT clear the viper counter", inf.viperTurns, 20)
  checkEq("infectedTurns is the larger of the two", inf.infectedTurns(), 20)
  for k in [rtStandardzombie, rtRangedzombie, rtFastzombie, rtBigzombie]:
    var i2 = Infection()
    i2.setInfected(k)
    checkEq($k & " infects for 10", i2.zombieTurns, 10)
  var i3 = Infection()
  i3.setInfected(rtSoldier)
  check("a SOLDIER cannot infect at all", not i3.isInfected())
  i3.setInfected(rtGuard)
  check("and neither can a GUARD", not i3.isInfected())

# --- the tick --------------------------------------------------------------
block:
  var inf = Infection()
  inf.setInfected(rtViper)
  checkEq("a viper tick deals exactly 2.0", inf.tickInfection(), 2.0)
  checkEq("and decrements to 19", inf.viperTurns, 19)
  var z = Infection()
  z.setInfected(rtStandardzombie)
  checkEq("a zombie tick deals nothing", z.tickInfection(), 0.0)
  checkEq("and decrements to 9", z.zombieTurns, 9)
  ## Twenty viper turns deal FORTY total, which is not enough to kill a full
  ## 60-HP soldier — so the named vector is one already at 40 or below.
  var v = Infection()
  v.setInfected(rtViper)
  var total = 0.0
  for i in 0 ..< 25: total += v.tickInfection()
  checkEq("twenty viper turns deal 40 in all", total, 40.0)
  checkEq("and the counter is spent", v.viperTurns, 0)
  check("so a full 60-HP soldier survives a whole viper infection",
    60.0 - total > 0.0)

# --- it runs in processEndOfTurn, and only when health > 0 ----------------
block:
  ## Played through the real round loop: a viper infects a soldier, and the
  ## soldier loses exactly 2.0 at the end of each of ITS OWN turns.
  let w = bare()
  let v = w.put(rtViper, loc(10, 10), teamA)
  let s = w.put(rtSoldier, loc(13, 12), teamB)
  checkEq("the target is inside the viper's r2 20",
    v.loc.distanceSquaredTo(s.loc), 13)
  discard w.doAttack(v, s.loc)
  checkEq("the viper's 2 damage lands", s.health, 58.0)
  checkEq("and the infection is set", s.inf.viperTurns, 20)
  checkEq("the victim's team records an infection suffered",
    w.stats.infectionsSuffered[1], 1)
  checkEq("and the attacker's an infection inflicted",
    w.stats.infectionsInflicted[0], 1)
  let sheets = defaultSheets()
  let sides = newSides16(sheets, 0)
  runRound(w, sides, [ckBulwark, ckBulwark])
  check("after one round the soldier has taken the 2.0 infection tick too",
    s.health <= 56.0)

block:
  ## A robot at health 0 takes NO infection tick — `processEndOfTurn` is
  ## guarded by `health > 0` in the round loop.
  let w = bare()
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  s.inf.setInfected(rtViper)
  w.changeHealthLevel(s, -60.0, dcNormal)
  check("the soldier is dead", not w.existsRobot(s.id))

# --- the die-and-turn conversion, every type ------------------------------
proc turnsCheck(kind, becomes: RobotType) =
  let w = bare()
  let r = w.put(kind, loc(11, 11), teamA)
  r.inf.setInfected(rtStandardzombie)
  w.changeHealthLevel(r, -5000.0, dcNormal)
  let z = w.getRobot(loc(11, 11))
  check("an infected " & $kind & " stands back up", z != nil)
  if z != nil:
    checkEq("as a " & $becomes, z.kind, becomes)
    checkEq("on the horde's team", z.team, teamZombie)
    checkEq("at its own square", z.loc, loc(11, 11))
  checkEq("and leaves NO rubble", w.getRubble(loc(11, 11)), 0.0)
  checkEq("and the loser's `robots_turned` counter ticks",
    w.stats.robotsTurned[0], 1)

block:
  turnsCheck(rtArchon, rtBigzombie)
  turnsCheck(rtScout, rtFastzombie)
  turnsCheck(rtSoldier, rtStandardzombie)
  turnsCheck(rtGuard, rtStandardzombie)
  turnsCheck(rtViper, rtRangedzombie)
  turnsCheck(rtTurret, rtRangedzombie)
  turnsCheck(rtTtm, rtRangedzombie)

block:
  ## The zombie it becomes is scaled at THE ROUND IT TURNS, not the round the
  ## victim was built.
  let w = bare()
  let a = w.put(rtArchon, loc(11, 11), teamA)
  w.currentRound = 2700
  a.inf.setInfected(rtViper)
  w.changeHealthLevel(a, -5000.0, dcNormal)
  let z = w.getRobot(loc(11, 11))
  check("the archon turns", z != nil and z.kind == rtBigzombie)
  if z != nil:
    checkEq("at the CURRENT outbreak level, not its own build round",
      z.maxHealth, 1500.0)
    checkEq("with the scaled attack too", z.attackPower, 75.0)

block:
  ## A NEUTRAL killed by ACTIVATION never turns, even when infected — the
  ## `cause != ACTIVATION` guard covers both effects.
  let w = bare()
  let a = w.at(3, 15)
  let n = w.put(rtGuard, loc(4, 15), teamNeutral)
  n.inf.setInfected(rtViper)
  discard w.doActivate(a, n.loc)
  let after = w.getRobot(loc(4, 15))
  check("the activated neutral is OURS, not a zombie",
    after != nil and after.team == teamA and after.kind == rtGuard)
  checkEq("the fresh robot carries no infection", after.inf.infectedTurns(),
    0)

block:
  ## A DISINTEGRATING infected robot DOES turn: `runRound:178-181` suicides it
  ## AFTER `processEndOfTurn`, as an ordinary death signal.
  let w = bare()
  let s = w.put(rtSoldier, loc(11, 11), teamA)
  s.inf.setInfected(rtStandardzombie)
  w.doDisintegrate(s)
  check("the robot is marked", s.disintegrated)
  w.visitDeathSignal(s, dcNormal)
  let z = w.getRobot(loc(11, 11))
  check("and an infected disintegration still becomes an enemy zombie",
    z != nil and z.team == teamZombie and z.kind == rtStandardzombie)

block:
  ## The new zombie takes NO TURN in the round it spawns: the exec sweep is a
  ## SNAPSHOT taken before it, so an appended id is not visited.
  let w = bare()
  let s = w.put(rtSoldier, loc(11, 11), teamA)
  s.inf.setInfected(rtStandardzombie)
  let before = w.execOrder.len
  w.changeHealthLevel(s, -5000.0, dcNormal)
  let z = w.getRobot(loc(11, 11))
  check("the zombie exists", z != nil)
  checkEq("the exec list is the same length (one out, one in)",
    w.execOrder.len, before)
  checkEq("and the new zombie is at the END of it, not in the dead one's slot",
    w.execOrder[^1], z.id)
  checkEq("with roundsAlive 0", z.roundsAlive, 0)

# --- a VIPER infection can kill, and then the victim turns -----------------
block:
  let w = bare()
  let s = w.put(rtSoldier, loc(11, 11), teamA)
  s.health = 1.5
  s.inf.setInfected(rtViper)
  let sheets = defaultSheets()
  let sides = newSides16(sheets, 0)
  ## Run one round: the soldier's own `processEndOfTurn` ticks the infection,
  ## the 2.0 kills it, and it IS infected — so it becomes a zombie.
  runRound(w, sides, [ckBulwark, ckBulwark])
  let z = w.getRobot(loc(11, 11))
  check("the viper tick killed it and it turned",
    z != nil and z.team == teamZombie and z.kind == rtStandardzombie)
  checkEq("and the port recorded the viper infection damage",
    w.stats.viperInfectionDamage[0] >= 1, true)

finish("test_bc16_infection")
