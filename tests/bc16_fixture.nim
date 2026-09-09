## Shared bc16 test scaffolding: a synthetic 30x30 board with real rubble,
## real parts, real archons and a real den schedule, so a shard can assert one
## rule at a time without loading a 900-square converted map.
##
## NOT A TEST SHARD. `ci.yml` runs every `tests/*.nim`, so the `isMainModule`
## block below says what this file is rather than exiting silently and looking
## like an empty test.
##
## The layout is deliberately the engine's own. Two facts it exercises on
## every shard that touches it:
##
## * `initial_robots` are in FILE ORDER, because that order IS the opening
##   exec order in 2016 (`gameObjectsByID` is a `LinkedHashMap` and the map
##   file's rows are inserted first). They are NOT sorted by id — unlike 2022,
##   where the map file carried the ids;
## * ids come from the `IDGenerator`, whose 2016 block starts at **0** and
##   therefore mints ids from **1**, against the 10 000 floor every later year
##   uses. A shard that hard-codes an id is testing the generator, not the
##   rule, so every shard here looks robots up by location.

import battlecode/sheet
import battlecode/years/bc16/[maps, world, units, delays, health, economy,
                              signals, zombies, rules, knobs]
import battlecode/years/bc16/chassis/greenhorn as greenhorn16
import battlecode/years/bc16/chassis/bulwark as bulwark16

export sheet, maps, world, units, delays, health, economy, signals, zombies,
       rules, knobs, greenhorn16, bulwark16

const
  TestWidth* = 30
  TestHeight* = 30
  TestSeed* = 4242

proc flatSpec*(rubble: seq[tuple[l: Loc, amount: float64]] = @[],
               parts: seq[tuple[l: Loc, amount: float64]] = @[],
               robots: seq[tuple[x, y, kind, team: int]] = @[],
               dens: seq[DenSpec] = @[],
               schedule: seq[tuple[round: int, counts: array[4, int]]] = @[],
               symmetry = symRotational,
               rounds = 3000): MapSpec =
  ## A 30x30 board: rubble 0 everywhere unless asked for, and one archon a
  ## side well away from the middle unless the shard names its own.
  result.name = "testflat16"
  result.width = TestWidth
  result.height = TestHeight
  result.randomSeed = TestSeed
  result.rounds = rounds
  result.symmetry = symmetry
  result.symmetriesFound = @[symmetry]
  let size = TestWidth * TestHeight
  result.rubble = newSeq[float64](size)
  result.parts = newSeq[float64](size)
  for r in rubble: result.rubble[r.l.x + r.l.y * TestWidth] = r.amount
  for p in parts: result.parts[p.l.x + p.l.y * TestWidth] = p.amount
  if robots.len == 0:
    result.initialRobots = @[
      (x: 3, y: 15, kind: ord(rtArchon), team: ord(teamA)),
      (x: 26, y: 15, kind: ord(rtArchon), team: ord(teamB))]
  else:
    result.initialRobots = robots
  result.schedule = schedule
  result.dens = dens

proc bare*(rubble: seq[tuple[l: Loc, amount: float64]] = @[],
           parts: seq[tuple[l: Loc, amount: float64]] = @[],
           robots: seq[tuple[x, y, kind, team: int]] = @[],
           dens: seq[DenSpec] = @[],
           schedule: seq[tuple[round: int, counts: array[4, int]]] = @[],
           symmetry = symRotational,
           rounds = 3000,
           maxRounds = 3000): World =
  newWorld(flatSpec(rubble, parts, robots, dens, schedule, symmetry, rounds),
           maxRounds)

proc put*(w: World, kind: RobotType, l: Loc, t: Team,
          buildDelay = 0): Robot {.discardable.} =
  ## Spawn a robot directly, the way the engine's `spawnRobot` does, and make
  ## it ACTIVE (`roundsAlive >= buildDelay`) unless the shard asks otherwise.
  result = w.spawnRobot(kind, l, t, buildDelay)
  if buildDelay == 0: result.roundsAlive = 0

proc at*(w: World, x, y: int): Robot = w.getRobot(loc(x, y))

proc defaultSheets*(): array[2, Sheet] =
  [defaultSheet(YearBc16), defaultSheet(YearBc16)]

proc sheetsFrom*(a, b: string): array[2, Sheet] =
  ## Two doctrines from raw JSON payloads, through the SAME `sheet.validate`
  ## the LLM path uses -- so a test doctrine and a champion's doctrine are
  ## built by exactly the same code.
  [parseReply(a, YearBc16), parseReply(b, YearBc16)]

when isMainModule:
  echo "bc16_fixture: shared bc16 test scaffolding; not a test shard"
