## THE ECONOMIC-SURVIVAL GATE, with an inverted control that MUST FAIL.
##
## §Tests item 17, and the LEARNINGS pin. The key design point is bc22-specific
## and easy to get wrong: **in this year the map's lead is finite unless you
## leave some behind**, so a chassis that strip-mines looks rich for four
## hundred rounds and then starves. A "did it build units?" check passes that
## failure. This gate therefore keys on UNITS, BUILDINGS, GOLD, ARCHON SURVIVAL
## and LEAD STILL ON THE MAP — and the `-d:bc22BrokenChassis` control proves it
## can go red.
##
## THE COMMITTED THRESHOLDS ARE MEASURED, NOT GUESSED. Phase 20 ran the healthy
## mirror on the two gate maps at both side assignments and the broken control
## on the same, and the numbers below sit between them with margin:
##
##   HEALTHY (weak seat of each game, six games)
##     miners built      8   (chalice)      soldiers built  10  (snowflake)
##     lead mined     3806   (chalice)      builders         1
##     labs finished     1                  gold transmuted 132 (snowflake)
##     archons at 1500   1                  robots alive    17  (chalice)
##     lead left on the map at 2000: 1950 of 220 (chalice), 2843 of 760
##     (snowflake) — i.e. 886 % and 374 % of the starting inventory, because
##     `mine_floor: 1` lets every worked square regenerate for ever
##     anomalies that measurably hit someone: every game
##
##   BROKEN (`-d:bc22BrokenChassis`, the same two maps)
##     builders 0, laboratories 0, gold 0, squares mined dry 14-22, and
##     `snowflake_redux` STRIPPED TO ZERO LEAD ON THE MAP
##
## THE DESIGN NOTE'S FLOOR asked for 25 miners and 15 soldiers built. Those are
## unsatisfiable on the measured healthy mirror — `chalice` carries 220 lead on
## twenty squares and one archon a side, so the whole economy is about four
## lead a round — so, per the note's own bc23 r1-F21/F22 ruling, the committed
## numbers are roughly HALF the weak seat's measured value and BOTH measured
## ranges are recorded above. Every other clause of the note's floor is kept as
## written or raised.

import std/[os, osproc, strutils]
import harness
import bc22_fixture

const
  MinMinersBuilt = 4          ## half the measured weak seat's 8
  MinSoldiersBuilt = 5        ## half the measured weak seat's 10
  MinLeadMined = 1800         ## half the measured weak seat's 3806
  MinBuilders = 1             ## the note's floor, kept
  MinLabsFinished = 1         ## the note's floor, kept
  MinGoldTransmuted = 5       ## the note's floor, kept (measured min 132)
  MinArchonsAt1500 = 1        ## the note's floor, kept
  MinRobotsAlive = 8          ## half the measured weak seat's 17
  MinLeadOnMapPct = 25        ## the note's floor, kept (measured 374-886 %)

type GateResult = object
  games: int
  reachedTheEnd: int
  failures: seq[string]

proc runGate(): GateResult =
  for mapName in ["chalice", "snowflake_redux"]:
    for seed in [0, 256, 512]:
      ## bc22's only per-episode entropy is the SIDE ASSIGNMENT: the map's own
      ## `randomSeed` fixes the `IDGenerator` and the vortex draw, so a third
      ## seed that lands on the same side really does replay the first game.
      ## That is stated rather than hidden, and the pair is still played from
      ## both sides.
      let sa = sideAslotFor(seed, 0)
      let (w, o) = playGame(loadMap(mapName), defaultSheets(),
                            [ckWololo, ckWololo], 0, sa, 2000, 0)
      inc result.games
      let tag = mapName & " seed " & $seed
      if o.endReason != "annihilated": inc result.reachedTheEnd
      for slot in 0 .. 1:
        template want(name: string, got, floorAmount: int) =
          if got < floorAmount:
            result.failures.add(tag & " seat " & $slot & ": " & name & " " &
              $got & " < " & $floorAmount)
        want("miners built", o.minersBuilt[slot], MinMinersBuilt)
        want("soldiers built", o.soldiersBuilt[slot], MinSoldiersBuilt)
        want("lead mined", o.leadMined[slot], MinLeadMined)
        want("builders built", o.buildersBuilt[slot], MinBuilders)
        want("laboratories built", o.labsBuilt[slot], 1)
        want("laboratories FINISHED", o.labsFinished[slot], MinLabsFinished)
        want("gold transmuted", o.goldTransmuted[slot], MinGoldTransmuted)
        want("archons alive at round 1500", o.archonsAliveAt1500[slot],
             MinArchonsAt1500)
        want("robots alive at the end", o.robotsAlive[slot], MinRobotsAlive)
      ## ACROSS THE TWO SEATS: the map must still hold a quarter of its
      ## starting lead at round 2000 — the `mine_floor: 1` default working —
      ## and at least one anomaly must have measurably hit someone.
      if o.leadOnMapEnd * 100 < o.leadOnMapStart * MinLeadOnMapPct:
        result.failures.add(tag & ": the map holds " & $o.leadOnMapEnd &
          " of its starting " & $o.leadOnMapStart & " lead")
      var anomalyBite = 0
      for slot in 0 .. 1:
        anomalyBite += o.anomalyLossesCharge[slot] +
          o.anomalyLossesFuryHp[slot] + o.anomalyLossesAbyssLead[slot]
      if anomalyBite < 1:
        result.failures.add(tag & ": no anomaly measurably hit anyone")
      discard w

when defined(bc22BrokenChassis):
  ## THE NEGATIVE CONTROL, run as a SUBPROCESS by the healthy build below. It
  ## prints its verdict and exits non-zero when the gate PASSES, because a gate
  ## that cannot fail is not a gate.
  when isMainModule:
    let r = runGate()
    echo "BROKEN-CONTROL games=", r.games, " failures=", r.failures.len
    for f in r.failures[0 .. min(5, r.failures.high)]:
      echo "  ", f
    if r.failures.len == 0:
      quit("the broken chassis PASSED the survival gate; the gate is dead", 1)
    echo "BROKEN-CONTROL: correctly red"
else:
  block:
    let r = runGate()
    checkEq("six games were played", r.games, 6)
    checkEq("and in AT LEAST FIVE the game reached the round limit or the " &
      "Singularity ladder rather than an annihilation", true,
      r.reachedTheEnd >= 5)
    if r.failures.len > 0:
      for f in r.failures: echo "  GATE: ", f
    checkEq("the healthy mirror clears every floor", r.failures.len, 0)

  block:
    ## THE INVERTED CONTROL. `-d:bc22BrokenChassis` makes every miner ignore
    ## `mine_floor` and mine to zero and stops the archons ever commissioning a
    ## builder, so no laboratory is ever built, no gold is ever made and the
    ## map is stripped. It is EXACTLY the failure a "did it build units?" check
    ## would pass, and it is the failure this year's signature knob exists to
    ## prevent.
    ##
    ## CI runs it; a bare `nim r` of this file without a Nim on PATH skips it
    ## loudly rather than reporting a pass it did not earn.
    let nim = findExe("nim")
    if nim.len == 0:
      echo "SKIP: no `nim` on PATH, so the negative control did not run"
      check("the negative control needs a Nim compiler", false)
    else:
      let out0 = getTempDir() / "bc22_broken_control"
      let cmd = nim & " c -d:release -d:bc22BrokenChassis --hints:off " &
        "--path:src --path:tests -o:" & out0 & " tests/test_bc22_survival.nim"
      let (buildLog, buildCode) = execCmdEx(cmd)
      checkEq("the broken control BUILDS", buildCode, 0)
      if buildCode != 0:
        echo buildLog
      else:
        let (runLog, runCode) = execCmdEx(out0)
        echo runLog.strip()
        checkEq("and it comes back RED against the gate", runCode, 0)
        check("having actually failed clauses",
          "failures=0" notin runLog)
        check("and it never built a laboratory or made a gold",
          "laboratories built" in runLog or "gold transmuted" in runLog or
          "laboratories FINISHED" in runLog)

  finish("test_bc22_survival")
