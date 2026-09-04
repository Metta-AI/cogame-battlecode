## The politician — the walking bomb, and the only unit that takes a Center.
##
##   * if a capturable Center is inside `r^2 <= 9`, size the radius so the
##     Center is included and empower;
##   * else evaluate all four legal radii {1, 2, 4, 9} with the SCAN-ORDER
##     robot set the sim will actually use, score each by `convert_over_kill`,
##     and empower if the best score clears `empower_threshold`;
##   * else path to the current target (`expansion`-selected) or, if none is
##     known, along the map's symmetry axis toward the mirrored position of an
##     own Center — which on a symmetric map is always an enemy Center.
##
## A politician adjacent to a capturable Center ALWAYS empowers regardless of
## the threshold, and a politician about to die to a sensed enemy politician
## empowers rather than waste itself.

import kit, pathing, ec

type
  RadiusScore = object
    radius: int
    convertible: int     ## enemy Centers and enemy politicians — they come back
    killable: int        ## everything else hostile
    friendlyWaste: int
    takesCenter: bool

proc scoreRadius(w: World, side: Side, r: Robot, radius: int,
                 buff: float64): RadiusScore =
  result.radius = radius
  var bots: seq[Robot]
  for l in w.locationsWithinRadiusSquared(r.loc, radius):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot != nil: bots.add(bot)
  let numBots = bots.len - 1
  if numBots <= 0: return
  let give = float64(r.conviction) - float64(EmpowerTax)
  if give <= 0: return
  let per = give / float64(numBots)
  for bot in bots:
    if bot.id == r.id: continue
    if bot.team == side.team:
      if bot.kind == rtEnlightenmentCenter:
        discard          # feeding an own Center is not waste, but is not damage
      else:
        result.friendlyWaste += int(per * buff)
      continue
    let landed = int(per * buff)
    if bot.kind == rtEnlightenmentCenter:
      result.convertible += min(landed, bot.conviction)
      if landed > bot.conviction:
        result.takesCenter = true
    elif bot.kind == rtPolitician:
      result.convertible += min(landed, bot.conviction)
    else:
      result.killable += min(landed, bot.conviction)

proc value(s: RadiusScore, convertOverKill: bool): int =
  ## `convert_over_kill` decides what a speech is FOR. When true the radius
  ## search maximises CONVERTIBLE conviction — enemy Centers and enemy
  ## politicians, which come back as your robots — and breaks ties away from
  ## radii that waste conviction on friendly units. When false it maximises
  ## total enemy conviction removed, which favours popping slanderer and
  ## muckraker clusters.
  if convertOverKill:
    4 * s.convertible + s.killable div 2 - s.friendlyWaste
  else:
    s.convertible div 2 + 2 * s.killable

proc bestRadius(w: World, side: Side, r: Robot):
    tuple[radius: int, score: RadiusScore] =
  let buff = w.getBuff(side.team)
  result.radius = 0
  var best = -1
  for radius in EmpowerRadii:
    if r.opsLeft <= 0: break
    let s = scoreRadius(w, side, r, radius, buff)
    let v = s.value(side.doctrine.convertOverKill)
    if s.takesCenter and not result.score.takesCenter:
      best = v
      result.radius = radius
      result.score = s
    elif s.takesCenter == result.score.takesCenter and v > best:
      best = v
      result.radius = radius
      result.score = s

proc dyingToEnemy(w: World, side: Side, r: Robot): bool =
  ## A sensed enemy politician whose usable conviction would kill this one
  ## outright: better to speak now than be converted.
  for l in w.locationsWithinRadiusSquared(r.loc, 9):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil: continue
    if bot.team == side.team: continue
    if bot.kind != rtPolitician: continue
    if bot.conviction - EmpowerTax >= r.conviction: return true
  false

proc runPolitician*(w: World, side: Side, r: Robot) =
  observe(w, side, r)
  let d = side.doctrine

  if isReady(r):
    let (radius, score) = bestRadius(w, side, r)
    if radius > 0:
      let usable = max(1, r.conviction - EmpowerTax)
      ## And it decides what COUNTS toward `empower_threshold`: a
      ## convert-first politician does not spend itself on a muckraker crowd.
      let counted =
        if d.convertOverKill: score.convertible
        else: score.convertible + score.killable
      let pct = counted * 100 div usable
      if score.takesCenter or pct >= d.empowerThreshold or
          dyingToEnemy(w, side, r):
        w.doEmpower(r, radius)
        return

  ## No speech worth making: walk toward the target.
  var target = w.mirrorTarget(side, r.loc)
  let (ok, note) = bestTarget(w, side, r.loc)
  if ok: target = note.loc
  if not d.convertOverKill:
    ## KILL, not convert: go where the soft targets are. The nearest reported
    ## enemy slanderer outranks a Centre, because popping a slanderer cluster
    ## is what this setting is for.
    var bestD = high(int)
    for sighting in side.slandererSightings:
      if w.currentRound - sighting.round > 80: continue
      let dist = r.loc.distanceSquaredTo(sighting.loc)
      if dist < bestD:
        bestD = dist
        target = sighting.loc
  if side.isDefender(r.id) and side.ownCenters.len > 0:
    ## A politician the Center built as DEFENCE holds the ring rather than
    ## walking off with the invasion.
    let home = side.nearestOwnCenter(r.loc)
    target = home
    if r.loc.distanceSquaredTo(home) <= 8:
      setFlag(r, encodeFlag(fkNeedDefence, home))
      return
  elif d.expansion == exDefendHome and side.ownCenters.len > 0:
    let home = side.nearestOwnCenter(r.loc)
    if r.loc.distanceSquaredTo(home) > 100:
      target = home
  moveToward(w, side, r, target)

  setFlag(r, encodeFlag(
    (if ok and note.hostile: fkEnemyEcHere
     elif ok: fkNeutralEcHere
     else: fkSilent),
    (if ok: note.loc else: r.loc),
    (if ok: influenceHint(max(0, note.influence)) else: 0)))
