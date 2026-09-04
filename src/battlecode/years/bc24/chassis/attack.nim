## bc24 raiding: contesting the middle before `flag_rush_round`, committing to
## an enemy flag after it, and the escort screen a carrier gets.
##
## Behaviour ported from `chenyx512/battlecode24` `src/bot1/` (the six-role
## claim, the raid roles) and `davidteather/battlecode_24` `src/submit6/` (the
## carrier-return micro), both AGPL-3.0 and credited in NOTICE.
##
## `flag_rush_round`'s range is 201..1200 and CANNOT EXPRESS "NEVER": below it
## the attackers still farm crumbs, still kill in enemy territory for the
## 30-crumb bounty and still level attack; above it they commit. At 1200 there
## are still 800 rounds of raiding left.

import kit, micro

export kit, micro

func commitRound*(side: Side): int = side.doctrine.flagRushRound

proc bestKnownEnemyFlag*(w: World, side: Side, r: Robot):
    tuple[ok: bool, at: Loc, index: int] =
  ## The raider's own role picks which of the three it goes for; if that one
  ## is unknown it falls back to the nearest known.
  ##
  ## A SENSED location beats a broadcast one, and a BROADCAST one is worth
  ## less than the enemy spawn centre it sits near: the broadcast fix is only
  ## accurate to `r^2 <= 100` — ten tiles — while a duck's vision is `r^2 <=
  ## 20`, so walking to the broadcast tile routinely reveals nothing at all.
  ## The spawn-zone centres are public (they are in the doctrine brief and the
  ## map guarantees put the flags there), so an unsensed flag is hunted at its
  ## centre and sensing takes over on arrival.
  let brain = side.brainFor(r)
  let want = if brain.hasRole: brain.role - 3 else: 0
  if want >= 0 and want <= 2 and side.knownEnemyFlag[want].round >= 0:
    if side.knownEnemyFlag[want].sensed:
      return (true, side.knownEnemyFlag[want].loc, want)
    return (true, side.enemyCentres[want], want)
  var bestD = high(int)
  for i in 0 .. 2:
    if side.knownEnemyFlag[i].round < 0: continue
    let at = (if side.knownEnemyFlag[i].sensed: side.knownEnemyFlag[i].loc
              else: side.enemyCentres[i])
    let d = r.loc.distanceSquaredTo(at)
    if d < bestD:
      bestD = d
      result = (true, at, i)

proc carrierRunHome*(w: World, side: Side, r: Robot) =
  ## A carrier cannot attack, heal, build, dig or fill: it moves and it drops.
  ## It walks the field to the nearest own spawn centre, and the capture fires
  ## the moment it steps onto a friendly spawn tile.
  let slot = w.homeSpawnSlot(side, r)
  var target = side.ownCentres[0]
  for i in 0 .. 2:
    if side.ownFieldIndex(i) == slot: target = side.ownCentres[i]
  discard w.travelTo(side, r, slot, target)

proc escortTarget*(w: World, side: Side, r: Robot):
    tuple[ok: bool, at: Loc] =
  ## `flag_carry_escort` friendly ducks convert to escorts for as long as the
  ## carry lasts, screening the carrier and attacking anything that closes. 0
  ## means the carrier runs alone and everyone else keeps raiding.
  ##
  ## WHICH ducks is decided once a round by `assignEscorts`, in exec order, so
  ## the assignment is deterministic and the COUNT is exactly the knob.
  if side.doctrine.flagCarryEscort <= 0: return
  if side.carriers.len == 0: return
  if not side.isEscort(r): return
  var bestD = high(int)
  for id in side.carriers:
    if not spend(r, 1): break
    let carrier = w.robotById(id)
    if carrier == nil or not carrier.spawned: continue
    if carrier.id == r.id: continue
    let d = r.loc.distanceSquaredTo(carrier.loc)
    if d > EscortRallyRadiusSquared: continue
    if d < bestD:
      bestD = d
      result = (ok: true, at: carrier.loc)

proc assignEscorts*(w: World, side: Side) =
  ## The `flag_carry_escort` nearest own ducks to each carrier, chosen in exec
  ## order with distance as the key and the exec index as the tiebreak.
  side.escorts.setLen(0)
  if side.doctrine.flagCarryEscort <= 0: return
  for id in side.carriers:
    let carrier = w.robotById(id)
    if carrier == nil or not carrier.spawned: continue
    var picked = 0
    var taken: array[RobotCapacity * 2, bool]
    while picked < side.doctrine.flagCarryEscort:
      var best: Robot = nil
      var bestD = high(int)
      for r in w.robots:
        if r.team != side.team or not r.spawned: continue
        if r.id == carrier.id: continue
        ## Only the RAIDERS escort: a builder that walks off to screen a
        ## carrier is a builder that stopped building, and the census already
        ## says how many ducks fight.
        if not side.isAttacker(r): continue
        if taken[r.execIndex]: continue
        if side.isEscort(r): continue
        let d = r.loc.distanceSquaredTo(carrier.loc)
        if d > EscortRallyRadiusSquared: continue
        if d < bestD:
          bestD = d
          best = r
      if best == nil: break
      taken[best.execIndex] = true
      side.escorts.add(best.id)
      picked += 1

proc runRaider*(w: World, side: Side, r: Robot) =
  ## One attacker's post-setup turn.
  if r.hasFlag():
    w.carrierRunHome(side, r)
    return

  ## THE LAST SIX TILES. A committed raider inside `r^2 <= 36` of the flag it
  ## is going for pushes for the flag rather than trading blows in front of
  ## it: the whole point of the rush is to come home with something, and a
  ## duck that stops to fight every defender never arrives. It still retreats
  ## at `retreat_hp`, and it still fights when it cannot move.
  let close = w.bestKnownEnemyFlag(side, r)
  if close.ok and w.currentRound >= side.commitRound() and
      r.loc.distanceSquaredTo(close.at) <= 36 and not side.shouldBreak(r):
    if w.canPickupFlag(r, r.loc):
      w.pickupFlag(r, r.loc)
      return
    for l in w.locationsWithinRadiusSquared(r.loc, InteractRadiusSquared):
      if not spend(r, 1): break
      if w.canPickupFlag(r, l):
        w.pickupFlag(r, l)
        return
    if w.greedyStep(side, r, close.at): return

  if w.fightOrRetreat(side, r): return
  w.stunSelfDefence(side, r)

  ## ESCORT DUTY OUTRANKS RAIDING, but not fighting: a duck already in contact
  ## screens by killing what is in front of it. The rally radius is well
  ## beyond a duck's own vision because the carrier's tile is on the shared
  ## array, so converging on it is something the flock legitimately knows how
  ## to do.
  let escort = w.escortTarget(side, r)
  if escort.ok:
    if r.loc.distanceSquaredTo(escort.at) > 4:
      discard w.travelTo(side, r, w.homeSpawnSlot(side, r), escort.at)
    ## Otherwise HOLD STATION. `fightOrRetreat` above has already taken any
    ## shot the duck had; chasing the nearest enemy from beside the carrier is
    ## how a screen stops being a screen.
    return

  ## A flag under this duck's feet is always taken, whatever the round.
  if w.canPickupFlag(r, r.loc):
    w.pickupFlag(r, r.loc)
    return
  for l in w.locationsWithinRadiusSquared(r.loc, InteractRadiusSquared):
    if not spend(r, 1): break
    if w.canPickupFlag(r, l):
      w.pickupFlag(r, l)
      return

  let known = w.bestKnownEnemyFlag(side, r)
  if w.currentRound >= side.commitRound() and known.ok:
    let slot = side.enemyFieldIndex(known.index)
    discard w.travelTo(side, r, slot, known.at)
    return

  ## Before the rush: take the crumbs off the floor, hunt in enemy territory
  ## for the 30-crumb bounty, and never stand still.
  let pile = w.nearestCrumbPile(r)
  if pile.ok:
    discard w.greedyStep(side, r, pile.at)
    return
  let enemy = w.nearestEnemy(r, VisionRadiusSquared)
  if enemy != nil:
    discard w.greedyStep(side, r, enemy.loc)
    return
  if known.ok:
    let slot = side.enemyFieldIndex(known.index)
    discard w.travelTo(side, r, slot, known.at)
  else:
    let slot = side.enemyFieldIndex(0)
    discard w.travelTo(side, r, slot, side.enemyCentres[0])
