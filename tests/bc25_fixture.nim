## Shared bc25 test scaffolding: a synthetic map with real ruins, real
## starting towers and no walls, so a shard can assert one rule at a time
## without loading a 900-tile converted map.
##
## NOT A TEST SHARD. `ci.yml` runs every `tests/*.nim`, so the `isMainModule`
## block below says what this file is rather than exiting silently and looking
## like an empty test.
##
## The layout is deliberately the engine's own: the four starting bodies are
## `InitialBodyTable` rows in FILE order (which every real `.map25` writes in
## DESCENDING id order), so `newWorld`'s ascending-id sort is exercised by
## every shard that reads `execOrder`.

import battlecode/sheet
import battlecode/years/bc25/[maps, world, towers, comms, rules, knobs]

export sheet, maps, world, towers, comms, rules, knobs

const
  TestWidth* = 30
  TestHeight* = 30

proc flatMap*(ruins: seq[Loc] = @[], walls: seq[Loc] = @[]): MapSpec =
  ## A 30x30 board: no walls unless asked for, four starting towers well away
  ## from the middle, and whatever extra ruins the shard needs.
  ##
  ## The four bodies are listed id-DESCENDING, exactly as the real map files
  ## do, so a shard that reads `execOrder` sees the engine's own ascending-id
  ## order and would catch a port that trusted file order.
  result.name = "testflat"
  result.width = TestWidth
  result.height = TestHeight
  result.randomSeed = 4242
  result.symmetry = symVertical
  result.walls = newSeq[bool](TestWidth * TestHeight)
  for l in walls:
    result.walls[l.x + l.y * TestWidth] = true
  for l in ruins:
    result.ruins.add(l)
  result.initialBodies = @[
    (id: 4, x: 26, y: 26, team: 2, kind: 2),   ## B money
    (id: 3, x: 26, y: 3, team: 2, kind: 1),    ## B paint
    (id: 2, x: 3, y: 26, team: 1, kind: 2),    ## A money
    (id: 1, x: 3, y: 3, team: 1, kind: 1)]     ## A paint

proc bare*(rounds = 2000, ruins: seq[Loc] = @[],
           walls: seq[Loc] = @[]): World =
  newWorld(flatMap(ruins, walls), rounds)

proc place*(w: World, team: Team, kind: UnitType, at: Loc): Robot
    {.discardable.} =
  ## Spawn a specific unit at a specific tile with both cooldowns clear,
  ## bypassing the build rules the shards test separately.
  let r = w.spawnRobot(kind, at, team)
  if kind.isTowerType():
    w.towersByLoc[w.idx(at)] = int8(ord(team) + 1)
  r.actionCooldown = 0
  r.movementCooldown = 0
  r

proc paintArea*(w: World, kind: PatternKind, team: Team, centre: Loc,
                skipCentre = false) =
  ## Paint the exact 5x5 a pattern wants, straight into the colour array
  ## through `setPaint` so the live count stays honest.
  for ddx in LoOffset .. HiOffset:
    for ddy in LoOffset .. HiOffset:
      if skipCentre and ddx == 0 and ddy == 0: continue
      w.setPaint(centre.translate(ddx, ddy), wantedPaint(kind, ddx, ddy, team))

proc defaultSheets*(): array[2, Sheet] =
  [defaultSheet("bc25"), defaultSheet("bc25")]

proc sheetFrom*(json: string): Sheet = parseReply(json, "bc25")

when isMainModule:
  echo "bc25_fixture: shared bc25 test scaffolding; not a test shard"
