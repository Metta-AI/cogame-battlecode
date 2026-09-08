## The 22 committed maps, against the design note's MEASURED table.
##
## §Tests item 12. Every number below was read off the official `.map22` with
## `tools/convert_maps_bc22.py`'s own vtable walk, so this shard compares the
## committed JSON to the engine's own bytes rather than to a transcription.

import std/[math, os, strutils, tables]
import harness
import bc22_fixture

type Row = tuple[name: string, w, h, seed: int, sym: Symmetry, archons: int,
                 rubbleMean10, rubbleMax, rubbleMin: int,
                 leadSquares, leadTotal, leadMax: int,
                 ab, ch, fu, vo, first: int]

const Pinned: array[22, Row] = [
  ("chalice", 20, 20, 350, symVertical, 1, 86, 50, 0, 20, 220, 20, 3, 2, 4, 0, 200),
  ("maze", 20, 20, 474, symHorizontal, 3, 347, 60, 0, 12, 240, 20, 2, 3, 3, 1, 201),
  ("nottestsmall", 20, 20, 396, symRotation, 1, 364, 98, 0, 24, 960, 64, 0, 6, 0, 5, 180),
  ("snowflake_redux", 20, 20, 319, symRotation, 2, 146, 50, 0, 32, 760, 50, 4, 2, 3, 0, 200),
  ("rugged", 21, 21, 850, symRotation, 1, 271, 100, 2, 26, 550, 40, 0, 0, 0, 0, -1),
  ("charge", 25, 30, 51, symRotation, 1, 139, 60, 0, 16, 460, 60, 2, 6, 1, 1, 200),
  ("equals", 30, 30, 681, symHorizontal, 2, 123, 64, 0, 28, 804, 45, 5, 0, 5, 0, 201),
  ("monument", 30, 30, 970, symVertical, 1, 204, 100, 0, 10, 500, 50, 10, 0, 0, 0, 200),
  ("island_hopping", 30, 30, 273, symRotation, 1, 219, 30, 0, 40, 880, 40, 2, 2, 4, 1, 200),
  ("progress", 30, 30, 999, symHorizontal, 2, 92, 50, 0, 32, 1600, 50, 1, 2, 3, 2, 200),
  ("collaboration", 38, 25, 707, symRotation, 4, 183, 100, 0, 34, 412, 190, 4, 3, 3, 0, 189),
  ("standoff", 40, 25, 884, symRotation, 3, 100, 80, 0, 40, 220, 10, 1, 5, 1, 2, 200),
  ("intersection", 49, 25, 491, symHorizontal, 2, 212, 100, 0, 40, 2000, 50, 5, 4, 0, 0, 200),
  ("pyramid_raiders", 42, 34, 363, symVertical, 1, 581, 100, 0, 30, 150, 5, 2, 4, 3, 0, 200),
  ("defenseless", 40, 31, 250, symHorizontal, 2, 163, 80, 0, 41, 205, 5, 0, 6, 2, 5, 5),
  ("fisherman", 45, 35, 793, symHorizontal, 3, 139, 90, 0, 36, 180, 5, 0, 6, 3, 0, 200),
  ("turtle", 40, 40, 196, symVertical, 2, 120, 40, 0, 20, 360, 50, 4, 2, 3, 1, 200),
  ("flowers", 40, 40, 830, symRotation, 2, 55, 40, 0, 38, 810, 30, 2, 2, 3, 2, 169),
  ("despair", 45, 45, 315, symRotation, 2, 187, 100, 0, 56, 1284, 42, 3, 3, 3, 1, 225),
  ("chessboard", 47, 47, 445, symRotation, 2, 238, 90, 0, 60, 1360, 50, 3, 2, 5, 0, 200),
  ("colosseum", 60, 60, 354, symHorizontal, 3, 250, 99, 0, 124, 3160, 40, 3, 4, 2, 0, 201),
  ("vortex", 60, 60, 26, symRotation, 4, 242, 100, 0, 140, 3500, 25, 0, 0, 0, 12, 51)]

block:
  checkEq("the small pool is six", SmallPool.len, 6)
  checkEq("the mixed pool — the bc22 variant's — is ten", MixedPool.len, 10)
  checkEq("the large pool is six", LargePool.len, 6)
  var all: seq[string]
  for n in SmallPool: all.add(n)
  for n in MixedPool: all.add(n)
  for n in LargePool: all.add(n)
  checkEq("twenty-two maps are committed", all.len, 22)
  var seen = initTable[string, bool]()
  for n in all:
    check("no map is in two pools: " & n, not seen.hasKey(n))
    seen[n] = true
  for row in Pinned:
    check("the pinned map " & row.name & " is in a pool", seen.hasKey(row.name))

block:
  for row in Pinned:
    let spec = loadMap(row.name)
    checkEq(row.name & " width", spec.width, row.w)
    checkEq(row.name & " height", spec.height, row.h)
    checkEq(row.name & " seed", spec.randomSeed, row.seed)
    checkEq(row.name & " symmetry", spec.symmetry, row.sym)
    checkEq(row.name & " rounds is the engine's hard-coded 2000", spec.rounds,
      2000)
    checkEq(row.name & " archons a side", spec.archonsPerSide(), row.archons)
    checkEq(row.name & " archons the other side",
      spec.archonsOf(teamB).len, row.archons)
    checkEq(row.name & " rubble mean (tenths)",
      int(round(spec.rubbleMean() * 10.0)), row.rubbleMean10)
    checkEq(row.name & " rubble max", spec.rubbleMax(), row.rubbleMax)
    checkEq(row.name & " lead squares", spec.leadSquaresOf(), row.leadSquares)
    checkEq(row.name & " lead total", spec.leadTotalOf(), row.leadTotal)
    checkEq(row.name & " biggest lead square", spec.leadMaxSquare(),
      row.leadMax)
    var minRubble = 100
    for v in spec.rubble: minRubble = min(minRubble, v)
    checkEq(row.name & " rubble min", minRubble, row.rubbleMin)
    var counts = [0, 0, 0, 0]
    for a in spec.anomalies: counts[ord(a.kind)] += 1
    checkEq(row.name & " abyss count", counts[0], row.ab)
    checkEq(row.name & " charge count", counts[1], row.ch)
    checkEq(row.name & " fury count", counts[2], row.fu)
    checkEq(row.name & " vortex count", counts[3], row.vo)
    checkEq(row.name & " first anomaly round",
      (if spec.anomalies.len == 0: -1 else: spec.anomalies[0].round), row.first)

block:
  ## The rule-set bounds, checked on every committed map.
  for row in Pinned:
    let spec = loadMap(row.name)
    check(row.name & " is within 20..60 in both dimensions",
      spec.width >= MapMinWidth and spec.width <= MapMaxWidth and
      spec.height >= MapMinHeight and spec.height <= MapMaxHeight)
    check(row.name & " has 1..4 archons a side",
      spec.archonsPerSide() >= MinStartingArchons and
      spec.archonsPerSide() <= MaxStartingArchons)
    var everyBodyIsAnArchon = true
    for b in spec.initialBodies:
      if b.kind != 4: everyBodyIsAnArchon = false
    check(row.name & ": EVERY initial body is an ARCHON", everyBodyIsAnArchon)
    var rubbleOk = true
    for v in spec.rubble:
      if v < MinRubble or v > MaxRubble: rubbleOk = false
    check(row.name & " rubble is inside 0..100", rubbleOk)
    var ascending = true
    for i in 1 ..< spec.anomalies.len:
      if spec.anomalies[i].round < spec.anomalies[i - 1].round:
        ascending = false
    check(row.name & "'s anomaly schedule is ascending in round", ascending)
    var idsAscending = true
    for i in 1 ..< spec.initialBodies.len:
      if spec.initialBodies[i].id < spec.initialBodies[i - 1].id:
        idsAscending = false
    check(row.name & "'s bodies are emitted id-ascending", idsAscending)

block:
  ## A bc22 map name that another year also uses must resolve to the bc22 file.
  for name in ["island_hopping", "maze", "flowers", "turtle"]:
    let path = mapPath(name)
    check("the bc22 " & name & " lives under maps/bc22", "bc22" in path)
    check("and it exists", fileExists(path))
    let spec = loadMap(name)
    checkEq("and reports its own name", spec.name, name)

block:
  ## The draw: distinct maps, and the alternating side assignment.
  for pool in ["small", "mixed", "large"]:
    let drawn = drawMaps(pool, 871345, 3)
    checkEq(pool & " draws three", drawn.len, 3)
    check(pool & "'s draw is distinct",
      drawn[0] != drawn[1] and drawn[1] != drawn[2] and drawn[0] != drawn[2])
    for name in drawn:
      check(pool & " draws from its own pool", name in poolNames(pool))
  checkEq("the draw is deterministic", drawMaps("mixed", 42, 3),
    drawMaps("mixed", 42, 3))
  for seed in [0, 1, 256, 871345]:
    checkEq("sides alternate every game",
      sideAslotFor(seed, 0), 1 - sideAslotFor(seed, 1))
    checkEq("and come back", sideAslotFor(seed, 0), sideAslotFor(seed, 2))

block:
  ## THE SMOKE'S SEED IS PINNED so the map cannot drift silently. `ci.yml`
  ## passes `"seed": 2029` on the `small` pool with `gamesPerMatch: 1`.
  let drawn = drawMaps("small", 2029, 1)
  checkEq("the docker-smoke seed draws snowflake_redux", drawn,
    @["snowflake_redux"])

block:
  ## The first VORTEX permutation of every committed map with a vortex is a
  ## deterministic function of `Random(mapSeed)` — the ONE place the 2022 round
  ## loop reads an RNG. The port must reproduce the draw, not replace it.
  for row in Pinned:
    if row.vo == 0: continue
    let spec = loadMap(row.name)
    var a = newWorld(spec, 2000)
    var b = newWorld(spec, 2000)
    var reportA = AnomalyReport()
    var reportB = AnomalyReport()
    let idxA = a.causeVortexGlobal(reportA)
    let idxB = b.causeVortexGlobal(reportB)
    checkEq(row.name & "'s first vortex permutation is deterministic",
      idxA, idxB)
    case spec.symmetry
    of symVertical:
      checkEq(row.name & " is VERTICAL, so changeIdx is 2", idxA, 2)
    of symHorizontal:
      checkEq(row.name & " is HORIZONTAL, so changeIdx is 1", idxA, 1)
    of symRotation:
      if spec.width == spec.height:
        check(row.name & " is SQUARE rotational, so the draw is 0, 1 or 2",
          idxA in 0 .. 2)
      else:
        check(row.name & " is NON-SQUARE rotational, so the draw is 1 or 2",
          idxA in 1 .. 2)
    var total = 0
    for v in a.rubble: total += v
    var want = 0
    for v in spec.rubble: want += v
    checkEq(row.name & "'s rubble is PERMUTED, never created", total, want)

finish("test_bc22_maps")
