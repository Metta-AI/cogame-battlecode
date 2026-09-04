## bc24 traps: building one, the trigger index, the enter/interact split, the
## water trap's flood set, and de-registration.
##
## Ported from `RobotControllerImpl.assertCanBuild` / `build` and
## `GameWorld.placeTrap` / `triggerTrap` at the pinned commit.
##
## THE THREE THINGS THAT MAKE TRAPS A RULE RATHER THAN A DETAIL:
##
## * A build onto a tile that already holds an ENEMY EXPLOSIVE spends the
##   crumbs and the cooldown, queues that trap as an *interact* trigger, and
##   PLACES NOTHING — and earns no build XP.
## * A trigger fires at the END OF THE TRIGGERING DUCK'S TURN, in queue order,
##   not at the moment it is queued.
## * De-registration sweeps `r^2 <= 2` around the trap regardless of the
##   trap's own `triggerRadius`, which is exactly what the engine does.

import world

export world

proc canBuildTrap*(w: World, r: Robot, kind: TrapKind, l: Loc): bool =
  ## `assertCanBuild`, in the engine's own order.
  if not r.spawned: return false
  if r.loc.distanceSquaredTo(l) > InteractRadiusSquared: return false
  if not w.onTheMap(l): return false
  if not r.canActCooldown(): return false
  if w.getCrumbs(r.team) < trapCostFor(kind, r.levelOf(skBuild)): return false
  for adj in w.locationsWithinRadiusSquared(l, 2):
    let bot = w.getRobot(adj)
    if bot != nil and bot.team != r.team: return false
  if kind == tkExplosive:
    if not w.isPassable(l) and not w.getWater(l): return false
  else:
    if not w.isPassable(l): return false
  if w.hasTrap(l) and w.getTrap(l).team == r.team: return false
  not r.hasFlag()

proc buildTrap*(w: World, r: Robot, kind: TrapKind, l: Loc) =
  ## `RobotControllerImpl.build`: charge, deduct, THEN decide whether anything
  ## is placed.
  if not w.canBuildTrap(r, kind, l):
    w.refusedActions += 1
    return
  let level = r.levelOf(skBuild)
  let cost = trapCostFor(kind, level)
  r.actionCooldown += trapCooldownFor(kind, level)
  w.addCrumbs(r.team, -cost)
  w.stats.crumbsSpentTraps[ord(r.team)] += cost

  if w.hasTrap(l) and w.getTrap(l).team != r.team and
      w.getTrap(l).kind == tkExplosive:
    r.addTrapTrigger(w.getTrap(l), false)
    return

  w.placeTrapAt(l, kind, r.team)
  w.stats.trapsBuilt[ord(r.team)] += 1
  w.stats.trapsBuiltByKind[ord(r.team)][kind] += 1
  ## Telemetry for the knob-teeth gate: whether this trap landed inside the
  ## ring the `flag_ring` placement aims at. Never read by a rule.
  for f in w.allFlags:
    if f.team == r.team and f.loc.distanceSquaredTo(l) <= 8:
      w.stats.trapsNearOwnFlag[ord(r.team)] += 1
      break
  w.incrementSkill(r, skBuild)
  w.noteFirstAction(r, Bc24ActionBuild)

proc triggerTrap*(w: World, trap: Trap, r: Robot, entered: bool) =
  ## `GameWorld.triggerTrap`.
  let l = trap.loc
  let spec = TrapSpecs[trap.kind]
  let victimTeam = trap.team.other()
  case trap.kind
  of tkStun:
    for adj in w.locationsWithinRadiusSquared(l, spec.enterRadius):
      let bot = w.getRobot(adj)
      if bot == nil or bot.team != victimTeam: continue
      ## SET, not added.
      bot.movementCooldown = spec.opponentCooldown
      bot.actionCooldown = spec.opponentCooldown
  of tkExplosive:
    var rad = spec.interactRadius
    var dmg = spec.interactDamage
    if entered:
      rad = spec.enterRadius
      dmg = spec.enterDamage
    ## The victim list is taken BEFORE any damage lands, exactly as
    ## `getAllRobotsWithinRadiusSquared` collects it into an array first.
    var victims: seq[Robot]
    for adj in w.locationsWithinRadiusSquared(l, rad):
      let bot = w.getRobot(adj)
      if bot != nil and bot.team == victimTeam:
        victims.add(bot)
    for bot in victims:
      if not bot.spawned: continue
      w.stats.trapDamage[ord(trap.team)] += min(dmg, bot.health)
      w.addHealth(bot, -dmg)
  of tkWater:
    for adj in w.locationsWithinRadiusSquared(l, spec.enterRadius):
      if w.getRobot(adj) != nil: continue
      if not w.isPassable(adj): continue
      if w.getSpawnZone(adj) != 0: continue
      if w.getTrap(adj) != nil: continue
      w.setWater(adj)
  of tkNone:
    discard

  for adj in w.locationsWithinRadiusSquared(l, 2):
    let i = w.idx(adj)
    for k in 0 ..< w.trapTriggers[i].len:
      if w.trapTriggers[i][k] == trap:
        w.trapTriggers[i].delete(k)
        break
  w.trapLocations[w.idx(l)] = nil
  w.stats.trapsTriggered[ord(trap.team)] += 1

  ## `trap_wave` — one bounded beat each time a clan's triggered-trap count
  ## crosses a multiple of ten.
  let t = ord(trap.team)
  let step = w.stats.trapsTriggered[t] div 10
  if step > w.trapWaveStep[t]:
    w.trapWaveStep[t] = step
    discard w.beat(BeatTrapWave, "trap_wave", t, w.stats.trapsTriggered[t],
      w.stats.trapDamage[t])

proc processTriggerQueue*(w: World, r: Robot) =
  ## `InternalRobot.processEndOfTurn`'s first half: every queued trap fires
  ## now, IN QUEUE ORDER, and the queue is emptied afterwards.
  for i in 0 ..< r.trapsToTrigger.len:
    w.triggerTrap(r.trapsToTrigger[i], r, r.enteredTraps[i])
  r.trapsToTrigger.setLen(0)
  r.enteredTraps.setLen(0)
