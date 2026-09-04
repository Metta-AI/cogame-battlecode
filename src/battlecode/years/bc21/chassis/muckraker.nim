## The muckraker — one influence, the longest sight on the board, and the only
## unit that can kill the enemy's economy.
##
##   * expose anything exposable within `r^2 <= 12`, preferring the
##     HIGHEST-INFLUENCE slanderer, which is the biggest buff;
##   * else roam per `flank_policy`;
##   * else park adjacent to a sensed enemy Center to deny it a build tile.
##
## `flank_policy`:
##   `screen_home`     — hold a ring at Chebyshev 5 around own Centers and
##                       expose anything that walks in.
##   `hunt_slanderers` — path to the nearest sensed or flag-reported enemy
##                       slanderer, else toward the nearest known enemy Center.
##   `flank_wide`      — California Roll's "muck flanking": route to the enemy
##                       Center along the map edge, entering from the far side,
##                       and sit on the enemy's slanderer ring rather than its
##                       politician wall.

import kit, pathing, ec

proc bestExposeTarget(w: World, side: Side, r: Robot): tuple[ok: bool, at: Loc] =
  var bestInfluence = -1
  for l in w.locationsWithinRadiusSquared(r.loc,
      RobotSpecs[rtMuckraker].actionRadiusSquared):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil: continue
    if bot.team == side.team or bot.team == teamNeutral: continue
    if bot.kind != rtSlanderer: continue
    if bot.influence > bestInfluence:
      bestInfluence = bot.influence
      result.ok = true
      result.at = l

proc edgeWaypoint(w: World, r: Robot, target: Loc): Loc =
  ## `flank_wide`: aim first at the map edge nearest to us on the axis the
  ## target is NOT on, then at the target. Two-leg routing, no state.
  let goLeft = r.loc.x <= target.x
  let x = if goLeft: 1 else: w.width - 2
  let y = clamp(target.y, 1, w.height - 2)
  if r.loc.distanceSquaredTo(loc(x, y)) <= 25: target
  else: loc(x, y)

proc runMuckraker*(w: World, side: Side, r: Robot) =
  observe(w, side, r)
  let brain = side.brainFor(r)
  brain.turnCount += 1

  if isReady(r):
    let target = bestExposeTarget(w, side, r)
    if target.ok:
      w.expose(r, target.at)
      setFlag(r, encodeFlag(fkSlandererSeen, target.at))
      return

  ## Where to go.
  var goal = w.mirrorTarget(side, r.loc)
  var said = fkSilent
  var saidAt = r.loc
  let (ok, note) = bestTarget(w, side, r.loc)
  if ok:
    said = if note.hostile: fkEnemyEcHere else: fkNeutralEcHere
    saidAt = note.loc

  case side.doctrine.flankPolicy
  of fpScreenHome:
    if side.ownCenters.len > 0:
      let home = side.nearestOwnCenter(r.loc)
      let ring = 5
      if chebyshev(r.loc, home) < ring:
        goal = loc(clamp(home.x + (r.loc.x - home.x) * 2, 0, w.width - 1),
                   clamp(home.y + (r.loc.y - home.y) * 2, 0, w.height - 1))
        if goal == home:
          goal = loc(clamp(home.x + ring, 0, w.width - 1), home.y)
      elif chebyshev(r.loc, home) > ring + 2:
        goal = home
      else:
        goal = r.loc
  of fpHuntSlanderers:
    var bestD = high(int)
    for sighting in side.slandererSightings:
      if w.currentRound - sighting.round > 60: continue
      let dist = r.loc.distanceSquaredTo(sighting.loc)
      if dist < bestD:
        bestD = dist
        goal = sighting.loc
        said = fkSlandererSeen
        saidAt = sighting.loc
    if bestD == high(int):
      ## No slanderer seen lately: walk at the enemy's Centers, where they
      ## live. NEVER at a neutral Center — that is the politician's errand.
      let hostile = side.nearestHostileCenter(r.loc)
      goal = if hostile.ok: hostile.at else: w.mirrorTarget(side, r.loc)
  of fpFlankWide:
    let hostile = side.nearestHostileCenter(r.loc)
    let enemy = if hostile.ok: hostile.at else: w.mirrorTarget(side, r.loc)
    goal = edgeWaypoint(w, r, enemy)

  if goal == r.loc:
    ## Standing on station: deny a build tile if we are next to a hostile
    ## Center, otherwise hold.
    discard
  else:
    moveToward(w, side, r, goal)

  setFlag(r, encodeFlag(said, saidAt,
    (if said in {fkEnemyEcHere, fkNeutralEcHere}:
       influenceHint(max(0, note.influence)) else: 0)))
