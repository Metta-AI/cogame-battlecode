## A LUMBERJACK's turn: strike, chop or walk -- and the own-HP rule that stops
## the swarm eating its own farm.
##
## A lumberjack is 100 bullets, 50 HP, **carries no bullets at all**, and has
## two verbs:
##
##   * `strike()` -- 2 damage to EVERY robot and EVERY tree within distance 2
##     of it, **WITH NO TEAM CHECK**: its own gardeners and its own farm
##     included. `orchard` NEVER fires a strike whose own-HP cost (own robots
##     plus own trees inside the disc) exceeds the enemy's, at EVERY setting
##     of `lumberjack_share`, and counts every refusal so the test can see it.
##   * `chop(tree)` -- 5 damage to ONE tree, and **the only action in the game
##     that releases a neutral tree's contents** (a robot joins the chopping
##     team; bullets are credited to it).
##
## `chop_policy` decides what it goes for: `never` (bodies only),
## `clear_path` (only what blocks the rally lane) or `harvest` (trees with a
## robot inside first, then trees with bullets, then the lane).

import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit, econ, military, comms

export kit

proc strikeValue*(w: World, s: Side, r: Robot): (int, int) =
  ## (enemy HP at risk, own HP at risk) inside the strike disc, counting
  ## trees as well as bodies -- because the trees are the income.
  var enemyHp = 0
  var ownHp = 0
  for c in w.robotIndex.withinRadius(r.loc, lumberjackStrikeRadius):
    let other = w.robots.getOrDefault(int(c.id))
    if other == nil or other.id == r.id: continue
    if not r.chargeFor(1): break
    let hp = int(min(other.health, attackPower(r.kind)))
    if other.team == s.team: ownHp += hp + 1 else: enemyHp += hp + 1
  for c in w.treeIndex.withinRadius(r.loc, lumberjackStrikeRadius):
    let tr = w.trees.getOrDefault(int(c.id))
    if tr == nil: continue
    if not r.chargeFor(1): break
    if tr.team == s.team: ownHp += 3        ## an own tree is income, so it
                                            ## is priced above a body's HP
    elif tr.team != tNeutral: enemyHp += 3
  (enemyHp, ownHp)

proc chopTarget*(w: World, s: Side, r: Robot): int =
  ## The tree this lumberjack should chop, per `chop_policy`.
  result = -1
  if s.doctrine.chopPolicy == cp17Never:
    return -1
  var bestScore = -1
  for id in w.senseTrees(r, bodyRadius(r.kind) + neutralTreeMaxRadius +
                            interactionDistFromEdge):
    let tr = w.trees.getOrDefault(id)
    if tr == nil or tr.team == s.team: continue
    if not r.canInteractWithTree(tr): continue
    if not r.chargeFor(1): break
    var score = 0
    if tr.team != tNeutral:
      score = 40                     ## an enemy bullet tree is always worth it
    else:
      case s.doctrine.chopPolicy
      of cp17Never: continue
      of cp17ClearPath:
        ## Only what blocks the lane: a tree between us and the rally point.
        let rally = s.enemyBase(r.loc)
        let toRally = (if r.loc == rally: dirRads(0'f32)
                       else: directionTo(r.loc, rally))
        let toTree = directionTo(r.loc, tr.loc)
        if abs(radiansBetween(toRally, toTree)) < 1'f32: score = 10
        else: continue
      of cp17Harvest:
        if tr.containedRobot >= 0: score = 60
        elif tr.containedBullets > 0: score = 30
        else: score = 5
    if score > bestScore:
      bestScore = score
      result = id

proc runLumberjack*(w: World, s: Side, r: Robot) =
  let enemies = w.senseRobots(r, -1'f32, ord(s.team.opponent()))
  ## Strike when it is worth it, and NEVER when it is not.
  if not r.hasAttacked():
    let (enemyHp, ownHp) = w.strikeValue(s, r)
    if enemyHp > 0 and ownHp <= enemyHp:
      discard w.strike(r)
    elif enemyHp > 0:
      inc s.strikesRefused
  if not r.hasAttacked():
    let target = w.chopTarget(s, r)
    if target >= 0:
      discard w.chop(r, target)
  if r.hasMoved(): return
  if enemies.len > 0:
    let e = w.robots.getOrDefault(enemies[0])
    if e != nil:
      w.walkTowards(r, e.loc)
      return
  ## Nothing in reach: walk at the chop target, then at the rally point.
  let target = w.chopTarget(s, r)
  if target >= 0 and w.trees.hasKey(target):
    w.walkTowards(r, w.trees[target].loc)
  else:
    w.walkTowards(r, w.readRally(s, r))
