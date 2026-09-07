## The bc24 doctrine sheet: every one of the ten knobs absent, out of range and
## mistyped; `upgrade_order`'s four malformations taking the WHOLE default
## array and being recorded ONCE; unknown keys recorded within their caps; THE
## D1 ASSERTION that a submitted `chassis` is recorded and never honoured; and
## rune-boundary truncation of `notes` and `motto` including astral-plane
## characters, plus the 16 KB byte cap cut on a rune boundary.

import std/[json, strutils, unicode]
import harness
import battlecode/[sheet, sim_types]

proc sheetOf(text: string): Sheet = parseReply(text, YearBc24)

# --- the defaults -----------------------------------------------------------
block:
  let s = sheetOf("{}")
  let d = s.doctrine24
  checkEq("split", $d.specialisationSplit, "balanced")
  checkEq("flag_rush_round", d.flagRushRound, 450)
  checkEq("trap_budget", d.trapBudget, 30)
  checkEq("trap_placement", $d.trapPlacement, "flag_ring")
  checkEq("trap_mix", $d.trapMix, "mixed")
  checkEq("heal_priority", $d.healPriority, "wounded_first")
  checkEq("water_dig_policy", $d.waterDigPolicy, "choke_dig")
  checkEq("retreat_hp", d.retreatHp, 400)
  checkEq("flag_carry_escort", d.flagCarryEscort, 2)
  checkEq("upgrade_order", $d.upgradeOrder, "[attack, heal, capture]")
  checkEq("an empty sheet applies no repairs", s.defaultsApplied.len, 0)
  checkEq("and records no unknown fields", s.unknownFields.len, 0)
  checkEq("exactly ten known keys", KnownKeys24.len, 10)

# --- every knob, three ways -------------------------------------------------
block:
  let s = sheetOf("""{"sheet":{"specialisation_split":"attack",
    "flag_rush_round":260,"trap_budget":10,"trap_placement":"choke",
    "trap_mix":"stun","heal_priority":"carrier_first",
    "water_dig_policy":"fill_paths",
    "upgrade_order":["capture","attack","heal"],
    "retreat_hp":250,"flag_carry_escort":5}}""")
  let d = s.doctrine24
  checkEq("a fully specified sheet applies verbatim", $d.specialisationSplit,
    "attack")
  checkEq("flag_rush_round", d.flagRushRound, 260)
  checkEq("trap_budget", d.trapBudget, 10)
  checkEq("trap_placement", $d.trapPlacement, "choke")
  checkEq("trap_mix", $d.trapMix, "stun")
  checkEq("heal_priority", $d.healPriority, "carrier_first")
  checkEq("water_dig_policy", $d.waterDigPolicy, "fill_paths")
  checkEq("upgrade_order", $d.upgradeOrder, "[capture, attack, heal]")
  checkEq("retreat_hp", d.retreatHp, 250)
  checkEq("flag_carry_escort", d.flagCarryEscort, 5)
  checkEq("and nothing was repaired", s.defaultsApplied.len, 0)

block:
  for (key, bad) in [
      ("specialisation_split", "\"sideways\""),
      ("trap_placement", "\"nowhere\""),
      ("trap_mix", "\"napalm\""),
      ("heal_priority", "\"nobody\""),
      ("water_dig_policy", "\"tunnel\"")]:
    let s = sheetOf("""{"sheet":{"""" & key & """":""" & bad & "}}")
    check(key & ": an unknown enum value takes the default",
      key in s.defaultsApplied)
  for (key, bad) in [
      ("specialisation_split", "7"),
      ("trap_placement", "true"),
      ("trap_mix", "[]"),
      ("heal_priority", "{}"),
      ("water_dig_policy", "null")]:
    let s = sheetOf("""{"sheet":{"""" & key & """":""" & bad & "}}")
    check(key & ": a mistyped enum takes the default",
      key in s.defaultsApplied)

block:
  for (key, lo, hi) in [("flag_rush_round", 201, 1200),
                        ("trap_budget", 0, 60),
                        ("retreat_hp", 100, 900),
                        ("flag_carry_escort", 0, 6)]:
    let under = sheetOf("""{"sheet":{"""" & key & """":""" & $(lo - 1) & "}}")
    check(key & ": one below the range is repaired", key in under.defaultsApplied)
    let over = sheetOf("""{"sheet":{"""" & key & """":""" & $(hi + 1) & "}}")
    check(key & ": one above the range is repaired", key in over.defaultsApplied)
    let atLo = sheetOf("""{"sheet":{"""" & key & """":""" & $lo & "}}")
    check(key & ": the low bound itself is accepted",
      key notin atLo.defaultsApplied)
    let atHi = sheetOf("""{"sheet":{"""" & key & """":""" & $hi & "}}")
    check(key & ": the high bound itself is accepted",
      key notin atHi.defaultsApplied)
    let typed = sheetOf("""{"sheet":{"""" & key & """":"soon"}}""")
    check(key & ": a mistyped int is repaired", key in typed.defaultsApplied)

block:
  ## `flag_rush_round`'s range CANNOT EXPRESS "never": 1200 is the ceiling and
  ## it still leaves 800 rounds of raiding.
  let s = sheetOf("""{"sheet":{"flag_rush_round":99999}}""")
  checkEq("an enormous rush round is repaired to 450",
    s.doctrine24.flagRushRound, 450)
  let z = sheetOf("""{"sheet":{"flag_rush_round":0}}""")
  checkEq("and so is zero", z.doctrine24.flagRushRound, 450)

# --- upgrade_order ----------------------------------------------------------
block:
  for bad in ["""["attack","heal"]""",
              """["attack","heal","capture","attack"]""",
              """["attack","attack","capture"]""",
              """["attack","heal","sideways"]""",
              """"attack"""",
              "42",
              """{"first":"attack"}"""]:
    let s = sheetOf("""{"sheet":{"upgrade_order":""" & bad & "}}")
    checkEq("a malformed upgrade_order takes the WHOLE default array: " & bad,
      $s.doctrine24.upgradeOrder, "[attack, heal, capture]")
    var recorded = 0
    for f in s.defaultsApplied:
      if f == "upgrade_order": recorded += 1
    checkEq("and is recorded exactly ONCE: " & bad, recorded, 1)

# --- D1: chassis is not a knob ----------------------------------------------
block:
  let s = sheetOf("""{"sheet":{"chassis":"examplefuncsplayer24",
    "trap_budget":50}}""")
  check("a submitted `chassis` is recorded as an UNKNOWN FIELD",
    "chassis" in s.unknownFields)
  checkEq("the rest of the sheet still applies", s.doctrine24.trapBudget, 50)
  check("`chassis` is not a known key", "chassis" notin KnownKeys24)
  var inSchema = false
  for key, _ in bc24SheetSchema():
    if key == "chassis": inSchema = true
  check("and it is not in the schema the brief carries", not inSchema)

# --- unknown keys and their caps --------------------------------------------
block:
  var parts: seq[string]
  for i in 0 ..< 40:
    parts.add("\"junk" & $i & "\":1")
  let s = sheetOf("{\"sheet\":{" & parts.join(",") & "}}")
  check("at most sixteen unknown keys are recorded",
    s.unknownFields.len <= MaxUnknownFields)
  var tooLong = false
  for f in s.unknownFields:
    if f.runeLen > MaxUnknownFieldRunes: tooLong = true
  check("and each is capped at forty runes", not tooLong)

block:
  let long = "k" & repeat("\u00e9", 80)
  let s = sheetOf("{\"sheet\":{\"" & long & "\":1}}")
  checkEq("a long unknown key is cut to forty RUNES",
    s.unknownFields[0].runeLen, MaxUnknownFieldRunes)
  check("on a rune boundary", s.unknownFields[0].validateUtf8() < 0)

# --- notes and motto --------------------------------------------------------
block:
  let notes = repeat("\u4e2d", 400)
  let motto = repeat("\u{1F986}", 80)     ## the duck, an astral-plane rune
  let s = sheetOf("""{"sheet":{},"notes":"""" & notes & """","motto":"""" &
    motto & """"}""")
  checkEq("notes are cut to 280 RUNES", s.notes.runeLen, MaxNoteRunes)
  checkEq("motto is cut to 48 RUNES", s.motto.runeLen, MaxMottoRunes)
  check("notes stay valid UTF-8", s.notes.validateUtf8() < 0)
  check("and so does the motto, astral plane and all",
    s.motto.validateUtf8() < 0)
  checkEq("a four-byte rune really is four bytes", s.motto.len,
    MaxMottoRunes * 4)

block:
  let s = sheetOf("""{"sheet":{},"notes":"one\ntwo\r\nthree"}""")
  check("newlines are collapsed so one record stays one line",
    "\n" notin s.notes and "\r" notin s.notes)

# --- the whole-reply byte cap -----------------------------------------------
block:
  ## The cap is 16 KB of BYTES, cut on a rune boundary -- `truncateRunes`
  ## would have kept 16 384 RUNES, i.e. up to 64 KB (commit a8684c0).
  let padded = repeat("\u{1F986}", 8000)
  let text = """{"sheet":{"trap_budget":55},"notes":"""" & padded & """"}"""
  check("the reply really is over the cap", text.len > MaxReplyBytes)
  let cut = text.truncateBytes(MaxReplyBytes)
  check("the cut is at most 16 KB", cut.len <= MaxReplyBytes)
  check("and it is still valid UTF-8", cut.validateUtf8() < 0)

block:
  ## A reply with no JSON object at all is the ONE condition the retry and
  ## then the fallback exist for.
  var raised = false
  try:
    discard sheetOf("I would rather not say.")
  except CatchableError:
    raised = true
  check("a reply with no JSON object raises", raised)

block:
  let s = sheetOf("here you go:\n```json\n{\"sheet\":{\"trap_budget\":7}}\n```")
  checkEq("a fenced reply is still parsed", s.doctrine24.trapBudget, 7)

# --- plain words ------------------------------------------------------------
block:
  let s = sheetOf("""{"sheet":{"trap_budget":0,"water_dig_policy":"none",
    "flag_carry_escort":0}}""")
  let words = plainWords(s)
  checkEq("ten plain-words lines, one per knob", words.len, 10)
  var joined = words.join("; ")
  check("and they say what the sheet says",
    "builds no traps" in joined and "never digs" in joined and
    "alone" in joined)

finish("bc24 sheet")
