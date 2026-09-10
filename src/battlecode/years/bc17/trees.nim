## Trees: the whole of the 2017 economy, and the one phase whose ORDER is a
## rule.
##
## A port of `world/InternalTree.java` (209 lines) and
## `GameWorld.{updateTrees,destroyTree}` at commit `165d8a8e`.
##
## **FOUR THINGS THAT DECIDE GAMES:**
##
## * **`updateTree` pays income BEFORE it decays** and returns ZERO for its
##   first 81 turns: `roundsAlive <= 80` grows the tree by
##   `BULLET_TREE_MAX_HEALTH * 0.01f` (= exactly 0.5) and returns 0, so a
##   planted tree pays NOTHING until `roundsAlive == 81`. The 1.6.2 spec says
##   "the next 80 turns"; the engine's branch is `<= 80`, i.e. EIGHTY-ONE
##   turns, and the engine wins (docs/RULES-BC17.md, disagreement 5).
## * **The `totalTreeSupply` accumulation is a FLOAT32 SUM IN TROVE ORDER**
##   (`GameWorld.java:121-124`) and the spec's claim that "the ordering of this
##   phase is not important to the outcome of a match" IS FALSE: the sum lands
##   in the bullet supply that `donate`'s integer floor and every
##   affordability test read. `trove.nim` reproduces the order (D1).
## * **`destroyTree` releases goodies ONLY when `fromChop`.** A tree that dies
##   to a bullet, a lumberjack strike, a tank body attack or its own decay
##   releases NOTHING AT ALL -- not its bullets and not the robot inside it.
##   A chop spawns the contained robot on the CHOPPING team at the tree's
##   centre, and **any SCOUT overlapping that circle is killed first** (the
##   falling-debris rule, `GameWorld.java:410-418`).
## * **`healTree` clamps AFTER the add**, so watering a 48-HP tree wastes 3 of
##   the 5.

import ../../sim_types
import constants, units, geom, world

export world

proc noteTreeLoss(w: World, tr: Tree, hitBy: Team, cause: string) =
  if tr.team == tNeutral:
    if hitBy != tNeutral:
      w.stats.neutralTreesFelled[ord(hitBy)] += 1
    return
  let t = ord(tr.team)
  w.stats.treesLost[t] += 1
  if cause == "strike":
    w.stats.treesLostToStrike[t] += 1
  if hitBy != tNeutral and hitBy != tr.team:
    w.stats.enemyTreesFelled[ord(hitBy)] += 1
  w.treeLostBeats[t] += 1
  if w.treeLostBeats[t] <= 6 or (w.treeLostBeats[t] mod 4) == 0:
    discard w.beat(BeatTreeLost, "tree_lost", t,
                   int(tr.loc.x * 10) * 100000 + int(tr.loc.y * 10),
                   w.treesAlive(tr.team) - 1, cause)

proc destroyTree*(w: World, id: int, destroyedBy: Team, fromChop: bool,
                  cause = "bullet") =
  ## `GameWorld.destroyTree` (`:397-431`), in the engine's own order.
  if not w.trees.hasKey(id): return
  let tr = w.trees[id]
  if fromChop:
    let toSpawn = tr.containedRobot
    let containedBullets = tr.containedBullets
    if toSpawn >= 0 and destroyedBy != tNeutral:
      ## First, kill any SCOUT that would overlap the new robot -- and ONLY a
      ## scout: the engine's `else` branch is a commented-out exception
      ## ("seems like we only hit this on floating point errors"), so a
      ## non-scout overlap is silently allowed.
      let kind = RobotType(toSpawn)
      var doomed: seq[int]
      for c in w.robotIndex.withinRadius(tr.loc, bodyRadius(kind)):
        if w.robots.hasKey(int(c.id)) and
            w.robots[int(c.id)].kind == rtScout:
          doomed.add(int(c.id))
      for victim in doomed:
        w.destroyRobot(victim)
      discard w.spawnRobot(kind, tr.loc, destroyedBy)
      w.stats.robotsReleasedFromTrees[ord(destroyedBy)] += 1
      w.stats.unitsBuilt[ord(destroyedBy)] += 1
      w.chopRevealBeats[ord(destroyedBy)] += 1
      discard w.beat(BeatChopReveal, "chop_reveal", ord(destroyedBy),
                     int(tr.loc.x * 10) * 100000 + int(tr.loc.y * 10),
                     toSpawn, unitName(kind))
    if containedBullets > 0:
      w.adjustBulletSupply(destroyedBy, float32(containedBullets))
      w.stats.bulletsShaken[ord(destroyedBy)] =
        w.stats.bulletsShaken[ord(destroyedBy)] + float32(containedBullets)
  w.noteTreeLoss(tr, destroyedBy, cause)
  tr.alive = false
  w.treeCount[ord(tr.team)] -= 1
  w.trees.del(id)
  w.treeKeys.remove(id)
  w.treeIndex.remove(int32(id))

proc damageTree*(w: World, tr: Tree, damage: float32, hitBy: Team,
                 fromChop: bool, cause = "bullet") =
  ## `InternalTree.damageTree` (`:357-362`): `health -= damage`, clamp a
  ## NEGATIVE health to 0, then `killTreeIfDead` on an **exact `health == 0`
  ## compare**.
  if not tr.alive: return
  tr.health = tr.health - damage
  if tr.health < 0'f32:
    tr.health = 0'f32
  if hitBy != tNeutral:
    if tr.team == hitBy:
      w.stats.ownTreesDamaged[ord(hitBy)] =
        w.stats.ownTreesDamaged[ord(hitBy)] + damage
  if tr.health == 0'f32:
    w.destroyTree(tr.id, hitBy, fromChop, cause)

proc healTree*(tr: Tree, healAmount: float32) =
  ## `InternalTree.healTree`: the add, then `keepMaxHealth` -- **so watering a
  ## 48-HP tree wastes 3 of the 5.**
  tr.health = tr.health + healAmount
  if tr.health > tr.maxHealth:
    tr.health = tr.maxHealth

proc growTree*(tr: Tree) =
  ## `healTree(BULLET_TREE_MAX_HEALTH * 0.01f)` -- the product is float32 and
  ## is exactly 0.5, which `tests/test_bc17_arith.nim` asserts rather than
  ## assumes.
  tr.healTree(bulletTreeMaxHealth * 0.01'f32)

proc waterTree*(tr: Tree) =
  tr.healTree(waterHealthRegenRate)

proc decayTree*(w: World, tr: Tree) =
  ## `decayTree` = `damageTree(BULLET_TREE_DECAY_RATE, Team.NEUTRAL, false)`,
  ## which **can kill the tree, releasing nothing**.
  w.damageTree(tr, bulletTreeDecayRate, tNeutral, false, "decay")

proc updateTree*(w: World, tr: Tree): float32 =
  ## `InternalTree.updateTree` (`:390-402`), verbatim: NEUTRAL pays 0; a tree
  ## with `roundsAlive <= 80` grows and pays 0; otherwise the income is
  ## `health * BULLET_TREE_BULLET_PRODUCTION_RATE` computed BEFORE the decay.
  if tr.team == tNeutral:
    return 0'f32
  if tr.roundsAlive <= TreeGrowthRounds:
    tr.growTree()
    return 0'f32
  let bulletIncome = tr.health * bulletTreeBulletProductionRate
  w.decayTree(tr)
  bulletIncome

proc updateTrees*(w: World) =
  ## `GameWorld.updateTrees` (`:120-128`) -- **the float32 accumulation whose
  ## ORDER IS OBSERVABLE** (D1), then A's credit and then B's.
  ##
  ## A tree can DIE inside this pass (its own decay), and the engine's trove
  ## `forEachValue` simply never revisits it: a tree is only ever removed by
  ## its OWN visit here, so the walk sees every tree exactly once even when a
  ## third of them die in one round. That is a proof, not a hope, and
  ## `tests/test_bc17_trove.nim` asserts it.
  var totalTreeSupply: array[3, float32]
  for id in w.treeKeys.forEachValue:
    if not w.trees.hasKey(id): continue
    let tr = w.trees[id]
    totalTreeSupply[ord(tr.team)] =
      totalTreeSupply[ord(tr.team)] + w.updateTree(tr)
  w.adjustBulletSupply(tA, totalTreeSupply[ord(tA)])
  w.adjustBulletSupply(tB, totalTreeSupply[ord(tB)])
  for t in 0 .. 1:
    w.stats.bulletsFromTrees[t] =
      w.stats.bulletsFromTrees[t] + totalTreeSupply[t]
    ## The farm-online beats: the first round a side's tree income passes 10,
    ## 25 and 50 bullets a round. Derived from the sim, so it fires for ANY
    ## chassis.
    let income = totalTreeSupply[t]
    const marks = [10'f32, 25'f32, 50'f32]
    for m in 0 .. 2:
      if not w.farmOnlineSeen[t][m] and income >= marks[m]:
        w.farmOnlineSeen[t][m] = true
        discard w.beat(BeatFarmOnline, "farm_online", t,
                       w.matureTrees(Team(t)), int(income * 10'f32))
