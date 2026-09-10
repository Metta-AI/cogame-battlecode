## Battlecode 2019 "Crusade" gameplay constants -- GENERATED, do not edit.
##
## Source: github.com/battlecode/battlecode19 at commit `80cf1cc535ec5a30559274aa1b49807ad4859925`,
## file `coldbrew/specs.json`, read by
## `tools/gen_year_constants.py --year bc19`. The `test` job of
## `.github/workflows/ci.yml` re-runs that generator with `--check`,
## which byte-diffs this file, so an edit here fails the build
## instead of quietly changing the rules under a `GameVersion` that
## no longer describes them.
##
## THE 2019 SPEC EXISTS ONLY AS THIS FILE PLUS `app/src/views/docs.js`
## (the human-readable page), and where the two disagree THE ENGINE
## WINS -- all seven disagreements are tabled in
## `docs/RULES-BC19.md`.
##
## 2019 IS AN INTEGER YEAR. Health, karbonite, fuel, damage,
## capacities, radii, yields and costs are all integers, so a Nim
## `int` port is bit-exact by construction. Exactly TWO non-integer
## operations exist on gameplay paths and both have finite domains
## and are TABLED in `data/bc19/tables.json`:
## `Math.ceil(Math.sqrt(r2))` for r2 in 0..7938 and the reclaim's
## `Math.floor(a/b)`. There is NO `sqrt`, NO `pow`, NO `exp` and NO
## float64 accumulation on any runtime path, and
## `src/battlecode/fdlibm.nim` is not imported by bc19 at all.
##
## THREE `null`/scalar coercions in this table are REAL RULES (D6),
## which is why every nullable column carries its own `*Null` flag
## rather than collapsing to 0:
##   1. `CHURCH.ATTACK_RADIUS` is the SCALAR `0`, not a pair, so
##      `r > radius[1]` and `r < radius[0]` are both `false` and a
##      CHURCH may legally `attack` any on-board square for 0 fuel
##      and 0 damage, consuming its turn;
##   2. `PILGRIM.ATTACK_RADIUS` is `null`, so `null[1]` throws and a
##      pilgrim attack is a VALIDATION FAILURE, not an action;
##   3. `CASTLE`/`CHURCH` capacities are `null` and
##      `Math.min(n, null) === 0`, so a structure that lands a kill
##      reclaims exactly nothing.

const EngineCommit* = "80cf1cc535ec5a30559274aa1b49807ad4859925"
const EngineNpmPackage* = "bc19@0.4.6"

type
  UnitKind* = enum
    ## `SPECS`'s own ordinal order. THE ORDINAL IS LOAD-BEARING: it is
    ## `build_unit` on the wire, the `SPECS.UNITS` index and the
    ## sprite-atlas index.
    ukCastle = 0
    ukChurch = 1
    ukPilgrim = 2
    ukCrusader = 3
    ukProphet = 4
    ukPreacher = 5

  AttackRadiusShape* = enum
    ## What `SPECS.UNITS[u].ATTACK_RADIUS` actually IS in the JSON.
    arPair       ## a two-element `[min, max]` array
    arScalarZero ## the bare number `0` -- the CHURCH (D6.1)
    arNull       ## `null` -- the PILGRIM (D6.2)

  UnitSpec* = object
    constructionKarbonite*: int
    constructionKarboniteNull*: bool
    constructionFuel*: int
    constructionFuelNull*: bool
    karboniteCapacity*: int
    karboniteCapacityNull*: bool
    fuelCapacity*: int
    fuelCapacityNull*: bool
    speed*: int
    fuelPerMove*: int
    fuelPerMoveNull*: bool
    startingHp*: int
    visionRadius*: int
    attackDamage*: int
    attackDamageNull*: bool
    attackRadius*: AttackRadiusShape
    attackRadiusMin*: int
    attackRadiusMax*: int
    attackFuelCost*: int
    attackFuelCostNull*: bool
    damageSpread*: int
    damageSpreadNull*: bool

const
  CommunicationBits* = 16
  CastleTalkBits* = 8
  MaxRounds* = 1000
  TrickleFuel* = 25
  InitialKarbonite* = 100
  InitialFuel* = 500
  MineFuelCost* = 1
  KarboniteYield* = 2
  FuelYield* = 10
  MaxTrade* = 1024
  MaxBoardSize* = 64
  MaxId* = 4096
  Castle* = 0
  Church* = 1
  Pilgrim* = 2
  Crusader* = 3
  Prophet* = 4
  Preacher* = 5
  Red* = 0
  Blue* = 1
  ChessInitial* = 100
  ChessExtra* = 20
  TurnMaxTime* = 200
  MaxMemory* = 50000000

  Units*: array[UnitKind, UnitSpec] = [
    UnitSpec(  ## CASTLE
      constructionKarbonite: -1, constructionKarboniteNull: true,
      constructionFuel: -1, constructionFuelNull: true,
      karboniteCapacity: -1, karboniteCapacityNull: true,
      fuelCapacity: -1, fuelCapacityNull: true,
      speed: 0,
      fuelPerMove: -1, fuelPerMoveNull: true,
      startingHp: 200,
      visionRadius: 100,
      attackDamage: 10, attackDamageNull: false,
      attackRadius: arPair,
      attackRadiusMin: 1, attackRadiusMax: 64,
      attackFuelCost: 10, attackFuelCostNull: false,
      damageSpread: 0, damageSpreadNull: false),
    UnitSpec(  ## CHURCH
      constructionKarbonite: 50, constructionKarboniteNull: false,
      constructionFuel: 200, constructionFuelNull: false,
      karboniteCapacity: -1, karboniteCapacityNull: true,
      fuelCapacity: -1, fuelCapacityNull: true,
      speed: 0,
      fuelPerMove: -1, fuelPerMoveNull: true,
      startingHp: 100,
      visionRadius: 100,
      attackDamage: 0, attackDamageNull: false,
      attackRadius: arScalarZero,
      attackRadiusMin: -1, attackRadiusMax: -1,
      attackFuelCost: 0, attackFuelCostNull: false,
      damageSpread: 0, damageSpreadNull: false),
    UnitSpec(  ## PILGRIM
      constructionKarbonite: 10, constructionKarboniteNull: false,
      constructionFuel: 50, constructionFuelNull: false,
      karboniteCapacity: 20, karboniteCapacityNull: false,
      fuelCapacity: 100, fuelCapacityNull: false,
      speed: 4,
      fuelPerMove: 1, fuelPerMoveNull: false,
      startingHp: 10,
      visionRadius: 100,
      attackDamage: -1, attackDamageNull: true,
      attackRadius: arNull,
      attackRadiusMin: -1, attackRadiusMax: -1,
      attackFuelCost: -1, attackFuelCostNull: true,
      damageSpread: -1, damageSpreadNull: true),
    UnitSpec(  ## CRUSADER
      constructionKarbonite: 15, constructionKarboniteNull: false,
      constructionFuel: 50, constructionFuelNull: false,
      karboniteCapacity: 20, karboniteCapacityNull: false,
      fuelCapacity: 100, fuelCapacityNull: false,
      speed: 9,
      fuelPerMove: 1, fuelPerMoveNull: false,
      startingHp: 40,
      visionRadius: 49,
      attackDamage: 10, attackDamageNull: false,
      attackRadius: arPair,
      attackRadiusMin: 1, attackRadiusMax: 16,
      attackFuelCost: 10, attackFuelCostNull: false,
      damageSpread: 0, damageSpreadNull: false),
    UnitSpec(  ## PROPHET
      constructionKarbonite: 25, constructionKarboniteNull: false,
      constructionFuel: 50, constructionFuelNull: false,
      karboniteCapacity: 20, karboniteCapacityNull: false,
      fuelCapacity: 100, fuelCapacityNull: false,
      speed: 4,
      fuelPerMove: 2, fuelPerMoveNull: false,
      startingHp: 20,
      visionRadius: 64,
      attackDamage: 10, attackDamageNull: false,
      attackRadius: arPair,
      attackRadiusMin: 16, attackRadiusMax: 64,
      attackFuelCost: 25, attackFuelCostNull: false,
      damageSpread: 0, damageSpreadNull: false),
    UnitSpec(  ## PREACHER
      constructionKarbonite: 30, constructionKarboniteNull: false,
      constructionFuel: 50, constructionFuelNull: false,
      karboniteCapacity: 20, karboniteCapacityNull: false,
      fuelCapacity: 100, fuelCapacityNull: false,
      speed: 4,
      fuelPerMove: 3, fuelPerMoveNull: false,
      startingHp: 60,
      visionRadius: 16,
      attackDamage: 20, attackDamageNull: false,
      attackRadius: arPair,
      attackRadiusMin: 1, attackRadiusMax: 16,
      attackFuelCost: 15, attackFuelCostNull: false,
      damageSpread: 3, damageSpreadNull: false),
  ]

  MaxSignalRadius* = 2 * (MaxBoardSize - 1) * (MaxBoardSize - 1)
    ## `game.js:833`: `signal_radius <= 2*Math.pow(MAX_BOARD_SIZE-1,2)`
    ## = 7938, which is also the domain bound of the tabled
    ## `ceil(sqrt(r2))`.

  MaxGiveAmount* = 255
    ## `game.js:904`: `give_karbonite < 2^8` and `give_fuel < 2^8`.

