## bc20 determinism and replay: same seed + same sheets ⇒ identical hash chain,
## record → RE-DERIVE for every bc20 end reason including the wall-clock stop,
## a STRICT UTF-8 parse of the written bytes, and the blockchain re-derived
## from events + config + seed with nothing stored.
##
## This is the bc20 half of `tests/test_determinism.nim` and
## `tests/test_replay.nim`. It is a separate shard rather than two more blocks
## in each, because both of those are written against bc26's own world type and
## a year-neutral rewrite of them would touch bc26 for no reason.

import std/[json, os, strutils, unicode]
import harness
import battlecode/[baselines, broadcast, match, replay, results, sheet,
                   sim_types]
import battlecode/years/dispatch
import battlecode/years/bc20/[maps, rules, world]

const Chassis = [scBowlOfChowder, scExamplefuncsplayer]

proc sheets(): array[2, Sheet] =
  [baselineSheet("bc20", blBowlOfChowder),
   baselineSheet("bc20", blExamplefuncsplayer)]

# --- the same world twice ---------------------------------------------------
block:
  let s = sheets()
  let (a, _) = playGameFor("bc20", "WateredDown", s, Chassis, 0, 0, 500, 0)
  let (b, _) = playGameFor("bc20", "WateredDown", s, Chassis, 0, 0, 500, 0)
  checkEq("identical hash chain", a.hashChain, b.hashChain)
  checkEq("identical rounds", a.roundsPlayed, b.roundsPlayed)
  checkEq("identical points", a.points, b.points)
  checkEq("identical end reason", a.endReason, b.endReason)
  checkEq("identical per-round chain", a.roundChains, b.roundChains)

block:
  ## A different doctrine really is a different world.
  var s = sheets()
  let a = playGameFor("bc20", "Hourglass", s, Chassis, 0, 0, 400, 0)[0]
  s[0] = parseReply("""{"sheet":{"landscaper_count_curve":"swarm",
                                 "wall_hq_round":60}}""", YearBc20)
  let b = playGameFor("bc20", "Hourglass", s, Chassis, 0, 0, 400, 0)[0]
  check("changing a knob changes the hash chain", a.hashChain != b.hashChain)

block:
  ## The MAP seed, not the episode seed, drives the world RNG.
  let s = sheets()
  let a = playGameFor("bc20", "WateredDown", s, Chassis, 0, 0, 300, 0)[0]
  let b = playGameFor("bc20", "Hourglass", s, Chassis, 0, 0, 300, 0)[0]
  check("different maps produce different chains", a.hashChain != b.hashChain)

# --- record → re-derive -----------------------------------------------------
proc deriveAndCompare(config: GameConfig, doctrines: array[2, Sheet],
                      seed: int, onMaps: seq[string] = @[]):
                        tuple[reason: EpisodeReason, ok: bool,
                              games: seq[GameOutcome], doc: ReplayDoc] =
  var plan = buildPlan(config, doctrines, seed)
  plan.chassis = Chassis
  if onMaps.len > 0:
    plan.maps = onMaps
    plan.sideAslots = @[]
    plan.abandonAfter = @[]
    for m in onMaps:
      plan.sideAslots.add(0)
      plan.abandonAfter.add(-1)
  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: doctrines[slot],
      chassis: (if slot == 0: "bowl-of-chowder" else: "examplefuncsplayer"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": seed, "year": config.year}, seed: seed, seats: seats,
    events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc20", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))
  ## Re-derive from the WRITTEN BYTES, exactly as the wasm viewer does.
  let reparsed = parseReplay($doc.toJson())
  let deriver = newDeriver(reparsed)
  while deriver.advance(): discard
  (reason, deriver.mismatchRound < 0, games, reparsed)

proc bc20Config(rounds = 400, games = 1, pool = "small"): GameConfig =
  result = defaultGameConfig()
  result.year = "bc20"
  result.pool = pool
  result.gamesPerMatch = games
  result.maxRounds = rounds

proc bare(): World =
  ## An empty 15x15 world for the ladder rungs a played game cannot reach: the
  ## committed maps arrive with their own HQs and cows, and the last three
  ## rungs need an exact roster.
  var spec = MapSpec(name: "flat", width: 15, height: 15,
    symmetry: symRotational, randomSeed: 4242)
  for i in 0 ..< 15 * 15:
    spec.elevation.add(0)
    spec.water.add(false)
    spec.pollution.add(0)
    spec.soup.add(0)
  newWorld(spec, 1500)

## Which end reasons this shard proves, and how. A rung that only a contrived
## world can reach cannot be produced by a scripted game, so it is proved by a
## LADDER VECTOR through the same `checkEndOfMatch` a played game calls; the
## rungs a played game does reach are proved by a full record → re-derive of
## the written bytes. The coverage check below names which list each reason is
## in, so it can never pass on a string nobody produced.
var reDerived: seq[string]      ## recorded, written, re-derived, no mismatch
var ladderVector: seq[string]   ## produced by `checkEndOfMatch` in this shard

block:
  ## `quantity`: the round cap with both HQs standing.
  let r = deriveAndCompare(bc20Config(260), sheets(), 4, @["Hourglass"])
  checkEq("a short bc20 game completes", r.reason, epComplete)
  check("and re-derives with no hash mismatch", r.ok)
  checkEq("one game was recorded", r.games.len, 1)
  checkEq("and it ended on the round limit", r.games[0].endReason, "quantity")
  reDerived.add(r.games[0].endReason)

block:
  ## `hq_destroyed`: the scaffold drowns on `maptestsmall`, whose HQ ring sits
  ## at elevation 1 and floods at round 256.
  let r = deriveAndCompare(bc20Config(400), sheets(), 3, @["maptestsmall"])
  checkEq("the drowning game completes", r.reason, epComplete)
  check("and re-derives with no hash mismatch", r.ok)
  checkEq("and it ended on an HQ", r.games[0].endReason, "hq_destroyed")
  checkEq("with the cause recorded as drowning",
    r.games[0].stats["hq_lost_cause"][1].getStr(), "drowned")
  reDerived.add(r.games[0].endReason)

block:
  ## `quality`: equal robot counts, unequal net worth. Driven at the world
  ## level, because the ladder's third rung needs an exact tie on the second.
  var w = newWorld(loadMap("maptestsmall"), 1500)
  discard w.spawnRobot(rtHq, loc(2, 2), teamA)
  discard w.spawnRobot(rtHq, loc(29, 29), teamB)
  w.stats.soup[0] = w.stats.soup[1] + 500
  w.currentRound = w.maxRounds - 1
  w.checkEndOfMatch()
  checkEq("the quality rung is reachable", $w.domination, "quality")
  checkEq("and the richer side wins", w.winner, teamA)
  ladderVector.add($w.domination)

block:
  ## `broadcasts`: equal worth, more MINTED transactions.
  var w = bare()
  discard w.spawnRobot(rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(rtHq, loc(13, 13), teamB)
  w.stats.blockchainsSent = [3, 1]
  w.currentRound = w.maxRounds - 1
  w.checkEndOfMatch()
  checkEq("the broadcasts rung is reachable", $w.domination, "broadcasts")
  checkEq("and the chattier side wins", w.winner, teamA)
  ladderVector.add($w.domination)

block:
  ## `highest_id`: the highest living NON-NEUTRAL robot id. The cow is ignored.
  var w = bare()
  discard w.spawnRobot(50_000, rtHq, loc(1, 1), teamA)
  discard w.spawnRobot(50_001, rtHq, loc(13, 13), teamB)
  discard w.spawnRobot(60_000, rtCow, loc(7, 7), teamNeutral)
  w.currentRound = w.maxRounds - 1
  w.checkEndOfMatch()
  checkEq("the highest_id rung is reachable", $w.domination, "highest_id")
  checkEq("and the higher id wins", w.winner, teamB)
  ladderVector.add($w.domination)

block:
  ## `coin_flip`: reachable only when NEITHER team has a living robot, and
  ## drawn from the world RNG rather than `Math.random()`.
  var w = bare()
  discard w.spawnRobot(60_000, rtCow, loc(7, 7), teamNeutral)
  w.currentRound = w.maxRounds - 1
  w.checkEndOfMatch()
  checkEq("the coin_flip rung is reachable", $w.domination, "coin_flip")
  ladderVector.add($w.domination)

block:
  ## `abandoned`, end to end and DETERMINISTICALLY. The wall-clock guard is
  ## the recorder's; `plan.abandon_after[g]` is the ONE load-bearing record of
  ## it; and playback applies that record with the same proc. A 1500-round
  ## game of this sim runs in a quarter of a second, so no honest budget makes
  ## the guard fire on its own — the round callback holds the clock instead,
  ## which is the recorder's real code path and not a mocked one.
  let s = sheets()
  let slow = proc (w: World, round: int) {.closure.} = sleep(40)
  let (_, aborted) = playGame(loadMap("Hourglass"), s, [chassisKindFor(Chassis[0]), chassisKindFor(Chassis[1])], 0, 0, 400, 1,
    slow)
  check("the wall-clock guard fired", aborted.aborted)
  checkEq("and the game is recorded as abandoned", aborted.endReason,
    "abandoned")
  check("at the first sampling point past the budget",
    aborted.roundsPlayed > 0 and (aborted.roundsPlayed and 0x1F) == 0)
  let stopAt = aborted.roundsPlayed

  var config = bc20Config(400)
  var plan = buildPlan(config, s, 9)
  plan.chassis = Chassis
  plan.maps = @["Hourglass"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[stopAt]
  var events: seq[MatchEvent]
  events.add(ev("game_abandoned", game = 0, round = stopAt,
    fields = %*{"map": plan.maps[0]}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: s[slot],
      chassis: (if slot == 0: "bowl-of-chowder" else: "examplefuncsplayer"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc20",
    config: %*{"year": "bc20"}, seed: 9, seats: seats, events: events,
    result: resultsJson(seats, @[], plan, epDeadline, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "s" & $slot
  let written = $doc.toJson()
  checkEq("the abandoned episode is recorded as a deadline",
    parseJson(written)["result"]["reason"].getStr(), "deadline")
  checkEq("an abandoned game is DISCARDED, never scored half-played",
    parseJson(written)["result"]["games"].len, 0)
  checkEq("and the stop round is the one load-bearing record",
    parseJson(written)["plan"]["abandon_after"][0].getInt(), stopAt)

  ## Re-derive it from the WRITTEN BYTES and compare frame by frame against
  ## the chain the recorder was on — the abandoned game carries no
  ## `GameHeader`, so this is the only thing that proves the two agree.
  let deriver = newDeriver(parseReplay(written))
  var frames = 0
  while deriver.advance(): frames += 1
  checkEq("playback re-derives every recorded round", frames, stopAt)
  checkEq("and stops exactly where the recorder stopped",
    deriver.session.currentRound, stopAt)
  checkEq("with the recorder's own hash chain at the stop round",
    deriver.session.hashChainHex(),
    aborted.roundChains[(stopAt - 1) * ChainHexLen ..< stopAt * ChainHexLen])
  reDerived.add("abandoned")

block:
  ## Every bc20 end reason is covered, and by the means named above.
  for reason in ["hq_destroyed", "quantity", "abandoned"]:
    check("record -> re-derive covered " & reason, reason in reDerived)
  for reason in ["quality", "broadcasts", "highest_id", "coin_flip"]:
    check("a ladder vector produced " & reason, reason in ladderVector)

# --- the written bytes ------------------------------------------------------
block:
  let r = deriveAndCompare(bc20Config(200), sheets(), 4, @["Hourglass"])
  let text = $r.doc.toJson()

  ## STRICT UTF-8. A byte-sliced multi-byte character renders fine in a
  ## browser and then fails every strict parser there is.
  check("the replay document is valid UTF-8", validateUtf8(text) == -1)
  check("and parses back", (block:
    var ok = true
    try: discard parseJson(text) except CatchableError: ok = false
    ok))
  let back = parseReplay(text)
  checkEq("the year survives the round trip", back.year, "bc20")
  checkEq("and the game version", back.gameVersion, GameVersion)
  checkEq("and the chassis each seat drove", back.seats[0].chassis,
    "bowl-of-chowder")
  checkEq("and the other seat's", back.seats[1].chassis, "examplefuncsplayer")
  let doc = parseJson(text)
  checkEq("the sheet emitted is the bc20 sheet, with no chassis key",
    doc["seats"][0]["sheet"].hasKey("chassis"), false)
  check("and it carries all ten knobs",
    doc["seats"][0]["sheet"].len == 10)

  ## NOTHING about the blockchain is stored: the sim re-derives every block.
  ## The only occurrences of the word are the two per-game COUNTERS
  ## (`blockchain_soup_spent`, and the mint counts) — never a block, never a
  ## message, never a transaction id.
  check("no block is stored in the replay",
    "\"blockchain\":" notin text and "\"blocks\"" notin text and
    "\"transactions\":" notin text)
  check("and no engine bytes either",
    "match_b64" notin text and ".bc20" notin text)

block:
  ## The viewer's re-derivation reproduces the recorded per-round hashes, and
  ## the RE-DERIVED blockchain is what the endcard reads.
  let r = deriveAndCompare(bc20Config(220), sheets(), 4, @["Hourglass"])
  check("the recorded match re-derives cleanly", r.ok)
  let deriver = newDeriver(r.doc)
  while deriver.advance(): discard
  checkEq("no mismatching round", deriver.mismatchRound, -1)
  let w = deriver.session.w20
  checkEq("the deriver played every recorded round", w.currentRound,
    r.games[0].roundsPlayed)
  checkEq("and minted one block per round", w.blockchain.len,
    r.games[0].roundsPlayed)
  var minted = 0
  for blk in w.blockchain: minted += blk.len
  checkEq("the re-derived chain matches the recorded mint count", minted,
    r.games[0].stats["transactions_minted"][0].getInt() +
    r.games[0].stats["transactions_minted"][1].getInt())

  ## And the chrome reads the re-derived blocks, not a stored dump.
  var view = initViewerState()
  let chrome = parseJson(sessionChromeJson(r.doc, deriver.session, view, 0,
    deriver.totalFrames, 0, 0, newJArray(), newJArray(), true))
  checkEq("the chrome is stamped with the year", chrome["year"].getStr(),
    "bc20")
  check("and carries the blockchain panel", chrome.hasKey("bc20_chain"))
  checkEq("whose mint counts come from the re-derivation",
    chrome["bc20_chain"]["minted"][0].getInt() +
    chrome["bc20_chain"]["minted"][1].getInt(), minted)
  check("and the flood readout", chrome.hasKey("bc20_flood"))
  check("and the soup readout", chrome.hasKey("bc20_soup"))
  check("and the unit readout", chrome.hasKey("bc20_units"))

# --- the committed fixture --------------------------------------------------
block:
  ## `tests/fixtures/replay-bc20.json` is a REAL recording, committed
  ## (§Tests item 17): the bytes `tools/wasm_replay_smoke.cjs` drives the
  ## emitted wasm module against, independently of whatever `docker-smoke`
  ## produced in the same run. Here it is proved natively: the committed bytes
  ## still parse, still carry the year and a compatible `GameVersion`, and
  ## still re-derive round for round under the CURRENT sim.
  ##
  ## When a rule changes this check goes red. That is the point — re-record
  ## with `nim r --path:src tools/gen_bc20_fixture_replay.nim`, in the commit
  ## that bumps the version.
  const FixturePath = "tests/fixtures/replay-bc20.json"
  check("the committed bc20 fixture replay exists", fileExists(FixturePath))
  let bytes = readFile(FixturePath)
  check("and is valid UTF-8", validateUtf8(bytes) == -1)
  let node = parseJson(bytes)
  checkEq("and is a battlecode replay", node["format"].getStr(),
    "cogame-battlecode-replay")
  checkEq("of the bc20 year", node["year"].getStr(), "bc20")
  check("at a GameVersion this build still loads",
    node["game_version"].getStr() in ReplayCompatibleGameVersions)
  let fixture = parseReplay(bytes)
  let fixtureDeriver = newDeriver(fixture)
  var fixtureFrames = 0
  while fixtureDeriver.advance(): fixtureFrames += 1
  check("the fixture is long enough for the wasm smoke's 50-frame floor",
    fixtureFrames >= 50)
  checkEq("it re-derives every recorded round", fixtureFrames,
    fixture.games[0].rounds)
  checkEq("with no divergence from the recorded chain — re-record with " &
    "tools/gen_bc20_fixture_replay.nim if a rule changed",
    fixtureDeriver.mismatchRound, -1)

finish("test_bc20_replay")
