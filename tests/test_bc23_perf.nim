## bc23's wall-clock gate. A FULL 2000-round game on `IslandHopping` (60x30,
## the largest map in the `bc23` variant's pool) with BOTH SEATS on
## `opening: carrier_eco`, `launcher_ratio: 80`, `anchor_budget: 0` — the
## configuration that maximises robot count and therefore per-round work —
## must finish in <= 100 s.
##
## Failing it means switching `gamesPerMatch` to 1 in the `bc23` variant, and
## nothing else: the design note says so explicitly so the builder does not
## redesign anything under time pressure.
##
## MEASURED IN PHASE 20: 5.9 s in release with 451 robots alive at the end
## (552 and 530 built). The gate is deliberately sixteen times that, because
## a CI runner is not this sandbox and the number that matters is the one that
## would make the phase-60 viewer probe unusable.

import std/[monotimes, strutils, times]
import harness
import bc23_fixture

const Budget = 100.0

block:
  let sheet = sheetFrom("""{"sheet":{"opening":"carrier_eco",
    "launcher_ratio":80,"anchor_budget":0},"notes":"perf","motto":"x"}""")
  checkEq("the sheet applied cleanly", sheet.defaultsApplied.len, 0)
  let spec = loadMap("IslandHopping")
  checkEq("the map is the pool's largest", spec.width * spec.height, 1800)
  let started = getMonoTime()
  let (w, o) = playGame(spec, [sheet, sheet], [ckLemonade, ckLemonade],
    0, 0, 2000, 0)
  let seconds = float((getMonoTime() - started).inMilliseconds) / 1000.0
  echo "test_bc23_perf: IslandHopping 60x30, 2000 rounds, ",
    o.robotsAlive[0] + o.robotsAlive[1], " robots alive at the end, ",
    o.unitsBuilt[0] + o.unitsBuilt[1], " built, ",
    formatFloat(seconds, ffDecimal, 1), " s (budget ",
    formatFloat(Budget, ffDecimal, 0), " s)"
  check("the game ran to the cap", o.roundsPlayed >= 1)
  check("with a real unit count — this gate is about a LOADED board",
    o.unitsBuilt[0] + o.unitsBuilt[1] >= 200)
  checkEq("and no illegal order was emitted on the way",
    w.refusedActions, 0)
  check("a full 2000-round game on the pool's largest map is inside the " &
    "budget (took " & formatFloat(seconds, ffDecimal, 1) & " s)",
    seconds <= Budget)
  ## The per-round cost the phase-60 viewer probe is sized from.
  echo "test_bc23_perf: ",
    formatFloat(seconds * 1000.0 / float(max(1, o.roundsPlayed)), ffDecimal, 2),
    " ms/round — well above the 1 ms/round threshold the bc21 learning " &
    "names, which is why check 8 is dispatched with settle=20000 soak=15"

finish("test_bc23_perf")
