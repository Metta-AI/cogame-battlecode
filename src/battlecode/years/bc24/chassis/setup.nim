## bc24 setup, rounds 1 to 200: the dam is up, nobody can attack, and the two
## flocks spend two hundred rounds deciding where the war will be fought.
##
## What happens here:
##
## * **The three flag carriers.** The three lowest sequence ids each take one
##   own flag and walk it two tiles DEEPER into their own half, checking the
##   six-tile spacing rule BEFORE they put it down — because a team that fails
##   the check at round 200 has all three flags teleported home. By round 190
##   they drop wherever the check passes, and failing that they walk back and
##   drop on the start tile.
## * **The builders** dig or fill per `water_dig_policy` and lay the first
##   traps per `trap_budget`. Digging on a checkerboard parity in own territory
##   is also how a builder reaches build level 4 before the dam falls — five,
##   ten, fifteen, twenty XP, cheap, and it halves every later cost.
## * **Everyone else** walks crumbs off the floor and takes station. No attack
##   is possible; healing is.

import kit, builder

export kit, builder

const
  SetupDropDeadline* = 190
    ## After this round a carrier drops at the first legal, spacing-safe tile
    ## rather than holding out for its ideal one.
  SetupDigTarget* = 24
    ## Enough digs to carry a builder past build level 4 (20 XP) with margin,
    ## and cheap at 20 crumbs each against the 2 400 crumbs setup brings in.

proc setupFlagFor*(w: World, side: Side, r: Robot): int =
  ## Sequence ids 0, 1 and 2 relocate own flags 0, 1 and 2. Everybody else
  ## returns -1.
  let s = seqIdOf(r)
  if s <= 2: s else: -1

proc awayFromEnemy(side: Side, at: Loc): Dir =
  var toward = side.enemyCentres[0]
  var bestD = high(int)
  for c in side.enemyCentres:
    let d = at.distanceSquaredTo(c)
    if d < bestD:
      bestD = d
      toward = c
  at.directionTo(toward).opposite()

proc flagDropOk(w: World, side: Side, r: Robot, at: Loc): bool =
  ## The six-tile rule, checked against the OTHER two own flags' current
  ## locations, exactly as `confirmFlagPlacements` will check it at round 200.
  if not w.isPassable(at): return false
  for f in w.allFlags:
    if f.team != side.team: continue
    if f.carriedBy == r.id: continue
    if f.loc.distanceSquaredTo(at) < MinFlagSpacingSquared: return false
  true

proc runSetupCarrier*(w: World, side: Side, r: Robot): bool =
  ## True when this duck spent its turn on flag business.
  let brain = side.brainFor(r)
  let index = w.setupFlagFor(side, r)
  if index < 0: return false
  if brain.setupDone: return false

  if not r.hasFlag():
    ## Pick up own flag `index` if it is in reach and still at home.
    var target = loc(-1, -1)
    var i = 0
    for f in w.allFlags:
      if f.team != side.team: continue
      if i == index:
        target = f.loc
        if f.carriedBy >= 0 and f.carriedBy != r.id: return false
      i += 1
    if target.x < 0:
      brain.setupDone = true
      return false
    if r.loc.distanceSquaredTo(target) <= InteractRadiusSquared and
        w.canPickupFlag(r, target):
      w.pickupFlag(r, target)
      return true
    if chebyshev(r.loc, target) > 1:
      discard w.travelTo(side, r, side.ownFieldIndex(index), target)
      return true
    return false

  ## Carrying: walk two tiles deeper, then drop.
  let home = side.ownCentres[index]
  let dir = side.awayFromEnemy(home)
  let want = loc(home.x + 2 * dir.dx, home.y + 2 * dir.dy)
  let goal = if w.onTheMap(want) and w.isPassable(want): want else: home
  if r.loc == goal or w.currentRound >= SetupDropDeadline:
    if w.flagDropOk(side, r, r.loc) and w.canDropFlag(r, r.loc):
      w.dropFlag(r, r.loc)
      brain.setupDone = true
      return true
    ## Not a legal placement here: walk back home and drop there, which is
    ## always spacing-safe because that is where the flag started.
    if r.loc == home:
      if w.canDropFlag(r, r.loc):
        w.dropFlag(r, r.loc)
        brain.setupDone = true
        return true
    else:
      discard w.travelTo(side, r, side.ownFieldIndex(index), home)
    return true
  discard w.greedyStep(side, r, goal)
  true

proc setupDigTarget(w: World, side: Side, r: Robot): tuple[ok: bool, at: Loc] =
  ## Checkerboard parity, at Chebyshev 3..5 from an own flag: far enough from
  ## the spawn zone that the water does not pen the flock in, close enough
  ## that a builder does not walk the map for XP.
  for l in w.locationsWithinRadiusSquared(r.loc, InteractRadiusSquared):
    if not spend(r, 1): break
    if ((l.x + l.y) and 1) != 0: continue
    var near = false
    for c in side.ownCentres:
      let d = chebyshev(l, c)
      if d >= 3 and d <= 5: near = true
    if not near: continue
    if w.canDig(r, l): return (true, l)

proc runSetupBuilder*(w: World, side: Side, r: Robot) =
  let kind = side.plannedTrapKind()
  if w.mayBuildPlannedTrap(side, r, kind):
    let target = w.trapTargetNear(side, r, kind)
    if target.ok:
      w.buildTrap(r, kind, target.at)
      side.trapSlot += 1
      return

  if side.doctrine.waterDigPolicy != wdNone and
      w.stats.tilesDug[ord(side.team)] < SetupDigTarget * 3:
    let dig = w.setupDigTarget(side, r)
    if dig.ok and w.mayTerraform(side, r, digCostFor(r.levelOf(skBuild))):
      w.doDig(r, dig.at)
      return

  let terra = w.terraformTarget(side, r)
  if terra.kind == 1 and w.mayTerraform(side, r, digCostFor(r.levelOf(skBuild))):
    w.doDig(r, terra.at)
    return
  if terra.kind == 2 and w.mayTerraform(side, r, fillCostFor(r.levelOf(skBuild))):
    w.doFill(r, terra.at)
    return

  let pile = w.nearestCrumbPile(r)
  if pile.ok:
    discard w.greedyStep(side, r, pile.at)
    return
  discard w.greedyStep(side, r, w.trapStation(side, r))
