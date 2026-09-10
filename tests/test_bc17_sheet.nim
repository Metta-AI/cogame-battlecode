## §Tests item 17 -- the sheet: eleven knobs, and the envelope resolver from
## the bc17 side.
##
## The bc17 knob surface joins bc22, bc16 and bc19 in counting an **ABSENT**
## known key in `defaults_applied`, so a seat that played the schema defaults
## is machine-visible rather than looking like a seat that chose them. The
## change is PROVABLY SCOPED: a bc19 empty sheet still records what it always
## did, and this shard asserts both halves.
##
## The other half of the file is the LEARNINGS 2026-09-08 envelope pin. An
## LLM champion that wraps its sheet in a protocol envelope used to have every
## knob land in `sheet_unknown_fields` and play the defaults while
## `sheet_defaults_applied` stayed EMPTY -- it happened in 2 of the first 3
## bc23 league rounds and one champion won on defaults. Seven payload shapes
## are checked here from the bc17 side, each with the envelope rule it must
## report.

import std/[json, strutils, unicode]
import harness
import bc17_fixture
import battlecode/years/bc17/knobs
from battlecode/years/bc17/knobs as k17 import nil

# --- eleven knobs, and only eleven ------------------------------------------
block:
  checkEq("bc17 declares exactly eleven knobs", KnownKeys17.len, 11)
  checkEq("and they are the schema's", @(KnownKeys17),
    @["opening", "gardener_count", "farm_layout", "soldier_tank_ratio",
      "lumberjack_share", "scout_harass", "vp_donate_policy",
      "shake_neutral_trees", "chop_policy", "bullet_reserve",
      "defend_radius"])
  check("`chassis` is deliberately NOT one of them",
    "chassis" notin KnownKeys17)
  checkEq("knownKeysFor agrees", knownKeysFor("bc17"), @(KnownKeys17))

# --- an EMPTY sheet records all eleven --------------------------------------
block:
  let s = doctrine("{}")
  checkEq("an empty bc17 sheet records ALL ELEVEN absent knobs",
    s.defaultsApplied.len, 11)
  for key in KnownKeys17:
    check(key & " is in defaults_applied", key in s.defaultsApplied)
  checkEq("and its doctrine is the default one", s.doctrine17,
    defaultDoctrine17())
  ## The scoping half: a bc19 empty sheet is untouched by this.
  let nineteen = parseReply("{}", "bc19")
  check("a bc19 empty sheet still records its own knobs, not bc17's",
    nineteen.defaultsApplied.len > 0)
  for key in KnownKeys17:
    if key in knownKeysFor("bc19"): continue
    check("and none of them is a bc17-only key (" & key & ")",
      key notin nineteen.defaultsApplied)

# --- a FULL sheet records none ----------------------------------------------
block:
  let s = doctrine("""{"opening":"tank_rush","gardener_count":3,
    "farm_layout":"line","soldier_tank_ratio":80,"lumberjack_share":25,
    "scout_harass":40,"vp_donate_policy":"rush_1000",
    "shake_neutral_trees":"dedicated","chop_policy":"harvest",
    "bullet_reserve":250,"defend_radius":18}""")
  checkEq("a complete sheet records NO defaults", s.defaultsApplied.len, 0)
  checkEq("opening", s.doctrine17.opening, op17TankRush)
  checkEq("gardener_count", s.doctrine17.gardenerCount, 3)
  checkEq("farm_layout", s.doctrine17.farmLayout, fl17Line)
  checkEq("soldier_tank_ratio", s.doctrine17.soldierTankRatio, 80)
  checkEq("lumberjack_share", s.doctrine17.lumberjackShare, 25)
  checkEq("scout_harass", s.doctrine17.scoutHarass, 40)
  checkEq("vp_donate_policy", s.doctrine17.vpDonatePolicy, vp17Rush1000)
  checkEq("shake_neutral_trees", s.doctrine17.shakeNeutralTrees,
    sn17Dedicated)
  checkEq("chop_policy", s.doctrine17.chopPolicy, cp17Harvest)
  checkEq("bullet_reserve", s.doctrine17.bulletReserve, 250)
  checkEq("defend_radius", s.doctrine17.defendRadius, 18)
  checkEq("and no unknown fields", s.unknownFields.len, 0)

# --- the six integer knobs CLAMP, never default -----------------------------
block:
  ## "As many gardeners as possible" must still mean something, so an
  ## out-of-range integer is clamped to the bound AND recorded.
  let low = doctrine("""{"gardener_count":-5,"soldier_tank_ratio":-1,
    "lumberjack_share":-1,"scout_harass":-1,"bullet_reserve":-1,
    "defend_radius":-1}""")
  checkEq("gardener_count clamps up to its floor",
    low.doctrine17.gardenerCount, GardenerCountLo)
  checkEq("soldier_tank_ratio too", low.doctrine17.soldierTankRatio,
    SoldierTankRatioLo)
  checkEq("lumberjack_share too", low.doctrine17.lumberjackShare,
    LumberjackShareLo)
  checkEq("scout_harass too", low.doctrine17.scoutHarass, ScoutHarassLo)
  checkEq("bullet_reserve too", low.doctrine17.bulletReserve,
    BulletReserveLo)
  checkEq("defend_radius too", low.doctrine17.defendRadius, k17.DefendReachLo)
  for key in ["gardener_count", "soldier_tank_ratio", "lumberjack_share",
              "scout_harass", "bullet_reserve", "defend_radius"]:
    check("a clamped " & key & " is RECORDED", key in low.defaultsApplied)
  let high = doctrine("""{"gardener_count":9999,"soldier_tank_ratio":9999,
    "lumberjack_share":9999,"scout_harass":9999,"bullet_reserve":999999,
    "defend_radius":9999}""")
  checkEq("gardener_count clamps down to its ceiling",
    high.doctrine17.gardenerCount, GardenerCountHi)
  checkEq("bullet_reserve too", high.doctrine17.bulletReserve,
    BulletReserveHi)
  checkEq("defend_radius too", high.doctrine17.defendRadius, k17.DefendReachHi)
  ## A NON-INTEGER takes the default rather than clamping.
  let mistyped = doctrine("""{"gardener_count":"lots"}""")
  checkEq("a mistyped integer knob takes the DEFAULT",
    mistyped.doctrine17.gardenerCount, defaultDoctrine17().gardenerCount)
  check("and is recorded", "gardener_count" in mistyped.defaultsApplied)
  ## An in-range value is neither clamped nor recorded.
  let good = doctrine("""{"gardener_count":4}""")
  checkEq("an in-range integer is taken as given",
    good.doctrine17.gardenerCount, 4)
  check("and is NOT recorded as a default",
    "gardener_count" notin good.defaultsApplied)

# --- the enums are case-folded, trimmed and dash/space normalised -----------
block:
  for text in ["TANK_RUSH", " tank_rush ", "Tank-Rush", "tank rush",
               "TANK RUSH"]:
    let s = doctrine("""{"opening":""" & escapeJsonUnquoted(text).
      escapeJson() & "}")
    checkEq("opening " & text & " resolves", s.doctrine17.opening,
      op17TankRush)
    check("and is not recorded as a default",
      "opening" notin s.defaultsApplied)
  let unknown = doctrine("""{"opening":"turtle_and_pray"}""")
  checkEq("an unknown enum takes the default", unknown.doctrine17.opening,
    defaultDoctrine17().opening)
  check("and is recorded", "opening" in unknown.defaultsApplied)
  let mistyped = doctrine("""{"opening":7}""")
  checkEq("a mistyped enum takes the default too",
    mistyped.doctrine17.opening, defaultDoctrine17().opening)
  check("and is recorded", "opening" in mistyped.defaultsApplied)

# --- unknown keys are recorded and bounded ----------------------------------
block:
  let s = doctrine("""{"opening":"tree_farm","chassis":"orchard",
    "secret_weapon":"none"}""")
  checkEq("two unknown keys were recorded", s.unknownFields.len, 2)
  check("a submitted chassis lands there", "chassis" in s.unknownFields)
  check("and it is NEVER honoured -- the chassis is not a knob",
    "chassis" notin KnownKeys17)
  ## Bounds: at most 16 unknown fields, each at most 40 runes.
  var many = "{\"opening\":\"tree_farm\""
  for i in 0 ..< 40:
    many.add(",\"junk" & $i & "\":1")
  many.add("}")
  let bounded = doctrine(many)
  check("the unknown-field list is bounded at 16",
    bounded.unknownFields.len <= 16)
  var longKey = "{\"" & repeat("z", 200) & "\":1}"
  let cut = doctrine(longKey)
  check("and each name is cut to 40 runes",
    cut.unknownFields.len == 1 and cut.unknownFields[0].runeLen <= 40)

# --- notes and motto are cut on a RUNE boundary -----------------------------
block:
  let astral = repeat("\u{1F332}", 400)   ## an evergreen tree, 4 bytes each
  let s = doctrine("""{"notes":"""" & astral & """","motto":"""" & astral &
    """"}""")
  check("notes survived as valid UTF-8", s.notes.validateUtf8() < 0)
  check("motto too", s.motto.validateUtf8() < 0)
  check("both were truncated", s.notes.runeLen < 400)
  check("on a rune boundary, so no half character",
    s.notes.len mod 4 == 0)
  ## The 16 384-BYTE reply cap, also cut on a rune boundary. The object goes
  ## FIRST and the padding after it, because the cap keeps the first 16 384
  ## bytes -- a reply whose object is cut in half is not JSON any more, which
  ## is what the retry and then the scripted fallback exist for.
  let huge = """{"opening":"tank_rush"} """ & repeat("\u{1F332}", 20000)
  check("the reply is well over the cap", huge.len > 16384)
  let capped = parseReply(huge, "bc17")
  checkEq("the object at the front survives the cap",
    capped.doctrine17.opening, op17TankRush)
  ## And a reply whose OBJECT is past the cap raises, honestly.
  var buried = repeat("\u{1F332}", 20000) & """{"opening":"tank_rush"}"""
  var raised = false
  try:
    discard parseReply(buried, "bc17")
  except CatchableError:
    raised = true
  check("while an object buried past the cap is not recovered", raised)

# --- plainWords17 is complete and article-free ------------------------------
block:
  ## EVERY value of EVERY knob maps to a complete clause. The endcard reads
  ## these out, and an article concatenation is the bug this rule exists for.
  var clauses = 0
  for opening in Opening17:
    for layout in FarmLayout17:
      for donate in VpDonatePolicy17:
        for shake in ShakeNeutralTrees17:
          for chop in ChopPolicy17:
            var d = defaultDoctrine17()
            d.opening = opening
            d.farmLayout = layout
            d.vpDonatePolicy = donate
            d.shakeNeutralTrees = shake
            d.chopPolicy = chop
            let words = plainWords17(d)
            inc clauses
            if words.len != 11:
              check("every doctrine gives eleven clauses", false)
              break
            for phrase in words:
              if phrase.len == 0:
                check("no clause is empty", false)
              if phrase.startsWith("a ") or phrase.startsWith("an ") or
                  phrase.startsWith("the "):
                check("no clause starts with an article: " & phrase, false)
  checkEq("every combination of the five enum knobs was read out",
    clauses, 4 * 3 * 4 * 3 * 3)
  check("and there are 432 of them", clauses == 432)

# --- toJson17 round-trips ----------------------------------------------------
block:
  let s = doctrine("""{"opening":"scout_squat","gardener_count":7,
    "farm_layout":"ring","vp_donate_policy":"endgame_dump",
    "chop_policy":"never","defend_radius":33}""")
  let back = doctrineOf(%*{"sheet": toJson17(s.doctrine17)})
  checkEq("an applied sheet round-trips through toJson17",
    back.doctrine17, s.doctrine17)
  checkEq("and records no defaults second time round",
    back.defaultsApplied.len, 0)
  checkEq("the JSON carries all eleven keys", toJson17(s.doctrine17).len, 11)

# --- the schema is GENERATED from the table ---------------------------------
block:
  let schema = bc17SheetSchema()
  for key in KnownKeys17:
    check("the schema declares " & key, schema.hasKey(key))
  checkEq("and nothing else", schema.len, KnownKeys17.len)

# --- the envelope resolver, seven payload shapes ----------------------------
block:
  type Shape = tuple[name, payload, envelope: string]
  let shapes: seq[Shape] = @[
    ("a bare flat sheet", """{"opening":"tank_rush"}""", ""),
    ("{\"sheet\": ...}", """{"sheet":{"opening":"tank_rush"}}""", "sheet"),
    ("{\"doctrine\": ...}", """{"doctrine":{"opening":"tank_rush"}}""",
     "doctrine"),
    ("a protocol envelope",
     """{"protocol":"v1","doctrine":{"opening":"tank_rush"}}""", "doctrine"),
    ("{\"battlecode_2017_doctrine\": ...}",
     """{"battlecode_2017_doctrine":{"opening":"tank_rush"}}""",
     "battlecode_2017_doctrine"),
    ("both a flat knob AND a doctrine key",
     """{"opening":"tank_rush","doctrine":{"opening":"tree_farm"}}""", ""),
    ("two objects and no unwrap",
     """{"a":{"opening":"tree_farm"},"b":{"opening":"tank_rush"}}""", ""),
  ]
  for shape in shapes:
    let s = doctrine(shape.payload)
    checkEq(shape.name & " reports envelope '" & shape.envelope & "'",
      s.envelope, shape.envelope)
  ## The FLAT KNOB WINS: a payload with both is used as-is, so the nested
  ## `tree_farm` is ignored and the flat `tank_rush` is applied.
  let both = doctrine(
    """{"opening":"tank_rush","doctrine":{"opening":"tree_farm"}}""")
  checkEq("with both, the FLAT knob wins", both.doctrine17.opening,
    op17TankRush)
  check("and the nested object is recorded as unknown",
    "doctrine" in both.unknownFields)
  ## Two objects and no unwrap: the payload is used as-is, so NOTHING is
  ## applied and all eleven knobs are recorded absent.
  let two = doctrine(
    """{"a":{"opening":"tree_farm"},"b":{"opening":"tank_rush"}}""")
  checkEq("with two objects, nothing is unwrapped and all eleven are absent",
    two.defaultsApplied.len, 11)
  ## Unwrapped AT MOST ONCE -- a deliberate bound.
  let nested = doctrine(
    """{"doctrine":{"doctrine":{"opening":"tank_rush"}}}""")
  checkEq("nesting is unwrapped at most once", nested.envelope, "doctrine")
  checkEq("so the doubly-nested knob is NOT applied",
    nested.doctrine17.opening, defaultDoctrine17().opening)
  ## Key names go through normalizeKey.
  for key in ["Doctrine", "my-sheet", "MY SHEET"]:
    let s = doctrine("{\"" & key & "\":{\"opening\":\"tank_rush\"}}")
    check("'" & key & "' resolves to an envelope", s.envelope.len > 0)
    checkEq("and its knob is applied", s.doctrine17.opening, op17TankRush)

# --- a reply with no JSON object at all -------------------------------------
block:
  ## The one condition the retry and then the scripted fallback exist for.
  var raised = false
  try:
    discard parseReply("I would rather not.", "bc17")
  except CatchableError:
    raised = true
  check("a reply with no JSON object raises", raised)
  ## But a reply with prose AROUND an object does not.
  let s = parseReply("""Sure! Here you go:
    {"opening":"tank_rush"}
    Hope that helps.""", "bc17")
  checkEq("prose around the object is tolerated", s.doctrine17.opening,
    op17TankRush)

finish("test_bc17_sheet")
