## An ARCHON's turn: hire, keep out of the way, and stamp the rally point.
##
## An archon is 400 HP, radius 2, strides 0.5, **cannot be built and cannot
## shoot**, and is the only unit that can hire a GARDENER. So its whole job is
## to keep hiring, which means it must never box itself in: it hires into the
## free direction nearest its REAR (an archon that plants a gardener between
## itself and its own farm has spent its next ten turns walking).
##
## It also carries the year's quietest rule: **tiebreak rung 3 sums
## `type.bulletCost` over live robots and `ARCHON.bulletCost` is `-1`**, so a
## surviving archon is worth MINUS ONE BULLET on the third rung. Keeping it
## alive is still right -- rung 1 and rung 2 come first, and a dead archon
## hires nothing -- but it is why `orchard` does not hide its archons behind
## the whole army.

import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit, econ, comms, military

export kit

proc hireDirection*(w: World, s: Side, r: Robot): (Dir, bool) =
  ## The free direction nearest the rear, scanning sixteen bearings from
  ## "away from the enemy" outward. One credit per bearing evaluated.
  let enemy = s.enemyBase(r.loc)
  let away = (if r.loc == enemy: dirRads(0'f32)
              else: directionTo(r.loc, enemy).opposite())
  for step in 0 .. 7:
    for sign in [1'f32, -1'f32]:
      if not r.chargeFor(1): return (away, false)
      let d = (if sign > 0'f32: away.rotateLeftDegrees(float32(step) * 22'f32)
               else: away.rotateRightDegrees(float32(step) * 22'f32))
      if w.canBuildRobot(r, rtGardener, d):
        return (d, true)
      if step == 0: break
  (away, false)

proc runArchon*(w: World, s: Side, r: Robot) =
  ## 1. hire while the target is unmet; 2. retreat from the nearest sensed
  ## enemy on a fifteen-unit leash; 3. stamp the rally point every five
  ## rounds.
  if w.wantsGardener(s) and r.isBuildReady():
    let essential = w.gardenerIsEssential(s)
    if w.canSpend(s, bulletCostF(rtGardener), essential):
      let (dir, ok) = w.hireDirection(s, r)
      if ok and w.hireGardener(r, dir):
        s.commit(bulletCostF(rtGardener))

  let enemies = w.senseRobots(r, -1'f32, ord(s.team.opponent()))
  if enemies.len > 0:
    let threat = w.robots.getOrDefault(enemies[0])
    if threat != nil and distanceTo(r.loc, threat.loc) < 8'f32:
      w.walkAwayFrom(r, threat.loc, s.homeArchon(r.loc), 15'f32)
  elif not r.hasMoved():
    ## Keep the spawn ring clear: drift one stride away from the nearest own
    ## gardener rather than standing in its farm.
    let friends = w.senseRobots(r, 6'f32, ord(s.team))
    for id in friends:
      let f = w.robots.getOrDefault(id)
      if f != nil and f.kind == rtGardener and
          distanceTo(r.loc, f.loc) < 4'f32:
        w.walkAwayFrom(r, f.loc, s.homeArchon(r.loc), 12'f32)
        break

  w.postRally(s, r, s.enemyBase(r.loc))
