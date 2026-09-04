## Sensing, detection and flags: the radii per type, the fog that makes a
## slanderer look like a politician to everyone but Centers and muckrakers,
## the muckraker's detection radius exceeding its sensor radius, cross-team
## flag reads, the unlimited Enlightenment Center channel, and the flag range.

import harness
import battlecode/years/bc21/[constants, world]
import battlecode/years/bc21/chassis/flags

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

proc bare(): World = newWorld(flat(30, 30), 1500)

# --- the radii ---------------------------------------------------------------
block:
  checkEq("Center sensor 40", RobotSpecs[rtEnlightenmentCenter].sensorRadiusSquared, 40)
  checkEq("Center detection 40", RobotSpecs[rtEnlightenmentCenter].detectionRadiusSquared, 40)
  checkEq("Center action 2", RobotSpecs[rtEnlightenmentCenter].actionRadiusSquared, 2)
  checkEq("politician sensor 25", RobotSpecs[rtPolitician].sensorRadiusSquared, 25)
  checkEq("politician action 9", RobotSpecs[rtPolitician].actionRadiusSquared, 9)
  checkEq("slanderer sensor 20", RobotSpecs[rtSlanderer].sensorRadiusSquared, 20)
  checkEq("slanderer action 0 — it never acts",
    RobotSpecs[rtSlanderer].actionRadiusSquared, 0)
  checkEq("muckraker sensor 30", RobotSpecs[rtMuckraker].sensorRadiusSquared, 30)
  checkEq("muckraker action 12", RobotSpecs[rtMuckraker].actionRadiusSquared, 12)
  check("and the muckraker's DETECTION radius is larger than its sensor one",
    RobotSpecs[rtMuckraker].detectionRadiusSquared >
      RobotSpecs[rtMuckraker].sensorRadiusSquared)
  checkEq("muckraker detection 40",
    RobotSpecs[rtMuckraker].detectionRadiusSquared, 40)

# --- the fog -----------------------------------------------------------------
block:
  checkEq("a Center true-senses a slanderer",
    sensedKind(rtEnlightenmentCenter, rtSlanderer), rtSlanderer)
  checkEq("a muckraker true-senses a slanderer",
    sensedKind(rtMuckraker, rtSlanderer), rtSlanderer)
  checkEq("a POLITICIAN sees a slanderer as a politician",
    sensedKind(rtPolitician, rtSlanderer), rtPolitician)
  checkEq("and so does a SLANDERER",
    sensedKind(rtSlanderer, rtSlanderer), rtPolitician)
  checkEq("nothing else is disguised",
    sensedKind(rtPolitician, rtMuckraker), rtMuckraker)
  check("canTrueSense is exactly Centers and muckrakers",
    canTrueSense(rtEnlightenmentCenter) and canTrueSense(rtMuckraker) and
    not canTrueSense(rtPolitician) and not canTrueSense(rtSlanderer))

# --- sensing versus detecting ------------------------------------------------
block:
  var w = bare()
  let id = w.spawnRobot(-1, rtMuckraker, loc(15, 15), teamA, 1)
  let m = w.robotsById[id]
  ## (15+5, 15+2) is 25 + 4 = 29 away: inside sensor 30.
  check("r^2 = 29 is sensed", w.canSenseLocation(m, loc(20, 17)))
  ## (15+6, 15+1) is 36 + 1 = 37 away: outside sensor 30, inside detection 40.
  check("r^2 = 37 is NOT sensed", not w.canSenseLocation(m, loc(21, 16)))
  check("but it IS detected", w.canDetectLocation(m, loc(21, 16)))
  ## (15+6, 15+3) is 36 + 9 = 45: outside both.
  check("r^2 = 45 is neither", not w.canDetectLocation(m, loc(21, 18)))
  check("nothing off the map is sensed", not w.canSenseLocation(m, loc(-1, 15)))

block:
  var w = bare()
  let id = w.spawnRobot(-1, rtPolitician, loc(15, 15), teamA, 30)
  let p = w.robotsById[id]
  check("a politician's detection radius equals its sensor radius",
    w.canDetectLocation(p, loc(20, 15)) == w.canSenseLocation(p, loc(20, 15)))
  check("r^2 = 25 is in", w.canSenseLocation(p, loc(20, 15)))
  check("r^2 = 26 is out", not w.canSenseLocation(p, loc(20, 16)))
  check("r^2 = 9 is inside the ACTION radius", canActLocation(p, loc(18, 15)))
  check("r^2 = 10 is not", not canActLocation(p, loc(18, 16)))

# --- flags -------------------------------------------------------------------
block:
  var w = bare()
  let ecA = w.spawnRobot(-1, rtEnlightenmentCenter, loc(1, 1), teamA, 100)
  let ecB = w.spawnRobot(-1, rtEnlightenmentCenter, loc(28, 28), teamB, 100)
  let far = w.spawnRobot(-1, rtMuckraker, loc(28, 20), teamB, 1)
  let near = w.spawnRobot(-1, rtMuckraker, loc(3, 3), teamB, 1)
  let mine = w.spawnRobot(-1, rtMuckraker, loc(2, 2), teamA, 1)
  check("an Enlightenment Center reads ANY robot's flag, at any range",
    w.canGetFlag(w.robotsById[ecA], far))
  check("including the enemy's Center", w.canGetFlag(w.robotsById[ecA], ecB))
  check("a unit reads any ENLIGHTENMENT CENTER's flag at any range",
    w.canGetFlag(w.robotsById[mine], ecB))
  check("a unit reads a nearby ENEMY unit's flag",
    w.canGetFlag(w.robotsById[mine], near))
  check("but not a distant one",
    not w.canGetFlag(w.robotsById[mine], far))
  w.destroyRobot(far)
  check("and never a robot that no longer exists",
    not w.canGetFlag(w.robotsById[ecA], far))

block:
  var w = bare()
  let id = w.spawnRobot(-1, rtMuckraker, loc(5, 5), teamA, 1)
  let r = w.robotsById[id]
  check("0 is a legal flag", canSetFlag(0))
  check("16777215 is a legal flag", canSetFlag(MaxFlagValue))
  check("16777216 is not", not canSetFlag(MaxFlagValue + 1))
  check("-1 is not", not canSetFlag(-1))
  setFlag(r, MaxFlagValue + 1)
  checkEq("an out-of-range flag is refused, not clamped", r.flag, 0)
  setFlag(r, 12345)
  checkEq("a legal one sticks", r.flag, 12345)
  checkEq("and it persists until changed", r.flag, 12345)

# --- the shared 24-bit word --------------------------------------------------
block:
  for kind in FlagKind:
    for x in [0, 1, 31, 63]:
      for y in [0, 7, 63]:
        for payload in [0, 1, 255, 511]:
          let word = encodeFlag(kind, loc(x, y), payload)
          check("the word is inside MAX_FLAG_VALUE",
            word >= 0 and word <= MaxFlagValue)
          let back = decodeFlag(word)
          if kind != fkSilent or word != 0:
            checkEq("kind round-trips", back.kind, kind)
            checkEq("x round-trips", back.x, x)
            checkEq("y round-trips", back.y, y)
            checkEq("payload round-trips", back.payload, payload)
  checkEq("the influence hint buckets by 8", influenceHint(500), 62)
  checkEq("and saturates rather than wrapping", influenceHint(1_000_000), 511)
  checkEq("and reads back coarsely", influenceFromHint(62), 496)

finish("bc21 sensing")
