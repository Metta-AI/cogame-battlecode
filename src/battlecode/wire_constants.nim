## The JS wire-constants block: the handful of engine constants the browser
## chrome must agree with. Rendered ONCE from the same Nim consts the sim runs
## on, so a retuned playback speed or a moved chrome sprite id can never
## desync the page. `tools/gen_wire_constants.nim` emits it for the static
## wasm bundle, exactly as coworld-ctf does.

import broadcast, render, sim_types

proc jsIntArray(values: openArray[int]): string =
  result = "["
  for i, v in values:
    if i > 0: result.add ","
    result.add $v
  result.add "]"

const WireConstantsJs* =
  "window.CTF_WIRE={speeds:" & jsIntArray(PlaybackSpeeds) &
  ",fps:" & $TargetFps &
  ",chromeSpriteId:" & $BroadcastChromeSpriteId &
  ",tileSize:" & $TileSize &
  ",gameVersion:\"" & GameVersion & "\"" &
  ",teamColors:{ash:\"#e8a33d\",basil:\"#b06fd0\"}" &
  ",teamOrder:[\"ash\",\"basil\"]" &
  "};window.BC_WIRE=window.CTF_WIRE;"
  ## The key is `CTF_WIRE` because `client/chrome_common.js` is the starter's
  ## file BYTE FOR BYTE and reads that name; `BC_WIRE` is the alias the
  ## battlecode game block uses so nothing in this repo has to pretend to be
  ## paintball.

const WireConstantsMarker* = "<!-- WIRE_CONSTANTS -->"
