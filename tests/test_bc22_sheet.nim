## The eleven knobs, the ENVELOPE RESOLVER, and the D1 assertion.
##
## §Tests item 13. Two things here are the LEARNINGS 2026-09-08 finding made
## into a gate: the envelope resolver, and the fact that bc22 — and ONLY bc22 —
## counts an ABSENT known key in `sheet_defaults_applied`.

import std/[json, strutils, unicode]
import harness
import bc22_fixture

proc bc22(text: string): Sheet = parseReply(text, "bc22")
proc knobs(text: string): Doctrine22 = bc22(text).doctrine22

# --- absent keys are RECORDED (the envelope pin, item 2) --------------------
block:
  let s = bc22("""{"sheet":{}}""")
  checkEq("an empty bc22 sheet reports ALL ELEVEN knobs as defaulted",
    s.defaultsApplied.len, 11)
  var missing: seq[string]
  for key in KnownKeys22:
    if key notin s.defaultsApplied: missing.add(key)
  checkEq("and names every one of them", missing, newSeq[string]())
  checkEq("the applied sheet is the schema default", s.doctrine22,
    defaultDoctrine22())

block:
  ## THE SCOPING ASSERTION: doing this year-neutrally would change what a
  ## bc23 episode records, which "prior years' semantics unchanged" forbids.
  let other = parseReply("""{"sheet":{}}""", "bc23")
  checkEq("a bc23 empty sheet still reports NONE",
    other.defaultsApplied.len, 0)
  let bc26sheet = parseReply("""{"sheet":{}}""", "bc26")
  checkEq("and so does a bc26 one", bc26sheet.defaultsApplied.len, 0)

block:
  let s = bc22("""{"sheet":{"opening":"soldier_rush","miner_count_curve":"heavy",
    "mine_floor":3,"soldier_sage_ratio":20,"lab_round":140,"lab_solitude":4,
    "gold_use":"mutations","watchtower_policy":"forward",
    "anomaly_play":"ignore","archon_relocate":"lead","retreat_hp":70}}""")
  checkEq("a complete sheet reports NOTHING defaulted",
    s.defaultsApplied.len, 0)
  checkEq("opening", s.doctrine22.opening, opSoldierRush)
  checkEq("miner_count_curve", s.doctrine22.minerCountCurve, mcHeavy)
  checkEq("mine_floor", s.doctrine22.mineFloor, 3)
  checkEq("soldier_sage_ratio", s.doctrine22.soldierSageRatio, 20)
  checkEq("lab_round", s.doctrine22.labRound, 140)
  checkEq("lab_solitude", s.doctrine22.labSolitude, 4)
  checkEq("gold_use", s.doctrine22.goldUse, guMutations)
  checkEq("watchtower_policy", s.doctrine22.watchtowerPolicy, wpForward)
  checkEq("anomaly_play", s.doctrine22.anomalyPlay, apIgnore)
  checkEq("archon_relocate", s.doctrine22.archonRelocate, arLead)
  checkEq("retreat_hp", s.doctrine22.retreatHp, 70)

# --- repairs ----------------------------------------------------------------
block:
  let s = bc22("""{"sheet":{"opening":42,"gold_use":"platinum",
    "watchtower_policy":["home"],"lab_round":"soon"}}""")
  checkEq("a mistyped enum takes its default", s.doctrine22.opening,
    opMinerEco)
  checkEq("an unknown enum value likewise", s.doctrine22.goldUse, guSages)
  checkEq("an array where a string belongs likewise",
    s.doctrine22.watchtowerPolicy, wpHome)
  checkEq("and a NON-INTEGER integer knob takes its default",
    s.doctrine22.labRound, 300)
  for key in ["opening", "gold_use", "watchtower_policy", "lab_round"]:
    check("the repair is recorded: " & key, key in s.defaultsApplied)

block:
  ## AN INTEGER KNOB CLAMPS, never defaults, so "as much as possible" still
  ## means something.
  let low = knobs("""{"sheet":{"mine_floor":-9,"soldier_sage_ratio":-40,
    "lab_round":0,"lab_solitude":-1,"retreat_hp":-5}}""")
  checkEq("mine_floor clamps low", low.mineFloor, MineFloorLo)
  checkEq("soldier_sage_ratio clamps low", low.soldierSageRatio,
    SoldierSageRatioLo)
  checkEq("lab_round clamps low", low.labRound, LabRoundLo)
  checkEq("lab_solitude clamps low", low.labSolitude, LabSolitudeLo)
  checkEq("retreat_hp clamps low", low.retreatHp, RetreatHpLo)
  let high = knobs("""{"sheet":{"mine_floor":99,"soldier_sage_ratio":900,
    "lab_round":99999,"lab_solitude":900,"retreat_hp":900}}""")
  checkEq("mine_floor clamps high", high.mineFloor, MineFloorHi)
  checkEq("soldier_sage_ratio clamps high", high.soldierSageRatio,
    SoldierSageRatioHi)
  checkEq("lab_round clamps high", high.labRound, LabRoundHi)
  checkEq("lab_solitude clamps high", high.labSolitude, LabSolitudeHi)
  checkEq("retreat_hp clamps high", high.retreatHp, RetreatHpHi)

block:
  ## Enum values are case-folded, trimmed and `-`/space normalised.
  let s = knobs("""{"sheet":{"opening":" Soldier-Rush ",
    "miner_count_curve":"HEAVY","archon_relocate":"Lead",
    "anomaly_play":"Time Pushes"}}""")
  checkEq("case, dashes and padding all fold", s.opening, opSoldierRush)
  checkEq("upper case folds", s.minerCountCurve, mcHeavy)
  checkEq("mixed case folds", s.archonRelocate, arLead)
  checkEq("and a SPACE normalises to the underscore the enum spells",
    s.anomalyPlay, apTimePushes)

# --- D1: a submitted `chassis` is recorded and NEVER honoured ---------------
block:
  let s = bc22("""{"sheet":{"chassis":"examplefuncsplayer22",
    "opening":"sage_spam"}}""")
  check("`chassis` lands in sheet_unknown_fields",
    "chassis" in s.unknownFields)
  check("and is NOT a known key", "chassis" notin KnownKeys22)
  checkEq("the rest of the sheet still applies", s.doctrine22.opening,
    opSageSpam)
  checkEq("the knob table is exactly eleven names", KnownKeys22.len, 11)

block:
  var body = """{"sheet":{"""
  for i in 0 ..< 40:
    if i > 0: body.add(",")
    body.add("\"junk" & $i & "\":1")
  body.add("}}")
  let s = bc22(body)
  check("at most sixteen unknown keys are recorded",
    s.unknownFields.len <= MaxUnknownFields)
  for field in s.unknownFields:
    check("each is at most forty runes",
      field.runeLen <= MaxUnknownFieldRunes)

# --- THE ENVELOPE RESOLVER ---------------------------------------------------
block:
  let flat = bc22("""{"opening":"sage_spam","retreat_hp":10}""")
  checkEq("a BARE FLAT sheet needs no envelope", flat.envelope, "")
  checkEq("and its knobs apply", flat.doctrine22.opening, opSageSpam)

  let sheeted = bc22("""{"sheet":{"opening":"sage_spam"}}""")
  checkEq("a `sheet` envelope is recorded as such", sheeted.envelope, "sheet")
  checkEq("and its knobs apply", sheeted.doctrine22.opening, opSageSpam)

  let doctrine = bc22("""{"doctrine":{"opening":"sage_spam"}}""")
  checkEq("a `doctrine` envelope is recorded", doctrine.envelope, "doctrine")
  checkEq("and its knobs apply", doctrine.doctrine22.opening, opSageSpam)

  let protocol = bc22(
    """{"protocol":"cogame.battlecode.v1","doctrine":{"opening":"sage_spam"}}""")
  checkEq("THE EXACT SHAPE THAT LOST TWO BC23 LEAGUE ROUNDS is unwrapped",
    protocol.envelope, "doctrine")
  checkEq("and its knobs apply", protocol.doctrine22.opening, opSageSpam)
  checkEq("so it does NOT report all eleven defaulted",
    protocol.defaultsApplied.len, 10)

  let named = bc22("""{"battlecode_2022_doctrine":{"opening":"sage_spam"}}""")
  checkEq("a SINGLE object-valued key is unwrapped", named.envelope,
    "battlecode_2022_doctrine")
  checkEq("and its knobs apply", named.doctrine22.opening, opSageSpam)

  let cased = bc22("""{"Doctrine":{"opening":"sage_spam"}}""")
  checkEq("the key name folds through normalizeKey", cased.envelope,
    "doctrine")
  let dashed = bc22("""{"my-sheet":{"opening":"sage_spam"}}""")
  checkEq("and a dashed one-off key resolves", dashed.envelope, "my_sheet")

  let both = bc22("""{"opening":"soldier_rush","doctrine":{"opening":"sage_spam"}}""")
  checkEq("with BOTH a known knob key and a `doctrine` key, THE FLAT ONE WINS",
    both.envelope, "")
  checkEq("so the flat value applies", both.doctrine22.opening, opSoldierRush)

  let two = bc22("""{"alpha":{"opening":"sage_spam"},"beta":{"x":1}}""")
  checkEq("TWO object-valued keys is ambiguous, so nothing is unwrapped",
    two.envelope, "")
  checkEq("and the seat plays the defaults", two.doctrine22.opening,
    opMinerEco)

  let nested = bc22("""{"doctrine":{"sheet":{"opening":"sage_spam"}}}""")
  checkEq("nesting is unwrapped AT MOST ONCE", nested.envelope, "doctrine")
  checkEq("so the inner sheet is NOT reached", nested.doctrine22.opening,
    opMinerEco)

# --- free text --------------------------------------------------------------
block:
  var notes = ""
  for i in 0 ..< 400: notes.add("\u00e9")
  var motto = ""
  for i in 0 ..< 90: notes.add("x")
  for i in 0 ..< 90: motto.add("\U0001F600")
  let s = validate(%*{"sheet": {}, "notes": notes, "motto": motto}, "bc22")
  checkEq("notes are cut to 280 RUNES", s.notes.runeLen, MaxNoteRunes)
  checkEq("motto to 48 RUNES", s.motto.runeLen, MaxMottoRunes)
  check("and the result is still valid UTF-8", s.motto.validateUtf8() == -1)
  check("even at the astral plane", s.motto.runeLen * 4 >= s.motto.len)

block:
  ## The 16 KB cap is measured in BYTES and still cut on a rune boundary.
  var padded = """{"sheet":{"mine_floor":5}}"""
  while padded.len < MaxReplyBytes * 2: padded.add("\u{1F600}")
  let s = bc22(padded)
  checkEq("the object at the front of an over-long reply still applies",
    s.doctrine22.mineFloor, 5)
  ## And the cap really BITES: astral text INSIDE the object runs past the
  ## byte cap, the reply is cut mid-object and cannot be parsed, and the seat
  ## retries. Under a RUNE-based cut this reply came through whole, at four
  ## times the cap.
  var notes = ""
  for i in 0 ..< 8000: notes.add("\u{1F600}")
  let overCap = "{\"sheet\":{\"mine_floor\":5},\"notes\":\"" & notes & "\"}"
  check("the over-cap reply is over the cap", overCap.len > MaxReplyBytes)
  var raised = false
  try:
    discard bc22(overCap)
  except CatchableError:
    raised = true
  check("a reply whose object runs past the BYTE cap does not parse", raised)
  check("and every cut lands on a rune boundary",
    overCap.truncateBytes(MaxReplyBytes).validateUtf8() < 0)

# --- plainWords22: complete clauses, no article concatenation ---------------
block:
  ## THE "a accelerating" FIX. bc23 shipped that string because it
  ## concatenated `"a "` with an enum value; every clause here is a complete
  ## phrase and this asserts it for EVERY VALUE OF EVERY KNOB.
  var checked = 0
  var bad = 0
  proc audit(d: Doctrine22) =
    for clause in plainWords22(d):
      inc checked
      if clause.len == 0: inc bad
      if clause.startsWith("a ") or clause.startsWith("an ") or
         clause.endsWith(" a") or clause.endsWith(" an") or
         " a " & "_" in clause: inc bad
      if "_" in clause: inc bad
  for opening in Opening22:
    for curve in MinerCurve:
      for gold in GoldUse:
        for tower in WatchtowerPolicy:
          for play in AnomalyPlay:
            for reloc in ArchonRelocate:
              var d = defaultDoctrine22()
              d.opening = opening
              d.minerCountCurve = curve
              d.goldUse = gold
              d.watchtowerPolicy = tower
              d.anomalyPlay = play
              d.archonRelocate = reloc
              audit(d)
  for floorAmount in MineFloorLo .. MineFloorHi:
    var d = defaultDoctrine22()
    d.mineFloor = floorAmount
    audit(d)
  for hp in [0, 40, 90, 100]:
    var d = defaultDoctrine22()
    d.retreatHp = hp
    audit(d)
  for solitude in [0, 4, 12, 30, 40]:
    var d = defaultDoctrine22()
    d.labSolitude = solitude
    audit(d)
  for ratio in [0, 15, 65, 90, 100]:
    var d = defaultDoctrine22()
    d.soldierSageRatio = ratio
    audit(d)
  check("every knob value produced clauses", checked > 2000)
  checkEq("and every one is a non-empty, article-free complete clause", bad, 0)

block:
  ## The schema the prompt carries is GENERATED from the knob table, so a knob
  ## cannot exist in the sim and be missing from the brief.
  let schema = bc22SheetSchema()
  for key in KnownKeys22:
    check("the brief carries " & key, schema.hasKey(key))
  checkEq("and nothing else", schema.len, KnownKeys22.len)
  check("`chassis` is NOT in the brief", not schema.hasKey("chassis"))

block:
  ## `toJson22` round-trips through `validate`.
  let s = bc22("""{"sheet":{"opening":"sage_spam","mine_floor":4,
    "lab_solitude":2,"retreat_hp":80}}""")
  let again = validate(%*{"sheet": toJson22(s.doctrine22)}, "bc22")
  checkEq("an applied sheet re-validates to itself", again.doctrine22,
    s.doctrine22)
  checkEq("and reports nothing defaulted, because it is complete",
    again.defaultsApplied.len, 0)

finish("test_bc22_sheet")
