## The converted bc24 map pool, the loader and the per-episode draw.
##
## Maps are read from `data/maps/bc24/<name>.json`, produced by
## `tools/convert_maps_bc24.py` from the official `.map24` flatbuffers at the
## pinned battlecode24 commit and COMMITTED (CI re-converts and diffs). The
## wasm bundle gets the same directory through emscripten's `--preload-file
## data@data`, so the browser re-derives from exactly the bytes the server
## played.
##
## 22 of the 78 official maps are converted. Everything above 2 700 tiles is
## out of the played pools for wall-clock reasons; `QuestionableChess` and
## `Racetrack` have ZERO crumb piles, which collapses the whole build half of
## the game; the remaining 52 are simply not converted in v1 and the converter
## handles any `.map24` (docs/RULES-BC24.md §Divergences item 10).

import std/[json, math, os, strutils]
import ../../sim_types
import world

const
  SmallPool* = ["DefaultSmall", "Yinyang", "BreadPudding", "Rivers", "Tunnels",
                "Occulus"]
  MixedPool* = ["DefaultSmall", "Yinyang", "GaltonBoard", "StackGame",
                "Alligator", "Randy", "Anchor", "DefaultMedium", "Gauntlet",
                "HungerGames", "Soccer", "DefaultLarge"]
  LargePool* = ["Bunkers", "Fountain", "CH3353C4K3F4CT0RY", "Islands",
                "Battlecode24", "DefaultHuge"]

proc poolNames*(pool: string): seq[string] =
  case pool.toLowerAscii()
  of "small": @SmallPool
  of "large": @LargePool
  of "mixed", "": @MixedPool
  else: @[]

proc dataRoot*(): string =
  ## `/data` is where emscripten mounts the preloaded directory in the wasm
  ## bundle; `data` is the repo layout the container and the tests use.
  ##
  ## `getAppDir()` is DELIBERATELY not a candidate: under emscripten it walks
  ## `os.getApplAux`, whose `readlink("/proc/self/exe")` returns -1 and whose
  ## next line is a `Natural` conversion that raises before anything is opened.
  for candidate in ["data", "/data", "/workspace/battlecode/data"]:
    if dirExists(candidate / "maps" / "bc24"):
      return candidate
  "data"

proc parseSymmetry(text: string): Symmetry =
  case text
  of "vertical": symVertical
  of "horizontal": symHorizontal
  else: symRotation

proc bits(text: string, expected: int, what, name: string): seq[bool] =
  if text.len != expected:
    raise newException(ConfigError,
      "bc24 map " & name & " has a " & $text.len & "-tile " & what &
      " array, expected " & $expected)
  result = newSeq[bool](expected)
  for i in 0 ..< expected:
    result[i] = text[i] == '1'

proc parseMapSpec*(text: string): MapSpec =
  let doc = parseJson(text)
  result.name = doc["name"].getStr()
  result.width = doc["width"].getInt()
  result.height = doc["height"].getInt()
  result.randomSeed = doc["random_seed"].getInt()
  result.symmetry = parseSymmetry(doc["symmetry"].getStr())
  let expected = result.width * result.height
  result.walls = bits(doc["walls"].getStr(), expected, "walls", result.name)
  result.water = bits(doc["water"].getStr(), expected, "water", result.name)
  result.dam = bits(doc["dam"].getStr(), expected, "dam", result.name)
  for c in doc["crumbs"]:
    result.crumbs.add((x: c[0].getInt(), y: c[1].getInt(),
                       amount: c[2].getInt()))
  for i in 0 .. 5:
    result.spawnLocations[i] = loc(doc["spawn_locations"][i][0].getInt(),
                                   doc["spawn_locations"][i][1].getInt())
    result.spawnCenters[i] = loc(doc["spawn_centers"][i][0].getInt(),
                                 doc["spawn_centers"][i][1].getInt())

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc24" / (name & ".json")

proc loadMap*(name: string): MapSpec =
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no converted bc24 map at " & path)
  parseMapSpec(readFile(path))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Identical in shape to bc26's, bc20's and bc21's draws, so the
  ## four years rank the same way for the same seed.
  let names = poolNames(pool)
  var remaining = names
  var s = uint32(seed) xor 0x9E3779B9'u32
  for i in 0 ..< min(count, remaining.len):
    s = s * 1664525'u32 + 1013904223'u32
    let pick = int(s shr 16) mod remaining.len
    result.add(remaining[pick])
    remaining.delete(pick)

proc sideAslotFor*(seed, gameIndex: int): int =
  ## `(seed shr 8) and 1` picks which SEAT takes side A in game 1; sides
  ## alternate every game after that.
  ((seed shr 8) and 1) xor (gameIndex and 1)

# ---------------------------------------------------------------------------
#  Map cards — the per-map facts a seat may legitimately know
# ---------------------------------------------------------------------------

proc centersOf*(spec: MapSpec, team: Team): array[3, Loc] =
  for i in 0 .. 2:
    result[i] = spec.spawnCenters[i * 2 + (if team == teamA: 0 else: 1)]

proc minSeparation*(spec: MapSpec): float64 =
  ## The shortest Euclidean distance between an A centre and a B centre: the
  ## one number that says how far a raid has to run.
  var best = high(float64)
  for a in spec.centersOf(teamA):
    for b in spec.centersOf(teamB):
      best = min(best, sqrt(float64(a.distanceSquaredTo(b))))
  if best == high(float64): 0.0 else: best

proc mapCard*(spec: MapSpec, slot, sideAslot: int): JsonNode =
  ## Every map is symmetric, so both seats' cards are numerically identical;
  ## `you_are` and which mirrored coordinate set is labelled "yours" are the
  ## only asymmetries.
  let side = if sideAslot == slot: teamA else: teamB
  var mine = newJArray()
  for l in spec.centersOf(side):
    mine.add(%*[l.x, l.y])
  var theirs = newJArray()
  for l in spec.centersOf(side.other()):
    theirs.add(%*[l.x, l.y])
  var walls, water, dam = 0
  for v in spec.walls:
    if v: walls += 1
  for v in spec.water:
    if v: water += 1
  for v in spec.dam:
    if v: dam += 1
  var total = 0
  for c in spec.crumbs: total += c.amount
  let tiles = max(1, spec.width * spec.height)
  var nearest = 0
  block nearestPile:
    var best = high(int)
    for c in spec.crumbs:
      for centre in spec.centersOf(side):
        best = min(best, centre.distanceSquaredTo(loc(c.x, c.y)))
    if best < high(int):
      nearest = int(round(sqrt(float64(best))))
  %*{
    "map": spec.name,
    "width": spec.width,
    "height": spec.height,
    "symmetry": ($spec.symmetry).replace("sym", "").toLowerAscii(),
    "you_are": (if sideAslot == slot: "A" else: "B"),
    "setup_rounds": SetupRounds,
    "your_spawn_centers": mine,
    "enemy_spawn_centers": theirs,
    "min_spawn_separation": round(spec.minSeparation() * 10.0) / 10.0,
    "terrain": {
      "walls": walls, "water": water, "dam": dam,
      "passable_pct":
        round(float(tiles - walls - water) / float(tiles) * 1000.0) / 10.0
    },
    "crumbs": {"piles": spec.crumbs.len, "total": total,
               "nearest_pile_to_you": nearest}
  }
