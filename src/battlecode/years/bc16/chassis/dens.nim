## `bulwark`'s `dens.nim schedule()` — when the faction commits a strike group
## to killing a ZOMBIEDEN, and which one.
##
## A den is 2000 HP and pays 200 parts on death, and killing it deletes that
## den's share of EVERY FUTURE WAVE for the rest of the game (measured: a
## played-pool den holds 51 to 138 queued zombies across a game). But 2000 HP
## at a soldier's 4 damage is FIVE HUNDRED attacks, and a den damages every
## adjacent non-zombie for 10 a round whenever it has a queue. Early is a real
## investment; late is a real concession — which is exactly what
## `den_clear_round` is asking the cog to decide.
##
## The target is the den with the largest remaining queue and the cheapest
## approach, and every member of the strike group is kept OUT of the eight
## adjacent squares except while attacking.

import ../world
import kit

export kit

proc schedule*(w: World, s: Side) =
  ## Run once a round, before the exec sweep.
  s.denCommitted = false
  s.hasDenTarget = false
  s.denTarget = loc(-1, -1)
  if w.brokenChassis: return              ## the negative control never commits
  if w.currentRound < s.doctrine.denClearRound: return
  ## A faction with nothing but its archons does not go den hunting — but the
  ## gate is an ABSOLUTE four attackers, not three per archon. Measured on the
  ## `small` pool: with the per-archon form, a three-archon faction under
  ## pressure never reached nine standing attackers at the same time and
  ## therefore NEVER BROKE A DEN in 3 000 rounds, while the horde escalated to
  ## x3 — so the knob could not be spent and the game had exactly one
  ## outcome.
  if s.attackers < 4: return
  var bestScore = -1.0e18
  for den in w.liveDens():
    let queue = w.denQueueRemaining(den)
    var approach = high(int)
    for a in s.archons:
      approach = min(approach, a.distanceSquaredTo(den.loc))
    if approach == high(int): approach = 0
    let score = float64(queue * 40) - float64(approach)
    if score > bestScore:
      bestScore = score
      s.denTarget = den.loc
      s.hasDenTarget = true
  s.denCommitted = s.hasDenTarget

func denApproachSquare*(w: World, s: Side, r: Robot): Loc =
  ## Where a strike-group member wants to stand: inside its own attack radius
  ## of the den but OUTSIDE the eight adjacent squares, so it never pays the
  ## 10-damage proximity charge while it works.
  result = loc(-1, -1)
  if not s.hasDenTarget: return
  let den = s.denTarget
  if r.kind.attackRadiusSquared() <= 2:
    ## A GUARD's reach is r2 2, which IS adjacent: it has to stand in the
    ## damage ring, and that is the price of a melee unit on a den.
    return den
  var bestScore = -1.0e18
  for l in w.locationsWithinRadiusSquared(den, r.kind.attackRadiusSquared()):
    if not r.spend(1): break
    if l.distanceSquaredTo(den) <= 2: continue
    if w.isLocationOccupied(l) and not (l == r.loc): continue
    if rubbleBlocks(w.getRubble(l), r.kind): continue
    let score = -float64(l.distanceSquaredTo(r.loc)) - w.getRubble(l) / 10.0
    if score > bestScore:
      bestScore = score
      result = l
