## The bc24 PARITY ORACLE's Nim side: the same trace as
## `tools/oracle/bc24/Bc24Trace.java`, emitted from the Nim port driving the
## ported `examplefuncsplayer24` chassis (or, under `-d:bc24Scenario`, the
## scenario bot) on both teams.
##
## CI-TIME ONLY, and not part of any image: `.github/workflows/ci.yml`'s
## `parity-oracle-bc24` job builds it, runs it once per map and diffs it
## against the Java trace line for line.
##
##   tools/parity_trace_bc24 --map:DefaultSmall --rounds:2000 --out:/tmp/nim.txt
##
## THE FORMAT IS THE JAVA ONE, with ONE deliberate difference, handled by the
## job rather than hidden here: the `bc=` field (bytecodes used) is NOT
## emitted. There is no JVM here and no bytecode counter to emit; the job
## strips it from the Java side before diffing and reads it separately for the
## Tier A headroom assertion (docs/RULES-BC24.md §Divergences item 1).
##
## bc24 needs no coordinate offset: `GameMapIO` fixes the origin at (0, 0) for
## every 2024 map.

import std/[os, strutils]
import battlecode/sheet
import battlecode/baselines
import battlecode/years/bc24/[maps, rules, world]

proc teamChar(team: Team): char =
  if team == teamA: 'A' else: 'B'

proc emitRound(w: World, out0: var string) =
  let round = w.currentRound
  for t in 0 .. 1:
    let team = Team(t)
    var alive = 0
    for r in w.robots:
      if r.team == team and r.spawned: alive += 1
    var mask = ""
    for i in 0 .. 2:
      mask.add(if w.stats.upgrades[t][i]: '1' else: '0')
    out0.add("R " & $round & " T " & teamChar(team) &
      " crumbs=" & $w.stats.crumbs[t] &
      " caps=" & $w.stats.flagsCaptured[t] &
      " picked=" & $w.stats.flagsPickedUp[t] &
      " lvl=" & $w.levelSum(team) &
      " alive=" & $alive &
      " up=" & mask &
      " upp=" & $w.stats.upgradePoints[t] & "\n")

  ## Units in EXEC ORDER, not id order — which is what makes an ordering bug
  ## visible at all.
  for r in w.robots:
    out0.add("R " & $round & " U " & $r.id &
      " team=" & teamChar(r.team) &
      " sp=" & (if r.spawned: "1" else: "0") &
      " x=" & (if r.spawned: $r.loc.x else: "-1") &
      " y=" & (if r.spawned: $r.loc.y else: "-1") &
      " hp=" & $r.health &
      " acd=" & $r.actionCooldown &
      " mcd=" & $r.movementCooldown &
      " ax=" & $r.attackExp &
      " bx=" & $r.buildExp &
      " hx=" & $r.healExp &
      " flag=" & (if r.flag != nil: $r.flag.id else: "-1") &
      " ra=" & $r.roundsAlive & "\n")

  for f in w.allFlags:
    out0.add("R " & $round & " F " & $f.id &
      " team=" & teamChar(f.team) &
      " x=" & $f.loc.x &
      " y=" & $f.loc.y &
      " start=" & (if f.locIsStartRef: "1" else: "0") &
      " carried=" & $f.carriedBy &
      " dropped=" & $f.droppedRounds & "\n")

proc main() =
  var mapName = "DefaultSmall"
  var rounds = 2000
  var outPath = ""
  for arg in commandLineParams():
    if arg.startsWith("--map:"): mapName = arg[6 .. ^1]
    elif arg.startsWith("--rounds:"): rounds = parseInt(arg[9 .. ^1])
    elif arg.startsWith("--out:"): outPath = arg[6 .. ^1]
  let spec = loadMap(mapName)
  let sheets = [baselineSheet("bc24", blExamplefuncsplayer24),
                baselineSheet("bc24", blExamplefuncsplayer24)]
  var w = newWorld(spec, rounds)
  var sides = newSides24(sheets, 0)
  let chassis = [ckExamplefuncsplayer24, ckExamplefuncsplayer24]
  var text = newStringOfCap(24 * 1024 * 1024)
  while w.running and w.currentRound < rounds:
    runRound(w, sides, chassis)
    emitRound(w, text)
  text.add("R " & $w.currentRound & " W winner=" &
    (if w.hasWinner: $teamChar(w.winner) else: "-") &
    " dom=" & (if w.domination == dfNone: "-" else: (
      case w.domination
      of dfCapture: "CAPTURE"
      of dfMoreFlagCaptures: "MORE_FLAG_CAPTURES"
      of dfLevelSum: "LEVEL_SUM"
      of dfMoreBread: "MORE_BREAD"
      of dfCoinFlip: "WON_BY_DUBIOUS_REASONS"
      of dfNone: "-")) & "\n")
  if outPath.len > 0:
    writeFile(outPath, text)
  else:
    stdout.write(text)

main()
