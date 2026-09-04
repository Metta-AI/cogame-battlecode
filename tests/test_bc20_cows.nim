## The NPC cows: the seed, the four draws, the early exit, the odd-id
## reversal, and the symmetry the reversal reads.

import harness
import battlecode/rng
import battlecode/years/bc20/[constants, cows, maps, world]

proc flat(width, height: int, wet: seq[int] = @[]): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.symmetry = symRotational
  result.randomSeed = 43223
  for i in 0 ..< width * height:
    result.elevation.add(0)
    result.water.add(i in wet)
    result.pollution.add(0)
    result.soup.add(0)

block:
  ## `new Random(84307 * mapSeed + 20201 * (cowId / 2))`, in Java `int`
  ## arithmetic, WHICH OVERFLOWS: 84307 * 43223 alone is 3 644 001 461. Java
  ## wraps; a checked conversion would raise on exactly the seeds that matter.
  checkEq("the wrapped product for map seed 43223 and cow 0",
    cowSeed(43223, 0), int(cast[int32](3644001461'u32)))
  checkEq("cow 1 shares cow 0's seed (id / 2)", cowSeed(43223, 1),
    cowSeed(43223, 0))
  checkEq("cow 2 does not", cowSeed(43223, 2),
    int(cast[int32](3644001461'u32 + 20201'u32)))

block:
  ## A READY cow draws up to four directions and STOPS THE MOMENT IT MOVES.
  var w = newWorld(flat(9, 9), 1500)
  let id = w.spawnRobot(6, rtCow, loc(4, 4), teamNeutral)
  let cow = w.robotsById[id]
  cow.cooldownTurns = 0.0'f32
  var reference = initJavaRandom(cowSeed(w.map.randomSeed, 6))
  ## On an empty flat map the first draw is always legal, so exactly ONE
  ## nextDouble is consumed.
  let firstDir = MoveDirs[int(reference.nextDouble() * 8.0)]
  w.runCow(cow)
  checkEq("the cow moved in the first drawn direction", cow.loc,
    loc(4, 4) + firstDir)
  var after = w.cowRand[id]
  var fresh = initJavaRandom(cowSeed(w.map.randomSeed, 6))
  discard fresh.nextDouble()
  checkEq("and exactly one draw was consumed", after.seed, fresh.seed)

block:
  ## A cow that is NOT ready burns exactly four `nextDouble` calls and does
  ## nothing.
  var w = newWorld(flat(9, 9), 1500)
  let id = w.spawnRobot(6, rtCow, loc(4, 4), teamNeutral)
  let cow = w.robotsById[id]
  cow.cooldownTurns = 5.0'f32
  w.runCow(cow)
  checkEq("it did not move", cow.loc, loc(4, 4))
  var fresh = initJavaRandom(cowSeed(w.map.randomSeed, 6))
  for i in 1 .. 4: discard fresh.nextDouble()
  checkEq("and burned exactly four draws", w.cowRand[id].seed, fresh.seed)

block:
  ## An ODD id reverses the drawn direction through the map symmetry.
  for sym in [symVertical, symHorizontal, symRotational]:
    var w = newWorld(flat(9, 9), 1500)
    w.symmetry = sym
    checkEq("north reverses correctly under " & $sym,
      w.reverseDirection(dNorth),
      (case sym
       of symVertical: dNorth
       of symHorizontal: dSouth
       of symRotational: dSouth))
    checkEq("east reverses correctly under " & $sym,
      w.reverseDirection(dEast),
      (case sym
       of symVertical: dWest
       of symHorizontal: dEast
       of symRotational: dWest))
    checkEq("northeast reverses correctly under " & $sym,
      w.reverseDirection(dNortheast),
      (case sym
       of symVertical: dNorthwest
       of symHorizontal: dSoutheast
       of symRotational: dSouthwest))

block:
  ## A cow never walks into water.
  var w = newWorld(flat(5, 5, @[0, 1, 2, 3, 4, 5, 9, 10, 14, 15, 19,
                                20, 21, 22, 23, 24]), 1500)
  let id = w.spawnRobot(6, rtCow, loc(2, 2), teamNeutral)
  let cow = w.robotsById[id]
  for turn in 1 .. 50:
    cow.cooldownTurns = 0.0'f32
    w.runCow(cow)
    if cow.dead: break
  check("the cow is still alive", not cow.dead)
  check("and stayed on dry land", not w.isFlooded(cow.loc))

block:
  ## The sim's own symmetry detector agrees with the converter's committed
  ## value on every map in the variant's pool, on round 1.
  for name in MixedPool:
    let spec = loadMap(name)
    let w = newWorld(spec, 1500)
    checkEq("the sim recomputes " & name & "'s symmetry as committed",
      w.symmetry, spec.symmetry)
    checkEq("and a fresh recomputation agrees: " & name,
      w.recomputeSymmetry(), spec.symmetry)

finish("test_bc20_cows")
