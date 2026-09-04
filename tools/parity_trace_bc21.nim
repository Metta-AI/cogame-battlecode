## The bc21 PARITY ORACLE's Nim side: the same trace as
## `tools/oracle/bc21/Bc21Trace.java`, emitted from the Nim port driving the
## ported `examplefuncsplayer21` chassis on both teams.
##
## CI-TIME ONLY, and not part of any image: `.github/workflows/ci.yml`'s
## `parity-oracle-bc21` job builds it, runs it once per map and diffs it
## against the Java trace line for line.
##
##   tools/parity_trace_bc21 --map:maptestsmall --rounds:200 --out:/tmp/nim
##
## THE FORMAT IS THE JAVA ONE, with two deliberate differences, both handled
## by the job rather than hidden here:
##
##   * the `bc=` field (bytecodes used) is NOT emitted. There is no JVM here
##     and no bytecode counter to emit; the job strips it from the Java side
##     before diffing, and reads it separately to report the peak use and to
##     find the first round the JVM cut a robot off mid-turn, which is what
##     sizes the Tier A window (docs/RULES-BC21.md §Divergences item 1).
##   * coordinates are printed in the ENGINE's absolute frame, i.e. offset by
##     the map's own `minCorner`, because that is what the engine prints. The
##     sim itself is 0-based (docs/RULES-BC21.md §Divergences item 6).

import std/[math, os, strformat, strutils]
import battlecode/sheet
import battlecode/baselines
import battlecode/years/bc21/[constants, maps, rules, world]

proc teamChar(team: Team): char =
  case team
  of teamA: 'A'
  of teamB: 'B'
  of teamNeutral: 'N'

proc emitRound(w: World, spec: MapSpec, out0: var string) =
  let round = w.currentRound
  let ox = spec.origin[0]
  let oy = spec.origin[1]

  for t in 0 .. 1:
    let team = Team(t)
    var ecs, infl, pol, sla, muc = 0
    var topBid = 0
    var bidder = -1
    var best: Robot = nil
    for _, r in w.robotsById:
      if r.team != team: continue
      infl += r.influence
      case r.kind
      of rtEnlightenmentCenter: inc ecs
      of rtPolitician: inc pol
      of rtSlanderer: inc sla
      of rtMuckraker: inc muc
      if r.kind == rtEnlightenmentCenter:
        let bid = r.bid
        if best == nil or bid > topBid or
            (bid == topBid and
             (r.roundsAlive < best.roundsAlive or
              (r.roundsAlive == best.roundsAlive and r.id < best.id))):
          topBid = bid
          best = r
    if best != nil: bidder = best.id
    out0.add(&"R {round} T {teamChar(team)} votes={w.stats.votes[t]} " &
      &"buffs={w.stats.numBuffs[t]} ecs={ecs} infl={infl} pol={pol} " &
      &"sla={sla} muc={muc} topbid={topBid} bidder={bidder}\n")

  ## EXEC ORDER, not id order.
  for id in w.execOrder:
    if id notin w.robotsById: continue
    let r = w.robotsById[id]
    out0.add(&"R {round} U {r.id} t={r.kind} team={teamChar(r.team)} " &
      &"x={r.loc.x + ox} y={r.loc.y + oy} inf={r.influence} " &
      &"conv={r.conviction} cd={r.cooldownTurns.formatFloat(ffDecimal, 9)} " &
      &"flag={r.flag} bid={r.bid} ra={r.roundsAlive}\n")

  out0.add(&"R {round} W winner=" &
    (if w.hasWinner: $teamChar(w.winner) else: "-") & " dom=" &
    (if w.domination == dfNone: "-"
     else: ($w.domination).toUpperAscii().replace("COIN_FLIP",
       "WON_BY_DUBIOUS_REASONS")) & "\n")

proc emitTail(): string =
  ## `--tail`: the same 4 096 log-spaced samples of `getPassiveInfluence` in
  ## (4096, 1e8] that `tools/JavaBc21Tables.java tail` prints, computed here
  ## through the fdlibm port. Outside the committed table's range the sim
  ## computes rather than looks up, so this is the only thing that proves the
  ## computation is the JDK's.
  const
    lo = EmbezzleMaxInfluence + 1
    hi = 100_000_000
    n = 4096
  var previous = -1'i64
  for i in 0 ..< n:
    let f = float64(i) / float64(n - 1)
    var x = int64(round(exp(ln(float64(lo)) + f * (ln(float64(hi)) - ln(float64(lo))))))
    if x <= previous: x = previous + 1
    if x > hi: break
    previous = x
    result.add(&"E {x} {embezzleAt(int(x))}\n")

proc main() =
  var mapName = "maptestsmall"
  var rounds = 200
  var outPath = ""
  for arg in commandLineParams():
    if arg.startsWith("--map:"): mapName = arg[6 .. ^1]
    elif arg.startsWith("--rounds:"): rounds = parseInt(arg[9 .. ^1])
    elif arg.startsWith("--out:"): outPath = arg[6 .. ^1]
    elif arg == "--tail":
      let tail = emitTail()
      stdout.write(tail)
      return


  let spec = loadMap(mapName)
  let sheet = baselineSheet("bc21", blExamplefuncsplayer21)
  var w = newWorld(spec, GameMaxNumberOfRounds)
  var sides = newSides21([sheet, sheet], 0)
  const chassis = [ckExamplefuncsplayer21, ckExamplefuncsplayer21]

  var out0 = newStringOfCap(1 shl 20)
  for round in 1 .. rounds:
    if not w.running: break
    runRound(w, sides, chassis)
    emitRound(w, spec, out0)

  if outPath.len > 0: writeFile(outPath, out0)
  else: stdout.write(out0)

main()
