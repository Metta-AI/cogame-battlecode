## `examplefuncsplayer23` — the weak floor and the parity oracle's other side.
##
## Ported STATEMENT FOR STATEMENT from
## `battlecode23/example-bots/src/main/examplefuncsplayer/RobotPlayer.java` at
## commit `af42086ecd09709dc603b2aaa9e9b98312c9ef79`. IT MAY NOT GAIN
## BEHAVIOUR: it is one side of the differential oracle, and a "fix" here is a
## parity failure, not an improvement.
##
## Four things are load-bearing and are reproduced exactly:
##
## * **the `Random(6147)` call sequence.** `static final Random rng` is a
##   static field, and static fields are PER ROBOT under the instrumenter, so
##   every robot gets its own stream from the same seed — which is why this
##   bot needs no determinism patch, exactly as in bc24 and bc25. The calls,
##   in order: a headquarters draws `nextInt(8)` then `nextBoolean()`; a
##   carrier draws `nextBoolean()` once per COLLECTABLE well tile in its 3x3,
##   then `nextInt(20)`, then `nextInt(3)` when it can see more than one well,
##   then `nextInt(8)`; a launcher draws `nextInt(8)`.
## * **the eight `directions` IN THE FILE'S OWN ORDER** — NORTH, NORTHEAST,
##   EAST, SOUTHEAST, SOUTH, SOUTHWEST, WEST, NORTHWEST — because
##   `rng.nextInt(8)` indexes it.
## * **the launcher attacks the square ONE STEP EAST OF ITSELF**, not the
##   enemy it just sensed (`toAttack = rc.getLocation().add(Direction.EAST)`;
##   the sensible line is commented out upstream).
## * **the anchor branch's `HashSet<MapLocation>` iteration order**, which
##   depends on `MapLocation.hashCode() = (y + 0x8000) & 0xffff | (x << 16)`
##   and on `HashSet`'s table size. It is DEAD CODE IN PRACTICE — the bot
##   never calls `takeAnchor`, so its carriers never hold anchors — but it is
##   reproduced anyway because a parity oracle whose two sides differ on an
##   unreachable branch is one refactor away from differing on a reachable
##   one. `tests/test_bc23_scaffold.nim` pins it.

import ../world, ../comms as simcomms

export world

const
  ScaffoldDirections* = [dNorth, dNortheast, dEast, dSoutheast,
                         dSouth, dSouthwest, dWest, dNorthwest]
    ## `directions` in the file's own order; `rng.nextInt(8)` indexes it.

func javaHashCode*(l: Loc): int32 =
  ## `MapLocation.hashCode()`, in 32-bit two's complement.
  int32(((l.y + 0x8000) and 0xffff) or (l.x shl 16))

func spread(h: int32): int32 =
  ## `HashMap.hash(key)`: `h ^ (h >>> 16)`, an UNSIGNED right shift.
  let u = cast[uint32](h)
  cast[int32](u xor (u shr 16))

proc javaHashSetFirst*(locs: seq[Loc]): Loc =
  ## The first element `new HashSet<MapLocation>(...).iterator().next()`
  ## returns, reproduced from Java's own table geometry.
  ##
  ## `HashMap` starts at capacity 16 with threshold 12 and doubles whenever
  ## `size > threshold`; a resize SPLITS each bucket preserving the relative
  ## order of its entries, so inserting every distinct key in insertion order
  ## into a table of the FINAL capacity gives the same chains. Iteration then
  ## walks buckets ascending and each chain in insertion order.
  result = loc(-1, -1)
  var distinctLocs: seq[Loc]
  for l in locs:
    var seen = false
    for d in distinctLocs:
      if d == l:
        seen = true
        break
    if not seen: distinctLocs.add(l)
  if distinctLocs.len == 0: return
  var cap = 16
  while distinctLocs.len > (cap * 3) div 4: cap = cap * 2
  var bestBucket = cap
  for l in distinctLocs:
    let bucket = int(cast[uint32](spread(javaHashCode(l)))) and (cap - 1)
    if bucket < bestBucket:
      bestBucket = bucket
      result = l

proc runScaffoldHeadquarters(w: World, r: Robot) =
  let dir = ScaffoldDirections[r.scaffoldRng.nextInt(8)]
  let newLoc = r.loc + dir
  if w.canBuildAnchor(r, anStandard):
    w.doBuildAnchor(r, anStandard)
  if r.scaffoldRng.nextBoolean():
    if w.canBuildRobot(r, rtCarrier, newLoc):
      discard w.doBuildRobot(r, rtCarrier, newLoc)
      w.noteFirstAction(r.team, Bc23ActionBuildRobot)
  else:
    if w.canBuildRobot(r, rtLauncher, newLoc):
      discard w.doBuildRobot(r, rtLauncher, newLoc)
      w.noteFirstAction(r.team, Bc23ActionBuildRobot)

proc runScaffoldCarrier(w: World, r: Robot) =
  if r.typeAnchor() != anNone:
    ## Dead code in practice: this bot never calls `takeAnchor`.
    var islandLocs: seq[Loc]
    for islandIdx in w.senseNearbyIslands(r,
        RobotSpecs[r.kind].visionRadiusSquared):
      for tile in w.islands[islandIdx].tiles:
        if w.canSenseLocation(r, tile): islandLocs.add(tile)
    if islandLocs.len > 0:
      let islandLocation = javaHashSetFirst(islandLocs)
      ## `while (!rc.getLocation().equals(islandLocation))` is an UNBOUNDED
      ## loop upstream; in the JVM the bytecode limit ends the turn. Here the
      ## `DecisionOps` budget does exactly the same job.
      while not (r.loc == islandLocation):
        if not r.spend(4): break
        let dir = r.loc.directionTo(islandLocation)
        if w.canMove(r, dir):
          w.doMove(r, dir)
        else:
          break
      ## `rc.canPlaceAnchor()` is upstream's own guard, and it includes the
      ## enemy-anchor test.
      let islandIdx = w.islandAt(r.loc)
      if r.isActionReady() and islandIdx >= 0 and r.totalAnchors > 0 and
          w.islands[islandIdx].canPlaceAnchor(r.team):
        discard w.doPlaceAnchor(r)

  ## Try to gather from squares around us: dx and dy BOTH from -1 to 1, so
  ## the robot's own tile is included.
  let me = r.loc
  for ddx in -1 .. 1:
    for ddy in -1 .. 1:
      let wellLocation = me.translate(ddx, ddy)
      if not r.spend(1): break
      if w.onTheMap(wellLocation) and
          w.canCollectResource(r, wellLocation, -1):
        if r.scaffoldRng.nextBoolean():
          discard w.doCollectResource(r, wellLocation, -1)
          w.noteFirstAction(r.team, Bc23ActionCollect)

  ## Occasionally try out the carrier's attack.
  if r.scaffoldRng.nextInt(20) == 1:
    var first: Robot = nil
    for other in w.senseNearbyRobots(r, RobotSpecs[r.kind].visionRadiusSquared,
                                     ord(r.team.other())):
      first = other
      break
    if first != nil and w.canAttack(r, first.loc):
      discard w.doAttack(r, first.loc)
      w.noteFirstAction(r.team, Bc23ActionThrow)

  ## If we can see more than one well, move toward `wells[1]`.
  var wells: seq[Loc]
  for l in w.senseNearbyWells(r, RobotSpecs[r.kind].visionRadiusSquared):
    wells.add(l)
  if wells.len > 1 and r.scaffoldRng.nextInt(3) == 1:
    let dir = me.directionTo(wells[1])
    if w.canMove(r, dir):
      w.doMove(r, dir)

  ## Also try to move randomly.
  let dir = ScaffoldDirections[r.scaffoldRng.nextInt(8)]
  if w.canMove(r, dir):
    w.doMove(r, dir)

proc runScaffoldLauncher(w: World, r: Robot) =
  ## `enemies.length >= 0` is always true, so the branch always runs — and
  ## `toAttack` is the square ONE STEP EAST, not the enemy.
  let toAttack = r.loc + dEast
  if w.canAttack(r, toAttack):
    discard w.doAttack(r, toAttack)
    w.noteFirstAction(r.team, Bc23ActionAttack)
  let dir = ScaffoldDirections[r.scaffoldRng.nextInt(8)]
  if w.canMove(r, dir):
    w.doMove(r, dir)

proc runScaffold23*(w: World, r: Robot) =
  ## The `switch (rc.getType())`: BOOSTER, DESTABILIZER and AMPLIFIER all
  ## `break` without doing anything, and this bot never builds one anyway.
  r.scaffoldTurns += 1
  case r.kind
  of rtHeadquarters: runScaffoldHeadquarters(w, r)
  of rtCarrier: runScaffoldCarrier(w, r)
  of rtLauncher: runScaffoldLauncher(w, r)
  else: discard
