## `bulwark`'s shared per-side memory, its navigator and the `DecisionOps`
## charging — the file every other chassis module imports.
##
## **PROVENANCE, stated here because it is a licensing fact and not a
## courtesy.** `TheDuck314/battlecode2016` and `bshimanuki/battlecode2016`
## CARRY NO LICENCE. Neither repository was cloned, read, copied, vendored,
## compiled or translated by this run, and neither contributes a single line
## to it. Every line here is Nim written against this coworld's own `World`
## from the ENGINE's own mechanics and from the three archetypes the run's
## idea text itself names — turret turtle, aggressive soldier/viper, scout
## zombie-pull. `NOTICE` and `docs/RULES-BC16.md` state the same thing.
##
## What the side remembers, and why each piece is cheap:
##
## * **the census**, refreshed once a round before the exec sweep, so every
##   robot this round reads the same numbers (and two archons cannot both
##   think they are the only one);
## * **the den roster**, read from the map. The whole-map zombie schedule is
##   PUBLIC in the real game (`getZombieSpawnSchedule()` is free to every
##   robot) and this coworld's own observation hands both cogs the den
##   locations, so the chassis reads them rather than rediscovering them —
##   recorded in `docs/RULES-BC16.md` as a CHASSIS convenience, never a rule:
##   the sim's fog is untouched and no RULE reads this roster;
## * **the enemy archon estimate**, seeded from
##   `getInitialArchonLocations(enemy)` (public from round 0) and refined by
##   sightings;
## * **the parts ledger**, so two archons cannot promise the same 30 parts;
## * **the navigator**: a cost-aware greedy step with a six-square no-repeat
##   history, weighted by the REAL cost of the step
##   (`movementDelay x (1.4 if diagonal) x (2.0 if destination rubble >= 50)`,
##   impassable at 100 unless the mover ignores rubble). It is deliberately
##   NOT a full BFS: at 3000 rounds and a budgeted 300 robots on the board a
##   per-robot BFS is the difference between a 15-second game and a
##   150-second one, and `tests/test_bc16_perf.nim` is the gate that decides
##   that. Every direction evaluated is charged 1 `DecisionOps`.

import ../world, ../signals, ../knobs

export world, knobs

type
  Side* = ref object
    team*: Team
    doctrine*: Doctrine16
    ## --- census, refreshed once a round ---
    archons*: seq[Loc]
    counts*: array[RobotType, int]
    attackers*: int
    ready*: bool
    ## --- memory ---
    enemyArchons*: seq[Loc]
    partsCommitted*: float64
    denCommitted*: bool
    denTarget*: Loc
    hasDenTarget*: bool
    strikeGroup*: seq[int]
      ## THE STANDING STRIKE GROUP: the ids of the attackers committed to
      ## breaking `denTarget`, re-formed once a round from the attackers
      ## nearest the den. A den is 2000 HP and a SOLDIER deals 4 at
      ## attackDelay 2 — TWO a round — so a group has to be at least
      ## `DenStrikeGroup` strong to break one inside a few hundred rounds, and
      ## it has to be a NAMED SUBSET rather than "everyone" or the defensive
      ## floor (which answers every hostile inside r2 64 of an archon, and the
      ## horde arrives on a schedule) reclaims the whole army every round and
      ## the den is never touched. A member of this group is the ONE unit
      ## class that outranks the defensive floor; every attacker outside it
      ## still holds the ring. Measured: without the named subset, the
      ## all-defaults mirror killed 6 dens across the six `small` maps and
      ## reached round 3000 once; with it, the table in
      ## `tests/test_bc16_survival.nim`'s header.
    turretSites*: seq[Loc]
    claimedNeutrals*: seq[Loc]
    frontier*: Loc
    partsTargets*: seq[Loc]
      ## THE REMEMBERED MAP's parts half: the squares that still hold parts,
      ## refreshed every `PartsRefreshRounds` rounds ONCE PER SIDE rather than
      ## once per archon, because a whole-map scan per archon per round is the
      ## difference between 0.5 ms and 5 ms a round. Only an ARCHON collects
      ## parts and it takes the WHOLE square, so this list shrinks
      ## monotonically as the map is eaten.
    partsRefreshedAt*: int
    threats*: seq[Loc]
      ## THE DEFENSIVE FLOOR of the anti-inert rule, and it is why a faction
      ## answers what is coming at it rather than what it planned for: every
      ## hostile robot inside r2 64 of one of our own archons, collected once
      ## a round. r2 64 is inside the collective sight of an archon (r2 35)
      ## plus the guard screen standing in front of it, so it is what the
      ## faction really knows and not a fog violation — the sim's fog is
      ## untouched and no RULE reads this list.

const PartsRefreshRounds* = 40

proc newSide*(team: Team, doctrine: Doctrine16): Side =
  Side(team: team, doctrine: doctrine, frontier: loc(-1, -1),
       denTarget: loc(-1, -1), partsRefreshedAt: -1000)

# ---------------------------------------------------------------------------
#  The census
# ---------------------------------------------------------------------------

proc refreshCensus*(w: World, s: Side) =
  ## Once a round, before the exec sweep.
  s.archons.setLen(0)
  for k in RobotType: s.counts[k] = 0
  for id in w.execOrder:
    if not w.robotsById.hasKey(id): continue
    let r = w.robotsById[id]
    if r.team != s.team: continue
    s.counts[r.kind] += 1
    if r.kind == rtArchon: s.archons.add(r.loc)
  s.attackers = s.counts[rtSoldier] + s.counts[rtGuard] + s.counts[rtViper] +
    s.counts[rtTurret] + s.counts[rtTtm]
  s.partsCommitted = 0.0
  if s.enemyArchons.len == 0:
    s.enemyArchons = w.initialArchonLocations(s.team.opponent())
  ## The frontier is the midpoint between our archon centroid and theirs: the
  ## direction the war is in, and the square a new build wants to face.
  if s.archons.len > 0 and s.enemyArchons.len > 0:
    var ax, ay, bx, by = 0
    for l in s.archons:
      ax += l.x
      ay += l.y
    for l in s.enemyArchons:
      bx += l.x
      by += l.y
    ax = ax div s.archons.len
    ay = ay div s.archons.len
    bx = bx div s.enemyArchons.len
    by = by div s.enemyArchons.len
    s.frontier = loc((ax + bx) div 2, (ay + by) div 2)
  elif s.archons.len > 0:
    s.frontier = s.archons[0]
  ## The threat list: what is close enough to our archons to matter.
  s.threats.setLen(0)
  if s.archons.len > 0:
    for id in w.execOrder:
      if not w.robotsById.hasKey(id): continue
      let r = w.robotsById[id]
      if r.team == s.team or r.team == teamNeutral: continue
      if r.kind == rtZombieden: continue
      for a in s.archons:
        if a.distanceSquaredTo(r.loc) <= 64:
          s.threats.add(r.loc)
          break
  ## The parts memory, refreshed on a fixed cadence.
  if w.currentRound - s.partsRefreshedAt >= PartsRefreshRounds:
    s.partsRefreshedAt = w.currentRound
    s.partsTargets.setLen(0)
    for i in 0 ..< w.partsAt.len:
      if w.partsAt[i] > 0.0:
        s.partsTargets.add(w.indexToLoc(i))
  s.ready = true

proc nearestThreat*(s: Side, from0: Loc): Loc =
  result = loc(-1, -1)
  var best = high(int)
  for l in s.threats:
    let d = l.distanceSquaredTo(from0)
    if d < best:
      best = d
      result = l

proc nearestPartsTarget*(w: World, s: Side, from0: Loc): Loc =
  ## The nearest remembered parts square that still holds parts. A square
  ## someone already ate is skipped in place, so the list self-cleans.
  result = loc(-1, -1)
  var best = high(int)
  for l in s.partsTargets:
    if w.getParts(l) <= 0.0: continue
    let d = l.distanceSquaredTo(from0)
    if d < best:
      best = d
      result = l

func nearestArchon*(s: Side, from0: Loc): Loc =
  ## The nearest friendly archon — the only healing in the game.
  result = loc(-1, -1)
  var best = high(int)
  for l in s.archons:
    let d = l.distanceSquaredTo(from0)
    if d < best:
      best = d
      result = l

func nearestEnemyArchon*(s: Side, from0: Loc): Loc =
  result = loc(-1, -1)
  var best = high(int)
  for l in s.enemyArchons:
    let d = l.distanceSquaredTo(from0)
    if d < best:
      best = d
      result = l

func meanArchonDistance*(s: Side): float64 =
  ## The statistic `archon_spread` moves, and the one
  ## `tests/test_bc16_knobs.nim` reads.
  if s.archons.len < 2: return 0.0
  var total = 0.0
  var pairs = 0
  for i in 0 ..< s.archons.len:
    for j in i + 1 ..< s.archons.len:
      total += float64(s.archons[i].distanceSquaredTo(s.archons[j]))
      pairs += 1
  if pairs == 0: 0.0 else: total / float64(pairs)

# ---------------------------------------------------------------------------
#  Dens and neutrals, read from the map
# ---------------------------------------------------------------------------

iterator liveDens*(w: World): Robot =
  for id in w.execOrder:
    if not w.robotsById.hasKey(id): continue
    let r = w.robotsById[id]
    if r.kind == rtZombieden: yield r

proc denQueueRemaining*(w: World, den: Robot): int =
  ## How many zombies this den still owes over the rest of the game — the
  ## number `dens.nim schedule()` ranks by, and it is public information.
  if den.denIndex < 0: return 0
  for row in w.map.dens[den.denIndex].schedule:
    if row.round >= w.currentRound:
      for c in row.counts: result += c

func nearDenWithQueue*(w: World, l: Loc): bool =
  ## True when `l` is one of the eight squares around a den that still has a
  ## queue — the squares that take 10 damage a round. The chassis never walks
  ## its LAST archon into one of them, at any knob setting.
  for id in w.execOrder:
    if not w.robotsById.hasKey(id): continue
    let r = w.robotsById[id]
    if r.kind != rtZombieden: continue
    if r.loc.isAdjacentTo(l):
      for i in 0 .. 3:
        if r.denQueue[i] > 0: return true
      ## A den with an empty queue this instant may still fill it next round,
      ## so a scheduled wave inside twenty rounds counts too.
      if r.denIndex >= 0:
        for row in w.map.dens[r.denIndex].schedule:
          if row.round >= w.currentRound and
              row.round <= w.currentRound + 20:
            return true
  false

# ---------------------------------------------------------------------------
#  The navigator
# ---------------------------------------------------------------------------

func stepCost*(w: World, r: Robot, d: Dir): float64 =
  ## The REAL cost of one step: `movementDelay x factor1 x factor3`. This is
  ## what makes the navigator prefer a longer flat route to a shorter one
  ## through rubble 60, which is the whole point of `rubble_clear`.
  let dest = r.loc + d
  RobotSpecs[r.kind].movementDelay * moveFactor1(d) *
    moveFactor3(w.getRubble(dest), r.kind)

proc rememberStep(r: Robot, l: Loc) =
  r.noRepeat.add(l)
  if r.noRepeat.len > 6:
    r.noRepeat.delete(0)

func recentlyVisited(r: Robot, l: Loc): bool =
  for v in r.noRepeat:
    if v == l: return true
  false

proc stepToward*(w: World, r: Robot, target: Loc,
                 away = false): bool {.discardable.} =
  ## One cost-aware step toward (or away from) `target`, with the no-repeat
  ## history breaking oscillation. Charges 1 `DecisionOps` per direction
  ## evaluated and returns whether the robot moved.
  if not canMoveType(r.kind): return false
  if not r.d.isCoreReady(): return false
  if target.x < 0: return false
  var bestDir = dNone
  var bestScore = -1e18
  for d in MoveDirs:
    if not r.spend(1): break
    if not w.canMove(r, d): continue
    let dest = r.loc + d
    let before = float64(r.loc.distanceSquaredTo(target))
    let after = float64(dest.distanceSquaredTo(target))
    var gain = if away: after - before else: before - after
    ## Normalise the gain by the cost of the step, so a diagonal onto rubble
    ## 60 (core 5.6) is worth less than a cardinal on flat ground (core 2).
    let cost = w.stepCost(r, d)
    var score = gain / max(0.5, cost)
    if recentlyVisited(r, dest): score -= 6.0
    if score > bestScore:
      bestScore = score
      bestDir = d
  if bestDir == dNone:
    return false
  if bestScore <= 0.0:
    ## WALL-FOLLOW. A purely greedy step returns false here, and on this
    ## year's maps that is the difference between a working faction and a
    ## stuck one: `checkers` has 450 of its 900 squares at rubble 200 and
    ## `caverns` 1 078 of 1 892, so a unit whose every distance-reducing step
    ## is blocked has to be allowed a LATERAL one. The six-square no-repeat
    ## history is what bounds the oscillation that permits — it is why the
    ## history exists.
    var lateral = dNone
    var lateralScore = -1.0e18
    for d in MoveDirs:
      if not r.spend(1): break
      if not w.canMove(r, d): continue
      let dest = r.loc + d
      if recentlyVisited(r, dest): continue
      let score = -float64(dest.distanceSquaredTo(target)) -
        w.stepCost(r, d)
      if score > lateralScore:
        lateralScore = score
        lateral = d
    if lateral == dNone: return false
    rememberStep(r, r.loc)
    return w.doMove(r, lateral)
  rememberStep(r, r.loc)
  w.doMove(r, bestDir)

proc stepAnywhere*(w: World, r: Robot): bool {.discardable.} =
  ## The last resort: any legal step that is not one we just came from. Used
  ## when a unit is boxed in, so a faction can never deadlock itself into
  ## doing nothing.
  if not canMoveType(r.kind) or not r.d.isCoreReady(): return false
  for d in MoveDirs:
    if not r.spend(1): break
    if w.canMove(r, d) and not recentlyVisited(r, r.loc + d):
      rememberStep(r, r.loc)
      return w.doMove(r, d)
  false
