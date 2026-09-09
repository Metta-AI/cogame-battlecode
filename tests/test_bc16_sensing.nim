## Shard 7 of the note's list — **sensing**.
##
## Sight r2 <= 24 (soldier, guard, viper, turret, TTM), <= 35 (archon),
## <= 53 (scout), and **-1 = THE WHOLE MAP for every zombie and every den,
## always**. `senseRubble`/`senseParts` return **-1** out of range rather than
## throwing. `senseNearbyRobots` returns in INSERTION ORDER with self excluded
## — which is what fixes which enemy `greenhorn` attacks — and
## `senseHostileRobots` keeps the enemy team **and `Team.ZOMBIE`**. The static
## scan order is **x ascending outer, y ascending inner** over the `floor(sqrt(r2))`
## box keeping `d2 <= r2`. **An attack needs no vision at all.**

import std/[sequtils]
import harness
import bc16_fixture

# --- the sight radii -------------------------------------------------------
block:
  for (k, r2) in [(rtSoldier, 24), (rtGuard, 24), (rtViper, 24),
                  (rtTurret, 24), (rtTtm, 24), (rtArchon, 35), (rtScout, 53)]:
    checkEq($k & " sees r2 " & $r2, k.sightRadiusSquared(), r2)
  for k in [rtZombieden, rtStandardzombie, rtRangedzombie, rtFastzombie,
            rtBigzombie]:
    checkEq($k & " sees -1, i.e. THE WHOLE MAP", k.sightRadiusSquared(), -1)

block:
  let w = bare()
  let s = w.put(rtSoldier, loc(15, 15), teamA)
  check("a soldier senses a square at r2 20", w.canSense(s, loc(19, 17)))
  checkEq("which really is r2 20", loc(15, 15).distanceSquaredTo(loc(19, 17)),
    20)
  ## The boundary itself: (2, 2) from (15, 15) is r2 8; the largest square a
  ## soldier can reach is one at exactly r2 24, and r2 25 is out.
  check("and one at exactly r2 24", w.canSense(s, loc(15 + 2, 15 - 2 - 2)))
  checkEq("(2, -4) really is r2 20",
    loc(15, 15).distanceSquaredTo(loc(17, 11)), 20)
  var maxSeen = 0
  for dx in -6 .. 6:
    for dy in -6 .. 6:
      let l = loc(15 + dx, 15 + dy)
      if w.canSense(s, l):
        maxSeen = max(maxSeen, loc(15, 15).distanceSquaredTo(l))
  ## 24 is not a sum of two squares, so the furthest square a soldier can
  ## actually reach on the integer lattice is r2 20 — the bound is 24 and the
  ## lattice cannot land on it. Asserted so nobody "fixes" the radius later.
  checkEq("the furthest square a soldier can sense is r2 20 (24 is not a " &
    "sum of two squares)", maxSeen, 20)
  check("and not one at r2 25", not w.canSense(s, loc(20, 15)))
  let sc = w.put(rtScout, loc(15, 17), teamA)
  check("a scout senses r2 53", w.canSense(sc, loc(15 + 7, 17 + 2)))
  let z = w.put(rtBigzombie, loc(15, 19), teamZombie)
  check("a zombie senses the far corner of the map",
    w.canSense(z, loc(0, 0)) and w.canSense(z, loc(29, 29)))

# --- senseRubble / senseParts return -1 out of range, never throw ---------
block:
  let w = bare(rubble = @[(loc(29, 29), 500.0)],
               parts = @[(loc(29, 28), 40.0)])
  let s = w.put(rtSoldier, loc(2, 2), teamA)
  checkEq("senseRubble out of range is -1", w.senseRubble(s, loc(29, 29)),
    -1.0)
  checkEq("senseParts out of range is -1", w.senseParts(s, loc(29, 28)),
    -1.0)
  let z = w.put(rtBigzombie, loc(3, 3), teamZombie)
  checkEq("a zombie reads the real rubble anywhere",
    w.senseRubble(z, loc(29, 29)), 500.0)
  checkEq("and the real parts", w.senseParts(z, loc(29, 28)), 40.0)

# --- senseNearbyRobots is INSERTION ORDER, self excluded ------------------
block:
  let w = bare(robots = @[])
  let me = w.put(rtScout, loc(15, 15), teamA)
  var spawned: seq[int]
  ## Spawn them in an order that DISAGREES with distance, so a port that
  ## sorted by distance would be caught.
  for l in [loc(17, 15), loc(16, 15), loc(15, 18), loc(15, 16)]:
    spawned.add(w.put(rtSoldier, l, teamB).id)
  var seen: seq[int]
  for r in w.senseNearbyRobots(me, -1): seen.add(r.id)
  ## The two archons of the fixture are not there (`robots = @[]` keeps the
  ## default pair, so filter to the ones this block spawned).
  checkEq("senseNearbyRobots returns INSERTION order, not distance order",
    seen.filterIt(it in spawned), spawned)
  check("and never the sensing robot itself", me.id notin seen)

block:
  ## `senseHostileRobots` keeps the ENEMY TEAM **and Team.ZOMBIE**, and drops
  ## NEUTRALs.
  let w = bare(robots = @[])
  let me = w.put(rtSoldier, loc(15, 15), teamA)
  let friend = w.put(rtSoldier, loc(16, 15), teamA)
  let enemy = w.put(rtSoldier, loc(14, 15), teamB)
  let zombie = w.put(rtStandardzombie, loc(15, 14), teamZombie)
  let neutral = w.put(rtSoldier, loc(15, 16), teamNeutral)
  var seen: seq[int]
  for r in w.senseHostileRobots(me, 24): seen.add(r.id)
  check("the enemy is hostile", enemy.id in seen)
  check("THE HORDE is hostile too", zombie.id in seen)
  check("a friend is not", friend.id notin seen)
  check("and a NEUTRAL is not", neutral.id notin seen)
  checkEq("so exactly two are returned", seen.len, 2)

block:
  ## The radius argument really bites, and `-1` means "everything I can
  ## sense" rather than "nothing".
  let w = bare(robots = @[])
  let me = w.put(rtScout, loc(15, 15), teamA)
  discard w.put(rtSoldier, loc(16, 15), teamB)
  discard w.put(rtSoldier, loc(15 + 7, 15 + 2), teamB)
  var near = 0
  for r in w.senseNearbyRobots(me, 4): inc near
  checkEq("a radius of 4 sees only the adjacent one", near, 1)
  var all = 0
  for r in w.senseNearbyRobots(me, 53): inc all
  checkEq("and 53 sees both", all, 2)

# --- the static scan order: x ascending OUTER, y ascending INNER ----------
block:
  ## `MapLocation.getAllMapLocationsWithinRadiusSq` walks the
  ## `floor(sqrt(r2))` box with x outer and y inner, keeping `d2 <= r2`. The
  ## ORDER is what a parts scan returns, so it is a rule.
  let w = bare()
  var got: seq[Loc]
  for l in w.locationsWithinRadiusSquared(loc(15, 15), 4): got.add(l)
  var want: seq[Loc]
  let radius = intSqrt(4)
  for dx in -radius .. radius:
    for dy in -radius .. radius:
      let l = loc(15 + dx, 15 + dy)
      if loc(15, 15).distanceSquaredTo(l) <= 4: want.add(l)
  checkEq("the scan is x ascending outer, y ascending inner over the " &
    "floor-sqrt box", got, want)
  checkEq("and r2 4 yields the thirteen squares of that disc", got.len, 13)
  ## The box is the FLOOR of the square root, which is why r2 = 53 scans a
  ## 15x15 box and not a 16x16 one.
  checkEq("floor(sqrt(53)) is 7", intSqrt(53), 7)

block:
  ## Off the map is dropped, not clamped.
  let w = bare()
  var got = 0
  for l in w.locationsWithinRadiusSquared(loc(0, 0), 4): inc got
  checkEq("a disc at the corner yields only its on-map quarter", got, 6)

# --- getInitialArchonLocations is sorted and public from round 0 ----------
block:
  let w = bare(robots = @[
    (x: 20, y: 3, kind: ord(rtArchon), team: ord(teamA)),
    (x: 4, y: 25, kind: ord(rtArchon), team: ord(teamB)),
    (x: 4, y: 3, kind: ord(rtArchon), team: ord(teamA)),
    (x: 20, y: 25, kind: ord(rtArchon), team: ord(teamB))])
  checkEq("A's initial archons come back SORTED by MapLocation.compareTo " &
    "(x then y)", w.initialArchonLocations(teamA), @[loc(4, 3), loc(20, 3)])
  checkEq("and B's likewise", w.initialArchonLocations(teamB),
    @[loc(4, 25), loc(20, 25)])
  checkEq("compareTo is x then y", compareLoc(loc(4, 25), loc(20, 3)) < 0,
    true)
  ## Public from round 0: it reads the MAP, not the board, so it survives the
  ## archons dying.
  let a = w.at(4, 3)
  w.visitDeathSignal(a, dcNormal)
  checkEq("and it is still the map's roster after an archon dies",
    w.initialArchonLocations(teamA).len, 2)

# --- an attack needs NO vision --------------------------------------------
block:
  let w = bare()
  let t = w.put(rtTurret, loc(10, 10), teamA)
  let e = w.put(rtSoldier, loc(16, 12), teamB)
  check("the target is outside the turret's sight r2 24",
    not w.canSense(t, e.loc))
  check("and inside its attack r2 40", w.canAttackLocation(t, e.loc))
  check("and the attack lands", w.doAttack(t, e.loc))
  checkEq("for its full 13", e.health, 47.0)

# --- the tabled floor-sqrt is what both radius scans use ------------------
block:
  checkEq("intSqrt(0)", intSqrt(0), 0)
  checkEq("intSqrt(1)", intSqrt(1), 1)
  checkEq("intSqrt(3)", intSqrt(3), 1)
  checkEq("intSqrt(4)", intSqrt(4), 2)
  checkEq("intSqrt(10000)", intSqrt(10000), 100)
  checkEq("and it saturates rather than reading off the end",
    intSqrt(99999), intSqrt(10000))

finish("test_bc16_sensing")
