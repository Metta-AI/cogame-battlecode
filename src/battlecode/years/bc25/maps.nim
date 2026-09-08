## The converted bc25 map pool, the loader and the per-episode draw.
##
## Maps are read from `data/maps/bc25/<name>.json`, produced by
## `tools/convert_maps_bc25.py` from the official `.map25` flatbuffers at the
## pinned battlecode25 commit and COMMITTED (CI re-converts and byte-diffs).
## The wasm bundle gets the same directory through emscripten's
## `--preload-file data@data`, so the browser re-derives from exactly the
## bytes the server played.
##
## 22 of the 75 official maps are converted. Everything above 1500 tiles is out
## of the PLAYED pools for wall-clock reasons (six are converted anyway, under
## `large`); `Terminal`, `box`, `catface`, `fix`, `gridworld`, `maze`, `shell`
## and `windmill` have ZERO pre-painted tiles, which is legal but makes the
## first fifty rounds identical on every doctrine; the remaining 45 are simply
## not converted in v1 and the converter handles any `.map25`
## (docs/RULES-BC25.md §Divergences item 11).
##
## `mixed` is the `bc25` variant's pool and is chosen to span the axis the
## doctrines argue about: all three symmetries; 400 to 1500 tiles; ruin density
## from 12.0 per 1000 tiles (`leavemealone`, a coverage war because there is
## barely anything to build on) to 30.0 (`DefaultSmall`, a tower sprint); and
## wall percentages from 1.6 % (`DefaultLarge`, where no choke exists at all
## and `defense_tower_chokes` is nearly a dead knob) to 14.4 % (`roads`, where
## it is the whole game).

import std/[json, math, os, strutils]
import ../../sim_types
import world

const
  SmallPool* = ["DefaultSmall", "CastleDefense", "Paintball", "Justice",
                "Filter", "Jail"]
  MixedPool* = ["DefaultSmall", "Justice", "Fossil", "SandyBeach", "rain",
                "roads", "DefaultMedium", "Money", "Portal", "Bunny",
                "DefaultLarge", "leavemealone"]
  LargePool* = ["HungerGames", "Oasis", "DefaultHuge", "Leaf", "SMILE",
                "gardenworld"]

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
    if dirExists(candidate / "maps" / "bc25"):
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
  let expected = result.width * result.height
  let bits = doc["walls"].getStr()
  if bits.len != expected:
    raise newException(ConfigError,
      "bc25 map " & result.name & " has a " & $bits.len &
      "-tile wall array, expected " & $expected)
  result.walls = newSeq[bool](expected)
  for i in 0 ..< expected:
    result.walls[i] = bits[i] == '1'
  for r in doc["ruins"]:
    result.ruins.add(loc(r[0].getInt(), r[1].getInt()))
  for p in doc["paint"]:
    result.paint.add((x: p[0].getInt(), y: p[1].getInt(),
                      colour: p[2].getInt()))
  for b in doc["initial_bodies"]:
    result.initialBodies.add((id: b[0].getInt(), x: b[1].getInt(),
                              y: b[2].getInt(), team: b[3].getInt(),
                              kind: b[4].getInt()))

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc25" / (name & ".json")

proc loadMap*(name: string): MapSpec =
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no converted bc25 map at " & path)
  parseMapSpec(readFile(path))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Identical in shape to the four shipped years' draws, so the five
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

proc startTowersOf*(spec: MapSpec, team: Team): seq[JsonNode] =
  ## The four starting towers are PUBLIC: every map is symmetric and the
  ## engine's own map file puts them there, so hiding them would hide nothing
  ## and cost the doctrine its opening.
  var bodies = spec.initialBodies
  for i in 1 ..< bodies.len:
    var j = i
    while j > 0 and bodies[j - 1].id > bodies[j].id:
      swap(bodies[j - 1], bodies[j])
      dec j
  for b in bodies:
    let bodyTeam = if b.team == 1: teamA else: teamB
    if bodyTeam != team: continue
    result.add(%*{
      "kind": (if b.kind == 1: "paint" else: "money"),
      "level": 2, "x": b.x, "y": b.y})

proc startSeparation*(spec: MapSpec): float64 =
  ## The shortest Euclidean distance between an A starting tower and a B one:
  ## the one number that says how far a rush has to run.
  var best = high(float64)
  for a in spec.initialBodies:
    for b in spec.initialBodies:
      if a.team == b.team: continue
      let d = float64((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
      best = min(best, sqrt(d))
  if best == high(float64): 0.0 else: best

proc chokeCount*(spec: MapSpec): int =
  ## A cheap, deterministic reading of "how many narrow passable cuts does
  ## this map have": columns (or rows, on a vertical mirror) whose passable
  ## count is at most a quarter of the map's dimension. Never used by a rule;
  ## it is a number the doctrine can plan `defense_tower_chokes` against.
  var ruin = newSeq[bool](spec.width * spec.height)
  for r in spec.ruins: ruin[r.x + r.y * spec.width] = true
  let vertical = spec.symmetry != symHorizontal
  let outerLen = if vertical: spec.width else: spec.height
  let innerLen = if vertical: spec.height else: spec.width
  let threshold = max(1, innerLen div 4)
  for a in 0 ..< outerLen:
    var open = 0
    for b in 0 ..< innerLen:
      let i = if vertical: a + b * spec.width else: b + a * spec.width
      if not spec.walls[i] and not ruin[i]: open += 1
    if open <= threshold: result += 1

proc mapCard*(spec: MapSpec, slot, sideAslot: int): JsonNode =
  ## Every map is symmetric, so both seats' cards are numerically identical;
  ## `you_are` and which mirrored coordinate set is labelled "yours" are the
  ## only asymmetries.
  let side = if sideAslot == slot: teamA else: teamB
  var walls = 0
  for v in spec.walls:
    if v: walls += 1
  let tiles = spec.width * spec.height
  let areaWithoutWalls = tiles - walls
  ## The file's ruin list plus the four starting-tower tiles, which the engine
  ## adds to `allRuins` in its own constructor.
  var ruinSet = newSeq[bool](tiles)
  for r in spec.ruins: ruinSet[r.x + r.y * spec.width] = true
  for b in spec.initialBodies: ruinSet[b.x + b.y * spec.width] = true
  var ruins = 0
  for v in ruinSet:
    if v: ruins += 1
  var mine = newJArray()
  for t in spec.startTowersOf(side): mine.add(t)
  var theirs = newJArray()
  for t in spec.startTowersOf(side.other()): theirs.add(t)
  %*{
    "map": spec.name,
    "width": spec.width,
    "height": spec.height,
    "symmetry": ($spec.symmetry).replace("sym", "").toLowerAscii(),
    "you_are": (if sideAslot == slot: "A" else: "B"),
    "your_start_towers": mine,
    "enemy_start_towers": theirs,
    "start_separation": round(spec.startSeparation() * 10.0) / 10.0,
    "terrain": {
      "walls": walls,
      "wall_pct": round(float(walls) / float(max(1, tiles)) * 1000.0) / 10.0,
      "ruins": ruins,
      "ruins_per_1000":
        round(float(ruins) / float(max(1, tiles)) * 10000.0) / 10.0,
      "area_without_walls": areaWithoutWalls,
      "truly_paintable": areaWithoutWalls - ruins,
      "tiles_to_win": tilesToWin(areaWithoutWalls),
      "pre_painted": spec.paint.len
    },
    "chokes": spec.chokeCount()
  }
