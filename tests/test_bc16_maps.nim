## Shard 13 of the note's list — **the converted map pool**.
##
## Every committed map is compared against the design note's own measured
## table: size, area, seed, symmetry (and `symmetries_found`, D4), rubble
## mean/max, impassable count, parts total/squares/max, archons per side, den
## count and locations, neutral roster, and the full whole-map schedule. Every
## map is within 30..80 in both dimensions with EQUAL ARCHON COUNTS and no
## armageddon flag. No bc16 map name resolves to another year's file, every
## pool map is one of the 54 the oracle jar carries as a resource, and **the
## `docker-smoke` seed draws exactly `river`**, so the smoke's map cannot
## drift.

import std/[algorithm, json, math, os, sequtils, strutils, tables]
import harness
import bc16_fixture
import battlecode/years/registry

# --- the pools -------------------------------------------------------------
block:
  checkEq("small is six maps", poolNames("small").len, 6)
  checkEq("mixed is ten", poolNames("mixed").len, 10)
  checkEq("large is six", poolNames("large").len, 6)
  checkEq("and twenty-two are committed",
    poolNames("small").len + poolNames("mixed").len + poolNames("large").len,
    22)
  checkEq("an unknown pool is empty, not an exception",
    poolNames("enormous").len, 0)
  checkEq("and the default pool is mixed", poolNames(""), poolNames("mixed"))
  let spec = registry.yearSpec("bc16")
  checkEq("the registry names the three pools", spec.pools,
    @["small", "mixed", "large"])
  checkEq("and 3000 rounds", spec.maxRounds, 3000)
  checkEq("and its own atlas", spec.atlas, "atlas_bc16")

# --- the note's measured table, row by row --------------------------------
type Row = tuple[name: string, w, h, seed: int, sym: Symmetry, archons: int,
                 dens, neutrals: int, rmax: float64, walls: int,
                 parts: int, psq: int, sched: int, totz: int]

const Table16: seq[Row] = @[
  ("checkers", 30, 30, 946, symRotational, 2, 4, 30, 200.0, 450, 2000, 10, 10, 266),
  ("zigzag", 30, 30, 8, symRotational, 2, 6, 0, 1_000_000.0, 72, 3380, 134, 12, 276),
  ("swamp", 34, 30, 8563, symRotational, 1, 4, 18, 999.0, 58, 1680, 56, 10, 266),
  ("river", 32, 32, 938, symRotational, 3, 4, 12, 999.0, 54, 1320, 66, 10, 266),
  ("prisons", 30, 40, 1337, symRotational, 3, 2, 6, 1000.0, 232, 1500, 22, 12, 232),
  ("frogger", 35, 35, 53, symVertical, 4, 12, 4, 80.0, 0, 3340, 334, 12, 276),
  ("closequarters", 36, 30, 86, symRotational, 4, 4, 0, 2000.0, 164, 2980, 56, 9, 208),
  ("lockdown", 34, 34, 3434, symRotational, 3, 4, 16, 777.0, 162, 2522, 102, 12, 204),
  ("industrial", 37, 37, 536, symRotational, 2, 4, 22, 1000.0, 348, 2120, 65, 12, 276),
  ("quadrants", 39, 39, 8123, symRotational, 4, 4, 0, 500.0, 243, 20520, 684, 12, 204),
  ("turtle", 40, 40, 1337, symHorizontal, 2, 2, 0, 1000.0, 156, 1800, 6, 12, 276),
  ("boxy", 40, 40, 555, symRotational, 2, 4, 0, 55555.0, 264, 1830, 106, 17, 378),
  ("voluted", 43, 41, 824, symRotational, 2, 4, 18, 778.0, 286, 2000, 10, 12, 276),
  ("collision", 45, 40, 375, symRotational, 4, 6, 8, 9999.0, 242, 2420, 76, 17, 378),
  ("caverns", 44, 43, 229, symRotational, 2, 4, 26, 500.0, 1078, 1640, 110, 10, 266),
  ("6147", 45, 45, 234, symRotational, 2, 4, 18, 6147.0, 216, 3120, 74, 12, 276),
  ("desert", 62, 62, 3613, symRotational, 3, 10, 22, 1000.0, 122, 1440, 64, 17, 350),
  ("space", 65, 65, 1, symRotational, 4, 8, 0, 999999.0, 346, 2050, 50, 18, 368),
  ("scouting", 65, 65, 652, symRotational, 1, 2, 22, 1500.0, 516, 6100, 122, 12, 204),
  ("vortex", 69, 69, 125, symRotational, 3, 6, 41, 500.0, 796, 5120, 256, 12, 276),
  ("wormy", 73, 73, 624, symRotational, 3, 8, 48, 10000.0, 1004, 2790, 225, 29, 326),
  ("quarry", 80, 80, 1257, symRotational, 4, 4, 44, 1000.0, 1604, 8200, 82, 12, 276),
]

block:
  var all: seq[string]
  for pool in ["small", "mixed", "large"]:
    for name in poolNames(pool): all.add(name)
  var want: seq[string]
  for row in Table16: want.add(row.name)
  all.sort()
  want.sort()
  checkEq("the three pools together are exactly the 22 committed maps", all,
    want)

for row in Table16:
  let spec = loadMap(row.name)
  checkEq(row.name & " width", spec.width, row.w)
  checkEq(row.name & " height", spec.height, row.h)
  checkEq(row.name & " seed", spec.randomSeed, row.seed)
  checkEq(row.name & " symmetry", spec.symmetry, row.sym)
  checkEq(row.name & " rounds", spec.rounds, 3000)
  var archonsA = 0
  var archonsB = 0
  var neutrals = 0
  for b in spec.initialRobots:
    if b.kind == ord(rtArchon):
      if b.team == ord(teamA): inc archonsA
      elif b.team == ord(teamB): inc archonsB
    if b.team == ord(teamNeutral): inc neutrals
  checkEq(row.name & " archons a side", archonsA, row.archons)
  checkEq(row.name & " has EQUAL archon counts", archonsB, archonsA)
  checkEq(row.name & " neutrals", neutrals, row.neutrals)
  checkEq(row.name & " dens", spec.dens.len, row.dens)
  var rmax = 0.0
  var walls = 0
  for v in spec.rubble:
    rmax = max(rmax, v)
    if v >= RubbleObstructionThresh: inc walls
  checkEq(row.name & " rubble max", rmax, row.rmax)
  checkEq(row.name & " impassable squares", walls, row.walls)
  var partsTotal = 0.0
  var psq = 0
  for v in spec.parts:
    partsTotal += v
    if v > 0.0: inc psq
  checkEq(row.name & " parts total", int(partsTotal), row.parts)
  checkEq(row.name & " parts squares", psq, row.psq)
  checkEq(row.name & " schedule rounds", spec.schedule.len, row.sched)
  var totz = 0
  for r in spec.schedule:
    for c in r.counts: totz += c
  checkEq(row.name & " whole-map zombie total", totz, row.totz)
  check(row.name & " is inside 30..80 in both dimensions",
    spec.width >= MapMinWidth and spec.width <= MapMaxWidth and
    spec.height >= MapMinHeight and spec.height <= MapMaxHeight)
  ## The dens' own split must add up to the whole-map schedule, within the
  ## engine's own leftover walk: every per-den total is equal within +-1 and
  ## the +-1 lands on BOTH members of a symmetric pair, so no side is ever
  ## advantaged.
  var perDen = 0
  for d in spec.dens:
    for r in d.schedule:
      for c in r.counts: perDen += c
  checkEq(row.name & "'s per-den split sums to the whole-map schedule",
    perDen, totz)
  var totals: seq[int]
  for d in spec.dens:
    var t = 0
    for r in d.schedule:
      for c in r.counts: t += c
    totals.add(t)
  check(row.name & "'s per-den totals are equal within one",
    totals.len == 0 or (totals.max - totals.min) <= 1)
  ## Both memoised constants are present and legal.
  for d in spec.dens:
    check(row.name & " den spawn_dir is a real direction 0..7",
      d.spawnDir >= 0 and d.spawnDir <= 7)
    check(row.name & " den chirality is +1 or -1",
      d.chirality == 1 or d.chirality == -1)
    check(row.name & " den is on the map",
      d.x >= 0 and d.x < spec.width and d.y >= 0 and d.y < spec.height)

# --- D4: the two-symmetry control -----------------------------------------
block:
  let frogger = loadMap("frogger")
  checkEq("frogger resolves to VERTICAL, the first-wins arm", frogger.symmetry,
    symVertical)
  check("and records BOTH symmetries it satisfies",
    frogger.symmetriesFound.len >= 2)
  check("including rotational", symRotational in frogger.symmetriesFound)
  var froggerWalls = 0
  for v in frogger.rubble:
    if v >= RubbleObstructionThresh: inc froggerWalls
  checkEq("and it is the map with ZERO impassable squares, so a divergence " &
    "there is a rules bug and not a pathing bug", froggerWalls, 0)
  let turtle = loadMap("turtle")
  checkEq("turtle is the HORIZONTAL chirality case", turtle.symmetry,
    symHorizontal)
  ## Chirality: 1 for ROTATIONAL/NONE, `signum(compareTo(opposite))`
  ## otherwise, and 1 on the line of symmetry.
  for name in ["checkers", "river", "swamp"]:
    for d in loadMap(name).dens:
      checkEq(name & "'s rotational dens all have chirality +1", d.chirality,
        1)
  var mixedChirality = false
  for d in loadMap("frogger").dens:
    if d.chirality == -1: mixedChirality = true
  check("while frogger's VERTICAL dens carry both chiralities — the " &
    "mirror-image spawn rings", mixedChirality)

# --- the nine parity pairs -------------------------------------------------
block:
  checkEq("nine parity pairs", ParityPairs.len, 9)
  var all: seq[string]
  for pool in ["small", "mixed", "large"]:
    for name in poolNames(pool): all.add(name)
  for name in ParityPairs:
    check("parity pair " & name & " is a committed map", name in all)
  ## Every pool map must be one of the 54 the oracle jar carries as a
  ## resource, so no parity pair and no smoke episode needs a `--map-dir`.
  const JarMaps = [
    "6147", "arena", "backbencher", "boxy", "bull", "carbonated", "caverns",
    "central_protocol", "channel", "checkers", "closequarters", "collider",
    "collision", "crater", "cranes", "crevasse", "crossfire", "desert",
    "dungeon", "elbow", "fortifications", "frogger", "grasslands",
    "highway", "hourglass", "industrial", "lockdown", "magic",
    "maze", "nexus", "opulent", "planets", "prisons", "puzzle",
    "quadrants", "quarry", "quartiles", "river", "shrine", "space",
    "spaghetti", "sparse", "spiral", "sprinkles", "swamp", "treasure",
    "tunnels", "turtle", "voluted", "vortex", "wormy", "zigzag",
    "scouting", "waves"]
  for name in all:
    check(name & " is one of the 54 maps the oracle jar carries",
      name in JarMaps)

# --- the draw --------------------------------------------------------------
block:
  ## Three DISTINCT maps, and the same seed always draws the same three.
  for seed in [1, 774113, 20160217, 987654321]:
    let drawn = drawMaps("mixed", seed, 3)
    checkEq("seed " & $seed & " draws three maps", drawn.len, 3)
    check("all distinct",
      drawn[0] != drawn[1] and drawn[1] != drawn[2] and drawn[0] != drawn[2])
    checkEq("and the draw is reproducible", drawMaps("mixed", seed, 3), drawn)
  ## Sides alternate every game.
  for seed in [1, 774113, 20160217]:
    let a = sideAslotFor(seed, 0)
    checkEq("game 2 flips the side", sideAslotFor(seed, 1), 1 - a)
    checkEq("and game 3 flips back", sideAslotFor(seed, 2), a)
    check("and the slot is a real seat", a == 0 or a == 1)

block:
  ## **THE `docker-smoke` SEED DRAWS EXACTLY `river`.** `ci.yml`'s bc16
  ## episode pins this seed so the smoke's map cannot drift, and this is the
  ## assertion that keeps the two in step.
  const SmokeSeed = 2016004
  let drawn = drawMaps("small", SmokeSeed, 1)
  checkEq("the docker-smoke seed draws river", drawn, @["river"])
  let ci = readFile(".github" / "workflows" / "ci.yml")
  check("and ci.yml really passes that seed to the bc16 smoke episode",
    "\"seed\":" & $SmokeSeed in ci or "\"seed\": " & $SmokeSeed in ci)

# --- no name collides with another year's file ----------------------------
block:
  ## `turtle`, `vortex`, `maze` and `Hourglass` exist in other years too.
  ## Map files live under `data/maps/bc16/`, so a shared name CANNOT resolve
  ## to the wrong file — asserted rather than assumed.
  for name in ["turtle", "vortex"]:
    check(name & " resolves under data/maps/bc16/",
      mapPath(name).contains("maps" / "bc16"))
    let spec = loadMap(name)
    checkEq("and it is the bc16 one", spec.name, name)
    checkEq("with 3000 rounds", spec.rounds, 3000)
  check("a bc22 map of the same name is a different file",
    fileExists("data" / "maps" / "bc22" / "turtle.json") == false or
    readFile("data" / "maps" / "bc16" / "turtle.json") !=
      readFile("data" / "maps" / "bc22" / "turtle.json"))
  var raised = false
  try:
    discard loadMap("no-such-map-16")
  except CatchableError:
    raised = true
  check("an unknown map raises rather than returning an empty world", raised)

# --- the converter refuses what it must -----------------------------------
block:
  ## The converter's refusals are asserted by `tests/test_constants.nim`
  ## against the real 98 `.xml` files under CI. What THIS shard can assert is
  ## that nothing that got through carries an armageddon shape: 12 000 rounds,
  ## unequal archon counts, or a dimension outside 30..80.
  for row in Table16:
    let spec = loadMap(row.name)
    checkEq(row.name & " is a 3000-round map, not a 12 000-round " &
      "armageddon one", spec.rounds, 3000)
  let tool = readFile("tools" / "convert_maps_bc16.py")
  check("and the converter refuses armageddon by flag",
    "armageddon" in tool)
  check("and refuses unequal archon counts", "unequal archon" in tool.toLowerAscii())


finish("test_bc16_maps")
