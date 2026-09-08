## The bc22 value types and the PURE per-unit arithmetic.
##
## Everything in this file is a function of its arguments alone: the
## `RobotType` and `AnomalyType` tables read straight out of `constants.nim`,
## the per-level health/damage/healing/mutation-cost/worth/reclaim ladders, the
## FLOAT64 rubble cooldown multiplier, the float32 prototype-health, reclaim and
## anomaly truncations, and the `RobotMode` predicates. Nothing here touches a
## `World`, which is what lets `world.nim` import it.
##
## THE HALF THAT MUTATES STATE — `addHealth` with its cap, its
## PROTOTYPE -> TURRET promotion and its destroy-at-zero, the reclaim drop, the
## team stockpiles, `transform` and `mutate` — lives in `world.nim` and
## `buildings.nim` beside the state it changes; `docs/RULES-BC22.md`
## §Divergences item 14 records that split against the design note's file table.
##
## Six pieces of arithmetic in here are load-bearing and are ported literally:
##
## * **the rubble cooldown multiplier is `(int)((1 + rubble/10.0) * base)`** — a
##   float64 divide, a float64 multiply and a TRUNCATION, and it is **not** the
##   integer form. Measured on the JVM over `rubble 0..100 x base in
##   {2,10,16,20,24,25,100,200}`, the two disagree on **22 of the 808 pairs**,
##   always by one and always with the float one lower (`base 25 rubble 36` is
##   114 and not 115; `base 100 rubble 13` is 229; `base 200 rubble 92` is
##   2039). `data/bc22/tables.json` carries the whole lattice, the 22 differing
##   pairs are flagged in it, and `tests/test_bc22_cooldown.nim` names them;
## * **the prototype health is `(int)(0.8f * maxHealth)`** — float32, so a
##   1944-HP archon prototype is 1555 and not 1555.2;
## * **the reclaim drop is `(int)(worth * 0.2f)`** — float32;
## * **ABYSS is `(int)(0.1f * metal)` per square**, which is ZERO for any square
##   holding nine or fewer, and `(int)(-1 * 0.1f * reserve)` per team;
## * **CHARGE's cut is `(int)(0.05f * droidCount)`**, which is ZERO for every
##   count of nineteen or fewer;
## * **FURY is `(int)(-1 * maxHealth * 0.05f)`** — float32 and truncating, so a
##   level-1 watchtower loses **7** and not 8.
##
## The laboratory's transmutation rate — the year's one transcendental — is NOT
## here: its whole finite domain is tabled into `data/bc22/tables.json` at build
## time and read by `economy.nim`, so the runtime path has no `exp` at all.

import constants

export constants

type
  Team* = enum
    teamA = 0
    teamB = 1

  Dir* = enum
    ## Ordinals match `common/Direction.java`; `CENTER` is last, exactly as
    ## `values()` returns it. The example bot indexes `directions[rng.nextInt(8)]`
    ## into the first EIGHT, in this order, which is why the order is a rule and
    ## not a convention.
    dNorth = 0
    dNortheast
    dEast
    dSoutheast
    dSouth
    dSouthwest
    dWest
    dNorthwest
    dCenter

  Symmetry* = enum
    ## `world/MapSymmetry.java`, in `values()` order — which is the index space
    ## the map file's `symmetry` field lives in. UNLIKE EVERY OTHER YEAR THIS
    ## REPO SHIPS, bc22 reads it at RUN TIME: `causeVortexGlobal` switches on it.
    symRotation = 0
    symHorizontal = 1
    symVertical = 2

  RobotMode* = enum
    ## `common/RobotMode.java` with its three predicates. A DROID always acts
    ## and moves; a PROTOTYPE does neither until a builder fills it; a TURRET
    ## acts and may transform; a PORTABLE moves and may transform.
    rmDroid = "DROID"
    rmPrototype = "PROTOTYPE"
    rmTurret = "TURRET"
    rmPortable = "PORTABLE"

  Loc* = object
    x*, y*: int

  Domination* = enum
    ## `world/DominationFactor.java` in snake_case, plus our own wall-clock
    ## value. `WON_BY_DUBIOUS_REASONS` is spelled `coin_flip` because that is
    ## what the manifest's `end_reason` enum already calls it (bc21's and
    ## bc26's). `RESIGNATION` has no value at all: `rc.resign()` is a real
    ## engine method but a doctrine is a JSON sheet and neither chassis can call
    ## it (docs/RULES-BC22.md §Divergences item 8).
    dfNone
    dfAnnihilated = "annihilated"
    dfMoreArchons = "more_archons"
    dfMoreGoldNetWorth = "more_gold_net_worth"
    dfMoreLeadNetWorth = "more_lead_net_worth"
    dfCoinFlip = "coin_flip"

const
  AllDirs* = [dNorth, dNortheast, dEast, dSoutheast,
              dSouth, dSouthwest, dWest, dNorthwest, dCenter]
  MoveDirs* = [dNorth, dNortheast, dEast, dSoutheast,
               dSouth, dSouthwest, dWest, dNorthwest]
    ## `Direction.values()`'s first EIGHT, in the enum's own order. The example
    ## bot's `directions[rng.nextInt(8)]` indexes exactly this array.

  Droids* = [rtMiner, rtBuilder, rtSoldier, rtSage]
  Buildings* = [rtArchon, rtLaboratory, rtWatchtower]

  CeilSqrtTable*: array[54, int] = block:
    ## `Math.ceil(Math.sqrt(r2))` for every squared radius the 2022 rule set can
    ## reach (the largest is a LABORATORY's `visionRadiusSquared = 53`),
    ## precomputed so the port needs no `sqrt` and therefore no `fdlibm` path on
    ## the scan-order path at all.
    var t: array[54, int]
    for r2 in 0 .. 53:
      var k = 0
      while k * k < r2: inc k
      t[r2] = k
    t

func other*(t: Team): Team = (if t == teamA: teamB else: teamA)

func canAct*(m: RobotMode): bool = m == rmDroid or m == rmTurret
func canMove*(m: RobotMode): bool = m == rmDroid or m == rmPortable
func canTransform*(m: RobotMode): bool = m == rmTurret or m == rmPortable

# ---------------------------------------------------------------------------
#  Geometry that does not need a world
# ---------------------------------------------------------------------------

func dx*(d: Dir): int =
  case d
  of dNorth, dSouth, dCenter: 0
  of dNortheast, dEast, dSoutheast: 1
  of dSouthwest, dWest, dNorthwest: -1

func dy*(d: Dir): int =
  case d
  of dEast, dWest, dCenter: 0
  of dNorth, dNortheast, dNorthwest: 1
  of dSoutheast, dSouth, dSouthwest: -1

func opposite*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 4) mod 8)

func rotateLeft*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 7) mod 8)

func rotateRight*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 1) mod 8)

func loc*(x, y: int): Loc = Loc(x: x, y: y)
func `+`*(a: Loc, d: Dir): Loc = loc(a.x + d.dx, a.y + d.dy)
func `==`*(a, b: Loc): bool = a.x == b.x and a.y == b.y
func translate*(a: Loc, ddx, ddy: int): Loc = loc(a.x + ddx, a.y + ddy)

func distanceSquaredTo*(a, b: Loc): int =
  let ddx = a.x - b.x
  let ddy = a.y - b.y
  ddx * ddx + ddy * ddy

func isWithinDistanceSquared*(a, b: Loc, r2: int): bool =
  a.distanceSquaredTo(b) <= r2

func isAdjacentTo*(a, b: Loc): bool =
  abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1

func chebyshev*(a, b: Loc): int = max(abs(a.x - b.x), abs(a.y - b.y))

func directionTo*(a, b: Loc): Dir =
  ## `MapLocation.directionTo`, ported with the engine's own 2.414 fan and its
  ## `>=` comparisons (which differ from 2023's `>`).
  let ddx = b.x - a.x
  let ddy = b.y - a.y
  let ax = abs(ddx)
  let ay = abs(ddy)
  ## `Math.abs(dx) >= 2.414 * Math.abs(dy)` without a float: `ax*1000 >= ay*2414`.
  if ax * 1000 >= ay * 2414:
    if ddx > 0: return dEast
    elif ddx < 0: return dWest
    else: return dCenter
  if ay * 1000 >= ax * 2414:
    return (if ddy > 0: dNorth else: dSouth)
  if ddy > 0:
    return (if ddx > 0: dNortheast else: dNorthwest)
  (if ddx > 0: dSoutheast else: dSouthwest)

# ---------------------------------------------------------------------------
#  The per-type table
# ---------------------------------------------------------------------------

func spec*(k: RobotType): RobotSpec = RobotSpecs[k]

func isBuilding*(k: RobotType): bool =
  k == rtArchon or k == rtLaboratory or k == rtWatchtower

func canBuildType*(builder, built: RobotType): bool =
  ## `RobotType.canBuild`: ARCHON -> MINER|BUILDER|SOLDIER|SAGE,
  ## BUILDER -> LABORATORY|WATCHTOWER, and nothing else builds anything.
  (builder == rtArchon and (built == rtMiner or built == rtBuilder or
                            built == rtSoldier or built == rtSage)) or
  (builder == rtBuilder and (built == rtLaboratory or built == rtWatchtower))

func canAttackType*(k: RobotType): bool =
  k == rtWatchtower or k == rtSoldier or k == rtSage

func canEnvisionType*(k: RobotType): bool = k == rtSage

func canRepairType*(repairer, repaired: RobotType): bool =
  (repairer == rtArchon and not repaired.isBuilding()) or
  (repairer == rtBuilder and repaired.isBuilding())

func canMineType*(k: RobotType): bool = k == rtMiner

func canMutateType*(mutator, mutated: RobotType): bool =
  mutator == rtBuilder and mutated.isBuilding()

func canTransmuteType*(k: RobotType): bool = k == rtLaboratory

func startingMode*(k: RobotType): RobotMode =
  ## `InternalRobot`'s constructor: an ARCHON spawns as a TURRET, every other
  ## building as a PROTOTYPE, every droid as a DROID.
  if k == rtArchon: rmTurret
  elif k.isBuilding(): rmPrototype
  else: rmDroid

func maxHealthOf*(k: RobotType, level: int): int =
  ## `RobotType.getMaxHealth`, verbatim.
  if not k.isBuilding() or level == 1: RobotSpecs[k].health
  elif k == rtArchon: (if level == 2: 1080 else: 1944)
  elif k == rtLaboratory: (if level == 2: 180 else: 324)
  else: (if level == 2: 270 else: 486)

func damageOf*(k: RobotType, level: int): int =
  ## `RobotType.getDamage`. NEGATIVE for a repairer.
  if not k.isBuilding() or level == 1: RobotSpecs[k].damage
  elif k == rtArchon: (if level == 2: -4 else: -6)
  elif k == rtLaboratory: 0
  else: (if level == 2: 8 else: 12)

func healingOf*(k: RobotType, level: int): int =
  ## `RobotType.getHealing`: `-getDamage(level)` for an ARCHON or a BUILDER,
  ## 0 for everything else.
  if k == rtArchon or k == rtBuilder: -damageOf(k, level) else: 0

func leadMutateCost*(k: RobotType, level: int): int =
  ## Only level 2 costs lead.
  if level != 2: 0
  elif k == rtArchon: 300
  elif k == rtWatchtower: 150
  elif k == rtLaboratory: 150
  else: 0

func goldMutateCost*(k: RobotType, level: int): int =
  ## Only level 3 costs gold.
  if level != 3: 0
  elif k == rtArchon: 80
  elif k == rtWatchtower: 60
  elif k == rtLaboratory: 25
  else: 0

func leadWorth*(k: RobotType, level: int): int =
  result = RobotSpecs[k].buildCostLead
  for i in 2 .. level: result += leadMutateCost(k, i)

func goldWorth*(k: RobotType, level: int): int =
  result = RobotSpecs[k].buildCostGold
  for i in 2 .. level: result += goldMutateCost(k, i)

func reclaim*(worth: int): int =
  ## `(int)(worth * RECLAIM_COST_MULTIPLIER)` — a FLOAT32 product, truncated.
  int(float32(worth) * ReclaimCostMultiplier)

func leadDropped*(k: RobotType, level: int): int = reclaim(leadWorth(k, level))
func goldDropped*(k: RobotType, level: int): int = reclaim(goldWorth(k, level))

func prototypeHealth*(full: int): int =
  ## `(int)(PROTOTYPE_HP_PERCENTAGE * maxHealth)` — FLOAT32, truncated.
  ## Measured: 600 -> 480, 1080 -> 864, 1944 -> 1555, 150 -> 120, 270 -> 216,
  ## 486 -> 388, 100 -> 80, 180 -> 144, 324 -> 259.
  int(PrototypeHpPercentage * float32(full))

func budgetFor*(k: RobotType): int =
  ## The `DecisionOps` budget that replaces the JVM bytecode limit: one tenth of
  ## `RobotType.bytecodeLimit`, the same convention bc20, bc21, bc23, bc24 and
  ## bc25 use.
  case k
  of rtArchon: DecisionOpsArchon
  of rtBuilder: DecisionOpsBuilder
  of rtLaboratory: DecisionOpsLaboratory
  else: DecisionOpsStandard

# ---------------------------------------------------------------------------
#  The rubble multiplier — FLOAT64, and NOT the integer form
# ---------------------------------------------------------------------------

func cooldownWithMultiplier*(base, rubble: int): int =
  ## `GameWorld.getCooldownWithMultiplier`:
  ## `(int) ((1 + getRubble(location) / 10.0) * cooldown)`.
  ##
  ## The float64 divide, the float64 multiply and the TRUNCATION are all
  ## load-bearing: the integer form `((10 + r) * c) div 10` disagrees on 22 of
  ## the 808 reachable `(rubble, base)` pairs, always one higher.
  int((1.0 + float64(rubble) / 10.0) * float64(base))

# ---------------------------------------------------------------------------
#  The anomaly truncations, each float32
# ---------------------------------------------------------------------------

func abyssGlobalTake*(metal: int): int =
  ## `(int)(0.1f * currentLead)` per square. ZERO for any square holding <= 9.
  int(AnomalySpecs[anAbyss].globalPercentage * float32(metal))

func abyssSageTake*(metal: int): int =
  int(AnomalySpecs[anAbyss].sagePercentage * float32(metal))

func abyssReserveDelta*(reserve: int): int =
  ## `(int)(-1 * 0.1f * reserve)`, i.e. a NEGATIVE amount truncated toward zero.
  int(-1.0'f32 * AnomalySpecs[anAbyss].globalPercentage * float32(reserve))

func chargeCut*(droidCount: int): int =
  ## `(int)(0.05f * droids.size())`. Measured: 19 -> 0, 20 -> 1, 39 -> 1,
  ## 40 -> 2, 59 -> 2, 60 -> 3. UNDER TWENTY DROIDS A GLOBAL CHARGE KILLS NOBODY.
  int(AnomalySpecs[anCharge].globalPercentage * float32(droidCount))

func chargeSageDelta*(maxHealth: int): int =
  ## `(int)(-1 * 0.22f * maxHealth)`.
  int(-1.0'f32 * AnomalySpecs[anCharge].sagePercentage * float32(maxHealth))

func furyGlobalDelta*(maxHealth: int): int =
  ## `(int)(-1 * maxHealth * 0.05f)`. Measured: 150 -> -7 (not -8), 270 -> -13,
  ## 1944 -> -97, 600 -> -30, 100 -> -5.
  int(-1.0'f32 * float32(maxHealth) * AnomalySpecs[anFury].globalPercentage)

func furySageDelta*(maxHealth: int): int =
  int(-1.0'f32 * float32(maxHealth) * AnomalySpecs[anFury].sagePercentage)

# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

func share*(x, y: int): float32 =
  ## 0.5 on a 0-0 total, the same choice bc23/bc24/bc25 made and for the same
  ## reason: two factions that both ended with zero gold should not be scored
  ## differently by an arithmetic accident. On THIS year's evidence that case is
  ## the COMMON one for gold — the measured example-bot mirrors ended 0 Au to
  ## 0 Au in every game.
  if x + y == 0: 0.5'f32 else: float32(x) / float32(x + y)
