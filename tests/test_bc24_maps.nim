## The committed bc24 map set: every map re-converts identically from the
## pinned `.map24` (that byte-diff is `ci.yml`'s job; this shard asserts the
## FACTS the design note pinned), every size inside 20..60, three spawn-zone
## centres a team whose 3x3 is all spawn zone and which are pairwise at least
## six apart, the centres re-deriving in the engine's index-ascending
## interleaved order with `flag.id == tile index`, no bc24 map name resolving
## to another year's file, and the seed the docker smoke passes drawing
## exactly `Yinyang`.

import std/[os, sets, strutils, tables]
import harness
import bc24_fixture

## Every row is (width, height, seed, symmetry, dam, water, walls, piles,
## crumb total), read out of the real `.map24` flatbuffers and pinned in the
## design note's own table.
const Pinned = {
  "DefaultSmall": (31, 31, 664, "rotation", 133, 22, 36, 34, 8200),
  "Yinyang": (31, 31, 21, "rotation", 133, 154, 24, 48, 6400),
  "BreadPudding": (30, 30, 938, "vertical", 98, 110, 108, 54, 5800),
  "Rivers": (30, 30, 363, "rotation", 66, 124, 60, 24, 4200),
  "Tunnels": (30, 30, 890, "vertical", 16, 138, 124, 40, 6600),
  "Occulus": (30, 30, 155, "rotation", 78, 110, 100, 62, 11400),
  "GaltonBoard": (31, 30, 817, "vertical", 60, 84, 40, 216, 37800),
  "StackGame": (31, 30, 31, "vertical", 76, 104, 112, 92, 9200),
  "Alligator": (40, 31, 675, "rotation", 40, 138, 168, 42, 12600),
  "Randy": (41, 31, 392, "vertical", 64, 290, 136, 95, 17000),
  "Anchor": (41, 32, 294, "vertical", 201, 60, 84, 67, 20100),
  "DefaultMedium": (45, 31, 482, "rotation", 46, 249, 54, 31, 7900),
  "Gauntlet": (45, 30, 36, "vertical", 198, 212, 104, 46, 5600),
  "HungerGames": (50, 30, 418, "horizontal", 112, 124, 80, 94, 22200),
  "Soccer": (53, 30, 810, "vertical", 60, 124, 182, 22, 6200),
  "DefaultLarge": (59, 31, 187, "vertical", 70, 196, 34, 53, 9100),
  "Bunkers": (40, 40, 228, "rotation", 44, 132, 110, 22, 5600),
  "Fountain": (40, 40, 41, "horizontal", 86, 358, 170, 34, 5400),
  "CH3353C4K3F4CT0RY": (45, 45, 7, "vertical", 121, 56, 101, 264, 26400),
  "Islands": (49, 49, 349, "rotation", 97, 396, 86, 104, 11600),
  "Battlecode24": (59, 59, 884, "horizontal", 118, 446, 640, 243, 42500),
  "DefaultHuge": (59, 59, 0, "rotation", 111, 90, 140, 36, 7400)
}.toTable

let allNames = @SmallPool & @MixedPool & @LargePool
var distinct0 = initHashSet[string]()
for n in allNames: distinct0.incl(n)

block:
  checkEq("twenty-two converted maps", distinct0.len, 22)
  checkEq("and the note pins every one of them", Pinned.len, 22)
  for n in distinct0:
    check(n & " is in the note's table", n in Pinned)
  checkEq("the small pool has six", SmallPool.len, 6)
  checkEq("the mixed pool -- the bc24 variant's -- has twelve",
    MixedPool.len, 12)
  checkEq("and the reserved large pool six", LargePool.len, 6)

block:
  for name in distinct0:
    let spec = loadMap(name)
    let want = Pinned[name]
    checkEq(name & " width", spec.width, want[0])
    checkEq(name & " height", spec.height, want[1])
    checkEq(name & " seed", spec.randomSeed, want[2])
    checkEq(name & " symmetry",
      ($spec.symmetry).replace("sym", "").toLowerAscii(), want[3])
    var dam, water, walls = 0
    for v in spec.dam:
      if v: dam += 1
    for v in spec.water:
      if v: water += 1
    for v in spec.walls:
      if v: walls += 1
    checkEq(name & " dam tiles", dam, want[4])
    checkEq(name & " water tiles", water, want[5])
    checkEq(name & " wall tiles", walls, want[6])
    checkEq(name & " crumb piles", spec.crumbs.len, want[7])
    var total = 0
    for c in spec.crumbs: total += c.amount
    checkEq(name & " crumb total", total, want[8])
    check(name & " is inside 20..60 in both dimensions",
      spec.width >= MapMinWidth and spec.width <= MapMaxWidth and
      spec.height >= MapMinHeight and spec.height <= MapMaxHeight)

# --- the spawn zones and the flags ------------------------------------------
block:
  for name in distinct0:
    let spec = loadMap(name)
    let w = newWorld(spec, 2000)
    var perTeam = [0, 0]
    for i in 0 ..< spec.width * spec.height:
      if w.spawnZones[i] == 1: perTeam[0] += 1
      elif w.spawnZones[i] == 2: perTeam[1] += 1
    checkEq(name & ": twenty-seven A spawn tiles (three 3x3 zones)",
      perTeam[0], 27)
    checkEq(name & ": twenty-seven B spawn tiles", perTeam[1], 27)
    for team in [teamA, teamB]:
      let centres = spec.centersOf(team)
      for c in centres:
        var all = true
        for dx in -1 .. 1:
          for dy in -1 .. 1:
            let l = loc(c.x + dx, c.y + dy)
            if not w.onTheMap(l) or w.getSpawnZone(l) != ord(team) + 1:
              all = false
        check(name & ": every centre's 3x3 is all spawn zone", all)
      for i in 0 .. 2:
        for j in i + 1 .. 2:
          check(name & ": own centres are pairwise at least six apart",
            centres[i].distanceSquaredTo(centres[j]) >= MinFlagSpacingSquared)

block:
  for name in distinct0:
    let spec = loadMap(name)
    ## The engine re-derives the centres index-ascending and interleaves A
    ## into the even slots; the converter records exactly that order, and it
    ## is what fixes the flag ids.
    for slot in 0 .. 4:
      if slot mod 2 == 0 and slot + 2 <= 4:
        let a = spec.spawnCenters[slot]
        let b = spec.spawnCenters[slot + 2]
        check(name & ": A's centres are in ascending tile-index order",
          a.x + a.y * spec.width < b.x + b.y * spec.width)
      if slot mod 2 == 1 and slot + 2 <= 5:
        let a = spec.spawnCenters[slot]
        let b = spec.spawnCenters[slot + 2]
        check(name & ": B's centres are in ascending tile-index order",
          a.x + a.y * spec.width < b.x + b.y * spec.width)
    let w = newWorld(spec, 2000)
    checkEq(name & ": six flags", w.allFlags.len, 6)
    var idsOk = true
    var order = true
    var last = -1
    for f in w.allFlags:
      if f.id != f.startLoc.x + f.startLoc.y * spec.width: idsOk = false
      if f.id <= last: order = false
      last = f.id
    check(name & ": flag.id IS the tile index", idsOk)
    check(name & ": and the flags are created in ascending index order", order)
    var perTeam = [0, 0]
    for f in w.allFlags: perTeam[ord(f.team)] += 1
    checkEq(name & ": three flags a side", perTeam, [3, 3])

# --- no name collides with another year -------------------------------------
block:
  ## THREE bc24 NAMES ARE ALSO bc26 NAMES -- `DefaultSmall`, `DefaultMedium`
  ## and `DefaultLarge` -- exactly as `Maze` and `Hourglass` already exist
  ## twice across the other years. What must hold is not that the names are
  ## unique but that a bc24 draw can never resolve to another year's FILE.
  var shared: seq[string]
  for name in distinct0:
    for other in ["bc26", "bc20", "bc21"]:
      if fileExists("data" / "maps" / other / (name & ".json")):
        shared.add(other & "/" & name)
  check("some names really are shared across years, so this matters",
    shared.len > 0)
  for name in distinct0:
    check(name & " resolves under data/maps/bc24",
      mapPath(name).contains("maps" / "bc24"))
    let spec = loadMap(name)
    checkEq(name & ": the loaded map is the one that was asked for",
      spec.name, name)
    checkEq(name & ": with the bc24 file's own size",
      (spec.width, spec.height), (Pinned[name][0], Pinned[name][1]))

# --- the smoke seed ---------------------------------------------------------
const SmokeSeed* = 1000
  ## The seed `ci.yml`'s bc24 docker-smoke episode passes. Pinned HERE so the
  ## smoke's map cannot drift silently.
block:
  let drawn = drawMaps("small", SmokeSeed, 1)
  checkEq("the docker-smoke seed draws exactly Yinyang", drawn, @["Yinyang"])
  checkEq("and Yinyang is in the small pool", "Yinyang" in SmallPool, true)

block:
  let three = drawMaps("mixed", 871345, 3)
  checkEq("a three-map draw returns three", three.len, 3)
  check("all distinct", three[0] != three[1] and three[1] != three[2] and
    three[0] != three[2])
  checkEq("and it is deterministic in the seed", drawMaps("mixed", 871345, 3),
    three)

block:
  checkEq("side A alternates every game", [sideAslotFor(4, 0),
    sideAslotFor(4, 1), sideAslotFor(4, 2)], [0, 1, 0])
  checkEq("and the seed decides who starts", [sideAslotFor(256, 0),
    sideAslotFor(256, 1)], [1, 0])

finish("bc24 maps")
