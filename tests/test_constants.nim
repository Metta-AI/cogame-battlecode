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

finish("test_constants")
