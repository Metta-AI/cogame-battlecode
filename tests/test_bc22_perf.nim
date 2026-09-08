## The wall-clock gate.
##
## §Tests item 19: a full 2000-round game on `fisherman` (45x35 = 1 575 squares,
## the largest map in the played `mixed` pool, THREE archons a side at rubble
## mean 13.9 — i.e. the most build actions a round on the fastest ground, which
## is what maximises the robot census) with BOTH seats on the configuration
## that maximises robot count and therefore per-round work, in <= 100 s.
##
## MEASURED IN PHASE 20: 0.9 s. If this ever goes red the fix is ONE CONFIG
## VALUE — `gamesPerMatch: 3 -> 1` in the `bc22` variant — and the design note
## says so, so nobody redesigns anything.

import std/[json, monotimes, times]
import harness
import bc22_fixture

block:
  let heavy = validate(%*{"sheet": {
    "opening": "miner_eco", "miner_count_curve": "heavy",
    "mine_floor": 0, "retreat_hp": 0}}, "bc22")
  checkEq("the heaviest doctrine is what it says", heavy.doctrine22.mineFloor,
    0)
  let spec = loadMap("fisherman")
  checkEq("fisherman is 45x35", spec.width * spec.height, 45 * 35)
  checkEq("with three archons a side", spec.archonsPerSide(), 3)
  let started = getMonoTime()
  let (w, o) = playGame(spec, [heavy, heavy], [ckWololo, ckWololo], 0, 0,
                        2000, 0)
  let seconds = (getMonoTime() - started).inMilliseconds.int div 1000
  echo "  fisherman 2000 rounds in ", seconds, " s, ",
    o.robotsAlive[0] + o.robotsAlive[1], " robots alive at the end, peak ",
    w.opsUsedPeak, " DecisionOps"
  checkEq("the whole game was played", o.roundsPlayed, 2000)
  check("in at most a hundred seconds", seconds <= 100)
  checkEq("with no illegal order", w.refusedActions, 0)
  check("and no robot over its budget", w.opsUsedPeak <= DecisionOpsArchon)

finish("test_bc22_perf")
