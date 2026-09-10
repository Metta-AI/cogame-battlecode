## `farm.nim slots()` -- WHERE THE TREES GO, and it is a real geometry choice
## because in 2017 trees are also walls.
##
## * **`hex`**: up to SIX radius-1 trees packed around one gardener at spacing
##   `1 + 0.01 + 1`, the classic 2017 flower. Maximum trees per
##   gardener-turn of walking, and the gardener waters all six without moving
##   -- but ONE lumberjack `strike()` in the middle hits all six trees AND the
##   gardener.
## * **`line`**: a row along the own-archon -> enemy-archon axis at spacing
##   2.5, which turns the farm into a WALL across the approach and spreads the
##   strike damage, at the cost of a gardener that must walk to water.
## * **`ring`**: a circle of radius 4 centred on the archon leaving four
##   lanes -- the layout that keeps the archon's own spawn ring clear and lets
##   fighters through, and the only one that does not box a gardener in.
##
## A slot is a DIRECTION plus the gardener's own standing position, because
## `plantTree(dir)` spawns the tree at
## `bodyRadius + GENERAL_SPAWN_OFFSET + BULLET_TREE_RADIUS` = 2.01 units away:
## the gardener chooses where to stand and which way to face, never a
## coordinate.

import std/math
import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit, econ

export kit

func hexDirs*(away: Dir): seq[Dir] =
  ## **FIVE of the classic flower's six petals, and the sixth is left open on
  ## purpose.** Six radius-1 trees at spacing 2.01 around a radius-1 gardener
  ## close the ring completely: `canBuildRobot` then fails in every direction,
  ## the gardener's ten-turn slot can only ever plant, and the farm has built
  ## itself a present for the first lumberjack. So the petal pointing AT the
  ## enemy is kept clear as the build lane -- which is also the direction a
  ## new fighter wants to walk anyway.
  for i in 0 .. 4:
    let step = float32(i) * 60'f32
    result.add(if i mod 2 == 0: away.rotateLeftDegrees(step)
               else: away.rotateRightDegrees(step + 60'f32))

func lineDirs*(axis: Dir): seq[Dir] =
  ## Along the approach axis, both ways, then the two shoulders -- so a
  ## blocked line still plants rather than stalling.
  @[axis.rotateLeftDegrees(90'f32), axis.rotateRightDegrees(90'f32),
    axis, axis.opposite()]

func ringDirs*(outward: Dir): seq[Dir] =
  ## Outward from the archon, with the four 30-degree lanes left empty: the
  ## offsets are +-15 and +-45 degrees, never 0, 90, 180 or 270.
  @[outward.rotateLeftDegrees(15'f32), outward.rotateRightDegrees(15'f32),
    outward.rotateLeftDegrees(45'f32), outward.rotateRightDegrees(45'f32),
    outward.rotateLeftDegrees(105'f32), outward.rotateRightDegrees(105'f32)]

proc plantDirs*(w: World, s: Side, r: Robot): seq[Dir] =
  ## The layout's candidate directions for THIS gardener, in the order it
  ## should try them. Charged one credit per slot scored.
  let home = s.homeArchon(r.loc)
  let enemy = s.enemyBase(r.loc)
  let axis = (if r.loc == enemy: dirRads(0'f32)
              else: directionTo(r.loc, enemy))
  let away = axis.opposite()
  let outward = (if r.loc == home: axis else: directionTo(home, r.loc))
  case s.doctrine.farmLayout
  of fl17Hex: result = hexDirs(away)
  of fl17Line: result = lineDirs(axis)
  of fl17Ring: result = ringDirs(outward)
  discard r.chargeFor(result.len)

proc farmStand*(w: World, s: Side, r: Robot): Loc =
  ## Where this gardener wants to STAND, which is the whole of the layout's
  ## walking: `hex` sits four units behind its archon, `line` walks OUT along
  ## the approach axis by 2.5 units per tree it has planted, and `ring` sits
  ## on the circle of radius 4 around the archon.
  let home = s.homeArchon(r.loc)
  let enemy = s.enemyBase(home)
  let axis = (if home == enemy: dirRads(0'f32) else: directionTo(home, enemy))
  case s.doctrine.farmLayout
  of fl17Hex:
    ## Four units behind the archon, and one further out for every slot the
    ## flower has already used -- a hex farm that fills up walks on rather
    ## than standing in a ring of its own trees.
    addDist(home, axis.opposite().rotateLeftDegrees(
      float32((r.id mod 5) - 2) * 25'f32),
      4'f32 + float32(min(r.task, 6)) * 2'f32)
  of fl17Line:
    ## One gardener per lane: the id spreads them across the shoulders, and
    ## each walks further out with every tree it plants, which is what makes
    ## the line a line.
    let lane = float32((r.id mod 3) - 1) * 3'f32
    let steps = float32(min(r.task, 8)) * 2.5'f32
    addDist(addDist(home, axis.rotateLeftDegrees(90'f32), lane),
            axis, 6'f32 + steps)
  of fl17Ring:
    let spread = float32((r.id mod 6)) * 60'f32 +
      float32(min(r.task, 8)) * 12'f32
    addDist(home, axis.rotateLeftDegrees(spread), 4'f32)

proc tryPlant*(w: World, s: Side, r: Robot): bool {.discardable.} =
  ## Plant into the first clear slot of the layout, claiming it so no other
  ## gardener plants into the same circle.
  if r.kind != rtGardener or not r.isBuildReady(): return false
  when defined(bc17BrokenChassis):
    discard
  if not w.canSpend(s, bulletTreeCost, w.treeIsEssential(s)): return false
  for dir in w.plantDirs(s, r):
    if not w.canPlantTree(r, dir): continue
    let spawnLoc = addDist(r.loc, dir, r.spawnDistFor(bulletTreeRadius))
    if not s.claimSlot(spawnLoc, r.id): continue
    if w.plantTree(r, dir):
      s.commit(bulletTreeCost)
      inc r.task              ## how far along its line this gardener is
      return true
  ## **THE FLOOR BEATS THE LAYOUT.** On a board like `HouseDivided` -- 30x30,
  ## archons 6.5 apart, 41 neutral trees -- every slot of every layout can be
  ## blocked at once, and a gardener that plants nothing is the inert faction
  ## the anti-inert rule forbids. So when the layout has no room the gardener
  ## sweeps sixteen bearings and takes the first clear circle; the layout
  ## still SHAPES the farm wherever there is room for it to, which is what
  ## `tests/test_bc17_knobs.nim` measures.
  for step in 0 .. 15:
    if not r.chargeFor(1): return false
    let dir = dirRads(0'f32).rotateLeftDegrees(float32(step) * 22.5'f32)
    if not w.canPlantTree(r, dir): continue
    let spawnLoc = addDist(r.loc, dir, r.spawnDistFor(bulletTreeRadius))
    if not s.claimSlot(spawnLoc, r.id): continue
    if w.plantTree(r, dir):
      s.commit(bulletTreeCost)
      return true
  false

proc lowestOwnTreeInReach*(w: World, s: Side, r: Robot): int =
  ## The lowest-health own tree the gardener can water, which is the one
  ## watering keeps alive. Charged one credit per tree scored.
  result = -1
  var worst = 0'f32
  for id in w.senseTrees(r, bodyRadius(r.kind) + neutralTreeMaxRadius +
                            interactionDistFromEdge, ord(s.team)):
    let tr = w.trees.getOrDefault(id)
    if tr == nil or tr.team != s.team: continue
    if not r.canInteractWithTree(tr): continue
    if tr.health >= tr.maxHealth: continue
    if result < 0 or tr.health < worst:
      result = id
      worst = tr.health

proc tryWater*(w: World, s: Side, r: Robot): bool {.discardable.} =
  ## **Watering is the farm's whole survival**: a tree withers 0.5 a round for
  ## ever and a gardener returns +5 for one turn that costs no bullets and no
  ## cooldown. The broken-chassis control (`-d:bc17BrokenChassis`) is exactly
  ## this proc disabled, which is why it is the one the survival gate's
  ## negative control removes.
  when defined(bc17BrokenChassis):
    return false
  if r.kind != rtGardener or r.waterCount >= 1: return false
  let id = w.lowestOwnTreeInReach(s, r)
  if id < 0: return false
  w.water(r, id)
