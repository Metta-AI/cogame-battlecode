## Target selection: what a rat is allowed to want.
##
## Two knobs have their site here. `backstab_policy` gates the ENEMY list —
## with hostilities closed an enemy rat is simply not a candidate, which is
## what makes "cooperate" a real state rather than a label. `cat_engagement`
## weights the cat list: `avoid` removes cats outright, `hunt` ranks them
## above cheese, `feed` additionally arms the carry-a-rat-to-a-cat play.

import kit

type
  TargetKind* = enum
    tkNone
    tkCheese
    tkCat
    tkEnemy
    tkKing

  Target* = object
    kind*: TargetKind
    loc*: Loc
    robotId*: int

proc catsAreTargets*(clan: Clan): bool =
  clan.doctrine.catEngagement != ceAvoid

proc catWeight*(clan: Clan): int =
  ## Higher beats cheese. `hunt` is the only setting that outranks economy.
  case clan.doctrine.catEngagement
  of ceAvoid: 0
  of ceOpportunistic: 2
  of ceHunt: 8
  of ceFeed: 3

proc visibleTargets*(w: World, clan: Clan, r: Robot): seq[Target] =
  ## Everything this rat may legitimately act on, in sense order.
  if not r.spend(20): return
  for other in w.senseNearbyRobots(r):
    if not r.spend(2): break
    if other.unit == utCat:
      if clan.catsAreTargets():
        result.add(Target(kind: tkCat, loc: other.loc, robotId: other.id))
    elif other.team != clan.team:
      if clan.hostilitiesOpen(w):
        let kind = if other.unit == utRatKing: tkKing else: tkEnemy
        result.add(Target(kind: kind, loc: other.loc, robotId: other.id))

proc nearestCheese*(w: World, clan: Clan, r: Robot): Target =
  ## The richest tile of cheese inside the rat's cone, ties broken by
  ## distance then by tile index so the choice is stable.
  result = Target(kind: tkNone)
  if not r.spend(10): return
  var bestAmount = 0
  var bestDist = high(int)
  for l in w.allLocationsWithinRadiusSquared(
      r.loc, r.visionRadiusSquared, r.chirality):
    if not r.spend(1): break
    if not r.canSenseLocation(l): continue
    let amount = w.getCheeseAmount(l)
    if amount <= 0: continue
    let d = r.loc.distanceSquaredTo(l)
    if amount > bestAmount or (amount == bestAmount and d < bestDist):
      bestAmount = amount
      bestDist = d
      result = Target(kind: tkCheese, loc: l, robotId: -1)

proc nearestCheeseMine*(w: World, clan: Clan, r: Robot): Target =
  ## The nearest cheese MINE inside the rat's cone. A mine is a fixed tile
  ## that drops 20 cheese within four tiles of itself every dozen rounds or
  ## so, all game; a miner that knows where one is has an income, and one that
  ## only ever chases cheese already in its cone does not (r2-D2: the clans
  ## left 2 900 cheese lying on `DefaultSmall` while their kings starved).
  result = Target(kind: tkNone)
  if not r.spend(10): return
  var bestDist = high(int)
  for l in w.allLocationsWithinRadiusSquared(
      r.loc, r.visionRadiusSquared, r.chirality):
    if not r.spend(1): break
    if not w.hasCheeseMine(l): continue
    if not r.canSenseLocation(l): continue
    let d = r.loc.distanceSquaredTo(l)
    if d < bestDist:
      bestDist = d
      result = Target(kind: tkCheese, loc: l, robotId: -1)

proc bestAttackTarget*(w: World, clan: Clan, r: Robot): Target =
  ## The adjacent thing worth biting, ranked by the `cat_engagement` weight
  ## against a flat enemy-rat weight.
  result = Target(kind: tkNone)
  var best = 0
  for t in visibleTargets(w, clan, r):
    if not r.spend(2): break
    if not w.canAttack(r, t.loc): continue
    let weight =
      case t.kind
      of tkCat: clan.catWeight()
      of tkKing: 7
      of tkEnemy: 5
      else: 0
    if weight > best:
      best = weight
      result = t
