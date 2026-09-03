## Battlecode 2026 gameplay constants -- GENERATED, do not edit.
##
## Source: github.com/battlecode/battlecode26 at tag `engine.1.2.5`,
## files `common/GameConstants.java`, `common/UnitType.java` and
## `common/TrapType.java`, read by `tools/gen_year_constants.py`.
## `tests/test_constants.nim` regenerates this file and byte-diffs it,
## so an edit here fails the build instead of quietly changing the
## rules under a `GameVersion` that no longer describes them.

const EngineTag* = "engine.1.2.5"

type
  UnitType* = enum
    utBabyRat = "BABY_RAT"
    utRatKing = "RAT_KING"
    utCat = "CAT"

  TrapType* = enum
    ttRatTrap = "RAT_TRAP"
    ttCatTrap = "CAT_TRAP"
    ttNone = "NONE"

  UnitSpec* = object
    ## `common/UnitType.java`'s constructor arguments, verbatim.
    health*, size*, visionConeRadiusSquared*, visionConeAngle*: int
    actionCooldown*, movementCooldown*, bytecodeLimit*: int

  TrapSpec* = object
    ## `common/TrapType.java`'s constructor arguments, verbatim.
    buildCost*, damage*, stunTime*: int
    actionCooldown*, maxCount*, triggerRadiusSquared*: int

const
  SpecVersion*: string = "1"
  MapMinHeight*: int = 20
  MapMaxHeight*: int = 60
  MapMinWidth*: int = 20
  MapMaxWidth*: int = 60
  MinCheeseMineSpacingSquared*: int = 25
  MaxDirtPercentage*: int = 50
  MaxWallPercentage*: int = 20
  GameDefaultSeed*: int = 6370
  GameMaxNumberOfRounds*: int = 2000
  IndicatorStringMaxLength*: int = 256
  TimelineLabelMaxLength*: int = 64
  ExceptionBytecodePenalty*: int = 500
  InitialTeamCheese*: int = 2500
  CatTrapRoundsAfterBackstab*: int = 100
  MaxNumberOfRatKings*: int = 5
  MaxNumberOfRatKingsAfterCutoff*: int = 2
  RatKingCutoffRound*: int = 1200
  MaxTeamExecutionTime*: int64 = 1200000000000
  MoveStrafeCooldown*: int = 18
  CheeseCooldownPenalty*: float64 = 0.01
  RatKingCheeseConsumption*: int = 2
  RatKingHealthLoss*: int = 10
  CheeseMineSpawnProbability*: float32 = 0.01
  SqCheeseSpawnRadius*: int = 4
  CheeseSpawnAmount*: int = 20
  NumberInitialRatKings*: int = 1
  CheeseTransferRadiusSquared*: int = 9
  CheesePickUpRadiusSquared*: int = 2
  BuildRobotRadiusSquared*: int = 8
  BuildRobotBaseCost*: int = 10
  BuildRobotCostIncrease*: int = 10
  NumRobotsForCostIncrease*: int = 4
  BuildDistanceSquared*: int = 2
  CatBuildDistanceSquared*: float32 = 4.5
  RatKingBuildDistanceSquared*: int = 8
  AttackDistanceSquared*: int = 2
  RatKingAttackDistanceSquared*: int = 8
  MessageRoundDuration*: int = 5
  MaxMessagesSentRobot*: int = 1
  SqueakRadiusSquared*: int = 16
  ThrowDamage*: int = 10
  ThrowDamagePerTile*: int = 4
  TilesFlownPerTurn*: int = 2
  RatBiteDamage*: int = 10
  CatScratchDamage*: int = 20
  CatPounceMaxDistanceSquared*: int = 13
  CatDigAdditionalCooldown*: int = 5
  HealthGrabThreshold*: int = 0
  RatKingUpgradeCheeseCost*: int = 50
  DigDirtCheeseCost*: int = 5
  PlaceDirtCheeseCost*: int = 0
  SharedArraySize*: int = 64
  CommArrayMaxValue*: int = 1023
  CooldownLimit*: int = 10
  CooldownsPerTurn*: int = 10
  TurningCooldown*: int = 10
  BuildRobotCooldown*: int = 10
  CheeseTransferCooldown*: int = 10
  DigCooldown*: int = 25
  CarryCooldownMultiplier*: float64 = 1.5
  MaxCarryTowerHeight*: int = 2
  MaxCarryDuration*: int = 10
  SameRobotCarryCooldownTurns*: int = 2
  ThrowDuration*: int = 4
  ThrowRatCooldown*: int = 20
  HitGroundCooldown*: int = 10
  HitTargetCooldown*: int = 20
  CatSleepTime*: int = 2

  UnitSpecs*: array[UnitType, UnitSpec] = [
    utBabyRat: UnitSpec(health: 100, size: 1, visionConeRadiusSquared: 20,
      visionConeAngle: 90, actionCooldown: 10, movementCooldown: 10,
      bytecodeLimit: 17500),
    utRatKing: UnitSpec(health: 600, size: 3, visionConeRadiusSquared: 25,
      visionConeAngle: 360, actionCooldown: 10, movementCooldown: 40,
      bytecodeLimit: 20000),
    utCat: UnitSpec(health: 4000, size: 2, visionConeRadiusSquared: 17,
      visionConeAngle: 180, actionCooldown: 30, movementCooldown: 20,
      bytecodeLimit: 17500),
  ]

  TrapSpecs*: array[TrapType, TrapSpec] = [
    ttRatTrap: TrapSpec(buildCost: 20, damage: 50, stunTime: 30,
      actionCooldown: 15, maxCount: 25, triggerRadiusSquared: 2),
    ttCatTrap: TrapSpec(buildCost: 10, damage: 100, stunTime: 20,
      actionCooldown: 10, maxCount: 10, triggerRadiusSquared: 2),
    ttNone: TrapSpec(buildCost: 0, damage: 0, stunTime: 0,
      actionCooldown: 0, maxCount: 0, triggerRadiusSquared: 0),
  ]

  # The per-robot DECISION BUDGET that replaces the engine's JVM
  # bytecode limit. Hand-authored, not generated: it is this port's
  # own rule, listed in docs/RULES.md §Divergences.
  DecisionOpsBabyRat* = 1500
  DecisionOpsRatKing* = 2500
  DecisionOpsCat* = 800

