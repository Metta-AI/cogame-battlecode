## `applyCurrents` — the end-of-round shove, as a DETERMINISTIC WORKLIST.
##
## A behaviour port of `GameWorld.applyCurrents` and `addToNotMoving` at
## commit `af42086ecd09709dc603b2aaa9e9b98312c9ef79`. The engine's version is
## driven by `HashMap`/`HashSet` iteration; the port replaces that with a FIFO
## worklist over robot ids ascending (D3), and the replacement is exact rather
## than approximate:
##
## * every robot forecasts `location + current(location)` (`CENTER` when the
##   tile has no current);
## * a robot is IMMEDIATELY BLOCKED when its forecast tile is impassable, off
##   the map, or contested by more than one robot;
## * the blocked set is closed TRANSITIVELY — a robot forecast onto the tile
##   of a robot that is not moving is also not moving;
## * every remaining robot standing on a real current is lifted off the board
##   and set down one square along it.
##
## The closure is a well-defined FIXED POINT independent of iteration order,
## because at most one robot occupies a tile and the engine's `visited`-by-
## location guard makes "visited" and "processed" the same predicate. So the
## worklist computes the same set the `HashSet` recursion does, in an order
## that does not depend on a hash.
##
## MEASURED over all 103 official maps: no current flows into a wall or off
## the map and no two currents share a target, so the only real driver of
## blocking is robots blocking robots. `tests/test_bc23_currents.nim` asserts
## the closure against a reference fixed point over 500 random layouts.

import std/[algorithm, tables]
import world

export world

proc applyCurrents*(w: World) =
  ## Rule 4d. `currentRound % CURRENT_STRENGTH == 0` is `% 1`, i.e. ALWAYS.
  var ids = w.execOrder
  ## Ascending id, so the worklist is deterministic. The result is
  ## order-independent; the ORDER is pinned anyway so the trace is.
  ids.sort()

  var forecastOwners = initTable[int, seq[int]]()
    ## forecast TILE INDEX (or -1 for off the map) -> robot ids, ascending.
  var forecastOf = initTable[int, int]()
  var offMap: seq[int]
  for id in ids:
    let r = w.robotsById[id]
    let d = w.getCurrent(r.loc)
    let dest = r.loc + d
    if not w.onTheMap(dest):
      offMap.add(id)
      forecastOf[id] = -1
      continue
    let i = w.idx(dest)
    forecastOf[id] = i
    if not forecastOwners.hasKey(i):
      forecastOwners[i] = @[]
    forecastOwners[i].add(id)

  var notMoving = initTable[int, bool]()
  var queue: seq[int]

  proc markBlocked(id: int) =
    if notMoving.hasKey(id): return
    notMoving[id] = true
    queue.add(id)

  ## Immediately blocked: the forecast tile is off the map, impassable, or
  ## contested by more than one robot.
  for id in offMap: markBlocked(id)
  for i, owners in forecastOwners:
    let dest = w.indexToLoc(i)
    if (not w.isPassable(dest)) or owners.len > 1:
      for id in owners: markBlocked(id)

  ## Transitive closure: a robot forecast onto the CURRENT tile of a robot
  ## that is not moving is also not moving. The engine's `visited` set is
  ## keyed by the blocked robot's ORIGINAL location, which is the same as
  ## keying by the robot, because at most one robot occupies a tile.
  var head = 0
  while head < queue.len:
    let id = queue[head]
    head += 1
    if not w.existsRobot(id): continue
    let here = w.idx(w.robotsById[id].loc)
    if forecastOwners.hasKey(here):
      for other in forecastOwners[here]:
        markBlocked(other)

  ## Lift and set down. Every robot that is still moving and stands on a REAL
  ## current is removed from the board first, then placed, exactly as the
  ## engine does it in two passes — which is what lets a chain of robots on a
  ## conveyor all advance one square in the same round.
  var moving: seq[int]
  for id in ids:
    if notMoving.hasKey(id): continue
    if not w.existsRobot(id): continue
    let r = w.robotsById[id]
    if w.getCurrent(r.loc) == dCenter: continue
    moving.add(id)
  for id in moving:
    let r = w.robotsById[id]
    w.occupant[w.idx(r.loc)] = nil
  for id in moving:
    let r = w.robotsById[id]
    let dest = r.loc + w.getCurrent(r.loc)
    r.loc = dest
    w.occupant[w.idx(dest)] = r
    w.stats.currentRides[ord(r.team)] += 1
