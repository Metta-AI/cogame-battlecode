## The bc16 round loop, the four-rung end ladder, the points formula and one
## game.
##
## `runRound` mirrors `GameWorld.runRound` / `processBeginningOfRound` /
## `processEndOfRound` step for step, and THE STEP LIST IS THE RULES: a
## re-ordering is a rules change and bumps `GameVersion`
## (docs/RULES-BC16.md §The round loop).
##
##   1. beginning of round: `currentRound += 1` — FROM -1, so the first round
##      played is round 0 and the last is 2999. Then every robot's
##      `processBeginningOfRound`, whose body in 2016 is EMPTY (`:431-432`),
##      and `controlProvider.roundStarted()`, which is empty in both providers.
##      Both are genuine no-ops with no observable effect and are therefore
##      NOT PORTED AT ALL (D1) — and both iterate a `LinkedHashMap` anyway, so
##      even their order is insertion order.
##   2. the turn order: a SNAPSHOT of the insertion-ordered id list taken
##      BEFORE the sweep, with a `robot == null` guard, so a robot built this
##      round takes NO turn this round and a robot destroyed mid-sweep is
##      skipped.
##   3. each robot's turn, in four parts:
##      a. `processBeginningOfTurn`: `decrementDelays()` (V1: exactly 1.0 off
##         both counters, each floored at 0), `repairCount = 0`,
##         `basicSignalCount = 0`, `messageSignalCount = 0`, and the
##         `DecisionOps` budget reset — to ZERO for a robot with
##         `!isActive()`, which is how a soldier built this round is a live,
##         blocking, damageable robot that does nothing for 12 turns;
##      b. run the controller: a PLAYER robot runs its team's chassis under
##         its doctrine; a ZOMBIE or a DEN runs the engine's own
##         `ZombieControlProvider` logic, which IS the sim and costs nothing
##         against any budget; a NEUTRAL robot does nothing;
##      c. record the ops used (telemetry only — NO RULE READS IT, which is
##         what V1 buys);
##      d. `processEndOfTurn`, AND ONLY IF `health > 0`: `roundsAlive += 1`
##         then `processBeingInfected()` — the viper strain's 2.0 damage,
##         which can kill, and then the robot IS infected, so it becomes a
##         zombie — and finally the disintegrate suicide.
##   4. end of round, in exactly this order:
##      a. every robot's `processEndOfRound` — EMPTY in 2016 (`:459`), a
##         genuine no-op (D1);
##      b. parts income: A's stockpile `+= max(0, 2 - 0.01 * robots)`, then
##         B's;
##      c. the end-of-match check, if `timeLimitReached()` AND no winner is
##         set: the four-rung ladder, first non-zero difference wins, on
##         EXACT FLOAT64 DIFFERENCES;
##      d. `running = false` if a winner is set; then the state hash.

import std/[monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import world, economy, signals, zombies, maps, knobs
import chassis/[kit, bulwark, greenhorn, scenario16]

export world, economy, signals, zombies, maps, knobs, kit

type
  ChassisKind16* = enum
    ckBulwark = "bulwark"
    ckGreenhorn = "greenhorn"

  GameOutcome16* = object
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
    ## Per-game statistics, BY SEAT — the optional year-specific siblings in
    ## `results.games[]`.
    archonsStart*: array[2, int]
    archonsEnd*: array[2, int]
    archonsLost*: array[2, int]
    archonHealthEndTenths*: array[2, int]
    partsEndTenths*: array[2, int]
    partsWorthEnd*: array[2, int]
    partsCollectedTenths*: array[2, int]
    partsIncomeTenths*: array[2, int]
    partsSpentTenths*: array[2, int]
    unitsBuilt*: array[2, int]
    scoutsBuilt*: array[2, int]
    soldiersBuilt*: array[2, int]
    guardsBuilt*: array[2, int]
    vipersBuilt*: array[2, int]
    turretsBuilt*: array[2, int]
    turretPacks*: array[2, int]
    robotsAlive*: array[2, int]
    robotsLost*: array[2, int]
    robotsTurned*: array[2, int]
    neutralsActivated*: array[2, int]
    neutralArchonsActivated*: array[2, int]
    densDestroyed*: array[2, int]
    denDamageDealt*: array[2, int]
    damageDealt*: array[2, int]
    zombieDamageDealt*: array[2, int]
    zombieDamageTaken*: array[2, int]
    enemyDamageDealt*: array[2, int]
    enemyDamageTaken*: array[2, int]
    infectionsSuffered*: array[2, int]
    infectionsInflicted*: array[2, int]
    viperInfectionDamage*: array[2, int]
    repairs*: array[2, int]
    hpRepaired*: array[2, int]
    rubbleClearedTenths*: array[2, int]
    rubbleCreatedTenths*: array[2, int]
    squaresOpened*: array[2, int]
    basicSignals*: array[2, int]
    messageSignals*: array[2, int]
    archonPartsWalks*: array[2, int]
    archonsAliveAt2000*: array[2, int]
    ## Scalars.
    archonsPerSide*: int
    densPerSide*: int
    densOnMap*: int
    partsOnMapStart*: int
    partsSquaresStart*: int
    rubbleMeanTenths*: int
    impassableSquaresStart*: int
    impassableSquaresEnd*: int
    neutralsOnMapStart*: int
    zombiesSpawned*: int
    zombiesAliveEnd*: int
    zombiesKilled*: int
    outbreakLevelEnd*: int
    scheduleRounds*: int
    tiebreakRound*: int

proc chassisFromName*(name: string): ChassisKind16 =
  case name.strip().toLowerAscii()
  of "greenhorn", "scaffold", "example", "examplefuncsplayer":
    ckGreenhorn
  else: ckBulwark

proc chassisKindFor*(sc: ScriptedChassis): ChassisKind16 =
  ## The year-neutral `ScriptedChassis` mapped into bc16's own kind. A name
  ## belonging to another year falls back to bc16's STRONG chassis, so a bc22
  ## name on a bc16 game plays `bulwark` rather than nothing.
  case sc
  of scGreenhorn: ckGreenhorn
  else: ckBulwark

proc slotOf*(outcome: GameOutcome16, team: Team): int =
  if team == teamA: outcome.sideAslot else: 1 - outcome.sideAslot

proc newSides16*(sheets: array[2, Sheet], sideAslot: int): array[2, Side] =
  ## `sides[ord(team)]`. Which SEAT is behind team A alternates per game.
  result[0] = newSide(teamA, sheets[sideAslot].doctrine16)
  result[1] = newSide(teamB, sheets[1 - sideAslot].doctrine16)

proc runControllerFor*(w: World, sides: array[2, Side],
                       chassis: array[2, ChassisKind16], r: Robot) =
  ## Rule 3.2. A ZOMBIE or a DEN is the SIM, not a chassis: it runs the
  ## ported `ZombieControlProvider` and costs nothing against any budget. A
  ## NEUTRAL robot takes its turn and does nothing.
  if r.team == teamZombie:
    w.runZombieController(r)
    return
  if r.team == teamNeutral:
    return
  if not r.canExecuteCode():
    ## `getBytecodeLimit()` returns 0 for a robot that cannot execute code,
    ## so its controller cannot do anything at all.
    return
  when defined(bc16Idle):
    ## **TIER A**, and it is CI-only: `-d:bc16Idle` is the Nim twin of
    ## `tools/oracle/bc16/bc16idle/RobotPlayer.java`, whose whole body is
    ## `while (true) Clock.yield();`. It is not a degenerate tier — the
    ## zombie half of this game is ENGINE-SIDE, so an idle player still
    ## exercises the den schedules and their per-den split, the spawn ring's
    ## direction and chirality, `spawnAllPossible` and its proximity-damage
    ## fallback, the whole eight-step zombie movement ladder, ALL THREE RNG
    ## STREAMS, infection and the die-and-turn conversion, the corpse-rubble
    ## deposit, `clearRubble` by digging zombies, the parts income curve, both
    ## factions' archons being eaten, the mid-turn `DESTROYED` check and the
    ## round-2999 ladder.
    return
  when defined(bc16Scenario):
    runScenario16(w, r)
  else:
    let side = sides[ord(r.team)]
    case chassis[ord(r.team)]
    of ckBulwark: runBulwark(w, side, r)
    of ckGreenhorn: runGreenhorn(w, r)

# ---------------------------------------------------------------------------
#  The four-rung end ladder, in the engine's own order
# ---------------------------------------------------------------------------

func timeLimitReached*(w: World): bool =
  ## `GameWorld.timeLimitReached` is `currentRound >= gameMap.getRounds() - 1`,
  ## and every official map declares `rounds = 3000`, so it fires at the END
  ## OF ROUND 2999 — round 2999 IS PLAYED.
  w.currentRound >= w.maxRounds - 1

proc setWinnerIfNonzero(w: World, n: float64, d: Domination): bool =
  ## `GameWorld.setWinnerIfNonzero`: `n > 0 -> A`, `n < 0 -> B`, and the
  ## return value is `n != 0`. EXACT FLOAT64 comparisons.
  if n > 0.0: w.setWinner(teamA, d)
  elif n < 0.0: w.setWinner(teamB, d)
  n != 0.0

proc checkEndOfMatch*(w: World) =
  ## `processEndOfRound`'s ladder (`:634-679`), first non-zero difference
  ## wins:
  ##   1 more ARCHONs                      -> PWNED
  ##   2 greater total live-archon health   -> OWNED
  ##   3 greater `parts + sum(partCost)`    -> BARELY_BEAT
  ##   4 higher maximum live archon id      -> WON_BY_DUBIOUS_REASONS,
  ##     and the `else` branch awards B — so a 0-vs-0 tie goes to B.
  ##
  ## Rung 3's accumulator is SEEDED with the parts difference and then walks
  ## every live robot of either team ONCE, in insertion order
  ## (`partsNetWorthDiff`), exactly as the engine does.
  if w.timeLimitReached() and not w.hasWinner:
    let archonDiff = float64(w.archonsAlive(teamA) - w.archonsAlive(teamB))
    if not w.setWinnerIfNonzero(archonDiff, dfPwned):
      let healthDiff = w.archonHealthTotal(teamA) - w.archonHealthTotal(teamB)
      let partsDiff = w.partsNetWorthDiff()
      if not w.setWinnerIfNonzero(healthDiff, dfOwned) and
          not w.setWinnerIfNonzero(partsDiff, dfBarelyBeat):
        if w.highestArchonId(teamA) > w.highestArchonId(teamB):
          w.setWinner(teamA, dfDubious)
        else:
          w.setWinner(teamB, dfDubious)
    w.tiebreakRung = ord(w.domination)
    discard w.beat(BeatTiebreak, "tiebreak", ord(w.domination),
                   w.archonsAlive(teamA) * 100 + w.archonsAlive(teamB),
                   w.partsWorth(teamA) * 100000 + w.partsWorth(teamB),
                   $int(w.archonHealthTotal(teamA) * 10.0) & ":" &
                     $int(w.archonHealthTotal(teamB) * 10.0))
  if w.hasWinner:
    w.running = false

# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

func share*(x, y: int): float32 =
  ## The bc22-bc25 choice, and bc16 keeps it: a 0-0 total is 0.5, NOT 0. Two
  ## factions that both ended with no archons should not be separated by an
  ## arithmetic accident, and on this year's evidence a double annihilation
  ## by the horde is a real outcome.
  if x + y == 0: 0.5'f32 else: float32(x) / float32(x + y)

proc gamePoints*(w: World): array[2, int] =
  ## A continuous reading of the engine's OWN tiebreak ladder, in its own
  ## priority order and weighted in that order: archons 64, archon health 24,
  ## parts net worth 12.
  ##
  ## Rungs 2 and 3 are float64 in the engine and are NARROWED TO INTEGERS
  ## here — archon health to TENTHS, parts worth to a truncated integer —
  ## before any share is taken, and every share is then narrowed through
  ## FLOAT32 with the weighted sum TRUNCATED by the `int()` cast. That is
  ## deliberate: `points` must be reproducible bit for bit between the native
  ## recorder and the wasm re-deriver, and a float64 sum reduced in a
  ## different order would not be.
  ##
  ## THE `end_reason` IS NOT COMPUTED THIS WAY: the ladder uses the engine's
  ## exact float64 differences, so a razor-thin margin can decide the WINNER
  ## on a difference that rounds away in POINTS. Stated explicitly, tested
  ## explicitly (`tests/test_bc16_scoring.nim`), and not a bug.
  ##
  ## The weights are SUPER-INCREASING (`24 > 12` and `64 > 24 + 12`), so a
  ## DECISIVE margin on a higher rung dominates everything below it. THIS
  ## CLAIMS NO MORE THAN THAT: a one-unit margin on a rung with large totals
  ## gives an arbitrarily small advantage (4 vs 3 archons is
  ## `4/7 - 3/7 = 0.143`, i.e. 9.1 points against 36 available below), so
  ## `points` ALONE CAN FAVOUR THE LOSER. It measures the SHAPE of the game,
  ## not who won it; `results.scores` adds 200 per game won and IS
  ## win-dominated by construction.
  let archons = [w.archonsAlive(teamA), w.archonsAlive(teamB)]
  let archonHp = [int(10.0 * w.archonHealthTotal(teamA)),
                  int(10.0 * w.archonHealthTotal(teamB))]
  let worth = [w.partsWorth(teamA), w.partsWorth(teamB)]
  for t in 0 .. 1:
    let o = 1 - t
    result[t] = int(64.0'f32 * share(archons[t], archons[o]) +
                    24.0'f32 * share(archonHp[t], archonHp[o]) +
                    12.0'f32 * share(worth[t], worth[o]))

# ---------------------------------------------------------------------------
#  One round
# ---------------------------------------------------------------------------

proc processBeginningOfTurn(w: World, r: Robot) =
  ## Rule 3.1. `decrementDelays()` runs for EVERY robot including one that
  ## cannot act, which is why a robot's delays keep draining while it is
  ## being built.
  r.d.decrementDelays()
  r.repairCount = 0
  r.basicSignalCount = 0
  r.messageSignalCount = 0
  r.opsLeft = (if r.canExecuteCode(): budgetFor(r.kind) else: 0)
  r.opsUsed = 0

proc processEndOfTurn(w: World, r: Robot) =
  ## Rule 3.4, and ONLY when `health > 0` — the caller checks that.
  r.roundsAlive += 1
  if r.opsUsed > w.opsUsedPeak: w.opsUsedPeak = r.opsUsed
  let damage = r.inf.tickInfection()
  if damage > 0.0:
    if r.team.isPlayer():
      w.stats.viperInfectionDamage[ord(r.team)] += int(damage)
    w.changeHealthLevel(r, -damage, dcNormal)

proc emitRoundBeats(w: World) =
  ## The beats that read the round's own deltas, all bounded per game.
  for row in w.turnedThisRound:
    discard w.beat(BeatTurned, "turned", row.team, ord(row.kind),
                   row.l.x * 100 + row.l.y,
                   ($row.became).toLowerAscii() & ":" &
                     $outbreakLevel(w.currentRound))
  w.turnedThisRound.setLen(0)
  for row in w.archonLostThisRound:
    discard w.beat(BeatArchonLost, "archon_lost", row.team,
                   w.archonsAlive(Team(row.team)), 0, row.cause)
  w.archonLostThisRound.setLen(0)
  if w.attackersLostThisRound[0] > 0 and w.attackersLostThisRound[1] > 0:
    discard w.beat(BeatDuel, "duel", w.attackersLostThisRound[0],
                   w.attackersLostThisRound[1])
  for t in 0 .. 1:
    if w.lostThisRound[t] >= 5:
      discard w.beat(BeatRout, "rout", t, w.lostThisRound[t])

proc emitScheduleBeats(w: World) =
  ## `zombie_wave` on every scheduled round, and `outbreak` on every 300th.
  for row in w.map.schedule:
    if row.round == w.currentRound:
      var total = 0
      for c in row.counts: total += c
      discard w.beat(BeatZombieWave, "zombie_wave", total,
                     w.densStanding(), outbreakLevel(w.currentRound),
                     $row.counts[0] & ":" & $row.counts[1] & ":" &
                       $row.counts[2] & ":" & $row.counts[3])
  if w.currentRound > 0 and (w.currentRound mod OutbreakTimer) == 0:
    discard w.beat(BeatOutbreak, "outbreak", outbreakLevel(w.currentRound),
                   int(outbreakMultiplier(w.currentRound) * 1000.0))

proc runRound*(w: World, sides: array[2, Side],
               chassis: array[2, ChassisKind16]) =
  ## Rule 1a. `currentRound++` from -1.
  inc w.currentRound
  ## Rules 1b and 1c are GENUINE NO-OPS in 2016 and are not ported (D1).

  ## THE CHASSIS'S ROUND-LEVEL BOOKKEEPING RUNS FIRST, so every robot this
  ## round reads the same census and the same den programme.
  when not defined(bc16Scenario) and not defined(bc16Idle):
    for t in 0 .. 1:
      case chassis[t]
      of ckBulwark: beginRound(w, sides[t])
      of ckGreenhorn: discard
  for t in 0 .. 1:
    w.lostThisRound[t] = 0
    w.attackersLostThisRound[t] = 0

  w.emitScheduleBeats()

  ## Rules 2 and 3. THE ARRAY BEING ITERATED IS A SNAPSHOT taken before the
  ## sweep (`gameObjectsByID.keySet().stream()...toArray()`), so a robot
  ## built this round does NOT take a turn this round, and a robot destroyed
  ## mid-sweep is skipped by the `robot == null` guard.
  let snapshot = w.execOrder
  for id in snapshot:
    if not w.existsRobot(id): continue
    let r = w.robotsById[id]
    w.processBeginningOfTurn(r)
    w.runControllerFor(sides, chassis, r)
    if w.existsRobot(id) and r.health > 0.0:
      w.processEndOfTurn(r)
    ## `runRound:178-181`: a robot that terminated is suicided AFTER
    ## `processEndOfTurn`, as an ordinary death signal — so a robot that
    ## disintegrates WHILE INFECTED still becomes an enemy zombie.
    if w.existsRobot(id) and r.disintegrated:
      w.visitDeathSignal(r, dcNormal)

  ## Rule 4a is a GENUINE NO-OP in 2016 (D1). Rule 4b:
  w.addPartsIncome()
  ## Rule 4c/4d.
  w.emitRoundBeats()
  if w.currentRound == 2000:
    for t in 0 .. 1:
      w.stats.archonsAliveAt2000[t] = w.archonsAlive(Team(t))
  w.checkEndOfMatch()

  ## The per-round hash chain: NINETEEN per-team values plus THIRTEEN
  ## globals, so a re-derivation that diverged in only one of them cannot
  ## reproduce the chain (the GV02 lesson). Folding the TWO RNG STATES is a
  ## bc16-specific decision and it is the cheapest possible tripwire for a
  ## missed or extra draw (D2b/D2c).
  ##
  ## EVERY COUNT IS ITS OWN `mixHash` CALL (r1-F7). The six player-type
  ## censuses were packed base-100/base-1000000 into two values and the four
  ## zombie censuses base-100 into one, so any single count of 100 or more
  ## carried into the next field and two distinct censuses could fold to the
  ## same chain value. That is not hypothetical on this year: the parity job
  ## measures `peak_robots` of 104-162 and the survival gate builds 177-212
  ## units a seat on `checkers`/`prisons`. A collision can only HIDE a
  ## divergence, never manufacture one, which is exactly why it had to go:
  ## the chain is a tripwire and a tripwire with a blind spot is worse than a
  ## loud one.
  for t in 0 .. 1:
    let team = Team(t)
    w.mixHash(w.archonsAlive(team))
    w.mixHash(w.robotTypeCount(team, rtScout))
    w.mixHash(w.robotTypeCount(team, rtSoldier))
    w.mixHash(w.robotTypeCount(team, rtGuard))
    w.mixHash(w.robotTypeCount(team, rtViper))
    w.mixHash(w.robotTypeCount(team, rtTurret))
    w.mixHash(w.robotTypeCount(team, rtTtm))
    w.mixHash(w.totalHealthTenths(team))
    w.mixHash(int(w.archonHealthTotal(team) * 10.0))
    w.mixHash(int(w.resources[t] * 10.0))
    w.mixHash(w.partsWorth(team))
    w.mixHash(w.infectedCount(team))
    w.mixHash(w.stats.robotsLost[t])
    w.mixHash(w.stats.partsCollectedTenths[t])
    w.mixHash(w.stats.densDestroyed[t])
    w.mixHash(w.stats.neutralsActivated[t])
    w.mixHash(w.stats.robotsTurned[t])
    w.mixHash(w.stats.rubbleClearedTenths[t])
    w.mixHash(w.stats.damageDealt[t])
  w.mixHash(w.currentRound)
  w.mixHashU(w.rubbleChecksum())
  w.mixHashU(w.partsChecksum())
  w.mixHashU(w.execOrderChecksum())
  w.mixHash(w.execOrder.len)
  w.mixHash(w.zombieCountByType(rtStandardzombie))
  w.mixHash(w.zombieCountByType(rtRangedzombie))
  w.mixHash(w.zombieCountByType(rtFastzombie))
  w.mixHash(w.zombieCountByType(rtBigzombie))
  w.mixHash(w.densStanding())
  w.mixHash(w.neutralsStanding())
  w.mixHashU(cast[uint64](w.rand.seed))
  w.mixHashU(cast[uint64](w.zombieRand.seed))

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

proc endReasonFor(w: World): string =
  case w.domination
  of dfNone: $dfPwned
  else: $w.domination

proc harvest(w: World, outcome: var GameOutcome16) =
  for team in [teamA, teamB]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    outcome.archonsStart[slot] = w.stats.archonsStart[t]
    outcome.archonsEnd[slot] = w.archonsAlive(team)
    outcome.archonsLost[slot] = w.stats.archonsLost[t]
    outcome.archonHealthEndTenths[slot] = int(w.archonHealthTotal(team) * 10.0)
    outcome.partsEndTenths[slot] = int(w.resources[t] * 10.0)
    outcome.partsWorthEnd[slot] = w.partsWorth(team)
    outcome.partsCollectedTenths[slot] = w.stats.partsCollectedTenths[t]
    outcome.partsIncomeTenths[slot] = w.stats.partsIncomeTenths[t]
    outcome.partsSpentTenths[slot] = w.stats.partsSpentTenths[t]
    outcome.unitsBuilt[slot] = w.stats.unitsBuilt[t]
    outcome.scoutsBuilt[slot] = w.stats.scoutsBuilt[t]
    outcome.soldiersBuilt[slot] = w.stats.soldiersBuilt[t]
    outcome.guardsBuilt[slot] = w.stats.guardsBuilt[t]
    outcome.vipersBuilt[slot] = w.stats.vipersBuilt[t]
    outcome.turretsBuilt[slot] = w.stats.turretsBuilt[t]
    outcome.turretPacks[slot] = w.stats.turretPacks[t]
    outcome.robotsAlive[slot] = w.robotCountOf(team)
    outcome.robotsLost[slot] = w.stats.robotsLost[t]
    outcome.robotsTurned[slot] = w.stats.robotsTurned[t]
    outcome.neutralsActivated[slot] = w.stats.neutralsActivated[t]
    outcome.neutralArchonsActivated[slot] =
      w.stats.neutralArchonsActivated[t]
    outcome.densDestroyed[slot] = w.stats.densDestroyed[t]
    outcome.denDamageDealt[slot] = w.stats.denDamageDealt[t]
    outcome.damageDealt[slot] = w.stats.damageDealt[t]
    outcome.zombieDamageDealt[slot] = w.stats.zombieDamageDealt[t]
    outcome.zombieDamageTaken[slot] = w.stats.zombieDamageTaken[t]
    outcome.enemyDamageDealt[slot] = w.stats.enemyDamageDealt[t]
    outcome.enemyDamageTaken[slot] = w.stats.enemyDamageTaken[t]
    outcome.infectionsSuffered[slot] = w.stats.infectionsSuffered[t]
    outcome.infectionsInflicted[slot] = w.stats.infectionsInflicted[t]
    outcome.viperInfectionDamage[slot] = w.stats.viperInfectionDamage[t]
    outcome.repairs[slot] = w.stats.repairs[t]
    outcome.hpRepaired[slot] = w.stats.hpRepaired[t]
    outcome.rubbleClearedTenths[slot] = w.stats.rubbleClearedTenths[t]
    outcome.rubbleCreatedTenths[slot] = w.stats.rubbleCreatedTenths[t]
    outcome.squaresOpened[slot] = w.stats.squaresOpened[t]
    outcome.basicSignals[slot] = w.stats.basicSignals[t]
    outcome.messageSignals[slot] = w.stats.messageSignals[t]
    outcome.archonPartsWalks[slot] = w.stats.archonPartsWalks[t]
    outcome.archonsAliveAt2000[slot] = w.stats.archonsAliveAt2000[t]
  outcome.archonsPerSide = w.stats.archonsStart[0]
  outcome.densOnMap = w.map.dens.len
  outcome.densPerSide = w.map.dens.len div 2
  var partsTotal = 0.0
  var partsSquares = 0
  for v in w.map.parts:
    partsTotal += v
    if v > 0.0: partsSquares += 1
  outcome.partsOnMapStart = int(partsTotal)
  outcome.partsSquaresStart = partsSquares
  outcome.rubbleMeanTenths = w.rubbleMeanTenths()
  var impassableStart = 0
  for v in w.map.rubble:
    if v >= RubbleObstructionThresh: impassableStart += 1
  outcome.impassableSquaresStart = impassableStart
  outcome.impassableSquaresEnd = w.impassableSquares()
  var neutrals = 0
  for b in w.map.initialRobots:
    if b.team == ord(teamNeutral): neutrals += 1
  outcome.neutralsOnMapStart = neutrals
  outcome.zombiesSpawned = w.stats.zombiesSpawned
  outcome.zombiesKilled = w.stats.zombiesKilled
  outcome.zombiesAliveEnd = w.robotCountOf(teamZombie) - w.densStanding()
  outcome.outbreakLevelEnd = outbreakLevel(max(0, w.currentRound))
  outcome.scheduleRounds = w.map.schedule.len
  outcome.tiebreakRound = w.maxRounds - 1
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(teamA)] = pts[0]
  outcome.points[outcome.slotOf(teamB)] = pts[1]
  ## Rounds are 0-based, so a game that played rounds 0..2999 played 3000.
  outcome.roundsPlayed = w.currentRound + 1
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], chassis: array[2, ChassisKind16],
  index, sideAslot, maxRounds: int, budgetSeconds: int,
  onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome16) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of
  ## monotonic wall clock elapse. An abandoned game is DISCARDED by the match
  ## (its `aborted` flag says so); it is never scored half-played.
  ##
  ## `budgetSeconds <= 0` means UNBOUNDED here. Note that
  ## `match.nim:480` clamps `perGameBudgetSeconds` to `max(1, ...)` ONE LEVEL
  ## UP, so a test helper that zeroes that field buys a ONE-SECOND budget
  ## rather than an unbounded one — every bc16 test uses the
  ## `if perGame > 0:` convention instead.
  var w = newWorld(spec, maxRounds)
  var sides = newSides16(sheets, sideAslot)
  ## `sides` is indexed by TEAM and `chassis` arrives by SEAT — re-index once
  ## here so the round loop never has to.
  let chassisByTeam = [chassis[sideAslot], chassis[1 - sideAslot]]
  var outcome = GameOutcome16(
    index: index, mapName: spec.name, sideAslot: sideAslot, winnerSlot: -1)
  var partsOnMap = 0.0
  for v in spec.parts: partsOnMap += v
  var neutrals = 0
  for b in spec.initialRobots:
    if b.team == ord(teamNeutral): neutrals += 1
  discard w.beat(BeatGameStart, "game_start", index, w.width, w.height,
    spec.name & ":" & $w.stats.archonsStart[0] & ":" & $spec.dens.len & ":" &
      $int(partsOnMap) & ":" & $neutrals & ":" & $spec.schedule.len)
  let started = getMonoTime()
  let budget = initDuration(seconds = budgetSeconds)
  while w.running and w.currentRound < maxRounds - 1:
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
    discard w.beat(BeatGameEnd, "game_abandoned", index, w.currentRound, 0,
                   spec.name)
    return (w, outcome)
  outcome.endReason = w.endReasonFor()
  harvest(w, outcome)
  if w.hasWinner:
    outcome.winnerSlot = outcome.slotOf(w.winner)
  discard w.beat(BeatGameEnd, "game_end", index,
                 (if outcome.winnerSlot >= 0: outcome.winnerSlot else: -1),
                 outcome.points[0] * 1000 + outcome.points[1],
                 outcome.endReason & ":" & $outcome.archonsEnd[0] & ":" &
                   $outcome.archonsEnd[1])
  (w, outcome)
