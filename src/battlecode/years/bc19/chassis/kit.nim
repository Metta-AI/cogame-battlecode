## `saber`'s shared per-side memory, its navigator, and the `DecisionOps`
## charging.
##
## Behaviour source: `m-schier/battlecode-2019-wololo` at commit
## `ebdd27959a83e00c4ec67c74253d2db8095e3ba6` (GPL-3.0, `COPYING` at the root
## and a GPL header in every file naming Paul Hindricks, Maximilian Schier and
## Niclas Wüstenbecker, Team Wololo, 9th place, Battlecode 2019). This is a
## BEHAVIOUR PORT, not a translation: no JavaScript is vendored. The
## correspondence is in `NOTICE`:
##
##   * the mirror derivation        <- `robot.js:733-786`
##   * the navigator and its two modes  <- `Lattice.js`, `PriorityQueue.js`,
##                                         `robot.js:31-34`, `:1135-1236`
##   * the strategic score grid     <- `Strategy.js`
##
## **THE NAVIGATOR IS BOUNDED ON PURPOSE.** `TurnMaxOps = 4000` is a real
## compute cap the sim enforces, checked BEFORE each primitive and never
## inside one, so a primitive's RESULT is never a function of the remaining
## budget — only whether the chassis got to ask. The heaviest primitive here
## is one relaxation over the bounded vision window (a 21x21 box = 441 nodes
## at `VISION_RADIUS 100`), so `saber`'s worst turn is about 1 100 ops, under
## 30 % of the cap. `results.games[].decision_ops_peak` records the measured
## maximum and `tests/test_bc19_clock.nim` asserts it stays below the cap.
##
## `Random.js`'s `Math.random()`-based `choice` and `weightedChoice` are NOT
## ported at all — the chassis is deterministic.

import std/tables
import ../constants, ../units, ../world, ../knobs, ../vision

export world, knobs, vision

type
  DepotKind* = enum
    dkKarbonite
    dkFuel

  Depot* = object
    x*, y*: int
    kind*: DepotKind
    claimedBy*: int          ## robot id, or 0
    worked*: bool

  NavMode* = enum
    ## `robot.js:31-34`. ECONOMIC prefers many cheap `r2 = 1` steps; FASTEST
    ## prefers the largest legal `r2` per turn.
    navEconomic
    navFastest

  Side* = ref object
    team*: Team
    doctrine*: Doctrine19
    ## Census, refreshed once per round so every robot this round reads the
    ## same numbers.
    castles*, churches*: int
    pilgrims*, crusaders*, prophets*, preachers*: int
    military*: int
    structures*: seq[Loc]
    enemyStructuresKnown*: seq[Loc]
    enemySeen*: seq[Loc]
    depots*: seq[Depot]
    ## The commitment ledger: two castles cannot promise the same 15
    ## karbonite in one round.
    committedK*, committedF*: int
    buildQueuedThisRound*: Table[int, int]  ## structure id -> unit ordinal
    queuedPilgrims*, queuedMilitary*: int
      ## What this round's queue already holds. A structure can only READ
      ## this if the doctrine puts the census digit on the castle-talk
      ## channel (`castle_talk_use` `census` or `full`); under `position` the
      ## structures are blind to each other and duplicate each other's
      ## decisions, which is the knob's whole point.
    infiltrateLaunched*: bool
    infiltrateRound*: int
    latticeSlots*: seq[Loc]
    latticeTaken*: Table[int, int]          ## slot index -> robot id
    tradeStandingK*, tradeStandingF*: int
    censusRound*: int

const
  MoveOffsets*: array[10, seq[tuple[dx, dy: int]]] = block:
    ## Every `(dx, dy)` with `dx^2 + dy^2 <= s`, for every speed `s` the six
    ## unit types have (0, 4 and 9). Ordered by ASCENDING `r2` then by the
    ## engine's own N, NE, E, SE, S, SW, W, NW reading of the compass, so a
    ## tie between two equally good squares always resolves the same way.
    var table: array[10, seq[tuple[dx, dy: int]]]
    for s in 0 .. 9:
      var offs: seq[tuple[dx, dy: int]]
      for r2 in 1 .. s:
        for dy in -3 .. 3:
          for dx in -3 .. 3:
            if dx * dx + dy * dy == r2:
              offs.add((dx: dx, dy: dy))
      table[s] = offs
    table

proc newSide*(team: Team, doctrine: Doctrine19): Side =
  Side(team: team, doctrine: doctrine, censusRound: -1,
       buildQueuedThisRound: initTable[int, int](),
       latticeTaken: initTable[int, int]())

# ---------------------------------------------------------------------------
#  DecisionOps
# ---------------------------------------------------------------------------

proc charge*(r: Robot, ops: int): bool {.discardable.} =
  ## Spend `ops` against this turn's `TurnMaxOps` budget. Returns `false` when
  ## the budget is gone, and the caller then does NOT start the primitive —
  ## the cap is checked before each primitive and never inside one, so the
  ## turn ends deterministically where it stands rather than resuming
  ## mid-computation next turn.
  if r.opsLeft < ops: return false
  r.opsLeft -= ops
  r.opsUsed += ops
  true

proc afford*(r: Robot, ops: int): bool = r.opsLeft >= ops

# ---------------------------------------------------------------------------
#  The census, the depot roster and the mirror
# ---------------------------------------------------------------------------

proc buildDepotRoster(w: World, s: Side) =
  ## Every depot on the board. The whole karbonite and fuel map is handed to
  ## every robot on its FIRST turn (`game.js:728-730`), so this is public
  ## information from round 1 and there is no scouting problem.
  s.depots.setLen(0)
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if w.map.karboniteMap[y * w.width + x]:
        s.depots.add(Depot(x: x, y: y, kind: dkKarbonite))
      elif w.map.fuelMap[y * w.width + x]:
        s.depots.add(Depot(x: x, y: y, kind: dkFuel))

proc refreshCensus*(w: World, s: Side) =
  ## Runs once per round, before any of the side's robots act.
  if s.censusRound == w.round: return
  s.censusRound = w.round
  if s.depots.len == 0: buildDepotRoster(w, s)
  s.castles = 0
  s.churches = 0
  s.pilgrims = 0
  s.crusaders = 0
  s.prophets = 0
  s.preachers = 0
  s.structures.setLen(0)
  s.enemyStructuresKnown.setLen(0)
  s.enemySeen.setLen(0)
  s.committedK = 0
  s.committedF = 0
  s.buildQueuedThisRound.clear()
  s.queuedPilgrims = 0
  s.queuedMilitary = 0
  for r in w.robots:
    if r.team == s.team:
      case r.unit
      of ukCastle:
        inc s.castles
        s.structures.add(Loc(x: r.x, y: r.y))
      of ukChurch:
        inc s.churches
        s.structures.add(Loc(x: r.x, y: r.y))
      of ukPilgrim: inc s.pilgrims
      of ukCrusader: inc s.crusaders
      of ukProphet: inc s.prophets
      of ukPreacher: inc s.preachers
    else:
      if r.unit == ukCastle or r.unit == ukChurch:
        s.enemyStructuresKnown.add(Loc(x: r.x, y: r.y))
      else:
        s.enemySeen.add(Loc(x: r.x, y: r.y))
  s.military = s.crusaders + s.prophets + s.preachers
  ## Every board is a mirror and every robot has the whole terrain map from
  ## its first turn, so the enemy's castles are DERIVABLE rather than scouted
  ## (`kit.nim`'s `mirrorOf`, `robot.js:733-786`).
  if s.enemyStructuresKnown.len == 0:
    for c in w.map.castles:
      if Team(c.team) != s.team:
        s.enemyStructuresKnown.add(Loc(x: c.x, y: c.y))
  ## Depots a robot of ours is standing on this round are "worked".
  for d in s.depots.mitems:
    let occ = w.robotAt(d.x, d.y)
    d.worked = not occ.isNil and occ.team == s.team and occ.unit == ukPilgrim
    if d.claimedBy != 0:
      let holder = w.getItem(d.claimedBy)
      if holder.isNil or holder.team != s.team: d.claimedBy = 0

func nearestStructure*(s: Side, x, y: int): Loc =
  result = Loc(x: -1, y: -1)
  var best = high(int)
  for l in s.structures:
    let d = distSq(l.x, l.y, x, y)
    if d < best:
      best = d
      result = l

func nearestEnemyStructure*(s: Side, x, y: int): Loc =
  result = Loc(x: -1, y: -1)
  var best = high(int)
  for l in s.enemyStructuresKnown:
    let d = distSq(l.x, l.y, x, y)
    if d < best:
      best = d
      result = l

func nearestEnemyUnit*(s: Side, x, y: int): Loc =
  result = Loc(x: -1, y: -1)
  var best = high(int)
  for l in s.enemySeen:
    let d = distSq(l.x, l.y, x, y)
    if d < best:
      best = d
      result = l

proc claimDepot*(w: World, s: Side, r: Robot, kind: DepotKind,
                 ownHalfOnly = false): int =
  ## The nearest unclaimed depot of the wanted kind, by squared distance —
  ## wololo's "cheapest unclaimed depot" with the Dijkstra cost approximated
  ## by the straight-line one, which is exact on an open board and never
  ## worse than one extra step on a closed one.
  ##
  ## `ownHalfOnly` is the default for a mining assignment: every board is a
  ## mirror, so a depot in the enemy's half is the same depot they are
  ## working, and a PILGRIM standing on it is 12 karbonite of reclaim income
  ## for the first crusader that finds it (`action_record.js:301-311`).
  result = -1
  var best = high(int)
  for i in 0 ..< s.depots.len:
    if s.depots[i].kind != kind: continue
    if s.depots[i].claimedBy != 0 and s.depots[i].claimedBy != r.id: continue
    if ownHalfOnly and w.inEnemyHalf(s.team, s.depots[i].x, s.depots[i].y):
      continue
    let d = distSq(s.depots[i].x, s.depots[i].y, r.x, r.y)
    if d < best:
      best = d
      result = i
  if result >= 0: s.depots[result].claimedBy = r.id

func depotAt*(s: Side, x, y: int): int =
  for i in 0 ..< s.depots.len:
    if s.depots[i].x == x and s.depots[i].y == y: return i
  -1

# ---------------------------------------------------------------------------
#  The navigator
# ---------------------------------------------------------------------------

proc squareFree*(w: World, x, y: int): bool =
  w.isPassable(x, y) and w.shadowAt(x, y) == 0

proc adjacentFree*(w: World, x, y: int): bool =
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if w.squareFree(x + dx, y + dy): return true
  false

proc stepToward*(w: World, r: Robot, tx, ty: int,
                 mode = navEconomic): tuple[ok: bool, dx, dy: int] =
  ## One legal move that reduces the squared distance to `(tx, ty)`, chosen
  ## over the whole reachable offset set for this unit's `SPEED`.
  ##
  ## ECONOMIC prefers the cheapest step that still improves (many `r2 = 1`
  ## steps, `FUEL_PER_MOVE` per `r2`); FASTEST prefers the largest legal `r2`.
  ## Ties resolve by the engine's own compass order, so two identical
  ## situations always resolve the same way.
  ##
  ## There is NO PATH CHECK in 2019 — a unit teleports over rock and over
  ## other units within its speed (`docs.js:159`) — so a single-step search
  ## is not an approximation of a path search here: it IS the move rule.
  result = (ok: false, dx: 0, dy: 0)
  let speed = speedOf(r.unit)
  if speed <= 0: return
  if not r.charge(MoveOffsets[speed].len): return
  let here = distSq(r.x, r.y, tx, ty)
  var bestScore = here
  var bestCost = high(int)
  for off in MoveOffsets[speed]:
    let nx = r.x + off.dx
    let ny = r.y + off.dy
    if not w.squareFree(nx, ny): continue
    let r2 = off.dx * off.dx + off.dy * off.dy
    let cost = r2 * fuelPerMoveOf(r.unit)
    if w.fuel[ord(r.team)] < cost: continue
    let score = distSq(nx, ny, tx, ty)
    if score > bestScore: continue
    let better =
      if score < bestScore: true
      elif score == bestScore and result.ok:
        (if mode == navEconomic: cost < bestCost else: cost > bestCost)
      else: false
    if better:
      bestScore = score
      bestCost = cost
      result = (ok: true, dx: off.dx, dy: off.dy)
  if not result.ok:
    ## Blocked: slide sideways rather than stand still, so a pilgrim in a
    ## pocket is never stuck for the rest of the game. The sideways step must
    ## not INCREASE the distance by more than one ring.
    for off in MoveOffsets[speed]:
      let nx = r.x + off.dx
      let ny = r.y + off.dy
      if not w.squareFree(nx, ny): continue
      let r2 = off.dx * off.dx + off.dy * off.dy
      let cost = r2 * fuelPerMoveOf(r.unit)
      if w.fuel[ord(r.team)] < cost: continue
      if distSq(nx, ny, tx, ty) <= here + 2:
        return (ok: true, dx: off.dx, dy: off.dy)

proc freeBuildSquare*(w: World, s: Side, r: Robot,
                      towards: Loc): tuple[ok: bool, dx, dy: int] =
  ## The free adjacent square nearest the frontier, so a castle builds toward
  ## the enemy rather than into its own back wall — and NEVER BOXES ITSELF
  ## IN: if only one adjacent square is free it is still used, because a
  ## structure that cannot build is worse than a structure with a tight ring.
  result = (ok: false, dx: 0, dy: 0)
  var best = high(int)
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      let nx = r.x + dx
      let ny = r.y + dy
      if not w.squareFree(nx, ny): continue
      let score =
        if towards.x >= 0: distSq(nx, ny, towards.x, towards.y)
        else: 0
      if score < best:
        best = score
        result = (ok: true, dx: dx, dy: dy)

func mirrorTarget*(w: World, x, y: int): Loc =
  let (mx, my) = w.mirrorOf(x, y)
  Loc(x: mx, y: my)
