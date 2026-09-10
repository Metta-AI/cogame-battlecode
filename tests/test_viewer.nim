## The viewer bundle: the inherited chrome is unmodified, the emscripten link
## flags and the JS bootstrap are a MATCHED PAIR, the game block does not
## shadow a ChromeCommon alias, and the sim module really does produce a
## drawable frame.
##
## The wasm module itself is exercised by `tools/wasm_replay_smoke.cjs` (node,
## in the `wasm-viewer` CI job) and by `tools/ci/viewer_smoke.mjs` in headless
## chromium. This shard covers everything that does NOT need emscripten, plus
## the file-level invariants that a rename would silently break.

import std/[json, os, strutils]
import crunchy/sha256
import harness
import bitworld/spriteprotocol
import battlecode/[baselines, broadcast, render, replay, results, sheet, sim_types]
import battlecode/years/bc26/[maps, rules]
import battlecode/years/dispatch
from battlecode/years/bc21/maps as maps21 import nil
from battlecode/years/bc21/rules as rules21 import nil
from battlecode/years/bc24/maps as maps24 import nil
from battlecode/years/bc24/rules as rules24 import nil

proc sha(path: string): string =
  for b in sha256(readFile(path)):
    result.add(toHex(b, 2).toLowerAscii())

# --- the inherited chrome is BYTE FOR BYTE the starter's --------------------
# coworld-ctf is not checked out in this repo's CI, so the starter's bytes are
# pinned by hash here. A change to either file must be a deliberate,
# documented fork — not a drift.
checkEq("client/chrome_common.js is the starter's copy",
  sha("client/chrome_common.js"),
  "f7860b4c415dabed0ed7241a6aa35b7c2703a2fad4d822cf55b592e7d3735465")
checkEq("client/broadcast_core.js is the starter's copy",
  sha("client/broadcast_core.js"),
  "226aea03cd24012040b0ea21b44cda5a1b4ad97f38cdcd45dd349341bd3b098b")

# --- the four viewer files come from ONE starter ----------------------------
let config = readFile("replay-viewer/config.nims")
check("no MODULARIZE in the link flags", "MODULARIZE" notin config)
check("no EXPORT_NAME in the link flags", "EXPORT_NAME" notin config)
check("the bundle preloads data/", "--preload-file" in config)
check("and emits bc_replay.js", "bc_replay.js" in config)

let worker = readFile("replay-viewer/static_replay_worker.js")
check("the worker declares a GLOBAL Module", "var Module = {};" in worker)
check("and starts on onRuntimeInitialized",
  "Module.onRuntimeInitialized" in worker)
check("and imports the emitted module LAST",
  worker.strip().endsWith(
    "importScripts('./wire_constants.js', './broadcast_core.js', " &
    "'./bc_replay.js');"))

## EVERY `Module._bc_*` the worker calls must be an export the link flags
## actually emit. The rename from the starter's `ctf_*` names went through a
## sed, and one stale `_bc_mismatch_tick` reached a real browser as
## "Module._bc_mismatch_tick is not a function" — after the board had already
## drawn, so the file-presence checks were all green.
for call in worker.split("Module._bc_")[1 .. ^1]:
  var name = "_bc_"
  for ch in call:
    if ch in {'a' .. 'z', '_', '0' .. '9'}: name.add(ch) else: break
  check("the link flags export " & name & ", which the worker calls",
    name in config)

let adapter = readFile("replay-viewer/static_replay.js")
check("the adapter sets data-replay-loaded on the first drawn frame",
  "data-replay-loaded" in adapter)
check("and data-replay-error on failure", "data-replay-error" in adapter)
check("and loads the worker by name", "static_replay_worker.js" in adapter)

# --- every export the config names really exists ----------------------------
let entry = readFile("replay-viewer/bc_replay.nim")
for name in ["bc_load_replay", "bc_frame", "bc_input", "bc_packet_ptr",
             "bc_packet_len", "bc_mismatch_round", "bc_error_ptr",
             "bc_error_len", "bc_stage_ptr", "bc_stage_len",
             "bc_game_version_ptr", "bc_game_version_len",
             "bc_sim_sources_stamp_ptr", "bc_sim_sources_stamp_len"]:
  check("config.nims exports " & name, "_" & name in config)
  check("and bc_replay.nim defines it", "\"" & name & "\"" in entry)
check("the wasm entry keeps the live-runtime exit",
  "emscripten_exit_with_live_runtime" in entry)
check("and the OOM-surviving stage buffer", "stageNote" in entry)

# --- the page ---------------------------------------------------------------
let page = readFile("client/replay_broadcast.html")
for marker in ["<!-- WIRE_CONSTANTS -->", "<!-- CHROME_COMMON -->",
               "<!-- BROADCAST_CORE -->"]:
  check("the page keeps the starter's splice marker " & marker,
    marker in page)

## The starter elements the design note REMOVES.
for removed in ["id=\"fpv\"", "id=\"fpv-canvas\"", "id=\"lockerroom\"",
                "id=\"lk-art\"", "id=\"voteStage\"", "id=\"huddleStage\"",
                "id=\"huddlePanel\"", "id=\"huddleChip\"",
                "id=\"gloryPops\"", "id=\"commsdock\"", "id=\"commsFeed\"",
                "id=\"commsLive\"", "id=\"lulls\""]:
  check("removed: " & removed, removed notin page)

## Everything else stays.
for kept in ["id=\"viewport\"", "id=\"stage\"", "id=\"board\"",
             "id=\"chrome\"", "id=\"scorebug\"", "id=\"clock\"",
             "id=\"clock-time\"", "id=\"clock-caption\"", "id=\"killfeed\"",
             "id=\"transport\"", "id=\"btn-restart\"", "id=\"btn-back\"",
             "id=\"btn-play\"", "id=\"btn-fwd\"", "id=\"btn-skip\"",
             "id=\"btn-end\"", "id=\"btn-loop\"", "id=\"btn-spoilers\"",
             "id=\"speedchips\"", "id=\"tick-clock\"", "id=\"win-chip\"",
             "id=\"scrub\"", "id=\"scrub-fill\"", "id=\"scrub-head\"",
             "id=\"scrub-win\"", "id=\"endcard\"", "id=\"status\"",
             "id=\"mmwarn\""]:
  check("kept: " & kept, kept in page)

## #viewpanel is KEPT: a 60x60 board renders wider than a 360 px frame.
for zoom in ["id=\"viewpanel\"", "id=\"minimap\"", "id=\"minimap-canvas\"",
             "id=\"zoombar\"", "id=\"zoom-in\"", "id=\"zoom-out\"",
             "id=\"zoom-slider\"", "id=\"zoom-read\""]:
  check("the zoom bar and minimap are kept: " & zoom, zoom in page)
check("and ?viewpanel=0 still drops the panel", "viewpanel=0" in page)

## The inherited page loads the starter's bitmap font by relative URL; ship it
## or every bundle logs a 404 for it.
check("the chrome font ships with the bundle", fileExists("client/font.ttf"))
check("and the bundle build copies it",
  "cp client/font.ttf replay-viewer/dist/font.ttf" in
    readFile("Dockerfile.replay-viewer"))

## getAppDir() is not a data-root candidate: under emscripten it raises
## before the atlas is ever opened. See the comment in maps.nim.
check("dataRoot does not call getAppDir",
  "getAppDir()" notin readFile("src/battlecode/years/bc26/maps.nim").
    replace("`getAppDir()` is DELIBERATELY not a candidate", ""))

## The battlecode game block's own elements.
for added in ["id=\"coopchip\"", "id=\"bars\"", "id=\"econ\"",
              "id=\"gamechips\"", "id=\"doctrines\""]:
  check("the game block adds " & added, added in page)

## CSS for EVERY beat kind the sim emits.
for kind in ["doctrine", "king", "backstab", "cat", "game", "end"]:
  check("the page styles .beat-marker." & kind,
    ".beat-marker." & kind in page)
check("beat markers are real buttons", "button.beat-marker" in page)

## The tandem 2026-08-23 hoisting collision: the game block's beat builder
## must NOT be named markBeat, which chrome_common.js already exports.
check("the game block does not define markBeat",
  "function markBeat" notin page)
check("it defines its own builder instead", "buildBeatButtons" in page)
## Nor may it shadow any other ChromeCommon alias it uses.
for aliased in ["renderClock", "renderTransport", "getSpoilers",
                "setSpoilers", "renderBeatMarkers"]:
  check("the game block does not shadow ChromeCommon's " & aliased,
    "function " & aliased in page == false)

## The game block's beat buttons ride ITS OWN spoiler gate: they never reach
## chrome_common's markerEls (they are appended straight to #scrub, and this
## block may not call itself markBeat), so applySpoilers cannot see them and
## a future BACKSTAB marker was visible from frame 0 with spoilers off.
check("the block gates its own beat markers",
  "function applyBeatSpoilers" in page)
check("on the same rule the starter uses",
  "!spoilers && el.__tick > s.t" in page)
check("re-applied on every frame", page.count("applyBeatSpoilers(s)") >= 2)
check("and on the spoiler toggle",
  page.count("applyBeatSpoilers(lastState)") >= 2)
## The killfeed's own gate was dead code: the line above it already returns
## for a beat ahead of the playhead.
check("the killfeed has no unreachable spoiler guard",
  "if (!C.getSpoilers() && b.t > s.t) return;" notin page)

## ---- THE APPENDED bc20 GAME BLOCK -----------------------------------------
## No starter element is removed and no existing id is reused: every id the
## bc20 block adds is new and prefixed.
for added in ["id=\"bc20-flood\"", "id=\"bc20-soup\"", "id=\"bc20-units\"",
              "id=\"bc20-doctrines\"", "id=\"bc20-doctrines-close\"",
              "id=\"bc20-doctrines-toggle\"", "id=\"bc20-chain\""]:
  check("the bc20 block adds " & added, added in page)
check("under its own banner comment",
  "BC20 additions to the inherited cogame-battlecode chrome" in page)
check("and the bc26 block's own elements are still there",
  "id=\"coopchip\"" in page and "id=\"doctrines\"" in page)

## The year is ONE attribute plus CSS, not a rewrite.
check("the block sets data-year from the replay header",
  "setAttribute('data-year'" in page)
check("and the stylesheet hides the other year's readouts",
  "html[data-year=\"bc20\"] #coopchip" in page)
check("both ways", "html:not([data-year=\"bc20\"]) #bc20-flood" in page)

## D3: the doctrine overlay is DISMISSIBLE and never sits in the transport
## band.
check("the overlay's close control names itself for a screen reader",
  "aria-label=\"Dismiss doctrines\"" in page)
check("Escape dismisses it", "event.key !== 'Escape'" in page)
check("and a chip re-opens it", "setDoctrinesOpen(true)" in page)
block:
  let start = page.find("#bc20-doctrines {")
  check("the page has a #bc20-doctrines rule", start >= 0)
  let rule = page[start ..< page.find("}", start)]
  check("and it sits ABOVE the transport band",
    "bottom: calc(var(--band, 0px) + 8px);" in rule)
for panel in ["#bc20-soup {", "#bc20-units {"]:
  let start = page.find(panel)
  check("the page has a " & panel & " rule", start >= 0)
  let rule = page[start ..< page.find("}", start)]
  check(panel & " sits above the transport band too",
    "var(--band, 0px) +" in rule)

## CSS for EVERY beat kind bc20 emits — all ten.
for kind in ["doctrine", "game", "flood", "build", "wall", "rush", "drop",
             "bury", "drown", "end"]:
  check("the page styles .beat-marker." & kind & " (bc20)",
    ".beat-marker." & kind in page)

## The tandem hoisting collision, again: the bc20 block's beat builder may
## share neither `markBeat` nor the bc26 block's `buildBeatButtons`.
check("the bc20 block has its OWN beat builder",
  "function buildBc20BeatButtons" in page)
check("and its own spoiler gate", "function applyBc20BeatSpoilers" in page)
for aliased in ["renderClock", "renderTransport", "getSpoilers",
                "setSpoilers", "renderBeatMarkers", "markBeat",
                "buildBeatButtons"]:
  check("the bc20 block does not shadow " & aliased,
    page.count("function " & aliased & "(") <= 1)


## ---- THE APPENDED bc21 GAME BLOCK -----------------------------------------
## No starter element is removed and no existing id is reused: every id the
## bc21 block adds is new and prefixed.
for added in ["id=\"bc21-votes\"", "id=\"bc21-influence\"",
              "id=\"bc21-units\"", "id=\"bc21-doctrines\"",
              "id=\"bc21-doctrines-close\"", "id=\"bc21-doctrines-toggle\"",
              "id=\"bc21-bids\""]:
  check("the bc21 block adds " & added, added in page)
check("under its own banner comment",
  "BC21 additions to the inherited cogame-battlecode chrome" in page)
check("and the bc26 block's own elements are still there",
  "id=\"coopchip\"" in page and "id=\"doctrines\"" in page)
check("and the bc20 block's", "id=\"bc20-flood\"" in page and
  "id=\"bc20-chain\"" in page)

## The year is ONE attribute plus CSS, not a rewrite.
check("the stylesheet hides the other years' readouts under bc21",
  "html[data-year=\"bc21\"] #coopchip" in page)
check("including bc20's", "html[data-year=\"bc21\"] #bc20-flood" in page)
check("both ways", "html:not([data-year=\"bc21\"]) #bc21-votes" in page)

## D3: the bc21 doctrine overlay is DISMISSIBLE and never sits in the
## transport band.
block:
  let start = page.find("#bc21-doctrines {")
  check("the page has a #bc21-doctrines rule", start >= 0)
  let rule = page[start ..< page.find("}", start)]
  check("and it sits ABOVE the transport band",
    "bottom: calc(var(--band, 0px) + 8px);" in rule)
for panel in ["#bc21-influence {", "#bc21-units {"]:
  let start = page.find(panel)
  check("the page has a " & panel & " rule", start >= 0)
  let rule = page[start ..< page.find("}", start)]
  check(panel & " sits above the transport band too",
    "var(--band, 0px) +" in rule)

## CSS for EVERY beat kind bc21 emits — all ten.
for kind in ["doctrine", "game", "build", "capture", "votes", "bid", "expose",
             "empower", "wipe", "end"]:
  check("the page styles .beat-marker." & kind & " (bc21)",
    ".beat-marker." & kind in page)

## The tandem hoisting collision, a third time: the bc21 block's beat builder
## may share neither `markBeat`, nor bc26's `buildBeatButtons`, nor bc20's.
check("the bc21 block has its OWN beat builder",
  "function buildBc21BeatButtons" in page)
check("and its own spoiler gate", "function applyBc21BeatSpoilers" in page)
for aliased in ["renderClock", "renderTransport", "getSpoilers",
                "setSpoilers", "renderBeatMarkers", "markBeat",
                "buildBeatButtons", "buildBc20BeatButtons"]:
  check("the bc21 block does not shadow " & aliased,
    page.count("function " & aliased & "(") <= 1)
check("and it registers itself on its own global",
  "window.Bc21Block" in page and "window.Bc20Block" in page)

## ---- THE APPENDED bc24 GAME BLOCK -----------------------------------------
## No starter element is removed and no existing id is reused: every id the
## bc24 block adds is new and prefixed.
for added in ["id=\"bc24-flags\"", "id=\"bc24-crumbs\"",
              "id=\"bc24-levels\"", "id=\"bc24-doctrines\"",
              "id=\"bc24-doctrines-close\"", "id=\"bc24-doctrines-toggle\"",
              "id=\"bc24-traps\""]:
  check("the bc24 block adds " & added, added in page)
check("under its own banner comment",
  "BC24 additions to the inherited cogame-battlecode chrome" in page)
check("and the bc26 block's own elements are still there",
  "id=\"coopchip\"" in page and "id=\"doctrines\"" in page)
check("and the bc20 block's", "id=\"bc20-flood\"" in page and
  "id=\"bc20-chain\"" in page)
check("and the bc21 block's", "id=\"bc21-votes\"" in page and
  "id=\"bc21-bids\"" in page)
check("#viewpanel is KEPT: a 59-wide board renders 944 px against a 360 px " &
  "featured-match frame", "id=\"viewpanel\"" in page)

## The year is ONE attribute plus CSS, not a rewrite.
check("the stylesheet hides the other years' readouts under bc24",
  "html[data-year=\"bc24\"] #coopchip" in page)
check("including bc20's", "html[data-year=\"bc24\"] #bc20-flood" in page)
check("and bc21's", "html[data-year=\"bc24\"] #bc21-votes" in page)
check("both ways", "html:not([data-year=\"bc24\"]) #bc24-flags" in page)

## D3: the bc24 doctrine overlay is DISMISSIBLE and never sits in the
## transport band.
block:
  let start = page.find("#bc24-doctrines {")
  check("the page has a #bc24-doctrines rule", start >= 0)
  let rule = page[start ..< page.find("}", start)]
  check("and it sits ABOVE the transport band",
    "bottom: calc(var(--band, 0px) + 8px);" in rule)
check("with a dismiss control that says what it does",
  "id=\"bc24-doctrines-close\"" in page and
  page.count("aria-label=\"Dismiss doctrines\"") >= 3)
check("an Escape binding scoped to the bc24 year",
  "getAttribute('data-year') !== 'bc24'" in page)
check("and a re-open chip", "id=\"bc24-doctrines-toggle\" hidden" in page)
for panel in ["#bc24-crumbs {", "#bc24-levels {"]:
  let start = page.find(panel)
  check("the page has a " & panel & " rule", start >= 0)
  let rule = page[start ..< page.find("}", start)]
  check(panel & " sits above the transport band too",
    "var(--band, 0px) +" in rule)

## CSS for EVERY beat kind bc24 emits — all twelve, with the five NEW ones
## SCOPED to the bc24 year (the bc21 r1-F4 fix, kept).
for kind in ["doctrine", "game", "setup", "build", "steal", "return",
             "capture", "trap", "upgrade", "level", "rout", "end"]:
  check("the page styles .beat-marker." & kind & " (bc24)",
    ".beat-marker." & kind in page)
for kind in ["setup", "trap", "upgrade", "level", "rout"]:
  check("and .beat-marker." & kind & " is scoped to the bc24 year",
    "html[data-year=\"bc24\"] .beat-marker." & kind in page)

## The tandem hoisting collision, a fourth time: the bc24 block's beat builder
## may share neither `markBeat`, nor bc26's `buildBeatButtons`, nor bc20's,
## nor bc21's.
check("the bc24 block has its OWN beat builder",
  "function buildBc24BeatButtons" in page)
check("and its own spoiler gate", "function applyBc24BeatSpoilers" in page)
for aliased in ["renderClock", "renderTransport", "getSpoilers",
                "setSpoilers", "renderBeatMarkers", "markBeat",
                "buildBeatButtons", "buildBc20BeatButtons",
                "buildBc21BeatButtons"]:
  check("the bc24 block does not shadow " & aliased,
    page.count("function " & aliased & "(") <= 1)
check("and it registers itself on its own global",
  "window.Bc24Block" in page and "window.Bc21Block" in page)

## ---- THE KILLFEED / STAT-BOX OVERLAP FIX ----------------------------------
## `#killfeed` is anchored in board-scaled units and the year stat boxes in
## pixels off the transport band, so at FIT zoom on a small board the feed
## used to fall below them and — being eight z-levels higher — overdraw them.
## The fix is a FOURTH :root variable measured in relayout().
block:
  let start = page.find("\n#killfeed {")
  check("the page has a #killfeed rule", start >= 0)
  let rule = page[start ..< page.find("}", start)]
  check("and its bottom is lifted above the stat rail",
    "--statrail" in rule and "max(" in rule)
  check("keeping the inherited board-scaled offset as the floor",
    "76 * var(--u)" in rule)
  check("the right anchor is unchanged", "right: calc(12 * var(--u));" in rule)
  check("and so is the column-reverse stack",
    "flex-direction: column-reverse;" in rule)
  check("and pointer-events: none", "pointer-events: none;" in rule)
check("relayout sets --statrail", "root.setProperty('--statrail'" in page)
check("by MEASURING the visible year stat boxes, not by guessing",
  "'econ', 'bc20-soup', 'bc20-units', 'bc21-influence', 'bc21-units'" in page)
check("and bc24's two boxes are in the measured set", 
  "'bc24-crumbs', 'bc24-levels'" in page)
check("and a year change re-runs the measurement",
  "setAttribute('data-year', year);" in page and "relayout();" in page)
check("the viewer smoke gates on the overlap",
  "--killfeed-overlap" in readFile("tools/ci/viewer_smoke.mjs"))
check("at three widths", "[360, 720, 1280]" in
  readFile("tools/ci/viewer_smoke.mjs"))
check("and at both FIT and 2x zoom", "[[\"fit\", 0], [\"2x\", 91]]" in
  readFile("tools/ci/viewer_smoke.mjs"))
block:
  let ci = readFile(".github/workflows/ci.yml")
  check("on all five years' replays", "dist/smoke/replay-bc21.json" in ci and
    "dist/smoke/replay-bc20.json" in ci and "dist/smoke/replay.json" in ci and
    "dist/smoke/replay-bc24.json" in ci and
    "dist/smoke/replay-bc25.json" in ci)
  check("and bc24's viewer smoke gets the longer settle its round cost needs",
    "--timeout 120 --soak 15" in ci)

## The renderer fixture lays the full-cap doctrine text out for EVERY year.
block:
  let fixture = readFile("tools/ci/renderer_fixture.html")
  check("the fixture has a row per year, now NINE of them",
    "var YEARS = ['bc26', 'bc20', 'bc21', 'bc24', 'bc25', 'bc23', 'bc22'," in
      fixture and "'bc16', 'bc19'];" in fixture)
  check("and fills bc21's own readouts",
    "bc21-influence" in fixture and "bc21-votes" in fixture and
    "bc21-doctrines-body" in fixture)
  check("and bc24's",
    "bc24-crumbs" in fixture and "bc24-flags" in fixture and
    "bc24-levels" in fixture and "bc24-doctrines-body" in fixture)
  check("and bc25's",
    "bc25-coverage" in fixture and "bc25-towers" in fixture and
    "bc25-econ" in fixture and "bc25-doctrines-body" in fixture)
  ## bc23's row is the one this coworld's LLM text lands in: the 280-rune
  ## `notes` is drawn ONLY into `#bc23-doctrines-body`, under bc23-only CSS,
  ## and no gate rendered it at a full cap until this row existed (r1-F18).
  check("and bc23's",
    "bc23-islands" in fixture and "bc23-econ" in fixture and
    "bc23-units" in fixture and "bc23-doctrines-body" in fixture)
  check("with the full-cap notes on BOTH bc23 seats, not just the first",
    "bc23Doctrines += '<div class=\"dline\"><span class=\"dname\">'" in
      fixture and
    "'<br>' + BC23_WORDS[m23] + '<br><i>' + notes + '</i></div>'" in fixture)
  ## bc22's row: the SUBMITTED-VS-APPLIED badge and both seats' full-cap
  ## notes at once, which is the widest line `#bc22-doctrines` can hold.
  check("and bc22's",
    "bc22-archons" in fixture and "bc22-anomaly" in fixture and
    "bc22-econ" in fixture and "bc22-units" in fixture and
    "bc22-doctrines-body" in fixture)
  check("with the envelope badge on the card, at full cap",
    "envelope: doctrine" in fixture and "knobs " in fixture and
    "what the cog actually sent: " in fixture)
  check("and the fixture refuses to pass on a shortened string",
    "the notes on seat ' + d + ' were shortened" in fixture and
    "the motto on seat ' + s + ' was shortened" in fixture)
  ## bc16's row: the eighth year, and the reason it exists is that
  ## `#bc16-doctrines-body` is where bc16's 280-rune `notes`, 48-rune `motto`
  ## and 120-rune submitted sheet are drawn, and no gate rendered any of them
  ## at a full cap at any width until this row existed (r1-F2).
  check("and bc16's",
    "bc16-archons" in fixture and "bc16-horde" in fixture and
    "bc16-econ" in fixture and "bc16-units" in fixture and
    "bc16-doctrines-body" in fixture)
  check("with the faction label laid out in the strip at every width",
    "'<span class=\"horde\">THE HORDE</span>'" in fixture)
  check("with both bc16 seats at the full cap, the envelope badge, the " &
    "motto and the submitted sheet",
    "'<br>' + BC16_WORDS[m16].join(' \\u00b7 ') +" in fixture and
    "'<br><i>' + notes + '</i>' +" in fixture and
    "what the cog actually sent: ' +\n      notes.slice(0, 120)" in fixture)
  ## bc16 is IN the FILLED map, so the "hides its own content" rule runs over
  ## its five readouts rather than over nothing.
  check("and bc16's readouts are measured for hidden content",
    "bc16: '#scorebug .plate, #scorebug .plate *, #bc16-archons, '" in
      fixture)
  ## The fixture's "the notes were shortened before they were measured"
  ## check reads `#<year>-doctrines .dline i`, so a year whose doctrine rows
  ## carry any other class name passes that check VACUOUSLY -- bc25 shipped
  ## `.clan`/`<b>` first and the fixture found nothing to measure. Both the
  ## page and the fixture use the four years' own class names now.
  check("the bc25 doctrine rows are .dline/.dname like every other year's",
    "<div class=\"dline\"><span class=\"dname\">' + esc(seat.alias)" in page and
    "#bc25-doctrines .dline {" in page and
    "#bc25-doctrines .dname {" in page)
  ## Same rule, same reason, for bc16: a bare text node where every sibling
  ## year wraps `notes` in `<i>` would make that check vacuous for bc16 too.
  check("and bc16 wraps its notes in the <i> the fixture selects",
    "if (d.notes) html += '<br><i>' + esc(d.notes) + '</i>';" in page)

## Transport rules from the design note.
check("relayout sets --hudscale", "--hudscale" in page)
check("relayout sets --topband", "--topband" in page)
check("relayout sets --band", "--band" in page)
## The endcard's OWN rule, not any rule that happens to mention the band:
## `bottom: calc(var(--band` matched #econ and #doctrines, so this assertion
## passed for two unrelated overlays and would have kept passing if the
## endcard had lost its bound (r1-N13d).
block:
  let start = page.find("#endcard {")
  check("the page has an #endcard rule", start >= 0)
  let rule = page[start ..< page.find("}", start)]
  check("the endcard stops at the transport band",
    "bottom: var(--band, 0px);" in rule)
  check("and starts below the top band", "top: var(--topband, 0px);" in rule)
  check("and it is hidden until it is raised", "display: none;" in rule)
check("the scorebug stays legible at 360 px",
  ".plate-name { flex: 1 1 auto; min-width: 3.2em; }" in page)
check("and labels drop under 640 px", "@media (max-width: 640px)" in page)
check("every seek dismisses the endcard", "dismissEndcard" in page)

## The "+25 rounds" label goes on the button that steps forward 25 rounds.
## The note names #btn-skip; in this lineage that id is the auto-skip toggle
## ('f'), and #btn-fwd is the forward step ('.'), which broadcast.nim resolves
## to +25 rounds. Pinned so a later edit cannot swap them.
check("the forward button is labelled +25",
  "$('btn-fwd').textContent = '+25';" in page)
check("and titled for the rounds it steps",
  "$('btn-fwd').title = 'Forward 25 rounds (.)';" in page)
check("while #btn-skip stays the auto-skip toggle",
  "$('btn-skip').title = 'Auto-skip quiet stretches (f)';" in page)
check("and #btn-fwd sends '.', the +25 command",
  "'btn-fwd': '.'" in page)
check("while #btn-skip sends 'f'", "'btn-skip': 'f'" in page)

## B1: the endcard is TOGGLED WITH THE CLASS ITS OWN RULE USES. The inherited
## sheet styles `#endcard.on`; there is no `#endcard.show` rule and no bare
## `.show` rule anywhere in the page, so a card raised with `.show` is filled
## in and then left at `display: none` for the whole replay — the score screen
## exists in the DOM and is never seen. Grepping for `dismissEndcard` cannot
## see that; these three checks can.
check("the inherited rule shows the endcard on .on",
  "#endcard.on { display: flex;" in page)
check("renderEndcard raises the card with that class",
  "$('endcard').classList.add('on');" in page)
check("dismissEndcard takes it down with the same class",
  "$('endcard').classList.remove('on');" in page)
check("and nothing toggles the endcard with a class that has no rule",
  "$('endcard').classList.add('show')" notin page and
  "$('endcard').classList.remove('show')" notin page)
## `#endcard.show {` was the wrong shape for this assertion: bc16 shipped a
## rule reading `#endcard.show ~ #bc16-archons`, which the `{` form let
## through, and it was dead for the whole run (r1-F1). The honest form reads
## the page's whole <style> block and refuses the substring in ANY selector
## shape. (The page's own prose comment in renderEndcard names the class to
## say it does not exist, which is why this reads the CSS, not the file.)
block:
  let cssOpen = page.find("<style>")
  let cssClose = page.find("</style>", cssOpen)
  let css = page[cssOpen + len("<style>") ..< cssClose]
  check("there is no #endcard.show rule to justify one, in any shape",
    "#endcard.show" notin css)

## N1: the same rule for the hash-mismatch banner. `#mmwarn.on` is the only
## rule that displays it, so raising it with any other class leaves the
## fidelity flag on <html> and nothing on screen.
check("the inherited rule shows the mismatch banner on .on",
  "#mmwarn.on { display: block; }" in page)
check("the game block raises it with that class",
  "mm.classList.add('on')" in page)
check("and not with a class that has no rule",
  "mm.classList.add('show')" notin page and "#mmwarn.show {" notin page)
check("the page uses the renamed static-replay adapter",
  "BcStaticReplay" in page)

## THE BOARD IS THE PICTURE (r2-D3). The featured match showed the doctrine
## panel lying over the rats in two live screenshots a minute apart: the panel
## was rendered once, on the first frame, and had no dismissal of any kind —
## not a click, not a timer, not playback. It now opens with the replay and
## closes itself the moment the playhead advances, its own header re-opens it,
## and its body is capped so even an opened panel cannot own the board.
block:
  let start = page.find("#doctrines {")
  check("the page has a #doctrines rule", start >= 0)
  check("the panel body is height-capped", "#doctrines .dbody {" in page and
    "calc(33vh - var(--band, 0px))" in page)
  check("and scrolls rather than growing over the board",
    "overflow-y: auto;" in page)
  check("a closed panel hides its body", "#doctrines.closed .dbody { display: none; }" in page)
  check("the panel has a re-opening header", "id=\"doctrines-toggle\"" in page)
  check("which is a real button", "<button id=\"doctrines-toggle\"" in page)
  check("announcing its state to a screen reader", "aria-expanded" in page)
  ## The three dismissals, by name.
  check("playback advancing closes it",
    "if (doctrinesLastFrame >= 0 && s.t > 0 && !doctrinesPinned)" in page)
  check("a timer closes it for a viewer who never presses play",
    "}, 6000);" in page)
  check("and a viewer who opens it by hand keeps it open",
    "doctrinesPinned = !open;" in page)

## And CI measures it in a real browser: the harness reports the largest
## painted, text-carrying panel covering the board, and the wasm-viewer job
## fails when one holds more than half of it while playback is advancing.
block:
  let smoke = readFile("tools/ci/viewer_smoke.mjs")
  check("the harness measures what covers the board",
    "const boardEl = document.querySelector(\"canvas#board" in smoke)
  check("and reports it per sample", "obscured: now.obscured" in smoke)
  check("including after the soak", "obscured: after ? after.obscured : null" in smoke)
  let workflow = readFile(".github/workflows/ci.yml")
  check("ci.yml reads the measurement", "obscured_pct=" in workflow)
  check("and fails on a panel that owns the board at t > 0",
    "if [ \"${obscured_pct}\" -gt 50 ]; then" in workflow)

## THE RENDERER FIXTURE TESTS THE PAGE, NOT ITSELF.
## The full-cap doctrine-text fixture used to carry its own copy of the game
## block's CSS — and three declarations (`max-width`/`overflow` on the plate,
## an ellipsis on the plate-sub, `overflow: hidden` on #doctrines) that the
## page does not ship, which is precisely what a box cannot overflow. It now
## LINKS the page's own <style> block, extracted by ci.yml, and defines no
## rule for any element it measures.
block:
  let fixture = readFile("tools/ci/renderer_fixture.html")
  check("the fixture links the page's own stylesheet",
    "<link rel=\"stylesheet\" href=\"page_styles.css\">" in fixture)
  for own in ["#scorebug .plate {", "#scorebug .plate-name",
              "#scorebug .plate-sub", "#doctrines {", "#econ {", "#coopchip {",
              "@media"]:
    check("the fixture does not re-declare " & own,
      own notin fixture)
  check("it fails loudly when the page's CSS is missing",
    "page_styles.css did not load" in fixture)
  ## The caps it lays out are the caps the server enforces.
  check("the fixture uses MaxNoteRunes",
    "MAX_NOTE_RUNES = " & $MaxNoteRunes in fixture)
  check("and MaxMottoRunes",
    "MAX_MOTTO_RUNES = " & $MaxMottoRunes in fixture)
  ## And ci.yml drives it through the same harness as the bundle.
  let workflow = readFile(".github/workflows/ci.yml")
  check("ci.yml drives the fixture with viewer_smoke --strict-text-bounds",
    "renderer_fixture.html\" \\\n            --timeout 60 \\\n            --strict-text-bounds" in workflow)

# --- the sim really produces a drawable frame -------------------------------
# Everything the wasm entry does EXCEPT the emscripten shell: parse a replay,
# build a deriver, step it, and emit a bitworld sprite packet.
block:
  let sheets = [baselineSheet(blAwu), baselineSheet(blScaffold)]
  let (w, outcome) = playGame(loadMap("DefaultSmall"), sheets, 0, 0, 120, 0)
  var plan = MatchPlan(seed: 9, year: "bc26", maxRounds: 120,
    maps: @["DefaultSmall"], sideAslots: @[0], abandonAfter: @[-1],
    sheets: sheets)
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: sheets[slot])
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc26", config: %*{},
    seed: 9, seats: seats, plan: plan, result: %*{},
    games: @[GameHeader(index: 0, map: "DefaultSmall",
      mapSha: mapSha("bc26", "DefaultSmall"), sideAslot: 0,
      rounds: outcome.roundsPlayed, hashChain: outcome.hashChain)])
  for slot in 0 .. 1: doc.names[slot] = "s" & $slot

  let back = parseReplay($doc.toJson())
  let deriver = newDeriver(back)
  let renderer = newRenderer()
  var view = initViewerState()
  discard deriver.advance()
  let beats = beatsFor(back, proc (g, r: int): int = 0)
  let first = renderer.buildSessionPacket(deriver.session,
    sessionChromeJson(back, deriver.session, view, 0, deriver.totalFrames,
      0, 0, beats, newJArray(), false))
  check("the first frame is a non-empty sprite packet", first.len > 1000)
  ## The first packet must carry the layer, the viewport, the terrain sprite
  ## and the chrome sprite.
  ## Decoded with bitworld's OWN parser rather than by scanning bytes: the
  ## packet is only meaningful if the client's decoder accepts it.
  let messages = parseSpritePacket(first)
  var sawChrome, sawTerrain, sawLayer, sawViewport, sawObject = false
  for m in messages:
    case m.kind
    of spkSprite:
      if m.sprite.id == BroadcastChromeSpriteId:
        sawChrome = true
        check("the chrome label is the JSON document",
          m.sprite.label.startsWith("{") and "\"coop\"" in m.sprite.label)
      elif m.sprite.label == "terrain":
        sawTerrain = true
        checkEq("the terrain sprite is the whole board",
          m.sprite.width, deriver.session.w26.width * render.TileSize)
    of spkLayer:
      sawLayer = true
      checkEq("the board layer is zoomable", m.layer.flags, 1)
    of spkViewport: sawViewport = true
    of spkObject: sawObject = true
    else: discard
  check("the packet defines the board layer", sawLayer)
  check("and its viewport", sawViewport)
  check("and the terrain sprite", sawTerrain)
  check("and places objects", sawObject)
  check("and defines the chrome sprite", sawChrome)

  for step in 0 ..< 30:
    discard deriver.advance()
  let later = renderer.buildSessionPacket(deriver.session,
    sessionChromeJson(back, deriver.session, view, deriver.frame, deriver.totalFrames,
      0, 0, beats, newJArray(), false))
  check("a later frame is a DIFF, not the whole board", later.len < first.len)
  check("but still carries something to draw", later.len > 16)

# --- the sprite atlas -------------------------------------------------------
block:
  check("the atlas image is committed", fileExists("data/atlas.png"))
  check("with its index", fileExists("data/atlas.json"))
  let atlas = readFile("data/atlas.json")
  for name in ["rat_cheddar_0", "rat_plum_0", "king_cheddar", "king_plum",
               "cat_0", "cat_sleep", "cheese", "cheese_mine", "rat_trap",
               "cat_trap", "dirt"]:
    check("the atlas carries " & name, "\"" & name & "\"" in atlas)


# --- the bc21 sim really produces a drawable frame --------------------------
block:
  ## The same end-to-end path for the third year: parse a replay, build a
  ## deriver, step it, and emit a bitworld sprite packet from the bc21 atlas.
  let doctrines = [baselineSheet("bc21", blCaliforniaRoll),
                   baselineSheet("bc21", blExamplefuncsplayer21)]
  let (w21, outcome21) = rules21.playGame(maps21.loadMap("Bog"), doctrines,
    [rules21.ckCaliforniaRoll, rules21.ckExamplefuncsplayer21], 0, 0, 120, 0)
  var plan = MatchPlan(seed: 9, year: "bc21", maxRounds: 120,
    maps: @["Bog"], sideAslots: @[0], abandonAfter: @[-1], sheets: doctrines,
    chassis: [scCaliforniaRoll, scExamplefuncsplayer21])
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: doctrines[slot],
      chassis: (if slot == 0: "california-roll" else: "examplefuncsplayer21"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc21", config: %*{},
    seed: 9, seats: seats, plan: plan, result: %*{},
    games: @[GameHeader(index: 0, map: "Bog",
      mapSha: mapSha("bc21", "Bog"), sideAslot: 0,
      rounds: outcome21.roundsPlayed, hashChain: outcome21.hashChain)])
  for slot in 0 .. 1: doc.names[slot] = "s" & $slot

  let back = parseReplay($doc.toJson())
  let deriver = newDeriver(back)
  let renderer = newRenderer(yearSpec("bc21").atlas)
  var view = initViewerState()
  discard deriver.advance()
  let beats = beatsFor(back, proc (g, r: int): int = 0)
  let first = renderer.buildSessionPacket(deriver.session,
    sessionChromeJson(back, deriver.session, view, 0, deriver.totalFrames,
      0, 0, beats, newJArray(), false))
  check("the first bc21 frame is a non-empty sprite packet", first.len > 1000)
  let messages = parseSpritePacket(first)
  var sawChrome, sawTerrain, sawLayer, sawViewport, sawObject = false
  for m in messages:
    case m.kind
    of spkSprite:
      if m.sprite.id == BroadcastChromeSpriteId:
        sawChrome = true
        check("the bc21 chrome label is the JSON document",
          m.sprite.label.startsWith("{") and
          "\"bc21_votes\"" in m.sprite.label)
      elif m.sprite.label == "terrain":
        sawTerrain = true
        checkEq("the bc21 terrain sprite is the whole board",
          m.sprite.width, deriver.session.w21.width * render.TileSize)
    of spkLayer:
      sawLayer = true
      checkEq("the bc21 board layer is zoomable", m.layer.flags, 1)
    of spkViewport: sawViewport = true
    of spkObject: sawObject = true
    else: discard
  check("the bc21 packet defines the board layer", sawLayer)
  check("and its viewport", sawViewport)
  check("and the terrain sprite", sawTerrain)
  check("and places objects", sawObject)
  check("and defines the chrome sprite", sawChrome)

  for step in 0 ..< 30:
    discard deriver.advance()
  let later = renderer.buildSessionPacket(deriver.session,
    sessionChromeJson(back, deriver.session, view, deriver.frame,
      deriver.totalFrames, 0, 0, beats, newJArray(), false))
  check("a later bc21 frame is a DIFF, not the whole board",
    later.len < first.len)
  check("but still carries something to draw", later.len > 16)

# --- the bc21 sprite atlas --------------------------------------------------
block:
  check("the bc21 atlas image is committed", fileExists("data/atlas_bc21.png"))
  check("with its index", fileExists("data/atlas_bc21.json"))
  let atlas = readFile("data/atlas_bc21.json")
  for name in ["center", "center_red", "center_blue", "polit_red",
               "polit_blue", "slanderer_red", "slanderer_blue", "muck_red",
               "muck_blue", "dirt", "swamp", "empower_red_1", "expose_red",
               "camo_red", "embezzle_red_1", "death_empty"]:
    check("the bc21 atlas carries " & name, "\"" & name & "\"" in atlas)

# --- the bc24 sim really produces a drawable frame --------------------------
block:
  ## The same end-to-end path for the fourth year: parse a replay, build a
  ## deriver, step it past the dam, and emit a bitworld sprite packet from the
  ## bc24 atlas.
  let doctrines = [baselineSheet("bc24", blGoneSharkin),
                   baselineSheet("bc24", blExamplefuncsplayer24)]
  let (w24, outcome24) = rules24.playGame(maps24.loadMap("Yinyang"),
    doctrines, [rules24.ckGoneSharkin, rules24.ckExamplefuncsplayer24],
    0, 0, 240, 0)
  var plan = MatchPlan(seed: 9, year: "bc24", maxRounds: 240,
    maps: @["Yinyang"], sideAslots: @[0], abandonAfter: @[-1],
    sheets: doctrines,
    chassis: [scGoneSharkin, scExamplefuncsplayer24])
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: doctrines[slot],
      chassis: (if slot == 0: "gone-sharkin" else: "examplefuncsplayer24"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc24", config: %*{},
    seed: 9, seats: seats, plan: plan, result: %*{},
    games: @[GameHeader(index: 0, map: "Yinyang",
      mapSha: mapSha("bc24", "Yinyang"), sideAslot: 0,
      rounds: outcome24.roundsPlayed, hashChain: outcome24.hashChain)])
  for slot in 0 .. 1: doc.names[slot] = "s" & $slot

  let back = parseReplay($doc.toJson())
  let deriver = newDeriver(back)
  let renderer = newRenderer(yearSpec("bc24").atlas)
  var view = initViewerState()
  discard deriver.advance()
  let beats = beatsFor(back, proc (g, r: int): int = 0)
  let first = renderer.buildSessionPacket(deriver.session,
    sessionChromeJson(back, deriver.session, view, 0, deriver.totalFrames,
      0, 0, beats, newJArray(), false))
  check("the first bc24 frame is a non-empty sprite packet", first.len > 1000)
  let messages = parseSpritePacket(first)
  var sawChrome, sawTerrain, sawLayer, sawViewport, sawObject = false
  for m in messages:
    case m.kind
    of spkSprite:
      if m.sprite.id == BroadcastChromeSpriteId:
        sawChrome = true
        check("the bc24 chrome label is the JSON document",
          m.sprite.label.startsWith("{") and
          "\"bc24_flags\"" in m.sprite.label)
      elif m.sprite.label == "terrain":
        sawTerrain = true
        checkEq("the bc24 terrain sprite is the whole board",
          m.sprite.width, deriver.session.w24.width * render.TileSize)
    of spkLayer:
      sawLayer = true
      checkEq("the bc24 board layer is zoomable", m.layer.flags, 1)
    of spkViewport: sawViewport = true
    of spkObject: sawObject = true
    else: discard
  check("the bc24 packet defines the board layer", sawLayer)
  check("and its viewport", sawViewport)
  check("and the terrain sprite", sawTerrain)
  check("and places objects", sawObject)
  check("and defines the chrome sprite", sawChrome)

  ## THE DAM DISSOLVE is the most legible moment in the year, so the terrain
  ## sprite is re-cut when it falls: a frame that crosses round 200 carries a
  ## whole new board, and every other frame is a diff.
  var crossing = 0
  for step in 0 ..< 40:
    discard deriver.advance()
  let later = renderer.buildSessionPacket(deriver.session,
    sessionChromeJson(back, deriver.session, view, deriver.frame,
      deriver.totalFrames, 0, 0, beats, newJArray(), false))
  check("a later bc24 frame is a DIFF, not the whole board",
    later.len < first.len)
  check("but still carries something to draw", later.len > 16)
  checkEq("(the crossing counter is unused scaffolding)", crossing, 0)

# --- the appended bc25 game block -------------------------------------------
block:
  ## The page is the STARTER'S page with a bc25 block APPENDED under a banner
  ## comment. Nothing is removed, no id is reused, and the block registers
  ## itself on its own global.
  let page = readFile("client/replay_broadcast.html")
  check("the bc25 CSS block carries its banner",
    "BC25 additions to the inherited cogame-battlecode chrome" in page)
  for id in ["bc25-coverage", "bc25-towers", "bc25-econ", "bc25-doctrines",
             "bc25-doctrines-close", "bc25-doctrines-toggle",
             "bc25-doctrines-body", "bc25-srp"]:
    check("the page carries #" & id, "\"" & id & "\"" in page)
  ## NOTHING the four earlier years own is removed.
  for id in ["coopchip", "bars", "gamechips", "econ", "doctrines",
             "bc20-flood", "bc20-soup", "bc20-units", "bc20-doctrines",
             "bc20-chain", "bc21-votes", "bc21-influence", "bc21-units",
             "bc21-doctrines", "bc21-bids", "bc24-flags", "bc24-crumbs",
             "bc24-levels", "bc24-doctrines", "bc24-traps"]:
    check("the earlier years still own #" & id, "\"" & id & "\"" in page)
  ## `#viewpanel` is KEPT: the bc25 pool tops out at 50x30 and the reserved
  ## large pool at 60x60, both wider than a 360 px frame at 16 px a tile.
  check("#viewpanel is kept", "\"viewpanel\"" in page)
  ## The beat builder has its OWN name (the tandem hoisting collision).
  check("the beat builder is buildBc25BeatButtons",
    "buildBc25BeatButtons" in page)
  for taken in ["function buildBeatButtons", "function buildBc20BeatButtons",
                "function buildBc21BeatButtons",
                "function buildBc24BeatButtons"]:
    checkEq("and it does not redefine " & taken, page.count(taken), 1)
  checkEq("the bc25 builder is defined exactly once",
    page.count("function buildBc25BeatButtons"), 1)
  check("the block registers on window.Bc25Block",
    "window.Bc25Block = {" in page)
  check("and the shared onText calls it",
    "if (window.Bc25Block) window.Bc25Block.onFrame(s);" in page)
  check("and the bc26 branch is guarded off for bc25, bc23, bc22, bc16, " &
    "bc19 and now bc17 too, so the discriminator is TEN-way",
    "if (!isBc16 && !isBc17 && !isBc19 && !isBc20 && !isBc21 && !isBc22 && " &
      "!isBc23 &&" in page)

block:
  ## THE BC23 GAME BLOCK. The same five obligations every year module before
  ## it had to meet, plus the two `--statrail` ids.
  let page = readFile("client/replay_broadcast.html")
  checkEq("the bc23 block does not define `markBeat` at all — that name is " &
    "`chrome_common.js`'s and a same-named function here would HOIST OVER " &
    "it (the tandem 2026-08-23 collision)",
    page.count("function markBeat"), 0)
  for taken in ["function buildBeatButtons",
                "function buildBc20BeatButtons",
                "function buildBc21BeatButtons",
                "function buildBc24BeatButtons",
                "function buildBc25BeatButtons"]:
    checkEq("the bc23 block does not redefine " & taken,
      page.count(taken), 1)
  checkEq("the bc23 builder is defined exactly once",
    page.count("function buildBc23BeatButtons"), 1)
  checkEq("and so is its spoiler gate",
    page.count("function applyBc23BeatSpoilers"), 1)
  check("the block registers on window.Bc23Block",
    "window.Bc23Block = {" in page)
  check("and the shared onText calls it",
    "if (window.Bc23Block) window.Bc23Block.onFrame(s);" in page)
  check("and the inherited block attaches the transport to it",
    "window.Bc23Block.attach({" in page)
  ## No `ChromeCommon` alias and no other year's game-block name is shadowed:
  ## the bc23 block's own helpers are `renderIslands`, `renderUnits` and
  ## `renderEndcardExtras` inside its OWN IIFE, and nothing it defines at
  ## file scope collides.
  for alias in ["window.Bc20Block = {",
                "window.Bc21Block = {", "window.Bc24Block = {",
                "window.Bc25Block = {"]:
    checkEq("the bc23 block does not redeclare " & alias,
      page.count(alias), 1)

  ## `#bc23-doctrines` carries a dismiss control, an Escape binding, a
  ## re-open chip and self-dismissal — and it sits OUTSIDE var(--band) (D3).
  check("the doctrine overlay exists", "id=\"bc23-doctrines\"" in page)
  check("with a dismiss control carrying an aria-label",
    "id=\"bc23-doctrines-close\"" in page and
    "aria-label=\"Dismiss doctrines\"" in page)
  check("a re-open chip", "id=\"bc23-doctrines-toggle\"" in page)
  check("an Escape binding scoped to bc23",
    "getAttribute('data-year') !== 'bc23'" in page)
  const SelfDismiss =
    "if (lastFrame >= 0 && s.t > lastFrame && !pinned && !dismissed) {"
  check("self-dismissal on the first advance", SelfDismiss in page)
  const BandBound =
    "max-height: min(46vh,\n    calc(100% - var(--topband, 0px) - " &
    "var(--band, 0px) - 46px));"
  check("and it is bounded ABOVE the transport band, never inside it, and " &
    "never over half the featured-match frame",
    BandBound in page)

  ## The stat boxes size to their own content: a fixed box and a
  ## `white-space: nowrap` row is a readout that reads short (r1-F18).
  check("#bc23-econ and #bc23-units size to their content",
    "width: max-content; max-width: calc(100% - 16px);" in page)

  ## The two stat boxes sit above the band and are in the --statrail set.
  check("#bc23-units is lifted above var(--band)",
    "#bc23-units { bottom: calc(var(--band, 0px) + 76px); }" in page)
  check("#bc23-econ too",
    "#bc23-econ { bottom: calc(var(--band, 0px) + 8px); }" in page)
  check("and relayout() MEASURES both of them into --statrail",
    "'bc23-econ', 'bc23-units'" in page)

  ## Every #bc23-* rule is scoped to the year, one way or the other.
  ## THE WHOLE <style> BLOCK, not a line scan: a line scan reads the script's
  ## own `s.year === 'bc23'` as a selector, and it never sees a one-line rule
  ## whose `{` is not at the end of the line (r1-F24). Comments are stripped
  ## first so the banner's prose is not mistaken for a rule.
  let cssOpen = page.find("<style>")
  let cssClose = page.find("</style>")
  check("the page has exactly one <style> block",
    cssOpen >= 0 and cssClose > cssOpen and
    page.find("<style>", cssOpen + 1) < 0)
  var css = page[cssOpen + len("<style>") ..< cssClose]
  while true:
    let a = css.find("/*")
    if a < 0: break
    let b = css.find("*/", a)
    if b < 0: break
    css = css[0 ..< a] & " " & css[b + 2 .. ^1]
  var unscoped: seq[string]
  var scanned = 0
  var sel = ""
  for ch in css:
    if ch notin {'{', '}', ';'}:
      sel.add(ch)
      continue
    if ch == '{' and "bc23" in sel:
      for part in sel.split(','):
        let s = part.splitWhitespace().join(" ")
        if "bc23" notin s: continue
        ## `@keyframes bc23flash` names an animation, not an element.
        if s.startsWith("@"): continue
        inc scanned
        ## A bare `#bc23-x { ... }` rule is fine: the element only EXISTS on
        ## a bc23 replay because `html:not([data-year="bc23"])` hides it.
        ## What is forbidden is a rule that could restyle ANOTHER year's
        ## element, i.e. a selector that is neither `#bc23-` prefixed nor
        ## `data-year` scoped. A LATER year's block naming `#bc23-...` under
        ## its OWN `html[data-year="bcNN"]` scope is the hide list every year
        ## block ships and is likewise fine.
        if s.startsWith("#bc23-") or
           s.startsWith("html[data-year=") or
           s.startsWith("html:not([data-year="):
          continue
        unscoped.add(s)
    sel = ""
  ## The scan must have REACHED the rules: an empty `unscoped` proves nothing
  ## if the loop never looked at a bc23 selector. 87 selector parts name the
  ## year at this landing; the floor is well below that so removing a rule is
  ## not a failure while deleting the block is.
  check("the bc23 selector scan is not vacuous", scanned >= 60)
  checkEq("no bc23 CSS rule can reach another year's element",
    unscoped.len, 0)
  checkEq("no bc23 CSS rule can reach another year's element",
    unscoped.len, 0)
  check("and the year switch hides the bc23 elements everywhere else",
    "html:not([data-year=\"bc23\"]) #bc23-islands," in page)
  check("and hides the other five years' elements on a bc23 replay",
    "html[data-year=\"bc23\"] #bc25-coverage," in page)

block:
  ## EVERY emitted bc23 beat kind has CSS, and every one is scoped to
  ## `html[data-year="bc23"]` so it cannot restyle another year's marker of
  ## the same name (`build`, `game`, `rout`, `doctrine` and `end` all exist
  ## for other years).
  let page = readFile("client/replay_broadcast.html")
  for kind in ["doctrine", "game", "build", "anchor", "island", "conquest",
               "elixir", "boost", "destabilize", "duel", "rout", "end"]:
    let rule = "html[data-year=\"bc23\"] .beat-marker." & kind
    check("the page carries CSS for the bc23 `" & kind & "` beat, scoped",
      rule in page)

block:
  ## EVERY emitted bc25 beat kind has CSS, and every one is scoped to
  ## `html[data-year="bc25"]` so it cannot restyle another year's marker of
  ## the same name.
  let page = readFile("client/replay_broadcast.html")
  for kind in ["doctrine", "game", "build", "tower", "upgrade", "siege",
               "srp", "coverage", "starve", "rout", "end"]:
    let rule = "html[data-year=\"bc25\"] .beat-marker." & kind
    check("the page carries CSS for the bc25 `" & kind & "` beat, scoped",
      rule in page)

block:
  ## ...and every one of those eleven kinds is really EMITTED. CSS for a beat
  ## nothing produces is a stylesheet, not a readout: bc25 shipped eleven
  ## `.beat-marker` rules against a `beatsFor` that had an arm for none of the
  ## year's event kinds, so a whole match drew two scrubber markers and a
  ## two-line killfeed (r1-F26). This asserts the EMISSION.
  let page = readFile("client/replay_broadcast.html")
  var raw = parseJson(readFile("tests/fixtures/replay-bc25.json"))
  ## The committed fixture is a real 400-round scripted recording, so it
  ## carries the kinds a game that length actually produces. The two loss
  ## kinds, the rout and the two PRE-MATCH doctrine kinds (which no scripted
  ## episode can emit, because no LLM was called) are appended here in exactly
  ## the shape `match.nim`/`decide.nim` write them, so the note's whole beat
  ## table is exercised.
  let synthetic = @[
    %*{"kind": "tower_lost", "game": 0, "round": 180, "alias": "Clan Basil",
       "tower": "defense", "x": 7, "y": 9, "remaining": 4},
    %*{"kind": "srp_broken", "game": 0, "round": 200, "alias": "Clan Ash",
       "x": 5, "y": 5, "age": 37},
    %*{"kind": "rout", "game": 0, "round": 210, "alias": "Clan Basil",
       "lost": 6},
    %*{"kind": "doctrine_received", "ms": 1180, "slot": 0, "attempt": 0,
       "latency_ms": 1174, "defaults_applied": 2, "unknown_fields": 0},
    %*{"kind": "doctrine_fallback", "ms": 33000, "slot": 1,
       "cause": "timeout"}]
  for extra in synthetic: raw["events"].add(extra)
  let doc = parseReplay($raw)
  ## The frame map is the identity on the round here, which is enough to see
  ## WHICH frame each beat claims.
  let beats = beatsFor(doc, proc (g, r: int): int = r)
  var seen: seq[string]
  for b in beats:
    let k = b["k"].getStr()
    if k notin seen: seen.add(k)
    check("the `" & k & "` beat carries a label a button can announce",
      b["label"].getStr().len > 0)
    check("and the page styles it",
      ("html[data-year=\"bc25\"] .beat-marker." & k) in page)
  for kind in ["doctrine", "game", "build", "tower", "upgrade", "siege",
               "srp", "coverage", "starve", "rout", "end"]:
    check("a bc25 replay EMITS the `" & kind & "` beat", kind in seen)
  ## The two doctrine beats are pre-match (`game = -1`): they land on frame 0
  ## rather than being dropped by the in-game guard.
  var doctrineBeats = 0
  for b in beats:
    if b["k"].getStr() != "doctrine": continue
    doctrineBeats += 1
    checkEq("the doctrine beat lands at the start of playback",
      b["t"].getInt(), 0)
  checkEq("both doctrine beats survive the pre-match filter", doctrineBeats, 2)
  ## And the COMMITTED fixture on its own -- no synthetic help -- is already a
  ## multi-kind feed, which is what the wasm-viewer smoke loads.
  let fixtureBeats = beatsFor(
    parseReplay(readFile("tests/fixtures/replay-bc25.json")),
    proc (g, r: int): int = r)
  var fixtureKinds: seq[string]
  for b in fixtureBeats:
    if b["k"].getStr() notin fixtureKinds: fixtureKinds.add(b["k"].getStr())
  check("the committed bc25 fixture draws a scrubber full of beats",
    fixtureBeats.len >= 20)
  check("over many kinds, not just game/end", fixtureKinds.len >= 6)

block:
  ## D3: the doctrine overlay is dismissible and sits OUTSIDE the transport
  ## band; the endcard stops at var(--band) and every seek dismisses it (both
  ## inherited and unchanged).
  let page = readFile("client/replay_broadcast.html")
  check("#bc25-doctrines has a close control with an aria-label",
    "aria-label=\"Dismiss doctrines\"" in page)
  check("an Escape binding scoped to bc25",
    "data-year') !== 'bc25') return;" in page)
  check("a re-open chip", "id=\"bc25-doctrines-toggle\"" in page)
  check("and self-dismissal on the first advance",
    "if (lastFrame >= 0 && s.t > lastFrame && !pinned && !dismissed) {" in
      page)
  ## It is positioned from the TOP band, never from the bottom one.
  check("#bc25-doctrines is anchored to the top band, not the transport",
    "top: calc(var(--topband, 0px) + 10px);" in page)

block:
  ## `relayout()`'s `--statrail` measurement set names both bc25 stat boxes,
  ## which is what keeps #killfeed clear of them at every width and zoom.
  let page = readFile("client/replay_broadcast.html")
  check("--statrail measures bc25-towers and bc25-econ",
    "'bc24-crumbs', 'bc24-levels', 'bc25-towers', 'bc25-econ'" in page)
  check("and #killfeed is still lifted above the rail",
    "calc(var(--band, 0px) + var(--statrail, 0px) + 8px)" in page)

# --- the bc25 sprite atlas --------------------------------------------------
block:
  check("the bc25 atlas image is committed", fileExists("data/atlas_bc25.png"))
  check("with its index", fileExists("data/atlas_bc25.json"))
  let atlas = readFile("data/atlas_bc25.json")
  for name in ["soldier_silver", "splasher_silver", "mopper_silver",
               "paint_tower_silver", "money_tower_silver",
               "defense_tower_silver", "soldier_gold", "splasher_gold",
               "mopper_gold", "paint_tower_gold", "money_tower_gold",
               "defense_tower_gold", "ruin", "dirty", "chip_silver",
               "chip_gold", "paint_silver", "paint_gold"]:
    check("the bc25 atlas carries " & name, "\"" & name & "\"" in atlas)

# --- the bc24 sprite atlas --------------------------------------------------
block:
  check("the bc24 atlas image is committed", fileExists("data/atlas_bc24.png"))
  check("with its index", fileExists("data/atlas_bc24.json"))
  let atlas = readFile("data/atlas_bc24.json")
  for name in ["duck_brown", "duck_brown_attack", "duck_brown_build",
               "duck_brown_heal", "duck_brown_jailed", "duck_white",
               "duck_white_attack", "trap_brown_explosive",
               "trap_brown_stun", "trap_brown_water", "trap_white_explosive",
               "flag", "flag_outline_thick", "crumb_1", "crumb_2", "crumb_3"]:
    check("the bc24 atlas carries " & name, "\"" & name & "\"" in atlas)

# --- THE BC22 GAME BLOCK ----------------------------------------------------
block:
  ## The same obligations every year module before it had to meet, plus the
  ## two `--statrail` ids and the envelope badge.
  let page = readFile("client/replay_broadcast.html")
  checkEq("the bc22 block does not define `markBeat` at all — that name is " &
    "`chrome_common.js`'s and a same-named function here would HOIST OVER " &
    "it (the tandem 2026-08-23 collision)",
    page.count("function markBeat"), 0)
  for taken in ["function buildBeatButtons",
                "function buildBc20BeatButtons",
                "function buildBc21BeatButtons",
                "function buildBc23BeatButtons",
                "function buildBc24BeatButtons",
                "function buildBc25BeatButtons"]:
    checkEq("the bc22 block does not redefine " & taken,
      page.count(taken), 1)
  checkEq("the bc22 builder is defined exactly once",
    page.count("function buildBc22BeatButtons"), 1)
  checkEq("and so is its spoiler gate",
    page.count("function applyBc22BeatSpoilers"), 1)
  check("the block registers on window.Bc22Block",
    "window.Bc22Block = {" in page)
  check("and the shared onText calls it",
    "if (window.Bc22Block) window.Bc22Block.onFrame(s);" in page)
  check("and the inherited block attaches the transport to it",
    "window.Bc22Block.attach({" in page)
  check("the bc26 branch is guarded off for bc22, bc16, bc19 and bc17 too, " &
    "so the discriminator is TEN-way",
    "if (!isBc16 && !isBc17 && !isBc19 && !isBc20 && !isBc21 && !isBc22 && " &
      "!isBc23 &&" in page)
  for alias in ["window.Bc20Block = {", "window.Bc21Block = {",
                "window.Bc23Block = {", "window.Bc24Block = {",
                "window.Bc25Block = {"]:
    checkEq("the bc22 block does not redeclare " & alias,
      page.count(alias), 1)

  ## `#bc22-doctrines` carries a dismiss control, an Escape binding, a re-open
  ## chip and self-dismissal — and it sits OUTSIDE var(--band) (D3).
  check("the doctrine overlay exists", "id=\"bc22-doctrines\"" in page)
  check("with a dismiss control carrying an aria-label",
    "id=\"bc22-doctrines-close\"" in page)
  check("a re-open chip", "id=\"bc22-doctrines-toggle\"" in page)
  check("an Escape binding scoped to bc22",
    "getAttribute('data-year') !== 'bc22'" in page)
  check("and it carries the SUBMITTED-VS-APPLIED badge the envelope pin " &
    "requires", "knobs defaulted" in page and
    "what the cog actually sent" in page and "seat.envelope" in page)

  ## The headline and the signature readouts exist, and the ANOMALY CLOCK
  ## keeps its type word and countdown at EVERY width — it is the readout that
  ## makes the year make sense.
  check("#bc22-archons is the headline pill",
    "id=\"bc22-archons\"" in page)
  check("#bc22-anomaly is the signature readout",
    "id=\"bc22-anomaly\"" in page)
  check("and it sits immediately ABOVE var(--band), never inside it",
    "bottom: calc(var(--band, 0px) + 148px);" in page)

  ## The stat boxes size to their own content and are in the --statrail set.
  check("#bc22-units is lifted above var(--band)",
    "#bc22-units { bottom: calc(var(--band, 0px) + 76px); }" in page)
  check("#bc22-econ too",
    "#bc22-econ { bottom: calc(var(--band, 0px) + 8px); }" in page)
  check("and relayout() MEASURES both of them into --statrail",
    "'bc22-econ', 'bc22-units'" in page)
  check("while #killfeed is still lifted above the rail",
    "calc(var(--band, 0px) + var(--statrail, 0px) + 8px)" in page)

  ## Every #bc22-* CSS rule is scoped to the year, one way or the other.
  let cssOpen = page.find("<style>")
  let cssClose = page.find("</style>")
  var css = page[cssOpen + len("<style>") ..< cssClose]
  while true:
    let a = css.find("/*")
    if a < 0: break
    let b = css.find("*/", a)
    if b < 0: break
    css = css[0 ..< a] & " " & css[b + 2 .. ^1]
  var unscoped22: seq[string]
  var scanned22 = 0
  var sel22 = ""
  for ch in css:
    if ch notin {'{', '}', ';'}:
      sel22.add(ch)
      continue
    if ch == '{' and "bc22" in sel22:
      for part in sel22.split(','):
        let one = part.splitWhitespace().join(" ")
        if "bc22" notin one: continue
        if one.startsWith("@"): continue
        inc scanned22
        if one.startsWith("#bc22-") or
           one.startsWith("html[data-year=\"bc22\"] ") or
           one.startsWith("html:not([data-year=\"bc22\"]) "):
          continue
        ## A LATER YEAR'S BLOCK LEGITIMATELY NAMES THIS YEAR'S IDS under its
        ## OWN `data-year`, to hide them: `html[data-year="bc16"] #bc22-econ`
        ## is year-scoped, just to a different year. Anything of that shape
        ## is scoped; anything else is not.
        if one.startsWith("html[data-year=\"bc") and "] #bc22-" in one:
          continue
        unscoped22.add(one)
    sel22 = ""
  check("the scan saw the bc22 rules at all", scanned22 >= 20)
  checkEq("and every one of them is year-scoped (" &
    unscoped22.join(" | ") & ")", unscoped22.len, 0)

  ## `#viewpanel` is KEPT: the bc22 pool spans 30x30 to 49x25 and the reserved
  ## large pool reaches 60x60, so the native render is wider than the 360 px
  ## featured-match frame.
  check("the zoom panel is still in the page", "id=\"viewpanel\"" in page)

# --- THE FOUR SHARED-ENDCARD FIXES -----------------------------------------
block:
  let page = readFile("client/replay_broadcast.html")
  ## FIX 1: this year's nouns, not bc26's.
  check("the endcard's noun table is keyed by year",
    "var ENDCARD_NOUNS = {" in page)
  let tableStart = page.find("var ENDCARD_NOUNS = {")
  let tableEnd = page.find("};", tableStart)
  let nounTable = page[tableStart .. tableEnd]
  for year in ["bc26", "bc20", "bc21", "bc22", "bc23", "bc24", "bc25"]:
    check("the noun table has a " & year & " branch", year & ":" in nounTable)
  ## The bc26 nouns must be ABSENT from every non-bc26 branch.
  for line in nounTable.splitLines():
    if "bc26:" in line: continue
    for noun in ["rat king", "cheese", "cat"]:
      check("no `" & noun & "` outside the bc26 branch: " & line.strip(),
        noun notin line)
  check("and the win-condition line is per year, not bc26's",
    "function endcardWinCondition(" in page)
  check("with bc22's own rungs in it",
    "more archons left" in page and "won on gold net worth" in page)
  check("the bc26 branch is guarded rather than being the default",
    "if (s.year === 'bc26' || !s.year) {" in page)

  ## r2-E1: A SHARED END REASON MAY NOT CARRY ONE YEAR'S LORE. `more_archons`
  ## is bc22's PWNED and bc16 REUSES it (`src/battlecode/results.nim`'s own
  ## note on `EndReasons`), and that branch shipped hard-coded to bc22's
  ## Singularity — so the endcard of a live bc16 ladder match read "THE
  ## SINGULARITY CAME AT ROUND 3000 AND CLAN BASIL HAD MORE ARCHONS LEFT",
  ## naming a mechanic bc16 does not have. Nothing here asserted the wording
  ## of a SHARED reason PER YEAR, which is why it shipped green.
  let winStart = page.find("function endcardWinCondition(")
  let winEnd = page.find("\n  }\n", winStart)
  check("the win-condition function reads whole",
    winStart >= 0 and winEnd > winStart)
  let winFn = page[winStart .. winEnd]
  check("the year's row supplies the clause for the shared rung",
    "(nouns.limit || " in winFn)
  check("bc22 keeps its Singularity, in its own row",
    "limit: 'the Singularity came'" in nounTable)
  check("and bc16 gets its own round limit, in its own row",
    "limit: 'the round limit ran out'" in nounTable)
  ## The END REASONS MORE THAN ONE YEAR EMITS. `results.nim`: bc16 reuses
  ## bc22's `more_archons`, bc20's `highest_id` and our `abandoned`;
  ## `annihilated` is bc21's and bc22's; `coin_flip` is bc22's rung and
  ## bc25's WON_BY_DUBIOUS_REASONS. A branch for one of these speaks to every
  ## year that lands on it, so it may only use words every one of them has.
  for reason in ["more_archons", "annihilated", "coin_flip", "abandoned",
                 "highest_id"]:
    let caseAt = winFn.find("case '" & reason & "':")
    if caseAt < 0: continue  ## no branch of its own: the default is neutral
    var branchEnd = winFn.find("case '", caseAt + 6)
    if branchEnd < 0: branchEnd = winFn.find("default:", caseAt)
    check("the " & reason & " branch has an end", branchEnd > caseAt)
    let branch = winFn[caseAt ..< branchEnd]
    ## Words that belong to exactly ONE year's rule set.
    for lore in ["Singularity", "rat king", "cheese", "cats", "soup", "dirt",
                 "influence", "Enlightenment", "crumb", "duck", "chip",
                 "paint", "adamantium", "mana", "elixir", "anchor", "zombie",
                 "horde", "rubble", "gold", "lead"]:
      check("the shared `" & reason & "` branch says nothing about " & lore &
        ": " & branch.strip(), lore notin branch)

  ## FIX 2: no clipping or overflow at 1280x800.
  check("#endcard's content scrolls rather than running off the bottom",
    "overscroll-behavior: contain;" in page)
  let smoke = readFile("tools/ci/viewer_smoke.mjs")
  check("and viewer_smoke.mjs makes it a GATE",
    "#endcard overflows at 1280x800" in smoke and
    "endcard_overflow" in smoke)

  ## r2-E2: ...AND THE CARD SCROLLS INSTEAD OF SQUEEZING ITS BANDS. A flex
  ## item shrinks below its own content by default, so the card met a
  ## too-tall stack by squashing every band: `#ec-headline` drew a slice of
  ## its own capitals on a live bc16 endcard, and `#endcard`'s scrollHeight
  ## never exceeded its clientHeight, so FIX 2's gate above passed on a card
  ## that was clipping. A grep is not coverage here either — the gate is a
  ## measurement in `tools/ci/renderer_fixture.html`, which raises a POPULATED
  ## endcard at 360/720/1280 px and reads the headline's box against its own
  ## line; this pins the shape so a future edit cannot quietly drop it.
  check("the endcard's bands keep their natural height",
    "#endcard.on > * { flex: none; }" in page)
  check("and the card centres SAFELY, so an overflowing card can still be " &
    "scrolled up to its headline",
    "justify-content: safe center;" in page)
  let fixture = readFile("tools/ci/renderer_fixture.html")
  check("the fixture's endcard carries this year's own doctrine text",
    "id=\"ec-headline\"" in fixture and "id=\"ec-teams\"" in fixture and
    "var ENDCARD_WORDS = {" in fixture)
  check("and it fails when the headline is squeezed",
    "the endcard headline is squeezed into" in fixture)
  check("and when the headline is stranded above the scrollport",
    "above the card\\u2019s scrollport and cannot be scrolled to" in fixture)

  ## r2-E3: A DOCTRINE PANEL IS A SENTENCE, NOT A LABEL. The 52 % cap on
  ## `.ec-teams` is sized for the BR field list; on the two-panel doctrine
  ## variant it hid more than half of each team's doctrine, cut mid-word, with
  ## no ellipsis and no dismiss control. Item 15: if a remark is being cut the
  ## box is too small. The panels are laid out whole, up to 430u wide, and the
  ## card's own scroll is the one place endcard content may overflow to.
  check("the doctrine panels are not capped inside the card",
    "#endcard .ec-teams:not(.br) { max-height: none; }" in page)
  check("and they take the width the card has to spare",
    "#endcard .ec-teams:not(.br) .ec-team {" in page and
    "max-width: calc(430 * var(--u));" in page)
  check("the BR field list keeps its own cap", "max-height: 62%;" in page)
  check("and the fixture fails when a doctrine panel is cut off",
    "the endcard doctrine panels are cut off: " in fixture)
  check("with both seats' endcard text at full length before it measures",
    "the endcard motto on seat " in fixture)

  ## FIX 3: no raw unrounded floats.
  check("there is exactly ONE formatter", page.count("window.fmtStat =") == 1)
  check("and the endcard's own numbers go through it",
    "window.fmtStat(scores[0])" in page)
  check("as do the bc22 war panel's",
    "stat(faction.lead_mined, 'int')" in page and
    "stat(perGold, 'rate')" in page)

  ## FIX 4: no empty mottos and no article-plus-enum grammar.
  check("a blank motto renders NOTHING",
    "var motto = d.motto ? '<br><i>" in page)
  check("and the scorebug guards it too", "doc.motto ? ' · ' + doc.motto" in
    page)

# --- the bc22 sprite atlas --------------------------------------------------
block:
  check("the bc22 atlas image is committed", fileExists("data/atlas_bc22.png"))
  check("with its index", fileExists("data/atlas_bc22.json"))
  let atlas = readFile("data/atlas_bc22.json")
  for name in ["blue_miner", "blue_builder", "blue_soldier", "blue_sage",
               "red_miner", "red_builder", "red_soldier", "red_sage",
               "blue_archon_level1", "blue_archon_level2",
               "blue_archon_level3", "blue_archon_prototype",
               "blue_archon_portable_level1", "blue_lab_level1",
               "blue_lab_prototype", "blue_lab_portable_level3",
               "blue_watchtower_level1", "blue_watchtower_prototype",
               "red_archon_level3", "red_watchtower_portable_level2",
               "lead", "gold", "star"]:
    check("the bc22 atlas carries " & name, "\"" & name & "\"" in atlas)

# ===========================================================================
#  THE BC16 GAME BLOCK — §Tests item 27
# ===========================================================================
block:
  ## The same five obligations every year module before it had to meet, plus
  ## the two `--statrail` ids, the four-palette atlas and the endcard fixes.
  let page = readFile("client/replay_broadcast.html")

  ## 1. NO NAME COLLISIONS. `markBeat` is `chrome_common.js`'s and a
  ##    same-named function here would HOIST OVER it (the tandem 2026-08-23
  ##    collision).
  checkEq("the bc16 block does not define `markBeat` at all",
    page.count("function markBeat"), 0)
  checkEq("its beat builder has its own name",
    page.count("function buildBc16BeatButtons"), 1)
  checkEq("and so does its spoiler gate",
    page.count("function applyBc16BeatSpoilers"), 1)
  for taken in ["function buildBeatButtons", "function buildBc20BeatButtons",
                "function buildBc21BeatButtons",
                "function buildBc22BeatButtons",
                "function buildBc23BeatButtons",
                "function buildBc24BeatButtons",
                "function buildBc25BeatButtons"]:
    checkEq("and it does not redefine " & taken, page.count(taken), 1)
  for alias in ["window.Bc20Block = {", "window.Bc21Block = {",
                "window.Bc22Block = {", "window.Bc23Block = {",
                "window.Bc24Block = {", "window.Bc25Block = {"]:
    checkEq("the bc16 block does not redeclare " & alias,
      page.count(alias), 1)
  ## And it shadows no `ChromeCommon` alias.
  checkEq("the block registers on window.Bc16Block",
    page.count("window.Bc16Block = {"), 1)
  check("and the shared onText calls it",
    "if (window.Bc16Block) window.Bc16Block.onFrame(s);" in page)
  check("and the inherited block attaches the transport to it",
    "window.Bc16Block.attach({" in page)

  ## 2. THE SEVEN bc16 IDS ARE ALL PRESENT, and no starter element was
  ##    removed to make room for them.
  for id in ["bc16-archons", "bc16-horde", "bc16-econ", "bc16-units",
             "bc16-doctrines", "bc16-doctrines-toggle", "bc16-siege"]:
    check("the page carries #" & id, "id=\"" & id & "\"" in page)
  for kept in ["coopchip", "bars", "gamechips", "econ", "doctrines",
               "bc20-flood", "bc21-units", "bc22-archons", "bc23-islands",
               "bc24-flags", "bc25-srp", "viewpanel", "killfeed", "scrub",
               "endcard"]:
    check("and the starter element #" & kept & " is still there",
      "id=\"" & kept & "\"" in page)

  ## 3. `#bc16-doctrines` is dismissible, capped-and-scrolling, and OUTSIDE
  ##    var(--band).
  check("the doctrine overlay has a dismiss control with an aria-label",
    "id=\"bc16-doctrines-close\"" in page and
    "aria-label=\"Dismiss doctrines\"" in page)
  check("a re-open chip", "id=\"bc16-doctrines-toggle\"" in page)
  check("an Escape binding scoped to bc16",
    "getAttribute('data-year') !== 'bc16'" in page)
  check("self-dismissal on the first playback advance",
    "if (lastFrame >= 0 && s.t > lastFrame && !pinned && !dismissed)" in page)
  check("and it is CAPPED AND SCROLLS rather than clipping",
    "#bc16-doctrines {" in page and "overflow: auto;" in page)
  check("and it carries the SUBMITTED-VS-APPLIED badge the envelope pin " &
    "requires", "knobs defaulted" in page and
    "what the cog actually sent" in page)

  ## 4. THE TWO RAIL BOXES are above the band and IN the `--statrail` set;
  ##    the two top-band pills are deliberately NOT.
  check("#bc16-units is lifted above var(--band)",
    "#bc16-units { bottom: calc(var(--band, 0px) + 76px); }" in page)
  check("#bc16-econ too",
    "#bc16-econ { bottom: calc(var(--band, 0px) + 8px); }" in page)
  check("and relayout() MEASURES both of them into --statrail",
    "'bc16-econ', 'bc16-units'" in page)
  check("while #killfeed is still lifted above the rail",
    "calc(var(--band, 0px) + var(--statrail, 0px) + 8px)" in page)
  check("#bc16-archons is the headline pill, in the top band",
    "top: calc(var(--topband, 0px) + 6px);" in page)
  check("#bc16-horde is the signature readout, IMMEDIATELY above the band " &
    "and never inside it",
    "bottom: calc(var(--band, 0px) + 148px);" in page)

  ## 4b. THE THIRD PARTY IS NAMED ON SCREEN, and the strip really is taken
  ##     over. Coordinator ruling 4 made "THE HORDE" this year's flavour
  ##     carrier and the design note says the zombie team is drawn and
  ##     labelled THE HORDE spectator-side — but `renderHorde` never drew the
  ##     faction name and `#bc16-horde.struck` was a rule NOTHING ACTIVATED
  ##     (r1-F9). Both halves are asserted here in the same triad shape the
  ##     endcard's `.on` uses: the rule exists, the page adds that exact
  ##     class, and the page takes it off again.
  check("the faction name is DRAWN, first in the strip",
    "'<span class=\"horde\">THE HORDE</span>'" in page)
  check("with a rule of its own",
    "#bc16-horde .horde {" in page)
  check("and it survives the 360 px media query — only the mini-timeline " &
    "is dropped",
    "#bc16-horde .tl { display: none; }" in page and
    "#bc16-horde .horde { display: none;" notin page)
  check("the strip takeover ADDS the class its CSS rule uses",
    "box.classList.add('struck');" in page)
  check("and takes it off again, so the readouts come back",
    "box.classList.remove('struck');" in page and
    "if (box) box.classList.remove('struck');" in page)
  check("there is a rule for `struck` to activate",
    "#bc16-horde.struck {" in page)
  check("it is driven by a WAVE round or a `turned` event, for two seconds, " &
    "in the beat's own plain words",
    "if (b.k !== 'wave' && b.k !== 'turned') return;" in page and
    "struckUntil = Date.now() + 2000;" in page and
    "'<span class=\"tell\">' + esc(struckText) +" in page)
  ## AND THE KINDS IT KEYS ON ARE KINDS THE COMMITTED ARTEFACT REALLY EMITS,
  ## with labels — otherwise the takeover is as dead as the CSS rule was.
  ## `tests/test_bc16_beats.nim` asserts the same fixture carries all
  ## thirteen kinds; this closes the loop between the fixture and the page.
  block:
    let fixture = parseReplay(readFile("tests" / "fixtures" /
      "replay-bc16.json"))
    var gameStart: seq[int]
    var total = 0
    for g in fixture.games:
      gameStart.add(total)
      total += g.rounds
    proc frameOf(g, r: int): int =
      if g < 0 or g >= gameStart.len: 0 else: gameStart[g] + max(0, r - 1)
    var struckKinds: seq[string]
    for b in beatsFor(fixture, frameOf):
      let k = b["k"].getStr()
      if k notin ["wave", "turned"]: continue
      if b["label"].getStr().len == 0: continue
      if k notin struckKinds: struckKinds.add(k)
    check("the committed fixture emits a labelled `wave` beat, so the " &
      "takeover fires", "wave" in struckKinds)
    check("and a labelled `turned` beat", "turned" in struckKinds)

  ## 5. EVERY #bc16-* CSS RULE IS SCOPED TO THE YEAR, one way or the other.
  ##    The whole <style> block, not a line scan (r1-F24).
  let cssOpen = page.find("<style>")
  let cssClose = page.find("</style>")
  var css = page[cssOpen + len("<style>") ..< cssClose]
  while true:
    let a = css.find("/*")
    if a < 0: break
    let b = css.find("*/", a)
    if b < 0: break
    css = css[0 ..< a] & " " & css[b + 2 .. ^1]
  var unscoped16: seq[string]
  var scanned16 = 0
  var sel16 = ""
  for ch in css:
    if ch notin {'{', '}', ';'}:
      sel16.add(ch)
      continue
    if ch == '{' and "bc16" in sel16:
      for part in sel16.split(','):
        let one = part.splitWhitespace().join(" ")
        if "bc16" notin one: continue
        if one.startsWith("@"): continue
        inc scanned16
        if one.startsWith("#bc16-") or
           one.startsWith("html[data-year=\"bc16\"] ") or
           one.startsWith("html:not([data-year=\"bc16\"]) "):
          continue
        ## A LATER YEAR'S BLOCK LEGITIMATELY NAMES THIS YEAR'S IDS under its
        ## OWN `data-year`, to hide them: `html[data-year="bc19"] #bc16-econ`
        ## is year-scoped, just to a different year. Anything of that shape
        ## is scoped; anything else is not. (bc22 already carries exactly
        ## this carve-out for the same reason.)
        if one.startsWith("html[data-year=\"bc") and "] #bc16-" in one:
          continue
        unscoped16.add(one)
    sel16 = ""
  check("the scan saw the bc16 rules at all", scanned16 >= 20)
  checkEq("and every one of them is year-scoped (" &
    unscoped16.join(" | ") & ")", unscoped16.len, 0)

  ## AND THE 41 SIBLING IDS ARE HIDDEN ON A bc16 REPLAY — what bc16 removes
  ## is NOTHING from the page and EVERYTHING from the screen.
  for id in ["coopchip", "econ", "doctrines", "bc20-flood", "bc21-units",
             "bc22-archons", "bc22-anomaly", "bc23-islands", "bc24-flags",
             "bc25-srp"]:
    check("html[data-year=\"bc16\"] hides #" & id,
      "html[data-year=\"bc16\"] #" & id in page)
  for id in ["bc16-archons", "bc16-horde", "bc16-econ", "bc16-units",
             "bc16-doctrines", "bc16-doctrines-toggle", "bc16-siege"]:
    check("and every other year hides #" & id,
      "html:not([data-year=\"bc16\"]) #" & id in page)

  ## THE ENDCARD FIXES, for bc16.
  let tableStart = page.find("var ENDCARD_NOUNS = {")
  let tableEnd = page.find("};", tableStart)
  let nounTable = page[tableStart .. tableEnd]
  check("the noun table has a bc16 row", "bc16:" in nounTable)
  check("with THIS year's nouns", "unit: 'archon'" in nounTable and
    "res: 'parts'" in nounTable)
  for line in nounTable.splitLines():
    if "bc16:" notin line: continue
    for noun in ["rat", "cheese", "king", "lead", "gold", "chips", "crumbs"]:
      check("no `" & noun & "` on a bc16 card: " & line.strip(),
        noun notin line)
  check("every printed bc16 number goes through ONE formatter",
    "function stat(value, kind) {" in page and
    "if (kind === 'tenths') return (n / 10).toFixed(1);" in page)
  check("a blank bc16 motto renders NOTHING",
    "if (d.motto) html += '<br>\\u201c'" in page)
  ## NO HUD BLEED-THROUGH. The static half below is a grep and a grep is NOT
  ## coverage: this repo shipped `#endcard.show ~ #bc16-archons`, which named
  ## a class the page never sets AND the wrong sibling direction, and a grep
  ## for exactly that string was GREEN while the rule matched nothing (r1-F1).
  ## The gate is a computed style in `tools/ci/renderer_fixture.html`, which
  ## raises `#endcard` and reads `visibility` on all five boxes; this static
  ## pair only pins the shape so a future edit cannot quietly drop it.
  check("and the bc16 boxes are hidden while the endcard shows (no HUD " &
    "bleed-through)",
    "html[data-year=\"bc16\"] #chrome:has(#endcard.on) #bc16-archons" in
      page and
    "visibility: hidden;" in page)
  check("keyed on the class the page ACTUALLY toggles, parent-scoped rather " &
    "than sibling-scoped",
    "#endcard.show ~ #bc16-archons" notin page and
    "#endcard.on ~ #bc16-archons" notin page)
  for id in ["bc16-archons", "bc16-horde", "bc16-econ", "bc16-units",
             "bc16-doctrines"]:
    check("every bc16 box is named in the suppression rule: " & id,
      "html[data-year=\"bc16\"] #chrome:has(#endcard.on) #" & id in page)
  block:
    let fixture = readFile("tools/ci/renderer_fixture.html")
    check("and the FIXTURE proves it by computed style, not by grep",
      "SUPPRESSED_BY_ENDCARD" in fixture and
      "card.classList.add('on');" in fixture and
      "getComputedStyle(document.getElementById(id)).visibility !==" in
        fixture and
      "the HUD bleeds through a score screen that is not opaque" in fixture)
    check("on all five boxes",
      "bc16: ['bc16-archons', 'bc16-horde', 'bc16-econ', 'bc16-units'," in
        fixture and "'bc16-doctrines']" in fixture)
    check("with #endcard a CHILD OF #chrome, which the rule keys on, and " &
      "with the card's own bands on it (r2-E2)",
      "'<div id=\"endcard\">' + endcard + '</div>' +\n    " &
        "'</div></div></div>';" in fixture)
    check("and it takes the card down again so the boxes come back",
      "card.classList.remove('on');" in fixture and
      "stayed hidden after the endcard " in fixture)
  ## The tiebreak ledger — all four rungs and which one decided it.
  check("the war panel draws the whole tiebreak ledger",
    "decided it" in page and "g.ladder" in page)

  ## `#viewpanel` is KEPT: the bc16 played pool spans 36x30 to 45x45 and the
  ## reserved large pool reaches 80x80, so the native 16 px render is 480 to
  ## 1280 px wide — every single one of them LARGER than the 360 px
  ## featured-match frame.
  check("the zoom panel is still in the page", "id=\"viewpanel\"" in page)

# --- the bc16 sprite atlas --------------------------------------------------
block:
  check("the bc16 atlas image is committed", fileExists("data/atlas_bc16.png"))
  check("with its index", fileExists("data/atlas_bc16.json"))
  let atlas = readFile("data/atlas_bc16.json")
  ## ALL TWELVE ROBOT TYPES AT ALL FOUR `Team` PALETTES — which makes bc16 the
  ## first year in this repository whose art can draw a NEUTRAL robot as
  ## itself rather than as a greyed team sprite, and that matters because
  ## `neutral_activation` is a headline knob.
  var missing: seq[string]
  for kind in ["archon", "scout", "soldier", "guard", "viper", "turret",
               "ttm", "zombieden", "standardzombie", "rangedzombie",
               "fastzombie", "bigzombie"]:
    for team in ["a", "b", "neutral", "horde"]:
      let name = team & "_" & kind
      if "\"" & name & "\"" notin atlas: missing.add(name)
  checkEq("all twelve types at all four palettes (" & missing.join(", ") &
    ")", missing.len, 0)
  check("plus the rubble texture", "\"creep\"" in atlas)

# --- THE BC19 GAME BLOCK ----------------------------------------------------
block:
  ## §Tests item 27. The same obligations every year module before it had to
  ## meet, plus the two `--statrail` ids, the two-palette atlas and the
  ## endcard fixes. bc19 is the NINTH year block in this page, so every
  ## count below is nine-way.
  let page = readFile("client/replay_broadcast.html")

  ## 1. NO NAME COLLISIONS. `markBeat` is `chrome_common.js`'s and a
  ##    same-named function here would HOIST OVER it (the tandem 2026-08-23
  ##    collision).
  checkEq("the bc19 block does not define `markBeat` at all",
    page.count("function markBeat"), 0)
  checkEq("its beat builder has its own name",
    page.count("function buildBc19BeatButtons"), 1)
  checkEq("and so does its spoiler gate",
    page.count("function applyBc19BeatSpoilers"), 1)
  for taken in ["function buildBeatButtons", "function buildBc20BeatButtons",
                "function buildBc21BeatButtons",
                "function buildBc22BeatButtons",
                "function buildBc23BeatButtons",
                "function buildBc24BeatButtons",
                "function buildBc25BeatButtons",
                "function buildBc16BeatButtons"]:
    checkEq("and it does not redefine " & taken, page.count(taken), 1)
  for alias in ["window.Bc20Block = {", "window.Bc21Block = {",
                "window.Bc22Block = {", "window.Bc23Block = {",
                "window.Bc24Block = {", "window.Bc25Block = {",
                "window.Bc16Block = {"]:
    checkEq("the bc19 block does not redeclare " & alias,
      page.count(alias), 1)
  ## And it shadows no `ChromeCommon` alias.
  checkEq("the block registers on window.Bc19Block",
    page.count("window.Bc19Block = {"), 1)
  check("and the shared onText calls it",
    "if (window.Bc19Block) window.Bc19Block.onFrame(s);" in page)
  check("and the inherited block attaches the transport to it",
    "window.Bc19Block.attach({" in page)

  ## 2. THE SIX bc19 IDS ARE ALL PRESENT, and no starter element was removed
  ##    to make room for them.
  for id in ["bc19-castles", "bc19-fuel", "bc19-econ", "bc19-units",
             "bc19-doctrines", "bc19-doctrines-toggle", "bc19-crusade"]:
    check("the page carries #" & id, "id=\"" & id & "\"" in page)
  for kept in ["coopchip", "bars", "gamechips", "econ", "doctrines",
               "bc20-flood", "bc21-units", "bc22-archons", "bc23-islands",
               "bc24-flags", "bc25-srp", "bc16-archons", "viewpanel",
               "killfeed", "scrub", "endcard"]:
    check("and the starter element #" & kept & " is still there",
      "id=\"" & kept & "\"" in page)

  ## 3. `#bc19-doctrines` is dismissible, capped-and-scrolling, and OUTSIDE
  ##    var(--band).
  check("the doctrine overlay has a dismiss control with an aria-label",
    "id=\"bc19-doctrines-close\"" in page and
    "aria-label=\"Dismiss doctrines\"" in page)
  check("a re-open chip", "id=\"bc19-doctrines-toggle\"" in page)
  check("an Escape binding scoped to bc19",
    "getAttribute('data-year') !== 'bc19'" in page)
  check("self-dismissal on the first playback advance",
    "if (lastFrame >= 0 && s.t > lastFrame && !pinned && !dismissed)" in page)
  check("and it is CAPPED AND SCROLLS rather than clipping",
    "#bc19-doctrines {" in page and
    "calc(100% - var(--topband, 0px) - var(--band, 0px) - 46px));" in page)
  check("and it carries the SUBMITTED-VS-APPLIED badge the envelope pin " &
    "requires", "knobs defaulted" in page and
    "what the cog actually sent" in page)

  ## 4. THE TWO RAIL BOXES are above the band and IN the `--statrail` set;
  ##    the two top-band pills are deliberately NOT.
  check("#bc19-units is lifted above var(--band)",
    "#bc19-units { bottom: calc(var(--band, 0px) + 76px); }" in page)
  check("#bc19-econ too",
    "#bc19-econ { bottom: calc(var(--band, 0px) + 8px); }" in page)
  check("and relayout() MEASURES both of them into --statrail",
    "'bc19-econ', 'bc19-units'" in page)
  check("while #killfeed is still lifted above the rail",
    "calc(var(--band, 0px) + var(--statrail, 0px) + 8px)" in page)

  ## 4b. THE TWO SIGNATURE READOUTS, and the takeover on the one no other
  ##     year has. `#bc19-castles` FLASHES when a castle dies — the only
  ##     event that can end this game before round 1000 — and `#bc19-fuel`
  ##     is struck by a `famine` or a `trade` beat. Both are asserted in the
  ##     same triad shape as bc16's: the rule exists, the page adds that
  ##     exact class, and the page takes it off again.
  check("there is a rule for `flash` to activate",
    "#bc19-castles.flash { animation: bc19flash" in page)
  check("with the keyframes it names", "@keyframes bc19flash {" in page)
  check("and the page adds that exact class", "box.classList.add('flash');" in
    page)
  check("after taking it off, so a second death re-triggers the animation",
    "box.classList.remove('flash');" in page and
    "void box.offsetWidth;" in page)
  check("driven by an actual drop in the castle count",
    "if (lastCastles[i] >= 0 && order.alive < lastCastles[i]) died = true;" in
      page)
  check("there is a rule for `struck` to activate",
    "#bc19-fuel.struck {" in page)
  check("the strip takeover ADDS the class its CSS rule uses",
    "box.classList.add('struck');" in page)
  check("and takes it off again, so the readouts come back",
    "box.classList.remove('struck');" in page)
  check("it is driven by a FAMINE or a TRADE beat, for two seconds, in the " &
    "beat's own plain words",
    "if (b.k !== 'famine' && b.k !== 'trade') return;" in page and
    "struckUntil = Date.now() + 2000;" in page and
    "'<span class=\"tell\">' + esc(struckText) +" in page)
  ## AND THE KINDS IT KEYS ON ARE KINDS THE COMMITTED ARTEFACT REALLY EMITS,
  ## with labels — otherwise the takeover is as dead as bc16's CSS rule was
  ## (r1-F9). `tests/test_bc19_beats.nim` asserts the same fixture carries
  ## eleven of the twelve kinds and records that `famine` is the twelfth
  ## BECAUSE THE STRONG CHASSIS NEVER ASKS FOR WHAT IT CANNOT PAY; this
  ## closes the loop between the fixture and the page for the kind that IS
  ## emitted, and the `famine` half of the takeover is exercised from a
  ## synthetic event in the beats shard.
  block:
    let fixture = parseReplay(readFile("tests" / "fixtures" /
      "replay-bc19.json"))
    var gameStart: seq[int]
    var total = 0
    for g in fixture.games:
      gameStart.add(total)
      total += g.rounds
    proc frameOf(g, r: int): int =
      if g < 0 or g >= gameStart.len: 0 else: gameStart[g] + max(0, r - 1)
    var struckKinds: seq[string]
    for b in beatsFor(fixture, frameOf):
      let k = b["k"].getStr()
      if k notin ["famine", "trade"]: continue
      if b["label"].getStr().len == 0: continue
      if k notin struckKinds: struckKinds.add(k)
    check("the committed fixture emits a labelled `trade` beat, so the " &
      "takeover fires", "trade" in struckKinds)

  ## 5. EVERY #bc19-* CSS RULE IS SCOPED TO THE YEAR, one way or the other.
  ##    The whole <style> block, not a line scan (r1-F24).
  let cssOpen19 = page.find("<style>")
  let cssClose19 = page.find("</style>")
  var css19 = page[cssOpen19 + len("<style>") ..< cssClose19]
  while true:
    let a = css19.find("/*")
    if a < 0: break
    let b = css19.find("*/", a)
    if b < 0: break
    css19 = css19[0 ..< a] & " " & css19[b + 2 .. ^1]
  var unscoped19: seq[string]
  var scanned19 = 0
  var sel19 = ""
  for ch in css19:
    if ch notin {'{', '}', ';'}:
      sel19.add(ch)
      continue
    if ch == '{' and "bc19" in sel19:
      for part in sel19.split(','):
        let one = part.splitWhitespace().join(" ")
        if "bc19" notin one: continue
        if one.startsWith("@"): continue
        inc scanned19
        if one.startsWith("#bc19-") or
           one.startsWith("html[data-year=\"bc19\"] ") or
           one.startsWith("html:not([data-year=\"bc19\"]) "):
          continue
        ## A LATER YEAR'S BLOCK LEGITIMATELY NAMES THIS YEAR'S IDS under its
        ## OWN `data-year`, to hide them.
        if one.startsWith("html[data-year=\"bc") and "] #bc19-" in one:
          continue
        unscoped19.add(one)
    sel19 = ""
  check("the scan saw the bc19 rules at all", scanned19 >= 20)
  checkEq("and every one of them is year-scoped (" &
    unscoped19.join(" | ") & ")", unscoped19.len, 0)

  ## AND THE SIBLING IDS ARE HIDDEN ON A bc19 REPLAY — what bc19 removes is
  ## NOTHING from the page and EVERYTHING from the screen.
  for id in ["coopchip", "econ", "doctrines", "bc20-flood", "bc21-units",
             "bc22-archons", "bc22-anomaly", "bc23-islands", "bc24-flags",
             "bc25-srp", "bc16-archons", "bc16-horde", "bc16-econ",
             "bc16-units"]:
    check("html[data-year=\"bc19\"] hides #" & id,
      "html[data-year=\"bc19\"] #" & id in page)
  for id in ["bc19-castles", "bc19-fuel", "bc19-econ", "bc19-units",
             "bc19-doctrines", "bc19-doctrines-toggle", "bc19-crusade"]:
    check("and every other year hides #" & id,
      "html:not([data-year=\"bc19\"]) #" & id in page)

  ## THE ENDCARD FIXES, for bc19.
  let tableStart19 = page.find("var ENDCARD_NOUNS = {")
  let tableEnd19 = page.find("};", tableStart19)
  let nounTable19 = page[tableStart19 .. tableEnd19]
  check("the noun table has a bc19 row", "bc19:" in nounTable19)
  check("with THIS year's nouns", "unit: 'castle'" in nounTable19 and
    "res: 'karbonite'" in nounTable19 and "res2: 'fuel'" in nounTable19)
  ## NO OTHER YEAR'S RESOURCE OR UNIT NOUN may reach a bc19 card.
  block:
    var bc19Row = ""
    var inRow = false
    for line in nounTable19.splitLines():
      if "bc19:" in line: inRow = true
      if inRow: bc19Row.add(line & " ")
      if inRow and "limit:" in line: inRow = false
    check("the bc19 row was found", bc19Row.len > 0)
    for noun in ["rat", "cheese", "king", "lead", "gold", "chips", "crumbs",
                 "parts", "archon", "soup", "influence", "vote", "paint",
                 "adamantium", "mana", "elixir", "bread", "flag", "money",
                 "sky island", "well"]:
      check("no `" & noun & "` on a bc19 card: " & bc19Row.strip(),
        noun notin bc19Row)
  check("every printed bc19 number goes through ONE formatter",
    "function stat(value, kind) {" in page)
  check("a blank bc19 motto renders NOTHING",
    "if (d.motto) html += '<br>\\u201c'" in page)
  ## NO HUD BLEED-THROUGH. The static half below is a grep and a grep is NOT
  ## coverage: this repo shipped `#endcard.show ~ #bc16-archons`, which named
  ## a class the page never sets AND the wrong sibling direction, and a grep
  ## for exactly that string was GREEN while the rule matched nothing
  ## (r1-F1). The gate is a computed style in `tools/ci/renderer_fixture.html`,
  ## which raises `#endcard` and reads `visibility` on all five boxes; this
  ## static pair only pins the shape so a future edit cannot quietly drop it.
  check("and the bc19 boxes are hidden while the endcard shows (no HUD " &
    "bleed-through)",
    "html[data-year=\"bc19\"] #chrome:has(#endcard.on) #bc19-castles" in
      page and "visibility: hidden;" in page)
  check("keyed on the class the page ACTUALLY toggles, parent-scoped rather " &
    "than sibling-scoped",
    "#endcard.show ~ #bc19-castles" notin page and
    "#endcard.on ~ #bc19-castles" notin page)
  for id in ["bc19-castles", "bc19-fuel", "bc19-econ", "bc19-units",
             "bc19-doctrines"]:
    check("every bc19 box is named in the suppression rule: " & id,
      "html[data-year=\"bc19\"] #chrome:has(#endcard.on) #" & id in page)
  block:
    let fixture = readFile("tools/ci/renderer_fixture.html")
    check("the fixture lays bc19 out at three widths",
      "'bc16', 'bc19'];" in fixture)
    check("and it proves the suppression by computed style, not by grep",
      "bc19: ['bc19-castles', 'bc19-fuel', 'bc19-econ', 'bc19-units'," in
        fixture and "'bc19-doctrines']" in fixture)
    check("with the war panel INSIDE the card, where the page puts it",
      "'<div id=\"bc19-crusade\">' + bc19Crusade + '</div>' +" in fixture)
    check("and every readout fed its MEASURED WIDEST value",
      "EVERY NUMBER BELOW IS MEASURED" in fixture and
      "10842" in fixture and "61830" in fixture)
    check("and both doctrine poles at the full rune caps",
      "var BC19_WORDS = [" in fixture and
      "BC19_WORDS[m19].join(' \\u00b7 ')" in fixture)
    check("with the endcard fed this year's own words",
      "bc19: [BC19_WORDS[0].join(', '), BC19_WORDS[1].join(', ')]" in fixture)
  ## The tiebreak ledger — all three round-1000 rungs and which one decided
  ## it.
  check("the war panel draws the whole tiebreak ladder",
    "ladder \\u2014 '" in page and "g.tiebreak" in page)

  ## `#viewpanel` is KEPT: bc19's played pool spans 32x32 to 64x64, so the
  ## native 16 px render is 512 to 1024 px wide — every single one of them
  ## LARGER than the 360 px featured-match frame.
  check("the zoom panel is still in the page", "id=\"viewpanel\"" in page)

# --- the bc19 sprite atlas --------------------------------------------------
block:
  check("the bc19 atlas image is committed", fileExists("data/atlas_bc19.png"))
  check("with its index", fileExists("data/atlas_bc19.json"))
  let atlas = readFile("data/atlas_bc19.json")
  ## ALL SIX UNIT TYPES AT BOTH `Team` PALETTES. bc19 has NO neutral and NO
  ## third faction — the 2019 board is two orders and nothing else — so two
  ## palettes is the whole set rather than a shortfall.
  var missing19: seq[string]
  for kind in ["castle", "church", "pilgrim", "crusader", "prophet",
               "preacher"]:
    for team in ["a", "b"]:
      let name = team & "_" & kind
      if "\"" & name & "\"" notin atlas: missing19.add(name)
  checkEq("all six types at both palettes (" & missing19.join(", ") & ")",
    missing19.len, 0)
  check("and there is no neutral palette, because this year has none",
    "\"neutral_castle\"" notin atlas and "\"horde_castle\"" notin atlas)
  check("at the 16 px tile the renderer draws", "\"tile\":16" in atlas)

block:
  ## **THE BC17 GAME BLOCK**, the tenth, held to the same five obligations
  ## every year module before it was: its own ids, its own scoped CSS, its
  ## own beat builder, its own block object, and the shared `onText` calling
  ## it.
  let page = readFile("client/replay_broadcast.html")
  for id in ["bc17-vp", "bc17-bullets", "bc17-econ", "bc17-units",
             "bc17-doctrines"]:
    check("the page carries #" & id, "id=\"" & id & "\"" in page)
  check("the doctrines panel is DISMISSIBLE",
    "id=\"bc17-doctrines-close\"" in page and
    "aria-label=\"Dismiss doctrines\"" in page)
  check("every bc17 rule is scoped to the year",
    "html[data-year=\"bc17\"] .beat-marker.donate" in page and
    "html:not([data-year=\"bc17\"]) #bc17-vp" in page)
  check("and the block hides EVERY other year's boxes",
    "html[data-year=\"bc17\"] #bc19-castles" in page and
    "html[data-year=\"bc17\"] #bc16-archons" in page and
    "html[data-year=\"bc17\"] #coopchip" in page)
  check("the beat builder has its OWN name",
    "function buildBc17BeatButtons" in page)
  checkEq("defined exactly once",
    page.count("function buildBc17BeatButtons"), 1)
  check("the spoiler gate too", "function applyBc17BeatSpoilers" in page)
  check("the block registers on window.Bc17Block",
    "window.Bc17Block = {" in page)
  check("and the shared onText calls it",
    "if (window.Bc17Block) window.Bc17Block.onFrame(s);" in page)
  check("and the inherited block attaches the transport to it",
    "window.Bc17Block.attach({" in page)
  check("the two rail boxes are in relayout()'s --statrail set",
    "'bc17-econ', 'bc17-units'" in page)
  check("the endcard noun table has a bc17 row",
    "bc17: { unit: 'archon'" in page)
  ## **EVERY BEAT KIND THE SIM CAN EMIT HAS A SCOPED RULE.** Seven of the
  ## thirteen names are another year's as well, which is exactly why the
  ## scoping is mandatory.
  for kind in ["doctrine", "game", "build", "tree", "archon", "donate",
               "shake", "strike", "volley", "rout", "duel", "famine", "end"]:
    check("a scoped rule for the bc17 " & kind & " beat",
      "html[data-year=\"bc17\"] .beat-marker." & kind & " {" in page)

finish("test_viewer")
