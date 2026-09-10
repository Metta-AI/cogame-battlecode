## The 22 committed bc19 boards, their geometry and THE DOCKER-SMOKE DRAW.
##
## bc19 ships no map files upstream: every board is procedurally generated
## from its seed by the pinned engine (V3), so the NAME IS THE RECIPE. The
## REGENERATION byte-diff needs Node and lives in `parity-oracle-bc19`; this
## shard checks what the committed files SAY against the geometry the design
## note measured, and that the runtime can load every one of them.

import std/[json, math, os, strutils]
import harness
import battlecode/years/bc19/[maps, world, units, mt19937]

const Expect = [
  ## name, size, passable, karbonite, fuel, castles a side, horizontal?, sep*10
  ("seed-0009", 32,  830,  4,  8, 1, true,  250),
  ("seed-0021", 33,  827,  4,  6, 1, true,  220),
  ("seed-0034", 33,  955,  4,  8, 1, false, 240),
  ("seed-0043", 35, 1095,  8,  8, 2, true,  140),
  ("seed-0048", 32,  786,  4,  4, 2, false, 210),
  ("seed-0107", 37,  965, 10,  8, 3, false, 140),
  ("seed-0005", 39, 1333, 12, 16, 2, false, 180),
  ("seed-0017", 41, 1501,  9, 10, 1, true,  280),
  ("seed-0035", 51, 1931, 14, 10, 2, true,  340),
  ("seed-0039", 50, 2302, 14, 14, 3, true,  270),
  ("seed-0042", 44, 1436,  8,  8, 3, true,  210),
  ("seed-0058", 44, 1346, 14, 18, 1, true,  370),
  ("seed-0060", 41, 1217, 14, 14, 3, false, 140),
  ("seed-0125", 48, 1716, 26, 18, 2, false, 150),
  ("seed-0001", 45, 1499,  8, 12, 3, true,  220),
  ("seed-0003", 50, 2280, 16, 12, 2, false, 270),
  ("seed-0013", 61, 2943, 16, 26, 2, false, 480),
  ("seed-0030", 62, 3324, 38, 34, 3, true,  230),
  ("seed-0045", 64, 3294, 24, 24, 3, false, 290),
  ("seed-0056", 64, 3438, 26, 30, 3, true,  270),
  ("seed-0077", 62, 3254, 22, 32, 2, true,  450),
  ("seed-0117", 63, 2795, 26, 32, 3, false, 180)]

block:
  checkEq("the three pools hold 22 boards between them",
    SmallPool.len + MixedPool.len + LargePool.len, 22)
  checkEq("`mixed` is the variant's played pool and has ten", MixedPool.len, 10)
  checkEq("`small` is the parity and smoke pool and has six", SmallPool.len, 6)
  checkEq("`large` is reserved and has six", LargePool.len, 6)
  checkEq("and there are nine parity pairs", ParityPairs.len, 9)
  var allNames: seq[string]
  for n in SmallPool: allNames.add(n)
  for n in MixedPool: allNames.add(n)
  for n in LargePool: allNames.add(n)
  for n in ParityPairs:
    check("every parity pair is a committed board: " & n, n in allNames)
  checkEq("and every expected row is in a pool", Expect.len, allNames.len)

block:
  for row in Expect:
    let (name, size, passable, karb, fuel, cast0, horiz, sep) = row
    check("the file is committed: " & name, fileExists(mapPath(name)))
    let spec = loadMap(name)
    checkEq(name & " is square", spec.width, spec.height)
    checkEq(name & "'s size", spec.width, size)
    check(name & " is inside 32..64",
      spec.width >= 32 and spec.width <= MaxBoardSize)
    checkEq(name & "'s passable count", spec.passableSquares, passable)
    checkEq(name & "'s karbonite depots", spec.karboniteDepots, karb)
    checkEq(name & "'s fuel depots", spec.fuelDepots, fuel)
    checkEq(name & "'s castles a side", spec.castlesPerSide, cast0)
    checkEq(name & "'s symmetry axis", spec.symmetryHorizontal, horiz)
    checkEq(name & "'s minimum castle separation x10",
      int(round(spec.separation(true) * 10.0)), sep)
    checkEq(name & " carries the seed its name promises",
      spec.mapSeed, parseInt(name[5 .. ^1]))
    ## The three boolean grids really are `width * height` and the passable
    ## count in the header really is the grid's.
    checkEq(name & "'s map grid is width*height",
      spec.passable.len, spec.width * spec.height)
    var counted = 0
    for v in spec.passable:
      if v: inc counted
    checkEq(name & "'s header passable count is the grid's",
      counted, spec.passableSquares)
    ## THE SAVED MT19937 STATE (V3, D1.2) -- 624 words and an `mti`.
    checkEq(name & " carries 624 MT words", spec.mtWords.len, MtN)
    check(name & "'s mti is in range",
      spec.mtMti >= 0 and spec.mtMti <= MtN)
    ## EQUAL CASTLE COUNTS >= 1, and the roster is in `to_create` order --
    ## RED, BLUE, RED, BLUE -- which is the opening queue order and therefore
    ## the order the ids are drawn in.
    var red = 0
    var blue = 0
    for i, c in spec.castles:
      if c.team == 0: inc red else: inc blue
      checkEq(name & "'s to_create order alternates at " & $i,
        c.team, i mod 2)
      check(name & "'s castle " & $i & " is on a passable square",
        spec.passable[c.y * spec.width + c.x])
    checkEq(name & " has equal castle counts", red, blue)
    check(name & " has at least one castle a side", red >= 1)
    ## The board really is a mirror across the axis the header names.
    var mirrored = true
    for y in 0 ..< spec.height:
      for x in 0 ..< spec.width:
        let (mx, my) =
          if spec.symmetryHorizontal: (spec.width - 1 - x, y)
          else: (x, spec.height - 1 - y)
        if spec.passable[y * spec.width + x] !=
            spec.passable[my * spec.width + mx]:
          mirrored = false
    check(name & " really is mirrored across its stated axis", mirrored)
    ## EXACTLY ONE PASSABLE REGION -- the curation rule that keeps the 13
    ## degenerate seeds out of the pool.
    var visited = newSeq[bool](spec.width * spec.height)
    var regions = 0
    for y in 0 ..< spec.height:
      for x in 0 ..< spec.width:
        let i = y * spec.width + x
        if not spec.passable[i] or visited[i]: continue
        inc regions
        var stack = @[(x, y)]
        while stack.len > 0:
          let (cx, cy) = stack.pop()
          let ci = cy * spec.width + cx
          if visited[ci]: continue
          visited[ci] = true
          for d in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
            let nx = cx + d[0]
            let ny = cy + d[1]
            if nx < 0 or ny < 0 or nx >= spec.width or ny >= spec.height:
              continue
            if spec.passable[ny * spec.width + nx] and
                not visited[ny * spec.width + nx]:
              stack.add((nx, ny))
    checkEq(name & " has exactly one passable region", regions, 1)
    check(name & " is at least 30 % passable",
      spec.passableSquares * 100 >= spec.width * spec.height * 30)
    ## A square is never both a karbonite depot and a fuel depot (the
    ## generator's `c_in` rejection, `game.js:258,269`).
    for i in 0 ..< spec.passable.len:
      check(name & " has no square on both resource maps at " & $i,
        not (spec.karboniteMap[i] and spec.fuelMap[i]))

block:
  ## NO bc19 MAP NAME RESOLVES TO ANOTHER YEAR'S FILE: `data/maps/bc19/` is
  ## its own directory and the names are `seed-NNNN`, which no other year
  ## uses.
  for name in ParityPairs:
    check(name & " resolves under data/maps/bc19",
      "maps" / "bc19" in mapPath(name))
    for other in ["bc16", "bc20", "bc21", "bc22", "bc23", "bc24", "bc25",
                  "bc26"]:
      check(name & " does not resolve under " & other,
        not fileExists(dataRoot() / "maps" / other / (name & ".json")))

block:
  ## THE DOCKER-SMOKE DRAW, pinned from this side so the smoke's map cannot
  ## drift silently. `ci.yml`'s bc19 episode passes `"seed": 13`.
  checkEq("the pinned smoke seed", SmokeSeed, 13)
  let drawn = drawMaps("small", SmokeSeed, 1)
  checkEq("draws exactly one map", drawn.len, 1)
  checkEq("AND IT IS seed-0043 -- 35x35, two castles a side, minimum " &
    "separation 14, 89.4 % passable", drawn[0], "seed-0043")
  ## And the three-map draw the `bc19` variant makes is three DISTINCT maps
  ## from `mixed`, for every seed the platform can hand it.
  for seed in [0, 1, 7, 42, 774113, 2_000_000_011]:
    let three = drawMaps("mixed", seed, 3)
    checkEq("three maps are drawn for seed " & $seed, three.len, 3)
    check("and they are distinct",
      three[0] != three[1] and three[1] != three[2] and three[0] != three[2])
    for n in three:
      check("and every one is in `mixed`", n in MixedPool)
  ## Sides alternate every game, and the seed picks the first.
  for seed in [0, 1, 256, 257]:
    let a = sideAslotFor(seed, 0)
    check("sideAslot is a slot", a == 0 or a == 1)
    checkEq("and it alternates in game 2", sideAslotFor(seed, 1), 1 - a)
    checkEq("and back in game 3", sideAslotFor(seed, 2), a)

block:
  ## The map card a seat is handed. Both seats' cards are numerically
  ## identical -- every board is a mirror -- and the only asymmetry is
  ## `you_are` and which mirrored coordinate set is labelled "yours".
  let spec = loadMap("seed-0043")
  let red = spec.mapCard(0, 0)
  let blue = spec.mapCard(1, 0)
  checkEq("the RED card says RED", red["you_are"].getStr(), "RED")
  checkEq("the BLUE card says BLUE", blue["you_are"].getStr(), "BLUE")
  for key in ["passable_squares", "total_squares", "width", "height",
              "map_seed"]:
    checkEq("the two cards agree on " & key, red[key], blue[key])
  checkEq("your castles are theirs and theirs are yours",
    red["your_castles"], blue["enemy_castles"])
  checkEq("and the mirror image of that", red["enemy_castles"],
    blue["your_castles"])
  checkEq("seed-0043 is 89.4 % passable", red["passable_pct"].getFloat(), 89.4)
  checkEq("with two castles a side", red["your_castles"].len, 2)
  check("and the note says which midline it is mirrored across",
    red["symmetry_note"].getStr().contains("VERTICAL midline"))
  check("rounds are 1-based", red["rounds_are_one_based"].getBool())
  check("and the deposit rule is on the card",
    red["deposit_note"].getStr().contains("UNSPENDABLE"))

finish("test_bc19_maps")
