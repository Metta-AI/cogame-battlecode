## Shared bc22 test scaffolding: a synthetic map with real rubble, real lead
## and real archons, so a shard can assert one rule at a time without loading a
## 900-square converted map.
##
## NOT A TEST SHARD. `ci.yml` runs every `tests/*.nim`, so the `isMainModule`
## block below says what this file is rather than exiting silently and looking
## like an empty test.
##
## The layout is deliberately the engine's own: the two starting bodies are
## `SpawnedBodyTable` rows listed id-DESCENDING, so `newWorld`'s reliance on the
## converter's ascending-id sort is exercised by every shard that reads
## `execOrder`, and the sort is not what the test is trusting. The ids are
## BELOW the 10 000 `IDGenerator` floor, exactly as every official `.map22`
## carries them.

import battlecode/sheet
import battlecode/years/bc22/[maps, world, buildings, economy, anomaly, rules,
                              knobs]

export sheet, maps, world, buildings, economy, anomaly, rules, knobs

const
  TestWidth* = 30
  TestHeight* = 30

proc flatMap*(rubble: seq[tuple[l: Loc, amount: int]] = @[],
              lead: seq[tuple[l: Loc, amount: int]] = @[],
              anomalies: seq[tuple[round: int, kind: AnomalyKind]] = @[],
              archons: seq[tuple[id, x, y, team: int]] = @[],
              symmetry = symVertical): MapSpec =
  ## A 30x30 board: rubble 0 everywhere unless asked for, and one archon a side
  ## well away from the middle unless the shard names its own.
  result.name = "testflat"
  result.width = TestWidth
  result.height = TestHeight
  result.randomSeed = 4242
  result.symmetry = symmetry
  result.rounds = 2000
  let size = TestWidth * TestHeight
  result.rubble = newSeq[int](size)
  result.lead = newSeq[int](size)
  for r in rubble: result.rubble[r.l.x + r.l.y * TestWidth] = r.amount
  for l in lead: result.lead[l.l.x + l.l.y * TestWidth] = l.amount
  result.anomalies = anomalies
  if archons.len == 0:
    ## id-DESCENDING, exactly as a real map file writes them.
    result.initialBodies = @[
      (id: 3, x: 26, y: 15, team: 2, kind: 4),
      (id: 2, x: 3, y: 15, team: 1, kind: 4)]
  else:
    for a in archons:
      result.initialBodies.add((id: a.id, x: a.x, y: a.y, team: a.team,
                                kind: 4))

proc bare*(rounds = 2000,
           rubble: seq[tuple[l: Loc, amount: int]] = @[],
           lead: seq[tuple[l: Loc, amount: int]] = @[],
           anomalies: seq[tuple[round: int, kind: AnomalyKind]] = @[],
           archons: seq[tuple[id, x, y, team: int]] = @[],
           symmetry = symVertical): World =
  result = newWorld(flatMap(rubble, lead, anomalies, archons, symmetry),
                    rounds)
  result.loadTransmuteTable()

proc place*(w: World, team: Team, kind: RobotType, at: Loc): Robot
    {.discardable.} =
  ## Spawn a specific robot at a specific square with both cooldowns clear,
  ## bypassing the build rules the shards test separately. A BUILDING spawned
  ## this way is still a PROTOTYPE, because that is what the engine does.
  let r = w.spawnRobot(w.idGen.nextId(), kind, at, team)
  r.actionCooldown = 0
  r.movementCooldown = 0
  r

proc placeLive*(w: World, team: Team, kind: RobotType, at: Loc): Robot
    {.discardable.} =
  ## The same, but a building comes up as a TURRET at full health — for the
  ## shards that are testing what a FINISHED building does rather than how it
  ## gets finished.
  let r = w.place(team, kind, at)
  if r.mode == rmPrototype:
    r.mode = rmTurret
    r.health = maxHealthOf(kind, 1)
  r

proc defaultSheets*(): array[2, Sheet] =
  [defaultSheet("bc22"), defaultSheet("bc22")]

proc sheetFrom*(json: string): Sheet = parseReply(json, "bc22")

proc mirror*(rounds = 2000, mapName = "chalice",
             sheet = defaultSheet("bc22"),
             chassis = [ckWololo, ckWololo],
             sideAslot = 0): (World, GameOutcome22) =
  ## One real converted-map game, the shape every behavioural shard needs.
  playGame(loadMap(mapName), [sheet, sheet], chassis, 0, sideAslot, rounds, 0)

proc duel*(rounds = 2000, mapName = "chalice",
           sheets: array[2, Sheet] = [defaultSheet("bc22"),
                                      defaultSheet("bc22")],
           chassis = [ckWololo, ckWololo],
           sideAslot = 0): (World, GameOutcome22) =
  playGame(loadMap(mapName), sheets, chassis, 0, sideAslot, rounds, 0)

when isMainModule:
  echo "bc22_fixture: shared bc22 test scaffolding; not a test shard"
