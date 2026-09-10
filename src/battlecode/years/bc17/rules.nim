## The bc17 round loop, the two immediate win conditions, the four-rung
## round-limit ladder, the points formula and one game.
##
## `runRound` mirrors `GameWorld.runRound` (`:88-118`) step for step, **AND
## THE STEP LIST IS THE RULES**: a re-ordering is a rules change and bumps
## `GameVersion` (docs/RULES-BC17.md §The round loop).
##
##   1. `processBeginningOfRound` (`:208-224`): `currentRound += 1`;
##      `previousBroadcasters = currentBroadcasters.values(...)` in TROVE
##      order and then `clear()` WITH THE CAPACITY RETAINED (D1); then
##      `eachRobot`/`eachTree`'s `healthChanged = false` sweeps, which have
##      **no state effect at all** -- said explicitly so nobody ports an
##      order that does not matter.
##   2. `updateDynamicBodies` (`:130-140`): `dynamicBodyExecOrder.toArray()`
##      **SNAPSHOTTED BEFORE THE LOOP**, then per id a robot turn (rule 4) or
##      a bullet update (rule 5), skipping any id that no longer exists. So a
##      body spawned this round does NOT act this round.
##   3. `updateTrees` (`:120-128`): the float32 income sum in trove order.
##   4. `processEndOfRound` (`:251-327`): the replay-only sweeps plus each
##      TREE's `roundsAlive++`; the bullet income for A then B; and, at
##      `currentRound >= rounds - 1` with no winner, the four-rung ladder.
##   5. `if (winner != null) running = false` -- **and nothing before this
##      point stops the round**, so a game decided mid-round still plays its
##      income, its decay and its deaths, and a `setWinner` later in the same
##      round OVERWRITES the earlier one.
##
## A game that was decided in round R is not reported DONE until the call for
## round R+1, exactly as `runRound`'s first line does it.

import std/[math, monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import constants, units, geom, world, trees, ballistics, actions, maps, knobs
import chassis/[kit, econ, farm, comms, micro, military, archon, gardener,
  lumberjack, scout, donate, orchard, examplefuncsplayer17, scenario17]

export world, maps, knobs, actions, trees, ballistics, kit

type
  ChassisKind17* = enum
    ck17Orchard = "orchard"
    ck17Examplefuncsplayer17 = "examplefuncsplayer17"

  GameOutcome17* = object
    index*: int
    mapName*: string
    sideAslot*: int              ## which SEAT plays engine-side Team.A
    roundsPlayed*: int
    winnerSlot*: int             ## -1 = no winner recorded (abandoned)
    endReason*: string
    points*: array[2, int]       ## BY SEAT
    hashChain*: string
    roundChains*: string
    aborted*: bool
    ## Per-game statistics, BY SEAT. Every float quantity is in TENTHS as an
    ## integer (the bc16 convention), because a raw float32 in a JSON results
    ## document is a formatter argument waiting to happen.
    archonsStart*: array[2, int]
    archonsEnd*: array[2, int]
    archonsLost*: array[2, int]
    gardenersBuilt*: array[2, int]
    gardenersEnd*: array[2, int]
    gardenersLost*: array[2, int]
    lumberjacksBuilt*: array[2, int]
    soldiersBuilt*: array[2, int]
    tanksBuilt*: array[2, int]
    scoutsBuilt*: array[2, int]
    unitsBuilt*: array[2, int]
    unitsAlive*: array[2, int]
    unitsLost*: array[2, int]
    victoryPoints*: array[2, int]
    bulletsEndTenths*: array[2, int]
    bulletsEarnedFromTreesTenths*: array[2, int]
    bulletsShakenTenths*: array[2, int]
    bulletsDonatedTenths*: array[2, int]
    bulletsSpentOnUnitsTenths*: array[2, int]
    bulletsSpentOnTreesTenths*: array[2, int]
    bulletsSpentOnShotsTenths*: array[2, int]
    bulletsTrickledTenths*: array[2, int]
    bulletWorthEndTenths*: array[2, int]
    treesPlanted*: array[2, int]
    treesEnd*: array[2, int]
    treesLost*: array[2, int]
    treesMatureEnd*: array[2, int]
    waterActions*: array[2, int]
    shakeActions*: array[2, int]
    chopActions*: array[2, int]
    neutralTreesFelled*: array[2, int]
    robotsReleasedFromTrees*: array[2, int]
    bulletsFired*: array[2, int]
    singleShots*: array[2, int]
    triadShots*: array[2, int]
    pentadShots*: array[2, int]
    attacks*: array[2, int]
    damageDealtTenths*: array[2, int]
    damageTakenTenths*: array[2, int]
    friendlyFireDamageTenths*: array[2, int]
    ownTreesDamagedTenths*: array[2, int]
    strikeActions*: array[2, int]
    bodyAttacks*: array[2, int]
    kills*: array[2, int]
    robotsLost*: array[2, int]
    moves*: array[2, int]
    broadcasts*: array[2, int]
    buildsRefused*: array[2, int]
    refusedActions*: array[2, int]
    decisionOpsPeak*: array[2, int]
    ## Telemetry the gates read.
    tanksBuiltBy600*: array[2, int]
    lumberjacksBuiltBy600*: array[2, int]
    scoutsBuiltBy600*: array[2, int]
    enemyGardenersKilled*: array[2, int]
    enemyTreesFelled*: array[2, int]
    treesAliveAt1500*: array[2, int]
    matureTreesBy600*: array[2, int]
    archonsAliveAt2000*: array[2, int]
    roundsBelowOneBullet*: array[2, int]
    treesLostToStrike*: array[2, int]
    ## Scalars.
    archonsPerSide*: int
    boardWidthTenths*: int
    boardHeightTenths*: int
    neutralTreesStart*: int
    neutralTreesWithBullets*: int
    neutralTreesWithRobots*: int
    archonSeparationMinTenths*: int
    archonSeparationMaxTenths*: int
    robotIdsIssued*: int
    bulletIdsIssued*: int
    peakBulletsInFlight*: int
    dominationFactor*: string
    tiebreakRound*: int

const DominationNames* = ["-", "PHILANTROPIED", "DESTROYED", "PWNED",
                          "OWNED", "BARELY_BEAT", "WON_BY_DUBIOUS_REASONS"]
  ## The engine's own `DominationFactor` names, carried beside our
  ## snake_case `end_reason` so a replay always traces back to a branch of
  ## the engine.

proc chassisFromName*(name: string): ChassisKind17 =
  case name.strip().toLowerAscii()
  of "examplefuncsplayer17", "examplefuncsplayer", "example", "scaffold":
    ck17Examplefuncsplayer17
  else: ck17Orchard

proc chassisKindFor*(sc: ScriptedChassis): ChassisKind17 =
  ## The year-neutral `ScriptedChassis` mapped into bc17's own kind. A name
  ## belonging to another year falls back to bc17's STRONG chassis, so a bc19
  ## name on a bc17 game plays `orchard` rather than nothing.
  case sc
  of scExamplefuncsplayer17, scScaffold: ck17Examplefuncsplayer17
  else: ck17Orchard

func slotOf*(outcome: GameOutcome17, team: Team): int =
  if team == tA: outcome.sideAslot else: 1 - outcome.sideAslot

proc newSides17*(sheets: array[2, Sheet], sideAslot: int): array[2, Side] =
  ## `sides[ord(team)]`. Which SEAT is behind engine-side Team.A alternates
  ## per game.
  result[0] = newSide(tA, sheets[sideAslot].doctrine17)
  result[1] = newSide(tB, sheets[1 - sideAslot].doctrine17)

proc runControllerFor*(w: World, sides: array[2, Side],
                       chassis: array[2, ChassisKind17], r: Robot) =
  when defined(bc17Idle):
    ## **TIER A**, and it is CI-only: `-d:bc17Idle` is the Nim twin of
    ## `tools/oracle/bc17/bc17idle/RobotPlayer.java`, whose whole body is
    ## `while (true) Clock.yield();`. **THIS TIER IS DELIBERATELY SMALL, and
    ## that is worth saying**: in 2017 NOTHING HAPPENS WITHOUT A PLAYER
    ## ACTION -- no NPCs, no passive spawning, no terrain change -- so what it
    ## proves is the round counter, the initial exec order off the map file,
    ## the neutral-tree pass (up to 1 228 trees a round, all returning zero
    ## income but all taking `processBeginningOfRound` and `roundsAlive++`),
    ## the trove machinery idle, THE INCOME CLIFF, and the ladder falling
    ## through to rung 4.
    discard
  elif defined(bc17Scenario) or defined(bc17ScenarioTree) or
       defined(bc17ScenarioKill) or defined(bc17ScenarioTie):
    runScenario17(w, r)
  else:
    let side = sides[ord(r.team)]
    case chassis[ord(r.team)]
    of ck17Orchard: runOrchard(w, side, r)
    of ck17Examplefuncsplayer17: runExamplefuncsplayer17(w, r)

# ---------------------------------------------------------------------------
#  Rule 4 -- one robot's turn
# ---------------------------------------------------------------------------

func canExecuteCode*(r: Robot): bool =
  ## `InternalRobot.canExecuteCode` (`:281-287`) --
  ## `health > 0 && (isBuildable() ? roundsAlive >= 20 : true)`. **A newly
  ## built fighter does NOTHING AT ALL for its first twenty turns** while it
  ## heals 4 % a turn, and a hired GARDENER acts from its second round (its
  ## first is the exec-order snapshot, not this rule).
  if r.health <= 0'f32: return false
  if isBuildable(r.kind): return r.roundsAlive >= DormancyRounds
  true

proc processBeginningOfTurn(w: World, r: Robot) =
  ## `InternalRobot.processBeginningOfTurn` (`:250-263`), in order.
  r.attackCount = 0
  r.moveCount = 0
  r.repairCount = 0
  r.waterCount = 0
  r.shakeCount = 0
  if r.buildCooldownTurns > 0:
    r.buildCooldownTurns -= 1
  if r.roundsAlive < DormancyRounds and isBuildable(r.kind):
    w.repairRobot(r, repairPerDormantTurn(r.kind))
  ## `currentBytecodeLimit = type.bytecodeLimit`, i.e. this turn's op budget
  ## (V1). `getBytecodeLimit()` returns 0 unless `canExecuteCode()`.
  r.ops = (if r.canExecuteCode(): opsFor(r.kind) else: DormantOps)
  r.opsUsed = 0

proc updateRobot(w: World, sides: array[2, Side],
                 chassis: array[2, ChassisKind17], r: Robot) =
  ## `GameWorld.updateRobot` (`:142-157`).
  w.processBeginningOfTurn(r)
  w.lastAction[r.id] = (act: ActNothing, tgt: 0, x: 0'f32, y: 0'f32,
                        arg: 0'f32)
  if r.ops > 0:
    try:
      w.runControllerFor(sides, chassis, r)
    except BattlecodeError:
      ## The engine's sandbox swallows a player exception and charges 500
      ## bytecodes; this port counts a refusal and moves on.
      w.stats.refusedActions[ord(r.team)] += 1
  let t = ord(r.team)
  if r.opsUsed > w.stats.decisionOpsPeak[t]:
    w.stats.decisionOpsPeak[t] = r.opsUsed
  ## `if (robot.getHealth() > 0) robot.processEndOfTurn()` -- a robot that
  ## died during its own turn does NOT increment `roundsAlive`.
  if r.alive and r.health > 0'f32:
    r.roundsAlive += 1

proc updateDynamicBodies(w: World, sides: array[2, Side],
                         chassis: array[2, ChassisKind17]) =
  ## `GameWorld.updateDynamicBodies` + `ObjectInfo.eachDynamicBodyByExecOrder`
  ## (`:132-155`): **the snapshot is taken BEFORE the loop**.
  let snapshot = w.execOrder
  for id in snapshot:
    if w.robots.hasKey(id):
      w.updateRobot(sides, chassis, w.robots[id])
    elif w.bullets.hasKey(id):
      w.updateBullet(w.bullets[id])
    else:
      ## The body was destroyed in an earlier iteration and is skipped --
      ## the engine's own `continue`.
      discard

# ---------------------------------------------------------------------------
#  Rules 2 and 9 -- the round's ends
# ---------------------------------------------------------------------------

proc processBeginningOfRound(w: World) =
  w.currentRound += 1
  w.updateBroadcastData()
  ## `eachRobot(processBeginningOfRound)` and `eachTree(...)` clear a
  ## replay-only `healthChanged` flag and have NO STATE EFFECT, so the trove
  ## order they walk is not observable and is deliberately not reproduced
  ## here (`InternalRobot.java:246-248`, `InternalTree.java:404-406`).

func timeLimitReached*(w: World): bool =
  ## `GameWorld.timeLimitReached` == `currentRound >= rounds - 1`, i.e. round
  ## **2 999** with the engine's own `rounds = 3000`.
  w.currentRound >= w.maxRounds - 1

proc runLadder(w: World) =
  ## `processEndOfRound`'s four-rung ladder (`:270-317`), first match wins.
  ## **There is no coin flip and no RNG anywhere on this path.**
  var victorDetermined = false
  if w.victoryPoints[ord(tA)] != w.victoryPoints[ord(tB)]:
    w.setWinner((if w.victoryPoints[ord(tA)] > w.victoryPoints[ord(tB)]: tA
                 else: tB), RungMoreVictoryPoints)
    victorDetermined = true
  if not victorDetermined:
    ## Rung 2 counts **all** own trees, sapling or mature: `getTreeCount` is a
    ## plain counter with no notion of "active" (disagreement 4).
    if w.treeCount[ord(tA)] != w.treeCount[ord(tB)]:
      w.setWinner((if w.treeCount[ord(tA)] > w.treeCount[ord(tB)]: tA
                   else: tB), RungMoreBulletTrees)
      victorDetermined = true
  var bestRobotId = low(int)
  var bestRobotTeam = tNeutral
  if not victorDetermined:
    ## Rung 3 walks `objectInfo.robots()` ONCE, computing both the highest
    ## robot id (rung 4's answer) and the two totals -- and
    ## `ARCHON.bulletCost` is `-1`, so each surviving archon SUBTRACTS a
    ## bullet (disagreement 3).
    var totalA = w.bulletSupply[ord(tA)]
    var totalB = w.bulletSupply[ord(tB)]
    for id, r in w.robots:
      if r.id > bestRobotId:
        bestRobotId = r.id
        bestRobotTeam = r.team
      if r.team == tA:
        totalA = totalA + bulletCostF(r.kind)
      else:
        totalB = totalB + bulletCostF(r.kind)
    if totalA != totalB:
      w.setWinner((if totalA > totalB: tA else: tB), RungMoreBulletWorth)
      victorDetermined = true
  if not victorDetermined:
    ## Rung 4: **the highest ROBOT id of any type**, not the highest archon
    ## id the spec claims (disagreement 2). With no robots at all the engine
    ## sets a null winner; this port keeps the team field and reports the rung.
    w.setWinner(bestRobotTeam, RungHighestId)
  w.tiebreakRound = w.currentRound

proc processEndOfRound(w: World) =
  ## `GameWorld.processEndOfRound` (`:251-327`).
  ## `eachRobot(processEndOfRound)` is replay-only; `eachTree` is replay-only
  ## **plus `roundsAlive++`**, which is the tree maturity clock.
  for id in w.treeKeys.forEachValue:
    if w.trees.hasKey(id):
      w.trees[id].roundsAlive += 1
  ## The round bullet income, A then B: `max(0, 2 - 0.01 * supply)` -- ZERO
  ## at any supply of 200 or more (measured).
  for team in [tA, tB]:
    let trickle = max(0'f32, archonBulletIncome -
      bulletIncomeUnitPenalty * w.bulletSupplyOf(team))
    w.adjustBulletSupply(team, trickle)
    w.stats.bulletsTrickled[ord(team)] =
      w.stats.bulletsTrickled[ord(team)] + trickle
  if w.timeLimitReached() and not w.hasWinner:
    w.runLadder()
  if w.hasWinner:
    w.running = false

# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

func share*(x, y: int): float32 =
  ## A 0-0 total is 0.5, NOT 0 (the bc16/bc19/bc22..bc25 choice): two sides
  ## that both donated nothing should not be separated by an arithmetic
  ## accident, and rung 1 falling through is the NORMAL case.
  if x + y == 0: 0.5'f32 else: float32(x) / float32(x + y)

func shareF*(x, y: float32): float32 =
  if x + y == 0'f32: 0.5'f32 else: x / (x + y)

proc gamePoints*(w: World): array[2, int] =
  ## A continuous reading of the engine's OWN tiebreak ladder, in its own
  ## priority order and weighted in that order: victory points 64, bullet
  ## trees 24, bullet worth 12. Rung 4 (highest robot id) is deliberately not
  ## a term: it measures nothing about play.
  ##
  ## `worth` uses the engine's own expression, **the archon's -1 included**,
  ## and is CLAMPED AT ZERO before `share` because a side reduced to three
  ## archons and no bullets has `worth = -3` and a negative share is not a
  ## share. **The clamp is applied to the SCORE only, never to the ladder** --
  ## the ladder compares the raw values, so a `worth` of -1 still beats -3 on
  ## rung 3 while both score 0.5.
  ##
  ## The weights are SUPER-INCREASING (`24 > 12` and `64 > 24 + 12`), so a
  ## DECISIVE margin on a higher rung dominates everything below it. THIS
  ## CLAIMS NO MORE THAN THAT: a 501-to-499 victory-point margin is 0.128 of
  ## a point against 36 available below, so **`points` ALONE CAN FAVOUR THE
  ## LOSER**. It measures the SHAPE of the game, not who won it;
  ## `results.scores` adds 200 per game won and is win-dominated by
  ## construction.
  let vp = [w.victoryPoints[ord(tA)], w.victoryPoints[ord(tB)]]
  let treeN = [w.treeCount[ord(tA)], w.treeCount[ord(tB)]]
  let worth = [max(0'f32, w.bulletWorth(tA)), max(0'f32, w.bulletWorth(tB))]
  for t in 0 .. 1:
    let o = 1 - t
    result[t] = int(64.0'f32 * share(vp[t], vp[o]) +
                    24.0'f32 * share(treeN[t], treeN[o]) +
                    12.0'f32 * shareF(worth[t], worth[o]))

# ---------------------------------------------------------------------------
#  One round
# ---------------------------------------------------------------------------

proc foldRoundHash(w: World) =
  ## THIRTEEN per-team values plus ELEVEN globals, so a re-derivation that
  ## diverged in only one of them cannot reproduce the chain (the GV02
  ## lesson). **Folding the bullet supply's RAW 32 BITS is a bc17-specific
  ## decision and the cheapest possible tripwire for a float divergence**:
  ## one wrong ulp in the tree-income sum shows up on the round it happens
  ## instead of as a mystery 400 rounds later.
  for t in 0 .. 1:
    let team = Team(t)
    w.mixHash(w.unitCount(team, rtArchon))
    w.mixHash(w.unitCount(team, rtGardener))
    w.mixHash(w.unitCount(team, rtLumberjack))
    w.mixHash(w.unitCount(team, rtSoldier))
    w.mixHash(w.unitCount(team, rtTank))
    w.mixHash(w.unitCount(team, rtScout))
    w.mixHash(w.treeCount[t])
    w.mixHashBits(w.bulletSupply[t])
    w.mixHash(w.victoryPoints[t])
    w.mixHash(w.stats.unitsBuilt[t])
    w.mixHash(w.stats.unitsLost[t])
    w.mixHash(w.stats.treesPlanted[t])
    w.mixHash(w.stats.treesLost[t])
  w.mixHash(w.currentRound)
  w.mixHashU(w.execOrderFold())
  w.mixHash(w.execOrder.len)
  w.mixHashU(w.robotBodyFold())
  w.mixHashU(w.treeBodyFold())
  w.mixHashU(w.bulletBodyFold())
  w.mixHash(w.bullets.len)
  w.mixHash(w.robotIdsIssued)
  w.mixHash(w.bulletIdsIssued)
  w.mixHash(w.idGen.cursor)
  w.mixHash(w.bulletIdGen.cursor)

proc emitRoundBeats(w: World) =
  if w.stats.lostThisRound[0] > 0 and w.stats.lostThisRound[1] > 0:
    discard w.beat(BeatDuel, "duel", w.stats.lostThisRound[0],
                   w.stats.lostThisRound[1])
  for t in 0 .. 1:
    if w.stats.lostThisRound[t] >= 4:
      discard w.beat(BeatRout, "rout", t, w.stats.lostThisRound[t])
    w.stats.lostThisRound[t] = 0
    if w.firedThisRound[t] >= 10:
      w.volleyBeats[t] += 1
      if w.volleyBeats[t] == 1 or (w.volleyBeats[t] mod 8) == 0:
        discard w.beat(BeatVolley, "volley", t, w.firedThisRound[t], 0,
                       $w.lastShotShape[t])
    w.firedThisRound[t] = 0
    ## The famine beat: the first round a side's supply is below one bullet.
    if w.bulletSupply[t] < 1'f32:
      w.stats.roundsBelowOneBullet[t] += 1
      if not w.famineSeen[t]:
        w.famineSeen[t] = true
        discard w.beat(BeatFamine, "famine", t)

proc sampleTelemetry(w: World) =
  ## Statistics no rule reads, sampled at the rounds the gates ask about.
  if w.currentRound == 600:
    for t in 0 .. 1:
      w.stats.matureTreesBy600[t] = w.matureTrees(Team(t))
  if w.currentRound == 1500:
    for t in 0 .. 1:
      w.stats.treesAliveAt1500[t] = w.treesAlive(Team(t))
  if w.currentRound == 2000:
    for t in 0 .. 1:
      w.stats.archonsAliveAt2000[t] = w.unitCount(Team(t), rtArchon)
  ## The mean distance of own fighters from own archons, and the mean pairwise
  ## distance between own trees -- the two `opening`/`farm_layout` deltas.
  if (w.currentRound mod 100) == 0:
    for t in 0 .. 1:
      let team = Team(t)
      var archons: seq[Loc]
      for id, r in w.robots:
        if r.team == team and r.kind == rtArchon: archons.add(r.loc)
      if archons.len > 0:
        for id, r in w.robots:
          if r.team != team or r.kind == rtArchon or r.kind == rtGardener:
            continue
          var best = -1'f32
          for a in archons:
            let d = distanceTo(r.loc, a)
            if best < 0'f32 or d < best: best = d
          w.stats.fighterDistanceSum[t] += int(best * 10'f32)
          w.stats.fighterDistanceSamples[t] += 1
      var locs: seq[Loc]
      for id, tr in w.trees:
        if tr.team == team: locs.add(tr.loc)
      if locs.len >= 2:
        for i in 0 ..< locs.len:
          for j in i + 1 ..< locs.len:
            w.stats.treePairDistanceSum[t] += int(distanceTo(locs[i],
                                                             locs[j]) * 10'f32)
            w.stats.treePairDistanceSamples[t] += 1

proc runRound*(w: World, sides: array[2, Side],
               chassis: array[2, ChassisKind17]) =
  ## ONE ROUND, in the engine's own method order.
  if not w.running: return
  when not defined(bc17Idle) and not defined(bc17Scenario) and
       not defined(bc17ScenarioTree) and not defined(bc17ScenarioKill) and
       not defined(bc17ScenarioTie):
    for t in 0 .. 1:
      if chassis[t] == ck17Orchard:
        beginRound(w, sides[t])
  w.processBeginningOfRound()
  w.updateDynamicBodies(sides, chassis)
  w.updateTrees()
  w.processEndOfRound()
  w.emitRoundBeats()
  w.sampleTelemetry()
  w.foldRoundHash()

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

func endReasonFor*(w: World): string =
  ## FAULT, never mislabel: `RungNone` is "no winner at all", which
  ## `processEndOfRound`'s ladder cannot produce while `maxRounds >= 2`.
  if w.domination == RungNone:
    raise newException(Defect,
      "bc17: the game ended with no ladder rung at round " &
      $w.currentRound & " of " & $w.maxRounds & ", hasWinner=" &
      $w.hasWinner & ". The four-rung ladder cannot produce that, so a rule " &
      "has changed; labelling it `more_victory_points` would hide it.")
  Bc17RungNames[w.domination]

proc harvest(w: World, outcome: var GameOutcome17) =
  for team in [tA, tB]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    template seat(field, value: untyped) = outcome.field[slot] = value
      ## NOT named `put`: `trove.nim`'s own `put` is in scope through
      ## `world.nim`, and an overload beats a template.
    template tenths(value: float32): int = int(value * 10'f32)
    seat(archonsStart, w.stats.archonsStart[t])
    seat(archonsEnd, w.unitCount(team, rtArchon))
    seat(archonsLost, w.stats.archonsLost[t])
    seat(gardenersBuilt, w.stats.gardenersBuilt[t])
    seat(gardenersEnd, w.unitCount(team, rtGardener))
    seat(gardenersLost, w.stats.gardenersLost[t])
    seat(lumberjacksBuilt, w.stats.lumberjacksBuilt[t])
    seat(soldiersBuilt, w.stats.soldiersBuilt[t])
    seat(tanksBuilt, w.stats.tanksBuilt[t])
    seat(scoutsBuilt, w.stats.scoutsBuilt[t])
    seat(unitsBuilt, w.stats.unitsBuilt[t])
    seat(unitsAlive, w.robotsAlive(team))
    seat(unitsLost, w.stats.unitsLost[t])
    seat(victoryPoints, w.victoryPoints[t])
    seat(bulletsEndTenths, tenths(w.bulletSupply[t]))
    seat(bulletsEarnedFromTreesTenths, tenths(w.stats.bulletsFromTrees[t]))
    seat(bulletsShakenTenths, tenths(w.stats.bulletsShaken[t]))
    seat(bulletsDonatedTenths, tenths(w.stats.bulletsDonated[t]))
    seat(bulletsSpentOnUnitsTenths, tenths(w.stats.bulletsSpentOnUnits[t]))
    seat(bulletsSpentOnTreesTenths, tenths(w.stats.bulletsSpentOnTrees[t]))
    seat(bulletsSpentOnShotsTenths, tenths(w.stats.bulletsSpentOnShots[t]))
    seat(bulletsTrickledTenths, tenths(w.stats.bulletsTrickled[t]))
    seat(bulletWorthEndTenths, tenths(w.bulletWorth(team)))
    seat(treesPlanted, w.stats.treesPlanted[t])
    seat(treesEnd, w.treesAlive(team))
    seat(treesLost, w.stats.treesLost[t])
    seat(treesMatureEnd, w.matureTrees(team))
    seat(waterActions, w.stats.waterActions[t])
    seat(shakeActions, w.stats.shakeActions[t])
    seat(chopActions, w.stats.chopActions[t])
    seat(neutralTreesFelled, w.stats.neutralTreesFelled[t])
    seat(robotsReleasedFromTrees, w.stats.robotsReleasedFromTrees[t])
    seat(bulletsFired, w.stats.bulletsFired[t])
    seat(singleShots, w.stats.singleShots[t])
    seat(triadShots, w.stats.triadShots[t])
    seat(pentadShots, w.stats.pentadShots[t])
    seat(attacks, w.stats.attacks[t])
    seat(damageDealtTenths, tenths(w.stats.damageDealt[t]))
    seat(damageTakenTenths, tenths(w.stats.damageTaken[t]))
    seat(friendlyFireDamageTenths, tenths(w.stats.friendlyFireDamage[t]))
    seat(ownTreesDamagedTenths, tenths(w.stats.ownTreesDamaged[t]))
    seat(strikeActions, w.stats.strikeActions[t])
    seat(bodyAttacks, w.stats.bodyAttacks[t])
    seat(kills, w.stats.kills[t])
    seat(robotsLost, w.stats.unitsLost[t])
    seat(moves, w.stats.moves[t])
    seat(broadcasts, w.stats.broadcasts[t])
    seat(buildsRefused, w.stats.buildsRefused[t])
    seat(refusedActions, w.stats.refusedActions[t])
    seat(decisionOpsPeak, w.stats.decisionOpsPeak[t])
    seat(tanksBuiltBy600, w.stats.tanksBuiltBy600[t])
    seat(lumberjacksBuiltBy600, w.stats.lumberjacksBuiltBy600[t])
    seat(scoutsBuiltBy600, w.stats.scoutsBuiltBy600[t])
    seat(enemyGardenersKilled, w.stats.enemyGardenersKilled[t])
    seat(enemyTreesFelled, w.stats.enemyTreesFelled[t])
    seat(treesAliveAt1500, w.stats.treesAliveAt1500[t])
    seat(matureTreesBy600, w.stats.matureTreesBy600[t])
    seat(archonsAliveAt2000, w.stats.archonsAliveAt2000[t])
    seat(roundsBelowOneBullet, w.stats.roundsBelowOneBullet[t])
    seat(treesLostToStrike, w.stats.treesLostToStrike[t])
  outcome.archonsPerSide = w.map.archonsPerSide
  outcome.boardWidthTenths = int(w.rect.width * 10'f32)
  outcome.boardHeightTenths = int(w.rect.height * 10'f32)
  outcome.neutralTreesStart = w.map.neutralTrees
  outcome.neutralTreesWithBullets = w.map.treesWithBullets
  outcome.neutralTreesWithRobots = w.map.treesWithRobots
  outcome.archonSeparationMinTenths = w.map.separationMinTenths
  outcome.archonSeparationMaxTenths = w.map.separationMaxTenths
  outcome.robotIdsIssued = w.robotIdsIssued
  outcome.bulletIdsIssued = w.bulletIdsIssued
  outcome.peakBulletsInFlight = w.stats.peakBulletsInFlight
  outcome.dominationFactor = DominationNames[w.domination]
  outcome.tiebreakRound = w.tiebreakRound
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(tA)] = pts[0]
  outcome.points[outcome.slotOf(tB)] = pts[1]
  outcome.roundsPlayed = w.currentRound
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], chassis: array[2, ChassisKind17],
  index, sideAslot, maxRounds: int, budgetSeconds: int,
  onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome17) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of
  ## monotonic wall clock elapse. An abandoned game is DISCARDED by the match
  ## (its `aborted` flag says so); it is never scored half-played.
  ##
  ## `budgetSeconds <= 0` means UNBOUNDED here. `match.nim`'s
  ## `perGame = max(1, min(field, remaining))` clamps ONE LEVEL UP, so a test
  ## helper that zeroes that field buys a ONE-SECOND budget rather than an
  ## unbounded one -- every bc17 test uses the `if perGame > 0:` convention
  ## instead.
  var w = newWorld(spec, maxRounds)
  var sides = newSides17(sheets, sideAslot)
  ## `sides` is indexed by TEAM and `chassis` arrives by SEAT -- re-index once
  ## here so the round loop never has to.
  let chassisByTeam = [chassis[sideAslot], chassis[1 - sideAslot]]
  var outcome = GameOutcome17(
    index: index, mapName: spec.name, sideAslot: sideAslot, winnerSlot: -1)
  let (rlo, rhi) = spec.treeRadiusRange()
  discard w.beat(BeatGameStart, "game_start", index,
                 int(w.rect.width * 10'f32) * 10000 +
                   int(w.rect.height * 10'f32),
                 spec.archonsPerSide,
                 spec.name & ":" & $spec.mapSeed & ":" &
                   $spec.neutralTrees & ":" & $spec.treesWithBullets & ":" &
                   $spec.treesWithRobots & ":" &
                   $spec.separationMinTenths & ":" & $int(rlo * 10.0) & ":" &
                   $int(rhi * 10.0))
  let started = getMonoTime()
  let budget = initDuration(seconds = budgetSeconds)
  while w.running:
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
  if w.hasWinner and w.winner != tNeutral:
    outcome.winnerSlot = outcome.slotOf(w.winner)
  if w.domination in {RungMoreVictoryPoints, RungMoreBulletTrees,
                      RungMoreBulletWorth, RungHighestId}:
    discard w.beat(BeatTiebreak, "tiebreak", w.domination,
                   w.victoryPoints[ord(tA)] * 100000 +
                     w.victoryPoints[ord(tB)],
                   w.treeCount[ord(tA)] * 100000 + w.treeCount[ord(tB)],
                   $int(w.bulletWorth(tA) * 10'f32) & ":" &
                     $int(w.bulletWorth(tB) * 10'f32))
  discard w.beat(BeatGameEnd, "game_end", index,
                 (if outcome.winnerSlot >= 0: outcome.winnerSlot else: -1),
                 outcome.points[0] * 1000 + outcome.points[1],
                 outcome.endReason & ":" & outcome.dominationFactor & ":" &
                   $outcome.victoryPoints[0] & ":" &
                   $outcome.victoryPoints[1] & ":" &
                   $outcome.treesEnd[0] & ":" & $outcome.treesEnd[1])
  (w, outcome)
