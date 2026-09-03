## Rule family: cooldowns, movement, turning, vision cones and CHIRALITY.

import std/[algorithm, math]
import harness
import battlecode/years/bc26/[constants, maps, world]

let spec = loadMap("DefaultSmall")

proc freshWorld(): World = newWorld(spec, GameMaxNumberOfRounds)

# --- cooldowns --------------------------------------------------------------
block:
  let w = freshWorld()
  var rat: Robot
  for r in w.liveRobots:
    if r.unit == utRatKing: rat = r
  check("the map spawns a rat king", rat != nil)
  checkEq("cooldowns start at the limit", rat.actionCooldown, CooldownLimit)
  check("a robot at the limit cannot act", not rat.canActCooldown)
  w.processBeginningOfTurn(rat)
  checkEq("beginning of turn decays by COOLDOWNS_PER_TURN",
    rat.actionCooldown, 0)
  check("and now it can act", rat.canActCooldown)
  w.addMovementCooldown(rat, rat.dir)
  checkEq("a king's move costs its movementCooldown", rat.movementCooldown,
    UnitSpecs[utRatKing].movementCooldown)

block:
  ## A baby rat pays MOVE_STRAFE_COOLDOWN for any direction but its facing.
  let w = freshWorld()
  w.spawnRobot(99001, utBabyRat, loc(2, 2), dNorth, 0, teamA)
  let rat = w.robotsById[99001]
  rat.movementCooldown = 0
  w.addMovementCooldown(rat, dNorth)
  checkEq("moving forward costs movementCooldown", rat.movementCooldown,
    UnitSpecs[utBabyRat].movementCooldown)
  rat.movementCooldown = 0
  w.addMovementCooldown(rat, dEast)
  checkEq("strafing costs MOVE_STRAFE_COOLDOWN", rat.movementCooldown,
    MoveStrafeCooldown)

block:
  ## The CARRY SLOWDOWN: 1 % more cooldown per carried cheese, on movement
  ## and on actions, and NOT on turning.
  let w = freshWorld()
  w.spawnRobot(99002, utBabyRat, loc(4, 4), dNorth, 0, teamA)
  let rat = w.robotsById[99002]
  rat.cheese = 100
  rat.movementCooldown = 0
  w.addMovementCooldown(rat, dNorth)
  checkEq("100 cheese doubles the move cooldown", rat.movementCooldown,
    UnitSpecs[utBabyRat].movementCooldown * 2)
  rat.actionCooldown = 0
  w.addActionCooldown(rat, 10)
  checkEq("100 cheese doubles the action cooldown", rat.actionCooldown, 20)
  rat.turningCooldown = 0
  w.addTurningCooldown(rat)
  checkEq("turning is not slowed by cheese", rat.turningCooldown,
    TurningCooldown)

# --- vision cones -----------------------------------------------------------
block:
  let w = freshWorld()
  w.spawnRobot(99003, utBabyRat, loc(10, 10), dNorth, 0, teamA)
  let rat = w.robotsById[99003]
  check("a rat sees straight ahead", rat.canSenseLocation(loc(10, 14)))
  check("a rat sees 45 degrees off its facing",
    rat.canSenseLocation(loc(12, 12)))
  check("a rat does NOT see behind it", not rat.canSenseLocation(loc(10, 6)))
  check("a rat does NOT see 90 degrees off its facing",
    not rat.canSenseLocation(loc(14, 10)))
  check("a rat does not see past its vision radius",
    not rat.canSenseLocation(loc(10, 10 + 5)))
  check("radius squared 20 reaches four tiles ahead",
    4 * 4 <= UnitSpecs[utBabyRat].visionConeRadiusSquared)

block:
  ## A rat king's cone is 360 degrees, so facing does not gate it.
  let w = freshWorld()
  w.spawnRobot(99004, utRatKing, loc(10, 10), dNorth, 0, teamA)
  let king = w.robotsById[99004]
  check("a king sees behind it", king.canSenseLocation(loc(10, 7)))
  check("a king sees to its side", king.canSenseLocation(loc(14, 10)))

# --- chirality --------------------------------------------------------------
block:
  ## Chirality mirrors a multi-tile robot's part list and the sense sweep. A
  ## mirrored cone that is not mirrored is a silent, match-long divergence.
  let w = freshWorld()
  w.spawnRobot(99005, utRatKing, loc(10, 10), dNorth, 0, teamA)
  w.spawnRobot(99006, utRatKing, loc(20, 20), dNorth, 1, teamB)
  let straight = w.allPartLocations(w.robotsById[99005])
  let mirrored = w.allPartLocations(w.robotsById[99006])
  checkEq("a king occupies nine tiles", straight.len, 9)
  checkEq("so does a mirrored king", mirrored.len, 9)
  check("chirality reverses the part ORDER",
    straight[0].x - 10 != mirrored[0].x - 20 or
    straight[0].y - 10 != mirrored[0].y - 20)
  ## Both cover the same 3x3 box; only the order differs.
  var straightSet, mirroredSet: seq[int]
  for l in straight: straightSet.add((l.x - 10) * 10 + (l.y - 10))
  for l in mirrored: mirroredSet.add((l.x - 20) * 10 + (l.y - 20))
  straightSet.sort()
  mirroredSet.sort()
  checkEq("but they cover the same box", straightSet, mirroredSet)

block:
  ## The location sweep is reversed by chirality, which is what makes the cat
  ## target loop (LAST rat wins) chirality-dependent.
  let w = freshWorld()
  let a = w.allLocationsWithinRadiusSquared(loc(10, 10), 4, 0)
  let b = w.allLocationsWithinRadiusSquared(loc(10, 10), 4, 1)
  checkEq("the same tiles are enumerated", a.len, b.len)
  check("in reversed order", a[0] != b[0])

# --- geometry ---------------------------------------------------------------
block:
  checkEq("distanceSquaredTo", loc(0, 0).distanceSquaredTo(loc(3, 4)), 25)
  check("bottomLeftDistanceSquaredTo offsets by half a tile",
    abs(float64(loc(0, 0).bottomLeftDistanceSquaredTo(loc(1, 1))) - 0.5) < 1e-6)
  checkEq("directionTo is the engine's 2.414 partition",
    loc(0, 0).directionTo(loc(3, 1)), dEast)
  checkEq("and the diagonal band", loc(0, 0).directionTo(loc(2, 2)),
    dNortheast)
  checkEq("directionTo self is CENTER", loc(5, 5).directionTo(loc(5, 5)),
    dCenter)
  checkEq("opposite", dNorth.opposite(), dSouth)
  checkEq("rotateRight", dNorth.rotateRight(), dNortheast)
  checkEq("rotateLeft", dNorth.rotateLeft(), dNorthwest)
  checkEq("CENTER never rotates", dCenter.rotateRight(), dCenter)

# --- movement legality ------------------------------------------------------
block:
  let w = freshWorld()
  w.spawnRobot(99007, utBabyRat, loc(1, 1), dNorth, 0, teamA)
  let rat = w.robotsById[99007]
  rat.movementCooldown = 0
  check("cannot move off the map", not w.canMove(rat, dSouth) or
    w.onTheMap(loc(1, 0)))
  ## Put a wall in front and check it blocks.
  w.walls[w.idx(loc(1, 2))] = true
  check("cannot move into a wall", not w.canMove(rat, dNorth))
  w.walls[w.idx(loc(1, 2))] = false
  check("can move into open floor", w.canMove(rat, dNorth))
  w.dirt[w.idx(loc(1, 2))] = true
  check("cannot move into dirt", not w.canMove(rat, dNorth))

finish("test_rules_motion")
