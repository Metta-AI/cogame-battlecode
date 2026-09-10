## The Battlecode 2019 "Crusade" world: state, the turn queue, the occupancy
## shadow, the id pool and every counter the score, the endcard and the parity
## trace read.
##
## A behaviour port of `coldbrew/game.js` (947 lines) at commit
## `80cf1cc535ec5a30559274aa1b49807ad4859925`. The port is the authority at
## run time; the JavaScript engine survives only as the `parity-oracle-bc19`
## CI job (`docs/PARITY.md` §bc19).
##
## **SIX THINGS IN HERE LOOK LIKE DETAILS AND ARE NOT:**
##
## * **The turn queue is a plain ARRAY and that is all it is.** `this.robots`
##   (`game.js:33`) is a JavaScript array, `robin` (`:41`) an index into it,
##   `createItem` APPENDS (`:461`) and `_deleteRobot` SPLICES and decrements
##   `robin` when the removed index is below it (`:939-942`). It is the only
##   robot collection the engine iterates — `isOver` (`:551`), `getItem`'s
##   linear scan (`:478`) and `getGameStateDump` (`:672`) all read it. THERE
##   IS NO HASH MAP, NO SET, NO SORT AND NO PRIORITY QUEUE ANYWHERE IN THE
##   ROUND LOOP (D2), so this file keeps one `seq[Robot]` with append-on-create
##   and by-value removal, plus an `id -> index` `Table` that is NEVER
##   ITERATED and is rebuilt on removal.
## * **A unit built in a round DOES take a turn in the same round**, because
##   the new robot is appended behind `robin`. Measured on `seed-0043`:
##   999 x 7 + 1 = 6 994 turns.
## * **`robin` starts at `Infinity`** (`:41`) and `round` at `0` (`:40`), so
##   the FIRST PLAYED ROUND IS ROUND 1 and the flat 25-fuel trickle lands
##   BEFORE the round's first robot acts.
## * **The id pool is drawn from 1 … 4095 without replacement and is NEVER
##   REFILLED** (`:433-435`). That rejection loop is the ONE live MT19937 draw
##   site in the whole round loop (D1.2) and it HANGS FOREVER at exhaustion —
##   so this port reproduces the loop exactly and adds ONE guard the engine
##   lacks (V4): at `ids.len >= MAX_ID - 1` a build is REFUSED rather than
##   looped. Degrade, never hang.
## * **`createItem` writes the shadow ONLY IF the square reads 0** (`:460`),
##   and `_deleteRobot` clears the square unconditionally (`:934`).
## * **An attack has no team check and no attacker exclusion**, so a PREACHER
##   firing at anything closer than r2 4 damages ITSELF (measured: 60 -> 40 HP)
##   and every friendly beside it.

import std/[strutils, tables]
import ../../sim_types
import constants, units, mt19937

export constants, units, mt19937, tables

type
  MapSpec* = object
    ## One committed board from `data/maps/bc19/<name>.json`. bc19 ships no
    ## map files upstream: every board is procedurally generated from its seed
    ## inside the engine constructor (`game.js:63,76-361`), so the NAME IS THE
    ## RECIPE and `tools/gen_maps_bc19.mjs` runs the pinned engine under the
    ## pinned Node at BUILD time (V3).
    name*: string
    mapSeed*: int
    width*, height*: int
    symmetryHorizontal*: bool
      ## `true` when the engine's `transpose` was true, i.e. the board is
      ## mirrored across the VERTICAL midline (`x -> width-1-x`).
    passable*: seq[bool]        ## `y * width + x`
    karboniteMap*: seq[bool]
    fuelMap*: seq[bool]
    castles*: seq[tuple[x, y, team: int]]
      ## IN `to_create` ORDER, which is the opening queue order and therefore
      ## the order the castles' ids are drawn in.
    mtWords*: seq[uint32]       ## the 624-word MT19937 state ...
    mtMti*: int                 ## ... and `mti`, IMMEDIATELY AFTER `makeMap`
    passableSquares*: int
    karboniteDepots*: int
    fuelDepots*: int
    castlesPerSide*: int
    separationMinMilli*: int
    separationMaxMilli*: int

  Robot* = ref object
    ## `createItem`'s record (`game.js:437-457`), minus the four fields the
    ## observation always deletes and minus `time` (V7 — wall-clock derived,
    ## so exposing it would make a prompt and a trace non-reproducible).
    id*: int
    team*: Team
    unit*: UnitKind
    x*, y*: int
    health*: int
    karbonite*: int
    fuel*: int
    turn*: int
    signal*: int
    signalRadius*: int
    castleTalk*: int
    chessOps*: int              ## V1: invariant at `ChessInitialOps`
    opsLeft*: int               ## this turn's `TurnMaxOps` budget
    opsUsed*: int
    alive*: bool
    ## Chassis-private memory. It lives on the robot because the engine gives
    ## each bot one closure per robot and nothing else; no rule reads any of
    ## it.
    step*: int                  ## `examplefuncsplayer19`'s own counter
    weakRng*: uint64            ## its patched per-robot `java.util.Random`
    weakRngReady*: bool
    role*: int
    task*: int
    taskX*, taskY*: int
    homeX*, homeY*: int
    charge*: int
    lastRadio*: int
    escortOf*: int
    latticeSlot*: int

  TeamStats* = object
    castlesStart*: array[2, int]
    castlesLost*: array[2, int]
    churchesBuilt*: array[2, int]
    churchesLost*: array[2, int]
    enemyHalfChurches*: array[2, int]
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
    moves*: array[2, int]
    moveFuelSpent*: array[2, int]
    militaryMoves*: array[2, int]
    militaryMoveDistance*: array[2, int]
      ## The same pair over MILITARY units only. `unit_mix` is asserted on
      ## mean speed per moving turn, and the board-wide mean is dominated by
      ## PILGRIMS — which the knob does not touch — so the board-wide
      ## number moves 10 % where the military number moves 60 %.
    moveDistance*: array[2, int]
      ## The sum of `r^2` over every move, so `moveDistance div moves` is the
      ## MEAN SPEED PER MOVING TURN. `moveFuelSpent` cannot answer that: it
      ## is `r^2 x FUEL_PER_MOVE` and the multiplier differs by unit type.
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
    zeroStoreStreak*: array[2, int]
    zeroStoreWorst*: array[2, int]
    roundsAtZeroFuel*: array[2, int]
      ## Rounds ENDED with the fuel store at 0 -- distinct from
      ## `zeroStoreStreak`, which needs BOTH stores empty. Fuel alone is the
      ## one `fuel_reserve` is asserted against, because fuel is what every
      ## action in this year is priced in.
    pilgrimMoveSteps*: array[2, int]
    pilgrimTrips*: array[2, int]
      ## Steps taken by pilgrims and round trips completed (one `give` into
      ## an own structure ends a trip), so `steps div trips` is the MEAN WALK
      ## LENGTH the `symmetry_wall` knob is asserted against: a wall that
      ## closes the midline lengthens your own miners' journeys too.
    militaryDistance*: array[2, int]
    militaryDistanceSamples*: array[2, int]
    duplicateBuilds*: array[2, int]
    ownPilgrimsKilled*: array[2, int]
    enemyStructureDamage*: array[2, int]
    enemyNearCastle*: array[2, int]
    killsInsideDefendRadius*: array[2, int]
    preachersBy200*: array[2, int]
    aliveAt500*: array[2, int]
    castlesAt700*: array[2, int]

  World* = ref object
    map*: MapSpec
    width*, height*: int
    maxRounds*: int
    round*: int                 ## 1-BASED, as the engine's is
    robin*: int                 ## `Infinity` at the start; `high(int)` here
    running*: bool
    robots*: seq[Robot]         ## INSERTION ORDER, by-value removal
    indexById*: Table[int, int] ## never iterated; rebuilt on removal
    shadow*: seq[int32]         ## `y * width + x`; 0 = empty, else the id
    karbonite*: array[2, int]
    fuel*: array[2, int]
    lastOffer*: array[2, array[2, int]]   ## `[[k,f],[k,f]]`, RED then BLUE
    gen*: Mt19937
    idsSpent*: seq[int]
    idIsSpent*: Table[int, bool]
    winner*: Team
    hasWinner*: bool
    winCondition*: int          ## the ENGINE's own integer, or -1
    endRung*: int               ## `Bc19RungNames` ordinal
    tiebreakRound*: int
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    beatCount*: array[24, int]
    hashChain*: uint64
    stats*: TeamStats
    firstActionSeen*: array[2, bool]
    unitMilestoneSeen*: array[2, array[UnitKind, bool]]
    depotBeats*: array[2, int]
    famineSeen*: array[2, array[2, bool]]  ## [team][0 karbonite | 1 fuel]
    splashBeats*: array[2, int]
    lostThisRound*: array[2, int]
    lastKillCause*: array[2, string]
    ## The last enacted record, flattened. TELEMETRY ONLY -- NO RULE READS
    ## ANY OF IT. `tools/parity_trace_bc19.nim` prints the `A` line from it,
    ## and the engine's own `ActionRecord` is not returned by `enactTurn`
    ## either, so both sides recover it the same way.
    lastAction*: int
    lastDx*, lastDy*: int
    lastBuildUnit*: int
    lastGiveK*, lastGiveF*: int
    lastTradeK*, lastTradeF*: int
    defendRadius*: array[2, int]
      ## Each side's `defend_radius` knob, copied here once a round by
      ## `beginRound` so `enactAttack` -- which knows nothing about
      ## doctrines -- can attribute a kill to the defence of a structure.
      ## TELEMETRY ONLY: no rule reads it.
    brokenChassis*: bool
      ## Set by `-d:bc19BrokenChassis`: the NEGATIVE CONTROL for the
      ## economic-survival gate. Pilgrims mine but never `give`, castles
      ## ignore `fuel_reserve` entirely and the order never builds a second
      ## pilgrim.

# ---------------------------------------------------------------------------
#  Beats and events
# ---------------------------------------------------------------------------

const
  BeatGameStart* = 0
  BeatFirstAction* = 1
  BeatUnitMilestone* = 2
  BeatChurchBuilt* = 3
  BeatChurchLost* = 4
  BeatCastleLost* = 5
  BeatDepotClaimed* = 6
  BeatFamine* = 7
  BeatTrade* = 8
  BeatPreacherSplash* = 9
  BeatRout* = 10
  BeatDuel* = 11
  BeatTiebreak* = 12
  BeatGameEnd* = 13

  BeatBounds* = [1, 2, 8, 16, 16, 6, 20, 4, 20, 20, 20, 20, 1, 2,
                 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    ## Per GAME, exactly the design note's own event table.
    ## `tests/test_bc19_replay.nim` asserts every one of them against a real
    ## match, so a pathological game cannot produce a 20 MB replay. The whole
    ## worst case is `3 x 156 = 468` in-match entries plus eleven pre-match.

  CastlePressureRadius* = 100
    ## The r^2 inside which an enemy unit counts as pressing one of our
    ## castles. TELEMETRY ONLY -- it is the `symmetry_wall` knob's asserted
    ## statistic, not a rule -- and it is 100 because that is a castle's own
    ## vision radius, i.e. exactly the ring inside which a castle can see
    ## what is coming.

  Bc19RungNone* = 0
  Bc19RungCastlesDestroyed* = 1
  Bc19RungCoinFlip* = 2
  Bc19RungMoreCastles* = 3
  Bc19RungMoreUnitHealth* = 4

proc emit*(w: World, kind: string, a = 0, b = 0, c = 0, s = "") =
  w.events.add((round: w.round, kind: kind, a: a, b: b, c: c, s: s))

proc beat*(w: World, slot: int, kind: string, a = 0, b = 0, c = 0,
           s = ""): bool {.discardable.} =
  if w.beatCount[slot] >= BeatBounds[slot]: return false
  w.beatCount[slot] += 1
  w.emit(kind, a, b, c, s)
  true

proc mixHash*(w: World, v: int) =
  w.hashChain = (w.hashChain xor uint64(v and 0xFFFFFFFF)) *
    0x100000001B3'u64

proc mixHashU*(w: World, v: uint64) =
  ## The same step for a value that is ALREADY 64 bits. `int` is 32 bits under
  ## wasm32, so masking into an `int` first raises `RangeDefect` in the
  ## browser while the native suite stays green (the bc22 lesson).
  w.hashChain = (w.hashChain xor (v and 0xFFFFFFFF'u64)) *
    0x100000001B3'u64

func fnv1a64*(values: openArray[int]): uint64 =
  result = 0xcbf29ce484222325'u64
  for v in values:
    var u = uint32(v and 0xFFFFFFFF)
    for _ in 0 .. 3:
      result = result xor uint64(u and 0xff'u32)
      result = result * 0x100000001B3'u64
      u = u shr 8

# ---------------------------------------------------------------------------
#  Geometry and the shadow
# ---------------------------------------------------------------------------

func idx*(w: World, x, y: int): int = y * w.width + x

func onBoard*(w: World, x, y: int): bool =
  x >= 0 and y >= 0 and x < w.width and y < w.height

func isPassable*(w: World, x, y: int): bool =
  w.onBoard(x, y) and w.map.passable[y * w.width + x]

func hasKarbonite*(w: World, x, y: int): bool =
  w.onBoard(x, y) and w.map.karboniteMap[y * w.width + x]

func hasFuel*(w: World, x, y: int): bool =
  w.onBoard(x, y) and w.map.fuelMap[y * w.width + x]

func shadowAt*(w: World, x, y: int): int =
  if not w.onBoard(x, y): 0 else: int(w.shadow[y * w.width + x])

proc setShadow*(w: World, x, y, v: int) =
  if w.onBoard(x, y): w.shadow[y * w.width + x] = int32(v)

proc getItem*(w: World, id: int): Robot =
  ## `game.js:474-484`: a linear scan in the engine, an index lookup here. The
  ## `Table` is NEVER ITERATED, so it cannot leak a hash order into a rule.
  if id == 0: return nil
  let i = w.indexById.getOrDefault(id, -1)
  if i < 0 or i >= w.robots.len: return nil
  w.robots[i]

proc robotAt*(w: World, x, y: int): Robot =
  w.getItem(w.shadowAt(x, y))

# ---------------------------------------------------------------------------
#  The id pool (D1.2, V4) and the robot lifecycle
# ---------------------------------------------------------------------------

proc idPoolExhausted*(w: World): bool =
  ## V4. The engine's rejection loop `do id = 1+floor(4095*random()); while
  ## (ids.indexOf(id) >= 0)` NEVER TERMINATES once all 4 095 ids are spent.
  ## This port refuses the build instead — the only place it adds a rule the
  ## engine does not have, and it exists because "degrade, never hang"
  ## outranks fidelity to a hang. Derived ceiling on the played pool: the
  ## richest map (`seed-0030`, 19 karbonite depots a side) funds at most about
  ## 2 400 units a side over 1 000 rounds, so the floor is not reached in
  ## practice.
  w.idsSpent.len >= MaxId - 1

proc drawId*(w: World): int =
  ## `game.js:433-435`, exactly: ONE draw per attempt, rejected only on a
  ## collision with an already-spent id. The number of draws is therefore a
  ## pure function of the generator state and the spent set, which is why the
  ## per-round hash chain folds the whole MT state.
  while true:
    let id = 1 + int(4095.0 * w.gen.random())
    if not w.idIsSpent.getOrDefault(id, false):
      w.idsSpent.add(id)
      w.idIsSpent[id] = true
      return id

proc createItem*(w: World, x, y: int, team: Team, unit: UnitKind): Robot =
  ## `game.js:430-464`. The id draw first, then the record with every field at
  ## its documented start value, then `shadow[y][x] = id` ONLY IF the square
  ## reads 0, then APPEND to `robots` — which is why a unit built in a round
  ## takes a turn in the same round.
  let id = w.drawId()
  result = Robot(
    id: id, team: team, unit: unit, x: x, y: y,
    health: startingHpOf(unit), karbonite: 0, fuel: 0, turn: 0,
    signal: 0, signalRadius: 0, castleTalk: 0,
    chessOps: ChessInitialOps, opsLeft: 0, opsUsed: 0, alive: true,
    step: -1, role: 0, task: 0, taskX: -1, taskY: -1,
    homeX: x, homeY: y, charge: 0, lastRadio: -99, escortOf: 0,
    latticeSlot: -1)
  if w.shadowAt(x, y) == 0:
    w.setShadow(x, y, id)
  w.indexById[id] = w.robots.len
  w.robots.add(result)

proc reindexFrom(w: World, start: int) =
  for i in start ..< w.robots.len:
    w.indexById[w.robots[i].id] = i

proc deleteRobot*(w: World, r: Robot) =
  ## `_deleteRobot`, `game.js:933-943`: clear the shadow square, splice the
  ## robot out of the array, and DECREMENT `robin` when the removed index was
  ## below it — which is why a unit killed after it has already acted does not
  ## make the sweep skip the next one. Ids are NEVER RETURNED TO THE POOL.
  let i = w.indexById.getOrDefault(r.id, -1)
  if i < 0: return
  w.setShadow(r.x, r.y, 0)
  r.alive = false
  w.robots.delete(i)
  w.indexById.del(r.id)
  w.reindexFrom(i)
  if i < w.robin and w.robin != high(int):
    dec w.robin

# ---------------------------------------------------------------------------
#  Censuses the ladder, the score and the chrome read
# ---------------------------------------------------------------------------

func castlesAlive*(w: World, t: Team): int =
  for r in w.robots:
    if r.team == t and r.unit == ukCastle: inc result

func churchesAlive*(w: World, t: Team): int =
  for r in w.robots:
    if r.team == t and r.unit == ukChurch: inc result

func unitCount*(w: World, t: Team, u: UnitKind): int =
  for r in w.robots:
    if r.team == t and r.unit == u: inc result

func robotsOf*(w: World, t: Team): int =
  for r in w.robots:
    if r.team == t: inc result

func totalHealth*(w: World, t: Team): int =
  ## `isOver`'s rung 2 sums `robot.health` over EVERY live initialized unit of
  ## the team, not just its castles (`game.js:556-557`). The docs say "more
  ## total health" and mean exactly that.
  for r in w.robots:
    if r.team == t: result += r.health

func worthOf*(w: World, t: Team): int =
  ## `karbonite + fuel div 5 + sum of build karbonite over live units`.
  ## `fuel div 5` is the ENGINE'S OWN exchange rate, not a taste: one `mine`
  ## action buys 2 karbonite or 10 fuel, so 1 karbonite = 5 fuel at the
  ## margin. A CASTLE cannot be built and contributes 0; a CHURCH contributes
  ## 50.
  result = w.karbonite[ord(t)] + w.fuel[ord(t)] div 5
  for r in w.robots:
    if r.team == t: result += buildKarboniteOf(r.unit)

func carriedKarbonite*(w: World, t: Team): int =
  for r in w.robots:
    if r.team == t: result += r.karbonite

func carriedFuel*(w: World, t: Team): int =
  for r in w.robots:
    if r.team == t: result += r.fuel

proc shadowChecksum*(w: World): uint64 =
  ## FNV-1a 64 over the occupancy shadow, y ascending outer, x ascending
  ## inner — the engine's own sweep order.
  result = 0xcbf29ce484222325'u64
  for v in w.shadow:
    var u = uint32(v)
    for _ in 0 .. 3:
      result = result xor uint64(u and 0xff'u32)
      result = result * 0x100000001B3'u64
      u = u shr 8

proc queueChecksum*(w: World): uint64 =
  ## FNV-1a 64 over the queue's id list IN QUEUE ORDER, which is what makes an
  ## ordering bug visible on the round it happens.
  var ids = newSeq[int](w.robots.len)
  for i, r in w.robots: ids[i] = r.id
  fnv1a64(ids)

# ---------------------------------------------------------------------------
#  Construction
# ---------------------------------------------------------------------------

proc newWorld*(spec: MapSpec, maxRounds: int): World =
  ## `new Game(seed, chess_initial, chess_extra, false, false, false)`, with
  ## `makeMap()` replaced by the COMMITTED board and the generator RESTORED to
  ## the state `makeMap()` left (V3, D1) — so the castles' ids, and therefore
  ## every id after them, are exactly the engine's.
  result = World(
    map: spec, width: spec.width, height: spec.height,
    maxRounds: maxRounds,
    round: 0, robin: high(int), running: true,
    shadow: newSeq[int32](spec.width * spec.height),
    karbonite: [InitialKarbonite, InitialKarbonite],
    fuel: [InitialFuel, InitialFuel],
    lastOffer: [[0, 0], [0, 0]],
    indexById: initTable[int, int](),
    idIsSpent: initTable[int, bool](),
    winner: tRed, hasWinner: false, winCondition: -1,
    endRung: Bc19RungNone, tiebreakRound: maxRounds,
    hashChain: 0xcbf29ce484222325'u64)
  result.gen.loadState(spec.mtWords, spec.mtMti)
  when defined(bc19BrokenChassis):
    result.brokenChassis = true
  for c in spec.castles:
    discard result.createItem(c.x, c.y, Team(c.team), ukCastle)
  for t in 0 .. 1:
    result.stats.castlesStart[t] = result.castlesAlive(Team(t))

func mirrorOf*(w: World, x, y: int): (int, int) =
  ## Every 2019 board is a mirror and every robot is handed the whole terrain,
  ## karbonite and fuel map on its FIRST turn (`game.js:728-730`), so the
  ## enemy's castles are derivable from your own in a few operations on turn
  ## 1. This is that derivation.
  if w.map.symmetryHorizontal: (w.width - 1 - x, y) else: (x, w.height - 1 - y)

func inEnemyHalf*(w: World, t: Team, x, y: int): bool =
  ## RED's castles are the ones the generator emitted first and they sit in
  ## the LOW half of the mirrored axis; BLUE's are their mirror. "The enemy's
  ## half" is therefore the far side of the midline on the mirrored axis.
  if w.map.symmetryHorizontal:
    if t == tRed: x * 2 >= w.width else: x * 2 < w.width
  else:
    if t == tRed: y * 2 >= w.height else: y * 2 < w.height

proc noteCastleLoss*(w: World, r: Robot, cause: string) =
  let t = ord(r.team)
  w.stats.castlesLost[t] += 1
  discard w.beat(BeatCastleLost, "castle_lost", t, r.x * 100 + r.y,
                 w.castlesAlive(r.team) - 1, cause)

proc noteChurchLoss*(w: World, r: Robot) =
  let t = ord(r.team)
  w.stats.churchesLost[t] += 1
  discard w.beat(BeatChurchLost, "church_lost", t, r.x * 100 + r.y,
                 w.churchesAlive(r.team) - 1)

func endReasonName*(rung: int): string =
  case rung
  of Bc19RungCastlesDestroyed: "castles_destroyed"
  of Bc19RungCoinFlip: "coin_flip"
  of Bc19RungMoreCastles: "more_castles"
  of Bc19RungMoreUnitHealth: "more_unit_health"
  else: "abandoned"

func hashChainHexOf*(w: World): string = toHex(w.hashChain)
