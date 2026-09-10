## `saber` — the strong bc19 chassis and the champions' chassis.
##
## A behaviour port of `m-schier/battlecode-2019-wololo` at commit
## `ebdd27959a83e00c4ec67c74253d2db8095e3ba6` (GPL-3.0), parameterised by all
## eleven doctrine knobs. The correspondence, file by file, is in `NOTICE`.
##
## **THE NAME IS `saber`, NOT `wololo`, DELIBERATELY.** `scWololo` / `blWololo`
## are bc22's strong chassis (`sim_types.nim`), and a duplicate enum string
## would compile and then seat the wrong bot.
##
## This file is the turn dispatcher and the round-level bookkeeping; every
## decision it makes lives in one of the other twelve chassis modules.

import ../constants, ../units, ../world, ../knobs
import ../actions
import kit, econ, castle, pilgrim, military, micro, comms, lattice,
  infiltrate, church, trade

export kit

proc beginRound*(w: World, s: Side) =
  ## The chassis's round-level bookkeeping, run before any of the side's
  ## robots act so every robot this round reads the SAME census and the same
  ## depot roster.
  refreshCensus(w, s)
  buildLatticeSlots(w, s)
  abortIfLost(w, s)
  if launch(w, s, w.round):
    ## Commit the infiltration: the pilgrim furthest from home takes the job
    ## and the two nearest military units escort it.
    var best: Robot = nil
    var bestD = -1
    for r in w.robots:
      if r.team != s.team or r.unit != ukPilgrim: continue
      let home = s.nearestStructure(r.x, r.y)
      let d = (if home.x >= 0: distSq(r.x, r.y, home.x, home.y) else: 0)
      if d > bestD:
        bestD = d
        best = r
    if not best.isNil:
      best.role = RolePilgrimInfiltrator
      best.task = TaskMine
      best.taskX = -1
      best.taskY = -1
      var escorts = 0
      for r in w.robots:
        if escorts >= 2: break
        if r.team != s.team: continue
        if r.unit notin {ukCrusader, ukProphet, ukPreacher}: continue
        r.role = RoleMilitaryEscort
        inc escorts
    else:
      s.infiltrateLaunched = false

proc runMilitary(w: World, s: Side, r: Robot): Action =
  result = newAction()
  result.castleTalk = castleTalkFor(w, s, r)
  let radio = radioFor(w, s, r)
  result.signal = radio.value
  result.signalRadius = radio.radius

  ## 1. Shoot if there is anything worth shooting. The PREACHER's blast score
  ##    refuses any shot whose own-side kills exceed its enemy kills, at
  ##    every `preacher_share`.
  let shot = chooseAttack(w, s, r)
  if shot.ok:
    result.hasAction = true
    result.kind = akAttack
    result.dx = shot.dx
    result.dy = shot.dy
    return

  ## 2. Dodge a square that is about to kill us.
  let dodge = chooseDodge(w, s, r)
  if dodge.ok:
    result.hasAction = true
    result.kind = akMove
    result.dx = dodge.dx
    result.dy = dodge.dy
    return

  ## 3. Walk at the state machine's target. A PROPHET that is already inside
  ##    its own r2 16 blind zone backs OFF rather than closing, because it
  ##    cannot shoot what it is standing next to.
  let target = militaryTarget(w, s, r)
  if target.x < 0: return
  var tx = target.x
  var ty = target.y
  if prophetBlindTo(r, tx, ty):
    let home = s.nearestStructure(r.x, r.y)
    if home.x >= 0:
      tx = home.x
      ty = home.y
  if r.x == tx and r.y == ty: return
  ## **A MILITARY UNIT DOES NOT WALK ON THE ORDER'S LAST FUEL.** The only
  ## passive income in the game is 25 fuel a round and a PREACHER's move
  ## costs 3 per r2, so a wandering army starves the mining line that funds
  ## it. Movement is therefore gated on the fuel reserve — EXCEPT when the
  ## unit is answering an enemy inside `defend_radius` of one of our
  ## structures, which is what `defend_radius` is for.
  let defending = nearStructure(s, tx, ty) or nearStructure(s, r.x, r.y)
  if not defending and
      w.fuel[ord(s.team)] - s.fuelGate() < 3 * speedOf(r.unit):
    return
  let mode = (if r.unit == ukCrusader: navFastest else: navEconomic)
  let step = stepToward(w, r, tx, ty, mode)
  if step.ok:
    let home = s.nearestStructure(r.x, r.y)
    if home.x >= 0:
      w.stats.militaryDistance[ord(s.team)] += distSq(r.x, r.y, home.x, home.y)
      w.stats.militaryDistanceSamples[ord(s.team)] += 1
    if r.latticeSlot >= 0 and r.latticeSlot < s.latticeSlots.len and
        r.x + step.dx == s.latticeSlots[r.latticeSlot].x and
        r.y + step.dy == s.latticeSlots[r.latticeSlot].y:
      w.stats.latticeUnitsPlaced[ord(s.team)] += 1
    result.hasAction = true
    result.kind = akMove
    result.dx = step.dx
    result.dy = step.dy

proc runSaber*(w: World, s: Side, r: Robot): Action =
  case r.unit
  of ukCastle: runCastle(w, s, r)
  of ukChurch: runChurch(w, s, r)
  of ukPilgrim: runPilgrim(w, s, r)
  of ukCrusader, ukProphet, ukPreacher: runMilitary(w, s, r)
