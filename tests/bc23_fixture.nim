## Shared bc23 test scaffolding: a synthetic map with real wells, real islands
## and real headquarters, so a shard can assert one rule at a time without
## loading a 900-tile converted map.
##
## NOT A TEST SHARD. `ci.yml` runs every `tests/*.nim`, so the `isMainModule`
## block below says what this file is rather than exiting silently and looking
## like an empty test.
##
## The layout is deliberately the engine's own: the two starting bodies are
## `SpawnedBodyTable` rows listed id-DESCENDING, so `newWorld`'s ascending-id
## walk is exercised by every shard that reads `execOrder`, and the converter's
## own sort is not what the test is trusting.

import battlecode/sheet
import battlecode/years/bc23/[maps, world, currents, comms, rules, knobs]

export sheet, maps, world, currents, comms, rules, knobs

const
  TestWidth* = 30
  TestHeight* = 30

proc flatMap*(wells: seq[tuple[l: Loc, kind: int]] = @[],
              islands: seq[tuple[l: Loc, id: int]] = @[],
              walls: seq[Loc] = @[],
              clouds: seq[Loc] = @[],
              currents: seq[tuple[l: Loc, dir: int]] = @[],
              hqs: seq[tuple[id, x, y, team: int]] = @[]): MapSpec =
  ## A 30x30 board: no terrain unless asked for, and one headquarters a side
  ## well away from the middle unless the shard names its own.
  result.name = "testflat"
  result.width = TestWidth
  result.height = TestHeight
  result.randomSeed = 4242
  result.symmetry = symVertical
  result.rounds = 2000
  let size = TestWidth * TestHeight
  result.walls = newSeq[bool](size)
  result.clouds = newSeq[bool](size)
  result.currents = newSeq[int](size)
  result.islandIds = newSeq[int](size)
  result.resources = newSeq[int](size)
  for l in walls: result.walls[l.x + l.y * TestWidth] = true
  for l in clouds: result.clouds[l.x + l.y * TestWidth] = true
  for c in currents: result.currents[c.l.x + c.l.y * TestWidth] = c.dir
  for i in islands: result.islandIds[i.l.x + i.l.y * TestWidth] = i.id
  for wl in wells: result.resources[wl.l.x + wl.l.y * TestWidth] = wl.kind
  if hqs.len == 0:
    ## id-DESCENDING, exactly as a real map file writes them.
    result.initialBodies = @[
      (id: 3, x: 26, y: 15, team: 2, kind: 0),
      (id: 2, x: 3, y: 15, team: 1, kind: 0)]
  else:
    for h in hqs:
      result.initialBodies.add((id: h.id, x: h.x, y: h.y, team: h.team,
                                kind: 0))

proc bare*(rounds = 2000,
           wells: seq[tuple[l: Loc, kind: int]] = @[],
           islands: seq[tuple[l: Loc, id: int]] = @[],
           walls: seq[Loc] = @[],
           clouds: seq[Loc] = @[],
           currents: seq[tuple[l: Loc, dir: int]] = @[],
           hqs: seq[tuple[id, x, y, team: int]] = @[]): World =
  newWorld(flatMap(wells, islands, walls, clouds, currents, hqs), rounds)

proc place*(w: World, team: Team, kind: RobotType, at: Loc): Robot
    {.discardable.} =
  ## Spawn a specific robot at a specific tile with both cooldowns clear,
  ## bypassing the build rules the shards test separately.
  let r = w.spawnRobot(w.idGen.nextId(), kind, at, team)
  r.actionCooldown = 0
  r.movementCooldown = 0
  r

proc defaultSheets*(): array[2, Sheet] =
  [defaultSheet("bc23"), defaultSheet("bc23")]

proc sheetFrom*(json: string): Sheet = parseReply(json, "bc23")

proc mirror*(rounds = 2000, mapName = "Quiet",
             sheet = defaultSheet("bc23"),
             chassis = [ckLemonade, ckLemonade],
             sideAslot = 0): (World, GameOutcome23) =
  ## One real converted-map game, the shape every behavioural shard needs.
  playGame(loadMap(mapName), [sheet, sheet], chassis, 0, sideAslot, rounds, 0)

when isMainModule:
  echo "bc23_fixture: shared bc23 test scaffolding; not a test shard"
