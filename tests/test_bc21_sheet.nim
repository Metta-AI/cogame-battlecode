## The bc21 doctrine sheet: every one of the ten knobs absent / out of range /
## mistyped, the deterministic ratio renormalisation, unknown keys recorded,
## the D1 assertion that `chassis` is NOT a knob, and rune-boundary truncation
## including astral-plane characters and the 16 KB byte cap.

import std/[json, strutils, unicode]
import harness
import battlecode/[sheet, sim_types]

proc s21(text: string): Sheet = parseReply(text, "bc21")

# --- the ten knobs and nothing else -----------------------------------------
block:
  checkEq("exactly ten known keys", KnownKeys21.len, 10)
  check("`chassis` is NOT one of them (D1)", "chassis" notin KnownKeys21)
  let known = knownKeysFor("bc21")
  checkEq("and the envelope agrees", known.len, 10)
  for key in KnownKeys21:
    check("the envelope knows " & key, key in known)

# --- defaults ----------------------------------------------------------------
block:
  let sheet = s21("""{"sheet":{}}""")
  let d = sheet.doctrine21
  checkEq("opening", $d.opening, "balanced")
  checkEq("slanderer_ratio", d.slandererRatio, 45)
  checkEq("muck_ratio", d.muckRatio, 25)
  checkEq("politician_size_curve", $d.politicianSizeCurve, "ramp")
  checkEq("bid_policy", $d.bidPolicy, "proportional")
  checkEq("expansion", $d.expansion, "neutral_centers_first")
  checkEq("flank_policy", $d.flankPolicy, "hunt_slanderers")
  checkEq("empower_threshold", d.empowerThreshold, 60)
  checkEq("convert_over_kill", d.convertOverKill, true)
  checkEq("eco_exponential_round", d.ecoExponentialRound, 700)
  checkEq("an empty sheet repairs nothing", sheet.defaultsApplied.len, 0)

# --- each knob: absent -> default, out of range -> default + recorded --------
block:
  for (key, bad) in [("slanderer_ratio", "101"), ("slanderer_ratio", "-1"),
                     ("muck_ratio", "1000"), ("empower_threshold", "301"),
                     ("empower_threshold", "-5"),
                     ("eco_exponential_round", "0"),
                     ("eco_exponential_round", "1501")]:
    let sheet = s21("""{"sheet":{"""" & key & """":""" & bad & """}}""")
    check(key & " = " & bad & " is repaired",
      key in sheet.defaultsApplied)
  for (key, bad) in [("opening", "\"turtle\""),
                     ("politician_size_curve", "\"chunky\""),
                     ("bid_policy", "\"sometimes\""),
                     ("expansion", "\"go_wide\""),
                     ("flank_policy", "\"sneak\"")]:
    let sheet = s21("""{"sheet":{"""" & key & """":""" & bad & """}}""")
    check(key & " = " & bad & " is repaired", key in sheet.defaultsApplied)
  for key in ["opening", "politician_size_curve", "bid_policy", "expansion",
              "flank_policy"]:
    let sheet = s21("""{"sheet":{"""" & key & """":42}}""")
    check(key & " mistyped as a number is repaired",
      key in sheet.defaultsApplied)
  let mistyped = s21("""{"sheet":{"slanderer_ratio":"lots"}}""")
  check("slanderer_ratio mistyped as prose is repaired",
    "slanderer_ratio" in mistyped.defaultsApplied)
  let bools = s21("""{"sheet":{"convert_over_kill":"maybe"}}""")
  check("convert_over_kill mistyped is repaired",
    "convert_over_kill" in bools.defaultsApplied)
  let yes = s21("""{"sheet":{"convert_over_kill":"no"}}""")
  checkEq("but `no` is honoured", yes.doctrine21.convertOverKill, false)
  checkEq("and nothing is recorded for it", yes.defaultsApplied.len, 0)

block:
  ## Every legal value of every enum knob is honoured.
  for value in ["muck_spam", "slanderer_turtle", "balanced"]:
    checkEq("opening " & value,
      $s21("""{"sheet":{"opening":"""" & value & """"}}""").doctrine21.opening,
      value)
  for value in ["cheap", "ramp", "fat"]:
    checkEq("curve " & value, $s21("""{"sheet":{"politician_size_curve":"""" &
      value & """"}}""").doctrine21.politicianSizeCurve, value)
  for value in ["never", "fixed", "proportional", "escalate_when_ahead"]:
    checkEq("bid " & value, $s21("""{"sheet":{"bid_policy":"""" & value &
      """"}}""").doctrine21.bidPolicy, value)
  for value in ["neutral_centers_first", "defend_home"]:
    checkEq("expansion " & value, $s21("""{"sheet":{"expansion":"""" & value &
      """"}}""").doctrine21.expansion, value)
  for value in ["screen_home", "hunt_slanderers", "flank_wide"]:
    checkEq("flank " & value, $s21("""{"sheet":{"flank_policy":"""" & value &
      """"}}""").doctrine21.flankPolicy, value)
  checkEq("a hyphenated enum value is normalised",
    $s21("""{"sheet":{"opening":"muck-spam"}}""").doctrine21.opening,
    "muck_spam")
  checkEq("and so is a shouted one",
    $s21("""{"sheet":{"opening":" MUCK SPAM "}}""").doctrine21.opening,
    "muck_spam")

# --- the renormalisation ------------------------------------------------------
block:
  ## `s' = s*100 div (s+m)`, `m' = 100 - s'`, politicians 0.
  let d = s21("""{"sheet":{"slanderer_ratio":90,"muck_ratio":60}}""").doctrine21
  let (slan, muck, pol) = d.spendMix()
  checkEq("s' = 90*100 div 150", slan, 60)
  checkEq("m' = 100 - s'", muck, 40)
  checkEq("politicians take nothing", pol, 0)
  let e = s21("""{"sheet":{"slanderer_ratio":70,"muck_ratio":30}}""").doctrine21
  let (s2, m2, p2) = e.spendMix()
  checkEq("exactly 100 is not renormalised", s2, 70)
  checkEq("muck", m2, 30)
  checkEq("politicians", p2, 0)
  let f = s21("""{"sheet":{"slanderer_ratio":10,"muck_ratio":20}}""").doctrine21
  let (s3, m3, p3) = f.spendMix()
  checkEq("under 100 is left alone", s3, 10)
  checkEq("muck", m3, 20)
  checkEq("and politicians take the rest", p3, 70)

# --- D1: a submitted `chassis` is recorded and never honoured ----------------
block:
  let sheet = s21("""{"sheet":{"chassis":"examplefuncsplayer21",
                               "opening":"muck_spam"}}""")
  check("`chassis` is recorded as an unknown field",
    "chassis" in sheet.unknownFields)
  check("it is not a repaired knob", "chassis" notin sheet.defaultsApplied)
  checkEq("and the knob it sat beside still applied",
    $sheet.doctrine21.opening, "muck_spam")

# --- unknown keys: at most 16, each at most 40 runes -------------------------
block:
  var payload = """{"sheet":{"""
  for i in 0 ..< 40:
    payload.add("\"junk_" & $i & "\":1,")
  payload.add("\"opening\":\"muck_spam\"}}")
  let sheet = s21(payload)
  check("at most 16 unknown keys are recorded",
    sheet.unknownFields.len <= MaxUnknownFields)
  let long0 = "z".repeat(200)
  let sheet2 = s21("""{"sheet":{"""" & long0 & """":1}}""")
  checkEq("and each is truncated to 40 runes",
    sheet2.unknownFields[0].runeLen, MaxUnknownFieldRunes)

block:
  ## At most 32 sheet keys are even LOOKED at.
  var payload = """{"sheet":{"""
  for i in 0 ..< 60:
    payload.add("\"k" & $i & "\":1,")
  payload.add("\"opening\":\"muck_spam\"}}")
  let sheet = s21(payload)
  checkEq("the 33rd key is past the cap, so `opening` never lands",
    $sheet.doctrine21.opening, "balanced")

# --- rune-boundary truncation -------------------------------------------------
block:
  let astral = "\u{1F600}"          # a 4-byte codepoint
  let notes = astral.repeat(400)
  let sheet = s21("""{"sheet":{},"notes":"""" & notes & """"}""")
  checkEq("notes are cut at 280 RUNES", sheet.notes.runeLen, MaxNoteRunes)
  check("and the result is valid UTF-8", sheet.notes.validateUtf8() == -1)
  let motto = astral.repeat(200)
  let sheet2 = s21("""{"sheet":{},"motto":"""" & motto & """"}""")
  checkEq("motto is cut at 48 runes", sheet2.motto.runeLen, MaxMottoRunes)
  check("and is valid UTF-8", sheet2.motto.validateUtf8() == -1)

block:
  ## The 16 KB cap is measured in BYTES and still lands on a rune boundary.
  let astral = "\u{1F600}"
  var junk = """{"sheet":{"opening":"muck_spam"},"notes":""""
  junk.add(astral.repeat(20000))
  junk.add(""""}""")
  check("the reply is far over the byte cap", junk.len > MaxReplyBytes)
  let capped = junk.truncateBytes(MaxReplyBytes)
  check("the cut is at most 16 KB", capped.len <= MaxReplyBytes)
  check("and it is valid UTF-8", capped.validateUtf8() == -1)

# --- a sheet can never be REJECTED -------------------------------------------
block:
  let sheet = s21("""nonsense before {"sheet":{"opening":"muck_spam"}} after""")
  checkEq("fenced prose around the object is tolerated",
    $sheet.doctrine21.opening, "muck_spam")
  let bare = s21("""{"opening":"muck_spam"}""")
  checkEq("and a sheet without the `sheet` wrapper is read directly",
    $bare.doctrine21.opening, "muck_spam")
  let empty = validate(newJNull(), "bc21")
  checkEq("a null payload takes every default and records them",
    empty.defaultsApplied.len, 10)

# --- plain words --------------------------------------------------------------
block:
  let words = s21("""{"sheet":{"opening":"muck_spam","muck_ratio":70,
                               "politician_size_curve":"cheap",
                               "flank_policy":"flank_wide",
                               "empower_threshold":0,
                               "eco_exponential_round":250}}""").plainWords()
  check("the overlay says what the doctrine does", words.len >= 8)
  check("spams muckrakers", "spams muckrakers" in words)
  check("70 % of spend on muckrakers", "70 % of spend on muckrakers" in words)
  check("cheap politicians", "cheap politicians" in words)
  check("flanks wide", "flanks wide" in words)
  check("empowers on contact", "empowers on contact" in words)
  check("stops compounding at round 250",
    "stops compounding at round 250" in words)

# --- the round trip ------------------------------------------------------------
block:
  let sheet = s21("""{"sheet":{"opening":"slanderer_turtle",
                               "slanderer_ratio":70,"muck_ratio":15,
                               "politician_size_curve":"fat",
                               "bid_policy":"escalate_when_ahead",
                               "expansion":"defend_home",
                               "flank_policy":"screen_home",
                               "empower_threshold":180,
                               "convert_over_kill":false,
                               "eco_exponential_round":1100}}""")
  let doc = sheet.toJson()
  checkEq("the applied sheet round-trips with all ten keys", doc.len, 10)
  checkEq("opening", doc["opening"].getStr(), "slanderer_turtle")
  checkEq("convert_over_kill", doc["convert_over_kill"].getBool(), false)
  checkEq("eco_exponential_round", doc["eco_exponential_round"].getInt(), 1100)

finish("bc21 sheet")
