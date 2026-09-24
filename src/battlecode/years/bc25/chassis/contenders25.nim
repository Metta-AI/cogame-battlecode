## Source-informed native adaptations of the four archived 2025 contenders.
## The tower production rules are separate from the legacy doctrine chassis.
## Movement, pattern filling and mobile micro reuse the native primitives;
## see docs/PLAYERS-BC25.md for the explicit limits of this adaptation.
import kit, soldier, mopper, splasher
import comms as messages
import ../contenders

export contenders

proc towerMemory*(side: Side, r: Robot, round: int): ContenderTowerMemory =
  if not side.contenderTowers.hasKey(r.id):
    side.contenderTowers[r.id] = ContenderTowerMemory(
      born: round, lastSpawn: -1, lastDefense: -100, lastEnemy: round,
      plan: -1)
  side.contenderTowers[r.id]

proc nearby(w: World, r: Robot, team: Team): seq[Robot] =
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not r.spend(1): break
    let other = w.getRobot(l)
    if other != nil and other.id != r.id and other.team == team:
      result.add(other)

proc confusedBuild*(w: World, r: Robot, m: ContenderTowerMemory): UnitType =
  ## finals/Tower.java:getNextToSpawn. Counters belong to EACH tower and
  ## reset at rounds 100 and 250, not to a team-wide live census.
  let round = w.currentRound
  let chips = w.getMoney(r.team)
  if towerKindOf(r.kind) == tkPaint:
    if round < 100:
      if min(w.width, w.height) <= 30 and m.splashers == 0:
        return utSplasher
      return utSoldier
    let s = float(m.soldiers) / (if round < 250: 3.0 else: 1.0)
    let p = float(m.splashers) / (if round < 250: 1.0 else: 4.0)
    let mop = float(m.moppers) / 2.0
    if p <= s and p <= mop and
        (round >= 250 or w.stats.towers[ord(r.team)] > 6):
      return utSplasher
    let margin = if round < 250: 0.5 else: 2.0
    if mop <= s - margin: return utMopper
    if s <= mop - margin: return utSoldier
    return (if chips >= 2000: utMopper else: utSoldier)
  if round < 100:
    if min(w.width, w.height) <= 30 and m.splashers == 0 and r.paint >= 300:
      return utSplasher
    return utSoldier
  if r.paint < 200: return utMopper
  if round < 250:
    return (if chips > 1500 and r.paint >= 300: utSplasher else: utSoldier)
  if r.paint < 300: return utSoldier
  if chips > 1500 and round mod 10 != 0: return utSplasher
  utSoldier

proc spaarkWeights*(towers, paintTowers: int): array[3, float] =
  ## SPAARK/Tower.java:run, in soldier/mopper/splasher order.
  result = [1.5 - float(towers) * 0.05, 1.2, 0.2 + float(paintTowers) * 0.3]
  let total = result[0] + result[1] + result[2]
  for i in 0 .. 2: result[i] /= total

proc spaarkBuild*(w: World, r: Robot, m: ContenderTowerMemory,
                  weights: array[3, float]): UnitType =
  if (w.currentRound < 50 or towerKindOf(r.kind) == tkMoney) and m.spawned < 3:
    return utSoldier
  let s = m.soldierWeight + weights[0] - float(m.soldiers)
  let mop = m.mopperWeight + weights[1] - float(m.moppers)
  let p = m.splasherWeight + weights[2] - float(m.splashers)
  if s >= p and s >= mop: utSoldier
  elif mop >= p: utMopper
  else: utSplasher

const OmNomPlans = [
  @[utSoldier, utSoldier, utSoldier, utSoldier, utMopper],
  @[utSplasher, utSplasher, utSoldier, utSoldier, utMopper],
  @[utSoldier, utSoldier, utSoldier, utMopper],
  @[utSplasher, utSoldier, utMopper]]

proc omNomBuild*(w: World, r: Robot, m: ContenderTowerMemory): UnitType =
  ## templates/Tower.java.jinja2:getSpawnPlan/initTurn. A plan is chosen
  ## at birth and every 200 rounds; the per-plan cursor survives switches.
  if m.plan < 0 or w.currentRound mod 200 == 0:
    let early = w.currentRound < 30 or
      (w.getMoney(r.team) < 2000 and w.stats.towers[ord(r.team)] < 4)
    m.plan = (if towerKindOf(r.kind) == tkPaint: 0 else: 2) +
      (if early: 0 else: 1)
  OmNomPlans[m.plan][m.planCursors[m.plan]]

proc advanceOmNom(m: ContenderTowerMemory) =
  m.planCursors[m.plan] = (m.planCursors[m.plan] + 1) mod OmNomPlans[m.plan].len

proc buildAt(w: World, r: Robot, kind: UnitType, target: Loc): bool =
  var pick = loc(-1, -1)
  var distance = high(int)
  for l in w.locationsWithinRadiusSquared(r.loc, BuildRobotRadiusSquared):
    if not r.spend(1): break
    if not w.canBuildRobot(r, kind, l): continue
    let d = l.distanceSquaredTo(target)
    if d < distance:
      distance = d
      pick = l
  if pick.x < 0: return false
  w.doBuildRobot(r, kind, pick)
  true

proc recordBuild(m: ContenderTowerMemory, kind: UnitType, round: int) =
  inc m.spawned
  m.lastSpawn = round
  case kind
  of utSoldier: inc m.soldiers
  of utMopper: inc m.moppers
  of utSplasher: inc m.splashers
  else: discard

proc contenderShots(w: World, r: Robot, kind: Contender25) =
  ## Preserve the notable targeting differences: Om Nom prioritizes painted
  ## splashers; Just Woke Up prioritizes soldiers; confused picks lowest HP.
  if kind != ctOmNom and w.canTowerAttackArea(r): w.doTowerAttackArea(r)
  var pick: Robot
  var best = high(int)
  for enemy in nearby(w, r, r.team.other()):
    if not w.canTowerAttackSingle(r, enemy.loc): continue
    if kind == ctOmNom and enemy.paint == 0: continue
    var score = enemy.health
    if kind == ctOmNom:
      score += (if enemy.kind == utSplasher: 0
                elif enemy.kind == utSoldier: 10000 else: 20000)
    elif kind == ctJustWokeUp and enemy.kind != utSoldier:
      score += 10000
    if kind == ctSpaark and pick != nil:
      let strength = UnitSpecs[r.kind].attackStrength
      if (pick.health > strength and enemy.health < pick.health) or
          (enemy.health > pick.health and enemy.health <= strength):
        pick = enemy
      continue
    if score < best:
      best = score
      pick = enemy
  if pick != nil: w.doTowerAttackSingle(r, pick.loc)
  if kind == ctOmNom and w.canTowerAttackArea(r): w.doTowerAttackArea(r)

proc runContenderTower*(w: World, side: Side, r: Robot, kind: Contender25) =
  let m = towerMemory(side, r, w.currentRound)
  let round = w.currentRound
  let chips = w.getMoney(r.team)
  let allies = nearby(w, r, r.team)
  let enemies = nearby(w, r, r.team.other())
  let moneyChanged = chips != m.previousMoney
  m.previousMoney = chips
  if enemies.len > 0: m.lastEnemy = round
  if kind == ctConfused and round in [100, 250]:
    m.soldiers = 0
    m.moppers = 0
    m.splashers = 0
    m.defenseMoppers = 0

  var upgrade = false
  if r.kind.canUpgradeType():
    let cost = UnitSpecs[r.kind.nextLevel()].moneyCost
    case kind
    of ctOmNom:
      upgrade = towerKindOf(r.kind) == tkPaint and chips >= cost + 1000 and
        round - m.lastEnemy >= 10
    of ctJustWokeUp:
      upgrade = if towerKindOf(r.kind) == tkPaint:
        chips > 2500 and (allies.len >= 3 or chips > 3500)
      else: chips > 3600 and (allies.len > 3 or chips > 4000)
    of ctSpaark: upgrade = chips >= cost + 1000
    of ctConfused: discard # The native mobile upgrade path handles this.
  if upgrade and w.canUpgradeTower(r, r.loc): w.doUpgradeTower(r, r.loc)
  contenderShots(w, r, kind)

  var want = utSoldier
  var allowed = false
  var defense = false
  var target = loc(w.width div 2, w.height div 2)
  var alliedMoppers, enemySoldiers = 0
  for ally in allies:
    if ally.kind == utMopper: inc alliedMoppers
  for enemy in enemies:
    if enemy.kind == utSoldier: inc enemySoldiers
  var weights: array[3, float]
  case kind
  of ctConfused:
    if m.born == 1 and round <= 3:
      allowed = true
    elif round > 4:
      want = confusedBuild(w, r, m)
      allowed = w.getMoney(r.team) >= UnitSpecs[want].moneyCost + 1000
      for enemy in enemies:
        if enemy.kind.isTowerType(): continue
        if r.loc.distanceSquaredTo(enemy.loc) <= 9 and alliedMoppers < 2 and
            m.defenseMoppers < 1:
          want = utMopper
          allowed = true
          defense = true
          target = enemy.loc
          break
  of ctJustWokeUp:
    if enemySoldiers > alliedMoppers and moneyChanged and
        (round - m.lastDefense > 25 or m.defenseMoppers < enemySoldiers):
      want = utMopper
      defense = true
      allowed = true
      target = enemies[0].loc
    elif towerKindOf(r.kind) == tkPaint or m.born < 8:
      if round < 400 and w.stats.towers[ord(r.team)] <= 5:
        want = if m.planCursor mod 3 < 2: utSoldier else: utSplasher
        allowed = moneyChanged and allies.len < 3 and
          ((m.planCursor < 2 and m.born < 8) or chips > 2100)
      else:
        want = [utSoldier, utMopper, utSplasher][m.planCursor mod 3]
        allowed = moneyChanged and chips > 1100
    else:
      want = utSoldier
      allowed = (w.stats.towers[ord(r.team)] >= 4 or chips > 2000) and chips > 1100
  of ctOmNom:
    want = omNomBuild(w, r, m)
    for enemy in enemies:
      if enemy.kind in {utSoldier, utSplasher} and round - m.lastDefense >= 30:
        defense = true
        want = utMopper
        target = enemy.loc
        break
    let grace = if w.width * w.height <= 600: 50 else: 10
    allowed = defense or round <= grace or w.getMoney(r.team) >= 1250
    if r.paint < UnitSpecs[want].paintCost and towerKindOf(r.kind) == tkMoney:
      if round > 30: advanceOmNom(m)
      allowed = false
  of ctSpaark:
    var paintTowers = 0
    var seen: seq[Loc]
    for l in side.homeTowers & side.knownRuins:
      if l in seen: continue
      seen.add(l)
      let tower = w.getRobot(l)
      if tower != nil and tower.team == r.team and tower.kind.isTowerType() and
          towerKindOf(tower.kind) == tkPaint:
        inc paintTowers
    weights = spaarkWeights(w.stats.towers[ord(r.team)], paintTowers)
    want = spaarkBuild(w, r, m, weights)
    allowed = w.stats.towers[ord(r.team)] == MaxNumberOfTowers or round < 10 or
      (w.getMoney(r.team) - UnitSpecs[want].moneyCost >= 900 and
       (round < 100 or (m.lastSpawn + 1 < round and allies.len < 4)))
  if allowed and buildAt(w, r, want, target):
    recordBuild(m, want, round)
    if defense:
      if round - m.lastDefense > 25: m.defenseMoppers = 0
      inc m.defenseMoppers
      m.lastDefense = round
    else:
      inc m.planCursor
      if kind == ctOmNom: advanceOmNom(m)
    if kind == ctSpaark:
      m.soldierWeight += weights[0]
      m.mopperWeight += weights[1]
      m.splasherWeight += weights[2]
  messages.towerRelay(w, side, r)

proc persistentRefill(w: World, side: Side, r: Robot): bool =
  ## Just Woke Up's 25% entry / 75% exit hysteresis prevents repeated short
  ## refill trips. The state belongs to the unit, never to the whole team.
  let capacity = UnitSpecs[r.kind].paintCapacity
  if r.paint * 4 <= capacity: side.contenderRefilling[r.id] = true
  if r.paint * 4 >= capacity * 3: side.contenderRefilling[r.id] = false
  if not side.contenderRefilling.getOrDefault(r.id): return false
  let target = nearestFriendlyTower(w, side, r, needPaint = true)
  if target.x < 0: return false
  if r.loc.distanceSquaredTo(target) <= PaintTransferRadiusSquared:
    discard withdrawFrom(w, side, r, target)
  else:
    w.stepToward(side, r, target)
    discard paintFrontier(w, side, r)
  true

proc runContenderSoldier(w: World, side: Side, r: Robot, kind: Contender25) =
  observeRuins(w, side, r)
  # Both confused and Om Nom put combat ahead of economy in their turn loop.
  if kind in {ctConfused, ctOmNom} and strikeTower(w, side, r): return
  if kind == ctJustWokeUp:
    if persistentRefill(w, side, r): return
    if r.health > 40:
      for enemy in nearby(w, r, r.team.other()):
        if enemy.kind.isTowerType() and towerKindOf(enemy.kind) != tkDefense:
          if w.canAttackRobot(r, enemy.loc):
            w.doAttackRobot(r, enemy.loc)
            return
  elif tryRefill(w, side, r): return
  if workClaim(w, side, r): return
  if claimTarget(w, side, r) and workClaim(w, side, r): return
  let srpReady = case kind
    of ctJustWokeUp: w.stats.towers[ord(r.team)] >= 4 and
      nearby(w, r, r.team.other()).len == 0
    of ctSpaark: w.currentRound >= 50
    else: true
  if srpReady and workSrp(w, side, r, earliestRound = 50): return
  if strikeTower(w, side, r): return
  w.stepToward(side, r, frontierFor(w, side))
  discard paintFrontier(w, side, r)

proc runContender25*(w: World, side: Side, r: Robot, kind: Contender25) =
  observeHome(w, side)
  measureChokes(w, side)
  refreshCensus(w, side)
  noteTowerLoss(w, side)
  if r.kind.isTowerType():
    runContenderTower(w, side, r, kind)
    return
  if kind == ctConfused:
    let up = upgradePick(w, side, r)
    if up.x >= 0 and w.canUpgradeTower(r, up): w.doUpgradeTower(r, up)
  case r.kind
  of utSoldier: runContenderSoldier(w, side, r, kind)
  of utMopper: runMopper(w, side, r)
  of utSplasher: runSplasher(w, side, r)
  else: discard
  messages.soldierReport(w, side, r)
