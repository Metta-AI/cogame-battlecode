## §Tests item 6 -- the bullet trees, which are this year's whole economy.
##
## The 2017 spec and the 2017 engine disagree about trees more than about
## anything else, and every disagreement below is resolved IN FAVOUR OF THE
## ENGINE with a test that says so:
##
##   * a planted tree grows for EIGHTY-ONE rounds and pays NOTHING for all of
##     them (`roundsAlive <= 80`), then pays `health x (1/50)` computed
##     BEFORE its own decay;
##   * `healTree` clamps at `maxHealth` AFTER the add, so watering a 48-HP
##     tree wastes 3 of the 5;
##   * `damageTree` clamps a negative health to 0 and kills on an EXACT
##     `health == 0` compare;
##   * **only a CHOP releases anything.** A bullet, a strike, a body attack or
##     plain decay destroys the tree and its contents with it.

import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom, units, world, trees, maps,
                              actions]

proc board17(): (World, proc (dx, dy: float32): Loc) =
  ## `Alone` is 100x100 and EMPTY -- no neutral trees to collide with -- and
  ## its origin is not (0, 0), so every shard coordinate is relative to it.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  (w, proc (dx, dy: float32): Loc = loc(o.x + dx, o.y + dy))

# --- the 81-round growth, value by value ------------------------------------
block:
  let (w, at) = board17()
  let tr = w.spawnTree(tA, bulletTreeRadius, at(50, 50), 0, -1)
  checkEq("a planted tree is born at exactly 10.0", bits(tr.health),
    bits(10'f32))
  checkEq("with roundsAlive 0", tr.roundsAlive, 0)
  var income = 0'f32
  var sequence: seq[float32]
  for i in 0 .. 80:
    sequence.add(tr.health)
    income = income + w.updateTree(tr)
    tr.roundsAlive += 1
  checkEq("eighty-one growth turns were taken", sequence.len, 81)
  checkEq("the first value is 10.0", bits(sequence[0]), bits(10'f32))
  var stepFailures = 0
  for i in 1 .. 80:
    if bits(sequence[i]) != bits(sequence[i - 1] + 0.5'f32):
      inc stepFailures
  checkEq("every step is exactly +0.5", stepFailures, 0)
  checkEq("so the sequence ends at 50.0", bits(tr.health), bits(50'f32))
  checkEq("and the tree paid ZERO income throughout", bits(income),
    bits(0'f32))
  checkEq("roundsAlive is now 81", tr.roundsAlive, 81)
  ## The first paying turn.
  let first = w.updateTree(tr)
  var fullHealth = 50'f32
  var prodRate = bulletTreeBulletProductionRate
  checkEq("the first income is health x (1/50) = 1.0 at full health",
    bits(first), bits(fullHealth * prodRate))
  checkEq("and the income is computed BEFORE the decay", bits(tr.health),
    bits(50'f32 - bulletTreeDecayRate))
  let second = w.updateTree(tr)
  check("so the second income is smaller", second < first)
  var afterOneDecay = 50'f32 - bulletTreeDecayRate
  var rate = bulletTreeBulletProductionRate
  checkEq("by exactly the decay's worth", bits(second),
    bits(afterOneDecay * rate))

# --- growth stops at maxHealth ---------------------------------------------
block:
  let (w, at) = board17()
  let tr = w.spawnTree(tA, bulletTreeRadius, at(30, 30), 0, -1)
  tr.health = 49.75'f32
  tr.growTree()
  checkEq("growth CLAMPS at maxHealth", bits(tr.health), bits(50'f32))
  tr.growTree()
  checkEq("and stays there", bits(tr.health), bits(50'f32))

# --- watering ---------------------------------------------------------------
block:
  let (w, at) = board17()
  let tr = w.spawnTree(tA, bulletTreeRadius, at(30, 30), 0, -1)
  tr.health = 40'f32
  tr.waterTree()
  checkEq("watering adds exactly 5", bits(tr.health), bits(45'f32))
  tr.health = 48'f32
  tr.waterTree()
  checkEq("watering a 48-HP tree CLAMPS at 50, wasting 3 of the 5",
    bits(tr.health), bits(50'f32))
  ## The waste is the point: a chassis that waters a nearly-full tree has
  ## spent its turn for 2 HP.
  checkEq("WATER_HEALTH_REGEN_RATE is 5", bits(waterHealthRegenRate),
    bits(5'f32))

# --- neutral trees ----------------------------------------------------------
block:
  let (w, at) = board17()
  let tr = w.spawnTree(tNeutral, 2.5'f32, at(60, 60), 7, -1)
  checkEq("a neutral tree's health is 200 x radius", bits(tr.health),
    bits(neutralTreeHealthRate * 2.5'f32))
  checkEq("and its maxHealth is the same", bits(tr.maxHealth),
    bits(tr.health))
  let before = tr.health
  for i in 0 ..< 5:
    checkEq("a neutral tree pays no income", bits(w.updateTree(tr)),
      bits(0'f32))
  checkEq("and NEVER decays", bits(tr.health), bits(before))
  checkEq("it does not grow either", tr.roundsAlive, 0)
  ## It cannot be watered: `canInteractWithTree` is not the gate here --
  ## `water` refuses a tree that is not the caller's own team.
  let gardener = w.spawnRobot(rtGardener, at(60, 57), tA)
  gardener.roundsAlive = 1
  check("and a gardener may not water it",
    not w.water(gardener, tr.id))
  checkEq("so its health is untouched", bits(tr.health), bits(before))

# --- damageTree's exact-zero kill -------------------------------------------
block:
  let (w, at) = board17()
  let tr = w.spawnTree(tA, bulletTreeRadius, at(30, 30), 0, -1)
  tr.health = 10'f32
  w.damageTree(tr, 3'f32, tB, false, "bullet")
  checkEq("damage subtracts in float32", bits(tr.health), bits(7'f32))
  check("and the tree lives", tr.alive)
  w.damageTree(tr, 100'f32, tB, false, "bullet")
  check("overkill clamps to 0 and kills", not tr.alive)
  checkEq("the tree is gone from the world", w.trees.hasKey(tr.id), false)
  checkEq("and from the count", w.treesAlive(tA), 0)
  ## An EXACT zero, reached without overshoot.
  let two = w.spawnTree(tA, bulletTreeRadius, at(35, 35), 0, -1)
  two.health = 5'f32
  w.damageTree(two, 5'f32, tB, false, "bullet")
  check("an exact zero kills too", not two.alive)

# --- destroyTree's fromChop gate --------------------------------------------
block:
  ## FOUR ways to kill a tree that release NOTHING, and one that releases
  ## everything.
  for (cause, fromChop) in [("bullet", false), ("strike", false),
                            ("body", false), ("decay", false)]:
    let (w, at) = board17()
    let tr = w.spawnTree(tNeutral, 1'f32, at(50, 50), 11, ord(rtTank))
    let supplyBefore = w.bulletSupplyOf(tB)
    let robotsBefore = w.robotsAlive(tB)
    w.destroyTree(tr.id, tB, fromChop, cause)
    checkEq("a " & cause & " releases NO bullets",
      bits(w.bulletSupplyOf(tB)), bits(supplyBefore))
    checkEq("and NO contained robot", w.robotsAlive(tB), robotsBefore)
  let (w, at) = board17()
  let tr = w.spawnTree(tNeutral, 1'f32, at(50, 50), 11, ord(rtTank))
  let supplyBefore = w.bulletSupplyOf(tB)
  let robotsBefore = w.robotsAlive(tB)
  w.destroyTree(tr.id, tB, true, "chop")
  checkEq("a CHOP releases the bullets", bits(w.bulletSupplyOf(tB)),
    bits(supplyBefore + 11'f32))
  checkEq("and the contained robot, on the CHOPPING team",
    w.robotsAlive(tB), robotsBefore + 1)
  checkEq("counted as shaken bullets", bits(w.stats.bulletsShaken[ord(tB)]),
    bits(11'f32))
  checkEq("and as a released robot", w.stats.robotsReleasedFromTrees[ord(tB)],
    1)

# --- the chop kills an overlapping SCOUT, and only a SCOUT ------------------
block:
  let (w, at) = board17()
  let tr = w.spawnTree(tNeutral, 1'f32, at(50, 50), 0, ord(rtTank))
  ## A SCOUT standing on the tree -- legal in 2017, and the only body type
  ## that can be there.
  let scout = w.spawnRobot(rtScout, at(50, 50), tA)
  let bystander = w.spawnRobot(rtSoldier, at(56, 50), tA)
  w.destroyTree(tr.id, tB, true, "chop")
  check("the overlapping SCOUT was killed by the release",
    not w.robots.hasKey(scout.id))
  check("the bystander outside the spawn circle was not",
    w.robots.hasKey(bystander.id))
  check("and the TANK was released", w.unitCount(tB, rtTank) == 1)

# --- a chop with nothing inside ---------------------------------------------
block:
  let (w, at) = board17()
  let tr = w.spawnTree(tNeutral, 1'f32, at(50, 50), 0, -1)
  let robotsBefore = w.robotsAlive(tB)
  w.destroyTree(tr.id, tB, true, "chop")
  checkEq("chopping an empty tree releases nothing", w.robotsAlive(tB),
    robotsBefore)
  checkEq("and it still counts as felled",
    w.stats.neutralTreesFelled[ord(tB)], 1)

# --- decay can kill, releasing nothing --------------------------------------
block:
  let (w, at) = board17()
  let tr = w.spawnTree(tA, bulletTreeRadius, at(50, 50), 0, -1)
  tr.health = bulletTreeDecayRate
  tr.roundsAlive = TreeGrowthRounds + 1
  let income = w.updateTree(tr)
  check("the tree paid its last income before dying", income > 0'f32)
  check("and then decayed to death", not tr.alive)
  checkEq("with the loss booked against its own team",
    w.stats.treesLost[ord(tA)], 1)

# --- updateTrees credits both teams in A-then-B order -----------------------
block:
  let (w, at) = board17()
  for i in 0 ..< 4:
    let a = w.spawnTree(tA, bulletTreeRadius, at(float32(20 + i * 4), 20),
                        0, -1)
    a.roundsAlive = TreeGrowthRounds + 1
    a.health = 50'f32
    let b = w.spawnTree(tB, bulletTreeRadius, at(float32(20 + i * 4), 60),
                        0, -1)
    b.roundsAlive = TreeGrowthRounds + 1
    b.health = 50'f32
  let beforeA = w.bulletSupplyOf(tA)
  let beforeB = w.bulletSupplyOf(tB)
  w.updateTrees()
  checkEq("four full trees pay A exactly 4.0",
    bits(w.bulletSupplyOf(tA) - beforeA), bits(4'f32))
  checkEq("and B exactly the same", bits(w.bulletSupplyOf(tB) - beforeB),
    bits(4'f32))
  checkEq("the income is booked in the stats",
    bits(w.stats.bulletsFromTrees[ord(tA)]), bits(4'f32))
  checkEq("every tree decayed once", w.trees.len, 8)
  var wrong = 0
  for id, tr in w.trees:
    if bits(tr.health) != bits(49.5'f32): inc wrong
  checkEq("to exactly 49.5", wrong, 0)

# --- the tree count is a PLAIN COUNTER --------------------------------------
block:
  ## `getTreeCount` has no notion of "active", so a 10-HP sapling counts as
  ## much as a mature tree -- which is exactly what tiebreak rung 2 reads.
  let (w, at) = board17()
  let sapling = w.spawnTree(tA, bulletTreeRadius, at(20, 20), 0, -1)
  let mature = w.spawnTree(tA, bulletTreeRadius, at(30, 20), 0, -1)
  mature.health = 50'f32
  mature.roundsAlive = 200
  checkEq("both count", w.treesAlive(tA), 2)
  checkEq("but only one is MATURE", w.matureTrees(tA), 1)
  check("and the sapling is the young one", sapling.roundsAlive == 0)

finish("test_bc17_trees")
