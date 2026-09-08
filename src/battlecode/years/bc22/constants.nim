## Battlecode 2022 "Mutation" gameplay constants -- GENERATED, do not edit.
##
## Source: github.com/battlecode/battlecode22 at commit `6ed05b679c0822e9bbe332812ff5655812dd023e`,
## files `common/GameConstants.java`, `common/RobotType.java` and
## `common/AnomalyType.java`, read by `tools/gen_year_constants.py
## --year bc22`. The `test` job of `.github/workflows/ci.yml` re-runs
## that generator with `--check`, which byte-diffs this file, so an
## edit here fails the build instead of quietly changing the rules
## under a `GameVersion` that no longer describes them.
##
## `SPEC_VERSION` below is "2.2.1" and -- unlike bc23's and bc25's
## -- it MATCHES the released jar's own version, so the oracle job
## asserts the string as well as the sha256 pinned in
## `tools/oracle/bc22/jar.lock`.
##
## THE ONE TRANSCENDENTAL IN BC22 is the laboratory's transmutation
## rate, `(int)(20.0 - 18.0 * exp(-k*n))`, whose domain is finite
## (3 levels x n in 0..176) and is therefore TABLED whole into
## `data/bc22/tables.json` rather than evaluated at run time. Every
## other non-integer expression -- the float64 rubble multiplier and
## the float32 prototype, reclaim and anomaly truncations -- is
## likewise tabled over its whole reachable domain.

const EngineCommit* = "6ed05b679c0822e9bbe332812ff5655812dd023e"
const OracleJarVersion* = "2.2.1"

type
  RobotType* = enum
    rtArchon = "ARCHON"
    rtLaboratory = "LABORATORY"
    rtWatchtower = "WATCHTOWER"
    rtMiner = "MINER"
    rtBuilder = "BUILDER"
    rtSoldier = "SOLDIER"
    rtSage = "SAGE"

  AnomalyKind* = enum
    anAbyss = "ABYSS"
    anCharge = "CHARGE"
    anFury = "FURY"
    anVortex = "VORTEX"

  RobotSpec* = object
    ## `common/RobotType.java`'s nine constructor arguments, in the
    ## file's own order. `damage` is NEGATIVE for a repairer (ARCHON
    ## -2, BUILDER -2) and `getHealing` is its negation, exactly as
    ## the engine carries it.
    buildCostLead*, buildCostGold*: int
    actionCooldown*, movementCooldown*, health*, damage*: int
    actionRadiusSquared*, visionRadiusSquared*, bytecodeLimit*: int

  AnomalySpec* = object
    ## `common/AnomalyType.java`'s four constructor arguments.
    isGlobalAnomaly*, isSageAnomaly*: bool
    globalPercentage*, sagePercentage*: float32

const
  SpecVersion*: string = "2.2.1"
  MapMinHeight*: int = 20
  MapMaxHeight*: int = 60
  MapMinWidth*: int = 20
  MapMaxWidth*: int = 60
  MinStartingArchons*: int = 1
  MaxStartingArchons*: int = 4
  MinRubble*: int = 0
  MaxRubble*: int = 100
  IndicatorStringMaxLength*: int = 64
  SharedArrayLength*: int = 64
  MaxSharedArrayValue*: int = 65535
  ExceptionBytecodePenalty*: int = 500
  InitialLeadAmount*: int = 200
  InitialGoldAmount*: int = 0
  PassiveLeadIncrease*: int = 2
  AddLeadEveryRounds*: int = 20
  AddLead*: int = 5
  CooldownLimit*: int = 10
  CooldownsPerTurn*: int = 10
  TransformCooldown*: int = 100
  MutateCooldown*: int = 100
  PrototypeHpPercentage*: float32 = 0.800000011920929
  ReclaimCostMultiplier*: float32 = 0.20000000298023224
  MaxLevel*: int = 3
  AlchemistLonelinessA*: float64 = 20.0
  AlchemistLonelinessB*: float64 = 18.0
  AlchemistLonelinessKL1*: float64 = 0.02
  AlchemistLonelinessKL2*: float64 = 0.01
  AlchemistLonelinessKL3*: float64 = 0.005
  GameDefaultSeed*: int = 6370
  GameMaxNumberOfRounds*: int = 2000

  DecisionOpsArchon*: int = 2000
  DecisionOpsStandard*: int = 1250
  DecisionOpsBuilder*: int = 750
  DecisionOpsLaboratory*: int = 500
    ## Replace `RobotType.bytecodeLimit` outside the JVM: no mid-turn
    ## resumption, no mid-primitive cut, enforced by the sim rather
    ## than by the bot.

  RobotSpecs*: array[RobotType, RobotSpec] = [
    rtArchon: RobotSpec(buildCostLead: 0,
      buildCostGold: 100,
      actionCooldown: 10, movementCooldown: 24,
      health: 600, damage: -2,
      actionRadiusSquared: 20, visionRadiusSquared: 34,
      bytecodeLimit: 20000),
    rtLaboratory: RobotSpec(buildCostLead: 180,
      buildCostGold: 0,
      actionCooldown: 10, movementCooldown: 24,
      health: 100, damage: 0,
      actionRadiusSquared: 0, visionRadiusSquared: 53,
      bytecodeLimit: 5000),
    rtWatchtower: RobotSpec(buildCostLead: 150,
      buildCostGold: 0,
      actionCooldown: 10, movementCooldown: 24,
      health: 150, damage: 4,
      actionRadiusSquared: 20, visionRadiusSquared: 34,
      bytecodeLimit: 10000),
    rtMiner: RobotSpec(buildCostLead: 50,
      buildCostGold: 0,
      actionCooldown: 2, movementCooldown: 20,
      health: 40, damage: 0,
      actionRadiusSquared: 2, visionRadiusSquared: 20,
      bytecodeLimit: 10000),
    rtBuilder: RobotSpec(buildCostLead: 40,
      buildCostGold: 0,
      actionCooldown: 10, movementCooldown: 20,
      health: 30, damage: -2,
      actionRadiusSquared: 5, visionRadiusSquared: 20,
      bytecodeLimit: 7500),
    rtSoldier: RobotSpec(buildCostLead: 75,
      buildCostGold: 0,
      actionCooldown: 10, movementCooldown: 16,
      health: 50, damage: 3,
      actionRadiusSquared: 13, visionRadiusSquared: 20,
      bytecodeLimit: 10000),
    rtSage: RobotSpec(buildCostLead: 0,
      buildCostGold: 20,
      actionCooldown: 200, movementCooldown: 25,
      health: 100, damage: 45,
      actionRadiusSquared: 25, visionRadiusSquared: 34,
      bytecodeLimit: 10000),
  ]

  AnomalySpecs*: array[AnomalyKind, AnomalySpec] = [
    anAbyss: AnomalySpec(isGlobalAnomaly: true, isSageAnomaly: true,
      globalPercentage: 0.10000000149011612'f32,
      sagePercentage: 0.9900000095367432'f32),
    anCharge: AnomalySpec(isGlobalAnomaly: true, isSageAnomaly: true,
      globalPercentage: 0.05000000074505806'f32,
      sagePercentage: 0.2199999988079071'f32),
    anFury: AnomalySpec(isGlobalAnomaly: true, isSageAnomaly: true,
      globalPercentage: 0.05000000074505806'f32,
      sagePercentage: 0.10000000149011612'f32),
    anVortex: AnomalySpec(isGlobalAnomaly: true, isSageAnomaly: false,
      globalPercentage: 0.0'f32,
      sagePercentage: 0.0'f32),
  ]

