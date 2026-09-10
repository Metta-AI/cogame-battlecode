## The bc19 driver loop, the seven-rung `isOver` ladder, the points formula
## and one game.
##
## `runRound` mirrors `runtime.js`'s `gameLoop` (`:58-76`) and `game.js`'s
## `enactTurn` (`:746-788`) step for step, AND THE STEP LIST IS THE RULES: a
## re-ordering is a rules change and bumps `GameVersion`
## (`docs/RULES-BC19.md` §The round loop).
##
##   1. THE DRIVER LOOP, repeated until it stops:
##      a. drain the init queue — in this port every robot is handed its
##         side's chassis at the moment it is created, so the queue is always
##         empty, `initialized` is always true and `hook` is never null. That
##         makes `isOver`'s win conditions 3 and 4 UNREACHABLE HERE (V6);
##      b. **evaluate `isOver()` — BEFORE EVERY SINGLE TURN, not at the end
##         of a round.** Two consequences the port reproduces and tests: a
##         game that ends by castle annihilation stops IMMEDIATELY AFTER THE
##         KILLING ROBOT'S TURN and the rest of that round's robots do NOT
##         act; and ROUND 1000 CONSISTS OF EXACTLY ONE ROBOT TURN — measured,
##         999 full rounds plus one turn, 6 994 turns on `seed-0043`;
##      c. if not over, `enactTurn()`.
##   2. `enactTurn`:
##      a. if `robin >= robots.len`: `robin = 0`; `round += 1`; `fuel[RED] +=
##         25`; `fuel[BLUE] += 25`. `robin` starts at `Infinity` and `round`
##         at 0, so THE FIRST PLAYED ROUND IS ROUND 1 and the trickle lands
##         BEFORE the round's first robot acts;
##      b. `robot = robots[robin]`; `robot.turn += 1`;
##      c. `robot.time += CHESS_EXTRA` — V1: the robot is credited
##         `ChessExtraOps`;
##      d. build the observation and run the chassis. A CHASSIS EXCEPTION IS
##         SWALLOWED and becomes "no action";
##      e. a FRESH `ActionRecord`, then the validation ladder. A validation
##         failure leaves the record with whatever was already set and
##         discards the rest;
##      f. `record.enact(game, robot)`;
##      g. eight bytes appended to the `.bc19` replay — NOT PORTED (V5).

import std/[monotimes, strutils, times]
import ../../sim_types
import ../../sheet
import constants, units, mt19937, world, vision, resources, actions, maps,
  knobs
import chassis/[kit, econ, castle, pilgrim, military, micro, saber,
  examplefuncsplayer19, scenario19]

export world, maps, knobs, actions, kit

type
  ChassisKind19* = enum
    ck19Saber = "saber"
    ck19Examplefuncsplayer19 = "examplefuncsplayer19"

  GameOutcome19* = object
    index*: int
    mapName*: string
    sideAslot*: int              ## which SEAT plays engine-side RED
    roundsPlayed*: int
    winnerSlot*: int             ## -1 = no winner recorded (abandoned)
    endReason*: string
    points*: array[2, int]       ## BY SEAT
    hashChain*: string
    roundChains*: string
    aborted*: bool
    ## Per-game statistics, BY SEAT.
    castlesStart*: array[2, int]
    castlesEnd*: array[2, int]
    castlesLost*: array[2, int]
    churchesBuilt*: array[2, int]
    churchesEnd*: array[2, int]
    churchesLost*: array[2, int]
    enemyHalfChurches*: array[2, int]
    unitHealthEnd*: array[2, int]
    karboniteEnd*: array[2, int]
    fuelEnd*: array[2, int]
    netWorthEnd*: array[2, int]
    karboniteMined*: array[2, int]
    fuelMined*: array[2, int]
    karboniteSpent*: array[2, int]
    fuelSpent*: array[2, int]
    fuelTrickled*: array[2, int]
    karboniteReclaimed*: array[2, int]
    fuelReclaimed*: array[2, int]
    karboniteDeposited*: array[2, int]
    fuelDeposited*: array[2, int]
    unitsBuilt*: array[2, int]
    pilgrimsBuilt*: array[2, int]
    crusadersBuilt*: array[2, int]
    prophetsBuilt*: array[2, int]
    preachersBuilt*: array[2, int]
    unitsAlive*: array[2, int]
    unitsLost*: array[2, int]
    mineActions*: array[2, int]
    mineActionsWasted*: array[2, int]
    giveActions*: array[2, int]
    attacks*: array[2, int]
    damageDealt*: array[2, int]
    damageTaken*: array[2, int]
    friendlyFireDamage*: array[2, int]
    selfDamage*: array[2, int]
    splashKills*: array[2, int]
    kills*: array[2, int]
    robotsLost*: array[2, int]
    moves*: array[2, int]
    moveFuelSpent*: array[2, int]
    radioMessages*: array[2, int]
    radioFuelSpent*: array[2, int]
    castleTalks*: array[2, int]
    tradesProposed*: array[2, int]
    tradesExecuted*: array[2, int]
    tradeKarboniteNet*: array[2, int]
    tradeFuelNet*: array[2, int]
    latticeUnitsPlaced*: array[2, int]
    buildsRefused*: array[2, int]
    refusedActions*: array[2, int]
    decisionOpsPeak*: array[2, int]
    ## Scalars.
    castlesPerSide*: int
    boardWidth*: int
    passableSquares*: int
    karboniteDepots*: int
    fuelDepots*: int
    symmetryHorizontal*: int
    castleSeparationMin*: float
    castleSeparationMax*: float
    idsSpent*: int
    winCondition*: int
    tiebreakRound*: int
    queueLengthEnd*: int

proc chassisFromName*(name: string): ChassisKind19 =
  case name.strip().toLowerAscii()
  of "examplefuncsplayer19", "examplefuncsplayer", "example", "scaffold":
    ck19Examplefuncsplayer19
  else: ck19Saber

proc chassisKindFor*(sc: ScriptedChassis): ChassisKind19 =
  ## The year-neutral `ScriptedChassis` mapped into bc19's own kind. A name
  ## belonging to another year falls back to bc19's STRONG chassis, so a bc22
  ## name on a bc19 game plays `saber` rather than nothing.
  case sc
  of scExamplefuncsplayer19, scScaffold: ck19Examplefuncsplayer19
  else: ck19Saber

func slotOf*(outcome: GameOutcome19, team: Team): int =
  if team == tRed: outcome.sideAslot else: 1 - outcome.sideAslot

proc newSides19*(sheets: array[2, Sheet], sideAslot: int): array[2, Side] =
  ## `sides[ord(team)]`. Which SEAT is behind engine-side RED alternates per
  ## game.
  result[0] = newSide(tRed, sheets[sideAslot].doctrine19)
  result[1] = newSide(tBlue, sheets[1 - sideAslot].doctrine19)

proc runControllerFor*(w: World, sides: array[2, Side],
                       chassis: array[2, ChassisKind19], r: Robot): Action =
  when defined(bc19Idle):
    ## **TIER A**, and it is CI-only: `-d:bc19Idle` is the Nim twin of
    ## `tools/oracle/bc19/bc19idle/robot.js`, whose whole `turn()` returns
    ## `null`. THIS TIER IS DELIBERATELY SMALL, and that is the single most
    ## important difference between bc19 parity and bc16 parity: in bc16 the
    ## zombies are engine-side, so an idle player still exercises half the
    ## game; IN BC19 NOTHING AT ALL HAPPENS WITHOUT A PLAYER ACTION. What it
    ## does prove is the queue and `robin`, the round counter, the flat fuel
    ## trickle, the initial castles' id draws off the committed MT state, the
    ## `isOver` evaluation points, and the round-1000 ladder with all three
    ## rungs.
    newAction()
  elif defined(bc19Scenario):
    runScenario19(w, r)
  else:
    let side = sides[ord(r.team)]
    case chassis[ord(r.team)]
    of ck19Saber: runSaber(w, side, r)
    of ck19Examplefuncsplayer19: runExamplefuncsplayer19(w, r)

# ---------------------------------------------------------------------------
#  Rule 5 — the seven-rung ladder, in the engine's own order
# ---------------------------------------------------------------------------

proc evaluateIsOver*(w: World): bool =
  ## `game.js:537-614`: one census pass, then a seven-branch ladder, first
  ## match wins. Rungs 1 and 2 are UNREACHABLE in this port (V6) and are
  ## written out anyway so the ladder reads as the engine's.
  ##
  ## **THE `win_condition = 1` OVERWRITE IS REPRODUCED LITERALLY.** At
  ## `:604` the engine executes `this.win_condition = 1;` UNCONDITIONALLY at
  ## the end of the round-1000 else block, AFTER the inner branch has already
  ## set 2 for the coin-flip case. So a round-1000 all-square game is
  ## RECORDED BY THE ENGINE as win condition 1 ("greater health") while the
  ## winner really is a coin flip. The port keeps BOTH: the trace and
  ## `results.games[].win_condition` carry the engine's own number, and
  ## `end_reason` carries the finer-grained truth.
  if w.winCondition >= 0: return true
  var red = 0
  var blue = 0
  var castles = [0, 0]
  var nulls = [0, 0]
  var total = [0, 0]
  for r in w.robots:
    total[ord(r.team)] += 1
    ## Every robot in this port is initialized and has a hook (V6), so the
    ## `else nulls[team]++` arm is unreachable.
    if r.team == tRed: red += r.health else: blue += r.health
    if r.unit == ukCastle: castles[ord(r.team)] += 1
  if total[0] == 0: nulls[0] = -1
  if total[1] == 0: nulls[1] = -1

  if nulls[0] == total[0] and nulls[1] == total[1]:
    ## Rung 1 — UNREACHABLE (V6).
    w.winner = Team(int(w.gen.random() > 0.5))
    w.winCondition = 4
    w.endRung = Bc19RungCoinFlip
  elif nulls[0] == total[0]:
    w.winner = tBlue
    w.winCondition = 3
    w.endRung = Bc19RungCastlesDestroyed
  elif nulls[1] == total[1]:
    w.winner = tRed
    w.winCondition = 3
    w.endRung = Bc19RungCastlesDestroyed
  elif castles[0] == 0 and castles[1] != 0:
    w.winner = tBlue
    w.winCondition = 0
    w.endRung = Bc19RungCastlesDestroyed
  elif castles[0] != 0 and castles[1] == 0:
    w.winner = tRed
    w.winCondition = 0
    w.endRung = Bc19RungCastlesDestroyed
  elif castles[0] == 0 and castles[1] == 0:
    w.winCondition = 2
    w.winner = Team(int(w.gen.random() > 0.5))
    w.endRung = Bc19RungCoinFlip
  elif w.round >= w.maxRounds:
    w.tiebreakRound = w.round
    if castles[0] != castles[1]:
      w.winner = (if castles[1] > castles[0]: tBlue else: tRed)
      w.winCondition = 0
      w.endRung = Bc19RungMoreCastles
    else:
      if red != blue:
        w.winner = (if red > blue: tRed else: tBlue)
        w.endRung = Bc19RungMoreUnitHealth
      else:
        w.winCondition = 2
        w.winner = Team(int(w.gen.random() > 0.5))
        w.endRung = Bc19RungCoinFlip
      ## `:604`, verbatim and unconditional.
      w.winCondition = 1
    discard w.beat(BeatTiebreak, "tiebreak", w.endRung,
                   castles[0] * 100 + castles[1],
                   w.worthOf(tRed) * 100000 + w.worthOf(tBlue),
                   $red & ":" & $blue)
  if w.winCondition >= 0:
    w.hasWinner = true
    return true
  false

# ---------------------------------------------------------------------------
#  Scoring
# ---------------------------------------------------------------------------

func share*(x, y: int): float32 =
  ## A 0-0 total is 0.5, NOT 0 (the bc16/bc22-bc25 choice): two orders that
  ## both ended castle-less should not be separated by an arithmetic
  ## accident, and rung 4 of the ladder proves that is a real outcome.
  if x + y == 0: 0.5'f32 else: float32(x) / float32(x + y)

proc gamePoints*(w: World): array[2, int] =
  ## A continuous reading of the engine's OWN tiebreak ladder, in its own
  ## priority order and weighted in that order: castles 64, total unit health
  ## 24, net worth 12.
  ##
  ## Every quantity is ALREADY AN INTEGER — bc19 has no float state at all
  ## (D5) — so unlike bc16 there is NO tenths-narrowing anywhere. The only
  ## floats are the three `float32` shares and the TRUNCATING `int()`, which
  ## is what makes `points` reproducible bit for bit between the native
  ## recorder and the wasm re-deriver.
  ##
  ## The weights are SUPER-INCREASING (`24 > 12` and `64 > 24 + 12`), so a
  ## DECISIVE margin on a higher rung dominates everything below it. THIS
  ## CLAIMS NO MORE THAN THAT: a one-castle margin on a 3-vs-2 board is
  ## `3/5 - 2/5 = 0.2` of 64 = 12.8 points against 36 available below, so
  ## `points` ALONE CAN FAVOUR THE LOSER. It measures the SHAPE of the game,
  ## not who won it; `results.scores` adds 200 per game won and IS
  ## win-dominated by construction.
  ##
  ## THE `end_reason` IS NOT COMPUTED THIS WAY: the ladder uses the engine's
  ## exact INTEGER comparisons, so a razor-thin margin can decide the WINNER
  ## on a difference that rounds away in POINTS. Stated explicitly, tested
  ## explicitly, and not a bug.
  let castles = [w.castlesAlive(tRed), w.castlesAlive(tBlue)]
  let health = [w.totalHealth(tRed), w.totalHealth(tBlue)]
  let worth = [w.worthOf(tRed), w.worthOf(tBlue)]
  for t in 0 .. 1:
    let o = 1 - t
    result[t] = int(64.0'f32 * share(castles[t], castles[o]) +
                    24.0'f32 * share(health[t], health[o]) +
                    12.0'f32 * share(worth[t], worth[o]))

# ---------------------------------------------------------------------------
#  One turn, one round
# ---------------------------------------------------------------------------

proc enactTurn*(w: World, sides: array[2, Side],
                chassis: array[2, ChassisKind19]) =
  ## Rule 2, in the engine's own order.
  if w.robin >= w.robots.len:
    w.robin = 0
    inc w.round
    w.addTrickle()
  if w.robots.len == 0: return
  let r = w.robots[w.robin]
  inc r.turn
  ## Rule 2.3 — V1: `robot.time += CHESS_EXTRA` becomes a credit of
  ## `ChessExtraOps`, and `processAction` charges exactly the same number
  ## back, so `chessOps` is INVARIANT and no robot is ever frozen.
  r.chessOps += ChessExtraOps
  r.opsLeft = TurnMaxOps
  r.opsUsed = 0
  var action = newAction()
  ## Rule 2.4 — a chassis exception is SWALLOWED and becomes "no action".
  try:
    action = runControllerFor(w, sides, chassis, r)
  except CatchableError:
    action = newAction()
  let t = ord(r.team)
  if r.opsUsed > w.stats.decisionOpsPeak[t]:
    w.stats.decisionOpsPeak[t] = r.opsUsed
  ## Rule 2.5 — a FRESH record, then the validation ladder.
  var rec = newRecord()
  try:
    w.processAction(r, action, rec)
  except CatchableError as e:
    w.stats.refusedActions[t] += 1
    when defined(bc19Debug):
      echo "REFUSE-validate r=", w.round, " ", unitName(r.unit), " ", e.msg
  if rec.action != akNothing and not w.firstActionSeen[t]:
    w.firstActionSeen[t] = true
    discard w.beat(BeatFirstAction, "first_action", t, ord(rec.action),
                   w.round)
  ## Telemetry for the parity trace: the flattened record, exactly as the
  ## engine's `ActionRecord` carries it, with `null` rendered the way the
  ## driver renders it.
  w.lastAction = ord(rec.action)
  w.lastDx = (if rec.action in {akMove, akAttack, akBuild, akGive}: rec.dx
              else: 0)
  w.lastDy = (if rec.action in {akMove, akAttack, akBuild, akGive}: rec.dy
              else: 0)
  w.lastBuildUnit = (if rec.action == akBuild: ord(rec.buildUnit) else: -1)
  w.lastGiveK = (if rec.action == akGive: rec.giveK else: 0)
  w.lastGiveF = (if rec.action == akGive: rec.giveF else: 0)
  w.lastTradeK = (if rec.action == akTrade: rec.tradeK else: 0)
  w.lastTradeF = (if rec.action == akTrade: rec.tradeF else: 0)
  ## Rule 2.6.
  try:
    w.enact(r, rec)
  except CatchableError as e:
    w.stats.refusedActions[t] += 1
    when defined(bc19Debug):
      echo "REFUSE-enact r=", w.round, " ", unitName(r.unit), " ", e.msg
    ## `enact` throws only from `enactMine` (off a depot) and `enactTrade`
    ## (an agreed deal that is not payable), and in both cases `robin` has
    ## already advanced, so the sweep is not disturbed.
  ## The depot-claim beat, derived from the sim rather than from the chassis
  ## so it fires for ANY chassis.
  if rec.action == akMine:
    let kind = (if w.hasKarbonite(r.x, r.y): "karbonite" else: "fuel")
    w.depotBeats[t] += 1
    if w.depotBeats[t] <= 6 or (w.depotBeats[t] mod 4) == 0:
      discard w.beat(BeatDepotClaimed, "depot_claimed", t,
                     r.x * 100 + r.y, w.depotBeats[t], kind)

proc foldRoundHash(w: World) =
  ## THIRTEEN per-team values plus NINE globals, so a re-derivation that
  ## diverged in only one of them cannot reproduce the chain (the GV02
  ## lesson). **Folding the MT19937 state is a bc19-specific decision and it
  ## is the cheapest possible tripwire for a missed or extra id draw
  ## (D1.2)** — which, given that the id stream is the only live randomness,
  ## is the single most likely way this port can desynchronise.
  for t in 0 .. 1:
    let team = Team(t)
    w.mixHash(w.castlesAlive(team))
    w.mixHash(w.churchesAlive(team))
    w.mixHash(w.unitCount(team, ukPilgrim))
    w.mixHash(w.unitCount(team, ukCrusader))
    w.mixHash(w.unitCount(team, ukProphet))
    w.mixHash(w.unitCount(team, ukPreacher))
    w.mixHash(w.totalHealth(team))
    w.mixHash(w.karbonite[t])
    w.mixHash(w.fuel[t])
    w.mixHash(w.stats.unitsBuilt[t])
    w.mixHash(w.stats.unitsLost[t])
    w.mixHash(w.stats.karboniteMined[t])
    w.mixHash(w.stats.fuelMined[t])
  w.mixHash(w.round)
  w.mixHash(w.robin)
  w.mixHashU(w.shadowChecksum())
  w.mixHashU(w.queueChecksum())
  w.mixHash(w.robots.len)
  w.mixHash(w.idsSpent.len)
  w.mixHash((w.lastOffer[0][0] + MaxTrade) * 1_000_000 +
            (w.lastOffer[0][1] + MaxTrade) * 1000 +
            (w.lastOffer[1][0] + MaxTrade))
  w.mixHashU(w.gen.stateFold())
  w.mixHash(w.gen.mti)

proc emitRoundBeats(w: World) =
  if w.lostThisRound[0] > 0 and w.lostThisRound[1] > 0:
    discard w.beat(BeatDuel, "duel", w.lostThisRound[0], w.lostThisRound[1])
  for t in 0 .. 1:
    if w.lostThisRound[t] >= 4:
      discard w.beat(BeatRout, "rout", t, w.lostThisRound[t])
    w.lostThisRound[t] = 0

proc runRound*(w: World, sides: array[2, Side],
               chassis: array[2, ChassisKind19]) =
  ## ONE ROUND: every turn from the state where `robin >= robots.len` through
  ## the last robot of the next round. The `isOver` check is INSIDE the loop
  ## and BEFORE every turn, which is what makes a castle annihilation stop
  ## the game mid-round and round `maxRounds` play exactly one turn.
  when not defined(bc19Scenario) and not defined(bc19Idle):
    for t in 0 .. 1:
      case chassis[t]
      of ck19Saber: beginRound(w, sides[t])
      of ck19Examplefuncsplayer19: discard
  var played = 0
  while w.running:
    if w.evaluateIsOver():
      w.running = false
      break
    w.enactTurn(sides, chassis)
    inc played
    if w.robots.len == 0: break
    if w.robin >= w.robots.len: break
  if played > 0:
    w.emitRoundBeats()
    for t in 0 .. 1:
      if w.karbonite[t] <= 0 and w.fuel[t] <= 0:
        inc w.stats.zeroStoreStreak[t]
        if w.stats.zeroStoreStreak[t] > w.stats.zeroStoreWorst[t]:
          w.stats.zeroStoreWorst[t] = w.stats.zeroStoreStreak[t]
      else:
        w.stats.zeroStoreStreak[t] = 0
      if w.fuel[t] <= 0: inc w.stats.roundsAtZeroFuel[t]
      if w.round == 500: w.stats.aliveAt500[t] = w.robotsOf(Team(t))
      if w.round == 700: w.stats.castlesAt700[t] = w.castlesAlive(Team(t))
    ## One sample per enemy unit that ended the round within r^2 100 of one
    ## of our castles -- the pressure `symmetry_wall` is asserted to relieve.
    ## Castles are collected first because there are at most six of them and
    ## up to a few hundred units, and this runs every round of every game.
    var castleAt: array[2, seq[Loc]]
    for r in w.robots:
      if r.unit == ukCastle: castleAt[ord(r.team)].add(Loc(x: r.x, y: r.y))
    for r in w.robots:
      if r.unit.isStructure: continue
      let foe = 1 - ord(r.team)
      for c in castleAt[foe]:
        if distSq(c.x, c.y, r.x, r.y) <= CastlePressureRadius:
          inc w.stats.enemyNearCastle[foe]
          break
    w.foldRoundHash()

# ---------------------------------------------------------------------------
#  One game
# ---------------------------------------------------------------------------

proc endReasonFor*(w: World): string =
  ## FAULT, never mislabel. `Bc19RungNone` is "no winner at all" and it is
  ## UNREACHABLE in the shipped configuration: `evaluateIsOver` fires at
  ## `round >= maxRounds` and always sets a rung, and the abandoned path
  ## returns before this proc is called. An impossible state that reports a
  ## plausible answer is the wrong failure mode.
  if w.endRung == Bc19RungNone:
    raise newException(Defect,
      "bc19: the game ended with no ladder rung at round " & $w.round &
      " of " & $w.maxRounds & ", hasWinner=" & $w.hasWinner &
      ". evaluateIsOver's seven-rung ladder cannot produce that while " &
      "maxRounds >= 1, so a rule has changed. Labelling it `" &
      endReasonName(Bc19RungCastlesDestroyed) & "` would hide the change.")
  endReasonName(w.endRung)

proc harvest(w: World, outcome: var GameOutcome19) =
  for team in [tRed, tBlue]:
    let t = ord(team)
    let slot = outcome.slotOf(team)
    template put(field, value: untyped) = outcome.field[slot] = value
    put(castlesStart, w.stats.castlesStart[t])
    put(castlesEnd, w.castlesAlive(team))
    put(castlesLost, w.stats.castlesLost[t])
    put(churchesBuilt, w.stats.churchesBuilt[t])
    put(churchesEnd, w.churchesAlive(team))
    put(churchesLost, w.stats.churchesLost[t])
    put(enemyHalfChurches, w.stats.enemyHalfChurches[t])
    put(unitHealthEnd, w.totalHealth(team))
    put(karboniteEnd, w.karbonite[t])
    put(fuelEnd, w.fuel[t])
    put(netWorthEnd, w.worthOf(team))
    put(karboniteMined, w.stats.karboniteMined[t])
    put(fuelMined, w.stats.fuelMined[t])
    put(karboniteSpent, w.stats.karboniteSpent[t])
    put(fuelSpent, w.stats.fuelSpent[t])
    put(fuelTrickled, w.stats.fuelTrickled[t])
    put(karboniteReclaimed, w.stats.karboniteReclaimed[t])
    put(fuelReclaimed, w.stats.fuelReclaimed[t])
    put(karboniteDeposited, w.stats.karboniteDeposited[t])
    put(fuelDeposited, w.stats.fuelDeposited[t])
    put(unitsBuilt, w.stats.unitsBuilt[t])
    put(pilgrimsBuilt, w.stats.pilgrimsBuilt[t])
    put(crusadersBuilt, w.stats.crusadersBuilt[t])
    put(prophetsBuilt, w.stats.prophetsBuilt[t])
    put(preachersBuilt, w.stats.preachersBuilt[t])
    put(unitsAlive, w.robotsOf(team))
    put(unitsLost, w.stats.unitsLost[t])
    put(mineActions, w.stats.mineActions[t])
    put(mineActionsWasted, w.stats.mineActionsWasted[t])
    put(giveActions, w.stats.giveActions[t])
    put(attacks, w.stats.attacks[t])
    put(damageDealt, w.stats.damageDealt[t])
    put(damageTaken, w.stats.damageTaken[t])
    put(friendlyFireDamage, w.stats.friendlyFireDamage[t])
    put(selfDamage, w.stats.selfDamage[t])
    put(splashKills, w.stats.splashKills[t])
    put(kills, w.stats.kills[t])
    put(robotsLost, w.stats.unitsLost[t])
    put(moves, w.stats.moves[t])
    put(moveFuelSpent, w.stats.moveFuelSpent[t])
    put(radioMessages, w.stats.radioMessages[t])
    put(radioFuelSpent, w.stats.radioFuelSpent[t])
    put(castleTalks, w.stats.castleTalks[t])
    put(tradesProposed, w.stats.tradesProposed[t])
    put(tradesExecuted, w.stats.tradesExecuted[t])
    put(tradeKarboniteNet, w.stats.tradeKarboniteNet[t])
    put(tradeFuelNet, w.stats.tradeFuelNet[t])
    put(latticeUnitsPlaced, w.stats.latticeUnitsPlaced[t])
    put(buildsRefused, w.stats.buildsRefused[t])
    put(refusedActions, w.stats.refusedActions[t])
    put(decisionOpsPeak, w.stats.decisionOpsPeak[t])
  outcome.castlesPerSide = w.map.castlesPerSide
  outcome.boardWidth = w.width
  outcome.passableSquares = w.map.passableSquares
  outcome.karboniteDepots = w.map.karboniteDepots
  outcome.fuelDepots = w.map.fuelDepots
  outcome.symmetryHorizontal = (if w.map.symmetryHorizontal: 1 else: 0)
  outcome.castleSeparationMin = w.map.separation(true)
  outcome.castleSeparationMax = w.map.separation(false)
  outcome.idsSpent = w.idsSpent.len
  outcome.winCondition = w.winCondition
  outcome.tiebreakRound = w.tiebreakRound
  outcome.queueLengthEnd = w.robots.len
  let pts = w.gamePoints()
  outcome.points[outcome.slotOf(tRed)] = pts[0]
  outcome.points[outcome.slotOf(tBlue)] = pts[1]
  outcome.roundsPlayed = w.round
  outcome.hashChain = toHex(w.hashChain)

proc playGame*(
  spec: MapSpec, sheets: array[2, Sheet], chassis: array[2, ChassisKind19],
  index, sideAslot, maxRounds: int, budgetSeconds: int,
  onRound: proc (w: World, round: int) {.closure.} = nil
): (World, GameOutcome19) =
  ## Plays one game to its end, or abandons it when `budgetSeconds` of
  ## monotonic wall clock elapse. An abandoned game is DISCARDED by the match
  ## (its `aborted` flag says so); it is never scored half-played.
  ##
  ## `budgetSeconds <= 0` means UNBOUNDED here. `match.nim:568` clamps
  ## `perGameBudgetSeconds` to `max(1, ...)` ONE LEVEL UP, so a test helper
  ## that zeroes that field buys a ONE-SECOND budget rather than an unbounded
  ## one — every bc19 test uses the `if perGame > 0:` convention instead.
  var w = newWorld(spec, maxRounds)
  var sides = newSides19(sheets, sideAslot)
  ## `sides` is indexed by TEAM and `chassis` arrives by SEAT — re-index once
  ## here so the round loop never has to.
  let chassisByTeam = [chassis[sideAslot], chassis[1 - sideAslot]]
  var outcome = GameOutcome19(
    index: index, mapName: spec.name, sideAslot: sideAslot, winnerSlot: -1)
  discard w.beat(BeatGameStart, "game_start", index, w.width,
                 w.map.castlesPerSide,
                 spec.name & ":" & $spec.mapSeed & ":" &
                   (if spec.symmetryHorizontal: "horizontal" else: "vertical") &
                   ":" & $spec.karboniteDepots & ":" & $spec.fuelDepots &
                   ":" & $(spec.separationMinMilli div 100))
  let started = getMonoTime()
  let budget = initDuration(seconds = budgetSeconds)
  while w.running:
    runRound(w, sides, chassisByTeam)
    outcome.roundChains.add(toHex(w.hashChain))
    if onRound != nil:
      onRound(w, w.round)
    if budgetSeconds > 0 and (w.round and 0x1F) == 0 and
        getMonoTime() - started >= budget:
      outcome.aborted = true
      break
  if outcome.aborted:
    outcome.endReason = "abandoned"
    harvest(w, outcome)
    outcome.winnerSlot = -1
    discard w.beat(BeatGameEnd, "game_abandoned", index, w.round, 0,
                   spec.name)
    return (w, outcome)
  outcome.endReason = w.endReasonFor()
  harvest(w, outcome)
  if w.hasWinner:
    outcome.winnerSlot = outcome.slotOf(w.winner)
  discard w.beat(BeatGameEnd, "game_end", index,
                 (if outcome.winnerSlot >= 0: outcome.winnerSlot else: -1),
                 outcome.points[0] * 1000 + outcome.points[1],
                 outcome.endReason & ":" & $outcome.castlesEnd[0] & ":" &
                   $outcome.castlesEnd[1] & ":" & $w.winCondition)
  (w, outcome)
