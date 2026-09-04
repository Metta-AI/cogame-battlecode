## Battlecode 2021 "Campaign" gameplay constants -- GENERATED, do not edit.
##
## Source: github.com/battlecode/battlecode21 at commit `ed39c1a49574db57e5463d720736220506280294`
## (release 2021.3.0.5), files `common/GameConstants.java` and
## `common/RobotType.java`, read by
## `tools/gen_year_constants.py --year bc21`. The `test` job of
## `.github/workflows/ci.yml` re-runs that generator with `--check`,
## which byte-diffs this file, so an edit here fails the build instead
## of quietly changing the rules under a `GameVersion` that no longer
## describes them.
##
## `RobotType.getPassiveInfluence` is NOT a constant: the Enlightenment
## Center curve and the slanderer embezzle formula live in
## `economy.nim`, backed by the committed JDK-generated tables in
## `data/bc21/`.

const EngineCommit* = "ed39c1a49574db57e5463d720736220506280294"
const EngineRelease* = "2021.3.0.5"

type
  RobotKind* = enum
    rtEnlightenmentCenter = "ENLIGHTENMENT_CENTER"
    rtPolitician = "POLITICIAN"
    rtSlanderer = "SLANDERER"
    rtMuckraker = "MUCKRAKER"

  RobotSpec* = object
    ## `common/RobotType.java`'s constructor arguments, verbatim.
    ## `convictionRatio`, `actionCooldown` and `initialCooldown` are
    ## Java `float`s; widening them changes which round a robot is
    ## ready, so they stay float32 here.
    convictionRatio*, actionCooldown*, initialCooldown*: float32
    actionRadiusSquared*, sensorRadiusSquared*: int
    detectionRadiusSquared*, bytecodeLimit*: int
    decisionOps*: int

const
  SpecVersion*: string = "1.0"
  MapMinHeight*: int = 32
  MapMaxHeight*: int = 64
  MapMinWidth*: int = 32
  MapMaxWidth*: int = 64
  NumberOfIndicatorStrings*: int = 3
  ExceptionBytecodePenalty*: int = 500
  EmpowerTax*: int = 10
  ExposeBuffFactor*: float64 = 0.001
  ExposeBuffNumRounds*: int = 50
  EmbezzleNumRounds*: int = 50
  EmbezzleScaleFactor*: float32 = 0.029999999329447746
  EmbezzleDecayFactor*: float32 = 0.0010000000474974513
  CamouflageNumRounds*: int = 300
  InitialEnlightenmentCenterInfluence*: int = 150
  PassiveInfluenceRatioEnlightenmentCenter*: float32 = 0.20000000298023224
  RobotInfluenceLimit*: int = 100000000
  MinFlagValue*: int = 0
  MaxFlagValue*: int = 16777215
  GameDefaultSeed*: int = 6370
  GameMaxNumberOfRounds*: int = 1500

  RobotSpecs*: array[RobotKind, RobotSpec] = [
    rtEnlightenmentCenter: RobotSpec(convictionRatio: 1.0'f32,
      actionCooldown: 2.0'f32, initialCooldown: 0.0'f32,
      actionRadiusSquared: 2, sensorRadiusSquared: 40,
      detectionRadiusSquared: 40, bytecodeLimit: 20000,
      decisionOps: 2000),
    rtPolitician: RobotSpec(convictionRatio: 1.0'f32,
      actionCooldown: 1.0'f32, initialCooldown: 10.0'f32,
      actionRadiusSquared: 9, sensorRadiusSquared: 25,
      detectionRadiusSquared: 25, bytecodeLimit: 15000,
      decisionOps: 1500),
    rtSlanderer: RobotSpec(convictionRatio: 1.0'f32,
      actionCooldown: 2.0'f32, initialCooldown: 0.0'f32,
      actionRadiusSquared: 0, sensorRadiusSquared: 20,
      detectionRadiusSquared: 20, bytecodeLimit: 7500,
      decisionOps: 750),
    rtMuckraker: RobotSpec(convictionRatio: 0.699999988079071'f32,
      actionCooldown: 1.5'f32, initialCooldown: 10.0'f32,
      actionRadiusSquared: 12, sensorRadiusSquared: 30,
      detectionRadiusSquared: 40, bytecodeLimit: 15000,
      decisionOps: 1500),
  ]

