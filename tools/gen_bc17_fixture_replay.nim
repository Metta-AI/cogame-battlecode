## Records `tests/fixtures/replay-bc17.json`, the committed bc17 fixture
## replay (design note §Viewer and §Tests item 27).
##
##   nim r --path:src tools/gen_bc17_fixture_replay.nim [out.json]
##
## It is a REAL RECORDING, not a hand-written document: a three-game match of
## `orchard` against `orchard` on two real doctrines, written by the same
## `ReplayDoc.toJson` the server writes. Nothing about it is random -- bc17's
## whole RNG surface is two `IDGenerator`s seeded from the map, drawn only at
## block boundaries (D3) -- so re-running this produces the same bytes.
##
## **TWO REAL DOCTRINES ON THE SAME CHASSIS, not strong-against-weak.**
## `examplefuncsplayer17` never plants a tree, never waters one, never shakes,
## never chops and never donates, so a fixture with it on one side could not
## carry half of this year's beat vocabulary -- and it MAY NOT GAIN
## BEHAVIOUR, because it is one side of the differential parity oracle. The
## two sheets here are the league's own poles: the farm that buys the win
## against the lumberjack swarm that spends to its last bullet.
##
## THE MAPS ARE CHOSEN SO THE RECORDING CARRIES EVERY BEAT KIND THE SIM CAN
## EMIT, and that was MEASURED over the committed boards rather than hoped:
##
##   `GreenHouse` (58 neutral trees, **every one of them containing a robot**
##     and 56 holding bullets) is the only board where `chop_reveal` and
##     `shake` both fire early, and where a faction can grow by chopping;
##   `HouseDivided` (**archon separation 6.5**, the `docker-smoke` map) is
##     where first blood lands inside twenty rounds, so `strike`, `volley`,
##     `rout`, `duel`, `gardener_lost` and `archon_lost` all reach the bytes;
##   `CropCircles` (198 radius-0.5 trees on the smallest board, 190 of them
##     holding bullets) is the farming game that runs to the round limit and
##     supplies `tree_planted`, `farm_online`, `donation` and the `tiebreak`
##     into `end`.
##
## `tests/test_bc17_beats.nim` asserts the coverage FROM THESE BYTES, so if a
## rules change stops one kind being emitted the test fails rather than the
## CSS quietly covering nothing (the bc25 r1-F26 finding).

import std/[json, os]
import battlecode/[match, replay, results, sheet, sim_types]
import battlecode/years/dispatch

const
  Chassis = [scOrchard, scOrchard]
  DefaultOut = "tests/fixtures/replay-bc17.json"
  Seed = 2017
  Rounds = 900
    ## Not 2 999: the fixture is loaded by `tests/test_bc17_beats.nim`, by
    ## `tests/test_viewer.nim`, by `tools/wasm_replay_smoke.cjs` and by the
    ## `wasm-viewer` job, and the per-round hash chain is sixteen hex
    ## characters a round PER GAME. 900 rounds a game keeps the artefact
    ## under 200 kB while still passing the 81-round tree maturity, the
    ## 20-round dormancy and first contact -- the three clocks every beat
    ## kind hangs off.
  Maps = ["HouseDivided", "CropCircles", "GreenHouse"]
  SideAslots = [0, 1, 0]
    ## The sides alternate, exactly as an episode's do.

proc main() =
  var config = defaultGameConfig()
  config.year = "bc17"
  config.pool = "small"
  config.gamesPerMatch = Maps.len
  config.maxRounds = Rounds
  ## Generous wall clocks: this is a RECORDING, not an episode, and it must
  ## never be abandoned by a slow machine.
  config.perGameBudgetSeconds = 900
  config.matchBudgetSeconds = 3600
  let doctrines = [
    parseReply("""{"sheet":{"opening":"tree_farm","gardener_count":4,
      "farm_layout":"hex","soldier_tank_ratio":10,"lumberjack_share":20,
      "scout_harass":20,"vp_donate_policy":"when_ahead",
      "shake_neutral_trees":"dedicated","chop_policy":"harvest",
      "bullet_reserve":150,"defend_radius":14},
      "notes":"the farm pole: four gardeners, a hex flower each, every
      neutral tree shaken and every robot-bearing one chopped open, and the
      surplus above a hundred and fifty bullets spent on points the moment it
      appears","motto":"Plant, water, donate."}""", "bc17"),
    parseReply("""{"sheet":{"opening":"tank_rush","gardener_count":2,
      "farm_layout":"ring","soldier_tank_ratio":60,"lumberjack_share":40,
      "scout_harass":40,"vp_donate_policy":"endgame_dump",
      "shake_neutral_trees":"opportunistic","chop_policy":"clear_path",
      "bullet_reserve":20,"defend_radius":3},
      "notes":"the swarm pole: two gardeners, a ring that keeps the spawn
      lane open, half its army money on lumberjacks and a fifth
      on tanks, nothing held back and nothing donated -- their farm dies or mine does",
      "motto":"Arrive before the harvest."}""", "bc17")]
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
  ## record is real rather than decorative -- and it is what puts the
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
      chassis: "orchard")
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": Seed, "year": config.year, "max_rounds": Rounds},
    seed: Seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  doc.names[0] = "daveey"
  doc.names[1] = "daveey-1"
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc17", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))

  let text = $doc.toJson()
  ## Refuse to write a recording that does not re-derive: a fixture the sim
  ## cannot replay is worse than no fixture. **This is also the one place a
  ## float32 narrowing difference between the native and the wasm backend
  ## would show up as a hash-chain mismatch**, which is why
  ## `tools/wasm_replay_smoke.cjs` runs the same check under wasm.
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
