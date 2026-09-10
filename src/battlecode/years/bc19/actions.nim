## `processAction`'s validation ladder (rule 4) and `ActionRecord.enact`'s
## dispatch (rule 6), in ONE file because the two halves have to stay in the
## engine's own order and the `temp_fuel` handoff between them is the easiest
## thing in this year to get wrong.
##
## Ported from `coldbrew/game.js:804-930` and
## `coldbrew/action_record.js:319-339` at the pinned commit.
##
## **EVERY "throw" BELOW ABORTS THE REST OF VALIDATION AND LEAVES THE RECORD
## AS IT STANDS.** `enactTurn` catches it (`game.js:777-779`) and then enacts
## the record anyway, so an illegal `move` STILL PERFORMS the signal and the
## castle talk that were validated before it. That is a rule, not an
## accident, and `tests/test_bc19_actions.nim` asserts it.
##
## **`temp_fuel` IS NOT THE TEAM'S FUEL.** The signal step computes
## `temp_fuel = fuel - ceil(sqrt(radius))` (`:837`) and EVERY LATER
## AFFORDABILITY TEST IN THE TURN READS `temp_fuel`, not `this.fuel` — while
## the BUILD's karbonite test reads the real `karbonite[team]`. Reproducing
## that asymmetry is the difference between a bit-exact port and a plausible
## one.

import ../../sim_types
import constants, units, world, resources

export world, resources

type
  Action* = object
    ## What a chassis returns for one turn. The engine receives a JavaScript
    ## object; the starter library (`coldbrew/starter/js_starter.js:36-40`)
    ## ALWAYS attaches `signal`, `signal_radius` and `castle_talk`, so
    ## `'signal' in action` and `'castle_talk' in action` are true on every
    ## turn of every bot that inherits it — which is why the two flags below
    ## default to `true` with a value of 0.
    hasSignal*: bool
    signal*, signalRadius*: int
    hasCastleTalk*: bool
    castleTalk*: int
    hasAction*: bool
    kind*: ActionKind
    dx*, dy*: int
    buildUnit*: UnitKind
    giveK*, giveF*: int
    tradeK*, tradeF*: int

  ActionRecord* = object
    ## `coldbrew/action_record.js:3-19`, every field at its documented start
    ## value. A FRESH record is built for every turn.
    signal*, signalRadius*, castleTalk*: int
    action*: ActionKind
    dx*, dy*: int
    buildUnit*: UnitKind
    giveK*, giveF*: int
    tradeK*, tradeF*: int

func newAction*(): Action =
  Action(hasSignal: true, signal: 0, signalRadius: 0,
         hasCastleTalk: true, castleTalk: 0, hasAction: false,
         kind: akNothing, dx: 0, dy: 0, buildUnit: ukCastle,
         giveK: 0, giveF: 0, tradeK: 0, tradeF: 0)

func newRecord*(): ActionRecord =
  ActionRecord(signal: 0, signalRadius: 0, castleTalk: 0, action: akNothing,
               dx: 0, dy: 0, buildUnit: ukCastle, giveK: 0, giveF: 0,
               tradeK: 0, tradeF: 0)

func moveAction*(dx, dy: int): Action =
  result = newAction()
  result.hasAction = true
  result.kind = akMove
  result.dx = dx
  result.dy = dy

func attackAction*(dx, dy: int): Action =
  result = newAction()
  result.hasAction = true
  result.kind = akAttack
  result.dx = dx
  result.dy = dy

func buildAction*(dx, dy: int, unit: UnitKind): Action =
  result = newAction()
  result.hasAction = true
  result.kind = akBuild
  result.dx = dx
  result.dy = dy
  result.buildUnit = unit

func mineAction*(): Action =
  result = newAction()
  result.hasAction = true
  result.kind = akMine

func giveAction*(dx, dy, k, f: int): Action =
  result = newAction()
  result.hasAction = true
  result.kind = akGive
  result.dx = dx
  result.dy = dy
  result.giveK = k
  result.giveF = f

func tradeAction*(k, f: int): Action =
  result = newAction()
  result.hasAction = true
  result.kind = akTrade
  result.tradeK = k
  result.tradeF = f

# ---------------------------------------------------------------------------
#  Rule 4 — validation, in the engine's own order
# ---------------------------------------------------------------------------

proc processAction*(w: World, r: Robot, a: Action, rec: var ActionRecord) =
  ## `game.js:804-930`. Raises `BattlecodeError` exactly where the engine
  ## throws; the caller swallows it and enacts whatever the record already
  ## holds.
  ##
  ## Step 1 — `robot.time -= elapsed; if (robot.time < 0 || hook === null ||
  ## !initialized) throw` — is V1: the charge is the EXACT CONSTANT
  ## `TurnChargeOps`, which equals the refill, so `chessOps` is invariant at
  ## `ChessInitialOps` and the freeze branch is provably unreachable. Every
  ## robot in this port has a chassis at creation, so `hook` is never null and
  ## `initialized` is always true (V6).
  r.chessOps -= TurnChargeOps
  if r.chessOps < 0:
    raise newException(BattlecodeError,
      "Robot is frozen due to clock overdrawn by " & $(-r.chessOps) & " ops.")

  let t = ord(r.team)
  var tempFuel = w.fuel[t]

  ## Rule 4.4 — the signal, BEFORE the action.
  if a.hasSignal:
    if a.signal >= 0 and a.signal < (1 shl CommunicationBits) and
        a.signalRadius >= 0 and a.signalRadius <= MaxSignalRadius:
      let cost = signalCost(a.signalRadius)
      if w.fuel[t] >= cost:
        tempFuel -= cost
        rec.signal = a.signal
        rec.signalRadius = a.signalRadius
      else:
        if w.fuel[t] <= 0: w.noteFamine(r.team, 1)
        raise newException(BattlecodeError,
          "Insufficient fuel to signal given radius.")
    else:
      raise newException(BattlecodeError, "Invalid signal message.")

  ## Rule 4.5 — castle talk. FREE, and available to every unit.
  if a.hasCastleTalk:
    if a.castleTalk >= 0 and a.castleTalk < (1 shl CastleTalkBits):
      rec.castleTalk = a.castleTalk
    else:
      raise newException(BattlecodeError, "Invalid castle talk.")

  ## Rule 4.6 — a signal-only or castle-talk-only turn is legal and complete.
  if not a.hasAction: return

  ## Rule 4.8 — `trade` returns BEFORE the `dx`/`dy` gate.
  if a.kind == akTrade:
    if r.unit != ukCastle:
      raise newException(BattlecodeError, "Only Castles can trade.")
    if abs(a.tradeF) < MaxTrade and abs(a.tradeK) < MaxTrade:
      rec.action = akTrade
      rec.tradeK = a.tradeK
      rec.tradeF = a.tradeF
    else:
      raise newException(BattlecodeError,
        "Must provide valid fuel and karbonite offers.")
    return

  ## Rule 4.9 — `mine` returns BEFORE the `dx`/`dy` gate too, and the engine
  ## does NOT check here that the pilgrim is on a depot, nor that it is under
  ## capacity: both are decided at enact time.
  if a.kind == akMine:
    if r.unit != ukPilgrim:
      raise newException(BattlecodeError, "Only Pilgrims can mine.")
    if tempFuel - MineFuelCost < 0:
      if w.fuel[t] <= 0: w.noteFamine(r.team, 1)
      raise newException(BattlecodeError, "Not enough fuel to mine.")
    rec.action = akMine
    return

  ## Rule 4.10 — the `dx`/`dy` gate for the remaining three.
  if (a.dx == 0 and a.dy == 0) or abs(a.dx) >= MaxBoardSize or
      abs(a.dy) >= MaxBoardSize or
      not w.onBoard(r.x + a.dx, r.y + a.dy):
    raise newException(BattlecodeError,
      "Require a valid, onboard, nonzero dx and dy for given action.")

  case a.kind
  of akBuild:
    ## Rule 4.11, in the engine's own order.
    if not w.isPassable(r.x + a.dx, r.y + a.dy):
      raise newException(BattlecodeError, "Cannot build on impassable tile.")
    if not canBuildAtAll(r.unit):
      raise newException(BattlecodeError,
        "Only pilgrims, castles and churches can build.")
    if abs(a.dx) > 1 or abs(a.dy) > 1:
      raise newException(BattlecodeError,
        "Can only build on adjacent squares.")
    if not buildPairLegal(r.unit, a.buildUnit):
      raise newException(BattlecodeError,
        "Illegal builder/unit pair for build.")
    if w.shadowAt(r.x + a.dx, r.y + a.dy) != 0:
      raise newException(BattlecodeError,
        "Attempted to build on occupied tile.")
    if w.karbonite[t] < buildKarboniteOf(a.buildUnit) or
        tempFuel < buildFuelOf(a.buildUnit):
      if w.karbonite[t] <= 0: w.noteFamine(r.team, 0)
      if w.fuel[t] <= 0: w.noteFamine(r.team, 1)
      raise newException(BattlecodeError,
        "Cannot afford to build specified unit.")
    ## V4 — the ONE guard the engine lacks. `createItem`'s rejection loop
    ## never terminates once all 4 095 ids are spent, so a build that would
    ## reach it is REFUSED instead of looped.
    if w.idPoolExhausted():
      w.stats.buildsRefused[t] += 1
      raise newException(BattlecodeError,
        "Id pool exhausted; build refused (V4).")
    rec.action = akBuild
    rec.dx = a.dx
    rec.dy = a.dy
    rec.buildUnit = a.buildUnit
  of akGive:
    ## Rule 4.12. The engine tests the TERRAIN of the destination even though
    ## only an occupied square can receive, and there is NO TEAM CHECK.
    if not w.isPassable(r.x + a.dx, r.y + a.dy):
      raise newException(BattlecodeError, "Cannot give to impassable tile.")
    if abs(a.dx) > 1 or abs(a.dy) > 1:
      raise newException(BattlecodeError, "Can only give to adjacent squares.")
    if a.giveK < 0 or a.giveF < 0 or a.giveF > MaxGiveAmount or
        a.giveK > MaxGiveAmount:
      raise newException(BattlecodeError, "Invalid karbonite and fuel to give.")
    if r.karbonite < a.giveK or r.fuel < a.giveF:
      raise newException(BattlecodeError, "Tried to give more than you have.")
    rec.action = akGive
    rec.dx = a.dx
    rec.dy = a.dy
    rec.giveK = a.giveK
    rec.giveF = a.giveF
  of akMove:
    ## Rule 4.13. THERE IS NO PATH CHECK: a unit teleports over rock and over
    ## other units within its speed.
    if not w.isPassable(r.x + a.dx, r.y + a.dy):
      raise newException(BattlecodeError, "Cannot move to impassable tile.")
    let r2 = a.dx * a.dx + a.dy * a.dy
    if r2 > speedOf(r.unit):
      raise newException(BattlecodeError,
        "Slow down, cowboy.  Tried to move faster than unit can.")
    if w.shadowAt(r.x + a.dx, r.y + a.dy) > 0:
      raise newException(BattlecodeError, "Cannot move into occupied square.")
    if tempFuel < r2 * fuelPerMoveOf(r.unit):
      if w.fuel[t] <= 0: w.noteFamine(r.team, 1)
      raise newException(BattlecodeError,
        "Not enough fuel to move at given speed.")
    rec.action = akMove
    rec.dx = a.dx
    rec.dy = a.dy
  of akAttack:
    ## Rule 4.14. NO vision test, NO team check, NO target-exists test, and no
    ## on-the-map test beyond step 10. D6.1 makes a CHURCH attack legal and
    ## D6.2 makes a PILGRIM attack a validation FAILURE.
    if attackThrows(r.unit):
      raise newException(BattlecodeError,
        "Cannot read properties of null (reading '1')")
    let r2 = a.dx * a.dx + a.dy * a.dy
    if not attackRangeOk(r.unit, r2):
      raise newException(BattlecodeError,
        "Cannot attack outside of attack range.")
    if tempFuel < attackFuelOf(r.unit):
      if w.fuel[t] <= 0: w.noteFamine(r.team, 1)
      raise newException(BattlecodeError, "Not enough fuel to attack.")
    rec.action = akAttack
    rec.dx = a.dx
    rec.dy = a.dy
  else:
    raise newException(BattlecodeError,
      "Action must be move, attack, build, mine, trade, or give.")

# ---------------------------------------------------------------------------
#  Rule 6 — enact, in exactly the engine's order
# ---------------------------------------------------------------------------

proc enactMove(w: World, r: Robot, rec: ActionRecord) =
  ## `action_record.js:279-287`: charge the fuel, write the shadow at the
  ## destination, clear it at the origin, THEN move the robot. In that order,
  ## because a move onto your own square is impossible (rule 4.10).
  let r2 = rec.dx * rec.dx + rec.dy * rec.dy
  let cost = r2 * fuelPerMoveOf(r.unit)
  w.spendFuel(r.team, cost)
  w.stats.moveFuelSpent[ord(r.team)] += cost
  w.stats.moves[ord(r.team)] += 1
  w.setShadow(r.x + rec.dx, r.y + rec.dy, r.id)
  w.setShadow(r.x, r.y, 0)
  r.y = r.y + rec.dy
  r.x = r.x + rec.dx

proc enactAttack(w: World, r: Robot, rec: ActionRecord) =
  ## `action_record.js:289-317`. The engine sweeps the WHOLE BOARD, r (y)
  ## ascending outer and c (x) ascending inner; the port sweeps only the
  ## squares with `rad <= DAMAGE_SPREAD` IN THE SAME ORDER, which is provably
  ## the same set (`dx^2 + dy^2 = 3` has no integer solution, so a spread of
  ## 3 is exactly the nine squares of the 3x3 box).
  ##
  ## The order is load-bearing: multiple kills in one blast credit the reclaim
  ## in that order and the attacker's capacity clamps at 20 karbonite /
  ## 100 fuel, so the order decides what is collected and what is lost.
  ## Measured on the 9x9 probe: the (5,4) kill was processed before the (5,5)
  ## kill and the reclaim came out 14 karbonite / 33 fuel.
  let t = ord(r.team)
  let cost = attackFuelOf(r.unit)
  w.spendFuel(r.team, cost)
  w.stats.attacks[t] += 1
  let spread = damageSpreadOf(r.unit)
  let damage = attackDamageOf(r.unit)
  let tx = r.x + rec.dx
  let ty = r.y + rec.dy
  var box = 0
  while (box + 1) * (box + 1) <= spread: inc box
  var enemyKilled = 0
  var friendlyKilled = 0
  var selfDamage = 0
  for y in max(0, ty - box) .. min(w.height - 1, ty + box):
    for x in max(0, tx - box) .. min(w.width - 1, tx + box):
      let rad = distSq(tx, ty, x, y)
      if rad > spread: continue
      let target = w.robotAt(x, y)
      if target.isNil: continue
      let radToAttacker = distSq(r.x, r.y, x, y)
      target.health -= damage
      w.stats.damageTaken[ord(target.team)] += damage
      if target.id == r.id:
        w.stats.selfDamage[t] += damage
        selfDamage += damage
      elif target.team == r.team:
        w.stats.friendlyFireDamage[t] += damage
      else:
        w.stats.damageDealt[t] += damage
      if target.health <= 0:
        if target.unit == ukCastle:
          w.noteCastleLoss(target, unitName(r.unit))
        elif target.unit == ukChurch:
          w.noteChurchLoss(target)
        w.reclaimFrom(r, target, radToAttacker)
        w.stats.unitsLost[ord(target.team)] += 1
        w.lostThisRound[ord(target.team)] += 1
        if target.team == r.team:
          inc friendlyKilled
        else:
          inc enemyKilled
          w.stats.kills[t] += 1
          if r.unit == ukPreacher: w.stats.splashKills[t] += 1
          if target.unit == ukPilgrim:
            w.stats.ownPilgrimsKilled[ord(target.team)] += 1
        w.deleteRobot(target)
  if r.unit == ukPreacher and (enemyKilled > 0 or friendlyKilled > 0):
    w.splashBeats[t] += 1
    if w.splashBeats[t] == 1 or (w.splashBeats[t] mod 8) == 0:
      discard w.beat(BeatPreacherSplash, "preacher_splash", t,
                     enemyKilled * 100 + friendlyKilled, selfDamage,
                     $tx & ":" & $ty)

proc enactBuild(w: World, r: Robot, rec: ActionRecord) =
  ## `action_record.js:249-254`: karbonite, then fuel, then `createItem`.
  let t = ord(r.team)
  w.spendKarbonite(r.team, buildKarboniteOf(rec.buildUnit))
  w.spendFuel(r.team, buildFuelOf(rec.buildUnit))
  let built = w.createItem(r.x + rec.dx, r.y + rec.dy, r.team, rec.buildUnit)
  built.homeX = r.homeX
  built.homeY = r.homeY
  w.stats.unitsBuilt[t] += 1
  case rec.buildUnit
  of ukPilgrim: w.stats.pilgrimsBuilt[t] += 1
  of ukCrusader: w.stats.crusadersBuilt[t] += 1
  of ukProphet:
    w.stats.prophetsBuilt[t] += 1
  of ukPreacher:
    w.stats.preachersBuilt[t] += 1
    if w.round <= 200: w.stats.preachersBy200[t] += 1
  of ukChurch:
    w.stats.churchesBuilt[t] += 1
    let enemyHalf = w.inEnemyHalf(r.team, built.x, built.y)
    if enemyHalf: w.stats.enemyHalfChurches[t] += 1
    discard w.beat(BeatChurchBuilt, "church_built", t,
                   built.x * 100 + built.y,
                   w.churchesAlive(r.team),
                   (if enemyHalf: "1" else: "0"))
  else: discard
  if rec.buildUnit != ukChurch and not w.unitMilestoneSeen[t][rec.buildUnit]:
    w.unitMilestoneSeen[t][rec.buildUnit] = true
    discard w.beat(BeatUnitMilestone, "unit_milestone", t,
                   ord(rec.buildUnit), w.unitCount(r.team, rec.buildUnit))

proc enact*(w: World, r: Robot, rec: ActionRecord) =
  ## `action_record.js:319-339`, in exactly this order. `robin += 1` FIRST,
  ## which is why `_deleteRobot`'s `robin--` lands correctly even when the
  ## acting robot kills itself.
  if w.robin != high(int): inc w.robin
  r.signal = rec.signal
  r.signalRadius = rec.signalRadius
  r.castleTalk = rec.castleTalk
  ## All three default to 0, so a robot that broadcasts nothing this turn
  ## SILENTLY CLEARS last turn's broadcast: a signal is audible from the end
  ## of the sender's turn until the end of its next turn.
  let cost = signalCost(rec.signalRadius)
  w.spendFuel(r.team, cost)
  if rec.signalRadius > 0:
    w.stats.radioMessages[ord(r.team)] += 1
    w.stats.radioFuelSpent[ord(r.team)] += cost
  if rec.castleTalk != 0:
    w.stats.castleTalks[ord(r.team)] += 1
  case rec.action
  of akMove: enactMove(w, r, rec)
  of akAttack: enactAttack(w, r, rec)
  of akBuild: enactBuild(w, r, rec)
  of akMine: w.enactMine(r)
  of akTrade: w.enactTrade(r, rec.tradeK, rec.tradeF)
  of akGive: w.enactGive(r, rec.dx, rec.dy, rec.giveK, rec.giveF)
  else: discard
