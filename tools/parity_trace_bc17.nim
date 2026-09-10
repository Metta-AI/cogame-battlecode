## The bc17 parity oracle's NIM SIDE: play the same map with the same bot and
## print the same trace lines `tools/oracle/bc17/Bc17Trace.java` prints.
##
## CI-TIME ONLY (the `parity-oracle-bc17` job). Nothing here is in the game
## image; it is a separate binary built from the same sim module, once per
## bot, exactly as bc16's and bc19's are:
##
##   -d:bc17Idle                              Tier A    (`bc17idle`)
##   (no define)                              Tier A''  (`examplefuncsplayer17`)
##   -d:bc17Scenario                          Tier A'   (`bc17scenario`)
##   -d:bc17Scenario -d:bc17ScenarioTree      Tier A'   (`bc17scenariotree`)
##   -d:bc17Scenario -d:bc17ScenarioKill      Tier A'   (`bc17scenariokill`)
##   -d:bc17Scenario -d:bc17ScenarioTie       Tier A'   (`bc17scenariotie`)
##
##   nim c --hints:off -d:release -d:bc17Idle --path:src \
##     -o:/tmp/pt_bc17idle tools/parity_trace_bc17.nim
##   /tmp/pt_bc17idle <map> <rounds>
##
## **EVERY FLOAT IS PRINTED AS ITS RAW IEEE-754 BITS IN HEX, NEVER AS A
## DECIMAL, and that is bc17's one deliberate departure from every sibling
## year.** A float32 needs nine significant decimal digits to round-trip, and
## a formatter mismatch between Java's `%.9g` and Nim's `formatFloat` would
## masquerade as a divergence for a week -- bc16 solved that with a `%.6f`
## convention plus a per-field float allowlist in the comparator, and bc17
## removes the problem instead of managing it. The consequence is that
## `tools/ci/parity_tiers_bc17.py` needs NO float allowlist at all.
##
##   R <round> T <A|B> bul= vp= ar= ga= lj= so= ta= sc= tr= trm=
##   R <round> U <id> team= ty= x= y= hp= ra= ac= mc= wc= shc= cd= bc=
##   R <round> E <id> team= x= y= r= hp= mhp= cb= crob= ra=
##   R <round> B <id> team= x= y= dir= sp= dmg= ra=
##   R <round> A <id> act= tgt= x= y= arg=
##   R <round> G exec= execlen= ubod= tbod= bbod= nb= rid= bid= broad=
##   R <round> W winner= dom=
##
## ROBOTS AND BULLETS IN EXEC ORDER, TREES IN TROVE ORDER -- which is what
## makes an ordering bug visible on the round it happens. `bc=` is printed as
## 0: there is no bytecode counter on this side (the port meters `DecisionOps`
## instead -- docs/RULES-BC17.md V1), and `parity_tiers_bc17.py` strips the
## column from BOTH SIDES by one `normalize()` applied to each (LEARNINGS
## 2026-09-08: bc23's stripped it from the Java side only and every pair
## "diverged" at round 1) and uses the Java value only for the Tier B'
## headroom assertion.
##
## The `A` line's action is the PRIORITY MAXIMUM of the turn, not its last
## action, and `Bc17Trace.java`'s header explains why: the engine records
## FIRE/CHOP/SHAKE/WATER/PLANT/SPAWN_UNIT/STRIKE in `MatchMaker`'s action log
## and records a MOVE, a BROADCAST and a DONATE NOWHERE, so their order
## relative to the logged ones is not recoverable on the Java side at all.
## `actions.nim`'s `noteAction` keeps exactly the same maximum, `tgt` is the
## engine's own target where the engine has one, and `x`/`y` are the robot's
## location WHEN THE LINE IS PRINTED so that neither emitter has to know when
## in the turn the action happened.

import std/[os, strformat, strutils]
import battlecode/sheet
import battlecode/years/bc17/rules

proc javaHex(v: uint64): string =
  ## `java.lang.Long.toHexString`: lower case, NO leading zeros, and the
  ## single digit "0" for zero. Nim's `toHex` pads to sixteen.
  result = toLowerAscii(toHex(v))
  var i = 0
  while i < result.high and result[i] == '0':
    i += 1
  result = result[i .. ^1]

proc bits(v: float32): string = javaHex(uint64(cast[uint32](v)))

const UpperUnitNames = ["ARCHON", "GARDENER", "LUMBERJACK", "SOLDIER",
                        "TANK", "SCOUT"]
  ## `RobotType.name()`, which is NOT this port's own lower-case vocabulary.

const UpperActNames = ["NOTHING", "MOVE", "FIRE_SINGLE", "FIRE_TRIAD",
                       "FIRE_PENTAD", "STRIKE", "CHOP", "SHAKE", "WATER",
                       "PLANT", "HIRE", "BUILD", "BROADCAST", "DONATE",
                       "DISINTEGRATE", "BODY_ATTACK"]

proc teamLetter(t: Team): string =
  case t
  of tA: "A"
  of tB: "B"
  of tNeutral: "N"

proc javaDomination(d: int): string =
  ## `world/DominationFactor.java`'s own names. This port spells its rungs in
  ## the manifest's snake_case `end_reason` vocabulary, so a table is needed.
  DominationNames[d]

proc traceTgt(act, tgt: int): int =
  ## The `tgt` column, restricted to what the ENGINE's own action log carries
  ## on the other side: the tree for SHAKE/WATER/PLANT, the new robot for
  ## HIRE/BUILD, the victory points gained for DONATE, and ZERO everywhere
  ## else -- including a BROADCAST's channel, which the engine does not
  ## record and which a field invented on one side only would turn into a
  ## permanent false divergence (the bc23 mistake).
  case act
  of ActShake, ActWater, ActPlant, ActHire, ActBuild, ActDonate: tgt
  else: 0

proc main() =
  if paramCount() < 2:
    quit("usage: parity_trace_bc17 <map> <rounds>", 2)
  let mapName = paramStr(1)
  let rounds = parseInt(paramStr(2))
  let spec = loadMap(mapName)
  let sheets = [defaultSheet(YearBc17), defaultSheet(YearBc17)]
  var w = newWorld(spec, spec.rounds)
  var sides = newSides17(sheets, 0)
  ## Every bot in this job is selected by a COMPILE-TIME define in
  ## `rules.runControllerFor`; `examplefuncsplayer17` is the only one that
  ## comes through the chassis table, and it is the one bot with a live
  ## per-robot `java.util.Random(id)` -- which is what makes Tier A'' a test
  ## of `src/battlecode/rng.nim` as well as of the rules.
  let chassis = [ck17Examplefuncsplayer17, ck17Examplefuncsplayer17]

  var out0 = newStringOfCap(1 shl 20)
  var lastRound = -1
  var peakBullets = 0
  var actionsEver = 0

  for i in 0 ..< rounds:
    runRound(w, sides, chassis)
    let cur = w.currentRound
    lastRound = cur

    var mature: array[3, int]
    for id in w.treeKeys.valuesDescending:
      if w.trees.hasKey(id) and w.trees[id].roundsAlive > TreeGrowthRounds:
        mature[ord(w.trees[id].team)] += 1
    for t in [tA, tB]:
      out0.add(&"R {cur} T {teamLetter(t)} bul={bits(w.bulletSupply[ord(t)])}" &
        &" vp={w.victoryPoints[ord(t)]}" &
        &" ar={w.unitCount(t, rtArchon)}" &
        &" ga={w.unitCount(t, rtGardener)}" &
        &" lj={w.unitCount(t, rtLumberjack)}" &
        &" so={w.unitCount(t, rtSoldier)}" &
        &" ta={w.unitCount(t, rtTank)}" &
        &" sc={w.unitCount(t, rtScout)}" &
        &" tr={w.treeCount[ord(t)]}" &
        &" trm={mature[ord(t)]}\n")

    ## ROBOTS AND BULLETS IN EXEC ORDER.
    var bulletLines = ""
    var actionLines = ""
    var liveBullets = 0
    for id in w.execOrder:
      if w.robots.hasKey(id):
        let r = w.robots[id]
        out0.add(&"R {cur} U {r.id} team={teamLetter(r.team)}" &
          &" ty={UpperUnitNames[ord(r.kind)]}" &
          &" x={bits(r.loc.x)} y={bits(r.loc.y)} hp={bits(r.health)}" &
          &" ra={r.roundsAlive} ac={r.attackCount} mc={r.moveCount}" &
          &" wc={r.waterCount} shc={r.shakeCount}" &
          &" cd={r.buildCooldownTurns} bc=0\n")
        let la = w.lastAction.getOrDefault(r.id,
          (act: ActNothing, tgt: 0, x: 0'f32, y: 0'f32, arg: 0'f32))
        if la.act != ActNothing: actionsEver += 1
        actionLines.add(&"R {cur} A {r.id} act={UpperActNames[la.act]}" &
          &" tgt={traceTgt(la.act, la.tgt)}" &
          &" x={bits(r.loc.x)} y={bits(r.loc.y)} arg={bits(0'f32)}\n")
      elif w.bullets.hasKey(id):
        let b = w.bullets[id]
        liveBullets += 1
        bulletLines.add(&"R {cur} B {b.id} team={teamLetter(b.team)}" &
          &" x={bits(b.loc.x)} y={bits(b.loc.y)} dir={bits(b.dir.radians)}" &
          &" sp={bits(b.speed)} dmg={bits(b.damage)} ra={b.roundsAlive}\n")

    ## TREES IN TROVE ORDER (D1) -- the order the float32 income sum is
    ## accumulated in, so an ordering bug is visible here before it is
    ## visible in the bullet supply.
    for id in w.treeKeys.valuesDescending:
      if not w.trees.hasKey(id): continue
      let tr = w.trees[id]
      out0.add(&"R {cur} E {tr.id} team={teamLetter(tr.team)}" &
        &" x={bits(tr.loc.x)} y={bits(tr.loc.y)} r={bits(tr.radius)}" &
        &" hp={bits(tr.health)} mhp={bits(tr.maxHealth)}" &
        &" cb={tr.containedBullets}" &
        &" crob=" & (if tr.containedRobot < 0: "-"
                     else: UpperUnitNames[tr.containedRobot]) &
        &" ra={tr.roundsAlive}\n")
    out0.add(bulletLines)
    out0.add(actionLines)
    if liveBullets > peakBullets: peakBullets = liveBullets

    out0.add(&"R {cur} G exec={javaHex(w.execOrderFold())}" &
      &" execlen={w.execOrder.len}" &
      &" ubod={javaHex(w.robotBodyFold())}" &
      &" tbod={javaHex(w.treeBodyFold())}" &
      &" bbod={javaHex(w.bulletBodyFold())}" &
      &" nb={liveBullets}" &
      &" rid={w.peekRobotId()}" &
      &" bid={int(w.bulletIdGen.reserved[w.bulletIdGen.cursor])}" &
      &" broad={javaHex(w.broadcasterFold())}\n")

    if out0.len > (1 shl 22):
      stdout.write(out0)
      out0.setLen(0)
    if not w.running: break

  out0.add(&"R {lastRound} W winner=" &
    (if w.hasWinner: teamLetter(w.winner) else: "-") &
    &" dom={javaDomination(w.domination)}\n")
  stdout.write(out0)
  stdout.flushFile()
  stderr.writeLine(&"bc17-port map={mapName} rounds={lastRound}" &
    &" peak_bullets={peakBullets} actions={actionsEver}" &
    &" ops_peak={w.stats.decisionOpsPeak[0]}:{w.stats.decisionOpsPeak[1]}" &
    &" refused={w.stats.refusedActions[0]}:{w.stats.refusedActions[1]}")

main()
