## bc24 specialisation: the XP thresholds, `getLevel`'s boundaries, THE
## MASTERY RULE exactly as `incrementSkill` writes it, the fact that FILLING
## EARNS NO BUILD XP while digging and trap-building do, the jail penalty's
## attack -> build -> heal tiebreak, and THE TWO ROUNDING REGIMES asserted on
## values where they disagree.

import std/[json, os]
import harness
import bc24_fixture
import battlecode/years/bc24/[skills, traps]

let table = parseJson(readFile(dataRoot() / "bc24" / "skills.json"))
proc row(key: string): seq[int] =
  for v in table[key]: result.add(v.getInt())

# --- thresholds and level boundaries ----------------------------------------
block:
  checkEq("attack thresholds", row("attack_xp"), @[0, 15, 30, 45, 75, 110, 150])
  checkEq("build thresholds", row("build_xp"), @[0, 5, 10, 15, 20, 25, 30])
  checkEq("heal thresholds", row("heal_xp"), @[0, 20, 40, 70, 100, 140, 180])
  for skill in SkillKind:
    for level in 1 .. 6:
      let need = experienceFor(skill, level)
      checkEq($skill & " one below " & $level, levelFor(skill, need - 1),
        level - 1)
      checkEq($skill & " exactly at " & $level, levelFor(skill, need), level)
  checkEq("zero XP is level 0", levelFor(skAttack, 0), 0)
  checkEq("and it saturates at 6", levelFor(skAttack, 100000), 6)

# --- the mastery rule -------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  ## Drive attack to level 4, then prove build and heal freeze at 3.
  r.attackExp = experienceFor(skAttack, 4)
  checkEq("attack is level 4", r.levelOf(skAttack), 4)
  r.buildExp = experienceFor(skBuild, 3)
  for _ in 0 .. 30:
    w.incrementSkill(r, skBuild)
  checkEq("build FREEZES at its level-3 threshold once another skill is 4",
    r.buildExp, experienceFor(skBuild, 3))
  checkEq("so build stays level 3", r.levelOf(skBuild), 3)
  r.healExp = experienceFor(skHeal, 3)
  for _ in 0 .. 30:
    w.incrementSkill(r, skHeal)
  checkEq("heal freezes too", r.healExp, experienceFor(skHeal, 3))
  for _ in 0 .. 200:
    w.incrementSkill(r, skAttack)
  checkEq("the MASTERED skill keeps climbing to 6", r.levelOf(skAttack), 6)

block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  ## Below its own level-3 threshold a skill always gains, even with a
  ## level-4 sibling: the engine's condition is an OR.
  r.attackExp = experienceFor(skAttack, 5)
  r.buildExp = experienceFor(skBuild, 3) - 1
  w.incrementSkill(r, skBuild)
  checkEq("under its own level-3 threshold it still gains", r.buildExp,
    experienceFor(skBuild, 3))

# --- fill earns no build XP -------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  w.addCrumbs(teamA, 1000)
  let r = w.placeDuck(teamA, loc(5, 5))
  w.doDig(r, loc(6, 5))
  checkEq("digging earns one build XP", r.buildExp, 1)
  check("and the tile is water", w.getWater(loc(6, 5)))
  r.actionCooldown = 0
  w.doFill(r, loc(6, 5))
  checkEq("FILLING EARNS NO BUILD XP (patch 1.1.0)", r.buildExp, 1)
  check("but it did fill", not w.getWater(loc(6, 5)))
  r.actionCooldown = 0
  w.buildTrap(r, tkStun, loc(6, 5))
  checkEq("building a trap earns one build XP", r.buildExp, 2)

# --- the jail penalty's tiebreak --------------------------------------------
block:
  var w = bare()
  let r = w.robots[0]
  r.attackExp = 45      ## level 3
  r.buildExp = 15       ## level 3
  r.healExp = 70        ## level 3
  r.jailedPenalty()
  checkEq("a three-way tie goes to ATTACK", r.attackExp,
    45 + penaltyFor(skAttack, 3))
  checkEq("build untouched", r.buildExp, 15)
  checkEq("heal untouched", r.healExp, 70)

block:
  var w = bare()
  let r = w.robots[0]
  r.attackExp = 0
  r.buildExp = 15       ## level 3
  r.healExp = 70        ## level 3
  r.jailedPenalty()
  checkEq("a build/heal tie goes to BUILD", r.buildExp,
    15 + penaltyFor(skBuild, 3))
  checkEq("heal untouched", r.healExp, 70)

block:
  var w = bare()
  let r = w.robots[0]
  r.attackExp = 0
  r.buildExp = 0
  r.healExp = 70
  r.jailedPenalty()
  checkEq("heal alone takes it", r.healExp, 70 + penaltyFor(skHeal, 3))

block:
  var w = bare()
  let r = w.robots[0]
  r.attackExp = 1
  r.jailedPenalty()
  checkEq("the penalty clamps at zero", r.attackExp, 0)

block:
  var w = bare()
  let r = w.robots[0]
  r.jailedPenalty()
  checkEq("all-zero experience skips the penalty entirely",
    r.attackExp + r.buildExp + r.healExp, 0)

# --- the two rounding regimes, on values where they DISAGREE ----------------
block:
  ## `Math.round(float)` and `Math.round(double)` are different methods. At
  ## attack level 1 with the ATTACK upgrade the float32 product is
  ## 220.49999... and rounds DOWN; the float64 product is 220.5 and rounds UP.
  let f32 = damageFor(1, true)
  let f64 = javaRoundF64(210.0 * (1.0 + 0.01 * 5.0))
  checkEq("the float32 regime gives 220", f32, 220)
  checkEq("a float64 product would give 221", f64, 221)
  check("so the two regimes really do disagree here", f32 != f64)

block:
  ## Every cooldown and every crumb cost is the FLOAT64 regime, and the
  ## committed table is the record.
  for level in 0 .. 6:
    checkEq("attack cooldown " & $level, attackCooldownFor(level),
      row("attack_cooldown")[level])
    checkEq("heal cooldown " & $level, healCooldownFor(level),
      row("heal_cooldown")[level])
    checkEq("dig cost " & $level, digCostFor(level), row("dig_cost")[level])
    checkEq("fill cost " & $level, fillCostFor(level), row("fill_cost")[level])
    checkEq("dig cooldown " & $level, digCooldownFor(level),
      row("dig_cooldown")[level])
    checkEq("fill cooldown " & $level, fillCooldownFor(level),
      row("fill_cooldown")[level])
    checkEq("explosive cost " & $level, trapCostFor(tkExplosive, level),
      row("explosive_cost")[level])
    checkEq("stun cost " & $level, trapCostFor(tkStun, level),
      row("stun_cost")[level])
    checkEq("water cost " & $level, trapCostFor(tkWater, level),
      row("water_cost")[level])
    checkEq("trap cooldown " & $level, trapCooldownFor(tkExplosive, level),
      row("trap_cooldown")[level])
  checkEq("dig costs fall 20..10 with build level", row("dig_cost"),
    @[20, 18, 17, 16, 14, 12, 10])
  checkEq("an explosive falls 200..100", row("explosive_cost"),
    @[200, 180, 170, 160, 140, 120, 100])
  checkEq("and the trap build cooldown falls 5..3", row("trap_cooldown"),
    @[5, 5, 5, 4, 4, 4, 3])

# --- Math.round's two carve-outs --------------------------------------------
block:
  checkEq("Math.round(float) special-cases the greatest value below 0.5",
    javaRoundF32(GreatestFloat32BelowHalf), 0)
  checkEq("and Math.round(double) does the same",
    javaRoundF64(GreatestFloat64BelowHalf), 0)
  checkEq("0.5 rounds up", javaRoundF64(0.5), 1)
  checkEq("-0.5 rounds toward positive infinity", javaRoundF64(-0.5), 0)

finish("bc24 levels and specialisation")
