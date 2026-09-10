## §Tests item 27 -- THE BEAT CONTRACT: emission, label and style, ALL
## THREE, from the COMMITTED FIXTURE REPLAY.
##
## This is the obligation the bc25 run failed review on (r1-F26: eleven
## beat-kind CSS rules against two emitted kinds), so it is checked as three
## things together against `tests/fixtures/replay-bc17.json`:
##
##   1. EMISSION -- `beatsFor` returns >= 26 beats over >= 11 distinct kinds,
##      every kind inside the thirteen-kind bc17 vocabulary;
##   2. LABEL -- every beat carries a non-empty spectator-readable label of
##      <= 120 runes, and it reads like a sentence rather than an id dump;
##   3. STYLE -- `client/replay_broadcast.html` ships a
##      `html[data-year="bc17"] .beat-marker.<kind>` rule for EVERY KIND THE
##      FIXTURE ACTUALLY EMITTED, and no bc17-scoped rule names a kind
##      outside the vocabulary.
##
## **ONE OF THE THIRTEEN IS NOT IN THE RECORDING AND THE SHARD NAMES IT.**
## `rout` fires when FOUR robots of one side die in a single round. Over
## every doctrine pair and every board measured in phase 20 nothing produced
## it: 2017 armies are small (the committed fixture's three games build 8,
## 6 and 20 units a side) and its bullets are slow enough that losses arrive
## one at a time. The kind, its emission path, its label and its CSS rule all
## ship; the fixture does not exercise it, and this shard says so by name
## rather than quietly asserting a smaller vocabulary.

import std/[json, os, sets, strutils, unicode]
import harness
import bc17_fixture
import battlecode/[broadcast, replay]

const Vocabulary = ["doctrine", "game", "build", "tree", "archon", "donate",
                    "shake", "strike", "volley", "rout", "duel", "famine",
                    "end"]
const NotInTheFixture = ["rout"]

let doc = fixtureReplay()
checkEq("the fixture is a bc17 recording", doc.year, "bc17")
checkEq("at this GameVersion", doc.gameVersion, GameVersion)
checkEq("and it carries all three games -- the match did not clinch at two",
  doc.games.len, 3)

let beats = beatsFor(doc, proc (g, r: int): int = g * 4000 + r)

# --- 1. EMISSION ------------------------------------------------------------
var kinds = initHashSet[string]()
for b in beats:
  kinds.incl(b["k"].getStr())
check("the fixture emits AT LEAST 26 BEATS (got " & $beats.len & ")",
  beats.len >= 26)
check("over AT LEAST 11 DISTINCT KINDS (got " & $kinds.len & ")",
  kinds.len >= 11)
for k in kinds:
  check("every emitted kind `" & k & "` is in the thirteen-kind vocabulary",
    k in Vocabulary)
## And exactly which ones are missing, by name.
var missing: seq[string]
for k in Vocabulary:
  if k notin kinds: missing.add(k)
checkEq("the only vocabulary kind the fixture does not exercise is `rout` " &
  "(missing: " & missing.join(", ") & ")", missing, @NotInTheFixture)

# --- every beat lands on a real frame ---------------------------------------
block:
  var offFrame = 0
  for b in beats:
    if b["t"].getInt() < 0: inc offFrame
  checkEq("every beat lands on a non-negative frame", offFrame, 0)
  ## The two doctrine beats are pre-match and land on frame 0.
  var doctrineFrames: seq[int]
  for b in beats:
    if b["k"].getStr() == "doctrine": doctrineFrames.add(b["t"].getInt())
  checkEq("both doctrine beats land on frame 0", doctrineFrames, @[0, 0])

# --- 2. LABEL ---------------------------------------------------------------
for b in beats:
  let label = b["label"].getStr()
  check("the `" & b["k"].getStr() & "` beat carries a label", label.len > 0)
  check("of at most 120 runes", label.runeLen <= 120)
  check("and it is valid UTF-8", label.validateUtf8() == -1)

block:
  ## Spot-checks so the wording cannot silently become an id dump. Each is a
  ## phrase from the note's own feed lines.
  var sawBuild = false
  var sawTree = false
  var sawDonate = false
  var sawFamine = false
  var sawShake = false
  var sawStrike = false
  var sawVolley = false
  var sawDuel = false
  var sawArchon = false
  for b in beats:
    let label = b["label"].getStr()
    case b["k"].getStr()
    of "build":
      if "commissions its first" in label or "opens with" in label:
        sawBuild = true
    of "tree":
      if "plants" in label or "loses a tree" in label or
          "farm is paying" in label or "tree" in label.toLowerAscii():
        sawTree = true
    of "donate":
      if "donates" in label and "points" in label: sawDonate = true
    of "famine":
      if "bullet" in label.toLowerAscii(): sawFamine = true
    of "shake":
      if "shake" in label.toLowerAscii() or "chop" in label.toLowerAscii():
        sawShake = true
    of "strike":
      if "STRIKE" in label or "strike" in label: sawStrike = true
    of "volley":
      if "VOLLEY" in label or "bullets" in label: sawVolley = true
    of "duel":
      if "DUEL" in label or "lost" in label: sawDuel = true
    of "archon":
      if "archon" in label.toLowerAscii() or
          "gardener" in label.toLowerAscii(): sawArchon = true
    else: discard
  check("the build beats name the unit", sawBuild)
  check("the tree beats read like the farm ledger", sawTree)
  check("the donation beats name the points bought", sawDonate)
  check("the famine beat is about bullets", sawFamine)
  check("the shake beats are about shaking or chopping", sawShake)
  check("the strike beats say STRIKE", sawStrike)
  check("the volley beats count bullets", sawVolley)
  check("the duel beats report the exchange", sawDuel)
  check("and the archon beats name the body that fell", sawArchon)

block:
  ## The unit-milestone label reads a BC17 unit name. It used to read
  ## `Bc16UnitNames`, so a bc17 spectator was told a gardener was a
  ## `standardzombie`; the label is now year-dispatched and this pins it.
  const Bc16Only = ["standardzombie", "rangedzombie", "fastzombie",
                    "bigzombie", "zombieden", "viper", "turret", "ttm"]
  var wrongYear: seq[string]
  for b in beats:
    let label = b["label"].getStr()
    for word in Bc16Only:
      if word in label: wrongYear.add(word & " in " & label)
  checkEq("no beat label names a unit from another year", wrongYear.len, 0)
  var sawBc17Unit = false
  for b in beats:
    let label = b["label"].getStr()
    for word in ["archon", "gardener", "lumberjack", "soldier", "tank",
                 "scout"]:
      if "commissions its first " & word in label: sawBc17Unit = true
  check("and at least one names a real bc17 unit", sawBc17Unit)

# --- 3. STYLE ---------------------------------------------------------------
let page = readFile(pagePath())
for k in kinds:
  let rule = "html[data-year=\"bc17\"] .beat-marker." & k
  check("the page ships a bc17-scoped CSS rule for the emitted kind `" & k &
    "`", rule in page)
## And no bc17-scoped beat rule names a kind outside the vocabulary: a CSS
## inventory for kinds nothing can emit is exactly the r1-F26 defect.
var declared = initHashSet[string]()
var at = 0
while true:
  let i = page.find("html[data-year=\"bc17\"] .beat-marker.", at)
  if i < 0: break
  let start = i + "html[data-year=\"bc17\"] .beat-marker.".len
  var stop = start
  while stop < page.len and (page[stop].isAlphaAscii() or page[stop] == '-'):
    stop += 1
  declared.incl(page[start ..< stop])
  at = stop
checkEq("the page declares exactly the thirteen-kind vocabulary",
  declared.len, Vocabulary.len)
for k in declared:
  check("the declared rule `" & k & "` is in the vocabulary", k in Vocabulary)
for k in Vocabulary:
  check("and every vocabulary kind `" & k & "` has a rule", k in declared)

# --- the year discriminator -------------------------------------------------
block:
  ## `first_action`, `rout` and `duel` are spelled the same by several years
  ## and carry different fields, so `beatsFor` chooses the vocabulary by the
  ## replay header's year. A bc17 recording must never produce a label from
  ## another year's table.
  checkEq("the header says bc17 and nothing else reads it", doc.year, "bc17")
  var actionWords = 0
  for b in beats:
    if b["k"].getStr() != "build": continue
    for word in ["hire", "build", "plant", "move", "fire_single",
                 "fire_triad", "fire_pentad", "strike", "chop", "shake",
                 "water", "broadcast", "donate"]:
      if "opens with " & word in b["label"].getStr(): inc actionWords
  check("the first-action beats name a bc17 ACTION (" & $actionWords & ")",
    actionWords >= 2)

finish("test_bc17_beats")
