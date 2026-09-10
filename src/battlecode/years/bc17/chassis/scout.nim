## A SCOUT's turn: screen, squat or hunt -- and shake on the way.
##
## A scout is 80 bullets, **TEN health**, strides 1.25 (the fastest body in
## the game), sees 14 (the widest eyes), fires singles only for 0.5 damage --
## and is **THE ONLY BODY THAT MAY OVERLAP A TREE**, which is the one thing
## only a scout can do: park inside a neutral tree where nothing but a bullet
## can reach it and shoot gardeners from there.
##
## `scout_harass` is both the share of the budget and the DEPTH: below 34 it
## screens its own trees and shakes on the way; 34..66 it squats the enemy's
## neutral trees inside their farm; above 66 it hunts gardeners exclusively
## and never comes home.

import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit, econ, micro, military, comms

export kit

proc shakeTarget*(w: World, s: Side, r: Robot): int =
  ## The nearest neutral tree in reach that still holds bullets.
  result = -1
  if s.doctrine.shakeNeutralTrees == sn17Never: return -1
  for id in w.senseTrees(r, bodyRadius(r.kind) + neutralTreeMaxRadius +
                            interactionDistFromEdge, ord(tNeutral)):
    let tr = w.trees.getOrDefault(id)
    if tr == nil or tr.containedBullets <= 0: continue
    if r.canInteractWithTree(tr): return id

proc squatTarget*(w: World, s: Side, r: Robot): Loc =
  ## Where this scout wants to be. `dedicated` shaking sends it round the
  ## nearest bullet-bearing trees; otherwise the depth decides.
  let enemy = s.enemyBase(r.loc)
  if s.doctrine.shakeNeutralTrees == sn17Dedicated:
    for id in w.senseTrees(r, -1'f32, ord(tNeutral)):
      let tr = w.trees.getOrDefault(id)
      if tr != nil and tr.containedBullets > 0:
        return tr.loc
  if s.doctrine.scoutHarass > 66:
    ## Hunt gardeners: their farm is the mirror of ours, so aim there even
    ## before one is sensed.
    return enemy
  if s.doctrine.scoutHarass >= 34:
    ## Squat the enemy's neutral trees: a scout may overlap one.
    for id in w.senseTrees(r, -1'f32, ord(tNeutral)):
      let tr = w.trees.getOrDefault(id)
      if tr != nil and distanceTo(tr.loc, enemy) < distanceTo(r.loc, enemy):
        return tr.loc
    return enemy
  ## Screen: sit between our farm and theirs.
  let home = s.homeArchon(r.loc)
  addDist(home, (if home == enemy: dirRads(0'f32)
                 else: directionTo(home, enemy)), 8'f32)

proc runScout*(w: World, s: Side, r: Robot) =
  let enemies = w.senseRobots(r, -1'f32, ord(s.team.opponent()))
  ## A gardener is worth more than a soldier to a 0.5-damage pea.
  var target = -1
  for id in enemies:
    let e = w.robots.getOrDefault(id)
    if e == nil: continue
    if e.kind == rtGardener or e.kind == rtArchon:
      target = id
      break
  if target < 0 and enemies.len > 0: target = enemies[0]
  if target >= 0:
    let e = w.robots.getOrDefault(target)
    if e != nil and not r.hasAttacked():
      discard w.engage(s, r, @[target])
  ## Shake whatever is in reach -- free, and one turn.
  let shakeId = w.shakeTarget(s, r)
  if shakeId >= 0: discard w.shake(r, shakeId)
  ## Report, but never from inside enemy territory: broadcasting would put a
  ## 10-HP body on both teams' maps.
  let enemy = s.enemyBase(r.loc)
  if enemies.len > 0 and distanceTo(r.loc, enemy) > 20'f32:
    w.postThreat(s, r, r.loc, enemies.len)
  let threats = w.threatSet(r)
  if threats.len > 0 and w.dodge(r, threats): return
  if r.hasMoved(): return
  if target >= 0 and s.doctrine.scoutHarass >= 34:
    let e = w.robots.getOrDefault(target)
    if e != nil:
      w.walkTowards(r, e.loc)
      return
  w.walkTowards(r, w.squatTarget(s, r))
