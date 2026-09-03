## Biting, ratnapping, throwing, and feeding a carried rat to a cat.
##
## Knob site: `throw_rats_to_feed_cats`. The feed play is only armed when the
## doctrine asks for it AND `cat_engagement` is `feed`; on its own it is a
## way to lose a rat, which is exactly why it is a knob and not a default.

import kit, targets

proc feedArmed*(clan: Clan): bool =
  clan.doctrine.throwRatsToFeedCats and clan.doctrine.catEngagement == ceFeed

proc tryFeedCat*(w: World, clan: Clan, r: Robot): bool =
  ## Carry an ally rat up to a cat and throw it: the rat dies, the cat sleeps
  ## for `CAT_SLEEP_TIME` rounds and stops mauling the clan.
  if not feedArmed(clan): return false
  if not r.spend(6): return false

  if r.isCarryingRobot:
    for t in visibleTargets(w, clan, r):
      if t.kind != tkCat: continue
      if not r.spend(2): break
      let want = r.loc.directionTo(t.loc)
      if want == dCenter: continue
      if r.dir != want:
        if w.canTurn(r):
          w.turn(r, want)
        return true
      if w.canThrowRat(r):
        w.throwRat(r)
        clan.catsFed += 1
        return true
    return true

  ## Not carrying yet: grab the nearest ally rat, but only with a cat in
  ## sight, so the play cannot quietly disassemble the clan's own economy.
  var haveCat = false
  for t in visibleTargets(w, clan, r):
    if t.kind == tkCat:
      haveCat = true
      break
  if not haveCat: return false
  for d in NonCenterDirs:
    if not r.spend(1): break
    let spot = r.loc + d
    let other = w.getRobot(spot)
    if other != nil and other.team == clan.team and other.unit == utBabyRat and
        w.canCarryRat(r, spot):
      w.carryRat(r, spot)
      return true
  false

proc tryBite*(w: World, clan: Clan, r: Robot): bool =
  let t = bestAttackTarget(w, clan, r)
  if t.kind == tkNone: return false
  if not w.canAttack(r, t.loc): return false
  w.attack(r, t.loc)
  true

proc tryRatnap*(w: World, clan: Clan, r: Robot): bool =
  ## Only ever an ENEMY rat, and only with hostilities open — a ratnap is one
  ## of the four things that flips the world to BACKSTAB.
  if not clan.hostilitiesOpen(w): return false
  if r.isCarryingRobot: return false
  if not r.spend(4): return false
  for d in NonCenterDirs:
    if not r.spend(1): break
    let spot = r.loc + d
    let other = w.getRobot(spot)
    if other != nil and other.team != clan.team and other.unit == utBabyRat and
        w.canCarryRat(r, spot):
      w.carryRat(r, spot)
      return true
  false
