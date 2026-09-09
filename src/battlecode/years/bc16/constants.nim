## Battlecode 2016 "Zombie Invasion" gameplay constants -- GENERATED, do not edit.
##
## Source: github.com/battlecode/battlecode-server-2016 at commit `11a0b09f26a70da19f33a61ebec4ceaf6e161aa3`,
## files `common/GameConstants.java` and `common/RobotType.java`,
## read by `tools/gen_year_constants.py --year bc16`. The `test` job
## of `.github/workflows/ci.yml` re-runs that generator with
## `--check`, which byte-diffs this file, so an edit here fails the
## build instead of quietly changing the rules under a `GameVersion`
## that no longer describes them.
##
## THE OFFICIAL 2016 SPEC IS LOST (dead S3, dead battlecode.org, no
## Wayback copy) and there is NO `SPEC_VERSION` field in this year's
## `GameConstants` -- so the engine source IS the spec, this table is
## its transcription, and the oracle jar is pinned by sha256 AND size
## in `tools/oracle/bc16/jar.lock` instead of by a version string.
##
## 2016 IS A FLOAT64 YEAR: health, damage, both delay counters,
## rubble, parts and every multiplier are Java `double`, and there is
## NO float32 anywhere in the rule set. IEEE-754 binary64 add,
## subtract, multiply, divide and compare are exactly specified and
## identical on x86-64 SSE2 and on wasm32, so reproducing each
## expression in the engine's own order is bit-exact by construction.
## The two non-algebraic functions on gameplay paths --
## `Math.pow(x, 1.5)` in `decrementDelays` and `(int) Math.sqrt(r2)`
## in the radius scans -- both have finite domains and are TABLED in
## `data/bc16/tables.json`, so the runtime path has no
## transcendental at all.

const EngineCommit* = "11a0b09f26a70da19f33a61ebec4ceaf6e161aa3"
const OracleJarVersion* = "2016.0.2.2"

type
  RobotType* = enum
    ## `common/RobotType.java` in `values()` order. THE ORDINAL IS
    ## LOAD-BEARING: `ZombieCount.compareTo` sorts by it and the den's
    ## spawn priority reads it (the no-`break` loop takes the LAST
    ## non-zero type, so the priority is BIGZOMBIE, FASTZOMBIE,
    ## RANGEDZOMBIE, STANDARDZOMBIE).
    rtZombieden = "ZOMBIEDEN"
    rtStandardzombie = "STANDARDZOMBIE"
    rtRangedzombie = "RANGEDZOMBIE"
    rtFastzombie = "FASTZOMBIE"
    rtBigzombie = "BIGZOMBIE"
    rtArchon = "ARCHON"
    rtScout = "SCOUT"
    rtSoldier = "SOLDIER"
    rtGuard = "GUARD"
    rtViper = "VIPER"
    rtTurret = "TURRET"
    rtTtm = "TTM"

  RobotSpec* = object
    ## `common/RobotType.java`'s seventeen constructor arguments, in
    ## the file's own order. `spawnSource` and `turnsInto` are the
    ## ORDINAL of the named type, or -1 for the engine's `null`.
    isBuilding*, isZombie*: bool
    infectTurns*, spawnSource*: int
    partCost*, buildTurns*: int
    maxHealth*, attackPower*: float64
    attackRadiusSquared*: int
    movementDelay*, attackDelay*, cooldownDelay*: float64
    sensorRadiusSquared*, bytecodeLimit*, strengthWeight*: int
    turnsInto*: int
    ignoresRubble*: bool

const
  MapMinHeight*: int = 30
  MapMaxHeight*: int = 80
  MapMinWidth*: int = 30
  MapMaxWidth*: int = 80
  TeamMemoryLength*: int = 32
  NumberOfIndicatorStrings*: int = 3
  ExceptionBytecodePenalty*: int = 500
  NumberOfArchonsMax*: int = 4
  BroadcastRangeMultiplier*: float64 = 2.0
  BroadcastBaseDelayIncrease*: float64 = 0.05
  BroadcastAdditionalDelayIncrease*: float64 = 0.03
  PartsInitialAmount*: float64 = 300.0
  ArchonPartIncome*: float64 = 2.0
  PartIncomeUnitPenalty*: float64 = 0.01
  DenPartReward*: float64 = 200.0
  RubbleObstructionThresh*: float64 = 100.0
  RubbleSlowThresh*: float64 = 50.0
  RubbleClearPercentage*: float64 = 0.05
  RubbleClearFlatAmount*: float64 = 10.0
  RubbleFromTurretFactor*: float64 = 0.3333333333333333
  GuardZombieMultiplier*: float64 = 2.0
  GuardDefenseThreshold*: float64 = 10.0
  GuardDamageReduction*: float64 = 4.0
  ViperInfectionDamage*: float64 = 2.0
  TurretMinimumRange*: int = 6
  TurretTransformDelay*: int = 10
  DiagonalDelayMultiplier*: float64 = 1.4
  ArchonRepairAmount*: float64 = 1.0
  ArchonActivationRange*: int = 2
  DenSpawnProximityDamage*: float64 = 10.0
  OutbreakTimer*: int = 300
  ArmageddonDayTimer*: int = 300
  ArmageddonNightTimer*: int = 900
  ArmageddonDayOutbreakMultiplier*: float64 = 1.0
  ArmageddonNightOutbreakMultiplier*: float64 = 2.0
  ArmageddonDayZombieRegeneration*: float64 = -0.2
  ArmageddonNightZombieRegeneration*: float64 = 0.05
  SignalQueueMaxSize*: int = 1000
  BasicSignalsPerTurn*: int = 5
  MessageSignalsPerTurn*: int = 20
  GameDefaultSeed*: int = 6370
  GameDefaultRounds*: int = 3000

  DecisionOpsWide*: int = 2000
  DecisionOpsStandard*: int = 1000
    ## Replace `RobotType.bytecodeLimit` outside the JVM: 2000 for an
    ## ARCHON and a SCOUT, 1000 for everything else, 0 for a robot
    ## with `!isActive()`. No mid-turn resumption, no mid-primitive
    ## cut, enforced by the sim rather than by the bot.

  RobotSpecs*: array[RobotType, RobotSpec] = [
    rtZombieden: RobotSpec(isBuilding: true, isZombie: true,
      infectTurns: 0, spawnSource: -1,
      partCost: 0, buildTurns: 0,
      maxHealth: 2000, attackPower: 0,
      attackRadiusSquared: 0,
      movementDelay: 0, attackDelay: 0,
      cooldownDelay: 0,
      sensorRadiusSquared: -1, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: -1,
      ignoresRubble: false),
    rtStandardzombie: RobotSpec(isBuilding: false, isZombie: true,
      infectTurns: 10, spawnSource: 0,
      partCost: 0, buildTurns: 0,
      maxHealth: 60, attackPower: 2.5,
      attackRadiusSquared: 2,
      movementDelay: 3, attackDelay: 2,
      cooldownDelay: 1,
      sensorRadiusSquared: -1, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: -1,
      ignoresRubble: false),
    rtRangedzombie: RobotSpec(isBuilding: false, isZombie: true,
      infectTurns: 10, spawnSource: 0,
      partCost: 0, buildTurns: 0,
      maxHealth: 60, attackPower: 3,
      attackRadiusSquared: 13,
      movementDelay: 3, attackDelay: 1,
      cooldownDelay: 1,
      sensorRadiusSquared: -1, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: -1,
      ignoresRubble: false),
    rtFastzombie: RobotSpec(isBuilding: false, isZombie: true,
      infectTurns: 10, spawnSource: 0,
      partCost: 0, buildTurns: 0,
      maxHealth: 80, attackPower: 3,
      attackRadiusSquared: 2,
      movementDelay: 1.4, attackDelay: 1,
      cooldownDelay: 1,
      sensorRadiusSquared: -1, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: -1,
      ignoresRubble: true),
    rtBigzombie: RobotSpec(isBuilding: false, isZombie: true,
      infectTurns: 10, spawnSource: 0,
      partCost: 0, buildTurns: 0,
      maxHealth: 500, attackPower: 25,
      attackRadiusSquared: 2,
      movementDelay: 4, attackDelay: 3,
      cooldownDelay: 2,
      sensorRadiusSquared: -1, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: -1,
      ignoresRubble: true),
    rtArchon: RobotSpec(isBuilding: false, isZombie: false,
      infectTurns: 0, spawnSource: -1,
      partCost: 0, buildTurns: 0,
      maxHealth: 1000, attackPower: 0,
      attackRadiusSquared: 24,
      movementDelay: 2, attackDelay: 1,
      cooldownDelay: 1,
      sensorRadiusSquared: 35, bytecodeLimit: 20000,
      strengthWeight: 0, turnsInto: 4,
      ignoresRubble: false),
    rtScout: RobotSpec(isBuilding: false, isZombie: false,
      infectTurns: 0, spawnSource: 5,
      partCost: 25, buildTurns: 20,
      maxHealth: 80, attackPower: 0,
      attackRadiusSquared: 0,
      movementDelay: 1.4, attackDelay: 0,
      cooldownDelay: 1,
      sensorRadiusSquared: 53, bytecodeLimit: 20000,
      strengthWeight: 0, turnsInto: 3,
      ignoresRubble: true),
    rtSoldier: RobotSpec(isBuilding: false, isZombie: false,
      infectTurns: 0, spawnSource: 5,
      partCost: 30, buildTurns: 12,
      maxHealth: 60, attackPower: 4,
      attackRadiusSquared: 13,
      movementDelay: 2, attackDelay: 2,
      cooldownDelay: 1,
      sensorRadiusSquared: 24, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: 1,
      ignoresRubble: false),
    rtGuard: RobotSpec(isBuilding: false, isZombie: false,
      infectTurns: 0, spawnSource: 5,
      partCost: 30, buildTurns: 10,
      maxHealth: 145, attackPower: 1.5,
      attackRadiusSquared: 2,
      movementDelay: 2, attackDelay: 1,
      cooldownDelay: 1,
      sensorRadiusSquared: 24, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: 1,
      ignoresRubble: false),
    rtViper: RobotSpec(isBuilding: false, isZombie: false,
      infectTurns: 20, spawnSource: 5,
      partCost: 120, buildTurns: 30,
      maxHealth: 120, attackPower: 2,
      attackRadiusSquared: 20,
      movementDelay: 2, attackDelay: 3,
      cooldownDelay: 1,
      sensorRadiusSquared: 24, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: 2,
      ignoresRubble: false),
    rtTurret: RobotSpec(isBuilding: false, isZombie: false,
      infectTurns: 0, spawnSource: 5,
      partCost: 130, buildTurns: 25,
      maxHealth: 100, attackPower: 13,
      attackRadiusSquared: 40,
      movementDelay: 0, attackDelay: 3,
      cooldownDelay: 3,
      sensorRadiusSquared: 24, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: 2,
      ignoresRubble: false),
    rtTtm: RobotSpec(isBuilding: false, isZombie: false,
      infectTurns: 0, spawnSource: 10,
      partCost: 130, buildTurns: 10,
      maxHealth: 100, attackPower: 0,
      attackRadiusSquared: 0,
      movementDelay: 2, attackDelay: 0,
      cooldownDelay: 2,
      sensorRadiusSquared: 24, bytecodeLimit: 10000,
      strengthWeight: 0, turnsInto: 2,
      ignoresRubble: false),
  ]

  OutbreakMultipliers*: array[13, float64] = [
    ## `RobotType.getOutbreakMultiplier(round)`'s own switch for
    ## levels 0..9, then its `default: 3.00 + (level - 9)` arm for
    ## 10..12. `level = round / OUTBREAK_TIMER` (integer), applied to
    ## a ZOMBIE's maxHealth and attackPower AT THE MOMENT IT SPAWNS
    ## and never afterwards; a player unit never scales. A
    ## 3000-round game's last round is 2999, so level 9 is the last
    ## one a spawn actually reaches -- 10..12 are tabled anyway.
    1.0,
    1.1,
    1.2,
    1.3,
    1.5,
    1.7,
    2.0,
    2.3,
    2.6,
    3.0,
    4.0,
    5.0,
    6.0,
  ]

