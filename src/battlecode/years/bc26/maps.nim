## The converted map pool and the per-episode draw.
##
## Maps are read from `data/maps/bc26/<name>.json`, produced by
## `tools/convert_maps.py` from the official `.map26` files at tag
## `engine.1.2.5` and COMMITTED (CI re-converts and diffs). The wasm bundle
## gets the same directory through emscripten's `--preload-file data@data`,
## so the browser re-derives from exactly the bytes the server played.
##
## The pool at the pinned tag is 43 maps. `Stash`, `uneasy_alliance`,
## `Excavation` and `RUN` do NOT exist there — they landed later on master —
## and are deliberately absent.

import std/[json, os, strutils]
import ../../sim_types
import constants, world

const
  SmallPool* = ["DefaultSmall", "arrows", "closeup", "toomuchcheese",
                "cheesefarm", "dirtfulcat"]
  MixedPool* = ["DefaultSmall", "arrows", "closeup", "toomuchcheese",
                "cheesefarm", "dirtfulcat", "ZeroDay", "knifefight",
                "whatsthecatdoin", "thunderdome", "DefaultMedium",
                "mercifullattice"]
  LargePool* = ["DefaultLarge", "Nofreecheese", "averystrangespace",
                "safelycontained", "streetsofnewyork", "uneruesansfin"]

proc poolNames*(pool: string): seq[string] =
  case pool.toLowerAscii()
  of "small": @SmallPool
  of "large": @LargePool
  else: @MixedPool

proc dataRoot*(): string =
  ## `/data` is where emscripten mounts the preloaded directory in the wasm
  ## bundle; `data` is the repo layout the container and the tests use.
  for candidate in ["data", "/data", "/workspace/battlecode/data",
                    getAppDir() / "data"]:
    if dirExists(candidate / "maps" / "bc26"):
      return candidate
  "data"

proc parseSymmetry(text: string): Symmetry =
  case text
  of "horizontal": symHorizontal
  of "vertical": symVertical
  else: symRotational

proc parseDir(text: string): Dir =
  case text
  of "north": dNorth
  of "northeast": dNortheast
  of "east": dEast
  of "southeast": dSoutheast
  of "south": dSouth
  of "southwest": dSouthwest
  of "west": dWest
  of "northwest": dNorthwest
  else: dCenter

proc parseUnit(text: string): UnitType =
  case text
  of "rat_king": utRatKing
  of "cat": utCat
  else: utBabyRat

proc parseTeam(text: string): Team =
  case text
  of "A": teamA
  of "B": teamB
  else: teamNeutral

proc parseMapSpec*(text: string): MapSpec =
  let doc = parseJson(text)
  result.name = doc["name"].getStr()
  result.width = doc["width"].getInt()
  result.height = doc["height"].getInt()
  result.symmetry = parseSymmetry(doc["symmetry"].getStr())
  result.randomSeed = doc["random_seed"].getInt()
  for v in doc["walls"]: result.walls.add(v.getBool())
  for v in doc["dirt"]: result.dirt.add(v.getBool())
  for v in doc["cheese"]: result.cheese.add(v.getInt())
  for v in doc["cheese_mines"]: result.cheeseMines.add(v.getInt())
  for v in doc["cat_waypoint_ids"]: result.catWaypointIds.add(v.getInt())
  for vec in doc["cat_waypoint_vecs"]:
    var wps: seq[int]
    for v in vec: wps.add(v.getInt())
    result.catWaypointVecs.add(wps)
  for b in doc["initial_bodies"]:
    result.initialBodies.add(InitialBody(
      id: b["id"].getInt(),
      team: parseTeam(b["team"].getStr()),
      unit: parseUnit(b["unit"].getStr()),
      loc: loc(b["x"].getInt(), b["y"].getInt()),
      dir: parseDir(b["dir"].getStr()),
      chirality: b["chirality"].getInt()
    ))
  let expected = result.width * result.height
  if result.walls.len != expected or result.dirt.len != expected or
      result.cheese.len != expected:
    raise newException(ConfigError,
      "map " & result.name & " has inconsistent tile arrays")

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc26" / (name & ".json")

proc loadMap*(name: string): MapSpec =
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no converted map at " & path)
  parseMapSpec(readFile(path))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Deterministic in the episode seed and recorded in the results,
  ## so a spectator can re-run the same three games.
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
