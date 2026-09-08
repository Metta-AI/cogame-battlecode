## The bc25 wall-clock gate: a full 2000-round game on `DefaultLarge` (50x30,
## the largest map in the variant's own `mixed` pool) with BOTH seats on the
## configuration that maximises tower count and therefore per-round work --
## `opening: tower_rush`, `srp_priority: 100`, `defense_tower_chokes: early`.
##
## Failing this means switching `gamesPerMatch` to 1 in the `bc25` variant,
## and the design note says so in advance so nobody redesigns anything.
##
## MEASURED on a GitHub-hosted runner class in `-d:release`: see the printed
## line. The gate is 90 s; the debug pass is exempt, because a debug build
## with every range check on is three to five times slower and says nothing
## about the shipped binary.

import std/[monotimes, strutils, times]
import harness
import bc25_fixture

const Budget = 90.0

let sheet = parseReply("""{"sheet":{"opening":"tower_rush",
  "srp_priority":100,"defense_tower_chokes":"early"}}""", "bc25")

block:
  checkEq("the perf sheet really applied", sheet.defaultsApplied.len, 0)
  let started = getMonoTime()
  let (w, o) = playGame(loadMap("DefaultLarge"), [sheet, sheet],
    [ckSpaark, ckSpaark], 0, 0, 2000, 0)
  let seconds = float((getMonoTime() - started).inMilliseconds) / 1000.0
  echo "bc25 perf: DefaultLarge 50x30, ", o.roundsPlayed, " rounds in ",
    formatFloat(seconds, ffDecimal, 2), " s (", o.roundsPlayed, " rounds, ",
    w.execOrder.len, " units alive at the end, peak DecisionOps ",
    w.opsUsedPeak, ")"
  check("the game ran to its own end", o.roundsPlayed >= 2000 or
    o.endReason == "paint_enough_area" or o.endReason == "destroy_all_units")
  checkEq("with no illegal order", w.refusedActions, 0)
  when defined(release):
    check("a full 2000-round game on the biggest played map is under 90 s",
      seconds <= Budget)
  else:
    echo "NOTE: the 90 s gate is release-only; this was a debug run"

finish("test_bc25_perf")
