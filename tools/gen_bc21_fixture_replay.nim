## Records `tests/fixtures/replay-bc21.json`, the committed bc21 fixture
## replay (design note §Tests item 17).
##
##   nim r --path:src tools/gen_bc21_fixture_replay.nim [out.json]
##
## It is a real recording, not a hand-written document: one scripted
## `california-roll` vs `examplefuncsplayer21` game on `maptestsmall`, seed 3,
## capped at 120 rounds, written by the same `ReplayDoc.toJson` the server
## writes. Nothing about it is random — the world RNG comes from the map's own
## `randomSeed` — so re-running this produces the same bytes.
##
## The fixture exists so that the emitted wasm module can be driven against
## COMMITTED bytes (`tools/wasm_replay_smoke.cjs`) rather than only against
## the replay `docker-smoke` produced in the same run, and so that
## `tests/test_bc21_replay.nim` can prove a recording made at one
## `GameVersion` still re-derives. A rule change therefore turns that test
## red: re-record with this program, in the same commit that bumps the
## version.

import std/[json, os]
import battlecode/[baselines, match, replay, results, sheet, sim_types]
import battlecode/years/dispatch

const
  Chassis = [scCaliforniaRoll, scExamplefuncsplayer21]
  DefaultOut = "tests/fixtures/replay-bc21.json"
  Map = "maptestsmall"
  Seed = 3
  Rounds = 150

proc main() =
  var config = defaultGameConfig()
  config.year = "bc21"
  config.pool = "small"
  config.gamesPerMatch = 1
  config.maxRounds = Rounds
  let doctrines = [baselineSheet("bc21", blCaliforniaRoll),
                   baselineSheet("bc21", blExamplefuncsplayer21)]
  var plan = buildPlan(config, doctrines, Seed)
  plan.chassis = Chassis
  plan.maps = @[Map]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[-1]

  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  if games.len != 1:
    quit("the fixture game did not finish: reason " & $reason)

  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: doctrines[slot],
      chassis: (if slot == 0: "california-roll" else: "examplefuncsplayer21"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": Seed, "year": config.year, "max_rounds": Rounds},
    seed: Seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc21", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))

  let text = $doc.toJson()
  ## Refuse to write a recording that does not re-derive: a fixture the sim
  ## cannot replay is worse than no fixture.
  let deriver = newDeriver(parseReplay(text))
  var frames = 0
  while deriver.advance(): frames += 1
  if deriver.mismatchRound >= 0:
    quit("the recording diverges from its own re-derivation at round " &
      $deriver.mismatchRound)

  let outPath = if paramCount() >= 1: paramStr(1) else: DefaultOut
  writeFile(outPath, text)
  echo outPath, ": ", text.len, " bytes, ", frames, " rounds, ",
    GameVersion, ", re-derives clean"

main()
