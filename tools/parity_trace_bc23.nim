## The bc23 parity oracle's NIM side: play the same map with the same chassis
## and print the same trace lines `tools/oracle/bc23/Bc23Trace.java` prints.
##
## CI-TIME ONLY (the `parity-oracle-bc23` job). Nothing here is in the game
## image; it is a separate binary built from the same sim module.
##
##   nim c --hints:off -d:release --path:src -o:/tmp/parity_trace_bc23 \
##     tools/parity_trace_bc23.nim
##   /tmp/parity_trace_bc23 <map> <rounds> [scaffold|scenario]
##
## The `-d:bc23Scenario` build of the same file is the Tier A′ side: it swaps
## the chassis for `src/battlecode/years/bc23/chassis/scenario23.nim`, whose
## Java twin is `tools/oracle/bc23/bc23scenario/RobotPlayer.java`.
##
## The trace is byte-comparable with the Java side, LINE FOR LINE:
##
##   R <round> T <A|B> ad= mn= ex= isl= anch= anchheld=
##   R <round> I <islandId> own= hp= anch=
##   R <round> W <wellIdx> ty= rate= ad= mn= ex=
##   R <round> M chk=<fnv1a64 of the per-tile per-team multiplier hundredths>
##   R <round> U <id> team= ty= x= y= hp= ad= mn= ex= anc= acd= mcd= bc=
##   R <round> S <A|B> arr=<fnv1a64 of the 64-slot shared array>
##   R <round> Z winner= dom=
##
## `bc=` is printed as 0: there is no bytecode counter on this side, and
## `tools/ci/parity_tiers_bc23.py` strips the column from BOTH sides before
## the diff and uses the Java value only for the headroom assertion.

import std/[os, strutils]
import battlecode/[baselines, sheet, sim_types]
import battlecode/years/bc23/rules as r23
import battlecode/years/bc23/world as w23

proc teamLetter(t: Team): string = (if t == teamA: "A" else: "B")

proc resourceLetters(r: Resource): string =
  case r
  of resAdamantium: "AD"
  of resMana: "MN"
  of resElixir: "EX"
  of resNone: "-"

proc javaHex(v: uint64): string =
  ## `java.lang.Long.toHexString`: lower case with NO leading zeros, and the
  ## single digit "0" for zero. Nim's `toHex` pads to sixteen, so a checksum
  ## whose top nibble is zero read as a divergence on every line that carried
  ## it. Tier A never saw it because `examplefuncsplayer23` never writes the
  ## shared array and the all-zero fold has no leading zero; the Tier A'
  ## scenario bot writes on round 1 and hit it on round 13 (r1-F19).
  result = toLowerAscii(toHex(v))
  var i = 0
  while i < result.high and result[i] == '0':
    i += 1
  result = result[i .. ^1]

proc fnv(values: openArray[int]): uint64 =
  result = 0xCBF29CE484222325'u64
  for v in values:
    result = (result xor (uint64(v) and 0xFFFFFFFF'u64)) * 0x100000001B3'u64

proc multiplierChecksum(w: w23.World): uint64 =
  ## y ascending outer, x ascending inner, team A then team B per tile, in
  ## INTEGER HUNDREDTHS masked to 16 bits — exactly the Java fold.
  var flat = newSeq[int](w.width * w.height * 2)
  var k = 0
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      let i = w.idx(loc(x, y))
      flat[k] = w.tempo.hundredths[0][i] and 0xFFFF
      flat[k + 1] = w.tempo.hundredths[1][i] and 0xFFFF
      k += 2
  fnv(flat)

proc emitRound(w: w23.World, out0: File) =
  let cur = w.currentRound
  for ti in 0 .. 1:
    let t = Team(ti)
    let held = w.islandsOwned(t)
    out0.write("R ", cur, " T ", teamLetter(t),
      " ad=", w.stats.adamantium[ti],
      " mn=", w.stats.mana[ti],
      " ex=", w.stats.elixir[ti],
      " isl=", held,
      " anch=", w.stats.totalAnchorsPlaced[ti],
      " anchheld=", held, "\n")
  for isl in w.islands:
    out0.write("R ", cur, " I ", isl.id,
      " own=", isl.owner,
      " hp=", isl.health,
      " anch=", (if isl.anchor == anNone: "-" else: $isl.anchor), "\n")
  for i in 0 ..< w.wellAt.len:
    if not w.wellAt[i].present: continue
    out0.write("R ", cur, " W ", i,
      " ty=", resourceLetters(w.wellAt[i].kind),
      " rate=", w.wellAt[i].rate(),
      " ad=", w.wellAt[i].adamantium,
      " mn=", w.wellAt[i].mana,
      " ex=", w.wellAt[i].elixir, "\n")
  out0.write("R ", cur, " M chk=", javaHex(multiplierChecksum(w)),
    "\n")
  for id in w.execOrder:
    let r = w.robotsById[id]
    out0.write("R ", cur, " U ", r.id,
      " team=", teamLetter(r.team),
      " ty=", $r.kind,
      " x=", r.loc.x, " y=", r.loc.y,
      " hp=", r.health,
      " ad=", r.adamantium, " mn=", r.mana, " ex=", r.elixir,
      " anc=", r.totalAnchors,
      " acd=", r.actionCooldown, " mcd=", r.movementCooldown,
      " bc=0\n")
  for ti in 0 .. 1:
    var arr = newSeq[int](SharedArrayLength)
    for i in 0 ..< SharedArrayLength:
      arr[i] = w.stats.sharedArray[ti][i]
    out0.write("R ", cur, " S ", teamLetter(Team(ti)),
      " arr=", javaHex(fnv(arr)), "\n")

proc main() =
  if paramCount() < 2:
    quit("usage: parity_trace_bc23 <map> <rounds> [scaffold|scenario]", 2)
  let mapName = paramStr(1)
  let rounds = parseInt(paramStr(2))
  let which = if paramCount() >= 3: paramStr(3) else: "scaffold"
  let sheetIn =
    when defined(bc23Scenario): defaultSheet("bc23")
    else: baselineSheet("bc23", blExamplefuncsplayer23)
  let kind =
    when defined(bc23Scenario): r23.ckLemonade
    else: r23.ckExamplefuncsplayer23
  discard which

  let spec = r23.loadMap(mapName)
  ## THE WORLD'S CAP IS THE MAP'S OWN `rounds`, not the trace length. The
  ## Java side always loads a 2000-round `LiveMap`, so a world built with
  ## `maxRounds = <trace length>` applies the end ladder early and the ONLY
  ## divergent line is the `Z` record — which is exactly the sort of
  ## harness artefact a parity job must not report as a rules bug.
  var w = w23.newWorld(spec, spec.rounds)
  var sides = r23.newSides23([sheetIn, sheetIn], 0)
  let out0 = stdout
  for round in 1 .. rounds:
    r23.runRound(w, sides, [kind, kind])
    emitRound(w, out0)
    if not w.running: break
  out0.write("R ", w.currentRound, " Z winner=",
    (if w.hasWinner: teamLetter(w.winner) else: "-"),
    " dom=", (if w.domination == dfNone: "-"
              else: toUpperAscii(($w.domination).replace("_", "_"))), "\n")
  out0.flushFile()

main()
