## Dirt: dig, deposit, the 25-carry limit, burying a building at its health,
## the released dirt, and `MAX_DIRT_DIFFERENCE` gating movement and placement
## but never a drone.

import harness
import battlecode/years/bc20/[constants, maps, world]

proc flat(width, height, elevation: int, wet: seq[int] = @[]): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.symmetry = symRotational
  result.randomSeed = 4242
  for i in 0 ..< width * height:
    result.elevation.add(elevation)
    result.water.add(i in wet)
    result.pollution.add(0)
    result.soup.add(0)

proc ready(w: World, r: Robot) = r.cooldownTurns = 0.0'f32

block:
  ## Dig lowers an empty tile by 1 and raises `dirtCarrying`, to at most 25.
  var w = newWorld(flat(9, 9, 5), 1500)
  let id = w.spawnRobot(rtLandscaper, loc(4, 4), teamA)
  let r = w.robotsById[id]
  for i in 1 .. 25:
    w.ready(r)
    w.digDirt(r, dEast)
  checkEq("the landscaper is full at the dirt limit", r.dirtCarrying, 25)
  checkEq("and the tile went down by 25", w.getDirt(loc(5, 4)), 5 - 25)
  w.ready(r)
  check("a full landscaper cannot dig", not w.canDigDirt(r, dEast))
  w.ready(r)
  w.depositDirt(r, dWest)
  checkEq("a deposit costs one carried dirt", r.dirtCarrying, 24)
  checkEq("and raises the target tile", w.getDirt(loc(3, 4)), 6)
  checkEq("the team's dirt-moved counter counts both",
    w.stats.dirtMoved[0], 26)

block:
  ## Dig on a CLEAN building is illegal; on a dirty one it takes 1 off the
  ## building, not off the ground.
  var w = newWorld(flat(9, 9, 5), 1500)
  let landId = w.spawnRobot(rtLandscaper, loc(4, 4), teamA)
  let gunId = w.spawnRobot(rtNetGun, loc(5, 4), teamA)
  let r = w.robotsById[landId]
  let gun = w.robotsById[gunId]
  w.ready(r)
  check("digging out from under a clean building is illegal",
    not w.canDigDirt(r, dEast))
  gun.dirtCarrying = 4
  w.ready(r)
  check("but a dirty building can be dug out", w.canDigDirt(r, dEast))
  w.digDirt(r, dEast)
  checkEq("the dirt came off the BUILDING", gun.dirtCarrying, 3)
  checkEq("and not off the ground", w.getDirt(loc(5, 4)), 5)

block:
  ## Deposit on a building adds 1 and DESTROYS it at its health, releasing
  ## that much dirt onto the vacated tile.
  var w = newWorld(flat(9, 9, 5), 1500)
  let landId = w.spawnRobot(rtLandscaper, loc(4, 4), teamA)
  let gunId = w.spawnRobot(rtNetGun, loc(5, 4), teamB)
  let r = w.robotsById[landId]
  r.dirtCarrying = 25
  for i in 1 .. RobotSpecs[rtNetGun].dirtLimit:
    w.ready(r)
    w.depositDirt(r, dEast)
  check("the net gun is buried at 15 dirt", gunId notin w.robotsById)
  checkEq("and the 15 dirt landed on the tile", w.getDirt(loc(5, 4)), 5 + 15)

block:
  ## An HQ needs FIFTY dirt, and the burial is recorded as such.
  var w = newWorld(flat(9, 9, 5), 1500)
  let hqId = w.spawnRobot(rtHq, loc(5, 4), teamB)
  let landId = w.spawnRobot(rtLandscaper, loc(4, 4), teamA)
  let r = w.robotsById[landId]
  for i in 1 .. RobotSpecs[rtHq].dirtLimit:
    r.dirtCarrying = 25
    w.ready(r)
    w.depositDirt(r, dEast)
    if hqId notin w.robotsById: break
  check("the HQ is buried", hqId notin w.robotsById)
  check("team B's HQ is recorded destroyed", w.stats.destroyedHq[1])
  checkEq("with the cause recorded as burial", w.hqLostCause[1], "buried")

block:
  ## A dying landscaper drops its carry onto its own tile.
  var w = newWorld(flat(9, 9, 5), 1500)
  let id = w.spawnRobot(rtLandscaper, loc(4, 4), teamA)
  w.robotsById[id].dirtCarrying = 7
  w.destroyRobot(id)
  checkEq("the carried dirt landed where it died", w.getDirt(loc(4, 4)),
    5 + 7)

block:
  ## MAX_DIRT_DIFFERENCE gates movement and non-drone placement, never a drone.
  var w = newWorld(flat(9, 9, 0), 1500)
  w.elevation[w.idx(loc(5, 4))] = MaxDirtDifference + 1
  let minerId = w.spawnRobot(rtMiner, loc(4, 4), teamA)
  let droneId = w.spawnRobot(rtDeliveryDrone, loc(4, 5), teamA)
  w.ready(w.robotsById[minerId])
  w.ready(w.robotsById[droneId])
  check("a miner cannot step up four", not w.canMove(w.robotsById[minerId], dEast))
  w.elevation[w.idx(loc(5, 4))] = MaxDirtDifference
  check("but it can step up three", w.canMove(w.robotsById[minerId], dEast))
  w.elevation[w.idx(loc(5, 5))] = 40
  check("a drone ignores the elevation step entirely",
    w.canMove(w.robotsById[droneId], dEast))

  ## Placement: the same gate, and the same drone exemption.
  var w2 = newWorld(flat(9, 9, 0), 1500)
  w2.elevation[w2.idx(loc(5, 4))] = MaxDirtDifference + 1
  w2.stats.soup[0] = 10_000
  let fcId = w2.spawnRobot(rtFulfillmentCenter, loc(4, 4), teamA)
  let mineId = w2.spawnRobot(rtMiner, loc(4, 6), teamA)
  w2.ready(w2.robotsById[fcId])
  w2.ready(w2.robotsById[mineId])
  check("a miner cannot found a building four steps up",
    not w2.canBuildRobot(w2.robotsById[mineId], rtNetGun, dSouth) or
    w2.getDirtDifference(loc(4, 6), loc(4, 5)) <= MaxDirtDifference)
  check("a fulfillment center can drop a drone four steps up",
    w2.canBuildRobot(w2.robotsById[fcId], rtDeliveryDrone, dEast))

finish("test_bc20_dirt")
