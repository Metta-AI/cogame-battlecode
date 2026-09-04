## The converted bc21 map pool, the loader and the per-episode draw.
##
## Maps are read from `data/maps/bc21/<name>.json`, produced by
## `tools/convert_maps_bc21.py` from the official `.map21` files at the pinned
## battlecode21 commit and COMMITTED (CI re-converts and diffs). The wasm
## bundle gets the same directory through emscripten's `--preload-file
## data@data`, so the browser re-derives from exactly the bytes the server
## played.
##
## 18 of the 76 official maps are converted. `Cow` (80x50, over the spec's own
## `MAP_MAX_WIDTH` and dropped from scrimmages by patch 2021.2.4.0) and
## `Misdirection` (two tiles at passability exactly 0.0, which give an infinite
## cooldown and freeze a robot for ever) are excluded on purpose
## (docs/RULES-BC21.md).

import std/[json, math, os, strutils]
import ../../sim_types
import world

const
  SmallPool* = ["maptestsmall", "Arena", "Bog", "FrogOrBath", "Smile", "Star"]
  MixedPool* = ["maptestsmall", "Arena", "Bog", "FrogOrBath", "Smile", "Star",
                "Corridor", "SeaFloor", "quadrants", "Maze", "Hourglass",
                "PaperWindmill"]
  LargePool* = ["Blotches", "Circles", "BadSnowflake", "AmidstWe", "Yoda",
                "Gridlock"]

proc poolNames*(pool: string): seq[string] =
  case pool.toLowerAscii()
  of "small": @SmallPool
  of "large": @LargePool
  of "mixed", "": @MixedPool
  else: @[]

proc dataRoot*(): string = bc21DataRoot()

proc parseSymmetry(text: string): Symmetry =
  case text
  of "vertical": symVertical
  of "horizontal": symHorizontal
  else: symRotational

proc parseKind(text: string): RobotKind =
  case text
  of "politician": rtPolitician
  of "slanderer": rtSlanderer
  of "muckraker": rtMuckraker
  else: rtEnlightenmentCenter

proc parseTeam(text: string): Team =
  case text
  of "a": teamA
  of "b": teamB
  else: teamNeutral

proc parseMapSpec*(text: string): MapSpec =
  let doc = parseJson(text)
  result.name = doc["name"].getStr()
  result.width = doc["width"].getInt()
  result.height = doc["height"].getInt()
  result.origin = [doc["origin"][0].getInt(), doc["origin"][1].getInt()]
  result.randomSeed = doc["random_seed"].getInt()
  result.symmetry = parseSymmetry(doc["symmetry"].getStr())
  for s in doc["symmetries"]:
    result.symmetries.add(parseSymmetry(s.getStr()))
  for v in doc["passability"]: result.passability.add(v.getFloat())
  for b in doc["initial_bodies"]:
    result.initialBodies.add(InitialBody(
      id: b["id"].getInt(),
      team: parseTeam(b["team"].getStr()),
      kind: parseKind(b["type"].getStr()),
      loc: loc(b["x"].getInt(), b["y"].getInt()),
      influence: b["influence"].getInt()))
  let expected = result.width * result.height
  if result.passability.len != expected:
    raise newException(ConfigError,
      "bc21 map " & result.name & " has a " & $result.passability.len &
      "-tile passability array, expected " & $expected)

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc21" / (name & ".json")

proc loadMap*(name: string): MapSpec =
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no converted bc21 map at " & path)
  parseMapSpec(readFile(path))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Deterministic in the episode seed and recorded in the results, so
  ## a spectator can re-run the same three games. Identical in shape to bc26's
  ## and bc20's draws, so the three years rank the same way for the same seed.
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

proc ownCenters*(spec: MapSpec, team: Team): seq[InitialBody] =
  for b in spec.initialBodies:
    if b.kind == rtEnlightenmentCenter and b.team == team:
      result.add(b)

proc neutralCenters*(spec: MapSpec): seq[InitialBody] =
  for b in spec.initialBodies:
    if b.kind == rtEnlightenmentCenter and b.team == teamNeutral:
      result.add(b)

proc centerSeparation*(spec: MapSpec): int =
  ## The minimum Euclidean distance between an A-owned Center and a B-owned
  ## one, rounded. It is the one number that says how long a politician has to
  ## walk before anything happens.
  var best = high(float64)
  for a in spec.ownCenters(teamA):
    for b in spec.ownCenters(teamB):
      best = min(best, sqrt(float64(a.loc.distanceSquaredTo(b.loc))))
  if best == high(float64): 0 else: int(round(best))

const SwampThreshold* = 0.5
  ## A tile below this passability at least doubles every action's cooldown;
  ## the map card calls those tiles "swamp". Ours, not the engine's — the 2021
  ## engine has no terrain categories at all, only the passability number.

proc mapCard*(spec: MapSpec, slot, sideAslot: int): JsonNode =
  ## The per-map facts a seat may legitimately know before writing its
  ## doctrine. Every map is symmetric, so both seats see numerically identical
  ## cards; `you_are` and which mirrored coordinate set is labelled "yours" are
  ## the only asymmetries.
  let side = if sideAslot == slot: teamA else: teamB
  var mine = newJArray()
  for b in spec.ownCenters(side):
    mine.add(%*{"x": b.loc.x, "y": b.loc.y, "influence": b.influence})
  var neutrals = newJArray()
  for b in spec.neutralCenters():
    neutrals.add(%*{"x": b.loc.x, "y": b.loc.y, "influence": b.influence})
  var symmetries = newJArray()
  for s in spec.symmetries:
    symmetries.add(%($s).replace("sym", "").toLowerAscii())
  var minPass = 1.0
  var sum = 0.0
  var swamp = 0
  for p in spec.passability:
    minPass = min(minPass, p)
    sum += p
    if p < SwampThreshold: swamp += 1
  let n = max(1, spec.passability.len)
  %*{
    "map": spec.name,
    "width": spec.width,
    "height": spec.height,
    "symmetry": ($spec.symmetry).replace("sym", "").toLowerAscii(),
    "symmetries": symmetries,
    "you_are": (if sideAslot == slot: "A" else: "B"),
    "your_centers": mine,
    "enemy_centers": spec.ownCenters(other(side)).len,
    "neutral_centers": neutrals,
    "center_separation": spec.centerSeparation(),
    "passability": {
      "min": round(minPass * 100.0) / 100.0,
      "mean": round(sum / float(n) * 1000.0) / 1000.0,
      "swamp_pct": round(float(swamp) / float(n) * 1000.0) / 10.0
    }
  }
