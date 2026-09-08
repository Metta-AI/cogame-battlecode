## `spaark`'s shared per-side memory, navigation and refill rule.
##
## Behaviour ported from `erikji/battlecode25` `src/SPAARK/` (AGPL-3.0, head
## `63165da`, the High-School 1st-place bot): the remembered map, the ruin
## claim table, the frontier-connectivity painting rule and the navigator's
## own-paint-preferring tiebreak. BEHAVIOUR, NOT CODE — rewritten in Nim and
## parameterised by this coworld's doctrine sheet. `NOTICE` names the files.
##
## Everything a unit learns is charged against its `DecisionOps` budget by
## `world.spend`, and the charge happens BEFORE each primitive, never inside
## one — so a sense sweep, a pattern check or a navigation step either runs to
## completion or does not start, and the answer is never a function of the
## remaining budget.
##
## THE NAVIGATOR IS DELIBERATELY CHEAP. bc25 puts up to 130 units on the board
## for 2000 rounds and a per-unit BFS would blow `tests/test_bc25_perf.nim`'s
## 90-second gate; SPAARK's own answer is the same one — a greedy step over the
## eight directions with a short no-repeat history to break oscillation, and a
## "prefer own paint" tiebreak because walking on own paint costs no paint at
## all. A bounded ring search is the fallback when every greedy candidate is
## blocked.

import ../world, ../towers, ../comms, ../knobs

export world, towers, comms, knobs

type
  Side* = ref object
    ## The per-team memory every unit shares. None of it is world state: a
    ## rule never reads it, and two clans with the same doctrine on the same
    ## map produce the same memory.
    team*: Team
    doctrine*: Doctrine25
    mix*: UnitMix                 ## `doctrine.unitMix`, clamped and normalised
    homeTowers*: seq[Loc]         ## our two starting towers, round 0
    enemyHome*: Loc               ## the enemy's nearer starting tower
    knownRuins*: seq[Loc]
      ## THE REMEMBERED MAP. Ruins are static terrain, so a clan that has once
      ## sensed one knows it is there — which is what lets a soldier WALK to a
      ## ruin outside its own vision radius instead of stumbling on one. A
      ## unit only ever learns a ruin it could legitimately sense.
    knownRuinSet*: seq[bool]
    knownCentres*: seq[Loc]
      ## Tiles the clan has SENSED to be legal resource-pattern centres — no
      ## wall and no ruin anywhere in their 5x5, two tiles from every edge.
      ## Walls and ruins are static terrain, so a tile that qualified when it
      ## was seen still qualifies; remembering them is what lets a soldier walk
      ## to a pattern site instead of waiting to stand on one.
    knownCentreSet*: seq[bool]
    claims*: Table[int, TowerKind]
      ## tile index -> the tower kind a soldier has committed to painting
      ## there. `econ.nim` is the only place chips are committed, so two
      ## soldiers can never promise the same 1000.
    claimOwner*: Table[int, int]  ## tile index -> robot id
    chokes*: seq[Loc]
    chokesMeasured*: bool
    towerCursor*: int             ## position in `tower_type_order`
    srpCentre*: Loc
    srpFunded*: bool
    srpDone*: bool
    protectedSrp*: Loc
      ## The clan's own most recent completed pattern.
    protected*: seq[Loc]
      ## EVERY completed pattern of ours. Nothing the clan does may touch one:
      ## no new pattern centred within four tiles of it (their 5x5s would
      ## overlap and the second would repaint the first), no ruin claimed
      ## whose tower pattern would overlap it, and no friendly splash inside
      ## it. One splash repaints its whole blast in ONE colour and an SRP is a
      ## two-colour picture, so a single friendly splash is 200 chips and
      ## fifty rounds in the bin.
    lostTowerRound*: int          ## -1 until the clan first loses a tower
    frontier*: Loc
    frontierRound*: int
    censusRound*: int
    soldiers*, moppers*, splashers*: int
    towersHeld*: int

proc newSide*(team: Team, doctrine: Doctrine25): Side =
  Side(team: team, doctrine: doctrine, mix: normalisedMix(doctrine.unitMix),
       claims: initTable[int, TowerKind](),
       claimOwner: initTable[int, int](),
       lostTowerRound: -1, frontierRound: -1, censusRound: -1,
       frontier: loc(-1, -1), srpCentre: loc(-1, -1),
       protectedSrp: loc(-1, -1))

# ---------------------------------------------------------------------------
#  Round-level bookkeeping
# ---------------------------------------------------------------------------

proc observeRuins*(w: World, side: Side, r: Robot) =
  ## Fold every ruin — and every legal resource-pattern centre — this unit can
  ## sense into the clan's memory. Charged one `DecisionOps` credit per tile
  ## examined, like every other sweep.
  if side.knownRuinSet.len == 0:
    side.knownRuinSet = newSeq[bool](w.width * w.height)
    side.knownCentreSet = newSeq[bool](w.width * w.height)
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not r.spend(1): break
    let i = w.idx(l)
    if w.hasRuin(l):
      if not side.knownRuinSet[i]:
        side.knownRuinSet[i] = true
        side.knownRuins.add(l)
    elif not side.knownCentreSet[i] and side.knownCentres.len < 64:
      if not r.spend(2): break
      if w.isValidPatternCenter(l, false):
        side.knownCentreSet[i] = true
        side.knownCentres.add(l)

func overlapsProtected*(side: Side, centre: Loc, span: int): bool =
  ## True when a 5x5 centred here would touch one of the clan's own live
  ## patterns.
  for p in side.protected:
    if chebyshev(p, centre) <= span: return true
  false

proc observeHome*(w: World, side: Side) =
  ## Called once, at the top of round 1: the two starting towers are ours and
  ## the nearer enemy tower is the direction the war runs in.
  if side.homeTowers.len > 0: return
  var best = high(int)
  for id in w.execOrder:
    let r = w.robotsById[id]
    if not r.kind.isTowerType(): continue
    if r.team == side.team:
      side.homeTowers.add(r.loc)
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.kind.isTowerType() and r.team != side.team:
      for home in side.homeTowers:
        let d = home.distanceSquaredTo(r.loc)
        if d < best:
          best = d
          side.enemyHome = r.loc
  if side.homeTowers.len == 0:
    side.enemyHome = loc(w.width div 2, w.height div 2)

proc refreshCensus*(w: World, side: Side) =
  ## Once a round, and never inside a unit's turn: the counts `econ.nim` reads
  ## to decide what a tower builds next.
  if side.censusRound == w.currentRound: return
  side.censusRound = w.currentRound
  side.soldiers = 0
  side.moppers = 0
  side.splashers = 0
  side.towersHeld = w.stats.towers[ord(side.team)]
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team != side.team: continue
    case r.kind
    of utSoldier: side.soldiers += 1
    of utMopper: side.moppers += 1
    of utSplasher: side.splashers += 1
    else: discard
  ## Drop claims whose ruin now carries a tower, and claims whose last known
  ## owner is dead — a soldier killed on the way to a ruin must not lock it
  ## out for the rest of the game. A ruin several soldiers joined keeps its
  ## claim as long as ANY of them is alive, because `claimOwner` is rewritten
  ## by each joiner.
  var stale: seq[int]
  for tile, _ in side.claims:
    let owner = side.claimOwner.getOrDefault(tile, -1)
    let at = w.indexToLoc(tile)
    if not w.existsRobot(owner) or w.hasTower(at):
      stale.add(tile)
  for tile in stale:
    side.claims.del(tile)
    side.claimOwner.del(tile)

proc noteTowerLoss*(w: World, side: Side) =
  if side.lostTowerRound < 0 and w.stats.towersLost[ord(side.team)] > 0:
    side.lostTowerRound = w.currentRound

# ---------------------------------------------------------------------------
#  Refill — the `paint_reserve_floor` test
# ---------------------------------------------------------------------------

func paintPct*(r: Robot): int = paintPercentage(r.paint, r.kind)

func needsRefill*(side: Side, r: Robot): bool =
  ## Below the floor a robot breaks off and walks to the nearest friendly
  ## paint tower (or asks the nearest mopper). Below 50 % the engine's own
  ## cooldown surcharge is already biting, so a LOW floor is a real trade:
  ## more time on task, slower actions, and a hard stop at 0.
  r.kind.isRobotType() and paintPct(r) < side.doctrine.paintReserveFloor

func isFull*(r: Robot): bool =
  r.paint >= UnitSpecs[r.kind].paintCapacity - 5

# ---------------------------------------------------------------------------
#  Sensing helpers, all charged
# ---------------------------------------------------------------------------

proc nearestFriendlyTower*(w: World, side: Side, r: Robot,
                           needPaint = false): Loc =
  ## The nearest friendly tower ANYWHERE — the chassis remembers its own
  ## towers, which is legitimate: a clan knows where it built.
  result = loc(-1, -1)
  var best = high(int)
  for id in w.execOrder:
    if not r.spend(1): break
    let t = w.robotsById[id]
    if t.team != side.team or not t.kind.isTowerType(): continue
    if needPaint and t.paint <= 0: continue
    let d = r.loc.distanceSquaredTo(t.loc)
    if d < best:
      best = d
      result = t.loc

proc senseEnemies*(w: World, r: Robot, r2 = VisionRadiusSquared): seq[Robot] =
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    if not r.spend(1): break
    let bot = w.getRobot(l)
    if bot != nil and bot.team != r.team:
      result.add(bot)

proc senseAllies*(w: World, r: Robot, r2 = VisionRadiusSquared): seq[Robot] =
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    if not r.spend(1): break
    let bot = w.getRobot(l)
    if bot != nil and bot.team == r.team and bot.id != r.id:
      result.add(bot)

# ---------------------------------------------------------------------------
#  Navigation
# ---------------------------------------------------------------------------

proc rememberStep(r: Robot, l: Loc) =
  r.noRepeat.add(l)
  if r.noRepeat.len > 6:
    r.noRepeat = r.noRepeat[1 .. ^1]

func recentlyVisited(r: Robot, l: Loc): bool =
  for seen in r.noRepeat:
    if seen == l: return true
  false

proc stepToward*(w: World, side: Side, r: Robot, target: Loc): bool
    {.discardable.} =
  ## One greedy step, scored: closer is better, own paint is better (it costs
  ## no paint to stand on), a tile visited in the last six steps is worse.
  ## Returns true when the robot actually moved.
  if target.x < 0: return false
  if not r.isMovementReady(): return false
  if not r.spend(12): return false
  var bestDir = dCenter
  var bestScore = low(int)
  let here = r.loc.distanceSquaredTo(target)
  for d in MoveDirs:
    let l = r.loc + d
    if not w.canMove(r, d): continue
    var score = (here - l.distanceSquaredTo(target)) * 8
    let colour = w.getPaint(l)
    if paintIsTeam(colour, side.team): score += 5
    elif hasPaintTeam(colour): score -= 4
    if recentlyVisited(r, l): score -= 20
    if score > bestScore:
      bestScore = score
      bestDir = d
  if bestDir == dCenter: return false
  rememberStep(r, r.loc)
  w.doMove(r, bestDir)
  true

proc stepAway*(w: World, side: Side, r: Robot, threat: Loc): bool
    {.discardable.} =
  if threat.x < 0: return false
  let mirror = loc(r.loc.x * 2 - threat.x, r.loc.y * 2 - threat.y)
  w.stepToward(side, r, mirror)

# ---------------------------------------------------------------------------
#  The frontier: the tile the clan is trying to colour next
# ---------------------------------------------------------------------------

proc frontierFor*(w: World, side: Side): Loc =
  ## Once a round: the midpoint between our home and the enemy's, nudged by
  ## how much of the map we already hold. It is a direction, not a plan — the
  ## soldiers do the actual choosing tile by tile.
  if side.frontierRound == w.currentRound: return side.frontier
  side.frontierRound = w.currentRound
  if side.homeTowers.len == 0:
    side.frontier = loc(w.width div 2, w.height div 2)
    return side.frontier
  let home = side.homeTowers[0]
  let ours = w.stats.livePainted[ord(side.team)]
  let theirs = w.stats.livePainted[ord(side.team.other())]
  ## Ahead on colour: push. Behind: consolidate.
  let push = if ours >= theirs: 60 else: 35
  side.frontier = loc(
    home.x + (side.enemyHome.x - home.x) * push div 100,
    home.y + (side.enemyHome.y - home.y) * push div 100)
  side.frontier
