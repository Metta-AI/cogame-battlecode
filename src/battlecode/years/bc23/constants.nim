## Battlecode 2023 "Tempest" gameplay constants -- GENERATED, do not edit.
##
## Source: github.com/battlecode/battlecode23 at commit `af42086ecd09709dc603b2aaa9e9b98312c9ef79`,
## files `common/GameConstants.java`, `common/RobotType.java` and
## `common/Anchor.java`, read by `tools/gen_year_constants.py --year
## bc23`. The `test` job of `.github/workflows/ci.yml` re-runs that
## generator with `--check`, which byte-diffs this file, so an edit
## here fails the build instead of quietly changing the rules under a
## `GameVersion` that no longer describes them.
##
## `SPEC_VERSION` below is the literal string "3.0.14" -- and so is
## the one inside the RELEASED 3.0.15 jar, which makes it useless as a
## version pin. The ORACLE JAR is therefore pinned by sha256 in
## `tools/oracle/bc23/jar.lock` instead, and Tier B cross-checks every
## constant here against the jar's own classes
## (docs/RULES-BC23.md §Divergences item 12).
##
## THE ONLY FLOAT32 IN BC23 is the conquest threshold 0.75f, the
## carrier's 1.25f damage factor and 0.375f movement slope, and the
## accelerating anchor's -0.15f; there is NO TRANSCENDENTAL ANYWHERE,
## which is why this year's arithmetic tier is provable over its whole
## finite domain rather than sampled.

const EngineCommit* = "af42086ecd09709dc603b2aaa9e9b98312c9ef79"
const OracleJarVersion* = "3.0.15"

type
  RobotType* = enum
    rtHeadquarters = "HEADQUARTERS"
    rtCarrier = "CARRIER"
    rtLauncher = "LAUNCHER"
    rtDestabilizer = "DESTABILIZER"
    rtBooster = "BOOSTER"
    rtAmplifier = "AMPLIFIER"

  AnchorType* = enum
    anNone = "-"
    anStandard = "STANDARD"
    anAccelerating = "ACCELERATING"

  RobotSpec* = object
    ## `common/RobotType.java`'s ten constructor arguments, in the
    ## file's own order. `-1` means the field has no meaning for that
    ## type and is carried rather than normalised, because the engine
    ## carries it: HEADQUARTERS cannot move, BOOSTER and AMPLIFIER
    ## have no action radius, AMPLIFIER has no action cooldown.
    buildCostAdamantium*, buildCostMana*, buildCostElixir*: int
    actionCooldown*, movementCooldown*, health*, damage*: int
    actionRadiusSquared*, visionRadiusSquared*, bytecodeLimit*: int

  AnchorSpec* = object
    ## `common/Anchor.java`'s eight constructor arguments, in the
    ## file's own order.
    totalHealth*, unitsAffected*: int
    accelerationFactor*: float32
    healingFrequency*, healingAmount*: int
    manaCost*, adamantiumCost*, elixirCost*: int

const
  SpecVersion*: string = "3.0.14"
  MapMinHeight*: int = 20
  MapMaxHeight*: int = 60
  MapMinWidth*: int = 20
  MapMaxWidth*: int = 60
  MinStartingHeadquarters*: int = 1
  MaxStartingHeadquarters*: int = 4
  MinNumberIslands*: int = 4
  MaxNumberIslands*: int = 35
  MaxIslandArea*: int = 20
  MaxDistanceBetweenWells*: int = 100
  MinNearestAdDistance*: int = 100
  MaxMapPercentWells*: float32 = 0.03999999910593033
  IndicatorStringMaxLength*: int = 64
  SharedArrayLength*: int = 64
  MaxSharedArrayValue*: int = 65535
  ExceptionBytecodePenalty*: int = 500
  InitialMnAmount*: int = 200
  InitialAdAmount*: int = 200
  PassiveAdIncrease*: int = 6
  PassiveMnIncrease*: int = 6
  PassiveIncreaseRounds*: int = 5
  UpgradeToElixir*: int = 600
  UpgradeWellAmount*: int = 1400
  WinPercentageOfIslandsOccupied*: float32 = 0.75
  DistanceSquaredFromSignalAmplifier*: int = 20
  DistanceSquaredFromIsland*: int = 4
  DistanceSquaredFromHeadquarter*: int = 9
  CarrierDamageFactor*: float32 = 1.25
  CarrierMovementSlope*: float32 = 0.375
  CarrierMovementIntercept*: int = 5
  CooldownLimit*: int = 10
  CooldownsPerTurn*: int = 10
  CurrentStrength*: int = 1
  CarrierCapacity*: int = 40
  AnchorWeight*: int = 40
  CloudVisionRadiusSquared*: int = 4
  BoosterMultiplier*: float64 = -0.1
  DestabilizerMultiplier*: float64 = 0.1
  AnchorMultiplier*: float64 = -0.15
  CloudMultiplier*: float64 = 0.2
  BoosterRadiusSquared*: int = 20
  DestabilizerRadiusSquared*: int = 15
  BoosterDuration*: int = 10
  DestabilizerDuration*: int = 5
  MaxBoostStacks*: int = 3
  MaxDestabilizeStacks*: int = 2
  MaxAnchorStacks*: int = 1
  WellStandardRate*: int = 1
  WellAcceleratedRate*: int = 3
  GameDefaultSeed*: int = 6370
  GameMaxNumberOfRounds*: int = 2000

  DecisionOpsHeadquarters*: int = 2000
  DecisionOpsCarrier*: int = 1250
  DecisionOpsOther*: int = 1000
    ## Replace `RobotType.bytecodeLimit` outside the JVM: no mid-turn
    ## resumption, no mid-primitive cut, enforced by the sim rather
    ## than by the bot.

  RobotSpecs*: array[RobotType, RobotSpec] = [
    rtHeadquarters: RobotSpec(buildCostAdamantium: 0,
      buildCostMana: 0, buildCostElixir: 0,
      actionCooldown: 2, movementCooldown: -1,
      health: 1, damage: 4,
      actionRadiusSquared: 9, visionRadiusSquared: 34,
      bytecodeLimit: 20000),
    rtCarrier: RobotSpec(buildCostAdamantium: 50,
      buildCostMana: 0, buildCostElixir: 0,
      actionCooldown: 10, movementCooldown: 0,
      health: 150, damage: 0,
      actionRadiusSquared: 9, visionRadiusSquared: 20,
      bytecodeLimit: 12500),
    rtLauncher: RobotSpec(buildCostAdamantium: 0,
      buildCostMana: 45, buildCostElixir: 0,
      actionCooldown: 10, movementCooldown: 20,
      health: 200, damage: 20,
      actionRadiusSquared: 16, visionRadiusSquared: 20,
      bytecodeLimit: 10000),
    rtDestabilizer: RobotSpec(buildCostAdamantium: 0,
      buildCostMana: 0, buildCostElixir: 200,
      actionCooldown: 70, movementCooldown: 25,
      health: 300, damage: 50,
      actionRadiusSquared: 13, visionRadiusSquared: 20,
      bytecodeLimit: 10000),
    rtBooster: RobotSpec(buildCostAdamantium: 0,
      buildCostMana: 0, buildCostElixir: 150,
      actionCooldown: 140, movementCooldown: 25,
      health: 400, damage: 0,
      actionRadiusSquared: -1, visionRadiusSquared: 20,
      bytecodeLimit: 10000),
    rtAmplifier: RobotSpec(buildCostAdamantium: 30,
      buildCostMana: 15, buildCostElixir: 0,
      actionCooldown: -1, movementCooldown: 15,
      health: 120, damage: 0,
      actionRadiusSquared: -1, visionRadiusSquared: 34,
      bytecodeLimit: 10000),
  ]

  AnchorSpecs*: array[AnchorType, AnchorSpec] = [
    anNone: AnchorSpec(totalHealth: 0, unitsAffected: 0,
      accelerationFactor: 0.0'f32, healingFrequency: 0,
      healingAmount: 0, manaCost: 0, adamantiumCost: 0,
      elixirCost: 0),
    anStandard: AnchorSpec(totalHealth: 250,
      unitsAffected: 0,
      accelerationFactor: 0.0'f32,
      healingFrequency: 1, healingAmount: 4,
      manaCost: 80, adamantiumCost: 80,
      elixirCost: 0),
    anAccelerating: AnchorSpec(totalHealth: 750,
      unitsAffected: 4,
      accelerationFactor: -0.15000000596046448'f32,
      healingFrequency: 1, healingAmount: 6,
      manaCost: 0, adamantiumCost: 0,
      elixirCost: 300),
  ]

