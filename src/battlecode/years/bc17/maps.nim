## The bc17 map pool, the loader and the per-episode draw.
##
## The boards are the engine's own `battlecode/world/resources/*.map17`
## flatbuffers, converted at BUILD time by `tools/convert_maps_bc17.py` --
## pure Python, reading them straight out of the pinned oracle jar with no JVM
## -- and COMMITTED as `data/maps/bc17/<Name>.json`. The `test` job re-runs
## the converter with `--check` and byte-diffs all 22, and
## `parity-oracle-bc17`'s Tier B cross-checks every one against the JVM's own
## `LiveMap` fields, so a hand-edited board fails the build. The runtime sim
## has NO flatbuffer reader (V2).
##
## **TWO CONVERSION RULES COME FROM THE ENGINE AND NOT FROM THE FILE**, and
## the loader inherits both: `rounds` is always
## `GameConstants.GAME_DEFAULT_ROUNDS` = 3000 (`GameMapIO.java:235` never
## reads a round count from the map, and all seventy official maps therefore
## run 2 999 played rounds), and a neutral tree's health is RECOMPUTED as
## `200 x radius` with the file's own `healths` vector ignored.
##
## `initial_bodies` is stored ASCENDING BY ID, which is `LiveMap`'s
## constructor's own sort (`LiveMap.java:67`) and therefore the opening exec
## order -- the order the archons take their turns in. On `HouseDivided`,
## **Team B's archon (id 54) precedes Team A's (id 55)**.

import std/[json, math, os, strutils]
import ../../sim_types
import constants, units, geom, world

export world

const
  SmallPool* = ["CropCircles", "GreenHouse", "HiddenTunnel", "HouseDivided",
                "OMGTree", "shrine"]
  MixedPool* = ["Aligned", "Barrier", "Blitzkrieg", "Chess", "Cramped",
                "DenseForest", "Hurdle", "Snowflake", "TreeFarm", "Waves"]
  LargePool* = ["Alone", "GiantForest", "Interference", "LineOfFire",
                "Maniple", "Whirligig"]

  ParityPairs* = ["CropCircles", "GreenHouse", "HiddenTunnel",
                  "HouseDivided", "OMGTree", "shrine", "Chess", "Cramped",
                  "Alone"]
    ## The nine Tier A / A' / A" pairs, chosen to cover every branch of every
    ## rule that has one: 198 radius-0.5 trees on the smallest board
    ## (`CropCircles`); 58 trees EVERY ONE of which contains a robot and 56 of
    ## which hold bullets, i.e. the chop-release path, the scout-crush rule
    ## and `shake` (`GreenHouse`); 484 radius-0.5 trees, the maximum candidate
    ## count per bullet update on a small board (`HiddenTunnel`); archon
    ## separation 6.5, so first blood lands inside twenty rounds -- **and this
    ## is the `docker-smoke` map** (`HouseDivided`); ONE radius-10 tree, the
    ## 2 000-HP wall and the largest possible `targetRadius` in `calcHitDist`
    ## (`OMGTree`); a near-empty board as the control that proves the tree
    ## phase is not what makes the others agree (`shrine`); 924 trees on 64x64
    ## with 28 holding robots, the heaviest candidate load and the perf gate's
    ## map (`Chess`); separation 5.0 with radius-2.5 trees, so bodies cannot
    ## pass each other and `canMove`'s tank/scout split matters from round 1
    ## (`Cramped`); and 100x100 with ZERO trees, the longest bullet flights and
    ## the cleanest test of the bullet id stream and the income cliff
    ## (`Alone`).

  SmokeSeed* = 5
    ## The `docker-smoke` seed, PINNED so the draw from the `small` pool is
    ## exactly `HouseDivided`. `tests/test_bc17_maps.nim` asserts that draw,
    ## so the smoke's map cannot drift.

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
  ## next line is a `Natural` conversion that raises before anything is
  ## opened.
  for candidate in ["data", "/data", "/workspace/battlecode/data"]:
    if dirExists(candidate / "maps" / "bc17"):
      return candidate
  "data"

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc17" / (name & ".json")

proc f32Of(node: JsonNode): float32 =
  ## Every float in a committed board is the shortest decimal that
  ## round-trips its float64 widening, so `getFloat` recovers the float64 and
  ## this narrowing recovers the engine's exact float32 bit pattern.
  float32(node.getFloat())

proc parseMapSpec*(text: string): MapSpec =
  let doc = parseJson(text)
  result.name = doc["name"].getStr()
  result.mapSeed = doc["seed"].getInt()
  result.rounds = doc["rounds"].getInt()
  result.rect = MapRect(
    origin: loc(f32Of(doc["origin"][0]), f32Of(doc["origin"][1])),
    width: f32Of(doc["width"]), height: f32Of(doc["height"]))
  var archonsA: seq[Loc]
  var archonsB: seq[Loc]
  for row in doc["initial_bodies"]:
    let kindText = row["kind"].getStr()
    let teamText = row["team"].getStr()
    let team = (case teamText
                of "A": tA
                of "B": tB
                else: tNeutral)
    let l = loc(f32Of(row["x"]), f32Of(row["y"]))
    if kindText == "robot":
      let typeText = row["type"].getStr().toUpperAscii()
      var kind = rtArchon
      var found = false
      for candidate in RobotType:
        if $candidate == typeText:
          kind = candidate
          found = true
      if not found:
        raise newException(ConfigError,
          "bc17 map " & result.name & " carries an unknown robot type " &
          typeText)
      result.bodies.add(MapBody(isRobot: true, id: row["id"].getInt(),
                                team: team, kind: kind, loc: l,
                                containedRobot: -1))
      if kind == rtArchon:
        if team == tA: archonsA.add(l) else: archonsB.add(l)
    else:
      var contained = -1
      let containedText = row["contained_robot"].getStr().toUpperAscii()
      if containedText != "-":
        for candidate in RobotType:
          if $candidate == containedText:
            contained = ord(candidate)
        if contained < 0:
          raise newException(ConfigError,
            "bc17 map " & result.name & " has a tree containing an unknown " &
            "type " & containedText)
      let radius = f32Of(row["radius"])
      result.bodies.add(MapBody(
        isRobot: false, id: row["id"].getInt(), team: tNeutral, loc: l,
        radius: radius, health: f32Of(row["health"]),
        containedBullets: row["contained_bullets"].getInt(),
        containedRobot: contained))
      inc result.neutralTrees
      if row["contained_bullets"].getInt() > 0: inc result.treesWithBullets
      if contained >= 0: inc result.treesWithRobots
  if archonsA.len != archonsB.len:
    raise newException(ConfigError,
      "bc17 map " & result.name & " has " & $archonsA.len & " A archons and " &
      $archonsB.len & " B archons; every official board has equal counts")
  result.archonsPerSide = archonsA.len
  var lo = -1.0
  var hi = -1.0
  for a in archonsA:
    for b in archonsB:
      let d = float(distanceTo(a, b))
      if lo < 0 or d < lo: lo = d
      if d > hi: hi = d
  result.separationMinTenths = int(round(max(lo, 0.0) * 10.0))
  result.separationMaxTenths = int(round(max(hi, 0.0) * 10.0))

var mapCache: seq[tuple[name: string, spec: MapSpec]]

proc loadMap*(name: string): MapSpec =
  ## Cached: a best-of-three episode loads the same board once per game and
  ## the parity trace loads it once per pair, and `LineOfFire` carries 1 228
  ## trees.
  for entry in mapCache:
    if entry.name == name: return entry.spec
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no converted bc17 map at " & path)
  result = parseMapSpec(readFile(path))
  mapCache.add((name: name, spec: result))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Identical in shape to the nine shipped years' draws, so the ten
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
  ## `(seed shr 8) and 1` picks which SEAT takes engine-side **Team.A** in
  ## game 1; sides alternate every game after that.
  ((seed shr 8) and 1) xor (gameIndex and 1)

# ---------------------------------------------------------------------------
#  Map cards -- the per-map facts a seat may legitimately know
# ---------------------------------------------------------------------------

func archonsOf*(spec: MapSpec, team: Team): seq[MapBody] =
  for b in spec.bodies:
    if b.isRobot and b.kind == rtArchon and b.team == team:
      result.add(b)

func totalContainedBullets*(spec: MapSpec): int =
  for b in spec.bodies:
    if not b.isRobot: result += b.containedBullets

func treeRadiusRange*(spec: MapSpec): (float, float) =
  var lo = -1.0
  var hi = 0.0
  for b in spec.bodies:
    if b.isRobot: continue
    let r = float(b.radius)
    if lo < 0 or r < lo: lo = r
    if r > hi: hi = r
  (max(lo, 0.0), hi)

func totalTreeRadius*(spec: MapSpec): float =
  for b in spec.bodies:
    if not b.isRobot: result += float(b.radius)

proc round1*(v: float): float = round(v * 10.0) / 10.0

proc mapCard*(spec: MapSpec, slot, sideAslot: int): JsonNode =
  ## Both seats' cards are numerically identical -- every 2017 board is
  ## symmetric by reflection or rotation -- and the only asymmetry is
  ## `you_are` and which archon roster is labelled "yours".
  ##
  ## **BOTH FACTIONS' ARCHON POSITIONS ARE GIVEN BECAUSE THEY ARE NOT
  ## SECRET**: `getInitialArchonLocations(team)` returns EITHER team's,
  ## sorted (`RobotControllerImpl.java:112-131`), so a chassis has them from
  ## its first turn -- and `kit.nim` reads them exactly that way in-match.
  let youAreA = slot == sideAslot
  let yours = spec.archonsOf(if youAreA: tA else: tB)
  let theirs = spec.archonsOf(if youAreA: tB else: tA)
  var yourArchons = newJArray()
  for a in yours:
    yourArchons.add(%*{"id": a.id, "x": round(float(a.loc.x) * 10000.0) /
                       10000.0, "y": round(float(a.loc.y) * 10000.0) /
                       10000.0})
  var enemyArchons = newJArray()
  for a in theirs:
    enemyArchons.add(%*{"id": a.id, "x": round(float(a.loc.x) * 10000.0) /
                        10000.0, "y": round(float(a.loc.y) * 10000.0) /
                        10000.0})
  let (rlo, rhi) = spec.treeRadiusRange()
  var first = ""
  var firstId = -1
  for b in spec.bodies:
    if b.isRobot and b.kind == rtArchon:
      firstId = b.id
      first = (if (b.team == tA) == youAreA: "you" else: "them")
      break
  %*{
    "map": spec.name,
    "map_seed": spec.mapSeed,
    "width": round1(float(spec.rect.width)),
    "height": round1(float(spec.rect.height)),
    "origin": [round(float(spec.rect.origin.x) * 10000.0) / 10000.0,
               round(float(spec.rect.origin.y) * 10000.0) / 10000.0],
    "you_are": (if youAreA: "A" else: "B"),
    "rounds": spec.rounds - 1,
    "rounds_are_one_based": true,
    "round_limit_note":
      "the engine's round cap is " & $spec.rounds & " but the game is " &
      "decided at the END of round " & $(spec.rounds - 1) & ", so " &
      $(spec.rounds - 1) & " rounds are played",
    "continuous_space_note":
      "coordinates are 32-bit floats, not grid cells. Every body is a " &
      "CIRCLE: an archon and a tank have body radius 2, everything else 1, " &
      "a bullet tree 1 and a neutral tree 0.5 to 10. Distance is measured " &
      "centre to centre and 'within distance 1 of a tree' means 1 beyond " &
      "its radius.",
    "your_archons": yourArchons,
    "enemy_archons": enemyArchons,
    "archon_separation_min": round1(spec.archonSeparationMin()),
    "archon_separation_max": round1(spec.archonSeparationMax()),
    "who_moves_first":
      "robot id " & $firstId & " (" & first & ") comes first in the map " &
      "file, and turn order is that file's id order",
    "neutral_trees": {
      "count": spec.neutralTrees,
      "total_radius": round1(spec.totalTreeRadius()),
      "radius_min": round1(rlo),
      "radius_max": round1(rhi),
      "with_bullets": spec.treesWithBullets,
      "total_contained_bullets": spec.totalContainedBullets(),
      "with_a_robot": spec.treesWithRobots,
      "note": "a neutral tree has 200 x radius health, blocks every body " &
              "except a SCOUT, and can be SHAKEN by any robot at distance " &
              "1 for the bullets inside it. Only a LUMBERJACK's chop() " &
              "releases a contained ROBOT, which then joins the chopping " &
              "team."
    }
  }
