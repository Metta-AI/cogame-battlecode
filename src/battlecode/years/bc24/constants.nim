## Battlecode 2024 "Breadwars" gameplay constants -- GENERATED, do not edit.
##
## Source: github.com/battlecode/battlecode24 at commit `166c79bbf4156c866caf434062cb1f403c01695f`,
## files `common/GameConstants.java`, `common/SkillType.java`,
## `common/TrapType.java` and `common/GlobalUpgrade.java`, read by
## `tools/gen_year_constants.py --year bc24`. The `test` job of
## `.github/workflows/ci.yml` re-runs that generator with `--check`,
## which byte-diffs this file, so an edit here fails the build instead
## of quietly changing the rules under a `GameVersion` that no longer
## describes them.
##
## `SpecVersion` here is MASTER's string. The released oracle jar is
## 3.0.5 and every gameplay constant in it is identical; the
## `parity-oracle-bc24` job proves that rather than assuming it
## (docs/RULES-BC24.md §Divergences item 9).
##
## THE TWO ROUNDING REGIMES are not in this file — they are in
## `skills.nim`, which is the only place that multiplies these tables
## out: damage and heal are a Java FLOAT32 product through
## `Math.round(float)`, and every cooldown and every crumb cost is a
## FLOAT64 product through `Math.round(double)`.

const EngineCommit* = "166c79bbf4156c866caf434062cb1f403c01695f"
const OracleJarVersion* = "3.0.5"

type
  SkillKind* = enum
    skAttack = "ATTACK"
    skBuild = "BUILD"
    skHeal = "HEAL"

  TrapKind* = enum
    tkExplosive = "EXPLOSIVE"
    tkWater = "WATER"
    tkStun = "STUN"
    tkNone = "NONE"

  UpgradeKind* = enum
    ugAttack = "ATTACK"
    ugHealing = "HEALING"
    ugCapturing = "CAPTURING"
    ugAction = "ACTION"

  SkillSpec* = object
    ## `common/SkillType.java`'s constructor arguments plus its four
    ## seven-entry tables, indexed by LEVEL 0..6.
    skillEffect*, cooldown*: int
    experience*: array[7, int]
    cooldownDelta*: array[7, int]
    effectDelta*: array[7, int]
    penalty*: array[7, int]

  TrapSpec* = object
    ## `common/TrapType.java`'s constructor arguments, verbatim.
    buildCost*, triggerRadius*, enterRadius*, interactRadius*: int
    enterDamage*, interactDamage*: int
    doesDig*: bool
    actionCooldownIncrease*: int
    isInvisible*: bool
    opponentCooldown*: int

  UpgradeSpec* = object
    ## `common/GlobalUpgrade.java`'s constructor arguments, verbatim.
    baseAttackChange*, baseHealChange*: int
    flagReturnDelayChange*, movementDelayChange*: int

const
  SpecVersion*: string = "3.0.6"
  MapMinHeight*: int = 20
  MapMaxHeight*: int = 60
  MapMinWidth*: int = 20
  MapMaxWidth*: int = 60
  MinFlagSpacingSquared*: int = 36
  GameDefaultSeed*: int = 6370
  GameMaxNumberOfRounds*: int = 2000
  BytecodeLimit*: int = 25000
  IndicatorStringMaxLength*: int = 64
  SharedArrayLength*: int = 64
  MaxSharedArrayValue*: int = 65535
  ExceptionBytecodePenalty*: int = 500
  DefaultHealth*: int = 1000
  RobotCapacity*: int = 50
  NumberFlags*: int = 3
  DigCost*: int = 20
  FillCost*: int = 30
  FlagBroadcastUpdateInterval*: int = 100
  FlagBroadcastNoiseRadius*: int = 100
  FlagDroppedResetRounds*: int = 4
  InitialCrumbsAmount*: int = 400
  PassiveCrumbsIncrease*: int = 10
  KillCrumbReward*: int = 30
  SetupRounds*: int = 200
  GlobalUpgradeRounds*: int = 600
  JailedRounds*: int = 25
  VisionRadiusSquared*: int = 20
  AttackRadiusSquared*: int = 4
  HealRadiusSquared*: int = 4
  InteractRadiusSquared*: int = 2
  CooldownLimit*: int = 10
  CooldownsPerTurn*: int = 10
  MovementCooldown*: int = 10
  FlagMovementCooldown*: int = 20
  PickupDropCooldown*: int = 10
  AttackCooldown*: int = 20
  HealCooldown*: int = 30
  DigCooldown*: int = 20
  FillCooldown*: int = 30

  DecisionOps*: int = 2500
    ## Replaces `BytecodeLimit` outside the JVM: no mid-turn
    ## resumption, enforced by the sim rather than by the bot.

  SkillSpecs*: array[SkillKind, SkillSpec] = [
    skAttack: SkillSpec(skillEffect: 150, cooldown: 20,
      experience: [0, 15, 30, 45, 75, 110, 150],
      cooldownDelta: [0, -5, -7, -10, -20, -35, -60],
      effectDelta: [0, 5, 7, 10, 30, 35, 60],
      penalty: [-1, -2, -2, -5, -5, -10, -12]),
    skBuild: SkillSpec(skillEffect: 0, cooldown: 0,
      experience: [0, 5, 10, 15, 20, 25, 30],
      cooldownDelta: [0, -5, -10, -15, -20, -30, -50],
      effectDelta: [0, -10, -15, -20, -30, -40, -50],
      penalty: [-1, -2, -2, -3, -3, -4, -6]),
    skHeal: SkillSpec(skillEffect: 80, cooldown: 30,
      experience: [0, 20, 40, 70, 100, 140, 180],
      cooldownDelta: [0, -5, -10, -15, -15, -15, -25],
      effectDelta: [0, 3, 5, 7, 10, 15, 25],
      penalty: [-1, -5, -5, -10, -10, -15, -18]),
  ]

  TrapSpecs*: array[TrapKind, TrapSpec] = [
    tkExplosive: TrapSpec(buildCost: 200, triggerRadius: 0, enterRadius: 4,
      interactRadius: 2, enterDamage: 750, interactDamage: 200,
      doesDig: false, actionCooldownIncrease: 5, isInvisible: true,
      opponentCooldown: 0),
    tkWater: TrapSpec(buildCost: 100, triggerRadius: 2, enterRadius: 9,
      interactRadius: 0, enterDamage: 0, interactDamage: 0,
      doesDig: true, actionCooldownIncrease: 5, isInvisible: true,
      opponentCooldown: 0),
    tkStun: TrapSpec(buildCost: 100, triggerRadius: 2, enterRadius: 13,
      interactRadius: 0, enterDamage: 0, interactDamage: 0,
      doesDig: false, actionCooldownIncrease: 5, isInvisible: true,
      opponentCooldown: 40),
    tkNone: TrapSpec(buildCost: 100, triggerRadius: 0, enterRadius: 0,
      interactRadius: 0, enterDamage: 0, interactDamage: 0,
      doesDig: false, actionCooldownIncrease: 0, isInvisible: false,
      opponentCooldown: 0),
  ]

  UpgradeSpecs*: array[UpgradeKind, UpgradeSpec] = [
    ugAttack: UpgradeSpec(baseAttackChange: 60, baseHealChange: 0,
      flagReturnDelayChange: 0, movementDelayChange: 0),
    ugHealing: UpgradeSpec(baseAttackChange: 0, baseHealChange: 50,
      flagReturnDelayChange: 0, movementDelayChange: 0),
    ugCapturing: UpgradeSpec(baseAttackChange: 0, baseHealChange: 0,
      flagReturnDelayChange: 21, movementDelayChange: -8),
    ugAction: UpgradeSpec(baseAttackChange: 0, baseHealChange: 0,
      flagReturnDelayChange: 0, movementDelayChange: 0),
  ]

