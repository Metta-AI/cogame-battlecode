## Vision radii, the engine's SCAN ORDER, and the fact that an attack needs no
## vision at all.
##
## §Tests item 8. The scan order is load-bearing: it fixes which enemy
## `senseNearbyRobots` returns first — which is the square the example bot's
## soldier attacks — the order ABYSS and FURY sweep the map, and the order the
## sage anomalies apply.

import std/math
import harness
import bc22_fixture

block:
  checkEq("a miner sees r2 <= 20", RobotSpecs[rtMiner].visionRadiusSquared, 20)
  checkEq("a builder likewise", RobotSpecs[rtBuilder].visionRadiusSquared, 20)
  checkEq("a soldier likewise", RobotSpecs[rtSoldier].visionRadiusSquared, 20)
  checkEq("an archon sees r2 <= 34",
    RobotSpecs[rtArchon].visionRadiusSquared, 34)
  checkEq("a watchtower likewise",
    RobotSpecs[rtWatchtower].visionRadiusSquared, 34)
  checkEq("a sage likewise", RobotSpecs[rtSage].visionRadiusSquared, 34)
  checkEq("and a LABORATORY sees r2 <= 53",
    RobotSpecs[rtLaboratory].visionRadiusSquared, 53)

block:
  ## `ceil(sqrt(r2))` over the finite set the rule set can reach, precomputed
  ## so the port needs no `sqrt` on this path.
  for r2 in [2, 5, 13, 20, 25, 34, 53]:
    checkEq("ceil(sqrt(" & $r2 & "))", CeilSqrtTable[r2],
      int(ceil(sqrt(float64(r2)))))

block:
  ## THE SCAN ORDER: x ascending outer, y ascending inner, over the clamped
  ## `ceil(sqrt(r2)) + 1` box, keeping squares with dx2+dy2 <= r2.
  var w = bare()
  var got: seq[Loc]
  for l in w.locationsWithinRadiusSquared(loc(10, 10), 2):
    got.add(l)
  checkEq("r2 <= 2 is the nine squares of the miner's reach", got.len, 9)
  checkEq("in x-ascending, y-ascending order", got,
    @[loc(9, 9), loc(9, 10), loc(9, 11),
      loc(10, 9), loc(10, 10), loc(10, 11),
      loc(11, 9), loc(11, 10), loc(11, 11)])

block:
  var w = bare()
  var count = 0
  for l in w.locationsWithinRadiusSquared(loc(15, 15), 53):
    inc count
  checkEq("r2 <= 53 is 177 squares, which is why n runs 0..176", count, 177)
  count = 0
  for l in w.locationsWithinRadiusSquared(loc(15, 15), 20):
    inc count
  checkEq("r2 <= 20 is 69 squares", count, 69)
  count = 0
  for l in w.locationsWithinRadiusSquared(loc(15, 15), 34):
    inc count
  checkEq("and r2 <= 34 is 109", count, 109)

block:
  ## Clamped to the map at a corner, and never off it.
  var w = bare()
  var offMap = 0
  for l in w.locationsWithinRadiusSquared(loc(0, 0), 34):
    if not w.onTheMap(l): inc offMap
  checkEq("the box clamps to the map", offMap, 0)

block:
  ## `senseNearbyRobots` EXCLUDES SELF and returns in scan order.
  var w = bare()
  let me = w.place(teamA, rtSoldier, loc(10, 10))
  let west = w.place(teamB, rtMiner, loc(8, 10))
  let east = w.place(teamB, rtMiner, loc(12, 10))
  var seen: seq[int]
  for other in w.senseNearbyRobots(me, -1):
    seen.add(other.id)
  checkEq("two robots are sensed and self is not", seen.len, 2)
  checkEq("the WESTERN one first, because x ascends outermost",
    seen[0], west.id)
  checkEq("then the eastern one", seen[1], east.id)

block:
  ## An attack needs NO vision. A soldier's action radius is 13 and its vision
  ## 20, so the honest statement is the rule itself: `canAttack` consults the
  ## ACTION radius and the map, never `canSenseLocation`.
  var w = bare()
  let s = w.place(teamA, rtSoldier, loc(10, 10))
  let victim = w.place(teamB, rtMiner, loc(13, 12))
  check("the target is inside the action radius", w.canActLocation(s, loc(13, 12)))
  check("and inside vision too, here", w.canSenseLocation(s, loc(13, 12)))
  check("the attack is legal", w.canAttack(s, loc(13, 12)))
  discard victim
  ## A SAGE reaches r2 <= 25 with vision 34, so the two radii genuinely differ
  ## and the port must use the ACTION one.
  let sage = w.place(teamA, rtSage, loc(20, 20))
  check("a sage cannot act at r2 = 26",
    not w.canActLocation(sage, loc(21, 25)))
  check("even though it can SEE that far",
    w.canSenseLocation(sage, loc(21, 25)))

block:
  ## `getNumVisibleFriendlyRobots` counts friendly robots EXCLUDING ITSELF
  ## inside r2 <= 53 for a laboratory.
  var w = bare()
  let lab = w.placeLive(teamA, rtLaboratory, loc(15, 15))
  checkEq("a lonely laboratory sees nobody",
    w.updateNumVisibleFriendlyRobots(lab), 0)
  for i in 0 ..< 5:
    discard w.place(teamA, rtMiner, loc(13 + i, 17))
  discard w.place(teamB, rtMiner, loc(16, 16))
  checkEq("five friends, and the enemy does not count",
    w.updateNumVisibleFriendlyRobots(lab), 5)

block:
  ## THERE IS NO OCCLUSION OF ANY KIND in this year — no clouds, no terrain
  ## vision rule. Rubble slows, it does not blind.
  var w = bare(rubble = @[(l: loc(11, 10), amount: 100)])
  let s = w.place(teamA, rtSoldier, loc(10, 10))
  check("a robot sees straight through rubble 100",
    w.canSenseLocation(s, loc(14, 10)))

finish("test_bc22_sensing")
