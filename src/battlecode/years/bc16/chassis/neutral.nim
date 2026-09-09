## `bulwark`'s `neutral.nim plan()` — free units for two core delay.
##
## Measured: 80 of the 98 official maps carry neutrals, the played pool
## carries 0 to 26 each, and `caverns` and `industrial` each carry two neutral
## ARCHONS — a whole extra tiebreak rung, another repair field and another
## parts collector, for zero parts.
##
## `never`: archons never detour, and the horde eats the neutrals (rule
## 5.5h). `opportunistic`: activate anything already within r2 <= 8 of the
## archon's intended path. `hunt`: route archons deliberately along the
## roster, nearest-first with neutral ARCHONs and TURRETs first by value.

import ../world
import kit

export kit

func neutralValue*(k: RobotType): int =
  ## `partCost` with ARCHON above everything — an archon cannot be built at
  ## any price, so its value is not its cost.
  case k
  of rtArchon: 1000
  of rtTurret: 130
  of rtViper: 120
  of rtSoldier, rtGuard: 30
  of rtScout: 25
  else: 0

proc activateAdjacent*(w: World, s: Side, r: Robot): bool {.discardable.} =
  ## The activation itself: r2 <= 2, so the eight neighbours and the archon's
  ## own square. Taken at EVERY setting except `never`, because a neutral
  ## already in reach costs nothing but two core delay.
  if r.kind != rtArchon: return false
  if s.doctrine.neutralActivation == naNever: return false
  var bestAt = loc(-1, -1)
  var bestValue = 0
  for d in MoveDirs:
    if not r.spend(1): break
    let target = r.loc + d
    if not w.canActivate(r, target): continue
    let other = w.getRobot(target)
    if other == nil: continue
    let value = neutralValue(other.kind)
    if value > bestValue:
      bestValue = value
      bestAt = target
  if bestAt.x < 0: return false
  w.doActivate(r, bestAt)

proc target*(w: World, s: Side, r: Robot): Loc =
  ## Where an archon should walk to pick a neutral up, or `(-1, -1)`.
  result = loc(-1, -1)
  if s.doctrine.neutralActivation == naNever: return
  let radius = if s.doctrine.neutralActivation == naHunt: 2000 else: 8
  var bestScore = -1.0e18
  for other in w.senseNearbyRobots(r, -1):
    if not r.spend(1): break
    if other.team != teamNeutral: continue
    let d = other.loc.distanceSquaredTo(r.loc)
    if d > radius: continue
    var claimed = false
    for c in s.claimedNeutrals:
      if c == other.loc: claimed = true
    if claimed: continue
    let score = float64(neutralValue(other.kind) * 10) - float64(d)
    if score > bestScore:
      bestScore = score
      result = other.loc
  if result.x >= 0:
    s.claimedNeutrals.add(result)
