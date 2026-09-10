## `orchard`'s shared kit: the per-side memory, the `DecisionOps` charging,
## the mirror, the rosters and the navigator.
##
## **THE OP BUDGET IS ENFORCED BY THE SIM, NOT BY THE BOT** (V1). One credit
## is charged for each body examined in a candidate query, grid cell scanned,
## farm slot scored, direction evaluated in the `tryMove` probe, bullet tested
## by `willCollideWithMe`, target scored, broadcast channel read, and tree
## scored for watering or chopping. **The budget is checked BEFORE a primitive
## starts and never inside one**, so a primitive's RESULT is never a function
## of the remaining budget -- only whether the chassis got to ask.
##
## `ArchonOps` is 3 000 and `UnitOps` 1 500 (one tenth of the engine's own
## 30 000 / 15 000 bytecode limits, the repo's standing convention), and
## **`DormantOps` is 0 -- which is not the divergence but THE RULE**:
## `getBytecodeLimit()` returns 0 unless `canExecuteCode()`, i.e.
## `health > 0 && (isBuildable() ? roundsAlive >= 20 : true)`.
##
## LICENCE. Two behaviours in this file and in `micro.nim` are ports of the
## **AGPL-3.0** `battlecode/battlecode-scaffold-2017`
## `src/examplefuncsplayer/RobotPlayer.java` at `76e7b51e`, and `NOTICE`
## names them individually rather than leaving it implicit:
##
##   * `tryMove` -- the seven-direction obstacle probe (try the intended
##     direction, then +-20 degrees, +-40, +-60) at `RobotPlayer.java:215-244`;
##   * `willCollideWithMe` -- the bullet-collision test at `:253-277`, which
##     lives in `micro.nim`.
##
## Nothing else in `orchard` comes from anywhere but the engine source, the
## 1.6.2 spec page and this run's own design.

import std/[math, tables]
import ../../../sim_types
import ../constants, ../units, ../geom, ../world, ../actions, ../knobs

export world, actions, knobs

type
  Posture* = enum
    ## `military.nim`'s four-state machine.
    poRally = "rally"
    poPush = "push"
    poScreen = "screen"
    poAnswer = "answer"

  Side* = ref object
    ## The per-side memory every robot of one faction shares. It is the
    ## chassis's, not the sim's: no rule reads a byte of it.
    team*: Team
    doctrine*: Doctrine17
    ownArchonStarts*: seq[Loc]
      ## `getInitialArchonLocations(us)` -- public from round 1.
    enemyArchonStarts*: seq[Loc]
      ## `getInitialArchonLocations(them)` -- ALSO public from round 1, which
      ## is why 2017 has no scouting problem for the enemy BASE.
    rally*: Loc
    ## Farm-slot claims, keyed by a quantised location so two gardeners
    ## cannot plant into the same circle.
    claims*: Table[int, int]
    ## The per-archon commitment ledger, so two archons cannot promise the
    ## same 100 bullets in one round.
    committed*: float32
    committedRound*: int
    ## Military accounting: bullets spent per type, so `mix()` can serve the
    ## doctrine's percentages over time rather than per build.
    spentOn*: array[RobotType, float32]
    ## Remembered neutral trees worth visiting, and a claim bit each.
    treeClaims*: Table[int, int]
    ## Telemetry the tests read.
    strikesRefused*: int

const
  ProbeAngles* = [0'f32, 20'f32, -20'f32, 40'f32, -40'f32, 60'f32, -60'f32]
    ## The licensed `tryMove` probe order, verbatim: the intended direction
    ## first, then alternating left and right by 20 degrees at a time.

proc newSide*(team: Team, doctrine: Doctrine17): Side =
  Side(team: team, doctrine: doctrine, claims: initTable[int, int](),
       treeClaims: initTable[int, int]())

# ---------------------------------------------------------------------------
#  The op budget
# ---------------------------------------------------------------------------

func canThink*(r: Robot): bool = r.opsUsed < r.ops
  ## Checked BEFORE a primitive, never inside one.

proc spend*(r: Robot, n: int) =
  r.opsUsed += n

proc chargeFor*(r: Robot, n: int): bool {.discardable.} =
  ## Charge `n` credits up front, for a primitive whose cost is known before
  ## it runs (a direction probe, a channel read).
  if not r.canThink(): return false
  r.spend(n)
  true

# ---------------------------------------------------------------------------
#  Charged sensing
# ---------------------------------------------------------------------------

proc senseRobots*(w: World, r: Robot, radius: float32,
                  team = -1): seq[int] =
  if not r.canThink(): return @[]
  result = w.senseNearbyRobots(r, radius, team)
  r.spend(max(1, result.len))

proc senseTrees*(w: World, r: Robot, radius: float32, team = -1): seq[int] =
  if not r.canThink(): return @[]
  result = w.senseNearbyTrees(r, radius, team)
  r.spend(max(1, result.len))

proc senseBullets*(w: World, r: Robot, radius: float32): seq[int] =
  if not r.canThink(): return @[]
  result = w.senseNearbyBullets(r, radius)
  r.spend(max(1, result.len))

proc readChannel*(w: World, r: Robot, channel: int): int =
  if not r.chargeFor(1): return 0
  w.readBroadcast(r, channel)

# ---------------------------------------------------------------------------
#  The mirror, the rosters and the rally point
# ---------------------------------------------------------------------------

proc learnStarts*(w: World, s: Side) =
  ## `getInitialArchonLocations` for BOTH teams, read once per game from the
  ## map's own initial bodies exactly as the engine's own accessor reads them
  ## -- sorted, and public to both sides.
  if s.ownArchonStarts.len > 0: return
  for b in w.map.bodies:
    if not b.isRobot or b.kind != rtArchon: continue
    if b.team == s.team: s.ownArchonStarts.add(b.loc)
    elif b.team != tNeutral: s.enemyArchonStarts.add(b.loc)
  if s.enemyArchonStarts.len > 0:
    s.rally = s.enemyArchonStarts[0]
  elif s.ownArchonStarts.len > 0:
    s.rally = s.ownArchonStarts[0]

func nearestOf*(l: Loc, points: seq[Loc]): Loc =
  result = l
  var best = -1'f32
  for p in points:
    let d = distanceSquaredTo(l, p)
    if best < 0'f32 or d < best:
      best = d
      result = p

func mirrorOf*(s: Side, l: Loc): Loc =
  ## The faction's own mirror, derived from the two public archon rosters:
  ## the translation that carries our nearest start onto their nearest one.
  ## Every 2017 board is symmetric by reflection or rotation, so this is
  ## enough to aim a wave at "the mirror of my own base" without a scout.
  if s.ownArchonStarts.len == 0 or s.enemyArchonStarts.len == 0:
    return l
  let a = nearestOf(l, s.ownArchonStarts)
  let b = nearestOf(a, s.enemyArchonStarts)
  loc(l.x + (b.x - a.x), l.y + (b.y - a.y))

func homeArchon*(s: Side, l: Loc): Loc = nearestOf(l, s.ownArchonStarts)

func enemyBase*(s: Side, l: Loc): Loc = nearestOf(l, s.enemyArchonStarts)

# ---------------------------------------------------------------------------
#  Navigation -- the licensed probe plus a continuous-space wall-follow
# ---------------------------------------------------------------------------

proc tryMove*(w: World, r: Robot, dir: Dir, dist = -1'f32): bool
    {.discardable.} =
  ## **A PORT OF `examplefuncsplayer`'s `tryMove`** (AGPL-3.0,
  ## `RobotPlayer.java:215-244`): try the intended direction, then +-20, +-40
  ## and +-60 degrees, and move into the first one that is legal. Each
  ## direction evaluated costs one credit.
  let d = (if dist < 0'f32: strideRadius(r.kind) else: dist)
  if r.hasMoved(): return false
  for angle in ProbeAngles:
    if not r.chargeFor(1): return false
    let candidate = (if angle == 0'f32: dir
                     elif angle > 0'f32: dir.rotateLeftDegrees(angle)
                     else: dir.rotateRightDegrees(-angle))
    if w.canMove(r, candidate, d):
      return w.move(r, candidate, d)
  false

proc walkTowards*(w: World, r: Robot, target: Loc): bool {.discardable.} =
  ## The navigator: the licensed probe towards the target, and when all seven
  ## directions are blocked a CONTINUOUS-SPACE WALL-FOLLOW -- walk along the
  ## blocking body's tangent, at most twelve turns before giving up and
  ## re-planning. (A grid year would sidestep; in float space the tangent is
  ## the only thing that gets a radius-2 tank past a radius-10 tree.)
  if r.hasMoved(): return false
  if r.loc == target: return false
  let dir = directionTo(r.loc, target)
  if w.tryMove(r, dir):
    r.wallTurns = 0
    return true
  ## Blocked: pick the tangent that makes progress, and remember we are
  ## following a wall so the next turns keep the same hand.
  if r.wallTurns >= 12:
    r.wallTurns = 0
    return false
  inc r.wallTurns
  let hand = (if (r.id and 1) == 0: 1'f32 else: -1'f32)
  for step in [70'f32, 90'f32, 110'f32, 140'f32, 180'f32]:
    if not r.chargeFor(1): return false
    let tangent = (if hand > 0'f32: dir.rotateLeftDegrees(step)
                   else: dir.rotateRightDegrees(step))
    if w.canMove(r, tangent):
      return w.move(r, tangent)
  false

proc walkAwayFrom*(w: World, r: Robot, threat: Loc, keepNear: Loc,
                   leash: float32): bool {.discardable.} =
  ## Retreat, but on a leash: an archon that runs off the board cannot hire.
  if r.hasMoved(): return false
  let away = directionTo(threat, r.loc)
  let target = addDist(r.loc, away, strideRadius(r.kind))
  if distanceTo(target, keepNear) <= leash and w.canMoveTo(r, target):
    return w.moveTo(r, target)
  w.tryMove(r, away)

# ---------------------------------------------------------------------------
#  Small shared helpers
# ---------------------------------------------------------------------------

func slotKey*(l: Loc): int =
  ## A farm slot's identity: its centre quantised to half a unit, so two
  ## gardeners cannot claim the same circle and the claim survives the
  ## gardener walking about.
  int(floor(float(l.x) * 2.0)) * 100000 + int(floor(float(l.y) * 2.0))

proc claimSlot*(s: Side, l: Loc, robotId: int): bool =
  let key = slotKey(l)
  let holder = s.claims.getOrDefault(key, 0)
  if holder != 0 and holder != robotId: return false
  s.claims[key] = robotId
  true

proc releaseClaims*(s: Side, robotId: int) =
  var doomed: seq[int]
  for key, holder in s.claims:
    if holder == robotId: doomed.add(key)
  for key in doomed: s.claims.del(key)

proc beginRound*(w: World, s: Side) =
  ## Once a round, before any of the side's robots act: refresh the ledger
  ## and forget claims whose gardener is dead.
  w.learnStarts(s)
  if s.committedRound != w.currentRound:
    s.committed = 0'f32
    s.committedRound = w.currentRound
  var doomed: seq[int]
  for key, holder in s.claims:
    if not w.robots.hasKey(holder): doomed.add(key)
  for key in doomed: s.claims.del(key)

func uncommitted*(w: World, s: Side): float32 =
  ## What is left of the side's bullets after this round's promises.
  w.bulletSupplyOf(s.team) - s.committed

proc commit*(s: Side, amount: float32) =
  s.committed = s.committed + amount

func ownStructuresNear*(w: World, s: Side, l: Loc, radius: float32): int =
  ## Archons, gardeners and own bullet trees within `radius` -- what
  ## `defend_radius` is measured against. Uncharged: it reads the side's own
  ## memory rather than the world's index... except it does read the index,
  ## so every caller charges for it.
  for c in w.robotIndex.withinRadius(l, radius):
    let other = w.robots.getOrDefault(int(c.id))
    if other != nil and other.team == s.team and
        (other.kind == rtArchon or other.kind == rtGardener):
      inc result
  for c in w.treeIndex.withinRadius(l, radius):
    let tr = w.trees.getOrDefault(int(c.id))
    if tr != nil and tr.team == s.team:
      inc result
