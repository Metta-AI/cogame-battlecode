## The converted bc20 map pool, the loader and the per-episode draw.
##
## Maps are read from `data/maps/bc20/<name>.json`, produced by
## `tools/convert_maps_bc20.py` from the official `.map20` files at the pinned
## battlecode20 commit and COMMITTED (CI re-converts and diffs). The wasm
## bundle gets the same directory through emscripten's `--preload-file
## data@data`, so the browser re-derives from exactly the bytes the server
## played.
##
## 18 of the 52 official maps are converted. `CowFarm` and
## `DidAMonkeyMakeThis` are deliberately excluded: both carry tiles at
## `Integer.MAX_VALUE/2` elevation, which is legal but makes the elevation
## shading meaningless and the timing untypical (docs/RULES-BC20.md).

import std/[json, os, strutils]
import ../../sim_types
import world, flood

const
  SmallPool* = ["maptestsmall", "WateredDown", "Infinity", "Spiral",
                "Hourglass", "ALandDivided"]
  MixedPool* = ["maptestsmall", "WateredDown", "Infinity", "Spiral",
                "Hourglass", "ALandDivided", "Climb", "Constriction",
                "CentralLake", "Toothpaste", "TwoLakeLand", "CentralSoup"]
  LargePool* = ["Hills", "OmgThisIsProcedural", "Squares",
                "BeachFrontProperty", "Maze", "TheHighGround"]

proc poolNames*(pool: string): seq[string] =
  case pool.toLowerAscii()
  of "small": @SmallPool
  of "large": @LargePool
  of "mixed", "": @MixedPool
  else: @[]

proc dataRoot*(): string = bc20DataRoot()

proc parseSymmetry(text: string): Symmetry =
  case text
  of "vertical": symVertical
  of "horizontal": symHorizontal
  else: symRotational

proc parseKind(text: string): RobotKind =
  case text
  of "hq": rtHq
  of "miner": rtMiner
  of "refinery": rtRefinery
  of "vaporator": rtVaporator
  of "design_school": rtDesignSchool
  of "fulfillment_center": rtFulfillmentCenter
  of "landscaper": rtLandscaper
  of "delivery_drone": rtDeliveryDrone
  of "net_gun": rtNetGun
  else: rtCow

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
  result.initialWater = doc["initial_water"].getInt()
  for v in doc["elevation"]: result.elevation.add(v.getInt())
  for v in doc["water"]: result.water.add(v.getBool())
  for v in doc["pollution"]: result.pollution.add(v.getInt())
  for v in doc["soup"]: result.soup.add(v.getInt())
  for b in doc["initial_bodies"]:
    result.initialBodies.add(InitialBody(
      id: b["id"].getInt(),
      team: parseTeam(b["team"].getStr()),
      kind: parseKind(b["type"].getStr()),
      loc: loc(b["x"].getInt(), b["y"].getInt())))
  let expected = result.width * result.height
  if result.elevation.len != expected or result.water.len != expected or
      result.soup.len != expected or result.pollution.len != expected:
    raise newException(ConfigError,
      "bc20 map " & result.name & " has inconsistent tile arrays")

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc20" / (name & ".json")

proc loadMap*(name: string): MapSpec =
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no converted bc20 map at " & path)
  parseMapSpec(readFile(path))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Deterministic in the episode seed and recorded in the results, so
  ## a spectator can re-run the same three games. Identical in shape to bc26's
  ## draw, so the two years rank the same way for the same seed.
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

proc hqLocations*(spec: MapSpec): array[2, Loc] =
  for b in spec.initialBodies:
    if b.kind == rtHq and b.team != teamNeutral:
      result[ord(b.team)] = b.loc

proc mapCard*(spec: MapSpec, slot, sideAslot: int): JsonNode =
  ## The per-map facts a seat may legitimately know before writing its
  ## doctrine. Every map is symmetric, so both seats see numerically identical
  ## cards; `you_are` is the only asymmetry.
  let hqs = spec.hqLocations()
  let side = if sideAslot == slot: 0 else: 1
  let mine = hqs[side]
  var soupTiles = 0
  var soupTotal = 0
  var soupNearHq = 0
  for i, amount in spec.soup:
    if amount > 0:
      soupTiles += 1
      soupTotal += amount
      let l = loc(i mod spec.width, i div spec.width)
      if l.distanceSquaredTo(mine) <= 100:
        soupNearHq += amount
  var cows = 0
  for b in spec.initialBodies:
    if b.kind == rtCow: cows += 1
  var floodedTiles = 0
  for wet in spec.water:
    if wet: floodedTiles += 1
  %*{
    "map": spec.name,
    "width": spec.width,
    "height": spec.height,
    "symmetry": ($spec.symmetry).replace("sym", "").toLowerAscii(),
    "you_are": (if sideAslot == slot: "A" else: "B"),
    "hq_elevation": spec.elevation[mine.x + spec.width * mine.y],
    "hq_separation": chebyshev(hqs[0], hqs[1]),
    "soup_tiles": soupTiles,
    "soup_total": soupTotal,
    "soup_near_hq": soupNearHq,
    "cows": cows,
    "initially_flooded_tiles": floodedTiles
  }
