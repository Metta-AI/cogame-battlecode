## Battlecode 2025 "Chromatic Conflict" gameplay constants -- GENERATED, do not edit.
##
## Source: github.com/battlecode/battlecode25 at commit `28975a487c1a30ed2b5bed644fe6ecd2c3dd1482`,
## files `common/GameConstants.java` and `common/UnitType.java`, read
## by `tools/gen_year_constants.py --year bc25`. The `test` job of
## `.github/workflows/ci.yml` re-runs that generator with `--check`,
## which byte-diffs this file, so an edit here fails the build instead
## of quietly changing the rules under a `GameVersion` that no longer
## describes them.
##
## `SpecVersion` is the literal string "1" in the 2025 sources, which
## is useless as a version pin -- so the ORACLE JAR is pinned by
## sha256 in `tools/oracle/bc25/jar.lock` instead, and Tier B
## cross-checks every constant here against the jar's own classes
## (docs/RULES-BC25.md §Divergences item 12).
##
## THERE IS NO FLOAT32 ANYWHERE IN BC25 and no transcendental in the
## round loop: the only floating point is `Math.round(double)` in four
## places, which is why this year's arithmetic tier is provable over
## its whole finite domain rather than sampled.

const EngineCommit* = "28975a487c1a30ed2b5bed644fe6ecd2c3dd1482"
const OracleJarVersion* = "3.1.0"

type
  UnitType* = enum
    utSoldier = "SOLDIER"
    utSplasher = "SPLASHER"
    utMopper = "MOPPER"
    utLevelOnePaintTower = "LEVEL_ONE_PAINT_TOWER"
    utLevelTwoPaintTower = "LEVEL_TWO_PAINT_TOWER"
    utLevelThreePaintTower = "LEVEL_THREE_PAINT_TOWER"
    utLevelOneMoneyTower = "LEVEL_ONE_MONEY_TOWER"
    utLevelTwoMoneyTower = "LEVEL_TWO_MONEY_TOWER"
    utLevelThreeMoneyTower = "LEVEL_THREE_MONEY_TOWER"
    utLevelOneDefenseTower = "LEVEL_ONE_DEFENSE_TOWER"
    utLevelTwoDefenseTower = "LEVEL_TWO_DEFENSE_TOWER"
    utLevelThreeDefenseTower = "LEVEL_THREE_DEFENSE_TOWER"

  UnitSpec* = object
    ## `common/UnitType.java`'s thirteen constructor arguments, in the
    ## file's own order. `-1` means the field has no meaning for that
    ## type and is carried rather than normalised, because the engine
    ## carries it.
    paintCost*, moneyCost*, attackCost*, health*, level*: int
    paintCapacity*, actionCooldown*, actionRadiusSquared*: int
    attackStrength*, aoeAttackStrength*: int
    paintPerTurn*, moneyPerTurn*, attackMoneyBonus*: int

const
  SpecVersion*: string = "1"
  MapMinHeight*: int = 20
  MapMaxHeight*: int = 60
  MapMinWidth*: int = 20
  MapMaxWidth*: int = 60
  MinRuinSpacingSquared*: int = 25
  MaxWallPercentage*: int = 20
  ResourcePattern*: int = 28873275
  PaintTowerPattern*: int = 18157905
  MoneyTowerPattern*: int = 15583086
  DefenseTowerPattern*: int = 4685252
  GameDefaultSeed*: int = 6370
  GameMaxNumberOfRounds*: int = 2000
  RobotBytecodeLimit*: int = 17500
  TowerBytecodeLimit*: int = 20000
  IndicatorStringMaxLength*: int = 256
  TimelineLabelMaxLength*: int = 64
  ExceptionBytecodePenalty*: int = 500
  PenaltyEnemyTerritory*: int = 2
  PenaltyNeutralTerritory*: int = 1
  InitialTeamMoney*: int = 2500
  PaintPercentToWin*: int = 70
  MaxNumberOfTowers*: int = 25
  MaxTeamExecutionTime*: int64 = 1200000000000
  NumberInitialTowers*: int = 2
  NumberInitialPaintTowers*: int = 1
  NumberInitialMoneyTowers*: int = 1
  NumberInitialDefenseTowers*: int = 0
  InitialRobotPaintPercentage*: int = 100
  InitialTowerPaintAmount*: int = 500
  PatternSize*: int = 5
  MarkPatternPaintCost*: int = 25
  CompleteResourcePatternCost*: int = 200
  ExtraResourcesFromPattern*: int = 3
  ResourcePatternActiveDelay*: int = 50
  ExtraDamageFromDefenseTower*: int = 5
  ExtraTowerDamageLevelIncrease*: int = 2
  DefenseAttackBuffAoeEffectiveness*: int = 0
  MaxTurnsWithoutPaint*: int = 10
  IncreasedCooldownThreshold*: int = 50
  IncreasedCooldownIntercept*: int = 100
  IncreasedCooldownSlope*: int = -2
  MopperPaintPenaltyMultiplier*: int = 2
  VisionRadiusSquared*: int = 20
  MarkRadiusSquared*: int = 2
  PaintTransferRadiusSquared*: int = 2
  BuildRobotRadiusSquared*: int = 4
  BuildTowerRadiusSquared*: int = 2
  ResourcePatternRadiusSquared*: int = 8
  MopperAttackPaintDepletion*: int = 10
  MopperAttackPaintAddition*: int = 5
  MopperSwingPaintDepletion*: int = 5
  MaxMessageBytes*: int = 4
  MessageRadiusSquared*: int = 20
  BroadcastRadiusSquared*: int = 80
  MessageRoundDuration*: int = 5
  MaxMessagesSentRobot*: int = 1
  MaxMessagesSentTower*: int = 20
  NoPaintDamage*: int = 20
  SplasherAttackAoeRadiusSquared*: int = 4
  SplasherAttackEnemyPaintRadiusSquared*: int = 2
  CooldownLimit*: int = 10
  CooldownsPerTurn*: int = 10
  MovementCooldown*: int = 10
  BuildRobotCooldown*: int = 10
  AttackMopperSwingCooldown*: int = 20
  PaintTransferCooldown*: int = 10

  DecisionOpsRobot*: int = 1750
  DecisionOpsTower*: int = 2000
    ## Replace `RobotBytecodeLimit` / `TowerBytecodeLimit` outside the
    ## JVM: no mid-turn resumption, no mid-primitive cut, enforced by
    ## the sim rather than by the bot.

  UnitSpecs*: array[UnitType, UnitSpec] = [
    utSoldier: UnitSpec(paintCost: 200, moneyCost: 250, attackCost: 5,
      health: 250, level: -1, paintCapacity: 200,
      actionCooldown: 10, actionRadiusSquared: 9,
      attackStrength: 50, aoeAttackStrength: -1,
      paintPerTurn: 0, moneyPerTurn: 0,
      attackMoneyBonus: 0),
    utSplasher: UnitSpec(paintCost: 300, moneyCost: 400, attackCost: 50,
      health: 150, level: -1, paintCapacity: 300,
      actionCooldown: 50, actionRadiusSquared: 4,
      attackStrength: -1, aoeAttackStrength: 100,
      paintPerTurn: 0, moneyPerTurn: 0,
      attackMoneyBonus: 0),
    utMopper: UnitSpec(paintCost: 100, moneyCost: 300, attackCost: 0,
      health: 50, level: -1, paintCapacity: 100,
      actionCooldown: 30, actionRadiusSquared: 2,
      attackStrength: -1, aoeAttackStrength: -1,
      paintPerTurn: 0, moneyPerTurn: 0,
      attackMoneyBonus: 0),
    utLevelOnePaintTower: UnitSpec(paintCost: 0, moneyCost: 1000, attackCost: 0,
      health: 1000, level: 1, paintCapacity: 1000,
      actionCooldown: 10, actionRadiusSquared: 9,
      attackStrength: 20, aoeAttackStrength: 10,
      paintPerTurn: 5, moneyPerTurn: 0,
      attackMoneyBonus: 0),
    utLevelTwoPaintTower: UnitSpec(paintCost: 0, moneyCost: 2500, attackCost: 0,
      health: 1500, level: 2, paintCapacity: 1000,
      actionCooldown: 10, actionRadiusSquared: 9,
      attackStrength: 20, aoeAttackStrength: 10,
      paintPerTurn: 10, moneyPerTurn: 0,
      attackMoneyBonus: 0),
    utLevelThreePaintTower: UnitSpec(paintCost: 0, moneyCost: 5000, attackCost: 0,
      health: 2000, level: 3, paintCapacity: 1000,
      actionCooldown: 10, actionRadiusSquared: 9,
      attackStrength: 20, aoeAttackStrength: 10,
      paintPerTurn: 15, moneyPerTurn: 0,
      attackMoneyBonus: 0),
    utLevelOneMoneyTower: UnitSpec(paintCost: 0, moneyCost: 1000, attackCost: 0,
      health: 1000, level: 1, paintCapacity: 1000,
      actionCooldown: 10, actionRadiusSquared: 9,
      attackStrength: 20, aoeAttackStrength: 10,
      paintPerTurn: 0, moneyPerTurn: 20,
      attackMoneyBonus: 0),
    utLevelTwoMoneyTower: UnitSpec(paintCost: 0, moneyCost: 2500, attackCost: 0,
      health: 1500, level: 2, paintCapacity: 1000,
      actionCooldown: 10, actionRadiusSquared: 9,
      attackStrength: 20, aoeAttackStrength: 10,
      paintPerTurn: 0, moneyPerTurn: 30,
      attackMoneyBonus: 0),
    utLevelThreeMoneyTower: UnitSpec(paintCost: 0, moneyCost: 5000, attackCost: 0,
      health: 2000, level: 3, paintCapacity: 1000,
      actionCooldown: 10, actionRadiusSquared: 9,
      attackStrength: 20, aoeAttackStrength: 10,
      paintPerTurn: 0, moneyPerTurn: 40,
      attackMoneyBonus: 0),
    utLevelOneDefenseTower: UnitSpec(paintCost: 0, moneyCost: 1000, attackCost: 0,
      health: 2000, level: 1, paintCapacity: 1000,
      actionCooldown: 10, actionRadiusSquared: 16,
      attackStrength: 40, aoeAttackStrength: 20,
      paintPerTurn: 0, moneyPerTurn: 0,
      attackMoneyBonus: 20),
    utLevelTwoDefenseTower: UnitSpec(paintCost: 0, moneyCost: 2500, attackCost: 0,
      health: 2500, level: 2, paintCapacity: 1000,
      actionCooldown: 10, actionRadiusSquared: 16,
      attackStrength: 50, aoeAttackStrength: 25,
      paintPerTurn: 0, moneyPerTurn: 0,
      attackMoneyBonus: 30),
    utLevelThreeDefenseTower: UnitSpec(paintCost: 0, moneyCost: 5000, attackCost: 0,
      health: 3000, level: 3, paintCapacity: 1000,
      actionCooldown: 10, actionRadiusSquared: 16,
      attackStrength: 60, aoeAttackStrength: 30,
      paintPerTurn: 0, moneyPerTurn: 0,
      attackMoneyBonus: 40),
  ]

