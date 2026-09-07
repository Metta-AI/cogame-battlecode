## THE bc24 PERF GATE.
##
## A full 2000-round game on `DefaultLarge` (59x31, the largest map in the
## `bc24` variant's `mixed` pool) with BOTH seats on
## `specialisation_split: build`, `trap_budget: 60`, `water_dig_policy: moat` --
## the configuration that maximises per-turn work -- must complete in <= 90 s.
## The design note's sanctioned fix if this ever goes red is ONE config value,
## `gamesPerMatch: 3 -> 1` in the `bc24` variant, not a redesign.
##
## The budget arithmetic this protects: the match guard is 340 s for three
## games, so a single game must sit comfortably inside 110 s
## (`perGameBudgetSeconds`) or a hosted episode settles `deadline` instead of
## `complete`.
##
## THE 90 s BUDGET IS ASSERTED IN RELEASE ONLY. The image, the wasm bundle and
## every hosted episode are `-d:release`; a debug build carries range checks,
## stack traces and no inlining and runs about seven times slower, so asserting
## a wall-clock budget against it would be measuring the wrong binary. The
## debug pass still plays the same game to the same round count with every
## check enabled, which is what the debug pass is for.
##
## bc24's cost is FLAT: exactly one hundred duck-turns a round, always, because
## the roster is fixed at fifty a side and jailed ducks still take (cheap)
## turns. The enforced worst case is 2 500 DecisionOps a turn, so 2.5e5 a round
## and 5e8 for a whole game; the realistic average is two orders of magnitude
## below that, and this gate is what keeps the claim honest.

import std/[monotimes, times]
import harness
import battlecode/sheet
import battlecode/years/bc24/[maps, rules]

const Budget = 90.0

var largest = ""
var largestTiles = 0
for name in MixedPool:
  let spec = loadMap(name)
  if spec.width * spec.height > largestTiles:
    largestTiles = spec.width * spec.height
    largest = name
echo "largest map in the bc24 mixed pool: ", largest, " (", largestTiles,
  " tiles)"
checkEq("and it is DefaultLarge", largest, "DefaultLarge")
checkEq("59 x 31", largestTiles, 59 * 31)

let worstCase = parseReply("""{"sheet":{"specialisation_split":"build",
  "trap_budget":60,"water_dig_policy":"moat"}}""", YearBc24)
checkEq("the worst-case doctrine parsed without a repair",
  worstCase.defaultsApplied.len, 0)

let started = getMonoTime()
let (_, outcome) = playGame(loadMap(largest), [worstCase, worstCase],
  [ckGoneSharkin, ckGoneSharkin], 0, 0, 2000, 0)
let seconds = (getMonoTime() - started).inMilliseconds.float / 1000.0
echo "bc24 perf: ", largest, " ", outcome.roundsPlayed, " rounds in ",
  seconds, " s (", seconds * 1000.0 / float(max(1, outcome.roundsPlayed)),
  " ms/round)"

check("the game really was played to the end or to a capture",
  outcome.roundsPlayed >= 800)
check("and both flocks were on the board",
  outcome.ducksSpawned[0] >= 45 and outcome.ducksSpawned[1] >= 45)

when defined(release):
  check("a full worst-case bc24 game fits in " & $Budget & " s (" &
    $seconds & " s)", seconds <= Budget)
  check("and comfortably inside perGameBudgetSeconds = 110",
    seconds <= 110.0)
else:
  echo "bc24 perf: debug build; the wall-clock budget is asserted in release"

finish("bc24 perf")
