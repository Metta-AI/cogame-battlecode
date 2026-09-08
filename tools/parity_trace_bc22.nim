## The bc22 parity oracle's NIM side: play the same map with the same chassis
## and print the same trace lines `tools/oracle/bc22/Bc22Trace.java` prints.
##
## CI-TIME ONLY (the `parity-oracle-bc22` job). Nothing here is in the game
## image; it is a separate binary built from the same sim module.
##
##   nim c --hints:off -d:release --path:src -o:/tmp/parity_trace_bc22 \
##     tools/parity_trace_bc22.nim
##   /tmp/parity_trace_bc22 <map> <rounds>
##
## The `-d:bc22Scenario` build of the same file is the Tier A′ side: it swaps
## the chassis for `src/battlecode/years/bc22/chassis/scenario22.nim`, whose
## Java twin is `tools/oracle/bc22/bc22scenario/RobotPlayer.java`. The three
## further switches `-d:bc22ScenarioAnnihilate`, `-d:bc22ScenarioTie` and
## `-d:bc22ScenarioFury` select that bot's three end-forcing variants.
##
## The trace is byte-comparable with the Java side, LINE FOR LINE:
##
##   R <round> T <A|B> pb= au= ar= la= wa= mi= bu= so= sa=
##   R <round> G leadchk= goldchk= rubblechk= leadsum= goldsum=
##   R <round> U <id> team= ty= md= lv= x= y= hp= acd= mcd= bc=
##   R <round> S <A|B> arr=<fnv1a64 of the 64-slot shared array>
##   R <round> H hashord=<fnv1a64 of the ids in robotsArray() order>
##   R <round> A next=<idx> type=<ABYSS|CHARGE|FURY|VORTEX|-> round=<n>
##   R <round> Z winner=<A|B|-> dom=<NAME|->
##
## `bc=` is printed as 0: there is no bytecode counter on this side (the port
## meters DecisionOps instead — docs/RULES-BC22.md §Divergences item 1), and
## `tools/ci/parity_tiers_bc22.py` strips the column from BOTH sides before the
## diff and uses the Java value only for the Tier A headroom assertion.
##
## The hex fold is printed the way `java.lang.Long.toHexString` prints it —
## lower case, NO leading zeros — because that is the cheaper half of the
## agreement; the comparator canonicalises both sides anyway (bug 3 of the
## three it fixes), so neither emitter's formatting can create or hide a
## divergence.

import std/[os, strutils]
import battlecode/[baselines, sheet, sim_types]
import battlecode/years/bc22/rules as r22
import battlecode/years/bc22/world as w22

proc teamLetter(t: Team): string = (if t == teamA: "A" else: "B")

proc javaHex(v: uint64): string =
  ## `java.lang.Long.toHexString`: lower case with NO leading zeros, and the
  ## single digit "0" for zero. Nim's `toHex` pads to sixteen.
  result = toLowerAscii(toHex(v))
  var i = 0
  while i < result.high and result[i] == '0':
    i += 1
  result = result[i .. ^1]

proc javaDomination(d: Domination): string =
  ## `world/DominationFactor.java`'s own names. `dfCoinFlip` is spelled
  ## `coin_flip` in this port because the manifest's `end_reason` enum already
  ## calls it that, so `$d` is NOT the Java name and a table is required.
  case d
  of dfNone: "-"
  of dfAnnihilated: "ANNIHILATION"
  of dfMoreArchons: "MORE_ARCHONS"
  of dfMoreGoldNetWorth: "MORE_GOLD_NET_WORTH"
  of dfMoreLeadNetWorth: "MORE_LEAD_NET_WORTH"
  of dfCoinFlip: "WON_BY_DUBIOUS_REASONS"

proc emitRound(w: w22.World, out0: File) =
  let cur = w.currentRound
  for ti in 0 .. 1:
    let t = Team(ti)
    out0.write("R ", cur, " T ", teamLetter(t),
      " pb=", w.teamLead(t),
      " au=", w.teamGold(t),
      " ar=", w.robotCountByType(t, rtArchon),
      " la=", w.robotCountByType(t, rtLaboratory),
      " wa=", w.robotCountByType(t, rtWatchtower),
      " mi=", w.robotCountByType(t, rtMiner),
      " bu=", w.robotCountByType(t, rtBuilder),
      " so=", w.robotCountByType(t, rtSoldier),
      " sa=", w.robotCountByType(t, rtSage), "\n")

  var leadSum = 0
  var goldSum = 0
  for v in w.leadAt: leadSum += v
  for v in w.goldAt: goldSum += v
  out0.write("R ", cur, " G leadchk=", javaHex(w.leadChecksum()),
    " goldchk=", javaHex(w.goldChecksum()),
    " rubblechk=", javaHex(w.rubbleChecksum()),
    " leadsum=", leadSum,
    " goldsum=", goldSum, "\n")

  ## IN EXEC ORDER, not id order — the whole point of the `U` records.
  for id in w.execOrder:
    let r = w.robotById(id)
    if r == nil: continue
    out0.write("R ", cur, " U ", r.id,
      " team=", teamLetter(r.team),
      " ty=", $r.kind,
      " md=", $r.mode,
      " lv=", r.level,
      " x=", r.loc.x, " y=", r.loc.y,
      " hp=", r.health,
      " acd=", r.actionCooldown, " mcd=", r.movementCooldown,
      " bc=0\n")

  for ti in 0 .. 1:
    var arr = newSeq[int](SharedArrayLength)
    for i in 0 ..< SharedArrayLength:
      arr[i] = w.stats.sharedArray[ti][i]
    out0.write("R ", cur, " S ", teamLetter(Team(ti)),
      " arr=", javaHex(fnvArray(arr)), "\n")

  out0.write("R ", cur, " H hashord=", javaHex(w.hashOrderChecksum()), "\n")

  let nxt = w.nextAnomaly()
  out0.write("R ", cur, " A next=", w.anomalyCursor,
    " type=", (if nxt.has: $nxt.kind else: "-"),
    " round=", (if nxt.has: nxt.round else: -1), "\n")

proc main() =
  if paramCount() < 2:
    quit("usage: parity_trace_bc22 <map> <rounds>", 2)
  let mapName = paramStr(1)
  let rounds = parseInt(paramStr(2))
  let sheetIn =
    when defined(bc22Scenario): defaultSheet("bc22")
    else: baselineSheet("bc22", blExamplefuncsplayer22)
  let kind = r22.ckExamplefuncsplayer22

  let spec = r22.loadMap(mapName)
  ## THE WORLD'S CAP IS THE MAP'S OWN `rounds`, not the trace length. The Java
  ## side always loads a 2000-round `LiveMap` (`GameMapIO` hard-codes
  ## `GAME_MAX_NUMBER_OF_ROUNDS`; the field is not even in the map file), so a
  ## world built with `maxRounds = <trace length>` applies the Singularity
  ## ladder early and the ONLY divergent line is the `Z` record — exactly the
  ## sort of harness artefact a parity job must not report as a rules bug.
  var w = w22.newWorld(spec, spec.rounds)
  ## AS `playGame` DOES. `newWorld` leaves the laboratory rate table zeroed —
  ## it is loaded from `data/bc22/tables.json`, which lives outside `world.nim`
  ## — and a zero rate makes gold FREE. Measured: without this line the Tier A′
  ## scenario pair diverges at `chalice` round 367, the round the first
  ## laboratory finishes, and on lead alone.
  w.loadTransmuteTable()
  var sides = r22.newSides22([sheetIn, sheetIn], 0)
  let out0 = stdout
  for round in 1 .. rounds:
    r22.runRound(w, sides, [kind, kind])
    emitRound(w, out0)
    if not w.running: break
  out0.write("R ", w.currentRound, " Z winner=",
    (if w.hasWinner: teamLetter(w.winner) else: "-"),
    " dom=", javaDomination(w.domination), "\n")
  out0.flushFile()

main()
