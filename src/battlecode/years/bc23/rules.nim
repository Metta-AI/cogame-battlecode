## The bc23 round loop, the end ladder, the points formula and one game.
##
## `runRound` mirrors `GameWorld.runRound` / `processBeginningOfRound` /
## `updateDynamicBodies` / `processEndOfRound` step for step, and THE STEP
## LIST IS THE RULES: a re-ordering is a rules change and bumps `GameVersion`
## (docs/RULES-BC23.md §The round loop).
##
##   1. beginning of round: `currentRound += 1`; every robot's
##      `processBeginningOfRound` (which only clears the indicator string, so
##      it is a NO-OP here); and ON ROUND 1 ONLY, +200 adamantium and +200
##      mana to EACH headquarters, walked in exec order
##   2. the turn order: a SNAPSHOT of the dynamic exec order, taken before the
##      sweep, with an `existsRobot` guard
##   3. each robot's turn: both cooldowns decay by 10 and floor at 0, the
##      DecisionOps budget resets, the controller runs, `roundsAlive += 1`,
##      and a robot that disintegrated is destroyed at the end of its OWN turn
##   4. end of round, in exactly this order:
##      a. every island advances a turn (ascending island id)
##      b. boosts and destabilisations expire, whole-map location order, team
##         A then team B, and each expiring destabilisation deals 50
##      c. every robot's end of round: a headquarters deals 4 to every enemy
##         within r² <= 9 and, every fifth round, banks +6/+6
##      d. currents apply
##      e. the end-of-match ladder
##      f. `running = false` if a winner is set; then the state hash
##
## STEPS 1b AND 4c ARE ASCENDING-ID SWEEPS HERE AND HASH-ORDER SWEEPS IN THE
## ENGINE (`ObjectInfo.eachRobot` -> trove `forEachValue`). D1's argument is
## written out in docs/RULES-BC23.md: 1b is a no-op with no observable effect,
## and 4c's damage and resource addition are both order-independent in outcome
## (each headquarters deals its 4 to each enemy in range exactly once; a robot
## on 4k HP with k headquarters in range dies under every order; resource
## addition commutes).

import std/[algorithm, monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import world, currents, comms, maps, knobs
import chassis/[kit, lemonade, scaffold23, scenario23]

export world, currents, comms, maps, knobs, kit

type
  ChassisKind23* = enum
    ckLemonade = "lemonade"
    ckExamplefuncsplayer23 = "examplefuncsplayer23"

  GameOutcome23* = object
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
    islandsHeldEnd*: array[2, int]
    islandsCaptured*: array[2, int]
    islandsLost*: array[2, int]
    roundsHoldingAnyIsland*: array[2, int]
    longestHoldStreak*: array[2, int]
    anchorsBuilt*: array[2, int]
    anchorsPlaced*: array[2, int]
    anchorsLost*: array[2, int]
    acceleratingAnchorsPlaced*: array[2, int]
    adamantiumEnd*: array[2, int]
    manaEnd*: array[2, int]
    elixirEnd*: array[2, int]
    adamantiumMined*: array[2, int]
    manaMined*: array[2, int]
    elixirMined*: array[2, int]
    resourcesThrown*: array[2, int]
    resourcesBanked*: array[2, int]
    wellsTransformed*: array[2, int]
    wellsUpgraded*: array[2, int]
    unitsBuilt*: array[2, int]
    carriersBuilt*: array[2, int]
    launchersBuilt*: array[2, int]
    amplifiersBuilt*: array[2, int]
    destabilizersBuilt*: array[2, int]
    boostersBuilt*: array[2, int]
    robotsAlive*: array[2, int]
    robotsLost*: array[2, int]
    damageDealt*: array[2, int]
    throwDamage*: array[2, int]
    destabilizeDamage*: array[2, int]
    hqDamage*: array[2, int]
    anchorHeals*: array[2, int]
    arrayWrites*: array[2, int]
    boostsCast*: array[2, int]
    destabilizesCast*: array[2, int]
    carrierRoundsLoaded*: array[2, int]
    currentRides*: array[2, int]
    firstAnchorRound*: array[2, int]
    capturedDistanceMean*: array[2, int]
    strikeDistanceMean*: array[2, int]
    carrierDamageTaken*: array[2, int]
    launchersBuiltBy400*: array[2, int]
    carriersBuiltBy400*: array[2, int]
    ## Scalars.
    islandsOnMap*: int
    islandsToWin*: int
    headquartersPerSide*: int
    cloudTiles*: int
    currentTiles*: int
    wellsTotal*: int

proc parseChassisKind23*(name: string): ChassisKind23 =
  ## Anything unrecognised is `lemonade`: a seat that says nothing useful
  ## plays the strong published doctrine, not the deliberately weak floor
  ## (§Decisions).
  case name
  of "examplefuncsplayer23", "examplefuncsplayer", "scaffold", "example":
    ckExamplefuncsplayer23
  else: ckLemonade

proc chassisKindFor*(sc: ScriptedChassis): ChassisKind23 =
  ## The year-neutral `ScriptedChassis` mapped into bc23's own kind. A name
  ## belonging to another year falls back to bc23's STRONG chassis.
  case sc
  of scExamplefuncsplayer23: ckExamplefuncsplayer23
  else: ckLemonade

proc slotOf*(outcome: GameOutcome23, team: Team): int =
  if team == teamA: outcome.sideAslot else: 1 - outcome.sideAslot

proc newSides23*(sheets: array[2, Sheet], sideAslot: int): array[2, Side] =
  ## `sides[ord(team)]`. Which SEAT is behind team A alternates per game.
  result[0] = newSide(teamA, sheets[sideAslot].doctrine23)
  result[1] = newSide(teamB, sheets[1 - sideAslot].doctrine23)

proc runControllerFor*(w: World, sides: array[2, Side],
                       chassis: array[2, ChassisKind23], r: Robot) =
  when defined(bc23Scenario):
    runScenario23(w, r)
  else:
    let side = sides[ord(r.team)]
    case chassis[ord(r.team)]
    of ckLemonade: runLemonade(w, side, r)
    of ckExamplefuncsplayer23: runScaffold23(w, r)

# ---------------------------------------------------------------------------
#  The end-of-match ladder, in the engine's own order
# ---------------------------------------------------------------------------

proc setWinnerIfMoreSkyIslands*(w: World): bool =
  let a = w.islandsOwned(teamA)
  let b = w.islandsOwned(teamB)
  if a > b: w.setWinner(teamA, dfMoreSkyIslands); true
  elif b > a: w.setWinner(teamB, dfMoreSkyIslands); true
  else: false

proc setWinnerIfMoreRealityAnchors*(w: World): bool =
  let a = w.stats.totalAnchorsPlaced[0]
  let b = w.stats.totalAnchorsPlaced[1]
  if a > b: w.setWinner(teamA, dfMoreRealityAnchors); true
  elif b > a: w.setWinner(teamB, dfMoreRealityAnchors); true
  else: false

proc setWinnerIfMoreElixir*(w: World): bool =
  let a = w.stats.elixir[0]
  let b = w.stats.elixir[1]
  if a > b: w.setWinner(teamA, dfMoreElixirNetWorth); true
  elif b > a: w.setWinner(teamB, dfMoreElixirNetWorth); true
  else: false

proc setWinnerIfMoreMana*(w: World): bool =
  let a = w.stats.mana[0]
  let b = w.stats.mana[1]
  if a > b: w.setWinner(teamA, dfMoreManaNetWorth); true
  elif b > a: w.setWinner(teamB, dfMoreManaNetWorth); true
  else: false

proc setWinnerIfMoreAdamantium*(w: World): bool =
  let a = w.stats.adamantium[0]
  let b = w.stats.adamantium[1]
  if a > b: w.setWinner(teamA, dfMoreAdamantiumNetWorth); true
  elif b > a: w.setWinner(teamB, dfMoreAdamantiumNetWorth); true
  else: false

proc setWinnerArbitrary*(w: World) =
  ## `setWinnerArbitrary` uses `Math.random()`, which is wall-clock seeded and
  ## therefore not reproducible. A draw from the WORLD RNG replaces it — a
  ## documented divergence (D4), reachable only when islands, anchors, elixir,
  ## mana AND adamantium are all tied at round 2000.
  w.setWinner((if w.rand.nextDouble() < 0.5: teamA else: teamB), dfCoinFlip)

func timeLimitReached*(w: World): bool =
  ## `GameWorld.timeLimitReached` is `currentRound >= gameMap.getRounds()`,
  ## and every 2023 map's `rounds` is `GAME_MAX_NUMBER_OF_ROUNDS = 2000`.
  ## ROUND 2000 IS PLAYED.
  w.currentRound >= w.maxRounds

proc checkEndOfMatch*(w: World) =
  if w.timeLimitReached() and not w.hasWinner:
    if w.setWinnerIfMoreSkyIslands(): discard
    elif w.setWinnerIfMoreRealityAnchors(): discard
    elif w.setWinnerIfMoreElixir(): discard
    elif w.setWinnerIfMoreMana(): discard
    elif w.setWinnerIfMoreAdamantium(): discard
    else: w.setWinnerArbitrary()
  if w.hasWinner:
    w.running = false

# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

func share*(x, y: int): float32 =
  ## 0.5 on a 0-0 total, the same choice bc24 and bc25 made and for the same
  ## reason: two factions that both ended with zero elixir should not be
  ## scored differently by an arithmetic accident. On THIS year's evidence
  ## that case is the COMMON one.
  if x + y == 0: 0.5'f32 else: float32(x) / float32(x + y)

proc gamePoints*(w: World): array[2, int] =
  ## A continuous reading of the engine's OWN end ladder, in its own priority
  ## order and weighted in that order: islands 60, anchors 22, elixir 10,
  ## mana 5, adamantium 3.
  ##
  ## THE WEIGHTS ARE STRICTLY SUPER-INCREASING FROM THE BOTTOM —
  ## `22 > 10+5+3`, `10 > 5+3`, `5 > 3` and `60 > 22+10+5+3` — which makes the
  ## tiebreak property PROVABLE rather than hopeful: a rung is only reached
  ## when every rung above it is tied, a tie contributes exactly 0.5 of its
  ## weight to both seats, and the winner's strict advantage on the deciding
  ## rung exceeds everything the loser can take from all rungs below it. So a
  ## win on any of the five rungs ALWAYS comes with the winner's `points`
  ## strictly above the loser's.
  ##
  ## Every share is narrowed through FLOAT32 before the weighted sum and the
  ## sum is TRUNCATED by the `int()` cast — for RECORDER/RE-DERIVER AGREEMENT:
  ## the same arithmetic runs natively on x86-64 and in wasm32 and must
  ## produce the same integer.
  let islands = [w.islandsOwned(teamA), w.islandsOwned(teamB)]
  let anchors = [w.stats.totalAnchorsPlaced[0], w.stats.totalAnchorsPlaced[1]]
  let elixir = [w.stats.elixir[0], w.stats.elixir[1]]
  let mana = [w.stats.mana[0], w.stats.mana[1]]
  let adamantium = [w.stats.adamantium[0], w.stats.adamantium[1]]
  for t in 0 .. 1:
    let o = 1 - t
    result[t] = int(60.0'f32 * share(islands[t], islands[o]) +
                    22.0'f32 * share(anchors[t], anchors[o]) +
                    10.0'f32 * share(elixir[t], elixir[o]) +
                     5.0'f32 * share(mana[t], mana[o]) +
                     3.0'f32 * share(adamantium[t], adamantium[o]))

# ---------------------------------------------------------------------------
#  One round
# ---------------------------------------------------------------------------

proc processBeginningOfRound(w: World) =
  ## Rule 1. `currentRound++`; then `processBeginningOfRound` on every robot,
  ## which clears the indicator string and NOTHING ELSE — this port has no
  ## indicator strings, so step 1b has no observable effect and no code.
  ## Then, ON ROUND 1 ONLY, walk the exec order and give EACH headquarters
  ## +200 adamantium and +200 mana, added to that headquarters' own stockpile
  ## AND to the team total.
  inc w.currentRound
  if w.currentRound == 1:
    for id in w.execOrder:
      let r = w.robotsById[id]
      if r.kind != rtHeadquarters:
        raise newException(BattlecodeError,
          "bc23: robots must be headquarters in round 1")
      w.addResourceAmount(r, resAdamantium, InitialAdAmount)
      w.addResourceAmount(r, resMana, InitialMnAmount)

proc processBeginningOfTurn(w: World, r: Robot) =
  r.actionCooldown = max(0, r.actionCooldown - CooldownsPerTurn)
  r.movementCooldown = max(0, r.movementCooldown - CooldownsPerTurn)
  r.opsLeft = budgetFor(r.kind)
  r.opsUsed = 0

proc processEndOfTurn(w: World, r: Robot) =
  r.roundsAlive += 1
  if r.opsUsed > w.opsUsedPeak: w.opsUsedPeak = r.opsUsed

proc expireTempo(w: World) =
  ## Rule 4b, in the engine's own whole-map location order (x ascending outer,
  ## y ascending inner over `getAllLocations()`), TEAM A THEN TEAM B.
  for x in 0 ..< w.width:
    for y in 0 ..< w.height:
      let l = loc(x, y)
      let i = w.idx(l)
      for teamIndex in 0 .. 1:
        let team = Team(teamIndex)
        w.tempo.expireBoosts(i, team, w.currentRound)
        let hits = w.tempo.expireDestabilizes(i, team, w.currentRound)
        if hits > 0:
          for k in 0 ..< hits:
            let victim = w.getRobot(l)
            ## AT MOST ONE ROBOT PER TILE, and only of the destabilised team.
            ## A robot can be hit twice if two entries expire together.
            if victim != nil and ord(victim.team) == teamIndex:
              let before = victim.health
              w.addHealth(victim, -RobotSpecs[rtDestabilizer].damage)
              let after = if victim.alive: victim.health else: 0
              w.stats.destabilizeDamage[1 - teamIndex] += before - after
              if not victim.alive:
                discard w.beat(BeatDestabilizeHit, "destabilize_hit",
                  1 - teamIndex, x * 100 + y, before - after)

proc robotsEndOfRound(w: World) =
  ## Rule 4c, ascending id (D1). Only a headquarters does anything.
  var ids = w.execOrder
  ids.sort()
  for id in ids:
    if not w.existsRobot(id): continue
    let r = w.robotsById[id]
    if r.kind != rtHeadquarters: continue
    for l in w.locationsWithinRadiusSquared(
        r.loc, RobotSpecs[rtHeadquarters].actionRadiusSquared):
      let other = w.getRobot(l)
      if other != nil and other.team != r.team:
        let before = other.health
        w.addHealth(other, -RobotSpecs[rtHeadquarters].damage)
        let after = if other.alive: other.health else: 0
        w.stats.hqDamage[ord(r.team)] += before - after
        w.stats.damageDealt[ord(r.team)] += before - after
    if w.currentRound mod PassiveIncreaseRounds == 0:
      w.addResourceAmount(r, resAdamantium, PassiveAdIncrease)
      w.addResourceAmount(r, resMana, PassiveMnIncrease)

proc emitConquestBeats(w: World) =
  ## `conquest_progress` fires the first time a faction reaches each of a
  ## third, two thirds and one island short of `islands_to_win`.
  let toWin = islandsToWin(w.islands.len)
  if toWin <= 0: return
  for t in 0 .. 1:
    let held = w.islandsOwned(Team(t))
    var stage = 0
    if held >= max(1, toWin - 1): stage = 3
    elif held * 3 >= toWin * 2: stage = 2
    elif held * 3 >= toWin: stage = 1
    if stage > w.conquestStage[t]:
      w.conquestStage[t] = stage
      discard w.beat(BeatConquestProgress, "conquest_progress", t, held, toWin)

proc runRound*(w: World, sides: array[2, Side],
               chassis: array[2, ChassisKind23]) =
  w.processBeginningOfRound()
  ## THE CHASSIS'S ROUND-LEVEL BOOKKEEPING RUNS BEFORE THE COUNTERS ARE
  ## CLEARED, because `retreat_on_launcher_loss` reads LAST round's losses. It
  ## ran after the reset once and the knob silently had no teeth at all.
  when not defined(bc23Scenario):
    for t in 0 .. 1:
      case chassis[t]
      of ckLemonade: beginRound(w, sides[t])
      of ckExamplefuncsplayer23: discard
  for t in 0 .. 1:
    w.lostThisRound[t] = 0
    w.launchersLostThisRound[t] = 0

  ## Rules 2 and 3. THE ARRAY BEING ITERATED IS A SNAPSHOT taken before the
  ## sweep (`dynamicBodyExecOrder.toArray()`), so a robot built this round
  ## does NOT take a turn this round, and a robot destroyed mid-sweep is
  ## skipped by the `existsRobot` guard.
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

  ## Rule 4a: every island advances a turn, ASCENDING ISLAND ID (D2).
  for islandIdx in 0 ..< w.islands.len:
    w.islandAdvanceTurn(islandIdx)
  for t in 0 .. 1:
    if w.islandsOwned(Team(t)) > 0:
      w.stats.roundsHoldingAnyIsland[t] += 1
      w.stats.holdStreak[t] += 1
      if w.stats.holdStreak[t] > w.stats.longestHoldStreak[t]:
        w.stats.longestHoldStreak[t] = w.stats.holdStreak[t]
    else:
      w.stats.holdStreak[t] = 0

  ## Rule 4b, 4c, 4d.
  w.expireTempo()
  w.robotsEndOfRound()
  if w.currentRound mod CurrentStrength == 0:
    w.applyCurrents()

  ## Beats that read the round's own deltas.
  w.emitConquestBeats()
  if w.launchersLostThisRound[0] > 0 and w.launchersLostThisRound[1] > 0:
    discard w.beat(BeatDuel, "duel", w.launchersLostThisRound[0],
      w.launchersLostThisRound[1])
  for t in 0 .. 1:
    if w.lostThisRound[t] >= 5:
      discard w.beat(BeatRout, "rout", t, w.lostThisRound[t])

  ## Rule 4e/4f.
  w.checkEndOfMatch()

  ## The per-round hash chain. Eleven per-team values plus six globals; a
  ## re-derivation that diverged only in one of them would otherwise reproduce
  ## the chain and report no mismatch (the GV02 lesson).
  for t in 0 .. 1:
    let team = Team(t)
    w.mixHash(w.islandsOwned(team))
    w.mixHash(w.stats.totalAnchorsPlaced[t])
    w.mixHash(w.stats.currentAnchorsPlaced[t])
    w.mixHash(w.stats.adamantium[t])
    w.mixHash(w.stats.mana[t])
    w.mixHash(w.stats.elixir[t])
    w.mixHash(w.robotCountByType(team, rtHeadquarters) * 100000 +
              w.robotCountByType(team, rtCarrier) * 10000 +
              w.robotCountByType(team, rtLauncher) * 1000 +
              w.robotCountByType(team, rtDestabilizer) * 100 +
              w.robotCountByType(team, rtBooster) * 10 +
              w.robotCountByType(team, rtAmplifier))
    w.mixHash(w.totalHealth(team))
    w.mixHash(w.cargoWeight(team))
    w.mixHash(w.anchorsInStock(team))
  w.mixHash(w.currentRound)
  w.mixHashU(w.islandChecksum())
  w.mixHashU(w.tempo.checksum(w.width, w.height))
  w.mixHashU(w.wellChecksum())
  w.mixHashU(w.sharedArrayChecksum())
  w.mixHash(w.execOrder.len)

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

proc endReasonFor(w: World): string =
  case w.domination
  of dfNone: "more_sky_islands"
  else: $w.domination

proc harvest(w: World, outcome: var GameOutcome23) =
  for team in [teamA, teamB]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    outcome.islandsHeldEnd[slot] = w.islandsOwned(team)
    outcome.islandsCaptured[slot] = w.stats.islandsCaptured[t]
    outcome.islandsLost[slot] = w.stats.islandsLost[t]
    outcome.roundsHoldingAnyIsland[slot] = w.stats.roundsHoldingAnyIsland[t]
    outcome.longestHoldStreak[slot] = w.stats.longestHoldStreak[t]
    outcome.anchorsBuilt[slot] = w.stats.anchorsBuilt[t]
    outcome.anchorsPlaced[slot] = w.stats.totalAnchorsPlaced[t]
    outcome.anchorsLost[slot] = w.stats.anchorsLost[t]
    outcome.acceleratingAnchorsPlaced[slot] =
      w.stats.acceleratingAnchorsPlaced[t]
    outcome.adamantiumEnd[slot] = w.stats.adamantium[t]
    outcome.manaEnd[slot] = w.stats.mana[t]
    outcome.elixirEnd[slot] = w.stats.elixir[t]
    outcome.adamantiumMined[slot] = w.stats.adamantiumMined[t]
    outcome.manaMined[slot] = w.stats.manaMined[t]
    outcome.elixirMined[slot] = w.stats.elixirMined[t]
    outcome.resourcesThrown[slot] = w.stats.resourcesThrown[t]
    outcome.resourcesBanked[slot] = w.stats.resourcesBanked[t]
    outcome.wellsTransformed[slot] = w.stats.wellsTransformed[t]
    outcome.wellsUpgraded[slot] = w.stats.wellsUpgraded[t]
    outcome.unitsBuilt[slot] = w.stats.unitsBuilt[t]
    outcome.carriersBuilt[slot] = w.stats.carriersBuilt[t]
    outcome.launchersBuilt[slot] = w.stats.launchersBuilt[t]
    outcome.amplifiersBuilt[slot] = w.stats.amplifiersBuilt[t]
    outcome.destabilizersBuilt[slot] = w.stats.destabilizersBuilt[t]
    outcome.boostersBuilt[slot] = w.stats.boostersBuilt[t]
    outcome.robotsAlive[slot] = w.robotsAlive(team)
    outcome.robotsLost[slot] = w.stats.robotsLost[t]
    outcome.damageDealt[slot] = w.stats.damageDealt[t]
    outcome.throwDamage[slot] = w.stats.throwDamage[t]
    outcome.destabilizeDamage[slot] = w.stats.destabilizeDamage[t]
    outcome.hqDamage[slot] = w.stats.hqDamage[t]
    outcome.anchorHeals[slot] = w.stats.anchorHeals[t]
    outcome.arrayWrites[slot] = w.stats.arrayWrites[t]
    outcome.boostsCast[slot] = w.stats.boostsCast[t]
    outcome.destabilizesCast[slot] = w.stats.destabilizesCast[t]
    outcome.carrierRoundsLoaded[slot] = w.stats.carrierRoundsLoaded[t]
    outcome.currentRides[slot] = w.stats.currentRides[t]
    outcome.firstAnchorRound[slot] = w.stats.firstAnchorRound[t]
    outcome.carrierDamageTaken[slot] = w.stats.carrierDamageTaken[t]
    outcome.launchersBuiltBy400[slot] = w.stats.launchersBuiltBy400[t]
    outcome.carriersBuiltBy400[slot] = w.stats.carriersBuiltBy400[t]
    outcome.capturedDistanceMean[slot] =
      (if w.stats.capturedDistanceCount[t] == 0: 0
       else: w.stats.capturedDistanceSum[t] div
             w.stats.capturedDistanceCount[t])
    outcome.strikeDistanceMean[slot] =
      (if w.stats.strikeDistanceCount[t] == 0: 0
       else: w.stats.strikeDistanceSum[t] div w.stats.strikeDistanceCount[t])
  outcome.islandsOnMap = w.islands.len
  outcome.islandsToWin = islandsToWin(w.islands.len)
  outcome.headquartersPerSide = w.headquarters[0].len
  for v in w.clouds:
    if v: outcome.cloudTiles += 1
  for d in w.currents:
    if d != dCenter: outcome.currentTiles += 1
  for well in w.wellAt:
    if well.present: outcome.wellsTotal += 1
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(teamA)] = pts[0]
  outcome.points[outcome.slotOf(teamB)] = pts[1]
  outcome.roundsPlayed = w.currentRound
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], chassis: array[2, ChassisKind23],
  index, sideAslot, maxRounds: int, budgetSeconds: int,
  onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome23) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of
  ## monotonic wall clock elapse. An abandoned game is DISCARDED by the match
  ## (its `aborted` flag says so); it is never scored half-played.
  var w = newWorld(spec, maxRounds)
  var sides = newSides23(sheets, sideAslot)
  ## `sides` is indexed by TEAM and `chassis` arrives by SEAT — re-index once
  ## here so the round loop never has to.
  let chassisByTeam = [chassis[sideAslot], chassis[1 - sideAslot]]
  var outcome = GameOutcome23(
    index: index, mapName: spec.name, sideAslot: sideAslot, winnerSlot: -1)
  discard w.beat(BeatGameStart, "game_start", index, w.width, w.height,
    spec.name & ":" & $w.islands.len & ":" & $islandsToWin(w.islands.len) &
      ":" & $w.headquarters[0].len)
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
