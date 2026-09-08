## bc23's twelve knobs through the SAME `validate` the LLM path uses: absent
## -> default, mistyped -> default + recorded, unknown enum value -> default +
## recorded; THE FOUR INTEGER KNOBS CLAMP to their range rather than
## defaulting (and a non-integer defaults); enum values case-folded and
## trimmed; unknown keys recorded and capped; A SUBMITTED `chassis` RECORDED
## AND NEVER HONOURED (the D1 assertion); rune-boundary truncation including
## astral-plane characters; and the 16 KB BYTE cap cut on a rune boundary.

import std/[json, strutils, unicode]
import harness
import bc23_fixture

proc sheetOf(text: string): Sheet = parseReply(text, "bc23")

# --- absent -> default ----------------------------------------------------
block:
  let s = sheetOf("""{"sheet":{}}""")
  let d = defaultDoctrine23()
  checkEq("opening", s.doctrine23.opening, d.opening)
  checkEq("launcher_ratio", s.doctrine23.launcherRatio, d.launcherRatio)
  checkEq("well_priority", s.doctrine23.wellPriority, d.wellPriority)
  checkEq("elixir_tech", s.doctrine23.elixirTech, d.elixirTech)
  checkEq("elixir_spend", s.doctrine23.elixirSpend, d.elixirSpend)
  checkEq("anchor_round", s.doctrine23.anchorRound, d.anchorRound)
  checkEq("anchor_budget", s.doctrine23.anchorBudget, d.anchorBudget)
  checkEq("island_priority", s.doctrine23.islandPriority, d.islandPriority)
  checkEq("amplifier_use", s.doctrine23.amplifierUse, d.amplifierUse)
  checkEq("destabilizer_use", s.doctrine23.destabilizerUse,
    d.destabilizerUse)
  checkEq("retreat_on_launcher_loss", s.doctrine23.retreatOnLauncherLoss,
    d.retreatOnLauncherLoss)
  checkEq("carrier_throw", s.doctrine23.carrierThrow, d.carrierThrow)
  checkEq("nothing was repaired", s.defaultsApplied.len, 0)
  checkEq("and nothing was unknown", s.unknownFields.len, 0)
  checkEq("exactly twelve knobs", KnownKeys23.len, 12)
  check("and `chassis` is NOT one of them", "chassis" notin KnownKeys23)

# --- the defaults are the note's fallback sheet, verbatim ----------------
block:
  let d = defaultDoctrine23()
  checkEq("opening", $d.opening, "balanced")
  checkEq("launcher_ratio", d.launcherRatio, 45)
  checkEq("well_priority", $d.wellPriority, "balanced")
  checkEq("elixir_tech", $d.elixirTech, "mid")
  checkEq("elixir_spend", $d.elixirSpend, "accelerating_anchors")
  checkEq("anchor_round", d.anchorRound, 400)
  checkEq("anchor_budget", d.anchorBudget, 35)
  checkEq("island_priority", $d.islandPriority, "nearest")
  checkEq("amplifier_use", $d.amplifierUse, "one")
  checkEq("destabilizer_use", $d.destabilizerUse, "defend")
  checkEq("retreat_on_launcher_loss", $d.retreatOnLauncherLoss, "regroup")
  checkEq("carrier_throw", d.carrierThrow, 25)

# --- the four integer knobs CLAMP ---------------------------------------
block:
  for (key, lo, hi) in [("launcher_ratio", 20, 80),
                        ("anchor_round", 1, 1800),
                        ("anchor_budget", 0, 100),
                        ("carrier_throw", 0, 100)]:
    let under = sheetOf("""{"sheet":{"""" & key & """":""" & $(lo - 5) & "}}")
    checkEq(key & " under the floor is CLAMPED, not defaulted, and recorded",
      under.defaultsApplied, @[key])
    let over = sheetOf("""{"sheet":{"""" & key & """":""" & $(hi + 5) & "}}")
    checkEq(key & " over the ceiling is recorded too", over.defaultsApplied,
      @[key])
  let lowRatio = sheetOf("""{"sheet":{"launcher_ratio":0}}""")
  checkEq("launcher_ratio 0 clamps UP to 20 — no doctrine can say " &
    "'no launchers'", lowRatio.doctrine23.launcherRatio, 20)
  let highRatio = sheetOf("""{"sheet":{"launcher_ratio":999}}""")
  checkEq("and 999 clamps DOWN to 80 — the carrier floor is unconditional",
    highRatio.doctrine23.launcherRatio, 80)
  let earlyAnchor = sheetOf("""{"sheet":{"anchor_round":0}}""")
  checkEq("anchor_round 0 clamps to 1", earlyAnchor.doctrine23.anchorRound, 1)
  let lateAnchor = sheetOf("""{"sheet":{"anchor_round":9999}}""")
  checkEq("and 9999 clamps to 1800", lateAnchor.doctrine23.anchorRound, 1800)
  let noAnchors = sheetOf("""{"sheet":{"anchor_budget":0}}""")
  checkEq("anchor_budget 0 is IN RANGE and is a real strategy",
    noAnchors.doctrine23.anchorBudget, 0)
  checkEq("so nothing is recorded", noAnchors.defaultsApplied.len, 0)

block:
  ## A NON-INTEGER takes the default.
  let s = sheetOf("""{"sheet":{"anchor_round":"soon"}}""")
  checkEq("a string anchor_round takes the default 400",
    s.doctrine23.anchorRound, 400)
  checkEq("and is recorded", s.defaultsApplied, @["anchor_round"])
  let t = sheetOf("""{"sheet":{"carrier_throw":{"a":1}}}""")
  checkEq("and so does an OBJECT carrier_throw", t.doctrine23.carrierThrow, 25)
  checkEq("recorded", t.defaultsApplied, @["carrier_throw"])
  ## A NUMERIC STRING is accepted, the same tolerance every other year has:
  ## a model that writes "35" has answered the question.
  let str = sheetOf("""{"sheet":{"carrier_throw":"35"}}""")
  checkEq("a numeric string is read", str.doctrine23.carrierThrow, 35)

# --- every enum knob ------------------------------------------------------
block:
  for (key, value) in [("opening", "launcher_rush"),
                       ("well_priority", "mana"),
                       ("elixir_tech", "early"),
                       ("elixir_spend", "boosters"),
                       ("island_priority", "safe"),
                       ("amplifier_use", "escort"),
                       ("destabilizer_use", "siege"),
                       ("retreat_on_launcher_loss", "home")]:
    let good = sheetOf("""{"sheet":{"""" & key & """":"""" & value & """"}}""")
    checkEq(key & " accepts a listed value", good.defaultsApplied.len, 0)
    let bad = sheetOf("""{"sheet":{"""" & key & """":"nonsense"}}""")
    checkEq(key & " refuses an unknown value and records it",
      bad.defaultsApplied, @[key])
    let typed = sheetOf("""{"sheet":{"""" & key & """":7}}""")
    checkEq(key & " refuses a number and records it", typed.defaultsApplied,
      @[key])

block:
  ## Case-folded and trimmed.
  let s = sheetOf("""{"sheet":{"opening":"  LAUNCHER_RUSH  ",
                               "Well_Priority":"MANA"}}""")
  checkEq("an upper-case, padded enum value is accepted",
    $s.doctrine23.opening, "launcher_rush")
  checkEq("and the KEY is normalised too", $s.doctrine23.wellPriority, "mana")
  checkEq("nothing was repaired", s.defaultsApplied.len, 0)

block:
  ## `well_priority: elixir` is deliberately NOT a value.
  let s = sheetOf("""{"sheet":{"well_priority":"elixir"}}""")
  checkEq("`elixir` is refused as a well priority", $s.doctrine23.wellPriority,
    "balanced")
  checkEq("and recorded", s.defaultsApplied, @["well_priority"])

# --- D1: a submitted `chassis` is recorded and NEVER honoured -------------
block:
  let s = sheetOf("""{"sheet":{"chassis":"examplefuncsplayer23",
                               "opening":"carrier_eco"}}""")
  check("`chassis` lands in the unknown fields", "chassis" in s.unknownFields)
  checkEq("the rest of the sheet still applies", $s.doctrine23.opening,
    "carrier_eco")
  checkEq("and nothing was defaulted", s.defaultsApplied.len, 0)
  check("`chassis` is not a knob at all", "chassis" notin knownKeysFor("bc23"))

# --- unknown keys are recorded and capped --------------------------------
block:
  var parts: seq[string]
  for i in 0 ..< 30:
    parts.add("\"k" & $i & "\":1")
  let s = sheetOf("{\"sheet\":{" & parts.join(",") & "}}")
  check("unknown keys are capped at 16", s.unknownFields.len <= 16)
  for f in s.unknownFields:
    check("and each is capped at 40 runes", f.runeLen <= 40)

block:
  let long = "x".repeat(120)
  let s = sheetOf("{\"sheet\":{\"" & long & "\":1}}")
  checkEq("a very long unknown key is truncated to 40 runes",
    s.unknownFields[0].runeLen, 40)

# --- rune-boundary truncation, including astral-plane text ---------------
block:
  let astral = "\u{1F680}".repeat(400)
  let s = sheetOf("{\"sheet\":{},\"notes\":\"" & astral & "\"}")
  checkEq("notes is 280 RUNES", s.notes.runeLen, 280)
  checkEq("and every rune survives whole", s.notes.len, 280 * 4)
  check("the string is valid UTF-8", s.notes.validateUtf8() == -1)
  let m = sheetOf("{\"sheet\":{},\"motto\":\"" & astral & "\"}")
  checkEq("motto is 48 runes", m.motto.runeLen, 48)
  check("and valid UTF-8", m.motto.validateUtf8() == -1)

block:
  ## The 16 KB cap is measured in BYTES and still cut on a rune boundary.
  let filler = "\u{1F680}".repeat(20000)
  let reply = "{\"sheet\":{\"opening\":\"launcher_rush\"},\"notes\":\"" &
    filler & "\"}"
  check("the raw reply is well over the cap", reply.len > MaxReplyBytes)
  checkEq("the cap is 16 KB of BYTES", MaxReplyBytes, 16 * 1024)
  let cut = reply.truncateBytes(MaxReplyBytes)
  check("the cut is at most 16 KB", cut.len <= MaxReplyBytes)
  check("and it lands ON A RUNE BOUNDARY", cut.validateUtf8() == -1)
  ## The cut lands mid-JSON, so the object no longer parses at all — which is
  ## exactly the retry-then-fallback path, and the reason the cap exists.
  var raised = false
  try:
    discard sheetOf(reply)
  except CatchableError:
    raised = true
  check("an over-long reply is unparseable rather than silently mangled",
    raised)

# --- the schema is generated from the table, not re-typed ----------------
block:
  let schema = bc23SheetSchema()
  for key in KnownKeys23:
    check("the schema names " & key, schema.hasKey(key))
  checkEq("and nothing else", schema.len, KnownKeys23.len)
  checkEq("launcher_ratio's range is the clamped one",
    schema["launcher_ratio"]["range"], %*[20, 80])
  var wellValues: seq[string]
  for v in schema["well_priority"]["values"]: wellValues.add(v.getStr())
  check("`elixir` is not offered as a well priority",
    "elixir" notin wellValues)

# --- toJson round-trips through validate ---------------------------------
block:
  let s = sheetOf("""{"sheet":{"opening":"carrier_eco","launcher_ratio":35,
    "well_priority":"mana","elixir_tech":"early",
    "elixir_spend":"destabilizers","anchor_round":150,"anchor_budget":60,
    "island_priority":"safe","amplifier_use":"escort",
    "destabilizer_use":"siege","retreat_on_launcher_loss":"home",
    "carrier_throw":10}}""")
  let again = validate(%*{"sheet": s.toJson()}, "bc23")
  checkEq("the applied sheet round-trips", again.toJson(), s.toJson())
  checkEq("with no repairs", again.defaultsApplied.len, 0)
  check("plainWords says something for every knob",
    s.plainWords().len >= 11)

finish("test_bc23_sheet")
