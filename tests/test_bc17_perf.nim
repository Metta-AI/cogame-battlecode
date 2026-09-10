## §Tests item 23 -- THE WALL-CLOCK GATE.
##
## A full 2 999-round game on `Chess` -- **64x64 with 924 neutral trees**,
## the board that maximises the per-bullet candidate count, because
## `updateBullet` queries `getAllTreesWithinRadius(checkCenter,
## NEUTRAL_TREE_MAX_RADIUS + distToFinish/2)` once per bullet per round and
## `Chess` puts the most discs inside that reach of any committed board.
##
## **MEASURED IN PHASE 20: 4.1 s in `-d:release`.** The committed budget is
## 60 s, fourteen times the measurement, because a shared CI runner is not a
## sandbox. If this ever goes red the fix is ONE CONFIG VALUE --
## `gamesPerMatch: 3 -> 2 -> 1` in the `bc17` variant -- and the design note
## says so, so nobody redesigns anything.

import std/[monotimes, times]
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, world, rules, maps]

block:
  let spec = loadMap("Chess")
  ## 64.0 x 63.999996 -- a 2017 board's extent is a float32 and the height
  ## does not round-trip to a whole number.
  check("Chess is 64x64 to float32",
    abs(float(spec.rect.width) - 64.0) < 0.001 and
      abs(float(spec.rect.height) - 64.0) < 0.001)
  checkEq("with 924 neutral trees", spec.neutralTrees, 924)
  checkEq("and two archons a side", spec.archonsPerSide, 2)
  ## The all-defaults doctrine is the configuration that put the most
  ## bullets in flight on this board of every one measured in phase 20: the
  ## alternatives that build more tanks never meet an enemy across a
  ## 56-unit archon separation and fire nothing at all.
  let sheet = defaultSheet(YearBc17)
  let started = getMonoTime()
  let (w, o) = playGame(spec, [sheet, sheet], [ck17Orchard, ck17Orchard],
                        0, 0, 3000, 0)
  let seconds = (getMonoTime() - started).inMilliseconds.int div 1000
  echo "  Chess ", o.roundsPlayed, " rounds in ", seconds, " s; ",
    o.unitsAlive[0] + o.unitsAlive[1], " robots alive at the end, peak ",
    o.peakBulletsInFlight, " bullets in flight, peak ",
    max(o.decisionOpsPeak[0], o.decisionOpsPeak[1]), " DecisionOps"
  check("the game ran to the round limit or a real end", o.roundsPlayed > 2900)
  check("in at most sixty seconds (measured 4)", seconds <= 60)
  checkEq("with no illegal order", o.refusedActions[0] + o.refusedActions[1],
    0)
  check("and no robot over its budget",
    o.decisionOpsPeak[0] < ArchonOps and o.decisionOpsPeak[1] < ArchonOps)
  check("the game was not abandoned", not o.aborted)

block:
  ## The second-heaviest board, as a cross-check that the cost is in the
  ## TREE COUNT and not in one map's quirk: `LineOfFire` carries 1 228 trees
  ## on 100x30. Measured 4.9 s.
  let spec = loadMap("LineOfFire")
  checkEq("LineOfFire carries 1228 neutral trees", spec.neutralTrees, 1228)
  let sheet = defaultSheet(YearBc17)
  let started = getMonoTime()
  let (w, o) = playGame(spec, [sheet, sheet], [ck17Orchard, ck17Orchard],
                        0, 0, 3000, 0)
  let seconds = (getMonoTime() - started).inMilliseconds.int div 1000
  echo "  LineOfFire ", o.roundsPlayed, " rounds in ", seconds, " s"
  check("in at most sixty seconds (measured 4)", seconds <= 60)
  checkEq("and no illegal order", o.refusedActions[0] + o.refusedActions[1],
    0)

finish("test_bc17_perf")
