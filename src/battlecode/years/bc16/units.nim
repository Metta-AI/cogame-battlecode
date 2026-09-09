## The bc16 value types and the PURE per-unit arithmetic.
##
## Everything in this file is a function of its arguments alone: the twelve-row
## `RobotType` table read straight out of `constants.nim`, the eight derived
## predicates, the outbreak ladder, the move-cost factors, the guard
## multiplier and reduction, the rubble-clear map, `directionTo`'s 2.414 fan
## and the tabled `(int) Math.sqrt(r2)`. Nothing here touches a `World`, which
## is what lets `world.nim` import it.
##
## Ported from `battlecode/battlecode-server-2016` at commit
## `11a0b09f26a70da19f33a61ebec4ceaf6e161aa3`: `common/RobotType.java`,
## `common/Direction.java`, `common/MapLocation.java`, `common/Team.java` and
## the arithmetic halves of `world/GameWorld.java` and
## `world/RobotControllerImpl.java`.
##
## FIVE PIECES OF ARITHMETIC IN HERE ARE LOAD-BEARING and are ported literally:
##
## * **2016 is a FLOAT64 year.** Health, damage, both delay counters, rubble,
##   parts and every multiplier are Java `double`. IEEE-754 binary64
##   add/subtract/multiply/divide/compare are exactly specified and identical
##   on x86-64 SSE2 and on wasm32, so reproducing each expression IN THE
##   ENGINE'S OWN ORDER AND PARENTHESISATION is bit-exact by construction.
##   Nothing here re-associates or factors: `100 * 0.95 - 10` is written the
##   way `visitClearRubbleSignal` writes it, `2 * 1.4 * 2` the way `move()`
##   does.
## * **`directionTo` uses the engine's own doubles**, not an integer
##   rescaling: `Math.abs(dx) >= 2.414 * Math.abs(dy)` with `2.414` as the
##   double the literal denotes. An integer form (`ax*1000 >= ay*2414`) is a
##   DIFFERENT predicate on some lattice points, and this direction decides
##   every zombie's step and every den's spawn ring.
## * **`(int) Math.sqrt(r2)` is TABLED for r2 = 0..10 000**, so there is no
##   `sqrt` on any runtime path. `Math.sqrt` is exactly rounded, so the
##   integer-search table below is the same value for every argument in range.
## * **The outbreak multiplier applies to a ZOMBIE's `maxHealth` and
##   `attackPower` AT THE MOMENT IT SPAWNS** (`InternalRobot.java:68,70`) and
##   never afterwards; a player unit never scales
##   (`RobotType.java:352-358`).
## * **The GUARD pair**: a GUARD ATTACKER doubles its damage against a zombie
##   TARGET (`rate = 2.0`), and a GUARD TARGET hit for MORE THAN 10.0 takes
##   `damage - 4.0`. The threshold is strict `>`; 10 exactly is unreduced.

import constants

export constants

type
  Team* = enum
    ## `common/Team.java` in `values()` order, which is the index space the
    ## converted map file's `team` column lives in. FOUR values: the horde and
    ## the neutrals are real teams that own real robots.
    teamA = 0
    teamB = 1
    teamNeutral = 2
    teamZombie = 3

  Dir* = enum
    ## `common/Direction.java` in `values()` order. NOTE THE Y AXIS: 2016's
    ## NORTH is `(0, -1)` — y grows SOUTHWARD — which is the opposite of
    ## bc22's port and is why this year has its own `Dir`.
    ## `ZombieControlProvider.DIRECTIONS` is exactly the first eight, in this
    ## order, and `random.nextInt(8)` indexes it.
    dNorth = 0
    dNortheast
    dEast
    dSoutheast
    dSouth
    dSouthwest
    dWest
    dNorthwest
    dNone
    dOmni

  Symmetry* = enum
    ## `world/GameMap.Symmetry` in `values()` order, which is ALSO the
    ## first-wins test order of `updateSymmetries` (D4). Only the winner is
    ## read at run time, and only by `getSpawnChirality`.
    symVertical = "vertical"
    symHorizontal = "horizontal"
    symRotational = "rotational"
    symNegativeDiagonal = "negative_diagonal"
    symPositiveDiagonal = "positive_diagonal"
    symNone = "none"

  Loc* = object
    x*, y*: int

  Domination* = enum
    ## `world/DominationFactor.java` in this repo's snake_case `end_reason`
    ## vocabulary. `ZOMBIFIED` and `CLEANSED` have no values: both are
    ## reachable only on armageddon maps, which are out of scope (V4).
    ## `RESIGNATION` has none either: `rc.resign()` is a real engine method
    ## but a doctrine is a JSON sheet and neither chassis can call it (V5).
    dfNone
    dfDestroyed = "archons_destroyed"
    dfPwned = "more_archons"
    dfOwned = "more_archon_health"
    dfBarelyBeat = "more_parts_net_worth"
    dfDubious = "highest_id"

  DeathCause* = enum
    ## `world/signal/DeathSignal.RobotDeathCause`. `TURRET` cuts the corpse's
    ## rubble to a third; `ACTIVATION` skips BOTH the rubble deposit and the
    ## infection conversion.
    dcNormal
    dcTurret
    dcActivation

const
  MoveDirs* = [dNorth, dNortheast, dEast, dSoutheast,
               dSouth, dSouthwest, dWest, dNorthwest]
    ## `ZombieControlProvider.DIRECTIONS`, and the eight `move`/`build`
    ## directions. The ORDER IS A RULE: `random.nextInt(8)` indexes it and
    ## `DIRECTIONS[floorMod(start + i * chir, 8)]` walks it.

  ZombieSpawnTypes* = [rtStandardzombie, rtRangedzombie, rtFastzombie,
                       rtBigzombie]
    ## `ZombieControlProvider.ZOMBIE_TYPES`. `spawnAllPossible`'s type loop has
    ## NO `break`, so it keeps the LAST non-zero entry — i.e. the spawn
    ## priority is BIGZOMBIE, then FASTZOMBIE, then RANGEDZOMBIE, then
    ## STANDARDZOMBIE.

  PlayerTypes* = [rtArchon, rtScout, rtSoldier, rtGuard, rtViper, rtTurret,
                  rtTtm]

  BuildableByArchon* = [rtScout, rtSoldier, rtGuard, rtViper, rtTurret]
    ## `isBuildable() and spawnSource == ARCHON`. TTM is NOT here: its
    ## `spawnSource` is TURRET, so a TTM is not buildable at all and is only
    ## reachable by packing.

  IntSqrtMax* = 10_000
  IntSqrtTable*: array[IntSqrtMax + 1, int] = block:
    ## `(int) Math.sqrt(r2)` for every squared radius the 2016 rule set can
    ## reach, so there is no `sqrt` and therefore no `fdlibm` path anywhere on
    ## a runtime path. `Math.sqrt` is exactly rounded for a `double` argument,
    ## so truncating it equals the integer floor computed here.
    var t: array[IntSqrtMax + 1, int]
    var k = 0
    for r2 in 0 .. IntSqrtMax:
      while (k + 1) * (k + 1) <= r2: inc k
      t[r2] = k
    t

func isPlayer*(t: Team): bool = t == teamA or t == teamB
  ## `Team.isPlayer()`. NEUTRAL and ZOMBIE are not players, which is what
  ## `getNearestPlayerControlled` filters on.

func opponent*(t: Team): Team =
  ## `Team.opponent()`: A <-> B, and NEUTRAL/ZOMBIE map to themselves.
  case t
  of teamA: teamB
  of teamB: teamA
  else: t

func other*(t: Team): Team = t.opponent()

func dx*(d: Dir): int =
  case d
  of dNorth, dSouth, dNone, dOmni: 0
  of dNortheast, dEast, dSoutheast: 1
  of dSouthwest, dWest, dNorthwest: -1

func dy*(d: Dir): int =
  ## 2016's y axis points SOUTH: NORTH is `(0, -1)`.
  case d
  of dEast, dWest, dNone, dOmni: 0
  of dNorth, dNortheast, dNorthwest: -1
  of dSoutheast, dSouth, dSouthwest: 1

func isDiagonal*(d: Dir): bool =
  ## `Direction.isDiagonal()`: `ordinal() < 8 and ordinal() % 2 == 1`.
  ord(d) < 8 and (ord(d) mod 2) == 1

func opposite*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 4) mod 8)

func rotateLeft*(d: Dir): Dir =
  if ord(d) >= 8: d elif ord(d) == 0: dNorthwest else: Dir(ord(d) - 1)

func rotateRight*(d: Dir): Dir =
  if ord(d) >= 8: d elif ord(d) == 7: dNorth else: Dir(ord(d) + 1)

func loc*(x, y: int): Loc = Loc(x: x, y: y)
func `+`*(a: Loc, d: Dir): Loc = loc(a.x + d.dx, a.y + d.dy)
func `==`*(a, b: Loc): bool = a.x == b.x and a.y == b.y
func translate*(a: Loc, ddx, ddy: int): Loc = loc(a.x + ddx, a.y + ddy)

func distanceSquaredTo*(a, b: Loc): int =
  let ddx = a.x - b.x
  let ddy = a.y - b.y
  ddx * ddx + ddy * ddy

func isAdjacentTo*(a, b: Loc): bool =
  let d = a.distanceSquaredTo(b)
  d == 1 or d == 2

func chebyshev*(a, b: Loc): int = max(abs(a.x - b.x), abs(a.y - b.y))

func compareLoc*(a, b: Loc): int =
  ## `MapLocation.compareTo`: x first, then y. `getSpawnChirality` reads only
  ## its SIGN, and the expression is translation invariant, which is why the
  ## origin can be dropped (V3).
  if a.x != b.x: a.x - b.x else: a.y - b.y

func directionTo*(a, b: Loc): Dir =
  ## `MapLocation.directionTo` (`:146-183`), with the engine's own doubles.
  ## Equal locations give OMNI. THIS IS THE WHOLE ZOMBIE TARGETING GEOMETRY
  ## and the den spawn ring's start, so the comparison is written exactly as
  ## the engine writes it rather than rescaled into integers.
  let ddx = float64(b.x - a.x)
  let ddy = float64(b.y - a.y)
  if abs(ddx) >= 2.414 * abs(ddy):
    if ddx > 0.0: return dEast
    elif ddx < 0.0: return dWest
    else: return dOmni
  elif abs(ddy) >= 2.414 * abs(ddx):
    return (if ddy > 0.0: dSouth else: dNorth)
  else:
    if ddy > 0.0:
      return (if ddx > 0.0: dSoutheast else: dSouthwest)
    else:
      return (if ddx > 0.0: dNortheast else: dNorthwest)

func intSqrt*(r2: int): int =
  ## The tabled `(int) Math.sqrt(radiusSquared)`, clamped to the table.
  if r2 <= 0: 0
  elif r2 >= IntSqrtMax: IntSqrtTable[IntSqrtMax]
  else: IntSqrtTable[r2]

# ---------------------------------------------------------------------------
#  The per-type table and its eight derived predicates
# ---------------------------------------------------------------------------

func spec*(k: RobotType): RobotSpec = RobotSpecs[k]

func typeOfOrdinal*(o: int): RobotType =
  ## The converted map file's `type` column and the spec table's
  ## `spawnSource` / `turnsInto` are ORDINALS.
  RobotType(o)

func canAttack*(k: RobotType): bool = RobotSpecs[k].attackPower > 0.0
  ## `RobotType.canAttack()`. ARCHON, SCOUT, TTM and ZOMBIEDEN cannot attack.

func canInfect*(k: RobotType): bool = RobotSpecs[k].infectTurns > 0
  ## VIPER and all four zombies.

func isZombieType*(k: RobotType): bool = RobotSpecs[k].isZombie

func isInfectable*(k: RobotType): bool =
  ## `!isZombie && this != ZOMBIEDEN` — EVERY player unit, archons included.
  (not RobotSpecs[k].isZombie) and k != rtZombieden

func canMoveType*(k: RobotType): bool = k != rtZombieden and k != rtTurret

func canBuildType*(k: RobotType): bool = k == rtArchon or k == rtZombieden

func canMessageSignal*(k: RobotType): bool = k == rtArchon or k == rtScout

func isBuildable*(k: RobotType): bool =
  ## `spawnSource == ARCHON || spawnSource == ZOMBIEDEN`. TTM's spawnSource is
  ## TURRET, so a TTM is NOT buildable and can only be reached by packing.
  RobotSpecs[k].spawnSource == ord(rtArchon) or
    RobotSpecs[k].spawnSource == ord(rtZombieden)

func canClearRubble*(k: RobotType): bool = k != rtTurret and k != rtTtm

func ignoresRubble*(k: RobotType): bool = RobotSpecs[k].ignoresRubble

func turnsInto*(k: RobotType): RobotType =
  ## `RobotType.turnsInto`. ARCHON -> BIGZOMBIE, SCOUT -> FASTZOMBIE,
  ## SOLDIER and GUARD -> STANDARDZOMBIE, VIPER/TURRET/TTM -> RANGEDZOMBIE.
  ## Only ever read for an infectable type, all of which have one.
  RobotType(RobotSpecs[k].turnsInto)

func hasTurnsInto*(k: RobotType): bool = RobotSpecs[k].turnsInto >= 0

func partCost*(k: RobotType): int = RobotSpecs[k].partCost
func buildTurns*(k: RobotType): int = RobotSpecs[k].buildTurns
func sightRadiusSquared*(k: RobotType): int = RobotSpecs[k].sensorRadiusSquared
func attackRadiusSquared*(k: RobotType): int =
  RobotSpecs[k].attackRadiusSquared

func budgetFor*(k: RobotType): int =
  ## The `DecisionOps` budget that replaces `RobotType.bytecodeLimit` (V2):
  ## one tenth of the engine's own limit. A ZOMBIEDEN and a zombie ARE THE SIM
  ## and have no budget at all — `zombies.nim` never charges one.
  if k == rtArchon or k == rtScout: DecisionOpsWide
  else: DecisionOpsStandard

# ---------------------------------------------------------------------------
#  The outbreak ladder
# ---------------------------------------------------------------------------

func outbreakLevel*(round: int): int =
  ## `round / GameConstants.OUTBREAK_TIMER`, integer division. Rounds are
  ## 0-based, so level 9 is the last one a 3000-round game reaches.
  if round <= 0: 0 else: round div OutbreakTimer

func outbreakMultiplier*(round: int): float64 =
  ## `RobotType.getOutbreakMultiplier(round)`, from the tabled switch. Above
  ## the table the engine's own `3.00 + (level - 9)` arm is evaluated.
  let level = outbreakLevel(round)
  if level < OutbreakMultipliers.len: OutbreakMultipliers[level]
  else: 3.00 + float64(level - 9)

func maxHealthOf*(k: RobotType, round: int): float64 =
  ## `RobotType.maxHealth(round)`: scaled for a ZOMBIE, base for a player
  ## unit, evaluated at the round the robot SPAWNS.
  if RobotSpecs[k].isZombie:
    RobotSpecs[k].maxHealth * outbreakMultiplier(round)
  else:
    RobotSpecs[k].maxHealth

func attackPowerOf*(k: RobotType, round: int): float64 =
  if RobotSpecs[k].isZombie:
    RobotSpecs[k].attackPower * outbreakMultiplier(round)
  else:
    RobotSpecs[k].attackPower

# ---------------------------------------------------------------------------
#  Rubble, movement and damage arithmetic
# ---------------------------------------------------------------------------

func rubbleAfterClear*(rubble: float64): float64 =
  ## `visitClearRubbleSignal` + `alterRubble`'s `max(0.0, ...)`:
  ## `max(0, r * (1 - 0.05) - 10.0)`. Vectors: 100 -> 85, 10 -> 0,
  ## 1 000 000 -> 949 990.
  max(0.0, (rubble * (1.0 - RubbleClearPercentage)) - RubbleClearFlatAmount)

func rubbleBlocks*(rubble: float64, k: RobotType): bool =
  ## `GameWorld.canMove`'s rubble half: `rubble < 100.0 || ignoresRubble`.
  ## A SCOUT, a FASTZOMBIE and a BIGZOMBIE pass anything.
  not (rubble < RubbleObstructionThresh or RobotSpecs[k].ignoresRubble)

func rubbleSlows*(rubble: float64, k: RobotType): bool =
  ## `move()`'s `factor3`: `!ignoresRubble && rubble(dest) >= 50.0`.
  (not RobotSpecs[k].ignoresRubble) and rubble >= RubbleSlowThresh

func moveFactor1*(d: Dir): float64 =
  ## `move()`'s `factor1`, the DIAGONAL multiplier — and it hits the CORE
  ## delay only.
  if d.isDiagonal(): DiagonalDelayMultiplier else: 1.0

func moveFactor3*(rubble: float64, k: RobotType): float64 =
  if rubbleSlows(rubble, k): 2.0 else: 1.0

func guardRate*(attacker, target: RobotType): float64 =
  ## `visitAttackSignal`: a GUARD attacker doubles against a ZOMBIE target.
  if attacker == rtGuard and RobotSpecs[target].isZombie:
    GuardZombieMultiplier
  else:
    1.0

func damageToTarget*(rawDamage: float64, target: RobotType): float64 =
  ## `visitAttackSignal`'s guard block: a GUARD target hit for MORE THAN 10.0
  ## takes `damage - 4.0`. Strictly greater — 10.0 exactly is unreduced.
  if target == rtGuard and rawDamage > GuardDefenseThreshold:
    rawDamage - GuardDamageReduction
  else:
    rawDamage

func rubbleFactorFor*(cause: DeathCause): float64 =
  ## `visitDeathSignal`: `1.0` normally, `1.0/3.0` when a TURRET landed the
  ## killing blow. `145 * (1.0/3.0) = 48.33333333333333` is a named vector,
  ## MEASURED against the JVM (`tests/test_bc16_arith.nim`) -- the design
  ## note's `48.333333333333336` was one ulp out and the ENGINE is the
  ## authority (docs/RULES-BC16.md section Divergences, note corrections).
  if cause == dcTurret: RubbleFromTurretFactor else: 1.0

func broadcastDelayIncrease*(radiusSquared: int, sightR2: int): float64 =
  ## `visitBroadcastSignal`: `x = r2 / (double) sensorRadiusSquared - 2`, then
  ## `0.05 + 0.03 * max(0, x)`, ADDED TO BOTH counters. A broadcast inside
  ## twice your own sight radius costs a flat 0.05.
  let x = (float64(radiusSquared) / float64(sightR2)) - 2.0
  BroadcastBaseDelayIncrease + BroadcastAdditionalDelayIncrease * max(0.0, x)
