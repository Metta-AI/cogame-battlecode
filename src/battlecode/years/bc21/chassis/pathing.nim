## Pathing: a bounded BFS over the sensed window with a passability-weighted
## cost, falling back to a greedy step with a six-tile no-repeat history to
## break oscillation. Every node expanded and every direction evaluated is
## charged against the robot's `DecisionOps` budget.
##
## Behaviour from `StoneT2000/Battlecode2021` `src/maxecosushi/` (AGPL-3.0,
## commit 5c2a7ee) — the "step toward the target on the cheapest passable
## neighbour, remembering where you have been" discipline, rewritten in Nim.

import kit

const
  BfsBudget* = 96
    ## Nodes expanded per call. The window a robot can see is at most ~125
    ## tiles, so this is a real bound rather than a formality.
  HistoryLen* = 6

proc remember(brain: Brain, l: Loc) =
  brain.history.add(l)
  if brain.history.len > HistoryLen:
    brain.history.delete(0)

proc visitedRecently(brain: Brain, l: Loc): bool =
  for h in brain.history:
    if h == l: return true
  false

proc stepCost(w: World, l: Loc): float64 =
  let p = w.getPassability(l)
  if p <= 0.0: 1.0e9 else: 1.0 / p

proc greedyStep*(w: World, side: Side, r: Robot, target: Loc): Dir =
  ## The fallback, and the whole of the move for a robot with no budget left:
  ## the legal neighbour that most reduces the squared distance, breaking ties
  ## on passability and refusing a tile in the no-repeat history.
  let brain = side.brainFor(r)
  var best = dCenter
  var bestScore = high(float64)
  for d in MoveDirs:
    if not spend(r, 1): break
    let l = r.loc + d
    if not w.canMove(r, d): continue
    var score = float64(l.distanceSquaredTo(target)) * stepCost(w, l)
    if brain.visitedRecently(l): score = score * 4.0
    if score < bestScore:
      bestScore = score
      best = d
  best

proc pathStep*(w: World, side: Side, r: Robot, target: Loc): Dir =
  ## A bounded Dijkstra-ish BFS over the sensed window. Returns the FIRST step
  ## of the cheapest route found; falls back to `greedyStep` when the target is
  ## outside the window or the budget runs out.
  if not r.kind.canMoveKind(): return dCenter
  if r.loc == target: return dCenter
  let radius = RobotSpecs[r.kind].sensorRadiusSquared
  if r.loc.distanceSquaredTo(target) > radius:
    return greedyStep(w, side, r, target)

  var frontier: seq[tuple[l: Loc, first: Dir, cost: float64]]
  var seen: seq[Loc]
  for d in MoveDirs:
    if not w.canMove(r, d): continue
    let l = r.loc + d
    frontier.add((l: l, first: d, cost: stepCost(w, l)))
    seen.add(l)

  var bestDir = dCenter
  var bestCost = high(float64)
  var head = 0
  var expanded = 0
  while head < frontier.len and expanded < BfsBudget:
    if not spend(r, 1): break
    let node = frontier[head]
    inc head
    inc expanded
    if node.l == target:
      if node.cost < bestCost:
        bestCost = node.cost
        bestDir = node.first
      break
    for d in MoveDirs:
      let n = node.l + d
      if not w.onTheMap(n): continue
      if n.distanceSquaredTo(r.loc) > radius: continue
      if w.isLocationOccupied(n) and not (n == target): continue
      var known = false
      for s in seen:
        if s == n:
          known = true
          break
      if known: continue
      seen.add(n)
      frontier.add((l: n, first: node.first, cost: node.cost + stepCost(w, n)))

  if bestDir == dCenter:
    return greedyStep(w, side, r, target)
  bestDir

proc moveToward*(w: World, side: Side, r: Robot, target: Loc): bool
    {.discardable.} =
  ## One step toward `target`, remembering where we went. False when the robot
  ## could not move at all.
  if not isReady(r): return false
  let d = pathStep(w, side, r, target)
  if d == dCenter: return false
  if not w.canMove(r, d): return false
  w.move(r, d)
  side.brainFor(r).remember(r.loc)
  true

proc moveAwayFrom*(w: World, side: Side, r: Robot, threat: Loc): bool
    {.discardable.} =
  if not isReady(r): return false
  var best = dCenter
  var bestScore = -1
  for d in MoveDirs:
    if not spend(r, 1): break
    if not w.canMove(r, d): continue
    let l = r.loc + d
    let score = l.distanceSquaredTo(threat)
    if score > bestScore:
      bestScore = score
      best = d
  if best == dCenter: return false
  w.move(r, best)
  side.brainFor(r).remember(r.loc)
  true
