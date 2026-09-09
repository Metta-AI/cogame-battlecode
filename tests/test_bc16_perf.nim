## Shard 20 of the note's list — **the bc16 perf gate**.
##
## A full 3000-round game on `6147` (45x45 = 2025 squares, the LARGEST map in
## the `bc16` variant's played pool, two archons a side at rubble mean 532.6
## with 18 neutrals) with BOTH seats on the configuration that maximises unit
## count, movement and rubble work — `opening: soldier_viper_aggro`,
## `turret_count: 0`, `guard_ratio: 0`, `rubble_clear: aggressive`,
## `retreat_hp: 0` — must complete in **<= 130 s**. The design note's
## sanctioned fix if this ever goes red is ONE config value,
## `gamesPerMatch: 3 -> 2` and then `-> 1` in the `bc16` variant, not a
## redesign.
##
## The budget arithmetic this protects: the match guard is 360 s for three
## games, so a single game must sit comfortably inside 120 s
## (`perGameBudgetSeconds`) or a hosted episode settles `deadline` instead of
## `complete`.
##
## **THE 130 s BUDGET IS ASSERTED IN RELEASE ONLY, and this is the repo's own
## precedent** (`tests/test_bc21_perf.nim`, with the reason in its header).
## The image, the wasm bundle and every hosted episode are `-d:release`; a
## debug build carries range checks, stack traces and no inlining and runs
## about seven times slower, so asserting a wall-clock budget against it would
## be measuring the wrong binary. The debug pass still plays the SAME game to
## the SAME round count with every check enabled, which is what the debug pass
## is for — and it still asserts everything except the clock.

import std/[json, monotimes, times]
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc16/[maps, rules]

const Budget = 130.0

var largest = ""
var largestTiles = 0
for name in MixedPool:
  let spec = loadMap(name)
  if spec.width * spec.height > largestTiles:
    largestTiles = spec.width * spec.height
    largest = name
echo "largest map in the bc16 mixed pool: ", largest, " (", largestTiles,
  " tiles)"
checkEq("and it is 45x45, as the design note pins", largestTiles, 45 * 45)
checkEq("named 6147", largest, "6147")

let aggro = parseReply(
  """{"sheet":{"opening":"soldier_viper_aggro","turret_count":0,
    "guard_ratio":0,"zombie_kiting":"ranged_only","den_clear_round":900,
    "parts_priority":"units","archon_spread":"split",
    "neutral_activation":"hunt","retreat_hp":0,"rubble_clear":"aggressive",
    "infection_policy":"suicide_squad"}}""", "bc16")

block:
  checkEq("the unit-maximising sheet really parsed", aggro.doctrine16.opening,
    opSoldierViperAggro)
  checkEq("with no turrets", aggro.doctrine16.turretCount, 0)
  checkEq("no guards", aggro.doctrine16.guardRatio, 0)
  checkEq("aggressive digging", aggro.doctrine16.rubbleClear, rcAggressive)
  checkEq("and nothing ever retreating", aggro.doctrine16.retreatHp, 0)

let started = getMonoTime()
let (w, outcome) = playGame(loadMap(largest), [aggro, aggro],
                            [ckBulwark, ckBulwark], 0, 0, 3000, 0)
let seconds = (getMonoTime() - started).inMilliseconds.float / 1000.0
echo "bc16 perf: ", outcome.roundsPlayed, " rounds on ", largest, " in ",
  seconds, " s (", (seconds * 1000.0) / float(max(1, outcome.roundsPlayed)),
  " ms/round), ", outcome.unitsBuilt[0] + outcome.unitsBuilt[1],
  " units built, ", w.opsUsedPeak, " ops peak, ",
  outcome.robotsAlive[0] + outcome.robotsAlive[1], " robots alive at the end"

block:
  ## The game really ran, and it really was the heavy configuration.
  check("it played a full game or ended on the ladder",
    outcome.roundsPlayed >= 400)
  check("the unit count really did grow",
    outcome.unitsBuilt[0] + outcome.unitsBuilt[1] >= 60)
  check("and the diggers really dug",
    outcome.rubbleClearedTenths[0] + outcome.rubbleClearedTenths[1] > 0)
  checkEq("and no illegal order was emitted at this setting",
    w.refusedActions, 0)
  check("no robot exceeded its DecisionOps budget",
    w.opsUsedPeak <= 2000)

when defined(release):
  check("the heaviest bc16 configuration on the largest played map finishes " &
    "in " & $Budget & " s (measured " & $seconds & " s)", seconds <= Budget)
  ## And the per-game budget the variant declares really is enough.
  check("which is inside the variant's own perGameBudgetSeconds of 120",
    seconds <= 120.0)
else:
  echo "debug build: the wall-clock budget is asserted in -d:release only " &
    "(tests/test_bc21_perf.nim's precedent). The same game, the same round " &
    "count and every other assertion still ran."

finish("test_bc16_perf")
