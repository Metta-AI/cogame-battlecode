## bc24 combat: the FLOAT32 damage and heal tables at every level with and
## without their upgrades, asserted against the committed
## `data/bc24/skills.json` (which CI regenerates from the released jar's own
## classes and byte-diffs), plus every attack and heal precondition and the
## thirty-crumb kill bounty's territory test.

import std/[json, os]
import harness
import bc24_fixture
import battlecode/years/bc24/skills

let table = parseJson(readFile(dataRoot() / "bc24" / "skills.json"))

proc row(key: string): seq[int] =
  for v in table[key]: result.add(v.getInt())

# --- the two float32 tables, over their whole domain ------------------------
block:
  let dmg = row("damage")
  let dmgUp = row("damage_upgraded")
  let heal = row("heal")
  let healUp = row("heal_upgraded")
  checkEq("the committed damage table is the note's", dmg,
    @[150, 158, 161, 165, 195, 203, 240])
  checkEq("the committed heal table is the note's", heal,
    @[80, 82, 84, 86, 88, 92, 100])
  for level in 0 .. 6:
    checkEq("damage at level " & $level, damageFor(level, false), dmg[level])
    checkEq("damage +ATTACK at level " & $level, damageFor(level, true),
      dmgUp[level])
    checkEq("heal at level " & $level, healFor(level, false), heal[level])
    checkEq("heal +HEALING at level " & $level, healFor(level, true),
      healUp[level])
  ## THE DESIGN NOTE'S OWN TABLE IS WRONG IN ONE CELL and the engine is right:
  ## 210 * 1.05f is 220.49999... in float32, so `Math.round(float)` gives 220,
  ## not the note's 221. The generated table and this assertion follow the
  ## engine.
  checkEq("damage +ATTACK at level 1 is 220, not the note's 221",
    damageFor(1, true), 220)

# --- attack preconditions ---------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let a = w.placeDuck(teamA, loc(5, 5))
  let b = w.placeDuck(teamB, loc(6, 5))
  check("an enemy at r2 = 1 is attackable", w.canAttack(a, loc(6, 5)))
  check("an empty tile is not", not w.canAttack(a, loc(5, 6)))
  let friend = w.placeDuck(teamA, loc(4, 5))
  check("a friendly duck is not", not w.canAttack(a, loc(4, 5)))
  check("(the friend is there)", friend.spawned)
  check("r2 = 5 is out of range", not w.canAttack(a, loc(7, 6)))
  a.actionCooldown = 10
  check("and the action counter gates it", not w.canAttack(a, loc(6, 5)))
  a.actionCooldown = 0
  w.currentRound = SetupRounds
  check("attacking is ILLEGAL during setup", not w.canAttack(a, loc(6, 5)))
  w.currentRound = SetupRounds + 1
  check("and legal the round after", w.canAttack(a, loc(6, 5)))
  let f = w.ownFlags(teamB)[0]
  w.removeFlagAt(f.loc, f)
  a.flag = f
  f.carriedBy = a.id
  check("a carrier cannot attack", not w.canAttack(a, loc(6, 5)))
  a.flag = nil
  checkEq("(the victim is still whole)", b.health, DefaultHealth)

block:
  var w = bare()
  w.postSetup()
  let a = w.placeDuck(teamA, loc(5, 5))
  let b = w.placeDuck(teamB, loc(6, 5))
  w.doAttack(a, loc(6, 5))
  checkEq("level-0 damage lands", b.health, DefaultHealth - 150)
  checkEq("the attack cooldown is charged", a.actionCooldown,
    attackCooldownFor(0))
  checkEq("and the attacker gained one attack XP", a.attackExp, 1)

# --- the kill bounty --------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  ## x < 15 is A's territory and x > 15 is B's, because the dam column splits
  ## the flood fill.
  checkEq("A owns the left half", w.getTeamSide(loc(5, 5)), 1)
  checkEq("B owns the right half", w.getTeamSide(loc(25, 5)), 2)
  let a = w.placeDuck(teamA, loc(25, 5))
  let b = w.placeDuck(teamB, loc(26, 5))
  b.health = 40
  let before = w.getCrumbs(teamA)
  w.doAttack(a, loc(26, 5))
  check("the victim died", not b.spawned)
  checkEq("thirty crumbs for a kill on ENEMY ground",
    w.getCrumbs(teamA) - before, KillCrumbReward)

block:
  var w = bare()
  w.postSetup()
  let a = w.placeDuck(teamA, loc(5, 5))
  let b = w.placeDuck(teamB, loc(6, 5))
  b.health = 40
  let before = w.getCrumbs(teamA)
  w.doAttack(a, loc(6, 5))
  check("the victim died", not b.spawned)
  checkEq("but NOTHING is paid for a kill on our own ground",
    w.getCrumbs(teamA) - before, 0)

block:
  var w = bare()
  w.postSetup()
  let a = w.placeDuck(teamA, loc(25, 5))
  let b = w.placeDuck(teamB, loc(26, 5))
  let before = w.getCrumbs(teamA)
  w.doAttack(a, loc(26, 5))
  check("the victim survived", b.spawned)
  checkEq("and a non-killing blow pays nothing",
    w.getCrumbs(teamA) - before, 0)

# --- heal preconditions -----------------------------------------------------
block:
  var w = bare()
  let a = w.placeDuck(teamA, loc(5, 5))
  let b = w.placeDuck(teamA, loc(6, 5))
  w.currentRound = 40
  check("healing IS legal during setup", not w.canHeal(a, loc(6, 5)))
  b.health = 500
  check("...once the target is wounded", w.canHeal(a, loc(6, 5)))
  check("self-healing is never legal", not w.canHeal(a, loc(5, 5)))
  let e = w.placeDuck(teamB, loc(4, 5))
  check("an enemy cannot be healed", not w.canHeal(a, loc(4, 5)))
  check("(the enemy is there)", e.spawned)
  b.health = DefaultHealth
  check("a duck at full health cannot be healed", not w.canHeal(a, loc(6, 5)))

block:
  var w = bare()
  w.postSetup()
  let a = w.placeDuck(teamA, loc(5, 5))
  let b = w.placeDuck(teamA, loc(6, 5))
  b.health = 500
  w.doHeal(a, loc(6, 5))
  checkEq("level-0 heal is 80", b.health, 580)
  checkEq("the heal cooldown is charged", a.actionCooldown, healCooldownFor(0))
  checkEq("and the healer gained one heal XP", a.healExp, 1)
  b.health = DefaultHealth - 10
  a.actionCooldown = 0
  w.doHeal(a, loc(6, 5))
  checkEq("healing is capped at 1000", b.health, DefaultHealth)

block:
  var w = bare()
  w.postSetup()
  w.stats.upgrades[ord(teamA)][2] = true
  let a = w.placeDuck(teamA, loc(5, 5))
  let b = w.placeDuck(teamA, loc(6, 5))
  b.health = 500
  w.doHeal(a, loc(6, 5))
  checkEq("+HEALING makes the level-0 heal 130", b.health, 630)

block:
  var w = bare()
  w.postSetup()
  w.stats.upgrades[ord(teamA)][0] = true
  let a = w.placeDuck(teamA, loc(5, 5))
  let b = w.placeDuck(teamB, loc(6, 5))
  w.doAttack(a, loc(6, 5))
  checkEq("+ATTACK makes the level-0 blow 210", b.health, DefaultHealth - 210)

finish("bc24 combat")
