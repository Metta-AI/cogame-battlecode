## The landscaper: three modes, in priority order.
##
##  (a) WALL, from round `wall_hq_round`: claim one of the 8 tiles adjacent to
##      the own HQ, stand ON it, and raise it under yourself to
##      `waterLevel(round + 400) + 2` by digging from a tile OUTSIDE the ring.
##      An HQ is a building, so dirt dropped on it BURIES it — the HQ's own
##      tile can never be raised. The only way an HQ survives the flood is a
##      ring of eight tiles the water can never cross, which is exactly what
##      this mode builds. When every ring tile clears the bar the side emits
##      `wall_closed` and the landscaper drops to (b).
##  (b) TERRAFORM, from `terraform_start_round`: raise the lowest lattice tile
##      inside `lattice_radius` that is below `waterLevel(round + 250) + 1`,
##      keeping Bowl of Chowder's checkerboard parity so units can still path.
##  (c) ATTACK: a landscaper delivered next to an enemy building digs its wall
##      down and then buries it. 50 dirt kills an HQ; a landscaper carries 25.
##
## Any landscaper on a tile that floods next round MOVES FIRST and digs second.
##
## Behaviour, not code, from `StoneT2000/Battlecode2020` (AGPL-3.0; see NOTICE).

import kit, pathing, signals, lattice

const
  ModeWall = 0
  ModeTerraform = 1
  ModeAttack = 2

proc wallTileNeedsWork*(w: World, side: Side, l: Loc): bool =
  let occupant = w.getRobot(l)
  if occupant != nil and occupant.kind.isBuilding(): return false
  w.getDirt(l) < w.wallTarget(side)

proc wallComplete*(w: World, side: Side): bool =
  if not side.hasHq: return false
  for l in w.ringTiles(side.hqLoc):
    if w.wallTileNeedsWork(side, l): return false
  true

proc minRingElevation*(w: World, side: Side): int =
  if not side.hasHq: return 0
  result = high(int)
  for l in w.ringTiles(side.hqLoc):
    result = min(result, w.getDirt(l))
  if result == high(int): result = 0

proc claimWallTile(w: World, side: Side, r: Robot): (bool, Loc) =
  ## The ring tile this landscaper works on. A tile it is ALREADY STANDING ON
  ## or standing NEXT TO wins outright, because a landscaper that has raised
  ## its own tile to the bar is usually eight elevation steps above everything
  ## around it and can no longer walk anywhere — but it is still adjacent to
  ## the two neighbouring ring tiles, and it can deposit onto them from where
  ## it stands. Preferring the globally lowest tile instead is what left three
  ## ring tiles at elevation 3 while one landscaper piled 235 dirt onto its own.
  if not side.hasHq: return (false, loc(0, 0))
  var best = loc(0, 0)
  var bestScore = high(int)
  var found = false
  for l in w.ringTiles(side.hqLoc):
    if not r.spend(1): break
    if not w.wallTileNeedsWork(side, l): continue
    ## A ring tile with a UNIT standing on it is still claimable: dirt dropped
    ## on a non-building goes onto the GROUND, so a miner in the way does not
    ## stop the wall going up under it. Only a building blocks, and
    ## `wallTileNeedsWork` has already excluded those.
    let reach =
      if r.loc == l: 0
      elif r.loc.isAdjacentTo(l): 1
      else: 2
    let score = reach * 1_000_000 + w.getDirt(l) * 64 +
      r.loc.distanceSquaredTo(l)
    if score < bestScore:
      bestScore = score
      best = l
      found = true
  (found, best)

proc depositToward(w: World, r: Robot, target: Loc): bool =
  let d = fromDelta(target.x - r.loc.x, target.y - r.loc.y)
  if not w.canDepositDirt(r, d): return false
  w.depositDirt(r, d)
  true

proc digFrom(w: World, side: Side, r: Robot, protect: openArray[Loc]): bool =
  let d = w.digSourceFor(side, r, protect)
  if d == dCenter: return false
  if not w.canDigDirt(r, d): return false
  w.digDirt(r, d)
  true

proc runWallMode(w: World, side: Side, r: Robot): bool =
  let (haveTile, tile) = w.claimWallTile(side, r)
  if not haveTile: return false
  if r.loc == tile:
    if r.dirtCarrying > 0 and w.wallTileNeedsWork(side, tile):
      return w.depositToward(r, r.loc)
    var protect = w.ringTiles(side.hqLoc)
    protect.add(side.hqLoc)
    return w.digFrom(side, r, protect)
  if r.loc.isAdjacentTo(tile):
    ## Standing next to an unclaimed ring tile: raise it from here — this is
    ## also how a FLOODED ring tile is resurfaced, since `addDirt` runs
    ## `tryResurface` the moment the elevation clears the water.
    if r.dirtCarrying > 0:
      if w.depositToward(r, tile): return true
    var protect = w.ringTiles(side.hqLoc)
    protect.add(side.hqLoc)
    if w.digFrom(side, r, protect): return true
    ## Nothing to dig here — step on if we can.
    return w.stepToward(side, r, tile)
  w.stepToward(side, r, tile)

proc runTerraformMode(w: World, side: Side, r: Robot): bool =
  let (haveTile, tile) = w.lowestLatticeTileNear(side, r)
  if not haveTile:
    if side.hasHq and chebyshev(r.loc, side.hqLoc) > side.doctrine.latticeRadius:
      return w.stepToward(side, r, side.hqLoc)
    return false
  if r.loc.isAdjacentTo(tile) or r.loc == tile:
    if r.dirtCarrying > 0:
      if w.depositToward(r, tile): return true
    var protect = w.ringTiles(side.hqLoc)
    protect.add(side.hqLoc)
    protect.add(tile)
    return w.digFrom(side, r, protect)
  w.stepToward(side, r, tile)

proc adjacentEnemyBuilding(w: World, side: Side, r: Robot): (bool, Loc) =
  for d in MoveDirs:
    if not r.spend(1): break
    let l = r.loc + d
    let occupant = w.getRobot(l)
    if occupant == nil: continue
    if occupant.team == side.team or occupant.team == teamNeutral: continue
    if not occupant.kind.isBuilding(): continue
    return (true, l)
  (false, loc(0, 0))

proc runAttackMode(w: World, side: Side, r: Robot): bool =
  let (haveTarget, target) = w.adjacentEnemyBuilding(side, r)
  if haveTarget:
    if r.dirtCarrying > 0:
      return w.depositToward(r, target)
    ## Nothing carried: take dirt from the ground beside the enemy wall.
    return w.digFrom(side, r, [target])
  if not side.hasEnemyHq: return false
  ## The enemy HQ's own ring is walled: dig it back down on the way in.
  if chebyshev(r.loc, side.enemyHqLoc) <= 2 and r.dirtCarrying <
      RobotSpecs[rtLandscaper].dirtLimit:
    if w.digFrom(side, r, [side.enemyHqLoc]): return true
  w.stepToward(side, r, side.enemyHqLoc)

proc chooseMode(w: World, side: Side, r: Robot, brain: Brain): int =
  let d = side.doctrine
  if brain.mode == ModeAttack: return ModeAttack
  let rushing =
    d.rushTrigger > 0 and w.currentRound >= d.rushTrigger and side.hasEnemyHq
  if rushing:
    ## With `opening = rush` half the roster commits; with any other opening
    ## the knob sends a SINGLE harassing landscaper (§Decisions).
    let commit =
      if d.opening == opRush: (r.id and 1) == 0
      else: side.rushUnits == 0
    if commit:
      side.rushUnits += 1
      if not side.rushLaunched:
        side.rushLaunched = true
        w.emit("rush_launched", ord(side.team), side.rushUnits, w.currentRound)
      return ModeAttack
  if d.wallHqRound > 0 and w.currentRound >= w.effectiveWallRound(side) and
      not w.wallComplete(side):
    return ModeWall
  if w.currentRound >= d.terraformStartRound:
    return ModeTerraform
  if d.wallHqRound > 0 and not w.wallComplete(side):
    return ModeWall
  ModeTerraform

proc runLandscaper*(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)
  brain.turnCount += 1
  w.readBlocks(side, r)
  w.noteEnemyHq(side)
  if w.fleeWater(side, r): return
  if r.dead: return
  if not isReady(r): return

  let mode = w.chooseMode(side, r, brain)
  brain.mode = mode
  var acted = false
  case mode
  of ModeAttack: acted = w.runAttackMode(side, r)
  of ModeWall: acted = w.runWallMode(side, r)
  else: acted = w.runTerraformMode(side, r)
  if r.dead: return

  ## The wall is a team fact, so it is announced once, by whoever closes it.
  if not side.wallClosed and side.doctrine.wallHqRound > 0 and
      w.wallComplete(side):
    side.wallClosed = true
    side.wallClosedRound = w.currentRound
    w.emit("wall_closed", ord(side.team), w.minRingElevation(side),
      w.currentRound)
    w.broadcast(side, r, SigWallClosed, w.minRingElevation(side))

  if not acted and isReady(r) and mode != ModeAttack:
    ## An idle landscaper tops up the tile it stands on — but ONLY up to the
    ## bar. Without the cap a landscaper that had finished its wall tile and
    ## could no longer walk anywhere (it is eight steps above its neighbours)
    ## dug and dropped for the rest of the match and built a 235-high spike.
    let cap = max(w.wallTarget(side), side.latticeTarget(w.currentRound))
    if r.dirtCarrying > 0 and w.getDirt(r.loc) < cap:
      discard w.depositToward(r, r.loc)
    elif r.dirtCarrying < RobotSpecs[rtLandscaper].dirtLimit and
        w.getDirt(r.loc) < cap:
      var protect = w.ringTiles(side.hqLoc)
      protect.add(side.hqLoc)
      discard w.digFrom(side, r, protect)
