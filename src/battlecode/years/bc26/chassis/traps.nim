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

proc tryPlaceTraps*(w: World, clan: Clan, r: Robot): bool =
  ## One trap per turn at most (it costs the action). Cat traps go on the
  ## tile a nearby cat is walking into; rat traps go beside the rat, which is
  ## where an enemy chasing it will step.
  if not r.canActCooldown: return false
  if not r.spend(8): return false

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
