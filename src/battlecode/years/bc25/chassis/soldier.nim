## `soldier.nim` — the unit that actually colours the map.
##
## Behaviour ported from `erikji/battlecode25` `src/SPAARK/` (AGPL-3.0, head
## `63165da`): the ruin claim table, the mark-then-fill loop (which is exactly
## the loop the upstream example bot uses and the one SPAARK optimises), and
## the FRONTIER-CONNECTIVITY painting rule — paint the bare or enemy tile that
## maximises the count of own-paint neighbours, which is what makes a
## connected blob rather than confetti. Connectivity is not decoration: a
## robot->tower message needs an unbroken path of own paint, so the blob IS
## the clan's telephone line.
##
## Priority, and every branch of it paints or builds something:
##   1. refill when below `paint_reserve_floor`
##   2. finish a claimed ruin: mark it, fill the pattern, complete it
##   3. claim the nearest unclaimed ruin inside `ruin_claim_radius`
##      (a choke ruin first when `defense_tower_chokes` has opened)
##   4. lay the 25 tiles of a funded Special Resource Pattern and complete it
##   5. otherwise paint the frontier

import kit, econ, siege

export kit, econ, siege

proc withdrawFrom*(w: World, side: Side, r: Robot, towerLoc: Loc): bool
    {.discardable.} =
  ## A NEGATIVE transfer is the only legal withdraw and it is legal only FROM
  ## A TOWER. The cooldown is charged from the POST-transfer stash, so a
  ## robot that tops itself up pays the fast cooldown, not the slow one.
  let tower = w.getRobot(towerLoc)
  if tower == nil or not tower.kind.isTowerType(): return false
  if tower.team != side.team or tower.paint <= 0: return false
  let want = min(UnitSpecs[r.kind].paintCapacity - r.paint, tower.paint)
  if want <= 0: return false
  if not w.canTransferPaint(r, towerLoc, -want): return false
  w.doTransferPaint(r, towerLoc, -want)
  true

proc tryRefill*(w: World, side: Side, r: Robot): bool =
  ## Walk to the nearest friendly tower holding paint and drink. Returns true
  ## when the turn was spent on it.
  if not needsRefill(side, r): return false
  let towerLoc = nearestFriendlyTower(w, side, r, needPaint = true)
  if towerLoc.x < 0: return false
  if r.loc.distanceSquaredTo(towerLoc) <= PaintTransferRadiusSquared:
    return w.withdrawFrom(side, r, towerLoc)
  w.stepToward(side, r, towerLoc)
  ## Still worth painting under ourselves on the way home if we can.
  if r.isActionReady() and r.kind == utSoldier and
      not paintIsTeam(w.getPaint(r.loc), side.team) and
      w.canAttackRobot(r, r.loc):
    w.doAttackRobot(r, r.loc)
  true

# ---------------------------------------------------------------------------
#  Ruins
# ---------------------------------------------------------------------------

proc srpSoldier*(side: Side, r: Robot): bool =
  ## Which soldiers are on resource-pattern duty. `srp_priority` is the
  ## percentage of chip INCOME reserved for patterns, and the soldier-turns
  ## that lay the 25 tiles are the other half of that reservation — so the
  ## same knob picks the share of soldiers, deterministically by robot id.
  ## At 0 no soldier is ever assigned, which is the knob's own "never".
  side.doctrine.srpPriority > 0 and
    (r.id mod 100) < max(20, side.doctrine.srpPriority)

proc claimTarget*(w: World, side: Side, r: Robot): bool =
  ## Claim the nearest unclaimed, tower-free ruin inside `ruin_claim_radius`.
  ## A choke ruin wins outright when `defense_tower_chokes` has opened, which
  ## is what gives that knob its teeth.
  ##
  ## A soldier on resource-pattern duty NEVER takes a ruin claim while the
  ## clan is still funding a pattern: with four soldiers alive and four ruins
  ## in reach, a chassis that let them claim would never lay a single pattern
  ## and `srp_priority` would be a knob with no teeth at all.
  if r.hasClaim: return true
  if srpSoldier(side, r) and not side.srpDone and srpBudget(w, side):
    return false
  let chokeRuin = chokePlan(w, side, r)
  if chokeRuin.x >= 0 and not side.claims.hasKey(w.idx(chokeRuin)):
    r.claimed = chokeRuin
    r.claimedKind = tkDefense
    r.hasClaim = true
    side.claims[w.idx(chokeRuin)] = tkDefense
    side.claimOwner[w.idx(chokeRuin)] = r.id
    return true
  ## THE REMEMBERED RUIN LIST, not the sense sweep: a soldier walks to a ruin
  ## it once saw rather than waiting to bump into one, which is the single
  ## biggest difference between a clan that builds towers and one that paints
  ## in circles.
  ##
  ## TWO PASSES, and the second one is what makes the tower economy work at
  ## all. A pattern is 24 tiles and a soldier paints one a turn, so a lone
  ## soldier needs twenty-five undisturbed turns to raise a tower and rarely
  ## lives that long. The first pass takes an unclaimed ruin; the second
  ## JOINS a ruin another soldier has already claimed, so two or three
  ## soldiers finish together what one of them could not. `side.claims` still
  ## fixes the tower KIND, so the joiners paint the same picture.
  let radius = claimRadiusSquared(side, w.currentRound)
  var best = high(int)
  var pick = loc(-1, -1)
  var pickKind = tkMoney
  for pass in 0 .. 1:
    for l in side.knownRuins:
      if not r.spend(1): break
      let d = l.distanceSquaredTo(r.loc)
      if d > radius: continue
      if d >= best: continue
      if w.hasTower(l): continue
      let claimed = side.claims.hasKey(w.idx(l))
      if pass == 0 and claimed: continue
      if pass == 1 and not claimed: continue
      if not w.isValidPatternCenter(l, true): continue
      ## A tower pattern painted over one of our own live resource patterns
      ## would break it: same tiles, different picture.
      if overlapsProtected(side, l, 4): continue
      best = d
      pick = l
      pickKind = if claimed: side.claims[w.idx(l)] else: towerKindFor(w, side)
    if pick.x >= 0: break
  if pick.x < 0: return false
  let tile = w.idx(pick)
  let fresh = not side.claims.hasKey(tile)
  r.claimed = pick
  r.claimedKind = pickKind
  r.hasClaim = true
  side.claims[tile] = pickKind
  side.claimOwner[tile] = r.id
  if fresh:
    commitTowerKind(w, side)
    if side.homeTowers.len > 0:
      w.stats.claimDistanceSum[ord(side.team)] +=
        chebyshev(pick, side.homeTowers[0])
      w.stats.claimDistanceCount[ord(side.team)] += 1
  true

proc dropClaim(side: Side, w: World, r: Robot) =
  if not r.hasClaim: return
  let tile = w.idx(r.claimed)
  if side.claimOwner.getOrDefault(tile, -1) == r.id:
    side.claims.del(tile)
    side.claimOwner.del(tile)
  r.hasClaim = false

proc patternGap(w: World, side: Side, r: Robot, kind: PatternKind,
                centre: Loc, skipCentre: bool): Loc =
  ## The FIRST tile of the 5x5, in engine scan order, whose colour is wrong
  ## and which this clan could legally recolour. `(-1, -1)` means the pattern
  ## is as good as a soldier alone can make it — either finished, or blocked
  ## by enemy paint that needs a mopper or a splasher.
  result = loc(-1, -1)
  for ddx in LoOffset .. HiOffset:
    for ddy in LoOffset .. HiOffset:
      if skipCentre and ddx == 0 and ddy == 0: continue
      if not r.spend(1): return loc(-1, -1)
      let l = centre.translate(ddx, ddy)
      if not w.onTheMap(l): continue
      if not w.isPaintable(l): continue
      let want = wantedPaint(kind, ddx, ddy, side.team)
      let have = w.getPaint(l)
      if have == want: continue
      if hasPaintTeam(have) and teamFromPaint(have) != side.team: continue
      return l

proc fillPattern(w: World, side: Side, r: Robot, kind: PatternKind,
                 centre: Loc, skipCentre: bool): bool =
  ## Paint the first wrong tile of the 5x5 — WALKING TO IT WHEN IT IS OUT OF
  ## RANGE. A soldier parked beside a ruin can only reach tiles within
  ## r2 <= 9 of ITSELF, and the far corner of a 5x5 measured from one tile off
  ## the centre is 18 away, so a soldier that never moved could never finish a
  ## pattern and would drop the claim and start again somewhere else forever.
  ## Returns true when the turn was spent on the pattern.
  let gap = patternGap(w, side, r, kind, centre, skipCentre)
  if gap.x < 0: return false
  let ddx = gap.x - centre.x
  let ddy = gap.y - centre.y
  let want = wantedPaint(kind, ddx, ddy, side.team)
  if r.isActionReady() and w.canAttackRobot(r, gap):
    w.doAttackRobot(r, gap, want == secondaryPaint(side.team))
    return true
  w.stepToward(side, r, gap)
  true

proc workClaim*(w: World, side: Side, r: Robot): bool =
  ## Mark the pattern, fill it, complete it. Returns true when the turn was
  ## spent on the claim.
  ##
  ## THE ORDER HERE IS THE WHOLE TOWER ECONOMY. A soldier standing beside a
  ## ruin can reach tiles within r2 <= 9 OF ITSELF, and the far corner of the
  ## ruin's 5x5 measured from one tile off the centre is 13 to 18 away — so it
  ## MUST walk around the ruin to finish the pattern. A chassis that walked
  ## back to the ruin every turn before looking for the next wrong tile would
  ## oscillate forever and never build a tower; that is exactly what the first
  ## draft of this file did, and it built between zero and one tower a game.
  if not r.hasClaim: return false
  let centre = r.claimed
  if w.hasTower(centre) or not w.hasRuin(centre):
    dropClaim(side, w, r)
    return false

  ## Too far to see it: walk, and paint what is under us on the way, which is
  ## free coverage and stops the neutral-territory paint bill.
  if r.loc.distanceSquaredTo(centre) > VisionRadiusSquared:
    w.stepToward(side, r, centre)
    if r.isActionReady() and
        not paintIsTeam(w.getPaint(r.loc), side.team) and
        w.canAttackRobot(r, r.loc):
      w.doAttackRobot(r, r.loc,
        w.getMarker(side.team, r.loc) == MarkerSecondary)
    return true

  ## Mark once: if the tile one step off the centre carries no marker, the
  ## pattern has not been marked yet.
  if w.getMarker(side.team, centre.translate(1, 0)) == MarkerNone and
      w.canMarkTowerPattern(r, r.claimedKind, centre):
    w.doMarkTowerPattern(r, r.claimedKind, centre)

  if w.canCompleteTowerPattern(r, r.claimedKind, centre, r) and
      towerBudgetOk(w, side):
    w.doCompleteTowerPattern(r, r.claimedKind, centre)
    dropClaim(side, w, r)
    return true

  let kind = patternKindFor(r.claimedKind)
  let gap = patternGap(w, side, r, kind, centre, skipCentre = true)
  if gap.x >= 0:
    let want = wantedPaint(kind, gap.x - centre.x, gap.y - centre.y,
                           side.team)
    if r.isActionReady() and w.canAttackRobot(r, gap):
      w.doAttackRobot(r, gap, want == secondaryPaint(side.team))
    else:
      w.stepToward(side, r, gap)
    return true

  ## No gap: the pattern is exact. Either the clan cannot afford the 1000
  ## chips yet — hold the claim and stand by the ruin — or an enemy-painted
  ## tile inside it needs a mopper or a splasher, in which case the claim is
  ## released so the clan does not deadlock on it.
  if w.checkTowerPattern(side.team, centre, towerTypeFor(r.claimedKind), r):
    if r.loc.distanceSquaredTo(centre) > BuildTowerRadiusSquared:
      w.stepToward(side, r, centre)
    return true
  dropClaim(side, w, r)
  false

# ---------------------------------------------------------------------------
#  Special Resource Patterns
# ---------------------------------------------------------------------------

proc workSrp*(w: World, side: Side, r: Robot): bool =
  ## Lay the 25 tiles of a funded pattern and complete it. `srp_priority`
  ## decides whether one is ever funded; nothing else in the chassis competes
  ## for the soldier-turns it takes.
  ##
  ## THE SOLDIER STANDS ON THE CENTRE. A resource pattern has no ruin at its
  ## middle, and the centre is the ONLY tile from which all 25 are inside a
  ## soldier's r2 <= 9 action radius (the corners are 8 away from it and 13 to
  ## 18 away from anywhere else).
  if not srpBudget(w, side): return false
  if not side.srpFunded:
    let centre = pickSrpCentre(w, side, r)
    if centre.x < 0: return false
    side.srpCentre = centre
    side.srpFunded = true
  let centre = side.srpCentre
  if centre.x < 0: return false

  if w.canCompleteResourcePattern(r, centre, r):
    w.doCompleteResourcePattern(r, centre)
    side.srpFunded = false
    side.srpDone = true
    side.protectedSrp = centre
    side.protected.add(centre)
    side.srpCentre = loc(-1, -1)
    return true

  if not (r.loc == centre):
    if w.stepToward(side, r, centre):
      ## Paint what is under us on the way; the marker says which colour.
      if r.isActionReady() and
          not paintIsTeam(w.getPaint(r.loc), side.team) and
          w.canAttackRobot(r, r.loc):
        w.doAttackRobot(r, r.loc,
          w.getMarker(side.team, r.loc) == MarkerSecondary)
      return true
    ## Blocked (an ally is standing on the centre): keep filling from here.

  if w.getMarker(side.team, centre) == MarkerNone and
      w.canMarkResourcePattern(r, centre):
    w.doMarkResourcePattern(r, centre)

  fillPattern(w, side, r, pkResource, centre, skipCentre = false)

# ---------------------------------------------------------------------------
#  The frontier
# ---------------------------------------------------------------------------

proc paintFrontier*(w: World, side: Side, r: Robot): bool
    {.discardable.} =
  ## The tile under the soldier first — standing on own paint is free and
  ## standing on anything else costs 1 or 2 a turn. Otherwise the bare or
  ## enemy tile within r2 <= 9 that maximises the count of OWN-PAINT
  ## NEIGHBOURS, which is what grows one connected blob instead of confetti.
  if not r.isActionReady(): return false
  ## A tile carrying OUR OWN MARKER is part of a pattern somebody is laying,
  ## so paint the colour the marker asks for rather than the primary. Without
  ## this the frontier painter quietly breaks the tower patterns its own clan
  ## is halfway through — the tile is bare, so it looks like free coverage.
  let here = w.getPaint(r.loc)
  let mark = w.getMarker(side.team, r.loc)
  if not paintIsTeam(here, side.team) and w.canAttackRobot(r, r.loc):
    w.doAttackRobot(r, r.loc, mark == MarkerSecondary)
    return true
  var best = low(int)
  var pick = loc(-1, -1)
  for l in w.locationsWithinRadiusSquared(
      r.loc, UnitSpecs[utSoldier].actionRadiusSquared):
    if not r.spend(1): break
    if not w.isPaintable(l): continue
    let colour = w.getPaint(l)
    if paintIsTeam(colour, side.team): continue
    if hasPaintTeam(colour): continue   ## a soldier cannot overpaint enemies
    var score = 0
    for d in MoveDirs:
      let n = l + d
      if w.onTheMap(n) and paintIsTeam(w.getPaint(n), side.team):
        score += 3
    score -= l.distanceSquaredTo(r.loc)
    ## An enemy TOWER in range is worth more than any tile: 50 damage a turn
    ## and the tower cannot run.
    if score > best:
      best = score
      pick = l
  if pick.x < 0: return false
  if not w.canAttackRobot(r, pick): return false
  w.doAttackRobot(r, pick, w.getMarker(side.team, pick) == MarkerSecondary)
  true

proc strikeTower*(w: World, side: Side, r: Robot): bool =
  ## A soldier beside an enemy tower hits it for 50 rather than painting: a
  ## tower that falls takes its mining, its spawning and its two free shots
  ## with it.
  if not r.isActionReady(): return false
  for l in w.locationsWithinRadiusSquared(
      r.loc, UnitSpecs[utSoldier].actionRadiusSquared):
    if not r.spend(1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team == side.team: continue
    if not bot.kind.isTowerType(): continue
    if not w.canAttackRobot(r, l): continue
    w.doAttackRobot(r, l)
    return true
  false

proc runSoldier*(w: World, side: Side, r: Robot) =
  observeRuins(w, side, r)
  if tryRefill(w, side, r): return
  ## A soldier on SRP duty lays the pattern BEFORE it looks for a ruin: a
  ## resource pattern nobody is assigned to is a resource pattern that never
  ## gets laid, which is exactly what an unfunded knob is supposed to mean and
  ## a funded one is not.
  if srpSoldier(side, r) and not r.hasClaim and workSrp(w, side, r): return
  if workClaim(w, side, r): return
  ## Only a soldier with nothing structural to do hammers a tower: 50 damage a
  ## turn is worth having, but not at the price of never building anything.
  if strikeTower(w, side, r): return
  if claimTarget(w, side, r) and workClaim(w, side, r): return
  if workSrp(w, side, r): return
  ## Nothing structural to do: walk the frontier and colour it.
  w.stepToward(side, r, frontierFor(w, side))
  discard paintFrontier(w, side, r)
