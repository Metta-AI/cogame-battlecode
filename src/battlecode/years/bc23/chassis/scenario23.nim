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
## * **cheap** — the parity job asserts it never exceeds 25 % of its bytecode
##   limit, so it can never be cut off mid-turn;
## * **scripted by round number to force every rare path early.**
##
## Two further variants force the ends: `-d:bc23ScenarioConquest` anchors
## enough islands for `CONQUEST` to fire, and `-d:bc23ScenarioTie` mirrors both
## sides exactly so the ladder walks down to `MORE_ADAMANTIUM_NET_WORTH`.

import ../world, ../comms as simcomms

export world

proc firstFreeTile(w: World, centre: Loc): Loc =
  ## The first unoccupied passable tile in the ENGINE'S OWN SCAN ORDER inside
  ## a headquarters' build radius.
  for l in w.locationsWithinRadiusSquared(centre, DistanceSquaredFromHeadquarter):
    if not w.isLocationOccupied(l) and w.isPassable(l):
      return l
  loc(-1, -1)

proc firstIslandTile(w: World): Loc =
  ## The lowest tile index of the lowest island id. No hashing, no RNG.
  if w.islands.len == 0: return loc(-1, -1)
  if w.islands[0].tiles.len == 0: return loc(-1, -1)
  w.islands[0].tiles[0]

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
    let l = firstFreeTile(w, r.loc)
    if l.x >= 0 and w.canBuildRobot(r, rtCarrier, l):
      discard w.doBuildRobot(r, rtCarrier, l)
  if round == 3 or round mod 41 == 0:
    let l = firstFreeTile(w, r.loc)
    if l.x >= 0 and w.canBuildRobot(r, rtLauncher, l):
      discard w.doBuildRobot(r, rtLauncher, l)
  if round == 4:
    let l = firstFreeTile(w, r.loc)
    if l.x >= 0 and w.canBuildRobot(r, rtAmplifier, l):
      discard w.doBuildRobot(r, rtAmplifier, l)
  ## FIVE ACTIONS IN ONE TURN, forced once, so the cooldown rule is exercised.
  if round == 30:
    for k in 0 ..< 6:
      let l = firstFreeTile(w, r.loc)
      if l.x < 0: break
      if not w.canBuildRobot(r, rtCarrier, l): break
      discard w.doBuildRobot(r, rtCarrier, l)
  if round >= 6 and w.canBuildAnchor(r, anStandard) and
      w.anchorsInStock(r.team) == 0:
    discard w.doBuildAnchor(r, anStandard)
  if w.canBuildAnchor(r, anAccelerating):
    discard w.doBuildAnchor(r, anAccelerating)
  if r.elixir >= buildCost(rtDestabilizer, resElixir) and round mod 50 == 0:
    let l = firstFreeTile(w, r.loc)
    if l.x >= 0 and w.canBuildRobot(r, rtDestabilizer, l):
      discard w.doBuildRobot(r, rtDestabilizer, l)
  if r.elixir >= buildCost(rtBooster, resElixir) and round mod 51 == 0:
    let l = firstFreeTile(w, r.loc)
    if l.x >= 0 and w.canBuildRobot(r, rtBooster, l):
      discard w.doBuildRobot(r, rtBooster, l)
  ## A headquarters may always write.
  discard simcomms.doWriteSharedArray(w, r, round mod 64, round mod 65536)

proc scenarioCarrier(w: World, r: Robot) =
  let round = w.currentRound
  ## Holding an anchor: ferry it to the first island tile and plant it.
  if r.totalAnchors > 0:
    let target = firstIslandTile(w)
    if target.x >= 0:
      if w.islandAt(r.loc) >= 0:
        discard w.doPlaceAnchor(r)
      else:
        stepToward(w, r, target)
    return
  ## Empty and a headquarters holds an anchor: go and take it.
  if r.weight == 0 and w.anchorsInStock(r.team) > 0:
    for id in w.headquarters[ord(r.team)]:
      if not w.existsRobot(id): continue
      let hq = w.robotsById[id]
      if hq.totalAnchors == 0: continue
      if r.loc.isAdjacentTo(hq.loc):
        let kind = hq.typeAnchor()
        if kind != anNone and w.canTakeAnchor(r, hq.loc, kind):
          discard w.doTakeAnchor(r, hq.loc, kind)
          return
      else:
        stepToward(w, r, hq.loc)
        return
  ## Full: deposit at the first friendly headquarters we are beside, or pour
  ## into the first well we are beside once the round is past 200 (the
  ## transformation and the rate upgrade both have to fire).
  if r.weight >= CarrierCapacity or (r.weight > 0 and round mod 7 == 0):
    for l in w.locationsWithinRadiusSquared(r.loc,
        RobotSpecs[rtCarrier].actionRadiusSquared):
      if not r.loc.isAdjacentTo(l): continue
      if round >= 200 and w.isWell(l):
        for t in RealResources:
          if r.resourceOf(t) > 0 and w.canTransferResource(r, l, t,
              r.resourceOf(t)):
            discard w.doTransferResource(r, l, t, r.resourceOf(t))
            return
      if w.isHeadquarters(l) and w.getRobot(l).team == r.team:
        for t in RealResources:
          if r.resourceOf(t) > 0 and w.canTransferResource(r, l, t,
              r.resourceOf(t)):
            discard w.doTransferResource(r, l, t, r.resourceOf(t))
            return
    if w.headquarters[ord(r.team)].len > 0 and
        w.existsRobot(w.headquarters[ord(r.team)][0]):
      stepToward(w, r, w.robotsById[w.headquarters[ord(r.team)][0]].loc)
    return
  ## Otherwise mine the first collectable well tile in the 3x3.
  for ddx in -1 .. 1:
    for ddy in -1 .. 1:
      let l = r.loc.translate(ddx, ddy)
      if w.onTheMap(l) and w.canCollectResource(r, l, -1):
        discard w.doCollectResource(r, l, -1)
        return
  ## Nothing to mine: walk to the first well on the map, in index order.
  for i in 0 ..< w.wellAt.len:
    if w.wellAt[i].present:
      stepToward(w, r, w.indexToLoc(i))
      return
  ## Throw at the first enemy in scan order, so the throw path fires.
  if r.weight > 0 and round mod 13 == 0:
    for l in w.locationsWithinRadiusSquared(r.loc,
        RobotSpecs[rtCarrier].actionRadiusSquared):
      let other = w.getRobot(l)
      if other != nil and other.team != r.team and
          other.kind != rtHeadquarters and w.canAttack(r, l):
        discard w.doAttack(r, l)
        return

proc scenarioLauncher(w: World, r: Robot) =
  for l in w.locationsWithinRadiusSquared(r.loc,
      RobotSpecs[rtLauncher].actionRadiusSquared):
    let other = w.getRobot(l)
    if other != nil and other.team != r.team and
        other.kind != rtHeadquarters and w.canAttack(r, l):
      discard w.doAttack(r, l)
      break
  let target = firstIslandTile(w)
  if target.x >= 0: stepToward(w, r, target)

proc scenarioDestabilizer(w: World, r: Robot) =
  if w.canDestabilize(r, r.loc):
    discard w.doDestabilize(r, r.loc)
  else:
    stepToward(w, r, firstIslandTile(w))

proc scenarioBooster(w: World, r: Robot) =
  if w.canBoost(r):
    discard w.doBoost(r)
  else:
    stepToward(w, r, firstIslandTile(w))

proc scenarioAmplifier(w: World, r: Robot) =
  ## The write-window probe: an amplifier may always write, and every robot
  ## near it may too.
  discard simcomms.doWriteSharedArray(w, r, 63, w.currentRound mod 65536)
  if w.currentRound == 500:
    ## Exercise the disintegrate path exactly once.
    w.disintegrate(r)
    return
  stepToward(w, r, firstIslandTile(w))

proc runScenario23*(w: World, r: Robot) =
  case r.kind
  of rtHeadquarters: scenarioHeadquarters(w, r)
  of rtCarrier: scenarioCarrier(w, r)
  of rtLauncher: scenarioLauncher(w, r)
  of rtDestabilizer: scenarioDestabilizer(w, r)
  of rtBooster: scenarioBooster(w, r)
  of rtAmplifier: scenarioAmplifier(w, r)
