## `splasher.nim` — `aim()`, and the floor that stops a splasher burning 50
## paint on one bare tile.
##
## The splasher aiming heuristic is behaviour-ported from
## `ecoArcGaming/battlecode25` `java/src/v3/` (AGPL-3.0, branch `newMopper`,
## head `8f17e87`, the Novice 2nd-place bot).
##
## A splash repaints EVERYTHING within r2 <= 4 of its centre and, inside
## r2 <= 2, paints over ENEMY PAINT — the only way a clan takes ground back at
## scale — and deals 100 to every enemy tower in the blast. `splash_targets`
## decides which of those two it is buying:
##
##   towers     maximise enemy-tower damage inside r2 <= 4
##   territory  maximise (enemy tiles inside r2 <= 2) + (bare tiles inside 4)
##   mixed      whichever scores higher this turn, with a 1.25x multiplier on
##              the tower term

import kit, econ, siege

export kit, econ, siege

const
  SplashFloorTiles* = 3
  SplashFloorTowers* = 1
    ## Never splash a centre whose score is below three tiles or one tower.

proc scoreCentre*(w: World, side: Side, r: Robot, centre: Loc,
                  towerTerm, territoryTerm: var int) =
  towerTerm = 0
  territoryTerm = 0
  for l in w.locationsWithinRadiusSquared(
      centre, SplasherAttackAoeRadiusSquared):
    let bot = w.getRobot(l)
    if bot != nil and bot.kind.isTowerType() and bot.team != side.team:
      towerTerm += 1
    if not w.isPaintable(l): continue
    let colour = w.getPaint(l)
    if colour == PaintNone:
      territoryTerm += 1
    elif not paintIsTeam(colour, side.team) and
        centre.isWithinDistanceSquared(l, SplasherAttackEnemyPaintRadiusSquared):
      territoryTerm += 2

proc aim*(w: World, side: Side, r: Robot): Loc =
  ## The best centre within the splasher's own r2 <= 4 action radius.
  result = loc(-1, -1)
  if not r.isActionReady(): return
  if r.paint < UnitSpecs[utSplasher].attackCost: return
  var best = low(int)
  for centre in w.locationsWithinRadiusSquared(
      r.loc, UnitSpecs[utSplasher].actionRadiusSquared):
    if not r.spend(3): break
    if not w.canAttackRobot(r, centre): continue
    var towerTerm, territoryTerm: int
    scoreCentre(w, side, r, centre, towerTerm, territoryTerm)
    let score =
      case side.doctrine.splashTargets
      of stTowers: towerTerm * 100
      of stTerritory: territoryTerm * 10
      of stMixed: max(towerTerm * 125, territoryTerm * 10)
    ## NEVER SPLASH OUR OWN LIVE RESOURCE PATTERN. A splash repaints its whole
    ## blast in ONE colour, and an SRP is a two-colour picture: one friendly
    ## splash inside it is 200 chips and fifty rounds in the bin.
    if overlapsProtected(side, centre, 4): continue
    if towerTerm == 0 and territoryTerm < SplashFloorTiles: continue
    if side.doctrine.splashTargets == stTowers and
        towerTerm < SplashFloorTowers: continue
    if score > best:
      best = score
      result = centre

proc runSplasher*(w: World, side: Side, r: Robot) =
  ## Refill first — a splasher at 0 paint is a 150-HP statue — then aim, then
  ## converge on the tower `siege.nim` names.
  if r.paint < UnitSpecs[utSplasher].attackCost or needsRefill(side, r):
    let towerLoc = nearestFriendlyTower(w, side, r, needPaint = true)
    if towerLoc.x >= 0:
      if r.loc.distanceSquaredTo(towerLoc) <= PaintTransferRadiusSquared:
        let want = min(UnitSpecs[r.kind].paintCapacity - r.paint,
                       w.getRobot(towerLoc).paint)
        if want > 0 and w.canTransferPaint(r, towerLoc, -want):
          w.doTransferPaint(r, towerLoc, -want)
          return
      else:
        w.stepToward(side, r, towerLoc)
        return

  let centre = aim(w, side, r)
  if centre.x >= 0:
    w.doAttackRobot(r, centre)
    return

  ## Nothing worth splashing here. Walk toward the tower we are trying to
  ## break, or the frontier when there is none in sight.
  let target = siegeTarget(w, side, r)
  if target.x >= 0 and side.doctrine.splashTargets != stTerritory:
    w.stepToward(side, r, target)
  else:
    w.stepToward(side, r, frontierFor(w, side))
