## Records `tests/fixtures/replay-bc19.json`, the committed bc19 fixture
## replay (design note §Viewer and §Tests item 24).
##
##   nim r --path:src tools/gen_bc19_fixture_replay.nim [out.json]
##
## It is a REAL RECORDING, not a hand-written document: a three-game match of
## `saber` against `saber` on two real doctrines, written by the same
## `ReplayDoc.toJson` the server writes. Nothing about it is random — bc19's
## only generator is MT19937 seeded from the map, and the maps are committed
## with the generator state `makeMap()` left behind (V3) — so re-running this
## produces the same bytes.
##
## **TWO REAL DOCTRINES ON THE SAME CHASSIS, not strong-against-weak.**
## `examplefuncsplayer19` never mines, never deposits, never raises a church,
## never barters and never fires a preacher, so a fixture with it on one side
## could not carry half of this year's beat vocabulary — and it may not gain
## behaviour, because it is one side of the differential parity oracle.
## The two sheets here are the league's own poles: the preacher rush that
## sells its fuel against the prophet turtle that buys it.
##
## THE MAPS ARE CHOSEN SO THE RECORDING CARRIES ELEVEN OF THE TWELVE BEAT
## KINDS, and that was MEASURED over all twenty-two committed boards in both
## seat orders rather than hoped:
##
##   `seed-0107` (three castles a side on the most closed small board) in
##     the SECOND seat order is the one board-and-order in the whole set that
##     reaches `rout` — four units lost by one side in one round
##     (`years/bc19/rules.nim`'s `emitRoundBeats`) — and it also supplies
##     `castle_lost`, `church_built`, `church_lost`, `trade`,
##     `preacher_splash` and `duel`, because three castles a side at
##     separation 14 with a preacher rush on one side is this year's densest
##     fight;
##   `seed-0043` (two castles a side, the most open small board, and the
##     `docker-smoke` map) supplies the early `first_action`,
##     `unit_milestone` and `depot_claimed` beats from two orders that start
##     fourteen squares apart;
##   `seed-0009` (the smallest one-castle board) is the elimination game:
##     losing the castle loses the match on the spot, which is what puts a
##     `castles_destroyed` `game_end` in the bytes beside the round-1000
##     `tiebreak` the other two produce.
##
## THE TWELFTH KIND, `famine`, IS DELIBERATELY ABSENT and that is a property
## of the chassis, not a gap in the fixture: `resources.nim`'s `noteFamine`
## fires when a store is at zero AND the acting robot asked for something it
## could not pay for, and `saber` NEVER ASKS FOR WHAT IT CANNOT PAY (that is
## the `refused_actions == 0` gate in `tests/test_bc19_survival.nim`). The
## beat is a spectator signal for a WEAK or an LLM order, `famine` has its
## CSS rule in the year block, and `tests/test_bc19_beats.nim` asserts CSS
## for every kind the fixture ACTUALLY emitted rather than for a hand-written
## list — which is exactly why it can say so.
##
## The fixture exists so that the emitted wasm module can be driven against
## COMMITTED bytes (`tools/wasm_replay_smoke.cjs`) rather than only against
## the replay `docker-smoke` produced in the same run, and so that
## `tests/test_bc19_replay.nim` can prove a recording made at one
## `GameVersion` still re-derives. A rule change therefore turns those tests
## red: RE-RECORD WITH THIS PROGRAM, in the same commit that bumps the
## version.

import std/[json, os]
import battlecode/[match, replay, results, sheet, sim_types]
import battlecode/years/dispatch

const
  Chassis = [scSaber, scSaber]
  DefaultOut = "tests/fixtures/replay-bc19.json"
  Seed = 2019
  Rounds = 1000
    ## The year's own `MAX_ROUNDS`. A bc19 fixture recorded short would not
    ## carry the round-1000 ladder, and three of the twelve beat kinds
    ## (`tiebreak` into `end`, and both coin-flip branches) live there.
  Maps = ["seed-0107", "seed-0043", "seed-0009"]
  SideAslots = [1, 0, 1]
    ## The sides alternate, exactly as an episode's do — and `seed-0107` is
    ## in the SECOND order deliberately (see the note above).

proc main() =
  var config = defaultGameConfig()
  config.year = "bc19"
  config.pool = "mixed"
  config.gamesPerMatch = Maps.len
  config.maxRounds = Rounds
  ## Generous wall clocks: this is a RECORDING, not an episode, and it must
  ## never be abandoned by a slow machine.
  config.perGameBudgetSeconds = 900
  config.matchBudgetSeconds = 3600
  let doctrines = [
    parseReply("""{"sheet":{"opening":"preacher_rush","pilgrim_curve":9,
      "church_expansion":"early","fuel_reserve":0,"unit_mix":20,
      "preacher_share":80,"church_saber_round":0,"symmetry_wall":"screen",
      "castle_talk_use":"full","defend_radius":1,
      "trade_policy":"offer_fuel"},
      "notes":"the rush pole: preachers from round one at the mirror of my
      own castle, nothing held back for defence, and my spare fuel sold to
      them for the karbonite that buys the next one","motto":"Nine squares
      at a time."}""", "bc19"),
    parseReply("""{"sheet":{"opening":"turtle","pilgrim_curve":9,
      "church_expansion":"early","fuel_reserve":0,"unit_mix":80,
      "preacher_share":10,"church_saber_round":0,"symmetry_wall":"wall",
      "castle_talk_use":"census","defend_radius":400,
      "trade_policy":"mirror"},
      "notes":"the turtle pole: a dense prophet wall on my half of the
      midline, everything answered inside twenty squares of a structure, and
      their fuel bought back whenever the rate is in my favour",
      "motto":"Let them come to the wall."}""", "bc19")]
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
      chassis: "saber")
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": Seed, "year": config.year, "max_rounds": Rounds},
    seed: Seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  doc.names[0] = "daveey"
  doc.names[1] = "daveey-1"
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc19", g.mapName), sideAslot: g.sideAslot,
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
