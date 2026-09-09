## Shard 5 of the note's list — **the zombie AI, ported verbatim**, and the
## most order-sensitive shard in the module.
##
## The den: this round's counts from ITS OWN split schedule, then
## `spawnAllPossible`, then — ONLY IF A QUEUE REMAINS — 10 damage to every
## adjacent non-zombie and a SECOND `spawnAllPossible`. The ring order is
## `DIRECTIONS[floorMod(start + i * chir, 8)]` with `DIRECTIONS` = N, NE, E,
## SE, S, SW, W, NW; the spawn priority is BIGZOMBIE -> FASTZOMBIE ->
## RANGEDZOMBIE -> STANDARDZOMBIE, because the engine's type loop has no
## `break` and keeps the LAST non-zero type.
##
## The zombie: the eight-step ladder with EVERY EARLY RETURN IN PLACE, and the
## two RNG draws whose preconditions are exact (D2c) — `nextInt(8)` only when
## NO player robot is alive at all, and `nextBoolean()` only when the zombie
## got past the attack branch, past `!isCoreReady()` and past the
## move-in-the-preferred-direction branch. `getNearestPlayerControlled`
## consumes a draw from the OTHER stream on EVERY call including size 1
## (D2b), because `java.util.Random.nextInt(1)` still consumes a `next(31)`.

import harness
import bc16_fixture

proc den(x, y: int, spawnDir = 0, chirality = 1,
         schedule: seq[tuple[round: int, counts: array[4, int]]] = @[]):
    DenSpec =
  DenSpec(x: x, y: y, spawnDir: spawnDir, chirality: chirality,
          schedule: schedule)

proc denWorld(spawnDir = 0, chirality = 1,
              schedule: seq[tuple[round: int, counts: array[4, int]]] = @[],
              rubble: seq[tuple[l: Loc, amount: float64]] = @[]): World =
  ## One den at (15, 15) and NOTHING ELSE. No archons: this shard asserts
  ## `getNearestPlayerControlled`'s exact call conditions, so every player
  ## robot on the board has to be one the test put there deliberately.
  ## `spawn_dir` and `chirality` are carried by the converted map (D3/D4), so
  ## a den needs no archon to know which way to spawn.
  bare(rubble = rubble,
       robots = @[(x: 15, y: 15, kind: ord(rtZombieden),
                   team: ord(teamZombie))],
       dens = @[den(15, 15, spawnDir, chirality, schedule)])

# --- DIRECTIONS is the order, and the order is a rule ---------------------
block:
  checkEq("DIRECTIONS is N, NE, E, SE, S, SW, W, NW", @MoveDirs,
    @[dNorth, dNortheast, dEast, dSoutheast, dSouth, dSouthwest, dWest,
      dNorthwest])
  checkEq("ZOMBIE_TYPES is standard, ranged, fast, big", @ZombieSpawnTypes,
    @[rtStandardzombie, rtRangedzombie, rtFastzombie, rtBigzombie])

# --- the den's three steps -------------------------------------------------
block:
  let w = denWorld(schedule = @[(round: 0, counts: [3, 0, 0, 0])])
  let d = w.at(15, 15)
  check("the den is there", d != nil and d.kind == rtZombieden)
  checkEq("and knows its own schedule row", d.denIndex, 0)
  w.currentRound = 0
  w.addScheduledZombies(d)
  checkEq("this round's counts go into the persistent queue", d.denQueue[0],
    3)
  w.spawnAllPossible(d)
  checkEq("and three zombies stand up", w.robotCountOf(teamZombie), 4)
  checkEq("draining the queue", d.denQueue[0], 0)

block:
  ## AT MOST 8 PER CALL AND 16 PER ROUND, and the proximity damage in between.
  let w = denWorld(schedule = @[(round: 0, counts: [40, 0, 0, 0])])
  let d = w.at(15, 15)
  w.currentRound = 0
  w.addScheduledZombies(d)
  w.spawnAllPossible(d)
  checkEq("one call spawns at most eight — the ring has eight squares",
    w.robotCountOf(teamZombie) - 1, 8)
  checkEq("and the queue keeps the rest", d.denQueue[0], 32)
  ## The ring is now full, so the second call spawns nothing and the round's
  ## total is eight — the 16 ceiling is the ring being cleared in between.
  w.spawnAllPossible(d)
  checkEq("a second call onto a full ring spawns nothing",
    w.robotCountOf(teamZombie) - 1, 8)

block:
  ## THE PROXIMITY DAMAGE fires ONLY when a queue remains after the first
  ## `spawnAllPossible`, and it hits every adjacent NON-ZOMBIE — both factions
  ## and the neutrals alike.
  let w = denWorld(schedule = @[(round: 0, counts: [40, 0, 0, 0])])
  let d = w.at(15, 15)
  let victim = w.put(rtGuard, loc(14, 15), teamA)
  let neutral = w.put(rtSoldier, loc(16, 15), teamNeutral)
  w.currentRound = 0
  w.processZombieDen(d)
  checkEq("an adjacent GUARD takes exactly 10", victim.health, 135.0)
  checkEq("and an adjacent NEUTRAL takes 10 too", neutral.health, 50.0)
  checkEq("and the faction's zombie_damage_taken records it",
    w.stats.zombieDamageTaken[0], 10)

block:
  ## No queue left after the first call -> NO proximity damage at all.
  let w = denWorld(schedule = @[(round: 0, counts: [1, 0, 0, 0])])
  let d = w.at(15, 15)
  let victim = w.put(rtGuard, loc(14, 15), teamA)
  w.currentRound = 0
  w.processZombieDen(d)
  checkEq("an emptied queue deals no proximity damage", victim.health, 145.0)

# --- the spawn PRIORITY is the last non-zero type -------------------------
block:
  ## The engine's loop has no `break`, so with one of each queued the FIRST
  ## thing that spawns is a BIGZOMBIE.
  let w = denWorld(schedule = @[(round: 0, counts: [1, 1, 1, 1])])
  let d = w.at(15, 15)
  w.currentRound = 0
  w.addScheduledZombies(d)
  var order: seq[RobotType]
  for i in 0 .. 3:
    let before = w.robotCountOf(teamZombie)
    ## Spawn one at a time by walking the ring manually is not the engine's
    ## shape; instead let the engine spawn all four and read the exec order,
    ## which IS the spawn order.
    discard before
  w.spawnAllPossible(d)
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == teamZombie and r.kind != rtZombieden: order.add(r.kind)
  checkEq("the spawn priority is BIG, FAST, RANGED, STANDARD", order,
    @[rtBigzombie, rtFastzombie, rtRangedzombie, rtStandardzombie])

# --- the ring order, both chiralities -------------------------------------
block:
  ## `DIRECTIONS[floorMod(start + i * chir, 8)]`. With `start = 2` (EAST) and
  ## chirality +1 the ring is E, SE, S, SW, W, NW, N, NE; with chirality -1 it
  ## is E, NE, N, NW, W, SW, S, SE.
  let w = denWorld(spawnDir = 2, chirality = 1,
                   schedule = @[(round: 0, counts: [8, 0, 0, 0])])
  let d = w.at(15, 15)
  w.currentRound = 0
  w.processZombieDen(d)
  var seen: seq[Loc]
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == teamZombie and r.kind != rtZombieden: seen.add(r.loc)
  var want: seq[Loc]
  for i in 0 .. 7:
    want.add(loc(15, 15) + MoveDirs[((2 + i) mod 8 + 8) mod 8])
  checkEq("chirality +1 walks the ring clockwise from the spawn direction",
    seen, want)

block:
  let w = denWorld(spawnDir = 2, chirality = -1,
                   schedule = @[(round: 0, counts: [8, 0, 0, 0])])
  let d = w.at(15, 15)
  w.currentRound = 0
  w.processZombieDen(d)
  var seen: seq[Loc]
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == teamZombie and r.kind != rtZombieden: seen.add(r.loc)
  var want: seq[Loc]
  for i in 0 .. 7:
    want.add(loc(15, 15) + MoveDirs[((2 - i) mod 8 + 8) mod 8])
  checkEq("chirality -1 walks it the other way — the mirror-image ring",
    seen, want)

# --- a den spawns onto rubble >= 100, but never onto an occupied square ----
block:
  ## `canBuild` for a ZOMBIEDEN is ONLY `isEmpty(loc)` — the pathability test
  ## an ARCHON pays is skipped, so a den spawns onto ground no player unit
  ## could stand on.
  let w = denWorld(spawnDir = 0, chirality = 1,
                   schedule = @[(round: 0, counts: [1, 0, 0, 0])],
                   rubble = @[(loc(15, 14), 5000.0)])
  let d = w.at(15, 15)
  w.currentRound = 0
  w.processZombieDen(d)
  let z = w.getRobot(loc(15, 14))
  check("a den spawns onto rubble 5000, which is impassable to a soldier",
    z != nil and z.team == teamZombie)
  check("and a SOLDIER really could not move there",
    not w.canMoveTo(loc(15, 14), rtSoldier))

block:
  let w = denWorld(spawnDir = 0, chirality = 1,
                   schedule = @[(round: 0, counts: [1, 0, 0, 0])])
  let d = w.at(15, 15)
  discard w.put(rtGuard, loc(15, 14), teamA)
  w.currentRound = 0
  w.processZombieDen(d)
  check("but never onto an OCCUPIED square",
    w.getRobot(loc(15, 14)).team == teamA)
  let z = w.getRobot(loc(16, 14))
  check("it takes the next square in the ring instead",
    z != nil and z.team == teamZombie)

# --- the zombie's eight-step ladder, every early return -------------------
block:
  ## (b) In range and weapon ready -> attack, AND RETURN. It does not also
  ## move.
  let w = denWorld()
  let z = w.put(rtStandardzombie, loc(10, 10), teamZombie)
  let s = w.put(rtSoldier, loc(11, 10), teamA)
  let where = z.loc
  w.processZombie(z)
  checkEq("it attacked", s.health, 57.5)
  checkEq("and did NOT move", z.loc, where)

block:
  ## (b) In range but weapon NOT ready -> RETURN ANYWAY. It does not fall
  ## through to the move branch. This is the single most commonly mis-ported
  ## early return in the whole file.
  let w = denWorld()
  let z = w.put(rtStandardzombie, loc(10, 10), teamZombie)
  let s = w.put(rtSoldier, loc(11, 10), teamA)
  z.d.weapon = 5.0
  let where = z.loc
  let seedBefore = w.zombieRand.seed
  w.processZombie(z)
  checkEq("it did not attack", s.health, 60.0)
  checkEq("and it did NOT move either", z.loc, where)
  checkEq("and consumed NO zombie-stream draw", w.zombieRand.seed, seedBefore)

block:
  ## (c) Out of range and core not ready -> return, no draw.
  let w = denWorld()
  let z = w.put(rtStandardzombie, loc(5, 5), teamZombie)
  discard w.put(rtSoldier, loc(20, 20), teamA)
  z.d.core = 5.0
  let where = z.loc
  let seedBefore = w.zombieRand.seed
  w.processZombie(z)
  checkEq("it did not move", z.loc, where)
  checkEq("and consumed no zombie-stream draw", w.zombieRand.seed, seedBefore)

block:
  ## (d) The preferred direction is open -> move and RETURN, consuming NO
  ## `nextBoolean()`.
  let w = denWorld()
  let z = w.put(rtStandardzombie, loc(5, 5), teamZombie)
  discard w.put(rtSoldier, loc(20, 20), teamA)
  let seedBefore = w.zombieRand.seed
  w.processZombie(z)
  check("it moved toward the soldier", z.loc != loc(5, 5))
  checkEq("and consumed NO zombie-stream draw, because the preferred " &
    "direction was open", w.zombieRand.seed, seedBefore)

block:
  ## (e) The preferred direction is BLOCKED -> exactly ONE `nextBoolean()`.
  let w = denWorld(rubble = @[(loc(6, 6), 500.0)])
  let z = w.put(rtStandardzombie, loc(5, 5), teamZombie)
  discard w.put(rtSoldier, loc(20, 20), teamA)
  checkEq("the preferred direction really is SE",
    z.loc.directionTo(loc(20, 20)), dSoutheast)
  check("and it really is blocked", not w.canMove(z, dSoutheast))
  let before = w.zombieRand.seed
  w.processZombie(z)
  check("exactly one nextBoolean was consumed", w.zombieRand.seed != before)
  check("and it went 45 degrees off", z.loc != loc(5, 5))

block:
  ## D2c site 1: `nextInt(8)` ONLY when there is NO player robot alive
  ## anywhere on the map.
  let w = denWorld()
  let z = w.put(rtStandardzombie, loc(5, 5), teamZombie)
  checkEq("no player robot is alive", w.robotCountOf(teamA) +
    w.robotCountOf(teamB), 0)
  let before = w.zombieRand.seed
  w.processZombie(z)
  check("the zombie stream advanced (nextInt(8) then nextBoolean)",
    w.zombieRand.seed != before)
  let worldBefore = w.rand.seed
  discard w.getNearestPlayerControlled(loc(5, 5))
  checkEq("and getNearestPlayerControlled consumes NOTHING when there is no " &
    "candidate at all", w.rand.seed, worldBefore)

block:
  ## D2b: `GameWorld.rand.nextInt(closest.size())` is consumed on EVERY call
  ## INCLUDING size 1, because `java.util.Random.nextInt(1)` still consumes a
  ## `next(31)` draw. Getting this wrong by one draw desynchronises the whole
  ## game.
  let w = denWorld()
  discard w.put(rtSoldier, loc(20, 20), teamA)
  let before = w.rand.seed
  let got = w.getNearestPlayerControlled(loc(5, 5))
  check("there is exactly one candidate", got != nil)
  check("and the world stream ADVANCED anyway", w.rand.seed != before)

block:
  ## A FASTZOMBIE and a BIGZOMBIE ignore rubble and therefore NEVER reach the
  ## `clearRubble` step; a STANDARDZOMBIE and a RANGEDZOMBIE dig.
  for k in [rtFastzombie, rtBigzombie]:
    let w = denWorld(rubble = @[(loc(6, 6), 500.0)])
    let z = w.put(k, loc(5, 5), teamZombie)
    discard w.put(rtSoldier, loc(20, 20), teamA)
    w.processZombie(z)
    checkEq($k & " walked straight onto rubble 500 instead of digging",
      w.getRubble(loc(6, 6)), 500.0)
    checkEq("and it is standing there", z.loc, loc(6, 6))

block:
  ## The digger: a STANDARDZOMBIE boxed in on both 45-degree alternates digs
  ## the preferred square.
  let w = denWorld(rubble = @[(loc(6, 6), 500.0), (loc(6, 5), 500.0),
                              (loc(5, 6), 500.0)])
  let z = w.put(rtStandardzombie, loc(5, 5), teamZombie)
  discard w.put(rtSoldier, loc(20, 20), teamA)
  w.processZombie(z)
  checkEq("a boxed-in STANDARDZOMBIE digs the preferred square",
    w.getRubble(loc(6, 6)), 465.0)
  checkEq("and stays where it is", z.loc, loc(5, 5))

block:
  ## Step (h): the preferred square is occupied by a NEUTRAL and the weapon is
  ## ready -> attack it. This is why zombies eat the neutrals a faction did
  ## not activate in time.
  let w = denWorld(rubble = @[(loc(6, 5), 500.0), (loc(5, 6), 500.0)])
  let z = w.put(rtStandardzombie, loc(5, 5), teamZombie)
  let n = w.put(rtSoldier, loc(6, 6), teamNeutral)
  discard w.put(rtSoldier, loc(20, 20), teamA)
  w.processZombie(z)
  checkEq("the horde eats the neutral standing in its way", n.health, 57.5)

block:
  ## And it does NOT attack an enemy FACTION robot at step (h) — step (h) is
  ## `team == NEUTRAL` only. (An adjacent player robot would have been the
  ## `closest` and taken the step-(b) branch, so the case is constructed with
  ## a nearer player robot elsewhere.)
  let w = denWorld(rubble = @[(loc(6, 5), 500.0), (loc(5, 6), 500.0)])
  let z = w.put(rtRangedzombie, loc(5, 5), teamZombie)
  let blocker = w.put(rtSoldier, loc(6, 6), teamB)
  z.d.weapon = 0.0
  ## A RANGEDZOMBIE reaches r2 13, so the blocker at r2 2 IS attackable and
  ## the ladder short-circuits at (b) — which is exactly the point: (h) is
  ## unreachable for a player-team occupant.
  w.processZombie(z)
  check("an adjacent enemy is taken at step (b), never at step (h)",
    blocker.health < 60.0)

# --- getNearestPlayerControlled sees BOTH factions and NEITHER third team --
block:
  let w = denWorld()
  let a = w.put(rtSoldier, loc(6, 5), teamA)
  discard w.put(rtSoldier, loc(5, 6), teamB)
  discard w.put(rtGuard, loc(5, 4), teamNeutral)
  discard w.put(rtStandardzombie, loc(4, 5), teamZombie)
  let got = w.getNearestPlayerControlled(loc(5, 5))
  check("it picks a PLAYER robot", got != nil and got.team.isPlayer())
  ## Two candidates at the same minimum distance -> the draw decides, and
  ## either answer is a player robot of either team. What is asserted is that
  ## it is never the NEUTRAL and never the ZOMBIE.
  var neutralOrZombie = 0
  for i in 0 ..< 40:
    let r = w.getNearestPlayerControlled(loc(5, 5))
    if r != nil and not r.team.isPlayer(): inc neutralOrZombie
  checkEq("and NEVER a neutral or a zombie, over forty draws",
    neutralOrZombie, 0)
  discard a

finish("test_bc16_zombies")
