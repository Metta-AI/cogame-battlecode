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

## Transport rules from the design note.
check("relayout sets --hudscale", "--hudscale" in page)
check("relayout sets --topband", "--topband" in page)
check("relayout sets --band", "--band" in page)
check("the endcard stops at the transport band",
  "bottom: calc(var(--band" in page)
check("the scorebug stays legible at 360 px",
  ".plate-name { flex: 1 1 auto; min-width: 3.2em; }" in page)
check("and labels drop under 640 px", "@media (max-width: 640px)" in page)
check("every seek dismisses the endcard", "dismissEndcard" in page)

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
check("there is no #endcard.show rule to justify one",
  "#endcard.show {" notin page)
check("the page uses the renamed static-replay adapter",
  "BcStaticReplay" in page)

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
      mapSha: mapSha("DefaultSmall"), sideAslot: 0,
      rounds: outcome.roundsPlayed, hashChain: outcome.hashChain)])
  for slot in 0 .. 1: doc.names[slot] = "s" & $slot

  let back = parseReplay($doc.toJson())
  let deriver = newDeriver(back)
  let renderer = newRenderer()
  var view = initViewerState()
  discard deriver.advance()
  let beats = beatsFor(back, proc (g, r: int): int = 0)
  let first = renderer.buildPacket(deriver.world, 0, 0,
    chromeJson(back, deriver.world, view, 0, deriver.totalFrames, 0, 0,
      beats, newJArray(), false))
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
          m.sprite.width, deriver.world.width * render.TileSize)
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
  let later = renderer.buildPacket(deriver.world, 0, 0,
    chromeJson(back, deriver.world, view, deriver.frame, deriver.totalFrames,
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

finish("test_viewer")
