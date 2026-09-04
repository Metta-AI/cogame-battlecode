## THE bc24 COMPETENCE GATE, with an inverted control.
##
## The LEARNINGS pin: a scripted baseline has to PLAY. `gone-sharkin` spawns
## every duck it can, walks crumbs off the floor, digs, lays traps, defends a
## flag it senses under threat, levels its ducks and raids the enemy's flags in
## every game -- and this gate reads survival and positive play counters rather
## than a win, because both seats are the same chassis.
##
## AND THE GATE MUST BE ABLE TO FAIL. The same assertions are re-run against a
## KNOWN-BROKEN chassis compiled behind `-d:bc24BrokenChassis` (a `sharkin.nim`
## variant that stops spawning after round 50) and MUST fail. A gate that
## cannot fail is not a gate, and this is the direct answer to the 2026-09-03
## finding that mechanical episode checks pass degenerate matches -- so this
## shard runs the broken control as a SUBPROCESS and asserts it comes back red.
##
##   nim r --path:src tests/test_bc24_survival.nim              # the gate
##   nim r -d:bc24BrokenChassis --path:src tests/…              # must FAIL
##
## THE THRESHOLDS ARE MEASURED, NOT THE NOTE'S. The design note asks for
## "level sum >= 30, >= 6 traps, >= 1 500 crumbs, >= 20 000 damage", written
## before the economy existed. A healthy bc24 mirror finishes at 157..199
## levels, 67..136 traps, 17 000..38 000 crumbs and 620 000..1 170 000 damage;
## the BROKEN control finishes at 8..34 levels, 21..32 traps, 22 000 crumbs and
## 44 000..63 000 damage. The note's numbers would let the broken chassis pass,
## so the gate uses the measured ones with margin -- which are a strict
## superset of the note's floor -- and says so here (the bc20 precedent).

import std/[os, osproc, strformat, strutils]
import harness
import battlecode/baselines
import battlecode/years/bc24/[maps, rules]

const
  OpenMaps = ["Yinyang", "BreadPudding", "Occulus"]
    ## LAND-CONNECTED after the dam falls, so both flocks can reach each
    ## other's flags. Three maps under both side assignments is six games, and
    ## the episode seed cannot make a seventh: bc24's chassis draws on no RNG
    ## at all, so (map, side assignment) is every distinct game these inputs
    ## can produce.
  LockedMaps = ["Rivers", "Tunnels"]
    ## Separated by WATER as well as by the dam -- a real property of the
    ## shipped `small` pool, confirmed against the Java engine. Nobody can
    ## touch a flag on these until a crossing is filled, so the flag clause
    ## cannot hold; what MUST hold is that the chassis fills the crossing and
    ## the war happens at all.
  MinDistinctSpawned = 45
  MinLevelSum = 120
  MinTraps = 40
  LockedMinLevelSum = 60
  LockedMinTraps = 20
    ## The water-locked pair spends the first part of the game filling a
    ## crossing rather than fighting over one, so its levels and traps land
    ## lower. The BROKEN control still finishes far below even these (8..34
    ## levels), which is what keeps the gate honest.
  MinTerraform = 10
  MinCrumbs = 15_000
  MinDamage = 200_000
  MinFlagPickupsAcrossSeats = 3

let doctrine = baselineSheet("bc24", blGoneSharkin)

var games = 0
var reached = 0

proc assertFloor(label: string, o: GameOutcome24,
                 minLevels = MinLevelSum, minTraps = MinTraps) =
  for seat in 0 .. 1:
    check(&"{label} seat {seat}: spawned >= {MinDistinctSpawned} distinct " &
      &"ducks ({o.ducksSpawned[seat]})",
      o.ducksSpawned[seat] >= MinDistinctSpawned)
    check(&"{label} seat {seat}: level sum >= {minLevels} " &
      &"({o.levelsEnd[seat]})", o.levelsEnd[seat] >= minLevels)
    check(&"{label} seat {seat}: >= {minTraps} traps built " &
      &"({o.trapsBuilt[seat]})", o.trapsBuilt[seat] >= minTraps)
    check(&"{label} seat {seat}: >= {MinTerraform} tiles dug or filled " &
      &"({o.tilesDug[seat] + o.tilesFilled[seat]})",
      o.tilesDug[seat] + o.tilesFilled[seat] >= MinTerraform)
    check(&"{label} seat {seat}: >= {MinCrumbs} crumbs collected " &
      &"({o.crumbsCollected[seat]})", o.crumbsCollected[seat] >= MinCrumbs)
    check(&"{label} seat {seat}: >= {MinDamage} damage dealt " &
      &"({o.damageDealt[seat]})", o.damageDealt[seat] >= MinDamage)

for name in OpenMaps:
  for sideAslot in 0 .. 1:
    let label = &"{name}/side{sideAslot}"
    let (_, o) = playGame(loadMap(name), [doctrine, doctrine],
      [ckGoneSharkin, ckGoneSharkin], 0, sideAslot, 2000, 0)
    games += 1
    ## Nothing may collapse early: the game either goes the distance or is won
    ## on a capture AFTER round 800.
    if o.roundsPlayed >= 2000 or
       (o.endReason == "capture" and o.roundsPlayed > 800):
      reached += 1
    assertFloor(label, o)
    ## A bc24 game where nobody ever touches a flag is not this game being
    ## played.
    check(&"{label}: >= {MinFlagPickupsAcrossSeats} enemy-flag pickups " &
      &"across the two seats ({o.flagsPickedUp[0] + o.flagsPickedUp[1]})",
      o.flagsPickedUp[0] + o.flagsPickedUp[1] >= MinFlagPickupsAcrossSeats)

checkEq("six games on the land-connected maps", games, 6)
check(&"at least five of six went the distance or captured after round 800 " &
  &"({reached})", reached >= 5)

for name in LockedMaps:
  let label = &"{name}/side0"
  let (_, o) = playGame(loadMap(name), [doctrine, doctrine],
    [ckGoneSharkin, ckGoneSharkin], 0, 0, 2000, 0)
  assertFloor(label, o, LockedMinLevelSum, LockedMinTraps)
  ## THE FLOOR NO KNOB CAN LOWER, second clause: SOMEBODY opens the crossing
  ## whatever `water_dig_policy` says, or there is no war at all. Which seat
  ## pays for it is not fixed -- the two flocks' cheapest routes share tiles,
  ## so the first to arrive fills them and the other walks through.
  check(&"{label}: the water crossing was filled " &
    &"({o.tilesFilled[0]} + {o.tilesFilled[1]})",
    o.tilesFilled[0] + o.tilesFilled[1] >= 1)

when not defined(bc24BrokenChassis):
  ## THE INVERTED CONTROL. Re-run this very file with the broken chassis and
  ## require a NON-ZERO exit. Skipped when the harness cannot find a compiler
  ## (the wasm and container builds never run tests).
  block:
    let nimExe = findExe("nim")
    if nimExe.len == 0:
      echo "bc24 survival: no `nim` on PATH; the inverted control is skipped"
    else:
      let selfPath = currentSourcePath()
      let cmd = quoteShell(nimExe) & " r --hints:off -d:release " &
        "-d:bc24BrokenChassis --path:src " & quoteShell(selfPath)
      echo "bc24 survival: running the inverted control: ", cmd
      let (output, code) = execCmdEx(cmd, options = {poUsePath})
      check("the SAME gate against the known-broken chassis FAILS " &
        "(exit " & $code & ")", code != 0)
      check("and it fails on the gate's own assertions, not on a compile error",
        "FAIL " in output or "checks failed" in output)

finish("bc24 survival")
