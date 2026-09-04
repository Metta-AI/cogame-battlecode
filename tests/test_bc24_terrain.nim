## bc24 terrain: dig and fill legality, their build-level prices and cooldowns,
## every refusal `assertCanDig` carries, the dam that is impassable through
## round 200 and plain diggable land after it, crumbs collected by the MOVER
## with the pile cleared, and the `amount < 100 -> x10` conversion applied ONCE
## at conversion time.

import std/[json, strutils]
import harness
import bc24_fixture

# --- dig legality -----------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  check("no crumbs, no dig", not w.canDig(r, loc(6, 5)))
  w.addCrumbs(teamA, DigCost)
  check("exactly the price is enough", w.canDig(r, loc(6, 5)))
  check("r2 = 5 is out of the interact radius", not w.canDig(r, loc(7, 6)))
  w.water[w.idx(loc(6, 4))] = true
  check("water cannot be dug", not w.canDig(r, loc(6, 4)))
  w.walls[w.idx(loc(4, 4))] = true
  check("a wall cannot be dug", not w.canDig(r, loc(4, 4)))
  let onSpawn = w.placeDuck(teamA, loc(3, 3))
  check("(the spawn-zone duck is there)", onSpawn.spawned)
  let s = w.placeDuck(teamA, loc(3, 4))
  check("a spawn zone can NEVER be dug", not w.canDig(s, loc(3, 3)))
  let blocker = w.placeDuck(teamB, loc(6, 6))
  check("an occupied tile cannot be dug", not w.canDig(r, loc(6, 6)))
  check("(the blocker is there)", blocker.spawned)
  r.actionCooldown = 10
  check("the action counter gates it", not w.canDig(r, loc(6, 5)))

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 1000)
  let f = w.ownFlags(teamA)[0]
  w.moveFlagSetStartLoc(f, loc(6, 5))
  let r = w.placeDuck(teamA, loc(5, 5))
  check("a tile with a flag on it cannot be dug", not w.canDig(r, loc(6, 5)))

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 1000)
  w.layTrap(teamA, tkStun, loc(6, 5))
  let r = w.placeDuck(teamA, loc(5, 5))
  check("a tile with a FRIENDLY trap cannot be dug", not w.canDig(r, loc(6, 5)))

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamB, 1000)
  w.layTrap(teamB, tkExplosive, loc(6, 5))
  w.addCrumbs(teamA, 1000)
  let r = w.placeDuck(teamA, loc(5, 5))
  check("but an ENEMY explosive does not stop the dig",
    w.canDig(r, loc(6, 5)))
  w.doDig(r, loc(6, 5))
  checkEq("it queues as an INTERACT trigger", r.trapsToTrigger.len, 1)
  checkEq("with entered = false", r.enteredTraps[0], false)

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 1000)
  let r = w.placeDuck(teamA, loc(5, 5))
  let f = w.ownFlags(teamB)[0]
  w.removeFlagAt(f.loc, f)
  r.flag = f
  f.carriedBy = r.id
  check("a carrier cannot dig", not w.canDig(r, loc(6, 5)))
  check("nor fill", not w.canFill(r, loc(6, 5)))

# --- prices and cooldowns ---------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 1000)
  let r = w.placeDuck(teamA, loc(5, 5))
  let before = w.getCrumbs(teamA)
  w.doDig(r, loc(6, 5))
  checkEq("a level-0 dig costs 20", before - w.getCrumbs(teamA), DigCost)
  checkEq("and charges 20 action cooldown", r.actionCooldown, DigCooldown)
  check("the tile is water", w.getWater(loc(6, 5)))
  checkEq("and it counted", w.stats.tilesDug[0], 1)

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 1000)
  let r = w.placeDuck(teamA, loc(5, 5))
  r.buildExp = experienceFor(skBuild, 6)
  let before = w.getCrumbs(teamA)
  w.doDig(r, loc(6, 5))
  checkEq("a level-6 dig costs 10", before - w.getCrumbs(teamA), 10)
  checkEq("and charges 10", r.actionCooldown, 10)

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 1000)
  let r = w.placeDuck(teamA, loc(5, 5))
  w.water[w.idx(loc(6, 5))] = true
  check("only water can be filled", w.canFill(r, loc(6, 5)))
  check("land cannot", not w.canFill(r, loc(6, 6)))
  let before = w.getCrumbs(teamA)
  w.doFill(r, loc(6, 5))
  checkEq("a level-0 fill costs 30", before - w.getCrumbs(teamA), FillCost)
  checkEq("and charges 30", r.actionCooldown, FillCooldown)
  check("the tile is land", not w.getWater(loc(6, 5)))
  checkEq("and it counted", w.stats.tilesFilled[0], 1)

# --- the dam ----------------------------------------------------------------
block:
  var w = bare()
  w.currentRound = SetupRounds
  check("the dam is up at round 200", w.getDam(loc(DamColumn, 5)))
  check("and impassable", not w.isPassable(loc(DamColumn, 5)))
  w.currentRound = SetupRounds + 1
  check("at round 201 it is gone", not w.getDam(loc(DamColumn, 5)))
  check("and passable", w.isPassable(loc(DamColumn, 5)))
  w.addCrumbs(teamA, 1000)
  let r = w.placeDuck(teamA, loc(DamColumn - 1, 5))
  check("and it is ordinary diggable land", w.canDig(r, loc(DamColumn, 5)))

block:
  var w = bare()
  w.currentRound = 100
  let r = w.placeDuck(teamA, loc(DamColumn - 1, 5))
  check("a duck cannot walk through the dam during setup",
    not w.canMove(r, dEast))
  w.currentRound = SetupRounds + 1
  check("and can the round after", w.canMove(r, dEast))

# --- crumbs -----------------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  w.crumbTiles[w.idx(loc(6, 5))] = 250
  let r = w.placeDuck(teamA, loc(5, 5))
  let before = w.getCrumbs(teamA)
  w.doMove(r, dEast)
  checkEq("the MOVER banks the whole pile", w.getCrumbs(teamA) - before, 250)
  checkEq("and the tile is cleared", w.getCrumbAmount(loc(6, 5)), 0)
  r.movementCooldown = 0
  let after = w.getCrumbs(teamA)
  w.doMove(r, dWest)
  w.doMove(r, dEast)
  checkEq("walking back over it pays nothing", w.getCrumbs(teamA) - after, 0)

block:
  ## `GameMapIO.Serial.deserialize` multiplies any pile below 100 by ten, and
  ## the converter applies it ONCE, at conversion time. Every shipped bc24 map
  ## is therefore free of sub-100 piles.
  var offenders: seq[string]
  for name in @SmallPool & @MixedPool & @LargePool:
    let doc = parseJson(readFile(mapPath(name)))
    for c in doc["crumbs"]:
      if c[2].getInt() < 100 and c[2].getInt() != 0:
        offenders.add(name & ":" & $c[2].getInt())
  checkEq("no committed bc24 map carries a sub-100 pile (the x10 rule is " &
    "applied at conversion time, once)", offenders.join(","), "")

finish("bc24 terrain")
