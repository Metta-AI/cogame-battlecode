## `examplefuncsplayer` — the weak floor and the parity oracle's other side.
##
## Ported STATEMENT FOR STATEMENT from
## `battlecode20/example-bots/src/main/examplefuncsplayer/RobotPlayer.java` at
## the pinned commit. The fidelity is the point: `parity-oracle` runs the Java
## engine driving the real examplefuncsplayer against itself and diffs the
## trace row for row against this (docs/PARITY.md). **It may not gain
## behaviour.** A "helpful" addition here — walling, terraforming, choosing a
## better direction — would break the only test that proves the ported rule set
## is the same rule set.
##
## Two upstream facts that look like bugs and are load-bearing:
##
##  * `tryBlockchain` builds `new int[10]`, and
##    `assertCanSubmitTransaction` rejects anything whose length is not
##    `BLOCKCHAIN_TRANSACTION_LENGTH = 7`. So `canSubmitTransaction` is always
##    false and **examplefuncsplayer never mints a transaction in 2020**. The
##    attempt is reproduced, and so is the refusal.
##  * `randomDirection()` calls `Math.random()`, which is wall-clock seeded, so
##    the stock bot is not reproducible even against itself. The CI oracle runs
##    a one-hunk patch of that file that replaces the single live call site
##    with a per-robot `new java.util.Random(rc.getID())`; this port reproduces
##    exactly that stream through `rng.nim`.

import kit

const
  Directions = [dNorth, dEast, dSouth, dWest]
    ## `RobotPlayer.directions`, in its own order — the random index means the
    ## order is part of the behaviour.
  ScaffoldMessageLength = 10
    ## `new int[10]`. Kept as a named constant so the length refusal below is
    ## obviously the upstream file's and not a typo here.
  ScaffoldMessageValue = 123
  ScaffoldMessageCost = 10

proc randomDirection(brain: Brain): Dir =
  Directions[int(brain.rng.nextDouble() * float(Directions.len))]

proc tryMove(w: World, r: Robot, d: Dir): bool {.discardable.} =
  if isReady(r) and w.canMove(r, d):
    w.move(r, d)
    return true
  false

proc tryBuild(w: World, r: Robot, kind: RobotKind, d: Dir): bool
    {.discardable.} =
  if isReady(r) and w.canBuildRobot(r, kind, d):
    w.buildRobot(r, kind, d)
    return true
  false

proc tryMine(w: World, r: Robot, d: Dir): bool {.discardable.} =
  if isReady(r) and w.canMineSoup(r, d):
    w.mineSoup(r, d)
    return true
  false

proc tryDepositSoup(w: World, r: Robot, d: Dir): bool {.discardable.} =
  if isReady(r) and w.canDepositSoup(r, d):
    w.depositSoup(r, d, r.soupCarrying)
    return true
  false

proc tryBlockchain(w: World, r: Robot, brain: Brain) =
  ## `turnCount < 3`, i.e. the robot's first two turns. The message is ten ints
  ## of 123 and the engine's own length check refuses it, so nothing is ever
  ## submitted — reproduced, not corrected.
  if brain.turnCount >= 3: return
  if ScaffoldMessageLength != TransactionLength: return
  var message: array[TransactionLength, int]
  for i in 0 ..< TransactionLength:
    message[i] = ScaffoldMessageValue
  if w.canSubmitTransaction(r, ScaffoldMessageCost):
    w.submitTransaction(r, message, ScaffoldMessageCost)

proc runHq(w: World, r: Robot) =
  for d in Directions:
    if not r.spend(1): return
    w.tryBuild(r, rtMiner, d)

proc runMiner(w: World, side: Side, r: Robot, brain: Brain) =
  w.tryBlockchain(r, brain)
  ## BOTH `randomDirection()` draws are always consumed, because the second is
  ## the argument of a `tryMove` inside an `if`.
  let first = brain.randomDirection()
  let second = brain.randomDirection()
  w.tryMove(r, first)
  w.tryMove(r, second)
  for d in Directions:
    if not r.spend(1): return
    w.tryBuild(r, rtFulfillmentCenter, d)
  for d in Directions:
    if not r.spend(1): return
    w.tryDepositSoup(r, d)
  for d in Directions:
    if not r.spend(1): return
    w.tryMine(r, d)

proc runFulfillmentCenter(w: World, r: Robot) =
  for d in Directions:
    if not r.spend(1): return
    w.tryBuild(r, rtDeliveryDrone, d)

proc runDeliveryDrone(w: World, side: Side, r: Robot, brain: Brain) =
  if not r.holdingUnit:
    ## `senseNearbyRobots(DELIVERY_DRONE_PICKUP_RADIUS_SQUARED, enemy)` returns
    ## the window in `getAllLocationsWithinRadiusSquared` order — x then y —
    ## and the bot takes `robots[0]`.
    for l in w.locationsWithinRadiusSquared(r.loc,
        DeliveryDronePickupRadiusSquared):
      if not r.spend(1): return
      let target = w.getRobot(l)
      if target == nil: continue
      if target.id == r.id: continue
      if not w.canSenseLocation(r, l): continue
      if target.team != side.team.other(): continue
      if w.canPickUpUnit(r, target.id):
        w.pickUpUnit(r, target.id)
      return
  else:
    w.tryMove(r, brain.randomDirection())

proc runScaffold*(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)
  brain.turnCount += 1
  case r.kind
  of rtHq: w.runHq(r)
  of rtMiner: w.runMiner(side, r, brain)
  of rtFulfillmentCenter: w.runFulfillmentCenter(r)
  of rtDeliveryDrone: w.runDeliveryDrone(side, r, brain)
  of rtRefinery, rtVaporator, rtDesignSchool, rtLandscaper, rtNetGun, rtCow:
    discard
