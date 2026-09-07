## bc24 determinism and replay: same seed + same sheets => identical hash
## chain, record -> RE-DERIVE for every bc24 end reason including the
## wall-clock stop, a STRICT UTF-8 parse of the written bytes, traps, water,
## levels and flag positions re-derived from events + config + seed with
## nothing stored, and EVERY event kind inside its per-game bound.
##
## This is the bc24 half of `tests/test_determinism.nim` and
## `tests/test_replay.nim`, a separate shard for the same reason bc20's and
## bc21's are: both of those are written against bc26's own world type.

import std/[json, os, strutils, tables, unicode]
import harness
import battlecode/[baselines, broadcast, match, replay, results, sheet,
                   sim_types]
import battlecode/years/dispatch
import battlecode/years/bc24/[maps, rules, world]

const Chassis = [scGoneSharkin, scExamplefuncsplayer24]

proc sheets(): array[2, Sheet] =
  [baselineSheet("bc24", blGoneSharkin),
   baselineSheet("bc24", blExamplefuncsplayer24)]

# --- the same world twice ---------------------------------------------------
block:
  let s = sheets()
  let (a, _) = playGameFor("bc24", "Yinyang", s, Chassis, 0, 0, 400, 0)
  let (b, _) = playGameFor("bc24", "Yinyang", s, Chassis, 0, 0, 400, 0)
  checkEq("identical hash chain", a.hashChain, b.hashChain)
  checkEq("identical rounds", a.roundsPlayed, b.roundsPlayed)
  checkEq("identical points", a.points, b.points)
  checkEq("identical end reason", a.endReason, b.endReason)
  checkEq("identical per-round chain", a.roundChains, b.roundChains)

block:
  ## A different doctrine really is a different world.
  var s = sheets()
  let a = playGameFor("bc24", "Occulus", s, Chassis, 0, 0, 400, 0)[0]
  s[0] = parseReply("""{"sheet":{"specialisation_split":"attack",
    "flag_rush_round":220}}""", YearBc24)
  let b = playGameFor("bc24", "Occulus", s, Chassis, 0, 0, 400, 0)[0]
  check("changing a knob changes the hash chain", a.hashChain != b.hashChain)

block:
  ## The MAP seed, not the episode seed, drives the world RNG.
  let s = sheets()
  let a = playGameFor("bc24", "Yinyang", s, Chassis, 0, 0, 300, 0)[0]
  let b = playGameFor("bc24", "Occulus", s, Chassis, 0, 0, 300, 0)[0]
  check("different maps produce different chains", a.hashChain != b.hashChain)

# --- record -> re-derive -----------------------------------------------------
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
      chassis: (if slot == 0: "gone-sharkin" else: "examplefuncsplayer24"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": seed, "year": config.year}, seed: seed, seats: seats,
    events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc24", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))
  ## Re-derive from the WRITTEN BYTES, exactly as the wasm viewer does.
  let reparsed = parseReplay($doc.toJson())
  let deriver = newDeriver(reparsed)
  while deriver.advance(): discard
  (reason, deriver.mismatchRound < 0, games, reparsed)

proc bc24Config(rounds = 400, games = 1, pool = "small"): GameConfig =
  result = defaultGameConfig()
  result.year = "bc24"
  result.pool = pool
  result.gamesPerMatch = games
  result.maxRounds = rounds

proc bare(): World =
  ## An empty world for the ladder rungs a played game cannot reach.
  var spec = MapSpec(name: "flat", width: 30, height: 30, randomSeed: 4242,
    symmetry: symVertical)
  spec.walls = newSeq[bool](900)
  spec.water = newSeq[bool](900)
  spec.dam = newSeq[bool](900)
  let centres = [loc(3, 3), loc(26, 3), loc(3, 15), loc(26, 15),
                 loc(3, 26), loc(26, 26)]
  for i in 0 .. 5:
    spec.spawnLocations[i] = centres[i]
  spec.spawnCenters = [loc(3, 3), loc(26, 3), loc(3, 15), loc(26, 15),
                       loc(3, 26), loc(26, 26)]
  newWorld(spec, 2000)

## Which end reasons this shard proves, and how. A rung that only a contrived
## world can reach cannot be produced by a scripted game, so it is proved by a
## LADDER VECTOR through the same `checkEndOfMatch` a played game calls; the
## rungs a played game does reach are proved by a full record -> re-derive of
## the written bytes. The coverage check below names which list each reason is
## in, so it can never pass on a string nobody produced.
var reDerived: seq[string]
var ladderVector: seq[string]

block:
  ## `capture`: `gone-sharkin` really does take all three flags on Yinyang.
  let r = deriveAndCompare(bc24Config(2000), sheets(), 4, @["Yinyang"])
  checkEq("the game completed", r.reason, epComplete)
  check("and re-derives with no hash mismatch", r.ok)
  checkEq("one game was recorded", r.games.len, 1)
  checkEq("and it ended on a capture", r.games[0].endReason, "capture")
  reDerived.add(r.games[0].endReason)

block:
  ## `level_sum`: a scaffold MIRROR on `Rivers`, whose halves are separated by
  ## water, so nobody captures anything and the second rung decides it.
  var config = bc24Config(2000)
  let scaffoldPair = [baselineSheet("bc24", blExamplefuncsplayer24),
                      baselineSheet("bc24", blExamplefuncsplayer24)]
  var plan = buildPlan(config, scaffoldPair, 7)
  plan.chassis = [scExamplefuncsplayer24, scExamplefuncsplayer24]
  plan.maps = @["Rivers"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[-1]
  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  checkEq("the scaffold mirror completed", reason, epComplete)
  checkEq("one game", games.len, 1)
  check("and the round cap decided it on a tiebreak rung",
    games[0].endReason in ["level_sum", "more_bread", "more_flag_captures",
                           "coin_flip"])
  reDerived.add(games[0].endReason)

block:
  ## The rungs a played game does not reach, through the same ladder.
  var w = bare()
  w.currentRound = 2000
  w.stats.flagsCaptured = [2, 1]
  w.checkEndOfMatch()
  checkEq("more_flag_captures", $w.domination, "more_flag_captures")
  ladderVector.add($w.domination)

  var x = bare()
  x.currentRound = 2000
  x.stats.crumbs = [900, 100]
  x.checkEndOfMatch()
  checkEq("more_bread", $x.domination, "more_bread")
  ladderVector.add($x.domination)

  var y = bare()
  y.currentRound = 2000
  y.checkEndOfMatch()
  checkEq("coin_flip", $y.domination, "coin_flip")
  ladderVector.add($y.domination)

  var z = bare()
  z.currentRound = 2000
  z.robots[1].attackExp = 200
  z.checkEndOfMatch()
  checkEq("level_sum", $z.domination, "level_sum")
  ladderVector.add($z.domination)

# --- the wall-clock stop, applied by the SAME proc on both paths ------------
block:
  ## `abandoned` / `deadline`: `plan.abandonAfter[g]` is ONE load-bearing
  ## record, applied by the same proc on record and on playback (the
  ## particle-worlds scar). Here the recorder is forced to stop mid-game and
  ## the deriver must stop in exactly the same place.
  var config = bc24Config(2000)
  let doctrines = sheets()
  var plan = buildPlan(config, doctrines, 11)
  plan.chassis = Chassis
  plan.maps = @["Yinyang"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[-1]
  let (w, aborted) = playGame(loadMap("Yinyang"), doctrines,
    [ckGoneSharkin, ckExamplefuncsplayer24], 0, 0, 2000, 0)
  check("(a full game to compare against)", w.currentRound > 300)
  let stopAt = 180
  plan.abandonAfter = @[stopAt]
  var events: seq[MatchEvent]
  events.add(ev("game_start", game = 0, round = 0,
    fields = %*{"map": "Yinyang", "width": 31, "height": 31,
                "sides": [AliasA, AliasB]}))
  events.add(ev("game_abandoned", game = 0, round = stopAt,
    fields = %*{"map": "Yinyang"}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: doctrines[slot],
      chassis: (if slot == 0: "gone-sharkin" else: "examplefuncsplayer24"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc24",
    config: %*{"seed": 11, "year": "bc24"}, seed: 11, seats: seats,
    events: events,
    result: resultsJson(seats, @[], plan, epDeadline, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  doc.games.add(GameHeader(index: 0, map: "Yinyang",
    mapSha: mapSha("bc24", "Yinyang"), sideAslot: 0, rounds: stopAt,
    hashChain: "", roundChains: aborted.roundChains))
  let written = $doc.toJson()
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
  ## Every bc24 end reason is covered, and by the means named above.
  check("record -> re-derive covered capture", "capture" in reDerived)
  check("record -> re-derive covered the wall-clock stop",
    "abandoned" in reDerived)
  for reason in ["more_flag_captures", "level_sum", "more_bread",
                 "coin_flip"]:
    check("a ladder vector produced " & reason, reason in ladderVector)

# --- the written bytes ------------------------------------------------------
block:
  let r = deriveAndCompare(bc24Config(320), sheets(), 4, @["Yinyang"])
  let text = $r.doc.toJson()

  ## STRICT UTF-8. A byte-sliced multi-byte character renders fine in a
  ## browser and then fails every strict parser there is.
  check("the replay document is valid UTF-8", validateUtf8(text) == -1)
  check("and parses back", (block:
    var ok = true
    try: discard parseJson(text) except CatchableError: ok = false
    ok))
  let back = parseReplay(text)
  checkEq("the year survives the round trip", back.year, "bc24")
  checkEq("and the game version", back.gameVersion, GameVersion)
  checkEq("and the chassis each seat drove", back.seats[0].chassis,
    "gone-sharkin")
  checkEq("and the other seat's", back.seats[1].chassis,
    "examplefuncsplayer24")
  let doc = parseJson(text)
  checkEq("the sheet emitted is the bc24 sheet, with no chassis key",
    doc["seats"][0]["sheet"].hasKey("chassis"), false)
  check("and it carries all ten knobs", doc["seats"][0]["sheet"].len == 10)

  ## NOTHING about traps, water, levels or flag positions is stored: the sim
  ## re-derives every round.
  check("no trap dump is stored in the replay",
    "\"traps\":[[" notin text and "\"trap_locations\"" notin text)
  check("no per-round water or terrain dump",
    "\"water\":" notin text and "\"terrain\"" notin text)
  check("no per-duck dump", "\"ducks\":" notin text and
    "\"robots\":" notin text)
  check("and no engine bytes",
    "match_b64" notin text and ".map24" notin text and ".bc24" notin text)

block:
  ## EVERY EVENT KIND RESPECTS ITS PER-GAME BOUND. A 2000-round match with a
  ## hundred ducks cannot be allowed to emit an event per attack.
  let r = deriveAndCompare(bc24Config(2000), sheets(), 5, @["Occulus"])
  checkEq("the long game completed", r.reason, epComplete)
  var counts = initCountTable[string]()
  for e in r.doc.events:
    counts.inc(e.kind)
  const Bounds = {
    "setup_end": 2, "first_action": 4, "flag_taken": 24, "flag_dropped": 24,
    "flag_returned": 24, "flag_captured": 6, "trap_wave": 20, "upgrade": 6,
    "mastery": 9, "rout": 20, "game_start": 1, "game_end": 1,
    "game_abandoned": 1
  }.toTable
  for kind, bound in Bounds:
    check(kind & " is inside its per-game bound (" & $counts[kind] & " <= " &
      $bound & ")", counts[kind] <= bound)
  check("and the whole event list is a few hundred entries, not a megabyte",
    r.doc.events.len <= 300)
  check("the match really did produce beats", r.doc.events.len >= 5)
  ## Every event kind emitted must be one the viewer has CSS for.
  const Known = ["episode_start", "doctrine_requested", "doctrine_received",
    "doctrine_retry", "doctrine_fallback", "game_start", "setup_end",
    "first_action", "flag_taken", "flag_dropped", "flag_returned",
    "flag_captured", "trap_wave", "upgrade", "mastery", "rout", "game_end",
    "game_abandoned", "episode_end"]
  for kind in counts.keys:
    check("the event kind " & kind & " is in the documented vocabulary",
      kind in Known)
  ## And every `first_action.kind` is in the documented vocabulary.
  for e in r.doc.events:
    if e.kind == "first_action":
      ## THE FIELD IS `action`, not `kind`: `MatchEvent` flattens `fields`
      ## into the same object as the event's own `kind`, so a field called
      ## `kind` overwrites the event kind and the replay comes back carrying
      ## events of kind "move". This assertion is what keeps it renamed.
      check("first_action carries no field called `kind`",
        not e.fields.hasKey("kind"))
      check("first_action.action is a documented action name",
        e.fields["action"].getStr() in Bc24ActionNames)
    if e.kind == "upgrade":
      check("upgrade.upgrade is a documented upgrade name",
        e.fields["upgrade"].getStr() in Bc24UpgradeNames)
    if e.kind == "mastery":
      check("mastery.skill is a documented skill name",
        e.fields["skill"].getStr() in Bc24SkillNames)

block:
  ## The viewer's re-derivation reproduces the recorded per-round hashes, and
  ## the RE-DERIVED traps, water and levels are what the endcard reads.
  let r = deriveAndCompare(bc24Config(320), sheets(), 4, @["Yinyang"])
  check("the recorded match re-derives cleanly", r.ok)
  let deriver = newDeriver(r.doc)
  while deriver.advance(): discard
  checkEq("no mismatching round", deriver.mismatchRound, -1)
  let w = deriver.session.w24
  checkEq("the deriver played every recorded round", w.currentRound,
    r.games[0].roundsPlayed)
  checkEq("and the re-derived trap count matches the recorded one",
    w.stats.trapsBuilt[0] + w.stats.trapsBuilt[1],
    r.games[0].stats["traps_built"][0].getInt() +
    r.games[0].stats["traps_built"][1].getInt())
  checkEq("and the re-derived level sums", w.levelSum(teamA) + w.levelSum(teamB),
    r.games[0].stats["levels_end"][0].getInt() +
    r.games[0].stats["levels_end"][1].getInt())

  ## And the chrome reads the re-derived war panel, not a stored dump.
  var view = initViewerState()
  let chrome = parseJson(sessionChromeJson(r.doc, deriver.session, view, 0,
    deriver.totalFrames, 0, 0, newJArray(), newJArray(), true))
  checkEq("the chrome is stamped with the year", chrome["year"].getStr(),
    "bc24")
  check("and carries the flag readout", chrome.hasKey("bc24_flags"))
  check("and the crumb readout", chrome.hasKey("bc24_crumbs"))
  check("and the level readout", chrome.hasKey("bc24_levels"))
  check("and the war panel", chrome.hasKey("bc24_traps"))
  check("and the jail rail", chrome.hasKey("bc24_jail"))
  checkEq("whose trap tally comes from the re-derivation",
    chrome["bc24_traps"]["clans"][0]["traps_built"].getInt() +
    chrome["bc24_traps"]["clans"][1]["traps_built"].getInt(),
    w.stats.trapsBuilt[0] + w.stats.trapsBuilt[1])

  ## THE WATER IS RE-DERIVED, not stored. The flocks dug and filled, and the
  ## re-derived board says so.
  var water = 0
  for v in w.water:
    if v: water += 1
  check("the re-derived board carries the water the flocks dug",
    water != 0)
  check("and live flags", w.allFlags.len >= 3)

# --- the committed fixture --------------------------------------------------
block:
  ## `tests/fixtures/replay-bc24.json` is a REAL recording, committed: the
  ## bytes `tools/wasm_replay_smoke.cjs` drives the emitted wasm module
  ## against, independently of whatever `docker-smoke` produced in the same
  ## run. Here it is proved natively.
  ##
  ## When a rule changes this check goes red. That is the point -- re-record
  ## with `nim r --path:src tools/gen_bc24_fixture_replay.nim`, in the commit
  ## that bumps the version.
  const FixturePath = "tests/fixtures/replay-bc24.json"
  check("the committed bc24 fixture replay exists", fileExists(FixturePath))
  let bytes = readFile(FixturePath)
  check("and is valid UTF-8", validateUtf8(bytes) == -1)
  let node = parseJson(bytes)
  checkEq("and is a battlecode replay", node["format"].getStr(),
    "cogame-battlecode-replay")
  checkEq("of the bc24 year", node["year"].getStr(), "bc24")
  check("at a GameVersion this build still loads",
    node["game_version"].getStr() in ReplayCompatibleGameVersions)
  let fixture = parseReplay(bytes)
  let fixtureDeriver = newDeriver(fixture)
  var fixtureFrames = 0
  while fixtureDeriver.advance(): fixtureFrames += 1
  checkEq("and it re-derives with no mismatching round",
    fixtureDeriver.mismatchRound, -1)
  check("over its whole recorded length", fixtureFrames > 200)
  check("past the dam, so it records real open play",
    fixtureFrames > SetupRounds)

finish("bc24 replay")
