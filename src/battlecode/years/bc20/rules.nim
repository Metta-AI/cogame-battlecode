## The bc20 round loop, the game, and the outcome.
##
## `runRound` mirrors `GameWorld.runRound` step for step, and the step list IS
## the rules: a re-ordering is a rules change and bumps `GameVersion`
## (docs/RULES-BC20.md §The round loop).
##
##   1. round += 1, both teams gain BASE_INCOME_PER_ROUND
##   2. every robot's beginning-of-round (a no-op in 2020, kept as a named step
##      because the hash chain and the parity trace are taken around it)
##   3. iterate the dynamic bodies in SPAWN order, skipping the already dead
##   4. a BLOCKED robot takes no turn and its cooldown does not decay — but its
##      pollution effect is still reset
##   5. beginning of turn: cooldown decay, DecisionOps budget reset
##   6. run the controller (the team chassis, or the ported cow provider)
##   7. end of turn: clear pollution, refine, vaporate, re-install pollution
##   8. end of round: mint the block, raise the water, flood one ring, check
##      the end-of-match ladder
##   9. append this round's state hash

import std/[monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import world, flood, cows, maps, knobs
import chassis/[kit, boc, scaffold]

export world, flood, maps, knobs, kit

type
  ChassisKind* = enum
    ckBowlOfChowder = "bowl-of-chowder"
    ckExamplefuncsplayer = "examplefuncsplayer"

  GameOutcome20* = object
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
    hqAlive*: array[2, bool]
    hqLostRound*: array[2, int]
    hqLostCause*: array[2, string]
    soupMined*: array[2, int]
    soupRefined*: array[2, int]
    netWorth*: array[2, int]
    unitsAlive*: array[2, int]
    unitsBuilt*: array[2, int]
    minersBuilt*: array[2, int]
    landscapersBuilt*: array[2, int]
    dronesBuilt*: array[2, int]
    vaporatorsBuilt*: array[2, int]
    netGunsBuilt*: array[2, int]
    dirtMoved*: array[2, int]
    dronePickups*: array[2, int]
    droneWaterDrops*: array[2, int]
    netGunKills*: array[2, int]
    transactionsSent*: array[2, int]
    transactionsMinted*: array[2, int]
    blockchainSoupSpent*: array[2, int]
    globalPollutionPeak*: int
    floodedTilesEnd*: int
    waterLevelEnd*: float

proc parseChassisKind*(name: string): ChassisKind =
  ## Anything unrecognised is `bowl-of-chowder`: a seat that says nothing
  ## useful plays the strong published doctrine, not the deliberately weak
  ## floor (§Decisions).
  case name
  of "examplefuncsplayer", "scaffold", "example": ckExamplefuncsplayer
  else: ckBowlOfChowder

proc chassisKindFor*(sc: ScriptedChassis): ChassisKind =
  ## The year-neutral `ScriptedChassis` mapped into bc20's own kind. A name
  ## belonging to another year falls back to bc20's STRONG chassis.
  case sc
  of scExamplefuncsplayer, scScaffold: ckExamplefuncsplayer
  else: ckBowlOfChowder

proc slotOf*(outcome: GameOutcome20, team: Team): int =
  if team == teamA: outcome.sideAslot else: 1 - outcome.sideAslot

proc newSides*(sheets: array[2, Sheet], chassis: array[2, ChassisKind],
               sideAslot: int): array[2, Side] =
  ## `sides[ord(team)]`. Which SEAT is behind team A alternates per game.
  result[0] = newSide(teamA, sheets[sideAslot].doctrine20)
  result[1] = newSide(teamB, sheets[1 - sideAslot].doctrine20)
  for t in 0 .. 1:
    result[t].applyOpening()

proc runControllerFor*(w: World, sides: array[2, Side],
                       chassis: array[2, ChassisKind], r: Robot) =
  if r.kind == rtCow:
    w.runCow(r)
    return
  if r.team == teamNeutral: return
  let side = sides[ord(r.team)]
  case chassis[ord(r.team)]
  of ckBowlOfChowder: w.runBowlOfChowder(side, r)
  of ckExamplefuncsplayer: w.runScaffold(side, r)

proc runRound*(w: World, sides: array[2, Side],
               chassis: array[2, ChassisKind]) =
  w.processBeginningOfRound()
  ## A SNAPSHOT of the exec order: bodies spawned this round do not act until
  ## the next one, and bodies that die are skipped rather than compacted out
  ## from under the iteration (`ObjectInfo.eachDynamicBodyByExecOrder`).
  let order = w.execOrder
  for id in order:
    if id notin w.robotsById: continue
    let r = w.robotsById[id]
    if r.blocked:
      ## Rule 4: no turn, no cooldown decay, but the pollution effect still
      ## goes (`GameWorld.updateRobot`).
      if r.kind.canAffectPollution():
        w.resetPollutionForRobot(r.id)
      continue
    w.processBeginningOfTurn(r)
    if r.dead: continue
    w.runControllerFor(sides, chassis, r)
    if r.dead: continue
    w.processEndOfTurn(r)

  ## Rule 8, in `GameWorld.processEndOfRound`'s own order.
  w.processBlockchain()
  let before = floodStageFor(w.waterLevel)
  w.updateWaterLevel()
  w.floodfill()
  let after = floodStageFor(w.waterLevel)
  if after > before:
    w.emit("flood_stage", after, w.floodedCount, w.currentRound)
  w.checkEndOfMatch()
  if w.hasWinner:
    w.running = false

  ## Rule 9: the per-round hash chain. Seven per-team values plus three
  ## globals; a re-derivation that diverged only in one of them would
  ## otherwise reproduce the chain and report no mismatch (the GV02 lesson).
  for t in 0 .. 1:
    w.mixHash(w.stats.soup[t])
    w.mixHash(w.stats.soupRefined[t])
    w.mixHash(w.robotCount[t])
    w.mixHash(w.netWorth(Team(t)))
    w.mixHash(w.stats.dirtMoved[t])
    w.mixHash(w.stats.blockchainsSent[t])
    w.mixHash(if w.stats.destroyedHq[t]: 0 else: 1)
  w.mixHash(w.globalPollution)
  w.mixHash(w.floodedCount)
  ## The water level enters the chain as its float32 BIT PATTERN, split into
  ## two 16-bit halves: `int(uint32)` traps under wasm32, where `int` is 32
  ## bits and half the patterns do not fit.
  let waterBits = cast[uint32](w.waterLevel)
  w.mixHash(int(waterBits shr 16))
  w.mixHash(int(waterBits and 0xFFFF'u32))

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

proc endReasonFor(w: World): string =
  case w.domination
  of dfNone: "quantity"
  else: $w.domination

proc harvest(w: World, outcome: var GameOutcome20) =
  for team in [teamA, teamB]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    outcome.hqAlive[slot] = not w.stats.destroyedHq[t]
    outcome.hqLostRound[slot] = w.hqLostRound[t]
    outcome.hqLostCause[slot] = w.hqLostCause[t]
    outcome.soupMined[slot] = w.stats.soupMined[t]
    outcome.soupRefined[slot] = w.stats.soupRefined[t]
    outcome.netWorth[slot] = w.netWorth(team)
    outcome.unitsAlive[slot] = w.robotCount[t]
    outcome.unitsBuilt[slot] = w.stats.unitsBuilt[t]
    outcome.minersBuilt[slot] = w.stats.minersBuilt[t]
    outcome.landscapersBuilt[slot] = w.stats.landscapersBuilt[t]
    outcome.dronesBuilt[slot] = w.stats.dronesBuilt[t]
    outcome.vaporatorsBuilt[slot] = w.stats.vaporatorsBuilt[t]
    outcome.netGunsBuilt[slot] = w.stats.netGunsBuilt[t]
    outcome.dirtMoved[slot] = w.stats.dirtMoved[t]
    outcome.dronePickups[slot] = w.stats.dronePickups[t]
    outcome.droneWaterDrops[slot] = w.stats.droneWaterDrops[t]
    outcome.netGunKills[slot] = w.stats.netGunKills[t]
    outcome.transactionsSent[slot] = w.stats.transactionsSent[t]
    outcome.transactionsMinted[slot] = w.stats.blockchainsSent[t]
    outcome.blockchainSoupSpent[slot] = w.stats.blockchainSoupSpent[t]
  outcome.globalPollutionPeak = w.globalPollutionPeak
  outcome.floodedTilesEnd = w.floodedCount
  outcome.waterLevelEnd = float(w.waterLevel)
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(teamA)] = pts[0]
  outcome.points[outcome.slotOf(teamB)] = pts[1]
  outcome.roundsPlayed = w.currentRound
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], chassis: array[2, ChassisKind],
  index, sideAslot, maxRounds: int, budgetSeconds: int,
  onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome20) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of
  ## monotonic wall clock elapse. An abandoned game is DISCARDED by the match
  ## (its `aborted` flag says so); it is never scored half-played.
  var w = newWorld(spec, maxRounds)
  var sides = newSides(sheets, chassis, sideAslot)
  ## `sides` is indexed by TEAM, and `chassis` arrives by SEAT — re-index it
  ## once here so the round loop never has to.
  let chassisByTeam = [chassis[sideAslot], chassis[1 - sideAslot]]
  var outcome = GameOutcome20(
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
