## bc24 building: the crumb spend plan, where the traps go, which trap, and
## the terraforming policy.
##
## Behaviour ported from `chenyx512/battlecode24` `src/bot1/` (the checkerboard
## builder dig, the stun-trap-on-a-threatened-flag rule) and `andli28/bc2024`
## `src/mainbot/` (the BFS memory layout), both AGPL-3.0 and credited in
## NOTICE. Parameterised by `trap_budget`, `trap_placement`, `trap_mix` and
## `water_dig_policy`.
##
## THE FLOOR THAT NO KNOB CAN LOWER (the LEARNINGS pin, D2): whatever the
## sheet says, the chassis keeps `DefenceReserve` crumbs after round 200 and
## spends them on a stun trap the moment an own flag is sensed under threat.
## `trap_budget: 0` therefore means "no PLANNED traps", never "an undefended
## flag".

import kit

export kit

const
  MaxChokesPerFlag* = 4
  RingRadius* = 2
    ## The Chebyshev ring `flag_ring` and `moat` both work on.

# ---------------------------------------------------------------------------
#  The spend plan
# ---------------------------------------------------------------------------

func trapAllowance*(w: World, side: Side): int =
  ## The share of crumb INCOME the builders may put into traps, cumulative
  ## over the game. At `trap_budget: 0` it is zero and the planned-trap path
  ## never fires at all — which is exactly what gives the knob its teeth.
  w.stats.crumbsCollected[ord(side.team)] * side.doctrine.trapBudget div 100

func trapAllowanceLeft*(w: World, side: Side): int =
  max(0, trapAllowance(w, side) - w.stats.crumbsSpentTraps[ord(side.team)])

proc plannedTrapKind*(side: Side): TrapKind =
  ## `trap_mix`: `mixed` alternates stun and explosive per placement slot.
  case side.doctrine.trapMix
  of tmStun: tkStun
  of tmExplosive: tkExplosive
  of tmMixed: (if (side.trapSlot and 1) == 0: tkStun else: tkExplosive)

proc mayBuildPlannedTrap*(w: World, side: Side, r: Robot,
                          kind: TrapKind): bool =
  let cost = trapCostFor(kind, r.levelOf(skBuild))
  if trapAllowanceLeft(w, side) < cost: return false
  w.getCrumbs(side.team) - cost >= DefenceReserve

proc mayTerraform*(w: World, side: Side, r: Robot, cost: int): bool =
  ## Terraforming never eats the defensive reserve, never runs the pool dry
  ## before round 300, and — when the doctrine wants traps — never spends the
  ## crumbs the next planned trap is being banked for. That last clause is
  ## what makes `trap_budget` trade against `water_dig_policy` rather than
  ## being two independent taps.
  let crumbs = w.getCrumbs(side.team)
  if crumbs - cost < DefenceReserve: return false
  if w.currentRound < 300 and crumbs - cost < 2 * DefenceReserve: return false
  if side.doctrine.trapBudget > 0:
    let want = trapCostFor(side.plannedTrapKind(), r.levelOf(skBuild))
    if trapAllowanceLeft(w, side) >= want and crumbs - cost < want + DefenceReserve:
      return false
  true

# ---------------------------------------------------------------------------
#  Chokes — measured ONCE, at round 201, by the BFS width test
# ---------------------------------------------------------------------------

proc measureChokes*(w: World, side: Side) =
  ## The narrowest passable cuts on the shortest route from an enemy spawn
  ## zone to each own flag. A tile is a candidate when it lies within four
  ## steps of a shortest path (`ownField + enemyField <= L + 4`); it is scored
  ## by how few passable neighbours it has, and tiles inside `r^2 <= 16` of an
  ## own flag are excluded — a choke at the flag IS the flag ring, and
  ## `trap_placement` would then have no teeth.
  if side.chokeMeasured: return
  side.chokeMeasured = true
  side.chokeTiles.setLen(0)
  for i in 0 .. 2:
    let oi = side.ownFieldIndex(i)
    if side.dist[oi].len == 0: continue
    var ej = -1
    var bestL = int(Unreachable)
    for j in 0 .. 2:
      let l = side.fieldAt(w, oi, side.enemyCentres[j])
      if l < bestL:
        bestL = l
        ej = side.enemyFieldIndex(j)
    if ej < 0 or bestL >= int(Unreachable): continue
    var picked = 0
    var bestScore = 9
    ## Two sweeps: the first finds the narrowest width on the corridor, the
    ## second takes up to four tiles at that width, in index order.
    for pass in 0 .. 1:
      for idx in 0 ..< w.width * w.height:
        let l = w.indexToLoc(idx)
        if w.walls[idx] or w.water[idx]: continue
        let a = int(side.dist[oi][idx])
        let b = int(side.dist[ej][idx])
        if a >= int(Unreachable) or b >= int(Unreachable): continue
        if a + b > bestL + 4: continue
        if a >= b: continue
        var nearFlag = false
        for c in side.ownCentres:
          if c.distanceSquaredTo(l) <= 16: nearFlag = true
        if nearFlag: continue
        var open = 0
        for dir in MoveDirs:
          let nl = l + dir
          if w.onTheMap(nl) and not w.walls[w.idx(nl)] and
             not w.water[w.idx(nl)]:
            open += 1
        if pass == 0:
          if open < bestScore: bestScore = open
        else:
          if open != bestScore: continue
          if picked >= MaxChokesPerFlag: break
          var already = false
          for t in side.chokeTiles:
            if t == l: already = true
          if already: continue
          side.chokeTiles.add(l)
          picked += 1

proc planBridge*(w: World, side: Side) =
  ## Is any enemy spawn centre reachable OVER LAND? If not, the flock is
  ## water-locked and no doctrine can play the game until a crossing is
  ## filled, so the cheapest route's water tiles become an unconditional
  ## builder job.
  side.bridgeTiles.setLen(0)
  if w.isSetupPhase(): return
  let n = w.width * w.height
  if side.landReach.len != n: side.landReach = newSeq[int32](n)
  for i in 0 ..< n: side.landReach[i] = 0
  var queue: seq[int32]
  for c in side.ownCentres:
    let i = w.idx(c)
    if side.landReach[i] == 0:
      side.landReach[i] = 1
      queue.add(int32(i))
  var head = 0
  while head < queue.len:
    let here = w.indexToLoc(int(queue[head]))
    head += 1
    for dir in MoveDirs:
      let nl = here + dir
      if not w.onTheMap(nl): continue
      let ni = w.idx(nl)
      if side.landReach[ni] != 0: continue
      if w.walls[ni] or w.water[ni]: continue
      side.landReach[ni] = 1
      queue.add(int32(ni))
  for c in side.enemyCentres:
    if side.landReach[w.idx(c)] != 0: return

  ## Water-locked. Walk downhill on the water-weighted field to the nearest
  ## enemy centre and collect the water tiles the route crosses.
  var best = -1
  var bestD = int(Unreachable)
  for j in 0 .. 2:
    let slot = side.enemyFieldIndex(j)
    let d = side.fieldAt(w, slot, side.ownCentres[0])
    if d < bestD:
      bestD = d
      best = slot
  if best < 0 or bestD >= int(Unreachable): return
  side.bridgeSlot = best
  var cur = side.ownCentres[0]
  for step in 0 ..< w.width * w.height:
    let here = side.fieldAt(w, best, cur)
    if here <= 0: break
    var nextLoc = cur
    var nextVal = here
    for dir in MoveDirs:
      let nl = cur + dir
      if not w.onTheMap(nl): continue
      if w.walls[w.idx(nl)]: continue
      let v = side.fieldAt(w, best, nl)
      if v < nextVal:
        nextVal = v
        nextLoc = nl
    if nextLoc == cur: break
    if w.getWater(nextLoc): side.bridgeTiles.add(nextLoc)
    cur = nextLoc

proc bridgeTargetNear*(w: World, side: Side, r: Robot):
    tuple[ok: bool, at: Loc] =
  for t in side.bridgeTiles:
    if not spend(r, 1): break
    if r.loc.distanceSquaredTo(t) > InteractRadiusSquared: continue
    if not w.getWater(t): continue
    if w.canFill(r, t): return (ok: true, at: t)

proc bridgeStation*(w: World, side: Side, r: Robot): tuple[ok: bool, at: Loc] =
  var bestD = high(int)
  for t in side.bridgeTiles:
    if not w.getWater(t): continue
    let d = r.loc.distanceSquaredTo(t)
    if d < bestD:
      bestD = d
      result = (ok: true, at: t)

# ---------------------------------------------------------------------------
#  Placement targets
# ---------------------------------------------------------------------------

iterator ringTiles*(w: World, centre: Loc, radius: int): Loc =
  ## The Chebyshev ring, walked clockwise from due north so the enemy-facing
  ## side is reached in a stable order.
  var x = centre.x - radius
  var y = centre.y + radius
  for step in 0 ..< 2 * radius:
    let l = loc(x + step, y)
    if w.onTheMap(l): yield l
  x = centre.x + radius
  for step in 0 ..< 2 * radius:
    let l = loc(x, y - step)
    if w.onTheMap(l): yield l
  y = centre.y - radius
  for step in 0 ..< 2 * radius:
    let l = loc(x - step, y)
    if w.onTheMap(l): yield l
  x = centre.x - radius
  for step in 0 ..< 2 * radius:
    let l = loc(x, y + step)
    if w.onTheMap(l): yield l

proc ownFlagLocs*(w: World, side: Side): seq[Loc] =
  for f in w.allFlags:
    if f.team == side.team: result.add(f.loc)

proc trapTargetNear*(w: World, side: Side, r: Robot,
                     kind: TrapKind): tuple[ok: bool, at: Loc] =
  ## The first legal placement inside the duck's interact radius that the
  ## doctrine's `trap_placement` asks for.
  case side.doctrine.trapPlacement
  of tpChoke:
    for t in side.chokeTiles:
      if not spend(r, 1): break
      if r.loc.distanceSquaredTo(t) > InteractRadiusSquared: continue
      if w.canBuildTrap(r, kind, t): return (true, t)
  of tpFlagRing:
    for centre in w.ownFlagLocs(side):
      for t in w.ringTiles(centre, RingRadius):
        if not spend(r, 1): break
        if r.loc.distanceSquaredTo(t) > InteractRadiusSquared: continue
        if w.canBuildTrap(r, kind, t): return (true, t)
  of tpSpawnRing:
    for centre in side.ownCentres:
      for t in w.ringTiles(centre, RingRadius):
        if not spend(r, 1): break
        if r.loc.distanceSquaredTo(t) > InteractRadiusSquared: continue
        if w.canBuildTrap(r, kind, t): return (true, t)

proc trapStation*(w: World, side: Side, r: Robot): Loc =
  ## Where a builder walks to when it wants to lay a trap: the placement
  ## anchor closest to it, so the flock spreads over the three flags.
  var best = side.ownCentres[0]
  var bestD = high(int)
  case side.doctrine.trapPlacement
  of tpChoke:
    if side.chokeTiles.len > 0:
      for t in side.chokeTiles:
        let d = r.loc.distanceSquaredTo(t)
        if d < bestD:
          bestD = d
          best = t
      return best
    for c in side.ownCentres:
      let d = r.loc.distanceSquaredTo(c)
      if d < bestD:
        bestD = d
        best = c
  of tpFlagRing:
    for c in w.ownFlagLocs(side):
      let d = r.loc.distanceSquaredTo(c)
      if d < bestD:
        bestD = d
        best = c
  of tpSpawnRing:
    for c in side.ownCentres:
      let d = r.loc.distanceSquaredTo(c)
      if d < bestD:
        bestD = d
        best = c
  best

# ---------------------------------------------------------------------------
#  Terraforming
# ---------------------------------------------------------------------------

func moatGap(w: World, side: Side, centre: Loc, l: Loc): bool =
  ## The gap a `moat` leaves so friendly ducks can still get to the flag: the
  ## three ring tiles on the side facing our OWN half. A moat that imprisons
  ## its own flock is exactly the self-starving setting the LEARNINGS pin
  ## forbids.
  var toward = side.ownCentres[0]
  var bestD = high(int)
  for c in side.enemyCentres:
    let d = centre.distanceSquaredTo(c)
    if d < bestD:
      bestD = d
      toward = c
  let away = centre + centre.directionTo(toward).opposite()
  chebyshev(l, away) <= 1

proc terraformTarget*(w: World, side: Side, r: Robot):
    tuple[kind: int, at: Loc] =
  ## `kind` is 0 none, 1 dig, 2 fill. Only tiles inside the duck's interact
  ## radius are ever returned; walking to them is `builderStation`'s job.
  result = (0, loc(-1, -1))
  case side.doctrine.waterDigPolicy
  of wdNone:
    discard
  of wdChokeDig:
    ## "Dig water across the two narrowest approaches to each own flag". The
    ## corridor is deliberately NARROW -- `r^2 <= 2` around each measured
    ## choke: an eight-radius version was tried and it walled the flock's OWN
    ## raiders in, which is precisely the self-starving setting the LEARNINGS
    ## pin forbids.
    for t in side.chokeTiles:
      for l in w.locationsWithinRadiusSquared(t, 2):
        if not spend(r, 1): return
        ## NEVER the choke tile itself: a builder that floods its own trap
        ## site cannot then trap it, and `trap_placement: choke` would have no
        ## teeth because the doctrine's own terraforming ate them.
        if l == t: continue
        if r.loc.distanceSquaredTo(l) > InteractRadiusSquared: continue
        if w.canDig(r, l): return (1, l)
  of wdMoat:
    for centre in w.ownFlagLocs(side):
      for t in w.ringTiles(centre, RingRadius):
        if not spend(r, 1): return
        if r.loc.distanceSquaredTo(t) > InteractRadiusSquared: continue
        if moatGap(w, side, centre, t): continue
        if w.canDig(r, t): return (1, t)
  of wdFillPaths:
    var slot = -1
    var bestD = high(int)
    for i in 0 .. 2:
      let ei = side.enemyFieldIndex(i)
      let d = side.fieldAt(w, ei, r.loc)
      if d < bestD:
        bestD = d
        slot = ei
    var best = loc(-1, -1)
    var bestField = high(int)
    for l in w.locationsWithinRadiusSquared(r.loc, InteractRadiusSquared):
      if not spend(r, 1): return
      if not w.getWater(l): continue
      if not w.canFill(r, l): continue
      let f = (if slot >= 0: side.fieldAt(w, slot, l) else: 0)
      if f < bestField:
        bestField = f
        best = l
    if best.x >= 0: return (2, best)

proc builderStation*(w: World, side: Side, r: Robot): Loc =
  ## Where a builder walks when it has nothing to do in reach.
  case side.doctrine.waterDigPolicy
  of wdFillPaths:
    var best = side.enemyCentres[0]
    var bestD = high(int)
    for c in side.enemyCentres:
      let d = r.loc.distanceSquaredTo(c)
      if d < bestD:
        bestD = d
        best = c
    best
  of wdChokeDig:
    if side.chokeTiles.len > 0:
      var best = side.chokeTiles[0]
      var bestD = high(int)
      for t in side.chokeTiles:
        let d = r.loc.distanceSquaredTo(t)
        if d < bestD:
          bestD = d
          best = t
      best
    else:
      w.trapStation(side, r)
  else:
    w.trapStation(side, r)
