## Battlecode 2017 "Robotic Wildlife Fund" gameplay constants -- GENERATED, do not edit.
##
## Source: the PINNED ORACLE JAR's own classes, reflected by
## `tools/JavaBc17Tables.java constants` under Temurin 8 and rendered
## by `tools/gen_year_constants.py --year bc17 --tables`. 2017's
## `GameConstants` is an INTERFACE, so its fields are implicitly
## `public static final` and reflection sees every one of them; the
## `RobotType` table is read out of `values()` so the ORDINAL -- which
## is the wire order, the atlas index and the `Bc17UnitNames` index --
## is the engine's own.
##
## The `parity-oracle-bc17` job re-runs that pair with `--check`,
## which byte-diffs this file, so an edit here fails the build instead
## of quietly changing the rules under a `GameVersion` that no longer
## describes them. The reflection needs a JVM, which is why the
## constants byte-diff lives in the oracle job and not in `test`;
## the MAP conversion is pure Python and runs in `test`.
##
## 2017 IS THE FLOAT32 YEAR AND THE ONLY CONTINUOUS-SPACE ONE:
## coordinates, radii, strides, bullet speeds, attack powers, health
## and the whole tree economy are Java `float`, every gameplay class
## is `strictfp`, and the transcendental surface is exactly
## `{sin, cos, atan2}` -- ported from fdlibm into
## `src/battlecode/fdlibm.nim` and pinned against the JVM's own
## `StrictMath` by `data/bc17/fdlibm_vectors.json`
## (docs/RULES-BC17.md F1-F5).

const EngineCommit* = "165d8a8ef24f03e13a101bb8bc9f5b32dcb33c6c"
const OracleJarVersion* = "2017.1.6.2"

type
  RobotType* = enum
    ## `common/RobotType.java` in `values()` order. THE ORDINAL IS
    ## LOAD-BEARING: it is the flatbuffer `BodyType` ordinal, the
    ## `Bc17UnitNames` index and the atlas cell index.
    rtArchon = "ARCHON"
    rtGardener = "GARDENER"
    rtLumberjack = "LUMBERJACK"
    rtSoldier = "SOLDIER"
    rtTank = "TANK"
    rtScout = "SCOUT"

  RobotSpec* = object
    ## `common/RobotType.java`'s eleven constructor arguments in the
    ## file's own order, plus the two derived values the engine
    ## computes. `spawnSource` is the ORDINAL of the named type, or
    ## -1 for the engine's `null` (ARCHON alone).
    ##
    ## `maxHealth` and `bulletCost` are Java `int`, and
    ## `ARCHON.bulletCost == -1` IS A RULE, NOT A SENTINEL: the
    ## round-2999 tiebreak rung 3 sums `type.bulletCost` over live
    ## robots, so every surviving archon SUBTRACTS one bullet from
    ## its own team's total (docs/RULES-BC17.md, spec-vs-engine
    ## disagreement 3).
    spawnSource*: int
    buildCooldownTurns*: int
    maxHealth*: int
    bulletCost*: int
    bodyRadius*: float32
    bulletSpeed*: float32
    attackPower*: float32
    sensorRadius*: float32
    bulletSightRadius*: float32
    strideRadius*: float32
    bytecodeLimit*: int
    startingHealth*: float32
      ## `getStartingHealth()` = `maxHealth` for an ARCHON and a
      ## GARDENER, `0.2f * maxHealth` for the four fighters -- so a
      ## SOLDIER is born at exactly 10.0, a TANK at 40.0 and a SCOUT
      ## at 2.0, and every fighter is DORMANT for its first 20 turns
      ## while it heals 4 % a turn.

const
  archonBulletIncome* = 2'f32
  broadcastMaxChannels* = 10000
  bulletsInitialAmount* = 300'f32
  bulletIncomeUnitPenalty* = 0.01'f32
  bulletSpawnOffset* = 0.05'f32
  bulletTreeBulletProductionRate* = 0.02'f32
  bulletTreeConstructionCooldown* = 10
  bulletTreeCost* = 50'f32
  bulletTreeDecayRate* = 0.5'f32
  bulletTreeMaxHealth* = 50'f32
  bulletTreeRadius* = 1'f32
  exceptionBytecodePenalty* = 500
  gameDefaultRounds* = 3000
  gameDefaultSeed* = 6370
  generalSpawnOffset* = 0.01'f32
  interactionDistFromEdge* = 1'f32
  lumberjackChopDamage* = 5'f32
  lumberjackStrikeRadius* = 2'f32
  mapMaxHeight* = 100
  mapMaxWidth* = 100
  mapMinHeight* = 30
  mapMinWidth* = 30
  maxRobotId* = 32000
  maxRobotRadius* = 2'f32
  neutralTreeHealthRate* = 200'f32
  neutralTreeMaxRadius* = 10'f32
  neutralTreeMinRadius* = 0.5'f32
  numberOfArchonsMax* = 3
  numberOfIndicatorStrings* = 3
  pentadShotCost* = 6'f32
  pentadSpreadDegrees* = 15'f32
  plantedUnitStartingHealthFraction* = 0.2'f32
  singleShotCost* = 1'f32
  specVersion* = "1.0"
  tankBodyDamage* = 4'f32
  teamMemoryLength* = 32
  triadShotCost* = 4'f32
  triadSpreadDegrees* = 20'f32
  victoryPointsToWin* = 1000
  vpBaseCost* = 7.5'f32
  vpIncreasePerRound* = 0.004166667'f32
  waterHealthRegenRate* = 5'f32

const
  ArchonOps* = 3000
    ## `ARCHON.bytecodeLimit / 10` (V1).
  UnitOps* = 1500
    ## `15000 / 10` for the other five types (V1).
  DormantOps* = 0
    ## NOT the divergence -- THE RULE. `getBytecodeLimit()` returns 0
    ## unless `canExecuteCode()`, i.e.
    ## `health > 0 && (isBuildable() ? roundsAlive >= 20 : true)`,
    ## so a newly built fighter does nothing at all for twenty turns
    ## (`InternalRobot.java:281-287`).
  DormancyRounds* = 20
  TreeGrowthRounds* = 80
    ## `updateTree` grows while `roundsAlive <= 80` and pays NOTHING
    ## during those 81 turns (spec-vs-engine disagreement 5).

const RobotSpecs*: array[RobotType, RobotSpec] = [
  rtArchon: RobotSpec(spawnSource: -1, buildCooldownTurns: 0,
    maxHealth: 400, bulletCost: -1,
    bodyRadius: 2'f32, bulletSpeed: -1'f32,
    attackPower: -1'f32, sensorRadius: 10'f32,
    bulletSightRadius: 15'f32, strideRadius: 0.5'f32,
    bytecodeLimit: 30000, startingHealth: 400'f32),
  rtGardener: RobotSpec(spawnSource: 0, buildCooldownTurns: 10,
    maxHealth: 40, bulletCost: 100,
    bodyRadius: 1'f32, bulletSpeed: -1'f32,
    attackPower: -1'f32, sensorRadius: 7'f32,
    bulletSightRadius: 10'f32, strideRadius: 0.5'f32,
    bytecodeLimit: 15000, startingHealth: 40'f32),
  rtLumberjack: RobotSpec(spawnSource: 1, buildCooldownTurns: 10,
    maxHealth: 50, bulletCost: 100,
    bodyRadius: 1'f32, bulletSpeed: -1'f32,
    attackPower: 2'f32, sensorRadius: 7'f32,
    bulletSightRadius: 10'f32, strideRadius: 0.75'f32,
    bytecodeLimit: 15000, startingHealth: 10'f32),
  rtSoldier: RobotSpec(spawnSource: 1, buildCooldownTurns: 10,
    maxHealth: 50, bulletCost: 100,
    bodyRadius: 1'f32, bulletSpeed: 2'f32,
    attackPower: 2'f32, sensorRadius: 7'f32,
    bulletSightRadius: 10'f32, strideRadius: 0.8'f32,
    bytecodeLimit: 15000, startingHealth: 10'f32),
  rtTank: RobotSpec(spawnSource: 1, buildCooldownTurns: 10,
    maxHealth: 200, bulletCost: 300,
    bodyRadius: 2'f32, bulletSpeed: 4'f32,
    attackPower: 5'f32, sensorRadius: 7'f32,
    bulletSightRadius: 10'f32, strideRadius: 0.5'f32,
    bytecodeLimit: 15000, startingHealth: 40'f32),
  rtScout: RobotSpec(spawnSource: 1, buildCooldownTurns: 10,
    maxHealth: 10, bulletCost: 80,
    bodyRadius: 1'f32, bulletSpeed: 1.5'f32,
    attackPower: 0.5'f32, sensorRadius: 14'f32,
    bulletSightRadius: 20'f32, strideRadius: 1.25'f32,
    bytecodeLimit: 15000, startingHealth: 2'f32),
]

func canAttack*(t: RobotType): bool = RobotSpecs[t].attackPower > 0
  ## `attackPower > 0` -- so an ARCHON and a GARDENER can NEVER
  ## attack, and the two `-1`s in the table are why.
func canHire*(t: RobotType): bool = t == rtArchon
func canBuild*(t: RobotType): bool = t == rtGardener
func isHireable*(t: RobotType): bool = RobotSpecs[t].spawnSource == ord(rtArchon)
func isBuildable*(t: RobotType): bool = RobotSpecs[t].spawnSource == ord(rtGardener)
func opsFor*(t: RobotType): int = (if t == rtArchon: ArchonOps else: UnitOps)
