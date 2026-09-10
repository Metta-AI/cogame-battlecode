## THE BEAT CONTRACT — emission, label and style, ALL THREE, from the
## COMMITTED FIXTURE REPLAY.
##
## This is the one place the bc25 run failed review (r1-F26: eleven beat-kind
## CSS rules against two emitted kinds), so it is asserted as three
## obligations that one test checks together against
## `tests/fixtures/replay-bc19.json`:
##
##   1. EMISSION — `beatsFor` returns >= 24 beats over >= 10 distinct kinds,
##      every kind inside the twelve-kind vocabulary;
##   2. LABEL — every beat carries a non-empty spectator-readable label of
##      <= 120 runes;
##   3. STYLE — `client/replay_broadcast.html` ships a
##      `html[data-year="bc19"] .beat-marker.<kind>` rule for EVERY KIND THE
##      FIXTURE ACTUALLY EMITTED, and no bc19-scoped rule names a kind
##      outside the vocabulary.
##
## `famine` IS THE ONE VOCABULARY KIND THE FIXTURE DOES NOT EMIT, and that is
## a property of the chassis rather than a gap: `noteFamine` fires when a
## store is at zero AND the acting robot asked for something it could not pay
## for, and `saber` never asks for what it cannot pay (that is the
## `refused_actions == 0` gate in `tests/test_bc19_survival.nim`). The beat is
## a spectator signal for a WEAK or an LLM order. Its CSS rule ships, its
## label is exercised here from a synthetic event, and obligation 3 is
## deliberately stated over the emitted set so this file can say so instead
## of pretending.

import std/[json, sets, strutils, unicode]
import harness
import bc19_fixture
import battlecode/broadcast

const Vocabulary = ["doctrine", "game", "build", "church", "castle", "mine",
                    "famine", "trade", "splash", "rout", "duel", "end"]

let doc = fixtureReplay()
checkEq("the fixture is a bc19 recording", doc.year, "bc19")
checkEq("at this GameVersion", doc.gameVersion, GameVersion)
checkEq("recorded over three games", doc.games.len, 3)

let beats = beatsFor(doc, proc (g, r: int): int = g * 2000 + r)

# --- 1. EMISSION --------------------------------------------------------
var kinds = initHashSet[string]()
for b in beats:
  kinds.incl(b["k"].getStr())
check("the fixture emits AT LEAST 24 BEATS (got " & $beats.len & ")",
  beats.len >= 24)
check("over AT LEAST 10 DISTINCT KINDS (got " & $kinds.len & ")",
  kinds.len >= 10)
for k in kinds:
  check("every emitted kind `" & k & "` is in the twelve-kind vocabulary",
    k in Vocabulary)
## The eleven the generator is written to produce, named individually so a
## failure says WHICH one went missing rather than just counting.
for k in ["doctrine", "game", "build", "church", "castle", "mine", "trade",
          "splash", "rout", "duel", "end"]:
  check("the committed fixture emits the `" & k & "` beat", k in kinds)
checkEq("and `famine` is the one it does not (see the header)",
  "famine" in kinds, false)
## Every beat lands on a frame the scrubber can reach, and the two pre-match
## doctrine beats land on frame 0.
var doctrineFrames = 0
for b in beats:
  check("beat `" & b["k"].getStr() & "` carries a frame", b.hasKey("t"))
  check("and it is non-negative", b["t"].getInt() >= 0)
  if b["k"].getStr() == "doctrine":
    inc doctrineFrames
    checkEq("a doctrine beat lands on frame 0", b["t"].getInt(), 0)
checkEq("both seats' doctrine records produced a beat", doctrineFrames, 2)

# --- 2. LABEL -----------------------------------------------------------
for b in beats:
  let label = b["label"].getStr()
  check("the `" & b["k"].getStr() & "` beat carries a label", label.len > 0)
  check("of at most 120 runes", label.runeLen <= 120)
  check("and it is valid UTF-8", label.validateUtf8() == -1)

## The year-specific wording, spot-checked so it cannot silently become an id
## dump — and so the THREE-WAY discriminators cannot regress. Every one of
## these is a line a bc19 spectator has to be able to read.
var sawSkirmish = false
var sawCastle = false
var sawChurch = false
var sawTrade = false
var sawSplash = false
var sawMine = false
var sawMilestone = false
var sawTiebreak = false
var sawRout = false
for b in beats:
  let label = b["label"].getStr()
  case b["k"].getStr()
  of "duel":
    ## bc19's `duel` counts EVERY unit lost by both sides, not just the ones
    ## that can attack, so it must read SKIRMISH and never LAUNCHER DUEL or
    ## TRADE.
    if "SKIRMISH" in label: sawSkirmish = true
    check("a bc19 duel beat is never bc23's LAUNCHER DUEL",
      "LAUNCHER DUEL" notin label)
    check("nor bc22's and bc16's attacker TRADE",
      "attackers lost" notin label)
  of "castle":
    if "CASTLE" in label: sawCastle = true
  of "church":
    if "church" in label.toLowerAscii(): sawChurch = true
  of "trade":
    if "karbonite" in label.toLowerAscii() or "fuel" in label.toLowerAscii():
      sawTrade = true
  of "splash":
    if "blast" in label.toLowerAscii() or "PREACHER" in label:
      sawSplash = true
  of "mine":
    if "depot" in label.toLowerAscii() or "karbonite" in
        label.toLowerAscii() or "fuel" in label.toLowerAscii():
      sawMine = true
  of "build":
    if "commissions its first" in label:
      sawMilestone = true
      ## bc19's unit vocabulary is SIX values; a bc19 spectator must never
      ## be told about a unit type this year does not have.
      for alien in ["archon", "sage", "launcher", "carrier", "mopper",
                    "splasher", "soldier", "guard", "viper", "scout",
                    "turret", "drone", "delivery", "landscaper",
                    "miner", "watchtower", "duck"]:
        check("the milestone label names no " & alien,
          alien notin label.toLowerAscii())
  of "end":
    if "ROUND" in label and "castles level" in label: sawTiebreak = true
  of "rout":
    if "ROUT" in label: sawRout = true
  else: discard
check("the duel beat reads SKIRMISH, this year's own wording", sawSkirmish)
check("the castle beat names the CASTLE", sawCastle)
check("the church beat names the church", sawChurch)
check("the trade beat names what moved", sawTrade)
check("the splash beat names the blast", sawSplash)
check("the mine beat names the depot", sawMine)
check("the unit milestone reads like the note's feed line", sawMilestone)
check("and the round-1000 tiebreak reads castles-level", sawTiebreak)
check("and the rout beat says ROUT", sawRout)

## `famine`'s label, from a synthetic event, because the strong chassis
## cannot produce one. Both resources, so neither branch is dead.
block:
  var probe = doc
  probe.events = @[]
  for resource in 0 .. 1:
    probe.events.add(MatchEvent(kind: "famine", ms: 0, game: 0, round: 300,
      fields: %*{"slot": 0, "alias": "Ash",
                 "resource": (if resource == 0: "karbonite" else: "fuel")}))
  let famineBeats = beatsFor(probe, proc (g, r: int): int = r)
  checkEq("two famine events make two beats", famineBeats.len, 2)
  for b in famineBeats:
    checkEq("and each is a famine beat", b["k"].getStr(), "famine")
    let label = b["label"].getStr()
    check("with a non-empty label", label.len > 0)
    check("of at most 120 runes", label.runeLen <= 120)
  check("the karbonite branch names karbonite",
    "karbonite" in famineBeats[0]["label"].getStr().toLowerAscii())
  check("and the fuel branch names fuel",
    "fuel" in famineBeats[1]["label"].getStr().toLowerAscii())

# --- 3. STYLE -----------------------------------------------------------
let page = readFile(pagePath())
for k in kinds:
  let rule = "html[data-year=\"bc19\"] .beat-marker." & k
  check("the page ships a bc19-scoped CSS rule for the emitted kind `" & k &
    "`", rule in page)
## And no bc19-scoped beat rule names a kind outside the vocabulary: a CSS
## inventory for kinds nothing emits is exactly the r1-F26 defect.
var declared = initHashSet[string]()
var at = 0
while true:
  let i = page.find("html[data-year=\"bc19\"] .beat-marker.", at)
  if i < 0: break
  let start = i + "html[data-year=\"bc19\"] .beat-marker.".len
  var stop = start
  while stop < page.len and (page[stop].isAlphaAscii() or page[stop] == '-'):
    stop += 1
  declared.incl(page[start ..< stop])
  at = stop
checkEq("the page declares exactly the twelve-kind vocabulary",
  declared.len, Vocabulary.len)
for k in declared:
  check("the declared rule `" & k & "` is in the vocabulary", k in Vocabulary)
for k in Vocabulary:
  check("and every vocabulary kind `" & k & "` has a rule", k in declared)

# --- the year discriminators, all of them ------------------------------
block:
  ## `first_action` and `rout` are spelled the same by five years and carry
  ## different fields, so `beatsFor`'s year test has to name bc19 too.
  ## Only the two ambiguous events are re-labelled under the other year's
  ## header: a whole bc19 recording read as bc24 would reach bc24's own
  ## `tiebreak` fields, which is not a case any reader can produce.
  var doc24 = doc
  doc24.year = "bc24"
  doc24.events = @[]
  for e in doc.events:
    if e.kind in ["first_action", "rout"]: doc24.events.add(e)
  check("the fixture really carries both ambiguous events",
    doc24.events.len >= 2)
  var sawBuild24 = false
  var sawRout24 = false
  for b in beatsFor(doc24, proc (g, r: int): int = r):
    if b["k"].getStr() == "build": sawBuild24 = true
    if b["k"].getStr() == "rout": sawRout24 = true
  check("`first_action` maps to `build` for bc19 and to NOTHING for bc24",
    not sawBuild24)
  check("and `rout` maps to nothing for bc24 either", not sawRout24)
  var sawBuild19 = false
  for b in beats:
    if b["k"].getStr() == "build": sawBuild19 = true
  check("while it really does map to `build` for bc19", sawBuild19)

# --- relayout()'s --statrail set names both bc19 stat boxes ------------
block:
  let i = page.find("--statrail")
  check("`relayout()` sets --statrail", i > 0)
  check("and it measures `bc19-econ`", "'bc19-econ'" in page or
    "\"bc19-econ\"" in page)
  check("and `bc19-units`", "'bc19-units'" in page or
    "\"bc19-units\"" in page)

finish("test_bc19_beats")
