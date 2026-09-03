## The wasm entry point for the static replay viewer.
##
## Forked function for function from `coworld-ctf/replay-viewer/ctf_replay.nim`
## (`ctf_* -> bc_*`), including the fixed `stageNote` buffer that survives an
## ABORTING_MALLOC abort and the `emscripten_exit_with_live_runtime` main that
## stops Nim's generated `main` from running every module-global destructor
## while JS keeps calling in.
##
## It parses OUR JSON replay instead of a bitreplay codec, then steps the
## SHARED sim module and emits bitworld sprite packets. The browser therefore
## re-derives every round from events + config + seed; no engine bytes ride in
## the replay.

import std/json
import bitworld/spriteprotocol
import battlecode/[broadcast, build_stamp, render, replay, sim_types]
import battlecode/years/bc26/world

var
  runtimeLoaded = false
  doc: ReplayDoc
  deriver: Deriver
  renderer: Renderer
  viewer: ViewerState
  beats: JsonNode
  gameChips: JsonNode
  packet: seq[uint8]
  lastError: string

var
  stageNote: array[192, char]
  stageNoteLen: int
  currentStage: string
  frameStage: string

proc stampStage(stage: string) =
  currentStage = stage
  stageNoteLen = min(stage.len, stageNote.len)
  if stageNoteLen > 0:
    copyMem(stageNote[0].addr, stage[0].unsafeAddr, stageNoteLen)

proc bytesFromPointer(data: ptr uint8, length: int): string =
  result = newString(length)
  if length > 0:
    copyMem(result[0].addr, data, length)

proc frameOfGameRound(g, r: int): int =
  for i in 0 ..< deriver.totalFrames:
    if deriver.frameGame[i] == g and deriver.frameRound[i] == r:
      return i
  0

proc buildGameChips(): JsonNode =
  result = newJArray()
  for e in doc.events:
    if e.kind != "game_end": continue
    result.add(%*{
      "game": e.game + 1,
      "winner": e.fields{"winner_alias"}.getStr(),
      "winner_slot": e.fields{"winner_slot"}.getInt(-1),
      "reason": e.fields{"end_reason"}.getStr()
    })

proc renderCurrent() =
  let gameIndex =
    if deriver.frame >= 0: deriver.frameGame[deriver.frame]
    else: 0
  let sideAslot = doc.plan.sideAslots[min(gameIndex, doc.plan.sideAslots.high)]
  let ended = deriver.frame >= deriver.totalFrames - 1
  let chrome = chromeJson(doc, deriver.world, viewer, max(0, deriver.frame),
    deriver.totalFrames, gameIndex, sideAslot, beats, gameChips, ended)
  packet = renderer.buildPacket(deriver.world, gameIndex, sideAslot, chrome)

proc bcLoadReplay(data: ptr uint8, length: cint): cint
    {.exportc: "bc_load_replay", cdecl.} =
  try:
    lastError = ""
    stampStage("parse replay")
    doc = parseReplay(data.bytesFromPointer(int(length)))
    ## One stamp per phase, not one for the lot: the stage note is the only
    ## thing that survives an ABORTING_MALLOC abort, and a single "initialize
    ## replay runtime" covering four different phases costs a whole CI round
    ## to bisect.
    stampStage("build the deriver")
    deriver = newDeriver(doc)
    stampStage("load the sprite atlas")
    renderer = newRenderer()
    stampStage("collect the scrubber beats")
    viewer = initViewerState()
    beats = beatsFor(doc, frameOfGameRound)
    gameChips = buildGameChips()
    runtimeLoaded = true
    frameStage = "advance replay"
    stampStage("render first frame")
    if deriver.totalFrames > 0:
      discard deriver.advance()
    renderCurrent()
    return 1
  except Exception as error:
    runtimeLoaded = false
    lastError = currentStage & ": " & error.msg
    return 0

proc bcInput(data: ptr uint8, length: cint) {.exportc: "bc_input", cdecl.} =
  if not runtimeLoaded: return
  try:
    let text = readSpriteInputText(data.bytesFromPointer(int(length)))
    if text.len == 0: return
    viewer.applyCommand(deriver.totalFrames, text)
    if viewer.seekFrame == -2:
      deriver.seek(max(0, deriver.frame - 1))
      viewer.seekFrame = -1
    elif viewer.seekFrame == -3:
      deriver.seek(min(deriver.totalFrames - 1, deriver.frame + 25))
      viewer.seekFrame = -1
    elif viewer.seekFrame >= 0:
      deriver.seek(viewer.seekFrame)
      viewer.seekFrame = -1
    renderCurrent()
  except Exception as error:
    lastError = "apply input: " & error.msg

proc bcFrame(): cint {.exportc: "bc_frame", cdecl.} =
  if not runtimeLoaded:
    return 0
  stampStage(frameStage)
  try:
    if viewer.playing:
      for i in 0 ..< max(1, viewer.speed):
        if not deriver.advance():
          if viewer.loop:
            deriver.restart()
            discard deriver.advance()
          else:
            viewer.playing = false
          break
    renderCurrent()
    return 1
  except Exception as error:
    lastError = "advance replay: " & error.msg
    return -1

proc bcPacketPointer(): ptr uint8 {.exportc: "bc_packet_ptr", cdecl.} =
  if packet.len == 0: nil else: packet[0].addr

proc bcPacketLength(): cint {.exportc: "bc_packet_len", cdecl.} =
  cint(packet.len)

proc bcMismatchRound(): cint {.exportc: "bc_mismatch_round", cdecl.} =
  if runtimeLoaded: cint(deriver.mismatchRound) else: -1

proc bcErrorPointer(): ptr uint8 {.exportc: "bc_error_ptr", cdecl.} =
  if lastError.len == 0: nil else: cast[ptr uint8](lastError[0].addr)

proc bcErrorLength(): cint {.exportc: "bc_error_len", cdecl.} =
  cint(lastError.len)

proc bcStagePointer(): ptr uint8 {.exportc: "bc_stage_ptr", cdecl.} =
  ## Unlike `bc_error_*` this stays valid after an allocation-failure abort,
  ## so the page can still report what the runtime was doing.
  if stageNoteLen == 0: nil else: cast[ptr uint8](stageNote[0].addr)

proc bcStageLength(): cint {.exportc: "bc_stage_len", cdecl.} =
  cint(stageNoteLen)

var gameVersionCopy: string
  ## A const string literal has no stable runtime address to export a pointer
  ## to, and module-level initializers do not reliably run on a call-in-only
  ## wasm bundle — so the copy happens lazily, at CALL time.

proc bcGameVersionPointer(): ptr uint8
    {.exportc: "bc_game_version_ptr", cdecl.} =
  if gameVersionCopy.len == 0: gameVersionCopy = GameVersion
  if gameVersionCopy.len == 0: nil
  else: cast[ptr uint8](gameVersionCopy[0].unsafeAddr)

proc bcGameVersionLength(): cint {.exportc: "bc_game_version_len", cdecl.} =
  if gameVersionCopy.len == 0: gameVersionCopy = GameVersion
  cint(gameVersionCopy.len)

var simSourcesStampCopy: string

proc bcSimSourcesStampPointer(): ptr uint8
    {.exportc: "bc_sim_sources_stamp_ptr", cdecl.} =
  if simSourcesStampCopy.len == 0: simSourcesStampCopy = bcSimSourcesStamp
  if simSourcesStampCopy.len == 0: nil
  else: cast[ptr uint8](simSourcesStampCopy[0].unsafeAddr)

proc bcSimSourcesStampLength(): cint
    {.exportc: "bc_sim_sources_stamp_len", cdecl.} =
  if simSourcesStampCopy.len == 0: simSourcesStampCopy = bcSimSourcesStamp
  cint(simSourcesStampCopy.len)

when defined(emscripten):
  proc emscriptenExitWithLiveRuntime() {.
    importc: "emscripten_exit_with_live_runtime", cdecl.}

when isMainModule and defined(emscripten):
  ## Nim's generated main runs every module-global destructor when it
  ## returns, freeing the atlas, the deriver and the packet while the wasm
  ## module stays alive and JS keeps calling in. Unwinding through
  ## emscripten's live-runtime exit skips that epilogue entirely.
  emscriptenExitWithLiveRuntime()
