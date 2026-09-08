## The converted bc23 map pool, the loader and the per-episode draw.
##
## Maps are read from `data/maps/bc23/<name>.json`, produced by
## `tools/convert_maps_bc23.py` from the official `.map23` flatbuffers at the
## pinned battlecode23 commit and COMMITTED (CI re-converts and byte-diffs).
## The wasm bundle gets the same directory through emscripten's
## `--preload-file data@data`, so the browser re-derives from exactly the
## bytes the server played.
##
## 22 of the 103 official maps are converted. Everything above 1 800 tiles is
## out of the PLAYED pools for wall-clock reasons (six are converted anyway,
## under `large`); `Marsh` (1 218 cloud tiles of 3 000, 40.6 %) and
## `BuildSite` (71.2 % walls) are converted for neither pool because a map
## where most of the board blinds or blocks the fight makes every doctrine
## look the same; the remaining 81 are simply not converted in v1 and the
## converter handles any `.map23` (docs/RULES-BC23.md §Divergences item 11).
##
## `mixed` is the `bc23` variant's pool and is chosen to span the axis the
## doctrines argue about: all three symmetries; 500 to 1 800 tiles; ISLANDS
## FROM 4 (`Eyelands`, `Rectangle` — conquest needs 3, so one launcher push
## decides the game) TO 20 (`Rainbow` — conquest needs 15, so ferry logistics
## and garrisons decide it); headquarters per side 2 and 3; cloud coverage
## from 0.9 % (`Eyelands`) to 13 % (`Rainbow`); and current density from 8
## tiles (`MoonPhases`) to 82 (`Eyelands`).

import std/[json, math, os, strutils, tables]
import ../../sim_types
import world

const
  SmallPool* = ["Quiet", "SmallElements", "Lantern", "Spin", "Sneaky",
                "Barcode"]
  MixedPool* = ["AllElements", "DefaultMap", "Cave", "MoonPhases", "Eyelands",
                "Rectangle", "Scatter", "HideAndSeek", "Rainbow",
                "IslandHopping"]
  LargePool* = ["Spiderweb", "ThirtyFive", "Target", "Spots", "Forest",
                "Grievance"]

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
    if dirExists(candidate / "maps" / "bc23"):
      return candidate
  "data"

proc parseSymmetry(text: string): Symmetry =
  case text
  of "vertical": symVertical
  of "horizontal": symHorizontal
  else: symRotation

proc parseMapSpec*(text: string): MapSpec =
  let doc = parseJson(text)
  result.name = doc["name"].getStr()
  result.width = doc["width"].getInt()
  result.height = doc["height"].getInt()
  result.randomSeed = doc["random_seed"].getInt()
  result.symmetry = parseSymmetry(doc["symmetry"].getStr())
  result.rounds = doc{"rounds"}.getInt(GameMaxNumberOfRounds)
  let expected = result.width * result.height
  for key in ["walls", "clouds"]:
    let bits = doc[key].getStr()
    if bits.len != expected:
      raise newException(ConfigError,
        "bc23 map " & result.name & " has a " & $bits.len & "-tile " & key &
        " array, expected " & $expected)
  let wallBits = doc["walls"].getStr()
  let cloudBits = doc["clouds"].getStr()
  result.walls = newSeq[bool](expected)
  result.clouds = newSeq[bool](expected)
  for i in 0 ..< expected:
    result.walls[i] = wallBits[i] == '1'
    result.clouds[i] = cloudBits[i] == '1'
  result.currents = newSeq[int](expected)
  result.islandIds = newSeq[int](expected)
  result.resources = newSeq[int](expected)
  for c in doc["currents"]:
    result.currents[c[0].getInt() + c[1].getInt() * result.width] =
      c[2].getInt()
  for c in doc["islands"]:
    result.islandIds[c[0].getInt() + c[1].getInt() * result.width] =
      c[2].getInt()
  for c in doc["resources"]:
    result.resources[c[0].getInt() + c[1].getInt() * result.width] =
      c[2].getInt()
  for b in doc["initial_bodies"]:
    result.initialBodies.add((id: b[0].getInt(), x: b[1].getInt(),
                              y: b[2].getInt(), team: b[3].getInt(),
                              kind: b[4].getInt()))

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc23" / (name & ".json")

proc loadMap*(name: string): MapSpec =
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no converted bc23 map at " & path)
  parseMapSpec(readFile(path))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Identical in shape to the five shipped years' draws, so the six
  ## years rank the same way for the same seed.
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

proc islandSizes*(spec: MapSpec): seq[int] =
  var byId = initTable[int, int]()
  var ids: seq[int]
  for id in spec.islandIds:
    if id == 0: continue
    if not byId.hasKey(id):
      byId[id] = 0
      ids.add(id)
    byId[id] += 1
  for id in ids: result.add(byId[id])
  ## Descending, so a doctrine reads the biggest garrison problem first.
  for i in 1 ..< result.len:
    var j = i
    while j > 0 and result[j - 1] < result[j]:
      swap(result[j - 1], result[j])
      dec j

proc islandCount*(spec: MapSpec): int = spec.islandSizes().len

proc headquartersOf*(spec: MapSpec, team: Team): seq[JsonNode] =
  ## The headquarters are PUBLIC: every map is symmetric and the engine's own
  ## map file puts them there, so hiding them would hide nothing and cost the
  ## doctrine its opening.
  for b in spec.initialBodies:
    let bodyTeam = if b.team == 1: teamA else: teamB
    if bodyTeam != team: continue
    result.add(%*{"x": b.x, "y": b.y})

proc headquartersPerSide*(spec: MapSpec): int =
  spec.headquartersOf(teamA).len

proc startSeparation*(spec: MapSpec): float64 =
  ## The shortest Euclidean distance between an A headquarters and a B one:
  ## the one number that says how far a launcher rush has to run.
  var best = high(float64)
  for a in spec.initialBodies:
    for b in spec.initialBodies:
      if a.team == b.team: continue
      let d = float64((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
      best = min(best, sqrt(d))
  if best == high(float64): 0.0 else: best

proc countResources(spec: MapSpec, kind: int): int =
  for v in spec.resources:
    if v == kind: result += 1

proc nearestWell*(spec: MapSpec, from0: JsonNode): JsonNode =
  ## The nearest well to a headquarters, by Chebyshev steps — the walking
  ## distance a carrier actually pays, because movement is eight-directional.
  if from0.isNil: return newJNull()
  let fx = from0["x"].getInt()
  let fy = from0["y"].getInt()
  var best = high(int)
  var bx, by, bt = 0
  for i in 0 ..< spec.resources.len:
    if spec.resources[i] == 0: continue
    let x = i mod spec.width
    let y = i div spec.width
    let steps = max(abs(x - fx), abs(y - fy))
    if steps < best:
      best = steps
      bx = x
      by = y
      bt = spec.resources[i]
  if best == high(int): return newJNull()
  %*{"type": (if bt == 1: "adamantium" elif bt == 2: "mana" else: "elixir"),
     "x": bx, "y": by, "steps": best}

proc nearestIsland*(spec: MapSpec, from0: JsonNode): JsonNode =
  if from0.isNil: return newJNull()
  let fx = from0["x"].getInt()
  let fy = from0["y"].getInt()
  var best = high(int)
  var bestId = 0
  var sizes = initTable[int, int]()
  for i in 0 ..< spec.islandIds.len:
    let id = spec.islandIds[i]
    if id == 0: continue
    if not sizes.hasKey(id): sizes[id] = 0
    sizes[id] += 1
    let steps = max(abs(i mod spec.width - fx), abs(i div spec.width - fy))
    if steps < best:
      best = steps
      bestId = id
  if bestId == 0: return newJNull()
  %*{"id": bestId, "tiles": sizes[bestId], "steps": best}

proc mapCard*(spec: MapSpec, slot, sideAslot: int): JsonNode =
  ## Every map is symmetric, so both seats' cards are numerically identical;
  ## `you_are` and which mirrored coordinate set is labelled "yours" are the
  ## only asymmetries.
  let side = if sideAslot == slot: teamA else: teamB
  var walls = 0
  for v in spec.walls:
    if v: walls += 1
  var clouds = 0
  for v in spec.clouds:
    if v: clouds += 1
  var currents = 0
  for v in spec.currents:
    if v != 0: currents += 1
  let tiles = spec.width * spec.height
  let sizes = spec.islandSizes()
  var sizeArray = newJArray()
  for s in sizes: sizeArray.add(%s)
  var islandTiles = 0
  for s in sizes: islandTiles += s
  var mine = newJArray()
  for h in spec.headquartersOf(side): mine.add(h)
  var theirs = newJArray()
  for h in spec.headquartersOf(side.other()): theirs.add(h)
  let firstMine = if mine.len > 0: mine[0] else: nil
  %*{
    "map": spec.name,
    "width": spec.width,
    "height": spec.height,
    "symmetry": ($spec.symmetry).replace("sym", "").toLowerAscii(),
    "you_are": (if sideAslot == slot: "A" else: "B"),
    "islands": sizes.len,
    "islands_to_win": islandsToWin(sizes.len),
    "island_tiles": islandTiles,
    "island_sizes": sizeArray,
    "your_headquarters": mine,
    "enemy_headquarters": theirs,
    "start_separation": round(spec.startSeparation() * 10.0) / 10.0,
    "terrain": {
      "impassable": walls,
      "impassable_pct": round(float(walls) / float(max(1, tiles)) * 1000.0) /
        10.0,
      "clouds": clouds,
      "cloud_pct": round(float(clouds) / float(max(1, tiles)) * 1000.0) / 10.0,
      "currents": currents,
      "adamantium_wells": spec.countResources(1),
      "mana_wells": spec.countResources(2),
      "elixir_wells": spec.countResources(3)
    },
    "nearest_well_to_you": spec.nearestWell(firstMine),
    "nearest_island_to_you": spec.nearestIsland(firstMine)
  }
