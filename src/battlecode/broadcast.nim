## The JSON chrome channel: the scorebug, the feed beats and the endcard
## payload, plus the viewer's own playback state.
##
## The document rides as the LABEL of `render.BroadcastChromeSpriteId`, which
## `client/broadcast_core.js` routes straight to `onText` and never draws.
## Its GENERIC keys (`t`, `st`, `mx`, `mt`, `sp`, `pl`, `lp`, `sk`, `ff`,
## `en`, `ph`, `beats`) are the starter's, so `client/chrome_common.js` drives
## the clock, the transport and the scrubber unchanged; the battlecode keys
## (`coop`, `bars`, `econ`, `gamechips`, `doctrines`) are what the appended
## game block draws.

import std/[json, strutils]
import sim_types, sheet, match, replay
import years/bc26/[constants, rules, world]

const
  PlaybackSpeeds* = [1, 2, 3, 4, 8, 16]
  TargetFps* = 24

type
  ViewerState* = object
    ## Everything a transport command can change. Held per viewer so a
    ## spectator's scrub cannot move anyone else's playhead.
    playing*: bool
    speed*: int
    loop*: bool
    skipLulls*: bool
    spoilers*: bool
    seekFrame*: int          ## -1 when no seek is pending
    accumulator*: int

proc initViewerState*(): ViewerState =
  ViewerState(playing: true, speed: 1, loop: false, skipLulls: false,
              seekFrame: -1)

proc applyCommand*(v: var ViewerState, totalFrames: int, text: string) =
  ## The starter's transport vocabulary, unchanged: the page and
  ## `chrome_common.js` already speak it.
  if text.len == 0: return
  if text.startsWith("s:"):
    let frac = try: parseFloat(text[2 .. ^1]) except CatchableError: -1.0
    if frac >= 0.0 and frac <= 1.0:
      v.seekFrame = int(frac * float(max(0, totalFrames - 1)))
    return
  if text.startsWith("v:"):
    return                      ## no per-seat POV in this coworld
  case text
  of " ": v.playing = not v.playing
  of ",": v.seekFrame = 0
  of "b": v.seekFrame = -2      ## one frame back, resolved by the caller
  of ".": v.seekFrame = -3      ## +25 rounds, resolved by the caller
  of "e": v.seekFrame = max(0, totalFrames - 1)
  of "r": v.loop = not v.loop
  of "f": v.skipLulls = not v.skipLulls
  of "o": v.spoilers = not v.spoilers
  of "+":
    for i, s in PlaybackSpeeds:
      if s == v.speed and i + 1 < PlaybackSpeeds.len:
        v.speed = PlaybackSpeeds[i + 1]
        break
  of "-":
    for i, s in PlaybackSpeeds:
      if s == v.speed and i > 0:
        v.speed = PlaybackSpeeds[i - 1]
        break
  of "1": v.speed = 1
  of "2": v.speed = 2
  of "3": v.speed = 3
  of "4": v.speed = 4
  of "8": v.speed = 8
  of "6": v.speed = 16
  else: discard

# ---------------------------------------------------------------------------
#  The chrome document
# ---------------------------------------------------------------------------

proc barsFor(w: World, sideAslot: int): JsonNode =
  ## The three-bar points breakdown, per SEAT: cat damage, kings, cheese —
  ## the same three shares the scoring formula weights.
  let ti = w.teamInfo
  let
    totalCat = ti.damageToCats[0] + ti.damageToCats[1]
    totalKings = ti.numRatKings[0] + ti.numRatKings[1]
    totalCheese = ti.cheeseTransferred[0] + ti.cheeseTransferred[1]
  result = newJArray()
  for slot in 0 .. 1:
    let t = if slot == sideAslot: 0 else: 1
    result.add(%*{
      "cat": (if totalCat > 0: ti.damageToCats[t] * 100 div totalCat else: 0),
      "kings": (if totalKings > 0: ti.numRatKings[t] * 100 div totalKings else: 0),
      "cheese": (if totalCheese > 0:
                   ti.cheeseTransferred[t] * 100 div totalCheese else: 0)
    })

proc econFor(w: World, sideAslot: int): JsonNode =
  ## The economic story the endcard and `#econ` report, per SEAT.
  result = newJArray()
  for slot in 0 .. 1:
    let t = if slot == sideAslot: 0 else: 1
    result.add(%*{
      "kings": w.teamInfo.numRatKings[t],
      "kings_built": w.teamInfo.kingsBuilt[t],
      "rats": w.teamInfo.numBabyRats[t],
      "rats_built": w.teamInfo.ratsBuilt[t],
      "cheese": w.teamInfo.cheeseTransferred[t],
      "bank": w.teamInfo.globalCheese[t],
      "cat_damage": w.teamInfo.damageToCats[t],
      "traps": w.teamInfo.trapsPlaced[t],
      "dirt": w.teamInfo.dirtPlaced[t]
    })

proc beatsFor*(doc: ReplayDoc, frameOfGameRound: proc (g, r: int): int): JsonNode =
  ## Every scrubber beat, with the ABSOLUTE frame it lands on. The game block
  ## turns each of these into a labelled, clickable `<button>`.
  result = newJArray()
  for e in doc.events:
    if e.game < 0 or e.round < 0: continue
    let kind =
      case e.kind
      of "backstab": "backstab"
      of "king_built": "king"
      of "cat_fed": "cat"
      of "game_start": "game"
      of "game_end": "end"
      of "game_abandoned": "end"
      else: ""
    if kind.len == 0: continue
    var label = ""
    case e.kind
    of "backstab":
      label = "BACKSTAB — " & e.fields{"by_alias"}.getStr() &
        ", game " & $(e.game + 1) & ", round " & $e.round
    of "king_built":
      label = e.fields{"alias"}.getStr() & " crowns a rat king — game " &
        $(e.game + 1) & ", round " & $e.round
    of "cat_fed":
      label = e.fields{"alias"}.getStr() & " feeds a rat to a cat — game " &
        $(e.game + 1) & ", round " & $e.round
    of "game_start":
      label = "Game " & $(e.game + 1) & " begins on " & e.fields{"map"}.getStr()
    of "game_end":
      label = "Game " & $(e.game + 1) & " — " &
        e.fields{"winner_alias"}.getStr() & " wins (" &
        e.fields{"end_reason"}.getStr().replace("_", " ") & ")"
    of "game_abandoned":
      label = "Game " & $(e.game + 1) & " abandoned at the wall clock"
    else: discard
    result.add(%*{
      "t": frameOfGameRound(e.game, max(1, e.round)),
      "k": kind,
      "label": label,
      "game": e.game,
      "round": e.round
    })

proc doctrinesJson*(doc: ReplayDoc): JsonNode =
  result = newJArray()
  for slot in 0 .. 1:
    var words = newJArray()
    for word in doc.seats[slot].sheet.plainWords():
      words.add(%word)
    result.add(%*{
      "alias": aliasFor(slot),
      "name": doc.seats[slot].name,
      "policy": doc.seats[slot].policyKind,
      "fallback": doc.seats[slot].fallback,
      "words": words,
      "notes": doc.seats[slot].sheet.notes,
      "motto": doc.seats[slot].sheet.motto
    })

proc chromeJson*(
  doc: ReplayDoc, w: World, view: ViewerState,
  frame, totalFrames, gameIndex, sideAslot: int,
  beats: JsonNode, gameChips: JsonNode, ended: bool
): string =
  ## One frame of chrome. `t` / `st` / `mx` / `mt` are the generic timeline
  ## keys `chrome_common.js` reads; everything from `coop` down is ours.
  let phase = if ended: "gameover" else: "playing"
  var node = %*{
    "t": frame,
    "st": 0,
    "mx": max(1, totalFrames - 1),
    "mt": 0,
    "sp": view.speed,
    "pl": view.playing,
    "lp": view.loop,
    "sk": view.skipLulls,
    "ff": false,
    "en": true,
    "ph": phase,
    "lob": 0,
    "pov": -1,
    "nim": GameVersion,
    "beats": beats,
    "game": gameIndex + 1,
    "games": doc.games.len,
    "map": doc.plan.maps[min(gameIndex, doc.plan.maps.high)],
    "round": w.currentRound,
    "rounds": doc.plan.maxRounds,
    "coop": w.isCooperation,
    "backstab_round": (if w.hasBackstabber: w.backstabRound else: -1),
    "backstab_by": (if w.hasBackstabber:
        aliasFor(if w.backstabber == teamA: sideAslot else: 1 - sideAslot)
      else: ""),
    "aliases": [AliasA, AliasB],
    "names": [doc.names[0], doc.names[1]],
    "points": [w.gamePoints()[(if sideAslot == 0: 0 else: 1)],
               w.gamePoints()[(if sideAslot == 0: 1 else: 0)]],
    "bars": barsFor(w, sideAslot),
    "econ": econFor(w, sideAslot),
    "gamechips": gameChips,
    "doctrines": doctrinesJson(doc),
    "result": doc.result
  }
  $node
