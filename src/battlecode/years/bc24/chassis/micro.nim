## bc24 micro: who to hit, who to mend, and when to break contact.
##
## Shared by every role. Ported from the behaviour of `chenyx512/battlecode24`
## `src/bot1/` and the retreat micro of `davidteather/battlecode_24`
## `src/submit6/` (both AGPL-3.0, credited in NOTICE), parameterised by
## `heal_priority` and `retreat_hp`.

import kit

export kit

proc attackTarget*(w: World, r: Robot): Robot =
  ## The lowest-HP enemy inside `r^2 <= 4`, ties broken toward the HIGHEST
  ## attack level: kill the veteran, because a level-6 attacker hits for 240
  ## and a fresh one for 150.
  var best: Robot = nil
  var bestHp = high(int)
  var bestLevel = -1
  for l in w.locationsWithinRadiusSquared(r.loc, AttackRadiusSquared):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team == r.team: continue
    let level = bot.levelOf(skAttack)
    if bot.health < bestHp or (bot.health == bestHp and level > bestLevel):
      bestHp = bot.health
      bestLevel = level
      best = bot
  best

proc healTarget*(w: World, side: Side, r: Robot): Robot =
  ## `heal_priority`, exactly as the knob table describes it.
  var lowest: Robot = nil
  var lowestHp = high(int)
  var veteran: Robot = nil
  var veteranHp = high(int)
  var carrier: Robot = nil
  for l in w.locationsWithinRadiusSquared(r.loc, HealRadiusSquared):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team != r.team: continue
    if bot.id == r.id: continue
    if bot.health >= DefaultHealth: continue
    if bot.health < lowestHp:
      lowestHp = bot.health
      lowest = bot
    if bot.levelOf(skAttack) >= 3 and bot.health < veteranHp:
      veteranHp = bot.health
      veteran = bot
    if bot.hasFlag() and carrier == nil:
      carrier = bot
  case side.doctrine.healPriority
  of hpWoundedFirst: lowest
  of hpAttackersFirst: (if veteran != nil: veteran else: lowest)
  of hpCarrierFirst: (if carrier != nil: carrier else: lowest)

proc shouldBreak*(side: Side, r: Robot): bool =
  ## `retreat_hp`. A duck that cannot retreat — cornered, or stunned — ATTACKS
  ## instead: the knob moves when a duck disengages, never whether it fights.
  r.health <= side.doctrine.retreatHp

proc retreatTarget*(w: World, side: Side, r: Robot): Loc =
  ## Toward the nearest friendly healer in sight, else toward the nearest own
  ## spawn centre.
  var best = loc(-1, -1)
  var bestD = high(int)
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team != r.team or bot.id == r.id: continue
    if bot.levelOf(skHeal) < 1 and not side.isHealer(bot): continue
    let d = r.loc.distanceSquaredTo(l)
    if d < bestD:
      bestD = d
      best = l
  if best.x >= 0: return best
  var target = side.ownCentres[0]
  var td = high(int)
  for c in side.ownCentres:
    let d = r.loc.distanceSquaredTo(c)
    if d < td:
      td = d
      target = c
  target

proc fightOrRetreat*(w: World, side: Side, r: Robot): bool
    {.discardable.} =
  ## The one combat routine every post-setup role calls first. Returns true
  ## when it did something with the duck's turn.
  if r.hasFlag(): return false
  let victim = w.attackTarget(r)
  if victim != nil and w.canAttack(r, victim.loc):
    w.doAttack(r, victim.loc)
    result = true
  if side.shouldBreak(r):
    let target = w.retreatTarget(side, r)
    if target.x >= 0 and w.greedyStep(side, r, target):
      return true
    ## Cornered or stunned: keep fighting rather than standing still.
    if victim == nil:
      let other = w.nearestEnemy(r, AttackRadiusSquared)
      if other != nil and w.canAttack(r, other.loc):
        w.doAttack(r, other.loc)
        return true

proc stunSelfDefence*(w: World, side: Side, r: Robot): bool
    {.discardable.} =
  ## "Drop a stun trap on your own tile when three or more enemies close and
  ## the crumbs are there" — bot1's rule, kept. Never spends the defensive
  ## reserve down past its own floor while the flock is still poor.
  if r.hasFlag(): return false
  if w.getCrumbs(side.team) < trapCostFor(tkStun, r.levelOf(skBuild)):
    return false
  if w.countNearby(r, 8, r.team.other()) < 3: return false
  if not w.canBuildTrap(r, tkStun, r.loc): return false
  w.buildTrap(r, tkStun, r.loc)
  true
