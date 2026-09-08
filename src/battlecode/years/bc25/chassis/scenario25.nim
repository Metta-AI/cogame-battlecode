## `scenario25` — the Tier A-prime scenario script, and the Nim twin of
## `tools/oracle/bc25/bc25scenario/RobotPlayer.java`.
##
## WHY IT EXISTS. Tier A's own measurement showed exactly what it cannot
## cover: over eight full 2000-round games the 2025 example bot never built a
## defense tower, never built a splasher (the branch is commented out
## upstream), never upgraded a tower, never completed a resource pattern,
## never sent a message, and ended every game on `MORE_SQUARES_PAINTED` at
## round 2000. So `paint_enough_area`, `destroy_all_units`, the four deeper
## tiebreak rungs, the SRP lifecycle, the 25-tower cap, the defense buff and
## the whole comms subsystem are untested by it — precisely the "rare code
## paths that fire mid-game" the Fleet card 1218171523823317 postmortem warns
## about.
##
## THREE PROPERTIES, each of which the parity job asserts:
##  (a) NO RNG AT ALL. Every decision is a function of the round number, the
##      unit's type and its position in the exec order. There is no draw to
##      desynchronise.
##  (b) CHEAP. The job asserts it never exceeds 25 % of its bytecode limit, so
##      it can never be cut off mid-turn and the "no mid-turn resumption"
##      divergence is never exercised.
##  (c) SCRIPTED BY ROUND NUMBER TO FORCE EVERY RARE PATH EARLY.
##
## Three variants, selected at compile time and mirrored by three Java
## packages:
##   -d:bc25Scenario       the base script
##   -d:bc25ScenarioPaint  + soldiers paint flat out, to fire PAINT_ENOUGH_AREA
##   -d:bc25ScenarioWipe   + everything hunts enemy units, to fire
##                           DESTROY_ALL_UNITS
##
## THE JAVA TWIN IS WRITTEN LINE FOR LINE AGAINST THIS FILE. If a scripted
## path turns out to be impossible to force deterministically, the failing
## item is DROPPED FROM BOTH SIDES and added to `docs/PARITY.md` §What is NOT
## compared with the reason — never silently left in a bot that does not reach
## it.

import kit

export kit

const
  ScenarioPaint* = defined(bc25ScenarioPaint)
  ScenarioWipe* = defined(bc25ScenarioWipe)

func scenarioTowerKind(index: int): TowerKind =
  ## Rotate the three families so all three are built, and both upgrade paths
  ## are exercised.
  case index mod 3
  of 0: tkMoney
  of 1: tkPaint
  else: tkDefense

proc firstEnemy(w: World, r: Robot, r2: int): Loc =
  ## `rc.getAllLocationsWithinRadiusSquared` CLAMPS its radius to
  ## `VISION_RADIUS_SQUARED` and then FILTERS by `canSenseLocation`. Every
  ## sweep in this file reproduces both, because the Java twin calls that
  ## method and a sweep that saw one more tile than the engine's would
  ## desynchronise the two bots on the first ruin at the edge of vision.
  result = loc(-1, -1)
  for l in w.locationsWithinRadiusSquared(r.loc, min(r2, VisionRadiusSquared)):
    if not r.spend(1): break
    if not w.canSenseLocation(r, l): continue
    let bot = w.getRobot(l)
    if bot != nil and bot.team != r.team:
      return l

proc scenarioTower(w: World, side: Side, r: Robot) =
  ## Shoot, shoot, build. The build schedule forces all three robot types
  ## early and then keeps a trickle going so the exec order keeps churning.
  let single = firstEnemy(w, r, UnitSpecs[r.kind].actionRadiusSquared)
  if single.x >= 0 and w.canTowerAttackSingle(r, single):
    w.doTowerAttackSingle(r, single)
  if single.x >= 0 and w.canTowerAttackArea(r):
    w.doTowerAttackArea(r)

  ## The build schedule forces all three robot types early and then keeps a
  ## trickle of soldiers going, because SOLDIERS ARE WHAT PAINT PATTERNS and a
  ## scenario bot that spent its towers' paint on moppers would never raise a
  ## tower and would prove nothing.
  var want = utSoldier
  if w.currentRound == 4: want = utMopper
  elif w.currentRound == 8: want = utSplasher
  elif w.currentRound mod 41 == 0: want = utMopper
  elif w.currentRound mod 53 == 0: want = utSplasher

  ## THE TOWER RESERVE: never spend the chips a `completeTowerPattern` needs.
  if w.getMoney(r.team) - UnitSpecs[want].moneyCost >=
      UnitSpecs[utLevelOneMoneyTower].moneyCost:
    for l in w.locationsWithinRadiusSquared(r.loc, BuildRobotRadiusSquared):
      if not r.spend(1): break
      if not w.canSenseLocation(r, l): continue
      if w.canBuildRobot(r, want, l):
        w.doBuildRobot(r, want, l)
        break

  ## Tower->tower broadcast across an unpainted gap: no connectivity needed,
  ## and it fires from round 5 so the comms path is compared early.
  if w.currentRound >= 5 and w.currentRound mod 11 == 0 and
      w.canBroadcastMessage(r):
    w.doBroadcastMessage(r, w.currentRound)

proc scenarioSoldier(w: World, side: Side, r: Robot) =
  ## Claim the FIRST ruin in scan order that has no tower, mark it, fill it,
  ## complete it, and upgrade any friendly tower in reach. Then paint under
  ## itself.
  var ruin = loc(-1, -1)
  var ruinIndex = 0
  var seen = 0
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not r.spend(1): break
    if not w.canSenseLocation(r, l): continue
    if not w.hasRuin(l): continue
    seen += 1
    if w.getRobot(l) != nil: continue
    if ruin.x < 0:
      ruin = l
      ruinIndex = w.idx(l)

  ## Upgrading is free of cooldown and paint, so it never competes with the
  ## turn's action — which is what makes the LEVEL_TWO and LEVEL_THREE paths
  ## reachable this early.
  for l in w.locationsWithinRadiusSquared(r.loc, BuildTowerRadiusSquared):
    if not r.spend(1): break
    if not w.canSenseLocation(r, l): continue
    if w.canUpgradeTower(r, l):
      w.doUpgradeTower(r, l)
      break

  if ruin.x >= 0:
    let kind = scenarioTowerKind(ruinIndex)
    if r.loc.distanceSquaredTo(ruin) > BuildTowerRadiusSquared:
      let dir = r.loc.directionTo(ruin)
      if w.canMove(r, dir):
        w.doMove(r, dir)
    let behind = ruin.translate(1, 0)
    let behindMark =
      if w.onTheMap(behind) and w.canSenseLocation(r, behind):
        w.getMarker(r.team, behind)
      else: MarkerNone
    if w.canMarkTowerPattern(r, kind, ruin) and behindMark == MarkerNone:
      w.doMarkTowerPattern(r, kind, ruin)
    for l in w.locationsWithinRadiusSquared(ruin, BuildTowerRadiusSquared * 4):
      if not r.spend(1): break
      if not w.canSenseLocation(r, l): continue
      let mark = w.getMarker(r.team, l)
      if mark == MarkerNone: continue
      let want = if mark == MarkerSecondary: secondaryPaint(r.team)
                 else: primaryPaint(r.team)
      if w.getPaint(l) == want: continue
      if w.canAttackRobot(r, l):
        w.doAttackRobot(r, l, mark == MarkerSecondary)
        break
    if w.canCompleteTowerPattern(r, kind, ruin, r):
      w.doCompleteTowerPattern(r, kind, ruin)

  ## The SRP lifecycle: mark, fill and complete a resource pattern centred on
  ## the soldier's own tile whenever it is a valid centre.
  block srp:
    if w.canCompleteResourcePattern(r, r.loc, r):
      w.doCompleteResourcePattern(r, r.loc)
    elif w.canMarkResourcePattern(r, r.loc) and
        w.getMarker(r.team, r.loc) == MarkerNone:
      w.doMarkResourcePattern(r, r.loc)
    else:
      for ddx in LoOffset .. HiOffset:
        for ddy in LoOffset .. HiOffset:
          if not r.spend(1): break
          let l = r.loc.translate(ddx, ddy)
          if not w.onTheMap(l): continue
          if not w.canSenseLocation(r, l): continue
          let mark = w.getMarker(r.team, l)
          if mark == MarkerNone: continue
          let want = if mark == MarkerSecondary: secondaryPaint(r.team)
                     else: primaryPaint(r.team)
          if w.getPaint(l) == want: continue
          if w.canAttackRobot(r, l):
            w.doAttackRobot(r, l, mark == MarkerSecondary)
            return

  when ScenarioWipe:
    let enemy = firstEnemy(w, r, UnitSpecs[utSoldier].actionRadiusSquared)
    if enemy.x >= 0 and w.canAttackRobot(r, enemy):
      w.doAttackRobot(r, enemy)
      return

  ## One robot in ten never paints and therefore starves at exactly 0 paint,
  ## losing 20 HP a turn until it dies — the `pnt=0` / falling `hp` record the
  ## parity job looks for.
  if r.id mod 10 == 3: return

  if not paintIsTeam(w.getPaint(r.loc), r.team) and
      w.canAttackRobot(r, r.loc):
    w.doAttackRobot(r, r.loc)
    return

  when ScenarioPaint:
    for l in w.locationsWithinRadiusSquared(
        r.loc, UnitSpecs[utSoldier].actionRadiusSquared):
      if not r.spend(1): break
      if not w.canSenseLocation(r, l): continue
      if not w.isPaintable(l): continue
      if paintIsTeam(w.getPaint(l), r.team): continue
      if hasPaintTeam(w.getPaint(l)): continue
      if w.canAttackRobot(r, l):
        w.doAttackRobot(r, l)
        return

  ## A SOLDIER WITH A RUIN TO WORK DOES NOT WANDER. It has to stay beside the
  ## pattern for the twenty-five turns it takes to paint it.
  if ruin.x < 0:
    let dir = Dir(w.currentRound mod 8)
    if w.canMove(r, dir):
      w.doMove(r, dir)

proc scenarioMopper(w: World, side: Side, r: Robot) =
  ## Swing in all four cardinals across four consecutive rounds, then mop the
  ## tile ahead. Every robot with id `mod 10 == 7` disintegrates at round 40,
  ## which is the free, no-range, no-cooldown path nothing else reaches.
  if w.currentRound == 40 and r.id mod 10 == 7:
    w.doDisintegrate(r)
    return
  let dir = CardinalDirs[w.currentRound mod 4]
  if w.canMopSwing(r, dir):
    w.doMopSwing(r, dir)
  else:
    let ahead = r.loc + dir
    if w.onTheMap(ahead) and w.canAttackRobot(r, ahead):
      w.doAttackRobot(r, ahead)
  if w.canMove(r, dir):
    w.doMove(r, dir)

proc scenarioSplasher(w: World, side: Side, r: Robot) =
  ## Splash the first tile in scan order that carries enemy paint or an enemy
  ## tower, so both the r2 <= 2 overpaint window and the 100-damage tower path
  ## fire.
  for l in w.locationsWithinRadiusSquared(
      r.loc, UnitSpecs[utSplasher].actionRadiusSquared):
    if not r.spend(1): break
    if not w.canSenseLocation(r, l): continue
    let bot = w.getRobot(l)
    let colour = w.getPaint(l)
    let interesting =
      (bot != nil and bot.kind.isTowerType() and bot.team != r.team) or
      (hasPaintTeam(colour) and teamFromPaint(colour) != r.team)
    if not interesting: continue
    if w.canAttackRobot(r, l):
      w.doAttackRobot(r, l)
      return
  let dir = Dir(w.currentRound mod 8)
  if w.canMove(r, dir):
    w.doMove(r, dir)

proc runScenario25*(w: World, side: Side, r: Robot) =
  case r.kind
  of utSoldier: scenarioSoldier(w, side, r)
  of utMopper: scenarioMopper(w, side, r)
  of utSplasher: scenarioSplasher(w, side, r)
  else: scenarioTower(w, side, r)
