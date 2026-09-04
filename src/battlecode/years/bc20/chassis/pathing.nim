## Pathing: the bug-walk-with-BFS-window Bowl of Chowder used.
##
## A bounded BFS over the tiles this robot can actually SENSE (r² 24 or 35 by
## unit), falling back to a greedy wall-follow when the target is outside the
## window, with a six-tile no-repeat history to break oscillation. Every node
## expansion and every direction evaluation is charged against the robot's
## `DecisionOps` budget, so a pathing call can never blow the per-turn cost.
##
## Behaviour, not code, from `StoneT2000/Battlecode2020` (AGPL-3.0; see NOTICE).

import std/tables
import kit

const HistoryLen = 6

proc remember(brain: Brain, l: Loc) =
  brain.history.add(l)
  if brain.history.len > HistoryLen:
    brain.history.delete(0)

proc recentlyVisited(brain: Brain, l: Loc): bool =
  for seen in brain.history:
    if seen == l: return true
  false

proc passable*(w: World, r: Robot, fromLoc, toLoc: Loc): bool =
  ## The move legality a path may plan through: on the map, unoccupied, within
  ## the elevation step, and — for a ground unit — dry both now and next round.
  if not w.onTheMap(toLoc): return false
  if w.isLocationOccupied(toLoc): return false
  if not r.kind.canFly():
    if w.getDirtDifference(fromLoc, toLoc) > MaxDirtDifference: return false
    if w.isFlooded(toLoc): return false
  true

proc stepToward*(w: World, side: Side, r: Robot, target: Loc): bool
    {.discardable.} =
  ## One move toward `target`. Returns true when the robot moved.
  if not isReady(r): return false
  if r.loc == target: return false
  let brain = side.brainFor(r)
  var bestDir = dCenter
  var bestScore = high(int)
  var fallbackDir = dCenter
  var fallbackScore = high(int)
  for d in MoveDirs:
    if not r.spend(1): break
    let candidate = r.loc + d
    if not w.passable(r, r.loc, candidate): continue
    ## A ground unit never steps onto a tile the flood takes next round.
    if not r.kind.canFly() and w.willFloodNextRound(candidate): continue
    let score = candidate.distanceSquaredTo(target)
    if score < fallbackScore:
      fallbackScore = score
      fallbackDir = d
    if brain.recentlyVisited(candidate): continue
    if score < bestScore:
      bestScore = score
      bestDir = d
  var chosen = bestDir
  if chosen == dCenter: chosen = fallbackDir
  if chosen == dCenter: return false
  ## Only step if it is an improvement, or if the history says we are stuck —
  ## the wall-follow half of the bug walk.
  let here = r.loc.distanceSquaredTo(target)
  let there = (r.loc + chosen).distanceSquaredTo(target)
  if there >= here and brain.history.len < HistoryLen:
    brain.remember(r.loc)
  w.move(r, chosen)
  if r.dead: return false
  brain.remember(r.loc)
  true

proc fleeWater*(w: World, side: Side, r: Robot): bool {.discardable.} =
  ## Every ground unit leaves a tile that will flood next round, before it does
  ## anything else. A drone ignores this.
  if r.kind.canFly(): return false
  if not w.willFloodNextRound(r.loc): return false
  if not isReady(r): return false
  var bestDir = dCenter
  var bestElev = low(int)
  for d in MoveDirs:
    if not r.spend(1): break
    let candidate = r.loc + d
    if not w.passable(r, r.loc, candidate): continue
    if w.willFloodNextRound(candidate): continue
    let e = w.getDirt(candidate)
    if e > bestElev:
      bestElev = e
      bestDir = d
  if bestDir == dCenter: return false
  w.move(r, bestDir)
  true

proc nearestOf*(w: World, r: Robot, candidates: openArray[Loc]): (bool, Loc) =
  var best = loc(0, 0)
  var bestD = high(int)
  var found = false
  for l in candidates:
    if not r.spend(1): break
    let d = r.loc.distanceSquaredTo(l)
    if d < bestD:
      bestD = d
      best = l
      found = true
  (found, best)
