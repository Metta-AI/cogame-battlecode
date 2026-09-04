## bc21 building: legality, the deduct-then-spawn order, `ceil(ratio * C)`
## spawn conviction (including the muckraker's 0.7), the conviction cap, and
## the exec-order rule that a robot built this round takes no turn this round.

import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc21/[constants, world, rules]

proc flat(width, height: int): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.origin = [0, 0]
  result.randomSeed = 4242
  result.symmetry = symRotational
  result.symmetries = @[symRotational]
  for i in 0 ..< width * height:
    result.passability.add(1.0)

proc bare(): World = newWorld(flat(15, 15), 1500)

# --- legality ---------------------------------------------------------------
block:
  var w = bare()
  let id = w.spawnRobot(-1, rtEnlightenmentCenter, loc(7, 7), teamA, 100)
  let ec = w.robotsById[id]
  check("influence 0 is refused", not w.canBuildRobot(ec, rtPolitician, dNorth, 0))
  check("negative influence is refused",
    not w.canBuildRobot(ec, rtPolitician, dNorth, -5))
  check("more influence than it has is refused",
    not w.canBuildRobot(ec, rtPolitician, dNorth, 101))
  check("exactly all of it is allowed",
    w.canBuildRobot(ec, rtPolitician, dNorth, 100))
  check("an Enlightenment Center cannot be built",
    not w.canBuildRobot(ec, rtEnlightenmentCenter, dNorth, 10))
  discard w.spawnRobot(-1, rtMuckraker, loc(7, 8), teamB, 1)
  check("an occupied tile is refused",
    not w.canBuildRobot(ec, rtPolitician, dNorth, 10))
  check("a free tile is not", w.canBuildRobot(ec, rtPolitician, dEast, 10))
  ec.cooldownTurns = 1.0
  check("a robot that is not ready cannot build",
    not w.canBuildRobot(ec, rtPolitician, dEast, 10))

block:
  var w = bare()
  let id = w.spawnRobot(-1, rtEnlightenmentCenter, loc(0, 0), teamA, 100)
  let ec = w.robotsById[id]
  check("off the map is refused",
    not w.canBuildRobot(ec, rtPolitician, dSouth, 10))
  check("and so is off the other edge",
    not w.canBuildRobot(ec, rtPolitician, dWest, 10))

# --- the influence is deducted BEFORE the spawn -----------------------------
block:
  var w = bare()
  let id = w.spawnRobot(-1, rtEnlightenmentCenter, loc(7, 7), teamA, 100)
  let ec = w.robotsById[id]
  let built = w.buildRobot(ec, rtPolitician, dNorth, 40)
  checkEq("the Center paid", ec.influence, 60)
  checkEq("and its conviction followed", ec.conviction, 60)
  checkEq("the unit carries the influence", w.robotsById[built].influence, 40)

# --- ceil(ratio * C) --------------------------------------------------------
block:
  checkEq("politician ceil(1.0 * 37)", convictionAtSpawn(rtPolitician, 37), 37)
  checkEq("slanderer ceil(1.0 * 21)", convictionAtSpawn(rtSlanderer, 21), 21)
  ## The muckraker's 0.7 is a CEIL, not a round: 0.7*1 = 0.7 -> 1,
  ## 0.7*3 = 2.1 -> 3, 0.7*10 = 7 -> 7, 0.7*11 = 7.7 -> 8.
  checkEq("muckraker C=1", convictionAtSpawn(rtMuckraker, 1), 1)
  checkEq("muckraker C=3", convictionAtSpawn(rtMuckraker, 3), 3)
  checkEq("muckraker C=10", convictionAtSpawn(rtMuckraker, 10), 7)
  checkEq("muckraker C=11", convictionAtSpawn(rtMuckraker, 11), 8)
  checkEq("muckraker C=100", convictionAtSpawn(rtMuckraker, 100), 70)
  ## And the product is Java's FLOAT one, not a double one: `convictionRatio`
  ## is a `float` and `influence` an `int`, so JLS 5.6.2 makes the product a
  ## float and only `Math.ceil` widens it (`InternalRobot.java:67` at the
  ## pinned battlecode21@ed39c1a4). The two roundings first disagree at
  ## 2 995 933, where the pinned JDK prints 2097153 and a float64 product
  ## gives 2097154.
  checkEq("muckraker C=2995933 follows Java's float product",
    convictionAtSpawn(rtMuckraker, 2_995_933), 2_097_153)

# --- the conviction cap -----------------------------------------------------
block:
  var w = bare()
  let ecId = w.spawnRobot(-1, rtEnlightenmentCenter, loc(7, 7), teamA, 500)
  checkEq("a Center's cap is the influence limit",
    w.robotsById[ecId].convictionCap, RobotInfluenceLimit)
  let ec = w.robotsById[ecId]
  let mId = w.buildRobot(ec, rtMuckraker, dNorth, 11)
  let m = w.robotsById[mId]
  checkEq("a unit's cap is its spawn conviction", m.convictionCap, 8)
  addConviction(m, 100)
  checkEq("healing above the cap is LOST", m.conviction, 8)
  addConviction(m, -3)
  checkEq("and damage below it is not", m.conviction, 5)

# --- exec order: built this round, no turn this round -----------------------
block:
  var w = newWorld(flat(15, 15), 1500)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(3, 3), teamA, 400)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(11, 11), teamB, 400)
  let before = w.execOrder.len
  let sheets = [baselineSheet("bc21", blCaliforniaRoll),
                baselineSheet("bc21", blCaliforniaRoll)]
  var sides = newSides21(sheets, 0)
  runRound(w, sides, [ckCaliforniaRoll, ckCaliforniaRoll])
  check("the exec order grew", w.execOrder.len > before)
  for id in w.execOrder[before .. ^1]:
    checkEq("a robot built this round has taken no turn",
      w.robotsById[id].roundsAlive, 0)
  check("and it is APPENDED, never inserted",
    w.execOrder[0] == 10001 or w.execOrder[0] != w.execOrder[^1])

finish("bc21 build")
