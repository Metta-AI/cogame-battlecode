## The bc22 round loop, the Singularity ladder, the points formula and one game.
##
## `runRound` mirrors `GameWorld.runRound` / `processBeginningOfRound` /
## `updateDynamicBodies` / `processEndOfRound` step for step, and THE STEP LIST
## IS THE RULES: a re-ordering is a rules change and bumps `GameVersion`
## (docs/RULES-BC22.md §The round loop).
##
##   1. beginning of round: `currentRound += 1`; every robot's
##      `processBeginningOfRound`, which ONLY clears the indicator string and is
##      therefore a NO-OP here. THERE IS NO ROUND-1 SPECIAL CASE: both teams'
##      200 Pb and 0 Au are credited by the world's constructor, once, PER TEAM
##      (not per archon), before round 1 begins.
##   2. the turn order: a SNAPSHOT of the dynamic exec order taken before the
##      sweep, with an `existsRobot` guard.
##   3. each robot's turn: both cooldowns decay by 10 and floor at 0, the
##      `DecisionOps` budget resets, the controller runs, `roundsAlive += 1`,
##      and a robot that disintegrated is destroyed at the end of its OWN turn.
##   4. end of round, in exactly this order:
##      a. `+2` lead to team A, then `+2` to team B — BEFORE the anomaly
##      b. every robot's end of round, whose body in 2022 is the comment
##         `// anything` and NOTHING ELSE — a genuine no-op (D1)
##      c. the scheduled anomaly, if one is due this round; exactly one entry is
##         consumed
##      d. the map's `+5` to every square holding `> 0`, every 20 rounds —
##         AFTER the anomaly
##      e. roll over the per-round team deltas
##      f. the end-of-match check: the Singularity ladder at round 2000
##      g. `running = false` if a winner is set; then the state hash
##
## STEPS 1b AND 4b ARE HASH-ORDER SWEEPS IN THE ENGINE
## (`ObjectInfo.eachRobot` -> trove `forEachValue`) AND ARE NOT PORTED AT ALL,
## because in 2022 neither has any observable behaviour: `processBeginningOfRound`
## clears an indicator string this port does not have, and
## `InternalRobot.processEndOfRound`'s whole body is a comment. That is D1, and
## it is stated so nobody ports it "to be safe" and then has to justify it.
## `robotsArray()`, by contrast, IS load-bearing at exactly one site
## (`causeChargeGlobal`) and IS ported, in `trove.nim` (D2).

import std/[algorithm, monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import world, buildings, economy, anomaly, maps, knobs
import chassis/[kit, wololo, scaffold22, scenario22]

export world, buildings, economy, anomaly, maps, knobs, kit

type
  ChassisKind22* = enum
    ckWololo = "wololo"
    ckExamplefuncsplayer22 = "examplefuncsplayer22"

  GameOutcome22* = object
    index*: int
    mapName*: string
    sideAslot*: int              ## which SEAT plays team A this game
    roundsPlayed*: int
    winnerSlot*: int             ## -1 = no winner recorded (abandoned)
    endReason*: string
    points*: array[2, int]       ## BY SEAT
    hashChain*: string
    roundChains*: string
    aborted*: bool
    ## Per-game statistics, BY SEAT. These are the optional year-specific
    ## siblings in `results.games[]`.
    archonsStart*: array[2, int]
    archonsEnd*: array[2, int]
    archonsLost*: array[2, int]
    archonRelocations*: array[2, int]
    leadMined*: array[2, int]
    goldMined*: array[2, int]
    leadEnd*: array[2, int]
    goldEnd*: array[2, int]
    leadNetWorthEnd*: array[2, int]
    goldNetWorthEnd*: array[2, int]
    leadReclaimed*: array[2, int]
    goldReclaimed*: array[2, int]
    squaresMinedDry*: array[2, int]
    unitsBuilt*: array[2, int]
    minersBuilt*: array[2, int]
    buildersBuilt*: array[2, int]
    soldiersBuilt*: array[2, int]
    sagesBuilt*: array[2, int]
    labsBuilt*: array[2, int]
    labsFinished*: array[2, int]
    watchtowersBuilt*: array[2, int]
    watchtowersFinished*: array[2, int]
    mutationsL2*: array[2, int]
    mutationsL3*: array[2, int]
    transmutes*: array[2, int]
    goldTransmuted*: array[2, int]
    leadSpentTransmuting*: array[2, int]
    repairs*: array[2, int]
    hpRepaired*: array[2, int]
    envisions*: array[2, int]
    damageDealt*: array[2, int]
    sageDamage*: array[2, int]
    soldierDamage*: array[2, int]
    watchtowerDamage*: array[2, int]
    arrayWrites*: array[2, int]
    transforms*: array[2, int]
    roundsWithALab*: array[2, int]
    robotsAlive*: array[2, int]
    robotsLost*: array[2, int]
    anomalyLossesCharge*: array[2, int]
    anomalyLossesFuryHp*: array[2, int]
    anomalyLossesAbyssLead*: array[2, int]
    anomaliesDodged*: array[2, int]
    archonsAliveAt1500*: array[2, int]
    ## Scalars.
    archonsPerSide*: int
    leadOnMapStart*: int
    leadOnMapEnd*: int
    leadSquaresStart*: int
    rubbleMean*: int
    anomaliesScheduled*: int
    vortexesScheduled*: int
    singularityRound*: int

proc chassisFromName*(name: string): ChassisKind22 =
  case name.strip().toLowerAscii()
  of "examplefuncsplayer22", "examplefuncsplayer", "scaffold", "example":
    ckExamplefuncsplayer22
  else: ckWololo

proc chassisKindFor*(sc: ScriptedChassis): ChassisKind22 =
  ## The year-neutral `ScriptedChassis` mapped into bc22's own kind. A name
  ## belonging to another year falls back to bc22's STRONG chassis.
  case sc
  of scExamplefuncsplayer22: ckExamplefuncsplayer22
  else: ckWololo

proc slotOf*(outcome: GameOutcome22, team: Team): int =
  if team == teamA: outcome.sideAslot else: 1 - outcome.sideAslot

proc newSides22*(sheets: array[2, Sheet], sideAslot: int): array[2, Side] =
  ## `sides[ord(team)]`. Which SEAT is behind team A alternates per game.
  result[0] = newSide(teamA, sheets[sideAslot].doctrine22)
  result[1] = newSide(teamB, sheets[1 - sideAslot].doctrine22)

proc runControllerFor*(w: World, sides: array[2, Side],
                       chassis: array[2, ChassisKind22], r: Robot) =
  when defined(bc22Scenario):
    runScenario22(w, r)
  else:
    let side = sides[ord(r.team)]
    case chassis[ord(r.team)]
    of ckWololo: runWololo(w, side, r)
    of ckExamplefuncsplayer22: runScaffold22(w, r)

# ---------------------------------------------------------------------------
#  The Singularity ladder, in the engine's own order
# ---------------------------------------------------------------------------

func timeLimitReached*(w: World): bool =
  ## `GameWorld.timeLimitReached` is `currentRound >= gameMap.getRounds()`, and
  ## every 2022 map's `rounds` is `GAME_MAX_NUMBER_OF_ROUNDS = 2000` (the field
  ## is not even in the map file — `GameMapIO` hard-codes it). ROUND 2000 IS
  ## PLAYED.
  w.currentRound >= w.maxRounds

proc checkEndOfMatch*(w: World) =
  if w.timeLimitReached() and not w.hasWinner:
    if w.setWinnerIfMoreArchons(): discard
    elif w.setWinnerIfMoreGoldValue(): discard
    elif w.setWinnerIfMoreLeadValue(): discard
    else: w.setWinnerArbitrary()
    discard w.beat(BeatSingularity, "singularity", ord(w.domination),
                   w.robotCountByType(teamA, rtArchon) * 100 +
                     w.robotCountByType(teamB, rtArchon),
                   w.goldNetWorth(teamA) * 100000 + w.goldNetWorth(teamB),
                   $w.leadNetWorth(teamA) & ":" & $w.leadNetWorth(teamB))
  if w.hasWinner:
    w.running = false

# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

proc gamePoints*(w: World): array[2, int] =
  ## A continuous reading of the engine's OWN Singularity ladder, in its own
  ## priority order and weighted in that order: archons 64, gold net worth 24,
  ## lead net worth 12.
  ##
  ## The weights are SUPER-INCREASING (`24 > 12` and `64 > 24 + 12`), so a
  ## DECISIVE margin on a higher rung dominates everything below it. THIS NOTE
  ## DOES NOT CLAIM MORE THAN THAT: a one-unit margin on a rung with large
  ## totals gives an arbitrarily small share advantage (4 vs 3 archons is
  ## `4/7 - 3/7 = 0.143`, i.e. 9.1 points, against 36 available below), so
  ## `points` ALONE CAN FAVOUR THE LOSER. `points` measures the SHAPE of the
  ## game, not who won it; `results.scores` adds 200 per game won and IS
  ## win-dominated by construction (§The game, Scoring).
  ##
  ## Every share is narrowed through FLOAT32 before the weighted sum and the sum
  ## is TRUNCATED by the `int()` cast — for RECORDER/RE-DERIVER AGREEMENT: the
  ## same arithmetic runs natively on x86-64 and in wasm32 and must produce the
  ## same integer.
  let archons = [w.robotCountByType(teamA, rtArchon),
                 w.robotCountByType(teamB, rtArchon)]
  let gold = [w.goldNetWorth(teamA), w.goldNetWorth(teamB)]
  let lead = [w.leadNetWorth(teamA), w.leadNetWorth(teamB)]
  for t in 0 .. 1:
    let o = 1 - t
    result[t] = int(64.0'f32 * share(archons[t], archons[o]) +
                    24.0'f32 * share(gold[t], gold[o]) +
                    12.0'f32 * share(lead[t], lead[o]))

# ---------------------------------------------------------------------------
#  One round
# ---------------------------------------------------------------------------

proc processBeginningOfRound(w: World) =
  ## Rule 1. `currentRound++`; then `processBeginningOfRound` on every robot,
  ## which clears the indicator string and NOTHING ELSE — this port has no
  ## indicator strings, so step 1b has no observable effect and no code (D1).
  inc w.currentRound

proc processBeginningOfTurn(w: World, r: Robot) =
  r.actionCooldown = max(0, r.actionCooldown - CooldownsPerTurn)
  r.movementCooldown = max(0, r.movementCooldown - CooldownsPerTurn)
  r.opsLeft = budgetFor(r.kind)
  r.opsUsed = 0

proc processEndOfTurn(w: World, r: Robot) =
  r.roundsAlive += 1
  if r.opsUsed > w.opsUsedPeak: w.opsUsedPeak = r.opsUsed

proc emitAnomalyBeat(w: World, report: AnomalyReport) =
  discard w.beat(BeatAnomalyStruck, "anomaly_struck", ord(report.kind),
                 report.droidsLost[0] * 1000 + report.droidsLost[1],
                 report.turretHpLost[0] * 100000 + report.turretHpLost[1],
                 $report.leadLost[0] & ":" & $report.leadLost[1] & ":" &
                   (if report.rubbleChanged: "1" else: "0"))

proc runRound*(w: World, sides: array[2, Side],
               chassis: array[2, ChassisKind22]) =
  w.processBeginningOfRound()
  ## THE CHASSIS'S ROUND-LEVEL BOOKKEEPING RUNS FIRST, so every robot this round
  ## reads the same census and the same anomaly programme.
  when not defined(bc22Scenario):
    for t in 0 .. 1:
      case chassis[t]
      of ckWololo: beginRound(w, sides[t])
      of ckExamplefuncsplayer22: discard
  for t in 0 .. 1:
    w.lostThisRound[t] = 0
    w.attackersLostThisRound[t] = 0

  ## Rules 2 and 3. THE ARRAY BEING ITERATED IS A SNAPSHOT taken before the
  ## sweep (`dynamicBodyExecOrder.toArray()`), so a robot built this round does
  ## NOT take a turn this round, and a robot destroyed mid-sweep is skipped by
  ## the `existsRobot` guard.
  let snapshot = w.execOrder
  for id in snapshot:
    if not w.existsRobot(id): continue
    let r = w.robotsById[id]
    w.processBeginningOfTurn(r)
    w.runControllerFor(sides, chassis, r)
    if w.existsRobot(id):
      w.processEndOfTurn(r)
      if r.disintegrated:
        w.destroyRobot(id)

  ## Rule 4a: the passive +2, BEFORE the anomaly.
  w.addPassiveLead()
  ## Rule 4b: every robot's end of round — a GENUINE NO-OP in 2022 (D1).
  ## Rule 4c: the scheduled anomaly.
  let fired = w.runScheduledAnomaly()
  if fired.fired:
    w.emitAnomalyBeat(fired.report)
  ## Rule 4d: the map's +5, AFTER the anomaly.
  w.regenerateMapLead()

  ## Beats that read the round's own deltas.
  if w.attackersLostThisRound[0] > 0 and w.attackersLostThisRound[1] > 0:
    discard w.beat(BeatDuel, "duel", w.attackersLostThisRound[0],
                   w.attackersLostThisRound[1])
  for t in 0 .. 1:
    if w.lostThisRound[t] >= 5:
      discard w.beat(BeatRout, "rout", t, w.lostThisRound[t])
    if w.archonsAlive[t] < w.stats.archonsStart[t] - w.stats.archonsLost[t]:
      discard
  for t in 0 .. 1:
    let lost = w.stats.archonsStart[t] - w.robotCountByType(Team(t), rtArchon)
    if lost > w.stats.archonsLost[t]:
      w.stats.archonsLost[t] = lost
      discard w.beat(BeatArchonLost, "archon_lost", t,
                     w.robotCountByType(Team(t), rtArchon),
                     goldDropped(rtArchon, 1))
  if w.currentRound == 1500:
    for t in 0 .. 1:
      w.stats.archonsAliveAt1500[t] = w.robotCountByType(Team(t), rtArchon)

  ## Rule 4e/4f/4g.
  w.checkEndOfMatch()

  ## The per-round hash chain. Fourteen per-team values plus seven globals; a
  ## re-derivation that diverged only in one of them would otherwise reproduce
  ## the chain and report no mismatch (the GV02 lesson).
  for t in 0 .. 1:
    let team = Team(t)
    w.mixHash(w.robotCountByType(team, rtArchon))
    w.mixHash(w.robotCountByType(team, rtLaboratory) * 1000000 +
              w.robotCountByType(team, rtWatchtower) * 100000 +
              w.robotCountByType(team, rtMiner) * 1000 +
              w.robotCountByType(team, rtBuilder) * 100 +
              w.robotCountByType(team, rtSoldier) * 10 +
              w.robotCountByType(team, rtSage))
    w.mixHash(w.modeCount(team, rmDroid) * 1000000 +
              w.modeCount(team, rmPrototype) * 10000 +
              w.modeCount(team, rmTurret) * 100 +
              w.modeCount(team, rmPortable))
    w.mixHash(w.totalHealth(team))
    w.mixHash(w.buildingLevelSum(team))
    w.mixHash(w.stats.lead[t])
    w.mixHash(w.stats.gold[t])
    w.mixHash(w.leadNetWorth(team))
    w.mixHash(w.goldNetWorth(team))
  w.mixHash(w.currentRound)
  w.mixHashU(w.rubbleChecksum())
  w.mixHashU(w.leadChecksum())
  w.mixHashU(w.goldChecksum())
  w.mixHashU(w.sharedArrayChecksum())
  w.mixHash(w.execOrder.len)
  w.mixHashU(w.hashOrderChecksum())
  w.mixHash(w.anomalyCursor)

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

proc endReasonFor(w: World): string =
  case w.domination
  of dfNone: "more_archons"
  else: $w.domination

proc harvest(w: World, outcome: var GameOutcome22) =
  for team in [teamA, teamB]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    outcome.archonsStart[slot] = w.stats.archonsStart[t]
    outcome.archonsEnd[slot] = w.robotCountByType(team, rtArchon)
    outcome.archonsLost[slot] = w.stats.archonsLost[t]
    outcome.archonRelocations[slot] = w.stats.archonRelocations[t]
    outcome.leadMined[slot] = w.stats.leadMined[t]
    outcome.goldMined[slot] = w.stats.goldMined[t]
    outcome.leadEnd[slot] = w.stats.lead[t]
    outcome.goldEnd[slot] = w.stats.gold[t]
    outcome.leadNetWorthEnd[slot] = w.leadNetWorth(team)
    outcome.goldNetWorthEnd[slot] = w.goldNetWorth(team)
    outcome.leadReclaimed[slot] = w.stats.leadReclaimed[t]
    outcome.goldReclaimed[slot] = w.stats.goldReclaimed[t]
    outcome.squaresMinedDry[slot] = w.stats.squaresMinedDry[t]
    outcome.unitsBuilt[slot] = w.stats.unitsBuilt[t]
    outcome.minersBuilt[slot] = w.stats.minersBuilt[t]
    outcome.buildersBuilt[slot] = w.stats.buildersBuilt[t]
    outcome.soldiersBuilt[slot] = w.stats.soldiersBuilt[t]
    outcome.sagesBuilt[slot] = w.stats.sagesBuilt[t]
    outcome.labsBuilt[slot] = w.stats.labsBuilt[t]
    outcome.labsFinished[slot] = w.stats.labsFinished[t]
    outcome.watchtowersBuilt[slot] = w.stats.watchtowersBuilt[t]
    outcome.watchtowersFinished[slot] = w.stats.watchtowersFinished[t]
    outcome.mutationsL2[slot] = w.stats.mutationsL2[t]
    outcome.mutationsL3[slot] = w.stats.mutationsL3[t]
    outcome.transmutes[slot] = w.stats.transmutes[t]
    outcome.goldTransmuted[slot] = w.stats.goldTransmuted[t]
    outcome.leadSpentTransmuting[slot] = w.stats.leadSpentTransmuting[t]
    outcome.repairs[slot] = w.stats.repairs[t]
    outcome.hpRepaired[slot] = w.stats.hpRepaired[t]
    outcome.envisions[slot] = w.stats.envisions[t]
    outcome.damageDealt[slot] = w.stats.damageDealt[t]
    outcome.sageDamage[slot] = w.stats.sageDamage[t]
    outcome.soldierDamage[slot] = w.stats.soldierDamage[t]
    outcome.watchtowerDamage[slot] = w.stats.watchtowerDamage[t]
    outcome.arrayWrites[slot] = w.stats.arrayWrites[t]
    outcome.transforms[slot] = w.stats.transforms[t]
    outcome.roundsWithALab[slot] = w.stats.roundsWithALab[t]
    outcome.robotsAlive[slot] = w.robotsAlive(team)
    outcome.robotsLost[slot] = w.stats.robotsLost[t]
    outcome.anomalyLossesCharge[slot] = w.stats.anomalyLossesCharge[t]
    outcome.anomalyLossesFuryHp[slot] = w.stats.anomalyLossesFuryHp[t]
    outcome.anomalyLossesAbyssLead[slot] = w.stats.anomalyLossesAbyssLead[t]
    outcome.anomaliesDodged[slot] = w.stats.anomaliesDodged[t]
    outcome.archonsAliveAt1500[slot] = w.stats.archonsAliveAt1500[t]
  outcome.archonsPerSide = w.stats.archonsStart[0]
  for v in w.map.lead: outcome.leadOnMapStart += v
  for v in w.map.lead:
    if v > 0: outcome.leadSquaresStart += 1
  outcome.leadOnMapEnd = w.leadOnMap()
  var rubbleTotal = 0
  for v in w.map.rubble: rubbleTotal += v
  ## In TENTHS, so the results document carries an integer and the viewer's
  ## `fmtStat` prints `x.x` (endcard fix 3: no raw unrounded floats).
  outcome.rubbleMean =
    if w.map.rubble.len == 0: 0
    else: (rubbleTotal * 10) div w.map.rubble.len
  outcome.anomaliesScheduled = w.map.anomalies.len
  for a in w.map.anomalies:
    if a.kind == anVortex: outcome.vortexesScheduled += 1
  outcome.singularityRound = w.maxRounds
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(teamA)] = pts[0]
  outcome.points[outcome.slotOf(teamB)] = pts[1]
  outcome.roundsPlayed = w.currentRound
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], chassis: array[2, ChassisKind22],
  index, sideAslot, maxRounds: int, budgetSeconds: int,
  onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome22) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of monotonic
  ## wall clock elapse. An abandoned game is DISCARDED by the match (its
  ## `aborted` flag says so); it is never scored half-played.
  var w = newWorld(spec, maxRounds)
  w.loadTransmuteTable()
  var sides = newSides22(sheets, sideAslot)
  ## `sides` is indexed by TEAM and `chassis` arrives by SEAT — re-index once
  ## here so the round loop never has to.
  let chassisByTeam = [chassis[sideAslot], chassis[1 - sideAslot]]
  var outcome = GameOutcome22(
    index: index, mapName: spec.name, sideAslot: sideAslot, winnerSlot: -1)
  var leadOnMap = 0
  for v in spec.lead: leadOnMap += v
  discard w.beat(BeatGameStart, "game_start", index, w.width, w.height,
    spec.name & ":" & $w.stats.archonsStart[0] & ":" & $leadOnMap & ":" &
      $spec.anomalies.len)
  let started = getMonoTime()
  let budget = initDuration(seconds = budgetSeconds)
  while w.running and w.currentRound < maxRounds:
    runRound(w, sides, chassisByTeam)
    outcome.roundChains.add(toHex(w.hashChain))
    if onRound != nil:
      onRound(w, w.currentRound)
    if budgetSeconds > 0 and (w.currentRound and 0x1F) == 0 and
        getMonoTime() - started >= budget:
      outcome.aborted = true
      break
  if outcome.aborted:
    outcome.endReason = "abandoned"
    harvest(w, outcome)
    outcome.winnerSlot = -1
    return (w, outcome)
  outcome.endReason = w.endReasonFor()
  harvest(w, outcome)
  if w.hasWinner:
    outcome.winnerSlot = outcome.slotOf(w.winner)
  (w, outcome)
