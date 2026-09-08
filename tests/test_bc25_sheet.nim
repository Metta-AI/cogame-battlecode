## bc25's ten knobs through the SAME `validate` the LLM path uses: absent ->
## default, out of range -> default + recorded, mistyped -> default +
## recorded; `unit_mix` and `tower_type_order` malformations taking the WHOLE
## default and recording ONCE; the clamps and the normalisation; unknown keys
## recorded and capped; A SUBMITTED `chassis` RECORDED AND NEVER HONOURED (the
## D1 assertion); and rune-boundary truncation including astral-plane text.

import std/[json, strutils, unicode]
import harness
import bc25_fixture

proc sheetOf(text: string): Sheet = parseReply(text, "bc25")

# --- absent -> default ------------------------------------------------------
block:
  let s = sheetOf("""{"sheet":{}}""")
  let d = defaultDoctrine25()
  checkEq("opening", s.doctrine25.opening, d.opening)
  checkEq("unit_mix", s.doctrine25.unitMix, d.unitMix)
  checkEq("srp_priority", s.doctrine25.srpPriority, d.srpPriority)
  checkEq("tower_type_order", s.doctrine25.towerTypeOrder, d.towerTypeOrder)
  checkEq("ruin_claim_radius", s.doctrine25.ruinClaimRadius,
    d.ruinClaimRadius)
  checkEq("defense_tower_chokes", s.doctrine25.defenseTowerChokes,
    d.defenseTowerChokes)
  checkEq("paint_reserve_floor", s.doctrine25.paintReserveFloor,
    d.paintReserveFloor)
  checkEq("mop_enemy_paint", s.doctrine25.mopEnemyPaint, d.mopEnemyPaint)
  checkEq("splash_targets", s.doctrine25.splashTargets, d.splashTargets)
  checkEq("upgrade_policy", s.doctrine25.upgradePolicy, d.upgradePolicy)
  checkEq("nothing was repaired", s.defaultsApplied.len, 0)
  checkEq("and nothing was unknown", s.unknownFields.len, 0)

# --- every scalar knob, accepted / out of range / mistyped ------------------
block:
  for (key, good, lo, hi) in [("srp_priority", 0, -1, 101),
                              ("ruin_claim_radius", 4, 3, 21),
                              ("paint_reserve_floor", 10, 9, 71),
                              ("mop_enemy_paint", 100, -1, 101)]:
    let ok = sheetOf("""{"sheet":{"""" & key & """":""" & $good & "}}")
    checkEq(key & " accepts an in-range value", ok.defaultsApplied.len, 0)
    for bad in [lo, hi]:
      let s = sheetOf("""{"sheet":{"""" & key & """":""" & $bad & "}}")
      checkEq(key & " rejects " & $bad & " and records it",
        s.defaultsApplied, @[key])
    let mistyped = sheetOf("""{"sheet":{"""" & key & """":"nonsense"}}""")
    checkEq(key & " rejects a string", mistyped.defaultsApplied, @[key])

block:
  for (key, good) in [("opening", "tower_rush"),
                      ("defense_tower_chokes", "early"),
                      ("splash_targets", "towers"),
                      ("upgrade_policy", "defense_first")]:
    let ok = sheetOf("""{"sheet":{"""" & key & """":"""" & good & """"}}""")
    checkEq(key & " accepts a known value", ok.defaultsApplied.len, 0)
    let bad = sheetOf("""{"sheet":{"""" & key & """":"nope"}}""")
    checkEq(key & " rejects an unknown one", bad.defaultsApplied, @[key])
    let num = sheetOf("""{"sheet":{"""" & key & """":7}}""")
    checkEq(key & " rejects a number", num.defaultsApplied, @[key])

block:
  let s = sheetOf("""{"sheet":{"opening":"TOWER RUSH"}}""")
  checkEq("enum values are read tolerantly", s.doctrine25.opening, opTowerRush)
  checkEq("with nothing recorded", s.defaultsApplied.len, 0)

# --- unit_mix ---------------------------------------------------------------
block:
  let s = sheetOf(
    """{"sheet":{"unit_mix":{"soldier":50,"mopper":30,"splasher":20}}}""")
  checkEq("a well-formed mix is taken", s.doctrine25.unitMix,
    UnitMix(soldier: 50, mopper: 30, splasher: 20))
  checkEq("and nothing recorded", s.defaultsApplied.len, 0)

block:
  for bad in ["""{"soldier":50,"mopper":30}""",
              """{"soldier":50,"mopper":30,"splasher":-1}""",
              """{"soldier":50,"mopper":30,"splasher":"x"}""",
              """[50,30,20]""",
              """{"soldier":0,"mopper":0,"splasher":0}""",
              """{"soldier":50,"mopper":30,"splasher":20,"extra":1}"""]:
    let s = sheetOf("""{"sheet":{"unit_mix":""" & bad & "}}")
    checkEq("a malformed mix takes the WHOLE default: " & bad,
      s.doctrine25.unitMix, DefaultUnitMix)
    checkEq("and is recorded exactly ONCE", s.defaultsApplied, @["unit_mix"])

block:
  ## The clamps are the anti-inert floor, and the normalisation is exact.
  for mix in [UnitMix(soldier: 100, mopper: 0, splasher: 0),
              UnitMix(soldier: 0, mopper: 100, splasher: 0),
              UnitMix(soldier: 0, mopper: 0, splasher: 100),
              UnitMix(soldier: 1, mopper: 1, splasher: 1),
              UnitMix(soldier: 80, mopper: 10, splasher: 10),
              UnitMix(soldier: 30, mopper: 10, splasher: 60)]:
    let n = normalisedMix(mix)
    checkEq("the three shares sum to exactly 100 (" & $mix & ")",
      n.soldier + n.mopper + n.splasher, 100)
    check("soldiers never fall below 30", n.soldier >= MinSoldierShare)
    check("moppers never below 10", n.mopper >= MinMopperShare)
    check("splashers never below 10", n.splasher >= MinSplasherShare)

# --- tower_type_order -------------------------------------------------------
block:
  let s = sheetOf(
    """{"sheet":{"tower_type_order":["paint","defense","money"]}}""")
  checkEq("a well-formed order is taken", s.doctrine25.towerTypeOrder,
    [tkPaint, tkDefense, tkMoney])
  checkEq("with nothing recorded", s.defaultsApplied.len, 0)

block:
  for bad in ["""["paint","money"]""",
              """["paint","money","defense","paint"]""",
              """["paint","paint","money"]""",
              """["paint","money","tower"]""",
              """["paint",7,"money"]""",
              "\"paint,money,defense\""]:
    let s = sheetOf("""{"sheet":{"tower_type_order":""" & bad & "}}")
    checkEq("a malformed order takes the WHOLE default: " & bad,
      s.doctrine25.towerTypeOrder, DefaultTowerOrder)
    checkEq("and is recorded exactly ONCE", s.defaultsApplied,
      @["tower_type_order"])

# --- D1: a submitted `chassis` is recorded and NEVER honoured --------------
block:
  let s = sheetOf(
    """{"sheet":{"chassis":"spaark","opening":"paint_eco"}}""")
  check("`chassis` is recorded as an unknown field",
    "chassis" in s.unknownFields)
  checkEq("the real knob beside it still applied", s.doctrine25.opening,
    opPaintEco)
  check("and `chassis` is NOT one of the ten known keys",
    "chassis" notin knownKeysFor("bc25"))
  checkEq("there are exactly ten known keys", knownKeysFor("bc25").len, 10)

# --- unknown keys are capped ------------------------------------------------
block:
  var body = ""
  for i in 0 .. 39:
    if body.len > 0: body.add(",")
    body.add("\"unknown_key_number_" & $i & "\":1")
  let s = sheetOf("""{"sheet":{""" & body & "}}")
  check("at most sixteen unknown keys are recorded",
    s.unknownFields.len <= MaxUnknownFields)
  for f in s.unknownFields:
    check("each is at most forty runes", f.runeLen <= MaxUnknownFieldRunes)

# --- rune-boundary truncation ----------------------------------------------
block:
  var notes = ""
  for i in 0 .. 499: notes.add("\u00e9")     ## two bytes each
  var motto = ""
  for i in 0 .. 99: motto.add("\U0001F3A8")  ## FOUR bytes each, astral plane
  let s = validate(%*{"sheet": {}, "notes": notes, "motto": motto}, "bc25")
  checkEq("notes are capped at 280 RUNES", s.notes.runeLen, MaxNoteRunes)
  checkEq("motto at 48 RUNES", s.motto.runeLen, MaxMottoRunes)
  check("and both are still valid UTF-8", s.notes.validateUtf8() < 0 and
    s.motto.validateUtf8() < 0)

block:
  ## The 16 KB whole-reply cap is measured in BYTES and still cut on a rune
  ## boundary, which is what `truncateBytes` exists for.
  var huge = "{\"sheet\":{\"notes\":\""
  for i in 0 .. 20_000: huge.add("\U0001F3A8")
  huge.add("\"}}")
  let capped = huge.truncateBytes(MaxReplyBytes)
  check("the cap is in bytes", capped.len <= MaxReplyBytes)
  check("and it lands on a rune boundary", capped.validateUtf8() < 0)
  ## A reply cut mid-string no longer parses, and THAT is the one condition
  ## the retry and then the scripted fallback exist for: `parseReply` raises,
  ## `decide.nim` catches it, and the seat plays the fallback sheet.
  var raised = false
  try:
    discard parseReply(huge, "bc25")
  except CatchableError:
    raised = true
  check("a reply cut mid-string raises, which is the fallback trigger",
    raised)
  check("while a legal short reply does not",
    parseReply("""{"sheet":{}}""", "bc25").doctrine25 ==
      defaultDoctrine25())

# --- the round trip ---------------------------------------------------------
block:
  let s = sheetOf("""{"sheet":{"opening":"tower_rush","srp_priority":0,
    "unit_mix":{"soldier":40,"mopper":20,"splasher":40},
    "tower_type_order":["defense","money","paint"],
    "ruin_claim_radius":6,"defense_tower_chokes":"early",
    "paint_reserve_floor":20,"mop_enemy_paint":15,
    "splash_targets":"towers","upgrade_policy":"defense_first"}}""")
  let j = toJson25(s.doctrine25)
  checkEq("toJson round-trips the opening", j["opening"].getStr(),
    "tower_rush")
  checkEq("the mix", j["unit_mix"]["splasher"].getInt(), 40)
  checkEq("the order", j["tower_type_order"][0].getStr(), "defense")
  check("and plainWords says something for every knob",
    plainWords25(s.doctrine25).len >= 10)

finish("test_bc25_sheet")
