## Pollution: the global floor, the one-round refinery effect, the vaporator's
## multiplicative scrub, cow haze, and both coefficients in Java `float`.

import harness
import battlecode/years/bc20/[constants, pollution, world]

proc flat(width, height: int): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.symmetry = symRotational
  result.randomSeed = 4242
  for i in 0 ..< width * height:
    result.elevation.add(0)
    result.water.add(false)
    result.pollution.add(0)
    result.soup.add(0)

block:
  ## The closed forms, in float32, and `Math.round(float)` as `floor(x + 0.5)`.
  checkEq("cooldownCoefficient(0)", cooldownCoefficient(0), 1.0'f32)
  checkEq("cooldownCoefficient(2000)", cooldownCoefficient(2000), 2.0'f32)
  checkEq("sensorCoefficient(0)", sensorCoefficient(0), 1.0'f32)
  checkEq("sensorCoefficient(4000)", sensorCoefficient(4000), 0.25'f32)
  checkEq("Math.round rounds a half UP", javaRoundF32(0.5'f32), 1)
  checkEq("and a negative half toward positive infinity",
    javaRoundF32(-0.5'f32), 0)
  checkEq("javaRoundF32(2.49)", javaRoundF32(2.49'f32), 2)
  checkEq("javaRoundF32(2.5)", javaRoundF32(2.5'f32), 3)

block:
  ## Global pollution FLOORS at zero.
  var w = newWorld(flat(9, 9), 1500)
  w.addGlobalPollution(3)
  checkEq("it goes up", w.globalPollution, 3)
  w.addGlobalPollution(-10)
  checkEq("and floors at zero", w.globalPollution, 0)
  checkEq("and the peak is remembered", w.globalPollutionPeak, 3)

block:
  ## A refinery's local +500 lasts EXACTLY ONE ROUND: it is installed at the
  ## end of its own turn and removed at the start of the next one.
  var w = newWorld(flat(15, 15), 1500)
  let id = w.spawnRobot(rtRefinery, loc(7, 7), teamA)
  let r = w.robotsById[id]
  r.soupCarrying = 40
  checkEq("no pollution before the turn", w.getPollution(loc(7, 7)), 0)
  w.processEndOfTurn(r)
  checkEq("the local additive is the type's",
    w.getPollution(loc(7, 7)), 500 + w.globalPollution)
  checkEq("it refined at most maxSoupProduced",
    w.stats.soupRefined[0], RobotSpecs[rtRefinery].maxSoupProduced)
  checkEq("and pushed global pollution up by one", w.globalPollution, 1)
  ## 7.1 of its OWN next turn removes it — and it re-installs, because it is
  ## still carrying soup.
  w.resetPollutionForRobot(id)
  checkEq("cleared", w.getPollution(loc(7, 7)), w.globalPollution)
  ## The radius is the type's, so a tile outside r^2 = 35 never saw it.
  w.processEndOfTurn(r)
  check("a tile inside r^2 = 35 is polluted",
    w.getPollution(loc(7, 12)) > w.globalPollution)
  checkEq("a tile outside is not", w.getPollution(loc(0, 0)),
    w.globalPollution)

block:
  ## The vaporator: x0.80 locally, -1 globally, +2 soup unconditionally.
  var w = newWorld(flat(15, 15), 1500)
  w.globalPollution = 1000
  let id = w.spawnRobot(rtVaporator, loc(7, 7), teamA)
  let r = w.robotsById[id]
  w.processEndOfTurn(r)
  checkEq("it prints two soup", w.stats.soup[0], InitialSoup + 2)
  checkEq("and scrubs one point of global pollution", w.globalPollution, 999)
  checkEq("and multiplies the local reading by 0.80",
    w.getPollution(loc(7, 7)), javaRoundF32(float32(999.0'f32 * 0.80'f32)))

block:
  ## Cows: +2000 over r^2 = 15, every round, unconditionally.
  var w = newWorld(flat(15, 15), 1500)
  let id = w.spawnRobot(rtCow, loc(7, 7), teamNeutral)
  w.processEndOfTurn(w.robotsById[id])
  checkEq("the cow's haze is 2000", w.getPollution(loc(7, 7)), 2000)
  checkEq("at the edge of r^2 = 15 too", w.getPollution(loc(10, 8)), 2000)
  checkEq("and nothing beyond it", w.getPollution(loc(12, 7)), 0)
  checkEq("a cow does not touch global pollution", w.globalPollution, 0)

block:
  ## Pollution shrinks the sensed radius and lengthens the cooldown, both in
  ## float32.
  var w = newWorld(flat(21, 21), 1500)
  let id = w.spawnRobot(rtMiner, loc(10, 10), teamA)
  let r = w.robotsById[id]
  checkEq("a clean miner senses its full radius",
    w.currentSensorRadiusSquared(r), RobotSpecs[rtMiner].sensorRadiusSquared)
  w.globalPollution = 4000
  checkEq("at 4000 pollution it senses a quarter as far",
    w.currentSensorRadiusSquared(r),
    javaRoundF32(float32(float32(RobotSpecs[rtMiner].sensorRadiusSquared) *
                         0.25'f32)))
  r.cooldownTurns = 0.0'f32
  w.addCooldownTurns(r)
  checkEq("and its action costs three cooldown turns instead of one",
    r.cooldownTurns, 3.0'f32)

finish("test_bc20_pollution")
