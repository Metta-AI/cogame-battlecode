## Shared bc17 test scaffolding.
##
## NOT A TEST SHARD. `ci.yml` runs every `tests/*.nim`, so the `isMainModule`
## block below says what this file is rather than exiting silently and
## looking like an empty test.
##
## What the bc17 shards share:
##
##   * `board()` / `mirror()` / `duel()` -- real committed boards, played;
##   * `doctrine()` -- one sheet from a JSON fragment, through the SAME
##     `validate` an LLM seat's reply goes through;
##   * `fixtureReplay()` -- the committed `tests/fixtures/replay-bc17.json`,
##     found from whichever directory the runner started in;
##   * `bits()` -- the raw IEEE-754 bits of a float32, because **every float
##     assertion in this year is made on bits and never on a decimal**: a
##     float32 needs nine significant digits to round-trip and a formatter
##     mismatch would masquerade as a divergence (docs/RULES-BC17.md F3).
##
## **THE ONE CONVENTION EVERY SHARD OBEYS:** never zero
## `perGameBudgetSeconds` in a helper. `match.nim`'s
## `perGame = max(1, min(field, remaining))` clamps it one level up, so a
## zeroed field buys a ONE-SECOND budget while `rules.nim` treats 0 as
## unbounded -- the symptom is a shard that passes in `-d:release` and fails
## in debug. `playGame` here is always called with an explicit 0, which IS
## unbounded at that level.

import std/[json, os, strutils]
import battlecode/[replay, rng, sheet, sim_types]
import battlecode/years/bc17/rules

export json, replay, rng, sheet, sim_types, rules

const FixtureRounds* = 900
  ## What `tools/gen_bc17_fixture_replay.nim` recorded with.

proc doctrine*(fragment: string): Sheet =
  ## One bc17 sheet from a JSON fragment, through the real reply parser -- so
  ## a shard's doctrine is validated, defaulted and clamped exactly as a
  ## champion's is.
  parseReply(fragment, "bc17")

proc doctrineOf*(node: JsonNode): Sheet = validate(node, YearBc17)

proc defaults*(): Sheet = defaultSheet(YearBc17)

func bits*(v: float32): uint32 = cast[uint32](v)
  ## The raw IEEE-754 bit pattern, for a width assertion that cannot be
  ## fooled by a formatter.

func f32of*(hex: string): float32 =
  cast[float32](uint32(parseHexInt(hex)))

proc board*(name = "HouseDivided", rounds = gameDefaultRounds): World =
  ## One committed board, unplayed: the shape a rule shard wants.
  newWorld(loadMap(name), rounds)

proc mirror*(name = "HouseDivided", sheet = defaultSheet(YearBc17),
             chassis = [ck17Orchard, ck17Orchard], sideAslot = 0,
             rounds = gameDefaultRounds): (World, GameOutcome17) =
  ## One real game with the SAME doctrine on both seats.
  let sheets: array[2, Sheet] = [sheet, sheet]
  playGame(loadMap(name), sheets, chassis, 0, sideAslot, rounds, 0)

proc duel*(name = "HouseDivided",
           sheets: array[2, Sheet] = [defaultSheet(YearBc17),
                                      defaultSheet(YearBc17)],
           chassis = [ck17Orchard, ck17Orchard], sideAslot = 0,
           rounds = gameDefaultRounds): (World, GameOutcome17) =
  ## One real game with two DIFFERENT doctrines -- the shape the knob shard
  ## and the fixture both need.
  playGame(loadMap(name), sheets, chassis, 0, sideAslot, rounds, 0)

proc fixturePath*(): string =
  for candidate in ["tests/fixtures/replay-bc17.json",
                    "fixtures/replay-bc17.json",
                    "../tests/fixtures/replay-bc17.json"]:
    if fileExists(candidate): return candidate
  "tests/fixtures/replay-bc17.json"

proc pagePath*(): string =
  for candidate in ["client/replay_broadcast.html",
                    "../client/replay_broadcast.html"]:
    if fileExists(candidate): return candidate
  "client/replay_broadcast.html"

proc fixtureReplay*(): ReplayDoc = parseReplay(readFile(fixturePath()))

proc vectorsPath*(): string =
  for candidate in ["data/bc17/fdlibm_vectors.json",
                    "../data/bc17/fdlibm_vectors.json",
                    "/data/bc17/fdlibm_vectors.json"]:
    if fileExists(candidate): return candidate
  "data/bc17/fdlibm_vectors.json"

when isMainModule:
  echo "bc17_fixture: shared bc17 test scaffolding; not a test shard"
