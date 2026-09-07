## bc24 traps: build legality at the build-level price, the enemy-explosive
## cancellation that still spends the crumbs and the cooldown, the trigger
## index over `triggerRadius`, firing at the END of the triggering duck's turn
## in queue order, the enter-versus-interact radius and damage split, stun's
## r2 <= 13, the water trap's flood set in engine scan order, de-registration
## over r2 <= 2, and the fact that enemy traps are invisible.

import harness
import bc24_fixture
import battlecode/years/bc24/[traps, skills]

# --- build legality ---------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  check("no crumbs, no trap", not w.canBuildTrap(r, tkStun, loc(6, 5)))
  w.addCrumbs(teamA, trapCostFor(tkStun, 0) - 1)
  check("one crumb short is still no", not w.canBuildTrap(r, tkStun, loc(6, 5)))
  w.addCrumbs(teamA, 1)
  check("exactly the price is enough", w.canBuildTrap(r, tkStun, loc(6, 5)))
  check("r2 = 5 is out of the interact radius",
    not w.canBuildTrap(r, tkStun, loc(7, 6)))
  r.actionCooldown = 10
  check("the action counter gates it", not w.canBuildTrap(r, tkStun, loc(6, 5)))
  r.actionCooldown = 0
  let e = w.placeDuck(teamB, loc(7, 5))
  check("no trap within r2 <= 2 of an ENEMY duck",
    not w.canBuildTrap(r, tkStun, loc(6, 5)))
  check("(the enemy is there)", e.spawned)
  w.despawnRobot(e)
  check("and it is legal again once the enemy is gone",
    w.canBuildTrap(r, tkStun, loc(6, 5)))

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  let r = w.placeDuck(teamA, loc(5, 5))
  w.water[w.idx(loc(6, 5))] = true
  check("an EXPLOSIVE may sit on water",
    w.canBuildTrap(r, tkExplosive, loc(6, 5)))
  check("a STUN may not", not w.canBuildTrap(r, tkStun, loc(6, 5)))
  check("nor a WATER trap", not w.canBuildTrap(r, tkWater, loc(6, 5)))
  w.walls[w.idx(loc(4, 5))] = true
  check("nobody may build on a wall",
    not w.canBuildTrap(r, tkExplosive, loc(4, 5)))

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  let r = w.placeDuck(teamA, loc(5, 5))
  w.buildTrap(r, tkStun, loc(6, 5))
  r.actionCooldown = 0
  check("a friendly trap blocks a second one on the same tile",
    not w.canBuildTrap(r, tkStun, loc(6, 5)))

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  let r = w.placeDuck(teamA, loc(5, 5))
  let f = w.ownFlags(teamB)[0]
  w.removeFlagAt(f.loc, f)
  r.flag = f
  f.carriedBy = r.id
  check("a carrier cannot build", not w.canBuildTrap(r, tkStun, loc(6, 5)))

# --- the price and the cooldown are the BUILD-LEVEL ones --------------------
block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  let r = w.placeDuck(teamA, loc(5, 5))
  r.buildExp = experienceFor(skBuild, 6)
  let before = w.getCrumbs(teamA)
  w.buildTrap(r, tkExplosive, loc(6, 5))
  checkEq("a level-6 builder pays 100 for an explosive, not 200",
    before - w.getCrumbs(teamA), 100)
  checkEq("and the build cooldown is 3, not 5", r.actionCooldown, 3)

# --- the enemy-explosive cancellation ---------------------------------------
block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  w.addCrumbs(teamB, 5000)
  let b = w.placeDuck(teamB, loc(9, 5))
  w.buildTrap(b, tkExplosive, loc(8, 5))
  check("B's explosive is down", w.hasTrap(loc(8, 5)))
  w.despawnRobot(b)
  let a = w.placeDuck(teamA, loc(7, 5))
  let before = w.getCrumbs(teamA)
  w.buildTrap(a, tkStun, loc(8, 5))
  checkEq("the crumbs are spent anyway", before - w.getCrumbs(teamA),
    trapCostFor(tkStun, 0))
  checkEq("the cooldown is spent anyway", a.actionCooldown,
    trapCooldownFor(tkStun, 0))
  checkEq("no build XP is earned", a.buildExp, 0)
  checkEq("and NOTHING is placed -- B's explosive is still there",
    w.getTrap(loc(8, 5)).team, teamB)
  checkEq("the enemy trap is queued as an INTERACT trigger",
    a.trapsToTrigger.len, 1)
  checkEq("with entered = false", a.enteredTraps[0], false)
  let hp = a.health
  w.processTriggerQueue(a)
  checkEq("and it does the INTERACT damage, 200, not 750", hp - a.health, 200)

# --- the trigger index ------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  let r = w.placeDuck(teamA, loc(5, 5))
  w.buildTrap(r, tkExplosive, loc(6, 5))
  checkEq("an EXPLOSIVE registers on its own tile only (triggerRadius 0)",
    w.trapTriggers[w.idx(loc(6, 5))].len, 1)
  checkEq("not on the neighbour", w.trapTriggers[w.idx(loc(7, 5))].len, 0)

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  let r = w.placeDuck(teamA, loc(5, 5))
  w.buildTrap(r, tkStun, loc(6, 5))
  var registered = 0
  for l in w.locationsWithinRadiusSquared(loc(6, 5), 2):
    if w.trapTriggers[w.idx(l)].len == 1: registered += 1
  checkEq("a STUN registers over its whole r2 <= 2 trigger radius",
    registered, 9)

# --- triggers fire at the END of the turn, in queue order -------------------
block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  w.layTrap(teamA, tkExplosive, loc(6, 5))
  let victim = w.placeDuck(teamB, loc(7, 5))
  w.doMove(victim, dWest)
  checkEq("the trap is queued, not fired", victim.health, DefaultHealth)
  checkEq("one entry in the queue", victim.trapsToTrigger.len, 1)
  checkEq("with entered = true", victim.enteredTraps[0], true)
  w.processTriggerQueue(victim)
  checkEq("and at the end of the turn it fires: 750 off 1000 leaves 250",
    victim.health, 250)
  checkEq("the queue is emptied", victim.trapsToTrigger.len, 0)

block:
  ## Enter damage is 750 inside r2 <= 4; interact damage is 200 inside
  ## r2 <= 2. A duck two tiles away takes the enter damage and nothing from an
  ## interact.
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  w.layTrap(teamA, tkExplosive, loc(6, 5))
  let near = w.placeDuck(teamB, loc(7, 5))
  let mid = w.placeDuck(teamB, loc(8, 5))
  let far = w.placeDuck(teamB, loc(9, 5))
  w.triggerTrap(w.getTrap(loc(6, 5)), near, true)
  checkEq("r2 = 1 takes 750", near.health, 250)
  checkEq("r2 = 4 takes 750 too", mid.health, 250)
  checkEq("r2 = 9 takes nothing", far.health, DefaultHealth)

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  w.layTrap(teamA, tkExplosive, loc(6, 5))
  let near = w.placeDuck(teamB, loc(7, 5))
  let mid = w.placeDuck(teamB, loc(8, 5))
  w.triggerTrap(w.getTrap(loc(6, 5)), near, false)
  checkEq("an INTERACT does 200 at r2 = 1", near.health, DefaultHealth - 200)
  checkEq("and nothing at r2 = 4", mid.health, DefaultHealth)

block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  w.layTrap(teamA, tkStun, loc(6, 5))
  let inner = w.placeDuck(teamB, loc(9, 6))    ## r2 = 3^2 + 1 = 10
  let outer = w.placeDuck(teamB, loc(10, 6))   ## r2 = 4^2 + 1 = 17
  w.triggerTrap(w.getTrap(loc(6, 5)), inner, true)
  checkEq("r2 = 10 is stunned", inner.actionCooldown, 40)
  checkEq("r2 = 17 is not", outer.actionCooldown, 0)

# --- the water trap's flood set ---------------------------------------------
block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  w.layTrap(teamA, tkWater, loc(8, 8))
  let occupant = w.placeDuck(teamB, loc(9, 8))
  w.walls[w.idx(loc(7, 8))] = true
  ## A second friendly trap inside the radius: the flood skips trapped tiles.
  w.layTrap(teamA, tkStun, loc(8, 10))
  w.triggerTrap(w.getTrap(loc(8, 8)), occupant, true)
  check("the flood reached r2 = 9", w.getWater(loc(11, 8)))
  check("it skipped the occupied tile", not w.getWater(loc(9, 8)))
  check("it skipped the wall", not w.getWater(loc(7, 8)))
  check("it skipped the trapped tile", not w.getWater(loc(8, 10)))
  check("and it skipped the spawn zone",
    not w.getWater(loc(3, 3)))
  check("nothing outside r2 = 9", not w.getWater(loc(12, 8)))

# --- de-registration --------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  w.layTrap(teamA, tkStun, loc(6, 5))
  let victim = w.placeDuck(teamB, loc(9, 9))
  w.triggerTrap(w.getTrap(loc(6, 5)), victim, true)
  var left = 0
  for i in 0 ..< w.trapTriggers.len:
    left += w.trapTriggers[i].len
  checkEq("de-registration sweeps r2 <= 2 and leaves nothing", left, 0)
  check("and the tile no longer holds a trap", not w.hasTrap(loc(6, 5)))

# --- enemy traps are invisible ----------------------------------------------
block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 5000)
  let builder = w.placeDuck(teamA, loc(5, 5))
  w.buildTrap(builder, tkStun, loc(6, 5))
  let trap = w.getTrap(loc(6, 5))
  checkEq("the trap knows its owner", trap.team, teamA)
  check("and every 2024 trap is invisible to the opponent",
    TrapSpecs[trap.kind].isInvisible)
  check("as is an explosive", TrapSpecs[tkExplosive].isInvisible)
  check("and a water trap", TrapSpecs[tkWater].isInvisible)

finish("bc24 traps")
