## The replay document round-trips, the written bytes are STRICT UTF-8, and
## the viewer's re-derivation reproduces the recorded per-round hashes.

import std/[json, strutils, unicode]
import harness
import battlecode/[baselines, broadcast, match, replay, results, sheet, sim_types]
import battlecode/years/bc26/[maps, rules]

proc buildDoc(mapName: string, notes, motto: string): (ReplayDoc, GameOutcome) =
  var sheets = [baselineSheet(blAwu), baselineSheet(blScaffold)]
  sheets[0].notes = notes
  sheets[0].motto = motto
  ## Through the YEAR BOUNDARY, exactly as the server does, so the document
  ## this test round-trips is the document the server writes.
  let (outcome, _) = playGameFor("bc26", mapName, sheets,
    [scBowlOfChowder, scBowlOfChowder], 0, 0, 500, 0)
  var plan = MatchPlan(seed: 4242, year: "bc26", maxRounds: 500,
    maps: @[mapName], sideAslots: @[0], abandonAfter: @[-1], sheets: sheets)
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: ["daveey", "daveey-1"][slot],
      alias: aliasFor(slot), policyKind: "scripted", sheet: sheets[slot],
      decisionMs: 8123)
  var events = @[
    ev("episode_start", ms = 0, fields = %*{"seed": 4242}),
    ev("game_start", game = 0, round = 0, fields = %*{"map": mapName}),
    ev("game_end", game = 0, round = outcome.roundsPlayed, fields = %*{
      "winner_alias": aliasFor(max(0, outcome.winnerSlot)),
      "winner_slot": outcome.winnerSlot,
      "end_reason": outcome.endReason,
      "points": [outcome.points[0], outcome.points[1]]})]
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc26",
    config: %*{"pool": "small", "seed": 4242}, seed: 4242, seats: seats,
    events: events, plan: plan,
    result: resultsJson(seats, @[outcome], plan, epComplete, 1.0, 2.0),
    games: @[GameHeader(index: 0, map: mapName, mapSha: mapSha("bc26", mapName),
      sideAslot: 0, rounds: outcome.roundsPlayed,
      hashChain: outcome.hashChain, roundChains: outcome.roundChains)])
  for slot in 0 .. 1: doc.names[slot] = seats[slot].name
  (doc, outcome)

# --- round trip -------------------------------------------------------------
block:
  let (doc, outcome) = buildDoc("DefaultSmall", "hold the line", "Cheese first.")
  let text = $doc.toJson()
  let back = parseReplay(text)
  checkEq("format survives", back.gameVersion, GameVersion)
  checkEq("year survives", back.year, "bc26")
  checkEq("seed survives", back.seed, 4242)
  checkEq("names survive", back.names[0], "daveey")
  checkEq("the map identity survives", back.games[0].map, "DefaultSmall")
  check("with a sha256 of the committed map", back.games[0].mapSha.len == 64)
  checkEq("the hash chain survives", back.games[0].hashChain, outcome.hashChain)
  checkEq("and one chain per round rides with it",
    back.games[0].roundChains.len, outcome.roundsPlayed * ChainHexLen)
  checkEq("whose last round is the final chain",
    back.games[0].roundChains[^ChainHexLen .. ^1], outcome.hashChain)
  checkEq("both sheets survive", back.seats[0].sheet.doctrine.chassis,
    doc.seats[0].sheet.doctrine.chassis)
  checkEq("notes survive", back.seats[0].sheet.notes, "hold the line")
  checkEq("motto survives", back.seats[0].sheet.motto, "Cheese first.")
  checkEq("events survive", back.events.len, doc.events.len)
  checkEq("the plan survives", back.plan.maps, doc.plan.maps)
  check("the result rides along", back.result.hasKey("scores"))
  ## Serialising the parsed document again must produce the same bytes.
  var again = doc
  again.result = back.result
  checkEq("a second serialisation is identical", $again.toJson(), text)

# --- the observation is IN the replay ---------------------------------------
block:
  ## Decisions are taken server-side, so the "observation" is the prompt
  ## payload the server composed per seat — and the replay records it
  ## verbatim, with the provider's own last words beside the one-word cause.
  ## Neither reached the document before r1-N10.
  var (doc, _) = buildDoc("DefaultSmall", "", "")
  doc.seats[0].brief = """{"protocol":"cogame.battlecode.v1","slot":0,"alias":"Clan Ash"}"""
  doc.seats[0].policyKind = "llm"
  doc.seats[1].fallback = "parse"
  var detail = ""
  for i in 0 ..< 400: detail.add("\u{1F400}")
  doc.seats[1].fallbackDetail = sanitizeLine(detail, MaxFallbackDetailRunes)
  doc.promptPreamble = "You command a clan of robot rats."
  let node = doc.toJson()
  checkEq("the seat's prompt payload is recorded",
    node["seats"][0]["prompt"]["alias"].getStr(), "Clan Ash")
  checkEq("the shared preamble is recorded once",
    node["prompt_preamble"].getStr(), "You command a clan of robot rats.")
  check("a scripted seat records no prompt",
    node["seats"][1]["prompt"].kind == JNull)
  checkEq("the provider's own words ride with the cause",
    node["seats"][1]["fallback_detail"].getStr().runeLen,
    MaxFallbackDetailRunes)
  check("and are still valid UTF-8",
    node["seats"][1]["fallback_detail"].getStr().validateUtf8() < 0)
  let back = parseReplay($node)
  checkEq("the prompt survives a re-parse",
    parseJson(back.seats[0].brief)["slot"].getInt(), 0)
  checkEq("and so does the detail", back.seats[1].fallbackDetail.runeLen,
    MaxFallbackDetailRunes)
  checkEq("and the preamble", back.promptPreamble,
    "You command a clan of robot rats.")

# --- strict UTF-8 -----------------------------------------------------------
block:
  ## Astral-plane text in the notes: the written bytes must parse as STRICT
  ## UTF-8, which is what a byte-truncated codepoint would break.
  var notes = ""
  for i in 0 ..< 400: notes.add("\u{1F400}\u{1F9C0}")
  var motto = ""
  for i in 0 ..< 100: motto.add("\u{1F400}")
  let capped = sanitizeLine(notes, MaxNoteRunes)
  let cappedMotto = sanitizeLine(motto, MaxMottoRunes)
  let (doc, _) = buildDoc("DefaultSmall", capped, cappedMotto)
  let text = $doc.toJson()
  checkEq("the written bytes are valid UTF-8", text.validateUtf8(), -1)
  checkEq("notes are capped in RUNES", doc.seats[0].sheet.notes.runeLen,
    MaxNoteRunes)
  let back = parseReplay(text)
  checkEq("and survive a strict re-parse",
    back.seats[0].sheet.notes.runeLen, MaxNoteRunes)

# --- re-derivation reproduces the recorded hashes ---------------------------
block:
  let (doc, outcome) = buildDoc("closeup", "", "")
  let deriver = newDeriver(parseReplay($doc.toJson()))
  checkEq("one frame per recorded round", deriver.totalFrames,
    outcome.roundsPlayed)
  var frames = 0
  while deriver.advance(): inc frames
  checkEq("the deriver plays every frame", frames, outcome.roundsPlayed)
  checkEq("with no hash mismatch", deriver.mismatchRound, -1)
  checkEq("and the same final cheese", deriver.session.w26.teamInfo.cheeseTransferred,
    [outcome.stats["cheese_transferred"][0].getInt(),
     outcome.stats["cheese_transferred"][1].getInt()])

# --- a mismatching chain is DETECTED, at the round it FIRST diverges --------
block:
  var (doc, _) = buildDoc("DefaultSmall", "", "")
  doc.games[0].hashChain = "DEADBEEFDEADBEEF"
  let deriver = newDeriver(parseReplay($doc.toJson()))
  while deriver.advance(): discard
  check("a corrupted final hash chain is reported", deriver.mismatchRound > 0)

block:
  ## The chain is compared EVERY round, so the round reported is the first
  ## divergent one — not the game's last, which is all a per-game comparison
  ## can ever say.
  var (doc, _) = buildDoc("DefaultSmall", "", "")
  const Corrupt = 40
  let at = (Corrupt - 1) * ChainHexLen
  doc.games[0].roundChains[at ..< at + ChainHexLen] = "DEADBEEFDEADBEEF"
  let deriver = newDeriver(parseReplay($doc.toJson()))
  while deriver.advance(): discard
  checkEq("the FIRST divergent round is the one reported",
    deriver.mismatchRound, Corrupt)

# --- an unknown game_version is refused, not silently re-simulated ----------
block:
  var (doc, _) = buildDoc("DefaultSmall", "", "")
  var node = doc.toJson()
  node["game_version"] = %"GV99"
  var raised = false
  try:
    discard parseReplay($node)
  except CatchableError as error:
    raised = "GV99" in error.msg
  check("an unknown game_version is refused with a readable message", raised)

# --- seeking ----------------------------------------------------------------
block:
  let (doc, outcome) = buildDoc("DefaultSmall", "", "")
  let deriver = newDeriver(parseReplay($doc.toJson()))
  ## Frames are 0-based and round `n` is frame `n - 1`.
  deriver.seek(outcome.roundsPlayed div 2)
  let midway = deriver.session.w26.hashChain
  checkEq("a forward seek lands on the right round",
    deriver.session.w26.currentRound, outcome.roundsPlayed div 2 + 1)
  deriver.seek(10)
  checkEq("a backward seek restarts and replays",
    deriver.session.w26.currentRound, 11)
  deriver.seek(outcome.roundsPlayed div 2)
  checkEq("and returning gives the same world", deriver.session.w26.hashChain,
    midway)

# --- the chrome document ----------------------------------------------------
block:
  let (doc, _) = buildDoc("DefaultSmall", "watch the flank", "Trust, briefly.")
  let back = parseReplay($doc.toJson())
  let deriver = newDeriver(back)
  discard deriver.advance()
  var view = initViewerState()
  let beats = beatsFor(back, proc (g, r: int): int = 0)
  let chrome = parseJson(chromeJson(back, deriver.session.w26, view, 0,
    deriver.totalFrames, 0, 0, beats, newJArray(), false))
  for key in ["t", "st", "mx", "mt", "sp", "pl", "lp", "sk", "ff", "en",
              "ph", "beats"]:
    check("the chrome carries the starter's generic key " & key,
      chrome.hasKey(key))
  for key in ["coop", "bars", "econ", "gamechips", "doctrines", "round",
              "rounds", "map", "aliases", "names", "points"]:
    check("the chrome carries the battlecode key " & key, chrome.hasKey(key))
  checkEq("aliases are the in-game ones", chrome["aliases"][0].getStr(), AliasA)
  checkEq("names are the spectator-side ones", chrome["names"][0].getStr(),
    "daveey")
  checkEq("the doctrine reads in plain words",
    chrome["doctrines"][0]["words"].len > 0, true)
  checkEq("the chrome is valid UTF-8", ($chrome).validateUtf8(), -1)

# --- the transport vocabulary ----------------------------------------------
block:
  var view = initViewerState()
  check("playback starts playing", view.playing)
  view.applyCommand(100, " ")
  check("space pauses", not view.playing)
  view.applyCommand(100, "4")
  checkEq("a speed chip sets the speed", view.speed, 4)
  view.applyCommand(100, "6")
  checkEq("6 is 16x", view.speed, 16)
  view.applyCommand(100, "r")
  check("r toggles loop", view.loop)
  view.applyCommand(100, "s:0.5")
  checkEq("a scrub seeks by fraction", view.seekFrame, 49)
  view.applyCommand(100, "e")
  checkEq("e jumps to the end", view.seekFrame, 99)
  view.applyCommand(100, "\x01\x02")
  check("an unknown command is ignored", view.speed == 16)

finish("test_replay")
