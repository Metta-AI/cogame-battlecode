## `years/bc26/constants.nim` is a GENERATED file. This shard proves it still
## describes engine.1.2.5.
##
## When the pinned engine checkout is present (`BC_ENGINE_DIR`, which
## `.github/workflows/ci.yml` fetches), the check is the real one: regenerate
## and byte-diff. Without it — a developer's laptop — the shard falls back to
## spot values transcribed from the tag, so it still fails on a hand-edit of
## anything load-bearing.

import std/[os, osproc, strutils]
import harness
import battlecode/years/bc26/constants

let engineDir = getEnv("BC_ENGINE_DIR")
if engineDir.len > 0 and dirExists(engineDir):
  let (output, code) = execCmdEx(
    "python3 tools/gen_year_constants.py --engine " & quoteShell(engineDir) &
    " --out src/battlecode/years/bc26/constants.nim --check")
  check("constants.nim is byte-identical to a fresh generation: " &
    output.strip(), code == 0)
else:
  echo "BC_ENGINE_DIR unset; falling back to spot values from the tag"

checkEq("EngineTag", EngineTag, "engine.1.2.5")
checkEq("GAME_MAX_NUMBER_OF_ROUNDS", GameMaxNumberOfRounds, 2000)
checkEq("INITIAL_TEAM_CHEESE", InitialTeamCheese, 2500)
checkEq("RAT_KING_CHEESE_CONSUMPTION", RatKingCheeseConsumption, 2)
checkEq("RAT_KING_HEALTH_LOSS", RatKingHealthLoss, 10)
checkEq("MAX_NUMBER_OF_RAT_KINGS", MaxNumberOfRatKings, 5)
checkEq("MAX_NUMBER_OF_RAT_KINGS_AFTER_CUTOFF", MaxNumberOfRatKingsAfterCutoff, 2)
checkEq("RAT_KING_CUTOFF_ROUND", RatKingCutoffRound, 1200)
checkEq("CAT_TRAP_ROUNDS_AFTER_BACKSTAB", CatTrapRoundsAfterBackstab, 100)
checkEq("COOLDOWNS_PER_TURN", CooldownsPerTurn, 10)
checkEq("COOLDOWN_LIMIT", CooldownLimit, 10)
checkEq("MOVE_STRAFE_COOLDOWN", MoveStrafeCooldown, 18)
checkEq("TURNING_COOLDOWN", TurningCooldown, 10)
checkEq("BUILD_ROBOT_COOLDOWN", BuildRobotCooldown, 10)
checkEq("CHEESE_TRANSFER_COOLDOWN", CheeseTransferCooldown, 10)
checkEq("DIG_COOLDOWN", DigCooldown, 25)
checkEq("THROW_RAT_COOLDOWN", ThrowRatCooldown, 20)
checkEq("HIT_GROUND_COOLDOWN", HitGroundCooldown, 10)
checkEq("HIT_TARGET_COOLDOWN", HitTargetCooldown, 20)
checkEq("CAT_DIG_ADDITIONAL_COOLDOWN", CatDigAdditionalCooldown, 5)
checkEq("CAT_SLEEP_TIME", CatSleepTime, 2)
checkEq("CAT_POUNCE_MAX_DISTANCE_SQUARED", CatPounceMaxDistanceSquared, 13)
checkEq("CAT_SCRATCH_DAMAGE", CatScratchDamage, 20)
checkEq("SQUEAK_RADIUS_SQUARED", SqueakRadiusSquared, 16)
checkEq("SHARED_ARRAY_SIZE", SharedArraySize, 64)
checkEq("CHEESE_SPAWN_AMOUNT", CheeseSpawnAmount, 20)
checkEq("SQ_CHEESE_SPAWN_RADIUS", SqCheeseSpawnRadius, 4)
checkEq("RAT_KING_UPGRADE_CHEESE_COST", RatKingUpgradeCheeseCost, 50)
checkEq("DIG_DIRT_CHEESE_COST", DigDirtCheeseCost, 5)
checkEq("PLACE_DIRT_CHEESE_COST", PlaceDirtCheeseCost, 0)
checkEq("BUILD_ROBOT_RADIUS_SQUARED", BuildRobotRadiusSquared, 8)
checkEq("MAX_CARRY_DURATION", MaxCarryDuration, 10)
checkEq("MAX_CARRY_TOWER_HEIGHT", MaxCarryTowerHeight, 2)
checkEq("SAME_ROBOT_CARRY_COOLDOWN_TURNS", SameRobotCarryCooldownTurns, 2)

## The carry multiplier is a DOUBLE that the engine casts to int before it
## multiplies, so it is 1 in every cooldown it touches. Ported as written.
check("CARRY_COOLDOWN_MULTIPLIER casts to 1", int(CarryCooldownMultiplier) == 1)
## CHEESE_MINE_SPAWN_PROBABILITY is a Java FLOAT, so `1 - it` widens to
## 0.9900000095367432, not 0.99 — which decides whether a long-quiet mine
## fires on a given round. Read through a `var` so the compiler cannot fold
## the comparison at full precision and hide the narrowing.
var spawnProbability = CheeseMineSpawnProbability
check("cheese spawn probability keeps float32 width",
  float64(spawnProbability) != 0.01)

checkEq("BABY_RAT spec", UnitSpecs[utBabyRat],
  UnitSpec(health: 100, size: 1, visionConeRadiusSquared: 20,
           visionConeAngle: 90, actionCooldown: 10, movementCooldown: 10,
           bytecodeLimit: 17500))
checkEq("RAT_KING spec", UnitSpecs[utRatKing],
  UnitSpec(health: 600, size: 3, visionConeRadiusSquared: 25,
           visionConeAngle: 360, actionCooldown: 10, movementCooldown: 40,
           bytecodeLimit: 20000))
checkEq("CAT spec", UnitSpecs[utCat],
  UnitSpec(health: 4000, size: 2, visionConeRadiusSquared: 17,
           visionConeAngle: 180, actionCooldown: 30, movementCooldown: 20,
           bytecodeLimit: 17500))
checkEq("RAT_TRAP spec", TrapSpecs[ttRatTrap],
  TrapSpec(buildCost: 20, damage: 50, stunTime: 30, actionCooldown: 15,
           maxCount: 25, triggerRadiusSquared: 2))
checkEq("CAT_TRAP spec", TrapSpecs[ttCatTrap],
  TrapSpec(buildCost: 10, damage: 100, stunTime: 20, actionCooldown: 10,
           maxCount: 10, triggerRadiusSquared: 2))

# ---------------------------------------------------------------------------
#  bc25 — the fifth generated constants table, and its two generated data sets
# ---------------------------------------------------------------------------
block:
  ## `BC25_DIR` is the pinned battlecode25 checkout `.github/workflows/ci.yml`
  ## fetches. With it, the check is the real one: regenerate the constants,
  ## re-convert all 22 committed maps, re-cut the sprite atlas and byte-diff
  ## every one of them, and read ALL 75 official `.map25` files with the
  ## converter's own vtable walk — a reader that only works on the maps we
  ## ship is a reader nobody can extend the pool with.
  let dir25 = getEnv("BC25_DIR")
  if dir25.len > 0 and dirExists(dir25):
    block:
      let (output, code) = execCmdEx(
        "python3 tools/gen_year_constants.py --year bc25 --engine " &
        quoteShell(dir25) & " --check")
      check("bc25 constants.nim is byte-identical to a fresh generation: " &
        output.strip(), code == 0)
    block:
      let (output, code) = execCmdEx(
        "python3 tools/convert_maps_bc25.py --engine " & quoteShell(dir25) &
        " --out data/maps/bc25 --check")
      check("the 22 committed bc25 maps re-convert identically: " &
        output.strip(), code == 0)
    block:
      let (output, code) = execCmdEx(
        "python3 tools/build_sprite_atlas_bc25.py --engine " &
        quoteShell(dir25) & " --out data --check")
      check("the bc25 sprite atlas is a fresh cut of the 2025 client art: " &
        output.strip(), code == 0)
    block:
      let (output, code) = execCmdEx(
        "python3 tools/convert_maps_bc25.py --engine " & quoteShell(dir25) &
        " --parse-all")
      check("the converter reads every official .map25", code == 0)
      var parsed = 0
      for line in output.splitLines():
        if line.len > 0 and line.contains("\t"): parsed += 1
      checkEq("all 75 of them", parsed, 75)
  else:
    echo "BC25_DIR unset; falling back to spot values from the pinned commit"

import battlecode/years/bc25/constants as c25

checkEq("bc25 EngineCommit", c25.EngineCommit,
  "28975a487c1a30ed2b5bed644fe6ecd2c3dd1482")
checkEq("bc25 OracleJarVersion", c25.OracleJarVersion, "3.1.0")
checkEq("bc25 SPEC_VERSION is the useless literal 1", c25.SpecVersion, "1")
checkEq("GAME_MAX_NUMBER_OF_ROUNDS", c25.GameMaxNumberOfRounds, 2000)
checkEq("PAINT_PERCENT_TO_WIN", c25.PaintPercentToWin, 70)
checkEq("MAP_MIN_WIDTH", c25.MapMinWidth, 20)
checkEq("MAP_MAX_WIDTH", c25.MapMaxWidth, 60)
checkEq("MIN_RUIN_SPACING_SQUARED", c25.MinRuinSpacingSquared, 25)
checkEq("MAX_NUMBER_OF_TOWERS", c25.MaxNumberOfTowers, 25)
checkEq("INITIAL_TEAM_MONEY", c25.InitialTeamMoney, 2500)
checkEq("INITIAL_TOWER_PAINT_AMOUNT", c25.InitialTowerPaintAmount, 500)
checkEq("INITIAL_ROBOT_PAINT_PERCENTAGE", c25.InitialRobotPaintPercentage, 100)
checkEq("PENALTY_NEUTRAL_TERRITORY", c25.PenaltyNeutralTerritory, 1)
checkEq("PENALTY_ENEMY_TERRITORY", c25.PenaltyEnemyTerritory, 2)
checkEq("MOPPER_PAINT_PENALTY_MULTIPLIER", c25.MopperPaintPenaltyMultiplier, 2)
checkEq("NO_PAINT_DAMAGE", c25.NoPaintDamage, 20)
checkEq("INCREASED_COOLDOWN_THRESHOLD", c25.IncreasedCooldownThreshold, 50)
checkEq("INCREASED_COOLDOWN_INTERCEPT", c25.IncreasedCooldownIntercept, 100)
checkEq("INCREASED_COOLDOWN_SLOPE", c25.IncreasedCooldownSlope, -2)
checkEq("VISION_RADIUS_SQUARED", c25.VisionRadiusSquared, 20)
checkEq("COOLDOWN_LIMIT", c25.CooldownLimit, 10)
checkEq("COOLDOWNS_PER_TURN", c25.CooldownsPerTurn, 10)
checkEq("MOVEMENT_COOLDOWN", c25.MovementCooldown, 10)
checkEq("BUILD_ROBOT_COOLDOWN", c25.BuildRobotCooldown, 10)
checkEq("ATTACK_MOPPER_SWING_COOLDOWN", c25.AttackMopperSwingCooldown, 20)
checkEq("PAINT_TRANSFER_COOLDOWN", c25.PaintTransferCooldown, 10)
checkEq("MARK_RADIUS_SQUARED", c25.MarkRadiusSquared, 2)
checkEq("PAINT_TRANSFER_RADIUS_SQUARED", c25.PaintTransferRadiusSquared, 2)
checkEq("BUILD_ROBOT_RADIUS_SQUARED", c25.BuildRobotRadiusSquared, 4)
checkEq("BUILD_TOWER_RADIUS_SQUARED", c25.BuildTowerRadiusSquared, 2)
checkEq("RESOURCE_PATTERN_RADIUS_SQUARED", c25.ResourcePatternRadiusSquared, 8)
checkEq("PATTERN_SIZE", c25.PatternSize, 5)
checkEq("MARK_PATTERN_PAINT_COST", c25.MarkPatternPaintCost, 25)
checkEq("COMPLETE_RESOURCE_PATTERN_COST", c25.CompleteResourcePatternCost, 200)
checkEq("EXTRA_RESOURCES_FROM_PATTERN", c25.ExtraResourcesFromPattern, 3)
checkEq("RESOURCE_PATTERN_ACTIVE_DELAY", c25.ResourcePatternActiveDelay, 50)
checkEq("EXTRA_DAMAGE_FROM_DEFENSE_TOWER", c25.ExtraDamageFromDefenseTower, 5)
checkEq("EXTRA_TOWER_DAMAGE_LEVEL_INCREASE",
  c25.ExtraTowerDamageLevelIncrease, 2)
checkEq("DEFENSE_ATTACK_BUFF_AOE_EFFECTIVENESS",
  c25.DefenseAttackBuffAoeEffectiveness, 0)
checkEq("SPLASHER_ATTACK_AOE_RADIUS_SQUARED",
  c25.SplasherAttackAoeRadiusSquared, 4)
checkEq("SPLASHER_ATTACK_ENEMY_PAINT_RADIUS_SQUARED",
  c25.SplasherAttackEnemyPaintRadiusSquared, 2)
checkEq("MOPPER_ATTACK_PAINT_DEPLETION", c25.MopperAttackPaintDepletion, 10)
checkEq("MOPPER_ATTACK_PAINT_ADDITION", c25.MopperAttackPaintAddition, 5)
checkEq("MOPPER_SWING_PAINT_DEPLETION", c25.MopperSwingPaintDepletion, 5)
checkEq("MESSAGE_RADIUS_SQUARED", c25.MessageRadiusSquared, 20)
checkEq("BROADCAST_RADIUS_SQUARED", c25.BroadcastRadiusSquared, 80)
checkEq("MESSAGE_ROUND_DURATION", c25.MessageRoundDuration, 5)
checkEq("MAX_MESSAGES_SENT_ROBOT", c25.MaxMessagesSentRobot, 1)
checkEq("MAX_MESSAGES_SENT_TOWER", c25.MaxMessagesSentTower, 20)
checkEq("the four pattern ints", [c25.ResourcePattern, c25.PaintTowerPattern,
  c25.MoneyTowerPattern, c25.DefenseTowerPattern],
  [28873275, 18157905, 15583086, 4685252])
checkEq("the DecisionOps budgets replace the bytecode limits",
  [c25.DecisionOpsRobot, c25.DecisionOpsTower], [1750, 2000])
checkEq("which are one tenth of the JVM's own",
  [c25.RobotBytecodeLimit div 10, c25.TowerBytecodeLimit div 10],
  [1750, 2000])

checkEq("SOLDIER spec", c25.UnitSpecs[c25.utSoldier],
  c25.UnitSpec(paintCost: 200, moneyCost: 250, attackCost: 5, health: 250,
    level: -1, paintCapacity: 200, actionCooldown: 10,
    actionRadiusSquared: 9, attackStrength: 50, aoeAttackStrength: -1,
    paintPerTurn: 0, moneyPerTurn: 0, attackMoneyBonus: 0))
checkEq("SPLASHER spec", c25.UnitSpecs[c25.utSplasher],
  c25.UnitSpec(paintCost: 300, moneyCost: 400, attackCost: 50, health: 150,
    level: -1, paintCapacity: 300, actionCooldown: 50,
    actionRadiusSquared: 4, attackStrength: -1, aoeAttackStrength: 100,
    paintPerTurn: 0, moneyPerTurn: 0, attackMoneyBonus: 0))
checkEq("MOPPER spec", c25.UnitSpecs[c25.utMopper],
  c25.UnitSpec(paintCost: 100, moneyCost: 300, attackCost: 0, health: 50,
    level: -1, paintCapacity: 100, actionCooldown: 30,
    actionRadiusSquared: 2, attackStrength: -1, aoeAttackStrength: -1,
    paintPerTurn: 0, moneyPerTurn: 0, attackMoneyBonus: 0))
checkEq("LEVEL_THREE_DEFENSE_TOWER spec",
  c25.UnitSpecs[c25.utLevelThreeDefenseTower],
  c25.UnitSpec(paintCost: 0, moneyCost: 5000, attackCost: 0, health: 3000,
    level: 3, paintCapacity: 1000, actionCooldown: 10,
    actionRadiusSquared: 16, attackStrength: 60, aoeAttackStrength: 30,
    paintPerTurn: 0, moneyPerTurn: 0, attackMoneyBonus: 40))
checkEq("LEVEL_TWO_PAINT_TOWER spec",
  c25.UnitSpecs[c25.utLevelTwoPaintTower],
  c25.UnitSpec(paintCost: 0, moneyCost: 2500, attackCost: 0, health: 1500,
    level: 2, paintCapacity: 1000, actionCooldown: 10,
    actionRadiusSquared: 9, attackStrength: 20, aoeAttackStrength: 10,
    paintPerTurn: 10, moneyPerTurn: 0, attackMoneyBonus: 0))
checkEq("LEVEL_TWO_MONEY_TOWER spec",
  c25.UnitSpecs[c25.utLevelTwoMoneyTower],
  c25.UnitSpec(paintCost: 0, moneyCost: 2500, attackCost: 0, health: 1500,
    level: 2, paintCapacity: 1000, actionCooldown: 10,
    actionRadiusSquared: 9, attackStrength: 20, aoeAttackStrength: 10,
    paintPerTurn: 0, moneyPerTurn: 30, attackMoneyBonus: 0))

finish("test_constants")
