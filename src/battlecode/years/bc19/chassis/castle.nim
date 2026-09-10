## A CASTLE's turn, in the engine's own action order.
##
## Behaviour source: `m-schier/battlecode-2019-wololo@ebdd279`,
## `robot.js:53-58` (`CASTLE_STATE`), GPL-3.0.
##
## Castle talk first — it is FREE and it accompanies any action — then a
## build into the free adjacent square nearest the frontier, NEVER BOXING
## ITSELF IN, then, if there is nothing to build and an enemy is inside
## r2 64, an attack for 10 damage and 10 fuel.
##
## **LOSE YOUR LAST CASTLE AND YOU LOSE ON THE SPOT**, so a castle's
## priorities are not a matter of taste: the build queue is what replaces the
## units that die and the attack is free damage a structure can put out
## without moving.

import ../constants, ../units, ../world, ../knobs
import ../actions
import kit, econ, micro, military, trade, comms

export kit

proc economyFloorUnmet*(w: World, s: Side): bool =
  ## THE UNCONDITIONAL ECONOMY FLOOR: at least one PILGRIM on a karbonite
  ## depot and at least one on a fuel depot, from the first affordable
  ## build, at every knob setting. A fuel pilgrim returns +10 fuel a turn for
  ## 1 fuel, so it is the single most net-positive thing an order can buy —
  ## and an order without one starves with a full karbonite bank.
  if w.brokenChassis: return s.pilgrims < 1
  s.pilgrims < 2 or karboniteWorkers(w, s) == 0 or fuelWorkers(w, s) == 0

proc wantsPilgrim*(w: World, s: Side, round: int): bool =
  if w.brokenChassis: return s.pilgrims < 1
  if economyFloorUnmet(w, s): return true
  s.pilgrims < s.pilgrimsWanted(round)

proc runCastle*(w: World, s: Side, r: Robot): Action =
  result = newAction()
  result.castleTalk = castleTalkFor(w, s, r)

  ## 1. The barter. A castle is the only unit that can trade, and an
  ##    unpayable match clears both offers and throws — so `trade.nim` only
  ##    ever returns an offer we can pay.
  let deal = tradePlan(w, s, r)
  if deal.ok:
    result.hasAction = true
    result.kind = akTrade
    result.tradeK = deal.k
    result.tradeF = deal.f
    return

  ## 2. The build queue. Pilgrims first while the economy floor is unmet,
  ##    then military up to the census target.
  let towards =
    block:
      let e = s.nearestEnemyStructure(r.x, r.y)
      if e.x >= 0: e else: mirrorTarget(w, r.x, r.y)
  let square = freeBuildSquare(w, s, r, towards)
  if square.ok and not s.buildQueuedThisRound.hasKey(r.id):
    ## THE BUILD PRIORITY, and every rung of it is one of the anti-inert
    ## floors: the two-military-per-structure floor first (an order with no
    ## army is farmed for reclaim), then the economy floor (an order with no
    ## fuel pilgrim starves with a full karbonite bank), then the pilgrim
    ## ramp up to HALF the `pilgrim_curve` target, then the military census,
    ## then the rest of the ramp. The interleave matters: without it a
    ## chassis whose pilgrims are being farmed rebuilds pilgrims for a
    ## thousand rounds and never fields an army (measured in phase 20: three
    ## military units in a whole game on `seed-0009`).
    var want = ukCastle          ## sentinel: nothing wanted
    let militaryFloor = MilitaryPerStructureFloor *
      max(1, s.castles + s.churches)
    let fuelOkForWar = w.fuel[ord(s.team)] >= MilitaryFuelFloor
    template tryMilitary(isEssential: bool) =
      let pick = mix(s, w.round)
      if canSpend(w, s, buildKarboniteOf(pick), buildFuelOf(pick),
                  essential = bool(isEssential)):
        want = pick
      elif canSpend(w, s, buildKarboniteOf(ukCrusader),
                    buildFuelOf(ukCrusader), essential = bool(isEssential)):
        want = ukCrusader
    if economyFloorUnmet(w, s) and
        canSpend(w, s, buildKarboniteOf(ukPilgrim), buildFuelOf(ukPilgrim),
                 essential = true):
      ## FIRST, ALWAYS. Karbonite has NO passive income in this year, so an
      ## order that spends its opening hundred on four military units has
      ## nothing left to buy a miner with and nothing that will ever earn it
      ## another karbonite. Measured in phase 20 with the two rungs the
      ## other way round: four units built in a whole 1000-round game, zero
      ## mined, zero damage, on three of four maps.
      want = ukPilgrim
    elif s.military < militaryFloor and fuelOkForWar:
      tryMilitary(true)
    elif s.pilgrims * 2 < s.pilgrimsWanted(w.round) and
        s.military >= min(4, s.militaryWanted(w.round)) and
        canSpend(w, s, buildKarboniteOf(ukPilgrim), buildFuelOf(ukPilgrim),
                 essential = true):
      want = ukPilgrim
    elif s.military < s.militaryWanted(w.round) and fuelOkForWar:
      tryMilitary(false)
    elif wantsPilgrim(w, s, w.round) and
        canSpend(w, s, buildKarboniteOf(ukPilgrim), buildFuelOf(ukPilgrim),
                 essential = true):
      want = ukPilgrim
    if want != ukCastle:
      s.commit(buildKarboniteOf(want), buildFuelOf(want))
      s.buildQueuedThisRound[r.id] = ord(want)
      result.hasAction = true
      result.kind = akBuild
      result.dx = square.dx
      result.dy = square.dy
      result.buildUnit = want
      return

  ## 3. Nothing to build: shoot, if anything is in range and the fuel gate
  ##    allows it.
  let shot = chooseAttack(w, s, r)
  if shot.ok:
    result.hasAction = true
    result.kind = akAttack
    result.dx = shot.dx
    result.dy = shot.dy

proc runChurch*(w: World, s: Side, r: Robot): Action =
  ## A church's own build queue once it exists. It has NO ATTACK (its
  ## `ATTACK_DAMAGE` is 0) and cannot read castle talk, so its turn is the
  ## build and nothing else. The legal 0-damage CHURCH attack (D6.1) is
  ## never emitted.
  result = newAction()
  result.castleTalk = castleTalkFor(w, s, r)
  let towards =
    block:
      let e = s.nearestEnemyStructure(r.x, r.y)
      if e.x >= 0: e else: mirrorTarget(w, r.x, r.y)
  let square = freeBuildSquare(w, s, r, towards)
  if not square.ok or s.buildQueuedThisRound.hasKey(r.id): return
  var want = ukCastle
  if wantsPilgrim(w, s, w.round) and
      canSpend(w, s, buildKarboniteOf(ukPilgrim), buildFuelOf(ukPilgrim),
               essential = true):
    want = ukPilgrim
  elif s.military < s.militaryWanted(w.round) and
      w.fuel[ord(s.team)] >= MilitaryFuelFloor:
    let pick = mix(s, w.round)
    if canSpend(w, s, buildKarboniteOf(pick), buildFuelOf(pick)):
      want = pick
  if want == ukCastle: return
  s.commit(buildKarboniteOf(want), buildFuelOf(want))
  s.buildQueuedThisRound[r.id] = ord(want)
  result.hasAction = true
  result.kind = akBuild
  result.dx = square.dx
  result.dy = square.dy
  result.buildUnit = want
