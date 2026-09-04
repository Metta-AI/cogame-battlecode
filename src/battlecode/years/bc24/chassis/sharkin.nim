## `gone-sharkin` — the strong published baseline and the champion chassis.
##
## Behaviour ported from `chenyx512/battlecode24` `src/bot1/` (AGPL-3.0,
## commit `bf245ef`; the 1st-place bot, whose README names `bot1` as the main
## bot), with the navigator and shared-array discipline from
## `jmerle/battlecode-2024` `src/camel_case_v21_final/` (AGPL-3.0, `d10ddcc`),
## the BFS and comms layout from `andli28/bc2024` `src/mainbot/` (AGPL-3.0,
## `4040df7`) and the carrier-return micro from `davidteather/battlecode_24`
## `src/submit6/` (AGPL-3.0, `d129abf`). BEHAVIOUR, not code, rewritten in Nim
## and parameterised by the ten doctrine knobs. NOTHING is vendored, and the
## unlicensed XSquare / IvanGeffner repositories are not read at all.
##
## THIS FILE IS THE ONE CHASSIS. Every knob setting drives it; no knob selects
## a different, weaker bot. Independently of the sheet it always spawns every
## duck it can, always walks crumbs off the floor, always defends a flag it
## senses under threat, always answers a sensed enemy, and always commits to an
## enemy flag by `flag_rush_round`.
##
## `-d:bc24BrokenChassis` compiles the NEGATIVE CONTROL the competence gate
## arms itself with: a chassis that stops spawning after round 50.
## `tests/test_bc24_survival.nim` asserts that the gate goes RED under it. A
## gate that cannot fail is not a gate.

import kit, micro, comms, builder, attack, defend, setup, upgrades

export kit, micro, comms, builder, attack, defend, setup, upgrades

proc trySpawn(w: World, side: Side, r: Robot): bool {.discardable.} =
  ## The own spawn tile nearest this duck's post that is free and passable.
  ## A duck that can spawn ALWAYS spawns: an unspawned roster is the inert
  ## flock the LEARNINGS pin forbids.
  when defined(bc24BrokenChassis):
    ## NEGATIVE CONTROL (compile-time only): stop reinforcing after round 50.
    if w.currentRound > 50: return false
  if not r.canSpawnCooldown(): return false
  let brain = side.brainFor(r)
  let index = min(if brain.hasRole: brain.role mod 3 else: seqIdOf(r) mod 3, 2)
  let post = side.ownCentres[index]
  var best = loc(-1, -1)
  var bestD = high(int)
  for l in w.spawnLocs[ord(side.team)]:
    if not spend(r, 1): break
    if not w.canSpawn(r, l): continue
    let d = l.distanceSquaredTo(post)
    if d < bestD:
      bestD = d
      best = l
  if best.x < 0: return false
  w.doSpawn(r, best)
  true

proc publishRound(w: World, side: Side, r: Robot) =
  ## The first duck of the team to act each round refreshes the shared
  ## picture the rest of the flock plans against, and spends any global
  ## upgrade point the team is holding.
  if side.firstActionDone: return
  side.firstActionDone = true
  w.publishOwnFlags(side, r)
  w.publishEnemyFlags(side, r)
  w.publishDistress(side, r)
  w.publishUpgrades(side, r)
  w.publishRoles(side, r)
  w.spendUpgradePoint(side, r)

proc runBuilder*(w: World, side: Side, r: Robot) =
  ## Post-setup builders: defend first, then the spend plan.
  if r.hasFlag():
    if w.canDropFlag(r, r.loc):
      w.dropFlag(r, r.loc)
    return
  if w.fightOrRetreat(side, r): return

  let threat = w.threatenedFlag(side, r)
  if threat.ok:
    let cost = trapCostFor(tkStun, r.levelOf(skBuild))
    if w.getCrumbs(side.team) >= cost and not w.trapNearFlag(side, threat.at):
      for l in w.locationsWithinRadiusSquared(r.loc, InteractRadiusSquared):
        if not spend(r, 1): break
        if l.distanceSquaredTo(threat.at) > 8: continue
        if w.canBuildTrap(r, tkStun, l):
          w.buildTrap(r, tkStun, l)
          return

  ## THE FLOOR NO KNOB CAN LOWER, second clause: open the crossing. On a
  ## water-locked map this is the only thing standing between the two flocks,
  ## and it happens whatever `water_dig_policy` says.
  let bridge = w.bridgeTargetNear(side, r)
  if bridge.ok and w.getCrumbs(side.team) >= fillCostFor(r.levelOf(skBuild)):
    w.doFill(r, bridge.at)
    return

  let kind = side.plannedTrapKind()
  if w.mayBuildPlannedTrap(side, r, kind):
    let target = w.trapTargetNear(side, r, kind)
    if target.ok:
      w.buildTrap(r, kind, target.at)
      side.trapSlot += 1
      ## Telemetry for the knob-teeth gate: a trap that landed ON or BESIDE a
      ## measured choke tile -- the choke is a cut, not a single square, and a
      ## trap one tile off it closes the same corridor. Never read by a rule.
      for t in side.chokeTiles:
        if t.distanceSquaredTo(target.at) <= 2:
          w.stats.trapsOnChoke[ord(side.team)] += 1
          break
      return

  let terra = w.terraformTarget(side, r)
  if terra.kind == 1 and w.mayTerraform(side, r, digCostFor(r.levelOf(skBuild))):
    w.doDig(r, terra.at)
    return
  if terra.kind == 2 and w.mayTerraform(side, r, fillCostFor(r.levelOf(skBuild))):
    w.doFill(r, terra.at)
    return

  let span = w.bridgeStation(side, r)
  if span.ok:
    if side.bridgeSlot >= 0:
      discard w.travelTo(side, r, side.bridgeSlot, span.at)
    else:
      discard w.greedyStep(side, r, span.at)
    return
  let pile = w.nearestCrumbPile(r)
  if pile.ok:
    discard w.greedyStep(side, r, pile.at)
    return
  let station = w.builderStation(side, r)
  ## CHEBYSHEV 1, NOT 2. A builder standing at Chebyshev 2 of its station is
  ## `r^2 = 8` away from it, and `INTERACT_RADIUS_SQUARED` is 2 -- so it
  ## cannot build there, and `trap_placement: choke` would quietly place
  ## nothing at all.
  if chebyshev(r.loc, station) > 1:
    discard w.greedyStep(side, r, station)

proc runGoneSharkin*(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)

  if not r.spawned:
    ## A jailed duck still takes a turn, and the shared array is legal for it.
    side.releaseRole(r)
    w.publishRound(side, r)
    w.trySpawn(side, r)
    if r.spawned:
      side.claimRole(r, defensive = not side.isAttacker(r))
    return

  side.claimRole(r, defensive = not side.isAttacker(r))
  w.publishRound(side, r)
  w.observe(side, r)
  let enemy = w.nearestEnemy(r, VisionRadiusSquared)
  if enemy != nil: w.noteSighting(side, r, enemy.loc)

  if w.isSetupPhase():
    if w.runSetupCarrier(side, r): return
    if side.isBuilder(r):
      w.runSetupBuilder(side, r)
      return
    ## Everyone else farms crumbs and takes station on its own half.
    let patient = w.healTarget(side, r)
    if patient != nil and w.canHeal(r, patient.loc):
      w.doHeal(r, patient.loc)
    let pile = w.nearestCrumbPile(r)
    if pile.ok:
      discard w.greedyStep(side, r, pile.at)
      return
    let index = min(if brain.hasRole: brain.role mod 3 else: 0, 2)
    let post = side.ownCentres[index]
    if chebyshev(r.loc, post) > 5:
      discard w.travelTo(side, r, side.ownFieldIndex(index), post)
    else:
      discard w.greedyStep(side, r, side.enemyCentres[index])
    return

  ## Post-setup. A crumb pile under a duck's nose is always worth the step,
  ## but combat and flags come first.
  if side.isBuilder(r):
    w.runBuilder(side, r)
  elif side.isHealer(r):
    w.runHealer(side, r)
  else:
    w.runRaider(side, r)

