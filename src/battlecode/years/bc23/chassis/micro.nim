## `lemonade`'s launcher micro: the target priority, the strike group's
## destination and what it does when it starts losing.
##
## Behaviour ported from `awesomelemonade/Battlecode2023`
## `src/finalBot/LauncherMicro` (AGPL-3.0): attack the lowest-HP enemy inside
## r² ≤ 16, tiebreaking toward launchers, then destabilizers, then carriers
## holding an anchor, then carriers, then amplifiers, then boosters; PREFER A
## TARGET OUR 20 DAMAGE WILL KILL; keep the cooldown-adjusted stand-off
## distance when the enemy's group is bigger. `destabilizer_use` decides where
## the group lives and `retreat_on_launcher_loss` what it does when a member
## dies.

import ../world, kit

export kit

func targetRank(w: World, r: Robot): int =
  ## Lower is more valuable. A carrier holding an anchor outranks a plain
  ## carrier because killing it destroys the anchor as well.
  case r.kind
  of rtLauncher: 0
  of rtDestabilizer: 1
  of rtCarrier: (if r.totalAnchors > 0: 2 else: 3)
  of rtAmplifier: 4
  of rtBooster: 5
  of rtHeadquarters: 9

proc bestTarget*(w: World, side: Side, r: Robot): Loc =
  ## The square this robot should attack, or `(-1, -1)`.
  result = loc(-1, -1)
  var best = high(int)
  let damage =
    if r.kind == rtCarrier: carrierThrowDamage(r.weight)
    else: RobotSpecs[r.kind].damage
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[r.kind].actionRadiusSquared):
    if not r.spend(1): break
    if not w.onTheMap(l): continue
    let other = w.getRobot(l)
    if other == nil or other.team == r.team: continue
    if other.kind == rtHeadquarters: continue
    ## An attack needs NO VISION, so a launcher fires into a cloud.
    var score = targetRank(w, other) * 1000 + other.health
    if damage >= other.health:
      ## A kill is always the best answer; refusing a free kill is not a
      ## strategy.
      score -= 100_000
    if score < best:
      best = score
      result = l

proc strikeTarget*(w: World, side: Side, r: Robot): Loc =
  ## `commit()` — where the faction's strike group goes.
  case side.doctrine.destabilizerUse
  of duHold:
    ## Sit on our own wells and islands. Still fights whatever comes: `hold`
    ## is a posture, not idleness.
    var best = high(int)
    result = side.nearestHome(r.loc)
    for islandIdx in side.knownIslands:
      let isl = w.islands[islandIdx]
      if isl.tiles.len == 0: continue
      if not isl.isOwnedBy(side.team): continue
      let d = chebyshev(r.loc, isl.tiles[0])
      if d < best:
        best = d
        result = isl.tiles[0]
    for l in side.knownWells:
      let d = chebyshev(r.loc, l) + 4
      if d < best:
        best = d
        result = l
  of duDefend:
    ## Intercept anything sensed INSIDE OUR OWN HALF; otherwise hold a picket
    ## a third of the way out.
    ##
    ## The picket is a third of the way and not the midpoint, and the
    ## interception is gated on the sighting being on our side of the mirror,
    ## for a measured reason: with both defaults posted at the midpoint the
    ## two launcher groups met head-on every game, the faction that took its
    ## turn FIRST stepped into range first and was shot first, and the mirror
    ## snowballed to annihilation by round 150. `defend` that walks into the
    ## middle of the map is `siege` with a different name.
    let home = side.nearestHome(r.loc)
    let front = side.nearestEnemyHome(home)
    let picket = loc((home.x * 2 + front.x) div 3, (home.y * 2 + front.y) div 3)
    if side.lastSightingRound >= 0 and
        w.currentRound - side.lastSightingRound <= 40 and
        chebyshev(side.lastSighting, home) <=
          chebyshev(side.lastSighting, front):
      result = side.lastSighting
    else:
      result = picket
  of duSiege:
    result = side.nearestEnemyHome(r.loc)

proc updateStrikeCentre*(w: World, side: Side) =
  ## The centroid of our own launchers, refreshed once a round. `regroup`
  ## falls back to it; `escort` amplifiers follow it; the knob test measures
  ## its distance from home.
  var sx = 0
  var sy = 0
  var n = 0
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team != side.team or r.kind != rtLauncher: continue
    sx += r.loc.x
    sy += r.loc.y
    n += 1
  if n == 0:
    side.strikeRound = -1
    return
  side.strikeCentre = loc(sx div n, sy div n)
  side.strikeRound = w.currentRound
  if side.homeHqs.len > 0:
    let home = side.nearestHome(side.strikeCentre)
    w.stats.strikeDistanceSum[ord(side.team)] +=
      chebyshev(side.strikeCentre, home)
    w.stats.strikeDistanceCount[ord(side.team)] += 1

proc noteLosses*(w: World, side: Side) =
  ## `retreat()`'s trigger: a round in which the faction lost a launcher.
  if w.launchersLostThisRound[ord(side.team)] <= 0: return
  case side.doctrine.retreatOnLauncherLoss
  of rpNever: discard
  of rpRegroup: side.regroupUntil = w.currentRound + 25
  of rpHome: side.regroupUntil = w.currentRound + 60

func retreating*(w: World, side: Side): bool =
  side.doctrine.retreatOnLauncherLoss != rpNever and
    w.currentRound <= side.regroupUntil

proc retreatTarget*(w: World, side: Side, r: Robot): Loc =
  ## Where a retreating launcher goes. `home` prefers an ANCHORED ISLAND of
  ## ours, because an anchor heals 4 or 6 a round and it is the only healing
  ## in the game.
  case side.doctrine.retreatOnLauncherLoss
  of rpNever: result = r.loc
  of rpRegroup:
    result = (if side.strikeRound >= 0: side.strikeCentre
              else: side.nearestHome(r.loc))
  of rpHome:
    var best = high(int)
    result = side.nearestHome(r.loc)
    for islandIdx in side.knownIslands:
      let isl = w.islands[islandIdx]
      if isl.tiles.len == 0 or not isl.isOwnedBy(side.team): continue
      let d = chebyshev(r.loc, isl.tiles[0])
      if d < best:
        best = d
        result = isl.tiles[0]
