## Records `tests/fixtures/replay-bc23.json`, the committed bc23 fixture
## replay (design note §Tests item 17).
##
##   nim r --path:src tools/gen_bc23_fixture_replay.nim [out.json]
##
## It is a real recording, not a hand-written document: one scripted
## two `lemonade` doctrines on `AllElements`, seed 7, capped at 2000 rounds, written by the same `ReplayDoc.toJson` the server
## writes. Nothing about it is random — the world RNG comes from the map's own
## `randomSeed` — so re-running this produces the same bytes.
##
## The fixture exists so that the emitted wasm module can be driven against
## COMMITTED bytes (`tools/wasm_replay_smoke.cjs`) rather than only against
## the replay `docker-smoke` produced in the same run, and so that
## `tests/test_bc23_replay.nim` can prove a recording made at one
## `GameVersion` still re-derives. A rule change therefore turns that test
## red: re-record with this program, in the same commit that bumps the
## version.

import std/[json, os]
import battlecode/[baselines, match, replay, results, sheet, sim_types]
import battlecode/years/dispatch

const
  Chassis = [scLemonade, scExamplefuncsplayer25]
  DefaultOut = "tests/fixtures/replay-bc23.json"
  Map = "AllElements"
  Seed = 7
  Rounds = 2000
    ## Long enough that the strong chassis has built an anchor, ferried it,
    ## captured an island, lost one, flipped a well to elixir and fought a
    ## launcher duel — so the fixture exercises THE YEAR'S OWN BEATS rather
    ## than four hundred rounds of walking. `tests/test_bc23_beats.nim`
    ## asserts the kinds it emits.

proc main() =
  var config = defaultGameConfig()
  config.year = "bc23"
  config.pool = "mixed"
  config.gamesPerMatch = 1
  config.maxRounds = Rounds
  ## TWO REAL DOCTRINES ON THE SAME CHASSIS, not strong-against-weak:
  ## `examplefuncsplayer23` never takes an anchor, never captures an island
  ## and never flips a well, so a fixture with it on one side could not carry
  ## half the year's beat vocabulary. The two sheets here are the league's own
  ## poles — the elixir/anchor economy against the launcher duel — and they
  ## are what puts `first_elixir_unit` and the tempo beats in the committed
  ## bytes.
  let doctrines = [
    parseReply("""{"sheet":{"opening":"carrier_eco","launcher_ratio":35,
      "well_priority":"balanced","elixir_tech":"early",
      "elixir_spend":"destabilizers","anchor_round":150,"anchor_budget":60,
      "island_priority":"safe","amplifier_use":"one",
      "destabilizer_use":"siege","retreat_on_launcher_loss":"home",
      "carrier_throw":10},"notes":"the alchemist pole",
      "motto":"Anchor the sky."}""", "bc23"),
    parseReply("""{"sheet":{"opening":"carrier_eco","launcher_ratio":30,
      "well_priority":"balanced","elixir_tech":"early",
      "elixir_spend":"boosters","anchor_round":200,"anchor_budget":40,
      "island_priority":"contested","amplifier_use":"escort",
      "destabilizer_use":"defend","retreat_on_launcher_loss":"regroup",
      "carrier_throw":70},"notes":"the duel pole",
      "motto":"Win the duel."}""", "bc23")]
  var plan = buildPlan(config, doctrines, Seed)
  plan.chassis = Chassis
  plan.maps = @[Map]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[-1]

  var events: seq[MatchEvent]
  ## The two `doctrine_received` records the doctrine phase writes. A scripted
  ## seat's sheet is read through the SAME `validate` an LLM seat's is, so the
  ## record is real rather than decorative — and it is what puts the
  ## `doctrine` beat kind in the committed fixture.
  for slot in 0 .. 1:
    events.add(MatchEvent(kind: "doctrine_received", ms: 0, game: -1,
      round: -1, fields: %*{"slot": slot, "attempt": 1, "latency_ms": 0,
        "defaults_applied": newJArray(), "unknown_fields": newJArray()}))
  let (games, reason) = playMatch(config, plan, events)
  if games.len != 1:
    quit("the fixture game did not finish: reason " & $reason)

  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: doctrines[slot],
      chassis: (if slot == 0: "lemonade" else: "examplefuncsplayer25"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": Seed, "year": config.year, "max_rounds": Rounds},
    seed: Seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc23", g.mapName), sideAslot: g.sideAslot,
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
