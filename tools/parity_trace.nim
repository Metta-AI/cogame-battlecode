## Emit the parity trace from the NIM sim, in the exact text
## `tools/parity_trace.py` emits from a Java `.bc26`. The `parity-oracle` CI
## job diffs the two (docs/PARITY.md).
##
##   nim r --path:src tools/parity_trace.nim --map DefaultSmall --rounds 50
##
## The chassis is `scaffold` on both sides — the ported examplefuncsplayer —
## because that is the bot the Java side runs and the only one whose
## behaviour can be compared statement for statement.

import std/[os, parseopt, strutils, tables]
import battlecode/sheet
import battlecode/years/bc26/[constants, maps, rules, world]

const DirName = ["NORTH", "NORTHEAST", "EAST", "SOUTHEAST",
                 "SOUTH", "SOUTHWEST", "WEST", "NORTHWEST", "CENTER"]

proc main() =
  var
    mapName = "DefaultSmall"
    rounds = 50
    outPath = ""
  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "map": mapName = val
      of "rounds": rounds = parseInt(val)
      of "out": outPath = val
      else: discard
    else: discard

  var sheets: array[2, Sheet]
  for i in 0 .. 1:
    sheets[i] = defaultSheet()
    sheets[i].doctrine.chassis = chScaffold

  let spec = loadMap(mapName)
  var w = newWorld(spec, GameMaxNumberOfRounds)
  let clans = newClans(sheets, 0)
  var lines: seq[string] = @[]

  while w.running and w.currentRound < rounds:
    ## The trace is emitted from the same records the engine writes: team
    ## info at end of round, and one line per robot turn. Turn state is read
    ## AFTER the turn, which is when the engine calls `endTurn`.
    let order = w.execOrder
    var turns: seq[string] = @[]
    w.processBeginningOfRound()
    for id in order:
      if id notin w.robotsById: continue
      let r = w.robotsById[id]
      w.processBeginningOfTurn(r)
      if r.dead: continue
      runControllerFor(w, clans, r)
      if r.dead: continue
      endOfTurnFor(w, clans, r)
      turns.add("R " & $w.currentRound & " U " & $r.id &
        " hp=" & $r.health & " chz=" & $r.cheese &
        " mc=" & $r.movementCooldown & " tc=" & $r.turningCooldown &
        " ac=" & $r.actionCooldown &
        " x=" & $r.loc.x & " y=" & $r.loc.y &
        " dir=" & DirName[ord(r.dir)] &
        " coop=" & (if w.isCooperation: "1" else: "0"))
    for t in 0 .. 1:
      lines.add("R " & $w.currentRound & " T " & (if t == 0: "A" else: "B") &
        " chz=" & $w.teamInfo.cheeseTransferred[t] &
        " cat=" & $w.teamInfo.damageToCats[t] &
        " kpk=" & $(w.teamInfo.numRatKings[t] + 10 * w.teamInfo.globalCheese[t]) &
        " rats=" & $w.teamInfo.numBabyRats[t] &
        " dirt=" & $w.teamInfo.dirtCounts[t] &
        " rt=" & $w.trapCount(ttRatTrap, Team(t)) &
        " ct=" & $w.trapCount(ttCatTrap, Team(t)))
    for line in turns:
      lines.add(line)
    w.processEndOfRound()

  let text = lines.join("\n") & "\n"
  if outPath.len > 0: writeFile(outPath, text) else: stdout.write(text)

main()
