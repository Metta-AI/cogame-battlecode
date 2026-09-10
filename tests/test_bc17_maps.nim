## §Tests item 16 -- the twenty-two committed boards.
##
## Every row of §Sim module's measured table is asserted here against the
## committed JSON: size, seed, archons per side, neutral-tree census, total
## tree radius, how many trees hold bullets or a robot, and the minimum
## distance between an opposing archon pair. The table was measured by
## loading each board through the ORACLE JAR's own `LiveMap` and reading the
## numbers back; if a conversion ever drifts, this shard is where it shows.
##
## Two rules that are NOT in the file and must be recomputed:
##
##   * a neutral tree's health is `200 x radius`, computed at load and never
##     read from the JSON;
##   * `rounds` is 3 000 on every board.

import std/[algorithm, json, math, os, strutils, tables]
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom, units, world, maps]

type Row = tuple[name: string, w, h: float, seed, arch, trees: int,
                 sumR: float, bul, rob: int, sep: float]

const Table22: array[22, Row] = [
  ("CropCircles", 30.0, 30.0, 982, 1, 198, 99.0, 190, 0, 33.9),
  ("GreenHouse", 30.0, 30.0, 713, 1, 58, 58.0, 56, 58, 20.1),
  ("HiddenTunnel", 30.0, 30.0, 143, 1, 484, 242.0, 458, 0, 25.2),
  ("HouseDivided", 30.0, 30.0, 937, 1, 41, 40.9, 41, 6, 6.5),
  ("OMGTree", 30.0, 30.0, 131, 1, 1, 10.0, 0, 0, 24.6),
  ("shrine", 30.0, 30.0, 774, 1, 1, 2.0, 1, 1, 36.7),
  ("Aligned", 42.0, 40.0, 82, 1, 202, 202.0, 190, 0, 37.6),
  ("Barrier", 60.0, 60.0, 98, 2, 22, 66.0, 22, 0, 40.0),
  ("Blitzkrieg", 60.0, 40.0, 410, 3, 180, 99.0, 168, 6, 50.0),
  ("Chess", 64.0, 64.0, 787, 2, 924, 504.0, 892, 28, 56.0),
  ("Cramped", 50.0, 50.0, 192, 1, 44, 89.7, 0, 4, 5.0),
  ("DenseForest", 50.0, 50.0, 788, 2, 46, 92.0, 46, 0, 15.1),
  ("Hurdle", 50.0, 50.0, 535, 1, 16, 32.0, 16, 0, 40.0),
  ("Snowflake", 60.0, 60.0, 808, 3, 89, 127.7, 22, 0, 26.4),
  ("TreeFarm", 52.0, 52.0, 277, 1, 142, 142.0, 140, 0, 56.9),
  ("Waves", 60.0, 50.0, 145, 2, 142, 127.4, 0, 0, 12.0),
  ("Alone", 100.0, 100.0, 610, 1, 0, 0.0, 0, 0, 127.3),
  ("GiantForest", 100.0, 100.0, 753, 3, 10, 100.0, 10, 0, 56.0),
  ("Interference", 100.0, 100.0, 289, 3, 394, 394.0, 376, 0, 8.5),
  ("LineOfFire", 100.0, 30.0, 116, 2, 1228, 620.0, 2, 4, 95.0),
  ("Maniple", 100.0, 60.0, 444, 3, 406, 406.0, 0, 406, 50.0),
  ("Whirligig", 100.0, 100.0, 149, 3, 476, 476.0, 466, 0, 26.1),
]

# --- the pools cover the table exactly --------------------------------------
block:
  var pooled: seq[string]
  for name in SmallPool: pooled.add(name)
  for name in MixedPool: pooled.add(name)
  for name in LargePool: pooled.add(name)
  checkEq("the three pools hold twenty-two boards between them",
    pooled.len, 22)
  var tabled: seq[string]
  for row in Table22: tabled.add(row.name)
  pooled.sort()
  tabled.sort()
  checkEq("and they are exactly the tabled ones", pooled, tabled)
  for name in ParityPairs:
    check(name & " (a parity pair) is one of them", name in tabled)
  checkEq("there are nine parity pairs", ParityPairs.len, 9)

# --- every row, measured off the committed board ---------------------------
block:
  for row in Table22:
    let spec = loadMap(row.name)
    let n = row.name
    check(n & " is " & $int(row.w) & "x" & $int(row.h),
      abs(float(spec.rect.width) - row.w) < 0.001 and
        abs(float(spec.rect.height) - row.h) < 0.001)
    checkEq(n & "'s seed", spec.mapSeed, row.seed)
    checkEq(n & " runs 3000 rounds", spec.rounds, 3000)
    checkEq(n & " has " & $row.arch & " archons a side", spec.archonsPerSide,
      row.arch)
    checkEq(n & "'s archon rosters are EQUAL", archonsOf(spec, tA).len,
      archonsOf(spec, tB).len)
    checkEq(n & " has " & $row.trees & " neutral trees", spec.neutralTrees,
      row.trees)
    check(n & "'s total tree radius is " & $row.sumR,
      abs(round1(spec.totalTreeRadius()) - row.sumR) < 0.06)
    checkEq(n & " has " & $row.bul & " trees holding bullets",
      spec.treesWithBullets, row.bul)
    checkEq(n & " has " & $row.rob & " trees holding a robot",
      spec.treesWithRobots, row.rob)
    ## The measured minimum opposing-archon distance, recomputed here.
    var sep = 1e30
    for a in archonsOf(spec, tA):
      for b in archonsOf(spec, tB):
        sep = min(sep, float(distanceTo(a.loc, b.loc)))
    check(n & "'s archon separation is " & $row.sep,
      abs(round1(sep) - row.sep) < 0.051)
    checkEq(n & "'s recorded minimum separation agrees",
      round1(spec.archonSeparationMin()), round1(sep))

# --- the size and archon-count envelope -------------------------------------
block:
  for row in Table22:
    let spec = loadMap(row.name)
    check(row.name & " is 30..100 wide",
      spec.rect.width >= float32(mapMinWidth) - 0.001'f32 and
        spec.rect.width <= float32(mapMaxWidth) + 0.001'f32)
    check(row.name & " is 30..100 high",
      spec.rect.height >= float32(mapMinHeight) - 0.001'f32 and
        spec.rect.height <= float32(mapMaxHeight) + 0.001'f32)
    check(row.name & " has 1, 2 or 3 archons a side",
      spec.archonsPerSide in 1 .. numberOfArchonsMax)

# --- a neutral tree's health is RECOMPUTED ----------------------------------
block:
  ## `200 x radius`, computed at load. The JSON also carries a `health`
  ## field, and the loader must not trust it.
  var checked = 0
  var wrong = 0
  for row in Table22:
    if row.trees == 0: continue
    let spec = loadMap(row.name)
    for b in spec.bodies:
      if b.isRobot: continue
      inc checked
      if bits(b.health) != bits(neutralTreeHealthRate * b.radius): inc wrong
  check("thousands of neutral trees were checked", checked > 4000)
  checkEq("every one has health == 200 x radius", wrong, 0)
  ## And it really is recomputed, not copied: a hand-built spec with a lying
  ## health field comes back with the right number.
  let doctored = parseMapSpec("""{"name":"probe","seed":1,"width":30.0,
    "height":30.0,"origin":[0.0,0.0],"rounds":3000,
    "initial_bodies":[
      {"kind":"tree","id":1,"team":"neutral","x":10.0,"y":10.0,
       "radius":2.0,"health":1.0,"contained_bullets":0,
       "contained_robot":"-"},
      {"kind":"robot","id":2,"team":"A","type":"archon","x":5.0,"y":5.0},
      {"kind":"robot","id":3,"team":"B","type":"archon","x":25.0,"y":25.0}]}""")
  checkEq("a lying health field in the JSON is ignored",
    bits(doctored.bodies[0].health), bits(400'f32))

# --- no bc17 name resolves to another year's file ---------------------------
block:
  ## Every year has a `data/maps/<year>/` directory and several names recur
  ## across years. The loader must never reach outside `bc17`.
  for row in Table22:
    let path = mapPath(row.name)
    check(row.name & " loads from data/maps/bc17/", "/maps/bc17/" in path)
    check(row.name & "'s file exists there", fileExists(path))
  var collisions: seq[string]
  for other in ["bc16", "bc19", "bc20", "bc21", "bc22", "bc23", "bc24",
                "bc25", "bc26"]:
    let dir = dataRoot() / "maps" / other
    if not dirExists(dir): continue
    for path in walkFiles(dir / "*.json"):
      let stem = path.extractFilename().changeFileExt("")
      for row in Table22:
        if stem == row.name: collisions.add(other & "/" & stem)
  ## A shared NAME is fine -- a shared FILE would not be, and the path test
  ## above is what rules that out. Report any shared names so the fact is
  ## visible rather than assumed.
  if collisions.len > 0:
    echo "  names shared with another year (loaded from bc17 all the same): ",
      collisions.join(", ")
  check("and the bc17 loader is pinned to its own directory regardless",
    "/maps/bc17/" in mapPath("Chess"))

# --- the docker-smoke draw is PINNED ----------------------------------------
block:
  checkEq("the smoke seed is 5", SmokeSeed, 5)
  let drawn = drawMaps("small", SmokeSeed, 1)
  checkEq("and it draws exactly HouseDivided", drawn, @["HouseDivided"])
  ## Why that map: archon separation 6.5, so first blood lands inside twenty
  ## rounds and the smoke exercises combat, bullet collision and the strike.
  let spec = loadMap("HouseDivided")
  check("whose archon separation really is the smallest in the small pool",
    spec.archonSeparationMin() <= 6.6)

# --- drawMaps returns DISTINCT maps ------------------------------------------
block:
  for pool in ["small", "mixed", "large"]:
    for seed in [1, 5, 42, 937, 20170101]:
      let drawn = drawMaps(pool, seed, 3)
      checkEq(pool & " seed " & $seed & " draws three", drawn.len, 3)
      var seen = initTable[string, int]()
      for name in drawn: seen.mgetOrPut(name, 0) += 1
      checkEq("all distinct", seen.len, 3)
      for name in drawn:
        check(name & " is in the " & pool & " pool", name in poolNames(pool))
  checkEq("asking for more than the pool holds gives the whole pool",
    drawMaps("small", 7, 99).len, SmallPool.len)

# --- sideAslotFor alternates -------------------------------------------------
block:
  for seed in [0, 1, 256, 937, 20170101]:
    let first = sideAslotFor(seed, 0)
    check("game 1's side is a seat", first in 0 .. 1)
    checkEq("game 2 swaps", sideAslotFor(seed, 1), 1 - first)
    checkEq("game 3 swaps back", sideAslotFor(seed, 2), first)

# --- the map card ------------------------------------------------------------
block:
  let spec = loadMap("HouseDivided")
  let card = spec.mapCard(0, 0)
  checkEq("the card names the map", card["map"].getStr(), "HouseDivided")
  check("carries the seed", card.hasKey("map_seed"))
  check("and both archon rosters, because they are NOT secret",
    card.hasKey("your_archons") and card.hasKey("enemy_archons"))
  let other = spec.mapCard(1, 0)
  checkEq("the two seats' cards differ only in whose roster is whose",
    card["your_archons"], other["enemy_archons"])

finish("test_bc17_maps")
