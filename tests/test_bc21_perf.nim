## THE bc21 PERF GATE.
##
## A full 1500-round game on `PaperWindmill` (48x48, the largest map in the
## `bc21` variant's pool) with BOTH seats on `opening: muck_spam`,
## `muck_ratio: 90` — the configuration that maximises unit count, because
## 2021 has no unit cap and a muckraker costs one influence — must complete in
## <= 75 s. The design note's sanctioned fix if this ever goes red is ONE
## config value, `gamesPerMatch: 3 -> 1` in the `bc21` variant, not a redesign.
##
## The budget arithmetic this protects: the match guard is 340 s for three
## games, so a single game must sit comfortably inside 110 s
## (`perGameBudgetSeconds`) or a hosted episode settles `deadline` instead of
## `complete`.
##
## THE 75 s BUDGET IS ASSERTED IN RELEASE ONLY. The image, the wasm bundle and
## every hosted episode are `-d:release`; a debug build carries range checks,
## stack traces and no inlining and runs about seven times slower, so asserting
## a wall-clock budget against it would be measuring the wrong binary. The
## debug pass still plays the same game to the same round count with every
## check enabled, which is what the debug pass is for.

import std/[monotimes, times]
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc21/[maps, rules]

const Budget = 75.0

var largest = ""
var largestTiles = 0
for name in MixedPool:
  let spec = loadMap(name)
  if spec.width * spec.height > largestTiles:
    largestTiles = spec.width * spec.height
    largest = name
echo "largest map in the bc21 mixed pool: ", largest, " (", largestTiles,
  " tiles)"
check("and it is 48x48, as the design note pins", largestTiles == 48 * 48)
check("PaperWindmill is one of the two that size",
  "PaperWindmill" in MixedPool)

proc timeGame(sheets: array[2, Sheet], mapName: string,
              rounds: int): (float, GameOutcome21) =
  let started = getMonoTime()
  let (_, outcome) = playGame(loadMap(mapName), sheets,
    [ckCaliforniaRoll, ckCaliforniaRoll], 0, 0, rounds, 0)
  ((getMonoTime() - started).inMilliseconds.float / 1000.0, outcome)

let muckSpam = parseReply(
  """{"sheet":{"opening":"muck_spam","muck_ratio":90,"slanderer_ratio":5}}""",
  "bc21")
let defaults = baselineSheet("bc21", blCaliforniaRoll)

block:
  let (seconds, outcome) = timeGame([muckSpam, muckSpam], "PaperWindmill", 1500)
  echo "muck-spam mirror on PaperWindmill: ", outcome.roundsPlayed,
    " rounds in ", seconds, " s, ", outcome.unitsAlive, " units alive"
  checkEq("it really ran to the cap", outcome.roundsPlayed, 1500)
  check("and the unit count really did explode — no unit cap in 2021",
    outcome.unitsBuilt[0] + outcome.unitsBuilt[1] >= 1000)
  when defined(release):
    check("the worst case plays a full game in <= 75 s (" & $seconds & " s)",
      seconds <= Budget)
  else:
    echo "(debug build: the 75 s budget is a release-only assertion)"

block:
  ## The default doctrine on the same map, which is what a hosted episode
  ## actually plays.
  let (seconds, outcome) = timeGame([defaults, defaults], "PaperWindmill", 1500)
  echo "the default mirror on PaperWindmill: ", outcome.roundsPlayed,
    " rounds in ", seconds, " s"
  when defined(release):
    check("the default mirror is inside the budget (" & $seconds & " s)",
      seconds <= Budget)

block:
  ## The `docker-smoke` bc21 episode itself: 400 rounds on `Arena`, which must
  ## finish in seconds and still outlast the viewer smoke's 10 s soak.
  let (seconds, outcome) = timeGame([defaults, defaults], "Arena", 400)
  echo "the docker-smoke episode (Arena, 400 rounds): ", seconds, " s"
  checkEq("it plays all 400 rounds", outcome.roundsPlayed, 400)
  when defined(release):
    check("in well under the smoke's own budget (" & $seconds & " s)",
      seconds <= 45.0)

finish("bc21 perf")
