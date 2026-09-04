## bc21 determinism and replay: same seed + same sheets ⇒ identical hash chain,
## record → RE-DERIVE for every bc21 end reason including the wall-clock stop,
## a STRICT UTF-8 parse of the written bytes, the flag traffic and the auction
## re-derived from events + config + seed with nothing stored, and EVERY event
## kind inside its per-game bound.
##
## This is the bc21 half of `tests/test_determinism.nim` and
## `tests/test_replay.nim`. It is a separate shard rather than more blocks in
## each, because both of those are written against bc26's own world type and a
## year-neutral rewrite of them would touch bc26 for no reason.

import std/[json, os, strutils, tables, unicode]
import harness
import battlecode/[baselines, broadcast, match, replay, results, sheet,
                   sim_types]
import battlecode/years/dispatch
import battlecode/years/bc21/[maps, rules, world]

const Chassis = [scCaliforniaRoll, scExamplefuncsplayer21]

proc sheets(): array[2, Sheet] =
  [baselineSheet("bc21", blCaliforniaRoll),
   baselineSheet("bc21", blExamplefuncsplayer21)]

# --- the same world twice ---------------------------------------------------
block:
  let s = sheets()
  let (a, _) = playGameFor("bc21", "Bog", s, Chassis, 0, 0, 400, 0)
  let (b, _) = playGameFor("bc21", "Bog", s, Chassis, 0, 0, 400, 0)
  checkEq("identical hash chain", a.hashChain, b.hashChain)
  checkEq("identical rounds", a.roundsPlayed, b.roundsPlayed)
  checkEq("identical points", a.points, b.points)
  checkEq("identical end reason", a.endReason, b.endReason)
  checkEq("identical per-round chain", a.roundChains, b.roundChains)

block:
  ## A different doctrine really is a different world.
  var s = sheets()
  let a = playGameFor("bc21", "Star", s, Chassis, 0, 0, 300, 0)[0]
  s[0] = parseReply("""{"sheet":{"opening":"muck_spam","muck_ratio":85}}""",
    YearBc21)
  let b = playGameFor("bc21", "Star", s, Chassis, 0, 0, 300, 0)[0]
  check("changing a knob changes the hash chain", a.hashChain != b.hashChain)

block:
  ## The MAP seed, not the episode seed, drives the world RNG.
  let s = sheets()
  let a = playGameFor("bc21", "Bog", s, Chassis, 0, 0, 250, 0)[0]
  let b = playGameFor("bc21", "Star", s, Chassis, 0, 0, 250, 0)[0]
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
      chassis: (if slot == 0: "california-roll" else: "examplefuncsplayer21"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": seed, "year": config.year}, seed: seed, seats: seats,
    events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc21", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))
  ## Re-derive from the WRITTEN BYTES, exactly as the wasm viewer does.
  let reparsed = parseReplay($doc.toJson())
  let deriver = newDeriver(reparsed)
  while deriver.advance(): discard
  (reason, deriver.mismatchRound < 0, games, reparsed)

proc bc21Config(rounds = 400, games = 1, pool = "small"): GameConfig =
  result = defaultGameConfig()
  result.year = "bc21"
  result.pool = pool
  result.gamesPerMatch = games
  result.maxRounds = rounds

proc bare(): World =
  ## An empty 15x15 world for the ladder rungs a played game cannot reach.
  var spec = MapSpec(name: "flat", width: 15, height: 15, origin: [0, 0],
    symmetry: symRotational, symmetries: @[symRotational], randomSeed: 4242)
  for i in 0 ..< 15 * 15: spec.passability.add(1.0)
  newWorld(spec, 400)

## Which end reasons this shard proves, and how. A rung that only a contrived
## world can reach cannot be produced by a scripted game, so it is proved by a
## LADDER VECTOR through the same `checkEndOfMatch` a played game calls; the
## rungs a played game does reach are proved by a full record → re-derive of
## the written bytes. The coverage check below names which list each reason is
## in, so it can never pass on a string nobody produced.
var reDerived: seq[string]
var ladderVector: seq[string]

block:
  ## `more_votes`: the round cap with both sides alive.
  let r = deriveAndCompare(bc21Config(250), sheets(), 4, @["Bog"])
  checkEq("a short bc21 game completes", r.reason, epComplete)
  check("and re-derives with no hash mismatch", r.ok)
  checkEq("one game was recorded", r.games.len, 1)
  checkEq("and it ended on the vote count", r.games[0].endReason, "more_votes")
  reDerived.add(r.games[0].endReason)

block:
  ## `more_enlightenment_centers`: an `examplefuncsplayer21` MIRROR on
  ## `FrogOrBath`, where both sides end level on votes and one has taken more
  ## Centres. A played game reaches this rung; the two below it do not, and
  ## are proved by ladder vectors instead.
  var config = bc21Config(1500)
  let scaffoldPair = [baselineSheet("bc21", blExamplefuncsplayer21),
                      baselineSheet("bc21", blExamplefuncsplayer21)]
  var plan = buildPlan(config, scaffoldPair, 7)
  plan.chassis = [scExamplefuncsplayer21, scExamplefuncsplayer21]
  plan.maps = @["FrogOrBath"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[-1]
  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  checkEq("the scaffold mirror completes", reason, epComplete)
  checkEq("and it ended on the Centres rung", games[0].endReason,
    "more_enlightenment_centers")
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: scaffoldPair[slot],
      chassis: "examplefuncsplayer21")
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc21",
    config: %*{"year": "bc21"}, seed: 7, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc21", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))
  let deriver = newDeriver(parseReplay($doc.toJson()))
  while deriver.advance(): discard
  checkEq("and it re-derives with no hash mismatch", deriver.mismatchRound, -1)
  reDerived.add(games[0].endReason)

block:
  ## `annihilated`. NO scripted pairing on the `small` pool produces it: even
  ## a team that has lost every Enlightenment Center keeps two or three
  ## 1-influence muckrakers wandering to the last round, which is exactly what
  ## the rule says should keep it alive. So it is proved by a ladder vector
  ## through the same `checkEndOfMatch` a played game calls — including the
  ## engine's own asymmetry, that a DOUBLE WIPE goes to B.
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(1, 1), teamA, 100)
  w.currentRound = 137
  w.checkEndOfMatch()
  checkEq("the annihilation rung is reachable", $w.domination, "annihilated")
  checkEq("and the surviving side wins", w.winner, teamA)
  check("at any round, not only at the cap", not w.timeLimitReached())
  ladderVector.add($w.domination)

block:
  ## The Centres rung as a VECTOR too, so the rung itself is pinned
  ## independently of which map happens to reach it.
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(1, 1), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(3, 3), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(13, 13), teamB, 200)
  w.stats.votes = [200, 200]
  w.currentRound = w.maxRounds
  w.checkEndOfMatch()
  checkEq("the Centres rung is reachable", $w.domination,
    "more_enlightenment_centers")
  checkEq("and the side with more of them wins", w.winner, teamA)
  ladderVector.add($w.domination)

block:
  ## `more_influence`: votes and Centres tied, influence not.
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(1, 1), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(13, 13), teamB, 100)
  discard w.spawnRobot(-1, rtMuckraker, loc(13, 12), teamB, 40)
  w.stats.votes = [200, 200]
  w.currentRound = w.maxRounds
  w.checkEndOfMatch()
  checkEq("the influence rung is reachable", $w.domination, "more_influence")
  checkEq("and the richer side wins", w.winner, teamB)
  ladderVector.add($w.domination)

block:
  ## `coin_flip`: everything tied, and drawn from the WORLD RNG rather than
  ## `Math.random()`.
  var w = bare()
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(1, 1), teamA, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(13, 13), teamB, 100)
  w.stats.votes = [200, 200]
  w.currentRound = w.maxRounds
  w.checkEndOfMatch()
  checkEq("the coin_flip rung is reachable", $w.domination, "coin_flip")
  ladderVector.add($w.domination)

block:
  ## `abandoned`, end to end and DETERMINISTICALLY. The wall-clock guard is
  ## the recorder's; `plan.abandon_after[g]` is the ONE load-bearing record of
  ## it; and playback applies that record with the same proc. A 400-round game
  ## of this sim runs in well under a second, so no honest budget makes the
  ## guard fire on its own — the round callback holds the clock instead, which
  ## is the recorder's real code path and not a mocked one.
  let s = sheets()
  let slow = proc (w: World, round: int) {.closure.} = sleep(40)
  let (_, aborted) = playGame(loadMap("Bog"), s,
    [ckCaliforniaRoll, ckExamplefuncsplayer21], 0, 0, 400, 1, slow)
  check("the wall-clock guard fired", aborted.aborted)
  checkEq("and the game is recorded as abandoned", aborted.endReason,
    "abandoned")
  check("at the first sampling point past the budget",
    aborted.roundsPlayed > 0 and (aborted.roundsPlayed and 0x1F) == 0)
  let stopAt = aborted.roundsPlayed

  var config = bc21Config(400)
  var plan = buildPlan(config, s, 9)
  plan.chassis = Chassis
  plan.maps = @["Bog"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[stopAt]
  var events: seq[MatchEvent]
  events.add(ev("game_abandoned", game = 0, round = stopAt,
    fields = %*{"map": plan.maps[0]}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: s[slot],
      chassis: (if slot == 0: "california-roll" else: "examplefuncsplayer21"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc21",
    config: %*{"year": "bc21"}, seed: 9, seats: seats, events: events,
    result: resultsJson(seats, @[], plan, epDeadline, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "s" & $slot
  let written = $doc.toJson()
  checkEq("the abandoned episode is recorded as a deadline",
    parseJson(written)["result"]["reason"].getStr(), "deadline")
  checkEq("an abandoned game is DISCARDED, never scored half-played",
    parseJson(written)["result"]["games"].len, 0)
  checkEq("and the stop round is the one load-bearing record",
    parseJson(written)["plan"]["abandon_after"][0].getInt(), stopAt)

  ## Re-derive it from the WRITTEN BYTES and compare against the chain the
  ## recorder was on — the abandoned game carries no `GameHeader`, so this is
  ## the only thing that proves the two agree.
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
  ## Every bc21 end reason is covered, and by the means named above.
  for reason in ["more_votes", "more_enlightenment_centers", "abandoned"]:
    check("record -> re-derive covered " & reason, reason in reDerived)
  for reason in ["annihilated", "more_enlightenment_centers", "more_influence",
                 "coin_flip"]:
    check("a ladder vector produced " & reason, reason in ladderVector)

# --- the written bytes ------------------------------------------------------
block:
  let r = deriveAndCompare(bc21Config(200), sheets(), 4, @["Bog"])
  let text = $r.doc.toJson()

  ## STRICT UTF-8. A byte-sliced multi-byte character renders fine in a
  ## browser and then fails every strict parser there is.
  check("the replay document is valid UTF-8", validateUtf8(text) == -1)
  check("and parses back", (block:
    var ok = true
    try: discard parseJson(text) except CatchableError: ok = false
    ok))
  let back = parseReplay(text)
  checkEq("the year survives the round trip", back.year, "bc21")
  checkEq("and the game version", back.gameVersion, GameVersion)
  checkEq("and the chassis each seat drove", back.seats[0].chassis,
    "california-roll")
  checkEq("and the other seat's", back.seats[1].chassis,
    "examplefuncsplayer21")
  let doc = parseJson(text)
  checkEq("the sheet emitted is the bc21 sheet, with no chassis key",
    doc["seats"][0]["sheet"].hasKey("chassis"), false)
  check("and it carries all ten knobs", doc["seats"][0]["sheet"].len == 10)

  ## NOTHING about the flags or the auction is stored: the sim re-derives
  ## every round.
  check("no flag dump is stored in the replay",
    "\"flags\":" notin text and "\"flag\":" notin text)
  check("no per-round bid dump either",
    "\"bids\":" notin text and "\"blocks\"" notin text)
  check("and no engine bytes",
    "match_b64" notin text and ".bc21" notin text)

block:
  ## EVERY EVENT KIND RESPECTS ITS PER-GAME BOUND. A 1500-round match with
  ## hundreds of robots cannot be allowed to emit an event per empower.
  let r = deriveAndCompare(bc21Config(1500), sheets(), 5, @["Bog"])
  checkEq("the long game completed", r.reason, epComplete)
  var counts = initCountTable[string]()
  for e in r.doc.events:
    counts.inc(e.kind)
  const Bounds = {
    "center_taken": 24, "vote_lead": 40, "bid_spike": 30, "expose_wave": 20,
    "empower_big": 40, "first_build": 6, "annihilated": 1, "game_start": 1,
    "game_end": 1, "game_abandoned": 1
  }.toTable
  for kind, bound in Bounds:
    check(kind & " is inside its per-game bound (" & $counts[kind] & " <= " &
      $bound & ")", counts[kind] <= bound)
  check("and the whole event list is a few hundred entries, not a megabyte",
    r.doc.events.len <= 300)
  check("the match really did produce beats", r.doc.events.len >= 5)
  ## Every event kind emitted must be one the viewer has CSS for.
  const Known = ["episode_start", "doctrine_requested", "doctrine_received",
    "doctrine_retry", "doctrine_fallback", "game_start", "first_build",
    "center_taken", "vote_lead", "bid_spike", "expose_wave", "empower_big",
    "annihilated", "game_end", "game_abandoned", "episode_end"]
  for kind in counts.keys:
    check("the event kind " & kind & " is in the documented vocabulary",
      kind in Known)

block:
  ## The viewer's re-derivation reproduces the recorded per-round hashes, and
  ## the RE-DERIVED auction is what the endcard reads.
  let r = deriveAndCompare(bc21Config(220), sheets(), 4, @["Bog"])
  check("the recorded match re-derives cleanly", r.ok)
  let deriver = newDeriver(r.doc)
  while deriver.advance(): discard
  checkEq("no mismatching round", deriver.mismatchRound, -1)
  let w = deriver.session.w21
  checkEq("the deriver played every recorded round", w.currentRound,
    r.games[0].roundsPlayed)
  let votes = w.stats.votes[0] + w.stats.votes[1]
  checkEq("and the re-derived vote tally matches the recorded one", votes,
    r.games[0].stats["votes"][0].getInt() +
    r.games[0].stats["votes"][1].getInt())

  ## And the chrome reads the re-derived auction, not a stored dump.
  var view = initViewerState()
  let chrome = parseJson(sessionChromeJson(r.doc, deriver.session, view, 0,
    deriver.totalFrames, 0, 0, newJArray(), newJArray(), true))
  checkEq("the chrome is stamped with the year", chrome["year"].getStr(),
    "bc21")
  check("and carries the election readout", chrome.hasKey("bc21_votes"))
  check("and the influence readout", chrome.hasKey("bc21_influence"))
  check("and the unit readout", chrome.hasKey("bc21_units"))
  check("and the auction panel", chrome.hasKey("bc21_bids"))
  checkEq("whose vote tally comes from the re-derivation",
    chrome["bc21_bids"]["clans"][0]["votes"].getInt() +
    chrome["bc21_bids"]["clans"][1]["votes"].getInt(), votes)

  ## THE FLAG TRAFFIC IS RE-DERIVED, not stored. Every robot's flag exists in
  ## the re-derived world and nowhere in the document.
  var flagged = 0
  for _, robot in w.robotsById:
    if robot.flag != 0: inc flagged
  check("the re-derived world carries live flag traffic", flagged > 0)

# --- the committed fixture --------------------------------------------------
block:
  ## `tests/fixtures/replay-bc21.json` is a REAL recording, committed
  ## (§Tests item 17): the bytes `tools/wasm_replay_smoke.cjs` drives the
  ## emitted wasm module against, independently of whatever `docker-smoke`
  ## produced in the same run. Here it is proved natively.
  ##
  ## When a rule changes this check goes red. That is the point — re-record
  ## with `nim r --path:src tools/gen_bc21_fixture_replay.nim`, in the commit
  ## that bumps the version.
  const FixturePath = "tests/fixtures/replay-bc21.json"
  check("the committed bc21 fixture replay exists", fileExists(FixturePath))
  let bytes = readFile(FixturePath)
  check("and is valid UTF-8", validateUtf8(bytes) == -1)
  let node = parseJson(bytes)
  checkEq("and is a battlecode replay", node["format"].getStr(),
    "cogame-battlecode-replay")
  checkEq("of the bc21 year", node["year"].getStr(), "bc21")
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
    "tools/gen_bc21_fixture_replay.nim if a rule changed",
    fixtureDeriver.mismatchRound, -1)

finish("test_bc21_replay")
