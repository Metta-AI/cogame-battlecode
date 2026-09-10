## `orchard` -- the strong bc17 chassis and the champions' chassis.
##
## Written from the ENGINE SOURCE, the 1.6.2 spec page and the four archetypes
## the run's own idea names (tree farm; tank rush; lumberjack swarm; scout
## squat). **NO 2017 COMPETITOR BOT WAS CLONED, FETCHED OR READ**: all three
## named upstreams carry no licence anywhere, so this run treats them as
## unreadable and none contributes a line. The only borrowed behaviours are
## the two named helpers of the AGPL-3.0 scaffold player -- `tryMove` in
## `kit.nim` and `willCollideWithMe` in `micro.nim` -- and `NOTICE` credits
## both individually.
##
## One dispatch per unit type, and the per-type files carry the behaviour:
## `archon.nim`, `gardener.nim`, `lumberjack.nim`, `scout.nim`, and the
## soldier/tank turn below, which is `micro.nim` plus `military.nim`'s
## posture. `donate.nim` runs on every unit, because **any robot may donate**
## and the cheapest point is the one bought the round the bullets arrive.

import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit, econ, farm, comms, micro, military, archon, gardener,
  lumberjack, scout, donate

export kit

proc runFighter(w: World, s: Side, r: Robot) =
  ## SOLDIER and TANK: dodge, answer, engage, advance.
  let answerId = w.threatNearOwnStuff(s, r)
  let mode = w.posture(s, r, answerId >= 0)
  let enemies = w.senseRobots(r, -1'f32, ord(s.team.opponent()))
  ## The bullet-threat set first: a soldier strides 0.8 against a bullet's 2,
  ## so dodging is only ever worth one move, and it is worth that one.
  let threats = w.threatSet(r)
  var dodged = false
  if threats.len > 0:
    dodged = w.dodge(r, threats)
  discard w.engage(s, r, enemies)
  if r.hasMoved() or dodged: return
  case mode
  of poAnswer:
    let e = w.robots.getOrDefault(answerId)
    if e != nil:
      w.walkTowards(r, e.loc)
      return
  of poPush:
    if enemies.len > 0:
      let e = w.robots.getOrDefault(enemies[0])
      if e != nil and distanceTo(r.loc, e.loc) > 3'f32:
        w.walkTowards(r, e.loc)
        return
    w.walkTowards(r, w.readRally(s, r))
    return
  of poScreen, poRally:
    ## Screen the farm: sit between our archon and theirs, a third of the way
    ## out, and answer anything that comes to us.
    if enemies.len > 0:
      let e = w.robots.getOrDefault(enemies[0])
      if e != nil and distanceTo(r.loc, e.loc) > 3'f32:
        w.walkTowards(r, e.loc)
        return
    let home = s.homeArchon(r.loc)
    let enemy = s.enemyBase(home)
    let post = addDist(home, (if home == enemy: dirRads(0'f32)
                              else: directionTo(home, enemy)),
                       min(10'f32, s.defendRadius()))
    if distanceTo(r.loc, post) > 2'f32:
      w.walkTowards(r, post)

proc opportunisticShake(w: World, s: Side, r: Robot) =
  ## `shake()` is free, takes one turn, works for ANY robot at distance 1 and
  ## hands over every bullet inside the tree -- so anything with a spare
  ## action and a neutral tree in reach takes it. `never` means never.
  if s.doctrine.shakeNeutralTrees == sn17Never or r.shakeCount > 0: return
  for id in w.senseTrees(r, bodyRadius(r.kind) + neutralTreeMaxRadius +
                            interactionDistFromEdge, ord(tNeutral)):
    let tr = w.trees.getOrDefault(id)
    if tr == nil or tr.containedBullets <= 0: continue
    if r.canInteractWithTree(tr):
      if w.shake(r, id): return

proc runOrchard*(w: World, s: Side, r: Robot) =
  ## One robot's whole turn. The op budget is enforced by the sim: every
  ## primitive below checks it before it runs, so a turn that runs out of
  ## credits simply ENDS WHERE IT STANDS with the world unchanged.
  case r.kind
  of rtArchon: w.runArchon(s, r)
  of rtGardener: w.runGardener(s, r)
  of rtLumberjack: w.runLumberjack(s, r)
  of rtScout: w.runScout(s, r)
  of rtSoldier, rtTank:
    w.runFighter(s, r)
    w.opportunisticShake(s, r)
  ## Any robot may donate, any number of times a turn -- and the price only
  ## ever goes up, so the surplus is spent the round it appears.
  discard w.tryDonate(s, r)
