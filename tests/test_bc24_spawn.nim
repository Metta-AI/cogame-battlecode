## bc24 spawning and jail: the spawn preconditions, the 250-turn spawn
## cooldown that IS twenty-five jail rounds, the roster of exactly fifty a
## side, the `IDGenerator(mapSeed)` id stream in `A, B, A, B, ...` creation
## order, and the exec order that never changes because a duck is never
## destroyed.

import harness
import bc24_fixture
import battlecode/rng

# --- the roster and the exec order ------------------------------------------
block:
  var w = bare()
  checkEq("one hundred ducks", w.robots.len, 2 * RobotCapacity)
  var a, b = 0
  for r in w.robots:
    if r.team == teamA: a += 1 else: b += 1
  checkEq("fifty on team A", a, RobotCapacity)
  checkEq("fifty on team B", b, RobotCapacity)
  var interleaved = true
  for i, r in w.robots:
    if (i mod 2 == 0) != (r.team == teamA): interleaved = false
    if r.execIndex != i: interleaved = false
  check("created A0, B0, A1, B1, ... and the exec index IS the slot",
    interleaved)

block:
  ## The ids are exactly `IDGenerator(map.randomSeed).nextId()` in that order.
  var w = bare()
  var gen = initIdGenerator(flatMap().randomSeed)
  var ok = true
  for r in w.robots:
    if r.id != gen.nextId(): ok = false
  check("every id comes off IDGenerator(mapSeed) in creation order", ok)
  var lookupOk = true
  for r in w.robots:
    if w.robotById(r.id) != r: lookupOk = false
  check("and the id lookup agrees", lookupOk)

# --- spawn legality ---------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.robots[2]
  check("A may spawn on an A spawn tile", w.canSpawn(r, loc(3, 3)))
  check("but not on a B spawn tile", not w.canSpawn(r, loc(26, 3)))
  check("nor on plain ground", not w.canSpawn(r, loc(10, 10)))
  check("nor off the map", not w.canSpawn(r, loc(-1, 3)))
  let blocker = w.placeDuck(teamA, loc(3, 4))
  check("nor on an occupied spawn tile", not w.canSpawn(r, loc(3, 4)))
  check("(the blocker is really there)", w.getRobot(loc(3, 4)) == blocker)
  w.water[w.idx(loc(2, 3))] = true
  check("nor on an impassable one", not w.canSpawn(r, loc(2, 3)))
  r.spawnCooldown = 10
  check("nor while the spawn counter is at 10", not w.canSpawn(r, loc(3, 3)))
  r.spawnCooldown = 9
  check("but 9 is fine", w.canSpawn(r, loc(3, 3)))

block:
  var w = bare()
  w.postSetup()
  let r = w.robots[0]
  w.doSpawn(r, loc(3, 3))
  check("spawned", r.spawned)
  check("and a spawned duck cannot spawn again",
    not w.canSpawn(r, loc(3, 2)))
  check("the tile holds it", w.getRobot(loc(3, 3)) == r)
  checkEq("one distinct duck counted", w.stats.ducksSpawned[0], 1)

# --- despawn, jail and the exact twenty-five rounds -------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  r.attackExp = 20
  w.despawnRobot(r)
  check("a despawned duck is off the board", not r.spawned)
  check("its tile is clear", w.getRobot(loc(5, 5)) == nil)
  checkEq("the spawn counter is 250 = 10 x 25", r.spawnCooldown,
    CooldownsPerTurn * JailedRounds)
  checkEq("the jail penalty hit its best skill", r.attackExp, 18)
  checkEq("and it counted as a jailing", w.stats.ducksJailed[0], 1)
  var turns = 0
  while not r.canSpawnCooldown():
    w.processBeginningOfTurn(r)
    turns += 1
  checkEq("jail lasts EXACTLY twenty-five turns", turns, JailedRounds)

block:
  var w = bare()
  w.postSetup()
  let r = w.robots[0]
  w.doSpawn(r, loc(3, 3))
  r.health = 120
  r.roundsAlive = 300
  w.addHealth(r, -200)
  check("a duck at or below zero HP despawns at once", not r.spawned)
  r.spawnCooldown = 0
  w.doSpawn(r, loc(3, 4))
  checkEq("respawn restores full health", r.health, DefaultHealth)
  checkEq("and roundsAlive restarts", r.roundsAlive, 0)
  checkEq("a respawn is not a second DISTINCT duck",
    w.stats.ducksSpawned[0], 1)
  checkEq("but it is a second spawn event", w.stats.spawnEvents[0], 2)

block:
  ## Ducks are never DESTROYED -- death is a despawn -- so the exec order is
  ## the same hundred slots at the end of the game as at the start.
  var w = bare()
  w.postSetup()
  let before = w.robots.len
  for i in 0 ..< 10:
    let r = w.placeDuck(teamA, loc(5, i + 2))
    w.addHealth(r, -DefaultHealth)
  checkEq("still one hundred slots after ten deaths", w.robots.len, before)
  var stillIndexed = true
  for i, r in w.robots:
    if r.execIndex != i: stillIndexed = false
  check("and the exec order never moved", stillIndexed)

# --- the jail penalty's tiebreak --------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  r.attackExp = 0
  r.buildExp = 0
  r.healExp = 0
  w.despawnRobot(r)
  checkEq("all three experiences zero: the penalty is SKIPPED",
    r.attackExp + r.buildExp + r.healExp, 0)

finish("bc24 spawning and jail")
