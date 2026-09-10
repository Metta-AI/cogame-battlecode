## §Tests item 7 -- the twelve actions of rule 6, with their guards in the
## ENGINE'S OWN ORDER.
##
## The order matters as much as the guards: `incrementMoveCount()` lands
## BEFORE the tank's body-attack branch, so a tank that body-attacks has
## spent its move even though it did not move; `chop` counts as the attack;
## `donate` deducts the WHOLE amount including the destroyed remainder and
## then checks for the win immediately.

import std/[math, algorithm]
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom, units, world, trees, actions,
                              maps]

proc empty17(): (World, proc (dx, dy: float32): Loc) =
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  (w, proc (dx, dy: float32): Loc = loc(o.x + dx, o.y + dy))

proc ready(r: Robot): Robot =
  ## Out of dormancy and off cooldown, which is the state every action test
  ## wants to start from.
  r.roundsAlive = DormancyRounds + 1
  r.buildCooldownTurns = 0
  r.health = maxHealthF(r.kind)
  r

# --- one move and one attack a turn, in EITHER order ------------------------
block:
  let (w, at) = empty17()
  let s = w.spawnRobot(rtSoldier, at(50, 50), tA).ready()
  check("a fresh turn has neither", not s.hasMoved() and not s.hasAttacked())
  check("the move is accepted", w.move(s, dirRads(0)))
  check("a second move is refused", not w.move(s, dirRads(0)))
  check("but the attack still is not", w.fireShot(s, ssSingle, dirRads(0)))
  check("and a second attack is refused",
    not w.fireShot(s, ssSingle, dirRads(0)))
  ## The other order.
  let (v, at2) = empty17()
  let t = v.spawnRobot(rtSoldier, at2(50, 50), tA).ready()
  check("attacking first is fine", v.fireShot(t, ssSingle, dirRads(0)))
  check("and the move still works after it", v.move(t, dirRads(0)))

# --- the over-stride RE-PROJECTION -----------------------------------------
block:
  ## A target further than one stride is not clamped along the segment: the
  ## robot goes `strideRadius` along `directionTo(target)`, an atan2 + sin/cos
  ## round trip, so the landing point is NOT exactly on the line.
  let (w, at) = empty17()
  let s = w.spawnRobot(rtSoldier, at(50, 50), tA).ready()
  let start = s.loc
  let far = at(90, 90)
  let projected = s.projectMove(far)
  checkEq("the projection is exactly one stride away",
    bits(distanceTo(start, projected)),
    bits(distanceTo(start, addDist(start, directionTo(start, far),
                                   strideRadius(rtSoldier)))))
  ## And it is NOT a vector scale: over a fan of targets the atan2 round
  ## trip lands on different float32 bits from the algebraic shortcut.
  var scaleDiffers = 0
  for i in 0 ..< 200:
    let target = at(50'f32 + float32(i mod 20) * 1.7'f32,
                    50'f32 + float32(i div 20) * 2.3'f32 + 3'f32)
    let d = distanceTo(start, target)
    if d <= strideRadius(rtSoldier): continue
    let p = s.projectMove(target)
    let scaledX = start.x + (target.x - start.x) * strideRadius(rtSoldier) / d
    let scaledY = start.y + (target.y - start.y) * strideRadius(rtSoldier) / d
    if bits(p.x) != bits(scaledX) or bits(p.y) != bits(scaledY):
      inc scaleDiffers
  check("and it is NOT a vector scale of the offset (" & $scaleDiffers &
    " of the fan disagree)", scaleDiffers > 0)
  check("a target INSIDE one stride is passed through unchanged",
    s.projectMove(at(50.2, 50)) == at(50.2, 50))
  discard w.moveTo(s, far)
  checkEq("moving to a far target lands on the projection", s.loc, projected)

# --- the TANK/SCOUT emptiness split -----------------------------------------
block:
  ## One world per body type, because a robot standing next to the tree
  ## would itself block the destination.
  for (kind, allowed) in [(rtScout, true), (rtSoldier, false),
                          (rtLumberjack, false), (rtTank, true)]:
    let (w, at) = empty17()
    discard w.spawnTree(tNeutral, 1'f32, at(51, 50), 0, -1)
    let r = w.spawnRobot(kind, at(51'f32 - strideRadius(kind) * 0.9'f32,
                                  50), tA).ready()
    let target = at(51, 50)
    check("the target is within one stride for a " & $kind,
      distanceTo(r.loc, target) <= strideRadius(kind))
    checkEq("a " & $kind & " ending its move ON a tree is " &
      (if allowed: "allowed" else: "refused"),
      w.canMoveTo(r, target), allowed)

# --- incrementMoveCount lands BEFORE the tank branch ------------------------
block:
  ## A tank whose destination overlaps a tree body-attacks it, and if the
  ## tree survives the tank does NOT move -- but its move is already spent.
  let (w, at) = empty17()
  let tr = w.spawnTree(tNeutral, 2'f32, at(51, 50), 0, -1)
  let tank = w.spawnRobot(rtTank, at(48, 50), tA).ready()
  let where = tank.loc
  let hp = tr.health
  check("the move is accepted", w.moveTo(tank, at(50.2, 50)))
  checkEq("the tree took the body attack's 4 damage", bits(tr.health),
    bits(hp - tankBodyDamage))
  checkEq("but the tank did NOT move", tank.loc, where)
  check("and its move is spent all the same", tank.hasMoved())
  check("so a second move is refused", not w.moveTo(tank, at(48, 52)))
  checkEq("the body attack is counted", w.stats.bodyAttacks[ord(tA)], 1)

# --- the shot gates ----------------------------------------------------------
block:
  let (w, at) = empty17()
  for kind in [rtArchon, rtGardener, rtLumberjack]:
    let r = w.spawnRobot(kind, at(float32(20 + ord(kind) * 6), 20),
                         tA).ready()
    for shape in ShotShape:
      check($kind & " may not fire a " & $shape,
        not w.canFireShot(r, shape))
  let scout = w.spawnRobot(rtScout, at(60, 20), tA).ready()
  check("a SCOUT may fire a single", w.canFireShot(scout, ssSingle))
  check("but not a triad", not w.canFireShot(scout, ssTriad))
  check("nor a pentad", not w.canFireShot(scout, ssPentad))
  let tank = w.spawnRobot(rtTank, at(70, 20), tA).ready()
  for shape in ShotShape:
    check("a TANK may fire a " & $shape, w.canFireShot(tank, shape))
  ## Funds.
  w.bulletSupply[ord(tA)] = 5'f32
  check("with 5 bullets a triad is affordable", w.canFireShot(tank, ssTriad))
  check("but a pentad is not", not w.canFireShot(tank, ssPentad))
  w.bulletSupply[ord(tA)] = 6'f32
  check("at exactly 6 the pentad is affordable -- the test is >=",
    w.canFireShot(tank, ssPentad))

# --- the CENTRE-LEFT-RIGHT spawn order and the bullet id sequence -----------
block:
  let (w, at) = empty17()
  let tank = w.spawnRobot(rtTank, at(50, 50), tA).ready()
  let before = w.bullets.len
  check("the pentad fires", w.fireShot(tank, ssPentad, dirRads(0)))
  checkEq("five bullets entered the world", w.bullets.len, before + 5)
  checkEq("and six bullets were debited", bits(w.bulletSupplyOf(tA)),
    bits(300'f32 - pentadShotCost))
  ## The five directions, recovered from the live bullets in id order --
  ## which is the order they were spawned in, because the generator hands
  ## them out in sequence.
  var byId: seq[(int, float32)]
  for id, b in w.bullets: byId.add((id, b.dir.radians))
  ## Ids are shuffled, so recover the spawn order from the EXEC ORDER: each
  ## bullet is inserted at indexOf(parent), so they sit in spawn order just
  ## before the tank.
  var spawnOrder: seq[float32]
  for id in w.execOrder:
    if w.bullets.hasKey(id): spawnOrder.add(w.bullets[id].dir.radians)
  checkEq("five bullets sit in the exec order", spawnOrder.len, 5)
  let centre = dirRads(0)
  checkEq("the CENTRE bullet is first", bits(spawnOrder[0]),
    bits(centre.radians))
  checkEq("then the first LEFT at +15 degrees", bits(spawnOrder[1]),
    bits(centre.rotateLeftDegrees(pentadSpreadDegrees).radians))
  checkEq("then the first RIGHT at -15", bits(spawnOrder[2]),
    bits(centre.rotateRightDegrees(pentadSpreadDegrees).radians))
  checkEq("then the second LEFT at +30", bits(spawnOrder[3]),
    bits(centre.rotateLeftDegrees(2'f32 * pentadSpreadDegrees).radians))
  checkEq("then the second RIGHT at -30", bits(spawnOrder[4]),
    bits(centre.rotateRightDegrees(2'f32 * pentadSpreadDegrees).radians))
  ## The muzzle offset.
  var muzzle = 0'f32
  for id in w.execOrder:
    if w.bullets.hasKey(id):
      muzzle = distanceTo(w.bullets[id].loc, tank.loc)
      break
  ## `addDist` then `distanceTo` is an atan2/sin/cos round trip, so the
  ## measured distance is the offset to within the float32 grid rather than
  ## bit-identical to it.
  check("and it is spawned at bodyRadius + BULLET_SPAWN_OFFSET",
    abs(muzzle - (bodyRadius(rtTank) + bulletSpawnOffset)) < 1e-5'f32)

# --- strike hits own robots and own trees -----------------------------------
block:
  let (w, at) = empty17()
  let lj = w.spawnRobot(rtLumberjack, at(50, 50), tA).ready()
  let friend = w.spawnRobot(rtSoldier, at(51, 50), tA).ready()
  let foe = w.spawnRobot(rtSoldier, at(49, 50), tB).ready()
  let ownTree = w.spawnTree(tA, 1'f32, at(50, 51.5), 0, -1)
  let outside = w.spawnRobot(rtSoldier, at(56, 50), tA).ready()
  let fHp = friend.health
  let eHp = foe.health
  let tHp = ownTree.health
  let oHp = outside.health
  check("the strike lands", w.strike(lj))
  check("the enemy took 2", foe.health == eHp - attackPower(rtLumberjack))
  check("SO DID THE FRIEND -- there is no team check",
    friend.health == fHp - attackPower(rtLumberjack))
  check("and so did its OWN tree",
    ownTree.health == tHp - attackPower(rtLumberjack))
  checkEq("the body outside the radius was untouched", bits(outside.health),
    bits(oHp))
  check("the lumberjack did not hit ITSELF",
    lj.health == maxHealthF(rtLumberjack))
  check("a second strike in the same turn is refused", not w.strike(lj))
  let (v, at2) = empty17()
  let notALumberjack = v.spawnRobot(rtSoldier, at2(50, 50), tA).ready()
  check("and only a LUMBERJACK may strike", not v.strike(notALumberjack))

# --- chop / shake / water at the interaction distance ------------------------
block:
  let (w, at) = empty17()
  let lj = w.spawnRobot(rtLumberjack, at(50, 50), tA).ready()
  ## `bodyRadius + treeRadius + 1` == 1 + 1 + 1 == 3.
  let far = w.spawnTree(tNeutral, 1'f32, at(53, 50), 5, -1)
  checkEq("the interaction reach is bodyRadius + radius + 1",
    bits(distanceTo(lj.loc, far.loc)),
    bits(bodyRadius(rtLumberjack) + far.radius + interactionDistFromEdge))
  check("a tree at exactly that distance is reachable",
    lj.canInteractWithTree(far))
  let beyond = w.spawnTree(tNeutral, 1'f32, at(53.01, 60), 0, -1)
  let ljTwo = w.spawnRobot(rtLumberjack, at(50, 60), tA).ready()
  check("and one a hundredth beyond is not",
    not ljTwo.canInteractWithTree(beyond))
  ## The chop.
  let hp = far.health
  check("the chop lands", w.chop(lj, far.id))
  checkEq("for LUMBERJACK_CHOP_DAMAGE", bits(far.health),
    bits(hp - lumberjackChopDamage))
  check("and it COUNTS AS THE ATTACK", lj.hasAttacked())
  check("so a strike afterwards is refused", not w.strike(lj))

# --- shake is ANY robot, once a turn ----------------------------------------
block:
  let (w, at) = empty17()
  let tr = w.spawnTree(tNeutral, 1'f32, at(52, 50), 9, -1)
  let scout = w.spawnRobot(rtScout, at(50, 50), tA).ready()
  let before = w.bulletSupplyOf(tA)
  check("a SCOUT may shake", w.shake(scout, tr.id))
  checkEq("and gets every bullet inside", bits(w.bulletSupplyOf(tA)),
    bits(before + 9'f32))
  checkEq("the tree is emptied", tr.containedBullets, 0)
  check("a second shake in the same turn is refused",
    not w.shake(scout, tr.id))
  let archon = w.spawnRobot(rtArchon, at(48, 50), tA).ready()
  check("an ARCHON may shake too -- it is any robot",
    w.shake(archon, tr.id))
  checkEq("though there is nothing left to take", bits(w.bulletSupplyOf(tA)),
    bits(before + 9'f32))

# --- water is a GARDENER, once a turn, never on a neutral tree --------------
block:
  let (w, at) = empty17()
  let g = w.spawnRobot(rtGardener, at(50, 50), tA).ready()
  let mine = w.spawnTree(tA, 1'f32, at(52, 50), 0, -1)
  let theirs = w.spawnTree(tB, 1'f32, at(48, 50), 0, -1)
  let wild = w.spawnTree(tNeutral, 1'f32, at(50, 52), 0, -1)
  let wildHp = wild.health
  check("a gardener may not water a NEUTRAL tree", not w.water(g, wild.id))
  checkEq("its health is untouched", bits(wild.health), bits(wildHp))
  check("but it MAY water the enemy's -- assertOwnedTree only rejects " &
    "NEUTRAL", w.water(g, theirs.id))
  check("and a second water in the same turn is refused",
    not w.water(g, mine.id))
  let two = w.spawnRobot(rtGardener, at(54, 50), tA).ready()
  let hp = mine.health
  check("another gardener may water it", w.water(two, mine.id))
  checkEq("for exactly +5", bits(mine.health), bits(hp + waterHealthRegenRate))
  let s = w.spawnRobot(rtSoldier, at(50, 48), tA).ready()
  check("a SOLDIER may not water at all", not w.water(s, mine.id))

# --- the spawn circles and the SHARED cooldown ------------------------------
block:
  let (w, at) = empty17()
  let g = w.spawnRobot(rtGardener, at(50, 50), tA).ready()
  checkEq("the spawn distance is bodyRadius + 0.01 + the new radius",
    bits(g.spawnDistFor(bulletTreeRadius)),
    bits(bodyRadius(rtGardener) + generalSpawnOffset + bulletTreeRadius))
  check("planting is possible", w.canPlantTree(g, dirRads(0)))
  check("and so is building a soldier",
    w.canBuildRobot(g, rtSoldier, dirRads(FloatPi)))
  check("the plant lands", w.plantTree(g, dirRads(0)))
  checkEq("the cooldown is the tree construction cooldown",
    g.buildCooldownTurns, bulletTreeConstructionCooldown)
  check("and it BLOCKS a build in the same breath -- one shared slot",
    not w.canBuildRobot(g, rtSoldier, dirRads(FloatPi)))
  check("and blocks another plant", not w.canPlantTree(g,
    dirRads(float32(PI / 2.0))))
  g.buildCooldownTurns = 0
  check("once it expires, building works again",
    w.canBuildRobot(g, rtSoldier, dirRads(FloatPi)))
  check("the build lands", w.buildRobot(g, rtSoldier, dirRads(FloatPi)))
  checkEq("and burns a ten-turn cooldown", g.buildCooldownTurns,
    buildCooldownTurns(rtSoldier))

# --- who may build what ------------------------------------------------------
block:
  let (w, at) = empty17()
  let archon = w.spawnRobot(rtArchon, at(50, 50), tA).ready()
  check("an ARCHON hires a GARDENER",
    w.canBuildRobot(archon, rtGardener, dirRads(0)))
  for kind in [rtSoldier, rtTank, rtScout, rtLumberjack, rtArchon]:
    check("but not a " & $kind, not w.canBuildRobot(archon, kind, dirRads(0)))
  let g = w.spawnRobot(rtGardener, at(60, 50), tA).ready()
  for kind in [rtSoldier, rtTank, rtScout, rtLumberjack]:
    check("a GARDENER builds a " & $kind,
      w.canBuildRobot(g, kind, dirRads(0)))
  check("but never a GARDENER", not w.canBuildRobot(g, rtGardener,
    dirRads(0)))
  check("and never an ARCHON", not w.canBuildRobot(g, rtArchon, dirRads(0)))

# --- broadcast bounds --------------------------------------------------------
block:
  let (w, at) = empty17()
  let r = w.spawnRobot(rtScout, at(50, 50), tA).ready()
  check("channel 0 is legal", w.broadcast(r, 0, 42))
  check("channel 9999 is legal", w.broadcast(r, 9999, 7))
  check("channel -1 is refused", not w.broadcast(r, -1, 1))
  check("channel 10000 is refused", not w.broadcast(r, 10000, 1))
  checkEq("what was written can be read back", w.readBroadcast(r, 0), 42)
  checkEq("and the far channel too", w.readBroadcast(r, 9999), 7)
  checkEq("an out-of-range read is 0, not a throw",
    w.readBroadcast(r, 10000), 0)
  check("broadcasting is free and unlimited in a turn",
    w.broadcast(r, 5, 1) and w.broadcast(r, 6, 2) and w.broadcast(r, 7, 3))
  checkEq("and costs no bullets", bits(w.bulletSupplyOf(tA)), bits(300'f32))
  ## The enemy's array is separate.
  let foe = w.spawnRobot(rtScout, at(60, 50), tB).ready()
  checkEq("the other team reads its OWN array", w.readBroadcast(foe, 0), 0)

# --- donate's exact arithmetic ----------------------------------------------
block:
  let (w, at) = empty17()
  let r = w.spawnRobot(rtArchon, at(50, 50), tA).ready()
  w.currentRound = 1
  let price = w.victoryPointCost()
  var base = vpBaseCost
  var slope = vpIncreasePerRound
  checkEq("the price at round 1", bits(price), bits(base + slope * 1'f32))
  w.bulletSupply[ord(tA)] = 100'f32
  let want = int(floor(float64(100'f32 / price)))
  check("the donation lands", w.donate(r, 100'f32))
  checkEq("and converts floor(bullets / price)", w.victoryPoints[ord(tA)],
    want)
  checkEq("the WHOLE amount is deducted, remainder destroyed",
    bits(w.bulletSupplyOf(tA)), bits(0'f32))
  ## Negative and unaffordable.
  check("a negative donation is refused", not w.donate(r, -1'f32))
  check("and one it cannot afford is refused", not w.donate(r, 1'f32))
  ## The immediate win at 1000.
  let (v, at2) = empty17()
  let a = v.spawnRobot(rtArchon, at2(50, 50), tA).ready()
  v.currentRound = 1
  v.bulletSupply[ord(tA)] = 1000000'f32
  check("a huge donation lands", v.donate(a, 100000'f32))
  check("it crossed a thousand victory points",
    v.victoryPoints[ord(tA)] >= victoryPointsToWin)
  check("and the winner was set IMMEDIATELY, inside donate", v.hasWinner)
  checkEq("by the victory-point rung", v.domination, RungVictoryPoints)
  checkEq("for team A", v.winner, tA)

# --- disintegrate ------------------------------------------------------------
block:
  let (w, at) = empty17()
  let r = w.spawnRobot(rtSoldier, at(50, 50), tA).ready()
  let id = r.id
  w.disintegrate(r)
  check("the robot is gone", not w.robots.hasKey(id))
  check("and out of the exec order", w.execOrder.find(id) < 0)

# --- every refusal is counted -----------------------------------------------
block:
  let (w, at) = empty17()
  let g = w.spawnRobot(rtGardener, at(50, 50), tA).ready()
  checkEq("no refusals yet", w.stats.refusedActions[ord(tA)], 0)
  discard w.fireShot(g, ssSingle, dirRads(0))
  checkEq("a refused shot is counted", w.stats.refusedActions[ord(tA)], 1)
  g.buildCooldownTurns = 5
  discard w.plantTree(g, dirRads(0))
  checkEq("a refused build is counted twice over -- once as a build",
    w.stats.buildsRefused[ord(tA)], 1)
  checkEq("and once as an action", w.stats.refusedActions[ord(tA)], 2)

finish("test_bc17_actions")
