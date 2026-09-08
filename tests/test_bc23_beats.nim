## THE BEAT CONTRACT — emission, label and style, ALL THREE, from the
## COMMITTED FIXTURE REPLAY.
##
## This is the one place the bc25 run failed review (r1-F26: eleven beat-kind
## CSS rules against two emitted kinds), so it is asserted as three
## obligations that one test checks together against
## `tests/fixtures/replay-bc23.json`:
##
##   1. EMISSION — `beatsFor` returns >= 24 beats over >= 8 distinct kinds,
##      every kind inside the twelve-kind vocabulary;
##   2. LABEL — every beat carries a non-empty spectator-readable label of
##      <= 120 runes;
##   3. STYLE — `client/replay_broadcast.html` ships a
##      `html[data-year="bc23"] .beat-marker.<kind>` rule for EVERY KIND THE
##      FIXTURE ACTUALLY EMITTED, and no bc23-scoped rule names a kind
##      outside the vocabulary.

import std/[json, os, sets, strutils, unicode]
import harness
import bc23_fixture
import battlecode/[broadcast, replay]

const Vocabulary = ["doctrine", "game", "build", "anchor", "island",
                    "conquest", "elixir", "boost", "destabilize", "duel",
                    "rout", "end"]

proc fixturePath(): string =
  for candidate in ["tests/fixtures/replay-bc23.json",
                    "fixtures/replay-bc23.json",
                    "../tests/fixtures/replay-bc23.json"]:
    if fileExists(candidate): return candidate
  "tests/fixtures/replay-bc23.json"

proc pagePath(): string =
  for candidate in ["client/replay_broadcast.html",
                    "../client/replay_broadcast.html"]:
    if fileExists(candidate): return candidate
  "client/replay_broadcast.html"

let doc = parseReplay(readFile(fixturePath()))
checkEq("the fixture is a bc23 recording", doc.year, "bc23")
checkEq("at this GameVersion", doc.gameVersion, GameVersion)

let beats = beatsFor(doc, proc (g, r: int): int = g * 4000 + r)

# --- 1. EMISSION --------------------------------------------------------
var kinds = initHashSet[string]()
for b in beats:
  kinds.incl(b["k"].getStr())
check("the fixture emits AT LEAST 24 BEATS (got " & $beats.len & ")",
  beats.len >= 24)
check("over AT LEAST 8 DISTINCT KINDS (got " & $kinds.len & ")",
  kinds.len >= 8)
for k in kinds:
  check("every emitted kind `" & k & "` is in the twelve-kind vocabulary",
    k in Vocabulary)
## The generator is written to produce all twelve, and the test says so
## loudly if it stops doing so.
var missing: seq[string]
for k in Vocabulary:
  if k notin kinds: missing.add(k)
checkEq("and the committed fixture in fact emits ALL TWELVE (missing: " &
  missing.join(", ") & ")", missing.len, 0)

# --- 2. LABEL -----------------------------------------------------------
for b in beats:
  let label = b["label"].getStr()
  check("the `" & b["k"].getStr() & "` beat carries a label", label.len > 0)
  check("of at most 120 runes", label.runeLen <= 120)
  check("and it is valid UTF-8", label.validateUtf8() == -1)
## A few of the note's own feed lines, spot-checked so the wording cannot
## silently become an id dump.
var sawIsland = false
var sawDuel = false
var sawElixir = false
for b in beats:
  let label = b["label"].getStr()
  case b["k"].getStr()
  of "island":
    if "anchors island" in label and "it needs" in label: sawIsland = true
    if "ANCHOR LOST" in label: sawIsland = true
  of "duel":
    if "LAUNCHER DUEL" in label and "lost to" in label: sawDuel = true
  of "elixir":
    if "into elixir" in label or "fields its first" in label or
        "to rate 3" in label: sawElixir = true
  else: discard
check("the island beats read like the note's feed line", sawIsland)
check("the duel beat reads like the note's feed line", sawDuel)
check("and so does the elixir beat", sawElixir)

# --- 3. STYLE -----------------------------------------------------------
let page = readFile(pagePath())
for k in kinds:
  let rule = "html[data-year=\"bc23\"] .beat-marker." & k
  check("the page ships a bc23-scoped CSS rule for the emitted kind `" & k &
    "`", rule in page)
## And no bc23-scoped beat rule names a kind outside the vocabulary: a CSS
## inventory for kinds nothing emits is exactly the r1-F26 defect.
var declared = initHashSet[string]()
var at = 0
while true:
  let i = page.find("html[data-year=\"bc23\"] .beat-marker.", at)
  if i < 0: break
  let start = i + "html[data-year=\"bc23\"] .beat-marker.".len
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

# --- the year discriminator is now THREE-WAY ---------------------------
block:
  ## `first_action` and `rout` are spelled the same by bc23, bc24 and bc25 and
  ## carry different fields, so `beatsFor`'s year test has to be three-way.
  var doc24 = doc
  doc24.year = "bc24"
  var sawBuild24 = false
  for b in beatsFor(doc24, proc (g, r: int): int = r):
    if b["k"].getStr() == "build": sawBuild24 = true
  check("`first_action` maps to `build` for bc23 and bc25 and to NOTHING " &
    "for bc24", not sawBuild24)
  var sawBuild23 = false
  for b in beats:
    if b["k"].getStr() == "build": sawBuild23 = true
  check("and it really does map to `build` for bc23", sawBuild23)

# --- relayout()'s --statrail set names both bc23 stat boxes ------------
block:
  let i = page.find("--statrail")
  check("`relayout()` sets --statrail", i > 0)
  ## The measured id list, wherever it is, must name both bc23 boxes.
  check("and it measures `bc23-econ`", "'bc23-econ'" in page or
    "\"bc23-econ\"" in page)
  check("and `bc23-units`", "'bc23-units'" in page or
    "\"bc23-units\"" in page)

finish("test_bc23_beats")
