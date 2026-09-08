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
## **EVERY QUERY BELOW IS ROBOT-LOCAL, and that is the whole reason the Java
## twin can exist at all.** A sandboxed robot has a `RobotController`, not a
## `GameWorld`: it cannot ask for the team's building count, for the enemy's
## archon list, or for the anomaly cursor. So every scan goes through the
## `visible` iterator — which is `getAllLocationsWithinRadiusSquared`, i.e. the
## engine's own x-outer/y-inner walk over the `ceil(sqrt) + 1` box, clamped to
## the type's vision radius — and the anomaly lookahead goes through
## `nextScheduled`, which is `rc.getAnomalySchedule()` scanned for the first
## entry at or after the current round. Anything this file reads that a robot
## could not read is a defect, not a shortcut.
##
## Four variants, selected by `-d:` switches:
##
## * `-d:bc22Scenario` — the base script: builder, laboratory prototype and its
##   ten repairs, transmute at three loneliness values, watchtower and its
##   fifteen repairs, level-2 (lead) and level-3 (gold) mutations, an archon
##   transform out and back, a sage envisioning each of ABYSS/CHARGE/FURY, a
##   shared-array write from a robot with nothing nearby, one square mined to
##   zero and another to exactly 1, and one disintegration;
## * `-d:bc22ScenarioAnnihilate` — every soldier homes on the rotational mirror
##   of its own square until it can see an enemy archon, then kills it, so
##   `ANNIHILATION` fires and the 20 Au reclaim lands;
## * `-d:bc22ScenarioTie` — nobody ever attacks, so the ladder walks all the way
##   down past MORE_ARCHONS and MORE_GOLD_NET_WORTH;
## * `-d:bc22ScenarioFury` — no transform anywhere, so every building stands in
##   TURRET mode through every scheduled FURY.

import ../anomaly as simAnomaly
import ../world, ../economy, ../buildings

export world

const
  ScenarioDirs = MoveDirs
    ## `Direction.values()`'s first eight, in the enum's own order. The Java
    ## twin declares the same eight literals rather than calling
    ## `Direction.allDirections()`, so neither side depends on the other's
    ## iteration order by accident.

iterator visible(w: World, r: Robot, r2: int): Loc =
  ## `rc.getAllLocationsWithinRadiusSquared(rc.getLocation(), r2)`, INCLUDING
  ## its clamp to the type's vision radius.
  let clamped = min(r2, RobotSpecs[r.kind].visionRadiusSquared)
  for l in w.locationsWithinRadiusSquared(r.loc, clamped):
    yield l

proc nextScheduled(w: World, r: Robot):
    tuple[has: bool, round: int, kind: AnomalyKind] =
  ## `rc.getAnomalySchedule()` scanned for the first entry at or after this
  ## round. A robot cannot see `LiveMap.nextAnomalyIndex`, so the bot may not
  ## read `w.anomalyCursor`: it re-derives the head from the public schedule.
  for e in w.map.anomalies:
    if e.round >= w.currentRound:
      return (true, e.round, e.kind)
  (false, 0, anAbyss)

proc buildFirst(w: World, r: Robot, kind: RobotType): bool =
  for d in ScenarioDirs:
    if w.canBuildRobot(r, kind, d):
      w.doBuildRobot(r, kind, d)
      return true
  false

proc moveFirst(w: World, r: Robot): bool =
  for d in ScenarioDirs:
    if w.canMove(r, d):
      w.doMove(r, d)
      return true
  false

proc seesFriendly(w: World, r: Robot, kind: RobotType): bool =
  for l in w.visible(r, RobotSpecs[r.kind].actionRadiusSquared):
    let b = w.getRobot(l)
    if b != nil and b.team == r.team and b.kind == kind:
      return true
  false

proc attackFirst(w: World, r: Robot): bool =
  for l in w.visible(r, RobotSpecs[r.kind].actionRadiusSquared):
    if w.canAttack(r, l):
      w.doAttack(r, l)
      return true
  false

proc scenarioArchon(w: World, r: Robot) =
  let round = w.currentRound
  ## Rounds 1-3: one miner each way, so there is an economy at all.
  if round <= 3:
    discard w.buildFirst(r, rtMiner)
    return
  when defined(bc22ScenarioAnnihilate):
    ## Every soldier the lead allows, for the annihilation run.
    discard w.buildFirst(r, rtSoldier)
    return
  ## Rounds 4-12: THE BUILDER, which is what unlocks every building path —
  ## retried until one exists, not attempted once. Measured: on `maze`,
  ## `turtle` and `vortex` the archon's square carries enough rubble that its
  ## action cooldown lands on round 4, a single attempt missed, and those three
  ## maps then ran 2000 rounds with no builder, no laboratory, no watchtower,
  ## no gold and no sage — i.e. Tier A′ proving nothing on three of eight maps.
  if round <= 12:
    if not w.seesFriendly(r, rtBuilder):
      if w.buildFirst(r, rtBuilder): return
    discard w.buildFirst(r, rtSoldier)
    return
  ## Rounds 13-40: soldiers, so the board is not empty.
  if round <= 40:
    discard w.buildFirst(r, rtSoldier)
    return
  ## ONE PASS over the action radius, answering both questions this script
  ## asks of it: is there already a sage, and what is the first damaged
  ## friendly droid. Two scans of a radius-20 box cost the ARCHON 28-36 % of
  ## its 20 000 bytecodes on the Java side — measured — and the whole point of
  ## this bot is a 25 % ceiling.
  var sageSeen = false
  var damaged = loc(-1, -1)
  for l in w.visible(r, RobotSpecs[rtArchon].actionRadiusSquared):
    let b = w.getRobot(l)
    if b == nil or b.team != r.team: continue
    if b.kind == rtSage: sageSeen = true
    if damaged.x < 0 and not b.kind.isBuilding() and
       b.health < maxHealthOf(b.kind, b.level):
      damaged = l
  ## ONE sage, and only one — the only unit that can envision. The uncapped
  ## form was measured to spend every gold the laboratory ever made: 1 722
  ## sage-rounds on `chalice`, a team gold that never rose above 20 for long,
  ## and therefore NO level-3 (gold) mutation anywhere in 32 whole games. A
  ## sage costs 20 Au and a level-3 mutation costs gold too, and the scenario
  ## has to fund both.
  if not sageSeen and
     w.teamGold(r.team) >= RobotSpecs[rtSage].buildCostGold:
    if w.buildFirst(r, rtSage): return
  ## Round 300: transform out to PORTABLE; rounds 301-319 move; round 320
  ## onwards transform back — proving exactly ONE counter is charged each time.
  ## THE RETURN WINDOW IS OPEN-ENDED ON PURPOSE. A three-round window (300 out,
  ## 301-302 move, 303 back) was measured to leave the archon PORTABLE FOR EVER
  ## on all eight maps: the transform cooldown is the type's movement cooldown
  ## scaled by rubble, so `canTransform` was still false on round 303, the
  ## archon never came back, never built again, and no sage — and therefore no
  ## envision — existed in the whole run.
  when not defined(bc22ScenarioFury):
    if round == 300 and r.mode == rmTurret and w.canTransform(r):
      w.doTransform(r)
      return
    if round in 301 .. 319 and r.mode == rmPortable:
      discard w.moveFirst(r)
      return
    if round >= 320 and r.mode == rmPortable:
      if w.canTransform(r):
        w.doTransform(r)
      return
  ## Otherwise: write the round number to the shared array (free in this year,
  ## and legal with nothing nearby — which is illegal in 2023), then repair the
  ## first damaged friendly droid in range.
  discard w.writeSharedArray(r, 0, round mod (MaxSharedArrayValue + 1))
  if damaged.x >= 0 and w.canRepair(r, damaged):
    w.doRepair(r, damaged)
    return
  discard w.buildFirst(r, rtSoldier)

proc scenarioBuilder(w: World, r: Robot) =
  ## ONE PASS over the action radius, collecting the first square of each
  ## category and the building census at the same time. The three-scan form
  ## this replaces peaked at 58 % of the BUILDER's 7 500 bytecodes on the Java
  ## side — measured — and the whole point of this bot is that it can never be
  ## cut off mid-turn.
  var proto = loc(-1, -1)
  var mutable = loc(-1, -1)
  var damaged = loc(-1, -1)
  var labs = 0
  var towers = 0
  for l in w.visible(r, RobotSpecs[rtBuilder].actionRadiusSquared):
    let b = w.getRobot(l)
    if b == nil or b.team != r.team: continue
    if b.kind == rtLaboratory: labs += 1
    elif b.kind == rtWatchtower: towers += 1
    if proto.x < 0 and b.mode == rmPrototype: proto = l
    if not b.kind.isBuilding(): continue
    if mutable.x < 0 and w.canMutate(r, l): mutable = l
    if damaged.x < 0 and b.health < maxHealthOf(b.kind, b.level): damaged = l
  ## Finish anything unfinished FIRST — ten repairs for a laboratory, fifteen
  ## for a watchtower — then mutate, then place the next one, then top up a
  ## finished building.
  if proto.x >= 0 and w.canRepair(r, proto):
    w.doRepair(r, proto)
    return
  if mutable.x >= 0:
    w.doMutate(r, mutable)
    return
  if labs == 0:
    if w.buildFirst(r, rtLaboratory): return
  elif towers < 2:
    if w.buildFirst(r, rtWatchtower): return
  if damaged.x >= 0 and w.canRepair(r, damaged):
    w.doRepair(r, damaged)

proc scenarioMiner(w: World, r: Robot) =
  ## One square is mined to ZERO and another to EXACTLY ONE, so the next
  ## multiple of twenty proves that only the second regenerates.
  var first = true
  for l in w.visible(r, RobotSpecs[rtMiner].actionRadiusSquared):
    while w.canMineGold(r, l):
      w.doMineGold(r, l)
    let floorAt = if first: 0 else: 1
    first = false
    while w.getLead(l) > floorAt and w.canMineLead(r, l):
      w.doMineLead(r, l)
  if r.canMoveCooldown():
    discard w.moveFirst(r)

proc scenarioSoldier(w: World, r: Robot) =
  when defined(bc22ScenarioTie):
    ## The tie run never attacks: the ladder has to walk all the way down.
    if r.canMoveCooldown():
      discard w.moveFirst(r)
    return
  if w.attackFirst(r): return
  when defined(bc22ScenarioAnnihilate):
    ## Home on the ROTATIONAL MIRROR of this square. A robot does not know the
    ## map's symmetry or its own spawn, but it does know `getMapWidth()` and
    ## `getMapHeight()`, and `(W-1-x, H-1-y)` is always in the other half — so
    ## soldiers cross the board, meet the enemy archon and kill it.
    if r.canMoveCooldown():
      let mirror = loc(w.width - 1 - r.loc.x, w.height - 1 - r.loc.y)
      let d = r.loc.directionTo(mirror)
      if w.canMove(r, d):
        w.doMove(r, d)
        return
  if r.canMoveCooldown():
    discard w.moveFirst(r)

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
  when not defined(bc22ScenarioTie):
    if w.attackFirst(r): return
  if r.canMoveCooldown():
    discard w.moveFirst(r)

proc scenarioTurret(w: World, r: Robot) =
  ## A watchtower: one stands in TURRET mode through a scheduled FURY and one
  ## stands up to PORTABLE before it, so the pair proves 7 and 0.
  if r.mode == rmPrototype: return
  when not defined(bc22ScenarioFury):
    let nxt = w.nextScheduled(r)
    ## A FURY WITHIN ELEVEN ROUNDS, not exactly eleven rounds away. The exact
    ## form was measured never to fire: a watchtower has to be alive, finished,
    ## even-id and off cooldown on one specific round, and over 32 whole games
    ## that never once coincided.
    let furySoon = nxt.has and nxt.kind == anFury and
                   nxt.round - w.currentRound <= 11
    if furySoon and r.id mod 2 == 0 and r.mode == rmTurret and
       w.canTransform(r):
      w.doTransform(r)
      return
    if r.mode == rmPortable and not furySoon:
      if w.canTransform(r):
        w.doTransform(r)
      return
  if r.mode != rmTurret: return
  when not defined(bc22ScenarioTie):
    discard w.attackFirst(r)

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
