## `bc23scenario` — the SCENARIO BOT, the Nim twin of
## `tools/oracle/bc23/bc23scenario/RobotPlayer.java`, written line for line
## against it and compiled only behind `-d:bc23Scenario`.
##
## Tier A's own measurement showed exactly what it cannot cover: over three
## full 2000-round games the official example bot NEVER took an anchor from a
## headquarters, never placed one, never captured an island, never built an
## amplifier, a destabilizer or a booster, never transferred a resource to a
## headquarters, never upgraded or transformed a well, and never wrote the
## shared array. So `CONQUEST`, the first two ladder rungs, the whole anchor
## and island subsystem, the elixir tree, the tempo fields and every comms
## path would be untested by it.
##
## This bot is written to be
##
## * **deterministic with NO RNG AT ALL** — every decision is a function of
##   the round number, the robot's type and the engine's own scan order;
## * **cheap** — the parity job asserts it never exceeds 50 % of its bytecode
##   limit, so it can never be cut off mid-turn (measured 28-43 % across the
##   six `small` maps, the carrier's 12 500 being the binding limit);
## * **scripted by round number to force every rare path early.**
##
## EVERYTHING IT LOOKS AT IS ROBOT-LOCAL. The Java twin runs inside the
## engine's sandbox and has a `RobotController`, not a `GameWorld`: it cannot
## ask for island 0's first tile, for the team's total anchor stock, or for
## the well list. So every query here goes through `visible`, which is
## `RobotControllerImpl.getAllLocationsWithinRadiusSquared` verbatim — the
## radius clamped to the type's vision radius, the engine's own x-outer,
## y-inner scan order, and `canSenseLocation` (hence the cloud collapse)
## applied to every tile. A helper here that read the world directly would
## have no Java twin and the tier would be uncomparable, not merely unequal.

import ../world, ../comms as simcomms

export world

iterator visible(w: World, r: Robot, r2: int): Loc =
  ## `RobotControllerImpl.getAllLocationsWithinRadiusSquared(getLocation(),
  ## r2)`: `min(r2, visionRadiusSquared)` over the engine's scan order,
  ## filtered by `canSenseLocation`. The clamp is against the TYPE'S vision
  ## radius, not the cloud-collapsed one — the collapse is the filter's job,
  ## which is why a launcher standing in a cloud sees four tiles and still
  ## has an action radius of sixteen.
  let clamped = min(r2, RobotSpecs[r.kind].visionRadiusSquared)
  for l in w.locationsWithinRadiusSquared(r.loc, clamped):
    if w.canSenseLocation(r, l):
      yield l

proc firstBuildTile(w: World, r: Robot): Loc =
  ## The first unoccupied passable tile in the ENGINE'S OWN SCAN ORDER inside
  ## a headquarters' build radius.
  for l in w.visible(r, DistanceSquaredFromHeadquarter):
    if not w.isLocationOccupied(l) and w.isPassable(l):
      return l
  loc(-1, -1)

proc firstIslandTile(w: World, r: Robot): Loc =
  ## The first island tile this robot can see. Not "island 0" — a sandboxed
  ## robot has no island list.
  for l in w.visible(r, RobotSpecs[r.kind].visionRadiusSquared):
    if w.islandAt(l) >= 0:
      return l
  loc(-1, -1)

proc firstFriendlyHeadquarters(w: World, r: Robot, withAnchor: bool): Loc =
  for l in w.visible(r, RobotSpecs[r.kind].visionRadiusSquared):
    let other = w.getRobot(l)
    if other == nil or other.team != r.team: continue
    if other.kind != rtHeadquarters: continue
    if withAnchor and other.totalAnchors == 0: continue
    return l
  loc(-1, -1)

proc firstWell(w: World, r: Robot): Loc =
  for l in w.visible(r, RobotSpecs[r.kind].visionRadiusSquared):
    if w.isWell(l):
      return l
  loc(-1, -1)

proc walkTarget(w: World, r: Robot, wantWell: bool): Loc =
  ## Where a full carrier walks: the first visible well whose CURRENT kind is
  ## not one we are carrying — the only kind of well a transfer can transform
  ## — and otherwise the first friendly headquarters we can see.
  ##
  ## ONE SCAN FOR BOTH. They are independent "first in scan order" queries,
  ## so folding them together changes no answer; it changes the bytecode
  ## bill, and the carrier is the type this bot peaks on (44 % of its 12 500
  ## with two scans, 33 % with one — against the job's 50 % headroom bound).
  var well = loc(-1, -1)
  var hq = loc(-1, -1)
  for l in w.visible(r, RobotSpecs[r.kind].visionRadiusSquared):
    if wantWell and well.x < 0 and w.isWell(l):
      let kindHere = w.wellAtLoc(l).kind
      for t in RealResources:
        if t != kindHere and r.resourceOf(t) > 0:
          well = l
          break
    if hq.x < 0:
      let other = w.getRobot(l)
      if other != nil and other.team == r.team and
          other.kind == rtHeadquarters:
        hq = l
    if hq.x >= 0 and (well.x >= 0 or not wantWell): break
  if well.x >= 0: well else: hq

proc firstEnemyTarget(w: World, r: Robot): Loc =
  for l in w.visible(r, RobotSpecs[r.kind].actionRadiusSquared):
    let other = w.getRobot(l)
    if other != nil and other.team != r.team and
        other.kind != rtHeadquarters and w.canAttack(r, l):
      return l
  loc(-1, -1)

proc stepToward(w: World, r: Robot, target: Loc) =
  ## `directionTo`, then the eight rotations in a fixed order. No memory, no
  ## BFS: the Java twin does exactly this.
  if not r.isMovementReady(): return
  if target.x < 0: return
  var d = r.loc.directionTo(target)
  for k in 0 ..< 8:
    if w.canMove(r, d):
      w.doMove(r, d)
      return
    d = d.rotateRight()

proc scenarioHeadquarters(w: World, r: Robot) =
  let round = w.currentRound
  ## Force the build paths early and on a fixed cadence.
  if round == 2 or round mod 40 == 0:
    let l = w.firstBuildTile(r)
    if l.x >= 0 and w.canBuildRobot(r, rtCarrier, l):
      discard w.doBuildRobot(r, rtCarrier, l)
  if round == 3 or round mod 41 == 0:
    let l = w.firstBuildTile(r)
    if l.x >= 0 and w.canBuildRobot(r, rtLauncher, l):
      discard w.doBuildRobot(r, rtLauncher, l)
  if round == 4:
    let l = w.firstBuildTile(r)
    if l.x >= 0 and w.canBuildRobot(r, rtAmplifier, l):
      discard w.doBuildRobot(r, rtAmplifier, l)
  ## SIX BUILDS ATTEMPTED IN ONE TURN, forced once, so the cooldown rule is
  ## exercised: a headquarters has no action cooldown, so what stops this is
  ## the resource check and the free-tile scan, not the clock.
  if round == 30:
    for k in 0 ..< 6:
      let l = w.firstBuildTile(r)
      if l.x < 0: break
      if not w.canBuildRobot(r, rtCarrier, l): break
      discard w.doBuildRobot(r, rtCarrier, l)
  ## THIS headquarters' own stock, not the team's: a sandboxed robot cannot
  ## see another headquarters' inventory unless it is in vision.
  if round >= 6 and r.totalAnchors == 0 and w.canBuildAnchor(r, anStandard):
    discard w.doBuildAnchor(r, anStandard)
  if w.canBuildAnchor(r, anAccelerating):
    discard w.doBuildAnchor(r, anAccelerating)
  if r.elixir >= buildCost(rtDestabilizer, resElixir) and round mod 50 == 0:
    let l = w.firstBuildTile(r)
    if l.x >= 0 and w.canBuildRobot(r, rtDestabilizer, l):
      discard w.doBuildRobot(r, rtDestabilizer, l)
  if r.elixir >= buildCost(rtBooster, resElixir) and round mod 51 == 0:
    let l = w.firstBuildTile(r)
    if l.x >= 0 and w.canBuildRobot(r, rtBooster, l):
      discard w.doBuildRobot(r, rtBooster, l)
  ## A headquarters may always write.
  discard simcomms.doWriteSharedArray(w, r, round mod 64, round mod 65536)

proc scenarioCarrier(w: World, r: Robot) =
  let round = w.currentRound
  ## Holding an anchor: plant it where we stand, or ferry it to the first
  ## island tile we can see. `doPlaceAnchor` re-checks the four clauses
  ## `assertCanPlaceAnchor` checks and returns false rather than throwing, so
  ## the Java twin's `if (canPlaceAnchor()) placeAnchor(); else …` and this
  ## take the same branch on the same states.
  if r.totalAnchors > 0:
    if w.islandAt(r.loc) < 0 or not w.doPlaceAnchor(r):
      stepToward(w, r, w.firstIslandTile(r))
    return
  ## Empty, and a headquarters we can see holds an anchor: go and take it.
  if r.weight == 0:
    let hq = w.firstFriendlyHeadquarters(r, withAnchor = true)
    if hq.x >= 0:
      if r.loc.isAdjacentTo(hq):
        let kind = w.getRobot(hq).typeAnchor()
        if kind != anNone and w.canTakeAnchor(r, hq, kind):
          discard w.doTakeAnchor(r, hq, kind)
      else:
        stepToward(w, r, hq)
      return
  ## Full. THE WELL CLAUSES ARE THE ELIXIR PROGRAMME AND THE ONLY WAY TO
  ## REACH IT. `Well.addAdamantium` flips a MANA well to ELIXIR at 600
  ## adamantium and `Well.addMana` flips an ADAMANTIUM well at 600 mana,
  ## while 1400 of a well's OWN kind trips its rate upgrade instead — so the
  ## two paths need opposite transfers and the script forces both:
  ##
  ##   * carrying elixir -> straight home, because a headquarters cannot buy
  ##     a destabilizer or a booster out of a well;
  ##   * beside a well of the other kind -> pour (the transformation);
  ##   * beside a well of our own kind, every third round -> pour (the rate
  ##     upgrade);
  ##   * beside a friendly headquarters -> deposit;
  ##   * otherwise walk to the nearest well of the other kind, then home.
  let weight = r.weight
  if weight >= CarrierCapacity or (weight > 0 and round mod 7 == 0):
    let carryingElixir = r.resourceOf(resElixir) > 0
    ## THE 3x3, not `visible(actionRadiusSquared)` filtered by
    ## `isAdjacentTo`: `locationsWithinRadiusSquared` is x ascending outer,
    ## y ascending inner, so restricting it to |dx| <= 1 and |dy| <= 1 IS
    ## this loop, in this order, and the twenty-nine-tile scan cost the
    ## carrier a fifth of its bytecode limit for eight useful tiles.
    ## Adjacent tiles are always sensible: r² <= 2 is inside the cloud
    ## collapse's radius of 4.
    for ddx in -1 .. 1:
      for ddy in -1 .. 1:
        let l = r.loc.translate(ddx, ddy)
        if not w.onTheMap(l): continue
        if round >= 200 and not carryingElixir and w.isWell(l):
          let kindHere = w.wellAtLoc(l).kind
          for t in RealResources:
            if r.resourceOf(t) == 0: continue
            if t != kindHere or round mod 3 == 0:
              if w.canTransferResource(r, l, t, r.resourceOf(t)):
                discard w.doTransferResource(r, l, t, r.resourceOf(t))
                return
        let other = w.getRobot(l)
        if other != nil and other.kind == rtHeadquarters and
            other.team == r.team:
          for t in RealResources:
            if r.resourceOf(t) > 0 and w.canTransferResource(r, l, t,
                r.resourceOf(t)):
              discard w.doTransferResource(r, l, t, r.resourceOf(t))
              return
    ## Nobody beside us: throw at the first enemy in range on a fixed
    ## cadence.
    if round mod 13 == 0:
      let target = w.firstEnemyTarget(r)
      if target.x >= 0:
        discard w.doAttack(r, target)
        return
    ## Then a well of the other kind if one is in sight, otherwise home.
    stepToward(w, r, w.walkTarget(r,
      wantWell = round >= 200 and not carryingElixir))
    return
  ## Otherwise mine the first collectable well tile in the 3x3.
  for ddx in -1 .. 1:
    for ddy in -1 .. 1:
      let l = r.loc.translate(ddx, ddy)
      if w.onTheMap(l) and w.canCollectResource(r, l, -1):
        discard w.doCollectResource(r, l, -1)
        return
  ## Nothing to mine: walk to the first well we can see.
  stepToward(w, r, w.firstWell(r))

proc scenarioLauncher(w: World, r: Robot) =
  let target = w.firstEnemyTarget(r)
  if target.x >= 0:
    discard w.doAttack(r, target)
  stepToward(w, r, w.firstIslandTile(r))

proc scenarioDestabilizer(w: World, r: Robot) =
  if w.canDestabilize(r, r.loc):
    discard w.doDestabilize(r, r.loc)
  else:
    stepToward(w, r, w.firstIslandTile(r))

proc scenarioBooster(w: World, r: Robot) =
  if w.canBoost(r):
    discard w.doBoost(r)
  else:
    stepToward(w, r, w.firstIslandTile(r))

proc scenarioAmplifier(w: World, r: Robot) =
  ## The write-window probe: an amplifier may always write, and every robot
  ## near it may too.
  discard simcomms.doWriteSharedArray(w, r, 63, w.currentRound mod 65536)
  if w.currentRound == 500:
    ## Exercise the disintegrate path exactly once.
    w.disintegrate(r)
    return
  stepToward(w, r, w.firstIslandTile(r))

proc runScenario23*(w: World, r: Robot) =
  case r.kind
  of rtHeadquarters: scenarioHeadquarters(w, r)
  of rtCarrier: scenarioCarrier(w, r)
  of rtLauncher: scenarioLauncher(w, r)
  of rtDestabilizer: scenarioDestabilizer(w, r)
  of rtBooster: scenarioBooster(w, r)
  of rtAmplifier: scenarioAmplifier(w, r)
