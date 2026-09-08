## The bc25 value types and the PURE per-unit arithmetic.
##
## Everything in this file is a function of its arguments alone: the
## `UnitType` table read straight out of `constants.nim`, the level and kind
## algebra of the twelve unit types, the low-paint cooldown surcharge, and the
## upgrade damage-carry rule. Nothing here touches a `World`, which is what
## lets `world.nim` import it.
##
## THE HALVES THAT MUTATE STATE — `addPaint`'s clamping, `addHealth` and
## destruction, and the end-of-turn paint bill — live in `world.nim` beside the
## state they change, and `docs/RULES-BC25.md` §Divergences item 14 records
## that split against the design note's file table.
##
## Two pieces of arithmetic in here are load-bearing and are ported literally
## from `world/InternalRobot.java`:
##
## * **the paint percentage is `Math.round(paint * 100.0 / capacity)`** — a
##   float64 round-half-up, not integer division, so a soldier at 99/200 is
##   50 % (and pays no surcharge) while one at 98/200 is 49 % (and does);
## * **the surcharge is `round(add * (100 + (-2) * pct) / 100.0)` with the
##   `int * int` product taken BEFORE the `/100.0`**, and it applies to ROBOTS
##   ONLY. A tower never pays it, at any paint level.

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
    ## "0 for rotation, 1 for horizontal, 2 for vertical". The 2025 engine
    ## never reads it for a rule; the chassis steers by it and the map card
    ## reports it.
    symRotation = 0
    symHorizontal = 1
    symVertical = 2

  Loc* = object
    x*, y*: int

  TowerKind* = enum
    ## The three tower families, level-free. `UnitType` spells out all nine
    ## level/family combinations; this is what a doctrine and the chassis
    ## talk in.
    tkPaint = "paint"
    tkMoney = "money"
    tkDefense = "defense"

  Domination* = enum
    ## `world/DominationFactor.java` in snake_case, plus our own wall-clock
    ## value. `RESIGNATION` is deliberately absent: `rc.resign()` is a real
    ## engine method but a doctrine is a JSON sheet and neither chassis can
    ## call it, and `MAX_TEAM_EXECUTION_TIME` is a JVM wall-clock rule with no
    ## port (docs/RULES-BC25.md §Divergences item 6).
    dfNone
    dfPaintEnoughArea = "paint_enough_area"
    dfDestroyAllUnits = "destroy_all_units"
    dfMoreSquaresPainted = "more_squares_painted"
    dfMoreTowersAlive = "more_towers_alive"
    dfMoreMoney = "more_money"
    dfMorePaintInUnits = "more_paint_in_units"
    dfMoreRobotsAlive = "more_robots_alive"
    dfCoinFlip = "coin_flip"

const
  AllDirs* = [dNorth, dNortheast, dEast, dSoutheast,
              dSouth, dSouthwest, dWest, dNorthwest, dCenter]
  MoveDirs* = [dNorth, dNortheast, dEast, dSoutheast,
               dSouth, dSouthwest, dWest, dNorthwest]
  CardinalDirs* = [dNorth, dSouth, dEast, dWest]
    ## The four `mopSwing` accepts, in `InternalRobot.mopSwing`'s own
    ## `dirIdx` order: NORTH 0, SOUTH 1, EAST 2, WEST 3.

  RobotTypes* = [utSoldier, utSplasher, utMopper]

  MopSwingDx*: array[4, array[6, int]] = [
    [-1, 0, 1, -1, 0, 1],
    [-1, 0, 1, -1, 0, 1],
    [1, 1, 1, 2, 2, 2],
    [-1, -1, -1, -2, -2, -2]]
  MopSwingDy*: array[4, array[6, int]] = [
    [1, 1, 1, 2, 2, 2],
    [-1, -1, -1, -2, -2, -2],
    [-1, 0, 1, -1, 0, 1],
    [-1, 0, 1, -1, 0, 1]]
    ## `InternalRobot.mopSwing`'s two tables, VERBATIM, indexed
    ## [NORTH, SOUTH, EAST, WEST][0..5].

  CeilSqrtTable*: array[81, int] = block:
    ## `Math.ceil(Math.sqrt(r2))` for every squared radius the rule set can
    ## reach (the largest is `BROADCAST_RADIUS_SQUARED = 80`), precomputed so
    ## the port needs no `sqrt` and therefore no `fdlibm` path at all.
    var t: array[81, int]
    for r2 in 0 .. 80:
      var k = 0
      while k * k < r2: inc k
      t[r2] = k
    t

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
func `-`*(a: Loc, d: Dir): Loc = loc(a.x - d.dx, a.y - d.dy)
func `==`*(a, b: Loc): bool = a.x == b.x and a.y == b.y
func translate*(a: Loc, ddx, ddy: int): Loc = loc(a.x + ddx, a.y + ddy)

func distanceSquaredTo*(a, b: Loc): int =
  let ddx = a.x - b.x
  let ddy = a.y - b.y
  ddx * ddx + ddy * ddy

func isWithinDistanceSquared*(a, b: Loc, r2: int): bool =
  a.distanceSquaredTo(b) <= r2

func chebyshev*(a, b: Loc): int = max(abs(a.x - b.x), abs(a.y - b.y))

func directionTo*(a, b: Loc): Dir =
  ## `MapLocation.directionTo`, ported with the engine's own 2.414 fan. The
  ## 2025 example bot steers with it, so the fan's exact boundaries are part
  ## of the Tier A comparison.
  let ddx = float64(b.x - a.x)
  let ddy = float64(b.y - a.y)
  if abs(ddx) >= 2.414 * abs(ddy):
    if ddx > 0: return dEast
    if ddx < 0: return dWest
    return dCenter
  elif abs(ddy) >= 2.414 * abs(ddx):
    if ddy > 0: return dNorth
    return dSouth
  elif ddx > 0:
    return (if ddy > 0: dNortheast else: dSoutheast)
  elif ddx < 0:
    return (if ddy > 0: dNorthwest else: dSouthwest)
  dCenter

func other*(t: Team): Team = (if t == teamA: teamB else: teamA)

# ---------------------------------------------------------------------------
#  The UnitType table
# ---------------------------------------------------------------------------

func spec*(t: UnitType): UnitSpec = UnitSpecs[t]

func isRobotType*(t: UnitType): bool =
  t == utSoldier or t == utSplasher or t == utMopper

func isTowerType*(t: UnitType): bool = not t.isRobotType()

func levelOf*(t: UnitType): int = UnitSpecs[t].level

func canUpgradeType*(t: UnitType): bool =
  (UnitSpecs[t].level == 1 or UnitSpecs[t].level == 2) and t.isTowerType()

func nextLevel*(t: UnitType): UnitType =
  ## `UnitType.getNextLevel`. A type with no next level answers ITSELF here
  ## rather than Java's `null`; every caller checks `canUpgradeType` first.
  case t
  of utLevelOneDefenseTower: utLevelTwoDefenseTower
  of utLevelTwoDefenseTower: utLevelThreeDefenseTower
  of utLevelOneMoneyTower: utLevelTwoMoneyTower
  of utLevelTwoMoneyTower: utLevelThreeMoneyTower
  of utLevelOnePaintTower: utLevelTwoPaintTower
  of utLevelTwoPaintTower: utLevelThreePaintTower
  else: t

func baseType*(t: UnitType): UnitType =
  ## `UnitType.getBaseType`.
  case t
  of utLevelTwoDefenseTower, utLevelThreeDefenseTower: utLevelOneDefenseTower
  of utLevelTwoPaintTower, utLevelThreePaintTower: utLevelOnePaintTower
  of utLevelTwoMoneyTower, utLevelThreeMoneyTower: utLevelOneMoneyTower
  else: t

func towerKindOf*(t: UnitType): TowerKind =
  case t
  of utLevelOnePaintTower, utLevelTwoPaintTower, utLevelThreePaintTower:
    tkPaint
  of utLevelOneMoneyTower, utLevelTwoMoneyTower, utLevelThreeMoneyTower:
    tkMoney
  else: tkDefense

func towerTypeFor*(kind: TowerKind): UnitType =
  ## The LEVEL ONE type of a family — the only type `completeTowerPattern`
  ## ever builds.
  case kind
  of tkPaint: utLevelOnePaintTower
  of tkMoney: utLevelOneMoneyTower
  of tkDefense: utLevelOneDefenseTower

func isDefenseTower*(t: UnitType): bool =
  t == utLevelOneDefenseTower or t == utLevelTwoDefenseTower or
    t == utLevelThreeDefenseTower

func defenseBuffOnSpawn*(t: UnitType): int =
  ## `GameWorld.spawnRobot`: only a LEVEL ONE defense tower adds the +5 on
  ## spawn, because every higher level is reached through `upgradeTower`.
  if t == utLevelOneDefenseTower: ExtraDamageFromDefenseTower else: 0

func defenseBuffOnUpgrade*(newType: UnitType): int =
  ## `GameWorld.upgradeTower`: +2 for each of the two upgrade steps.
  if newType == utLevelTwoDefenseTower or newType == utLevelThreeDefenseTower:
    ExtraTowerDamageLevelIncrease
  else: 0

func defenseBuffOnDestroy*(t: UnitType): int =
  ## `GameWorld.destroyRobot`'s switch, verbatim: the whole accumulated buff
  ## of that tower comes off the ledger, level included.
  case t
  of utLevelOneDefenseTower: ExtraDamageFromDefenseTower
  of utLevelTwoDefenseTower:
    ExtraDamageFromDefenseTower + ExtraTowerDamageLevelIncrease
  of utLevelThreeDefenseTower:
    ExtraDamageFromDefenseTower + 2 * ExtraTowerDamageLevelIncrease
  else: 0

func upgradedHealth*(oldType, newType: UnitType, health: int): int =
  ## `InternalRobot.upgradeTower`: DAMAGE IS CARRIED ACROSS THE UPGRADE.
  ## `newHealth = newType.health - (oldType.health - health)`.
  UnitSpecs[newType].health - (UnitSpecs[oldType].health - health)

# ---------------------------------------------------------------------------
#  Cooldowns
# ---------------------------------------------------------------------------

func javaRound*(x: float64): int =
  ## `Math.round(double)` is `floor(x + 0.5)` — NOT Nim's `round`, which is
  ## round-half-away-from-zero. The four places bc25 uses floating point all
  ## go through here.
  int(floor(x + 0.5))

func paintPercentage*(paint: int, t: UnitType): int =
  ## `Math.round(paintAmount * 100.0 / type.paintCapacity)`.
  javaRound(float64(paint) * 100.0 / float64(UnitSpecs[t].paintCapacity))

func cooldownSurcharge*(add, paint: int, t: UnitType): int =
  ## `InternalRobot.addActionCooldownTurns` / `addMovementCooldownTurns`: the
  ## total charge, surcharge included. TOWERS NEVER PAY IT.
  ##
  ## The `int * int` product is taken before the `/ 100.0`, which is what
  ## keeps the whole expression exact in float64 over the finite domain
  ## `add in {10, 20, 30, 50}` x `pct in 0..100` (Tier B).
  if not t.isRobotType(): return add
  let pct = paintPercentage(paint, t)
  if pct >= IncreasedCooldownThreshold: return add
  add + javaRound(
    float64(add * (IncreasedCooldownIntercept +
                   IncreasedCooldownSlope * pct)) / 100.0)

func coveragePermille*(painted, areaWithoutWalls: int): int =
  ## `GameWorld.processEndOfRound`: `round(painted * 1000.0 / area)`.
  if areaWithoutWalls <= 0: return 0
  javaRound(float64(painted) * 1000.0 / float64(areaWithoutWalls))

func tilesToWin*(areaWithoutWalls: int): int =
  ## The smallest live painted count that satisfies
  ## `painted / area * 100 >= PAINT_PERCENT_TO_WIN`, i.e.
  ## `ceil(0.70 * areaWithoutWalls)`.
  ##
  ## THE DENOMINATOR IS `width * height - walls`, which COUNTS RUIN AND TOWER
  ## TILES THAT CAN NEVER BE PAINTED. That is the engine's own arithmetic and
  ## not the spec's prose (docs/RULES-BC25.md §Divergences item 5); the viewer
  ## shows the truly-paintable count beside it so the gap is visible.
  (areaWithoutWalls * PaintPercentToWin + 99) div 100
