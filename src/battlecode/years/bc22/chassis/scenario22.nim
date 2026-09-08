## `scenario22.nim` — the Nim twin of `tools/oracle/bc22/bc22scenario/
## RobotPlayer.java`, written LINE FOR LINE against it.
##
## WHY IT EXISTS. Tier A's own measurement showed exactly what it cannot cover:
## over eight full 2000-round games the 2022 example bot **never built a
## builder, a sage, a laboratory or a watchtower, never mutated, never
## transformed, never transmuted, never envisioned, never wrote the shared
## array, never made a single gold, and ended EVERY game at round 2000 on
## `MORE_LEAD_NET_WORTH` with gold 0-0**. So the whole building, mutation, gold,
## sage and anomaly-response half of the rule set, and both of the ladder's
## upper rungs, and `ANNIHILATION` itself, are untested by it — precisely the
## "rare code paths that fire mid-game" the Fleet-card postmortem warns about,
## except that here they are most of the game.
##
## This bot is therefore (a) DETERMINISTIC WITH NO RNG AT ALL, (b) cheap — the
## parity job asserts it never exceeds 25 % of its bytecode limit, so it can
## never be cut off mid-turn — and (c) SCRIPTED BY ROUND NUMBER to force every
## rare path early. The Java side and this side must agree BIT FOR BIT for the
## whole game, and the job then asserts OFF THE JAVA TRACE that the paths really
## fired: a scenario bot that agrees bit for bit while doing nothing proves
## nothing.
##
## Four variants, selected by `-d:` switches:
##
## * `-d:bc22Scenario` — the base script: builder, laboratory prototype and its
##   ten repairs, transmute at three loneliness values, watchtower and its
##   fifteen repairs, level-2 (lead) and level-3 (gold) mutations, an archon
##   transform out and back, a sage envisioning each of ABYSS/CHARGE/FURY, a
##   shared-array write from a robot with nothing nearby, one square mined to
##   zero and another to exactly 1, and one disintegration;
## * `-d:bc22ScenarioAnnihilate` — walk soldiers onto the enemy's single archon
##   until `ANNIHILATION` fires;
## * `-d:bc22ScenarioTie` — mirror both sides so the ladder walks down to
##   `MORE_LEAD_NET_WORTH` and, on one seed, to `WON_BY_DUBIOUS_REASONS`;
## * `-d:bc22ScenarioFury` — stand every building up in TURRET mode through a
##   scheduled FURY so divergence 7's early gold/lead ladder can fire.

import ../anomaly as simAnomaly
import ../world, ../economy, ../buildings

export world

proc scenarioArchon(w: World, r: Robot) =
  let round = w.currentRound
  ## Rounds 1-3: one miner each way, so there is an economy at all.
  if round <= 3:
    for d in MoveDirs:
      if w.canBuildRobot(r, rtMiner, d):
        w.doBuildRobot(r, rtMiner, d)
        return
    return
  ## Round 4: the builder, which is what unlocks every building path.
  if round == 4:
    for d in MoveDirs:
      if w.canBuildRobot(r, rtBuilder, d):
        w.doBuildRobot(r, rtBuilder, d)
        return
    return
  when defined(bc22ScenarioAnnihilate):
    ## Every soldier the lead allows, for the annihilation run.
    for d in MoveDirs:
      if w.canBuildRobot(r, rtSoldier, d):
        w.doBuildRobot(r, rtSoldier, d)
        return
    return
  ## Rounds 5-40: soldiers, so the board is not empty.
  if round <= 40:
    for d in MoveDirs:
      if w.canBuildRobot(r, rtSoldier, d):
        w.doBuildRobot(r, rtSoldier, d)
        return
    return
  ## A sage the moment 20 gold exists — the only unit that can envision.
  if w.teamGold(r.team) >= RobotSpecs[rtSage].buildCostGold:
    for d in MoveDirs:
      if w.canBuildRobot(r, rtSage, d):
        w.doBuildRobot(r, rtSage, d)
        return
  ## Rounds 300-303: transform out to PORTABLE, move two squares, transform
  ## back — proving exactly ONE counter is charged each time.
  when not defined(bc22ScenarioFury):
    if round == 300 and r.mode == rmTurret and w.canTransform(r):
      w.doTransform(r)
      return
    if round in 301 .. 302 and r.mode == rmPortable:
      for d in MoveDirs:
        if w.canMove(r, d):
          w.doMove(r, d)
          return
      return
    if round == 303 and r.mode == rmPortable and w.canTransform(r):
      w.doTransform(r)
      return
  ## Otherwise: repair the weakest friendly droid in range, and write the round
  ## number to the shared array (free in this year, and legal with nothing
  ## nearby — which is illegal in 2023).
  discard w.writeSharedArray(r, 0, round mod (MaxSharedArrayValue + 1))
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtArchon].actionRadiusSquared):
    let b = w.getRobot(l)
    if b != nil and b.team == r.team and not b.kind.isBuilding() and
       b.health < b.maxHealth() and w.canRepair(r, l):
      w.doRepair(r, l)
      return
  for d in MoveDirs:
    if w.canBuildRobot(r, rtSoldier, d):
      w.doBuildRobot(r, rtSoldier, d)
      return

proc scenarioBuilder(w: World, r: Robot) =
  ## Finish anything unfinished FIRST — ten repairs for a laboratory, fifteen
  ## for a watchtower — then mutate, then place the next building.
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtBuilder].actionRadiusSquared):
    let b = w.getRobot(l)
    if b != nil and b.team == r.team and b.mode == rmPrototype and
       w.canRepair(r, l):
      w.doRepair(r, l)
      return
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtBuilder].actionRadiusSquared):
    let b = w.getRobot(l)
    if b != nil and b.team == r.team and b.kind.isBuilding() and
       w.canMutate(r, l):
      w.doMutate(r, l)
      return
  var labs = 0
  var towers = 0
  for _, b in w.robotsById:
    if b.team != r.team: continue
    if b.kind == rtLaboratory: labs += 1
    elif b.kind == rtWatchtower: towers += 1
  if labs == 0:
    for d in MoveDirs:
      if w.canBuildRobot(r, rtLaboratory, d):
        w.doBuildRobot(r, rtLaboratory, d)
        return
  elif towers < 2:
    for d in MoveDirs:
      if w.canBuildRobot(r, rtWatchtower, d):
        w.doBuildRobot(r, rtWatchtower, d)
        return
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtBuilder].actionRadiusSquared):
    let b = w.getRobot(l)
    if b != nil and b.team == r.team and b.kind.isBuilding() and
       b.health < b.maxHealth() and w.canRepair(r, l):
      w.doRepair(r, l)
      return

proc scenarioMiner(w: World, r: Robot) =
  ## One square is mined to ZERO and another to EXACTLY ONE, so the next
  ## multiple of twenty proves that only the second regenerates.
  var first = true
  for l in w.locationsWithinRadiusSquared(r.loc, 2):
    while w.canMineGold(r, l):
      w.doMineGold(r, l)
    let floorAt = if first: 0 else: 1
    first = false
    while w.getLead(l) > floorAt and w.canMineLead(r, l):
      w.doMineLead(r, l)
  if r.canMoveCooldown():
    for d in MoveDirs:
      if w.canMove(r, d):
        w.doMove(r, d)
        return

proc scenarioSoldier(w: World, r: Robot) =
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtSoldier].actionRadiusSquared):
    if w.canAttack(r, l):
      w.doAttack(r, l)
      return
  when defined(bc22ScenarioAnnihilate):
    ## Walk at the enemy's archon and keep hitting it.
    var target = loc(-1, -1)
    for _, b in w.robotsById:
      if b.team != r.team and b.kind == rtArchon:
        target = b.loc
        break
    if target.x >= 0 and r.canMoveCooldown():
      let d = r.loc.directionTo(target)
      if w.canMove(r, d):
        w.doMove(r, d)
        return
  if r.canMoveCooldown():
    for d in MoveDirs:
      if w.canMove(r, d):
        w.doMove(r, d)
        return

proc scenarioSage(w: World, r: Robot) =
  ## Envision each of ABYSS, CHARGE and FURY in turn, proving the three radii
  ## and the three truncations. `VORTEX.isSageAnomaly == false`, so a sage
  ## cannot envision one and the port refuses it.
  let choice = case (r.id mod 3)
    of 0: anAbyss
    of 1: anCharge
    else: anFury
  if w.canEnvision(r, choice):
    w.doEnvision(r, choice)
    return
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtSage].actionRadiusSquared):
    if w.canAttack(r, l):
      w.doAttack(r, l)
      return
  if r.canMoveCooldown():
    for d in MoveDirs:
      if w.canMove(r, d):
        w.doMove(r, d)
        return

proc scenarioTurret(w: World, r: Robot) =
  ## A watchtower: one stands in TURRET mode through a scheduled FURY and one
  ## stands up to PORTABLE before it, so the pair proves 7 and 0.
  if r.mode == rmPrototype: return
  when not defined(bc22ScenarioFury):
    let nxt = w.nextAnomaly()
    if nxt.has and nxt.kind == anFury and nxt.round - w.currentRound == 11 and
       r.id mod 2 == 0 and r.mode == rmTurret and w.canTransform(r):
      w.doTransform(r)
      return
    if r.mode == rmPortable and (not nxt.has or nxt.kind != anFury):
      if w.canTransform(r):
        w.doTransform(r)
      return
  if r.mode != rmTurret: return
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtWatchtower].actionRadiusSquared):
    if w.canAttack(r, l):
      w.doAttack(r, l)
      return

proc scenarioLab(w: World, r: Robot) =
  if r.mode != rmTurret: return
  if w.canTransmute(r):
    w.doTransmute(r)

proc runScenario22*(w: World, r: Robot) =
  case r.kind
  of rtArchon: scenarioArchon(w, r)
  of rtBuilder: scenarioBuilder(w, r)
  of rtMiner:
    ## Exactly one miner disintegrates, at round 500, so the death path and its
    ## reclaim drop are exercised without an attack.
    if w.currentRound == 500 and r.id mod 7 == 0:
      w.doDisintegrate(r)
      return
    scenarioMiner(w, r)
  of rtSoldier: scenarioSoldier(w, r)
  of rtSage: scenarioSage(w, r)
  of rtWatchtower: scenarioTurret(w, r)
  of rtLaboratory: scenarioLab(w, r)
