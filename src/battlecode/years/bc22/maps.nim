## The converted bc22 map pool, the loader and the per-episode draw.
##
## Maps are read from `data/maps/bc22/<name>.json`, produced by
## `tools/convert_maps_bc22.py` from the official `.map22` flatbuffers at the
## pinned battlecode22 commit and COMMITTED (CI re-converts and byte-diffs).
## The wasm bundle gets the same directory through emscripten's
## `--preload-file data@data`, so the browser re-derives from exactly the bytes
## the server played.
##
## 22 of the 75 official maps are converted. Everything above 1 600 squares is
## out of the PLAYED pool for wall-clock reasons (four are converted anyway,
## under `large`); `maptestsmall` (rubble uniformly 1 and 1 016 lead squares
## totalling 49 788 — an engine test fixture, not a game) and `squer` (204 lead
## on 625 squares and no anomalies — a starvation map) are converted for neither
## pool; the remaining 53 are simply not converted in v1 and the converter
## handles any `.map22` (docs/RULES-BC22.md §Divergences item 11).
##
## `mixed` is the `bc22` variant's pool and is chosen to span the axis the
## doctrines argue about: ALL THREE SYMMETRIES; 900 to 1 575 squares; ARCHONS
## PER SIDE 1, 2, 3 AND 4; lead totals from **150** (`pyramid_raiders`, thirty
## squares of five apiece, so `mine_floor` decides whether the map survives at
## all) to **2 000** (`intersection`, forty squares averaging fifty, so miners
## saturate and the game is a soldier war); rubble means from 9.2 (`progress`)
## to **58.1** (`pyramid_raiders`, where a soldier pays 16 x 6.8 per step and
## the game is almost static); and anomaly schedules from all-ABYSS (`monument`,
## ten of them) through charge-heavy (`standoff`, `fisherman`, `defenseless`) to
## vortex-heavy (`defenseless`, five, the first at round FIVE).
##
## `small` is the pool the parity oracle and the docker smoke run on; `large` is
## reserved for a later variant and supplies two of the eight parity pairs
## (`turtle` is the only VERTICAL map among them, and `vortex` is 60x60 square
## rotational with TWELVE vortexes and nothing else).

import std/[json, math, os, strutils]
import ../../sim_types
import world, economy

export world

const
  SmallPool* = ["chalice", "maze", "nottestsmall", "snowflake_redux",
                "rugged", "charge"]
  MixedPool* = ["equals", "monument", "island_hopping", "progress",
                "collaboration", "standoff", "intersection",
                "pyramid_raiders", "defenseless", "fisherman"]
  LargePool* = ["turtle", "flowers", "despair", "chessboard", "colosseum",
                "vortex"]

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
  let rubbleNode = doc["rubble"]
  if rubbleNode.len != expected:
    raise newException(ConfigError,
      "bc22 map " & result.name & " has a " & $rubbleNode.len &
      "-square rubble array, expected " & $expected)
  result.rubble = newSeq[int](expected)
  for i in 0 ..< expected:
    let v = rubbleNode[i].getInt()
    if v < MinRubble or v > MaxRubble:
      raise newException(ConfigError,
        "bc22 map " & result.name & " has rubble " & $v & " out of 0..100")
    result.rubble[i] = v
  result.lead = newSeq[int](expected)
  for c in doc["lead"]:
    result.lead[c[0].getInt() + c[1].getInt() * result.width] = c[2].getInt()
  for a in doc["anomalies"]:
    let kind = case a[1].getInt()
      of 0: anAbyss
      of 1: anCharge
      of 2: anFury
      else: anVortex
    result.anomalies.add((round: a[0].getInt(), kind: kind))
  for b in doc["initial_bodies"]:
    result.initialBodies.add((id: b[0].getInt(), x: b[1].getInt(),
                              y: b[2].getInt(), team: b[3].getInt(),
                              kind: b[4].getInt()))

proc mapPath*(name: string): string =
  dataRoot() / "maps" / "bc22" / (name & ".json")

proc loadMap*(name: string): MapSpec =
  let path = mapPath(name)
  if not fileExists(path):
    raise newException(ConfigError, "no converted bc22 map at " & path)
  parseMapSpec(readFile(path))

proc drawMaps*(pool: string, seed, count: int): seq[string] =
  ## `count` DISTINCT maps from the pool, chosen by successive seed-derived
  ## indices. Identical in shape to the six shipped years' draws, so the seven
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

proc archonsOf*(spec: MapSpec, team: Team): seq[JsonNode] =
  ## The archons are PUBLIC: every map is symmetric and the engine's own map
  ## file puts them there, so hiding them would hide nothing and cost the
  ## doctrine its opening.
  for b in spec.initialBodies:
    let bodyTeam = if b.team == 1: teamA else: teamB
    if bodyTeam != team: continue
    result.add(%*{"x": b.x, "y": b.y,
                  "rubble": spec.rubble[b.x + b.y * spec.width]})

proc archonsPerSide*(spec: MapSpec): int = spec.archonsOf(teamA).len

proc startSeparation*(spec: MapSpec): float64 =
  ## The shortest Euclidean distance between an A archon and a B one: the one
  ## number that says how far a soldier rush has to run.
  var best = high(float64)
  for a in spec.initialBodies:
    for b in spec.initialBodies:
      if a.team == b.team: continue
      let d = float64((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
      best = min(best, sqrt(d))
  if best == high(float64): 0.0 else: best

proc leadSquaresOf*(spec: MapSpec): int =
  for v in spec.lead:
    if v > 0: result += 1

proc leadTotalOf*(spec: MapSpec): int =
  for v in spec.lead: result += v

proc leadMaxSquare*(spec: MapSpec): int =
  for v in spec.lead:
    if v > result: result = v

proc rubbleMean*(spec: MapSpec): float64 =
  var total = 0
  for v in spec.rubble: total += v
  if spec.rubble.len == 0: 0.0
  else: float64(total) / float64(spec.rubble.len)

proc rubbleMedian*(spec: MapSpec): int =
  var counts: array[101, int]
  for v in spec.rubble: counts[v] += 1
  let half = spec.rubble.len div 2
  var seen = 0
  for v in 0 .. 100:
    seen += counts[v]
    if seen > half: return v
  0

proc rubbleMax*(spec: MapSpec): int =
  for v in spec.rubble:
    if v > result: result = v

proc squaresOver50Pct*(spec: MapSpec): float64 =
  var n = 0
  for v in spec.rubble:
    if v > 50: n += 1
  if spec.rubble.len == 0: 0.0
  else: round(float64(n) / float64(spec.rubble.len) * 1000.0) / 10.0

proc nearestLead*(spec: MapSpec, from0: JsonNode): JsonNode =
  ## The nearest lead deposit to an archon, by Chebyshev steps — the walking
  ## distance a miner actually pays, because movement is eight-directional.
  if from0.isNil: return newJNull()
  let fx = from0["x"].getInt()
  let fy = from0["y"].getInt()
  var best = high(int)
  var bx, by, amount = 0
  for i in 0 ..< spec.lead.len:
    if spec.lead[i] <= 0: continue
    let x = i mod spec.width
    let y = i div spec.width
    let steps = max(abs(x - fx), abs(y - fy))
    if steps < best:
      best = steps
      bx = x
      by = y
      amount = spec.lead[i]
  if best == high(int): return newJNull()
  %*{"x": bx, "y": by, "amount": amount, "steps": best}

proc leadWithinVision*(spec: MapSpec, archons: seq[JsonNode]): int =
  ## Lead squares inside r2 <= 34 of any of this faction's archons — the deposits
  ## a miner reaches on turn one.
  var seen = newSeq[bool](spec.lead.len)
  for a in archons:
    let ax = a["x"].getInt()
    let ay = a["y"].getInt()
    for i in 0 ..< spec.lead.len:
      if spec.lead[i] <= 0 or seen[i]: continue
      let dx = i mod spec.width - ax
      let dy = i div spec.width - ay
      if dx * dx + dy * dy <= 34:
        seen[i] = true
        result += 1

proc anomalyScheduleJson*(spec: MapSpec): JsonNode =
  result = newJArray()
  for a in spec.anomalies:
    result.add(%*{"round": a.round, "type": ($a.kind).toLowerAscii()})

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
  let firstMine = if mine.len > 0: mine[0] else: nil
  %*{
    "map": spec.name,
    "width": spec.width,
    "height": spec.height,
    "symmetry": ($spec.symmetry).replace("sym", "").toLowerAscii(),
    "you_are": (if sideAslot == slot: "A" else: "B"),
    "your_archons": mine,
    "enemy_archons": theirs,
    "start_separation": round(spec.startSeparation() * 10.0) / 10.0,
    "terrain": {
      "rubble_mean": round(spec.rubbleMean() * 10.0) / 10.0,
      "rubble_median": spec.rubbleMedian(),
      "rubble_max": spec.rubbleMax(),
      "squares_over_50_rubble_pct": spec.squaresOver50Pct()
    },
    "lead": {
      "squares": spec.leadSquaresOf(),
      "total": spec.leadTotalOf(),
      "max_square": spec.leadMaxSquare(),
      "nearest_to_you": spec.nearestLead(firstMine),
      "within_vision_of_your_archons": spec.leadWithinVision(mineSeq)
    },
    "gold": {
      "squares": 0, "total": 0,
      "note": "gold is never on the map at round 0: it comes only from a " &
              "laboratory or from the 20% reclaim a dying robot drops"
    },
    "anomaly_schedule": spec.anomalyScheduleJson(),
    "singularity_round": spec.rounds
  }
