## The NIM side of the bc19 parity trace — line for line what
## `tools/oracle/bc19/bc19_trace.js` prints from the pinned 2019 engine.
##
## CI-ONLY. Compiled once per bot with the matching define, exactly as bc16's
## is:
##
##   -d:bc19Idle            Tier A       (the engine's `bc19idle`)
##   (no define)            Tier A''     (`examplefuncsplayer19`)
##   -d:bc19Scenario        Tier A'      (`bc19scenario`)
##   -d:bc19Scenario -d:bc19ScenarioTrade   (`bc19scenariotrade`)
##   -d:bc19Scenario -d:bc19ScenarioKill    (`bc19scenariokill`)
##   -d:bc19Scenario -d:bc19ScenarioTie     (`bc19scenariotie`)
##
## **EVERY VALUE IN THE TRACE IS AN INTEGER**, which is the single biggest
## thing bc19 has going for it over its siblings: there is no float
## formatting for the two sides to disagree about, and therefore no float
## allowlist in the comparator.
##
##   nim r -d:release --path:src tools/parity_trace_bc19.nim \
##     --bot examplefuncsplayer19 --map seed-0043 --rounds 1000 --out t.txt

import std/[os, strformat, strutils]
import battlecode/sheet
import battlecode/years/bc19/rules

proc arg(name: string, dflt = ""): string =
  for i in 0 ..< paramCount():
    if paramStr(i + 1) == "--" & name and i + 2 <= paramCount():
      return paramStr(i + 2)
  dflt

let botName = arg("bot", "bc19idle")
let mapName = arg("map", "seed-0043")
let maxRounds = parseInt(arg("rounds", "1000"))
let outPath = arg("out", "")

const TeamNames = ["RED", "BLUE"]
const UnitNames = ["CASTLE", "CHURCH", "PILGRIM", "CRUSADER", "PROPHET",
                   "PREACHER"]
const ActionNames = ["NOTHING", "MOVE", "ATTACK", "BUILD", "MINE", "TRADE",
                     "GIVE", "TIMEOUT"]

var lines: seq[string]
proc emit(s: string) = lines.add(s)

let spec = loadMap(mapName)
var w = newWorld(spec, maxRounds)
let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
var sides = newSides19(sheets, 0)
## `bc19idle` and the four scenario bots are selected by the compile-time
## define; `examplefuncsplayer19` is the only one that comes through the
## chassis table, and it is the one bot with a live per-robot
## `java.util.Random` (patch hunk 1) — which is what makes Tier A'' a test of
## `src/battlecode/rng.nim` against a SECOND, INDEPENDENT generator running
## alongside the engine's own MT19937.
let chassis = [ck19Examplefuncsplayer19, ck19Examplefuncsplayer19]

proc emitRoundState(round: int) =
  emit(&"R {round} Q robin={w.robin} live={w.robots.len} ids={w.idsSpent.len}")
  for t in 0 .. 1:
    let team = Team(t)
    var ca, ch, pi, cr, pr, pe, hp = 0
    for r in w.robots:
      if r.team != team: continue
      hp += r.health
      case r.unit
      of ukCastle: inc ca
      of ukChurch: inc ch
      of ukPilgrim: inc pi
      of ukCrusader: inc cr
      of ukProphet: inc pr
      of ukPreacher: inc pe
    emit(&"R {round} T {TeamNames[t]} karb={w.karbonite[t]} " &
      &"fuel={w.fuel[t]} ca={ca} ch={ch} pi={pi} cr={cr} pr={pr} pe={pe} " &
      &"hp={hp} offer={w.lastOffer[t][0]}:{w.lastOffer[t][1]}")
  ## ROBOTS IN QUEUE ORDER, not id order — which is what makes an ordering
  ## bug visible on the round it happens.
  for r in w.robots:
    emit(&"R {round} U {r.id} team={TeamNames[ord(r.team)]} " &
      &"ty={UnitNames[ord(r.unit)]} x={r.x} y={r.y} hp={r.health} " &
      &"k={r.karbonite} f={r.fuel} t={r.turn} sig={r.signal} " &
      &"sr={r.signalRadius} ct={r.castleTalk}")
  ## THE `G` LINE IS THE MOST VALUABLE LINE IN THE TRACE. `mt` and `mti` are
  ## bc19's own addition (D1.2).
  emit(&"R {round} G shadowchk={w.shadowChecksum()} " &
    &"queuechk={w.queueChecksum()} mt={w.gen.stateFold()} mti={w.gen.mti}")

var winnerLine = "R 0 W winner=- wc=-"
var lastRoundEmitted = 0
var roundTurns = 0
while true:
  if w.evaluateIsOver():
    let who = (if w.hasWinner: TeamNames[ord(w.winner)] else: "-")
    let wc = (if w.winCondition >= 0: $w.winCondition else: "-")
    winnerLine = &"R {w.round} W winner={who} wc={wc}"
    break
  if w.robots.len == 0: break
  let idx = (if w.robin >= w.robots.len: 0 else: w.robin)
  let actingId = w.robots[idx].id
  w.enactTurn(sides, chassis)
  inc roundTurns
  emit(&"R {w.round} A {actingId} act={ActionNames[w.lastAction]} " &
    &"dx={w.lastDx} dy={w.lastDy} u={w.lastBuildUnit} gk={w.lastGiveK} " &
    &"gf={w.lastGiveF} tk={w.lastTradeK} tf={w.lastTradeF}")
  if w.robin >= w.robots.len:
    emitRoundState(w.round)
    lastRoundEmitted = w.round
if lastRoundEmitted != w.round:
  emitRoundState(w.round)
emit(winnerLine)

let text = lines.join("\n") & "\n"
if outPath.len > 0: writeFile(outPath, text)
else: stdout.write(text)
stderr.writeLine(&"""parity_trace_bc19 {{"bot":"{botName}","map":"{mapName}",""" &
  &""""rounds":{w.round},"lines":{lines.len},"ids_spent":{w.idsSpent.len},""" &
  &""""win_condition":{w.winCondition}}}""")
