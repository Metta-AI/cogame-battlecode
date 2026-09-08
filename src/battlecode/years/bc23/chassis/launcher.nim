## `lemonade`'s launcher, destabilizer, booster and amplifier turns.
##
## Behaviour ported from `awesomelemonade/Battlecode2023` `src/finalBot/`
## (AGPL-3.0) for the launcher and from `vrangr1/BattleCode2023`
## `src/AFinalsBot/BotBooster.java` + `BotDestabilizer.java` (AGPL-3.0) for
## the two elixir units. `micro.nim` owns the target priority and the group's
## destination; this file is the turn itself.
##
## THE LAUNCHER ANSWERS A THREAT TO ITS OWN HEADQUARTERS unconditionally, at
## every knob setting — the anti-inert rule's own clause. Past that,
## `destabilizer_use` says where the group lives and
## `retreat_on_launcher_loss` what it does when a member dies.

import ../world, kit, micro, amplifier, comms as chcomms

export kit

proc defendHome(w: World, side: Side, r: Robot): Loc =
  ## An enemy launcher sensed within r² ≤ 16 of one of our headquarters is
  ## answered, whatever the doctrine says.
  result = loc(-1, -1)
  var best = high(int)
  for other in w.senseNearbyRobots(r, RobotSpecs[r.kind].visionRadiusSquared,
                                   ord(side.team.other())):
    if other.kind != rtLauncher and other.kind != rtDestabilizer: continue
    for h in side.homeHqs:
      if other.loc.distanceSquaredTo(h) <=
          RobotSpecs[rtLauncher].actionRadiusSquared:
        let d = chebyshev(r.loc, other.loc)
        if d < best:
          best = d
          result = other.loc

proc runLauncher*(w: World, side: Side, r: Robot) =
  w.observe(side, r)

  let target = bestTarget(w, side, r)
  if target.x >= 0 and w.canAttack(r, target):
    if w.doAttack(r, target):
      w.noteFirstAction(side.team, Bc23ActionAttack)

  if not r.isMovementReady(): return

  ## STAND AND SHOOT. A launcher already inside an enemy launcher's r2<=16
  ## gains nothing by stepping: the exchange is already joined, and the robot
  ## that MOVES into range is the one that gets shot first. Measured: without
  ## this the faction that takes its turn first loses every mirror.
  for other in w.senseNearbyRobots(r, RobotSpecs[r.kind].visionRadiusSquared,
                                   ord(side.team.other())):
    if other.kind != rtLauncher: continue
    if r.loc.distanceSquaredTo(other.loc) <=
        RobotSpecs[rtLauncher].actionRadiusSquared:
      return

  ## DO NOT WALK INTO A FREE SHOT. A launcher that steps from outside r2<=16
  ## to inside it hands the enemy — who takes its turn later in the exec
  ## order — one unanswered 20 damage, every engagement, for ever. Measured:
  ## without this guard the faction that moves SECOND wins the mirror on
  ## every map, and the loser is annihilated by round 200. `siege` overrides
  ## it, because pushing is what `siege` is for.
  if side.doctrine.destabilizerUse != duSiege:
    var nearestFire = high(int)
    for other in w.senseNearbyRobots(r, RobotSpecs[r.kind].visionRadiusSquared,
                                     ord(side.team.other())):
      if other.kind != rtLauncher and other.kind != rtDestabilizer: continue
      nearestFire = min(nearestFire, r.loc.distanceSquaredTo(other.loc))
    if nearestFire <= RobotSpecs[rtLauncher].actionRadiusSquared * 2 and
        nearestFire > RobotSpecs[rtLauncher].actionRadiusSquared:
      return

  let threat = defendHome(w, side, r)
  if threat.x >= 0:
    discard w.moveToward(side, r, threat)
    return

  if retreating(w, side):
    discard w.moveToward(side, r, retreatTarget(w, side, r))
    return

  ## Keep the stand-off when the enemy's group is bigger: step away rather
  ## than into a losing trade.
  var friends = 0
  var foes = 0
  for other in w.senseNearbyRobots(r, RobotSpecs[r.kind].visionRadiusSquared):
    if other.kind == rtHeadquarters: continue
    if other.team == r.team: friends += 1 else: foes += 1
  if foes > friends + 1 and target.x >= 0:
    let away = loc(r.loc.x * 2 - target.x, r.loc.y * 2 - target.y)
    discard w.moveToward(side, r, away)
    return

  discard w.moveToward(side, r, strikeTarget(w, side, r))

proc runDestabilizer*(w: World, side: Side, r: Robot) =
  w.observe(side, r)
  if r.isActionReady():
    ## Cast on the densest enemy cluster inside r² ≤ 13; a destabilisation
    ## that hits nobody is 70 cooldown for nothing.
    var best = loc(-1, -1)
    var bestCount = 0
    for l in w.locationsWithinRadiusSquared(
        r.loc, RobotSpecs[rtDestabilizer].actionRadiusSquared):
      if not r.spend(1): break
      var count = 0
      for tile in w.locationsWithinRadiusSquared(l, DestabilizerRadiusSquared):
        let other = w.getRobot(tile)
        if other != nil and other.team != r.team and
            other.kind != rtHeadquarters:
          count += 1
      if count > bestCount:
        bestCount = count
        best = l
    if bestCount > 0 and best.x >= 0:
      if w.doDestabilize(r, best):
        w.noteFirstAction(side.team, Bc23ActionDestabilize)
        return
  if r.isMovementReady():
    discard w.moveToward(side, r, strikeTarget(w, side, r))

proc runBooster*(w: World, side: Side, r: Robot) =
  w.observe(side, r)
  ## The boosted patch is fixed to WHERE IT WAS CAST and does not follow the
  ## booster, so cast it standing with the group rather than on the way.
  var friends = 0
  for other in w.senseNearbyRobots(r, BoosterRadiusSquared, ord(side.team)):
    if other.kind != rtHeadquarters: friends += 1
  if r.isActionReady() and friends >= 3:
    if w.doBoost(r):
      w.noteFirstAction(side.team, Bc23ActionBoost)
      return
  if r.isMovementReady():
    discard w.moveToward(side, r, strikeTarget(w, side, r))

proc runAmplifier*(w: World, side: Side, r: Robot) =
  w.observe(side, r)
  if canSpeak(w, r):
    chcomms.publish(w, side, r)
  if r.isMovementReady():
    let post = amplifierPost(w, side, r)
    if post.x >= 0 and post != r.loc:
      discard w.moveToward(side, r, post)
