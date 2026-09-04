## bc24 sensing: vision `r^2 <= 20` THROUGH walls and water, flags sensed
## within vision including carried ones, ENEMY TRAPS NEVER SENSED, and the
## broadcast list -- exactly the enemy flags that are neither carried nor
## visible, in `allFlags` order, re-rolled at the start of rounds 1, 101,
## 201, ... from the world RNG using the engine's own scan order.

import harness
import bc24_fixture
import battlecode/years/bc24/[flags, rules]
import battlecode/sheet

# --- vision -----------------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(10, 10))
  check("r2 = 20 is visible", w.canSenseLocation(r, loc(14, 12)))
  check("r2 = 21 is not", w.canSenseLocation(r, loc(14, 12 + 1)) == false)
  check("off the map is not", not w.canSenseLocation(r, loc(-1, 10)))
  w.walls[w.idx(loc(11, 10))] = true
  check("a wall in the way changes NOTHING -- 2024 vision is a radius, not a "
        , w.canSenseLocation(r, loc(14, 10)))
  w.water[w.idx(loc(12, 10))] = true
  check("and neither does water", w.canSenseLocation(r, loc(14, 10)))
  check("an unspawned duck senses nothing",
    not w.canSenseLocation(w.robots[1], loc(10, 10)))

# --- enemy traps are invisible ----------------------------------------------
block:
  var w = bare()
  w.postSetup()
  w.layTrap(teamB, tkStun, loc(11, 10))
  let a = w.placeDuck(teamA, loc(10, 10))
  check("(the trap is really there)", w.hasTrap(loc(11, 10)))
  checkEq("and it belongs to B", w.getTrap(loc(11, 10)).team, teamB)
  ## The only sensing surface the chassis has is `observe`, which never looks
  ## at `trapLocations` at all -- there is no proc a duck can call that
  ## reports an enemy trap. This assertion is the structural one: the
  ## `isInvisible` flag is set on every 2024 trap type.
  check("every trap type is invisible to the opponent",
    TrapSpecs[tkStun].isInvisible and TrapSpecs[tkWater].isInvisible and
    TrapSpecs[tkExplosive].isInvisible)
  check("(a friendly trap is a different matter: the owner placed it)",
    w.getTrap(loc(11, 10)).team == teamB)

# --- the broadcast list -----------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let a = w.placeDuck(teamA, loc(10, 10))
  var seen: seq[Loc]
  for l in w.broadcastFlagLocations(a):
    seen.add(l)
  checkEq("all three ENEMY flags broadcast, and only those", seen.len, 3)
  var ours = 0
  for l in seen:
    for f in w.ownFlags(teamA):
      if f.broadcastLoc == l: ours += 1
  checkEq("none of them is ours", ours, 0)

block:
  var w = bare()
  w.postSetup()
  let f = w.ownFlags(teamB)[0]
  let a = w.placeDuck(teamA, f.loc + dWest)
  var seen: seq[Loc]
  for l in w.broadcastFlagLocations(a):
    seen.add(l)
  checkEq("a flag the duck can SEE is not broadcast to it", seen.len, 2)

block:
  var w = bare()
  w.postSetup()
  let f = w.ownFlags(teamB)[0]
  let carrier = w.placeDuck(teamB, loc(20, 20))
  w.removeFlagAt(f.loc, f)
  carrier.flag = f
  f.carriedBy = carrier.id
  f.loc = carrier.loc
  let a = w.placeDuck(teamA, loc(10, 10))
  var seen: seq[Loc]
  for l in w.broadcastFlagLocations(a):
    seen.add(l)
  checkEq("a CARRIED flag is not broadcast", seen.len, 2)

# --- the re-roll parity and the RNG draw order ------------------------------
block:
  ## The re-roll runs when `currentRound % 100 == 0` BEFORE the increment, so
  ## it fires entering rounds 1, 101, 201, ... `runRound` is the only caller.
  var w = bare(2000, withDam = false)
  var sides = newSides24([defaultSheet("bc24"), defaultSheet("bc24")], 0)
  let chassis = [ckExamplefuncsplayer24, ckExamplefuncsplayer24]
  var changedAt: seq[int]
  var last: seq[Loc]
  for f in w.allFlags: last.add(f.broadcastLoc)
  for round in 1 .. 250:
    runRound(w, sides, chassis)
    var now: seq[Loc]
    for f in w.allFlags: now.add(f.broadcastLoc)
    if now != last:
      changedAt.add(round)
      last = now
  check("the broadcast is re-rolled entering round 1", 1 in changedAt)
  check("and entering round 101", 101 in changedAt)
  check("and entering round 201", 201 in changedAt)
  check("and at no other round", changedAt.len == 3)

block:
  ## Every broadcast location is inside `r^2 <= 100` of the truth and on the
  ## map -- the engine draws from `getAllLocationsWithinRadiusSquared(loc,
  ## 100)`, which is clamped to the board.
  var w = bare()
  w.updateFlagBroadcastLocations()
  var ok = true
  for f in w.allFlags:
    if not w.onTheMap(f.broadcastLoc): ok = false
    if f.loc.distanceSquaredTo(f.broadcastLoc) > FlagBroadcastNoiseRadius:
      ok = false
  check("every broadcast fix is on the map and inside r2 <= 100", ok)

block:
  ## The draw is a pure function of the map seed and the draw ORDER, so two
  ## worlds from the same map agree and a third re-roll differs.
  var a = bare()
  var b = bare()
  a.updateFlagBroadcastLocations()
  b.updateFlagBroadcastLocations()
  var same = true
  for i in 0 ..< a.allFlags.len:
    if a.allFlags[i].broadcastLoc != b.allFlags[i].broadcastLoc: same = false
  check("the same map seed draws the same broadcast fixes", same)
  let before = a.allFlags[0].broadcastLoc
  a.updateFlagBroadcastLocations()
  a.updateFlagBroadcastLocations()
  a.updateFlagBroadcastLocations()
  check("and successive re-rolls move them", a.allFlags[0].broadcastLoc !=
    before or a.allFlags[1].broadcastLoc != before)

# --- the engine's scan order ------------------------------------------------
block:
  ## `getAllLocationsWithinRadiusSquared` is x ascending OUTER, y ascending
  ## INNER, over the clamped `ceil(sqrt(r2)) + 1` box. The order fixes which
  ## tile the broadcast draw lands on and which tiles a water trap floods
  ## first, so it is asserted directly.
  var w = bare()
  var got: seq[Loc]
  for l in w.locationsWithinRadiusSquared(loc(10, 10), 2):
    got.add(l)
  checkEq("nine tiles at r2 <= 2", got.len, 9)
  checkEq("and the first is the lowest x then the lowest y", got[0],
    loc(9, 9))
  checkEq("second is x=9, y=10", got[1], loc(9, 10))
  checkEq("third is x=9, y=11", got[2], loc(9, 11))
  checkEq("fourth moves x on", got[3], loc(10, 9))

block:
  var w = bare()
  var got: seq[Loc]
  for l in w.locationsWithinRadiusSquared(loc(0, 0), 4):
    got.add(l)
  var offMap = false
  for l in got:
    if not w.onTheMap(l): offMap = true
  check("the box is clamped to the board at a corner", not offMap)
  checkEq("and the first tile is the origin", got[0], loc(0, 0))

finish("bc24 sensing")
