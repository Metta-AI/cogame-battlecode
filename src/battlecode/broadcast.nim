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
from years/bc24/world as w24 import nil
from years/bc24/constants as c24 import nil
from years/bc24/rules as r24 import nil
from years/bc25/world as w25 import nil
from years/bc25/towers as t25 import nil
from years/bc25/units as u25 import nil
from years/bc25/constants as c25 import nil
from years/bc25/rules as r25 import nil
from years/bc23/world as w23 import nil
from years/bc23/units as u23 import nil
from years/bc23/islands as i23 import nil
from years/bc23/constants as c23 import nil
from years/bc23/rules as r23 import nil
from years/bc22/world as w22 import nil
from years/bc22/units as u22 import nil
from years/bc16/world as w16 import nil
from years/bc16/rules as r16 import nil
from years/bc16/constants as c16 import nil
from years/bc16/units as u16 import nil
from years/bc16/economy as e16 import nil
from years/bc16/health as h16 import nil
from years/bc22/anomaly as a22 import nil
from years/bc22/economy as e22 import nil
from years/bc22/constants as c22 import nil
from years/bc22/rules as r22 import nil

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

proc permille(value: int): string =
  ## bc16's outbreak multiplier travels as an integer per-mille (1000, 1100,
  ## … 3000) so the replay stays float-free. Rendered as `1.1`, `3.0`.
  $(value div 1000) & "." & $((value mod 1000) div 100)

proc beatsFor*(doc: ReplayDoc, frameOfGameRound: proc (g, r: int): int): JsonNode =
  ## Every scrubber beat, with the ABSOLUTE frame it lands on. The game block
  ## turns each of these into a labelled, clickable `<button>`.
  result = newJArray()
  ## `first_action` and `rout` are spelled the same by bc24 and bc25 but carry
  ## different fields, so the beat vocabulary for those two kinds is chosen by
  ## the replay header's year. Every other kind below belongs to exactly one
  ## year.
  let isBc25 = doc.year == "bc25"
  let isBc23 = doc.year == "bc23"
  let isBc22 = doc.year == "bc22"
  let isBc16 = doc.year == "bc16"
  ## The bc23-only kinds below (`anchor_built`, `island_captured`,
  ## `island_lost`, `conquest_progress`, `well_transformed`, `well_upgraded`,
  ## `first_elixir_unit`, `boost_field`, `destabilize_hit`) need no
  ## discriminator, because no other year emits them. `duel` is NOT one of
  ## them — bc22, bc23 and bc16 all emit it — so its LABEL tests the year.
  for e in doc.events:
    ## Pre-match events carry `ms` and `game = -1`, not a round. The two
    ## doctrine kinds still have a beat (every year's stylesheet ships
    ## `.beat-marker.doctrine`), and it lands on frame 0 — the start of
    ## playback, which is when the sheets were read. Every other pre-match
    ## kind falls out below on an empty beat kind.
    let preMatch = e.game < 0 or e.round < 0
    if preMatch and e.kind notin ["doctrine_received", "doctrine_fallback"]:
      continue
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
      of "first_action": (if isBc25 or isBc23 or isBc22 or isBc16: "build"
                          else: "")
      of "tower_built": "tower"
      of "tower_upgraded": "upgrade"
      of "tower_lost": "siege"
      of "srp_completed", "srp_active", "srp_broken": "srp"
      of "coverage": "coverage"
      of "starved": "starve"
      of "rout": (if isBc25 or isBc23 or isBc22 or isBc16: "rout" else: "")
      of "anchor_built": "anchor"
      of "island_captured", "island_lost": "island"
      of "conquest_progress": "conquest"
      of "well_transformed", "well_upgraded", "first_elixir_unit": "elixir"
      of "boost_field": "boost"
      of "destabilize_hit": "destabilize"
      of "duel": "duel"
      of "lab_built": "lab"
      of "first_sage": "sage"
      of "watchtower_built": "tower"
      of "mutation": "mutate"
      of "gold_milestone": "gold"
      of "anomaly_struck": "anomaly"
      of "anomaly_dodged": "dodge"
      of "archon_lost", "archon_relocated": "archon"
      of "unit_milestone": "build"
      of "zombie_wave": "wave"
      of "outbreak": "outbreak"
      of "den_destroyed": "den"
      of "neutral_activated": "activate"
      of "infection": "infect"
      of "turned": "turned"
      of "tiebreak": "end"
      of "singularity": "end"
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
    of "first_action":
      label = e.fields{"alias"}.getStr() & " opens with " &
        e.fields{"action"}.getStr().replace("_", " ") & " — game " &
        $(e.game + 1) & ", round " & $e.round
    of "tower_built":
      label = e.fields{"alias"}.getStr() & " builds a " &
        e.fields{"tower"}.getStr() & " tower (" &
        $e.fields{"total"}.getInt() & " alive) — game " &
        $(e.game + 1) & ", round " & $e.round
    of "tower_upgraded":
      label = e.fields{"alias"}.getStr() & " upgrades a " &
        e.fields{"tower"}.getStr() & " tower to level " &
        $e.fields{"level"}.getInt() & " — game " &
        $(e.game + 1) & ", round " & $e.round
    of "tower_lost":
      label = "TOWER LOST — " & e.fields{"alias"}.getStr() & "'s " &
        e.fields{"tower"}.getStr() & " tower, game " &
        $(e.game + 1) & ", round " & $e.round
    of "srp_completed":
      label = e.fields{"alias"}.getStr() & " completes a resource pattern at " &
        $e.fields{"x"}.getInt() & "," & $e.fields{"y"}.getInt() &
        " — game " & $(e.game + 1) & ", round " & $e.round
    of "srp_active":
      label = e.fields{"alias"}.getStr() & "'s resource pattern goes live: +" &
        $e.fields{"income_bonus"}.getInt() & " a tower — game " &
        $(e.game + 1) & ", round " & $e.round
    of "srp_broken":
      label = "SRP BROKEN — " & e.fields{"alias"}.getStr() & "'s pattern at " &
        $e.fields{"x"}.getInt() & "," & $e.fields{"y"}.getInt() &
        " after " & $e.fields{"age"}.getInt() & " rounds, game " &
        $(e.game + 1) & ", round " & $e.round
    of "coverage":
      ## The note's own feed line, word for word.
      label = e.fields{"alias"}.getStr() & " passes " &
        $(e.fields{"permille"}.getInt() div 10) & " % — " &
        $e.fields{"tiles_from_win"}.getInt() & " tiles from the win"
    of "starved":
      label = e.fields{"alias"}.getStr() & " runs dry: " &
        $e.fields{"robots"}.getInt() & " robots end the round at zero paint" &
        " — game " & $(e.game + 1) & ", round " & $e.round
    of "anchor_built":
      label = e.fields{"alias"}.getStr() & " builds a " &
        e.fields{"anchor"}.getStr() & " anchor — game " &
        $(e.game + 1) & ", round " & $e.round
    of "island_captured":
      label = e.fields{"alias"}.getStr() & " anchors island " &
        $e.fields{"island"}.getInt() & " (" &
        $e.fields{"held_now"}.getInt() & " of the " &
        $e.fields{"to_win"}.getInt() & " it needs) — game " &
        $(e.game + 1) & ", round " & $e.round
    of "island_lost":
      label = "ANCHOR LOST — " & e.fields{"alias"}.getStr() & "'s island " &
        $e.fields{"island"}.getInt() & " after " &
        $e.fields{"held_for"}.getInt() & " rounds"
    of "conquest_progress":
      label = e.fields{"alias"}.getStr() & " holds " &
        $e.fields{"held"}.getInt() & " of the " &
        $e.fields{"to_win"}.getInt() & " islands it needs — game " &
        $(e.game + 1) & ", round " & $e.round
    of "well_transformed":
      label = e.fields{"alias"}.getStr() & " turns the " &
        e.fields{"from"}.getStr() & " well at " &
        $e.fields{"x"}.getInt() & "," & $e.fields{"y"}.getInt() &
        " into elixir — game " & $(e.game + 1) & ", round " & $e.round
    of "well_upgraded":
      label = e.fields{"alias"}.getStr() & " upgrades the " &
        e.fields{"type"}.getStr() & " well at " &
        $e.fields{"x"}.getInt() & "," & $e.fields{"y"}.getInt() &
        " to rate 3 — game " & $(e.game + 1) & ", round " & $e.round
    of "first_elixir_unit":
      label = e.fields{"alias"}.getStr() & " fields its first " &
        e.fields{"unit"}.getStr().replace("_", " ") & " — game " &
        $(e.game + 1) & ", round " & $e.round
    of "boost_field":
      label = e.fields{"alias"}.getStr() & " boosts the field at " &
        $e.fields{"x"}.getInt() & "," & $e.fields{"y"}.getInt() &
        " (" & $e.fields{"stacks"}.getInt() & " deep) — game " &
        $(e.game + 1) & ", round " & $e.round
    of "destabilize_hit":
      label = "DESTABILISED — " & e.fields{"alias"}.getStr() & " detonates at " &
        $e.fields{"x"}.getInt() & "," & $e.fields{"y"}.getInt() &
        " for " & $e.fields{"damage"}.getInt() & ", game " &
        $(e.game + 1) & ", round " & $e.round
    of "duel":
      ## THREE years emit `duel`, with the SAME field name and TWO meanings.
      ## bc22 (`years/bc22/rules.nim:275`) and bc16
      ## (`years/bc16/rules.nim:321`) both count `attackersLostThisRound` —
      ## every unit that can attack, lost by both sides in the same round —
      ## and read as a TRADE. bc23 (`years/bc23/rules.nim:397`) counts
      ## `launchersLostThisRound`, one unit type, and reads as a LAUNCHER
      ## DUEL. bc16 has no launcher, so it takes bc22's wording; testing
      ## `isBc22` alone dropped bc16 into bc23's branch and told a bc16
      ## spectator about a unit its year does not have.
      if isBc22 or isBc16:
        label = "TRADE — " & $e.fields{"lost"}[0].getInt() &
          " attackers lost to " & $e.fields{"lost"}[1].getInt() & ", game " &
          $(e.game + 1) & ", round " & $e.round
      else:
        label = "LAUNCHER DUEL — " & $e.fields{"lost"}[0].getInt() &
          " lost to " & $e.fields{"lost"}[1].getInt() & ", game " &
          $(e.game + 1) & ", round " & $e.round
    of "unit_milestone":
      label = e.fields{"alias"}.getStr() & " commissions its first " &
        e.fields{"unit"}.getStr().replace("_", " ") & " — game " &
        $(e.game + 1) & ", round " & $e.round
    of "zombie_wave":
      label = "WAVE — " & $e.fields{"total"}.getInt() & " zombies from " &
        $e.fields{"dens_spawning"}.getInt() & " dens at outbreak level " &
        $e.fields{"outbreak_level"}.getInt() & ", game " & $(e.game + 1) &
        ", round " & $e.round
    of "outbreak":
      label = "OUTBREAK " & $e.fields{"level"}.getInt() &
        " — every new zombie is " &
        permille(e.fields{"multiplier_permille"}.getInt()) &
        "x stronger from here, game " & $(e.game + 1) & ", round " & $e.round
    of "den_destroyed":
      label = e.fields{"alias"}.getStr() & " breaks the den at " &
        $e.fields{"x"}.getInt() & "," & $e.fields{"y"}.getInt() & " — " &
        $e.fields{"bounty"}.getInt() & " parts and " &
        $e.fields{"queue_deleted"}.getInt() & " zombies deleted, game " &
        $(e.game + 1) & ", round " & $e.round
    of "neutral_activated":
      label = e.fields{"alias"}.getStr() & " activates a neutral " &
        e.fields{"unit"}.getStr().toUpperAscii() & " at " &
        $e.fields{"x"}.getInt() & "," & $e.fields{"y"}.getInt() &
        " — game " & $(e.game + 1) & ", round " & $e.round
    of "infection":
      label = e.fields{"alias"}.getStr() & "'s " &
        e.fields{"victim_unit"}.getStr().toUpperAscii() & " is infected by a " &
        e.fields{"source"}.getStr() & " for " &
        $e.fields{"turns"}.getInt() & " turns, game " & $(e.game + 1) &
        ", round " & $e.round
    of "turned":
      label = e.fields{"alias"}.getStr().toUpperAscii() & "'S " &
        e.fields{"unit"}.getStr().toUpperAscii() & " TURNS — a " &
        e.fields{"became"}.getStr().toUpperAscii() & " at " &
        $e.fields{"x"}.getInt() & "," & $e.fields{"y"}.getInt() &
        ", and it is hunting whoever is nearest, game " & $(e.game + 1) &
        ", round " & $e.round
    of "tiebreak":
      label = "ROUND " & $e.round & " — " &
        e.fields{"rung"}.getStr().replace("_", " ") & " decides it: archons " &
        $e.fields{"archons"}[0].getInt() & " to " &
        $e.fields{"archons"}[1].getInt() & ", archon health " &
        $e.fields{"archon_health_tenths"}[0].getInt() & " to " &
        $e.fields{"archon_health_tenths"}[1].getInt()
    of "lab_built":
      label = e.fields{"alias"}.getStr() &
        (if e.fields{"finished"}.getBool(): " finishes" else: " places") &
        " a laboratory at " & $e.fields{"x"}.getInt() & "," &
        $e.fields{"y"}.getInt() & " — " & $e.fields{"rate"}.getInt() &
        " lead per gold, game " & $(e.game + 1) & ", round " & $e.round
    of "first_sage":
      label = e.fields{"alias"}.getStr() & " fields its first sage after " &
        $e.fields{"gold_spent_total"}.getInt() & " gold — game " &
        $(e.game + 1) & ", round " & $e.round
    of "watchtower_built":
      label = e.fields{"alias"}.getStr() &
        (if e.fields{"finished"}.getBool(): " finishes" else: " places") &
        " a watchtower at " & $e.fields{"x"}.getInt() & "," &
        $e.fields{"y"}.getInt() & " — game " & $(e.game + 1) &
        ", round " & $e.round
    of "mutation":
      label = e.fields{"alias"}.getStr() & " mutates a " &
        e.fields{"target"}.getStr() & " to level " &
        $e.fields{"level"}.getInt() & " — game " & $(e.game + 1) &
        ", round " & $e.round
    of "gold_milestone":
      label = e.fields{"alias"}.getStr() & " reaches " &
        $e.fields{"gold_total"}.getInt() & " gold at " &
        $e.fields{"rate"}.getInt() & " lead apiece — game " &
        $(e.game + 1) & ", round " & $e.round
    of "anomaly_struck":
      let lost = e.fields{"droids_lost"}
      let a = (if lost != nil and lost.len > 1: lost[0].getInt() else: 0)
      let b = (if lost != nil and lost.len > 1: lost[1].getInt() else: 0)
      label = e.fields{"type"}.getStr().toUpperAscii() &
        (if a + b > 0: " — " & $(a + b) & " droids gone: " & $a & " " &
                       AliasA & ", " & $b & " " & AliasB
         else: " strikes") &
        ", game " & $(e.game + 1) & ", round " & $e.round
    of "anomaly_dodged":
      label = e.fields{"alias"}.getStr() & " dodges the " &
        e.fields{"type"}.getStr().toUpperAscii() & " — game " &
        $(e.game + 1) & ", round " & $e.round
    of "archon_lost":
      ## bc22 AND bc16 both emit `archon_lost`, with DIFFERENT FIELDS —
      ## bc22 carries `gold_dropped`, bc16 carries the `cause` — so the
      ## label switch tests the year here (and only here: the beat KIND is
      ## `archon` in both, and the CSS that colours it is scoped per year).
      if isBc16:
        label = "ARCHON DOWN — " & e.fields{"alias"}.getStr() & " has " &
          $e.fields{"archons_left"}.getInt() & " left, killed by " &
          (if e.fields{"cause"}.getStr().len > 0:
             e.fields{"cause"}.getStr().replace("_", " ")
           else: "the horde") & ", game " & $(e.game + 1) &
          ", round " & $e.round
      else:
        label = "ARCHON DOWN — " & e.fields{"alias"}.getStr() & " has " &
          $e.fields{"archons_left"}.getInt() & " left, and " &
          $e.fields{"gold_dropped"}.getInt() & " gold is on the ground"
    of "archon_relocated":
      label = e.fields{"alias"}.getStr() & " walks an archon from " &
        $e.fields{"from_x"}.getInt() & "," & $e.fields{"from_y"}.getInt() &
        " to " & $e.fields{"to_x"}.getInt() & "," &
        $e.fields{"to_y"}.getInt() & " — game " & $(e.game + 1) &
        ", round " & $e.round
    of "singularity":
      label = "SINGULARITY — round " & $e.round & ", decided on " &
        e.fields{"rung"}.getStr().replace("_", " ") & ", game " &
        $(e.game + 1)
    of "rout":
      label = "ROUT — " & e.fields{"alias"}.getStr() & " loses " &
        $e.fields{"lost"}.getInt() & " robots, game " &
        $(e.game + 1) & ", round " & $e.round
    of "doctrine_received":
      label = "Doctrine read for " & aliasFor(e.fields{"slot"}.getInt()) &
        " (" & $e.fields{"latency_ms"}.getInt() & " ms)"
    of "doctrine_fallback":
      label = "DOCTRINE FALLBACK — " & aliasFor(e.fields{"slot"}.getInt()) &
        " (" & e.fields{"cause"}.getStr().replace("_", " ") & ")"
    else: discard
    result.add(%*{
      "t": (if preMatch: 0 else: frameOfGameRound(e.game, max(1, e.round))),
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
    ## THE SUBMITTED-VS-APPLIED BADGE's data (the envelope pin, LEARNINGS
    ## 2026-09-08): which envelope rule fired, how many knobs took their
    ## default, how many there are, and the first 120 runes of what the cog
    ## actually sent. A seat that played the schema-default sheet because its
    ## knobs arrived inside a protocol envelope is then visible to a spectator
    ## in one glance, which is the whole point of the finding.
    var applied = newJArray()
    for field in doc.seats[slot].sheet.defaultsApplied:
      applied.add(%field)
    result.add(%*{
      "alias": aliasFor(slot),
      "name": doc.seats[slot].name,
      "policy": doc.seats[slot].policyKind,
      "fallback": doc.seats[slot].fallback,
      "words": words,
      "notes": doc.seats[slot].sheet.notes,
      "motto": doc.seats[slot].sheet.motto,
      "envelope": doc.seats[slot].sheet.envelope,
      "defaults_applied": applied,
      "knob_count": knownKeysFor(doc.year).len,
      "submitted":
        doc.seats[slot].sheet.submitted.truncateRunes(120)
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

# ---------------------------------------------------------------------------
#  bc24 -- flags, crumbs, levels and the war panel
# ---------------------------------------------------------------------------

proc bc24Flags(w: w24.World, sideAslot: int): JsonNode =
  ## `#bc24-flags`: the headline readout. Three pips a clan -- CAPTURED,
  ## CARRIED and HOME -- and the two captures that clinch the game.
  result = newJArray()
  for slot in 0 .. 1:
    let team = (if slot == sideAslot: w24.teamA else: w24.teamB)
    let t = ord(team)
    var carried = 0
    var home = 0
    var away = 0
    for f in w.allFlags:
      if f.team != w24.other(team): continue
      ## The pips a clan shows are about the ENEMY's flags: those are the ones
      ## it is trying to take home.
      if f.carriedBy >= 0:
        let carrier = w24.robotById(w, f.carriedBy)
        if carrier != nil and carrier.team == team: carried += 1
      elif f.locIsStartRef: home += 1
      else: away += 1
    result.add(%*{
      "alias": aliasFor(slot),
      "captured": w.stats.flagsCaptured[t],
      "carried": carried,
      "enemy_home": home,
      "enemy_dropped": away,
      "picked_up": w.stats.flagsPickedUp[t],
      "to_win": max(0, c24.NumberFlags - w.stats.flagsCaptured[t])
    })

proc bc24Crumbs(w: w24.World, sideAslot: int): JsonNode =
  ## `#bc24-crumbs`: per clan, crumbs banked, income a round, traps standing
  ## and water tiles owned.
  var water = 0
  for v in w.water:
    if v: water += 1
  result = newJArray()
  for slot in 0 .. 1:
    let t = if slot == sideAslot: 0 else: 1
    result.add(%*{
      "crumbs": w.stats.crumbs[t],
      "income": c24.PassiveCrumbsIncrease,
      "collected": w.stats.crumbsCollected[t],
      "spent": w.stats.crumbsSpent[t],
      "kill_crumbs": w.stats.killCrumbs[t],
      "traps": max(0, w.stats.trapsBuilt[t] - w.stats.trapsTriggered[t]),
      "traps_built": w.stats.trapsBuilt[t],
      "traps_triggered": w.stats.trapsTriggered[t],
      "dug": w.stats.tilesDug[t],
      "filled": w.stats.tilesFilled[t],
      "water_tiles": water
    })

proc bc24Levels(w: w24.World, sideAslot: int): JsonNode =
  ## `#bc24-levels`: per clan, the three level sums, ducks alive, ducks in
  ## jail and the upgrades owned as lit glyphs.
  result = newJArray()
  for slot in 0 .. 1:
    let team = (if slot == sideAslot: w24.teamA else: w24.teamB)
    let t = ord(team)
    var attack, build, heal, alive, jailed = 0
    for duck in w.robots:
      if duck.team != team: continue
      attack += w24.levelOf(duck, c24.skAttack)
      build += w24.levelOf(duck, c24.skBuild)
      heal += w24.levelOf(duck, c24.skHeal)
      if duck.spawned: alive += 1
      elif duck.spawnCooldown > 0: jailed += 1
    result.add(%*{
      "attack": attack,
      "build": build,
      "heal": heal,
      "total": attack + build + heal,
      "alive": alive,
      "roster": c24.RobotCapacity,
      "jailed": jailed,
      "masteries": w.stats.masteries[t],
      "upgrades": [w.stats.upgrades[t][0], w.stats.upgrades[t][1],
                   w.stats.upgrades[t][2]],
      "upgrade_points": w.stats.upgradePoints[t]
    })

proc bc24Traps(w: w24.World, sideAslot: int): JsonNode =
  ## `#bc24-traps`, the endcard's WAR PANEL. NOTHING about traps, water or
  ## levels is stored in the replay: the wasm sim re-derives every round and
  ## this reads the re-derived totals.
  var clans = newJArray()
  for slot in 0 .. 1:
    let team = (if slot == sideAslot: w24.teamA else: w24.teamB)
    let t = ord(team)
    var levels = 0
    for duck in w.robots:
      if duck.team == team: levels += w24.levelSumOf(duck)
    var rounds = newJArray()
    for i in 0 .. 2: rounds.add(%w.stats.upgradeRound[t][i])
    clans.add(%*{
      "alias": aliasFor(slot),
      "picked_up": w.stats.flagsPickedUp[t],
      "dropped": w.stats.flagsDropped[t],
      "returned": w.stats.flagsReturned[t],
      "captured": w.stats.flagsCaptured[t],
      "traps_built": w.stats.trapsBuilt[t],
      "traps_triggered": w.stats.trapsTriggered[t],
      "trap_damage": w.stats.trapDamage[t],
      "dug": w.stats.tilesDug[t],
      "filled": w.stats.tilesFilled[t],
      "crumbs_collected": w.stats.crumbsCollected[t],
      "crumbs_on_dig": w.stats.crumbsSpentDig[t],
      "crumbs_on_fill": w.stats.crumbsSpentFill[t],
      "crumbs_on_traps": w.stats.crumbsSpentTraps[t],
      "levels": levels,
      "masteries": w.stats.masteries[t],
      "upgrade_rounds": rounds,
      "jailed": w.stats.ducksJailed[t],
      "kills": w.stats.kills[t],
      "damage": w.stats.damageDealt[t],
      "healed": w.stats.healDealt[t]
    })
  %*{
    "clans": clans,
    "setup_teleports": w.stats.setupFlagTeleports,
    "rounds_with_carry": w.stats.roundsWithAnyCarry
  }

proc bc24Jail(w: w24.World, sideAslot: int): JsonNode =
  ## The JAIL RAIL beside the scorebug: twenty-five rounds of absence is a
  ## story and an empty tile is not, so a jailed duck is drawn greyed with a
  ## countdown rather than simply vanishing.
  result = newJArray()
  for slot in 0 .. 1:
    let team = (if slot == sideAslot: w24.teamA else: w24.teamB)
    var rail = newJArray()
    for duck in w.robots:
      if duck.team != team or duck.spawned: continue
      if duck.spawnCooldown <= 0: continue
      if rail.len >= 12: break
      rail.add(%*{"id": duck.execIndex,
                  "rounds": (duck.spawnCooldown + c24.CooldownsPerTurn - 1) div
                            c24.CooldownsPerTurn})
    result.add(rail)

proc bc24ChromeJson*(
  doc: ReplayDoc, w: w24.World, view: ViewerState,
  frame, totalFrames, gameIndex, sideAslot: int,
  beats: JsonNode, gameChips: JsonNode, ended: bool
): string =
  ## One frame of bc24 chrome. `t` / `st` / `mx` / `mt` are the GENERIC
  ## timeline keys `chrome_common.js` reads, unchanged, so the clock, the
  ## transport and the scrubber are driven by the starter's own code; the
  ## `bc24_*` keys are what the APPENDED bc24 game block draws.
  let phase = if ended: "gameover" else: "playing"
  let points = r24.gamePoints(w)
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
    "year": "bc24",
    "beats": beats,
    "game": gameIndex + 1,
    "games": doc.games.len,
    "map": doc.plan.maps[min(gameIndex, doc.plan.maps.high)],
    "round": w.currentRound,
    "rounds": doc.plan.maxRounds,
    "setup_rounds": c24.SetupRounds,
    "setup": w24.isSetupPhase(w),
    "aliases": [AliasA, AliasB],
    "names": [doc.names[0], doc.names[1]],
    "sides": [(if sideAslot == 0: "A" else: "B"),
              (if sideAslot == 0: "B" else: "A")],
    "points": [points[(if sideAslot == 0: 0 else: 1)],
               points[(if sideAslot == 0: 1 else: 0)]],
    "bc24_flags": bc24Flags(w, sideAslot),
    "bc24_crumbs": bc24Crumbs(w, sideAslot),
    "bc24_levels": bc24Levels(w, sideAslot),
    "bc24_traps": bc24Traps(w, sideAslot),
    "bc24_jail": bc24Jail(w, sideAslot),
    "gamechips": gameChips,
    "doctrines": doctrineWords(doc),
    "result": doc.result
  }
  $node

# ---------------------------------------------------------------------------
#  bc25 -- coverage, towers, the paint economy and the war panel
# ---------------------------------------------------------------------------

proc bc25Coverage(w: w25.World, sideAslot: int): JsonNode =
  ## `#bc25-coverage`: THE HEADLINE READOUT AND THE YEAR'S WHOLE STORY. Both
  ## clans' share of the map, the 70 % tick, the tiles still needed, and the
  ## bare remainder.
  ##
  ## `area_without_walls` is the engine's OWN denominator and it counts ruin
  ## and tower tiles that can never be painted; `truly_paintable` is beside it
  ## so a spectator can see the gap that divergence creates
  ## (docs/RULES-BC25.md section Divergences item 5).
  let area = max(1, w.areaWithoutWalls)
  let toWin = u25.tilesToWin(w.areaWithoutWalls)
  var clans = newJArray()
  var bare = area
  for slot in 0 .. 1:
    let t = if slot == sideAslot: 0 else: 1
    bare -= w.stats.livePainted[t]
    clans.add(%*{
      "alias": aliasFor(slot),
      "tiles": w.stats.livePainted[t],
      "permille": u25.coveragePermille(w.stats.livePainted[t],
                                       w.areaWithoutWalls),
      "peak_permille": w.stats.peakCoverage[t],
      "to_win": max(0, toWin - w.stats.livePainted[t])
    })
  %*{
    "clans": clans,
    "area_without_walls": w.areaWithoutWalls,
    "truly_paintable": w.trulyPaintable,
    "tiles_to_win": toWin,
    "win_permille": c25.PaintPercentToWin * 10,
    "bare": max(0, bare)
  }

proc bc25Towers(w: w25.World, sideAslot: int): JsonNode =
  ## `#bc25-towers`: per clan, money / paint / defense counts with level pips,
  ## towers alive out of the 25 cap, and towers lost.
  result = newJArray()
  for slot in 0 .. 1:
    let team = (if slot == sideAslot: u25.teamA else: u25.teamB)
    let t = ord(team)
    var levels = newJArray()
    var money, paint, defense = 0
    for id in w.execOrder:
      let unit = w.robotsById[id]
      if unit.team != team or not u25.isTowerType(unit.kind): continue
      case u25.towerKindOf(unit.kind)
      of u25.tkMoney: money += 1
      of u25.tkPaint: paint += 1
      of u25.tkDefense: defense += 1
      if levels.len < 25:
        levels.add(%*{"kind": $u25.towerKindOf(unit.kind),
                      "level": u25.levelOf(unit.kind),
                      "x": unit.loc.x, "y": unit.loc.y,
                      "hp": unit.health,
                      "max_hp": c25.UnitSpecs[unit.kind].health})
    result.add(%*{
      "alias": aliasFor(slot),
      "alive": w.stats.towers[t],
      "cap": c25.MaxNumberOfTowers,
      "money": money, "paint": paint, "defense": defense,
      "built": w.stats.towersBuilt[t],
      "upgraded": w.stats.towersUpgraded[t],
      "lost": w.stats.towersLost[t],
      "damage_buff": w.damageIncrease[t],
      "towers": levels
    })

proc bc25Econ(w: w25.World, sideAslot: int): JsonNode =
  ## `#bc25-econ`: per clan, chips banked, chips a round, paint held across
  ## all units, active SRPs and the income they add, and pending SRPs with
  ## their countdown to fifty.
  result = newJArray()
  for slot in 0 .. 1:
    let team = (if slot == sideAslot: u25.teamA else: u25.teamB)
    let t = ord(team)
    var income = 0
    var paintIncome = 0
    let bonus = w25.extraResourcesFromPatterns(w, team)
    for id in w.execOrder:
      let unit = w.robotsById[id]
      if unit.team != team: continue
      if c25.UnitSpecs[unit.kind].moneyPerTurn != 0:
        income += c25.UnitSpecs[unit.kind].moneyPerTurn + bonus
      if c25.UnitSpecs[unit.kind].paintPerTurn != 0:
        paintIncome += c25.UnitSpecs[unit.kind].paintPerTurn + bonus
    var pending = newJArray()
    for centre in w.srpCentres:
      let i = w25.idx(w, centre)
      if int(w.srpTeamByLoc[i]) != t + 1: continue
      let life = int(w.srpLifetimes[i])
      if life >= c25.ResourcePatternActiveDelay: continue
      if pending.len >= 8: break
      pending.add(%*{"x": centre.x, "y": centre.y,
                     "rounds_left": c25.ResourcePatternActiveDelay - life})
    result.add(%*{
      "alias": aliasFor(slot),
      "chips": w.stats.money[t],
      "chips_per_round": income,
      "paint_per_round": paintIncome,
      "paint_in_units": w25.paintInUnits(w, team),
      "chips_earned": w.stats.chipsEarned[t],
      "chips_spent": w.stats.chipsSpent[t],
      "paint_mined": w.stats.paintMined[t],
      "paint_spent": w.stats.paintSpent[t],
      "srp_active": w25.numActiveResourcePatterns(w, team),
      "srp_bonus": bonus,
      "srp_pending": pending,
      "robots": t25.robotsAlive(w, team),
      "soldiers": t25.robotCountByKind(w, team, c25.utSoldier),
      "splashers": t25.robotCountByKind(w, team, c25.utSplasher),
      "moppers": t25.robotCountByKind(w, team, c25.utMopper)
    })

proc bc25War(w: w25.World, sideAslot: int): JsonNode =
  ## `#bc25-srp`, the endcard's WAR PANEL. NOTHING about paint, towers or
  ## resource patterns is stored in the replay: the wasm sim re-derives every
  ## round and this reads the re-derived totals.
  var clans = newJArray()
  for slot in 0 .. 1:
    let team = (if slot == sideAslot: u25.teamA else: u25.teamB)
    let t = ord(team)
    clans.add(%*{
      "alias": aliasFor(slot),
      "tiles_painted": w.stats.tilesPainted[t],
      "tiles_mopped": w.stats.tilesMopped[t],
      "tiles_overpainted": w.stats.tilesOverpainted[t],
      "peak_permille": w.stats.peakCoverage[t],
      "final_permille": u25.coveragePermille(w.stats.livePainted[t],
                                             w.areaWithoutWalls),
      "towers_built": w.stats.towersBuilt[t],
      "towers_upgraded": w.stats.towersUpgraded[t],
      "towers_lost": w.stats.towersLost[t],
      "money_towers": t25.towerCountByKind(w, team, u25.tkMoney),
      "paint_towers": t25.towerCountByKind(w, team, u25.tkPaint),
      "defense_towers": t25.towerCountByKind(w, team, u25.tkDefense),
      "chips_earned": w.stats.chipsEarned[t],
      "chips_spent": w.stats.chipsSpent[t],
      "paint_mined": w.stats.paintMined[t],
      "paint_spent": w.stats.paintSpent[t],
      "robots_built": w.stats.robotsBuilt[t],
      "soldiers_built": w.stats.soldiersBuilt[t],
      "splashers_built": w.stats.splashersBuilt[t],
      "moppers_built": w.stats.moppersBuilt[t],
      "robots_lost": w.stats.robotsLost[t],
      "robot_rounds_starved": w.stats.robotRoundsStarved[t],
      "srp_completed": w.stats.srpCompleted[t],
      "srp_active": w25.numActiveResourcePatterns(w, team),
      "srp_broken": w.stats.srpBroken[t],
      "srp_rounds_active": w.stats.srpRoundsActive[t],
      "splash_attacks": w.stats.splashAttacks[t],
      "mop_swings": w.stats.mopSwings[t],
      "tower_damage": w.stats.towerDamageDealt[t],
      "robot_damage": w.stats.robotDamageDealt[t],
      "messages": w.stats.messagesSent[t]
    })
  %*{
    "clans": clans,
    "rounds_with_any_srp": w.stats.roundsWithAnySrp,
    "ruins": w.allRuins.len
  }

proc bc25ChromeJson*(
  doc: ReplayDoc, w: w25.World, view: ViewerState,
  frame, totalFrames, gameIndex, sideAslot: int,
  beats: JsonNode, gameChips: JsonNode, ended: bool
): string =
  ## One frame of bc25 chrome. `t` / `st` / `mx` / `mt` are the GENERIC
  ## timeline keys `chrome_common.js` reads, unchanged, so the clock, the
  ## transport and the scrubber are driven by the starter's own code; the
  ## `bc25_*` keys are what the APPENDED bc25 game block draws.
  let phase = if ended: "gameover" else: "playing"
  let points = r25.gamePoints(w)
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
    "year": "bc25",
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
    "bc25_coverage": bc25Coverage(w, sideAslot),
    "bc25_towers": bc25Towers(w, sideAslot),
    "bc25_econ": bc25Econ(w, sideAslot),
    "bc25_war": bc25War(w, sideAslot),
    "gamechips": gameChips,
    "doctrines": doctrineWords(doc),
    "result": doc.result
  }
  $node

# ---------------------------------------------------------------------------
#  bc23 — the islands readout, the economy, the census and the war panel
# ---------------------------------------------------------------------------

proc bc23Islands(w: w23.World, sideAslot: int): JsonNode =
  ## `#bc23-islands`: THE HEADLINE READOUT AND THE YEAR'S WHOLE STORY. Both
  ## factions' island tally, the conquest threshold, the neutral count and a
  ## health pip per held island that empties as an anchor is ground down.
  let toWin = u23.islandsToWin(w.islands.len)
  var factions = newJArray()
  for slot in 0 .. 1:
    let team = u23.Team(if slot == sideAslot: 0 else: 1)
    var pips = newJArray()
    for isl in w.islands:
      if i23.isOwnedBy(isl, team):
        pips.add(%*{"id": isl.id, "pips": i23.healthPips(isl),
                    "health": isl.health,
                    "max": c23.AnchorSpecs[isl.anchor].totalHealth,
                    "anchor": $isl.anchor})
    factions.add(%*{
      "alias": aliasFor(slot),
      "held": w23.islandsOwned(w, team),
      "captured": w.stats.islandsCaptured[ord(team)],
      "lost": w.stats.islandsLost[ord(team)],
      "anchors_placed": w.stats.totalAnchorsPlaced[ord(team)],
      "to_win": max(0, toWin - w23.islandsOwned(w, team)),
      "pips": pips
    })
  %*{
    "factions": factions,
    "islands": w.islands.len,
    "islands_to_win": toWin,
    "neutral": w23.islandsNeutral(w)
  }

proc bc23Econ(w: w23.World, sideAslot: int): JsonNode =
  ## `#bc23-econ`: adamantium, mana and ELIXIR banked, cargo in flight, wells
  ## worked and their rate, and the elixir-programme badge.
  var worked = 0
  var upgraded = 0
  var elixirWells = 0
  for well in w.wellAt:
    if not well.present: continue
    worked += 1
    if well.upgraded: upgraded += 1
    if well.kind == u23.resElixir: elixirWells += 1
  var factions = newJArray()
  for slot in 0 .. 1:
    let team = u23.Team(if slot == sideAslot: 0 else: 1)
    let t = ord(team)
    factions.add(%*{
      "alias": aliasFor(slot),
      "adamantium": w.stats.adamantium[t],
      "mana": w.stats.mana[t],
      "elixir": w.stats.elixir[t],
      "mined": w.stats.adamantiumMined[t] + w.stats.manaMined[t] +
        w.stats.elixirMined[t],
      "banked": w.stats.resourcesBanked[t],
      "thrown": w.stats.resourcesThrown[t],
      "cargo": w23.cargoWeight(w, team),
      "wells_transformed": w.stats.wellsTransformed[t],
      "wells_upgraded": w.stats.wellsUpgraded[t]
    })
  %*{
    "factions": factions,
    "wells": worked,
    "wells_upgraded": upgraded,
    "elixir_wells": elixirWells
  }

proc bc23Units(w: w23.World, sideAslot: int): JsonNode =
  ## `#bc23-units`: the six-type census with the LAUNCHER COUNT EMPHASISED —
  ## this is the year of the launcher duel — plus robots lost and the anchors
  ## sitting unused in headquarters.
  result = newJArray()
  for slot in 0 .. 1:
    let team = u23.Team(if slot == sideAslot: 0 else: 1)
    let t = ord(team)
    result.add(%*{
      "alias": aliasFor(slot),
      "headquarters": w23.robotCountByType(w, team, c23.rtHeadquarters),
      "carriers": w23.robotCountByType(w, team, c23.rtCarrier),
      "launchers": w23.robotCountByType(w, team, c23.rtLauncher),
      "amplifiers": w23.robotCountByType(w, team, c23.rtAmplifier),
      "destabilizers": w23.robotCountByType(w, team, c23.rtDestabilizer),
      "boosters": w23.robotCountByType(w, team, c23.rtBooster),
      "built": w.stats.unitsBuilt[t],
      "lost": w.stats.robotsLost[t],
      "anchors_in_stock": w23.anchorsInStock(w, team)
    })

proc bc23War(w: w23.World, sideAslot: int): JsonNode =
  ## `#bc23-tempest`, the endcard war panel: everything the doctrines argued
  ## about, per faction. Nothing here is stored in the replay — the wasm sim
  ## re-derives every round.
  result = newJArray()
  for slot in 0 .. 1:
    let team = u23.Team(if slot == sideAslot: 0 else: 1)
    let t = ord(team)
    result.add(%*{
      "alias": aliasFor(slot),
      "islands_captured": w.stats.islandsCaptured[t],
      "islands_lost": w.stats.islandsLost[t],
      "islands_held": w23.islandsOwned(w, team),
      "rounds_holding": w.stats.roundsHoldingAnyIsland[t],
      "anchors_built": w.stats.anchorsBuilt[t],
      "anchors_placed": w.stats.totalAnchorsPlaced[t],
      "anchors_lost": w.stats.anchorsLost[t],
      "accelerating_anchors": w.stats.acceleratingAnchorsPlaced[t],
      "adamantium_mined": w.stats.adamantiumMined[t],
      "mana_mined": w.stats.manaMined[t],
      "elixir_mined": w.stats.elixirMined[t],
      "banked": w.stats.resourcesBanked[t],
      "thrown": w.stats.resourcesThrown[t],
      "wells_transformed": w.stats.wellsTransformed[t],
      "wells_upgraded": w.stats.wellsUpgraded[t],
      "carriers_built": w.stats.carriersBuilt[t],
      "launchers_built": w.stats.launchersBuilt[t],
      "amplifiers_built": w.stats.amplifiersBuilt[t],
      "destabilizers_built": w.stats.destabilizersBuilt[t],
      "boosters_built": w.stats.boostersBuilt[t],
      "robots_lost": w.stats.robotsLost[t],
      "damage": {"launcher": max(0, w.stats.damageDealt[t] -
                                   w.stats.throwDamage[t] -
                                   w.stats.hqDamage[t]),
                 "throw": w.stats.throwDamage[t],
                 "destabilizer": w.stats.destabilizeDamage[t],
                 "headquarters": w.stats.hqDamage[t]},
      "anchor_heals": w.stats.anchorHeals[t],
      "array_writes": w.stats.arrayWrites[t],
      "current_rides": w.stats.currentRides[t]
    })

proc bc23ChromeJson*(
  doc: ReplayDoc, w: w23.World, view: ViewerState,
  frame, totalFrames, gameIndex, sideAslot: int,
  beats: JsonNode, gameChips: JsonNode, ended: bool
): string =
  ## One frame of bc23 chrome. `t` / `st` / `mx` / `mt` are the GENERIC
  ## timeline keys `chrome_common.js` reads, unchanged, so the clock, the
  ## transport and the scrubber are driven by the starter's own code; the
  ## `bc23_*` keys are what the APPENDED bc23 game block draws.
  let phase = if ended: "gameover" else: "playing"
  let points = r23.gamePoints(w)
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
    "year": "bc23",
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
    "bc23_islands": bc23Islands(w, sideAslot),
    "bc23_econ": bc23Econ(w, sideAslot),
    "bc23_units": bc23Units(w, sideAslot),
    "bc23_war": bc23War(w, sideAslot),
    "gamechips": gameChips,
    "doctrines": doctrineWords(doc),
    "result": doc.result
  }
  $node

proc bc22Archons(w: w22.World, sideAslot: int): JsonNode =
  ## `#bc22-archons`: THE HEADLINE READOUT AND THE YEAR'S WHOLE STORY. Both
  ## factions' archon tally with a health pip per archon that drains as it is
  ## shot, a level dot, and a PORTABLE outline on any archon currently walking.
  ## Lose your last archon and you lose the game immediately, so this is the
  ## only readout that can end the match.
  var factions = newJArray()
  for slot in 0 .. 1:
    let team = u22.Team(if slot == sideAslot: 0 else: 1)
    var pips = newJArray()
    for id in w.execOrder:
      let r = w22.robotById(w, id)
      if r == nil or r.team != team or r.kind != c22.rtArchon: continue
      pips.add(%*{"id": r.id, "x": r.loc.x, "y": r.loc.y,
                  "health": r.health, "max": u22.maxHealthOf(r.kind, r.level),
                  "level": r.level, "mode": $r.mode,
                  "portable": r.mode == u22.rmPortable})
    factions.add(%*{
      "alias": aliasFor(slot),
      "alive": w22.robotCountByType(w, team, c22.rtArchon),
      "start": w.stats.archonsStart[ord(team)],
      "lost": w.stats.archonsLost[ord(team)],
      "relocations": w.stats.archonRelocations[ord(team)],
      "pips": pips
    })
  %*{"factions": factions}

proc bc22Anomaly(w: w22.World): JsonNode =
  ## `#bc22-anomaly`: THE YEAR'S SIGNATURE READOUT, AND THE ONE NO OTHER YEAR
  ## HAS. The next scheduled anomaly and how many rounds away, the whole
  ## remaining schedule as a mini-timeline, and the Singularity countdown.
  let nxt = a22.nextAnomaly(w)
  var schedule = newJArray()
  for i in 0 ..< w.map.anomalies.len:
    let e = w.map.anomalies[i]
    schedule.add(%*{"round": e.round,
                    "type": ($e.kind).toLowerAscii(),
                    "past": i < w.anomalyCursor})
  %*{
    "next": (if nxt.has: ($nxt.kind).toLowerAscii() else: ""),
    "next_round": (if nxt.has: nxt.round else: -1),
    "in_rounds": (if nxt.has: max(0, nxt.round - w.currentRound) else: -1),
    "schedule": schedule,
    "scheduled": w.map.anomalies.len,
    "consumed": w.anomalyCursor,
    "singularity_round": w.maxRounds,
    "singularity_in": max(0, w.maxRounds - w.currentRound)
  }

proc bc22Econ(w: w22.World, sideAslot: int): JsonNode =
  ## `#bc22-econ`: lead and gold banked, lead still on the map and how many
  ## squares have been mined dry (the `mine_floor` story, made visible),
  ## laboratories standing with their current transmute rate, and gold spent.
  var factions = newJArray()
  for slot in 0 .. 1:
    let team = u22.Team(if slot == sideAslot: 0 else: 1)
    let t = ord(team)
    var labs = newJArray()
    for id in w.execOrder:
      let r = w22.robotById(w, id)
      if r == nil or r.team != team or r.kind != c22.rtLaboratory: continue
      labs.add(%*{"x": r.loc.x, "y": r.loc.y, "level": r.level,
                  "mode": $r.mode,
                  "rate": (if r.mode == u22.rmPrototype: 0
                           else: e22.peekTransmutationRate(w, r))})
    factions.add(%*{
      "alias": aliasFor(slot),
      "lead": w.stats.lead[t],
      "gold": w.stats.gold[t],
      "lead_mined": w.stats.leadMined[t],
      "gold_transmuted": w.stats.goldTransmuted[t],
      "lead_spent_transmuting": w.stats.leadSpentTransmuting[t],
      "squares_mined_dry": w.stats.squaresMinedDry[t],
      "lead_net_worth": w22.leadNetWorth(w, team),
      "gold_net_worth": w22.goldNetWorth(w, team),
      "labs": labs
    })
  %*{
    "factions": factions,
    "lead_on_map": w22.leadOnMap(w),
    "lead_squares": w22.leadSquares(w)
  }

proc bc22Units(w: w22.World, sideAslot: int): JsonNode =
  ## `#bc22-units`: the seven-type census with SOLDIERS EMPHASISED (this is the
  ## year of the soldier), prototypes shown separately from finished buildings,
  ## and robots lost.
  result = newJArray()
  for slot in 0 .. 1:
    let team = u22.Team(if slot == sideAslot: 0 else: 1)
    let t = ord(team)
    result.add(%*{
      "alias": aliasFor(slot),
      "archons": w22.robotCountByType(w, team, c22.rtArchon),
      "miners": w22.robotCountByType(w, team, c22.rtMiner),
      "builders": w22.robotCountByType(w, team, c22.rtBuilder),
      "soldiers": w22.robotCountByType(w, team, c22.rtSoldier),
      "sages": w22.robotCountByType(w, team, c22.rtSage),
      "laboratories": w22.robotCountByType(w, team, c22.rtLaboratory),
      "watchtowers": w22.robotCountByType(w, team, c22.rtWatchtower),
      "prototypes": w22.modeCount(w, team, u22.rmPrototype),
      "portable": w22.modeCount(w, team, u22.rmPortable),
      "built": w.stats.unitsBuilt[t],
      "lost": w.stats.robotsLost[t]
    })

proc bc22War(w: w22.World, sideAslot: int): JsonNode =
  ## `#bc22-mutation`: the ENDCARD war panel.
  result = newJArray()
  for slot in 0 .. 1:
    let team = u22.Team(if slot == sideAslot: 0 else: 1)
    let t = ord(team)
    result.add(%*{
      "alias": aliasFor(slot),
      "archons_start": w.stats.archonsStart[t],
      "archons_end": w22.robotCountByType(w, team, c22.rtArchon),
      "archons_lost": w.stats.archonsLost[t],
      "archon_relocations": w.stats.archonRelocations[t],
      "lead_mined": w.stats.leadMined[t],
      "gold_mined": w.stats.goldMined[t],
      "lead_reclaimed": w.stats.leadReclaimed[t],
      "gold_reclaimed": w.stats.goldReclaimed[t],
      "squares_mined_dry": w.stats.squaresMinedDry[t],
      "miners_built": w.stats.minersBuilt[t],
      "builders_built": w.stats.buildersBuilt[t],
      "soldiers_built": w.stats.soldiersBuilt[t],
      "sages_built": w.stats.sagesBuilt[t],
      "labs_built": w.stats.labsBuilt[t],
      "labs_finished": w.stats.labsFinished[t],
      "watchtowers_built": w.stats.watchtowersBuilt[t],
      "watchtowers_finished": w.stats.watchtowersFinished[t],
      "mutations_l2": w.stats.mutationsL2[t],
      "mutations_l3": w.stats.mutationsL3[t],
      "transmutes": w.stats.transmutes[t],
      "gold_transmuted": w.stats.goldTransmuted[t],
      "lead_spent_transmuting": w.stats.leadSpentTransmuting[t],
      "repairs": w.stats.repairs[t],
      "hp_repaired": w.stats.hpRepaired[t],
      "envisions": w.stats.envisions[t],
      "damage": {"soldier": w.stats.soldierDamage[t],
                 "sage": w.stats.sageDamage[t],
                 "watchtower": w.stats.watchtowerDamage[t]},
      "array_writes": w.stats.arrayWrites[t],
      "transforms": w.stats.transforms[t],
      "anomaly_losses": {"charge": w.stats.anomalyLossesCharge[t],
                         "fury_hp": w.stats.anomalyLossesFuryHp[t],
                         "abyss_lead": w.stats.anomalyLossesAbyssLead[t]},
      "anomalies_dodged": w.stats.anomaliesDodged[t]
    })

proc bc22ChromeJson*(
  doc: ReplayDoc, w: w22.World, view: ViewerState,
  frame, totalFrames, gameIndex, sideAslot: int,
  beats: JsonNode, gameChips: JsonNode, ended: bool
): string =
  ## One frame of bc22 chrome. `t` / `st` / `mx` / `mt` are the GENERIC
  ## timeline keys `chrome_common.js` reads, unchanged, so the clock, the
  ## transport and the scrubber are driven by the starter's own code; the
  ## `bc22_*` keys are what the APPENDED bc22 game block draws.
  let phase = if ended: "gameover" else: "playing"
  let points = r22.gamePoints(w)
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
    "year": "bc22",
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
    "bc22_archons": bc22Archons(w, sideAslot),
    "bc22_anomaly": bc22Anomaly(w),
    "bc22_econ": bc22Econ(w, sideAslot),
    "bc22_units": bc22Units(w, sideAslot),
    "bc22_war": bc22War(w, sideAslot),
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

proc bc16Archons(w: w16.World, sideAslot: int): JsonNode =
  ## `#bc16-archons`: THE HEADLINE READOUT AND THE YEAR'S WHOLE STORY. Both
  ## factions' archon tally with a health pip per archon that drains as it is
  ## shot (1000 hp each), a GREEN ring on any archon that is zombie-infected
  ## and a VIOLET ring on any that is viper-infected. Lose your last archon
  ## and you lose the game on the spot, so this is the only readout that can
  ## end the match.
  var factions = newJArray()
  for slot in 0 .. 1:
    let team = u16.Team(if slot == sideAslot: 0 else: 1)
    var pips = newJArray()
    for id in w.execOrder:
      let r = w16.robotById(w, id)
      if r == nil or r.team != team or r.kind != c16.rtArchon: continue
      pips.add(%*{"id": r.id, "x": r.loc.x, "y": r.loc.y,
                  "health": int(r.health), "max": int(r.maxHealth),
                  "zombie_infected": r.inf.zombieTurns,
                  "viper_infected": r.inf.viperTurns})
    factions.add(%*{
      "alias": aliasFor(slot),
      "alive": w16.archonsAlive(w, team),
      "start": w.stats.archonsStart[ord(team)],
      "lost": w.stats.archonsLost[ord(team)],
      "health_tenths": int(w16.archonHealthTotal(w, team) * 10.0),
      "pips": pips
    })
  %*{"factions": factions}

proc bc16Horde(w: w16.World): JsonNode =
  ## `#bc16-horde`: THE YEAR'S SIGNATURE READOUT, AND THE ONE NO OTHER YEAR
  ## HAS — the horde clock. Zombies alive by type, the NEXT SCHEDULED WAVE
  ## with its composition and how many rounds away, the outbreak level and
  ## multiplier, dens standing, and the tiebreak countdown. It keeps its wave
  ## composition and its countdown AT EVERY WIDTH, including 360 px, because
  ## it is the readout that makes the year make sense.
  var nextRound = -1
  var nextCounts = newJArray()
  for row in w.map.schedule:
    if row.round > w.currentRound:
      nextRound = row.round
      for i, kind in u16.ZombieSpawnTypes:
        nextCounts.add(%*{"type": ($kind).toLowerAscii(),
                          "count": row.counts[i]})
      break
  var schedule = newJArray()
  for row in w.map.schedule:
    var total = 0
    for c in row.counts: total += c
    schedule.add(%*{"round": row.round, "count": total,
                    "past": row.round <= w.currentRound})
  let level = u16.outbreakLevel(max(0, w.currentRound))
  %*{
    "alive": {
      "standardzombie": w16.zombieCountByType(w, c16.rtStandardzombie),
      "rangedzombie": w16.zombieCountByType(w, c16.rtRangedzombie),
      "fastzombie": w16.zombieCountByType(w, c16.rtFastzombie),
      "bigzombie": w16.zombieCountByType(w, c16.rtBigzombie)
    },
    "next_wave_round": nextRound,
    "next_wave_in": (if nextRound < 0: -1 else: nextRound - w.currentRound),
    "next_wave": nextCounts,
    "schedule": schedule,
    "outbreak_level": level,
    "outbreak_multiplier_permille":
      int(u16.outbreakMultiplier(max(0, w.currentRound)) * 1000.0),
    "dens_standing": w16.densStanding(w),
    "spawned": w.stats.zombiesSpawned,
    "killed": w.stats.zombiesKilled,
    "tiebreak_round": w.maxRounds - 1,
    "rounds_to_go": max(0, w.maxRounds - 1 - w.currentRound)
  }

proc bc16Econ(w: w16.World, sideAslot: int): JsonNode =
  ## `#bc16-econ`: parts banked, income per round (printed as `x.x`), parts
  ## still on the map, dens destroyed and the bounty collected, neutrals
  ## activated (and how many were ARCHONS), and IMPASSABLE SQUARES NOW VS AT
  ## ROUND 0 — the rubble story, made visible.
  var factions = newJArray()
  var impassableStart = 0
  for v in w.map.rubble:
    if v >= c16.RubbleObstructionThresh: impassableStart += 1
  for slot in 0 .. 1:
    let team = u16.Team(if slot == sideAslot: 0 else: 1)
    let t = ord(team)
    factions.add(%*{
      "alias": aliasFor(slot),
      "parts": int(w.resources[t]),
      "income_tenths": int(e16.incomeFor(w, team) * 10.0),
      "parts_worth": w16.partsWorth(w, team),
      "collected_tenths": w.stats.partsCollectedTenths[t],
      "spent_tenths": w.stats.partsSpentTenths[t],
      "dens_destroyed": w.stats.densDestroyed[t],
      "den_bounty": w.stats.densDestroyed[t] * int(c16.DenPartReward),
      "neutrals": w.stats.neutralsActivated[t],
      "neutral_archons": w.stats.neutralArchonsActivated[t],
      "rubble_cleared_tenths": w.stats.rubbleClearedTenths[t],
      "rubble_created_tenths": w.stats.rubbleCreatedTenths[t]
    })
  %*{"factions": factions,
     "parts_on_map": int(w16.partsOnMap(w)),
     "impassable_now": w16.impassableSquares(w),
     "impassable_start": impassableStart}

proc bc16Units(w: w16.World, sideAslot: int): JsonNode =
  ## `#bc16-units`: the six player-type census with archons emphasised, UNITS
  ## STILL BUILDING shown separately (a soldier is inert for 12 turns and a
  ## viper for 30 — the single most confusing thing on screen without it),
  ## units infected, and robots lost / robots turned.
  var factions = newJArray()
  for slot in 0 .. 1:
    let team = u16.Team(if slot == sideAslot: 0 else: 1)
    let t = ord(team)
    var building = 0
    var infected = 0
    for id in w.execOrder:
      let r = w16.robotById(w, id)
      if r == nil or r.team != team: continue
      if not w16.isActive(r): building += 1
      if h16.isInfected(r.inf): infected += 1
    factions.add(%*{
      "alias": aliasFor(slot),
      "archons": w16.archonsAlive(w, team),
      "scouts": w16.robotTypeCount(w, team, c16.rtScout),
      "soldiers": w16.robotTypeCount(w, team, c16.rtSoldier),
      "guards": w16.robotTypeCount(w, team, c16.rtGuard),
      "vipers": w16.robotTypeCount(w, team, c16.rtViper),
      "turrets": w16.robotTypeCount(w, team, c16.rtTurret),
      "ttms": w16.robotTypeCount(w, team, c16.rtTtm),
      "alive": w16.robotCountOf(w, team),
      "building": building,
      "infected": infected,
      "built": w.stats.unitsBuilt[t],
      "lost": w.stats.robotsLost[t],
      "turned": w.stats.robotsTurned[t]
    })
  %*{"factions": factions}

proc bc16Siege(w: w16.World, sideAslot: int): JsonNode =
  ## `#bc16-siege`: the endcard war panel. Per faction, everything the note's
  ## §Readouts list names, and the TIEBREAK LEDGER — all four rungs with both
  ## sides' numbers and which one decided it.
  var factions = newJArray()
  for slot in 0 .. 1:
    let team = u16.Team(if slot == sideAslot: 0 else: 1)
    let t = ord(team)
    factions.add(%*{
      "alias": aliasFor(slot),
      "archons_start": w.stats.archonsStart[t],
      "archons_left": w16.archonsAlive(w, team),
      "archons_lost": w.stats.archonsLost[t],
      "units_built": w.stats.unitsBuilt[t],
      "scouts_built": w.stats.scoutsBuilt[t],
      "soldiers_built": w.stats.soldiersBuilt[t],
      "guards_built": w.stats.guardsBuilt[t],
      "vipers_built": w.stats.vipersBuilt[t],
      "turrets_built": w.stats.turretsBuilt[t],
      "dens_destroyed": w.stats.densDestroyed[t],
      "neutrals_activated": w.stats.neutralsActivated[t],
      "neutral_archons_activated": w.stats.neutralArchonsActivated[t],
      "infections_suffered": w.stats.infectionsSuffered[t],
      "infections_inflicted": w.stats.infectionsInflicted[t],
      "robots_turned": w.stats.robotsTurned[t],
      "enemy_damage_dealt": w.stats.enemyDamageDealt[t],
      "enemy_damage_taken": w.stats.enemyDamageTaken[t],
      "zombie_damage_dealt": w.stats.zombieDamageDealt[t],
      "zombie_damage_taken": w.stats.zombieDamageTaken[t],
      "repairs": w.stats.repairs[t],
      "hp_repaired": w.stats.hpRepaired[t],
      "rubble_cleared_tenths": w.stats.rubbleClearedTenths[t],
      "rubble_created_tenths": w.stats.rubbleCreatedTenths[t],
      "parts_collected_tenths": w.stats.partsCollectedTenths[t],
      "parts_end": int(w.resources[t]),
      "parts_worth_end": w16.partsWorth(w, team)
    })
  let aArchons = w16.archonsAlive(w, u16.teamA)
  let bArchons = w16.archonsAlive(w, u16.teamB)
  %*{
    "factions": factions,
    "ladder": [
      {"rung": "more_archons", "a": aArchons, "b": bArchons},
      {"rung": "more_archon_health",
       "a": int(w16.archonHealthTotal(w, u16.teamA) * 10.0),
       "b": int(w16.archonHealthTotal(w, u16.teamB) * 10.0)},
      {"rung": "more_parts_net_worth",
       "a": w16.partsWorth(w, u16.teamA), "b": w16.partsWorth(w, u16.teamB)},
      {"rung": "highest_id",
       "a": w16.highestArchonId(w, u16.teamA),
       "b": w16.highestArchonId(w, u16.teamB)}
    ],
    "decided_by": (if w.tiebreakRung > 0:
                     $u16.Domination(w.tiebreakRung)
                   else: $w.domination)
  }

proc bc16ChromeJson*(
  doc: ReplayDoc, w: w16.World, view: ViewerState,
  frame, totalFrames, gameIndex, sideAslot: int,
  beats: JsonNode, gameChips: JsonNode, ended: bool
): string =
  ## One frame of bc16 chrome. `t` / `st` / `mx` / `mt` are the GENERIC
  ## timeline keys `chrome_common.js` reads, unchanged, so the clock, the
  ## transport and the scrubber are driven by the starter's own code; the
  ## `bc16_*` keys are what the APPENDED bc16 game block draws.
  let phase = if ended: "gameover" else: "playing"
  let points = r16.gamePoints(w)
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
    "year": "bc16",
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
    "bc16_archons": bc16Archons(w, sideAslot),
    "bc16_horde": bc16Horde(w),
    "bc16_econ": bc16Econ(w, sideAslot),
    "bc16_units": bc16Units(w, sideAslot),
    "bc16_siege": bc16Siege(w, sideAslot),
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
  of yBc24:
    bc24ChromeJson(doc, s.w24, view, frame, totalFrames, gameIndex, sideAslot,
      beats, gameChips, ended)
  of yBc25:
    bc25ChromeJson(doc, s.w25, view, frame, totalFrames, gameIndex, sideAslot,
      beats, gameChips, ended)
  of yBc23:
    bc23ChromeJson(doc, s.w23, view, frame, totalFrames, gameIndex, sideAslot,
      beats, gameChips, ended)
  of yBc22:
    bc22ChromeJson(doc, s.w22, view, frame, totalFrames, gameIndex, sideAslot,
      beats, gameChips, ended)
  of yBc16:
    bc16ChromeJson(doc, s.w16, view, frame, totalFrames, gameIndex, sideAslot,
      beats, gameChips, ended)
