## bc25 maps: every committed map against the design note's pinned table, the
## 20..60 bounds, the four initial bodies (two per team, one paint and one
## money, upgraded to LEVEL TWO with 500 paint at construction), the ruin list
## NOT containing the tower tiles while the world adds them, the ruin spacing
## rule, no name resolving to another year's file, and THE SEED THE SMOKE
## PASSES DRAWING `DefaultSmall`.

import std/[json, os, strutils]
import harness
import bc25_fixture

const Pinned = [
  ## name, width, height, seed, symmetry, walls, ruins (file + 4), pre-paint
  ("DefaultSmall", 20, 20, 363, "rotation", 28, 12, 16),
  ("CastleDefense", 20, 20, 842, "rotation", 60, 10, 62),
  ("Paintball", 20, 20, 733, "rotation", 46, 12, 122),
  ("Justice", 21, 20, 519, "vertical", 31, 12, 34),
  ("Filter", 21, 21, 64, "horizontal", 22, 9, 12),
  ("Jail", 20, 30, 63, "vertical", 60, 12, 106),
  ("Fossil", 30, 30, 520, "horizontal", 32, 18, 114),
  ("SandyBeach", 30, 30, 852, "vertical", 78, 20, 470),
  ("rain", 30, 30, 22, "rotation", 50, 16, 30),
  ("roads", 30, 30, 535, "horizontal", 130, 12, 146),
  ("DefaultMedium", 35, 35, 424, "vertical", 32, 23, 72),
  ("Money", 35, 35, 228, "rotation", 84, 24, 234),
  ("Portal", 35, 35, 955, "rotation", 96, 26, 140),
  ("Bunny", 44, 30, 137, "vertical", 92, 20, 258),
  ("DefaultLarge", 50, 30, 340, "vertical", 24, 24, 178),
  ("leavemealone", 50, 30, 134, "vertical", 136, 18, 324),
  ("HungerGames", 50, 50, 8, "rotation", 242, 30, 286),
  ("Oasis", 59, 59, 603, "rotation", 142, 28, 272),
  ("DefaultHuge", 59, 59, 248, "horizontal", 60, 53, 128),
  ("Leaf", 60, 60, 398, "vertical", 160, 56, 140),
  ("SMILE", 60, 60, 347, "vertical", 118, 42, 546),
  ("gardenworld", 60, 60, 684, "rotation", 420, 26, 60)]

block:
  var names: seq[string]
  for n in @SmallPool & @MixedPool & @LargePool:
    if n notin names: names.add(n)
  checkEq("22 maps are committed and pooled", names.len, 22)
  checkEq("the small pool is six", SmallPool.len, 6)
  checkEq("the mixed pool -- the bc25 variant's -- is twelve",
    MixedPool.len, 12)
  checkEq("and the reserved large pool is six", LargePool.len, 6)
  for n in names:
    check("the file exists: " & n, fileExists(mapPath(n)))

block:
  for (name, wid, hei, seed, sym, walls, ruins, prePaint) in Pinned:
    let spec = loadMap(name)
    checkEq(name & " name", spec.name, name)
    checkEq(name & " width", spec.width, wid)
    checkEq(name & " height", spec.height, hei)
    checkEq(name & " seed", spec.randomSeed, seed)
    checkEq(name & " symmetry",
      ($spec.symmetry).replace("sym", "").toLowerAscii(), sym)
    var wallCount = 0
    for v in spec.walls:
      if v: wallCount += 1
    checkEq(name & " walls", wallCount, walls)
    checkEq(name & " pre-painted tiles", spec.paint.len, prePaint)
    ## The file's ruin list does NOT contain the four tower tiles.
    checkEq(name & " file ruins plus the four tower tiles",
      spec.ruins.len + 4, ruins)
    for b in spec.initialBodies:
      check(name & " no tower tile is in the file's ruin list",
        loc(b.x, b.y) notin spec.ruins)
    ## But the world adds them.
    let w = newWorld(spec, 2000)
    checkEq(name & " the world's ruin list has all of them",
      w.allRuins.len, ruins)
    check(name & " is within 20..60 in width",
      spec.width >= MapMinWidth and spec.width <= MapMaxWidth)
    check(name & " is within 20..60 in height",
      spec.height >= MapMinHeight and spec.height <= MapMaxHeight)

proc ascendingInFile(spec: MapSpec): bool =
  for i in 1 ..< spec.initialBodies.len:
    if spec.initialBodies[i - 1].id > spec.initialBodies[i].id: return false
  true

var unsortedFiles = 0

block:
  ## Four initial bodies: two per team, one paint and one money each, and the
  ## world upgrades them to LEVEL TWO with 500 paint.
  for (name, _, _, _, _, _, _, _) in Pinned:
    let spec = loadMap(name)
    checkEq(name & " has four initial bodies", spec.initialBodies.len, 4)
    var perTeam = [0, 0]
    var kinds = [0, 0]
    for b in spec.initialBodies:
      perTeam[b.team - 1] += 1
      kinds[b.kind - 1] += 1
    checkEq(name & " two a side", perTeam, [2, 2])
    checkEq(name & " one paint and one money each", kinds, [2, 2])
    let w = newWorld(spec, 2000)
    var levelTwo = 0
    for id in w.execOrder:
      let t = w.robotsById[id]
      if UnitSpecs[t.kind].level == 2: levelTwo += 1
      checkEq(name & " a starting tower holds 500 paint", t.paint,
        InitialTowerPaintAmount)
      checkEq(name & " and full health for its level", t.health,
        UnitSpecs[t.kind].health)
    checkEq(name & " all four start at LEVEL TWO", levelTwo, 4)
    checkEq(name & " and the tower counts are two a side", w.stats.towers,
      [2, 2])
    discard
    ## `LiveMap` sorts by id, and every real map file lists them DESCENDING,
    ## so the exec order is the file's order reversed.
    var ascending = true
    for i in 1 ..< w.execOrder.len:
      if w.execOrder[i - 1] >= w.execOrder[i]: ascending = false
    check(name & " the exec order is ascending id", ascending)
    if not ascendingInFile(spec): unsortedFiles += 1

block:
  ## `MIN_RUIN_SPACING_SQUARED = 25`: ruin centres are pairwise at least 5
  ## apart. (The engine computes this and discards it -- `confirmRuinPlacements`
  ## is dead code -- but every shipped map satisfies it and a converter bug
  ## would show up here.)
  for (name, _, _, _, _, _, _, _) in Pinned:
    let w = newWorld(loadMap(name), 2000)
    var tooClose = 0
    for i in 0 ..< w.allRuins.len:
      for j in i + 1 ..< w.allRuins.len:
        if w.allRuins[i].distanceSquaredTo(w.allRuins[j]) <
            MinRuinSpacingSquared:
          tooClose += 1
    checkEq(name & " ruins are pairwise >= 5 apart", tooClose, 0)

block:
  ## A name shared with another year cannot resolve to the wrong file.
  for shared in ["DefaultSmall", "DefaultMedium", "DefaultLarge",
                 "DefaultHuge", "HungerGames"]:
    check(shared & " resolves under data/maps/bc25/",
      mapPath(shared).contains("bc25"))
  let mine = loadMap("DefaultSmall")
  checkEq("and it is the 2025 file, not 2024's", mine.randomSeed, 363)

block:
  ## THE SEED THE `docker-smoke` STEP PASSES DRAWS `DefaultSmall` FROM THE
  ## `small` POOL, so the smoke's map cannot drift silently. `ci.yml` passes
  ## the same seed in `SMOKE_CONFIG_OVERRIDE`.
  const SmokeSeed = 3
  let drawn = drawMaps("small", SmokeSeed, 1)
  checkEq("the smoke seed draws exactly one map", drawn.len, 1)
  checkEq("and it is DefaultSmall", drawn[0], "DefaultSmall")

block:
  ## The draw returns DISTINCT maps and alternates sides.
  for seed in [0, 1, 42, 871345]:
    let three = drawMaps("mixed", seed, 3)
    checkEq("three maps drawn for seed " & $seed, three.len, 3)
    check("and they are distinct",
      three[0] != three[1] and three[1] != three[2] and three[0] != three[2])
    for g in 0 .. 2:
      checkEq("sides alternate every game", sideAslotFor(seed, g),
        ((seed shr 8) and 1) xor (g and 1))

block:
  ## The map card reports the numbers the doctrine plans against.
  let spec = loadMap("DefaultSmall")
  let card = mapCard(spec, 0, 0)
  checkEq("area_without_walls", card["terrain"]["area_without_walls"].getInt(),
    372)
  checkEq("truly_paintable", card["terrain"]["truly_paintable"].getInt(), 360)
  checkEq("tiles_to_win", card["terrain"]["tiles_to_win"].getInt(), 261)
  checkEq("ruins", card["terrain"]["ruins"].getInt(), 12)
  checkEq("both seats' cards are numerically identical", 
    mapCard(spec, 1, 0)["terrain"], card["terrain"])
  checkEq("only `you_are` differs", mapCard(spec, 1, 0)["you_are"].getStr(),
    "B")
  checkEq("and the starting towers are public",
    card["your_start_towers"].len, 2)

block:
  ## THE SORT IS LOAD-BEARING, not cosmetic: some committed map files list
  ## their `InitialBodyTable` id-DESCENDING and some id-ascending, and
  ## `LiveMap`'s constructor sorts before the world ever sees them
  ## (docs/RULES-BC25.md Divergences 15). If every file happened to be sorted
  ## already this assertion would be the thing that noticed.
  check("at least one committed map lists its bodies out of id order",
    unsortedFiles > 0)

finish("test_bc25_maps")
