## Towers: mining, the two per-turn attacks, building robots, building and
## upgrading towers, and the defense-damage ledger.
##
## Ported from `world/InternalRobot.java` (`processBeginningOfRound`'s mining,
## `towerAttack`), `world/RobotControllerImpl.java` (`buildRobot`,
## `completeTowerPattern`, `upgradeTower`) and `world/GameWorld.java`
## (`completeTowerPattern`, `upgradeTower`, the 25-tower cap).
##
## Three things in here look like details and are not:
##
## * **A tower's attack costs NO COOLDOWN AT ALL.** `assertCanAttackTower`
##   never calls `assertIsActionReady`, and `RobotControllerImpl.attack` only
##   charges a cooldown when the actor `isRobotType()`. A tower may fire ONE
##   single-target shot and ONE area shot every single turn, forever.
## * **The `attackMoneyBonus` is paid ONCE PER SHOT THAT LANDS**, so a defense
##   tower that connects with both its single shot and its area shot earns it
##   twice in one turn.
## * **The AoE defense buff is `round(buff * 0 / 100.0)` = +0.**
##   `DEFENSE_ATTACK_BUFF_AOE_EFFECTIVENESS` is 0 in 2025, so a defense tower
##   buffs only the SINGLE-target shot of every allied tower. The expression is
##   kept in the port because it is the engine's, and because a future year
##   changing that constant should change this file and nothing else.

import world

export world

# ---------------------------------------------------------------------------
#  Mining — rule 1c
# ---------------------------------------------------------------------------

proc mine*(w: World, r: Robot) =
  ## `InternalRobot.processBeginningOfRound`'s two mining lines. A PAINT tower
  ## adds `paintPerTurn + 3 * (active SRPs of its team)` to ITS OWN stash,
  ## capped at its 1000 capacity; a MONEY tower adds the same shape to the
  ## TEAM chip pool. THE SRP BONUS IS PER MINING TOWER, NOT PER TEAM.
  let spec = UnitSpecs[r.kind]
  let bonus = w.extraResourcesFromPatterns(r.team)
  if spec.paintPerTurn != 0:
    let before = r.paint
    r.addPaint(spec.paintPerTurn + bonus)
    w.stats.paintMined[ord(r.team)] += r.paint - before
  if spec.moneyPerTurn != 0:
    w.addMoney(r.team, spec.moneyPerTurn + bonus)

# ---------------------------------------------------------------------------
#  Rule 4.6 — the two tower attacks
# ---------------------------------------------------------------------------

func canTowerAttackSingle*(w: World, r: Robot, l: Loc): bool =
  if not r.kind.isTowerType(): return false
  if r.towerSingleAttacked: return false
  w.canActLocation(r, l, UnitSpecs[r.kind].actionRadiusSquared)

func canTowerAttackArea*(w: World, r: Robot): bool =
  r.kind.isTowerType() and not r.towerAreaAttacked

proc doTowerAttackSingle*(w: World, r: Robot, l: Loc) =
  ## Single damage is `attackStrength + defenseTowerDamageIncrease(team)`.
  if not w.canTowerAttackSingle(r, l):
    w.refusedActions += 1
    return
  r.towerSingleAttacked = true
  var hit = false
  let target = w.getRobot(l)
  if target != nil and target.team != r.team:
    hit = true
    let damage = UnitSpecs[r.kind].attackStrength +
      w.damageIncrease[ord(r.team)]
    let dealt = min(damage, target.health)
    w.stats.robotDamageDealt[ord(r.team)] += dealt
    let fatal = target.health - damage <= 0
    w.addHealth(target, -damage)
    if fatal: w.stats.killsByTowers[ord(r.team)] += 1
  if hit:
    w.addMoney(r.team, UnitSpecs[r.kind].attackMoneyBonus)
  w.noteFirstAction(r, Bc25ActionTowerAttack)

proc doTowerAttackArea*(w: World, r: Robot) =
  ## `loc == null` in the engine: every ENEMY UNIT — robot or tower — within
  ## the tower's own `actionRadiusSquared`, in engine scan order.
  if not w.canTowerAttackArea(r):
    w.refusedActions += 1
    return
  r.towerAreaAttacked = true
  let aoe = UnitSpecs[r.kind].aoeAttackStrength +
    javaRound(float64(w.damageIncrease[ord(r.team)] *
      DefenseAttackBuffAoeEffectiveness) / 100.0)
  var hit = false
  var victims: seq[int]
  for l in w.locationsWithinRadiusSquared(
      r.loc, UnitSpecs[r.kind].actionRadiusSquared):
    let target = w.getRobot(l)
    if target != nil and target.team != r.team:
      hit = true
      victims.add(target.id)
  for id in victims:
    if not w.existsRobot(id): continue
    let target = w.robotsById[id]
    let dealt = min(aoe, target.health)
    w.stats.robotDamageDealt[ord(r.team)] += dealt
    let fatal = target.health - aoe <= 0
    w.addHealth(target, -aoe)
    if fatal: w.stats.killsByTowers[ord(r.team)] += 1
  if hit:
    w.addMoney(r.team, UnitSpecs[r.kind].attackMoneyBonus)
  w.noteFirstAction(r, Bc25ActionTowerAoe)

# ---------------------------------------------------------------------------
#  Rule 4.7 — build a robot
# ---------------------------------------------------------------------------

func canBuildRobot*(w: World, r: Robot, kind: UnitType, l: Loc): bool =
  if not w.canActLocation(r, l, BuildRobotRadiusSquared): return false
  if not r.isActionReady(): return false
  if not r.kind.isTowerType(): return false
  if not kind.isRobotType(): return false
  if r.paint < UnitSpecs[kind].paintCost: return false
  if w.getMoney(r.team) < UnitSpecs[kind].moneyCost: return false
  if w.isLocationOccupied(l): return false
  w.isPassable(l)

proc doBuildRobot*(w: World, r: Robot, kind: UnitType, l: Loc) =
  ## In the engine's own order: charge the tower +10 action cooldown (towers
  ## never get the low-paint surcharge), SPAWN the robot at 100 % of its paint
  ## capacity, deduct the paint from THE TOWER, deduct the chips from THE
  ## TEAM.
  if not w.canBuildRobot(r, kind, l):
    w.refusedActions += 1
    return
  r.addActionCooldownTurns(BuildRobotCooldown)
  w.spawnRobot(kind, l, r.team)
  r.addPaint(-UnitSpecs[kind].paintCost)
  w.addMoney(r.team, -UnitSpecs[kind].moneyCost)
  let t = ord(r.team)
  w.stats.paintSpent[t] += UnitSpecs[kind].paintCost
  w.stats.robotsBuilt[t] += 1
  if w.currentRound <= 400: w.stats.robotsBuiltBy400[t] += 1
  case kind
  of utSoldier: w.stats.soldiersBuilt[t] += 1
  of utSplasher: w.stats.splashersBuilt[t] += 1
  of utMopper: w.stats.moppersBuilt[t] += 1
  else: discard
  w.noteFirstAction(r, Bc25ActionBuildRobot)

# ---------------------------------------------------------------------------
#  Rule 4.10 — complete a tower pattern
# ---------------------------------------------------------------------------

proc canCompleteTowerPattern*(w: World, r: Robot, kind: TowerKind, l: Loc,
                              charge: Robot = nil): bool =
  ## `assertCanCompleteTowerPattern`, in its own order. The 25-tower cap is
  ## checked LAST, after the pattern itself, which is how the engine spends
  ## the check and how the port spends the `DecisionOps`.
  if not r.kind.isRobotType(): return false
  if not w.canActLocation(r, l, BuildTowerRadiusSquared): return false
  if w.hasTower(l): return false
  if not w.hasRuin(l): return false
  if w.getMoney(r.team) < UnitSpecs[towerTypeFor(kind)].moneyCost: return false
  if not w.isValidPatternCenter(l, true): return false
  if w.getRobot(l) != nil: return false
  if not w.checkTowerPattern(r.team, l, towerTypeFor(kind), charge):
    return false
  w.stats.towers[ord(r.team)] < MaxNumberOfTowers

proc doCompleteTowerPattern*(w: World, r: Robot, kind: TowerKind, l: Loc) =
  ## The tower appears at LEVEL ONE with 500 paint and full HP, the team pays
  ## 1000 chips, and a DEFENSE tower immediately adds +5 to the team's tower
  ## damage (inside `spawnRobot`).
  if not w.canCompleteTowerPattern(r, kind, l):
    w.refusedActions += 1
    return
  let kindType = towerTypeFor(kind)
  w.towersByLoc[w.idx(l)] = int8(ord(r.team) + 1)
  w.spawnRobot(kindType, l, r.team)
  w.addMoney(r.team, -UnitSpecs[kindType].moneyCost)
  let t = ord(r.team)
  w.stats.chipsSpentOnTowers[t] += UnitSpecs[kindType].moneyCost
  w.stats.towersBuilt[t] += 1
  if w.currentRound <= 400: w.stats.towersBuiltBy400[t] += 1
  if kind == tkDefense: w.stats.defenseTowersBuilt[t] += 1
  discard w.beat(BeatTowerBuilt, "tower_built", t, ord(kind),
    l.x * 100 + l.y, $w.stats.towers[t])
  w.noteFirstAction(r, Bc25ActionCompleteTowerPattern)

# ---------------------------------------------------------------------------
#  Rule 4.11 — upgrade a tower
# ---------------------------------------------------------------------------

func canUpgradeTower*(w: World, r: Robot, l: Loc): bool =
  if not w.canActLocation(r, l, BuildTowerRadiusSquared): return false
  let tower = w.getRobot(l)
  if tower == nil: return false
  if not tower.kind.isTowerType(): return false
  if tower.team != r.team: return false
  if not tower.kind.canUpgradeType(): return false
  w.getMoney(r.team) >= UnitSpecs[tower.kind.nextLevel()].moneyCost

proc doUpgradeTower*(w: World, r: Robot, l: Loc) =
  ## Pay the chips, then `InternalRobot.upgradeTower` — WHICH CARRIES THE
  ## DAMAGE ACROSS: `newHealth = newType.health - (oldType.health - health)`.
  ## No cooldown, no paint. A defense tower adds a further +2 to the team's
  ## tower damage.
  if not w.canUpgradeTower(r, l):
    w.refusedActions += 1
    return
  let tower = w.getRobot(l)
  let oldType = tower.kind
  let newType = oldType.nextLevel()
  w.addMoney(r.team, -UnitSpecs[newType].moneyCost)
  tower.health = upgradedHealth(oldType, newType, tower.health)
  tower.kind = newType
  w.damageIncrease[ord(r.team)] += defenseBuffOnUpgrade(newType)
  let t = ord(r.team)
  w.stats.chipsSpentOnTowers[t] += UnitSpecs[newType].moneyCost
  w.stats.towersUpgraded[t] += 1
  discard w.beat(BeatTowerUpgraded, "tower_upgraded", t,
    UnitSpecs[newType].level, l.x * 100 + l.y, $ord(towerKindOf(newType)))
  w.noteFirstAction(r, Bc25ActionUpgradeTower)

# ---------------------------------------------------------------------------
#  Census helpers the chassis and the chrome both read
# ---------------------------------------------------------------------------

func towersAlive*(w: World, t: Team): int = w.stats.towers[ord(t)]

func towerCountByKind*(w: World, t: Team, kind: TowerKind): int =
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == t and r.kind.isTowerType() and towerKindOf(r.kind) == kind:
      result += 1

func robotsAlive*(w: World, t: Team): int =
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == t and r.kind.isRobotType(): result += 1

func robotCountByKind*(w: World, t: Team, kind: UnitType): int =
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == t and r.kind == kind: result += 1
