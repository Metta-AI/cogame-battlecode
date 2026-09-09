## Shard 14 of the note's list — **the doctrine sheet**, every one of the
## eleven knobs, and the envelope resolver from the bc16 side.
##
## Absent -> default AND recorded in `defaults_applied` (the envelope pin,
## item 2, and it is bc16-and-bc22-only — the SAME test asserts a bc23 empty
## sheet still records none, so the change is provably scoped). Mistyped ->
## default + recorded. Unknown enum value -> default + recorded. **The four
## integer knobs CLAMP to their range rather than defaulting**, and a
## non-integer defaults. Enum values are case-folded, trimmed and `-`/space
## normalised. Unknown keys are recorded (<= 16, <= 40 runes). **A submitted
## `chassis` is recorded as an unknown field and never honoured** (D1) — this
## assertion fails if anyone re-adds the knob.

import std/[json, strutils, unicode]
import harness
import bc16_fixture
import battlecode/sheet

proc sheetOf(payload: string): Sheet = parseReply(payload, YearBc16)

# --- the eleven knobs, and no `chassis` -----------------------------------
block:
  checkEq("exactly eleven knobs", KnownKeys16.len, 11)
  checkEq("and they are the note's names", @KnownKeys16,
    @["opening", "turret_count", "guard_ratio", "zombie_kiting",
      "den_clear_round", "parts_priority", "archon_spread",
      "neutral_activation", "retreat_hp", "rubble_clear",
      "infection_policy"])
  check("`chassis` is NOT a knob (D1)", "chassis" notin @KnownKeys16)
  checkEq("knownKeysFor routes bc16 to them", knownKeysFor(YearBc16),
    @KnownKeys16)

block:
  let d = defaultDoctrine16()
  checkEq("default opening", d.opening, opTurtle)
  checkEq("default turret_count", d.turretCount, 3)
  checkEq("default guard_ratio", d.guardRatio, 45)
  checkEq("default zombie_kiting", d.zombieKiting, zkRangedOnly)
  checkEq("default den_clear_round", d.denClearRound, 900)
  checkEq("default parts_priority", d.partsPriority, ppUnits)
  checkEq("default archon_spread", d.archonSpread, asSpread)
  checkEq("default neutral_activation", d.neutralActivation, naOpportunistic)
  checkEq("default retreat_hp", d.retreatHp, 35)
  checkEq("default rubble_clear", d.rubbleClear, rcPaths)
  checkEq("default infection_policy", d.infectionPolicy, ipQuarantine)

# --- ABSENT -> default AND RECORDED ---------------------------------------
block:
  let s = sheetOf("{}")
  checkEq("an empty bc16 sheet records ALL ELEVEN as defaulted",
    s.defaultsApplied.len, 11)
  for key in KnownKeys16:
    check("including " & key, key in s.defaultsApplied)
  ## And the scoping proof: bc23 (and every other year) is unchanged.
  let bc23 = parseReply("{}", YearBc23)
  checkEq("while an EMPTY bc23 sheet still records NONE — the change is " &
    "provably scoped to bc16", bc23.defaultsApplied.len, 0)
  let bc26 = parseReply("{}", YearBc26)
  checkEq("and so does bc26", bc26.defaultsApplied.len, 0)
  ## bc22 is the other year that counts absent keys; it is untouched here.
  let bc22 = parseReply("{}", YearBc22)
  check("bc22 keeps its own absent-key counting", bc22.defaultsApplied.len > 0)

block:
  let s = sheetOf("""{"opening":"scout_zombie_pull","turret_count":1,
    "guard_ratio":20,"zombie_kiting":"always","den_clear_round":2200,
    "parts_priority":"vipers","archon_spread":"split",
    "neutral_activation":"hunt","retreat_hp":30,"rubble_clear":"paths",
    "infection_policy":"suicide_squad"}""")
  checkEq("a complete sheet records NOTHING as defaulted",
    s.defaultsApplied.len, 0)
  let d = s.doctrine16
  checkEq("opening", d.opening, opScoutZombiePull)
  checkEq("turret_count", d.turretCount, 1)
  checkEq("guard_ratio", d.guardRatio, 20)
  checkEq("zombie_kiting", d.zombieKiting, zkAlways)
  checkEq("den_clear_round", d.denClearRound, 2200)
  checkEq("parts_priority", d.partsPriority, ppVipers)
  checkEq("archon_spread", d.archonSpread, asSplit)
  checkEq("neutral_activation", d.neutralActivation, naHunt)
  checkEq("retreat_hp", d.retreatHp, 30)
  checkEq("rubble_clear", d.rubbleClear, rcPaths)
  checkEq("infection_policy", d.infectionPolicy, ipSuicideSquad)

# --- mistyped and unknown values ------------------------------------------
block:
  let s = sheetOf("""{"opening":42,"zombie_kiting":"sideways",
    "parts_priority":null,"archon_spread":["split"],
    "neutral_activation":"HUNT","rubble_clear":true,
    "infection_policy":"quarantine"}""")
  checkEq("a mistyped enum takes its default", s.doctrine16.opening, opTurtle)
  check("and is recorded", "opening" in s.defaultsApplied)
  checkEq("an unknown enum VALUE takes its default",
    s.doctrine16.zombieKiting, zkRangedOnly)
  check("and is recorded", "zombie_kiting" in s.defaultsApplied)
  checkEq("a null takes its default", s.doctrine16.partsPriority, ppUnits)
  checkEq("an array takes its default", s.doctrine16.archonSpread, asSpread)
  checkEq("a bool takes its default", s.doctrine16.rubbleClear, rcPaths)
  checkEq("and CASE IS FOLDED, so \"HUNT\" is honoured",
    s.doctrine16.neutralActivation, naHunt)
  check("so `neutral_activation` is NOT in defaults_applied",
    "neutral_activation" notin s.defaultsApplied)
  check("and neither is the one that was set correctly",
    "infection_policy" notin s.defaultsApplied)

block:
  ## Enums are case-folded, trimmed, and `-`/space normalised to `_`.
  for text in ["\"soldier_viper_aggro\"", "\"SOLDIER_VIPER_AGGRO\"",
               "\"  soldier viper aggro \"", "\"Soldier-Viper-Aggro\""]:
    let s = sheetOf("{\"opening\":" & text & "}")
    checkEq("opening " & text & " normalises", s.doctrine16.opening,
      opSoldierViperAggro)

# --- the FOUR integer knobs CLAMP -----------------------------------------
block:
  for (key, lo, hi, dflt) in [("turret_count", 0, 12, 3),
                              ("guard_ratio", 0, 100, 45),
                              ("den_clear_round", 1, 2800, 900),
                              ("retreat_hp", 0, 100, 35)]:
    let high0 = sheetOf("{\"" & key & "\": 99999}")
    let low0 = sheetOf("{\"" & key & "\": -99999}")
    let got = proc (s: Sheet): int =
      case key
      of "turret_count": s.doctrine16.turretCount
      of "guard_ratio": s.doctrine16.guardRatio
      of "den_clear_round": s.doctrine16.denClearRound
      else: s.doctrine16.retreatHp
    checkEq(key & " clamps UP to " & $hi, got(high0), hi)
    checkEq(key & " clamps DOWN to " & $lo, got(low0), lo)
    check(key & "'s clamp IS recorded", key in high0.defaultsApplied)
    ## A NON-INTEGER defaults rather than clamping — an integer knob is
    ## clamped, never defaulted, so "as many as possible" still means
    ## something; a value that is not a number at all has no bound to clamp
    ## to.
    let bad = sheetOf("{\"" & key & "\": \"lots\"}")
    checkEq(key & " with a STRING takes its default " & $dflt, got(bad), dflt)
    check("and is recorded", key in bad.defaultsApplied)
    let inRange = sheetOf("{\"" & key & "\": " & $((lo + hi) div 2) & "}")
    checkEq(key & " in range is honoured", got(inRange), (lo + hi) div 2)
    check("and NOT recorded", key notin inRange.defaultsApplied)

# --- D1: a submitted `chassis` is recorded and never honoured -------------
block:
  let s = sheetOf("""{"chassis":"greenhorn","opening":"turtle"}""")
  check("a submitted `chassis` lands in unknown_fields",
    "chassis" in s.unknownFields)
  check("and it is not a knob", "chassis" notin @KnownKeys16)
  ## The chassis a seat drives comes from `PLAYER_SCRIPTED` or is the fixed
  ## champion chassis; nothing in the sheet can move it.
  check("the Doctrine16 type has no chassis field",
    "chassis" notin ($toJson16(s.doctrine16)).toLowerAscii())

block:
  ## Unknown keys are capped at 16 and 40 runes each.
  var payload = "{"
  for i in 0 ..< 40:
    payload.add("\"unknown_key_number_" & $i & "\":1,")
  payload.add("\"opening\":\"turtle\"}")
  let s = sheetOf(payload)
  check("at most sixteen unknown keys are recorded",
    s.unknownFields.len <= MaxUnknownFields)
  for f in s.unknownFields:
    check("and each is at most forty runes", f.runeLen <= MaxUnknownFieldRunes)

# --- the envelope resolver, from the bc16 side ----------------------------
block:
  let cases = {
    """{"opening":"turtle","turret_count":7}""": "",
    """{"sheet":{"opening":"turtle","turret_count":7}}""": "sheet",
    """{"doctrine":{"opening":"turtle","turret_count":7}}""": "doctrine",
    """{"protocol":"x","doctrine":{"opening":"turtle","turret_count":7}}""":
      "doctrine",
    """{"battlecode_2016_doctrine":{"opening":"turtle","turret_count":7}}""":
      "battlecode_2016_doctrine",
  }
  for (payload, envelope) in cases:
    let s = sheetOf(payload)
    checkEq("envelope for " & payload[0 .. min(30, payload.high)],
      s.envelope, envelope)
    checkEq("and the knobs really applied", s.doctrine16.turretCount, 7)

block:
  ## A payload with BOTH a known knob key and a `doctrine` key: THE FLAT ONE
  ## WINS, because rule `""` fires first.
  let s = sheetOf("""{"opening":"scout_zombie_pull",
    "doctrine":{"opening":"soldier_viper_aggro"}}""")
  checkEq("the flat sheet wins over a sibling envelope", s.doctrine16.opening,
    opScoutZombiePull)
  checkEq("and no envelope is recorded", s.envelope, "")

block:
  ## A TWO-OBJECT payload with no known knob key and no named envelope: NO
  ## UNWRAP, because "the single object-valued key" rule needs exactly one.
  let s = sheetOf("""{"alpha":{"opening":"turtle"},"beta":{"x":1}}""")
  checkEq("a two-object payload is not unwrapped", s.envelope, "")
  checkEq("so all eleven knobs default", s.defaultsApplied.len, 11)

block:
  ## Nesting is unwrapped AT MOST ONCE.
  let s = sheetOf("""{"doctrine":{"sheet":{"opening":"scout_zombie_pull"}}}""")
  checkEq("one unwrap only", s.envelope, "doctrine")
  checkEq("so the inner sheet is NOT reached and opening defaults",
    s.doctrine16.opening, opTurtle)

block:
  ## `sheet_submitted` round-trips the sheet node AS RECEIVED.
  let s = sheetOf("""{"doctrine":{"opening":"turtle","turret_count":9}}""")
  check("the submitted sheet is recorded", s.submitted.len > 0)
  check("and it is the INNER node, before the knobs were repaired",
    "turret_count" in s.submitted)

# --- notes, motto, and rune-boundary truncation ---------------------------
block:
  var notes = ""
  for i in 0 ..< 400: notes.add("\u00e9")          ## a two-byte rune
  var motto = ""
  for i in 0 ..< 200: motto.add("\U0001F9DF")      ## an ASTRAL-plane rune
  let s = sheetOf("""{"notes":"""" & notes & """","motto":"""" & motto & """"}""")
  checkEq("notes truncate to 280 RUNES", s.notes.runeLen, MaxNoteRunes)
  checkEq("motto to 48 RUNES", s.motto.runeLen, MaxMottoRunes)
  check("and the result is still valid UTF-8 — the truncation landed on a " &
    "rune boundary", s.notes.validateUtf8() == -1 and
    s.motto.validateUtf8() == -1)
  check("and every rune in the truncated motto is whole",
    s.motto.toRunes().len == s.motto.runeLen)

block:
  ## The 16 KB reply cap is measured in BYTES and still cut on a rune
  ## boundary: byte-slicing a multi-byte character renders fine in a browser
  ## and then fails a strict UTF-8 parser, which is exactly what makes a
  ## replay unreadable to everything but one lenient viewer.
  checkEq("MaxReplyBytes is 16 KB", MaxReplyBytes, 16384)
  var padding = ""
  for i in 0 ..< 20000: padding.add("\u00e9")
  let payload = """{"opening":"turtle","notes":"""" & padding & """"}"""
  check("the payload is over the cap", payload.len > MaxReplyBytes)
  let capped = payload.truncateBytes(MaxReplyBytes)
  check("the cap is measured in BYTES", capped.len <= MaxReplyBytes)
  check("and the cut lands on a RUNE boundary, so the bytes are still " &
    "valid UTF-8 -- byte-slicing a multi-byte character renders fine in a " &
    "browser and then fails a strict UTF-8 parser",
    capped.validateUtf8() == -1)
  ## And an over-cap reply whose JSON the cut destroyed is UNPARSEABLE, which
  ## is exactly the condition the retry and then the fallback sheet exist for
  ## -- not a silently half-applied doctrine.
  var raised = false
  try:
    discard sheetOf(payload)
  except CatchableError:
    raised = true
  check("an over-cap reply that the cut left unparseable RAISES, so the " &
    "seat retries and then falls back", raised)

# --- plainWords16: a complete clause for EVERY value of EVERY knob --------
block:
  ## The "a accelerating" fix: no article concatenation anywhere, and every
  ## knob value maps to a COMPLETE CLAUSE.
  var seen = 0
  for opening in Opening16:
    for kiting in ZombieKiting16:
      for priority in PartsPriority16:
        for spread in ArchonSpread16:
          for neutral in NeutralActivation16:
            for rubble in RubbleClear16:
              for infection in InfectionPolicy16:
                if seen > 400: break
                inc seen
                var d = defaultDoctrine16()
                d.opening = opening
                d.zombieKiting = kiting
                d.partsPriority = priority
                d.archonSpread = spread
                d.neutralActivation = neutral
                d.rubbleClear = rubble
                d.infectionPolicy = infection
                let words = plainWords16(d)
                if words.len != 11:
                  checkEq("plainWords16 returns one clause per knob",
                    words.len, 11)
                for phrase in words:
                  if phrase.len == 0:
                    check("no clause is empty", false)
                  if phrase.strip().startsWith("a ") or
                      phrase.strip().startsWith("an "):
                    check("no clause is a bare article plus an enum name: " &
                      phrase, false)
  check("every combination produced eleven non-empty clauses", seen > 400)

block:
  ## And the integer knobs really reach the words.
  var d = defaultDoctrine16()
  d.turretCount = 9
  d.guardRatio = 77
  d.denClearRound = 1234
  d.retreatHp = 62
  let words = plainWords16(d).join(" | ")
  check("the turret count is in the words", "9" in words)
  check("the guard ratio is", "77" in words)
  check("the den clear round is", "1234" in words)
  check("and the retreat threshold is", "62" in words)

# --- toJson16 round-trips ---------------------------------------------------
block:
  let s = sheetOf("""{"opening":"soldier_viper_aggro","turret_count":11,
    "guard_ratio":88,"zombie_kiting":"never","den_clear_round":150,
    "parts_priority":"turrets","archon_spread":"huddle",
    "neutral_activation":"never","retreat_hp":5,"rubble_clear":"aggressive",
    "infection_policy":"ignore"}""")
  let j = toJson16(s.doctrine16)
  checkEq("toJson16 has all eleven keys", j.len, 11)
  for key in KnownKeys16:
    check("including " & key, j.hasKey(key))
  let again = parseReply($j, YearBc16)
  checkEq("and it round-trips with nothing defaulted",
    again.defaultsApplied.len, 0)
  checkEq("to the same doctrine", again.doctrine16, s.doctrine16)

finish("test_bc16_sheet")
