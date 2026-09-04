## The bc20 doctrine sheet: every one of the ten knobs repaired to its default,
## the recording of every repair, and — the D1 assertion — that a submitted
## `chassis` is recorded as an UNKNOWN FIELD and never honoured.

import std/[json, strutils, unicode]
import harness
import battlecode/[sheet, sim_types]
import battlecode/years/bc20/knobs

proc bc20(text: string): Sheet = parseReply(text, YearBc20)

# --- D1: the chassis is NOT a knob ------------------------------------------
block:
  ## THE D1 ASSERTION. It fails the moment anyone re-adds the knob.
  checkEq("the bc20 sheet has exactly ten knobs", KnownKeys20.len, 10)
  check("and `chassis` is not one of them", "chassis" notin KnownKeys20)
  let s = bc20("""{"sheet":{"chassis":"examplefuncsplayer","opening":"rush"}}""")
  check("a submitted chassis is recorded as an UNKNOWN field",
    "chassis" in s.unknownFields)
  check("and never as a repaired default",
    "chassis" notin s.defaultsApplied)
  checkEq("the rest of the sheet still applies", s.doctrine20.opening, opRush)
  check("and the emitted sheet carries no chassis key",
    not s.toJson().hasKey("chassis"))
  ## The chassis a seat drives comes from PLAYER_SCRIPTED, so a sheet that
  ## names one must not be able to change it.
  let other = bc20("""{"sheet":{"chassis":"bowl-of-chowder","opening":"rush"}}""")
  checkEq("two sheets differing only in chassis are the same doctrine",
    $other.toJson(), $s.toJson())

# --- absent / out of range / mistyped, for all ten --------------------------
block:
  let empty = bc20("{}")
  let d = empty.doctrine20
  checkEq("opening defaults", d.opening, opPassiveLattice)
  checkEq("terraform_start_round defaults", d.terraformStartRound, 300)
  checkEq("lattice_radius defaults", d.latticeRadius, 6)
  checkEq("landscaper_count_curve defaults", d.landscaperCountCurve, ccSteady)
  checkEq("miner_count_curve defaults", d.minerCountCurve, ccSteady)
  checkEq("vaporator_budget defaults", d.vaporatorBudget, 2)
  checkEq("drone_role defaults", d.droneRole, drHarass)
  checkEq("net_gun_ring defaults", d.netGunRing, 2)
  checkEq("rush_trigger defaults to NEVER", d.rushTrigger, 0)
  checkEq("wall_hq_round defaults", d.wallHqRound, 250)
  checkEq("an absent knob is not a repair", empty.defaultsApplied.len, 0)

block:
  ## Out of range: that field alone takes its default AND is recorded.
  let cases = {
    "terraform_start_round": %0,
    "lattice_radius": %99,
    "vaporator_budget": %(-1),
    "net_gun_ring": %7,
    "rush_trigger": %1501,
    "wall_hq_round": %(-4),
  }
  for (key, value) in cases:
    var payload = newJObject()
    var inner = newJObject()
    inner[key] = value
    payload["sheet"] = inner
    let s = validate(payload, YearBc20)
    check(key & " out of range is recorded", key in s.defaultsApplied)
  let defaults = defaultDoctrine20()
  let s = validate(%*{"sheet": {"lattice_radius": 99}}, YearBc20)
  checkEq("and the field keeps its default", s.doctrine20.latticeRadius,
    defaults.latticeRadius)

block:
  ## Mistyped: an enum given a number, a number given an object.
  let a = validate(%*{"sheet": {"opening": 7}}, YearBc20)
  check("a mistyped enum is recorded", "opening" in a.defaultsApplied)
  checkEq("and keeps its default", a.doctrine20.opening, opPassiveLattice)
  let b = validate(%*{"sheet": {"lattice_radius": {"nope": 1}}}, YearBc20)
  check("a mistyped number is recorded", "lattice_radius" in b.defaultsApplied)
  let c = validate(%*{"sheet": {"drone_role": "nonsense"}}, YearBc20)
  check("an unknown enum VALUE is recorded", "drone_role" in c.defaultsApplied)

block:
  ## Every legal value of every enum knob is honoured.
  for value in ["rush", "lattice", "passive_lattice", "turtle"]:
    let s = bc20("""{"sheet":{"opening":"""" & value & """"}}""")
    checkEq("opening " & value & " is honoured", $s.doctrine20.opening, value)
    checkEq("and is not a repair", s.defaultsApplied.len, 0)
  for value in ["harass", "wall", "buster", "carry_landscapers"]:
    let s = bc20("""{"sheet":{"drone_role":"""" & value & """"}}""")
    checkEq("drone_role " & value & " is honoured", $s.doctrine20.droneRole,
      value)
  for value in ["lean", "steady", "swarm"]:
    let s = bc20("""{"sheet":{"landscaper_count_curve":"""" & value & """"}}""")
    checkEq("landscaper_count_curve " & value & " is honoured",
      $s.doctrine20.landscaperCountCurve, value)

# --- unknown keys, caps and rune boundaries ---------------------------------
block:
  var inner = newJObject()
  for i in 0 ..< 30:
    inner["nonsense_" & $i] = %i
  let s = validate(%*{"sheet": inner}, YearBc20)
  check("unknown keys are capped at MaxUnknownFields",
    s.unknownFields.len <= MaxUnknownFields)
  for field in s.unknownFields:
    check("and each is capped at MaxUnknownFieldRunes",
      field.runeLen <= MaxUnknownFieldRunes)

block:
  ## Rune-boundary truncation, including astral-plane characters.
  let astral = "\u{1F9C0}"          ## U+1F9C0, four bytes
  var notes = ""
  for i in 0 ..< 400: notes.add(astral)
  let payload = %*{"sheet": {"opening": "rush"}, "notes": notes,
                   "motto": notes}
  let s = validate(payload, YearBc20)
  checkEq("notes are cut to the rune cap", s.notes.runeLen, MaxNoteRunes)
  checkEq("motto too", s.motto.runeLen, MaxMottoRunes)
  check("and the bytes are still valid UTF-8", (block:
    var ok = true
    try: discard $(%s.notes) except CatchableError: ok = false
    ok))

block:
  ## The whole-reply cap is BYTES, cut on a rune boundary.
  var padding = ""
  for i in 0 ..< 20_000: padding.add("\u{1F9C0}")
  let reply = """{"sheet":{"opening":"rush"},"notes":"""" & padding & """"}"""
  check("an oversized reply is longer than the cap", reply.len > MaxReplyBytes)
  let cut = reply.truncateBytes(MaxReplyBytes)
  check("the cut is inside the cap", cut.len <= MaxReplyBytes)
  checkEq("and lands on a rune boundary", cut.len mod 4,
    ("""{"sheet":{"opening":"rush"},"notes":"""").len mod 4)

# --- plain words ------------------------------------------------------------
block:
  let s = bc20("""{"sheet":{"opening":"rush","rush_trigger":240,
                            "wall_hq_round":300,"lattice_radius":3,
                            "landscaper_count_curve":"swarm",
                            "vaporator_budget":0,"net_gun_ring":0,
                            "drone_role":"harass"}}""")
  let words = s.plainWords().join(" | ")
  check("the overlay says it rushes", "rushes" in words)
  check("and when", "commits at round 240" in words)
  check("and when it walls", "walls at 300" in words)
  check("and that it skipped vaporators", "no vaporators" in words)
  check("and that it skipped net guns", "no net guns" in words)
  check("and what its drones do", "drones harass" in words)

block:
  ## The curve knobs really do change the targets they name.
  let lean = bc20("""{"sheet":{"landscaper_count_curve":"lean",
                               "miner_count_curve":"lean"}}""").doctrine20
  let swarm = bc20("""{"sheet":{"landscaper_count_curve":"swarm",
                                "miner_count_curve":"swarm"}}""").doctrine20
  check("swarm wants more landscapers than lean",
    swarm.landscaperTarget(600) > lean.landscaperTarget(600))
  check("and more miners", swarm.minerTarget(600) > lean.minerTarget(600))
  check("the landscaper target is capped at 40",
    swarm.landscaperTarget(100_000) == 40)
  check("and the miner target at 25", swarm.minerTarget(100_000) == 25)

finish("test_bc20_sheet")
