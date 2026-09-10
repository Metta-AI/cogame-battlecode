## A GARDENER's turn: water, plant, build, walk -- in that order of
## preference, and the order matters.
##
## **WATER FIRST, ALWAYS.** Watering costs no bullets and no cooldown, its own
## counter is separate from the build counter, and a tree withers 0.5 a round
## for ever. A farm nobody waters is a farm that dies, and the survival gate's
## negative control is exactly this proc removed.
##
## **THE TEN-TURN BUILD COOLDOWN IS SHARED BETWEEN PLANTING AND BUILDING**, so
## a farm and an army compete for the same slot -- which is what makes
## `gardener_count` "how many parallel ten-turn slots the faction owns".
## `orchard` spends the slot on a tree while the tree target is unmet and on a
## fighter otherwise, with the essential-tree floor funded THROUGH the reserve.

import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit, econ, farm, military, comms

export kit

proc buildFighter*(w: World, s: Side, r: Robot): bool {.discardable.} =
  ## Build the type `mix()` says is furthest below its share, into the first
  ## clear direction of an eight-bearing probe.
  if not r.isBuildReady(): return false
  if not w.wantsFighter(s): return false
  let essential = w.fighterIsEssential(s)
  ## The budget the mix may choose from: everything free above the reserve,
  ## or everything free at all while the two-per-gardener floor is unmet.
  let budget = (if essential: w.uncommitted(s)
                else: w.uncommitted(s) - w.bulletGate(s))
  let kind = w.nextFighter(s, budget)
  if not w.canSpend(s, bulletCostF(kind), essential):
    return false
  let enemy = s.enemyBase(r.loc)
  let toward = (if r.loc == enemy: dirRads(0'f32)
                else: directionTo(r.loc, enemy))
  ## SIXTEEN bearings, starting with the build lane the layout keeps clear
  ## (the one pointing at the enemy, which is also where the fighter wants to
  ## walk). A gardener ringed by its own farm has exactly one way out, and
  ## eight bearings can miss it.
  for step in 0 .. 15:
    if not r.chargeFor(1): return false
    let d = toward.rotateLeftDegrees(float32(step) * 22.5'f32)
    if w.canBuildRobot(r, kind, d):
      if w.buildRobot(r, kind, d):
        s.commit(bulletCostF(kind))
        s.noteSpend(kind)
        return true
  ## Every bearing is blocked: the gardener is walled in by its own trees and
  ## its neighbours. Walk out rather than stall -- `r.task` moves the
  ## layout's standing position one step further from the archon.
  inc r.task
  false

proc runGardener*(w: World, s: Side, r: Robot) =
  discard w.tryWater(s, r)
  if r.isBuildReady():
    ## **THE SHARED TEN-TURN SLOT, spent in the floor's own order**: the two
    ## fighters per gardener come before the next tree, then the farm, then
    ## the army's appetite. A gardener that plants twelve trees and guards
    ## none of them has built a present for a lumberjack.
    if w.fighterIsEssential(s):
      if not w.buildFighter(s, r):
        discard w.tryPlant(s, r)
    elif w.wantsTree(s):
      if not w.tryPlant(s, r):
        ## Every slot of the layout is blocked: walk on rather than stall,
        ## which is what makes `line` a line and stops `hex` boxing itself in.
        inc r.task
        discard w.buildFighter(s, r)
    else:
      discard w.buildFighter(s, r)
  ## Shake anything already in reach when the doctrine allows it: it is free
  ## and a gardener standing in a neutral grove is standing on bullets.
  if s.doctrine.shakeNeutralTrees != sn17Never and r.shakeCount == 0:
    for id in w.senseTrees(r, bodyRadius(r.kind) + neutralTreeMaxRadius +
                              interactionDistFromEdge, ord(tNeutral)):
      let tr = w.trees.getOrDefault(id)
      if tr == nil or tr.containedBullets <= 0: continue
      if r.canInteractWithTree(tr):
        if w.shake(r, id): break
  ## Walk to the layout's standing position, then stay: every step away from
  ## the farm is a tree that goes unwatered. `r.task` is how far along its
  ## own line this gardener is, so a blocked farm walks itself out of the
  ## corner it started in.
  let stand = w.farmStand(s, r)
  if distanceTo(r.loc, stand) > 1'f32:
    w.walkTowards(r, stand)
