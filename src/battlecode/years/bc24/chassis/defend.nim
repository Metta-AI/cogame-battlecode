## bc24 defence: holding the ring around an own flag, answering a raider, and
## the distress protocol that turns raiders around.
##
## A defender CANNOT pick its own flag up after setup, so "defence" is: kill
## the carrier, then keep the tile clear for the four rounds the flag needs to
## fly home. Behaviour ported from `chenyx512/battlecode24` `src/bot1/`
## (AGPL-3.0, credited in NOTICE).

import kit, micro, builder

export kit, micro, builder

proc ownFlagFor*(w: World, side: Side, index: int): tuple[ok: bool, f: Flag] =
  var i = 0
  for f in w.allFlags:
    if f.team != side.team: continue
    if i == index: return (true, f)
    i += 1

proc updateDistress*(w: World, side: Side, r: Robot) =
  ## A defender writes a distress bit when it sees more enemies than friends
  ## near its flag. The counter decays in the round loop, so distress means
  ## "now", not "once".
  let brain = side.brainFor(r)
  if not brain.hasRole or brain.role > 2: return
  let enemies = w.countNearby(r, VisionRadiusSquared, r.team.other())
  let friends = w.countNearby(r, VisionRadiusSquared, r.team)
  if enemies > friends:
    side.distress[brain.role] = min(60, side.distress[brain.role] + 2)

proc threatenedFlag*(w: World, side: Side, r: Robot):
    tuple[ok: bool, at: Loc] =
  ## An own flag inside this duck's vision with an enemy nearer to it than the
  ## duck is. This is the trigger for the reserved stun trap, and it fires
  ## whatever `trap_budget` says (D2).
  for f in w.allFlags:
    if f.team != side.team: continue
    if not spend(r, 1): continue
    if not w.canSenseLocation(r, f.loc): continue
    if f.carriedBy >= 0: return (true, f.loc)
    var threat = false
    for l in w.locationsWithinRadiusSquared(f.loc, 8):
      if not spend(r, 1): break
      let bot = w.getRobot(l)
      if bot != nil and bot.team != side.team: threat = true
    if threat: return (true, f.loc)

proc trapNearFlag*(w: World, side: Side, at: Loc): bool =
  ## Is a friendly trap already guarding this flag? The reserved stun is a
  ## FLOOR, not a carpet: one is enough, and without this test `trap_placement`
  ## would measure the reserve rather than the doctrine.
  for l in w.locationsWithinRadiusSquared(at, 4):
    if w.hasTrap(l) and w.getTrap(l).team == side.team: return true
  false

proc defendPost*(w: World, side: Side, r: Robot): Loc =
  ## The ring at Chebyshev 2..3 around this duck's flag; a duck already on the
  ## ring holds its ground.
  let brain = side.brainFor(r)
  let index = if brain.hasRole: brain.role else: 0
  let own = w.ownFlagFor(side, min(index, 2))
  if own.ok: return own.f.loc
  side.ownCentres[min(index, 2)]

proc runDefender*(w: World, side: Side, r: Robot) =
  ## One defender's post-setup turn.
  if r.hasFlag():
    ## A defender can only be holding an OWN flag if the setup phase left it
    ## there. Put it down on a passable tile at once.
    if w.canDropFlag(r, r.loc):
      w.dropFlag(r, r.loc)
      return

  w.updateDistress(side, r)
  if w.fightOrRetreat(side, r): return

  ## THE FLOOR NO KNOB CAN LOWER: a stun trap out of the reserved 100 crumbs
  ## the moment an own flag is sensed under threat.
  let threat = w.threatenedFlag(side, r)
  if threat.ok:
    let cost = trapCostFor(tkStun, r.levelOf(skBuild))
    if w.getCrumbs(side.team) >= cost and not w.trapNearFlag(side, threat.at):
      for l in w.locationsWithinRadiusSquared(r.loc, InteractRadiusSquared):
        if not spend(r, 1): break
        if l.distanceSquaredTo(threat.at) > 8: continue
        if w.canBuildTrap(r, tkStun, l):
          w.buildTrap(r, tkStun, l)
          return
    if r.loc.distanceSquaredTo(threat.at) > 2:
      discard w.greedyStep(side, r, threat.at)
      return

  w.stunSelfDefence(side, r)

  let post = w.defendPost(side, r)
  let d = chebyshev(r.loc, post)
  if d > 3:
    let brain = side.brainFor(r)
    let slot = side.ownFieldIndex(min(if brain.hasRole: brain.role else: 0, 2))
    discard w.travelTo(side, r, slot, post)
  elif d < 2:
    ## Standing on the flag blocks a friendly respawn and helps nobody: step
    ## back out onto the ring.
    let enemy = w.nearestEnemy(r, VisionRadiusSquared)
    if enemy != nil:
      discard w.greedyStep(side, r, enemy.loc)
    else:
      for dir in MoveDirs:
        if not spend(r, 1): break
        let nl = r.loc + dir
        if chebyshev(nl, post) == 2 and w.canMove(r, dir):
          discard w.greedyStep(side, r, nl)
          break
  else:
    let enemy = w.nearestEnemy(r, VisionRadiusSquared)
    if enemy != nil and chebyshev(enemy.loc, post) <= 6:
      discard w.greedyStep(side, r, enemy.loc)

proc runHealer*(w: World, side: Side, r: Robot) =
  ## Healers mend per `heal_priority`, fight when there is nothing to mend,
  ## and follow the wounded rather than the flag.
  if r.hasFlag():
    if w.canDropFlag(r, r.loc):
      w.dropFlag(r, r.loc)
      return

  let patient = w.healTarget(side, r)
  if patient != nil and w.canHeal(r, patient.loc):
    w.doHeal(r, patient.loc)
    if not r.canMoveCooldown(): return

  ## `carrier_first` is not only a TARGETING rule: a healer that never WALKS
  ## to the carrier will not be inside `r^2 <= 4` of it when it matters, and
  ## the knob would then move nothing but a tiebreak that almost never comes
  ## up. This is what gives it teeth, and it outranks picking a fight.
  if side.doctrine.healPriority == hpCarrierFirst:
    for id in side.carriers:
      if not spend(r, 1): break
      let carrier = w.robotById(id)
      if carrier == nil or not carrier.spawned: continue
      if r.loc.distanceSquaredTo(carrier.loc) > EscortRallyRadiusSquared:
        continue
      if r.loc.distanceSquaredTo(carrier.loc) > 2:
        discard w.travelTo(side, r, w.homeSpawnSlot(side, r), carrier.loc)
        return
      break

  if w.fightOrRetreat(side, r): return
  w.stunSelfDefence(side, r)

  ## Walk toward the nearest wounded friend in sight, else toward the flock's
  ## own flag ring — a healer with nobody to mend is a defender.
  var target = loc(-1, -1)
  var bestHp = DefaultHealth
  for l in w.sensedTiles(r):
    let bot = w.getRobot(l)
    if bot == nil or bot.team != r.team or bot.id == r.id: continue
    if bot.health < bestHp:
      bestHp = bot.health
      target = l
  if target.x >= 0:
    discard w.greedyStep(side, r, target)
    return
  let brain = side.brainFor(r)
  let index = min(if brain.hasRole: brain.role mod 3 else: 0, 2)
  let own = w.ownFlagFor(side, index)
  let post = if own.ok: own.f.loc else: side.ownCentres[index]
  if chebyshev(r.loc, post) > 4:
    discard w.travelTo(side, r, side.ownFieldIndex(index), post)
  else:
    let enemy = w.nearestEnemy(r, VisionRadiusSquared)
    if enemy != nil: discard w.greedyStep(side, r, enemy.loc)
