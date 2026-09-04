## The Fulfillment Center: build a Delivery Drone whenever the roster is under
## `4 + round/300` (capped 14) and the pool can pay.
##
## The design note's second clause — "and always when `NEED_DRONES` is on the
## chain" — is NOT implemented: nothing in this chassis broadcasts
## `NEED_DRONES`, so the branch would be dead code guarding a signal that never
## arrives. `SigNeedDrones` keeps its code point (removing it would renumber
## the signal table and change every recorded message) and is marked reserved
## in `signals.nim`. §Divergences item 15 in `docs/RULES-BC20.md`.
##
## Behaviour, not code, from `StoneT2000/Battlecode2020` (AGPL-3.0; see NOTICE).

import kit

proc droneTarget*(round: int): int = min(14, 4 + round div 300)

proc runFulfillmentCenter*(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)
  brain.turnCount += 1
  if not isReady(r): return
  if w.alive(side, rtDeliveryDrone) >= droneTarget(w.currentRound): return
  if w.stats.soup[ord(side.team)] < RobotSpecs[rtDeliveryDrone].cost: return
  for d in MoveDirs:
    if not r.spend(1): break
    if not w.canBuildRobot(r, rtDeliveryDrone, d): continue
    if w.buildRobot(r, rtDeliveryDrone, d) >= 0:
      w.firstBuild(side, rtDeliveryDrone)
    return
