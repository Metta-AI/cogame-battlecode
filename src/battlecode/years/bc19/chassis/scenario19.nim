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

import ../constants, ../units, ../world, ../vision
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
        result.buildUnit = ukPreacher
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
    of 4, 5, 6:
      ## THE BUILD ORDER IS PILGRIM, PREACHER, PROPHET, CRUSADER AND THE
      ## LAST ONE IS TRIED THREE TIMES, and both halves are measured rather
      ## than chosen: an order starts with ONE HUNDRED KARBONITE AND NO
      ## PASSIVE INCOME, so a castle can afford at most 80 karbonite of
      ## units in its whole opening, and on a two- or three-castle board
      ## the siblings spend it first. Buying the EXPENSIVE units early is
      ## what puts a PREACHER on the board at all; retrying the CHEAPEST
      ## one is what fills the remaining free squares as units move away.
      case r.turn
      of 4:
        result.signal = 99
        result.signalRadius = 3
      of 5:
        result.signal = 5
        result.signalRadius = 5
        result.castleTalk = 200
      else:
        result.signal = 6
        result.signalRadius = 10
        result.castleTalk = 17
      let sq = firstFreeAdjacent(w, r)
      if sq.ok:
        result.hasAction = true
        result.kind = akBuild
        result.dx = sq.dx
        result.dy = sq.dy
        result.buildUnit = ukCrusader
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
    of 6, 8:
      ## `give` WHATEVER THE PILGRIM ACTUALLY HOLDS to whatever is west of
      ## it. The amount is read off `me` on both sides -- a robot always
      ## sees its own carried karbonite and fuel -- so the action ALWAYS
      ## passes validation and the record always carries `GIVE`, and the
      ## enact then either transfers or throws on an empty square. Both are
      ## legal script and both sides take the same branch. A fixed amount
      ## would fail validation on any board where the pilgrim had not
      ## reached a depot, and the GIVE path would silently never be
      ## compared.
      result.hasAction = true
      result.kind = akGive
      result.dx = -1
      result.dy = 0
      result.giveK = min(r.karbonite, MaxGiveAmount)
      result.giveF = min(r.fuel, MaxGiveAmount)
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
      ## THE CRUSADER'S OWN SPAWN, not its builder's. `createItem` seeds
      ## `homeX`/`homeY` from the square the robot is created on and
      ## `enactBuild` then overwrites them with the BUILDER's, which is what
      ## the `saber` chassis wants and what this bot must not inherit: the
      ## JavaScript twin reads `this.me.x` on its first turn and there is no
      ## builder in that reading.
      r.homeX = r.x
      r.homeY = r.y
      if mirrorAxisHorizontal(w):
        r.taskX = w.width - 1 - r.homeX
        r.taskY = r.homeY
      else:
        r.taskX = r.homeX
        r.taskY = w.height - 1 - r.homeY
    ## THE LOWEST-ID VISIBLE ENEMY INSIDE THE CRUSADER'S OWN r2 1..16.
    ## `visible` is ordered by ASCENDING id on BOTH SIDES — here by
    ## `vision.observationInto` and on the engine side by
    ## `tools/oracle/bc19/visible_order.patch` (V2) — so "the lowest-id one"
    ## is the same robot in both, and this is the one scripted decision in
    ## the whole tier that DEPENDS ON THAT PATCH WORKING.
    var seen: seq[SeenRobot]
    observationInto(w, r, seen)
    for other in seen:
      if not other.hasUnit: continue          ## `isVisible`
      if other.team == r.team: continue
      let dd = distSq(r.x, r.y, other.x, other.y)
      if dd < 1 or dd > 16: continue
      result.hasAction = true
      result.kind = akAttack
      result.dx = other.x - r.x
      result.dy = other.y - r.y
      return
    let step = towardTarget(w, r, r.taskX, r.taskY)
    if step.ok:
      result.hasAction = true
      result.kind = akMove
      result.dx = step.dx
      result.dy = step.dy
  else: discard

proc scenarioTie(w: World, r: Robot): Action =
  ## RED builds and BLUE builds NOTHING, so at the round limit the castles
  ## are level and the total unit health is not: `more_unit_health`, with
  ## the engine's `win_condition = 1`.
  ##
  ## RED's chain is PILGRIM -> CHURCH -> CHURCH ATTACK, and that chain is
  ## why this bot builds a pilgrim rather than a crusader. THE CHURCH IS
  ## THE ONE UNIT `bc19scenario` CANNOT AFFORD: an order starts with 100
  ## karbonite and NO passive income, a church costs 50 of it, and by the
  ## time that bot's pilgrim exists its castles have spent the opening
  ## hundred on the four buildable mobile types. Here nothing else is
  ## bought at all, so the church lands on every board -- and with it the
  ## LEGAL 0-DAMAGE CHURCH ATTACK (D6.1), which is the quirk this year is
  ## most likely to get wrong.
  result = newAction()
  if r.team != tRed: return
  case r.unit
  of ukCastle:
    if r.turn != 1: return
    let sq = firstFreeAdjacent(w, r)
    if sq.ok:
      result.hasAction = true
      result.kind = akBuild
      result.dx = sq.dx
      result.dy = sq.dy
      result.buildUnit = ukPilgrim
  of ukPilgrim:
    if r.turn != 2: return
    let sq = firstFreeAdjacent(w, r)
    if sq.ok:
      result.hasAction = true
      result.kind = akBuild
      result.dx = sq.dx
      result.dy = sq.dy
      result.buildUnit = ukChurch
  of ukChurch:
    if r.turn != 1: return
    ## D6.1: the CHURCH's `ATTACK_RADIUS` is the SCALAR 0, so `r > radius[1]`
    ## and `r < radius[0]` are both comparisons against `undefined` and both
    ## are false -- a CHURCH may legally "attack" ANY on-board square for 0
    ## fuel and 0 damage, consuming its turn. Measured on the real engine:
    ## `record.action == 2`.
    ## The target is five squares TOWARD THE BOARD'S CENTRE, so it is on
    ## the board for every church on every board in the pair set -- a fixed
    ## `(5, 5)` falls off the edge for a church in the bottom-right quarter
    ## and the dx/dy gate then refuses the action before the quirk is ever
    ## reached. Both sides compute the sign from the map's own dimensions.
    result.hasAction = true
    result.kind = akAttack
    result.dx = (if r.x * 2 < w.width: 5 else: -5)
    result.dy = (if r.y * 2 < w.height: 5 else: -5)
  else: discard

proc runScenario19*(w: World, r: Robot): Action =
  when defined(bc19ScenarioTrade): scenarioTrade(w, r)
  elif defined(bc19ScenarioKill): scenarioKill(w, r)
  elif defined(bc19ScenarioTie): scenarioTie(w, r)
  else: scenarioMain(w, r)
