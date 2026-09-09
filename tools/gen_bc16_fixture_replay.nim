## Records `tests/fixtures/replay-bc16.json`, the committed bc16 fixture
## replay (design note §Tests item 24).
##
##   nim r --path:src tools/gen_bc16_fixture_replay.nim [out.json]
##
## It is a REAL RECORDING, not a hand-written document: one scripted match
## between two `bulwark` doctrines, written by the same `ReplayDoc.toJson` the
## server writes. Nothing about it is random — the three `java.util.Random`
## streams all come from the map's own `randomSeed` — so re-running this
## produces the same bytes.
##
## The fixture exists so that the emitted wasm module can be driven against
## COMMITTED bytes (`tools/wasm_replay_smoke.cjs`) rather than only against the
## replay `docker-smoke` produced in the same run, and so that
## `tests/test_bc16_beats.nim` can prove EMISSION, LABEL AND STYLE together
## against an artefact rather than against a hand-written list. A rule change
## therefore turns those tests red: re-record with this program, in the same
## commit that bumps the version.
##
## **TWO REAL DOCTRINES ON THE SAME CHASSIS, not strong-against-weak.**
## `greenhorn` never builds a guard, a scout, a viper or a turret, never
## clears rubble, never activates a neutral and never kills a den, so a
## fixture with it on one side could not carry half the year's beat
## vocabulary. The two sheets here are the league's own poles — the turret
## turtle against the scout-pull / infection doctrine — which is what puts
## `den_destroyed`, `neutral_activated`, `infection`, `turned` and
## `unit_milestone` in the committed bytes alongside the schedule's own
## `zombie_wave` and `outbreak`.
##
## THE MAPS ARE CHOSEN SO THE RECORDING CARRIES ALL THIRTEEN BEAT KINDS, and
## that was MEASURED rather than hoped:
##   `frogger` (35x35, FOUR archons a side, TWELVE dens, ZERO impassable
##     squares) is where the `den`, `turned`, `rout` and `duel` beats come
##     from — twelve dens on open ground is the densest horde in the pool;
##   `checkers` (30x30, two archons a side, THIRTY neutrals) is where
##     `activate` comes from;
##   `river` (32x32, three archons a side, MINIMUM ARCHON SEPARATION 4.0) is
##     where the early `build`, `infect` and `archon` beats come from, because
##     the two factions start in contact.
## The sides alternate, exactly as an episode's do.

import std/[json, os]
import battlecode/[match, replay, results, sheet, sim_types]
import battlecode/years/dispatch

const
  Chassis = [scBulwark, scBulwark]
  DefaultOut = "tests/fixtures/replay-bc16.json"
  Seed = 2016
  Rounds = 1600
    ## Long enough for FIVE outbreak steps, several scheduled waves, a viper
    ## (120 parts against a 2-a-round income) and the den programme to
    ## commit — and short enough that the committed fixture stays small.
  Maps = ["frogger", "checkers", "river"]
  SideAslots = [1, 0, 1]

proc main() =
  var config = defaultGameConfig()
  config.year = "bc16"
  config.pool = "small"
  config.gamesPerMatch = Maps.len
  config.maxRounds = Rounds
  ## Generous wall clocks: this is a RECORDING, not an episode, and it must
  ## never be abandoned by a slow machine.
  config.perGameBudgetSeconds = 900
  config.matchBudgetSeconds = 3600
  let doctrines = [
    parseReply("""{"sheet":{"opening":"turtle","turret_count":6,
      "guard_ratio":70,"zombie_kiting":"ranged_only","den_clear_round":600,
      "parts_priority":"turrets","archon_spread":"huddle",
      "neutral_activation":"hunt","retreat_hp":55,
      "rubble_clear":"aggressive","infection_policy":"quarantine"},
      "notes":"the bulwark pole: guards and turrets, a closed ring, and the
      nearest den broken at 600","motto":"The wall holds."}""", "bc16"),
    parseReply("""{"sheet":{"opening":"scout_zombie_pull","turret_count":1,
      "guard_ratio":20,"zombie_kiting":"always","den_clear_round":1500,
      "parts_priority":"vipers","archon_spread":"split",
      "neutral_activation":"hunt","retreat_hp":30,"rubble_clear":"paths",
      "infection_policy":"suicide_squad"},
      "notes":"the pullers pole: scouts on the far side of every den, vipers
      before the third soldier, and anything I infect dies next to their
      archon","motto":"Let them meet the horde first."}""", "bc16")]
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
    seats[slot] = SeatReport(name: (if slot == 0: "daveey" else: "daveey-1"),
      alias: aliasFor(slot), policyKind: "scripted", sheet: doctrines[slot],
      chassis: "bulwark")
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": Seed, "year": config.year, "max_rounds": Rounds},
    seed: Seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  doc.names[0] = "daveey"
  doc.names[1] = "daveey-1"
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc16", g.mapName), sideAslot: g.sideAslot,
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
