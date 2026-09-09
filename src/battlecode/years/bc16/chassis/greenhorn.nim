## `greenhorn` — the weak floor and the parity oracle's other side.
##
## **IT MAY NOT GAIN BEHAVIOUR: it is one side of the differential oracle.**
## `tools/oracle/bc16/bc16greenhorn/RobotPlayer.java` is its Java twin,
## statement for statement, and `tests/test_bc16_greenhorn.nim` asserts the
## `Random(2016)` call sequence and the branch order below against a recorded
## oracle trace. There is no upstream `examplefuncsplayer` for 2016 in the
## engine repository (the 2016 scaffold is a separate, unarchived project), so
## this bot is DEFINED HERE and the Java side is written from this
## specification rather than the other way round — which is why the two are
## kept to a shape small enough to verify by reading:
##
## 1. it seeds `new java.util.Random(2016)` PER ROBOT at construction and
##    calls only `nextInt(8)` (static fields are per robot under the
##    instrumenter, so every unit carries its own stream and it needs no
##    determinism patch);
## 2. an **ARCHON**: if `getTeamParts() >= 30` and the core is ready, pick
##    `d = DIRECTIONS[rng.nextInt(8)]` and `build(d, SOLDIER)` if
##    `canBuild(d, SOLDIER)`; otherwise, if the core is ready,
##    `move(DIRECTIONS[rng.nextInt(8)])` if it can; otherwise nothing. IT
##    NEVER REPAIRS AND NEVER ACTIVATES;
## 3. a **SOLDIER**: `senseHostileRobots(myLoc, attackRadiusSquared)`; if the
##    array is non-empty and the weapon is ready,
##    `attackLocation(hostiles[0].location)`; else if the core is ready,
##    `move(DIRECTIONS[rng.nextInt(8)])` if it can;
## 4. **every other type does nothing at all** — so `greenhorn` never builds
##    a guard, a scout, a viper or a turret, never clears rubble, never sends
##    a signal, never activates a neutral and never kills a den. That is what
##    being the weak floor means, and it is why the `docker-smoke` substance
##    assertions that need those things are asserted ACROSS THE PAIR and not
##    per seat;
## 5. `DIRECTIONS` is N, NE, E, SE, S, SW, W, NW in that order, because
##    `nextInt(8)` indexes it.
##
## The `DecisionOps` charge is deliberately light and mirrors what the bot
## actually looks at: one credit per draw and one per hostile examined.

import ../world

export world

proc runGreenhorn*(w: World, r: Robot) =
  case r.kind
  of rtArchon:
    if w.teamParts(r.team) >= float64(rtSoldier.partCost()) and
        r.d.isCoreReady():
      if not r.spend(1): return
      let d = MoveDirs[int(r.greenhornRng.nextInt(8))]
      if w.canBuild(r, d, rtSoldier):
        w.doBuild(r, d, rtSoldier)
    elif r.d.isCoreReady():
      if not r.spend(1): return
      let d = MoveDirs[int(r.greenhornRng.nextInt(8))]
      if w.canMove(r, d):
        w.doMove(r, d)
  of rtSoldier:
    var first: Robot = nil
    for other in w.senseHostileRobots(r, r.kind.attackRadiusSquared()):
      if not r.spend(1): break
      first = other
      break
    if first != nil and r.d.isWeaponReady():
      if w.canAttackLocation(r, first.loc):
        w.doAttack(r, first.loc)
    elif r.d.isCoreReady():
      if not r.spend(1): return
      let d = MoveDirs[int(r.greenhornRng.nextInt(8))]
      if w.canMove(r, d):
        w.doMove(r, d)
  else:
    ## SCOUT, GUARD, VIPER, TURRET and TTM: nothing.
    discard
