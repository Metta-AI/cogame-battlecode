## The doctrine sheet: every knob's default, out-of-range and mistyped path;
## unknown keys recorded and ignored; and RUNE-boundary truncation of
## `notes`/`motto` including astral-plane characters.

import std/[json, os, strutils, unicode]
import harness
import battlecode/[baselines, decide, match, sheet, sim_types]

# --- defaults ---------------------------------------------------------------
block:
  let s = validate(parseJson("""{"sheet":{}}"""))
  let d = defaultDoctrine()
  checkEq("chassis default", s.doctrine.chassis, d.chassis)
  checkEq("and the default chassis is awu", d.chassis, chAwu)
  checkEq("backstab_policy default", s.doctrine.backstabPolicy, d.backstabPolicy)
  checkEq("backstab_round default", s.doctrine.backstabRound, d.backstabRound)
  checkEq("cat_engagement default", s.doctrine.catEngagement, d.catEngagement)
  checkEq("cat_trap_budget default", s.doctrine.catTrapBudget, d.catTrapBudget)
  checkEq("rat_trap_budget default", s.doctrine.ratTrapBudget, d.ratTrapBudget)
  checkEq("spawn_curve default", s.doctrine.spawnCurve, d.spawnCurve)
  checkEq("cheese_ferry_ratio default", s.doctrine.cheeseFerryRatio,
    d.cheeseFerryRatio)
  checkEq("king_count_target default", s.doctrine.kingCountTarget,
    d.kingCountTarget)
  checkEq("dirt_wall_policy default", s.doctrine.dirtWallPolicy, d.dirtWallPolicy)
  checkEq("throw_rats_to_feed_cats default", s.doctrine.throwRatsToFeedCats,
    d.throwRatsToFeedCats)
  checkEq("nothing was repaired", s.defaultsApplied.len, 0)

# --- every knob accepts its own values --------------------------------------
block:
  let s = parseReply("""
    {"sheet":{"backstab_policy":"at_round_N",
              "backstab_round":700,"cat_engagement":"hunt",
              "cat_trap_budget":60,"rat_trap_budget":80,"spawn_curve":"swarm",
              "cheese_ferry_ratio":0.4,"king_count_target":4,
              "dirt_wall_policy":"choke","throw_rats_to_feed_cats":true},
     "notes":"Farm cats to 700, then take their kings.",
     "motto":"Trust, briefly."}""")
  checkEq("backstab_policy", s.doctrine.backstabPolicy, bpAtRoundN)
  checkEq("backstab_round", s.doctrine.backstabRound, 700)
  checkEq("cat_engagement", s.doctrine.catEngagement, ceHunt)
  checkEq("cat_trap_budget", s.doctrine.catTrapBudget, 60)
  checkEq("rat_trap_budget", s.doctrine.ratTrapBudget, 80)
  checkEq("spawn_curve", s.doctrine.spawnCurve, scSwarm)
  checkEq("cheese_ferry_ratio", s.doctrine.cheeseFerryRatio, 0.4)
  checkEq("king_count_target", s.doctrine.kingCountTarget, 4)
  checkEq("dirt_wall_policy", s.doctrine.dirtWallPolicy, dwChoke)
  checkEq("throw_rats_to_feed_cats", s.doctrine.throwRatsToFeedCats, true)
  checkEq("nothing was repaired", s.defaultsApplied.len, 0)
  checkEq("notes survive", s.notes, "Farm cats to 700, then take their kings.")
  checkEq("motto survives", s.motto, "Trust, briefly.")

# --- out of range -----------------------------------------------------------
block:
  let s = parseReply("""
    {"sheet":{"backstab_round":9999,"cat_trap_budget":-5,
              "rat_trap_budget":100000,"cheese_ferry_ratio":3.5,
              "king_count_target":0}}""")
  let d = defaultDoctrine()
  checkEq("out-of-range backstab_round takes the default",
    s.doctrine.backstabRound, d.backstabRound)
  checkEq("negative cat_trap_budget takes the default",
    s.doctrine.catTrapBudget, d.catTrapBudget)
  checkEq("huge rat_trap_budget takes the default",
    s.doctrine.ratTrapBudget, d.ratTrapBudget)
  checkEq("out-of-range ratio takes the default",
    s.doctrine.cheeseFerryRatio, d.cheeseFerryRatio)
  checkEq("king_count_target below 1 takes the default",
    s.doctrine.kingCountTarget, d.kingCountTarget)
  checkEq("all five repairs are recorded", s.defaultsApplied.len, 5)

# --- mistyped ---------------------------------------------------------------
block:
  let s = parseReply("""
    {"sheet":{"backstab_policy":["never"],
              "cat_engagement":null,"spawn_curve":{"a":1},
              "dirt_wall_policy":7,"cat_trap_budget":"not a number",
              "throw_rats_to_feed_cats":"maybe"}}""")
  let d = defaultDoctrine()
  checkEq("an array policy takes the default", s.doctrine.backstabPolicy,
    d.backstabPolicy)
  checkEq("a null engagement takes the default", s.doctrine.catEngagement,
    d.catEngagement)
  checkEq("an object curve takes the default", s.doctrine.spawnCurve,
    d.spawnCurve)
  checkEq("a numeric dirt policy takes the default", s.doctrine.dirtWallPolicy,
    d.dirtWallPolicy)
  checkEq("an unparseable budget takes the default", s.doctrine.catTrapBudget,
    d.catTrapBudget)
  checkEq("an unparseable bool takes the default",
    s.doctrine.throwRatsToFeedCats, d.throwRatsToFeedCats)
  check("every repair is recorded", s.defaultsApplied.len >= 6)

# --- tolerant spellings -----------------------------------------------------
block:
  let s = parseReply("""
    {"sheet":{"backstab_policy":" On-First Contact ","spawn_curve":"SWARM",
              "cat_trap_budget":"60","cheese_ferry_ratio":"0.25",
              "throw_rats_to_feed_cats":"yes"}}""")
  checkEq("hyphens and case normalise", s.doctrine.backstabPolicy,
    bpOnFirstContact)
  checkEq("upper case normalises", s.doctrine.spawnCurve, scSwarm)
  checkEq("a numeric string parses", s.doctrine.catTrapBudget, 60)
  checkEq("a float string parses", s.doctrine.cheeseFerryRatio, 0.25)
  checkEq("yes is true", s.doctrine.throwRatsToFeedCats, true)
  checkEq("nothing was repaired", s.defaultsApplied.len, 0)

# --- unknown keys -----------------------------------------------------------
block:
  let s = parseReply("""
    {"sheet":{"swarm_mode":true,"secret_weapon":"laser",
              "cat_engagement":"hunt"}}""")
  checkEq("known keys still apply", s.doctrine.catEngagement, ceHunt)
  checkEq("two unknown keys are recorded", s.unknownFields.len, 2)
  check("by name", "swarm_mode" in s.unknownFields)
  checkEq("and nothing was repaired", s.defaultsApplied.len, 0)

# --- `chassis` is NOT a knob (r2-D1) ----------------------------------------
block:
  ## The round-1 champion answered `{"chassis":"scaffold"}` and idled three
  ## games on the move-or-turn-only bot. `chassis` is not on the LLM knob
  ## surface at all now: the key is recorded as unknown, ignored, and the clan
  ## runs `awu` whatever the reply says.
  check("chassis is not a known key", "chassis" notin KnownKeys)
  let s = parseReply("""{"sheet":{"chassis":"scaffold","cat_engagement":"hunt"}}""")
  checkEq("an LLM reply naming a chassis still runs awu", s.doctrine.chassis,
    chAwu)
  check("and the key is recorded as unknown", "chassis" in s.unknownFields)
  checkEq("it is not counted as a repaired knob", s.defaultsApplied.len, 0)
  checkEq("and the rest of the sheet still applies", s.doctrine.catEngagement,
    ceHunt)
  ## Not even the spelling the preamble used to print.
  let awuReply = parseReply("""{"sheet":{"chassis":"awu"}}""")
  check("`chassis: awu` is unknown too", "chassis" in awuReply.unknownFields)
  ## The prompt no longer offers it.
  check("the preamble does not list a chassis knob",
    "\n  chassis " notin SystemPreamble)
  check("and says so in words", "not yours to choose" in SystemPreamble)

block:
  ## At most MaxUnknownFields keys are kept, each at most
  ## MaxUnknownFieldRunes long.
  var body = """{"sheet":{"""
  for i in 0 ..< 40:
    if i > 0: body.add(",")
    body.add("\"unknown_" & $i & "\":1")
  body.add("}}")
  let s = parseReply(body)
  check("the unknown list is capped", s.unknownFields.len <= MaxUnknownFields)

# --- fence tolerance and prose ----------------------------------------------
block:
  let s = parseReply("""
Here is my doctrine:
```json
{"sheet":{"cat_engagement":"hunt"},"notes":"hunt them"}
```
Good luck!""")
  checkEq("a fenced reply parses", s.doctrine.catEngagement, ceHunt)
  checkEq("with its notes", s.notes, "hunt them")

block:
  ## The prefilled `{` case: llm.nim re-attaches the prefix, so the parser
  ## sees a whole object.
  let s = parseReply("""{"sheet":{"king_count_target":5}}""")
  checkEq("a prefilled reply parses", s.doctrine.kingCountTarget, 5)

block:
  var raised = false
  try:
    discard parseReply("I refuse to answer.")
  except CatchableError:
    raised = true
  check("a reply with no JSON object raises", raised)

# --- rune truncation --------------------------------------------------------
block:
  ## Astral-plane characters are 4 BYTES and 1 RUNE each. Slicing by byte
  ## index would cut one in half and produce a document that renders fine in
  ## a browser and then fails a strict UTF-8 parser.
  let rat = "\u{1F400}"                      ## U+1F400 RAT
  checkEq("the rat is one rune", rat.runeLen, 1)
  checkEq("and four bytes", rat.len, 4)
  var longNotes = ""
  for i in 0 ..< 400: longNotes.add(rat)
  var longMotto = ""
  for i in 0 ..< 200: longMotto.add(rat)
  let s = validate(%*{"sheet": {}, "notes": longNotes, "motto": longMotto})
  checkEq("notes are capped at MaxNoteRunes", s.notes.runeLen, MaxNoteRunes)
  checkEq("motto is capped at MaxMottoRunes", s.motto.runeLen, MaxMottoRunes)
  checkEq("and the cut lands on a rune boundary", s.notes.len,
    MaxNoteRunes * 4)
  check("the truncated text is still valid UTF-8", s.notes.validateUtf8() < 0)
  check("and so is the motto", s.motto.validateUtf8() < 0)

block:
  ## Newlines collapse so one record stays one line.
  let s = validate(%*{"sheet": {}, "notes": "line one\nline two\r\nthree"})
  check("no newline survives in notes", '\n' notin s.notes)
  check("nor a carriage return", '\r' notin s.notes)

# --- the whole-reply cap is BYTES, cut on a rune boundary -------------------
block:
  ## r1-N14: `if text.len > MaxReplyBytes: text.truncateRunes(MaxReplyBytes)`
  ## measured the cap in bytes and then kept that many RUNES, so a reply of
  ## astral-plane text survived at four times the 16 KB cap.
  var astral = ""
  for i in 0 ..< 10_000: astral.add("\u{1F400}")          # 4 bytes each, 40 KB
  check("the sample really is over the cap", astral.len > MaxReplyBytes)
  let cut = astral.truncateBytes(MaxReplyBytes)
  check("the cut is at most MaxReplyBytes BYTES", cut.len <= MaxReplyBytes)
  check("and as close to it as a whole rune allows",
    cut.len > MaxReplyBytes - 4)
  check("and still valid UTF-8", cut.validateUtf8() < 0)
  checkEq("a short reply is untouched", "hello".truncateBytes(MaxReplyBytes),
    "hello")
  ## And end to end: the object at the front of an over-long reply is still
  ## parsed, and the padding past the cap is gone.
  var padded = """{"sheet":{"king_count_target":5}}"""
  while padded.len < MaxReplyBytes * 2: padded.add("\u{1F400}")
  let s = parseReply(padded)
  checkEq("an over-long reply still yields its sheet",
    s.doctrine.kingCountTarget, 5)
  ## And the cap really bites: 32 KB of astral text INSIDE the object is cut
  ## mid-object, so the reply cannot be parsed and the seat retries — which is
  ## what a 16 KB cap means. Under the rune-based cut this reply came through
  ## whole, at four times the cap.
  var notes = ""
  for i in 0 ..< 8_000: notes.add("\u{1F400}")
  let overCap = "{\"sheet\":{\"king_count_target\":5},\"notes\":\"" & notes & "\"}"
  check("the over-cap reply is over the cap", overCap.len > MaxReplyBytes)
  var raised = false
  try:
    discard parseReply(overCap)
  except CatchableError:
    raised = true
  check("a reply whose object runs past the byte cap does not parse", raised)

# --- round trip -------------------------------------------------------------
block:
  var s = parseReply("""{"sheet":{"king_count_target":5}}""")
  s.doctrine.chassis = chScaffold          ## as the filler path sets it
  let again = validate(%*{"sheet": s.toJson()})
  checkEq("and keeps its numbers", again.doctrine.kingCountTarget,
    s.doctrine.kingCountTarget)
  checkEq("the applied chassis rides in the recorded sheet",
    parseChassis(s.toJson(){"chassis"}.getStr()), chScaffold)
  check("plain words describe every sheet", s.plainWords().len >= 6)

# --- the decision layer records ONE fallback per seat, naming its cause -----
block:
  ## A provider that cannot be reached at all (a closed local port -- no
  ## network is touched): attempt 1 fails, and by the time the retry is
  ## considered the 1 ms phase budget is spent. Whichever of the two paths
  ## fires, the invariant is the same and it is what N3 broke: EXACTLY ONE
  ## `doctrine_fallback` per seat, and the cause the seat keeps is the cause
  ## the event names. Leaving the budget-timeout seats in `open` recorded a
  ## second event for the same seat and left "parse" in `results`/the replay
  ## for what was really a timeout.
  putEnv("AWS_ENDPOINT_URL_BEDROCK_RUNTIME", "http://127.0.0.1:1")
  putEnv("AWS_BEARER_TOKEN_BEDROCK", "test-not-a-real-token")
  var config = defaultGameConfig()
  config.pool = "small"
  config.gamesPerMatch = 1
  config.attempt1Ms = 1000
  config.retryMs = 1000
  config.doctrineBudgetMs = 1
  let sheets = [baselineSheet(blAwu), baselineSheet(blScaffold)]
  let plan = buildPlan(config, sheets, 11)
  var seats: array[2, SeatPolicy]
  for slot in 0 .. 1:
    seats[slot] = SeatPolicy(isLlm: true, prompt: "doctrine, please",
      registered: true)
  let decision = decide(config, plan, seats)
  delEnv("AWS_ENDPOINT_URL_BEDROCK_RUNTIME")
  delEnv("AWS_BEARER_TOKEN_BEDROCK")
  for slot in 0 .. 1:
    var causes: seq[string]
    for e in decision.events:
      if e.kind == "doctrine_fallback" and e.fields{"slot"}.getInt(-1) == slot:
        causes.add(e.fields{"cause"}.getStr())
    checkEq("seat " & $slot & " records exactly one doctrine_fallback",
      causes.len, 1)
    if causes.len == 1:
      checkEq("and the cause it keeps is the cause the event names",
        decision.fallback[slot], causes[0])
    check("and the seat still has a legal doctrine",
      decision.sheets[slot].plainWords().len >= 6)
    ## r1-N10: the observation and the provider's own words are kept, so the
    ## replay can record them.
    check("the composed prompt payload is kept",
      decision.briefs[slot].contains("opponent_alias"))
    check("and the provider's own words, within the 200-rune cap",
      decision.fallbackDetail[slot].len > 0 and
      decision.fallbackDetail[slot].runeLen <= MaxFallbackDetailRunes)

# --- THE YEAR-NEUTRAL ENVELOPE RESOLVER, from the other side ----------------
block:
  ## LEARNINGS 2026-09-08 changed ONE shared thing: `validate` now resolves a
  ## `doctrine` key and a single object-valued key as well as `sheet`. This
  ## block is the proof that the change is ADDITIVE for the six shipped years:
  ## every vector below parses to exactly the `Sheet` it parsed to before, and
  ## `Sheet.envelope` records which rule fired.
  for year in [YearBc26, YearBc20, YearBc21, YearBc24, YearBc25, YearBc23]:
    let bare = validate(parseJson("""{}"""), year)
    checkEq(year & ": an empty payload reports no envelope", bare.envelope, "")
    checkEq("and — unlike bc22 — records NOTHING defaulted",
      bare.defaultsApplied.len, 0)
    let sheeted = validate(parseJson("""{"sheet":{}}"""), year)
    checkEq(year & ": a `sheet` envelope is recorded as such",
      sheeted.envelope, "sheet")
    checkEq("and still records nothing defaulted",
      sheeted.defaultsApplied.len, 0)
    let doctrine = validate(parseJson("""{"doctrine":{}}"""), year)
    checkEq(year & ": a `doctrine` envelope is NOW unwrapped too",
      doctrine.envelope, "doctrine")
    let named = validate(parseJson("""{"my_wrapper":{}}"""), year)
    checkEq(year & ": and a single object-valued key", named.envelope,
      "my_wrapper")
    let two = validate(parseJson("""{"a":{},"b":{}}"""), year)
    checkEq(year & ": two object-valued keys is ambiguous, so no unwrap",
      two.envelope, "")

block:
  ## And the six shipped years' OWN knob vectors still parse to the same
  ## doctrine they did before the change.
  let bc26sheet = parseReply(
    """{"sheet":{"cat_engagement":"hunt","king_count_target":5}}""")
  checkEq("bc26's knobs still apply through a `sheet` envelope",
    bc26sheet.doctrine.kingCountTarget, 5)
  checkEq("and the envelope is recorded", bc26sheet.envelope, "sheet")
  let flat = parseReply("""{"king_count_target":4}""")
  checkEq("a BARE FLAT bc26 sheet needs no envelope", flat.envelope, "")
  checkEq("and its knobs apply", flat.doctrine.kingCountTarget, 4)
  let bc23sheet = parseReply(
    """{"protocol":"x","doctrine":{"launcher_ratio":70}}""", YearBc23)
  checkEq("and the protocol envelope that lost two bc23 league rounds is " &
    "now unwrapped FOR BC23 TOO", bc23sheet.doctrine23.launcherRatio, 70)
  checkEq("with the rule recorded", bc23sheet.envelope, "doctrine")

block:
  ## The one thing the change must NOT do: alter what a shipped year records
  ## in `sheet_defaults_applied`. bc22 counts absent keys; nobody else does.
  let bc22empty = parseReply("""{"sheet":{}}""", YearBc22)
  checkEq("bc22 records all eleven of its knobs as defaulted",
    bc22empty.defaultsApplied.len, 11)
  ## bc16 is the SECOND year to count absent keys, and it is the only other
  ## one: doing it year-neutrally would change what a bc20/bc21/bc23/bc24/
  ## bc25/bc26 episode records in that array.
  let bc16empty = parseReply("""{"sheet":{}}""", YearBc16)
  checkEq("and bc16 records all eleven of ITS knobs as defaulted",
    bc16empty.defaultsApplied.len, 11)
  for year in [YearBc26, YearBc20, YearBc21, YearBc24, YearBc25, YearBc23]:
    let empty = parseReply("""{"sheet":{}}""", year)
    checkEq(year & " still records NONE", empty.defaultsApplied.len, 0)

block:
  ## THE YEAR-NEUTRAL SIDE OF THE ENVELOPE RESOLVER, FROM bc19 (§Tests item
  ## 15). The bc19 run is provably ADDITIVE for the EIGHT already-shipped
  ## years: every vector above still parses to the `Sheet` it did before, and
  ## bc19 goes through the SAME resolver with no year-neutral change at all.
  ## The bc19 SIDE of the same resolver is `tests/test_bc19_sheet.nim`; what
  ## belongs here is the year-neutral half.
  let bc19 = parseReply(
    """{"protocol":"x","doctrine":{"unit_mix":70}}""", YearBc19)
  checkEq("a bc19 sheet inside a protocol envelope is unwrapped",
    bc19.doctrine19.unitMix, 70)
  checkEq("with the rule recorded", bc19.envelope, "doctrine")
  let bc19flat = parseReply("""{"unit_mix":70}""", YearBc19)
  checkEq("a BARE FLAT bc19 sheet needs no envelope", bc19flat.envelope, "")
  checkEq("and its knobs apply", bc19flat.doctrine19.unitMix, 70)
  let bc19named = parseReply(
    """{"battlecode_2019_doctrine":{"unit_mix":70}}""", YearBc19)
  checkEq("and a single object-valued key is unwrapped for bc19 too",
    bc19named.doctrine19.unitMix, 70)
  checkEq("with the key recorded", bc19named.envelope,
    "battlecode_2019_doctrine")
  checkEq("knownKeysFor routes bc19 to its own eleven",
    knownKeysFor(YearBc19).len, 11)
  check("and `chassis` is not one of them (D1)",
    "chassis" notin knownKeysFor(YearBc19))
  ## bc19 is the THIRD year to count absent keys as defaulted, beside bc22
  ## and bc16 — and it must not change what any other year records.
  let bc19empty = parseReply("""{"sheet":{}}""", YearBc19)
  checkEq("bc19 records all eleven of ITS knobs as defaulted",
    bc19empty.defaultsApplied.len, 11)
  ## And a bc19 payload parsed AS ANOTHER YEAR leaves that year's doctrine at
  ## its own defaults rather than bleeding across, in both directions.
  let bc19AsBc22 = parseReply("""{"unit_mix":70}""", YearBc22)
  checkEq("a bc19 knob name means nothing to bc22",
    bc19AsBc22.doctrine22, parseReply("{}", YearBc22).doctrine22)
  let bc16AsBc19 = parseReply("""{"turret_count":9}""", YearBc19)
  checkEq("and a bc16 knob name means nothing to bc19",
    bc16AsBc19.doctrine19, parseReply("{}", YearBc19).doctrine19)
  ## The whole resolver ladder, for bc19, in one pass — so this year cannot
  ## be the one that quietly diverges from the shared rule.
  for (payload, envelope) in [
      ("""{}""", ""),
      ("""{"sheet":{"unit_mix":70}}""", "sheet"),
      ("""{"doctrine":{"unit_mix":70}}""", "doctrine"),
      ("""{"protocol":"x","doctrine":{"unit_mix":70}}""", "doctrine"),
      ("""{"my_wrapper":{"unit_mix":70}}""", "my_wrapper"),
      ("""{"unit_mix":70}""", ""),
      ("""{"a":{},"b":{}}""", "")]:
    checkEq("bc19 envelope for " & payload,
      validate(parseJson(payload), YearBc19).envelope, envelope)

block:
  ## THE YEAR-NEUTRAL SIDE OF THE ENVELOPE RESOLVER, FROM bc16. This run is
  ## provably ADDITIVE for the seven shipped years: every existing vector
  ## above still parses to the same `Sheet` it did before, and bc16 goes
  ## through the SAME resolver with no year-neutral change at all.
  let bc16 = parseReply(
    """{"protocol":"x","doctrine":{"turret_count":9}}""", YearBc16)
  checkEq("a bc16 sheet inside a protocol envelope is unwrapped",
    bc16.doctrine16.turretCount, 9)
  checkEq("with the rule recorded", bc16.envelope, "doctrine")
  let bc16flat = parseReply("""{"turret_count":9}""", YearBc16)
  checkEq("a BARE FLAT bc16 sheet needs no envelope", bc16flat.envelope, "")
  checkEq("and its knobs apply", bc16flat.doctrine16.turretCount, 9)
  checkEq("knownKeysFor routes bc16 to its own eleven",
    knownKeysFor(YearBc16).len, 11)
  check("and `chassis` is not one of them (D1)",
    "chassis" notin knownKeysFor(YearBc16))
  ## And a bc16 payload parsed AS ANOTHER YEAR leaves that year's doctrine at
  ## its own defaults rather than bleeding across.
  let asBc22 = parseReply("""{"turret_count":9}""", YearBc22)
  checkEq("a bc16 knob name means nothing to bc22",
    asBc22.doctrine22, parseReply("{}", YearBc22).doctrine22)

finish("test_sheet")
