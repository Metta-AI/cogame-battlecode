## The converted bc21 map pool: the note's pinned table reproduced from the
## committed files, the spec's own size bounds, the passability floor that
## excluded `Misdirection`, the Center tables, the recorded symmetry actually
## holding, and no bc21 map name resolving to a bc20 map file.

import std/[json, math, os, sets, strutils]
import harness
import battlecode/years/bc21/[constants, maps, world]
from battlecode/years/bc20/maps as maps20 import nil

type Row = object
  name: string
  width, height, seed: int
  symmetry: string
  ownCenters, neutrals: int
  separation: int

const Table21 = [
  Row(name: "maptestsmall", width: 32, height: 32, seed: 30,
      symmetry: "vertical", ownCenters: 1, neutrals: 0, separation: 21),
  Row(name: "Arena", width: 32, height: 32, seed: 276514,
      symmetry: "rotational", ownCenters: 1, neutrals: 6, separation: 38),
  Row(name: "Bog", width: 32, height: 32, seed: 238084,
      symmetry: "rotational", ownCenters: 1, neutrals: 4, separation: 31),
  Row(name: "FrogOrBath", width: 32, height: 32, seed: 97,
      symmetry: "vertical", ownCenters: 2, neutrals: 4, separation: 7),
  Row(name: "Smile", width: 32, height: 32, seed: 644,
      symmetry: "vertical", ownCenters: 1, neutrals: 2, separation: 25),
  Row(name: "Star", width: 35, height: 35, seed: 276,
      symmetry: "vertical", ownCenters: 1, neutrals: 4, separation: 20),
  Row(name: "Corridor", width: 33, height: 40, seed: 504317,
      symmetry: "vertical", ownCenters: 1, neutrals: 6, separation: 35),
  Row(name: "SeaFloor", width: 45, height: 32, seed: 314512,
      symmetry: "vertical", ownCenters: 1, neutrals: 6, separation: 30),
  Row(name: "quadrants", width: 40, height: 40, seed: 215957,
      symmetry: "rotational", ownCenters: 2, neutrals: 2, separation: 24),
  Row(name: "Maze", width: 45, height: 45, seed: 886488,
      symmetry: "rotational", ownCenters: 2, neutrals: 4, separation: 40),
  Row(name: "Hourglass", width: 48, height: 48, seed: 692611,
      symmetry: "vertical", ownCenters: 1, neutrals: 4, separation: 25),
  Row(name: "PaperWindmill", width: 48, height: 48, seed: 417,
      symmetry: "rotational", ownCenters: 2, neutrals: 6, separation: 21),
  Row(name: "Blotches", width: 64, height: 32, seed: 21,
      symmetry: "rotational", ownCenters: 2, neutrals: 2, separation: 15),
  Row(name: "Circles", width: 64, height: 32, seed: 47,
      symmetry: "rotational", ownCenters: 2, neutrals: 2, separation: 19),
  Row(name: "BadSnowflake", width: 50, height: 50, seed: 299876,
      symmetry: "rotational", ownCenters: 2, neutrals: 4, separation: 10),
  Row(name: "AmidstWe", width: 64, height: 64, seed: 475369,
      symmetry: "rotational", ownCenters: 1, neutrals: 4, separation: 3),
  Row(name: "Yoda", width: 64, height: 64, seed: 309048,
      symmetry: "rotational", ownCenters: 2, neutrals: 4, separation: 29),
  Row(name: "Gridlock", width: 64, height: 64, seed: 535715,
      symmetry: "vertical", ownCenters: 1, neutrals: 6, separation: 59)
]

# --- the pools ----------------------------------------------------------------
block:
  checkEq("18 maps are converted", Table21.len, 18)
  checkEq("the small pool has 6", poolNames("small").len, 6)
  checkEq("the mixed pool — the bc21 variant's — has 12",
    poolNames("mixed").len, 12)
  checkEq("the large pool has 6", poolNames("large").len, 6)
  var all0: HashSet[string]
  for pool in ["small", "mixed", "large"]:
    for name in poolNames(pool): all0.incl(name)
  checkEq("and between them they name every converted map", all0.len, 18)
  for row in Table21:
    check(row.name & " is in a pool", row.name in all0)
  for name in poolNames("small"):
    check("the small pool is a subset of the mixed one",
      name in poolNames("mixed"))
  check("an unknown pool is empty, never a silent default",
    poolNames("enormous").len == 0)

# --- the note's table, from the committed files -------------------------------
block:
  for row in Table21:
    let spec = loadMap(row.name)
    checkEq(row.name & " name", spec.name, row.name)
    checkEq(row.name & " width", spec.width, row.width)
    checkEq(row.name & " height", spec.height, row.height)
    checkEq(row.name & " seed", spec.randomSeed, row.seed)
    checkEq(row.name & " symmetry",
      ($spec.symmetry).replace("sym", "").toLowerAscii(), row.symmetry)
    checkEq(row.name & " own Centers per side (A)",
      spec.ownCenters(teamA).len, row.ownCenters)
    checkEq(row.name & " own Centers per side (B)",
      spec.ownCenters(teamB).len, row.ownCenters)
    checkEq(row.name & " neutral Centers", spec.neutralCenters().len,
      row.neutrals)
    checkEq(row.name & " Center separation", spec.centerSeparation(),
      row.separation)

# --- the spec's own bounds, and the passability floor ------------------------
block:
  for row in Table21:
    let spec = loadMap(row.name)
    check(row.name & " is 32..64 wide",
      spec.width >= MapMinWidth and spec.width <= MapMaxWidth)
    check(row.name & " is 32..64 high",
      spec.height >= MapMinHeight and spec.height <= MapMaxHeight)
    checkEq(row.name & " has a full passability array",
      spec.passability.len, spec.width * spec.height)
    var lo = 2.0
    var hi = -1.0
    for p in spec.passability:
      lo = min(lo, p)
      hi = max(hi, p)
    ## THE CHECK THAT EXCLUDED `Misdirection`: a tile at passability 0.0 gives
    ## an infinite cooldown and freezes a robot for ever.
    check(row.name & " passability is in [0.1, 1.0]", lo >= 0.1 and hi <= 1.0)
    check(row.name & " has 1..3 Centers a side",
      spec.ownCenters(teamA).len in 1 .. 3)
    check(row.name & " has at most 6 neutrals", spec.neutralCenters().len <= 6)
    for b in spec.ownCenters(teamA) & spec.ownCenters(teamB):
      checkEq(row.name & " team Centers start at 150", b.influence,
        InitialEnlightenmentCenterInfluence)
    for b in spec.initialBodies:
      checkEq(row.name & " carries only Enlightenment Centers", b.kind,
        rtEnlightenmentCenter)
      check(row.name & " every body is on the map",
        b.loc.x >= 0 and b.loc.x < spec.width and
        b.loc.y >= 0 and b.loc.y < spec.height)

# --- the recorded symmetry actually holds -------------------------------------
block:
  for row in Table21:
    let spec = loadMap(row.name)
    check(row.name & " records at least one symmetry", spec.symmetries.len > 0)
    checkEq(row.name & " displays the first one", spec.symmetry,
      spec.symmetries[0])
    for sym in spec.symmetries:
      var broken = 0
      for x in 0 ..< spec.width:
        for y in 0 ..< spec.height:
          let tx = (if sym == symHorizontal: x else: spec.width - 1 - x)
          let ty = (if sym == symVertical: y else: spec.height - 1 - y)
          if spec.passability[x + spec.width * y] !=
             spec.passability[tx + spec.width * ty]:
            inc broken
      checkEq(row.name & " " & $sym & " really holds on passability", broken, 0)

block:
  ## `world.newWorld` picks the symmetry the CHASSIS steers by: the first
  ## recorded one that maps an own Center onto an enemy one.
  for row in Table21:
    let spec = loadMap(row.name)
    let w = newWorld(spec, 1500)
    var mapped = true
    for b in spec.ownCenters(teamA):
      let mirrored = w.symmetricLoc(b.loc)
      var found = false
      for e in spec.ownCenters(teamB):
        if e.loc == mirrored: found = true
      if not found: mapped = false
    check(row.name & ": the world's symmetry maps our capitals onto theirs",
      mapped)

# --- the two years do not share a map file ------------------------------------
block:
  ## `Hourglass` and `Maze` are bc20 map names TOO — different maps, different
  ## years, different directories.
  for shared in ["Hourglass", "Maze"]:
    let path21 = mapPath(shared)
    let path20 = maps20.mapPath(shared)
    check(shared & " exists in both years", fileExists(path21) and
      fileExists(path20))
    check(shared & " resolves to DIFFERENT files", path21 != path20)
    check(shared & " has different bytes", readFile(path21) != readFile(path20))
    let a = loadMap(shared)
    let b = maps20.loadMap(shared)
    check(shared & " is not even the same size in the two years",
      a.width != b.width or a.height != b.height or
      a.randomSeed != b.randomSeed)

# --- the draw ------------------------------------------------------------------
block:
  for seed in [0, 1, 7, 871345, 2_000_000_000]:
    let drawn = drawMaps("mixed", seed, 3)
    checkEq("three maps are drawn", drawn.len, 3)
    check("and they are distinct",
      drawn[0] != drawn[1] and drawn[1] != drawn[2] and drawn[0] != drawn[2])
    for name in drawn:
      check(name & " is in the mixed pool", name in poolNames("mixed"))
    checkEq("the draw is deterministic in the seed", drawMaps("mixed", seed, 3),
      drawn)
  checkEq("sides alternate every game", sideAslotFor(0, 0), 1 - sideAslotFor(0, 1))
  checkEq("and again", sideAslotFor(0, 1), 1 - sideAslotFor(0, 2))
  checkEq("seed bit 8 picks who starts as A", sideAslotFor(256, 0), 1)
  checkEq("and its complement", sideAslotFor(0, 0), 0)

# --- the map card ---------------------------------------------------------------
block:
  let spec = loadMap("PaperWindmill")
  let card = spec.mapCard(0, 0)
  checkEq("the card names the map", card["map"].getStr(), "PaperWindmill")
  checkEq("with its size", card["width"].getInt(), 48)
  checkEq("who we are", card["you_are"].getStr(), "A")
  checkEq("our own Centers", card["your_centers"].len, 2)
  checkEq("how many of theirs", card["enemy_centers"].getInt(), 2)
  checkEq("every neutral Center, with its influence",
    card["neutral_centers"].len, 6)
  checkEq("the separation", card["center_separation"].getInt(), 21)
  check("and a passability summary",
    card["passability"]["mean"].getFloat() > 0.0)
  let other0 = spec.mapCard(1, 0)
  checkEq("the other seat is B", other0["you_are"].getStr(), "B")
  checkEq("and sees the same aggregate numbers",
    other0["center_separation"].getInt(), card["center_separation"].getInt())
  checkEq("and the same neutral Centers",
    other0["neutral_centers"], card["neutral_centers"])

finish("bc21 maps")
