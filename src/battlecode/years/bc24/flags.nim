## bc24 flags: pickup, drop, the same-round-drop refusal, `locIsStartRef`, the
## round-200 confirmation, the return timer and the broadcast re-roll.
##
## Ported from `RobotControllerImpl.assertCanPickupFlag` / `pickupFlag` /
## `assertCanDropFlag` / `dropFlag`, `GameWorld.processEndOfRound` /
## `processEndOfSetupPhase` / `confirmFlagPlacements` /
## `updateFlagBroadcastLocations` and `world/Flag.java`.
##
## THE OBJECT-IDENTITY TEST. `flag.getLoc() != flag.getStartLoc()` in Java
## compares REFERENCES, not coordinates. It is true exactly when the flag has
## moved since the last time `moveFlagSetStartLoc` pointed both at the same
## object. `locIsStartRef` is that boolean, made explicit. Two consequences the
## port keeps: a flag dropped exactly on its own start TILE still runs a return
## timer (and returns to the same tile), and it cannot be picked up in the round
## it was dropped.

import world

export world

proc canPickupFlag*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanPickupFlag`. The two booleans are checked SEPARATELY over all
  ## flags on the tile, exactly as the engine checks them: a team-eligible flag
  ## and a rounds-eligible flag need not be the same flag.
  if not r.spawned: return false
  if r.loc.distanceSquaredTo(l) > InteractRadiusSquared: return false
  if not w.onTheMap(l): return false
  if not r.canActCooldown(): return false
  if r.hasFlag(): return false
  let here = w.placedFlags[w.idx(l)]
  if here.len == 0: return false
  let setup = w.isSetupPhase()
  let want = if setup: r.team else: r.team.other()
  var teamOk = false
  var roundsOk = false
  for f in here:
    if f.team == want: teamOk = true
    if setup or f.locIsStartRef or f.droppedRounds != 0: roundsOk = true
  teamOk and roundsOk

proc pickupFlag*(w: World, r: Robot, l: Loc) =
  ## Takes the FIRST flag on the tile belonging to the pickup-eligible team —
  ## tile lists are append-ordered, so that is "oldest dropped first". If the
  ## duck is already standing in a friendly spawn zone with an enemy flag, it
  ## captures on the spot.
  if not w.canPickupFlag(r, l):
    w.refusedActions += 1
    return
  let setup = w.isSetupPhase()
  let want = if setup: r.team else: r.team.other()
  var chosen: Flag = nil
  for f in w.placedFlags[w.idx(l)]:
    if f.team == want:
      chosen = f
      break
  if chosen == nil: return
  w.removeFlagAt(l, chosen)
  r.flag = chosen
  chosen.carriedBy = r.id
  chosen.droppedRounds = 0
  chosen.loc = r.loc
  chosen.locIsStartRef = false
  r.actionCooldown += PickupDropCooldown
  if not setup:
    w.stats.flagsPickedUp[ord(r.team)] += 1
    if w.currentRound < 700:
      w.stats.pickupsBeforeRound700[ord(r.team)] += 1
    discard w.beat(BeatFlagTaken, "flag_taken", ord(r.team), chosen.id,
      r.loc.x * 100 + r.loc.y)

  w.noteFirstAction(r, Bc24ActionPickup)

  if chosen.team != r.team and w.getSpawnZone(r.loc) == ord(r.team) + 1:
    w.captureFlagFor(r)

proc canDropFlag*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanDropFlag`.
  if not r.spawned: return false
  if r.loc.distanceSquaredTo(l) > InteractRadiusSquared: return false
  if not w.onTheMap(l): return false
  if not r.canActCooldown(): return false
  if not r.hasFlag(): return false
  w.isPassable(l)

proc dropFlag*(w: World, r: Robot, l: Loc) =
  ## `RobotControllerImpl.dropFlag`: place, +10 action, release, THEN
  ## `addMovementCooldownTurns()` — which by then sees `hasFlag() == false`
  ## and therefore charges a flat +10.
  if not w.canDropFlag(r, l):
    w.refusedActions += 1
    return
  let f = r.flag
  w.addFlagAt(l, f)
  r.actionCooldown += PickupDropCooldown
  r.flag = nil
  f.carriedBy = -1
  f.droppedRounds = 0
  w.stats.flagsDropped[ord(r.team)] += 1
  discard w.beat(BeatFlagDropped, "flag_dropped", ord(r.team), f.id,
    l.x * 100 + l.y, "dropped")
  w.noteFirstAction(r, Bc24ActionDrop)
  w.addMovementCooldownTurns(r)

# ---------------------------------------------------------------------------
#  End-of-round flag machinery
# ---------------------------------------------------------------------------

proc confirmFlagPlacements*(w: World, team: Team) =
  ## `GameWorld.confirmFlagPlacements`, per team INDEPENDENTLY: if all three of
  ## that team's flags are pairwise `dist^2 >= 36` the placements stick, and
  ## otherwise ALL THREE teleport back to their previous start locations.
  ## Either way a carried flag is taken off its carrier first.
  var flags: seq[Flag]
  for f in w.allFlags:
    if f.team == team: flags.add(f)
  var valid = true
  for i in 0 ..< flags.len:
    for j in i + 1 ..< flags.len:
      if flags[i].loc.distanceSquaredTo(flags[j].loc) < MinFlagSpacingSquared:
        valid = false
  if valid:
    for f in flags: w.moveFlagSetStartLoc(f, f.loc)
  else:
    w.stats.setupFlagTeleports += 1
    for f in flags: w.moveFlagSetStartLoc(f, f.startLoc)

proc processEndOfSetupPhase*(w: World) =
  w.confirmFlagPlacements(teamA)
  w.confirmFlagPlacements(teamB)

proc resetDroppedFlags*(w: World) =
  ## `GameWorld.processEndOfRound`'s second block. The return delay is 4
  ## rounds, or 25 when THE OPPONENT of the flag's owner holds CAPTURING.
  for f in w.allFlags:
    if f.carriedBy >= 0: continue
    if f.locIsStartRef: continue
    var extra = 0
    if w.hasUpgrade(f.team.other(), 1):
      extra = UpgradeSpecs[ugCapturing].flagReturnDelayChange
    if f.droppedRounds >= FlagDroppedResetRounds + extra:
      w.moveFlagSetStartLoc(f, f.startLoc)
      w.stats.flagsReturned[ord(f.team.other())] += 1
      discard w.beat(BeatFlagReturned, "flag_returned", ord(f.team), f.id)
    else:
      f.droppedRounds += 1

proc updateFlagBroadcastLocations*(w: World) =
  ## `GameWorld.updateFlagBroadcastLocations`, called BEFORE the round counter
  ## increments when `currentRound % 100 == 0` — which is true entering rounds
  ## 1, 101, 201, … The draw order is `allFlags` order and the candidate list
  ## is the engine's own scan order, so the RNG stream matches call for call.
  for f in w.allFlags:
    var count = 0
    for _ in w.locationsWithinRadiusSquared(f.loc, FlagBroadcastNoiseRadius):
      count += 1
    if count == 0: continue
    let pick = int(w.rand.nextInt(count))
    var i = 0
    for l in w.locationsWithinRadiusSquared(f.loc, FlagBroadcastNoiseRadius):
      if i == pick:
        f.broadcastLoc = l
        break
      i += 1

iterator broadcastFlagLocations*(w: World, r: Robot): Loc =
  ## `RobotControllerImpl.senseBroadcastFlagLocations`: every ENEMY flag that
  ## is neither carried nor currently visible, in `allFlags` order.
  for f in w.allFlags:
    if f.team == r.team: continue
    if f.carriedBy >= 0: continue
    if w.canSenseLocation(r, f.loc): continue
    yield f.broadcastLoc
