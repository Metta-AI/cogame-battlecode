## THE COMPETENCE GATE, with an inverted control.
##
## `spaark` vs `spaark` on the all-defaults sheet, 3 seeds x 2 `small` maps =
## six games. Nothing may collapse early and every seat must have PLAYED: it
## must have built robots, built and upgraded towers, coloured a real share of
## the map, earned chips, mined paint and stayed off the starvation floor —
## and across the two seats at least one Special Resource Pattern must have
## completed AND STAYED ACTIVE for fifty rounds, because a bc25 game where
## nobody ever lands a resource pattern is not this game being played.
##
## THE SAME GATE IS THEN RUN AS A SUBPROCESS AGAINST `-d:bc25BrokenChassis`
## AND MUST COME BACK RED. A gate that cannot fail is not a gate.
##
## THE MAPS ARE `Justice` AND `Filter`. They are the two `small` maps on which
## a resource pattern is possible at all: `areaIsPaintable` needs a 5x5 with no
## wall and no ruin anywhere in it, and `DefaultSmall`, `CastleDefense` and
## `Paintball` have ZERO such tiles (measured, all three). `Justice` has six
## and `Filter` fifty-six. That is a fact about the 2025 map set, not about the
## chassis, and it is why the gate names its maps.
##
## MEASURED, NOT GUESSED (2026-09-07, this tree, `-d:release`):
##
##   healthy mirror  towers built  2..4      upgraded 2..7  robots built 172..404
##                   coverage      165..478 permille        chips earned 130k..263k
##                   paint mined   55k..65k                 starvation 1..5 %
##                   SRP rounds active across the pair 3346..4766
##   broken control  towers built  0         upgraded 0..1  robots built 103..206
##                   coverage      0..44 permille           chips earned 60000
##                   paint mined   20k..28k                 starvation 4..8 %
##                   SRP rounds active 0
##
## The committed thresholds sit between the two, with margin, and never below
## the design note's floor.

import std/[os, osproc, strutils]
import harness
import bc25_fixture

const
  GateMaps = ["Justice", "Filter"]
  GateSeeds = [1, 2, 3]

  MinRobotsBuilt = 8          ## note floor 8; healthy 172+, broken 103+
  MinTowersBuilt = 2          ## note floor 2; healthy 2+, broken 0
  MinTowersUpgraded = 2       ## note floor 1; healthy 2+, broken 0..1
  MinCoveragePermille = 120   ## note floor 120; healthy 165+, broken 0..44
  MinChipsEarned = 90_000     ## note floor 4000; healthy 130k+, broken 60000
  MinPaintMined = 40_000      ## note floor 3000; healthy 55k+, broken 20k..28k
  MaxStarvedPercent = 25      ## note floor 25; healthy 1..5 %, broken 4..8 %
  MinSrpRoundsActive = 50     ## note floor: one pattern, fifty rounds

proc runGate(): int =
  ## Returns the number of failed assertions, so the broken control can be run
  ## as a subprocess and its exit code read.
  var failed = 0
  var srpRoundsAcrossThePair = 0
  var lateEnough = 0
  for mapName in GateMaps:
    for seed in GateSeeds:
      let spec = loadMap(mapName)
      let (w, o) = playGame(spec, defaultSheets(), [ckSpaark, ckSpaark],
        0, seed and 1, 2000, 0)
      let label = mapName & " s" & $seed

      ## Nothing may collapse early.
      if o.roundsPlayed >= 2000 or
          (o.endReason == "paint_enough_area" and o.roundsPlayed > 600):
        lateEnough += 1
      if o.endReason == "destroy_all_units" and o.roundsPlayed <= 600:
        echo "GATE ", label, ": destroy_all_units at round ", o.roundsPlayed
        failed += 1

      for seat in 0 .. 1:
        template want(name: string, got, floor: int) =
          if got < floor:
            echo "GATE ", label, " seat ", seat, ": ", name, " = ", got,
              " (want >= ", floor, ")"
            failed += 1
        want("robots built", o.robotsBuilt[seat], MinRobotsBuilt)
        want("towers built", o.towersBuilt[seat], MinTowersBuilt)
        want("towers upgraded", o.towersUpgraded[seat], MinTowersUpgraded)
        want("coverage permille", o.coveragePermille[seat],
          MinCoveragePermille)
        want("chips earned", o.chipsEarned[seat], MinChipsEarned)
        want("paint mined", o.paintMined[seat], MinPaintMined)
        let rounds = max(1, w.stats.robotRounds[
          (if seat == o.sideAslot: 0 else: 1)])
        let starved = o.robotRoundsStarved[seat] * 100 div rounds
        if starved > MaxStarvedPercent:
          echo "GATE ", label, " seat ", seat, ": ", starved,
            " % of robot-rounds at zero paint (want <= ", MaxStarvedPercent,
            ")"
          failed += 1
        srpRoundsAcrossThePair += o.srpRoundsActive[seat]

  if lateEnough < 5:
    echo "GATE: only ", lateEnough,
      " of 6 games reached round 2000 or won on paint after round 600"
    failed += 1
  if srpRoundsAcrossThePair < MinSrpRoundsActive:
    echo "GATE: ", srpRoundsAcrossThePair,
      " SRP-rounds active across the pair (want >= ", MinSrpRoundsActive, ")"
    failed += 1
  failed

when defined(bc25BrokenChassis):
  ## Compiled as the NEGATIVE CONTROL: run the gate and exit non-zero when it
  ## PASSES, so the parent's `execCmd` reads 0 only if the control really
  ## failed the gate.
  let broken = runGate()
  if broken > 0:
    echo "the broken chassis failed the gate on ", broken, " assertions"
    quit(0)
  echo "THE BROKEN CHASSIS PASSED THE GATE"
  quit(1)
else:
  checkEq("the real chassis passes the competence gate", runGate(), 0)

  block:
    ## THE INVERTED CONTROL. Compile this same file with
    ## `-d:bc25BrokenChassis` — a `spaark` variant whose soldiers stop
    ## painting the tile under themselves, so the clan bleeds paint on neutral
    ## ground and starves — and REQUIRE the gate to come back red.
    let nim = findExe("nim")
    if nim.len == 0:
      echo "NOTE: no nim on PATH; the negative control cannot be built"
      check("a nim compiler is available to build the negative control",
        false)
    else:
      let cmd = nim & " r --hints:off -d:release -d:bc25BrokenChassis" &
        " --path:src --path:tests tests/test_bc25_survival.nim"
      let code = execCmd(cmd)
      checkEq("the KNOWN-BROKEN chassis is failed by the same gate", code, 0)

  finish("test_bc25_survival")
