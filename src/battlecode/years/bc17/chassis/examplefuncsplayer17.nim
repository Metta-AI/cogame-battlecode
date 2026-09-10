## `examplefuncsplayer17` -- the deliberately weak floor AND the parity
## oracle's other side.
##
## A **statement-for-statement port** of
## `battlecode/battlecode-scaffold-2017/src/examplefuncsplayer/RobotPlayer.java`
## at commit `76e7b51e` (**AGPL-3.0**, credited in `NOTICE`), with the ONE
## committed patch hunk of `tools/oracle/bc17/examplefuncsplayer17/
## determinism.patch` applied: the stock bot's three `Math.random()` call
## sites become `rng.nextDouble()` on a **`java.util.Random` seeded with the
## robot's own `rc.getID()`**, created once per robot.
##
## **WHY THE PATCH.** The stock line draws from the wall-clock-seeded global
## RNG, so the stock bot is not reproducible even against itself and no
## bit-exact parity is possible with it. `java.util.Random` is the choice
## because `src/battlecode/rng.nim` already ports it -- so **Tier A" is also a
## test of that module**.
##
## **THE DRAW ORDER IS LOAD-BEARING AND IS PRESERVED EXACTLY.** Java's `&&`
## SHORT-CIRCUITS, so:
##
##   * an ARCHON draws for `randomDirection()`, and draws a SECOND time only
##     when `canHireGardener(dir)` is true;
##   * a GARDENER draws for `randomDirection()`, then draws for the SOLDIER
##     gate only when `canBuildRobot(SOLDIER, dir)` is true, and draws a THIRD
##     time only when that gate failed AND `canBuildRobot(LUMBERJACK, dir)` is
##     true;
##   * every `tryMove(randomDirection())` draws once more.
##
## `tests/test_bc17_examplefuncsplayer17.nim` pins the per-turn draw count for
## all four branch combinations.
##
## **IT MAY NOT GAIN BEHAVIOUR.** It never plants a tree, never waters one,
## never shakes, never chops and never donates, so it can never win by victory
## points and its only income is the sub-200 trickle. That is what being the
## weak floor means, and `tools/oracle/bc17/build_oracle.sh` greps the Java
## copy for `plantTree(`, `water(`, `donate(`, `shake(`, `chop(`,
## `RobotType.TANK` and `RobotType.SCOUT` and FAILS ON A HIT.
##
## **TANK and SCOUT have no `case` in the switch at all**, so `run()` returns
## immediately and the robot dies ("If this method returns, the robot dies!",
## `RobotPlayer.java:8-10`). The bot never builds either, so the path is not
## exercised in a real game -- but it IS a rule of this bot, and the test
## asserts it by building a TANK into it synthetically.

import std/math
import ../../../rng
import ../constants, ../units, ../geom, ../world, ../actions

export world

proc weakRng(r: Robot): var JavaRandom =
  ## `new java.util.Random(rc.getID())`, created ONCE per robot.
  if not r.weakRngReady:
    r.weakRng = initJavaRandom(r.id)
    r.weakRngReady = true
  r.weakRng

proc randomDirection(r: Robot): Dir =
  ## `new Direction((float)Math.random() * 2 * (float)Math.PI)` with the
  ## patched draw. The multiply is `(float)draw * 2 * (float)PI` in Java: a
  ## float32 product of a float32-narrowed double.
  let draw = float32(r.weakRng.nextDouble())
  dirRads(draw * 2'f32 * float32(PI))

proc tryMoveWeak(w: World, r: Robot, dir: Dir): bool {.discardable.} =
  ## The scaffold's own `tryMove(dir)` == `tryMove(dir, 20, 3)`: the intended
  ## direction, then +-20 degrees up to three times each way.
  if w.canMove(r, dir):
    return w.move(r, dir)
  var currentCheck = 1
  while currentCheck <= 3:
    if w.canMove(r, dir.rotateLeftDegrees(float32(20 * currentCheck))):
      return w.move(r, dir.rotateLeftDegrees(float32(20 * currentCheck)))
    if w.canMove(r, dir.rotateRightDegrees(float32(20 * currentCheck))):
      return w.move(r, dir.rotateRightDegrees(float32(20 * currentCheck)))
    inc currentCheck
  false

proc runArchonWeak(w: World, r: Robot) =
  ## `runArchon()`: a random direction, a 1-in-100 hire gate behind
  ## `canHireGardener` (the `&&` short-circuit decides whether the second
  ## draw happens at all), a random move, and TWO BROADCASTS EVERY TURN.
  let dir = r.randomDirection()
  if w.canBuildRobot(r, rtGardener, dir) and
      r.weakRng.nextDouble() < 0.01:
    discard w.hireGardener(r, dir)
  w.tryMoveWeak(r, r.randomDirection())
  discard w.broadcast(r, 0, int(r.loc.x))
  discard w.broadcast(r, 1, int(r.loc.y))

proc runGardenerWeak(w: World, r: Robot) =
  ## `runGardener()`: it reads channels 0 and 1 and **does nothing with
  ## them** -- the stock bot builds a `MapLocation` it never uses -- then the
  ## SOLDIER gate, then the LUMBERJACK gate (which additionally checks
  ## `isBuildReady()`), then a random move. **It never plants and never
  ## waters.**
  discard w.readBroadcast(r, 0)
  discard w.readBroadcast(r, 1)
  let dir = r.randomDirection()
  if w.canBuildRobot(r, rtSoldier, dir) and r.weakRng.nextDouble() < 0.01:
    discard w.buildRobot(r, rtSoldier, dir)
  elif w.canBuildRobot(r, rtLumberjack, dir) and
      r.weakRng.nextDouble() < 0.01 and r.isBuildReady():
    discard w.buildRobot(r, rtLumberjack, dir)
  w.tryMoveWeak(r, r.randomDirection())

proc runSoldierWeak(w: World, r: Robot) =
  ## `runSoldier()`: fire at `robots[0]` -- **the NEAREST enemy, because the
  ## candidate enumeration is ascending distance** (D2) -- then move at
  ## random.
  let enemies = w.senseNearbyRobots(r, -1'f32, ord(r.team.opponent()))
  if enemies.len > 0 and w.canFireShot(r, ssSingle):
    let target = w.robots.getOrDefault(enemies[0])
    if target != nil:
      discard w.fireShot(r, ssSingle, directionTo(r.loc, target.loc))
  w.tryMoveWeak(r, r.randomDirection())

proc runLumberjackWeak(w: World, r: Robot) =
  ## `runLumberjack()`: strike anything within `1 + STRIKE_RADIUS`, else
  ## chase the nearest enemy in sensor range, else move at random.
  let close = w.senseNearbyRobots(r, bodyRadius(r.kind) +
                                    lumberjackStrikeRadius,
                                  ord(r.team.opponent()))
  if close.len > 0 and not r.hasAttacked():
    discard w.strike(r)
  else:
    let enemies = w.senseNearbyRobots(r, -1'f32, ord(r.team.opponent()))
    if enemies.len > 0:
      let target = w.robots.getOrDefault(enemies[0])
      if target != nil:
        w.tryMoveWeak(r, directionTo(r.loc, target.loc))
        return
    w.tryMoveWeak(r, r.randomDirection())

proc runExamplefuncsplayer17*(w: World, r: Robot) =
  ## The switch, verbatim -- **and TANK and SCOUT are not in it**, so
  ## `run()` returns and the robot dies.
  case r.kind
  of rtArchon: w.runArchonWeak(r)
  of rtGardener: w.runGardenerWeak(r)
  of rtSoldier: w.runSoldierWeak(r)
  of rtLumberjack: w.runLumberjackWeak(r)
  of rtTank, rtScout:
    ## "If this method returns, the robot dies!"
    w.disintegrate(r)
