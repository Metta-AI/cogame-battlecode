## The bc23 shared arrays and the write window.
##
## A behaviour port of `TeamInfo.readSharedArray` / `writeSharedArray`,
## `RobotControllerImpl.assertCanWriteSharedArray` and
## `GameWorld.inRangeForAmplification` at commit
## `af42086ecd09709dc603b2aaa9e9b98312c9ef79`.
##
## Each team owns 64 slots of 0…65535. READING IS ALWAYS LEGAL, from any
## robot, at any distance, and neither team can read the other's array.
## WRITING has a window:
##
## * a HEADQUARTERS or an AMPLIFIER may always write;
## * any other robot needs a friendly amplifier within r² ≤ 20, a friendly
##   headquarters within r² ≤ 9, or one of ITS OWN islands within r² ≤ 4
##   (`Island.minDistTo`, i.e. the squared distance to the nearest island
##   tile).
##
## There is NO COOLDOWN AND NO COST. The port charges one `DecisionOps`
## credit per slot read or written, which is telemetry on the chassis's
## chatter and never a rule.

import world

export world

func canWriteSharedArray*(w: World, r: Robot, index, value: int): bool =
  if index < 0 or index >= SharedArrayLength: return false
  if value < 0 or value > MaxSharedArrayValue: return false
  if r.kind == rtHeadquarters or r.kind == rtAmplifier: return true
  ## `GameWorld.inRangeForAmplification`: ONE sweep at the larger of the two
  ## radii, then a per-type distance test inside it — which is why an
  ## amplifier at r² = 15 qualifies and a headquarters at r² = 15 does not.
  let maxInterest = max(DistanceSquaredFromHeadquarter,
                        DistanceSquaredFromSignalAmplifier)
  for l in w.locationsWithinRadiusSquared(r.loc, maxInterest):
    let other = w.getRobot(l)
    if other == nil or other.team != r.team or other.id == r.id: continue
    var maxDistance = 0
    if other.kind == rtAmplifier:
      maxDistance = DistanceSquaredFromSignalAmplifier
    elif other.kind == rtHeadquarters:
      maxDistance = DistanceSquaredFromHeadquarter
    if other.loc.distanceSquaredTo(r.loc) <= maxDistance: return true
  for isl in w.islands:
    if isl.isOwnedBy(r.team) and isl.minDistTo(r.loc) <=
        DistanceSquaredFromIsland:
      return true
  false

func readSharedArray*(w: World, t: Team, index: int): int =
  if index < 0 or index >= SharedArrayLength: 0
  else: w.stats.sharedArray[ord(t)][index]

proc doWriteSharedArray*(w: World, r: Robot, index,
                         value: int): bool {.discardable.} =
  if not w.canWriteSharedArray(r, index, value):
    w.refusedActions += 1
    return false
  w.stats.sharedArray[ord(r.team)][index] = value
  w.stats.arrayWrites[ord(r.team)] += 1
  true
