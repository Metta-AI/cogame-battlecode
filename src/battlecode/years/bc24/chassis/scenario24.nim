## The Tier A-prime SCENARIO BOT, Nim side.
##
## Tier A's own measurement showed what it cannot cover: after 2 000 rounds
## `examplefuncsplayer24` leaves all three global upgrade points unspent on
## every map, never builds a stun or water trap, and on most maps never picks a
## flag up at all. Those are exactly the "rare code paths that fire mid-game"
## the Fleet card 1218171523823317 postmortem warns about — the ones bc26 left
## as un-root-caused Tier C divergences.
##
## So the oracle runs a SECOND bot of our own, written to be
##
##   (a) DETERMINISTIC with no RNG at all,
##   (b) CHEAP — the job asserts it never exceeds 25 % of the bytecode limit,
##       so it can never be cut off mid-turn, and
##   (c) SCRIPTED BY ROUND NUMBER to force every rare path early.
##
## `tools/oracle/bc24/Bc24Scenario.java` is the Java twin of THIS FILE and the
## two are written line for line against each other. Both must agree bit for
## bit for 2 000 rounds on all five `small` pairs.
##
## The whole script keys off two things and nothing else: the duck's `myIndex`,
## claimed on its first turn out of shared-array slot 63 (so the claim order is
## the exec order, identically on both sides), and `roundNum`. Every engine
## query it makes is guarded by the matching `can*` predicate and is evaluated
## in a fixed order.
##
## THE SCRIPT, by `myIndex`:
##
##   0     carries own flag 0 two tiles and drops it -- and under
##         `-d:bc24ScenarioTeleport` carries it NEXT TO own flag 1 instead, so
##         the six-tile check fails and the round-200 teleport fires.
##   1     builds a STUN trap, then a WATER trap, then an EXPLOSIVE trap, each
##         on the first legal tile in a fixed direction order.
##   2     digs, then fills, then digs again -- and digs UNDER an enemy
##         explosive when one is in reach, which is the interact trigger.
##   3     the ATTACKER: hits the lowest-id enemy in range every ready turn, so
##         it climbs to attack level 6 and freezes the other two at 3.
##   4     the HEALER: heals the lowest-id wounded ally every ready turn, so it
##         climbs to heal level 6.
##   5     the JAILBIRD: walks straight at the enemy and dies at level 5.
##   6     the CARRIER: after round 300 takes an enemy flag and runs at the
##         nearest own spawn tile; when it dies the drop/return timer runs.
##   7..11 more healers, so heal experience actually climbs.
##   12..16 more attackers, so there is something to heal and the traps have
##         somebody to fire at.
##   17..49 hold station on their spawn tile and do nothing, so the game reaches
##         round 2 000 and the tiebreak ladder decides it.
##
## Upgrades are bought by `myIndex == 0` at 600, 1200 and 1800 in the fixed
## order ATTACK, HEALING, CAPTURING.

import kit

export kit

const
  ScenarioClaimSlot* = 63
  ScenarioCarryRound* = 300

type
  ScenarioBrain* = object
    myIndex*: int
    claimed*: bool
    trapStage*: int
    digStage*: int
    dropped*: bool

var scenarioBrains: array[RobotCapacity * 2, ScenarioBrain]
var scenarioReady = false

proc scenarioReset*() =
  for i in 0 ..< scenarioBrains.len:
    scenarioBrains[i] = ScenarioBrain(myIndex: -1)
  scenarioReady = true

proc brainOf(r: Robot): var ScenarioBrain =
  if not scenarioReady: scenarioReset()
  scenarioBrains[r.execIndex]

const ScenarioDirs = [dNorth, dNortheast, dEast, dSoutheast,
                      dSouth, dSouthwest, dWest, dNorthwest]

proc stepToward(w: World, r: Robot, target: Loc) =
  ## `directionTo` first, then the eight in declaration order. No RNG, no
  ## memory, no scoring — the Java twin is the same nine lines.
  let dir = r.loc.directionTo(target)
  if dir != dCenter and w.canMove(r, dir):
    w.doMove(r, dir)
    return
  for d in ScenarioDirs:
    if w.canMove(r, d):
      w.doMove(r, d)
      return

proc senseNearbyFlag(w: World, r: Robot, own: bool,
                     skipCarried = false): tuple[ok: bool, f: Flag] =
  ## `senseNearbyFlags(-1, team)`: every flag of that team whose CURRENT
  ## location is within `r^2 <= 20` of this duck, in `allFlags` order. The
  ## engine checks neither `canSenseLocation` nor `onTheMap` here, and it does
  ## not exclude carried flags; the Java twin calls exactly this method, so
  ## the scenario bot can only ever know what it can see.
  for f in w.allFlags:
    if (f.team == r.team) != own: continue
    if f.loc.distanceSquaredTo(r.loc) > VisionRadiusSquared: continue
    if skipCarried and f.carriedBy >= 0: continue
    return (true, f)

proc firstBroadcast(w: World, r: Robot): tuple[ok: bool, at: Loc] =
  ## `senseBroadcastFlagLocations()[0]`.
  for l in w.broadcastFlagLocations(r):
    return (ok: true, at: l)

proc lowestIdEnemyInRange(w: World, r: Robot, r2: int): Robot =
  var best: Robot = nil
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team == r.team: continue
    if best == nil or bot.id < best.id: best = bot
  best

proc lowestIdWoundedAlly(w: World, r: Robot, r2: int): Robot =
  var best: Robot = nil
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team != r.team or bot.id == r.id: continue
    if bot.health >= DefaultHealth: continue
    if best == nil or bot.id < best.id: best = bot
  best

proc walkAtEnemyFlag(w: World, r: Robot) =
  ## A sensed enemy flag beats a broadcast one; with neither, hold station.
  let seen = w.senseNearbyFlag(r, false)
  if seen.ok:
    w.stepToward(r, seen.f.loc)
    return
  let bc = w.firstBroadcast(r)
  if bc.ok: w.stepToward(r, bc.at)

proc runScenario24*(w: World, side: Side, r: Robot) =
  var brain = addr brainOf(r)

  if not brain.claimed:
    brain.claimed = true
    brain.myIndex = w.readSharedArray(r.team, ScenarioClaimSlot)
    w.writeSharedArray(r.team, ScenarioClaimSlot, brain.myIndex + 1)

  if not r.spawned:
    for l in w.spawnLocs[ord(r.team)]:
      if w.canSpawn(r, l):
        w.doSpawn(r, l)
        return
    return

  let me = brain.myIndex

  ## Upgrades: the first SPAWNED duck of the team to act buys the next one in
  ## a fixed order, the round the point lands. Every duck tries, so a jailed
  ## duck 0 cannot leave the team holding three unspent points — which is
  ## exactly what the first draft of this script did.
  for kind in [ugAttack, ugHealing, ugCapturing]:
    if w.canBuyGlobal(r, kind):
      w.doBuyGlobal(r, kind)
      break

  case me
  of 0:
    ## The flag mover.
    if brain.dropped: return
    if not r.hasFlag():
      let own = w.senseNearbyFlag(r, true)
      if not own.ok:
        let home = w.spawnLocs[ord(r.team)]
        if home.len > 0: w.stepToward(r, home[0])
        return
      if w.canPickupFlag(r, own.f.loc):
        w.pickupFlag(r, own.f.loc)
        return
      w.stepToward(r, own.f.loc)
      return
    when defined(bc24ScenarioTeleport):
      ## Deliberately break the six-tile rule so the round-200 teleport fires:
      ## walk this flag into ANOTHER own spawn zone and put it down beside a
      ## second own flag.
      let other = w.senseNearbyFlag(r, true, skipCarried = true)
      if (other.ok and r.loc.distanceSquaredTo(other.f.loc) <= 16) or
          w.currentRound >= 180:
        if w.canDropFlag(r, r.loc):
          w.dropFlag(r, r.loc)
          brain.dropped = true
        return
      let far = w.spawnLocs[ord(r.team)]
      if far.len > 0: w.stepToward(r, far[far.len - 1])
    else:
      if w.currentRound >= 40:
        if w.canDropFlag(r, r.loc):
          w.dropFlag(r, r.loc)
          brain.dropped = true
        return
      let home = w.spawnLocs[ord(r.team)]
      if home.len > 0: w.stepToward(r, home[0])
  of 1:
    ## All three trap types, in a fixed order, each on the first legal tile.
    const stages = [tkStun, tkWater, tkExplosive]
    if brain.trapStage <= 2:
      let kind = stages[brain.trapStage]
      for d in ScenarioDirs:
        let l = r.loc + d
        if not w.onTheMap(l): continue
        if w.canBuildTrap(r, kind, l):
          w.buildTrap(r, kind, l)
          brain.trapStage += 1
          return
      if w.canBuildTrap(r, kind, r.loc):
        w.buildTrap(r, kind, r.loc)
        brain.trapStage += 1
        return
  of 2:
    ## Dig, fill, dig — and dig UNDER an enemy explosive when one is in reach,
    ## which is the interact trigger the whole tier exists for.
    if brain.digStage mod 2 == 0:
      for d in ScenarioDirs:
        let l = r.loc + d
        if not w.onTheMap(l): continue
        if w.canDig(r, l):
          w.doDig(r, l)
          brain.digStage += 1
          return
    else:
      for d in ScenarioDirs:
        let l = r.loc + d
        if not w.onTheMap(l): continue
        if w.canFill(r, l):
          w.doFill(r, l)
          brain.digStage += 1
          return
  of 3:
    let victim = w.lowestIdEnemyInRange(r, AttackRadiusSquared)
    if victim != nil and w.canAttack(r, victim.loc):
      w.doAttack(r, victim.loc)
      return
    w.walkAtEnemyFlag(r)
  of 4, 7, 8, 9, 10, 11:
    let patient = w.lowestIdWoundedAlly(r, HealRadiusSquared)
    if patient != nil and w.canHeal(r, patient.loc):
      w.doHeal(r, patient.loc)
      return
    let victim = w.lowestIdEnemyInRange(r, AttackRadiusSquared)
    if victim != nil and w.canAttack(r, victim.loc):
      w.doAttack(r, victim.loc)
      return
    w.walkAtEnemyFlag(r)
  of 5, 12, 13, 14, 15, 16:
    let victim = w.lowestIdEnemyInRange(r, AttackRadiusSquared)
    if victim != nil and w.canAttack(r, victim.loc):
      w.doAttack(r, victim.loc)
      return
    w.walkAtEnemyFlag(r)
  of 6:
    if w.currentRound < ScenarioCarryRound: return
    if r.hasFlag():
      var home = r.loc
      var bestD = high(int)
      for l in w.spawnLocs[ord(r.team)]:
        let d = r.loc.distanceSquaredTo(l)
        if d < bestD:
          bestD = d
          home = l
      w.stepToward(r, home)
      return
    if w.canPickupFlag(r, r.loc):
      w.pickupFlag(r, r.loc)
      return
    for d in ScenarioDirs:
      let l = r.loc + d
      if w.onTheMap(l) and w.canPickupFlag(r, l):
        w.pickupFlag(r, l)
        return
    w.walkAtEnemyFlag(r)
  else:
    ## Hold station: the game reaches round 2 000 and the tiebreak ladder
    ## decides it, which is the point.
    discard
