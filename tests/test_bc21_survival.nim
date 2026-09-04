## THE bc21 ECONOMIC-SURVIVAL / SELF-PLAY GATE, with an inverted control.
##
## The LEARNINGS pin: a scripted baseline has to PLAY. `california-roll` builds,
## defends its Centers, hunts slanderers, captures neutrals and bids in every
## round of every game, and this gate reads survival and positive play counters
## rather than a win.
##
## AND THE GATE MUST BE ABLE TO FAIL. The same assertions are re-run against a
## KNOWN-BROKEN chassis compiled behind `-d:bc21BrokenChassis` (a `croll.nim`
## variant whose Enlightenment Centers stop building and stop bidding after
## round 50) and MUST fail. A gate that cannot fail is not a gate — so this
## shard runs the broken control as a SUBPROCESS and asserts it comes back red.
##
##   nim r --path:src tests/test_bc21_survival.nim              # the gate
##   nim r -d:bc21BrokenChassis --path:src tests/…              # must FAIL

import std/[os, osproc, strformat, strutils]
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc21/[constants, maps, rules, world]

const GateMaps = ["Bog", "Star"]
const GateSeeds = [1, 256, 768]
  ## The episode seed only chooses the map and the side assignment — the world
  ## RNG comes from the MAP's own `randomSeed` — so these six games are the two
  ## maps under both side assignments, which is every distinct game those
  ## inputs can produce.

let doctrine = baselineSheet("bc21", blCaliforniaRoll)

var reached = 0
var games = 0

for name in GateMaps:
  for seed in GateSeeds:
    let sa = sideAslotFor(seed, 0)
    var centersAt400 = [0, 0]
    proc onRound(w: World, round: int) {.closure.} =
      if round == 400:
        centersAt400 = [w.livingCenters(teamA), w.livingCenters(teamB)]
    let (w, o) = playGame(loadMap(name), [doctrine, doctrine],
      [ckCaliforniaRoll, ckCaliforniaRoll], 0, sa, 1500, 0, onRound)
    inc games
    let label = &"{name} seed {seed}"

    ## NOTHING MAY DIE TRIVIALLY EARLY: the game either goes the distance or
    ## ends on annihilation after round 400.
    if o.roundsPlayed >= 1500 or
       (o.endReason == "annihilated" and o.roundsPlayed > 400):
      inc reached

    for slot in 0 .. 1:
      check(&"{label}: seat {slot} built >= 40 units ({o.unitsBuilt[slot]})",
        o.unitsBuilt[slot] >= 40)
      check(&"{label}: seat {slot} spent >= 2000 influence " &
        &"({o.influenceSpent[slot]})", o.influenceSpent[slot] >= 2000)
      check(&"{label}: seat {slot} placed >= 100 bids " &
        &"({o.bidsPlaced[slot]})", o.bidsPlaced[slot] >= 100)
    let teamOfSeat0 = (if sa == 0: 0 else: 1)
    check(&"{label}: seat 0 held a Centre at round 400 " &
      &"({centersAt400[teamOfSeat0]})", centersAt400[teamOfSeat0] >= 1)
    check(&"{label}: seat 1 held a Centre at round 400 " &
      &"({centersAt400[1 - teamOfSeat0]})", centersAt400[1 - teamOfSeat0] >= 1)
    ## A DEAD AUCTION IS A DEAD ECONOMY.
    check(&"{label}: the two teams together won >= 900 of the 1500 votes " &
      &"({o.votes[0] + o.votes[1]})", o.votes[0] + o.votes[1] >= 900)

checkEq("six games", games, 6)
check(&"at least five of six went the distance or died after round 400 " &
  &"({reached})", reached >= 5)

when not defined(bc21BrokenChassis):
  ## THE INVERTED CONTROL. Re-run this very file with the broken chassis and
  ## require a NON-ZERO exit. Skipped when the harness cannot find a compiler
  ## (the wasm and container builds never run tests).
  block:
    let nimExe = findExe("nim")
    if nimExe.len == 0:
      echo "bc21 survival: no `nim` on PATH; the inverted control is skipped"
    else:
      let selfPath = currentSourcePath()
      let cmd = quoteShell(nimExe) & " r --hints:off -d:release " &
        "-d:bc21BrokenChassis --path:src " & quoteShell(selfPath)
      echo "bc21 survival: running the inverted control: ", cmd
      let (output, code) = execCmdEx(cmd, options = {poUsePath})
      check("the SAME gate against the known-broken chassis FAILS " &
        "(exit " & $code & ")", code != 0)
      check("and it fails on the gate's own assertions, not on a compile error",
        "FAIL " in output or "checks failed" in output)

finish("bc21 survival")
