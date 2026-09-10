## The pure bc19 arithmetic: the unit table's derived predicates, the two
## tabled non-integer operations, and the geometry primitives.
##
## Nothing in here holds state and nothing in here imports `world`. The
## constant table itself is GENERATED into `constants.nim` from the pinned
## engine's own `coldbrew/specs.json`, so no number below is hand-typed.
##
## THE PREDICATES ARE THE ENGINE'S OWN GUARDS, not a table of capabilities.
## `coldbrew/game.js` never asks "can this unit attack?" — it evaluates
## `r > ATTACK_RADIUS[1] || r < ATTACK_RADIUS[0]` and lets JavaScript's
## coercions answer. Reproducing the guards rather than a summary of them is
## what gets D6's three `null`/scalar rules right:
##
##   * a CHURCH's `ATTACK_RADIUS` is the SCALAR `0`, so both comparisons are
##     against `undefined`, both are `false`, and a church attack is a LEGAL
##     zero-damage zero-fuel action that consumes the turn;
##   * a PILGRIM's is `null`, so `null[1]` throws and a pilgrim attack is a
##     VALIDATION FAILURE;
##   * a CASTLE's and a CHURCH's capacities are `null` and
##     `Math.min(n, null) === 0`, so a structure that lands a kill reclaims
##     exactly nothing.

import std/[json, os, strutils]
import ../../sim_types
import constants

export constants

type
  Team* = enum
    ## The engine's `SPECS.RED` / `SPECS.BLUE`, in that ordinal order —
    ## `karbonite[0]`, `fuel[0]` and `last_offer[0]` are RED's, and the barter
    ## sign convention is "positive means the resource moves RED to BLUE".
    tRed = 0
    tBlue = 1

  Loc* = object
    x*, y*: int

  ActionKind* = enum
    ## `ActionRecord.action`'s ordinals (`coldbrew/action_record.js:7`).
    ## **7 (`timeout`) is UNREACHABLE**: `record.timeout()` is never called
    ## anywhere in `game.js` (V6).
    akNothing = 0
    akMove = 1
    akAttack = 2
    akBuild = 3
    akMine = 4
    akTrade = 5
    akGive = 6
    akTimeout = 7

const
  Bc19UnitNameTable* = ["castle", "church", "pilgrim", "crusader", "prophet",
                        "preacher"]
  Bc19ActionNameTable* = ["nothing", "move", "attack", "build", "mine",
                          "trade", "give", "timeout"]

  DecisionOpsPerMs* = 20
    ## V1. The ONE free parameter of the `DecisionOps` clock, chosen so every
    ## number below reads straight off the engine's own milliseconds.
  ChessInitialOps* = ChessInitial * DecisionOpsPerMs      ## 2 000
  ChessExtraOps* = ChessExtra * DecisionOpsPerMs          ## 400
  TurnMaxOps* = TurnMaxTime * DecisionOpsPerMs            ## 4 000
  TurnChargeOps* = ChessExtraOps                          ## 400 — EXACTLY the
    ## refill, which is the whole of V1: `chessOps` is invariant at
    ## `ChessInitialOps` for every robot for its whole life, so no robot is
    ## ever frozen and the engine's `robot.time < 0` branch
    ## (`game.js:806-808`) is provably unreachable in this port. The charge is
    ## deliberately NOT derived from the chassis's own work: the freeze rule
    ## is an ENGINE rule, and deriving its input from the chassis would make
    ## the chassis's implementation a rules input, so a one-line refactor of
    ## `saber`'s Dijkstra would change what a round resolves to.

  ReclaimDivisors* = [0, 1, 2, 4, 5, 8, 9, 10, 13, 16]
    ## Every `rad_to_attacker` value reachable inside a PREACHER's blast
    ## (`DAMAGE_SPREAD = 3` around the target square) plus the attacker's own
    ## square. The whole domain, tabled.

func unitName*(u: UnitKind): string = Bc19UnitNameTable[ord(u)]

func parseUnitKind*(name: string): UnitKind =
  let key = name.strip().toLowerAscii()
  for u in UnitKind:
    if unitName(u) == key: return u
  ukCastle

func other*(t: Team): Team = (if t == tRed: tBlue else: tRed)

func distSq*(a, b: Loc): int =
  (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)

func distSq*(ax, ay, bx, by: int): int =
  (ax - bx) * (ax - bx) + (ay - by) * (ay - by)

# ---------------------------------------------------------------------------
#  The committed arithmetic tables (D5)
# ---------------------------------------------------------------------------

proc dataRoot*(): string =
  ## `/data` is where emscripten mounts the preloaded directory in the wasm
  ## bundle; `data` is the repo layout the container and the tests use.
  ##
  ## `getAppDir()` is DELIBERATELY not a candidate: under emscripten it walks
  ## `os.getApplAux`, whose `readlink("/proc/self/exe")` returns -1 and whose
  ## next line is a `Natural` conversion that raises before anything is
  ## opened.
  for candidate in ["data", "/data", "/workspace/battlecode/data"]:
    if dirExists(candidate / "maps" / "bc19"):
      return candidate
  "data"

var
  signalCostTable: seq[int]
  reclaimTable: array[ReclaimDivisors.len, seq[int]]
  tablesLoaded = false

proc loadBc19Tables*() =
  ## `data/bc19/tables.json`, regenerated and byte-diffed by
  ## `parity-oracle-bc19` from the running Node's own `Math.ceil`,
  ## `Math.sqrt` and `Math.floor`. Loaded once, lazily; the wasm bundle gets
  ## the file through the existing `--preload-file {rootDir}/data@data`.
  if tablesLoaded: return
  let path = dataRoot() / "bc19" / "tables.json"
  if not fileExists(path):
    raise newException(ConfigError,
      "bc19: no arithmetic table at " & path & ". It is committed and is " &
      "regenerated by tools/JsBc19Tables.mjs; the sim cannot compute " &
      "ceil(sqrt(r2)) without it, deliberately (D5: there is no sqrt on any " &
      "runtime path).")
  let doc = parseJson(readFile(path))
  signalCostTable = newSeq[int](MaxSignalRadius + 1)
  let cs = doc["ceil_sqrt"]
  if cs.len != MaxSignalRadius + 1:
    raise newException(ConfigError,
      "bc19: tables.json carries " & $cs.len & " ceil(sqrt) values, expected " &
        $(MaxSignalRadius + 1))
  for i in 0 .. MaxSignalRadius:
    signalCostTable[i] = cs[i].getInt()
  let fhd = doc["floor_half_div"]
  for i, rad in ReclaimDivisors:
    let row = fhd[$rad]
    reclaimTable[i] = newSeq[int](row.len)
    for j in 0 ..< row.len:
      reclaimTable[i][j] = row[j].getInt()
  tablesLoaded = true

proc signalCost*(r2: int): int =
  ## `Math.ceil(Math.sqrt(signal_radius))` (`game.js:834`,
  ## `action_record.js:329`), over its whole finite domain 0 … 7938. The
  ## twelve measured values are
  ## `{0,1,2,3,4,5,9,10,16,64,100,7938} -> {0,1,2,2,2,3,3,4,4,8,10,90}`.
  loadBc19Tables()
  if r2 < 0 or r2 > MaxSignalRadius: return 0
  signalCostTable[r2]

proc reclaimDivDoubled*(numeratorDoubled, rad: int): int =
  ## `Math.floor(a / rad)` where `a` may be a HALF-integer (the reclaim's
  ## `karbonite + CONSTRUCTION_KARBONITE/2`, and `15/2` and `25/2` are not
  ## integers), keyed by TWICE the numerator so one table answers both the
  ## karbonite and the fuel case.
  ##
  ## `rad == 0` — the attacker's own square, which a PREACHER always includes
  ## — is `Infinity` in JavaScript and the caller is
  ## `Math.min(held + reclaimed, capacity)`, so it CLAMPS TO THE CAPACITY.
  ## The table records that as -1 and `resources.nim` pins the case.
  loadBc19Tables()
  for i, d in ReclaimDivisors:
    if d == rad:
      if numeratorDoubled < 0 or numeratorDoubled >= reclaimTable[i].len:
        ## Outside the tabled domain the arithmetic is plain integer
        ## division, which is exactly what `Math.floor(a/b)` is for
        ## non-negative `a` and positive `b`.
        if rad == 0: return -1
        return numeratorDoubled div (2 * rad)
      return reclaimTable[i][numeratorDoubled]
  if rad == 0: return -1
  numeratorDoubled div (2 * rad)

# ---------------------------------------------------------------------------
#  The engine's own guards (rule 4, D6)
# ---------------------------------------------------------------------------

func isStructure*(u: UnitKind): bool = u == ukCastle or u == ukChurch

func canBuildAtAll*(u: UnitKind): bool =
  ## `game.js:884`: only a PILGRIM, a CASTLE or a CHURCH may build.
  u == ukPilgrim or u == ukCastle or u == ukChurch

func buildPairLegal*(builder, target: UnitKind): bool =
  ## `game.js:887-889`, in the engine's own order: a PILGRIM may build ONLY a
  ## CHURCH; a non-pilgrim may NEVER build a CHURCH; and NOBODY may ever build
  ## a CASTLE.
  if builder == ukPilgrim and target != ukChurch: return false
  if builder != ukPilgrim and target == ukChurch: return false
  if target == ukCastle: return false
  true

func canMine*(u: UnitKind): bool = u == ukPilgrim        ## `game.js:869`
func canTrade*(u: UnitKind): bool = u == ukCastle        ## `game.js:857`

func speedOf*(u: UnitKind): int = Units[u].speed

func canMove*(u: UnitKind): bool =
  ## `canMove` is not a predicate the engine has: `game.js:915` refuses any
  ## move whose `r2 > SPEED`, and `dx == dy == 0` is already refused at
  ## `:878`, so `r2 >= 1 > 0 == SPEED` always holds for a CASTLE and a CHURCH.
  Units[u].speed > 0

func fuelPerMoveOf*(u: UnitKind): int =
  ## `null` for a structure, which is unreachable: a structure can never pass
  ## the `r2 <= SPEED` gate.
  if Units[u].fuelPerMoveNull: 0 else: Units[u].fuelPerMove

func visionRadiusOf*(u: UnitKind): int = Units[u].visionRadius

func visionBoxOf*(u: UnitKind): int =
  ## `floor(sqrt(VISION_RADIUS))`, the half-width of the bounded scan box the
  ## port uses in place of the engine's full-board mask. The four distinct
  ## radii are 100, 64, 49 and 16, so the four boxes are 10, 8, 7 and 4 —
  ## written as a literal `case` rather than a `sqrt` (D5: no transcendental
  ## on any runtime path).
  case Units[u].visionRadius
  of 100: 10
  of 64: 8
  of 49: 7
  of 16: 4
  else:
    var k = 0
    while (k + 1) * (k + 1) <= Units[u].visionRadius: inc k
    k

func attackRangeOk*(u: UnitKind, r2: int): bool =
  ## `game.js:924`, verbatim including its coercions (D6):
  ##   `if (r > ATTACK_RADIUS[1] || r < ATTACK_RADIUS[0]) throw`
  ## A CHURCH's `ATTACK_RADIUS` is the scalar `0`, so `0[1]` and `0[0]` are
  ## both `undefined`, both comparisons are `false`, and EVERY on-board
  ## square is in range.
  case Units[u].attackRadius
  of arPair: r2 <= Units[u].attackRadiusMax and r2 >= Units[u].attackRadiusMin
  of arScalarZero: true
  of arNull: false   ## the caller must treat this as a THROW, not a refusal

func attackThrows*(u: UnitKind): bool =
  ## A PILGRIM's `ATTACK_RADIUS` is `null`, so `null[1]` raises a `TypeError`
  ## that `enactTurn` swallows (`game.js:779`): the record keeps whatever the
  ## signal and castle-talk steps set and no action happens. Measured.
  Units[u].attackRadius == arNull

func attackFuelOf*(u: UnitKind): int =
  if Units[u].attackFuelCostNull: 0 else: Units[u].attackFuelCost

func attackDamageOf*(u: UnitKind): int =
  if Units[u].attackDamageNull: 0 else: Units[u].attackDamage

func damageSpreadOf*(u: UnitKind): int =
  if Units[u].damageSpreadNull: 0 else: Units[u].damageSpread

func karboniteCapacityOf*(u: UnitKind): int =
  ## `null` for a CASTLE and a CHURCH, and `Math.min(n, null) === 0`, so a
  ## structure holds — and reclaims — exactly nothing (D6.3).
  if Units[u].karboniteCapacityNull: 0 else: Units[u].karboniteCapacity

func fuelCapacityOf*(u: UnitKind): int =
  if Units[u].fuelCapacityNull: 0 else: Units[u].fuelCapacity

func buildKarboniteOf*(u: UnitKind): int =
  ## A CASTLE cannot be built and its cost is `null`; the score's `worth` term
  ## and the reclaim's `CONSTRUCTION_KARBONITE/2` both read 0 for it.
  if Units[u].constructionKarboniteNull: 0 else: Units[u].constructionKarbonite

func buildFuelOf*(u: UnitKind): int =
  if Units[u].constructionFuelNull: 0 else: Units[u].constructionFuel

func startingHpOf*(u: UnitKind): int = Units[u].startingHp
