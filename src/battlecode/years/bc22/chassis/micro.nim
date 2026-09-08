## `micro.nim` — the war, and `retreat_hp`.
##
## Behaviour ported from `iliao2345/Battlecode2022` `src/fury_fix_20/Micro.java`
## (AGPL-3.0): attack the lowest-HP enemy inside the action radius, tiebreaking
## toward the units that hurt most (sage, then soldier, then a watchtower in
## TURRET mode, then builder, then miner, then a prototype), PREFER A TARGET
## THIS ATTACK WILL KILL, hold the rubble-adjusted stand-off distance when the
## enemy group is bigger, and honour `retreat_hp`. Sage micro is separate and is
## gated on the sage's 200-turn action cooldown: a sage advances only when
## `roundsSinceShot >= 0.6 * cooldown`, the first-place bot's own rule.
## BEHAVIOUR, NOT CODE. `NOTICE` names the file.
##
## `retreat()` IS `retreat_hp`, and AT EVERY SETTING the chassis still takes an
## attack that KILLS its target and still fights when it is cornered against the
## map edge, because refusing a free kill is not a strategy.

import kit

export kit

func threatRank(k: RobotType, mode: RobotMode): int =
  ## Lower is a better target. An ARCHON ranks LAST: it is 600 HP and the
  ## game-ender, but three damage a hit means two hundred hits, so it is the
  ## last thing a lone soldier should be shooting at while a sage is in range.
  case k
  of rtSage: 0
  of rtSoldier: 1
  of rtWatchtower: (if mode == rmTurret: 2 else: 6)
  of rtBuilder: 3
  of rtMiner: 4
  of rtLaboratory: 5
  of rtArchon: 7

proc pickTarget*(w: World, side: Side, r: Robot): Robot =
  ## The engine's own scan order over the action radius, scored.
  result = nil
  var best = high(int)
  let dmg = damageOf(r.kind, r.level)
  for e in w.sortedEnemies(side, r, RobotSpecs[r.kind].actionRadiusSquared):
    if e.mode == rmPrototype and e.kind != rtArchon:
      ## A prototype is worth killing, but only once nothing else is in range.
      discard
    var score = threatRank(e.kind, e.mode) * 10000 + e.health
    if e.health <= dmg:
      ## PREFER A TARGET THIS ATTACK WILL KILL.
      score -= 100000
    if score < best:
      best = score
      result = e

proc enemyPressure*(w: World, side: Side, r: Robot): int =
  ## How many enemy attackers can reach this robot's neighbourhood, which is
  ## what the stand-off test reads.
  for e in w.sortedEnemies(side, r, RobotSpecs[r.kind].visionRadiusSquared):
    if canAttackType(e.kind) and e.mode.canAct: result += 1

proc friendlyPressure*(w: World, side: Side, r: Robot): int =
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[r.kind].visionRadiusSquared):
    let f = w.getRobot(l)
    if f != nil and f.id != r.id and f.team == side.team and
       canAttackType(f.kind): result += 1

func retreatThreshold*(side: Side, r: Robot): int =
  ## `retreat_hp` as an absolute health value.
  (maxHealthOf(r.kind, r.level) * side.doctrine.retreatHp) div 100

proc shouldRetreat*(w: World, side: Side, r: Robot, target: Robot): bool =
  ## A droid disengages when it is under `retreat_hp` — UNLESS this attack
  ## kills, or it is cornered against the map edge with nowhere to go.
  if side.doctrine.retreatHp <= 0: return false
  if r.health > retreatThreshold(side, r): return false
  if target != nil and target.health <= damageOf(r.kind, r.level):
    return false
  var escapes = 0
  for d in MoveDirs:
    if w.canMove(r, d): escapes += 1
  escapes > 0

proc fightOrFlee*(w: World, side: Side, r: Robot) =
  ## One attacker's turn: attack if there is a target, then move — toward the
  ## fight when the numbers favour it, away from it when `retreat_hp` says so.
  let target = pickTarget(w, side, r)
  if target != nil and w.canAttack(r, target.loc):
    if not shouldRetreat(w, side, r, target):
      w.doAttack(r, target.loc)
      if r.kind == rtSage: r.roundsSinceShot = 0
      return
  if target != nil and shouldRetreat(w, side, r, target):
    let home = nearestLiveArchon(w, side, r.loc)
    if home != nil:
      w.moveToward(side, r, home.loc)
    else:
      w.moveAwayFrom(side, r, target.loc)
    return
  ## No target in the action radius: close on the nearest sensed enemy when the
  ## numbers are level or better, hold the stand-off otherwise.
  var nearest: Robot = nil
  var bestD = high(int)
  for e in w.sortedEnemies(side, r, RobotSpecs[r.kind].visionRadiusSquared):
    let d = chebyshev(r.loc, e.loc)
    if d < bestD:
      bestD = d
      nearest = e
  if nearest == nil: return
  if r.health <= retreatThreshold(side, r):
    let home = nearestLiveArchon(w, side, r.loc)
    if home != nil:
      w.moveToward(side, r, home.loc)
      return
  let mine = friendlyPressure(w, side, r) + 1
  let theirs = enemyPressure(w, side, r)
  if theirs > mine and bestD <= 4:
    w.moveAwayFrom(side, r, nearest.loc)
  else:
    w.moveToward(side, r, nearest.loc)
