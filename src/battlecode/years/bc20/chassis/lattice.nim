## The lattice: which tiles inside `lattice_radius` of the own HQ are raised,
## and to what height.
##
## Bowl of Chowder's checkerboard parity is kept: only tiles whose `(x + y)` is
## EVEN are raised, so the odd tiles stay at ground level and units can always
## path through a finished lattice instead of being walled in by their own
## terraforming. The bar is `waterLevel(round + 250) + 1`, i.e. the lattice is
## always being built for the flood a quarter of a game ahead.
##
## Behaviour, not code, from `StoneT2000/Battlecode2020` (AGPL-3.0; see NOTICE).

import kit

func isLatticeTile*(l: Loc): bool = ((l.x + l.y) and 1) == 0

func isWallRing*(side: Side, l: Loc): bool =
  side.hasHq and chebyshev(l, side.hqLoc) == 1

proc latticeNeedsWork*(w: World, side: Side, l: Loc): bool =
  if not side.hasHq: return false
  if not l.isLatticeTile(): return false
  if chebyshev(l, side.hqLoc) > side.doctrine.latticeRadius: return false
  if l == side.hqLoc: return false
  if side.isWallRing(l): return false
  let occupant = w.getRobot(l)
  if occupant != nil and occupant.kind.isBuilding(): return false
  w.getDirt(l) < side.latticeTarget(w.currentRound)

proc lowestLatticeTileNear*(w: World, side: Side, r: Robot): (bool, Loc) =
  ## The lowest tile within the robot's own sense window that the lattice still
  ## wants raised. Charged per tile examined.
  var best = loc(0, 0)
  var bestElev = high(int)
  var found = false
  for l in w.sensed(r):
    if not w.latticeNeedsWork(side, l): continue
    let e = w.getDirt(l)
    if e < bestElev or (e == bestElev and found and
        l.distanceSquaredTo(r.loc) < best.distanceSquaredTo(r.loc)):
      bestElev = e
      best = l
      found = true
  (found, best)

proc digSourceFor*(w: World, side: Side, r: Robot,
                   protect: openArray[Loc]): Dir =
  ## A tile adjacent to the landscaper that dirt may be taken FROM: on the map,
  ## never the HQ ring, never a lattice tile the plan wants raised, never a
  ## building without dirt on it, and preferring the HIGHEST tile so the dig
  ## does not open a new flood path.
  var bestDir = dCenter
  var bestElev = low(int)
  for d in MoveDirs:
    if not r.spend(1): break
    let candidate = r.loc + d
    if not w.onTheMap(candidate): continue
    var skip = false
    for p in protect:
      if p == candidate: skip = true
    if skip: continue
    if side.isWallRing(candidate): continue
    if w.latticeNeedsWork(side, candidate): continue
    let occupant = w.getRobot(candidate)
    if occupant != nil and occupant.kind.isBuilding() and
        occupant.dirtCarrying <= 0: continue
    if not w.canDigDirt(r, d): continue
    let e = w.getDirt(candidate)
    if e > bestElev:
      bestElev = e
      bestDir = d
  bestDir
