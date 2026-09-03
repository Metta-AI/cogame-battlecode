## The round loop, the game, and the match.
##
## `runRound` mirrors `GameWorld.runRound` step for step, and the step list is
## the rules: a re-ordering is a rules change and bumps `GameVersion`
## (docs/RULES.md §The round loop).
##
##   1. round += 1
##   2. every robot's beginning-of-round (message expiry)
##   3. iterate the dynamic bodies in SPAWN order, skipping the already dead
##   4. beginning of turn — the FIRST body runs every cheese mine, then
##      carried-rat bookkeeping, throw travel, cooldown decay
##   5. the body's controller (the clan chassis, or nothing for a cat)
##   6. end of turn — king consumption/starvation, then the cat state machine
##   7. end of round — team stats into the hash chain
##   8. end-of-match check in the engine's own order

import std/[monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import constants, world, cats
import chassis/[kit, awu, scaffold]

export world, constants, kit

type
  GameOutcome* = object
    index*: int
    mapName*: string
    sideAslot*: int              ## which SEAT plays team A this game
    roundsPlayed*: int
    winnerSlot*: int             ## -1 = no winner recorded (abandoned)
    endReason*: EndReason
    cooperationAtEnd*: bool
    backstabRound*: int          ## -1 when the alliance held
    backstabBySlot*: int         ## -1 when the alliance held
    backstabTrigger*: string
    points*: array[2, int]       ## BY SEAT
    catDamage*: array[2, int]
    cheeseTransferred*: array[2, int]
    kingsAlive*: array[2, int]
    kingsBuilt*: array[2, int]
    ratsBuilt*: array[2, int]
    ratsAlive*: array[2, int]
    trapsPlaced*: array[2, int]
    dirtPlaced*: array[2, int]
    catsFed*: array[2, int]
    hashChain*: string
    aborted*: bool

proc slotOf*(outcome: GameOutcome, team: Team): int =
  ## Seat index for a team in this game. Sides alternate per game, so the
  ## mapping is per game, never global.
  if team == teamA: outcome.sideAslot else: 1 - outcome.sideAslot

proc teamOfSlot*(sideAslot, slot: int): Team =
  if slot == sideAslot: teamA else: teamB

proc runControllerFor*(w: World, clans: array[2, Clan], r: Robot) =
  if r.unit == utCat: return
  if r.team == teamNeutral: return
  let clan = clans[ord(r.team)]
  case clan.doctrine.chassis
  of chAwu: runAwu(w, clan, r)
  of chScaffold: runScaffold(w, clan, r)

proc endOfTurnFor*(w: World, clans: array[2, Clan], r: Robot) =
  if not r.isGrabbedByRobot and not r.isThrown:
    r.turnsSinceThrownOrDropped += 1

  if r.unit == utRatKing and w.teamInfo.numRatKings[ord(r.team)] > 0:
    if w.teamInfo.globalCheese[ord(r.team)] < RatKingCheeseConsumption:
      w.addHealth(r, -RatKingHealthLoss)
      if r.dead: return
    else:
      w.addRobotCheese(r, -RatKingCheeseConsumption)

  if r.unit == utCat:
    runCatTurn(w, r)
    if r.dead: return

  r.roundsAlive += 1

proc runRound*(w: World, clans: array[2, Clan]) =
  w.processBeginningOfRound()
  ## A SNAPSHOT of the exec order: bodies spawned this round do not act until
  ## the next one, and bodies that die are skipped rather than compacted out
  ## from under the iteration (`ObjectInfo.eachDynamicBodyByExecOrder`).
  let order = w.execOrder
  for id in order:
    if id notin w.robotsById: continue
    let r = w.robotsById[id]
    w.processBeginningOfTurn(r)
    ## The engine keeps calling into a robot that died inside its own
    ## beginning-of-turn; here the turn simply ends, which is the only place
    ## this port deliberately simplifies the loop (docs/RULES.md).
    if r.dead: continue
    runControllerFor(w, clans, r)
    if r.dead: continue
    endOfTurnFor(w, clans, r)
  w.processEndOfRound()

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

proc newClans*(sheets: array[2, Sheet], sideAslot: int): array[2, Clan] =
  ## `clans[ord(team)]`. Which SEAT is behind team A alternates per game.
  result[0] = newClan(teamA, sheets[sideAslot].doctrine)
  result[1] = newClan(teamB, sheets[1 - sideAslot].doctrine)

proc endReasonFor(w: World): EndReason =
  if w.domination == dfKillAllRatKings: erKingsDestroyed
  elif w.numCats == 0 and w.hasWinner: erCatsCleared
  else: erRoundLimit

proc harvest(w: World, clans: array[2, Clan], outcome: var GameOutcome) =
  for team in [teamA, teamB]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    outcome.catDamage[slot] = w.teamInfo.damageToCats[t]
    outcome.cheeseTransferred[slot] = w.teamInfo.cheeseTransferred[t]
    outcome.kingsAlive[slot] = w.teamInfo.numRatKings[t]
    outcome.kingsBuilt[slot] = w.teamInfo.kingsBuilt[t]
    outcome.ratsBuilt[slot] = w.teamInfo.ratsBuilt[t]
    outcome.ratsAlive[slot] = w.teamInfo.numBabyRats[t]
    outcome.trapsPlaced[slot] = w.teamInfo.trapsPlaced[t]
    outcome.dirtPlaced[slot] = w.teamInfo.dirtPlaced[t]
    outcome.catsFed[slot] = clans[t].catsFed
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(teamA)] = pts[0]
  outcome.points[outcome.slotOf(teamB)] = pts[1]
  outcome.cooperationAtEnd = w.isCooperation
  outcome.backstabRound = if w.hasBackstabber: w.backstabRound else: -1
  outcome.backstabBySlot =
    if w.hasBackstabber: outcome.slotOf(w.backstabber) else: -1
  outcome.backstabTrigger = w.backstabTrigger
  outcome.roundsPlayed = w.currentRound
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], index, sideAslot, maxRounds: int,
  budgetSeconds: int, onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of
  ## monotonic wall clock elapse. An abandoned game is DISCARDED by the match
  ## (its `aborted` flag says so); it is never scored half-played.
  var w = newWorld(spec, maxRounds)
  let clans = newClans(sheets, sideAslot)
  var outcome = GameOutcome(
    index: index, mapName: spec.name, sideAslot: sideAslot,
    winnerSlot: -1, backstabRound: -1, backstabBySlot: -1
  )
  let started = getMonoTime()
  let budget = initDuration(seconds = budgetSeconds)
  while w.running and w.currentRound < maxRounds:
    runRound(w, clans)
    if onRound != nil:
      onRound(w, w.currentRound)
    if budgetSeconds > 0 and (w.currentRound and 0x1F) == 0 and
        getMonoTime() - started >= budget:
      outcome.aborted = true
      break
  if outcome.aborted:
    outcome.endReason = erAbandoned
    harvest(w, clans, outcome)
    outcome.winnerSlot = -1
    return (w, outcome)
  outcome.endReason = w.endReasonFor()
  harvest(w, clans, outcome)
  if w.hasWinner:
    outcome.winnerSlot = outcome.slotOf(w.winner)
  return (w, outcome)
