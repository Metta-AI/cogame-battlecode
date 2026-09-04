## The delivery drone: pickup radius, what may and may not be lifted, the
## blocked rider, the drop, and what a dying drone does with its cargo.

import harness
import battlecode/years/bc20/[constants, world]

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

proc lastWaterDropVictim(w: World): string =
  ## The `drone_water_drop` event carries the DROPPED unit's team ordinal in
  ## its string slot; `match.nim` turns that into `victim_alias`.
  result = "none"
  for e in w.events:
    if e.kind == "drone_water_drop": result = e.s

block:
  ## Pickup radius squared is 3, and only UNITS may be lifted.
  var w = newWorld(flat(11, 11, 0), 1500)
  let droneId = w.spawnRobot(rtDeliveryDrone, loc(5, 5), teamA)
  let drone = w.robotsById[droneId]
  let nearId = w.spawnRobot(rtMiner, loc(6, 6), teamB)      ## d2 = 2
  let farId = w.spawnRobot(rtMiner, loc(7, 7), teamB)       ## d2 = 8
  let gunId = w.spawnRobot(rtNetGun, loc(4, 5), teamB)      ## a BUILDING
  let otherId = w.spawnRobot(rtDeliveryDrone, loc(5, 6), teamB)
  w.ready(drone)
  checkEq("the pickup radius squared is 3", DeliveryDronePickupRadiusSquared, 3)
  check("a unit at d2 = 2 can be picked up", w.canPickUpUnit(drone, nearId))
  check("a unit at d2 = 8 cannot", not w.canPickUpUnit(drone, farId))
  check("a building can never be picked up", not w.canPickUpUnit(drone, gunId))
  check("and neither can another drone", not w.canPickUpUnit(drone, otherId))

block:
  ## The held unit is BLOCKED — no turn, cooldown frozen — and rides with the
  ## drone.
  var w = newWorld(flat(11, 11, 0), 1500)
  let droneId = w.spawnRobot(rtDeliveryDrone, loc(5, 5), teamA)
  let riderId = w.spawnRobot(rtLandscaper, loc(5, 6), teamB)
  let drone = w.robotsById[droneId]
  let rider = w.robotsById[riderId]
  rider.cooldownTurns = 4.0'f32
  w.ready(drone)
  w.pickUpUnit(drone, riderId)
  check("the drone holds a unit", drone.holdingUnit)
  checkEq("and knows which", drone.heldId, riderId)
  check("the rider is blocked", rider.blocked)
  checkEq("the rider rides at the drone's tile", rider.loc, drone.loc)
  check("the rider's old tile is empty", w.getRobot(loc(5, 6)) == nil)
  checkEq("the drone's pickup counter moved", w.stats.dronePickups[0], 1)
  ## A blocked robot never runs `processBeginningOfTurn`, so its cooldown does
  ## not decay — the round loop skips it entirely. Assert the invariant the
  ## loop relies on.
  checkEq("the rider's cooldown is frozen where it was",
    rider.cooldownTurns, 4.0'f32)

  ## Moving the drone moves the rider.
  w.ready(drone)
  w.move(drone, dNorth)
  checkEq("the rider follows the drone", rider.loc, drone.loc)

  ## A drop needs an unoccupied, on-map tile.
  w.ready(drone)
  discard w.spawnRobot(rtMiner, drone.loc + dEast, teamA)
  check("a drop onto an occupied tile is refused",
    not w.canDropUnit(drone, dEast))
  check("but a clear tile is fine", w.canDropUnit(drone, dWest))
  w.dropUnit(drone, dWest)
  check("the rider is unblocked", not rider.blocked)
  check("and the drone is empty", not drone.holdingUnit)

block:
  ## A drop into water destroys a non-drone, and counts as a water drop when
  ## the victim is an enemy.
  var w = newWorld(flat(11, 11, 0, @[5 + 11 * 4]), 1500)
  let droneId = w.spawnRobot(rtDeliveryDrone, loc(5, 5), teamA)
  let riderId = w.spawnRobot(rtLandscaper, loc(6, 5), teamB)
  let drone = w.robotsById[droneId]
  w.ready(drone)
  w.pickUpUnit(drone, riderId)
  w.ready(drone)
  w.dropUnit(drone, dSouth)
  check("the enemy landscaper drowned", riderId notin w.robotsById)
  checkEq("and it is recorded as a water drop", w.stats.droneWaterDrops[0], 1)
  checkEq("and the event names the victim's own team", w.lastWaterDropVictim(),
    $ord(teamB))

block:
  ## A drone may drop its OWN unit, or a neutral cow, into the water. The
  ## event names whoever was dropped — never "the other clan" by assumption —
  ## and neither drop moves the enemy-drop counter.
  var w = newWorld(flat(11, 11, 0, @[5 + 11 * 4]), 1500)
  let droneId = w.spawnRobot(rtDeliveryDrone, loc(5, 5), teamA)
  let friendId = w.spawnRobot(rtLandscaper, loc(6, 5), teamA)
  let drone = w.robotsById[droneId]
  w.ready(drone)
  w.pickUpUnit(drone, friendId)
  w.ready(drone)
  w.dropUnit(drone, dSouth)
  check("the friendly landscaper drowned too", friendId notin w.robotsById)
  checkEq("the event names the friendly team as the victim",
    w.lastWaterDropVictim(), $ord(teamA))
  checkEq("and no enemy water drop was counted", w.stats.droneWaterDrops[0], 0)

  let cowId = w.spawnRobot(rtCow, loc(6, 5), teamNeutral)
  w.ready(drone)
  w.pickUpUnit(drone, cowId)
  w.ready(drone)
  w.dropUnit(drone, dSouth)
  check("the cow drowned", cowId notin w.robotsById)
  checkEq("the event names the neutral team as the victim",
    w.lastWaterDropVictim(), $ord(teamNeutral))
  checkEq("and the counter, which counts every unit that is not the drone's " &
    "own, moved", w.stats.droneWaterDrops[0], 1)

block:
  ## A dying drone drops its cargo on its OWN tile — and the cargo drowns if
  ## that tile is water.
  var w = newWorld(flat(11, 11, 0), 1500)
  let droneId = w.spawnRobot(rtDeliveryDrone, loc(5, 5), teamA)
  let riderId = w.spawnRobot(rtMiner, loc(6, 5), teamB)
  let drone = w.robotsById[droneId]
  w.ready(drone)
  w.pickUpUnit(drone, riderId)
  w.destroyRobot(droneId)
  check("the rider survived", riderId in w.robotsById)
  checkEq("and stands where the drone died", w.robotsById[riderId].loc,
    loc(5, 5))
  check("and is unblocked", not w.robotsById[riderId].blocked)
  check("and is back on the grid", w.getRobot(loc(5, 5)) != nil)

block:
  ## A carried COW stops polluting: `processEndOfTurn` never runs for a
  ## blocked body, and `updateRobot` clears its effect instead.
  var w = newWorld(flat(11, 11, 0), 1500)
  let droneId = w.spawnRobot(rtDeliveryDrone, loc(5, 5), teamA)
  let cowId = w.spawnRobot(rtCow, loc(6, 5), teamNeutral)
  let cow = w.robotsById[cowId]
  w.processEndOfTurn(cow)
  check("a free cow pollutes", w.getPollution(loc(6, 5)) > 0)
  let drone = w.robotsById[droneId]
  w.ready(drone)
  w.pickUpUnit(drone, cowId)
  check("the cow is blocked", cow.blocked)
  w.resetPollutionForRobot(cowId)
  checkEq("and its pollution is cleared", w.getPollution(loc(6, 5)), 0)

finish("test_bc20_drone")
