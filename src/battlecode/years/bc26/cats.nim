## The NPC cat state machine — `InternalRobot.processEndOfTurn`'s cat branch
## at tag `engine.1.2.5`, ported statement for statement.
##
## Two quirks in here are engine behaviour, not bugs in this port, and both
## change where cats actually go:
##
## * A cat that RE-FINDS its existing target chases the location stored in the
##   `RobotInfo` **snapshot** it took when it first saw the rat, not the rat's
##   live tile (`InternalRobot.java:1326`). It only refreshes when it picks a
##   new target.
## * The "look for a new target" loop has **no `break`**, so the LAST rat in
##   sense order wins — which is why `allLocationsInCone`'s chirality-reversed
##   sweep has to be exact.

import ../../rng
import constants, world

proc randomDir(w: World): Dir =
  NonCenterDirs[int(w.catRand.nextInt(NonCenterDirs.len))]

proc tryDigOrAttackAhead(w: World, r: Robot): bool =
  ## The engine's per-part-location loop: try to dig the blocking dirt, else
  ## bite whatever is standing there. Returns whether the cat did something.
  var didSomething = false
  for partLoc in w.allPartLocations(r):
    let nextLoc = partLoc + r.dir
    if w.canRemoveDirt(r, nextLoc):
      w.removeDirt(r, nextLoc)
      w.addActionCooldown(r, CatDigAdditionalCooldown)
      didSomething = true
    elif w.canAttack(r, nextLoc):
      w.attack(r, nextLoc)
      didSomething = true
      if r.dead: return true
  didSomething

proc canPounce(w: World, r: Robot, target: Loc): (bool, int, int) =
  ## `InternalRobot.canPounce`. Corner order comes from
  ## `getAllCatLocationsByChirality`, so the chosen trajectory depends on
  ## chirality.
  if not r.canMoveCooldown: return (false, 0, 0)
  let withinPounce =
    r.loc.bottomLeftDistanceSquaredTo(target) <=
      float32(CatPounceMaxDistanceSquared)
  if not w.onTheMap(target) or not w.isPassable(target) or not withinPounce:
    return (false, 0, 0)
  let parts = w.allPartLocations(r)
  for cornerToTest in parts:
    let toCentre = cornerToTest.directionTo(r.loc)
    let dx = toCentre.dx + (target.x - r.loc.x)
    let dy = toCentre.dy + (target.y - r.loc.y)
    var valid = true
    for tile in parts:
      let landing = tile.translate(dx, dy)
      if not w.onTheMap(landing):
        valid = false
      elif not w.isPassable(landing):
        valid = false
      else:
        let there = w.getRobot(landing)
        if there != nil and there.unit == utCat: valid = false
        elif there != nil and there.unit == utRatKing: valid = false
    if valid:
      return (true, dx, dy)
  (false, 0, 0)

proc pounce(w: World, r: Robot, dx, dy: int) =
  for partLoc in w.allPartLocations(r):
    let translated = partLoc.translate(dx, dy)
    let crushed = w.getRobot(translated)
    if crushed != nil and crushed.id != r.id:
      if crushed.isCarryingRobot:
        let carried = crushed.carrying
        w.addHealth(carried, -carried.health)
      w.addHealth(crushed, -crushed.health)
  if r.dead: return
  ## `translateLocation` is not exported; `move`'s crush handling would
  ## double-apply, so the pounce translation is done through the same
  ## primitive the engine uses: a raw part-location shift.
  let before = w.allPartLocations(r)
  for pl in before:
    if w.onTheMap(pl) and w.getRobot(pl) == r:
      w.occupant[w.idx(pl)] = nil
  r.loc = r.loc.translate(dx, dy)
  for pl in w.allPartLocations(r):
    if w.onTheMap(pl):
      w.occupant[w.idx(pl)] = r
  for partLoc in w.allPartLocations(r):
    w.processTrapsAtLocation(r, partLoc)
    if r.dead: return
  w.addMovementCooldown(r, r.dir)
  w.addMovementCooldown(r, r.dir)

proc runCatTurn*(w: World, r: Robot) =
  ## The whole cat branch. Called from `rules.processEndOfTurn`.
  if r.sleepTimeRemaining > 0:
    r.sleepTimeRemaining -= 1
    return
  if r.dir == dCenter:
    r.dir = w.randomDir()

  case r.catState
  of csExplore:
    var enteredAttack = false
    if r.catTurnsStuck >= 4:
      let random = w.randomDir()
      if w.canTurn(r):
        w.turn(r, random)
    elif r.catTurnsStuck == 0 and r.catWaypoints.len > 0:
      let waypoint = r.catWaypoints[r.currentWaypoint]
      if w.catCornerByChirality(r) == waypoint:
        if r.currentWaypoint == r.previousWaypoint:
          r.currentWaypoint = (r.currentWaypoint + 1) mod r.catWaypoints.len
        else:
          r.previousWaypoint = r.currentWaypoint
          r.catState = csAttack
          enteredAttack = true
      if not enteredAttack:
        r.catTargetLoc = r.catWaypoints[r.currentWaypoint]
        r.catTargetLocValid = true
        r.dir = w.getBfsDir(w.catCornerByChirality(r), r.catTargetLoc, r.chirality)
        if r.dir == dCenter:
          r.dir = w.catCornerByChirality(r).directionTo(r.catTargetLoc)
          if r.dir == dCenter:
            r.dir = w.randomDir()
    if enteredAttack:
      return

    if w.canMove(r, r.dir):
      w.move(r, r.dir)
      r.catTurnsStuck = 0
    else:
      var isStuck = not w.tryDigOrAttackAhead(r)
      if r.dead: return
      if isStuck:
        let twoTilesAway = w.catCornerByChirality(r) + r.dir + r.dir
        let (ok, dx, dy) = w.canPounce(r, twoTilesAway)
        if r.canMoveCooldown and ok:
          w.pounce(r, dx, dy)
          isStuck = false
          if r.dead: return
      if isStuck:
        r.catTurnsStuck += 1
      else:
        r.catTurnsStuck = 0

  of csAttack:
    r.catTurns += 1
    if r.catTurns > 8:
      r.catTurns = 0
      r.catState = csExplore
      return

    ## First squeak heard this turn distracts the cat.
    var haveSqueak = false
    var squeakSource: Loc
    if r.inbox.len > 0:
      haveSqueak = true
      squeakSource = r.inbox[0].source
    r.inbox.setLen(0)
    let nearbyRobots = w.senseNearbyRobots(r)
    if haveSqueak and r.loc.directionTo(squeakSource) != dCenter:
      r.dir = r.loc.directionTo(squeakSource)

    var sensedRat = false
    if r.catTargetId >= 0:
      for other in nearbyRobots:
        if other.id == r.catTargetId:
          sensedRat = true
          ## The SNAPSHOT location, deliberately: see the module doc comment.
          break
    if not sensedRat:
      r.catTargetId = -1
      r.catTargetLocValid = false
      ## No break: the LAST rat in sense order becomes the target.
      for other in nearbyRobots:
        if other.unit == utBabyRat or other.unit == utRatKing:
          sensedRat = true
          r.catTargetId = other.id
          r.catTargetLoc = other.loc
          r.catTargetLocValid = true

    if r.catTargetLocValid:
      if w.canAttack(r, r.catTargetLoc):
        w.attack(r, r.catTargetLoc)
        return
      else:
        let (ok, dx, dy) = w.canPounce(r, r.catTargetLoc)
        if r.canMoveCooldown and ok:
          w.pounce(r, dx, dy)
          return
        else:
          r.dir = w.getBfsDir(w.catCornerByChirality(r), r.catTargetLoc, r.chirality)
          if r.dir == dCenter:
            r.dir = w.catCornerByChirality(r).directionTo(r.catTargetLoc)
            if r.dir == dCenter:
              r.dir = w.randomDir()
          if w.canMove(r, r.dir):
            w.move(r, r.dir)
            r.catTurnsStuck = 0
            return
          else:
            for partLoc in w.allPartLocations(r):
              let nextLoc = partLoc + r.dir
              if w.canRemoveDirt(r, nextLoc):
                w.removeDirt(r, nextLoc)
                w.addActionCooldown(r, CatDigAdditionalCooldown)
                break

    ## Nothing worked: rotate in place.
    if w.canTurn(r):
      if r.chirality == 0:
        w.turn(r, r.dir.rotateRight())
      else:
        w.turn(r, r.dir.rotateLeft())
