## The twenty-two committed bc23 maps, against the design note's own pinned
## table: sizes, seeds, declared symmetry, wall/cloud/current counts, island
## counts and tiles, well counts and headquarters per side. Plus the engine's
## own bounds (20..60 in both dimensions, 4..35 islands, no island above 20
## tiles), the map-generation guarantees the prose states and the engine does
## not enforce, the fact that NO BC23 MAP NAME RESOLVES TO ANOTHER YEAR'S
## FILE, and THE SEED THE DOCKER SMOKE PASSES DRAWING EXACTLY `Quiet`.

import std/[json, os, sets, strutils, tables]
import harness
import bc23_fixture

type Row = tuple[name: string, w, h, seed: int, sym: string, hq: int,
                 walls, clouds, currents, islands, islandTiles, ad, mn: int,
                 toWin: int]

const Table23: array[22, Row] = [
  ("Quiet", 20, 20, 706, "rotation", 1, 46, 14, 20, 4, 8, 4, 2, 3),
  ("SmallElements", 20, 20, 899, "rotation", 2, 16, 16, 22, 4, 24, 4, 6, 3),
  ("Lantern", 20, 20, 899, "vertical", 1, 46, 50, 12, 4, 24, 2, 2, 3),
  ("Spin", 20, 20, 182, "rotation", 1, 18, 218, 50, 4, 20, 2, 2, 3),
  ("Sneaky", 20, 20, 527, "rotation", 3, 24, 148, 48, 4, 24, 2, 2, 3),
  ("Barcode", 20, 20, 95, "rotation", 2, 126, 112, 12, 7, 58, 2, 2, 6),
  ("AllElements", 30, 30, 524, "rotation", 2, 40, 22, 26, 6, 36, 6, 6, 5),
  ("DefaultMap", 32, 32, 386, "rotation", 3, 28, 42, 32, 6, 40, 4, 4, 5),
  ("Cave", 30, 20, 891, "rotation", 2, 132, 34, 48, 8, 104, 4, 4, 6),
  ("MoonPhases", 27, 25, 736, "rotation", 2, 72, 36, 8, 8, 86, 2, 4, 6),
  ("Eyelands", 50, 30, 451, "vertical", 2, 154, 8, 82, 4, 76, 8, 6, 3),
  ("Rectangle", 50, 30, 753, "rotation", 2, 120, 96, 80, 4, 44, 6, 6, 3),
  ("Scatter", 50, 30, 841, "rotation", 2, 120, 22, 36, 8, 70, 6, 4, 6),
  ("HideAndSeek", 37, 31, 575, "rotation", 2, 68, 123, 78, 16, 70, 4, 4, 12),
  ("Rainbow", 40, 30, 473, "vertical", 2, 268, 156, 36, 20, 112, 4, 4, 15),
  ("IslandHopping", 60, 30, 210, "vertical", 2, 112, 24, 70, 8, 124, 4, 4, 6),
  ("Spiderweb", 45, 45, 914, "rotation", 2, 90, 305, 372, 16, 318, 6, 6, 12),
  ("ThirtyFive", 48, 47, 748, "rotation", 3, 1614, 54, 68, 35, 232, 6, 6, 27),
  ("Target", 60, 60, 721, "rotation", 2, 1528, 280, 92, 12, 154, 4, 4, 9),
  ("Spots", 60, 60, 461, "horizontal", 2, 528, 620, 176, 8, 142, 8, 8, 6),
  ("Forest", 60, 60, 781, "vertical", 4, 210, 976, 120, 7, 128, 6, 4, 6),
  ("Grievance", 60, 60, 336, "rotation", 2, 284, 0, 152, 5, 90, 12, 12, 4)]

block:
  var seen = initHashSet[string]()
  for row in Table23:
    let spec = loadMap(row.name)
    seen.incl(row.name)
    checkEq(row.name & " width", spec.width, row.w)
    checkEq(row.name & " height", spec.height, row.h)
    checkEq(row.name & " seed", spec.randomSeed, row.seed)
    checkEq(row.name & " symmetry", $spec.symmetry, "sym" &
      row.sym[0].toUpperAscii() & row.sym[1 .. ^1])
    checkEq(row.name & " rounds", spec.rounds, GameMaxNumberOfRounds)
    var walls = 0
    for v in spec.walls:
      if v: walls += 1
    checkEq(row.name & " walls", walls, row.walls)
    var clouds = 0
    for v in spec.clouds:
      if v: clouds += 1
    checkEq(row.name & " clouds", clouds, row.clouds)
    var currents = 0
    for v in spec.currents:
      if v != 0: currents += 1
    checkEq(row.name & " currents", currents, row.currents)
    let sizes = spec.islandSizes()
    checkEq(row.name & " islands", sizes.len, row.islands)
    var tiles = 0
    for s in sizes: tiles += s
    checkEq(row.name & " island tiles", tiles, row.islandTiles)
    checkEq(row.name & " islands to win", islandsToWin(sizes.len), row.toWin)
    var ad = 0
    var mn = 0
    var ex = 0
    for v in spec.resources:
      if v == 1: ad += 1
      elif v == 2: mn += 1
      elif v == 3: ex += 1
    checkEq(row.name & " adamantium wells", ad, row.ad)
    checkEq(row.name & " mana wells", mn, row.mn)
    checkEq(row.name & " has NO elixir well — which is why `elixir_tech` " &
      "is a knob and not a map property", ex, 0)
    checkEq(row.name & " headquarters per side", spec.headquartersPerSide(),
      row.hq)

    ## The engine's own bounds.
    check(row.name & " width is within 20..60",
      spec.width >= MapMinWidth and spec.width <= MapMaxWidth)
    check(row.name & " height is within 20..60",
      spec.height >= MapMinHeight and spec.height <= MapMaxHeight)
    check(row.name & " island count is within 4..35",
      sizes.len >= MinNumberIslands and sizes.len <= MaxNumberIslands)
    for s in sizes:
      check(row.name & " no island exceeds 20 tiles", s <= MaxIslandArea)
    check(row.name & " headquarters per side is within 1..4",
      spec.headquartersPerSide() >= MinStartingHeadquarters and
      spec.headquartersPerSide() <= MaxStartingHeadquarters)
    checkEq(row.name & " both factions have the same number",
      spec.headquartersOf(teamA).len, spec.headquartersOf(teamB).len)

    ## The map-generation guarantees the prose states and the engine does not
    ## enforce, MEASURED here on every committed map.
    var offenders = 0
    var targets = initCountTable[int]()
    for i in 0 ..< spec.width * spec.height:
      if spec.clouds[i] and spec.currents[i] != 0: offenders += 1
      if spec.clouds[i] and spec.walls[i]: offenders += 1
      if spec.currents[i] != 0:
        let x = i mod spec.width
        let y = i div spec.width
        let d = DirectionOrder[spec.currents[i]]
        let nx = x + d.dx
        let ny = y + d.dy
        if nx < 0 or ny < 0 or nx >= spec.width or ny >= spec.height:
          offenders += 1
        elif spec.walls[nx + ny * spec.width]:
          offenders += 1
        else:
          targets.inc(nx + ny * spec.width)
    for _, count in targets:
      if count > 1: offenders += 1
    checkEq(row.name & ": no tile is both cloud and current, no cloud sits " &
      "on a wall, no current flows into a wall or off the map, and no two " &
      "currents share a target", offenders, 0)

    ## No headquarters sits on a current, an island or a well.
    var bad = 0
    for b in spec.initialBodies:
      let i = b.x + b.y * spec.width
      if spec.currents[i] != 0: bad += 1
      if spec.islandIds[i] != 0: bad += 1
      if spec.resources[i] != 0: bad += 1
    checkEq(row.name & ": no headquarters sits on a current, an island or " &
      "a well", bad, 0)
  checkEq("all twenty-two maps were read", seen.len, 22)

# --- the three pools ------------------------------------------------------
block:
  checkEq("the small pool is six", poolNames("small").len, 6)
  checkEq("the mixed pool is ten", poolNames("mixed").len, 10)
  checkEq("the large pool is six", poolNames("large").len, 6)
  checkEq("an empty pool name means `mixed`", poolNames(""), poolNames("mixed"))
  checkEq("an unknown pool is empty", poolNames("nonsense").len, 0)
  ## The mixed pool spans the axis the doctrines argue about.
  var minIslands = 999
  var maxIslands = 0
  var syms: HashSet[string]
  for name in poolNames("mixed"):
    let spec = loadMap(name)
    let n = spec.islandSizes().len
    minIslands = min(minIslands, n)
    maxIslands = max(maxIslands, n)
    syms.incl($spec.symmetry)
  checkEq("islands from 4", minIslands, 4)
  checkEq("to 20", maxIslands, 20)
  check("across at least two symmetries", syms.len >= 2)

# --- no bc23 name resolves to another year's file ------------------------
block:
  for pool in ["small", "mixed", "large"]:
    for name in poolNames(pool):
      let path = mapPath(name)
      check(name & " lives under maps/bc23/", "maps" / "bc23" in path)
      check(name & " exists", fileExists(path))
      checkEq(name & " round-trips its own name", loadMap(name).name, name)
  ## `Lantern` is also a bc25 map name; the per-year directory is what stops
  ## it resolving to the wrong file.
  check("the shared name `Lantern` resolves inside bc23",
    "bc23" in mapPath("Lantern"))

# --- the draw ------------------------------------------------------------
block:
  for seed in [1, 42, 871345, 999983]:
    let drawn = drawMaps("mixed", seed, 3)
    checkEq("the draw is three maps", drawn.len, 3)
    check("all distinct", drawn[0] != drawn[1] and drawn[1] != drawn[2] and
      drawn[0] != drawn[2])
    for name in drawn:
      check("and all from the pool", name in poolNames("mixed"))
    checkEq("the draw is deterministic", drawMaps("mixed", seed, 3), drawn)
  checkEq("sides alternate every game", sideAslotFor(1, 0), 0)
  checkEq("game 2", sideAslotFor(1, 1), 1)
  checkEq("game 3", sideAslotFor(1, 2), 0)
  checkEq("and the seed picks who starts", sideAslotFor(256, 0), 1)

# --- THE DOCKER SMOKE'S SEED DRAWS EXACTLY `Quiet` -----------------------
block:
  ## `ci.yml`'s bc23 episode passes `seed: 1009` on the `small` pool with
  ## `gamesPerMatch: 1`, so the map cannot drift silently.
  const SmokeSeed = 1009
  let drawn = drawMaps("small", SmokeSeed, 1)
  checkEq("the smoke's seed draws exactly one map", drawn.len, 1)
  checkEq("AND IT IS `Quiet` — the smallest map in the pool", drawn[0],
    "Quiet")

# --- the map card --------------------------------------------------------
block:
  let spec = loadMap("Rainbow")
  let card = spec.mapCard(0, 0)
  checkEq("the card names the map", card["map"].getStr(), "Rainbow")
  checkEq("the islands", card["islands"].getInt(), 20)
  checkEq("and the exact number a conquest needs",
    card["islands_to_win"].getInt(), 15)
  checkEq("both factions' headquarters are public",
    card["your_headquarters"].len, 2)
  checkEq("both of them", card["enemy_headquarters"].len, 2)
  checkEq("no elixir well", card["terrain"]["elixir_wells"].getInt(), 0)
  check("the nearest well is reported",
    card["nearest_well_to_you"].kind != JNull)
  check("and the nearest island", card["nearest_island_to_you"].kind != JNull)
  let other = spec.mapCard(1, 0)
  checkEq("the two seats' cards are numerically identical",
    other["islands"].getInt(), card["islands"].getInt())
  checkEq("and differ only in `you_are`", other["you_are"].getStr(), "B")

finish("test_bc23_maps")
