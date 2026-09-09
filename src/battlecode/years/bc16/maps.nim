## The converted bc16 map pool, the loader and the per-episode draw.
##
## Maps are read from `data/maps/bc16/<name>.json`, produced by
## `tools/convert_maps_bc16.py` from the official `.xml` maps at the pinned
## `battlecode-server-2016` commit and COMMITTED (CI re-converts and
## byte-diffs). The wasm bundle gets the same directory through emscripten's
## `--preload-file data@data`, so the browser re-derives from exactly the
## bytes the server played — INCLUDING the pre-split per-den schedules, so it
## never has to reproduce a Java `HashMap` (D3).
##
## 22 of the 98 official maps are converted (V7). Every one of the 98 is
## PARSED by CI, and **every map in every pool is one of the 54 the oracle jar
## also carries as a resource**, so no parity pair and no smoke episode needs
## a `--map-dir`.
##
## `mixed` (10 maps) is the `bc16` variant's played pool and spans the axis
## the doctrines argue about: BOTH REACHABLE SYMMETRIES (nine rotational, one
## horizontal); 1 080 to 2 025 squares; ARCHONS PER SIDE 2, 3 AND 4; dens per
## side from 1 (`turtle`) to 3 (`collision`); parts from 1 640 on 110 squares
## (`caverns`) to 20 520 on 684 (`quadrants`), and `turtle`'s 1 800 on SIX
## squares of 300 apiece; rubble means from 71.9 (`industrial`) to 1 263.5
## (`boxy`), and `caverns` with 1 078 of 1 892 squares ALREADY IMPASSABLE;
## first waves from round 0 to round 300; schedules from 9 to 17 rounds and
## 204 to 378 zombies; and neutral rosters from 0 to 26 including two neutral
## ARCHONS. One map would rank the map, not the doctrine.
##
## `small` (6) is the pool the parity oracle and the docker smoke run on;
## `large` (6) is reserved for a later variant and supplies two of the nine
## parity pairs.

import std/[json, math, os, strutils]
import ../../sim_types
import world, economy

export world

const
  SmallPool* = ["checkers", "zigzag", "swamp", "river", "prisons", "frogger"]
  MixedPool* = ["closequarters", "lockdown", "industrial", "quadrants",
                "turtle", "boxy", "voluted", "collision", "caverns", "6147"]
  LargePool* = ["desert", "space", "scouting", "vortex", "wormy", "quarry"]

  ParityPairs* = ["checkers", "zigzag", "swamp", "river", "prisons",
                  "frogger", "turtle", "desert", "space"]
    ## The nine Tier A/A'/A" pairs, chosen to cover every branch of the two
    ## rules that have branches: both reachable symmetries and both
    ## chiralities (`frogger` VERTICAL, `turtle` HORIZONTAL, the rest
    ## ROTATIONAL), a two-symmetry map where the engine's first-wins order
    ## decides, the rubble boundary at exactly 200 (`checkers`) and the
    ## extreme at 10^6 (`zigzag`), minimum (`river`, 4.0) and maximum
    ## (`desert`, 75) archon separation, one archon a side (`swamp`), four a
    ## side (`frogger`, `space`), two dens (`prisons`, `turtle`) and ten
    ## (`desert`), neutral ARCHONS (`prisons`), and a map with ZERO impassable
    ## squares as the control (`frogger`).

proc poolNames*(pool: string): seq[string] =
  case pool.toLowerAscii()
  of "small": @SmallPool
  of "large": @LargePool
  of "mixed", "": @MixedPool
  else: @[]

proc parseSymmetry(text: string): Symmetry =
  case text
  of "vertical": symVertical
  of "horizontal": symHorizontal
  of "rotational": symRotational
  of "negative_diagonal": symNegativeDiagonal
  of "positive_diagonal": symPositiveDiagonal
  else: symNone

proc zombieCounts(node: JsonNode): array[4, int] =
  ## The converted file names the four zombie types; the array is indexed by
  ## `ZombieSpawnTypes` position, which is `RobotType` ordinal order.
  for i, kind in ZombieSpawnTypes:
    result[i] = node{$kind}.getInt(0)

proc parseMapSpec*(text: string): MapSpec =
  let doc = parseJson(text)
  result.name = doc["name"].getStr()
  result.width = doc["width"].getInt()
  result.height = doc["height"].getInt()
  result.randomSeed = doc["random_seed"].getInt()
  result.rounds = doc{"rounds"}.getInt(GameDefaultRounds)
  result.symmetry = parseSymmetry(doc["symmetry"].getStr())
  for s in doc{"symmetries_found"}:
    result.symmetriesFound.add(parseSymmetry(s.getStr()))
  if result.width < MapMinWidth or result.width > MapMaxWidth or
      result.height < MapMinHeight or result.height > MapMaxHeight:
    raise newException(ConfigError,
      "bc16 map " & result.name & " is " & $result.width & "x" &
        $result.height & ", outside 30..80")
  let expected = result.width * result.height
  result.rubble = newSeq[float64](expected)
  result.parts = newSeq[float64](expected)
  ## Both arrays are `[y][x]` rows, exactly as `GameMap` holds them, and are
  ## flattened to `y * width + x` — `SquareArray.Double`'s own indexing (D5),
  ## so the two checksums line up.
  let rubbleRows = doc["rubble"]
  let partsRows = doc["parts"]
  if rubbleRows.len != result.height or partsRows.len != result.height:
    raise newException(ConfigError,
      "bc16 map " & result.name & " has " & $rubbleRows.len &
        " rubble rows, expected " & $result.height)
  for y in 0 ..< result.height:
    if rubbleRows[y].len != result.width or partsRows[y].len != result.width:
      raise newException(ConfigError,
        "bc16 map " & result.name & " row " & $y & " is not " &
          $result.width & " wide")
    for x in 0 ..< result.width:
      result.rubble[y * result.width + x] = rubbleRows[y][x].getFloat()
      result.parts[y * result.width + x] = partsRows[y][x].getFloat()
  for b in doc["initial_robots"]:
    result.initialRobots.add((x: b[0].getInt(), y: b[1].getInt(),
                              kind: b[2].getInt(), team: b[3].getInt()))
  for row in doc["schedule"]:
    result.schedule.add((round: row["round"].getInt(),
                         counts: zombieCounts(row["counts"])))
  for den in doc["dens"]:
    var spec = DenSpec(x: den["x"].getInt(), y: den["y"].getInt(),
                       spawnDir: den["spawn_dir"].getInt(),
                       chirality: den["chirality"].getInt())
    var rounds: seq[int]
    for key, _ in den["schedule"]:
      rounds.add(parseInt(key))
    ## Ascending, because `ZombieSpawnSchedule.getRounds()` sorts and the den
    ## queue is filled in that order.
    for i in 1 ..< rounds.len:
      let v = rounds[i]
      var j = i - 1
      while j >= 0 and rounds[j] > v:
        rounds[j + 1] = rounds[j]
        dec j
      rounds[j + 1] = v
    for r in rounds:
      spec.schedule.add((round: r,
                         counts: zombieCounts(den["schedule"][$r])))
    result.dens.add(spec)

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc16" / (name & ".json")

proc loadMap*(name: string): MapSpec =
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no converted bc16 map at " & path)
  parseMapSpec(readFile(path))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Identical in shape to the seven shipped years' draws, so the
  ## eight years rank the same way for the same seed.
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

proc archonsOf*(spec: MapSpec, team: Team): seq[JsonNode] =
  ## The initial archons are PUBLIC: `getInitialArchonLocations` is free to
  ## every robot in the real game (`RobotControllerImpl.java:101-118`), so
  ## hiding them would hide nothing and cost the doctrine its opening.
  for b in spec.initialRobots:
    if b.kind != ord(rtArchon): continue
    if b.team != ord(team): continue
    result.add(%*{"x": b.x, "y": b.y,
                  "rubble": int(spec.rubble[b.x + b.y * spec.width])})

proc archonsPerSide*(spec: MapSpec): int = spec.archonsOf(teamA).len

proc densOf*(spec: MapSpec): seq[JsonNode] =
  for d in spec.dens:
    result.add(%*{"x": d.x, "y": d.y})

proc neutralRoster*(spec: MapSpec): JsonNode =
  result = newJObject()
  for b in spec.initialRobots:
    if b.team != ord(teamNeutral): continue
    let key = ($RobotType(b.kind)).toLowerAscii()
    result[key] = %(result{key}.getInt(0) + 1)

proc neutralTotal*(spec: MapSpec): int =
  for b in spec.initialRobots:
    if b.team == ord(teamNeutral): result += 1

proc startSeparation*(spec: MapSpec): float64 =
  ## The shortest Euclidean distance between an A archon and a B archon: the
  ## one number that says how far a soldier rush has to run. `river`'s 4.0 is
  ## the minimum in the pool and `desert`'s 75 the maximum.
  var best = high(float64)
  for a in spec.initialRobots:
    if a.kind != ord(rtArchon) or a.team != ord(teamA): continue
    for b in spec.initialRobots:
      if b.kind != ord(rtArchon) or b.team != ord(teamB): continue
      let d = float64((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
      best = min(best, sqrt(d))
  if best == high(float64): 0.0 else: best

proc rubbleMean*(spec: MapSpec): float64 =
  if spec.rubble.len == 0: return 0.0
  var total = 0.0
  for v in spec.rubble: total += v
  total / float64(spec.rubble.len)

proc rubbleMax*(spec: MapSpec): float64 =
  for v in spec.rubble:
    if v > result: result = v

proc impassableSquares*(spec: MapSpec): int =
  for v in spec.rubble:
    if v >= RubbleObstructionThresh: result += 1

proc squaresOver50Pct*(spec: MapSpec): float64 =
  var n = 0
  for v in spec.rubble:
    if v >= RubbleSlowThresh: n += 1
  if spec.rubble.len == 0: 0.0
  else: round(float64(n) / float64(spec.rubble.len) * 1000.0) / 10.0

proc partsSquares*(spec: MapSpec): int =
  for v in spec.parts:
    if v > 0.0: result += 1

proc partsTotal*(spec: MapSpec): int =
  var total = 0.0
  for v in spec.parts: total += v
  int(total)

proc partsMaxSquare*(spec: MapSpec): int =
  var best = 0.0
  for v in spec.parts:
    if v > best: best = v
  int(best)

proc nearestParts*(spec: MapSpec, from0: JsonNode): JsonNode =
  ## The nearest parts deposit to an archon, by Chebyshev steps — the walking
  ## distance an archon actually pays, because movement is eight-directional.
  if from0.isNil: return newJNull()
  let fx = from0["x"].getInt()
  let fy = from0["y"].getInt()
  var best = high(int)
  var bx, by = 0
  var amount = 0.0
  for i in 0 ..< spec.parts.len:
    if spec.parts[i] <= 0.0: continue
    let x = i mod spec.width
    let y = i div spec.width
    let steps = max(abs(x - fx), abs(y - fy))
    if steps < best:
      best = steps
      bx = x
      by = y
      amount = spec.parts[i]
  if best == high(int): return newJNull()
  %*{"x": bx, "y": by, "amount": int(amount), "steps": best}

proc nearestNeutral*(spec: MapSpec, from0: JsonNode): JsonNode =
  if from0.isNil: return newJNull()
  let fx = from0["x"].getInt()
  let fy = from0["y"].getInt()
  var best = high(int)
  var found = false
  var bx, by = 0
  var kind = rtSoldier
  for b in spec.initialRobots:
    if b.team != ord(teamNeutral): continue
    let steps = max(abs(b.x - fx), abs(b.y - fy))
    if steps < best:
      best = steps
      bx = b.x
      by = b.y
      kind = RobotType(b.kind)
      found = true
  if not found: return newJNull()
  %*{"x": bx, "y": by, "type": ($kind).toLowerAscii(), "steps": best}

proc scheduleJson*(spec: MapSpec): JsonNode =
  ## The WHOLE-MAP schedule, which `getZombieSpawnSchedule()` exposes free to
  ## every robot. THE PER-DEN SPLIT IS NOT EXPOSED BY ANY 2016 API and is
  ## therefore not in the card.
  result = newJArray()
  for row in spec.schedule:
    var entry = %*{"round": row.round}
    for i, kind in ZombieSpawnTypes:
      if row.counts[i] > 0:
        entry[($kind).toLowerAscii()] = %row.counts[i]
    result.add(entry)

proc zombiesPerDen*(spec: MapSpec): int =
  if spec.dens.len == 0: return 0
  for row in spec.dens[0].schedule:
    for c in row.counts: result += c

proc mapCard*(spec: MapSpec, slot, sideAslot: int): JsonNode =
  ## Every map is symmetric, so both seats' cards are numerically identical;
  ## `you_are` and which mirrored coordinate set is labelled "yours" are the
  ## only asymmetries.
  let side = if sideAslot == slot: teamA else: teamB
  var mine = newJArray()
  let mineSeq = spec.archonsOf(side)
  for a in mineSeq: mine.add(a)
  var theirs = newJArray()
  for a in spec.archonsOf(side.other()):
    theirs.add(%*{"x": a["x"].getInt(), "y": a["y"].getInt()})
  var denLocs = newJArray()
  for d in spec.densOf(): denLocs.add(d)
  let firstMine = if mine.len > 0: mine[0] else: nil
  %*{
    "map": spec.name,
    "width": spec.width,
    "height": spec.height,
    "symmetry": $spec.symmetry,
    "you_are": (if sideAslot == slot: "A" else: "B"),
    "rounds_are_zero_based": true,
    "your_archons": mine,
    "enemy_archons": theirs,
    "start_separation": round(spec.startSeparation() * 10.0) / 10.0,
    "terrain": {
      "rubble_mean": round(spec.rubbleMean() * 10.0) / 10.0,
      "rubble_max": int(spec.rubbleMax()),
      "impassable_squares": spec.impassableSquares(),
      "total_squares": spec.width * spec.height,
      "squares_over_50_rubble_pct": spec.squaresOver50Pct(),
      "note": "a square is passable only if its rubble is UNDER 100, " &
              "except for SCOUTs, FASTZOMBIEs and BIGZOMBIEs which ignore " &
              "rubble entirely; rubble of 50 or more DOUBLES every movement " &
              "and cooldown charge"
    },
    "parts": {
      "squares": spec.partsSquares(),
      "total": spec.partsTotal(),
      "max_square": spec.partsMaxSquare(),
      "nearest_to_you": spec.nearestParts(firstMine),
      "note": "only an ARCHON collects parts, and it takes the WHOLE square " &
              "by standing on it or moving onto it"
    },
    "dens": {
      "count": spec.dens.len,
      "per_side": spec.dens.len div 2,
      "health_each": int(RobotSpecs[rtZombieden].maxHealth),
      "bounty_each": int(DenPartReward),
      "locations": denLocs,
      "zombies_queued_each_over_the_game": spec.zombiesPerDen()
    },
    "neutrals": {
      "total": spec.neutralTotal(),
      "by_type": spec.neutralRoster(),
      "nearest_to_you": spec.nearestNeutral(firstMine),
      "note": "an ARCHON activates a NEUTRAL within radius-squared 2 for " &
              "zero parts and 2 core delay; the neutral is replaced by an " &
              "identical robot on your team, immediately active. A neutral " &
              "ARCHON is a whole extra tiebreak rung."
    },
    "zombie_schedule": spec.scheduleJson(),
    "schedule_note": "these are WHOLE-MAP counts, divided as evenly as " &
                     "possible among the " & $spec.dens.len & " dens; a den " &
                     "spawns at most 8 zombies per attempt and 16 per " &
                     "round, and if it still has a queue it damages every " &
                     "adjacent non-zombie for 10 first",
    "tiebreak_round": spec.rounds - 1
  }
