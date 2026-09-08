## `examplefuncsplayer25` — the deliberately weak floor and the parity
## oracle's other side.
##
## Ported STATEMENT FOR STATEMENT from
## `battlecode25/example-bots/src/main/examplefuncsplayer/RobotPlayer.java` at
## the pinned commit. IT MAY NOT GAIN BEHAVIOUR: it is one side of the
## differential oracle, and any improvement here makes the oracle prove
## something other than "the ported rule set is the same rule set".
##
## LIKE 2024'S, THIS BOT NEEDS NO DETERMINISM PATCH. It declares
## `static final Random rng = new Random(6147)` and never calls
## `Math.random()`, so the oracle's Java side is upstream's file BYTE FOR BYTE.
## Static fields are per robot under the instrumenter, so every unit gets its
## own `Random(6147)` stream; `world.spawnRobotWithId` seeds one per unit and
## this file reproduces exactly that, in exactly that call order:
##
##   TOWER:    `rng.nextInt(8)` for a direction, then `rng.nextInt(3)` for a
##             type — ALWAYS BOTH, because neither is inside a short-circuit —
##             then build a SOLDIER on 0, a MOPPER on 1 and NOTHING on 2 (the
##             splasher branch is commented out upstream and stays commented
##             out here), then read messages.
##   SOLDIER:  scan `senseNearbyMapInfos()` in engine scan order and keep the
##             LAST ruin seen; step toward it; mark the PAINT-tower pattern if
##             the tile one step BACK from the ruin along that direction is
##             unmarked; paint every mismatched marked tile within r2 <= 8 of
##             the ruin; complete the pattern if it can. THEN, unconditionally,
##             one `rng.nextInt(8)`, a move if legal, and a paint under itself
##             if the tile is not already allied.
##   MOPPER:   one `rng.nextInt(8)`, a move if legal, then a mop swing in that
##             direction if legal ELSE a mop of the tile ahead, then the enemy
##             sweep.
##
## The eight `directions` are NORTH, NORTHEAST, EAST, SOUTHEAST, SOUTH,
## SOUTHWEST, WEST, NORTHWEST IN THAT ORDER, because `rng.nextInt(8)` indexes
## the array.
##
## `-d:bc25Scenario` compiles the Tier A-prime SCENARIO SCRIPT instead.

import kit
import scenario25

export kit

const ScaffoldSeed* = 6147
  ## `static final Random rng = new Random(6147)` — the same constant for
  ## every unit, and a SEPARATE STREAM for each of them.

const ScaffoldDirections* = [dNorth, dNortheast, dEast, dSoutheast,
                             dSouth, dSouthwest, dWest, dNorthwest]
  ## `RobotPlayer.directions`, in the file's own order.

proc updateEnemyRobots(w: World, side: Side, r: Robot) =
  ## `updateEnemyRobots`: sense every enemy in vision and, every twentieth
  ## round, offer the count to every ally it can reach. `canSendMessage`
  ## refuses robot<->robot, so in practice this only ever lands on a tower the
  ## mopper happens to be paint-connected to.
  var enemies: seq[Robot]
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not r.spend(1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.id == r.id: continue
    if bot.team == r.team: continue
    enemies.add(bot)
  if enemies.len == 0: return
  if w.currentRound mod 20 != 0: return
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not r.spend(1): break
    let ally = w.getRobot(l)
    if ally == nil or ally.team != r.team or ally.id == r.id: continue
    if w.canSendMessage(r, l, r):
      w.doSendMessage(r, l, enemies.len)

proc runScaffoldTower(w: World, side: Side, r: Robot) =
  let dir = ScaffoldDirections[int(r.scaffoldRng.nextInt(8))]
  let nextLoc = r.loc + dir
  let robotType = int(r.scaffoldRng.nextInt(3))
  if robotType == 0 and w.canBuildRobot(r, utSoldier, nextLoc):
    w.doBuildRobot(r, utSoldier, nextLoc)
  elif robotType == 1 and w.canBuildRobot(r, utMopper, nextLoc):
    w.doBuildRobot(r, utMopper, nextLoc)
  elif robotType == 2 and w.canBuildRobot(r, utSplasher, nextLoc):
    ## UPSTREAM COMMENTS OUT THE BUILD. The branch is reached, the indicator
    ## string is set, and nothing is built. It stays that way here.
    discard

proc runScaffoldSoldier(w: World, side: Side, r: Robot) =
  ## `senseNearbyMapInfos()` in engine scan order, keeping the LAST ruin seen
  ## — which is why the scan order is load-bearing for this bot.
  var curRuin = loc(-1, -1)
  var sawRuin = false
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not r.spend(1): break
    if w.hasRuin(l):
      curRuin = l
      sawRuin = true
  if sawRuin:
    let targetLoc = curRuin
    let dir = r.loc.directionTo(targetLoc)
    if w.canMove(r, dir):
      w.doMove(r, dir)
    let shouldBeMarked = targetLoc - dir
    if w.onTheMap(shouldBeMarked) and
        w.getMarker(r.team, shouldBeMarked) == MarkerNone and
        w.canMarkTowerPattern(r, tkPaint, targetLoc):
      w.doMarkTowerPattern(r, tkPaint, targetLoc)
    for l in w.locationsWithinRadiusSquared(targetLoc,
        ResourcePatternRadiusSquared):
      if not r.spend(1): break
      let mark = w.getMarker(r.team, l)
      if mark == MarkerNone: continue
      let want = if mark == MarkerSecondary: secondaryPaint(r.team)
                 else: primaryPaint(r.team)
      if w.getPaint(l) == want: continue
      if w.canAttackRobot(r, l):
        w.doAttackRobot(r, l, mark == MarkerSecondary)
    if w.canCompleteTowerPattern(r, tkPaint, targetLoc, r):
      w.doCompleteTowerPattern(r, tkPaint, targetLoc)

  let dir = ScaffoldDirections[int(r.scaffoldRng.nextInt(8))]
  if w.canMove(r, dir):
    w.doMove(r, dir)
  if not paintIsTeam(w.getPaint(r.loc), r.team) and
      w.canAttackRobot(r, r.loc):
    w.doAttackRobot(r, r.loc)

proc runScaffoldMopper(w: World, side: Side, r: Robot) =
  let dir = ScaffoldDirections[int(r.scaffoldRng.nextInt(8))]
  let nextLoc = r.loc + dir
  if w.canMove(r, dir):
    w.doMove(r, dir)
  if w.canMopSwing(r, dir):
    w.doMopSwing(r, dir)
  elif w.canAttackRobot(r, nextLoc):
    w.doAttackRobot(r, nextLoc)
  updateEnemyRobots(w, side, r)

proc runScaffold25*(w: World, side: Side, r: Robot) =
  when defined(bc25Scenario):
    runScenario25(w, side, r)
  else:
    r.scaffoldTurns += 1
    case r.kind
    of utSoldier: runScaffoldSoldier(w, side, r)
    of utMopper: runScaffoldMopper(w, side, r)
    of utSplasher: discard   ## `case SPLASHER: break;` upstream
    else: runScaffoldTower(w, side, r)
