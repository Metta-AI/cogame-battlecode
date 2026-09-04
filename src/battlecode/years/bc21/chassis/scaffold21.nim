## `examplefuncsplayer21` — the deliberately weak floor and the parity oracle's
## other side.
##
## Ported STATEMENT FOR STATEMENT from
## `battlecode21/example-bots/src/main/examplefuncsplayer/RobotPlayer.java` at
## the pinned commit. IT MAY NOT GAIN BEHAVIOUR: it is one side of the
## differential oracle, and any improvement here makes the oracle prove
## something other than "the ported rule set is the same rule set".
##
## The upstream bot calls `Math.random()` in `randomDirection()` AND in
## `randomSpawnableRobotType()`, seeded from the wall clock, so it is not
## reproducible even against itself. `tools/oracle/bc21/examplefuncsplayer21/`
## carries that file verbatim except for one committed hunk
## (`determinism.patch`): a static `java.util.Random RNG = new
## Random(rc.getID())` assigned at the top of `run()` — static fields are PER
## ROBOT under the instrumenter — and both `Math.random()` call sites replaced
## by `RNG.nextDouble()`. This file reproduces exactly that stream through
## `rng.nim`, in exactly that call order:
##
##   * Enlightenment Center: ONE `nextDouble` for the spawnable type, then the
##     eight-direction build loop that BREAKS at the first direction that
##     fails, then `bid(1)`;
##   * politician: sense the enemy inside the action radius; empower at
##     `r^2 = 9` if any is there (NO draw); else ONE `nextDouble` for a
##     direction and one attempted move;
##   * slanderer: ONE `nextDouble` and one attempted move;
##   * muckraker: expose the FIRST sensed enemy that can be exposed, in the
##     engine's own scan order (NO draw); else ONE `nextDouble` and one move.

import kit

const SpawnableRobots = [rtPolitician, rtSlanderer, rtMuckraker]
  ## `RobotPlayer.spawnableRobot`, in declaration order.

proc randomDirection(brain: Brain): Dir =
  ## `directions[(int)(RNG.nextDouble() * directions.length)]`, where
  ## `directions` is the eight in `MoveDirs`' order.
  MoveDirs[int(brain.rng.nextDouble() * 8.0)]

proc randomSpawnableRobotType(brain: Brain): RobotKind =
  SpawnableRobots[int(brain.rng.nextDouble() * 3.0)]

proc tryMove(w: World, r: Robot, d: Dir): bool {.discardable.} =
  if w.canMove(r, d):
    w.move(r, d)
    return true
  false

proc runScaffoldCenter(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)
  let toBuild = randomSpawnableRobotType(brain)
  const influence = 50
  for d in MoveDirs:
    if w.canBuildRobot(r, toBuild, d, influence):
      discard w.buildRobot(r, toBuild, d, influence)
      w.firstBuild(side, toBuild)
    else:
      break
  ## `rc.bid(1)` — unconditional, and refused by the engine when the Center
  ## has no influence at all.
  w.bid(r, 1)

proc runScaffoldPolitician(w: World, side: Side, r: Robot) =
  let actionRadius = RobotSpecs[rtPolitician].actionRadiusSquared
  var attackable = 0
  for l in w.locationsWithinRadiusSquared(r.loc, actionRadius):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil: continue
    if bot.id == r.id: continue
    if bot.team != other(r.team): continue
    attackable += 1
  if attackable != 0 and canEmpower(r, actionRadius):
    w.doEmpower(r, actionRadius)
    return
  tryMove(w, r, randomDirection(side.brainFor(r)))

proc runScaffoldSlanderer(w: World, side: Side, r: Robot) =
  tryMove(w, r, randomDirection(side.brainFor(r)))

proc runScaffoldMuckraker(w: World, side: Side, r: Robot) =
  let actionRadius = RobotSpecs[rtMuckraker].actionRadiusSquared
  for l in w.locationsWithinRadiusSquared(r.loc, actionRadius):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil: continue
    if bot.id == r.id: continue
    if bot.team != other(r.team): continue
    if not bot.kind.canBeExposed(): continue
    if w.canExpose(r, l):
      w.expose(r, l)
      return
  tryMove(w, r, randomDirection(side.brainFor(r)))

proc runScaffold21*(w: World, side: Side, r: Robot) =
  case r.kind
  of rtEnlightenmentCenter: runScaffoldCenter(w, side, r)
  of rtPolitician: runScaffoldPolitician(w, side, r)
  of rtSlanderer: runScaffoldSlanderer(w, side, r)
  of rtMuckraker: runScaffoldMuckraker(w, side, r)
