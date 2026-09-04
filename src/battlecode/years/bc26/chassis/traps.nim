## Trap laying. Knob sites: `cat_trap_budget` and `rat_trap_budget` — a rat
## stops placing once the team's LIVE trap count reaches the budget, so a
## doctrine that banks traps before it turns really does bank them.
##
## The engine caps live traps per team at `TrapType.maxCount` (25 rat, 10
## cat) regardless of the doctrine, so a budget above that ceiling means
## "always place when you can" rather than "place more than the rules allow".

import kit, targets

proc wantsCatTrap*(w: World, clan: Clan): bool =
  clan.doctrine.catTrapBudget > 0 and
    w.trapCount(ttCatTrap, clan.team) < clan.doctrine.catTrapBudget and
    w.catTrapsAllowed(clan.team)

proc wantsRatTrap*(w: World, clan: Clan): bool =
  clan.doctrine.ratTrapBudget > 0 and
    w.trapCount(ttRatTrap, clan.team) < clan.doctrine.ratTrapBudget

const KingThreatRadiusSquared* = 25
  ## A cat this close to a crown is closing on it: `CAT_POUNCE_MAX_DISTANCE_
  ## SQUARED` is 13 and a cat moves every other round, so five tiles is about
  ## two rounds of warning.

proc threatenedKing(w: World, clan: Clan, r: Robot): (bool, Loc, Loc) =
  ## The clan's own crown with a cat closing on it, and that cat. Nothing in
  ## the chassis used to read "a cat is near my king" at all: cat traps were
  ## laid wherever a rat happened to see a cat, never around the thing whose
  ## loss ends the game (r2-D2).
  for other in w.liveRobots:
    if other.unit != utCat: continue
    if not r.canSenseLocation(other.loc): continue
    for king in w.liveRobots:
      if king.team != clan.team or king.unit != utRatKing: continue
      if king.loc.distanceSquaredTo(other.loc) <= KingThreatRadiusSquared:
        return (true, king.loc, other.loc)
  (false, r.loc, r.loc)

proc tryPlaceTraps*(w: World, clan: Clan, r: Robot): bool =
  ## One trap per turn at most (it costs the action). Cat traps go between a
  ## closing cat and the clan's own crown when there is one to defend, else on
  ## the tile a nearby cat is walking into; rat traps go beside the rat, which
  ## is where an enemy chasing it will step.
  if not r.canActCooldown: return false
  if not r.spend(8): return false

  if wantsCatTrap(w, clan) and clan.catsAreTargets() and r.spend(6):
    ## RING THE CROWN. A cat trap is 100 damage and 20 rounds of stun for 10
    ## cheese; laid on the ring the cat has to cross it is the cheapest
    ## defence the clan has, and losing every king loses the game outright.
    ## A doctrine that says `cat_engagement: avoid` means it: an avoiding clan
    ## lays no cat traps and does no cat damage, here as everywhere else.
    let (threatened, kingLoc, catLoc) = threatenedKing(w, clan, r)
    if threatened:
      let toward = kingLoc.directionTo(catLoc)
      for d in [toward, toward.rotateLeft(), toward.rotateRight()]:
        if d == dCenter: continue
        for step in 2 .. 3:
          let spot = kingLoc.translate(d.dx * step, d.dy * step)
          if w.canPlaceTrap(r, spot, ttCatTrap):
            w.buildTrap(r, spot, ttCatTrap)
            return true

  if wantsCatTrap(w, clan):
    for t in visibleTargets(w, clan, r):
      if t.kind != tkCat: continue
      if not r.spend(3): break
      let ahead = t.loc
      for d in NonCenterDirs:
        let spot = ahead + d
        if w.canPlaceTrap(r, spot, ttCatTrap):
          w.buildTrap(r, spot, ttCatTrap)
          return true

  if wantsRatTrap(w, clan) and clan.hostilitiesOpen(w):
    for d in NonCenterDirs:
      if not r.spend(1): break
      let spot = r.loc + d
      if w.canPlaceTrap(r, spot, ttRatTrap):
        w.buildTrap(r, spot, ttRatTrap)
        return true
  false
