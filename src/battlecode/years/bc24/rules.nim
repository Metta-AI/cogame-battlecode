## The bc24 round loop, the end ladder, the points formula and one game.
##
## `runRound` mirrors `GameWorld.runRound` / `processBeginningOfRound` /
## `updateDynamicBodies` / `processEndOfRound` step for step, and the step list
## IS the rules: a re-ordering is a rules change and bumps `GameVersion`
## (docs/RULES-BC24.md §The round loop).
##
##   1. flag-broadcast re-roll (BEFORE the counter moves, so it fires entering
##      rounds 1, 101, 201, ...), then `currentRound += 1`, then the global
##      upgrade point at 600/1200/1800, then every duck's beginning-of-round
##   2. the round-1 endowment of 400 crumbs a side
##   3. the FIXED exec order: A0, B0, A1, B1, ..., A49, B49
##   4. beginning of turn: all three cooldowns decay by 10, the DecisionOps
##      budget resets -- FOR A JAILED DUCK TOO
##   5. run the controller
##   6. end of turn: every queued trap fires in queue order, then roundsAlive++
##   7. end of round: +10 crumbs a side, the round-200 flag confirmation, the
##      dropped-flag return timer, then the end ladder
##   8. append this round's state hash

import std/[monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import world, traps, flags, maps, knobs, skills
import chassis/[kit, sharkin, scaffold24, builder]

export world, traps, flags, maps, knobs, kit

type
  ChassisKind24* = enum
    ckGoneSharkin = "gone-sharkin"
    ckExamplefuncsplayer24 = "examplefuncsplayer24"

  GameOutcome24* = object
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
    flagsCaptured*: array[2, int]
    flagsPickedUp*: array[2, int]
    flagsDropped*: array[2, int]
    flagsReturned*: array[2, int]
    roundsCarrying*: array[2, int]
    crumbsEnd*: array[2, int]
    crumbsCollected*: array[2, int]
    crumbsSpent*: array[2, int]
    killCrumbs*: array[2, int]
    ducksSpawned*: array[2, int]
    ducksJailed*: array[2, int]
    aliveEnd*: array[2, int]
    attacks*: array[2, int]
    damageDealt*: array[2, int]
    kills*: array[2, int]
    heals*: array[2, int]
    healDealt*: array[2, int]
    trapsBuilt*: array[2, int]
    trapsTriggered*: array[2, int]
    trapDamage*: array[2, int]
    tilesDug*: array[2, int]
    tilesFilled*: array[2, int]
    levelsEnd*: array[2, int]
    attackLevelsEnd*: array[2, int]
    buildLevelsEnd*: array[2, int]
    healLevelsEnd*: array[2, int]
    masteries*: array[2, int]
    upgradesTaken*: array[2, int]
    upgradeFirstRound*: array[2, int]
    setupFlagTeleports*: int
    roundsWithAnyCarry*: int

proc parseChassisKind24*(name: string): ChassisKind24 =
  ## Anything unrecognised is `gone-sharkin`: a seat that says nothing useful
  ## plays the strong published doctrine, not the deliberately weak floor
  ## (§Decisions).
  case name
  of "examplefuncsplayer24", "examplefuncsplayer", "scaffold", "example":
    ckExamplefuncsplayer24
  else: ckGoneSharkin

proc chassisKindFor*(sc: ScriptedChassis): ChassisKind24 =
  ## The year-neutral `ScriptedChassis` mapped into bc24's own kind. A name
  ## belonging to another year falls back to bc24's STRONG chassis.
  case sc
  of scExamplefuncsplayer24: ckExamplefuncsplayer24
  else: ckGoneSharkin

proc slotOf*(outcome: GameOutcome24, team: Team): int =
  if team == teamA: outcome.sideAslot else: 1 - outcome.sideAslot

proc newSides24*(sheets: array[2, Sheet], sideAslot: int): array[2, Side] =
  ## `sides[ord(team)]`. Which SEAT is behind team A alternates per game.
  result[0] = newSide(teamA, sheets[sideAslot].doctrine24)
  result[1] = newSide(teamB, sheets[1 - sideAslot].doctrine24)

proc runControllerFor*(w: World, sides: array[2, Side],
                       chassis: array[2, ChassisKind24], r: Robot) =
  let side = sides[ord(r.team)]
  case chassis[ord(r.team)]
  of ckGoneSharkin: runGoneSharkin(w, side, r)
  of ckExamplefuncsplayer24: runScaffold24(w, side, r)

# ---------------------------------------------------------------------------
#  The end-of-match ladder, in the engine's own order
# ---------------------------------------------------------------------------

proc setWinner*(w: World, t: Team, d: Domination) =
  w.winner = t
  w.hasWinner = true
  w.domination = d

proc setWinnerIfMoreFlags*(w: World): bool =
  let a = w.stats.flagsCaptured[0]
  let b = w.stats.flagsCaptured[1]
  if a > b: w.setWinner(teamA, dfMoreFlagCaptures); true
  elif b > a: w.setWinner(teamB, dfMoreFlagCaptures); true
  else: false

func levelSum*(w: World, team: Team): int =
  ## `TeamInfo.getLevelSum`: EVERY duck on the team, jailed included.
  for r in w.robots:
    if r.team == team: result += r.levelSumOf()

proc setWinnerIfGreaterLevelSum*(w: World): bool =
  let a = w.levelSum(teamA)
  let b = w.levelSum(teamB)
  if a > b: w.setWinner(teamA, dfLevelSum); true
  elif b > a: w.setWinner(teamB, dfLevelSum); true
  else: false

proc setWinnerIfMoreBread*(w: World): bool =
  let a = w.stats.crumbs[0]
  let b = w.stats.crumbs[1]
  if a > b: w.setWinner(teamA, dfMoreBread); true
  elif b > a: w.setWinner(teamB, dfMoreBread); true
  else: false

proc setWinnerArbitrary*(w: World) =
  ## `setWinnerArbitrary` uses `Math.random()`, which is wall-clock seeded and
  ## therefore not reproducible. A draw from the WORLD RNG replaces it — a
  ## documented divergence, reachable only when captures, level sums and
  ## crumbs are all tied at round 2000
  ## (docs/RULES-BC24.md §Divergences item 2).
  w.setWinner((if w.rand.nextDouble() < 0.5: teamA else: teamB), dfCoinFlip)

func timeLimitReached*(w: World): bool =
  ## `GameWorld.timeLimitReached` is `currentRound >= gameMap.getRounds()`, and
  ## every 2024 map's `rounds` is `GAME_MAX_NUMBER_OF_ROUNDS = 2000`. Round
  ## 2000 IS played.
  w.currentRound >= w.maxRounds

proc checkEndOfMatch*(w: World) =
  ## `MORE_FLAGS_PICKED` is a DEAD RUNG: `checkEndOfMatch` never calls it.
  if w.timeLimitReached() and not w.hasWinner:
    if w.setWinnerIfMoreFlags(): discard
    elif w.setWinnerIfGreaterLevelSum(): discard
    elif w.setWinnerIfMoreBread(): discard
    else: w.setWinnerArbitrary()
  if w.hasWinner:
    w.running = false

# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

func share*(x, y: int): float32 =
  ## 0.5 on a 0-0 total, which is the deliberate difference from bc21's
  ## `x / max(1, total)`: in bc24 a great many honest games end 0-0 on
  ## captures, and a term that silently paid nobody would make two even games
  ## score differently for no reason.
  if x + y == 0: 0.5'f32 else: float32(x) / float32(x + y)

proc gamePoints*(w: World): array[2, int] =
  ## A continuous reading of the engine's OWN end ladder, in its own priority
  ## order: flags captured, then the level sum, then crumbs.
  ##
  ## Every share is narrowed through FLOAT32 before the weighted sum and the
  ## sum is TRUNCATED by the `int()` cast — not for fidelity to Java (this
  ## formula is ours) but for recorder/re-deriver agreement: the same
  ## arithmetic runs natively on x86-64 and in wasm32 and must produce the
  ## same integer.
  let caps = [w.stats.flagsCaptured[0], w.stats.flagsCaptured[1]]
  let levels = [w.levelSum(teamA), w.levelSum(teamB)]
  let crumbs = [w.stats.crumbs[0], w.stats.crumbs[1]]
  for t in 0 .. 1:
    let o = 1 - t
    result[t] = int(60.0'f32 * share(caps[t], caps[o]) +
                    25.0'f32 * share(levels[t], levels[o]) +
                    15.0'f32 * share(crumbs[t], crumbs[o]))

# ---------------------------------------------------------------------------
#  One round
# ---------------------------------------------------------------------------

proc prepareSides(w: World, sides: array[2, Side]) =
  ## Per-team bookkeeping the chassis reads: the navigation fields, the choke
  ## measurement (once, at round 201), the carrier list the escort rule needs,
  ## and the distress decay that makes distress mean "now".
  for t in 0 .. 1:
    let side = sides[t]
    let before = side.fieldsRound
    w.refreshFields(side)
    if w.currentRound == SetupRounds + 1:
      w.measureChokes(side)
    if side.fieldsRound != before and not w.isSetupPhase():
      w.planBridge(side)
    side.firstActionDone = false
    side.carriers.setLen(0)
    for i in 0 .. 2:
      if side.distress[i] > 0: side.distress[i] -= 1
  for f in w.allFlags:
    if f.carriedBy < 0: continue
    let carrier = w.robotById(f.carriedBy)
    if carrier == nil: continue
    if f.team == carrier.team: continue
    sides[ord(carrier.team)].carriers.add(carrier.id)
  for t in 0 .. 1:
    w.assignEscorts(sides[t])

proc sampleTelemetry(w: World) =
  ## Never read by a rule: the escort density and carry counters the
  ## knob-teeth gate asserts named, signed deltas on.
  var anyCarry = false
  for f in w.allFlags:
    if f.carriedBy < 0: continue
    let carrier = w.robotById(f.carriedBy)
    if carrier == nil or not carrier.spawned: continue
    anyCarry = true
    let t = ord(carrier.team)
    w.stats.roundsCarrying[t] += 1
    var friends = 0
    var close = 0
    for l in w.locationsWithinRadiusSquared(carrier.loc, VisionRadiusSquared):
      let bot = w.getRobot(l)
      if bot != nil and bot.team == carrier.team and bot.id != carrier.id:
        friends += 1
        if carrier.loc.distanceSquaredTo(l) <= 4: close += 1
    w.stats.escortCount[t] += friends
    w.stats.escortClose[t] += close
    w.stats.escortSamples[t] += 1
  if anyCarry: w.stats.roundsWithAnyCarry += 1
  if w.currentRound == 700:
    for t in 0 .. 1:
      w.stats.crumbsBy700[t] = w.stats.crumbsCollected[t]

proc runRound*(w: World, sides: array[2, Side],
               chassis: array[2, ChassisKind24]) =
  ## Rule 1. The broadcast re-roll happens BEFORE the counter moves, which is
  ## why it fires entering rounds 1, 101, 201, ... — `currentRound` is still
  ## the previous value when the modulo is taken.
  if w.currentRound mod FlagBroadcastUpdateInterval == 0:
    w.updateFlagBroadcastLocations()
  inc w.currentRound
  if w.currentRound != 0 and w.currentRound mod GlobalUpgradeRounds == 0:
    w.stats.upgradePoints[0] += 1
    w.stats.upgradePoints[1] += 1
  ## `InternalRobot.processBeginningOfRound` clears the indicator string and
  ## `diedLocation`; the named step survives because the hash chain and the
  ## parity trace are taken around it.
  for r in w.robots:
    r.diedLocation = loc(-1, -1)

  ## Rule 2: the round-1 endowment, credited INSIDE `runRound` after the
  ## beginning-of-round sweep — which is why a duck cannot spend it on round 0
  ## and why the trace shows 400 at the top of round 1.
  if w.currentRound == 1:
    w.addCrumbs(teamA, InitialCrumbsAmount)
    w.addCrumbs(teamB, InitialCrumbsAmount)

  w.prepareSides(sides)

  ## Rules 3 to 6. Ducks are NEVER destroyed, so the exec order is fixed and
  ## every duck takes a turn whether spawned or not.
  for r in w.robots:
    processBeginningOfTurn(w, r)
    w.runControllerFor(sides, chassis, r)
    w.processTriggerQueue(r)
    r.roundsAlive += 1

  ## Rule 7, in `GameWorld`'s own order: the passive crumbs are credited in
  ## `runRound`, BEFORE `processEndOfRound`.
  w.addCrumbs(teamA, PassiveCrumbsIncrease)
  w.addCrumbs(teamB, PassiveCrumbsIncrease)

  if w.currentRound == SetupRounds:
    w.processEndOfSetupPhase()
    discard w.beat(BeatSetupEnd, "setup_end", w.stats.setupFlagTeleports,
      w.stats.trapsBuilt[0], w.stats.trapsBuilt[1])
  if not w.isSetupPhase():
    w.resetDroppedFlags()

  w.sampleTelemetry()

  ## `rout` — a round in which a clan lost five or more ducks.
  for t in 0 .. 1:
    if w.stats.ducksJailed[t] - w.jailedAtRoundStart[t] >= 5:
      discard w.beat(BeatRout, "rout", t,
        w.stats.ducksJailed[t] - w.jailedAtRoundStart[t])
    w.jailedAtRoundStart[t] = w.stats.ducksJailed[t]

  w.checkEndOfMatch()

  ## Rule 8: the per-round hash chain. Nine per-team values plus four globals;
  ## a re-derivation that diverged only in one of them would otherwise
  ## reproduce the chain and report no mismatch (the GV02 lesson).
  var hpSum = 0
  var awayFlags = 0
  var highestCooldown = 0
  for r in w.robots:
    if r.spawned:
      hpSum += r.health
      highestCooldown = max(highestCooldown, r.actionCooldown)
  for f in w.allFlags:
    if not f.locIsStartRef: awayFlags += 1
  for t in 0 .. 1:
    let team = Team(t)
    w.mixHash(w.stats.crumbs[t])
    w.mixHash(w.stats.flagsCaptured[t])
    w.mixHash(w.stats.flagsPickedUp[t])
    w.mixHash(w.levelSum(team))
    w.mixHash(w.stats.ducksSpawned[t])
    w.mixHash(w.stats.ducksJailed[t])
    w.mixHash(w.stats.trapsBuilt[t] - w.stats.trapsTriggered[t])
    w.mixHash(w.stats.tilesDug[t] - w.stats.tilesFilled[t])
  w.mixHash(w.currentRound)
  w.mixHash(hpSum)
  w.mixHash(awayFlags)
  w.mixHash(highestCooldown)

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

proc endReasonFor(w: World): string =
  case w.domination
  of dfNone: "more_flag_captures"
  else: $w.domination

proc harvest(w: World, outcome: var GameOutcome24) =
  for team in [teamA, teamB]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    outcome.flagsCaptured[slot] = w.stats.flagsCaptured[t]
    outcome.flagsPickedUp[slot] = w.stats.flagsPickedUp[t]
    outcome.flagsDropped[slot] = w.stats.flagsDropped[t]
    outcome.flagsReturned[slot] = w.stats.flagsReturned[t]
    outcome.roundsCarrying[slot] = w.stats.roundsCarrying[t]
    outcome.crumbsEnd[slot] = w.stats.crumbs[t]
    outcome.crumbsCollected[slot] = w.stats.crumbsCollected[t]
    outcome.crumbsSpent[slot] = w.stats.crumbsSpent[t]
    outcome.killCrumbs[slot] = w.stats.killCrumbs[t]
    outcome.ducksSpawned[slot] = w.stats.ducksSpawned[t]
    outcome.ducksJailed[slot] = w.stats.ducksJailed[t]
    outcome.attacks[slot] = w.stats.attacks[t]
    outcome.damageDealt[slot] = w.stats.damageDealt[t]
    outcome.kills[slot] = w.stats.kills[t]
    outcome.heals[slot] = w.stats.heals[t]
    outcome.healDealt[slot] = w.stats.healDealt[t]
    outcome.trapsBuilt[slot] = w.stats.trapsBuilt[t]
    outcome.trapsTriggered[slot] = w.stats.trapsTriggered[t]
    outcome.trapDamage[slot] = w.stats.trapDamage[t]
    outcome.tilesDug[slot] = w.stats.tilesDug[t]
    outcome.tilesFilled[slot] = w.stats.tilesFilled[t]
    outcome.masteries[slot] = w.stats.masteries[t]
    outcome.upgradeFirstRound[slot] = w.stats.upgradeFirstRound[t]
    var mask = 0
    for i in 0 .. 2:
      if w.stats.upgrades[t][i]: mask = mask or (1 shl i)
    outcome.upgradesTaken[slot] = mask
    var alive, levels, attackL, buildL, healL = 0
    for r in w.robots:
      if r.team != team: continue
      if r.spawned: alive += 1
      attackL += r.levelOf(skAttack)
      buildL += r.levelOf(skBuild)
      healL += r.levelOf(skHeal)
    levels = attackL + buildL + healL
    outcome.aliveEnd[slot] = alive
    outcome.levelsEnd[slot] = levels
    outcome.attackLevelsEnd[slot] = attackL
    outcome.buildLevelsEnd[slot] = buildL
    outcome.healLevelsEnd[slot] = healL
  outcome.setupFlagTeleports = w.stats.setupFlagTeleports
  outcome.roundsWithAnyCarry = w.stats.roundsWithAnyCarry
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(teamA)] = pts[0]
  outcome.points[outcome.slotOf(teamB)] = pts[1]
  outcome.roundsPlayed = w.currentRound
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], chassis: array[2, ChassisKind24],
  index, sideAslot, maxRounds: int, budgetSeconds: int,
  onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome24) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of
  ## monotonic wall clock elapse. An abandoned game is DISCARDED by the match
  ## (its `aborted` flag says so); it is never scored half-played.
  var w = newWorld(spec, maxRounds)
  var sides = newSides24(sheets, sideAslot)
  ## `sides` is indexed by TEAM and `chassis` arrives by SEAT — re-index once
  ## here so the round loop never has to.
  let chassisByTeam = [chassis[sideAslot], chassis[1 - sideAslot]]
  var outcome = GameOutcome24(
    index: index, mapName: spec.name, sideAslot: sideAslot, winnerSlot: -1)
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
