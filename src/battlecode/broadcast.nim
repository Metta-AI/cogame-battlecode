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
import years/dispatch
import years/bc26/[constants, rules, world]
from years/bc20/world as w20 import nil
from years/bc20/constants as c20 import nil
from years/bc20/chassis/signals as sig20 import nil
from years/bc21/world as w21 import nil
from years/bc21/constants as c21 import nil
from years/bc21/economy as e21 import nil
from years/bc21/rules as r21 import nil

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
      of "flood_stage": "flood"
      of "first_build": "build"
      of "wall_closed": "wall"
      of "rush_launched": "rush"
      of "drone_water_drop": "drop"
      of "hq_buried": "bury"
      of "hq_drowned": "drown"
      of "doctrine_received", "doctrine_fallback": "doctrine"
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
    of "flood_stage":
      label = "Water reaches elevation " & $e.fields{"level"}.getInt() &
        " — game " & $(e.game + 1) & ", round " & $e.round
    of "first_build":
      label = e.fields{"alias"}.getStr() & " builds its first " &
        e.fields{"unit"}.getStr().replace("_", " ") & " — game " &
        $(e.game + 1) & ", round " & $e.round
    of "wall_closed":
      label = e.fields{"alias"}.getStr() & " closes its HQ wall at elevation " &
        $e.fields{"min_ring_elevation"}.getInt() & " — game " &
        $(e.game + 1) & ", round " & $e.round
    of "rush_launched":
      label = e.fields{"alias"}.getStr() & " launches the rush — game " &
        $(e.game + 1) & ", round " & $e.round
    of "drone_water_drop":
      label = e.fields{"alias"}.getStr() & " drops a " &
        e.fields{"victim_unit"}.getStr().replace("_", " ") & " in the water — game " &
        $(e.game + 1) & ", round " & $e.round
    of "hq_buried":
      label = "HQ BURIED — " & e.fields{"alias"}.getStr() & ", game " &
        $(e.game + 1) & ", round " & $e.round
    of "hq_drowned":
      label = "HQ DROWNED — " & e.fields{"alias"}.getStr() & ", game " &
        $(e.game + 1) & ", round " & $e.round
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

proc bc20Flood(w: w20.World): JsonNode =
  ## `#bc20-flood`: the water level to 2 dp, the flood ring gauge, and the
  ## HQ-elevation-versus-water reading the panel flashes red on.
  var hqElev = [-1, -1]
  for t in 0 .. 1:
    let id = w.hqId[t]
    if id >= 0 and id in w.robotsById:
      hqElev[t] = w20.getDirt(w, w.robotsById[id].loc)
  %*{
    "water": float(w.waterLevel),
    "flooded": w.floodedCount,
    "tiles": w.width * w.height,
    "hq_elevation": hqElev,
    "global_pollution": w.globalPollution
  }

proc bc20Soup(w: w20.World, sideAslot: int): JsonNode =
  result = newJArray()
  for slot in 0 .. 1:
    let t = if slot == sideAslot: 0 else: 1
    result.add(%*{
      "pool": w.stats.soup[t],
      "mined": w.stats.soupMined[t],
      "refined": w.stats.soupRefined[t]
    })

proc bc20Units(w: w20.World, sideAslot: int): JsonNode =
  ## Per clan, counts by type plus the HQ's dirt load as `dirt/50`.
  result = newJArray()
  for slot in 0 .. 1:
    let t = if slot == sideAslot: 0 else: 1
    var hqDirt = 0
    let id = w.hqId[t]
    if id >= 0 and id in w.robotsById:
      hqDirt = w.robotsById[id].dirtCarrying
    result.add(%*{
      "miner": w.typeCount[t][c20.rtMiner],
      "landscaper": w.typeCount[t][c20.rtLandscaper],
      "drone": w.typeCount[t][c20.rtDeliveryDrone],
      "vaporator": w.typeCount[t][c20.rtVaporator],
      "net_gun": w.typeCount[t][c20.rtNetGun],
      "design_school": w.typeCount[t][c20.rtDesignSchool],
      "fulfillment_center": w.typeCount[t][c20.rtFulfillmentCenter],
      "refinery": w.typeCount[t][c20.rtRefinery],
      "hq_dirt": hqDirt,
      "hq_dirt_limit": c20.RobotSpecs[c20.rtHq].dirtLimit,
      "dirt_moved": w.stats.dirtMoved[t],
      "drone_drops": w.stats.droneWaterDrops[t],
      "net_gun_kills": w.stats.netGunKills[t]
    })

proc bc20Chain(w: w20.World, sideAslot: int): JsonNode =
  ## `#bc20-chain`, the endcard's blockchain panel. NOTHING about the chain is
  ## stored in the replay: the wasm sim re-derives every block, and this reads
  ## the re-derived blocks. Messages whose first int is not `SIGNAL_KEY` are
  ## shown as raw ints, which is what makes an opponent's private traffic look
  ## private without hiding that it happened.
  var minted = [0, 0]
  var spent = [0, 0]
  var topFee = [0, 0]
  var topRound = [-1, -1]
  var recent = newJArray()
  for roundIndex, blk in w.blockchain:
    for tx in blk:
      let slot = if tx.team == 0: sideAslot else: 1 - sideAslot
      minted[slot] += 1
      spent[slot] += tx.cost
      if tx.cost > topFee[slot]:
        topFee[slot] = tx.cost
        topRound[slot] = roundIndex + 1
      var words = ""
      if tx.message[0] == sig20.SignalKey:
        words = sig20.signalName(tx.message[2])
      else:
        for i, v in tx.message:
          if i > 0: words.add("_")
          words.add($v)
      recent.add(%*{"alias": aliasFor(slot), "round": roundIndex + 1,
                    "fee": tx.cost, "words": words})
  ## The LAST FIVE minted messages, decoded to plain words.
  var tail = newJArray()
  let start = max(0, recent.len - 5)
  for i in start ..< recent.len:
    tail.add(recent[i])
  %*{
    "minted": minted, "soup_spent": spent,
    "top_fee": topFee, "top_fee_round": topRound,
    "recent": tail
  }

proc doctrineWords(doc: ReplayDoc): JsonNode = doctrinesJson(doc)

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

proc bc21Votes(w: w21.World, sideAslot: int): JsonNode =
  ## `#bc21-votes`: the election readout. `to_clinch` is the number of votes
  ## that guarantees the round-1500 win, i.e. a majority of the 1500 on offer.
  var votes = newJArray()
  for slot in 0 .. 1:
    let t = if slot == sideAslot: 0 else: 1
    votes.add(%w.stats.votes[t])
  %*{
    "votes": votes,
    "on_offer": w.maxRounds,
    "to_clinch": w.maxRounds div 2 + 1,
    "tied_rounds": w.stats.votesTied
  }

proc bc21Influence(w: w21.World, sideAslot: int): JsonNode =
  ## `#bc21-influence`: per clan, total Centre influence, income per round, and
  ## Centres owned as `own / on the map`.
  var onMap = 0
  for _, r in w.robotsById:
    if r.kind == c21.rtEnlightenmentCenter: inc onMap
  result = newJArray()
  for slot in 0 .. 1:
    let team = (if slot == sideAslot: w21.teamA else: w21.teamB)
    var centreInfluence = 0
    for _, r in w.robotsById:
      if r.team == team and r.kind == c21.rtEnlightenmentCenter:
        centreInfluence += r.influence
    let owned = w21.livingCenters(w, team)
    result.add(%*{
      "influence": centreInfluence,
      "total_influence": w21.totalInfluence(w, team),
      "income": owned * e21.ecPassive(max(1, w.currentRound)),
      "centers": owned,
      "centers_on_map": onMap,
      "spent": w.stats.influenceSpent[ord(team)],
      "bid_spent": w.stats.bidInfluenceSpent[ord(team)]
    })

proc bc21Units(w: w21.World, sideAslot: int): JsonNode =
  ## `#bc21-units`: per clan, the three unit types alive and the live speech
  ## buff.
  result = newJArray()
  for slot in 0 .. 1:
    let t = if slot == sideAslot: 0 else: 1
    let team = w21.Team(t)
    result.add(%*{
      "politician": w.typeCount[t][c21.rtPolitician],
      "slanderer": w.typeCount[t][c21.rtSlanderer],
      "muckraker": w.typeCount[t][c21.rtMuckraker],
      "buff": w.stats.numBuffs[t],
      "buff_factor": 1.0 + 0.001 * float(w.stats.numBuffs[t]),
      "built": w.stats.unitsBuilt[t],
      "exposes": w.stats.exposes[t],
      "empowers": w.stats.empowers[t],
      "conversions": w.stats.conversions[t],
      "camouflaged": w.stats.camouflaged[t],
      "lost": w.stats.robotsLost[t]
    })

proc bc21Bids(w: w21.World, sideAslot: int): JsonNode =
  ## `#bc21-bids`, the endcard's auction panel. NOTHING about the auction is
  ## stored in the replay: the wasm sim re-derives every round and this reads
  ## the re-derived tally.
  var clans = newJArray()
  for slot in 0 .. 1:
    let t = if slot == sideAslot: 0 else: 1
    clans.add(%*{
      "alias": aliasFor(slot),
      "votes": w.stats.votes[t],
      "bids": w.stats.bidsPlaced[t],
      "burned": w.stats.bidInfluenceSpent[t],
      "top_bid": w.stats.topBid[t]
    })
  %*{
    "clans": clans,
    "tied_rounds": w.stats.votesTied,
    "no_bid_rounds": w.stats.roundsNoBid
  }

proc bc21ChromeJson*(
  doc: ReplayDoc, w: w21.World, view: ViewerState,
  frame, totalFrames, gameIndex, sideAslot: int,
  beats: JsonNode, gameChips: JsonNode, ended: bool
): string =
  ## One frame of bc21 chrome. `t` / `st` / `mx` / `mt` are the GENERIC
  ## timeline keys `chrome_common.js` reads, unchanged, so the clock, the
  ## transport and the scrubber are driven by the starter's own code; the
  ## `bc21_*` keys are what the APPENDED bc21 game block draws.
  let phase = if ended: "gameover" else: "playing"
  let points = r21.gamePoints(w)
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
    "year": "bc21",
    "beats": beats,
    "game": gameIndex + 1,
    "games": doc.games.len,
    "map": doc.plan.maps[min(gameIndex, doc.plan.maps.high)],
    "round": w.currentRound,
    "rounds": doc.plan.maxRounds,
    "aliases": [AliasA, AliasB],
    "names": [doc.names[0], doc.names[1]],
    "sides": [(if sideAslot == 0: "A" else: "B"),
              (if sideAslot == 0: "B" else: "A")],
    "points": [points[(if sideAslot == 0: 0 else: 1)],
               points[(if sideAslot == 0: 1 else: 0)]],
    "bc21_votes": bc21Votes(w, sideAslot),
    "bc21_influence": bc21Influence(w, sideAslot),
    "bc21_units": bc21Units(w, sideAslot),
    "bc21_bids": bc21Bids(w, sideAslot),
    "gamechips": gameChips,
    "doctrines": doctrineWords(doc),
    "result": doc.result
  }
  $node

proc bc20ChromeJson*(
  doc: ReplayDoc, w: w20.World, view: ViewerState,
  frame, totalFrames, gameIndex, sideAslot: int,
  beats: JsonNode, gameChips: JsonNode, ended: bool
): string =
  ## One frame of bc20 chrome. `t` / `st` / `mx` / `mt` are the GENERIC
  ## timeline keys `chrome_common.js` reads, unchanged, so the clock, the
  ## transport and the scrubber are driven by the starter's own code; the
  ## `bc20_*` keys are what the APPENDED bc20 game block draws.
  let phase = if ended: "gameover" else: "playing"
  let points = w20.gamePoints(w)
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
    "year": "bc20",
    "beats": beats,
    "game": gameIndex + 1,
    "games": doc.games.len,
    "map": doc.plan.maps[min(gameIndex, doc.plan.maps.high)],
    "round": w.currentRound,
    "rounds": doc.plan.maxRounds,
    "aliases": [AliasA, AliasB],
    "names": [doc.names[0], doc.names[1]],
    "sides": [(if sideAslot == 0: "A" else: "B"),
              (if sideAslot == 0: "B" else: "A")],
    "points": [points[(if sideAslot == 0: 0 else: 1)],
               points[(if sideAslot == 0: 1 else: 0)]],
    "bc20_flood": bc20Flood(w),
    "bc20_soup": bc20Soup(w, sideAslot),
    "bc20_units": bc20Units(w, sideAslot),
    "bc20_chain": bc20Chain(w, sideAslot),
    "gamechips": gameChips,
    "doctrines": doctrineWords(doc),
    "result": doc.result
  }
  $node

proc sessionChromeJson*(
  doc: ReplayDoc, s: Session, view: ViewerState,
  frame, totalFrames, gameIndex, sideAslot: int,
  beats: JsonNode, gameChips: JsonNode, ended: bool
): string =
  case s.year
  of yBc26:
    chromeJson(doc, s.w26, view, frame, totalFrames, gameIndex, sideAslot,
      beats, gameChips, ended)
  of yBc20:
    bc20ChromeJson(doc, s.w20, view, frame, totalFrames, gameIndex, sideAslot,
      beats, gameChips, ended)
  of yBc21:
    bc21ChromeJson(doc, s.w21, view, frame, totalFrames, gameIndex, sideAslot,
      beats, gameChips, ended)
