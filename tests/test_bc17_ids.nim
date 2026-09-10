## §Tests item 10 -- the two `IDGenerator`s (D3).
##
## This is the ENTIRE RNG surface of the 2017 engine and it is smaller than
## any other year here: two `java.util.Random`s, both seeded with the MAP
## seed, drawn from **only at block allocation**. Everything else about a
## bc17 game is a pure function of the map and the two doctrines.
##
## Three consequences the port has to get exactly right, and they are what
## this shard pins:
##
##   * the bullet generator has consumed TWO blocks' worth of shuffles before
##     its first id, because `setStart` allocates and the constructor already
##     did -- 2 x 4 095 draws, and its first block is 32 002 .. 36 097;
##   * NO DRAW HAPPENS PER SPAWN, so a build this port refuses and the engine
##     accepts shifts nothing until the 4 096th spawn;
##   * initial bodies take their ids from the MAP FILE, not the generator.

import std/algorithm
import harness
import bc17_fixture
import battlecode/rng
import battlecode/years/bc17/[constants, world, maps]

proc firstN(gen: var IdGenerator, n: int): seq[int] =
  for i in 0 ..< n: result.add(gen.nextId())

# --- the three measured seeds -----------------------------------------------
block:
  ## Measured against the engine in the sandbox. `Barrier` is seed 98.
  var robot98 = initIdGenerator(98)
  checkEq("the first 8 ROBOT ids for map seed 98", firstN(robot98, 8),
    @[13527, 10137, 10443, 12235, 13581, 11621, 11304, 11839])
  var bullet98 = initIdGenerator(98)
  ## `GameWorld:48-50` builds it the same way and then calls
  ## `setStart(MAX_ROBOT_ID + 1)`, which allocates a SECOND block from the
  ## SAME stream.
  bullet98.nextIdBlock = maxRobotId + 1
  bullet98.cursor = 0
  block:
    for i in 0 ..< 4096:
      bullet98.reserved[i] = int32(maxRobotId + 1 + i + 1)
    for i in countdown(4095, 1):
      let index = int(bullet98.random.nextInt(i + 1))
      let a = bullet98.reserved[index]
      bullet98.reserved[index] = bullet98.reserved[i]
      bullet98.reserved[i] = a
    bullet98.nextIdBlock += 4096
  checkEq("the first 8 BULLET ids for map seed 98", firstN(bullet98, 8),
    @[33728, 35734, 33147, 32964, 35666, 34517, 34646, 34056])

# --- the world builds both, and they are the world's ------------------------
block:
  ## The real construction path: `newWorld` off a committed map. `Barrier`'s
  ## seed is 98, so the world's two generators must be the two above.
  let spec = loadMap("Barrier")
  checkEq("Barrier's map seed is the one measured", spec.mapSeed, 98)
  var w = newWorld(spec, gameDefaultRounds)
  checkEq("the world's next robot id is the stream's first",
    w.peekRobotId(), 13527)
  checkEq("peeking does not consume it", w.peekRobotId(), 13527)
  let r = w.spawnRobot(rtScout, loc(30, 30), tA)
  checkEq("and the spawn takes exactly that id", r.id, 13527)
  checkEq("the next one follows the stream", w.peekRobotId(), 10137)
  var got: seq[int]
  for i in 0 ..< 4:
    got.add(w.spawnRobot(rtScout, loc(float32(20 + i), 20), tA).id)
  checkEq("four more come off the same block", got,
    @[10137, 10443, 12235, 13581])
  ## The BULLET stream is separate and starts two blocks in.
  let bid = w.spawnBullet(tA, 2'f32, 1'f32, loc(30, 30), dirRads(0), r.id)
  checkEq("the first bullet id is the bullet stream's first", bid, 33728)
  checkEq("robots and bullets cannot collide at these ids",
    bid > maxRobotId, true)

# --- the bullet stream's two-block head start -------------------------------
block:
  ## Prove the head start is REAL: a generator that only allocated once from
  ## the same seed gives a different first id.
  var single = initIdGenerator(98, maxRobotId + 1)
  let naive = single.nextId()
  check("a SINGLE allocation from 32001 gives a different first bullet id " &
    "(" & $naive & " rather than 33728) -- the head start is load-bearing",
    naive != 33728)
  check("both are inside the first bullet block 32002..36097",
    naive >= 32002 and naive <= 36097)

# --- the ids are a pure function of the seed and the COUNT ------------------
block:
  ## No draw per spawn: two worlds off the same map, one of which spawns
  ## nothing for a while, agree on the id the nth spawn takes.
  let spec = loadMap("HouseDivided")
  var a = newWorld(spec, gameDefaultRounds)
  var b = newWorld(spec, gameDefaultRounds)
  var idsA, idsB: seq[int]
  for i in 0 ..< 20:
    idsA.add(a.spawnRobot(rtScout, loc(float32(5 + i mod 10), 5), tA).id)
  ## `b` interleaves fifty BULLET spawns, which draw from the OTHER stream.
  for i in 0 ..< 20:
    for k in 0 ..< 2:
      discard b.spawnBullet(tA, 2'f32, 1'f32, loc(3, 3), dirRads(0), 0)
    idsB.add(b.spawnRobot(rtScout, loc(float32(5 + i mod 10), 5), tA).id)
  checkEq("the robot id stream is untouched by bullet spawns", idsA, idsB)

# --- the 4096-id block boundary ---------------------------------------------
block:
  var gen = initIdGenerator(937)
  var seen: seq[int]
  for i in 0 ..< 4096: seen.add(gen.nextId())
  checkEq("a block is exactly 4096 ids", seen.len, 4096)
  var lo = high(int)
  var hi = low(int)
  for v in seen:
    lo = min(lo, v)
    hi = max(hi, v)
  checkEq("the first block is 10001..14096 exactly", (lo, hi), (10001, 14096))
  var sorted = seen
  sorted.sort()
  var duplicates = 0
  for i in 1 ..< sorted.len:
    if sorted[i] == sorted[i - 1]: inc duplicates
  checkEq("with no repeats -- it is a shuffle, not a draw", duplicates, 0)
  check("and it is NOT in ascending order", seen != sorted)
  let next = gen.nextId()
  check("the 4097th id comes from the SECOND block 14097..18192",
    next >= 14097 and next <= 18192)

# --- V3: the guard the engine lacks -----------------------------------------
block:
  ## `IDGenerator` never checks `MAX_ROBOT_ID`. After five blocks the robot
  ## ids reach into the bullet space that starts at 32 002, and `ObjectInfo`'s
  ## own comment names the hazard. This port refuses the build instead. The
  ## test DOCUMENTS that the engine would collide here.
  let spec = loadMap("Alone")
  var w = newWorld(spec, gameDefaultRounds)
  check("a fresh world is nowhere near the ceiling", not w.idPoolWouldOverrun())
  ## Drive the generator straight to an id above the ceiling rather than
  ## spawning 22 000 robots: the guard reads `reserved[cursor]`.
  var found = false
  var gen = initIdGenerator(spec.mapSeed)
  for blockIdx in 0 ..< 6:
    for i in 0 ..< 4096:
      if int(gen.reserved[gen.cursor]) > maxRobotId:
        found = true
        break
      discard gen.nextId()
    if found: break
  check("the robot stream really does climb past MAX_ROBOT_ID (32000) " &
    "within six blocks -- the engine would then collide with a bullet id",
    found)
  w.idGen = gen
  check("and the port's guard sees it", w.idPoolWouldOverrun())

# --- the third Random is NOT ported -----------------------------------------
block:
  ## `GameWorld:39,62` constructs a third `Random(seed)` -- `GameWorld.rand`,
  ## which is written and NEVER READ. Porting it "to be safe" would be a
  ## third stream nothing consumes; the World has exactly two.
  let spec = loadMap("shrine")
  var w = newWorld(spec, gameDefaultRounds)
  var probe = initIdGenerator(spec.mapSeed)
  checkEq("the world's robot generator is seeded with the MAP seed and " &
    "nothing has been drawn from a third stream",
    w.peekRobotId(), probe.nextId())

# --- the counters the results document reports ------------------------------
block:
  let spec = loadMap("shrine")
  var w = newWorld(spec, gameDefaultRounds)
  checkEq("no generated id has been issued at construction",
    w.robotIdsIssued, 0)
  checkEq("nor any bullet id", w.bulletIdsIssued, 0)
  check("even though the map placed its initial bodies", w.robots.len > 0)
  discard w.spawnRobot(rtScout, loc(10, 10), tA)
  discard w.spawnBullet(tA, 2'f32, 1'f32, loc(10, 10), dirRads(0), 0)
  checkEq("one robot id issued", w.robotIdsIssued, 1)
  checkEq("one bullet id issued", w.bulletIdsIssued, 1)

finish("test_bc17_ids")
