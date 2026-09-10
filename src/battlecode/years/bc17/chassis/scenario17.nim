## The Nim twin of the four scripted oracle bots -- `bc17scenario`,
## `bc17scenariotree`, `bc17scenariokill` and `bc17scenariotie` -- written
## line for line against `tools/oracle/bc17/bc17scenario*/RobotPlayer.java`
## and selected by `-d:bc17Scenario` (+`Tree`/`Kill`/`Tie`).
##
## **CI ONLY, AND NO RNG AT ALL.** Every branch is a function of the round
## number and the robot's type, so both sides can be compared BIT FOR BIT for
## a whole 2 999-round game (Tier A'). The bots exist to force every rare path
## EARLY rather than hoping a real game reaches it:
##
##   * `bc17scenario` -- hire and prove the ten-turn cooldown; plant and prove
##     the SHARED cooldown; water at 45 and at 48 HP (the wasted 3); build one
##     of each fighter and prove the 20-turn dormancy and the 4 %-a-turn heal;
##     move at exactly `strideRadius`, at half of it and at TWICE it (the
##     atan2 re-projection); walk a SCOUT onto a neutral tree and a SOLDIER
##     into one (refused); fire a single, a triad and a pentad at a known
##     angle and prove the centre-left-right spawn order; fire into a body at
##     the muzzle; fire at a tree; let a bullet leave through the east edge;
##     fire so a bullet hits our OWN side; `strike()` with an own gardener, an
##     own tree, an enemy soldier and a neutral tree inside distance 2;
##     `chop` a neutral tree to zero and prove the contained robot IS
##     released, then kill an identical tree with a BULLET and prove nothing
##     is; `shake` a tree with bullets and one without; `broadcast` on 0 and
##     9 999 and read them back; and `donate` a NON-MULTIPLE of the price,
##     proving the remainder is destroyed.
##   * `bc17scenariotree` -- the tree life cycle in isolation: the 81-round
##     growth with its exact health sequence and ZERO income, the first income
##     round, decay to death, and a tree killed by a TANK BODY ATTACK.
##   * `bc17scenariokill` -- soldiers walked onto the enemy's single archon on
##     `HouseDivided` until `DESTROYED` fires, proving the winner is set
##     MID-ROUND, the round still finishes, and the next `runRound` is DONE.
##   * `bc17scenariotie` -- mirrored sides scripted so the round-limit ladder
##     walks rung 1, rung 2, rung 3 (including the archon's -1) and rung 4.

import ../constants, ../units, ../geom, ../world, ../actions

export world

func eastward(): Dir = dirDeltas(1'f32, 0'f32)
func northward(): Dir = dirDeltas(0'f32, 1'f32)

proc scenarioArchon(w: World, r: Robot) =
  ## Hire on round 2 and again on round 3 (refused: the cooldown), then again
  ## on round 13 (allowed: it has expired).
  if w.currentRound in {2, 3, 13}:
    discard w.hireGardener(r, northward())
  if w.currentRound == 5:
    discard w.broadcast(r, 0, 1234)
    discard w.broadcast(r, broadcastMaxChannels - 1, 4321)
  if w.currentRound == 20:
    ## A non-multiple of the price: 100 bullets at 7.5833 buys 13 points and
    ## destroys the remainder.
    discard w.donate(r, 100'f32)
  if w.currentRound == 30:
    ## Move at exactly one stride, at half of it, and at TWICE it -- the
    ## third goes through the atan2 re-projection.
    discard w.move(r, eastward(), strideRadius(r.kind))
  elif w.currentRound == 31:
    discard w.move(r, eastward(), strideRadius(r.kind) / 2'f32)
  elif w.currentRound == 32:
    discard w.moveTo(r, addDist(r.loc, eastward(),
                                strideRadius(r.kind) * 2'f32))

proc scenarioGardener(w: World, r: Robot) =
  ## Plant on its first ready round, then try to BUILD on the next one (the
  ## shared cooldown refuses it), then build one of each fighter as the
  ## cooldown comes up.
  if r.isBuildReady():
    if r.roundsAlive == 1:
      discard w.plantTree(r, eastward())
    elif r.roundsAlive == 2:
      discard w.buildRobot(r, rtSoldier, northward())
    elif r.roundsAlive == 12:
      discard w.buildRobot(r, rtSoldier, northward())
    elif r.roundsAlive == 23:
      discard w.buildRobot(r, rtLumberjack, northward())
    elif r.roundsAlive == 34:
      discard w.buildRobot(r, rtTank, northward())
    elif r.roundsAlive == 45:
      discard w.buildRobot(r, rtScout, northward())
  ## Water once the tree has decayed to 45 and again at 48, so the clamp's
  ## wasted 3 is on the trace.
  if r.waterCount == 0:
    for id in w.senseNearbyTrees(r, bodyRadius(r.kind) + bulletTreeRadius +
                                   interactionDistFromEdge, ord(r.team)):
      let tr = w.trees.getOrDefault(id)
      if tr == nil: continue
      if tr.health >= 45'f32 and tr.health <= 48'f32:
        discard w.water(r, id)
        break

proc scenarioFighter(w: World, r: Robot) =
  ## A SOLDIER fires a single, then a triad, then a pentad, all due east; a
  ## TANK walks east into whatever is there (the body attack); a SCOUT walks
  ## onto a tree; a LUMBERJACK strikes and then chops.
  case r.kind
  of rtSoldier:
    case r.roundsAlive mod 12
    of 1: discard w.fireShot(r, ssSingle, eastward())
    of 4: discard w.fireShot(r, ssTriad, eastward())
    of 7: discard w.fireShot(r, ssPentad, eastward())
    else: discard w.move(r, eastward())
  of rtTank:
    discard w.move(r, eastward())
  of rtScout:
    discard w.move(r, eastward())
  of rtLumberjack:
    if (r.roundsAlive mod 6) == 1:
      discard w.strike(r)
    else:
      var chopped = false
      for id in w.senseNearbyTrees(r, bodyRadius(r.kind) +
                                     neutralTreeMaxRadius +
                                     interactionDistFromEdge):
        let tr = w.trees.getOrDefault(id)
        if tr == nil or tr.team == r.team: continue
        if r.canInteractWithTree(tr):
          chopped = w.chop(r, id)
          break
      if not chopped:
        discard w.move(r, eastward())
  else: discard
  ## Shake anything in reach, so the bullet jump is on the trace.
  if r.shakeCount == 0:
    for id in w.senseNearbyTrees(r, bodyRadius(r.kind) +
                                   neutralTreeMaxRadius +
                                   interactionDistFromEdge, ord(tNeutral)):
      let tr = w.trees.getOrDefault(id)
      if tr == nil: continue
      if r.canInteractWithTree(tr):
        discard w.shake(r, id)
        break

proc runScenario17*(w: World, r: Robot) =
  when defined(bc17ScenarioTree):
    ## The tree life cycle alone: hire, plant, and then a tank walked into
    ## the tree once it is grown.
    case r.kind
    of rtArchon:
      if w.currentRound == 2: discard w.hireGardener(r, northward())
    of rtGardener:
      if r.isBuildReady():
        if r.roundsAlive == 1: discard w.plantTree(r, eastward())
        elif r.roundsAlive == 120: discard w.buildRobot(r, rtTank, eastward())
    of rtTank:
      discard w.move(r, dirDeltas(-1'f32, 0'f32))
    else: discard
  elif defined(bc17ScenarioKill):
    ## Soldiers walked at the enemy archon until DESTROYED fires.
    case r.kind
    of rtArchon:
      if w.currentRound in {2, 13, 24}:
        discard w.hireGardener(r, northward())
    of rtGardener:
      if r.isBuildReady() and (r.roundsAlive mod 11) == 1:
        discard w.buildRobot(r, rtSoldier, eastward())
    of rtSoldier:
      let enemies = w.senseNearbyRobots(r, -1'f32, ord(r.team.opponent()))
      if enemies.len > 0:
        let target = w.robots.getOrDefault(enemies[0])
        if target != nil:
          if w.canFireShot(r, ssSingle):
            discard w.fireShot(r, ssSingle, directionTo(r.loc, target.loc))
          discard w.moveTo(r, target.loc)
      else:
        discard w.move(r, eastward())
    else: discard
  elif defined(bc17ScenarioTie):
    ## Mirrored sides that plant, hold and donate exactly enough to walk one
    ## rung of the ladder per seed.
    case r.kind
    of rtArchon:
      if w.currentRound == 2: discard w.hireGardener(r, northward())
      if w.currentRound == 40 and r.team == tA:
        discard w.donate(r, 8'f32)     ## a single point: rung 1
    of rtGardener:
      if r.isBuildReady() and r.roundsAlive == 1:
        discard w.plantTree(r, eastward())
    else: discard
  else:
    case r.kind
    of rtArchon: w.scenarioArchon(r)
    of rtGardener: w.scenarioGardener(r)
    else: w.scenarioFighter(r)
