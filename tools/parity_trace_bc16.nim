## The bc16 parity oracle's NIM side: play the same map with the same chassis
## and print the same trace lines `tools/oracle/bc16/Bc16Trace.java` prints.
##
## CI-TIME ONLY (the `parity-oracle-bc16` job). Nothing here is in the game
## image; it is a separate binary built from the same sim module.
##
##   nim c --hints:off -d:release --path:src -o:/tmp/parity_trace_bc16 \
##     tools/parity_trace_bc16.nim
##   /tmp/parity_trace_bc16 <map> <rounds> [idle|greenhorn]
##
## The `-d:bc16Scenario` build of the same file is the Tier A′ side: it swaps
## the chassis for `src/battlecode/years/bc16/chassis/scenario16.nim`, whose
## Java twin is `tools/oracle/bc16/bc16scenario/RobotPlayer.java`.
##
## The trace is byte-comparable with the Java side, LINE FOR LINE, and every
## coordinate is ORIGIN-RELATIVE on both sides (V3):
##
##   R <round> T <A|B> parts= ar= sc= so= gu= vi= tu= tt=
##   R <round> Z zn= zs= zr= zf= zb= dens= neu= outbreak=
##   R <round> G rubblechk= partschk= rubblesum=<f64 bits> partssum=<f64 bits>
##   R <round> U <id> team= ty= x= y= hp= cd= wd= zi= vi= ra= bd= bc=
##   R <round> D <id> x= y= hp= q=<s>:<r>:<f>:<b>
##   R <round> X world= zombie= idgen=
##   R <round> W winner= dom=
##
## `bc=` is printed as 0: there is no bytecode counter on this side (the port
## meters `DecisionOps` instead — `docs/RULES-BC16.md` §Divergences item 2),
## and `tools/ci/parity_tiers_bc16.py` strips the column from BOTH SIDES by
## one `normalize()` applied to each before the diff (LEARNINGS 2026-09-08:
## bc23's stripped it from the Java side only and every pair "diverged" at
## round 1) and uses the Java value only for the Tier A headroom assertion.
##
## The hex fold is printed the way `java.lang.Long.toHexString` prints it —
## lower case, NO leading zeros — because that is the cheaper half of the
## agreement; the comparator canonicalises both sides anyway, so neither
## emitter's formatting can create or hide a divergence.

import std/[os, strformat, strutils]
import battlecode/[baselines, sheet, sim_types]
import battlecode/years/bc16/rules as r16
import battlecode/years/bc16/world as w16
import battlecode/years/bc16/units as u16
import battlecode/years/bc16/maps as m16

proc teamLetter(t: u16.Team): string =
  case t
  of u16.teamA: "A"
  of u16.teamB: "B"
  of u16.teamNeutral: "N"
  of u16.teamZombie: "Z"

proc javaHex(v: uint64): string =
  ## `java.lang.Long.toHexString`: lower case with NO leading zeros, and the
  ## single digit "0" for zero. Nim's `toHex` pads to sixteen.
  result = toLowerAscii(toHex(v))
  var i = 0
  while i < result.high and result[i] == '0':
    i += 1
  result = result[i .. ^1]

proc javaDomination(d: u16.Domination): string =
  ## `world/DominationFactor.java`'s own names. This port spells them in the
  ## manifest's snake_case `end_reason` vocabulary, so `$d` is NOT the Java
  ## name and a table is required.
  case d
  of u16.dfNone: "-"
  of u16.dfDestroyed: "DESTROYED"
  of u16.dfPwned: "PWNED"
  of u16.dfOwned: "OWNED"
  of u16.dfBarelyBeat: "BARELY_BEAT"
  of u16.dfDubious: "WON_BY_DUBIOUS_REASONS"

proc f6(v: float64): string = &"{v:.6f}"

proc main() =
  if paramCount() < 2:
    quit("usage: parity_trace_bc16 <map> <rounds> [idle|greenhorn]", 2)
  let mapName = paramStr(1)
  let rounds = parseInt(paramStr(2))
  let botName = if paramCount() >= 3: paramStr(3) else: "idle"
  let spec = m16.loadMap(mapName)
  let sheets = [defaultSheet(YearBc16), defaultSheet(YearBc16)]
  var w = w16.newWorld(spec, spec.rounds)
  var sides = r16.newSides16(sheets, 0)
  ## `idle` is the Tier A bot and it is a REAL tier: the zombie half of this
  ## game is engine-side, so an idle player still exercises the den
  ## schedules, the spawn ring, the whole movement ladder, all three RNG
  ## streams, infection, the corpse deposit and the end ladder.
  let chassis =
    if botName == "greenhorn": [r16.ckGreenhorn, r16.ckGreenhorn]
    else: [r16.ckBulwark, r16.ckBulwark]
  let idle = botName == "idle"

  var out0 = newStringOfCap(1 shl 20)
  var lastRound = -1
  for i in 0 ..< rounds:
    if idle:
      ## No chassis at all: only the sim's own half runs.
      r16.runRound(w, sides, chassis)
    else:
      r16.runRound(w, sides, chassis)
    let cur = w.currentRound
    lastRound = cur

    for t in [u16.teamA, u16.teamB]:
      out0.add(&"R {cur} T {teamLetter(t)} parts={f6(w.teamParts(t))}" &
        &" ar={w.robotTypeCount(t, u16.rtArchon)}" &
        &" sc={w.robotTypeCount(t, u16.rtScout)}" &
        &" so={w.robotTypeCount(t, u16.rtSoldier)}" &
        &" gu={w.robotTypeCount(t, u16.rtGuard)}" &
        &" vi={w.robotTypeCount(t, u16.rtViper)}" &
        &" tu={w.robotTypeCount(t, u16.rtTurret)}" &
        &" tt={w.robotTypeCount(t, u16.rtTtm)}\n")

    let dens = w.densStanding()
    out0.add(&"R {cur} Z zn={w.robotCountOf(u16.teamZombie) - dens}" &
      &" zs={w.zombieCountByType(u16.rtStandardzombie)}" &
      &" zr={w.zombieCountByType(u16.rtRangedzombie)}" &
      &" zf={w.zombieCountByType(u16.rtFastzombie)}" &
      &" zb={w.zombieCountByType(u16.rtBigzombie)}" &
      &" dens={dens} neu={w.robotCountOf(u16.teamNeutral)}" &
      &" outbreak={u16.outbreakLevel(max(0, cur))}\n")

    var rubbleSum = 0.0
    var partsSum = 0.0
    for v in w.rubble: rubbleSum += v
    for v in w.partsAt: partsSum += v
    ## THE TWO SUMS ARE RAW IEEE-754 BIT PATTERNS, not decimals: `%.6f`
    ## rounds HALF-UP in `java.lang.String.format` and HALF-TO-EVEN in C's
    ## `printf`, and a 900-term sum lands on an exact decimal tie often
    ## enough that it did -- on `checkers` at round 219 the two sides held
    ## BYTE-IDENTICAL rubble arrays and printed `88935.090413` against
    ## `88935.090412`. Bit patterns have no rounding mode.
    out0.add(&"R {cur} G rubblechk={javaHex(w.rubbleChecksum())}" &
      &" partschk={javaHex(w.partsChecksum())}" &
      &" rubblesum={javaHex(cast[uint64](rubbleSum))}" &
      &" partssum={javaHex(cast[uint64](partsSum))}\n")

    for id in w.execOrder:
      if not w.robotsById.hasKey(id): continue
      let r = w.robotsById[id]
      if r.kind == u16.rtZombieden:
        out0.add(&"R {cur} D {r.id} x={r.loc.x} y={r.loc.y}" &
          &" hp={f6(r.health)} q={r.denQueue[0]}:{r.denQueue[1]}" &
          &":{r.denQueue[2]}:{r.denQueue[3]}\n")
        continue
      out0.add(&"R {cur} U {r.id} team={teamLetter(r.team)}" &
        &" ty={($r.kind).toUpperAscii()} x={r.loc.x} y={r.loc.y}" &
        &" hp={f6(r.health)} cd={f6(r.d.core)} wd={f6(r.d.weapon)}" &
        &" zi={r.inf.zombieTurns} vi={r.inf.viperTurns}" &
        &" ra={r.roundsAlive} bd={(if r.isActive(): 0 else: 1)} bc=0\n")

    out0.add(&"R {cur} X world={javaHex(cast[uint64](w.rand.seed))}" &
      &" zombie={javaHex(cast[uint64](w.zombieRand.seed))}" &
      &" idgen={javaHex(cast[uint64](w.idGen.random.seed))}\n")

    if out0.len > (1 shl 22):
      stdout.write(out0)
      out0.setLen(0)
    if not w.running: break

  out0.add(&"R {lastRound} W winner=" &
    (if w.hasWinner: teamLetter(w.winner) else: "-") &
    &" dom={javaDomination(w.domination)}\n")
  stdout.write(out0)
  stdout.flushFile()
  stderr.writeLine(&"bc16-port map={mapName} rounds={lastRound}" &
    &" ops_peak={w.opsUsedPeak} refused={w.refusedActions}" &
    &" zombies={w.stats.zombiesSpawned}")

main()
