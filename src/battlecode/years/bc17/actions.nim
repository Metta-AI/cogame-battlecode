## The twelve player actions of 2017, with their guards, their counters and
## their immediate effects -- in ONE file because the guard order and the
## `incrementXCount()` placement are the easiest thing in this year to get
## wrong.
##
## A port of `world/RobotControllerImpl.java` (1 246 lines) at commit
## `165d8a8e`. Every proc here is the engine's own method, in its own order,
## and **each action takes effect IMMEDIATELY, in the order the chassis emits
## it** -- there is no queued-orders phase in 2017.
##
## **THE FIVE PLACEMENTS THAT DECIDE GAMES:**
##
## * **`incrementMoveCount()` fires BEFORE the tank branch**, so a
##   body-attacking tank HAS SPENT ITS MOVE even when it does not move
##   (`:579-603`).
## * **An over-stride `move(center)` is RE-PROJECTED, not scaled**:
##   `location.add(location.directionTo(center), strideRadius)` -- an
##   atan2 + sin/cos round trip, so the destination is NOT on the segment.
## * **TANK and SCOUT use `noRobotsExceptForRobot` and everything else uses
##   `isEmptyExceptForRobot`** (`:545-549`): a scout may end its move on a
##   tree, a tank may try to and then body-attacks instead, and a soldier may
##   not.
## * **`fireBulletSpread` spawns CENTRE, then LEFT, then RIGHT per ring**
##   (`:639-673`), which fixes the bullet id sequence and therefore the
##   exec-order insertion.
## * **A GARDENER's ten-turn build cooldown is SHARED between planting a tree
##   and building a fighter**, so a farm and an army compete for the same slot.
##
## Every refusal is COUNTED (`refused_actions`, and `builds_refused` for the
## three build verbs) and returns `false`; nothing here raises. The engine
## throws `GameActionException` instead, and a thrown exception costs the
## robot 500 bytecodes and ends nothing -- so a counted refusal is the same
## behaviour minus the metering this port does not have (V1).

import std/math
import ../../sim_types
import ../../fdlibm
import constants, units, geom, world, trees, ballistics

export world, trees, ballistics

# ---------------------------------------------------------------------------
#  Sensing -- the raw queries. `chassis/kit.nim` wraps these with the
#  `DecisionOps` charging; the sim enforces the budget, not the bot.
# ---------------------------------------------------------------------------

func canSenseLocation*(r: Robot, l: Loc): bool =
  ## `InternalRobot.canSenseLocation`: a EUCLIDEAN DISTANCE against
  ## `sensorRadius`, not a squared one -- a 2017 change from every previous
  ## year.
  distanceTo(r.loc, l) <= sensorRadius(r.kind)

func canSenseBulletLocation*(r: Robot, l: Loc): bool =
  distanceTo(r.loc, l) <= bulletSightRadius(r.kind)

func canSensePartOfCircle*(r: Robot, center: Loc, radius: float32): bool =
  ## `canSenseRadius(getLocation().distanceTo(center) - radius)`.
  (distanceTo(r.loc, center) - radius) <= sensorRadius(r.kind)

func canSenseAllOfCircle*(r: Robot, center: Loc, radius: float32): bool =
  (distanceTo(r.loc, center) + radius) <= sensorRadius(r.kind)

proc senseNearbyRobots*(w: World, r: Robot, radius: float32,
                        team: int = -1): seq[int] =
  ## `senseNearbyRobots(center, radius, team)` (`:365-387`): the candidate
  ## array **IN ASCENDING DISTANCE** (D2 (iv) -- fully observable, and the
  ## reason the normalisation is an order and not merely a tie-break), minus
  ## the sensing robot itself, minus anything whose circle it cannot sense
  ## part of, minus the other team when one is named.
  let reach = (if radius < 0'f32: sensorRadius(r.kind) else: radius)
  for id in w.robotIndex.sortedCandidates(r.loc, reach):
    let other = w.robots.getOrDefault(int(id))
    if other == nil or other.id == r.id: continue
    if not r.canSensePartOfCircle(other.loc, bodyRadius(other.kind)): continue
    if team >= 0 and ord(other.team) != team: continue
    result.add(other.id)

proc senseNearbyTrees*(w: World, r: Robot, radius: float32,
                       team: int = -1): seq[int] =
  let reach = (if radius < 0'f32: sensorRadius(r.kind) else: radius)
  for id in w.treeIndex.sortedCandidates(r.loc, reach):
    let tr = w.trees.getOrDefault(int(id))
    if tr == nil: continue
    if not r.canSensePartOfCircle(tr.loc, tr.radius): continue
    if team >= 0 and ord(tr.team) != team: continue
    result.add(tr.id)

proc senseNearbyBullets*(w: World, r: Robot, radius: float32): seq[int] =
  ## `senseNearbyBullets` uses `getAllBulletsWithinRadius`, which applies NO
  ## body-radius term -- a bullet is a point.
  let reach = (if radius < 0'f32: bulletSightRadius(r.kind) else: radius)
  for id in w.bulletIndex.sortedCandidates(r.loc, reach, pointOnly = true):
    let b = w.bullets.getOrDefault(int(id))
    if b == nil: continue
    if not r.canSenseBulletLocation(b.loc): continue
    result.add(b.id)

proc senseBroadcastingRobotLocations*(w: World): seq[Loc] =
  ## `senseBroadcastingRobotLocations` (`:453-458`) -- **the same array for
  ## BOTH teams**, in the trove order `updateBroadcastData` captured (D1), so
  ## broadcasting reveals the broadcaster's position to the ENEMY too.
  for b in w.previousBroadcasters:
    result.add(b.loc)

func treeAtLocation*(w: World, l: Loc): int =
  int(w.treeIndex.firstContaining(l))

func robotAtLocation*(w: World, l: Loc): int =
  int(w.robotIndex.firstContaining(l))

# ---------------------------------------------------------------------------
#  Emptiness -- `ObjectInfo.isEmpty` / `isEmptyExceptForRobot` /
#  `noRobotsExceptForRobot`
# ---------------------------------------------------------------------------

func isEmpty*(w: World, l: Loc, radius: float32): bool =
  if w.treeIndex.countWithin(l, radius) != 0: return false
  w.robotIndex.countWithin(l, radius) == 0

func isEmptyExceptForRobot*(w: World, l: Loc, radius: float32,
                            r: Robot): bool =
  if w.treeIndex.countWithin(l, radius) != 0: return false
  var n = 0
  var only = -1
  for c in w.robotIndex.withinRadius(l, radius):
    inc n
    only = int(c.id)
    if n > 1: return false
  if n == 0: return true
  only == r.id

func noRobotsExceptForRobot*(w: World, l: Loc, radius: float32,
                             r: Robot): bool =
  var n = 0
  var only = -1
  for c in w.robotIndex.withinRadius(l, radius):
    inc n
    only = int(c.id)
    if n > 1: return false
  if n == 0: return true
  only == r.id

# ---------------------------------------------------------------------------
#  Book-keeping shared by every refusal
# ---------------------------------------------------------------------------

proc refuse(w: World, r: Robot): bool =
  w.stats.refusedActions[ord(r.team)] += 1
  false

proc noteAction(w: World, r: Robot, act: int, tgt = 0, x = 0'f32,
                y = 0'f32, arg = 0'f32) =
  ## TELEMETRY ONLY, for `tools/parity_trace_bc17.nim`'s `A` line and the
  ## `first_action` beat. No rule reads it.
  w.lastAction[r.id] = (act: act, tgt: tgt, x: x, y: y, arg: arg)
  let t = ord(r.team)
  if act != ActNothing and not w.firstActionSeen[t]:
    w.firstActionSeen[t] = true
    discard w.beat(BeatFirstAction, "first_action", t, act, w.currentRound)

func haveBulletCosts*(w: World, r: Robot, cost: float32): bool =
  w.bulletSupply[ord(r.team)] >= cost

func isBuildReady*(r: Robot): bool = r.buildCooldownTurns == 0

func hasMoved*(r: Robot): bool = r.moveCount > 0
func hasAttacked*(r: Robot): bool = r.attackCount > 0

# ---------------------------------------------------------------------------
#  Rule 6.1 -- movement
# ---------------------------------------------------------------------------

func projectMove*(r: Robot, center: Loc): Loc =
  ## The engine's over-stride RE-PROJECTION (`:572-576`), shared by `canMove`
  ## and `move` so the two can never disagree: if the target is further than
  ## one stride, the robot goes `strideRadius` along
  ## `location.directionTo(center)` -- an atan2 + sin/cos round trip, NOT a
  ## vector scale, so the result is not exactly on the segment.
  if distanceTo(r.loc, center) > strideRadius(r.kind):
    if r.loc == center: return center
    return addDist(r.loc, directionTo(r.loc, center), strideRadius(r.kind))
  center

proc canMoveTo*(w: World, r: Robot, centerIn: Loc): bool =
  ## `canMove(MapLocation)` (`:536-552`).
  let center = r.projectMove(centerIn)
  let empty =
    if r.kind != rtTank and r.kind != rtScout:
      w.isEmptyExceptForRobot(center, bodyRadius(r.kind), r)
    else:
      ## Tanks have a special condition because of the body attack; scouts
      ## can just go over trees.
      w.noRobotsExceptForRobot(center, bodyRadius(r.kind), r)
  w.rect.onTheMap(center, bodyRadius(r.kind)) and empty

proc canMove*(w: World, r: Robot, dir: Dir, dist: float32): bool =
  let d = max(0'f32, min(dist, strideRadius(r.kind)))
  w.canMoveTo(r, addDist(r.loc, dir, d))

proc canMove*(w: World, r: Robot, dir: Dir): bool =
  w.canMove(r, dir, strideRadius(r.kind))

proc moveTo*(w: World, r: Robot, centerIn: Loc): bool {.discardable.} =
  ## `move(MapLocation)` (`:568-607`).
  if r.hasMoved(): return w.refuse(r)
  let center = r.projectMove(centerIn)
  if not w.canMoveTo(r, center): return w.refuse(r)
  r.moveCount += 1
  w.stats.moves[ord(r.team)] += 1
  if r.kind == rtTank:
    ## **The body attack.** The trees overlapping the DESTINATION circle, and
    ## the victim is the one with the strictly smallest
    ## `tree.location.distanceTo(robot.getLocation())` -- the distance to the
    ## tank's CURRENT centre, not to `center`. Then a re-query: if anything
    ## still overlaps, the tank does not move at all.
    var victim = -1
    var bestDist = FloatMax
    var bestKeyD = 0'f32
    for c in w.treeIndex.withinRadius(center, bodyRadius(rtTank)):
      let td = distanceTo(c.loc, r.loc)
      let kd = distanceSquaredTo(c.loc, center)
      if victim < 0 or td < bestDist or
          (td == bestDist and (kd < bestKeyD or
            (kd == bestKeyD and int(c.id) < victim))):
        victim = int(c.id)
        bestDist = td
        bestKeyD = kd
    if victim >= 0:
      w.stats.bodyAttacks[ord(r.team)] += 1
      w.damageTree(w.trees[victim], tankBodyDamage, r.team, false,
                   "body_attack")
      w.noteAction(r, ActBodyAttack, victim, r.loc.x, r.loc.y,
                   tankBodyDamage)
      if w.treeIndex.countWithin(center, bodyRadius(rtTank)) > 0:
        return true
  w.setRobotLocation(r, center)
  w.noteAction(r, ActMove, 0, center.x, center.y)
  true

proc move*(w: World, r: Robot, dir: Dir, dist: float32): bool
    {.discardable.} =
  ## `move(Direction, float)` (`:559-566`): the distance is clamped into
  ## `[0, strideRadius]` FIRST, in float32.
  if r.hasMoved(): return w.refuse(r)
  let d = max(0'f32, min(dist, strideRadius(r.kind)))
  w.moveTo(r, addDist(r.loc, dir, d))

proc move*(w: World, r: Robot, dir: Dir): bool {.discardable.} =
  w.move(r, dir, strideRadius(r.kind))

# ---------------------------------------------------------------------------
#  Rule 6.2 -- shooting
# ---------------------------------------------------------------------------

proc fireBulletSpread(w: World, r: Robot, centerDir: Dir, toFire: int,
                      spreadDegrees: float32) =
  ## `fireBulletSpread` (`:639-673`): the CENTRE bullet, then for
  ## `i = 1 .. (toFire-1)/2` the LEFT at `rotateLeftDegrees(i * spread)` and
  ## then the RIGHT -- each spawned at
  ## `location.add(thatDir, bodyRadius + BULLET_SPAWN_OFFSET)`.
  let bulletsPerSide = (toFire - 1) div 2
  let offset = bodyRadius(r.kind) + bulletSpawnOffset
  discard w.spawnBullet(r.team, bulletSpeed(r.kind), attackPower(r.kind),
                        addDist(r.loc, centerDir, offset), centerDir, r.id)
  for i in 1 .. bulletsPerSide:
    let deg = float32(i) * spreadDegrees
    let dirLeft = centerDir.rotateLeftDegrees(deg)
    discard w.spawnBullet(r.team, bulletSpeed(r.kind), attackPower(r.kind),
                          addDist(r.loc, dirLeft, offset), dirLeft, r.id)
    let dirRight = centerDir.rotateRightDegrees(deg)
    discard w.spawnBullet(r.team, bulletSpeed(r.kind), attackPower(r.kind),
                          addDist(r.loc, dirRight, offset), dirRight, r.id)

proc canFireShot*(w: World, r: Robot, shape: ShotShape): bool =
  ## `canFireSingleShot`/`canFireTriadShot`/`canFirePentadShot`.
  canFire(r.kind, shape) and w.haveBulletCosts(r, shotCost(shape)) and
    not r.hasAttacked()

proc fireShot*(w: World, r: Robot, shape: ShotShape, dir: Dir): bool
    {.discardable.} =
  ## `fireSingleShot`/`fireTriadShot`/`firePentadShot` (`:730-776`): the
  ## weapon-ready assertion, the type-and-funds gate, then
  ## `incrementAttackCount()`, then the DEBIT, then the spread.
  if r.hasAttacked(): return w.refuse(r)
  if not w.canFireShot(r, shape): return w.refuse(r)
  r.attackCount += 1
  let t = ord(r.team)
  w.stats.attacks[t] += 1
  let cost = shotCost(shape)
  w.adjustBulletSupply(r.team, -cost)
  w.stats.bulletsSpentOnShots[t] = w.stats.bulletsSpentOnShots[t] + cost
  w.stats.bulletsFired[t] += shotCount(shape)
  w.firedThisRound[t] += shotCount(shape)
  w.lastShotShape[t] = shape
  case shape
  of ssSingle: w.stats.singleShots[t] += 1
  of ssTriad: w.stats.triadShots[t] += 1
  of ssPentad: w.stats.pentadShots[t] += 1
  w.fireBulletSpread(r, dir, shotCount(shape), shotSpreadDegrees(shape))
  w.noteAction(r, (case shape
                   of ssSingle: ActFireSingle
                   of ssTriad: ActFireTriad
                   of ssPentad: ActFirePentad), 0, r.loc.x, r.loc.y,
               dir.radians)
  true

proc strike*(w: World, r: Robot): bool {.discardable.} =
  ## `strike()` (`:682-707`): LUMBERJACK only, one attack a turn, then **2
  ## damage to every robot within `LUMBERJACK_STRIKE_RADIUS` of it except
  ## itself, and 2 damage to every tree within it -- WITH NO TEAM CHECK on
  ## either list.** Including its own gardeners and its own farm.
  ##
  ## The two candidate arrays are MATERIALISED before any damage lands,
  ## exactly as the engine materialises them, because damage can destroy a
  ## body and the destruction sequence is observable through
  ## `setWinnerIfDestruction`.
  if r.kind != rtLumberjack: return w.refuse(r)
  if r.hasAttacked(): return w.refuse(r)
  r.attackCount += 1
  let t = ord(r.team)
  w.stats.attacks[t] += 1
  w.stats.strikeActions[t] += 1
  let robotIds = w.robotIndex.sortedCandidates(r.loc, lumberjackStrikeRadius)
  let treeIds = w.treeIndex.sortedCandidates(r.loc, lumberjackStrikeRadius)
  var enemyHit = 0
  var friendlyHit = 0
  var treesHit = 0
  var ownTreesHit = 0
  for id in robotIds:
    let other = w.robots.getOrDefault(int(id))
    if other == nil or other.id == r.id: continue
    if other.team == r.team: inc friendlyHit else: inc enemyHit
    w.damageRobot(other, attackPower(r.kind), r.team)
  for id in treeIds:
    let tr = w.trees.getOrDefault(int(id))
    if tr == nil: continue
    inc treesHit
    if tr.team == r.team: inc ownTreesHit
    w.damageTree(tr, attackPower(r.kind), r.team, false, "strike")
  w.strikeBeats[t] += 1
  if w.strikeBeats[t] == 1 or (w.strikeBeats[t] mod 8) == 0:
    discard w.beat(BeatStrike, "strike", t, enemyHit * 1000 + friendlyHit,
                   treesHit * 1000 + ownTreesHit,
                   $int(r.loc.x) & "," & $int(r.loc.y))
  w.noteAction(r, ActStrike, 0, r.loc.x, r.loc.y)
  true

# ---------------------------------------------------------------------------
#  Rule 6.3 -- the three tree interactions
# ---------------------------------------------------------------------------

func canInteractWithTree*(r: Robot, tr: Tree): bool =
  ## `canInteractWithCircle(tree.location, tree.radius)` ==
  ## `distanceTo(center) <= bodyRadius + radius + INTERACTION_DIST_FROM_EDGE`.
  distanceTo(r.loc, tr.loc) <=
    bodyRadius(r.kind) + tr.radius + interactionDistFromEdge

proc chop*(w: World, r: Robot, treeId: int): bool {.discardable.} =
  ## `chop(int)` (`:858-878`): LUMBERJACK only, chopping COUNTS AS THE ATTACK,
  ## and `fromChop = TRUE` -- which is what releases the goodies (rule 7.3).
  if r.kind != rtLumberjack: return w.refuse(r)
  if r.hasAttacked(): return w.refuse(r)
  let tr = w.trees.getOrDefault(treeId)
  if tr == nil or not r.canInteractWithTree(tr): return w.refuse(r)
  r.attackCount += 1
  w.stats.attacks[ord(r.team)] += 1
  w.stats.chopActions[ord(r.team)] += 1
  w.damageTree(tr, lumberjackChopDamage, r.team, true, "chop")
  w.noteAction(r, ActChop, treeId, r.loc.x, r.loc.y, lumberjackChopDamage)
  true

proc shake*(w: World, r: Robot, treeId: int): bool {.discardable.} =
  ## `shake(int)` (`:899-913`): **ANY robot**, once a turn, on ANY tree
  ## including a bullet tree (which holds 0), and it hands over EVERY bullet
  ## inside.
  if r.shakeCount >= 1: return w.refuse(r)
  let tr = w.trees.getOrDefault(treeId)
  if tr == nil or not r.canInteractWithTree(tr): return w.refuse(r)
  r.shakeCount += 1
  let t = ord(r.team)
  w.stats.shakeActions[t] += 1
  let got = float32(tr.containedBullets)
  w.adjustBulletSupply(r.team, got)
  w.stats.bulletsShaken[t] = w.stats.bulletsShaken[t] + got
  tr.containedBullets = 0
  if got > 0'f32:
    w.shakeBeats[t] += 1
    if w.shakeBeats[t] == 1 or (w.shakeBeats[t] mod 8) == 0:
      discard w.beat(BeatShake, "shake", t, int(got * 10'f32),
                     int(tr.loc.x * 10) * 100000 + int(tr.loc.y * 10))
  w.noteAction(r, ActShake, treeId, r.loc.x, r.loc.y, got)
  true

proc water*(w: World, r: Robot, treeId: int): bool {.discardable.} =
  ## `water(int)` (`:940-947`): a GARDENER only, once a turn, **and a NEUTRAL
  ## tree is refused** (`assertOwnedTree`). The +5 is clamped at `maxHealth`
  ## AFTER the add.
  if r.kind != rtGardener: return w.refuse(r)
  if r.waterCount >= 1: return w.refuse(r)
  let tr = w.trees.getOrDefault(treeId)
  if tr == nil or not r.canInteractWithTree(tr): return w.refuse(r)
  if tr.team == tNeutral: return w.refuse(r)
  r.waterCount += 1
  w.stats.waterActions[ord(r.team)] += 1
  tr.waterTree()
  w.noteAction(r, ActWater, treeId, r.loc.x, r.loc.y, waterHealthRegenRate)
  true

# ---------------------------------------------------------------------------
#  Rule 6.4 -- the three build verbs
# ---------------------------------------------------------------------------

func spawnDistFor*(r: Robot, otherRadius: float32): float32 =
  ## `getType().bodyRadius + GENERAL_SPAWN_OFFSET + <the new body's radius>`.
  bodyRadius(r.kind) + generalSpawnOffset + otherRadius

proc canBuildRobot*(w: World, r: Robot, kind: RobotType, dir: Dir): bool =
  ## `canBuildRobot(type, dir)` (`:1073-1086`).
  if RobotSpecs[kind].spawnSource != ord(r.kind): return false
  if not w.haveBulletCosts(r, bulletCostF(kind)): return false
  if not r.isBuildReady(): return false
  let spawnLoc = addDist(r.loc, dir, r.spawnDistFor(bodyRadius(kind)))
  w.rect.onTheMap(spawnLoc, bodyRadius(kind)) and
    w.isEmpty(spawnLoc, bodyRadius(kind))

proc canPlantTree*(w: World, r: Robot, dir: Dir): bool =
  if r.kind != rtGardener: return false
  if not w.haveBulletCosts(r, bulletTreeCost): return false
  if not r.isBuildReady(): return false
  let spawnLoc = addDist(r.loc, dir, r.spawnDistFor(bulletTreeRadius))
  w.rect.onTheMap(spawnLoc, bulletTreeRadius) and
    w.isEmpty(spawnLoc, bulletTreeRadius)

proc refuseBuild(w: World, r: Robot): bool =
  w.stats.buildsRefused[ord(r.team)] += 1
  w.refuse(r)

proc buildRobot*(w: World, r: Robot, kind: RobotType, dir: Dir): bool
    {.discardable.} =
  ## `buildRobot(type, dir)` (`:1127-1144`) and `hireGardener(dir)`
  ## (`:1108-1125`), which is the same method with `GARDENER` hard-wired.
  ##
  ## **V3, the one guard the engine lacks:** a spawn that would issue an id
  ## above `MAX_ROBOT_ID` is refused rather than allowed to collide with the
  ## bullet id space. It covers `hire`, `build` AND `plant`, because all three
  ## draw from the SAME generator.
  if not w.canBuildRobot(r, kind, dir): return w.refuseBuild(r)
  if w.idPoolWouldOverrun(): return w.refuseBuild(r)
  r.buildCooldownTurns = buildCooldownTurns(kind)
  let t = ord(r.team)
  w.adjustBulletSupply(r.team, -bulletCostF(kind))
  w.stats.bulletsSpentOnUnits[t] =
    w.stats.bulletsSpentOnUnits[t] + bulletCostF(kind)
  let spawnLoc = addDist(r.loc, dir, r.spawnDistFor(bodyRadius(kind)))
  let built = w.spawnRobot(kind, spawnLoc, r.team)
  w.stats.unitsBuilt[t] += 1
  case kind
  of rtGardener: w.stats.gardenersBuilt[t] += 1
  of rtLumberjack:
    w.stats.lumberjacksBuilt[t] += 1
    if w.currentRound <= 600: w.stats.lumberjacksBuiltBy600[t] += 1
  of rtSoldier: w.stats.soldiersBuilt[t] += 1
  of rtTank:
    w.stats.tanksBuilt[t] += 1
    if w.currentRound <= 600: w.stats.tanksBuiltBy600[t] += 1
  of rtScout:
    w.stats.scoutsBuilt[t] += 1
    if w.currentRound <= 600: w.stats.scoutsBuiltBy600[t] += 1
  of rtArchon: discard
  if not w.unitMilestoneSeen[t][kind]:
    w.unitMilestoneSeen[t][kind] = true
    discard w.beat(BeatUnitMilestone, "unit_milestone", t, ord(kind),
                   w.unitCount(r.team, kind), unitName(kind))
  w.noteAction(r, (if kind == rtGardener: ActHire else: ActBuild),
               built.id, spawnLoc.x, spawnLoc.y, bulletCostF(kind))
  true

proc hireGardener*(w: World, r: Robot, dir: Dir): bool {.discardable.} =
  w.buildRobot(r, rtGardener, dir)

proc plantTree*(w: World, r: Robot, dir: Dir): bool {.discardable.} =
  ## `plantTree(dir)` (`:1146-1165`): the tree is born at
  ## `0.2 * 50 = 10` HP with `maxHealth = 50`, and the cooldown it burns is
  ## the SAME slot a fighter would have used.
  if not w.canPlantTree(r, dir): return w.refuseBuild(r)
  if w.idPoolWouldOverrun(): return w.refuseBuild(r)
  r.buildCooldownTurns = bulletTreeConstructionCooldown
  let t = ord(r.team)
  w.adjustBulletSupply(r.team, -bulletTreeCost)
  w.stats.bulletsSpentOnTrees[t] =
    w.stats.bulletsSpentOnTrees[t] + bulletTreeCost
  let spawnLoc = addDist(r.loc, dir, r.spawnDistFor(bulletTreeRadius))
  let tr = w.spawnTree(r.team, bulletTreeRadius, spawnLoc, 0, -1)
  w.stats.treesPlanted[t] += 1
  w.treeBeats[t] += 1
  if w.treeBeats[t] <= 6 or (w.treeBeats[t] mod 4) == 0:
    discard w.beat(BeatTreePlanted, "tree_planted", t,
                   int(spawnLoc.x * 10) * 100000 + int(spawnLoc.y * 10),
                   w.treesAlive(r.team))
  w.noteAction(r, ActPlant, tr.id, spawnLoc.x, spawnLoc.y, bulletTreeCost)
  true

# ---------------------------------------------------------------------------
#  Rule 6.5 -- broadcasting, donating and disintegrating
# ---------------------------------------------------------------------------

proc broadcast*(w: World, r: Robot, channel, data: int): bool
    {.discardable.} =
  ## `broadcast(channel, data)` (`:993-998`): **any robot, any number of times
  ## a turn, free of bullets** -- and it puts the broadcaster's position in
  ## front of BOTH teams next round (rule 2.2), which is the one place in this
  ## year where communicating costs information rather than bullets.
  if channel < 0 or channel >= broadcastMaxChannels: return w.refuse(r)
  w.addBroadcaster(r)
  w.broadcastArray[ord(r.team)][channel] = data
  w.stats.broadcasts[ord(r.team)] += 1
  w.noteAction(r, ActBroadcast, channel, r.loc.x, r.loc.y, float32(data))
  true

func readBroadcast*(w: World, r: Robot, channel: int): int =
  if channel < 0 or channel >= broadcastMaxChannels: return 0
  w.broadcastArray[ord(r.team)][channel]

proc donate*(w: World, r: Robot, bullets: float32): bool {.discardable.} =
  ## `donate(float)` (`:1176-1184`): `gained = (int) Math.floor(bullets /
  ## getVictoryPointCost())` -- **the price and the divide in float32, the
  ## floor on the widened double** -- then the WHOLE amount is deducted (the
  ## remainder is destroyed, the spec's "extra generosity") and
  ## `setWinnerIfVictoryPoints()` fires IMMEDIATELY.
  if bullets < 0'f32: return w.refuse(r)
  if not w.haveBulletCosts(r, bullets): return w.refuse(r)
  let price = w.victoryPointCost()
  let gained = int(floor(float64(bullets / price)))
  w.adjustBulletSupply(r.team, -bullets)
  w.adjustVictoryPoints(r.team, gained)
  let t = ord(r.team)
  w.stats.bulletsDonated[t] = w.stats.bulletsDonated[t] + bullets
  w.stats.donations[t] += 1
  let vp = w.victoryPoints[t]
  if w.stats.donations[t] == 1 or
      (vp div 100) > ((vp - gained) div 100):
    w.donationBeats[t] += 1
    discard w.beat(BeatDonation, "donation", t, int(bullets * 10'f32),
                   gained * 100000 + vp, $int(price * 10'f32))
  w.setWinnerIfVictoryPoints()
  w.noteAction(r, ActDonate, gained, r.loc.x, r.loc.y, bullets)
  true

proc disintegrate*(w: World, r: Robot) =
  ## `disintegrate()` throws `RobotDeathException`, which the engine turns
  ## into a `destroyRobot` at the end of `updateRobot` (rule 4.5).
  w.noteAction(r, ActDisintegrate)
  w.destroyRobot(r.id)
