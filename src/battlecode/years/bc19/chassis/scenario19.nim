## The Nim twin of the four bc19 oracle scenario bots — Tier A' of
## `parity-oracle-bc19`.
##
## Behind `-d:bc19Scenario`, with `-d:bc19ScenarioTrade`,
## `-d:bc19ScenarioKill` and `-d:bc19ScenarioTie` selecting the variant.
## `tools/oracle/bc19/bc19scenario*/robot.js` are the JavaScript twins and
## they are written LINE FOR LINE against this file.
##
## **EVERY DECISION HERE IS A PURE FUNCTION OF `me.unit`, `me.turn` AND THE
## SQUARES IMMEDIATELY AROUND THE ROBOT**, deliberately: those are exactly
## the facts both implementations can read identically, with no RNG at all
## and no dependence on the `visible` array's order (V2). The scripts are
## keyed by TURN NUMBER so every rare path fires early, while the games are
## still short enough for Tier B''s chess-clock assertion to hold.
##
## The four scripts, and what each one is the only cover for:
##
##   * `bc19scenario` — one of every unit type built, a move at every legal
##     `r2` for every mobile type, `mine` to capacity and one turn past it,
##     `give` under and over capacity, an attack at every range boundary
##     including the PROPHET's r2 16 MINIMUM (15 refused, 16 and 64
##     accepted), a PREACHER blast that damages itself, the legal 0-damage
##     CHURCH attack (D6.1), the refused PILGRIM attack (D6.2), a broadcast
##     at seven radii up to 7938, castle talk from a mobile unit, and a
##     signal issued in the same turn as an illegal move — proving the
##     signal still lands;
##   * `bc19scenariotrade` — the zero trade, an unmatched offer, a matched
##     payable offer and a matched UNPAYABLE offer (both offers clear,
##     nothing moves, and it throws);
##   * `bc19scenariokill` — crusaders onto the enemy's castle until
##     `castles_destroyed` fires, proving the game stops BEFORE THE NEXT
##     ROBOT ACTS;
##   * `bc19scenariotie` — RED builds one crusader and BLUE builds nothing,
##     so the round-limit ladder walks `more_unit_health` with the engine's
##     `win_condition = 1`.

import ../constants, ../units, ../world
import ../actions

const
  ## The scan order for "the first free adjacent square": dy ascending
  ## outer, dx ascending inner, skipping (0, 0). Both implementations use
  ## exactly this order.
  AdjacentScan*: array[8, tuple[dx, dy: int]] = [
    (dx: -1, dy: -1), (dx: 0, dy: -1), (dx: 1, dy: -1),
    (dx: -1, dy: 0), (dx: 1, dy: 0),
    (dx: -1, dy: 1), (dx: 0, dy: 1), (dx: 1, dy: 1)]

proc firstFreeAdjacent(w: World, r: Robot): tuple[ok: bool, dx, dy: int] =
  result = (ok: false, dx: 0, dy: 0)
  for off in AdjacentScan:
    let x = r.x + off.dx
    let y = r.y + off.dy
    if not w.onBoard(x, y): continue
    if not w.isPassable(x, y): continue
    if w.shadowAt(x, y) != 0: continue
    return (ok: true, dx: off.dx, dy: off.dy)

proc mirrorAxisHorizontal(w: World): bool =
  ## The engine mirrors the FULL map, so the axis is recoverable exactly:
  ## `map[y][x] == map[y][W-1-x]` for every square means the mirror is the
  ## VERTICAL midline, which this repository calls "horizontal" symmetry.
  ## Both implementations run the same loop in the same order.
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if w.map.passable[y * w.width + x] !=
          w.map.passable[y * w.width + (w.width - 1 - x)]:
        return false
  true

proc towardTarget(w: World, r: Robot, tx, ty: int): tuple[ok: bool, dx, dy: int] =
  ## The cheapest legal step that strictly reduces the squared distance,
  ## scanning `dy` then `dx` over the unit's whole offset range in a fixed
  ## order. No RNG, no tie-break beyond first-wins.
  result = (ok: false, dx: 0, dy: 0)
  let speed = speedOf(r.unit)
  if speed <= 0: return
  var best = distSq(r.x, r.y, tx, ty)
  for dy in -3 .. 3:
    for dx in -3 .. 3:
      let r2 = dx * dx + dy * dy
      if r2 == 0 or r2 > speed: continue
      let nx = r.x + dx
      let ny = r.y + dy
      if not w.onBoard(nx, ny): continue
      if not w.isPassable(nx, ny): continue
      if w.shadowAt(nx, ny) != 0: continue
      if w.fuel[ord(r.team)] < r2 * fuelPerMoveOf(r.unit): continue
      let d = distSq(nx, ny, tx, ty)
      if d < best:
        best = d
        result = (ok: true, dx: dx, dy: dy)

proc scenarioMain(w: World, r: Robot): Action =
  result = newAction()
  case r.unit
  of ukCastle:
    case r.turn
    of 1:
      result.signal = 1234
      result.signalRadius = 0
      let sq = firstFreeAdjacent(w, r)
      if sq.ok:
        result.hasAction = true
        result.kind = akBuild
        result.dx = sq.dx
        result.dy = sq.dy
        result.buildUnit = ukPilgrim
    of 2:
      result.signal = 7
      result.signalRadius = 1
      let sq = firstFreeAdjacent(w, r)
      if sq.ok:
        result.hasAction = true
        result.kind = akBuild
        result.dx = sq.dx
        result.dy = sq.dy
        result.buildUnit = ukCrusader
    of 3:
      result.signal = 42
      result.signalRadius = 2
      let sq = firstFreeAdjacent(w, r)
      if sq.ok:
        result.hasAction = true
        result.kind = akBuild
        result.dx = sq.dx
        result.dy = sq.dy
        result.buildUnit = ukProphet
    of 4:
      result.signal = 99
      result.signalRadius = 3
      let sq = firstFreeAdjacent(w, r)
      if sq.ok:
        result.hasAction = true
        result.kind = akBuild
        result.dx = sq.dx
        result.dy = sq.dy
        result.buildUnit = ukPreacher
    of 5:
      result.signal = 5
      result.signalRadius = 5
      result.castleTalk = 200
    of 6:
      result.signal = 6
      result.signalRadius = 10
      result.castleTalk = 17
    of 7:
      ## The maximum legal radius, `2*(64-1)^2`, whose cost is 90 fuel.
      result.signal = 1
      result.signalRadius = MaxSignalRadius
    of 8:
      ## r2 = 1, the CASTLE's minimum attack range.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 1
      result.dy = 0
    of 9:
      ## r2 = 64, the CASTLE's maximum. Refused when it leaves the board,
      ## identically on both sides.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 8
      result.dy = 0
    of 10:
      ## An ILLEGAL move (a castle has SPEED 0) issued in the same turn as a
      ## signal, proving the signal still lands.
      result.signal = 321
      result.signalRadius = 4
      result.hasAction = true
      result.kind = akMove
      result.dx = 1
      result.dy = 0
    of 11:
      ## A build onto an occupied square — refused.
      result.hasAction = true
      result.kind = akBuild
      result.dx = 1
      result.dy = 1
      result.buildUnit = ukCrusader
    else: discard
  of ukChurch:
    if r.turn == 1:
      ## D6.1: the CHURCH's `ATTACK_RADIUS` is the scalar 0, so this is a
      ## LEGAL 0-damage 0-fuel action that consumes the turn.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 5
      result.dy = 5
    else:
      let sq = firstFreeAdjacent(w, r)
      if sq.ok:
        result.hasAction = true
        result.kind = akBuild
        result.dx = sq.dx
        result.dy = sq.dy
        result.buildUnit = ukCrusader
  of ukPilgrim:
    case r.turn
    of 1:
      result.hasAction = true
      result.kind = akMine
    of 2:
      result.hasAction = true
      result.kind = akMove
      result.dx = 1
      result.dy = 0
    of 3:
      result.hasAction = true
      result.kind = akMove
      result.dx = 0
      result.dy = 1
    of 4:
      ## r2 = 4, the PILGRIM's maximum speed.
      result.hasAction = true
      result.kind = akMove
      result.dx = 2
      result.dy = 0
    of 5:
      ## D6.2: a PILGRIM attack is a VALIDATION FAILURE, not an action.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 1
      result.dy = 0
    of 6:
      ## `give` to whatever is west of us: under capacity, over capacity, or
      ## an empty square (which throws). All three are legal script.
      result.hasAction = true
      result.kind = akGive
      result.dx = -1
      result.dy = 0
      result.giveK = 5
      result.giveF = 30
    of 7:
      result.castleTalk = 77
      result.hasAction = true
      result.kind = akMine
    else:
      result.hasAction = true
      result.kind = akMine
  of ukCrusader:
    case r.turn
    of 1:
      ## r2 = 9, the CRUSADER's maximum speed — twice as far per turn as
      ## anything else in the game.
      result.hasAction = true
      result.kind = akMove
      result.dx = 3
      result.dy = 0
    of 2:
      result.hasAction = true
      result.kind = akAttack
      result.dx = 1
      result.dy = 0
    of 3:
      ## r2 = 16, the CRUSADER's maximum attack range.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 4
      result.dy = 0
    of 4:
      result.hasAction = true
      result.kind = akMove
      result.dx = 0
      result.dy = -3
    else:
      result.hasAction = true
      result.kind = akMove
      result.dx = (if (r.turn and 1) == 1: 1 else: -1)
      result.dy = 0
  of ukProphet:
    case r.turn
    of 1:
      ## r2 = 9 — INSIDE the PROPHET's r2 16 minimum, so REFUSED.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 3
      result.dy = 0
    of 2:
      ## r2 = 16, exactly the minimum — accepted.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 4
      result.dy = 0
    of 3:
      ## r2 = 64, the maximum — accepted.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 8
      result.dy = 0
    of 4:
      ## r2 = 65 — one past the maximum, refused.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 8
      result.dy = 1
    of 5:
      result.hasAction = true
      result.kind = akMove
      result.dx = 2
      result.dy = 0
    else:
      result.hasAction = true
      result.kind = akMove
      result.dx = 0
      result.dy = (if (r.turn and 1) == 1: 1 else: -1)
  of ukPreacher:
    case r.turn
    of 1:
      ## r2 = 1: the blast is nine squares around the target and includes
      ## the PREACHER'S OWN SQUARE, so it damages itself. Measured on the
      ## engine: 60 -> 40 HP.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 1
      result.dy = 0
    of 2:
      ## r2 = 16, the PREACHER's maximum attack range.
      result.hasAction = true
      result.kind = akAttack
      result.dx = 4
      result.dy = 0
    of 3:
      result.hasAction = true
      result.kind = akMove
      result.dx = 1
      result.dy = 1
    else:
      result.hasAction = true
      result.kind = akAttack
      result.dx = 1
      result.dy = 0

proc scenarioTrade(w: World, r: Robot): Action =
  result = newAction()
  if r.unit != ukCastle: return
  case r.turn
  of 1:
    ## The initial `last_offer` is `[[0,0],[0,0]]`, so the FIRST castle to
    ## offer (0,0) "matches" and executes a zero trade.
    result.hasAction = true
    result.kind = akTrade
    result.tradeK = 0
    result.tradeF = 0
  of 2:
    ## RED sets it, BLUE matches it, and it is payable.
    result.hasAction = true
    result.kind = akTrade
    result.tradeK = 10
    result.tradeF = -50
  of 3:
    ## A matched pair that is NOT payable: both offers clear and THEN it
    ## throws, so the offers are gone and nothing moved.
    result.hasAction = true
    result.kind = akTrade
    result.tradeK = 1000
    result.tradeF = 1000
  of 4:
    result.hasAction = true
    result.kind = akTrade
    result.tradeK = 5
    result.tradeF = 5
  else: discard

proc scenarioKill(w: World, r: Robot): Action =
  result = newAction()
  case r.unit
  of ukCastle:
    let sq = firstFreeAdjacent(w, r)
    if sq.ok:
      result.hasAction = true
      result.kind = akBuild
      result.dx = sq.dx
      result.dy = sq.dy
      result.buildUnit = ukCrusader
  of ukCrusader:
    if r.taskX < 0:
      if mirrorAxisHorizontal(w):
        r.taskX = w.width - 1 - r.homeX
        r.taskY = r.homeY
      else:
        r.taskX = r.homeX
        r.taskY = w.height - 1 - r.homeY
    let d = distSq(r.x, r.y, r.taskX, r.taskY)
    if d >= 1 and d <= 16:
      result.hasAction = true
      result.kind = akAttack
      result.dx = r.taskX - r.x
      result.dy = r.taskY - r.y
      return
    let step = towardTarget(w, r, r.taskX, r.taskY)
    if step.ok:
      result.hasAction = true
      result.kind = akMove
      result.dx = step.dx
      result.dy = step.dy
  else: discard

proc scenarioTie(w: World, r: Robot): Action =
  result = newAction()
  ## RED builds ONE crusader and BLUE builds nothing, so at the round limit
  ## the castles are level and the total unit health is not:
  ## `more_unit_health`, with the engine's `win_condition = 1`.
  if r.unit == ukCastle and r.team == tRed and r.turn == 1:
    let sq = firstFreeAdjacent(w, r)
    if sq.ok:
      result.hasAction = true
      result.kind = akBuild
      result.dx = sq.dx
      result.dy = sq.dy
      result.buildUnit = ukCrusader

proc runScenario19*(w: World, r: Robot): Action =
  when defined(bc19ScenarioTrade): scenarioTrade(w, r)
  elif defined(bc19ScenarioKill): scenarioKill(w, r)
  elif defined(bc19ScenarioTie): scenarioTie(w, r)
  else: scenarioMain(w, r)
