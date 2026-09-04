## The Design School: build a Landscaper whenever the roster is under the
## `landscaper_count_curve` target and the pool can pay for one, preferring a
## direction on the HQ side so a new landscaper starts where the wall is.
##
## Behaviour, not code, from `StoneT2000/Battlecode2020` (AGPL-3.0; see NOTICE).

import kit

proc runDesignSchool*(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)
  brain.turnCount += 1
  if not isReady(r): return
  if w.alive(side, rtLandscaper) >=
      side.doctrine.landscaperTarget(w.currentRound): return
  if w.stats.soup[ord(side.team)] < RobotSpecs[rtLandscaper].cost: return
  var bestDir = dCenter
  var bestScore = high(int)
  for d in MoveDirs:
    if not r.spend(1): break
    if not w.canBuildRobot(r, rtLandscaper, d): continue
    let candidate = r.loc + d
    var score = if side.hasHq: chebyshev(candidate, side.hqLoc) else: 0
    if w.willFloodNextRound(candidate): score += 100
    if score < bestScore:
      bestScore = score
      bestDir = d
  if bestDir == dCenter: return
  if w.buildRobot(r, rtLandscaper, bestDir) >= 0:
    w.firstBuild(side, rtLandscaper)
