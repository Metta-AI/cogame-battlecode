## The bc24 skill system: experience, levels, the mastery rule, the jail
## penalty — and THE TWO ROUNDING REGIMES, which are the whole point of this
## file.
##
## Read them off `common/SkillType.java`, `world/InternalRobot.java` and
## `world/RobotControllerImpl.java` at the pinned commit, not off the spec:
##
## * **Damage and heal are a Java `float`.** `InternalRobot.getDamage()` is
##   `Math.round(base * ((float) skillEffect / 100 + 1))`: `(float) pct / 100`
##   is a FLOAT32 quotient, `+ 1` a float32 sum, `base * …` a float32 product,
##   and `Math.round(float)` the float overload.
## * **Every cooldown and every crumb cost is a Java `double`.**
##   `attack`/`heal`/`build`/`dig`/`fill` all compute
##   `(int) Math.round(C * (1 + .01 * pct))`, where `.01` is a `double`
##   literal — a FLOAT64 product through `Math.round(double)`.
##
## The two disagree, and `data/bc24/skills.json` (regenerated in CI from the
## released jar's own classes and byte-diffed) is the record of where.
##
## `Math.round` UNDER JDK 8 is not "round half away from zero": it is
## `(a != <greatest value below 0.5>) ? floor(a + 0.5) : 0`, with the ADDITION
## PERFORMED AT THE ARGUMENT'S OWN WIDTH. The float overload therefore adds
## `0.5f` in float32 before flooring. Both are reproduced literally; the
## `parity-oracle-bc24` job proves the whole finite domain agrees.

import std/math
import constants

export constants

const
  GreatestFloat32BelowHalf* = 0.49999997019767761'f32
    ## `0x1.fffffep-2f`, the special case `Math.round(float)` carves out.
  GreatestFloat64BelowHalf* = 0.49999999999999994'f64
    ## `0x1.fffffffffffffp-2`, the special case `Math.round(double)` carves out.

func javaRoundF32*(a: float32): int =
  ## `java.lang.Math.round(float)`, JDK 8. The `a + 0.5f` is a FLOAT32 add.
  if a == GreatestFloat32BelowHalf: return 0
  int(floor(float64(a + 0.5'f32)))

func javaRoundF64*(a: float64): int =
  ## `java.lang.Math.round(double)`, JDK 8.
  if a == GreatestFloat64BelowHalf: return 0
  int(floor(a + 0.5'f64))

# ---------------------------------------------------------------------------
#  Experience and levels
# ---------------------------------------------------------------------------

func experienceFor*(skill: SkillKind, level: int): int =
  ## `SkillType.getExperience(level)`.
  SkillSpecs[skill].experience[level]

func levelFor*(skill: SkillKind, exp: int): int =
  ## `InternalRobot.getLevel`: `for i in 0..5: if exp < experience(i+1): i`,
  ## else 6. (`SkillType.getLevel` is the same function written the other way
  ## round; the engine calls the InternalRobot one everywhere it matters.)
  for i in 0 .. 5:
    if exp < SkillSpecs[skill].experience[i + 1]:
      return i
  6

func penaltyFor*(skill: SkillKind, level: int): int =
  SkillSpecs[skill].penalty[level]

func effectPct*(skill: SkillKind, level: int): int =
  SkillSpecs[skill].effectDelta[level]

func cooldownPct*(skill: SkillKind, level: int): int =
  SkillSpecs[skill].cooldownDelta[level]

# ---------------------------------------------------------------------------
#  Regime 1 — FLOAT32: damage and heal
# ---------------------------------------------------------------------------

func damageFor*(attackLevel: int, upgraded: bool): int =
  ## `InternalRobot.getDamage()`.
  var base = SkillSpecs[skAttack].skillEffect
  if upgraded: base += UpgradeSpecs[ugAttack].baseAttackChange
  javaRoundF32(float32(base) *
    (float32(effectPct(skAttack, attackLevel)) / 100'f32 + 1'f32))

func healFor*(healLevel: int, upgraded: bool): int =
  ## `InternalRobot.getHeal()`.
  var base = SkillSpecs[skHeal].skillEffect
  if upgraded: base += UpgradeSpecs[ugHealing].baseHealChange
  javaRoundF32(float32(base) *
    (float32(effectPct(skHeal, healLevel)) / 100'f32 + 1'f32))

# ---------------------------------------------------------------------------
#  Regime 2 — FLOAT64: every cooldown and every crumb cost
# ---------------------------------------------------------------------------

func scaledCooldown*(base: int, skill: SkillKind, level: int): int =
  ## `(int) Math.round(C * (1 + .01 * SkillType.X.getCooldown(level)))`.
  javaRoundF64(float64(base) * (1.0 + 0.01 * float64(cooldownPct(skill, level))))

func scaledCost*(base: int, buildLevel: int): int =
  ## `(int) Math.round(C * (1 + 0.01 * SkillType.BUILD.getSkillEffect(level)))`.
  ## BUILD's `getSkillEffect` is NEGATIVE, so this makes things cheaper.
  javaRoundF64(float64(base) *
    (1.0 + 0.01 * float64(effectPct(skBuild, buildLevel))))

func attackCooldownFor*(attackLevel: int): int =
  scaledCooldown(AttackCooldown, skAttack, attackLevel)

func healCooldownFor*(healLevel: int): int =
  scaledCooldown(HealCooldown, skHeal, healLevel)

func digCooldownFor*(buildLevel: int): int =
  scaledCooldown(DigCooldown, skBuild, buildLevel)

func fillCooldownFor*(buildLevel: int): int =
  scaledCooldown(FillCooldown, skBuild, buildLevel)

func trapCooldownFor*(trap: TrapKind, buildLevel: int): int =
  scaledCooldown(TrapSpecs[trap].actionCooldownIncrease, skBuild, buildLevel)

func digCostFor*(buildLevel: int): int = scaledCost(DigCost, buildLevel)
func fillCostFor*(buildLevel: int): int = scaledCost(FillCost, buildLevel)
func trapCostFor*(trap: TrapKind, buildLevel: int): int =
  scaledCost(TrapSpecs[trap].buildCost, buildLevel)
