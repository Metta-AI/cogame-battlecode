## bc24 cooldowns: the two counters, the ten-per-turn decay, the strictly-under
## -ten legality test, the flag-carry charge, the drop's flat +10 movement, the
## stun trap SETTING both counters to 40 rather than adding, and the fact that
## `spawn()` resets neither.

import harness
import bc24_fixture
import battlecode/years/bc24/[traps, flags]

# --- the decay runs for jailed ducks too ------------------------------------
block:
  var w = bare()
  let r = w.robots[0]
  r.actionCooldown = 25
  r.movementCooldown = 14
  r.spawnCooldown = 250
  w.processBeginningOfTurn(r)
  checkEq("action decays by exactly 10", r.actionCooldown, 15)
  checkEq("movement decays by exactly 10", r.movementCooldown, 4)
  checkEq("spawn decays by exactly 10", r.spawnCooldown, 240)
  check("and the duck is not spawned", not r.spawned)
  for _ in 0 .. 3:
    w.processBeginningOfTurn(r)
  checkEq("action floors at 0", r.actionCooldown, 0)
  checkEq("movement floors at 0", r.movementCooldown, 0)

block:
  var w = bare()
  let r = w.robots[0]
  checkEq("a fresh duck starts at the cooldown LIMIT, not zero",
    r.actionCooldown, CooldownLimit)
  checkEq("both counters", r.movementCooldown, CooldownLimit)
  checkEq("and the spawn counter starts at zero", r.spawnCooldown, 0)
  check("so it cannot act before its first beginning-of-turn",
    not r.canActCooldown())
  check("nor move", not r.canMoveCooldown())
  check("but it CAN spawn", r.canSpawnCooldown())

# --- the legality test is STRICTLY under ten --------------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  r.actionCooldown = 9
  check("9 is ready", r.canActCooldown())
  r.actionCooldown = 10
  check("10 is NOT ready", not r.canActCooldown())
  r.movementCooldown = 9
  check("9 is movable", r.canMoveCooldown())
  r.movementCooldown = 10
  check("10 is not", not r.canMoveCooldown())
  check("and a move is refused at 10", not w.canMove(r, dEast))

# --- the flag-carry charge --------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  w.doMove(r, dEast)
  checkEq("a plain move charges +10", r.movementCooldown, MovementCooldown)

block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  let f = w.ownFlags(teamB)[0]
  w.removeFlagAt(f.loc, f)
  r.flag = f
  f.carriedBy = r.id
  f.loc = r.loc
  w.doMove(r, dEast)
  checkEq("carrying a flag charges +20", r.movementCooldown,
    FlagMovementCooldown)
  checkEq("and the flag came along", f.loc, r.loc)

block:
  var w = bare()
  w.postSetup()
  w.stats.upgrades[ord(teamA)][1] = true       ## CAPTURING
  let r = w.placeDuck(teamA, loc(5, 5))
  let f = w.ownFlags(teamB)[0]
  w.removeFlagAt(f.loc, f)
  r.flag = f
  f.carriedBy = r.id
  f.loc = r.loc
  w.doMove(r, dEast)
  checkEq("with CAPTURING it is 20 - 8 = 12", r.movementCooldown,
    FlagMovementCooldown + UpgradeSpecs[ugCapturing].movementDelayChange)

block:
  ## `dropFlag` charges +10 ACTION and then calls `addMovementCooldownTurns`,
  ## which by then sees `hasFlag() == false` -- so the movement charge is a
  ## flat +10 even though the duck was carrying a moment earlier.
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  let f = w.ownFlags(teamB)[0]
  w.removeFlagAt(f.loc, f)
  r.flag = f
  f.carriedBy = r.id
  f.loc = r.loc
  w.dropFlag(r, r.loc)
  checkEq("drop charges +10 action", r.actionCooldown, PickupDropCooldown)
  checkEq("and a FLAT +10 movement, not 20", r.movementCooldown,
    MovementCooldown)
  check("the flag is on the tile", w.hasFlagAt(loc(5, 5)))
  check("and the duck is empty-handed", not r.hasFlag())

# --- a stun trap SETS both counters -----------------------------------------
block:
  var w = bare()
  w.postSetup()
  let builder = w.placeDuck(teamA, loc(5, 5))
  w.addCrumbs(teamA, 1000)
  w.buildTrap(builder, tkStun, loc(6, 5))
  check("the stun trap is down", w.hasTrap(loc(6, 5)))
  let victim = w.placeDuck(teamB, loc(7, 5))
  victim.actionCooldown = 3
  victim.movementCooldown = 3
  let trap = w.getTrap(loc(6, 5))
  w.triggerTrap(trap, victim, true)
  checkEq("stun SETS the action counter to 40", victim.actionCooldown, 40)
  checkEq("and SETS the movement counter to 40", victim.movementCooldown, 40)
  check("the trap is gone from its tile", not w.hasTrap(loc(6, 5)))

block:
  var w = bare()
  w.postSetup()
  let builder = w.placeDuck(teamA, loc(5, 5))
  w.addCrumbs(teamA, 1000)
  w.buildTrap(builder, tkStun, loc(6, 5))
  let friend = w.placeDuck(teamA, loc(7, 5))
  friend.actionCooldown = 3
  w.triggerTrap(w.getTrap(loc(6, 5)), friend, true)
  checkEq("a stun never touches its OWNER's ducks", friend.actionCooldown, 3)

# --- spawn() does NOT reset either counter ----------------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.robots[0]
  r.actionCooldown = 7
  r.movementCooldown = 4
  r.spawnCooldown = 0
  w.doSpawn(r, loc(3, 3))
  check("the duck spawned", r.spawned)
  checkEq("spawn() does NOT reset the action counter (the engine's two " &
    "lines are commented out)", r.actionCooldown, 7)
  checkEq("nor the movement counter", r.movementCooldown, 4)
  checkEq("health is restored", r.health, DefaultHealth)
  checkEq("and roundsAlive restarts", r.roundsAlive, 0)

finish("bc24 cooldowns")
