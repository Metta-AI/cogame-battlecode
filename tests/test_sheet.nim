## The doctrine sheet: every knob's default, out-of-range and mistyped path;
## unknown keys recorded and ignored; and RUNE-boundary truncation of
## `notes`/`motto` including astral-plane characters.

import std/[json, unicode]
import harness
import battlecode/[sheet, sim_types]

# --- defaults ---------------------------------------------------------------
block:
  let s = validate(parseJson("""{"sheet":{}}"""))
  let d = defaultDoctrine()
  checkEq("chassis default", s.doctrine.chassis, d.chassis)
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
    {"sheet":{"chassis":"scaffold","backstab_policy":"at_round_N",
              "backstab_round":700,"cat_engagement":"hunt",
              "cat_trap_budget":60,"rat_trap_budget":80,"spawn_curve":"swarm",
              "cheese_ferry_ratio":0.4,"king_count_target":4,
              "dirt_wall_policy":"choke","throw_rats_to_feed_cats":true},
     "notes":"Farm cats to 700, then take their kings.",
     "motto":"Trust, briefly."}""")
  checkEq("chassis", s.doctrine.chassis, chScaffold)
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
    {"sheet":{"chassis":42,"backstab_policy":["never"],
              "cat_engagement":null,"spawn_curve":{"a":1},
              "dirt_wall_policy":7,"cat_trap_budget":"not a number",
              "throw_rats_to_feed_cats":"maybe"}}""")
  let d = defaultDoctrine()
  checkEq("a numeric chassis takes the default", s.doctrine.chassis, d.chassis)
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
  check("every repair is recorded", s.defaultsApplied.len >= 7)

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
    {"sheet":{"chassis":"awu","swarm_mode":true,"secret_weapon":"laser",
              "cat_engagement":"hunt"}}""")
  checkEq("known keys still apply", s.doctrine.catEngagement, ceHunt)
  checkEq("two unknown keys are recorded", s.unknownFields.len, 2)
  check("by name", "swarm_mode" in s.unknownFields)
  checkEq("and nothing was repaired", s.defaultsApplied.len, 0)

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

# --- round trip -------------------------------------------------------------
block:
  let s = parseReply("""{"sheet":{"chassis":"scaffold","king_count_target":5}}""")
  let again = validate(%*{"sheet": s.toJson()})
  checkEq("a sheet round-trips through its own JSON",
    again.doctrine.chassis, s.doctrine.chassis)
  checkEq("and keeps its numbers", again.doctrine.kingCountTarget,
    s.doctrine.kingCountTarget)
  check("plain words describe every sheet", s.plainWords().len >= 6)

finish("test_sheet")
