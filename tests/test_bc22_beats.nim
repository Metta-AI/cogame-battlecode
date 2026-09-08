## THE BEAT CONTRACT — emission, label and style, ALL THREE, from the
## COMMITTED FIXTURE REPLAY.
##
## This is where the bc25 run failed review (r1-F26: eleven beat-kind CSS
## rules against two emitted kinds), so it is asserted as three obligations
## that one test checks together against `tests/fixtures/replay-bc22.json`:
##
##   1. EMISSION — `beatsFor` returns >= 28 beats over >= 10 distinct kinds,
##      every kind inside the fourteen-kind vocabulary;
##   2. LABEL — every beat carries a non-empty spectator-readable label of
##      <= 120 runes;
##   3. STYLE — `client/replay_broadcast.html` ships a
##      `html[data-year="bc22"] .beat-marker.<kind>` rule for EVERY KIND THE
##      FIXTURE ACTUALLY EMITTED, and no bc22-scoped rule names a kind outside
##      the vocabulary.

import std/[json, os, sets, strutils, unicode]
import harness
import bc22_fixture
import battlecode/[broadcast, replay]

const Vocabulary = ["doctrine", "game", "build", "lab", "sage", "tower",
                    "mutate", "gold", "anomaly", "dodge", "archon", "rout",
                    "duel", "end"]

proc fixturePath(): string =
  for candidate in ["tests/fixtures/replay-bc22.json",
                    "fixtures/replay-bc22.json",
                    "../tests/fixtures/replay-bc22.json"]:
    if fileExists(candidate): return candidate
  "tests/fixtures/replay-bc22.json"

proc pagePath(): string =
  for candidate in ["client/replay_broadcast.html",
                    "../client/replay_broadcast.html"]:
    if fileExists(candidate): return candidate
  "client/replay_broadcast.html"

let doc = parseReplay(readFile(fixturePath()))
checkEq("the fixture is a bc22 recording", doc.year, "bc22")
checkEq("at this GameVersion", doc.gameVersion, GameVersion)

let beats = beatsFor(doc, proc (g, r: int): int = g * 4000 + r)

# --- 1. EMISSION ------------------------------------------------------------
var kinds = initHashSet[string]()
for b in beats:
  kinds.incl(b["k"].getStr())
check("the fixture emits AT LEAST 28 BEATS (got " & $beats.len & ")",
  beats.len >= 28)
check("over AT LEAST 10 DISTINCT KINDS (got " & $kinds.len & ")",
  kinds.len >= 10)
for k in kinds:
  check("every emitted kind `" & k & "` is in the fourteen-kind vocabulary",
    k in Vocabulary)
## The generator is written to produce all fourteen, and the test says so
## loudly if it stops doing so.
var missing: seq[string]
for k in Vocabulary:
  if k notin kinds: missing.add(k)
checkEq("and the committed fixture in fact emits ALL FOURTEEN (missing: " &
  missing.join(", ") & ")", missing.len, 0)

# --- 2. LABEL ---------------------------------------------------------------
for b in beats:
  let label = b["label"].getStr()
  check("the `" & b["k"].getStr() & "` beat carries a label", label.len > 0)
  check("of at most 120 runes", label.runeLen <= 120)
  check("and it is valid UTF-8", label.validateUtf8() == -1)
## A few of the note's own feed lines, spot-checked so the wording cannot
## silently become an id dump.
var sawLab = false
var sawAnomaly = false
var sawArchon = false
var sawSingularity = false
var sawDuel = false
for b in beats:
  let label = b["label"].getStr()
  case b["k"].getStr()
  of "lab":
    if "laboratory at" in label and "lead per gold" in label: sawLab = true
  of "anomaly":
    if "ABYSS" in label or "CHARGE" in label or "FURY" in label or
       "VORTEX" in label: sawAnomaly = true
  of "archon":
    if "ARCHON DOWN" in label and "gold is on the ground" in label:
      sawArchon = true
    if "walks an archon from" in label: sawArchon = true
  of "end":
    if "SINGULARITY" in label and "decided on" in label: sawSingularity = true
  of "duel":
    if "TRADE" in label and "attackers lost" in label: sawDuel = true
  else: discard
check("the laboratory beat reads like the note's feed line", sawLab)
check("the anomaly beat names its type in capitals", sawAnomaly)
check("the archon beat says what it cost", sawArchon)
check("the singularity beat names the rung", sawSingularity)
check("and bc22's `duel` reads as a TRADE, not as a launcher duel", sawDuel)

# --- 3. STYLE ---------------------------------------------------------------
let page = readFile(pagePath())
for k in kinds:
  let rule = "html[data-year=\"bc22\"] .beat-marker." & k
  check("the page ships a bc22-scoped CSS rule for the emitted kind `" & k &
    "`", rule in page)
## And no bc22-scoped beat rule names a kind outside the vocabulary: a CSS
## inventory for kinds nothing emits is exactly the r1-F26 defect.
var declared = initHashSet[string]()
var at = 0
while true:
  let i = page.find("html[data-year=\"bc22\"] .beat-marker.", at)
  if i < 0: break
  let start = i + "html[data-year=\"bc22\"] .beat-marker.".len
  var stop = start
  while stop < page.len and (page[stop].isAlphaAscii() or page[stop] == '-'):
    stop += 1
  declared.incl(page[start ..< stop])
  at = stop
checkEq("the page declares exactly the fourteen-kind vocabulary",
  declared.len, Vocabulary.len)
for k in declared:
  check("the declared rule `" & k & "` is in the vocabulary", k in Vocabulary)
for k in Vocabulary:
  check("and every vocabulary kind `" & k & "` has a rule", k in declared)

# --- the year discriminators are now THREE-WAY -----------------------------
block:
  ## `first_action` and `rout` are spelled the same by bc22, bc23 and bc25 and
  ## carry different fields, so `beatsFor`'s year test has to be three-way;
  ## `duel`'s LABEL switch gains a year test because bc22's `duel` carries the
  ## same field name with a different meaning (attackers lost, not launchers).
  var doc24 = doc
  doc24.year = "bc24"
  var sawBuild24 = false
  var sawRout24 = false
  for b in beatsFor(doc24, proc (g, r: int): int = r):
    if b["k"].getStr() == "build": sawBuild24 = true
    if b["k"].getStr() == "rout": sawRout24 = true
  check("`first_action` maps to NOTHING for bc24", not sawBuild24)
  check("and so does `rout`", not sawRout24)
  var sawBuild22 = false
  var sawRout22 = false
  for b in beats:
    if b["k"].getStr() == "build": sawBuild22 = true
    if b["k"].getStr() == "rout": sawRout22 = true
  check("but `first_action` really does map to `build` for bc22", sawBuild22)
  check("and `rout` to `rout`", sawRout22)
  var doc23 = doc
  doc23.year = "bc23"
  var launcherDuel = false
  for b in beatsFor(doc23, proc (g, r: int): int = r):
    if b["k"].getStr() == "duel" and "LAUNCHER DUEL" in b["label"].getStr():
      launcherDuel = true
  check("the SAME event labelled under bc23 reads as a launcher duel",
    launcherDuel)

# --- relayout()'s --statrail set names both bc22 stat boxes ----------------
block:
  let i = page.find("--statrail")
  check("`relayout()` sets --statrail", i > 0)
  check("and it measures `bc22-econ`", "'bc22-econ'" in page or
    "\"bc22-econ\"" in page)
  check("and `bc22-units`", "'bc22-units'" in page or
    "\"bc22-units\"" in page)
  ## The two TOP-band pills are deliberately NOT in the rail set.
  let listStart = page.find("['econ', 'bc20-soup'")
  check("the measured id list is where it was", listStart > 0)
  let listEnd = page.find("]", listStart)
  let railList = page[listStart .. listEnd]
  check("the rail measures bc22-econ", "'bc22-econ'" in railList)
  check("and bc22-units", "'bc22-units'" in railList)
  check("but NOT `bc22-archons`, which is a top-band pill",
    "bc22-archons" notin railList)
  check("nor `bc22-anomaly`", "bc22-anomaly" notin railList)

finish("test_bc22_beats")
