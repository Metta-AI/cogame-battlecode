## The Tier A' scenario bot: `scenario16.nim`, the Nim twin of
## `tools/oracle/bc16/bc16scenario/RobotPlayer.java` and its three variants,
## written LINE FOR LINE against them and selected by `-d:bc16Scenario`
## (+ `-d:bc16ScenarioTurn` / `-d:bc16ScenarioAnnihilate` /
## `-d:bc16ScenarioTie`).
##
## Tier A cannot cover any PLAYER action — an idle bot never builds, moves,
## attacks, clears, packs, repairs or activates — so this bot exists to force
## every rare path EARLY and DETERMINISTICALLY. Three properties are
## deliberate and all three are asserted by the oracle job:
##
## 1. **no RNG at all**: every decision is a function of `getRoundNum()` and
##    the robot's own type, so the two sides cannot drift for a reason that is
##    not a rules difference;
## 2. **cheap**: the Java side asserts at the end of every turn that
##    `Clock.getBytecodeNum()` is at or below `bytecodeLimit - 8000` and
##    `System.exit(4)` otherwise, so the engine's own `amountToDecrement` is
##    exactly 1.0 and V1 is never exercised;
## 3. **scripted by round number**, so the trace lines that prove each path
##    fired are at known rounds and `ci.yml` can assert them off the JAVA
##    trace rather than trusting the comparison.
##
## The script, by round (an ARCHON does the building; every built unit follows
## its own type's script):
##
##   round 1   build a SCOUT to the north      (buildTurns 20, proves the freeze)
##   round 30  build a SOLDIER to the east     (12)
##   round 50  build a GUARD to the south      (10)
##   round 70  build a VIPER to the west        (30)
##   round 110 build a TURRET to the north-east (25)
##   every round after 140, if a friendly non-archon is in r2 <= 24: REPAIR it
##             (1 HP, zero delay, once a turn — the one-per-turn cap proved by
##             calling it twice)
##   round 150+ activate any NEUTRAL in r2 <= 2 (no rubble, no turn,
##             immediately active)
##   SOLDIER:  attack the square 3 east of itself on every even round — an
##             EMPTY square if nothing is there, which is legal and costs full
##             delay — and step east on every odd round, proving the diagonal
##             and rubble factors separately as it crosses the map
##   GUARD:    step south-east every round (diagonal x rubble factors)
##   SCOUT:    clear the rubble to its north every round if there is any, else
##             step north — the cheapest digger, and the 100 -> 0 in fourteen
##             actions
##   VIPER:    attack the square 4 west of itself every third round (infects
##             for 20 turns at 2 damage a turn)
##   TURRET:   attack the square 3 north of itself every round (r2 9, inside
##             [6, 40]); pack at round 400 and unpack at round 430, proving
##             10-on-both twice
##
## `bc16ScenarioTurn` additionally lets an infected SOLDIER, SCOUT and ARCHON
## die; `bc16ScenarioAnnihilate` walks soldiers onto the enemy's single archon
## until `DESTROYED` fires; `bc16ScenarioTie` mirrors both sides so the ladder
## walks PWNED -> OWNED -> BARELY_BEAT and, on one seed,
## WON_BY_DUBIOUS_REASONS.

import ../world

export world

proc runScenario16*(w: World, r: Robot) =
  let round = w.currentRound
  case r.kind
  of rtArchon:
    if round == 1 and w.canBuild(r, dNorth, rtScout):
      w.doBuild(r, dNorth, rtScout)
      return
    if round == 30 and w.canBuild(r, dEast, rtSoldier):
      w.doBuild(r, dEast, rtSoldier)
      return
    if round == 50 and w.canBuild(r, dSouth, rtGuard):
      w.doBuild(r, dSouth, rtGuard)
      return
    if round == 70 and w.canBuild(r, dWest, rtViper):
      w.doBuild(r, dWest, rtViper)
      return
    if round == 110 and w.canBuild(r, dNortheast, rtTurret):
      w.doBuild(r, dNortheast, rtTurret)
      return
    if round >= 150:
      for d in MoveDirs:
        if w.canActivate(r, r.loc + d):
          w.doActivate(r, r.loc + d)
          return
    if round >= 140:
      for other in w.senseNearbyRobots(r, 24):
        if other.team == r.team and other.kind != rtArchon and
            w.canRepair(r, other.loc):
          w.doRepair(r, other.loc)
          ## The one-per-turn cap: the second call must be refused, and the
          ## Java side calls it twice for exactly that reason.
          discard w.canRepair(r, other.loc)
          return
  of rtSoldier:
    if (round mod 2) == 0:
      let at = r.loc.translate(3, 0)
      if w.canAttackLocation(r, at) and r.d.isWeaponReady():
        w.doAttack(r, at)
        return
    else:
      if w.canMove(r, dEast) and r.d.isCoreReady():
        w.doMove(r, dEast)
        return
  of rtGuard:
    if w.canMove(r, dSoutheast) and r.d.isCoreReady():
      w.doMove(r, dSoutheast)
      return
  of rtScout:
    if r.d.isCoreReady():
      if w.getRubble(r.loc + dNorth) > 0.0 and w.canClearRubble(r, dNorth):
        w.doClearRubble(r, dNorth)
        return
      if w.canMove(r, dNorth):
        w.doMove(r, dNorth)
        return
  of rtViper:
    if (round mod 3) == 0:
      let at = r.loc.translate(-4, 0)
      if w.canAttackLocation(r, at) and r.d.isWeaponReady():
        w.doAttack(r, at)
        return
  of rtTurret:
    if round == 400:
      w.doTransform(r)
      return
    let at = r.loc.translate(0, -3)
    if w.canAttackLocation(r, at) and r.d.isWeaponReady():
      w.doAttack(r, at)
      return
  of rtTtm:
    if round >= 430:
      w.doTransform(r)
      return
  else:
    discard
