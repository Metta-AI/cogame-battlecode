## Shared bc24 test scaffolding: a synthetic map with real spawn zones, real
## flags and a real territory split, so a shard can assert one rule at a time
## without loading a 900-tile converted map.
##
## NOT A TEST SHARD. `ci.yml` runs every `tests/*.nim`, so the `isMainModule`
## block below says what this file is rather than exiting silently and looking
## like an empty test.
##
## The layout is deliberately the engine's own: six spawn-zone centres in
## `spawnLocations` order (A, B, A, B, A, B), the same six re-derived into
## `spawnCenters` in ASCENDING TILE-INDEX order with A in the even slots, a dam
## column down the middle so `floodFillTeam` gives each side a real territory,
## and flags created at the centres with `flag.id = tile index`.

import battlecode/years/bc24/[maps, world, traps, skills]

export maps, world, traps, skills

const
  TestWidth* = 30
  TestHeight* = 30
  DamColumn* = 15

proc flatMap*(withDam = true): MapSpec =
  ## A 30x30 board: no walls, no water, no crumbs, a one-tile dam column at
  ## x = 15 when `withDam`, and three 3x3 spawn zones a side down the left and
  ## right edges. The three own centres are pairwise 11 or 23 apart, so the
  ## six-tile confirmation rule passes unless a test moves a flag.
  result.name = "testflat"
  result.width = TestWidth
  result.height = TestHeight
  result.randomSeed = 4242
  result.symmetry = symVertical
  result.walls = newSeq[bool](TestWidth * TestHeight)
  result.water = newSeq[bool](TestWidth * TestHeight)
  result.dam = newSeq[bool](TestWidth * TestHeight)
  if withDam:
    for y in 0 ..< TestHeight:
      result.dam[DamColumn + y * TestWidth] = true
  let centres = [loc(3, 3), loc(26, 3), loc(3, 15), loc(26, 15),
                 loc(3, 26), loc(26, 26)]
  for i in 0 .. 5:
    result.spawnLocations[i] = centres[i]
  ## `LiveMap.getSpawnZoneCenters` scans tile indices ASCENDING and interleaves
  ## A into the even slots; for this layout that is the same six in the same
  ## order, which the shards cross-check.
  result.spawnCenters = [loc(3, 3), loc(26, 3), loc(3, 15), loc(26, 15),
                         loc(3, 26), loc(26, 26)]

proc bare*(rounds = 2000, withDam = true): World =
  newWorld(flatMap(withDam), rounds)

proc postSetup*(w: World) =
  ## Put the world past the dam without playing two hundred rounds.
  w.currentRound = SetupRounds + 1

proc placeDuck*(w: World, team: Team, at: Loc, index = -1): Robot =
  ## Spawn a specific duck at a specific tile, bypassing the spawn-zone rule
  ## the shards test separately.
  var pick: Robot = nil
  var seen = 0
  for r in w.robots:
    if r.team != team or r.spawned: continue
    if index < 0 or seen == index:
      pick = r
      break
    seen += 1
  doAssert pick != nil, "no unspawned duck left for the fixture"
  w.occupant[w.idx(at)] = pick
  pick.spawned = true
  pick.everSpawned = true
  pick.loc = at
  pick.health = DefaultHealth
  pick.actionCooldown = 0
  pick.movementCooldown = 0
  pick.spawnCooldown = 0
  pick

proc layTrap*(w: World, team: Team, kind: TrapKind, at: Loc) =
  ## Put `team`'s trap on `at` without leaving a duck standing beside it: a
  ## builder has to be inside `r^2 <= 2` of the tile, and a duck left there
  ## would block the very move the trigger tests are about.
  w.addCrumbs(team, trapCostFor(kind, 0))
  var spot = loc(-1, -1)
  for dir in MoveDirs:
    let l = at + dir
    if not w.onTheMap(l): continue
    if not w.isPassable(l): continue
    if w.getRobot(l) != nil: continue
    spot = l
    break
  doAssert spot.x >= 0, "nowhere to stand while laying the fixture trap"
  let b = w.placeDuck(team, spot)
  w.buildTrap(b, kind, at)
  doAssert w.hasTrap(at), "the fixture trap was refused"
  w.despawnRobot(b)

proc ownFlags*(w: World, team: Team): seq[Flag] =
  for f in w.allFlags:
    if f.team == team: result.add(f)

when isMainModule:
  echo "bc24_fixture: shared bc24 test scaffolding; not a test shard"
