## `builder.nim` — prototypes and repairs, and `watchtower_policy`.
##
## Behaviour ported from `BSreenivas0713/Battlecode2022` `src/MPTempName/`
## (AGPL-3.0): the prototype-then-repair discipline and the mutation ladder.
## BEHAVIOUR, NOT CODE. `NOTICE` names the files.
##
## THE DISCIPLINE, and it is the whole file: a building spawns as a PROTOTYPE at
## `(int)(0.8f * maxHealth)` and can neither act nor move until a builder has
## repaired it to full. A laboratory needs **ten** builder repairs (80 -> 100 at
## 2 a repair) and a watchtower **fifteen** (120 -> 150). **A prototype that is
## never finished is 180 Pb of nothing**, so the builder finishes what it starts
## before it does anything else.
##
## `towers()` IS `watchtower_policy`:
##
## * `never` — no watchtowers at all, and the builder's lead goes to
##   laboratories;
## * `home` — one per archon, in the lowest-rubble square within four of the
##   archon, level-2-mutated with lead once the second laboratory exists;
## * `forward` — built at the frontier the strike group holds, which is the play
##   the 2022 meta never made.

import kit, econ, lab, gold

export kit

func wantsWatchtower*(w: World, side: Side): bool =
  case side.doctrine.watchtowerPolicy
  of wpNever: false
  of wpHome, wpForward: side.watchtowers < max(1, side.archons)

proc unfinishedNear*(w: World, side: Side, r: Robot): Robot =
  ## The nearest friendly PROTOTYPE inside the builder's r2 <= 5.
  result = nil
  var best = high(int)
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtBuilder].actionRadiusSquared):
    let b = w.getRobot(l)
    if b == nil or b.team != side.team: continue
    if b.mode != rmPrototype: continue
    let d = chebyshev(r.loc, l)
    if d < best:
      best = d
      result = b

proc anyUnfinished*(w: World, side: Side): Robot =
  ## The nearest friendly PROTOTYPE anywhere the faction knows about — what the
  ## builder walks to when it has nothing in range.
  result = nil
  var best = high(int)
  for _, b in w.robotsById:
    if b.team != side.team or b.mode != rmPrototype: continue
    if b.id < best:
      best = b.id
      result = b

proc towerSite*(w: World, side: Side, r: Robot): Loc =
  ## Where the next watchtower goes.
  case side.doctrine.watchtowerPolicy
  of wpNever:
    loc(-1, -1)
  of wpHome:
    let home = nearestLiveArchon(w, side, r.loc)
    if home == nil: loc(-1, -1)
    else: lowestRubbleNear(w, side, home.loc, 16)
  of wpForward:
    if side.lastSightingRound >= 0 and
       w.currentRound - side.lastSightingRound < 100:
      lowestRubbleNear(w, side, side.lastSighting, 9)
    else:
      lowestRubbleNear(w, side, nearestEnemyHome(side, r.loc), 16)

proc runBuilder*(w: World, side: Side, r: Robot) =
  w.observe(side, r)
  ## 1. FINISH WHAT IS STANDING. A prototype that is never repaired is dead lead.
  let near = unfinishedNear(w, side, r)
  if near != nil:
    if w.canRepair(r, near.loc):
      w.doRepair(r, near.loc)
      return
  ## 2. Mutate, when the ladder says so.
  let target = bestMutationTarget(w, side, r)
  if target != nil and w.canMutate(r, target.loc):
    w.doMutate(r, target.loc)
    return
  ## 3. Place a laboratory, when the schedule has come and none stands.
  if side.labs == 0 and w.currentRound >= labScheduleRound(side) and
     not w.brokenChassis:
    let site = labSite(w, side, r.loc)
    if site.x >= 0:
      if chebyshev(r.loc, site) <= 1:
        let d = r.loc.directionTo(site)
        if w.canBuildRobot(r, rtLaboratory, d):
          w.doBuildRobot(r, rtLaboratory, d)
          return
      else:
        w.moveToward(side, r, site)
        return
  ## 4. Put up a watchtower, when the policy asks for one.
  if wantsWatchtower(w, side):
    let site = towerSite(w, side, r)
    if site.x >= 0:
      if chebyshev(r.loc, site) <= 1:
        let d = r.loc.directionTo(site)
        if w.canBuildRobot(r, rtWatchtower, d):
          w.doBuildRobot(r, rtWatchtower, d)
          return
      else:
        w.moveToward(side, r, site)
        return
  ## 5. Repair anything friendly and damaged in range, then walk to the nearest
  ##    unfinished building anywhere.
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtBuilder].actionRadiusSquared):
    let b = w.getRobot(l)
    if b != nil and b.team == side.team and b.kind.isBuilding() and
       b.health < b.maxHealth() and w.canRepair(r, l):
      w.doRepair(r, l)
      return
  let far = anyUnfinished(w, side)
  if far != nil:
    w.moveToward(side, r, far.loc)
    return
  let home = nearestLiveArchon(w, side, r.loc)
  if home != nil and chebyshev(r.loc, home.loc) > 4:
    w.moveToward(side, r, home.loc)
