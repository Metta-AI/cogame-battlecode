## The bc25 round loop, the end ladder, the points formula and one game.
##
## `runRound` mirrors `GameWorld.runRound` / `processBeginningOfRound` /
## `updateDynamicBodies` / `processEndOfRound` step for step, and THE STEP LIST
## IS THE RULES: a re-ordering is a rules change and bumps `GameVersion`
## (docs/RULES-BC25.md §The round loop).
##
##   1. beginning of round: `currentRound += 1`; `updateResourcePatterns()`
##      walks the SRP list IN LIST ORDER; then every unit runs
##      `processBeginningOfRound` — messages older than five rounds dropped,
##      and TOWERS MINE
##   2. the turn order: a SNAPSHOT of the dynamic exec order, taken before the
##      sweep, with an `existsRobot` guard
##   3. beginning of turn: both cooldowns decay by 10, the two tower attack
##      flags clear, the message counter clears, the DecisionOps budget resets
##   4. run the controller
##   5. end of turn: the territory bill, the crowding bill, the 20 HP at zero
##      paint, `roundsAlive += 1`
##   6. end of round: the coverage per mille, the money snapshot, the end
##      ladder, then the state hash
##
## STEP 1c IS AN ASCENDING-ID SWEEP HERE AND A HASH-ORDER SWEEP IN THE ENGINE
## (`ObjectInfo.eachRobot` -> trove `forEachValue`). That is safe and the
## argument is written down: the sweep only clears per-unit state, tops up a
## tower's OWN capped paint stash, and adds to a COMMUTATIVE team chip total.
## No branch in it reads another unit's state (docs/RULES-BC25.md §Divergences
## item 3).

import std/[algorithm, monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import world, towers, comms, maps, knobs, patterns
import chassis/[kit, spaark, scaffold25]

export world, towers, comms, maps, knobs, kit

type
  ChassisKind25* = enum
    ckSpaark = "spaark"
    ckExamplefuncsplayer25 = "examplefuncsplayer25"

  GameOutcome25* = object
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
    squaresPainted*: array[2, int]
    coveragePermille*: array[2, int]
    peakCoveragePermille*: array[2, int]
    tilesPainted*: array[2, int]
    tilesMopped*: array[2, int]
    tilesOverpainted*: array[2, int]
    chipsEnd*: array[2, int]
    chipsEarned*: array[2, int]
    chipsSpent*: array[2, int]
    paintInUnitsEnd*: array[2, int]
    paintMined*: array[2, int]
    paintSpent*: array[2, int]
    robotsBuilt*: array[2, int]
    soldiersBuilt*: array[2, int]
    splashersBuilt*: array[2, int]
    moppersBuilt*: array[2, int]
    robotsAlive*: array[2, int]
    robotsLost*: array[2, int]
    robotRoundsStarved*: array[2, int]
    towersBuilt*: array[2, int]
    towersUpgraded*: array[2, int]
    towersAlive*: array[2, int]
    towersLost*: array[2, int]
    moneyTowersEnd*: array[2, int]
    paintTowersEnd*: array[2, int]
    defenseTowersEnd*: array[2, int]
    srpCompleted*: array[2, int]
    srpActiveEnd*: array[2, int]
    srpRoundsActive*: array[2, int]
    splashAttacks*: array[2, int]
    mopSwings*: array[2, int]
    towerDamageDealt*: array[2, int]
    robotDamageDealt*: array[2, int]
    messagesSent*: array[2, int]
    markersPlaced*: array[2, int]
    ## Scalars.
    paintableTiles*: int
    areaWithoutWalls*: int
    tilesToWin*: int
    ruins*: int
    roundsWithAnySrp*: int

proc parseChassisKind25*(name: string): ChassisKind25 =
  ## Anything unrecognised is `spaark`: a seat that says nothing useful plays
  ## the strong published doctrine, not the deliberately weak floor
  ## (§Decisions).
  case name
  of "examplefuncsplayer25", "examplefuncsplayer", "scaffold", "example":
    ckExamplefuncsplayer25
  else: ckSpaark

proc chassisKindFor*(sc: ScriptedChassis): ChassisKind25 =
  ## The year-neutral `ScriptedChassis` mapped into bc25's own kind. A name
  ## belonging to another year falls back to bc25's STRONG chassis.
  case sc
  of scExamplefuncsplayer25: ckExamplefuncsplayer25
  else: ckSpaark

proc slotOf*(outcome: GameOutcome25, team: Team): int =
  if team == teamA: outcome.sideAslot else: 1 - outcome.sideAslot

proc newSides25*(sheets: array[2, Sheet], sideAslot: int): array[2, Side] =
  ## `sides[ord(team)]`. Which SEAT is behind team A alternates per game.
  result[0] = newSide(teamA, sheets[sideAslot].doctrine25)
  result[1] = newSide(teamB, sheets[1 - sideAslot].doctrine25)

proc runControllerFor*(w: World, sides: array[2, Side],
                       chassis: array[2, ChassisKind25], r: Robot) =
  let side = sides[ord(r.team)]
  case chassis[ord(r.team)]
  of ckSpaark: runSpaark(w, side, r)
  of ckExamplefuncsplayer25: runScaffold25(w, side, r)

# ---------------------------------------------------------------------------
#  The end-of-match ladder, in the engine's own order
# ---------------------------------------------------------------------------

proc setWinnerIfMoreSquaresPainted*(w: World): bool =
  let a = w.stats.livePainted[0]
  let b = w.stats.livePainted[1]
  if a > b: w.setWinner(teamA, dfMoreSquaresPainted); true
  elif b > a: w.setWinner(teamB, dfMoreSquaresPainted); true
  else: false

proc setWinnerIfMoreTowersAlive*(w: World): bool =
  let a = w.stats.towers[0]
  let b = w.stats.towers[1]
  if a > b: w.setWinner(teamA, dfMoreTowersAlive); true
  elif b > a: w.setWinner(teamB, dfMoreTowersAlive); true
  else: false

proc setWinnerIfMoreMoney*(w: World): bool =
  let a = w.stats.money[0]
  let b = w.stats.money[1]
  if a > b: w.setWinner(teamA, dfMoreMoney); true
  elif b > a: w.setWinner(teamB, dfMoreMoney); true
  else: false

proc setWinnerIfMorePaintInUnits*(w: World): bool =
  let a = w.paintInUnits(teamA)
  let b = w.paintInUnits(teamB)
  if a > b: w.setWinner(teamA, dfMorePaintInUnits); true
  elif b > a: w.setWinner(teamB, dfMorePaintInUnits); true
  else: false

proc setWinnerIfMoreRobotsAlive*(w: World): bool =
  let a = w.robotsAlive(teamA)
  let b = w.robotsAlive(teamB)
  if a > b: w.setWinner(teamA, dfMoreRobotsAlive); true
  elif b > a: w.setWinner(teamB, dfMoreRobotsAlive); true
  else: false

proc setWinnerArbitrary*(w: World) =
  ## `setWinnerArbitrary` uses `Math.random()`, which is wall-clock seeded and
  ## therefore not reproducible. A draw from the WORLD RNG replaces it — a
  ## documented divergence, reachable only when area, towers, chips, paint and
  ## robot counts are ALL tied at round 2000
  ## (docs/RULES-BC25.md §Divergences item 2).
  w.setWinner((if w.rand.nextDouble() < 0.5: teamA else: teamB), dfCoinFlip)

func timeLimitReached*(w: World): bool =
  ## `GameWorld.timeLimitReached` is `currentRound >= gameMap.getRounds()`, and
  ## every 2025 map's `rounds` is `GAME_MAX_NUMBER_OF_ROUNDS = 2000`. ROUND
  ## 2000 IS PLAYED.
  w.currentRound >= w.maxRounds

proc checkEndOfMatch*(w: World) =
  if w.timeLimitReached() and not w.hasWinner:
    if w.setWinnerIfMoreSquaresPainted(): discard
    elif w.setWinnerIfMoreTowersAlive(): discard
    elif w.setWinnerIfMoreMoney(): discard
    elif w.setWinnerIfMorePaintInUnits(): discard
    elif w.setWinnerIfMoreRobotsAlive(): discard
    else: w.setWinnerArbitrary()
  if w.hasWinner:
    w.running = false

# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

func share*(x, y: int): float32 =
  ## 0.5 on a 0-0 total, the same choice bc24 made and for the same reason:
  ## two clans that both ended with zero towers should not be scored
  ## differently by an arithmetic accident.
  if x + y == 0: 0.5'f32 else: float32(x) / float32(x + y)

proc gamePoints*(w: World): array[2, int] =
  ## A continuous reading of the engine's OWN end ladder, in its own priority
  ## order and weighted in that order: area 55, towers 20, chips 10, paint 10,
  ## robots 5.
  ##
  ## Every share is narrowed through FLOAT32 before the weighted sum and the
  ## sum is TRUNCATED by the `int()` cast — not for fidelity to Java (this
  ## formula is ours) but for RECORDER/RE-DERIVER AGREEMENT: the same
  ## arithmetic runs natively on x86-64 and in wasm32 and must produce the
  ## same integer.
  ##
  ## Because a rung is only reached when every rung above it is TIED — and a
  ## tie gives both seats a share of exactly 0.5 on that term — a win on any
  ## of the five rungs ALWAYS comes with the winner's weighted sum strictly
  ## above the loser's.
  let area = [w.stats.livePainted[0], w.stats.livePainted[1]]
  let towers = [w.stats.towers[0], w.stats.towers[1]]
  let chips = [w.stats.money[0], w.stats.money[1]]
  let paint = [w.paintInUnits(teamA), w.paintInUnits(teamB)]
  let bots = [w.robotsAlive(teamA), w.robotsAlive(teamB)]
  for t in 0 .. 1:
    let o = 1 - t
    result[t] = int(55.0'f32 * share(area[t], area[o]) +
                    20.0'f32 * share(towers[t], towers[o]) +
                    10.0'f32 * share(chips[t], chips[o]) +
                    10.0'f32 * share(paint[t], paint[o]) +
                     5.0'f32 * share(bots[t], bots[o]))

# ---------------------------------------------------------------------------
#  One round
# ---------------------------------------------------------------------------

proc processBeginningOfRound(w: World) =
  ## Rule 1. `currentRound++`, then `updateResourcePatterns()`, then every
  ## unit's own beginning-of-round: drop stale messages and — for towers only
  ## — MINE.
  inc w.currentRound
  w.updateResourcePatterns()
  var ids = w.execOrder
  ids.sort()
  for id in ids:
    if not w.existsRobot(id): continue
    let r = w.robotsById[id]
    w.cleanMessages(r)
    if r.kind.isTowerType():
      w.mine(r)

proc emitCoverageBeats(w: World) =
  ## `coverage` fires the first time a clan crosses each multiple of 100 per
  ## mille upward, which caps it at fourteen a game.
  for t in 0 .. 1:
    let permille = coveragePermille(w.stats.livePainted[t], w.areaWithoutWalls)
    if permille > w.stats.peakCoverage[t]:
      w.stats.peakCoverage[t] = permille
    let decile = permille div 100
    if decile > w.coverageDecile[t]:
      w.coverageDecile[t] = decile
      discard w.beat(BeatCoverage, "coverage", t, decile * 100,
        max(0, tilesToWin(w.areaWithoutWalls) - w.stats.livePainted[t]))

proc runRound*(w: World, sides: array[2, Side],
               chassis: array[2, ChassisKind25]) =
  w.processBeginningOfRound()
  for t in 0 .. 1:
    w.starvedThisRound[t] = 0
    w.lostThisRound[t] = 0

  ## Rules 2 to 5. THE ARRAY BEING ITERATED IS A SNAPSHOT taken before the
  ## sweep (`dynamicBodyExecOrder.toArray()`), so a unit built this round does
  ## NOT take a turn this round, and a unit destroyed mid-sweep is skipped by
  ## the `existsRobot` guard.
  let snapshot = w.execOrder
  for id in snapshot:
    if not w.existsRobot(id): continue
    let r = w.robotsById[id]
    w.processBeginningOfTurn(r)
    w.runControllerFor(sides, chassis, r)
    if w.existsRobot(id):
      w.processEndOfTurn(r)

  ## Rule 6a/6b: the per-team round stats and the money snapshot. The
  ## coverage per mille is the one place the round loop touches floating
  ## point.
  w.emitCoverageBeats()
  for t in 0 .. 1:
    if w.starvedThisRound[t] >= 5:
      discard w.beat(BeatStarved, "starved", t, w.starvedThisRound[t])
    if w.lostThisRound[t] >= 5:
      discard w.beat(BeatRout, "rout", t, w.lostThisRound[t])
  for t in 0 .. 1:
    w.stats.defenseBuffRounds[t] += w.damageIncrease[t]
  if w.currentRound == 1000:
    for t in 0 .. 1:
      w.stats.chipsAt1000[t] = w.stats.money[t]
      w.stats.paintTowersAt1000[t] = w.towerCountByKind(Team(t), tkPaint)

  ## Rule 6c/6d.
  w.checkEndOfMatch()

  ## The per-round hash chain. Eight per-team values plus five globals; a
  ## re-derivation that diverged only in one of them would otherwise reproduce
  ## the chain and report no mismatch (the GV02 lesson).
  var colourHash = 0xCBF29CE484222325'u64
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      colourHash = (colourHash xor uint64(w.colours[x + y * w.width])) *
        0x100000001B3'u64
  var markerHash = 0xCBF29CE484222325'u64
  for t in 0 .. 1:
    for i in 0 ..< w.markers[t].len:
      markerHash = (markerHash xor uint64(w.markers[t][i])) *
        0x100000001B3'u64
  var hpSum = 0
  for id in w.execOrder:
    hpSum += w.robotsById[id].health
  for t in 0 .. 1:
    let team = Team(t)
    w.mixHash(w.stats.livePainted[t])
    w.mixHash(w.stats.money[t])
    w.mixHash(w.stats.towers[t])
    w.mixHash(w.towerCountByKind(team, tkPaint) * 100 +
              w.towerCountByKind(team, tkMoney) * 10 +
              w.towerCountByKind(team, tkDefense))
    w.mixHash(w.robotsAlive(team))
    w.mixHash(w.paintInUnits(team))
    w.mixHash(w.numActiveResourcePatterns(team))
    var lifetimes = 0
    for centre in w.srpCentres:
      if int(w.srpTeamByLoc[w.idx(centre)]) == t + 1:
        lifetimes += int(w.srpLifetimes[w.idx(centre)])
    w.mixHash(lifetimes)
  w.mixHash(w.currentRound)
  w.mixHashU(colourHash)
  w.mixHashU(markerHash)
  w.mixHash(hpSum)
  w.mixHash(w.execOrder.len)

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

proc endReasonFor(w: World): string =
  case w.domination
  of dfNone: "more_squares_painted"
  else: $w.domination

proc harvest(w: World, outcome: var GameOutcome25) =
  for team in [teamA, teamB]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    outcome.squaresPainted[slot] = w.stats.livePainted[t]
    outcome.coveragePermille[slot] =
      coveragePermille(w.stats.livePainted[t], w.areaWithoutWalls)
    outcome.peakCoveragePermille[slot] = w.stats.peakCoverage[t]
    outcome.tilesPainted[slot] = w.stats.tilesPainted[t]
    outcome.tilesMopped[slot] = w.stats.tilesMopped[t]
    outcome.tilesOverpainted[slot] = w.stats.tilesOverpainted[t]
    outcome.chipsEnd[slot] = w.stats.money[t]
    outcome.chipsEarned[slot] = w.stats.chipsEarned[t]
    outcome.chipsSpent[slot] = w.stats.chipsSpent[t]
    outcome.paintInUnitsEnd[slot] = w.paintInUnits(team)
    outcome.paintMined[slot] = w.stats.paintMined[t]
    outcome.paintSpent[slot] = w.stats.paintSpent[t]
    outcome.robotsBuilt[slot] = w.stats.robotsBuilt[t]
    outcome.soldiersBuilt[slot] = w.stats.soldiersBuilt[t]
    outcome.splashersBuilt[slot] = w.stats.splashersBuilt[t]
    outcome.moppersBuilt[slot] = w.stats.moppersBuilt[t]
    outcome.robotsAlive[slot] = w.robotsAlive(team)
    outcome.robotsLost[slot] = w.stats.robotsLost[t]
    outcome.robotRoundsStarved[slot] = w.stats.robotRoundsStarved[t]
    outcome.towersBuilt[slot] = w.stats.towersBuilt[t]
    outcome.towersUpgraded[slot] = w.stats.towersUpgraded[t]
    outcome.towersAlive[slot] = w.stats.towers[t]
    outcome.towersLost[slot] = w.stats.towersLost[t]
    outcome.moneyTowersEnd[slot] = w.towerCountByKind(team, tkMoney)
    outcome.paintTowersEnd[slot] = w.towerCountByKind(team, tkPaint)
    outcome.defenseTowersEnd[slot] = w.towerCountByKind(team, tkDefense)
    outcome.srpCompleted[slot] = w.stats.srpCompleted[t]
    outcome.srpActiveEnd[slot] = w.numActiveResourcePatterns(team)
    outcome.srpRoundsActive[slot] = w.stats.srpRoundsActive[t]
    outcome.splashAttacks[slot] = w.stats.splashAttacks[t]
    outcome.mopSwings[slot] = w.stats.mopSwings[t]
    outcome.towerDamageDealt[slot] = w.stats.towerDamageDealt[t]
    outcome.robotDamageDealt[slot] = w.stats.robotDamageDealt[t]
    outcome.messagesSent[slot] = w.stats.messagesSent[t]
    outcome.markersPlaced[slot] = w.stats.markersPlaced[t]
  outcome.paintableTiles = w.trulyPaintable
  outcome.areaWithoutWalls = w.areaWithoutWalls
  outcome.tilesToWin = tilesToWin(w.areaWithoutWalls)
  outcome.ruins = w.allRuins.len
  outcome.roundsWithAnySrp = w.stats.roundsWithAnySrp
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(teamA)] = pts[0]
  outcome.points[outcome.slotOf(teamB)] = pts[1]
  outcome.roundsPlayed = w.currentRound
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], chassis: array[2, ChassisKind25],
  index, sideAslot, maxRounds: int, budgetSeconds: int,
  onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome25) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of
  ## monotonic wall clock elapse. An abandoned game is DISCARDED by the match
  ## (its `aborted` flag says so); it is never scored half-played.
  var w = newWorld(spec, maxRounds)
  var sides = newSides25(sheets, sideAslot)
  ## `sides` is indexed by TEAM and `chassis` arrives by SEAT — re-index once
  ## here so the round loop never has to.
  let chassisByTeam = [chassis[sideAslot], chassis[1 - sideAslot]]
  var outcome = GameOutcome25(
    index: index, mapName: spec.name, sideAslot: sideAslot, winnerSlot: -1)
  discard w.beat(BeatGameStart, "game_start", index, w.width, w.height,
    spec.name)
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
