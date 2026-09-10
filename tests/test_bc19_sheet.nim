## The bc19 doctrine sheet: eleven knobs, NO `chassis` key, absent-key
## defaulting, and the envelope resolver FROM THE BC19 SIDE.

import std/[json, strutils, unicode]
import harness
import battlecode/sheet

proc parse(text: string): Sheet = parseReply(text, YearBc19)

block:
  checkEq("exactly eleven knobs", KnownKeys19.len, 11)
  for k in ["opening", "pilgrim_curve", "church_expansion", "fuel_reserve",
            "unit_mix", "preacher_share", "church_saber_round",
            "symmetry_wall", "castle_talk_use", "defend_radius",
            "trade_policy"]:
    check("the table names " & k, k in KnownKeys19)
  check("AND `chassis` IS NOT A KNOB (D1)", "chassis" notin KnownKeys19)

block:
  ## THE ENVELOPE PIN, ITEM 2: an ABSENT known key is recorded too, so
  ## `sheet_defaults_applied` is `[]` only when the cog really set all
  ## eleven.
  let empty = parse("""{"sheet":{}}""")
  checkEq("an empty bc19 sheet records ALL ELEVEN names",
    empty.defaultsApplied.len, 11)
  for k in KnownKeys19:
    check("including " & k, k in empty.defaultsApplied)
  ## AND THE CHANGE IS PROVABLY SCOPED: a bc23 empty sheet still records
  ## none, because doing this year-neutrally would change what every shipped
  ## year records in that array.
  let bc23 = parseReply("""{"sheet":{}}""", YearBc23)
  checkEq("a bc23 empty sheet still records NONE",
    bc23.defaultsApplied.len, 0)
  let bc26 = parseReply("""{"sheet":{}}""", YearBc26)
  checkEq("and neither does bc26", bc26.defaultsApplied.len, 0)

block:
  ## The five ENUM knobs: an unknown value takes the default and is
  ## recorded; the value is case-folded, trimmed and `-`/space normalised.
  let good = parse("""{"sheet":{"opening":"  PREACHER-RUSH ",
    "church_expansion":"Early","symmetry_wall":"WALL",
    "castle_talk_use":"full","trade_policy":"offer fuel"}}""")
  checkEq("opening normalises", good.doctrine19.opening, op19PreacherRush)
  checkEq("church_expansion normalises", good.doctrine19.churchExpansion,
    ce19Early)
  checkEq("symmetry_wall normalises", good.doctrine19.symmetryWall, sw19Wall)
  checkEq("castle_talk_use normalises", good.doctrine19.castleTalkUse,
    ct19Full)
  checkEq("trade_policy normalises with a SPACE", good.doctrine19.tradePolicy,
    tp19OfferFuel)
  for k in ["opening", "church_expansion", "symmetry_wall",
            "castle_talk_use", "trade_policy"]:
    check("and a normalised value is NOT recorded as defaulted: " & k,
      k notin good.defaultsApplied)
  let bad = parse("""{"sheet":{"opening":"nonsense","trade_policy":42}}""")
  checkEq("an unknown enum value takes the default",
    bad.doctrine19.opening, op19PilgrimEco)
  check("and is recorded", "opening" in bad.defaultsApplied)
  checkEq("a mistyped enum takes the default too",
    bad.doctrine19.tradePolicy, tp19Mirror)
  check("and is recorded", "trade_policy" in bad.defaultsApplied)

block:
  ## THE SIX INTEGER KNOBS CLAMP rather than defaulting, so "as many as
  ## possible" still means something -- and a NON-INTEGER takes the default.
  let hi = parse("""{"sheet":{"pilgrim_curve":9999,"fuel_reserve":100000,
    "unit_mix":500,"preacher_share":-40,"church_saber_round":5000,
    "defend_radius":100000}}""")
  checkEq("pilgrim_curve clamps to its maximum", hi.doctrine19.pilgrimCurve,
    PilgrimCurveHi)
  checkEq("fuel_reserve clamps", hi.doctrine19.fuelReserve, FuelReserveHi)
  checkEq("unit_mix clamps", hi.doctrine19.unitMix, UnitMixHi)
  checkEq("preacher_share clamps to its MINIMUM from below",
    hi.doctrine19.preacherShare, PreacherShareLo)
  checkEq("church_saber_round clamps", hi.doctrine19.churchSaberRound,
    ChurchSaberRoundHi)
  checkEq("defend_radius clamps", hi.doctrine19.defendRadius, DefendRadiusHi)
  for k in ["pilgrim_curve", "fuel_reserve", "unit_mix", "preacher_share",
            "church_saber_round", "defend_radius"]:
    check("and every clamp is recorded: " & k, k in hi.defaultsApplied)
  let inRange = parse("""{"sheet":{"pilgrim_curve":12,"fuel_reserve":250,
    "unit_mix":70,"preacher_share":30,"church_saber_round":400,
    "defend_radius":49}}""")
  checkEq("an in-range integer is taken as given",
    inRange.doctrine19.pilgrimCurve, 12)
  checkEq("and so is defend_radius", inRange.doctrine19.defendRadius, 49)
  for k in ["pilgrim_curve", "fuel_reserve", "unit_mix", "preacher_share",
            "church_saber_round", "defend_radius"]:
    check("and an in-range integer is NOT recorded: " & k,
      k notin inRange.defaultsApplied)
  let nonInt = parse("""{"sheet":{"fuel_reserve":"lots",
    "church_saber_round":{}}}""")
  checkEq("a NON-INTEGER takes the default", nonInt.doctrine19.fuelReserve,
    300)
  checkEq("and so does an object", nonInt.doctrine19.churchSaberRound, 0)

block:
  ## A SUBMITTED `chassis` IS RECORDED AS AN UNKNOWN FIELD AND NEVER
  ## HONOURED. The test fails if anyone re-adds the knob.
  let s = parse("""{"sheet":{"chassis":"examplefuncsplayer19",
    "opening":"turtle"}}""")
  check("`chassis` lands in sheet_unknown_fields",
    "chassis" in s.unknownFields)
  check("and it is NOT in defaults_applied", "chassis" notin s.defaultsApplied)
  checkEq("while the real knob still applied", s.doctrine19.opening,
    op19Turtle)
  ## Unknown keys are bounded and truncated.
  var many = """{"sheet":{"""
  for i in 0 .. 39:
    if i > 0: many.add(",")
    many.add("\"" & repeat("z", 80) & $i & "\":1")
  many.add("}}")
  let bulk = parse(many)
  check("unknown keys are capped", bulk.unknownFields.len <= MaxUnknownFields)
  for f in bulk.unknownFields:
    check("and each is truncated on a rune boundary",
      f.runeLen <= MaxUnknownFieldRunes)

block:
  ## THE ENVELOPE RESOLVER, from the bc19 side. Nesting is unwrapped AT MOST
  ## ONCE and the rule that fired is recorded.
  let flat = parse("""{"opening":"turtle","notes":"n"}""")
  checkEq("a bare flat sheet records no envelope", flat.envelope, "")
  checkEq("and applies", flat.doctrine19.opening, op19Turtle)
  let wrapped = parse("""{"sheet":{"opening":"turtle"}}""")
  checkEq("`sheet` is recorded", wrapped.envelope, "sheet")
  checkEq("and applies", wrapped.doctrine19.opening, op19Turtle)
  let doctrine = parse("""{"doctrine":{"opening":"turtle"}}""")
  checkEq("`doctrine` is recorded", doctrine.envelope, "doctrine")
  checkEq("and applies", doctrine.doctrine19.opening, op19Turtle)
  let proto = parse("""{"protocol":"x","doctrine":{"opening":"turtle"}}""")
  checkEq("a protocol envelope resolves to `doctrine`", proto.envelope,
    "doctrine")
  checkEq("and applies", proto.doctrine19.opening, op19Turtle)
  let single = parse("""{"battlecode_2019_doctrine":{"opening":"turtle"}}""")
  checkEq("a single object-valued key is recorded by name",
    single.envelope, "battlecode_2019_doctrine")
  checkEq("and applies", single.doctrine19.opening, op19Turtle)
  let both = parse("""{"opening":"turtle","doctrine":{"opening":"pilgrim_eco"}}""")
  checkEq("a payload with BOTH a known knob and a `doctrine` key uses the " &
    "FLAT one", both.envelope, "")
  checkEq("and the flat value wins", both.doctrine19.opening, op19Turtle)
  let two = parse("""{"a":{"opening":"turtle"},"b":{"opening":"turtle"}}""")
  checkEq("two object-valued keys unwrap NOTHING", two.envelope, "")
  checkEq("so every knob defaults", two.defaultsApplied.len, 11)
  let nested = parse("""{"sheet":{"sheet":{"opening":"turtle"}}}""")
  checkEq("nesting is unwrapped AT MOST ONCE", nested.envelope, "sheet")
  checkEq("so the inner one is an unknown field", nested.unknownFields, @["sheet"])

block:
  ## Rune-boundary truncation, INCLUDING astral-plane characters, and the
  ## 16 384-BYTE reply cap.
  let long = repeat("\u1F3F0", 400)          ## a castle emoji, 4 bytes each
  let s = parse("""{"sheet":{},"notes":"""" & long & """","motto":"""" &
    long & """"}""")
  check("notes is capped at 280 RUNES", s.notes.runeLen <= MaxNoteRunes)
  check("motto is capped at 48 RUNES", s.motto.runeLen <= MaxMottoRunes)
  check("and both are still valid UTF-8", validateUtf8(s.notes) < 0 and
    validateUtf8(s.motto) < 0)
  ## The whole reply is cut at 16 384 BYTES on a rune boundary -- a
  ## rune-count cap would keep up to 64 KB of astral-plane text.
  checkEq("the reply cap is 16384 BYTES", MaxReplyBytes, 16 * 1024)
  let huge = "{\"sheet\":{\"opening\":\"turtle\"},\"notes\":\"" &
    repeat("\u1F3F0", 20000) & "\"}"
  check("a 80 KB reply is longer than the cap", huge.len > MaxReplyBytes)
  let cut = truncateBytes(huge, MaxReplyBytes)
  check("and the cut is at most the cap", cut.len <= MaxReplyBytes)
  check("and lands on a rune boundary", validateUtf8(cut) < 0)

block:
  ## `plainWords19` returns a NON-EMPTY, ARTICLE-FREE COMPLETE CLAUSE for
  ## EVERY value of EVERY knob -- the endcard fix that stops
  ## "a accelerating"-class grammar.
  var d = defaultDoctrine19()
  proc words(d: Doctrine19): seq[string] = plainWords19(d)
  checkEq("eleven clauses", words(d).len, 11)
  for o in Opening19:
    d = defaultDoctrine19()
    d.opening = o
    for w in words(d):
      check("no empty clause for opening " & $o, w.len > 0)
      check("and no article concatenation", not w.startsWith("a ") or
        w.len > 3)
  for c in ChurchExpansion19:
    d = defaultDoctrine19()
    d.churchExpansion = c
    check("church_expansion " & $c & " reads as a clause", words(d)[2].len > 8)
  for wl in SymmetryWall19:
    d = defaultDoctrine19()
    d.symmetryWall = wl
    check("symmetry_wall " & $wl & " reads as a clause", words(d)[7].len > 8)
  for ct in CastleTalkUse19:
    d = defaultDoctrine19()
    d.castleTalkUse = ct
    check("castle_talk_use " & $ct & " reads as a clause", words(d)[8].len > 8)
  for tp in TradePolicy19:
    d = defaultDoctrine19()
    d.tradePolicy = tp
    check("trade_policy " & $tp & " reads as a clause", words(d)[10].len > 8)
  for v in [PilgrimCurveLo, 9, PilgrimCurveHi]:
    d = defaultDoctrine19()
    d.pilgrimCurve = v
    check("pilgrim_curve " & $v & " reads as a clause", words(d)[1].len > 8)

block:
  ## `toJson19` round-trips through `validate` with nothing defaulted --
  ## which is what `replay.nim` relies on when it re-validates the recorded
  ## APPLIED sheet.
  var d = defaultDoctrine19()
  d.opening = op19PreacherRush
  d.pilgrimCurve = 5
  d.churchExpansion = ce19Never
  d.fuelReserve = 120
  d.unitMix = 10
  d.preacherShare = 70
  d.churchSaberRound = 250
  d.symmetryWall = sw19Off
  d.castleTalkUse = ct19Full
  d.defendRadius = 36
  d.tradePolicy = tp19OfferFuel
  let round = validate(%*{"sheet": toJson19(d)}, YearBc19)
  checkEq("the applied sheet round-trips", round.doctrine19, d)
  checkEq("with NOTHING defaulted", round.defaultsApplied.len, 0)
  checkEq("and no unknown field", round.unknownFields.len, 0)

block:
  ## The schema the prompt carries is generated from the table, so a knob
  ## cannot exist in the sim and be missing from the brief.
  let schema = bc19SheetSchema()
  checkEq("the schema names eleven knobs", schema.len, 11)
  for k in KnownKeys19:
    check("the schema declares " & k, schema.hasKey(k))
    check("with a default", schema[k].hasKey("default"))

finish("test_bc19_sheet")
