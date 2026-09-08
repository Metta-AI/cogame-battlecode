## PROTOTYPE / TURRET / PORTABLE, `transform` and `mutate`.
##
## §Tests item 5, and the two prose-versus-engine resolutions the file
## `buildings.nim` exists for: a transform charges exactly ONE cooldown counter
## (the prose says both) and a mutation charges the BUILDING 100 on BOTH.

import std/[json, os, strutils]
import harness
import bc22_fixture

let tables = parseJson(readFile(dataRoot() / "bc22" / "tables.json"))

# --- the prototype ----------------------------------------------------------
block:
  for key, want in tables["prototype_health"]:
    checkEq("prototype health of " & key, prototypeHealth(parseInt(key)),
      want.getInt())
  checkEq("a watchtower prototype is 120", prototypeHealth(150), 120)
  checkEq("a laboratory prototype is 80", prototypeHealth(100), 80)
  checkEq("a level-3 archon prototype is 1555", prototypeHealth(1944), 1555)

block:
  var w = bare()
  let lab = w.place(teamA, rtLaboratory, loc(10, 10))
  checkEq("a laboratory spawns as a PROTOTYPE", lab.mode, rmPrototype)
  checkEq("at 80 % of its max health", lab.health, 80)
  check("and can neither act", not lab.canActCooldown())
  check("nor move", not lab.canMoveCooldown())
  check("nor transform", not w.canTransform(lab))
  check("nor be mutated", not lab.canMutateSelf())
  let arch = w.place(teamA, rtArchon, loc(12, 10))
  checkEq("an ARCHON spawns as a TURRET, not a prototype", arch.mode, rmTurret)
  checkEq("at full health", arch.health, 600)

# --- transform: ONE counter -------------------------------------------------
block:
  var w = bare()
  let arch = w.placeLive(teamA, rtArchon, loc(10, 10))
  check("a turret can transform", w.canTransform(arch))
  w.doTransform(arch)
  checkEq("and becomes PORTABLE", arch.mode, rmPortable)
  checkEq("charging 100 to the MOVEMENT counter", arch.movementCooldown, 100)
  checkEq("and NOTHING to the action counter", arch.actionCooldown, 0)
  checkEq("`transformCooldownTurns` reads the mode-appropriate one",
    arch.transformCooldownTurns(), 100)
  check("so it cannot transform back yet", not w.canTransform(arch))
  arch.movementCooldown = 0
  w.doTransform(arch)
  checkEq("back to TURRET", arch.mode, rmTurret)
  checkEq("charging 100 to the ACTION counter this time",
    arch.actionCooldown, 100)
  checkEq("and nothing more to movement", arch.movementCooldown, 0)

block:
  ## Ten of its own turns of doing nothing, on flat ground.
  var w = bare()
  let arch = w.placeLive(teamA, rtArchon, loc(10, 10))
  w.doTransform(arch)
  var turns = 0
  while arch.movementCooldown >= CooldownLimit and turns < 40:
    arch.movementCooldown = max(0, arch.movementCooldown - CooldownsPerTurn)
    inc turns
  checkEq("ten turns before a transformed building moves", turns, 10)

block:
  ## AN ARCHON IS A BUILDING: it transforms to PORTABLE and WALKS at movement
  ## cooldown 24 x rubble.
  var w = bare(rubble = @[(l: loc(11, 10), amount: 20)])
  let arch = w.placeLive(teamA, rtArchon, loc(10, 10))
  w.doTransform(arch)
  arch.movementCooldown = 0
  check("a portable archon can move", w.canMove(arch, dEast))
  w.doMove(arch, dEast)
  checkEq("and pays 24 x the DESTINATION's rubble",
    arch.movementCooldown, cooldownWithMultiplier(24, 20))
  checkEq("landing at 11,10", arch.loc, loc(11, 10))
  check("a TURRET cannot move at all", (block:
    arch.movementCooldown = 0
    w.doTransform(arch)
    arch.movementCooldown = 0
    not w.canMove(arch, dEast)))

# --- mutate -----------------------------------------------------------------
block:
  var w = bare()
  let b = w.place(teamA, rtBuilder, loc(10, 10))
  let lab = w.placeLive(teamA, rtLaboratory, loc(11, 10))
  w.addLead(teamA, 200)
  check("level 2 is a LEAD buy", w.canMutate(b, loc(11, 10)))
  let leadBefore = w.teamLead(teamA)
  w.doMutate(b, loc(11, 10))
  checkEq("it costs 150 lead", leadBefore - w.teamLead(teamA), 150)
  checkEq("the level is 2", lab.level, 2)
  checkEq("and the health rose by exactly the difference",
    lab.health, 100 + (180 - 100))
  b.actionCooldown = 0
  lab.actionCooldown = 0
  lab.movementCooldown = 0
  check("level 3 needs GOLD and there is none",
    not w.canMutate(b, loc(11, 10)))
  w.addGold(teamA, 25)
  check("with 25 gold it is legal", w.canMutate(b, loc(11, 10)))
  w.doMutate(b, loc(11, 10))
  checkEq("the level is 3", lab.level, 3)
  checkEq("the gold is spent", w.teamGold(teamA), 0)
  b.actionCooldown = 0
  lab.actionCooldown = 0
  lab.movementCooldown = 0
  w.addGold(teamA, 500)
  w.addLead(teamA, 500)
  check("and a level-3 building refuses a fourth mutation",
    not w.canMutate(b, loc(11, 10)))

block:
  var w = bare()
  let b = w.place(teamA, rtBuilder, loc(10, 10))
  let droid = w.place(teamA, rtMiner, loc(11, 10))
  let proto = w.place(teamA, rtLaboratory, loc(9, 10))
  w.addLead(teamA, 500)
  check("a DROID refuses mutation", not w.canMutate(b, loc(11, 10)))
  check("and so does a PROTOTYPE", not w.canMutate(b, loc(9, 10)))
  let enemy = w.placeLive(teamB, rtWatchtower, loc(10, 11))
  check("and an ENEMY building", not w.canMutate(b, loc(10, 11)))
  discard droid
  discard proto
  discard enemy

block:
  ## An ARCHON's ladder: 300 Pb to level 2, 80 Au to level 3, and the health
  ## jumps 600 -> 1080 -> 1944.
  var w = bare()
  let b = w.place(teamA, rtBuilder, loc(10, 10))
  let arch = w.placeLive(teamA, rtArchon, loc(11, 10))
  w.addLead(teamA, 400)
  w.addGold(teamA, 100)
  w.doMutate(b, loc(11, 10))
  checkEq("the archon is 1080", arch.health, 1080)
  b.actionCooldown = 0
  arch.actionCooldown = 0
  arch.movementCooldown = 0
  w.doMutate(b, loc(11, 10))
  checkEq("and then 1944", arch.health, 1944)
  checkEq("its repair rises to 6", healingOf(rtArchon, arch.level), 6)

finish("test_bc22_buildings")
