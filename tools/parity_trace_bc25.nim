## The bc25 parity oracle's NIM side: play the ported sim and print exactly the
## lines `tools/oracle/bc25/Bc25Trace.java` prints from the live Java objects.
##
## CI-TIME ONLY. Nothing here is in any runtime image; it is built and run by
## the `parity-oracle-bc25` job of `.github/workflows/ci.yml` and diffed
## against the Java trace by `tools/ci/parity_tiers_bc25.py`.
##
##   nim c -d:release --path:src -o:parity_trace_bc25 tools/parity_trace_bc25.nim
##   ./parity_trace_bc25 --map:DefaultSmall --rounds:2000 --out:trace.nim
##
## `-d:bc25Scenario` (optionally with `-d:bc25ScenarioPaint` or
## `-d:bc25ScenarioWipe`) builds the Tier A-prime scenario twin instead of the
## example bot. THE `bc=` COLUMN IS NOT EMITTED HERE: there is no bytecode
## counter on the Nim side, and the comparison strips it from the Java trace
## before diffing.

import std/[os, parseopt, strutils]
import battlecode/[baselines, sheet, sim_types]
import battlecode/years/bc25/[maps, rules, world, towers]

proc teamLetter(t: Team): string = (if t == teamA: "A" else: "B")

proc fnv(values: openArray[int8]): uint64 =
  result = 0xCBF29CE484222325'u64
  for v in values:
    result = (result xor (uint64(int(v)) and 0xFFFFFFFF'u64)) *
      0x100000001B3'u64

func unpadded(h: uint64): string =
  result = toLowerAscii(toHex(h))
  var at = 0
  while at < result.len - 1 and result[at] == '0': at += 1
  result = result[at .. ^1]

proc traceRound(w: World, sb: var string) =
  let cur = w.currentRound
  for t in [teamA, teamB]:
    sb.add("R " & $cur & " T " & teamLetter(t) &
      " money=" & $w.getMoney(t) &
      " painted=" & $w.stats.livePainted[ord(t)] &
      " towers=" & $w.stats.towers[ord(t)] &
      " bots=" & $w.robotsAlive(t) &
      " paintunits=" & $w.paintInUnits(t) &
      " srp=" & $w.numActiveResourcePatterns(t) & "\n")

  var both = newSeq[int8](w.markers[0].len + w.markers[1].len)
  for i in 0 ..< w.markers[0].len: both[i] = w.markers[0][i]
  for i in 0 ..< w.markers[1].len: both[w.markers[0].len + i] = w.markers[1][i]
  ## `Long.toUnsignedString(h, 16)` prints NO leading zeros; Nim's `toHex`
  ## pads to sixteen. Strip, so the two sides are byte-identical.
  sb.add("R " & $cur & " M chk=" & unpadded(fnv(w.colours)) &
    " mk=" & unpadded(fnv(both)) & "\n")

  for centre in w.srpCentres:
    let idx = w.idx(centre)
    sb.add("R " & $cur & " P " & $idx &
      " team=" & teamLetter(Team(int(w.srpTeamByLoc[idx]) - 1)) &
      " life=" & $int(w.srpLifetimes[idx]) & "\n")

  for id in w.execOrder:
    let r = w.robotsById[id]
    sb.add("R " & $cur & " U " & $r.id &
      " team=" & teamLetter(r.team) &
      " ty=" & $r.kind &
      " x=" & $r.loc.x & " y=" & $r.loc.y &
      " hp=" & $r.health & " pnt=" & $r.paint &
      " acd=" & $r.actionCooldown & " mcd=" & $r.movementCooldown &
      " ra=" & $r.roundsAlive & "\n")

proc main() =
  var mapName = "DefaultSmall"
  var rounds = 2000
  var outPath = ""
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "map": mapName = p.val
      of "rounds": rounds = parseInt(p.val)
      of "out": outPath = p.val
      else: discard
    of cmdArgument: discard

  ## `-d:bc25Scenario` swaps `scaffold25.nim`'s body for `scenario25.nim`'s
  ## inside the SAME chassis, so the chassis value is the same either way.
  let chassis = ckExamplefuncsplayer25
  let sheets = [baselineSheet("bc25", blExamplefuncsplayer25),
                baselineSheet("bc25", blExamplefuncsplayer25)]

  ## THE WORLD'S OWN ROUND CAP IS THE ENGINE'S, ALWAYS. `--rounds` bounds the
  ## TRACE, not the game: a world built with a 60-round cap would fire the end
  ## ladder at round 60 and the Java side, which reads the cap off the map,
  ## would not.
  var w = newWorld(loadMap(mapName), GameMaxNumberOfRounds)
  var sides = newSides25(sheets, 0)
  var sb = newStringOfCap(1 shl 22)
  var sink = if outPath.len > 0: open(outPath, fmWrite) else: stdout
  for round in 1 .. rounds:
    runRound(w, sides, [chassis, chassis])
    traceRound(w, sb)
    if sb.len > (1 shl 22):
      sink.write(sb)
      sb.setLen(0)
    if not w.running: break
  sb.add("R " & $w.currentRound & " W winner=" &
    (if w.hasWinner: teamLetter(w.winner) else: "-") &
    " dom=" & (if w.domination == dfNone: "-"
               else: toUpperAscii(replace($w.domination, "_", "_"))) & "\n")
  sink.write(sb)
  if outPath.len > 0: sink.close()

main()
