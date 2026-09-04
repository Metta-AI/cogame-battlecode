## Battlecode 2020 "Soup" gameplay constants -- GENERATED, do not edit.
##
## Source: github.com/battlecode/battlecode20 at commit `7618f6be7d12da39f2e6e25801e578f1fecfbd86`,
## files `common/GameConstants.java` and `common/RobotType.java`, read by
## `tools/gen_year_constants.py --year bc20`. The `test` job of
## `.github/workflows/ci.yml` re-runs that generator with `--check`,
## which byte-diffs this file, so an edit here fails the build instead
## of quietly changing the rules under a `GameVersion` that no longer
## describes them.
##
## The two derived functions `getWaterLevel`, `getSensorRadiusPollutionCoefficient`
## and `getCooldownPollutionCoefficient` are NOT constants and live in
## `flood.nim` and `pollution.nim`.

const EngineCommit* = "7618f6be7d12da39f2e6e25801e578f1fecfbd86"

type
  RobotKind* = enum
    rtHq = "HQ"
    rtMiner = "MINER"
    rtRefinery = "REFINERY"
    rtVaporator = "VAPORATOR"
    rtDesignSchool = "DESIGN_SCHOOL"
    rtFulfillmentCenter = "FULFILLMENT_CENTER"
    rtLandscaper = "LANDSCAPER"
    rtDeliveryDrone = "DELIVERY_DRONE"
    rtNetGun = "NET_GUN"
    rtCow = "COW"

  RobotSpec* = object
    ## `common/RobotType.java`'s constructor arguments, verbatim.
    cost*, dirtLimit*, soupLimit*: int
    actionCooldown*: float32
    sensorRadiusSquared*, pollutionRadiusSquared*: int
    localPollutionAdditiveEffect*: int
    localPollutionMultiplicativeEffect*: float32
    globalPollutionAmount*, maxSoupProduced*, bytecodeLimit*: int
    decisionOps*: int

const
  SpecVersion*: string = "1.0"
  MapMinHeight*: int = 32
  MapMaxHeight*: int = 64
  MapMinWidth*: int = 32
  MapMaxWidth*: int = 64
  MinWaterElevation*: int = -1073741824
  NumberOfIndicatorStrings*: int = 3
  ExceptionBytecodePenalty*: int = 500
  MaxRobotId*: int = 32000
  InitialSoup*: int = 200
  BaseIncomePerRound*: int = 1
  SoupMiningRate*: int = 7
  MaxDirtDifference*: int = 3
  DeliveryDronePickupRadiusSquared*: int = 3
  NetGunShootRadiusSquared*: int = 15
  BlockchainTransactionLength*: int = 7
  NumberOfTransactionsPerBlock*: int = 7
  InitialCooldownTurns*: int = 10
  GameDefaultSeed*: int = 6370
  GameMaxNumberOfRounds*: int = 10000

  RobotSpecs*: array[RobotKind, RobotSpec] = [
    rtHq: RobotSpec(cost: 0, dirtLimit: 50, soupLimit: 0,
      actionCooldown: 1'f32, sensorRadiusSquared: 48,
      pollutionRadiusSquared: 35, localPollutionAdditiveEffect: 500,
      localPollutionMultiplicativeEffect: 1'f32,
      globalPollutionAmount: 1, maxSoupProduced: 20,
      bytecodeLimit: 20000, decisionOps: 2000),
    rtMiner: RobotSpec(cost: 70, dirtLimit: 0, soupLimit: 100,
      actionCooldown: 1'f32, sensorRadiusSquared: 35,
      pollutionRadiusSquared: 0, localPollutionAdditiveEffect: 0,
      localPollutionMultiplicativeEffect: 1'f32,
      globalPollutionAmount: 0, maxSoupProduced: 0,
      bytecodeLimit: 10000, decisionOps: 1000),
    rtRefinery: RobotSpec(cost: 200, dirtLimit: 15, soupLimit: 0,
      actionCooldown: 1'f32, sensorRadiusSquared: 24,
      pollutionRadiusSquared: 35, localPollutionAdditiveEffect: 500,
      localPollutionMultiplicativeEffect: 1'f32,
      globalPollutionAmount: 1, maxSoupProduced: 20,
      bytecodeLimit: 5000, decisionOps: 500),
    rtVaporator: RobotSpec(cost: 500, dirtLimit: 15, soupLimit: 0,
      actionCooldown: 1'f32, sensorRadiusSquared: 24,
      pollutionRadiusSquared: 35, localPollutionAdditiveEffect: 0,
      localPollutionMultiplicativeEffect: 0.80'f32,
      globalPollutionAmount: -1, maxSoupProduced: 2,
      bytecodeLimit: 5000, decisionOps: 500),
    rtDesignSchool: RobotSpec(cost: 150, dirtLimit: 15, soupLimit: 0,
      actionCooldown: 1'f32, sensorRadiusSquared: 24,
      pollutionRadiusSquared: 0, localPollutionAdditiveEffect: 0,
      localPollutionMultiplicativeEffect: 1'f32,
      globalPollutionAmount: 0, maxSoupProduced: 0,
      bytecodeLimit: 5000, decisionOps: 500),
    rtFulfillmentCenter: RobotSpec(cost: 150, dirtLimit: 15, soupLimit: 0,
      actionCooldown: 1'f32, sensorRadiusSquared: 24,
      pollutionRadiusSquared: 0, localPollutionAdditiveEffect: 0,
      localPollutionMultiplicativeEffect: 1'f32,
      globalPollutionAmount: 0, maxSoupProduced: 0,
      bytecodeLimit: 5000, decisionOps: 500),
    rtLandscaper: RobotSpec(cost: 150, dirtLimit: 25, soupLimit: 0,
      actionCooldown: 1'f32, sensorRadiusSquared: 24,
      pollutionRadiusSquared: 0, localPollutionAdditiveEffect: 0,
      localPollutionMultiplicativeEffect: 1'f32,
      globalPollutionAmount: 0, maxSoupProduced: 0,
      bytecodeLimit: 10000, decisionOps: 1000),
    rtDeliveryDrone: RobotSpec(cost: 150, dirtLimit: 0, soupLimit: 0,
      actionCooldown: 1.5'f32, sensorRadiusSquared: 24,
      pollutionRadiusSquared: 0, localPollutionAdditiveEffect: 0,
      localPollutionMultiplicativeEffect: 1'f32,
      globalPollutionAmount: 0, maxSoupProduced: 0,
      bytecodeLimit: 10000, decisionOps: 1000),
    rtNetGun: RobotSpec(cost: 250, dirtLimit: 15, soupLimit: 0,
      actionCooldown: 1'f32, sensorRadiusSquared: 24,
      pollutionRadiusSquared: 0, localPollutionAdditiveEffect: 0,
      localPollutionMultiplicativeEffect: 1'f32,
      globalPollutionAmount: 0, maxSoupProduced: 0,
      bytecodeLimit: 7000, decisionOps: 700),
    rtCow: RobotSpec(cost: 0, dirtLimit: 0, soupLimit: 0,
      actionCooldown: 2'f32, sensorRadiusSquared: 10000,
      pollutionRadiusSquared: 15, localPollutionAdditiveEffect: 2000,
      localPollutionMultiplicativeEffect: 1'f32,
      globalPollutionAmount: 0, maxSoupProduced: 0,
      bytecodeLimit: 0, decisionOps: 0),
  ]

