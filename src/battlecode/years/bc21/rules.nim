## The bc21 round loop, the end ladder, the points formula and one game.
##
## `runRound` mirrors `GameWorld.runRound` / `processBeginningOfRound` /
## `updateDynamicBodies` / `processEndOfRound` step for step, and the step list
## IS the rules: a re-ordering is a rules change and bumps `GameVersion`
## (docs/RULES-BC21.md §The round loop).
##
##   1. round += 1; buff expiry; every robot's beginning-of-round (a no-op in
##      2021, kept as a named step because the hash chain and the parity trace
##      are taken around it)
##   2. iterate the dynamic bodies in SPAWN order, over a snapshot of the order
##      taken once at the start of the sweep
##   3. beginning of turn: cooldown decay, DecisionOps budget reset
##   4. run the controller (the team's chassis under its doctrine)
##   5. end of turn: roundsAlive += 1
##   6. end of round: collect bids + passive influence + camouflage, settle the
##      auction, apply the expose buffs, check the end ladder
##   7. append this round's state hash

import std/[monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import world, empower, votes, maps, knobs
import chassis/[kit, bids, croll, scaffold21]

export world, empower, votes, maps, knobs, kit

type
  ChassisKind21* = enum
    ckCaliforniaRoll = "california-roll"
    ckExamplefuncsplayer21 = "examplefuncsplayer21"

  GameOutcome21* = object
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
    centersOwned*: array[2, int]
    centersCaptured*: array[2, int]
    centersLost*: array[2, int]
    neutralsCaptured*: array[2, int]
    votes*: array[2, int]
    bidsPlaced*: array[2, int]
    bidInfluenceSpent*: array[2, int]
    topBid*: array[2, int]
    influenceSpent*: array[2, int]
    influenceEnd*: array[2, int]
    incomeEnd*: array[2, int]
    unitsBuilt*: array[2, int]
    politiciansBuilt*: array[2, int]
    slanderersBuilt*: array[2, int]
    muckrakersBuilt*: array[2, int]
    unitsAlive*: array[2, int]
    politiciansAlive*: array[2, int]
    slanderersAlive*: array[2, int]
    muckrakersAlive*: array[2, int]
    empowers*: array[2, int]
    empowerConviction*: array[2, int]
    conversions*: array[2, int]
    exposes*: array[2, int]
    buffPeak*: array[2, int]
    camouflaged*: array[2, int]
    robotsLost*: array[2, int]
    votesTied*: int
    roundsNoBid*: int

proc parseChassisKind21*(name: string): ChassisKind21 =
  ## Anything unrecognised is `california-roll`: a seat that says nothing
  ## useful plays the strong published doctrine, not the deliberately weak
  ## floor (§Decisions).
  case name
  of "examplefuncsplayer21", "examplefuncsplayer", "scaffold", "example":
    ckExamplefuncsplayer21
  else: ckCaliforniaRoll

proc chassisKindFor*(sc: ScriptedChassis): ChassisKind21 =
  ## The year-neutral `ScriptedChassis` mapped into bc21's own kind. A name
  ## belonging to another year falls back to bc21's STRONG chassis.
  case sc
  of scExamplefuncsplayer21: ckExamplefuncsplayer21
  else: ckCaliforniaRoll

proc slotOf*(outcome: GameOutcome21, team: Team): int =
  if team == teamA: outcome.sideAslot else: 1 - outcome.sideAslot

proc newSides21*(sheets: array[2, Sheet], sideAslot: int): array[2, Side] =
  ## `sides[ord(team)]`. Which SEAT is behind team A alternates per game.
  result[0] = newSide(teamA, sheets[sideAslot].doctrine21)
  result[1] = newSide(teamB, sheets[1 - sideAslot].doctrine21)

proc runControllerFor*(w: World, sides: array[2, Side],
                       chassis: array[2, ChassisKind21], r: Robot) =
  if r.team == teamNeutral: return
  let side = sides[ord(r.team)]
  case chassis[ord(r.team)]
  of ckCaliforniaRoll: runCaliforniaRoll(w, side, r)
  of ckExamplefuncsplayer21: runScaffold21(w, side, r)

# ---------------------------------------------------------------------------
#  The end-of-match ladder, in the engine's own order
# ---------------------------------------------------------------------------

proc setWinner*(w: World, t: Team, d: Domination) =
  w.winner = t
  w.hasWinner = true
  w.domination = d

proc setWinnerIfAnnihilated*(w: World): bool =
  ## A DOUBLE WIPE in the same round awards the win to B — the engine's own
  ## asymmetry (`GameWorld.setWinnerIfAnnihilated` tests A first), reproduced.
  if w.robotCount[0] == 0:
    w.setWinner(teamB, dfAnnihilated); true
  elif w.robotCount[1] == 0:
    w.setWinner(teamA, dfAnnihilated); true
  else: false

proc setWinnerIfMoreVotes*(w: World): bool =
  let a = w.stats.votes[0]
  let b = w.stats.votes[1]
  if a > b: w.setWinner(teamA, dfMoreVotes); true
  elif b > a: w.setWinner(teamB, dfMoreVotes); true
  else: false

proc setWinnerIfMoreEnlightenmentCenters*(w: World): bool =
  let a = w.livingCenters(teamA)
  let b = w.livingCenters(teamB)
  if a > b: w.setWinner(teamA, dfMoreEnlightenmentCenters); true
  elif b > a: w.setWinner(teamB, dfMoreEnlightenmentCenters); true
  else: false

proc setWinnerIfMoreInfluence*(w: World): bool =
  let a = w.totalInfluence(teamA)
  let b = w.totalInfluence(teamB)
  if a > b: w.setWinner(teamA, dfMoreInfluence); true
  elif b > a: w.setWinner(teamB, dfMoreInfluence); true
  else: false

proc setWinnerArbitrary*(w: World) =
  ## `setWinnerArbitrary` uses `Math.random()`, which is wall-clock seeded and
  ## therefore not reproducible. A draw from the WORLD RNG replaces it — a
  ## documented divergence, reachable only when votes, Center counts and total
  ## influence are all tied at round 1500
  ## (docs/RULES-BC21.md §Divergences item 2).
  w.setWinner((if w.rand.nextDouble() < 0.5: teamA else: teamB), dfCoinFlip)

func timeLimitReached*(w: World): bool =
  ## `GameWorld.timeLimitReached` is `currentRound >= gameMap.getRounds()`, and
  ## every 2021 map's `rounds` is `GAME_MAX_NUMBER_OF_ROUNDS = 1500`. Round 1500
  ## IS played — unlike bc20's `rounds - 1` off-by-one.
  w.currentRound >= w.maxRounds

proc checkEndOfMatch*(w: World) =
  discard w.setWinnerIfAnnihilated()
  if w.timeLimitReached() and not w.hasWinner:
    if not w.setWinnerIfMoreVotes():
      if not w.setWinnerIfMoreEnlightenmentCenters():
        if not w.setWinnerIfMoreInfluence():
          w.setWinnerArbitrary()
  if w.hasWinner:
    w.running = false

# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

proc gamePoints*(w: World): array[2, int] =
  ## A continuous reading of the engine's OWN end ladder, so the score and the
  ## winner never tell different stories: survival, then the votes rung, then
  ## the Centers rung, then the influence rung, weighted in that order.
  ##
  ## Every share is narrowed through FLOAT32 before the weighted sum and the
  ## sum is TRUNCATED by the `int()` cast — not for fidelity to Java (this
  ## formula is ours) but for recorder/re-deriver agreement: the same
  ## arithmetic runs natively on x86-64 and in wasm32 and must produce the same
  ## integer.
  var alive: array[2, int]
  for t in 0 .. 1:
    alive[t] = if w.robotCount[t] > 0: 1 else: 0
  let aliveTotal = max(1, alive[0] + alive[1])
  let votes = [w.stats.votes[0], w.stats.votes[1]]
  let voteTotal = max(1, votes[0] + votes[1])
  let centers = [w.livingCenters(teamA), w.livingCenters(teamB)]
  let centerTotal = max(1, centers[0] + centers[1])
  let influence = [w.totalInfluence(teamA), w.totalInfluence(teamB)]
  let influenceTotal = max(1, influence[0] + influence[1])
  for t in 0 .. 1:
    let survival = float32(alive[t]) / float32(aliveTotal)
    let shareV = float32(votes[t]) / float32(voteTotal)
    let shareC = float32(centers[t]) / float32(centerTotal)
    let shareI = float32(influence[t]) / float32(influenceTotal)
    result[t] = int(40.0'f32 * survival + 35.0'f32 * shareV +
                    15.0'f32 * shareC + 10.0'f32 * shareI)

# ---------------------------------------------------------------------------
#  One round
# ---------------------------------------------------------------------------

proc runRound*(w: World, sides: array[2, Side],
               chassis: array[2, ChassisKind21]) =
  ## Rule 1.
  inc w.currentRound
  w.updateNumBuffs()
  ## `InternalRobot.processBeginningOfRound` is a no-op in 2021; the named step
  ## survives because the hash chain and the parity trace are taken around it.

  ## Rule 2: a SNAPSHOT of the exec order. Bodies spawned (or converted) during
  ## this sweep do not act until the next round, and bodies that die are
  ## skipped rather than compacted out from under the iteration.
  for t in 0 .. 1:
    refreshOwnCenters(w, sides[t])
    if chassis[t] == ckCaliforniaRoll:
      noteAuction(w, sides[t])
  let order = w.execOrder
  for id in order:
    if id notin w.robotsById: continue
    let r = w.robotsById[id]
    ## Rule 3.
    processBeginningOfTurn(r)
    ## Rule 4.
    w.runControllerFor(sides, chassis, r)
    if r.dead: continue
    ## Telemetry only, and cheap: where the muckrakers actually spent the game.
    if r.kind == rtMuckraker and r.team.isPlayer() and
        w.inEnemyHalf(r.team, r.loc):
      w.stats.muckrakerTurnsEnemyHalf[ord(r.team)] += 1
    ## Rule 5.
    processEndOfTurn(r)

  ## Rule 6, in `GameWorld.processEndOfRound`'s own order.
  let (bids, bidders) = w.processEndOfRoundSweep()
  w.settleAuction(bids, bidders)
  w.applyExposeBuffs()

  ## The bounded beats the scrubber draws (§Server, player, protocol). All of
  ## them are derived from state the sim already holds, so a re-derivation
  ## reproduces them exactly.
  block beats:
    ## `vote_lead` — only when the lead CHANGES HANDS.
    let leader =
      if w.stats.votes[0] > w.stats.votes[1]: 0
      elif w.stats.votes[1] > w.stats.votes[0]: 1
      else: -1
    if leader >= 0 and leader != w.voteLeader:
      w.voteLeader = leader
      discard w.beat(BeatVoteLead, "vote_lead", leader,
        w.stats.votes[leader], w.stats.votes[1 - leader])
    ## `expose_wave` — each time a team's buff crosses a 5 % step.
    for t in 0 .. 1:
      let step = w.stats.numBuffs[t] div 50
      if step > w.buffStep[t]:
        w.buffStep[t] = step
        discard w.beat(BeatExposeWave, "expose_wave", t, w.stats.exposes[t],
          w.stats.numBuffs[t])
    ## `bid_spike` — the largest bid in each 100-round window per team.
    if w.currentRound mod 100 == 0:
      for t in 0 .. 1:
        if w.windowTopBid[t] > 0:
          discard w.beat(BeatBidSpike, "bid_spike", t, w.windowTopBid[t],
            w.windowInfluence[t])
        w.windowTopBid[t] = 0
        w.windowInfluence[t] = 0

  let hadWinner = w.hasWinner
  w.checkEndOfMatch()
  if not hadWinner and w.hasWinner and w.domination == dfAnnihilated:
    ## The CHAPTER MARKER: which clan was wiped off the map.
    discard w.beat(BeatAnnihilated, "annihilated", 1 - ord(w.winner))

  ## Rule 7: the per-round hash chain. Eight per-team values plus three
  ## globals; a re-derivation that diverged only in one of them would
  ## otherwise reproduce the chain and report no mismatch (the GV02 lesson).
  var highestId = 0
  for id in w.robotsById.keys:
    if id > highestId: highestId = id
  for t in 0 .. 1:
    let team = Team(t)
    w.mixHash(w.stats.votes[t])
    w.mixHash(w.stats.numBuffs[t])
    w.mixHash(w.livingCenters(team))
    w.mixHash(w.totalInfluence(team))
    w.mixHash(w.typeCount[t][rtPolitician])
    w.mixHash(w.typeCount[t][rtSlanderer])
    w.mixHash(w.typeCount[t][rtMuckraker])
    w.mixHash(w.stats.unitsBuilt[t])
  w.mixHash(w.currentRound)
  w.mixHash(w.robotsById.len)
  w.mixHash(highestId)

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

proc endReasonFor(w: World): string =
  case w.domination
  of dfNone: "more_votes"
  else: $w.domination

proc harvest(w: World, outcome: var GameOutcome21) =
  for team in [teamA, teamB]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    outcome.centersOwned[slot] = w.livingCenters(team)
    outcome.centersCaptured[slot] = w.stats.centersCaptured[t]
    outcome.centersLost[slot] = w.stats.centersLost[t]
    outcome.neutralsCaptured[slot] = w.stats.neutralsCaptured[t]
    outcome.votes[slot] = w.stats.votes[t]
    outcome.bidsPlaced[slot] = w.stats.bidsPlaced[t]
    outcome.bidInfluenceSpent[slot] = w.stats.bidInfluenceSpent[t]
    outcome.topBid[slot] = w.stats.topBid[t]
    outcome.influenceSpent[slot] = w.stats.influenceSpent[t]
    outcome.influenceEnd[slot] = w.totalInfluence(team)
    outcome.incomeEnd[slot] =
      w.livingCenters(team) * ecPassive(max(1, w.currentRound))
    outcome.unitsBuilt[slot] = w.stats.unitsBuilt[t]
    outcome.politiciansBuilt[slot] = w.stats.politiciansBuilt[t]
    outcome.slanderersBuilt[slot] = w.stats.slanderersBuilt[t]
    outcome.muckrakersBuilt[slot] = w.stats.muckrakersBuilt[t]
    outcome.unitsAlive[slot] = w.robotCount[t]
    outcome.politiciansAlive[slot] = w.typeCount[t][rtPolitician]
    outcome.slanderersAlive[slot] = w.typeCount[t][rtSlanderer]
    outcome.muckrakersAlive[slot] = w.typeCount[t][rtMuckraker]
    outcome.empowers[slot] = w.stats.empowers[t]
    outcome.empowerConviction[slot] = w.stats.empowerConviction[t]
    outcome.conversions[slot] = w.stats.conversions[t]
    outcome.exposes[slot] = w.stats.exposes[t]
    outcome.buffPeak[slot] = w.stats.buffPeak[t]
    outcome.camouflaged[slot] = w.stats.camouflaged[t]
    outcome.robotsLost[slot] = w.stats.robotsLost[t]
  outcome.votesTied = w.stats.votesTied
  outcome.roundsNoBid = w.stats.roundsNoBid
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(teamA)] = pts[0]
  outcome.points[outcome.slotOf(teamB)] = pts[1]
  outcome.roundsPlayed = w.currentRound
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], chassis: array[2, ChassisKind21],
  index, sideAslot, maxRounds: int, budgetSeconds: int,
  onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome21) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of
  ## monotonic wall clock elapse. An abandoned game is DISCARDED by the match
  ## (its `aborted` flag says so); it is never scored half-played.
  var w = newWorld(spec, maxRounds)
  var sides = newSides21(sheets, sideAslot)
  ## `sides` is indexed by TEAM and `chassis` arrives by SEAT — re-index once
  ## here so the round loop never has to.
  let chassisByTeam = [chassis[sideAslot], chassis[1 - sideAslot]]
  var outcome = GameOutcome21(
    index: index, mapName: spec.name, sideAslot: sideAslot, winnerSlot: -1)
  let started = getMonoTime()
  let budget = initDuration(seconds = budgetSeconds)
  while w.running and w.currentRound < maxRounds:
    runRound(w, sides, chassisByTeam)
    outcome.roundChains.add(toHex(w.hashChain))
    if onRound != nil:
      onRound(w, w.currentRound)
    if w.influenceClampHit:
      ## The 1e8 influence clamp is the ONE place the end-of-round sweep order
      ## could matter (docs/RULES-BC21.md §Divergences item 4). It is
      ## unreachable in any real game; if it ever is reached the episode says
      ## so loudly rather than quietly becoming order-dependent.
      raise newException(BattlecodeError,
        "bc21: ROBOT_INFLUENCE_LIMIT reached on " & spec.name & " at round " &
        $w.currentRound & "; the end-of-round sweep is no longer provably " &
        "order-independent")
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
