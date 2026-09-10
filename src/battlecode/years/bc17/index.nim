## The bc17 candidate index: a uniform grid over the arena, and the six
## `ObjectInfo` queries reproduced filter for filter.
##
## **D2 -- THE `net.sf.jsi` R-TREE IS NOT PORTED; THE CANDIDATE ORDER IS
## NORMALISED ON BOTH SIDES.** Every spatial query in the 2017 engine goes
## through `SpatialIndex.nearestN(point, procedure, Integer.MAX_VALUE, radius)`
## (`ObjectInfo.java:328-442`). Measured in the sandbox: `nearestN` delivers
## entries in ASCENDING DISTANCE from the query point (200 random points,
## 200/200 ascending), because it fills a descending priority queue and then
## calls `setSortOrder(ASCENDING)` and pops. **But for EXACT TIES the order is
## an artefact of the R-tree's node layout and the queue's heapify, and it is
## not even stable under a delete-and-re-add of the same point set** -- the
## same five points gave `[13527, 11304, 10137, 12235]` and then
## `[13527, 12235, 10137, 11304]` in one process. Reproducing that means
## porting jsi's R-tree with its split heuristics AND jsi's `PriorityQueue`'s
## heapify, and then depending on both forever.
##
## So: this file enumerates candidates from a uniform grid, applies the
## engine's own `isWithinDistance` filter, and orders them by
## **`(distanceSquaredTo(query) ascending, id ascending)`** -- computed with
## `MapLocation.distanceSquaredTo`'s exact float32 expression -- and
## `tools/oracle/bc17/rtree_order.patch` replaces `ObjectInfo`'s six `nearestN`
## call sites with THE SAME ENUMERATION ON THE ENGINE SIDE. The normalisation
## is symmetric; neither trace is massaged alone.
##
## **WHERE THE ORDER IS OBSERVABLE, EXHAUSTIVELY** (docs/RULES-BC17.md D2):
##   (i)   the two strict-minimum `hitDist` loops in `updateBullet` -- ties only;
##   (ii)  the tank's closest-tree pick -- ties only;
##   (iii) `getRobotAtLocation` / `getTreeAtLocation`, which return the FIRST
##         match -- ties only, and at most one body can contain a point unless
##         a SCOUT is standing on a tree;
##   (iv)  **the ORDER of the array `senseNearbyRobots`/`Trees`/`Bullets` hands
##         the chassis** -- fully order-dependent, and the reason the
##         normalisation must be ascending DISTANCE rather than merely a
##         tie-break: `examplefuncsplayer17` fires at `robots[0]` and that must
##         be the nearest enemy on both sides.
## Where it is NOT observable: `strike()` (every candidate is damaged),
## `destroyTree`'s scout scan (every overlapping scout dies) and
## `isEmpty`/`noRobotsExceptForRobot` (a length test).
##
## THE THREE STRICT-MINIMUM LOOPS DO NOT SORT, and that is not an
## optimisation: "the first candidate that achieves the minimum, in
## `(distSq, id)` order" IS "the lexicographic minimum of
## `(metric, distSq, id)`", so `minimalCandidate` computes the engine's answer
## in one allocation-free pass. `sortedCandidates` exists for the four
## chassis-visible senses, where the whole order is the observable.
##
## The grid is 8 units a cell over the map rectangle. It is a pure
## accelerator: `tests/test_bc17_index.nim` asserts it returns EXACTLY the
## engine's filtered set over 10 000 random configurations against a
## brute-force scan, so a cell-size change can never be a rules change.

import std/[algorithm, tables]
import geom

const CellSize* = 8'f32

type
  Circle* = object
    ## One indexed body: its id, its centre and its own radius. A bullet's
    ## radius is zero -- it is a moving point.
    id*: int32
    loc*: Loc
    radius*: float32

  Index* = object
    rect*: MapRect
    cols*, rows*: int
    cells*: seq[seq[int32]]
    cellOf*: Table[int32, int]
    circles*: Table[int32, Circle]
    maxRadius*: float32
      ## The largest radius ever stored. The scan widens by this, so it is
      ## deliberately monotone: a conservative over-scan can only add
      ## candidates the `isWithinDistance` filter then rejects, and never
      ## remove one.

func cellIndex(idx: Index, l: Loc): int =
  var cx = int((l.x - idx.rect.origin.x) / CellSize)
  var cy = int((l.y - idx.rect.origin.y) / CellSize)
  if cx < 0: cx = 0
  if cy < 0: cy = 0
  if cx >= idx.cols: cx = idx.cols - 1
  if cy >= idx.rows: cy = idx.rows - 1
  cy * idx.cols + cx

proc initIndex*(rect: MapRect): Index =
  result.rect = rect
  result.cols = max(1, int(rect.width / CellSize) + 1)
  result.rows = max(1, int(rect.height / CellSize) + 1)
  result.cells = newSeq[seq[int32]](result.cols * result.rows)
  result.cellOf = initTable[int32, int]()
  result.circles = initTable[int32, Circle]()
  result.maxRadius = 0'f32

proc add*(idx: var Index, id: int32, l: Loc, radius: float32) =
  let cell = idx.cellIndex(l)
  idx.cells[cell].add(id)
  idx.cellOf[id] = cell
  idx.circles[id] = Circle(id: id, loc: l, radius: radius)
  if radius > idx.maxRadius: idx.maxRadius = radius

proc remove*(idx: var Index, id: int32) =
  let cell = idx.cellOf.getOrDefault(id, -1)
  if cell < 0: return
  var i = 0
  while i < idx.cells[cell].len:
    if idx.cells[cell][i] == id:
      idx.cells[cell].delete(i)
      break
    inc i
  idx.cellOf.del(id)
  idx.circles.del(id)

proc move*(idx: var Index, id: int32, l: Loc) =
  ## `ObjectInfo.moveRobot`/`moveBullet`: a delete and an add at the new point.
  let old = idx.cellOf.getOrDefault(id, -1)
  var c = idx.circles.getOrDefault(id)
  c.loc = l
  idx.circles[id] = c
  let cell = idx.cellIndex(l)
  if cell == old: return
  if old >= 0:
    var i = 0
    while i < idx.cells[old].len:
      if idx.cells[old][i] == id:
        idx.cells[old].delete(i)
        break
      inc i
  idx.cells[cell].add(id)
  idx.cellOf[id] = cell

func contains*(idx: Index, id: int32): bool = idx.circles.hasKey(id)

func circleOf*(idx: Index, id: int32): Circle = idx.circles[id]

iterator scan(idx: Index, center: Loc, reach: float32): Circle =
  ## Every indexed body whose cell can hold something within `reach` of
  ## `center`, unfiltered and in no particular order.
  let ox = idx.rect.origin.x
  let oy = idx.rect.origin.y
  var x0 = int((center.x - reach - ox) / CellSize)
  var x1 = int((center.x + reach - ox) / CellSize)
  var y0 = int((center.y - reach - oy) / CellSize)
  var y1 = int((center.y + reach - oy) / CellSize)
  if x0 < 0: x0 = 0
  if y0 < 0: y0 = 0
  if x1 >= idx.cols: x1 = idx.cols - 1
  if y1 >= idx.rows: y1 = idx.rows - 1
  for cy in y0 .. y1:
    let base = cy * idx.cols
    for cx in x0 .. x1:
      for id in idx.cells[base + cx]:
        yield idx.circles[id]

iterator withinRadius*(idx: Index, center: Loc, radius: float32): Circle =
  ## `ObjectInfo.getAllTreesWithinRadius` / `getAllRobotsWithinRadius`'s
  ## FILTER: `body.location.isWithinDistance(center, body.radius + radius)`.
  ##
  ## The jsi search radius the engine passes (`radius + 10` for trees,
  ## `radius + 2` for robots) is redundant against this filter, because no
  ## tree radius exceeds `NEUTRAL_TREE_MAX_RADIUS` and no body radius exceeds
  ## `MAX_ROBOT_RADIUS` -- so the filter is the whole of the rule and the
  ## patched engine applies exactly it.
  for c in idx.scan(center, radius + idx.maxRadius):
    if isWithinDistance(c.loc, center, c.radius + radius):
      yield c

iterator withinPointRadius*(idx: Index, center: Loc, radius: float32): Circle =
  ## `ObjectInfo.getAllBulletsWithinRadius`: no body-radius term at all -- the
  ## engine passes the radius straight to `nearestN` as its furthest distance
  ## and applies NO procedure-side filter, so the cut IS the rule.
  for c in idx.scan(center, radius):
    if isWithinDistance(c.loc, center, radius):
      yield c

func sortedCandidates*(idx: Index, center: Loc, radius: float32,
                       pointOnly = false): seq[int32] =
  ## The normative enumeration: `(distanceSquaredTo(center), id)` ascending.
  ## Used wherever the ORDER of the returned array is observable to a chassis
  ## (D2 (iv)) and by the engine-side `rtree_order.patch`.
  var rows: seq[tuple[d: float32, id: int32]]
  if pointOnly:
    for c in idx.withinPointRadius(center, radius):
      rows.add((d: distanceSquaredTo(c.loc, center), id: c.id))
  else:
    for c in idx.withinRadius(center, radius):
      rows.add((d: distanceSquaredTo(c.loc, center), id: c.id))
  rows.sort(proc (a, b: tuple[d: float32, id: int32]): int =
    if a.d < b.d: -1
    elif a.d > b.d: 1
    elif a.id < b.id: -1
    elif a.id > b.id: 1
    else: 0)
  result = newSeqOfCap[int32](rows.len)
  for r in rows: result.add(r.id)

func countWithin*(idx: Index, center: Loc, radius: float32): int =
  ## `getAll...WithinRadius(...).length`, for the length tests
  ## (`isEmpty`, `noRobotsExceptForRobot`) where no order is observable.
  for _ in idx.withinRadius(center, radius): inc result

func firstContaining*(idx: Index, l: Loc): int32 =
  ## `getTreeAtLocation` / `getRobotAtLocation`: the engine returns the FIRST
  ## candidate whose circle contains the point, in enumeration order, so this
  ## is the `(distSq, id)`-minimal one. `-1` for none.
  ##
  ## `getAllTreesWithinRadius(loc, 0)`'s filter is `dist <= radius + 0`, which
  ## is exactly "the point is inside the circle", so the two queries share
  ## this one implementation.
  result = -1
  var bestD = 0'f32
  for c in idx.withinRadius(l, 0'f32):
    let d = distanceSquaredTo(c.loc, l)
    if result < 0 or d < bestD or (d == bestD and c.id < result):
      result = c.id
      bestD = d
