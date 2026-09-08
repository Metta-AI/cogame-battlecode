## Records `tests/fixtures/replay-bc22.json`, the committed bc22 fixture
## replay (design note §Tests item 22).
##
##   nim r --path:src tools/gen_bc22_fixture_replay.nim [out.json]
##
## It is a REAL RECORDING, not a hand-written document: one scripted match
## between two `wololo` doctrines on `snowflake_redux`, seed 2029, capped at
## 2000 rounds, written by the same `ReplayDoc.toJson` the server writes.
## Nothing about it is random — the world RNG comes from the map's own
## `randomSeed` — so re-running this produces the same bytes.
##
## The fixture exists so that the emitted wasm module can be driven against
## COMMITTED bytes (`tools/wasm_replay_smoke.cjs`) rather than only against the
## replay `docker-smoke` produced in the same run, and so that
## `tests/test_bc22_beats.nim` can prove EMISSION, LABEL AND STYLE together
## against an artefact rather than against a hand-written list. A rule change
## therefore turns those tests red: re-record with this program, in the same
## commit that bumps the version.
##
## TWO REAL DOCTRINES ON THE SAME CHASSIS, not strong-against-weak:
## `examplefuncsplayer22` never builds a builder, a laboratory, a watchtower or
## a sage, never mutates, never transforms and never makes a gold, so a fixture
## with it on one side could not carry half the year's beat vocabulary. The two
## sheets here are the league's own poles — the patch-driven soldier meta
## against the gold-and-anomaly game nobody played — which is what puts
## `lab_built`, `first_sage`, `mutation`, `gold_milestone` and `anomaly_dodged`
## in the committed bytes.

import std/[json, os]
import battlecode/[match, replay, results, sheet, sim_types]
import battlecode/years/dispatch

const
  Chassis = [scWololo, scWololo]
  DefaultOut = "tests/fixtures/replay-bc22.json"
  Seed = 2029
  Rounds = 2000
    ## The whole cap, so the SINGULARITY beat is in the bytes as well as the
    ## build, laboratory, gold, mutation and anomaly ones.
  Maps = ["collaboration", "maze", "snowflake_redux"]
  SideAslots = [0, 1, 0]
    ## THREE MAPS, chosen so the recording carries ALL FOURTEEN BEAT KINDS —
    ## which no single game does, and this was measured rather than hoped:
    ##   `collaboration` (38x25, FOUR archons a side, rubble to 100) is where
    ##     the `rout` and `duel` beats come from: four build posts a side means
    ##     a big enough army that a round can cost one faction five robots;
    ##   `maze` (20x20, three archons a side, rubble mean 34.7) is where the
    ##     `archon` beats come from — both `archon_lost` and
    ##     `archon_relocated`, because the archons on it are seven squares
    ##     apart and the lead is behind a wall of rubble;
    ##   `snowflake_redux` is the liveliest small map and carries the
    ##     laboratory, gold, mutation, sage, watchtower and anomaly beats.
    ## The sides alternate, exactly as an episode's do. The match CLINCHES in
    ## two, which is correct and not truncated — so the fixture also carries
    ## the clinch shape, with `plan.maps` holding all three drawn maps.

proc main() =
  var config = defaultGameConfig()
  config.year = "bc22"
  config.pool = "mixed"
  config.gamesPerMatch = Maps.len
  config.maxRounds = Rounds
  ## Generous wall clocks: this is a RECORDING, not an episode, and it must
  ## never be abandoned by a slow machine.
  config.perGameBudgetSeconds = 900
  config.matchBudgetSeconds = 3600
  let doctrines = [
    parseReply("""{"sheet":{"opening":"sage_spam","miner_count_curve":"steady",
      "mine_floor":1,"soldier_sage_ratio":25,"lab_round":120,
      "lab_solitude":4,"gold_use":"mutations","watchtower_policy":"forward",
      "anomaly_play":"time_pushes","archon_relocate":"lead","retreat_hp":60},
      "notes":"the transmuter pole: gold, mutations and anomaly timing",
      "motto":"Two lead a gold."}""", "bc22"),
    parseReply("""{"sheet":{"opening":"soldier_rush",
      "miner_count_curve":"heavy","mine_floor":1,"soldier_sage_ratio":80,
      "lab_round":300,"lab_solitude":12,"gold_use":"sages",
      "watchtower_policy":"home","anomaly_play":"time_pushes",
      "archon_relocate":"safety","retreat_hp":20},
      "notes":"the rush pole: out-mine them early, out-soldier them by 400",
      "motto":"Leave one lead behind."}""", "bc22")]
  var plan = buildPlan(config, doctrines, Seed)
  plan.chassis = Chassis
  plan.maps = @Maps
  plan.sideAslots = @SideAslots
  plan.abandonAfter = @[]
  for i in 0 ..< Maps.len: plan.abandonAfter.add(-1)

  var events: seq[MatchEvent]
  events.add(MatchEvent(kind: "episode_start", ms: 0, game: -1, round: -1,
    fields: %*{"seed": Seed, "year": config.year, "maps": %plan.maps,
               "aliases": [AliasA, AliasB]}))
  ## The two `doctrine_received` records the doctrine phase writes. A scripted
  ## seat's sheet is read through the SAME `validate` an LLM seat's is, so the
  ## record is real rather than decorative — and it is what puts the
  ## `doctrine` beat kind in the committed fixture.
  for slot in 0 .. 1:
    var applied = newJArray()
    for field in doctrines[slot].defaultsApplied: applied.add(%field)
    events.add(MatchEvent(kind: "doctrine_received", ms: 0, game: -1,
      round: -1, fields: %*{"slot": slot, "attempt": 1, "latency_ms": 0,
        "envelope": doctrines[slot].envelope,
        "defaults_applied": applied, "unknown_fields": newJArray()}))
  let (games, reason) = playMatch(config, plan, events)
  if games.len < 2 or reason != epComplete:
    quit("the fixture match did not finish: " & $games.len & " games, reason " &
      $reason)
  events.add(MatchEvent(kind: "episode_end", ms: 1, game: -1, round: -1,
    fields: %*{"reason": $reason}))

  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: (if slot == 0: "daveey-1" else: "daveey"),
      alias: aliasFor(slot), policyKind: "scripted", sheet: doctrines[slot],
      chassis: "wololo")
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": Seed, "year": config.year, "max_rounds": Rounds},
    seed: Seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  doc.names[0] = "daveey-1"
  doc.names[1] = "daveey"
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc22", g.mapName), sideAslot: g.sideAslot,
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
