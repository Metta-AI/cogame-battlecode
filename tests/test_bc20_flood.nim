## The rising water: the committed level table, the one-ring-per-round flood
## fill, drowning, resurfacing and drone-drop survival.

import std/strutils
import harness
import battlecode/years/bc20/[constants, flood, maps, world]

# --- the committed table matches the spec's own checkpoints ------------------
block:
  ## `GameConstants.getWaterLevel` is generated under the CI JDK into
  ## `data/bc20/water_levels.json` as float32 bit patterns; these are the
  ## rounds the 2020 spec itself quotes.
  checkEq("elevation 1 floods at round 256", roundWaterReaches(1), 256)
  checkEq("elevation 2 floods at round 464", roundWaterReaches(2), 464)
  checkEq("elevation 3 floods at round 677", roundWaterReaches(3), 677)
  checkEq("elevation 4 floods at round 931", roundWaterReaches(4), 931)
  checkEq("elevation 5 floods at round 1210", roundWaterReaches(5), 1210)
  checkEq("elevation 6 floods at round 1413", roundWaterReaches(6), 1413)
  check("elevation 7 is outside the 1500-round cap",
    roundWaterReaches(7) > 1500)
  checkEq("round 0 is dry", waterLevelAt(0), 0.0'f32)
  check("the level rises monotonically over the whole table", (block:
    var ok = true
    var prev = waterLevelAt(0)
    for r in 1 .. WaterTableMaxRound:
      let here = waterLevelAt(r)
      if here < prev: ok = false
      prev = here
    ok))

# --- a hand-built world -----------------------------------------------------
proc flat(width, height, elevation: int, wet: seq[int] = @[]): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.symmetry = symRotational
  result.randomSeed = 4242
  result.initialWater = 0
  for i in 0 ..< width * height:
    result.elevation.add(elevation)
    result.water.add(i in wet)
    result.pollution.add(0)
    result.soup.add(0)

block:
  ## The flood advances EXACTLY ONE RING per round, because the origin set is
  ## snapshotted before anything changes.
  var w = newWorld(flat(9, 9, 0, @[4 + 9 * 4]), 1500)
  w.currentRound = 300
  w.updateWaterLevel()
  check("the water is above elevation 0", w.waterLevel > 0.0'f32)
  checkEq("one flooded tile to start", w.floodedCount, 1)
  w.floodfill()
  checkEq("one ring after one fill", w.floodedCount, 9)
  w.floodfill()
  checkEq("two rings after two fills", w.floodedCount, 25)
  w.floodfill()
  checkEq("three rings after three fills", w.floodedCount, 49)

block:
  ## A non-flying robot on a newly flooded tile dies; a drone does not.
  var w = newWorld(flat(7, 7, 0, @[0]), 1500)
  w.currentRound = 300
  w.updateWaterLevel()
  let minerId = w.spawnRobot(rtMiner, loc(1, 0), teamA)
  let droneId = w.spawnRobot(rtDeliveryDrone, loc(0, 1), teamA)
  w.floodfill()
  check("the miner drowned", minerId notin w.robotsById)
  check("the drone did not", droneId in w.robotsById)

block:
  ## A deposit that lifts a tile to `elevation >= waterLevel` resurfaces it in
  ## the same action (`tryResurface`).
  var w = newWorld(flat(7, 7, 0, @[3 + 7 * 3]), 1500)
  w.currentRound = 250
  w.updateWaterLevel()
  check("the water is under elevation 1", w.waterLevel < 1.0'f32)
  check("the tile starts flooded", w.isFlooded(loc(3, 3)))
  w.addDirt(loc(3, 3), 1)
  check("and resurfaces the moment the dirt lands",
    not w.isFlooded(loc(3, 3)))
  checkEq("the flooded count follows", w.floodedCount, 0)

block:
  ## The initial flooded set comes from the map's own `water` array.
  let spec = loadMap("WateredDown")
  var w = newWorld(spec, 1500)
  var expected = 0
  for wet in spec.water:
    if wet: expected += 1
  checkEq("the initial flooded set is the map's", w.floodedCount, expected)
  checkEq("and the water starts at the map's initialWater",
    w.waterLevel, float32(spec.initialWater))

block:
  ## A drone dropped into water survives; a miner does not.
  var w = newWorld(flat(7, 7, 0, @[0, 1, 2, 3, 4, 5, 6]), 1500)
  let droneId = w.spawnRobot(rtDeliveryDrone, loc(3, 2), teamA)
  let minerId = w.spawnRobot(rtMiner, loc(3, 3), teamA)
  let drone = w.robotsById[droneId]
  drone.cooldownTurns = 0
  w.pickUpUnit(drone, minerId)
  check("the miner is held", drone.holdingUnit)
  check("and is blocked", w.robotsById[minerId].blocked)
  drone.cooldownTurns = 0
  ## Fly the drone over the water and drop.
  drone.loc = loc(3, 1)
  w.robotsById[minerId].loc = loc(3, 1)
  w.dropUnit(drone, dSouth)
  check("the miner dropped into water died", minerId notin w.robotsById)
  check("and the drone is still flying", droneId in w.robotsById)

finish("test_bc20_flood")
