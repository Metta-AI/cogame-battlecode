## The committed converted maps: shape, symmetry pairing, and the pools the
## design note pins. When the pinned engine checkout is present the shard also
## re-converts every map and byte-diffs it.

import std/[os, osproc, strutils, tables]
import harness
import battlecode/years/bc26/[constants, maps, world]

let engineDir = getEnv("BC_ENGINE_DIR")
if engineDir.len > 0 and dirExists(engineDir):
  let (output, code) = execCmdEx(
    "python3 tools/convert_maps.py --engine " & quoteShell(engineDir) &
    " --out data/maps/bc26 --check")
  check("every committed map re-converts identically: " & output.strip(),
    code == 0)
else:
  echo "BC_ENGINE_DIR unset; skipping the re-conversion byte-diff"

## The sizes and symmetries the design note pins, map for map.
const Expected = {
  "DefaultSmall": (30, 30, symRotational),
  "arrows": (30, 30, symRotational),
  "closeup": (30, 30, symRotational),
  "toomuchcheese": (30, 30, symRotational),
  "cheesefarm": (30, 30, symHorizontal),
  "dirtfulcat": (30, 30, symVertical),
  "ZeroDay": (40, 34, symRotational),
  "knifefight": (40, 40, symVertical),
  "whatsthecatdoin": (40, 40, symRotational),
  "thunderdome": (45, 35, symRotational),
  "DefaultMedium": (45, 45, symRotational),
  "mercifullattice": (41, 35, symRotational),
  "DefaultLarge": (60, 60, symRotational),
  "Nofreecheese": (60, 60, symRotational),
  "averystrangespace": (60, 60, symRotational),
  "safelycontained": (60, 60, symVertical),
  "streetsofnewyork": (60, 60, symVertical),
  "uneruesansfin": (60, 60, symRotational)
}.toTable

checkEq("small pool size", SmallPool.len, 6)
checkEq("mixed pool size", MixedPool.len, 12)
checkEq("large pool size", LargePool.len, 6)
for name in SmallPool:
  check("the small pool is a subset of the mixed pool", name in MixedPool)

## The four maps that do NOT exist at engine.1.2.5 must not be in any pool:
## they landed later on master.
for absent in ["Stash", "uneasy_alliance", "Excavation", "RUN"]:
  check(absent & " is not in any pool",
    absent notin MixedPool and absent notin LargePool)
  check(absent & " has no converted map", not fileExists(mapPath(absent)))

for name, want in Expected:
  let spec = loadMap(name)
  checkEq(name & " name", spec.name, name)
  checkEq(name & " width", spec.width, want[0])
  checkEq(name & " height", spec.height, want[1])
  checkEq(name & " symmetry", spec.symmetry, want[2])
  check(name & " has cheese mines", spec.cheeseMines.len > 0)
  check(name & " has an even number of cheese mines",
    spec.cheeseMines.len mod 2 == 0)
  check(name & " has cat waypoints", spec.catWaypointIds.len > 0)
  for i, catId in spec.catWaypointIds:
    check(name & " cat " & $catId & " has at least one waypoint",
      spec.catWaypointVecs[i].len > 0)

  ## Cheese mines are symmetry-PAIRED: every mine's mirror is also a mine.
  ## Without that the paired spawn in `spawnCheese` has nothing to pair to.
  let w = newWorld(spec, GameMaxNumberOfRounds)
  var paired = true
  for m in w.cheeseMines:
    if not w.hasCheeseMine(w.symmetryLocation(m.loc)): paired = false
  check(name & " cheese mines are symmetry-paired", paired)

  ## One rat king per team, and an EVEN number of cats.
  var kings = [0, 0]
  var cats = 0
  for body in spec.initialBodies:
    if body.unit == utRatKing: kings[ord(body.team)] += 1
    elif body.unit == utCat: inc cats
  checkEq(name & " team A rat kings", kings[0], NumberInitialRatKings)
  checkEq(name & " team B rat kings", kings[1], NumberInitialRatKings)
  check(name & " has an even number of cats", cats > 0 and cats mod 2 == 0)

## The draw: distinct maps, deterministic in the seed, and sides alternate.
for seed in [1, 871345, 99, 1048576]:
  let picked = drawMaps("mixed", seed, 3)
  checkEq("draw returns three maps", picked.len, 3)
  check("the three maps are distinct",
    picked[0] != picked[1] and picked[1] != picked[2] and picked[0] != picked[2])
  checkEq("the draw is deterministic", picked, drawMaps("mixed", seed, 3))
  check("sides alternate", sideAslotFor(seed, 0) != sideAslotFor(seed, 1))
  check("sides alternate back", sideAslotFor(seed, 0) == sideAslotFor(seed, 2))

finish("test_maps")
