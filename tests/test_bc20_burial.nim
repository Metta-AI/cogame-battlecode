## Burial: fifty dirt kills an HQ, the end-of-round ladder awards
## `hq_destroyed` in the SAME round, the released dirt raises the tile, and a
## double HQ loss falls through to `quantity`.

import harness
import battlecode/years/bc20/[constants, flood, world]

proc flat(width, height, elevation: int): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.symmetry = symRotational
  result.randomSeed = 4242
  for i in 0 ..< width * height:
    result.elevation.add(elevation)
    result.water.add(false)
    result.pollution.add(0)
    result.soup.add(0)

proc bury(w: World, target: Loc, from0: Loc) =
  let landId = w.spawnRobot(rtLandscaper, from0, teamA)
  let r = w.robotsById[landId]
  for i in 1 .. 60:
    r.dirtCarrying = 25
    r.cooldownTurns = 0.0'f32
    w.depositDirt(r, fromDelta(target.x - from0.x, target.y - from0.y))
    if w.getRobot(target) == nil: break

block:
  var w = newWorld(flat(11, 11, 5), 1500)
  let hqB = w.spawnRobot(rtHq, loc(5, 5), teamB)
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  checkEq("an HQ takes fifty dirt", RobotSpecs[rtHq].dirtLimit, 50)
  w.bury(loc(5, 5), loc(4, 5))
  check("the HQ is gone", hqB notin w.robotsById)
  check("and team B is recorded as having lost it", w.stats.destroyedHq[1])
  checkEq("the released 50 dirt raised the tile", w.getDirt(loc(5, 5)),
    5 + RobotSpecs[rtHq].dirtLimit)

  ## The ladder awards `hq_destroyed` to the other team in the same round.
  w.checkEndOfMatch()
  check("a winner was set", w.hasWinner)
  checkEq("and it is the other team", w.winner, teamA)
  checkEq("on hq_destroyed", $w.domination, "hq_destroyed")

block:
  ## A DOUBLE HQ loss in one round is not `hq_destroyed`: the ladder falls
  ## through to `quantity`.
  var w = newWorld(flat(11, 11, 5), 1500)
  let hqA = w.spawnRobot(rtHq, loc(1, 1), teamA)
  let hqB = w.spawnRobot(rtHq, loc(9, 9), teamB)
  discard w.spawnRobot(rtMiner, loc(2, 2), teamA)
  w.destroyRobot(hqA)
  w.destroyRobot(hqB)
  check("both HQs are recorded lost",
    w.stats.destroyedHq[0] and w.stats.destroyedHq[1])
  w.checkEndOfMatch()
  check("a winner was still set", w.hasWinner)
  checkEq("but not on hq_destroyed", $w.domination, "quantity")
  checkEq("and it is the side with more robots", w.winner, teamA)

block:
  ## An HQ that is never walled DROWNS, and the cause is recorded as such.
  var spec = flat(11, 11, 0)
  spec.water[0] = true
  var w = newWorld(spec, 1500)
  let hqA = w.spawnRobot(rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(rtHq, loc(9, 9), teamB)
  w.currentRound = 300
  w.updateWaterLevel()
  for i in 1 .. 4:
    w.floodfill()
  check("the HQ drowned", hqA notin w.robotsById)
  checkEq("with the cause recorded", w.hqLostCause[0], "drowned")
  check("and the round recorded", w.hqLostRound[0] >= 0)

finish("test_bc20_burial")
