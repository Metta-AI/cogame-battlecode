## Shared bc19 test scaffolding.
##
## NOT A TEST SHARD. `ci.yml` runs every `tests/*.nim`, so the `isMainModule`
## block below says what this file is rather than exiting silently and
## looking like an empty test.
##
## bc19's scaffolding is shaped differently from every other year's, and for
## a reason the design note names: **bc19 SHIPS NO MAP FILES UPSTREAM.**
## Every board is procedurally generated from its seed inside the engine
## constructor, so a synthetic `flatMap()` of the kind `bc22_fixture` and
## `bc23_fixture` build would be a board the engine could never produce — and
## the whole point of this year's maps is that the NAME IS THE RECIPE (V3).
## What the shards share instead is:
##
##   * `board()` / `mirror()` / `duel()` — real committed boards, played;
##   * `doctrine()` — one sheet from a JSON fragment, through the SAME
##     `validate` an LLM seat's reply goes through;
##   * `fixtureReplay()` — the committed `tests/fixtures/replay-bc19.json`,
##     found from whichever directory the runner started in.
##
## Synthetic boards do exist, but only where a shard is testing GEOMETRY
## rather than the map pool (`test_bc19_combat.nim`'s 9x9 blast probe builds
## its own), so they are not shared here.

import std/[json, os]
import battlecode/[replay, sheet, sim_types]
import battlecode/years/bc19/rules

export json, replay, sheet, sim_types, rules

proc doctrine*(fragment: string): Sheet =
  ## One bc19 sheet from a JSON fragment, through the real reply parser — so
  ## a shard's doctrine is validated, defaulted and clamped exactly as a
  ## champion's is.
  parseReply(fragment, "bc19")

proc doctrineOf*(node: JsonNode): Sheet = validate(node, YearBc19)

proc defaults*(): Sheet = defaultSheet(YearBc19)

proc board*(name = "seed-0043", rounds = MaxRounds): World =
  ## One committed board, unplayed: the shape a rule shard wants.
  newWorld(loadMap(name), rounds)

proc mirror*(name = "seed-0043", sheet = defaultSheet(YearBc19),
             chassis = [ck19Saber, ck19Saber], sideAslot = 0,
             rounds = MaxRounds): (World, GameOutcome19) =
  ## One real game with the SAME doctrine on both seats.
  let sheets: array[2, Sheet] = [sheet, sheet]
  playGame(loadMap(name), sheets, chassis, 0, sideAslot, rounds, 0)

proc duel*(name = "seed-0043",
           sheets: array[2, Sheet] = [defaultSheet(YearBc19),
                                      defaultSheet(YearBc19)],
           chassis = [ck19Saber, ck19Saber], sideAslot = 0,
           rounds = MaxRounds): (World, GameOutcome19) =
  ## One real game with two DIFFERENT doctrines — the shape the knob shard
  ## and the fixture both need.
  playGame(loadMap(name), sheets, chassis, 0, sideAslot, rounds, 0)

proc fixturePath*(): string =
  for candidate in ["tests/fixtures/replay-bc19.json",
                    "fixtures/replay-bc19.json",
                    "../tests/fixtures/replay-bc19.json"]:
    if fileExists(candidate): return candidate
  "tests/fixtures/replay-bc19.json"

proc pagePath*(): string =
  for candidate in ["client/replay_broadcast.html",
                    "../client/replay_broadcast.html"]:
    if fileExists(candidate): return candidate
  "client/replay_broadcast.html"

proc fixtureReplay*(): ReplayDoc = parseReplay(readFile(fixturePath()))

when isMainModule:
  echo "bc19_fixture: shared bc19 test scaffolding; not a test shard"
