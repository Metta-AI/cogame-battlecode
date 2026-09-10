## The bc19 map pool, the loader (including the saved MT19937 state) and the
## per-episode draw.
##
## **bc19 SHIPS NO MAP FILES UPSTREAM.** Every board is procedurally generated
## from the game seed inside the engine constructor (`coldbrew/game.js:63`,
## `:76-361`), so the NAME IS THE RECIPE: `seed-0043` is exactly what
## `new Game(43, ...)` generates. `tools/gen_maps_bc19.mjs` runs the pinned
## engine under the pinned Node ONCE, AT BUILD TIME, curates the result for
## playability and writes `data/maps/bc19/<name>.json`; the boards are
## COMMITTED and `parity-oracle-bc19` regenerates and byte-diffs all 22
## (V3). The wasm bundle gets the directory through the existing
## `--preload-file {rootDir}/data@data` flag, so no link flag changes.
##
## Why build time and not run time, both reasons measured:
##
##   (a) `regions.sort(x => -1*x.length)` (`:153`) passes a ONE-ARGUMENT,
##       sign-constant comparator, so the result is implementation-defined.
##       Under the pinned V8 it is a plain reversal in 42 of 42 multi-region
##       cases and the region kept passable is NOT the largest in 40 of them.
##   (b) 13 of the first 400 seeds produce UNPLAYABLE boards — 2 to 4 passable
##       squares and ZERO castles — because that same reversal keeps a tiny
##       pocket and the castle placement then exhausts its 1000-try counter
##       (`:177-188`). `isOver` takes rung 4 on the very first evaluation and
##       the game is decided by a coin flip at round 0. A pool that can draw
##       such a board is not a pool.
##
## The committed file also carries `mt_state`: THE 624-WORD MT19937 STATE AND
## `mti` IMMEDIATELY AFTER `makeMap()` RETURNED, which is exactly the
## generator state `createItem` draws the castles' ids from (D1.2).

import std/[json, math, os, strutils]
import ../../sim_types
import constants, units, world

export world

const
  SmallPool* = ["seed-0009", "seed-0021", "seed-0034", "seed-0043",
                "seed-0048", "seed-0107"]
  MixedPool* = ["seed-0005", "seed-0017", "seed-0035", "seed-0039",
                "seed-0042", "seed-0058", "seed-0060", "seed-0125",
                "seed-0001", "seed-0003"]
  LargePool* = ["seed-0013", "seed-0030", "seed-0045", "seed-0056",
                "seed-0077", "seed-0117"]

  ParityPairs* = ["seed-0009", "seed-0021", "seed-0034", "seed-0043",
                  "seed-0048", "seed-0107", "seed-0017", "seed-0125",
                  "seed-0045"]
    ## The nine Tier A / A' / A" pairs, chosen to cover every branch of every
    ## rule that has one: the smallest one-castle board (`seed-0009`), the
    ## poorest one (`seed-0021`), the other symmetry axis (`seed-0034`),
    ## separation 14 with two castles a side and the most open small board
    ## (`seed-0043`, which is also the `docker-smoke` map), the only board
    ## where an order can genuinely run out of both resources (`seed-0048`),
    ## three castles a side on the most closed small board (`seed-0107`),
    ## `castles_destroyed` on the first castle death (`seed-0017`), the
    ## church-expansion and depot-claim paths under load (`seed-0125`), and
    ## 64x64 with three castles a side (`seed-0045`).

  SmokeSeed* = 13
    ## The `docker-smoke` seed, PINNED so the draw is exactly `seed-0043`
    ## from the `small` pool. `tests/test_bc19_maps.nim` asserts that draw, so
    ## the smoke's map cannot drift.

proc poolNames*(pool: string): seq[string] =
  case pool.toLowerAscii()
  of "small": @SmallPool
  of "large": @LargePool
  of "mixed", "": @MixedPool
  else: @[]

proc parseBoolRows(node: JsonNode, width, height: int, what: string): seq[bool] =
  if node.len != height:
    raise newException(ConfigError,
      "bc19 map " & what & " has " & $node.len & " rows, expected " & $height)
  result = newSeq[bool](width * height)
  for y in 0 ..< height:
    let row = node[y].getStr()
    if row.len != width:
      raise newException(ConfigError,
        "bc19 map " & what & " row " & $y & " has " & $row.len &
        " columns, expected " & $width)
    for x in 0 ..< width:
      result[y * width + x] = row[x] == '1'

proc parseMapSpec*(text: string): MapSpec =
  let doc = parseJson(text)
  result.name = doc["name"].getStr()
  result.mapSeed = doc["seed"].getInt()
  result.width = doc["width"].getInt()
  result.height = doc["height"].getInt()
  result.symmetryHorizontal = doc["symmetry"].getStr() == "horizontal"
  result.passable = parseBoolRows(doc["map"], result.width, result.height,
                                  "map")
  result.karboniteMap = parseBoolRows(doc["karbonite_map"], result.width,
                                      result.height, "karbonite_map")
  result.fuelMap = parseBoolRows(doc["fuel_map"], result.width, result.height,
                                 "fuel_map")
  for row in doc["castles"]:
    result.castles.add((x: row[0].getInt(), y: row[1].getInt(),
                        team: row[2].getInt()))
  let mt = doc["mt_state"]
  result.mtMti = mt["mti"].getInt()
  for v in mt["mt"]:
    result.mtWords.add(uint32(v.getBiggestInt() and 0xFFFFFFFF))
  if result.mtWords.len != MtN:
    raise newException(ConfigError,
      "bc19 map " & result.name & " carries " & $result.mtWords.len &
      " MT19937 words, expected " & $MtN)
  result.passableSquares = doc["passable_squares"].getInt()
  result.karboniteDepots = doc["karbonite_depots"].getInt()
  result.fuelDepots = doc["fuel_depots"].getInt()
  result.castlesPerSide = doc["castles_per_side"].getInt()
  result.separationMinMilli = doc["castle_separation_min_milli"].getInt()
  result.separationMaxMilli = doc["castle_separation_max_milli"].getInt()

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc19" / (name & ".json")

var mapCache: seq[tuple[name: string, spec: MapSpec]]

proc loadMap*(name: string): MapSpec =
  ## Cached: a best-of-three episode loads the same board once per game and
  ## the parity trace loads it once per pair, and the file carries 624 MT
  ## words plus three full boolean grids.
  for entry in mapCache:
    if entry.name == name: return entry.spec
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no generated bc19 map at " & path)
  result = parseMapSpec(readFile(path))
  mapCache.add((name: name, spec: result))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Identical in shape to the eight shipped years' draws, so the
  ## nine years rank the same way for the same seed.
  let names = poolNames(pool)
  var remaining = names
  var s = uint32(seed) xor 0x9E3779B9'u32
  for i in 0 ..< min(count, remaining.len):
    s = s * 1664525'u32 + 1013904223'u32
    let pick = int(s shr 16) mod remaining.len
    result.add(remaining[pick])
    remaining.delete(pick)

proc sideAslotFor*(seed, gameIndex: int): int =
  ## `(seed shr 8) and 1` picks which SEAT takes engine-side RED in game 1;
  ## sides alternate every game after that.
  ((seed shr 8) and 1) xor (gameIndex and 1)

# ---------------------------------------------------------------------------
#  Map cards — the per-map facts a seat may legitimately know
# ---------------------------------------------------------------------------

func castlesOf*(spec: MapSpec, team: int): seq[tuple[x, y: int]] =
  for c in spec.castles:
    if c.team == team: result.add((x: c.x, y: c.y))

func depotsOf(spec: MapSpec, karbonite: bool): seq[tuple[x, y: int]] =
  let grid = (if karbonite: spec.karboniteMap else: spec.fuelMap)
  for y in 0 ..< spec.height:
    for x in 0 ..< spec.width:
      if grid[y * spec.width + x]: result.add((x: x, y: y))

func chebyshev(ax, ay, bx, by: int): int = max(abs(ax - bx), abs(ay - by))

proc nearestDepotCard(spec: MapSpec, karbonite: bool,
                      from0: seq[tuple[x, y: int]]): JsonNode =
  var best = -1
  var bx = 0
  var by = 0
  for d in depotsOf(spec, karbonite):
    for c in from0:
      let steps = chebyshev(c.x, c.y, d.x, d.y)
      if best < 0 or steps < best:
        best = steps
        bx = d.x
        by = d.y
  if best < 0: return newJNull()
  %*{"x": bx, "y": by, "steps": best}

proc separation*(spec: MapSpec, wantMin: bool): float =
  let milli = (if wantMin: spec.separationMinMilli else: spec.separationMaxMilli)
  ## Reported to ONE decimal, which is the only place a bc19 number is not an
  ## integer: `castle_separation_*` is a Euclidean distance between two
  ## squares and there is no integer reading of it (docs/RULES-BC19.md
  ## §Divergences item 15).
  round(float(milli) / 100.0) / 10.0

proc mapCard*(spec: MapSpec, slot, sideAslot: int): JsonNode =
  ## Both seats' cards are numerically identical — every board is a mirror —
  ## and the only asymmetry is `you_are` and which mirrored coordinate set is
  ## labelled "yours". Both orders' castle positions are given because THEY
  ## ARE NOT SECRET: every robot is handed the complete terrain, karbonite and
  ## fuel maps on its first turn (`game.js:728-730`), so the enemy castles are
  ## derivable in a few operations on turn 1.
  let youAreRed = slot == sideAslot
  let yours = spec.castlesOf(if youAreRed: 0 else: 1)
  let theirs = spec.castlesOf(if youAreRed: 1 else: 0)
  var yourCastles = newJArray()
  for c in yours: yourCastles.add(%*{"x": c.x, "y": c.y})
  var enemyCastles = newJArray()
  for c in theirs: enemyCastles.add(%*{"x": c.x, "y": c.y})
  let total = spec.width * spec.height
  let pct = round(float(spec.passableSquares) * 1000.0 / float(total)) / 10.0
  let symNote =
    if spec.symmetryHorizontal:
      "mirrored across the VERTICAL midline (x -> width-1-x). Every robot " &
      "is handed the whole terrain, karbonite and fuel map on its FIRST " &
      "turn, so their castles are exactly the mirror of yours and you know " &
      "where they are from round 1."
    else:
      "mirrored across the HORIZONTAL midline (y -> height-1-y). Every " &
      "robot is handed the whole terrain, karbonite and fuel map on its " &
      "FIRST turn, so their castles are exactly the mirror of yours and you " &
      "know where they are from round 1."
  %*{
    "map": spec.name,
    "map_seed": spec.mapSeed,
    "width": spec.width,
    "height": spec.height,
    "you_are": (if youAreRed: "RED" else: "BLUE"),
    "rounds_are_one_based": true,
    "symmetry": (if spec.symmetryHorizontal: "horizontal" else: "vertical"),
    "symmetry_note": symNote,
    "passable_squares": spec.passableSquares,
    "total_squares": total,
    "passable_pct": pct,
    "your_castles": yourCastles,
    "enemy_castles": enemyCastles,
    "castle_separation_min": spec.separation(true),
    "castle_separation_max": spec.separation(false),
    "karbonite_depots": {
      "total": spec.karboniteDepots,
      "per_side": spec.karboniteDepots div 2,
      "nearest_to_you": nearestDepotCard(spec, true, yours),
      "note": "a PILGRIM standing on one mines +2 unrefined karbonite a " &
        "turn (cap 20) for 1 fuel; mining at capacity still costs the fuel " &
        "and yields nothing"
    },
    "fuel_depots": {
      "total": spec.fuelDepots,
      "per_side": spec.fuelDepots div 2,
      "nearest_to_you": nearestDepotCard(spec, false, yours),
      "note": "a PILGRIM standing on one mines +10 unrefined fuel a turn " &
        "(cap 100) for 1 fuel"
    },
    "deposit_note": "unrefined karbonite and fuel are UNSPENDABLE until a " &
      "robot GIVEs them to an adjacent CASTLE or CHURCH, which credits that " &
      "structure's team global store"
  }
