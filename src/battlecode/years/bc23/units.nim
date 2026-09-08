## The bc23 value types and the PURE per-unit arithmetic.
##
## Everything in this file is a function of its arguments alone: the
## `RobotType` and `Anchor` tables read straight out of `constants.nim`, the
## carrier's weight-driven movement cooldown and throw damage, the
## cooldown-multiplier arithmetic in integer hundredths, the float32 conquest
## threshold and the island occupancy formula. Nothing here touches a `World`,
## which is what lets `world.nim` import it.
##
## THE HALVES THAT MUTATE STATE — `addHealth` and destruction, the inventory
## and the team stockpiles — live in `world.nim` beside the state they change;
## `docs/RULES-BC23.md` §Divergences item 14 records that split against the
## design note's file table.
##
## Four pieces of arithmetic in here are load-bearing and are ported literally:
##
## * **the cooldown multiplier is stored as INTEGER HUNDREDTHS and applied as
##   `Math.round(base * (hundredths / 100.0))` in FLOAT64.** The engine
##   accumulates a `double` through `Math.round(x*100.0)/100.0` after every
##   change, which over the reachable range is exactly the hundredths ladder;
##   but the APPLICATION must stay in float64, because `base = 5,
##   hundredths = 70` gives the float64 product 3.4999999999999996 and Java
##   rounds it to **3**, where an integer `(5*70 + 50) div 100` would give 4;
## * **the carrier's base movement cooldown is
##   `floor(0.375f * weight) + 5`** (`InternalRobot.getBaseMovementCooldown`),
##   exact in float32 because 0.375 is 3/8;
## * **the carrier's throw damage is `floor(1.25f * weight)`**
##   (`InternalCarrier.getDamage`), exact because 1.25 is 5/4;
## * **the conquest test is a FLOAT32 division**,
##   `((float) held) / islandCount >= 0.75f`.

import std/math
import constants

export constants

type
  Team* = enum
    teamA = 0
    teamB = 1

  Dir* = enum
    ## Ordinals match `common/Direction.java`; `CENTER` is last, exactly as
    ## `values()` returns it.
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
    ## The map file's own declared value: `schema/battlecode.fbs` says
    ## "0 for rotation, 1 for horizontal, 2 for vertical". The 2023 engine
    ## never reads it for a rule; the chassis steers by it and the map card
    ## reports it.
    symRotation = 0
    symHorizontal = 1
    symVertical = 2

  Loc* = object
    x*, y*: int

  Resource* = enum
    ## `common/ResourceType.java`, ordinals verbatim.
    resNone = 0
    resAdamantium = 1
    resMana = 2
    resElixir = 3

  Domination* = enum
    ## `world/DominationFactor.java` in snake_case, plus our own wall-clock
    ## value. `RESIGNATION` is deliberately absent from what a chassis can
    ## reach: `rc.resign()` is a real engine method but a doctrine is a JSON
    ## sheet and neither chassis can call it
    ## (docs/RULES-BC23.md §Divergences item 7).
    dfNone
    dfConquest = "conquest"
    dfMoreSkyIslands = "more_sky_islands"
    dfMoreRealityAnchors = "more_reality_anchors"
    dfMoreElixirNetWorth = "more_elixir_net_worth"
    dfMoreManaNetWorth = "more_mana_net_worth"
    dfMoreAdamantiumNetWorth = "more_adamantium_net_worth"
    dfCoinFlip = "coin_flip"

const
  AllDirs* = [dNorth, dNortheast, dEast, dSoutheast,
              dSouth, dSouthwest, dWest, dNorthwest, dCenter]
  MoveDirs* = [dNorth, dNortheast, dEast, dSoutheast,
               dSouth, dSouthwest, dWest, dNorthwest]

  DirectionOrder*: array[9, Dir] = [
    dCenter, dWest, dNorthwest, dNorth, dNortheast,
    dEast, dSoutheast, dSouth, dSouthwest]
    ## `Direction.DIRECTION_ORDER`, verbatim — the index space the converted
    ## map's `currents` list lives in (`GameWorld`'s constructor reads it with
    ## exactly this table).

  RealResources* = [resAdamantium, resMana, resElixir]
    ## `ResourceType.values()` MINUS `NO_RESOURCE`, in the enum's own order,
    ## which is the order every "for each resource" loop in the engine walks.

  CeilSqrtTable*: array[35, int] = block:
    ## `Math.ceil(Math.sqrt(r2))` for every squared radius the 2023 rule set
    ## can reach (the largest is a headquarters' and an amplifier's
    ## `visionRadiusSquared = 34`), precomputed so the port needs no `sqrt`
    ## and therefore no `fdlibm` path at all.
    var t: array[35, int]
    for r2 in 0 .. 34:
      var k = 0
      while k * k < r2: inc k
      t[r2] = k
    t

  CarrierMoveCooldown*: array[41, int] = block:
    ## `floor(0.375f * weight) + 5` for every reachable cargo weight 0..40.
    var t: array[41, int]
    for wgt in 0 .. 40:
      t[wgt] = int(floor(float32(CarrierMovementSlope) * float32(wgt))) +
        CarrierMovementIntercept
    t

  CarrierThrowDamage*: array[41, int] = block:
    ## `floor(1.25f * weight)` for every reachable cargo weight 0..40.
    var t: array[41, int]
    for wgt in 0 .. 40:
      t[wgt] = int(floor(float32(CarrierDamageFactor) * float32(wgt)))
    t

  BaseMultiplier* = 100
    ## `1.0` in integer hundredths.
  CloudHundredths* = 20
  BoostHundredths* = -10
  DestabilizeHundredths* = 10
  AnchorHundredths* = -15

func other*(t: Team): Team = (if t == teamA: teamB else: teamA)

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
  ## `MapLocation.isAdjacentTo`: `|dx| <= 1 && |dy| <= 1`, which INCLUDES the
  ## location itself. That is why a carrier standing ON a well can collect
  ## from it.
  abs(a.x - b.x) <= 1 and abs(a.y - b.y) <= 1

func chebyshev*(a, b: Loc): int = max(abs(a.x - b.x), abs(a.y - b.y))

func directionTo*(a, b: Loc): Dir =
  ## `MapLocation.directionTo`, ported with the engine's own 2.414 fan.
  let ddx = b.x - a.x
  let ddy = b.y - a.y
  if ddx == 0 and ddy == 0: return dCenter
  let ax = abs(ddx)
  let ay = abs(ddy)
  if ddx == 0:
    return (if ddy > 0: dNorth else: dSouth)
  if ddy == 0:
    return (if ddx > 0: dEast else: dWest)
  ## 2.414 = 1 + sqrt(2), the tangent of 67.5 degrees, compared without a
  ## division: `ay * 1000 > ax * 2414`.
  if ay * 1000 > ax * 2414:
    return (if ddy > 0: dNorth else: dSouth)
  if ax * 1000 > ay * 2414:
    return (if ddx > 0: dEast else: dWest)
  if ddx > 0:
    return (if ddy > 0: dNortheast else: dSoutheast)
  (if ddy > 0: dNorthwest else: dSouthwest)

# ---------------------------------------------------------------------------
#  The per-type table
# ---------------------------------------------------------------------------

func spec*(k: RobotType): RobotSpec = RobotSpecs[k]
func maxHealth*(k: RobotType): int = RobotSpecs[k].health
func canAttackType*(k: RobotType): bool =
  ## `RobotType.canAttack()`: launcher or carrier.
  k == rtLauncher or k == rtCarrier
func canMoveType*(k: RobotType): bool = k != rtHeadquarters
func buildCost*(k: RobotType, r: Resource): int =
  case r
  of resAdamantium: RobotSpecs[k].buildCostAdamantium
  of resMana: RobotSpecs[k].buildCostMana
  of resElixir: RobotSpecs[k].buildCostElixir
  of resNone: 0

func anchorCost*(a: AnchorType, r: Resource): int =
  case r
  of resAdamantium: AnchorSpecs[a].adamantiumCost
  of resMana: AnchorSpecs[a].manaCost
  of resElixir: AnchorSpecs[a].elixirCost
  of resNone: 0

func budgetFor*(k: RobotType): int =
  ## The `DecisionOps` budget that replaces the JVM bytecode limit: one tenth
  ## of `RobotType.bytecodeLimit`, the same convention bc20, bc21, bc24 and
  ## bc25 use.
  case k
  of rtHeadquarters: DecisionOpsHeadquarters
  of rtCarrier: DecisionOpsCarrier
  else: DecisionOpsOther

# ---------------------------------------------------------------------------
#  The four pieces of non-integer arithmetic, each over a finite domain
# ---------------------------------------------------------------------------

func applyMultiplier*(base, hundredths: int): int =
  ## `GameWorld.getCooldownWithMultiplier`:
  ## `(int) Math.round(cooldown * multiplier)`, with the multiplier a `double`
  ## that is always an exact hundredth. `Math.round(double)` is
  ## `floor(x + 0.5)`, which for a negative x differs from Nim's `round`; no
  ## reachable cooldown is negative, but the floor form is written out anyway
  ## so the port cannot drift if one ever is.
  let x = float64(base) * (float64(hundredths) / 100.0)
  int(floor(x + 0.5))

func carrierMoveCooldown*(weight: int): int =
  CarrierMoveCooldown[max(0, min(weight, 40))]

func carrierThrowDamage*(weight: int): int =
  CarrierThrowDamage[max(0, min(weight, 40))]

func baseMovementCooldown*(k: RobotType, weight: int): int =
  if k == rtCarrier: carrierMoveCooldown(weight)
  else: RobotSpecs[k].movementCooldown

func islandsToWin*(islandCount: int): int =
  ## The smallest `held` for which `((float) held) / islandCount >= 0.75f`.
  ## A genuine float32 division, evaluated exactly as the engine evaluates it.
  if islandCount <= 0: return 0
  for held in 0 .. islandCount:
    if float32(held) / float32(islandCount) >=
        WinPercentageOfIslandsOccupied:
      return held
  islandCount

func conquestReached*(held, islandCount: int): bool =
  islandCount > 0 and
    float32(held) / float32(islandCount) >= WinPercentageOfIslandsOccupied

func occupancyDiff*(ownerTiles, enemyTiles, area: int): int =
  ## `Island.advanceTurn`'s `(100 * (own - enemy)) / area`, JAVA INTEGER
  ## DIVISION — truncated TOWARD ZERO, which Nim's `div` matches for a
  ## negative numerator.
  if area <= 0: 0 else: (100 * (ownerTiles - enemyTiles)) div area
