## The converted bc20 maps: every one re-converts identically (checked by
## `tools/ci/check_bc20_maps.sh` in CI, and by shape here), the sizes and
## symmetries match the pinned table, the sim's own per-spawn detector agrees
## with the converter, and every array is `width x height`.

import std/[algorithm, json, os, strutils, tables]
import harness
import battlecode/years/bc20/[constants, maps, world]

const Pinned = {
  "maptestsmall": (32, 32, "vertical"),
  "WateredDown": (32, 32, "horizontal"),
  "Infinity": (33, 33, "rotational"),
  "Spiral": (33, 33, "rotational"),
  "Hourglass": (40, 32, "horizontal"),
  "ALandDivided": (41, 32, "vertical"),
  "Climb": (40, 40, "rotational"),
  "Constriction": (40, 40, "rotational"),
  "CentralLake": (41, 41, "rotational"),
  "Toothpaste": (45, 37, "rotational"),
  "TwoLakeLand": (45, 45, "horizontal"),
  "CentralSoup": (48, 48, "rotational"),
  "Hills": (60, 60, "rotational"),
  "OmgThisIsProcedural": (60, 64, "vertical"),
  "Squares": (63, 63, "vertical"),
  "BeachFrontProperty": (64, 64, "rotational"),
  "Maze": (64, 64, "rotational"),
  "TheHighGround": (64, 64, "rotational"),
}.toTable
  ## Read out of the real `.map20` flatbuffers, not assumed.

block:
  checkEq("the small pool has six maps", SmallPool.len, 6)
  checkEq("the mixed pool has twelve", MixedPool.len, 12)
  checkEq("the large pool has six", LargePool.len, 6)
  for name in SmallPool:
    check(name & " is also in the mixed pool", name in MixedPool)
  var all: seq[string]
  for pool in [@SmallPool, @MixedPool, @LargePool]:
    for name in pool:
      if name notin all: all.add(name)
  checkEq("eighteen distinct maps are committed", all.len, 18)
  check("CowFarm is deliberately excluded", "CowFarm" notin all)
  check("and DidAMonkeyMakeThis too", "DidAMonkeyMakeThis" notin all)
  checkEq("an unknown pool name is empty, not silently mixed",
    poolNames("nonsense").len, 0)

block:
  for name, want in Pinned:
    let spec = loadMap(name)
    checkEq(name & " has the pinned width", spec.width, want[0])
    checkEq(name & " has the pinned height", spec.height, want[1])
    checkEq(name & " has the pinned symmetry",
      ($spec.symmetry).replace("sym", "").toLowerAscii(), want[2])
    let n = spec.width * spec.height
    checkEq(name & "'s elevation array is width x height", spec.elevation.len, n)
    checkEq(name & "'s water array is width x height", spec.water.len, n)
    checkEq(name & "'s pollution array is width x height",
      spec.pollution.len, n)
    checkEq(name & "'s soup array is width x height", spec.soup.len, n)

    var hqs = 0
    for body in spec.initialBodies:
      if body.kind == rtHq: inc hqs
      check(name & "'s bodies are on the map",
        body.loc.x >= 0 and body.loc.y >= 0 and
        body.loc.x < spec.width and body.loc.y < spec.height)
      if body.kind == rtCow:
        checkEq(name & "'s cows are neutral", body.team, teamNeutral)
      else:
        check(name & "'s HQs belong to a side", body.team != teamNeutral)
    checkEq(name & " has exactly two HQs", hqs, 2)

    ## The spec says every map carries a tile at `MIN_WATER_ELEVATION`.
    ## `Infinity` does not — its floor is -12 — and the port follows the FILE
    ## rather than the prose (docs/RULES-BC20.md §Divergences item 11).
    var lowest = high(int)
    for e in spec.elevation: lowest = min(lowest, e)
    if name == "Infinity":
      checkEq("Infinity's real floor is -12, not MIN_WATER_ELEVATION",
        lowest, -12)
    else:
      checkEq(name & " has a tile at MIN_WATER_ELEVATION", lowest,
        MinWaterElevation)

block:
  ## The sim recomputes the symmetry on every NEUTRAL spawn from the CURRENT
  ## world; it must land on the committed value for every map, on round 1.
  for name, _ in Pinned:
    let spec = loadMap(name)
    let w = newWorld(spec, 1500)
    checkEq("the sim agrees with the converter on " & name, w.symmetry,
      spec.symmetry)

block:
  ## The committed JSON is the byte-stable form the converter emits: sorted
  ## keys, no spaces, one trailing newline. CI re-converts and diffs; this
  ## catches a hand-edit that never went through the converter at all.
  for name, _ in Pinned:
    let raw = readFile(mapPath(name))
    check(name & "'s file ends in exactly one newline",
      raw.endsWith("\n") and not raw.endsWith("\n\n"))
    check(name & "'s file is compact JSON", ", " notin raw and ": " notin raw)
    let doc = parseJson(raw)
    var keys: seq[string]
    for key, _ in doc: keys.add(key)
    var sorted = keys
    sorted.sort()
    checkEq(name & "'s keys are sorted", keys, sorted)

block:
  ## The draw is deterministic in the episode seed, distinct, and inside the
  ## pool; sides alternate every game.
  let drawn = drawMaps("mixed", 871345, 3)
  checkEq("three maps are drawn", drawn.len, 3)
  check("all distinct",
    drawn[0] != drawn[1] and drawn[1] != drawn[2] and drawn[0] != drawn[2])
  for name in drawn:
    check(name & " is in the mixed pool", name in MixedPool)
  checkEq("and the draw is deterministic", drawMaps("mixed", 871345, 3), drawn)
  for g in 0 .. 2:
    checkEq("sides alternate at game " & $g, sideAslotFor(871345, g),
      sideAslotFor(871345, 0) xor (g and 1))

block:
  ## The map card is what a doctrine plans against, and both seats see the
  ## same numbers on a symmetric map.
  let spec = loadMap("CentralLake")
  let a = spec.mapCard(0, 0)
  let b = spec.mapCard(1, 0)
  checkEq("both seats see the same HQ elevation",
    a["hq_elevation"].getInt(), b["hq_elevation"].getInt())
  checkEq("and the same separation",
    a["hq_separation"].getInt(), b["hq_separation"].getInt())
  checkEq("only the side differs", a["you_are"].getStr(), "A")
  checkEq("for the other seat", b["you_are"].getStr(), "B")
  check("the card names the soup", a["soup_tiles"].getInt() > 0)
  check("and the cows", a["cows"].getInt() >= 0)

finish("test_bc20_maps")
