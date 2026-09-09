## Shard 24 of the note's list — **THE BEAT CONTRACT: emission, label and
## style, all three, from the COMMITTED artefact.**
##
## This is where the bc25 run failed review (r1-F26: eleven beat-kind CSS
## rules against two emitted kinds), so it is asserted as three obligations
## that ONE test proves together against `tests/fixtures/replay-bc16.json`:
##
## 1. **Emission** — `beatsFor` returns >= 26 beats over >= 10 distinct kinds,
##    every kind inside the thirteen-kind vocabulary.
## 2. **Label** — every beat carries a non-empty, spectator-readable label of
##    <= 120 runes, which becomes the `<button>`'s `aria-label` and `title`.
## 3. **Style** — `client/replay_broadcast.html` ships a
##    `html[data-year="bc16"] .beat-marker.<kind>` rule for **every kind the
##    fixture ACTUALLY EMITTED** — not for every kind in a hand-written list,
##    which is exactly the inventory the bc25 finding was about.
##
## Four beat NAMES collide with other years and each needs the year test:
## `first_action` and `rout` (bc22/bc23/bc25 map them the same way and bc16
## joins them), `duel` (bc22's and bc23's, whose field means launchers lost
## rather than attackers lost), and **`archon_lost`**, which bc22 emits with
## `gold_dropped` where bc16 carries `cause` — so the LABEL switch tests the
## year there too.

import std/[algorithm, json, os, sequtils, strutils, unicode]
import harness
import battlecode/[broadcast, replay, sim_types]

const Fixture = "tests" / "fixtures" / "replay-bc16.json"
const Page = "client" / "replay_broadcast.html"

const Bc16BeatKinds = ["doctrine", "game", "build", "wave", "outbreak", "den",
                       "activate", "infect", "turned", "archon", "rout",
                       "duel", "end"]

let doc = parseReplay(readFile(Fixture))
let page = readFile(Page)

block:
  checkEq("the committed fixture is a bc16 recording", doc.year, "bc16")
  checkEq("at this GameVersion", doc.gameVersion, GameVersion)
  check("with a real event stream", doc.events.len >= 100)

## The frame mapping the game block uses: game index and round -> absolute
## frame. The fixture's own game headers give the round counts.
var gameStart: seq[int]
var total = 0
for g in doc.games:
  gameStart.add(total)
  total += g.rounds
proc frameOf(g, r: int): int =
  if g < 0 or g >= gameStart.len: 0
  else: gameStart[g] + max(0, r - 1)

let beats = beatsFor(doc, frameOf)

# --- 1. EMISSION ------------------------------------------------------------
var kinds: seq[string]
for b in beats:
  let k = b["k"].getStr()
  if k notin kinds: kinds.add(k)

block:
  check("at least 26 beats (got " & $beats.len & ")", beats.len >= 26)
  kinds.sort()
  check("over at least 10 distinct kinds (got " & $kinds.len & ": " &
    kinds.join(", ") & ")", kinds.len >= 10)
  for k in kinds:
    check("every emitted kind is in the thirteen-kind vocabulary: " & k,
      k in Bc16BeatKinds)
  ## And the four year-tested names really are among them, because they are
  ## the ones a wrong `doc.year` would silently drop.
  for k in ["build", "rout", "duel", "archon"]:
    check("the year-tested kind `" & k & "` is emitted", k in kinds)
  ## The bc16-only kinds, which no other year emits and which therefore need
  ## no discriminator at all.
  for k in ["wave", "outbreak", "den", "activate", "infect", "turned"]:
    check("the bc16-only kind `" & k & "` is emitted", k in kinds)
  for k in ["doctrine", "game", "end"]:
    check("and the shared chrome kind `" & k & "` is emitted", k in kinds)
  checkEq("so the fixture carries ALL THIRTEEN", kinds.len,
    Bc16BeatKinds.len)

block:
  ## A wrong year really would drop them — the discriminator is load-bearing
  ## and this is the negative control for it.
  var wrong = doc
  wrong.year = "bc25"
  let wrongBeats = beatsFor(wrong, frameOf)
  var wrongKinds: seq[string]
  for b in wrongBeats:
    let k = b["k"].getStr()
    if k notin wrongKinds: wrongKinds.add(k)
  check("re-read as bc25, the ARCHON label changes (the year test in the " &
    "label switch is real)",
    block:
      var bc16Label = ""
      var bc25Label = ""
      for b in beats:
        if b["k"].getStr() == "archon": bc16Label = b["label"].getStr()
      for b in wrongBeats:
        if b["k"].getStr() == "archon": bc25Label = b["label"].getStr()
      bc16Label.len > 0 and bc25Label.len > 0 and bc16Label != bc25Label)

# --- 2. LABEL ---------------------------------------------------------------
block:
  var empty = 0
  var tooLong = 0
  var longest = 0
  for b in beats:
    let label = b["label"].getStr()
    if label.len == 0: inc empty
    let runes = label.runeLen
    if runes > 120: inc tooLong
    longest = max(longest, runes)
  checkEq("every beat carries a label", empty, 0)
  checkEq("and none exceeds 120 runes (longest " & $longest & ")", tooLong, 0)
  check("and the labels are really sentences, not codes",
    longest >= 30)
  ## The frame each beat lands on must be inside the recording.
  var outOfRange = 0
  for b in beats:
    let t = b["t"].getInt()
    if t < 0 or t > total: inc outOfRange
  checkEq("every beat lands on a frame inside the recording", outOfRange, 0)
  ## Pre-match beats land on frame 0 — the start of playback, which is when
  ## the sheets were read.
  for b in beats:
    if b["game"].getInt() < 0:
      checkEq("a pre-match beat lands on frame 0", b["t"].getInt(), 0)

block:
  ## The year's own vocabulary really reaches the spectator: a sample of the
  ## bc16-only labels, each asserted to contain the words that make it
  ## readable without the schema.
  proc labelOf(kind: string): string =
    for b in beats:
      if b["k"].getStr() == kind: return b["label"].getStr()
    ""
  check("the WAVE label names the horde's own numbers",
    "WAVE" in labelOf("wave") and "zombies" in labelOf("wave"))
  check("the OUTBREAK label names the multiplier",
    "OUTBREAK" in labelOf("outbreak"))
  check("the DEN label names the bounty",
    "den" in labelOf("den").toLowerAscii() and
    "parts" in labelOf("den"))
  check("the ACTIVATE label names the unit type",
    "neutral" in labelOf("activate").toLowerAscii())
  check("the TURNED label says what it became",
    "TURNS" in labelOf("turned").toUpperAscii())
  check("the ARCHON label names the cause",
    "ARCHON DOWN" in labelOf("archon"))
  check("and it is the bc16 shape, not bc22's `gold`",
    "gold" notin labelOf("archon"))
  check("the INFECT label names the source",
    "viper" in labelOf("infect").toLowerAscii() or
    "zombie" in labelOf("infect").toLowerAscii())

block:
  ## **AND THE LABEL REALLY READS THE EVENT'S OWN FIELDS.** Words alone are
  ## not enough: `broadcast.nim` shipped `zombie_wave` and `outbreak` labels
  ## that read `count`/`dens`/`multiplier` while `match.nim` emits
  ## `total`/`dens_spawning`/`outbreak_level`/`multiplier_permille`, and a
  ## missing key in a `JsonNode` `{}` lookup reads back as ZERO — so every
  ## word-level assertion above passed while the spectator was shown
  ## "0 zombies from 0 dens". Each number the label promises is now asserted
  ## against the value in the event that produced it.
  proc firstEvent(kind: string): MatchEvent =
    for e in doc.events:
      if e.kind == kind: return e
    raise newException(ValueError, "no " & kind & " event in the fixture")
  proc labelFor(kind, beatKind: string): string =
    let e = firstEvent(kind)
    for b in beats:
      if b["k"].getStr() == beatKind and b["game"].getInt() == e.game and
         b["round"].getInt() == e.round:
        return b["label"].getStr()
    ""
  block:
    let e = firstEvent("zombie_wave")
    let label = labelFor("zombie_wave", "wave")
    check("the WAVE label carries the wave's own total (" &
      $e.fields{"total"}.getInt() & ")",
      $e.fields{"total"}.getInt() & " zombies" in label)
    check("and the number of dens that spawned (" &
      $e.fields{"dens_spawning"}.getInt() & ")",
      $e.fields{"dens_spawning"}.getInt() & " dens" in label)
  block:
    let e = firstEvent("outbreak")
    let label = labelFor("outbreak", "outbreak")
    let permille = e.fields{"multiplier_permille"}.getInt()
    check("the OUTBREAK label carries the level", "OUTBREAK " &
      $e.fields{"level"}.getInt() in label)
    check("and renders the per-mille multiplier " & $permille & " as " &
      $(permille div 1000) & "." & $((permille mod 1000) div 100) & "x",
      $(permille div 1000) & "." & $((permille mod 1000) div 100) & "x" in
      label)
  block:
    let e = firstEvent("den_destroyed")
    let label = labelFor("den_destroyed", "den")
    check("the DEN label carries the bounty",
      $e.fields{"bounty"}.getInt() & " parts" in label)
    check("and the size of the queue it deleted",
      $e.fields{"queue_deleted"}.getInt() & " zombies deleted" in label)
  block:
    let e = firstEvent("infection")
    let label = labelFor("infection", "infect")
    check("the INFECT label carries the turn count",
      $e.fields{"turns"}.getInt() & " turns" in label)
  block:
    let e = firstEvent("archon_lost")
    let label = labelFor("archon_lost", "archon")
    check("the ARCHON label carries how many are left",
      $e.fields{"archons_left"}.getInt() & " left" in label)

# --- 3. STYLE ---------------------------------------------------------------
block:
  ## A `.beat-marker.<kind>` rule for EVERY KIND THE FIXTURE ACTUALLY
  ## EMITTED, every one SCOPED to `html[data-year="bc16"]` so it cannot
  ## restyle another year's marker of the same name (the bc21 r1-F4 fix).
  for k in kinds:
    let rule = "html[data-year=\"bc16\"] .beat-marker." & k
    check("the page ships a scoped CSS rule for the emitted kind `" & k &
      "`: " & rule, rule in page)
  ## And every rule the page ships for bc16 is scoped — no bare
  ## `.beat-marker.wave` may exist, because six of the thirteen names are
  ## shared with other years.
  for k in Bc16BeatKinds:
    let scoped = page.count("html[data-year=\"bc16\"] .beat-marker." & k)
    check("the bc16 rule for `" & k & "` exists exactly once", scoped >= 1)
  ## The negative control for the scoping: the page must NOT carry an
  ## unscoped rule that a bc16 replay would pick up for a bc16-only kind.
  for k in ["wave", "outbreak", "den", "activate", "infect", "turned"]:
    let unscopedCount = page.count(".beat-marker." & k)
    let scopedCount = page.count("html[data-year=\"bc16\"] .beat-marker." & k)
    checkEq("every `.beat-marker." & k & "` occurrence in the page is the " &
      "bc16-scoped one", unscopedCount, scopedCount)

block:
  ## The block's own functions have bc16-specific names, so they cannot
  ## collide with another year's (the tandem 2026-08-23 hoisting scar).
  check("buildBc16BeatButtons exists", "buildBc16BeatButtons" in page)
  check("applyBc16BeatSpoilers exists", "applyBc16BeatSpoilers" in page)
  check("and neither is named markBeat", "function markBeat" notin page)
  check("nor collides with the bc26 builder",
    page.count("function buildBeatButtons") <= 1)

finish("test_bc16_beats")
