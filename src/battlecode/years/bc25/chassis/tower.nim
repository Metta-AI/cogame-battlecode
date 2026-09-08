## `tower.nim` — a tower's whole turn.
##
## Behaviour ported from `erikji/battlecode25` `src/SPAARK/` (AGPL-3.0, head
## `63165da`): the tower-driven build order and the comms word relay.
##
## A tower's shots are FREE — `assertCanAttackTower` never checks a cooldown —
## so the order is always: shoot, shoot, build, talk. There is never a reason
## to skip a shot, and a knob that could make a tower skip one would be a knob
## that makes the clan inert.
##
##   1. the SINGLE-target shot at the lowest-HP enemy robot in range, tiebreak
##      splasher -> soldier -> mopper (a splasher is the most expensive thing
##      on the board and the one that breaks towers)
##   2. the AREA shot whenever any enemy is in range
##   3. build the unit `econ.nim` asks for, at the free tile nearest the front
##   4. broadcast the frontier word while under the 20-message cap

import kit, econ, comms

export kit, econ, comms

func threatRank(k: UnitType): int =
  case k
  of utSplasher: 0
  of utSoldier: 1
  of utMopper: 2
  else: 3

proc singleShot*(w: World, side: Side, r: Robot): bool {.discardable.} =
  if r.towerSingleAttacked: return false
  var pick = loc(-1, -1)
  var bestHp = high(int)
  var bestRank = high(int)
  for l in w.locationsWithinRadiusSquared(
      r.loc, UnitSpecs[r.kind].actionRadiusSquared):
    if not r.spend(1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team == side.team: continue
    if not bot.kind.isRobotType(): continue
    let rank = threatRank(bot.kind)
    if bot.health < bestHp or (bot.health == bestHp and rank < bestRank):
      bestHp = bot.health
      bestRank = rank
      pick = l
  if pick.x < 0: return false
  w.doTowerAttackSingle(r, pick)
  true

proc areaShot*(w: World, side: Side, r: Robot): bool {.discardable.} =
  if r.towerAreaAttacked: return false
  var any = false
  for l in w.locationsWithinRadiusSquared(
      r.loc, UnitSpecs[r.kind].actionRadiusSquared):
    if not r.spend(1): break
    let bot = w.getRobot(l)
    if bot != nil and bot.team != side.team:
      any = true
      break
  if not any: return false
  w.doTowerAttackArea(r)
  true

proc buildStep*(w: World, side: Side, r: Robot): bool {.discardable.} =
  ## THE ANTI-INERT RULE, and it is unconditional: a tower that can pay for a
  ## robot builds one, on every doctrine, at every knob setting. What the
  ## knobs change is WHICH robot.
  if not r.isActionReady(): return false
  let want = nextBuild(w, side, r)
  var pick = loc(-1, -1)
  var best = high(int)
  let front = frontierFor(w, side)
  for l in w.locationsWithinRadiusSquared(r.loc, BuildRobotRadiusSquared):
    if not r.spend(1): break
    if not w.canBuildRobot(r, want, l): continue
    let d = l.distanceSquaredTo(front)
    if d < best:
      best = d
      pick = l
  if pick.x < 0: return false
  w.doBuildRobot(r, want, pick)
  true

proc runTower*(w: World, side: Side, r: Robot) =
  observeHome(w, side)
  refreshCensus(w, side)
  noteTowerLoss(w, side)
  discard singleShot(w, side, r)
  discard areaShot(w, side, r)
  discard buildStep(w, side, r)
  towerRelay(w, side, r)
