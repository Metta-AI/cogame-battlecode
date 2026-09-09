## `bulwark`'s archon turn — in the ENGINE'S OWN ACTION ORDER, because an
## archon is the only thing that decides this game.
##
## An ARCHON is 1000 HP, cannot be built, and is the only repair source (1 HP
## a turn, free, r2 <= 24, once a turn), the only parts collector (whole
## square, by standing on it or moving onto it) and the only activator of
## NEUTRALs (r2 <= 2, free, 2 core delay). LOSE YOUR LAST ONE AND YOU LOSE ON
## THE SPOT.
##
## The turn, in order:
##
## 1. **spend the free repair** on the weakest damaged friendly non-archon in
##    r2 <= 24 — it costs NO delay of either kind, so there is never a reason
##    not to;
## 2. **activate** a neutral already in reach (`neutral.nim`), which is a free
##    unit for two core delay;
## 3. **build** what `econ.nim queue()` asks for, into the free adjacent
##    square nearest the frontier, never boxing itself in and NEVER into a
##    square adjacent to a den that has zombies queued;
## 4. **posture** per `archon_spread`, walking over parts squares wherever the
##    route allows because a move onto parts collects them for nothing.
##
## The unconditional floors, at every knob setting: a build order whenever the
## stockpile is above 200, and the LAST archon never steps into a den's
## damage ring.

import ../world
import kit, econ, neutral, comms

export kit

proc repairSomebody(w: World, s: Side, r: Robot): bool {.discardable.} =
  if w.brokenChassis: return false        ## the negative control never repairs
  if r.repairCount >= 1: return false
  var bestAt = loc(-1, -1)
  var worst = 1.0e18
  for other in w.senseNearbyRobots(r, 24):
    if not r.spend(1): break
    if other.team != r.team: continue
    if other.kind == rtArchon: continue
    if other.health >= other.maxHealth: continue
    if not w.canRepair(r, other.loc): continue
    let deficit = other.health
    if deficit < worst:
      worst = deficit
      bestAt = other.loc
  if bestAt.x < 0: return false
  w.doRepair(r, bestAt)

proc buildSite(w: World, s: Side, r: Robot, kind: RobotType): Dir =
  ## The free adjacent square nearest the frontier that the new unit can
  ## actually stand on, and that is not in a den's damage ring.
  result = dNone
  var bestScore = -1.0e18
  for d in MoveDirs:
    if not r.spend(1): break
    if not w.canBuild(r, d, kind): continue
    let at = r.loc + d
    if nearDenWithQueue(w, at): continue
    var score = -w.getRubble(at) / 10.0
    if s.frontier.x >= 0:
      score -= float64(at.distanceSquaredTo(s.frontier)) / 10.0
    if score > bestScore:
      bestScore = score
      result = d

proc buildSomething(w: World, s: Side, r: Robot): bool {.discardable.} =
  if not r.d.isCoreReady(): return false
  for kind in buildQueue(w, s):
    if not canAfford(w, s, kind): continue
    let d = buildSite(w, s, r, kind)
    if d == dNone: continue
    if w.doBuild(r, d, kind):
      s.commit(kind)
      return true
  false

proc postureTarget(w: World, s: Side, r: Robot): Loc =
  ## `posture()` per `archon_spread`, and the parts walk that pays for it.
  ##
  ## `huddle`: keep every archon inside r2 <= 24 of another so their repair
  ## fields overlap. `spread`: hold r2 ~ 50-100 apart, each with its own
  ## screen. `split`: send one archon away to farm the far parts squares and
  ## the far neutrals while the rest hold — which the measured maps reward
  ## hard (`quadrants` has 20 520 parts over 684 squares; `turtle` has 1 800
  ## on SIX).
  result = loc(-1, -1)
  ## A neutral in reach outranks everything: it is a free unit.
  let neutralAt = neutral.target(w, s, r)
  if neutralAt.x >= 0: return neutralAt
  ## **`archon_spread` BIASES THE PARTS WALK, and that is where its teeth
  ## are.** MEASURED, and the reason this is here: with the knob reachable
  ## ONLY as the last arm of this proc, `huddle` and `split` produced
  ## byte-identical games on `river` and `checkers` (285 units, 31 800 parts
  ## and 1 den apiece) -- because an archon on a real map ALWAYS has a
  ## remembered parts square to walk at, so the posture arm below was never
  ## reached and the knob had no teeth at all.
  ##
  ## The bias is a distance term measured from OUR OWN ARCHON CENTROID:
  ##   `huddle` pulls the walk toward the centroid, so the repair fields stay
  ##     overlapped and one wall protects every archon;
  ##   `spread` is neutral -- nearest-and-richest, the default;
  ##   `split` sends the FIRST archon in the census outward and holds the rest
  ##     in, which is what a 20 520-parts-over-684-squares map rewards and
  ##     what a six-square map punishes.
  var cx = 0
  var cy = 0
  if s.archons.len > 0:
    for l in s.archons:
      cx += l.x
      cy += l.y
    cx = cx div s.archons.len
    cy = cy div s.archons.len
  let centroid = loc(cx, cy)
  let outward = s.doctrine.archonSpread == asSplit and
                s.archons.len > 1 and s.archons[0] == r.loc
  let inward = s.doctrine.archonSpread == asHuddle or
               (s.doctrine.archonSpread == asSplit and not outward)
  proc spreadBias(l: Loc): float64 =
    ## Positive is better. `huddle` prefers a square NEAR the centroid;
    ## `split`'s roamer prefers one FAR from it; `spread` is indifferent.
    if s.archons.len == 0: return 0.0
    let d = float64(l.distanceSquaredTo(centroid))
    if outward: d / 8.0
    elif inward: -d / 8.0
    else: 0.0
  ## Then the nearest parts square inside vision, because a move onto parts
  ## collects the whole square for nothing.
  var bestParts = loc(-1, -1)
  var bestScore = -1.0e18
  for l in w.locationsWithinRadiusSquared(r.loc, r.kind.sightRadiusSquared()):
    if not r.spend(1): break
    if w.getParts(l) <= 0.0: continue
    if rubbleBlocks(w.getRubble(l), r.kind): continue
    let score = w.getParts(l) - float64(l.distanceSquaredTo(r.loc)) +
                spreadBias(l)
    if score > bestScore:
      bestScore = score
      bestParts = l
  if bestParts.x >= 0: return bestParts
  ## Nothing in sight: walk at the best REMEMBERED parts square. Measured on
  ## `caverns` (1 078 of 1 892 squares impassable, 110 parts squares) a
  ## sight-radius-only archon collected ZERO parts in 1 350 rounds, because
  ## every deposit is outside r2 35 of its opening square.
  var remembered = loc(-1, -1)
  var bestRemembered = -1.0e18
  for l in s.partsTargets:
    if not r.spend(1): break
    if w.getParts(l) <= 0.0: continue
    let score = -float64(l.distanceSquaredTo(r.loc)) / 4.0 + spreadBias(l)
    if score > bestRemembered:
      bestRemembered = score
      remembered = l
  if remembered.x >= 0: return remembered
  case s.doctrine.archonSpread
  of asHuddle:
    ## Close on the nearest other archon until the repair fields overlap.
    var nearest = loc(-1, -1)
    var best = high(int)
    for l in s.archons:
      if l == r.loc: continue
      let d = l.distanceSquaredTo(r.loc)
      if d < best:
        best = d
        nearest = l
    if nearest.x >= 0 and best > 24: return nearest
    result = loc(-1, -1)
  of asSpread:
    ## Open up if we are inside r2 50 of another archon.
    for l in s.archons:
      if l == r.loc: continue
      if l.distanceSquaredTo(r.loc) < 50:
        return loc(r.loc.x + (r.loc.x - l.x), r.loc.y + (r.loc.y - l.y))
    result = loc(-1, -1)
  of asSplit:
    ## The FIRST archon in the census farms the far half of the map; the rest
    ## hold. "Far" is the enemy-facing side of our own centroid, which is
    ## where the unclaimed parts and neutrals are.
    if s.archons.len > 1 and s.archons[0] == r.loc and s.frontier.x >= 0:
      return s.frontier
    result = loc(-1, -1)

proc threatStep(w: World, s: Side, r: Robot): bool {.discardable.} =
  ## An ARCHON HAS NO ATTACK. Standing next to a BIGZOMBIE is 25 damage a
  ## round (75 at outbreak level 9) against the only unit that decides the
  ## game, so an archon that is in contact with something that can shoot it
  ## steps away first and builds afterwards.
  if not r.d.isCoreReady(): return false
  var threat = loc(-1, -1)
  var best = high(int)
  for other in w.senseHostileRobots(r, 8):
    if not r.spend(1): break
    if not canAttack(other.kind): continue
    let d = other.loc.distanceSquaredTo(r.loc)
    if d < best:
      best = d
      threat = other.loc
  if threat.x < 0: return false
  if best > 4: return false
  w.stepToward(r, threat, away = true)

proc runArchon*(w: World, s: Side, r: Robot) =
  discard repairSomebody(w, s, r)
  discard activateAdjacent(w, s, r)
  discard buildSomething(w, s, r)
  broadcastRally(w, s, r)
  if not r.d.isCoreReady(): return
  if threatStep(w, s, r): return
  let target = postureTarget(w, s, r)
  if target.x < 0: return
  ## THE LAST ARCHON NEVER STEPS INTO A DEN'S DAMAGE RING, at any setting.
  if s.archons.len <= 1:
    var safe = true
    for d in MoveDirs:
      if r.loc + d == target and nearDenWithQueue(w, target): safe = false
    if not safe: return
  discard w.stepToward(r, target)
