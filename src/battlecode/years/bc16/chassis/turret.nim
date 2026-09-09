## `bulwark`'s `turret.nim` — `target()`, `site()` and the pack/unpack
## schedule.
##
## A TURRET is 130 parts and 25 build turns of a FROZEN archon, cannot shoot
## anything closer than r2 6, reaches r2 40 for 13 damage (the longest reach
## in the game), and must PACK into a TTM — 10 delay on BOTH counters — to
## move at all, then UNPACK (another 10 on both) to shoot again. A relocation
## is therefore twenty turns of silence, and this module takes one only when
## the new site is clearly better.

import ../world
import kit, combat

export kit

const RelocateGain* = 2
  ## The covered-lane improvement a new site must show before a turret pays
  ## twenty turns of silence for it.

func coveredLanes*(w: World, s: Side, at: Loc): int =
  ## How many den approach lanes a site covers: dens whose straight line to
  ## our archon centroid passes inside r2 40 of `at`, which is what a turret
  ## can actually shoot.
  for id in w.execOrder:
    if not w.robotsById.hasKey(id): continue
    let den = w.robotsById[id]
    if den.kind != rtZombieden: continue
    if den.loc.distanceSquaredTo(at) <= 400: result += 1
  if s.frontier.x >= 0 and s.frontier.distanceSquaredTo(at) <= 400:
    result += 1

proc site*(w: World, s: Side, r: Robot): Loc =
  ## The lowest-rubble square inside the archon ring that covers the most
  ## lanes without sitting inside r2 6 of an archon (a turret cannot shoot
  ## what is standing on top of it).
  result = loc(-1, -1)
  let home = s.nearestArchon(r.loc)
  if home.x < 0: return
  var bestScore = -1.0e18
  for l in w.locationsWithinRadiusSquared(home, 40):
    if not r.spend(1): break
    if w.isLocationOccupied(l) and not (l == r.loc): continue
    if w.getRubble(l) >= RubbleObstructionThresh: continue
    if l.distanceSquaredTo(home) < TurretMinimumRange: continue
    let score = float64(coveredLanes(w, s, l) * 100) - w.getRubble(l)
    if score > bestScore:
      bestScore = score
      result = l

proc runTurret*(w: World, s: Side, r: Robot) =
  ## Unpack-and-hold: shoot the best target in [6, 40], and pack only when
  ## `site()` improves the covered-lane count by at least `RelocateGain`.
  let pick = pickTarget(w, s, r, s.denCommitted)
  if pick.ok:
    w.doAttack(r, pick.at)
    return
  let here = coveredLanes(w, s, r.loc)
  let want = site(w, s, r)
  if want.x >= 0 and not (want == r.loc) and
      coveredLanes(w, s, want) >= here + RelocateGain:
    r.hasTask = true
    r.taskLoc = want
    w.doTransform(r)                      ## pack: 10 on both counters

proc runTtm*(w: World, s: Side, r: Robot) =
  ## A TTM cannot attack and cannot clear rubble: it walks to its site and
  ## unpacks. If it has no site it unpacks where it stands rather than
  ## wandering, because a TTM is a 100-HP unit with no weapon.
  if r.hasTask and r.taskLoc.x >= 0 and not (r.loc == r.taskLoc):
    if w.stepToward(r, r.taskLoc): return
  r.hasTask = false
  w.doTransform(r)                        ## unpack
