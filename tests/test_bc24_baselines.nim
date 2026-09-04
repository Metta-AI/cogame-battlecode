## The bc24 baselines: bounded, LEGAL orders.
##
## (a) both `PLAYER_SCRIPTED` resolutions produce a sheet that passes the SAME
##     `validate` the LLM path uses;
## (b) in played games EVERY action either chassis emits is legal for the
##     acting duck at the moment it is emitted -- the sim counts every `do*`
##     whose own `can*` refused it, and this shard asserts that count is ZERO
##     -- and NO DUCK EVER EXCEEDS ITS 2 500 DecisionOps;
## (c) `examplefuncsplayer24` ACTS (it spawns, moves and attacks after round
##     200) but is NOT required to survive: it is the deliberate weak floor and
##     the parity oracle's other side, and it may not gain behaviour;
## (d) `gone-sharkin` beats `examplefuncsplayer24` on three small maps under
##     both side assignments, 6 of 6.

import std/strutils
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc24/[maps, rules, world]
import battlecode/years/dispatch

const GateMaps = ["Yinyang", "BreadPudding", "Occulus"]
  ## The three `small`-pool maps whose halves are LAND-CONNECTED after the dam
  ## falls. `Rivers` and `Tunnels` are separated by water as well as by the
  ## dam -- a real property of the shipped maps, confirmed against the Java
  ## engine -- and `DefaultSmall`'s 133-tile dam plus wall belt makes flag
  ## contact rare; both are covered by `tests/test_bc24_survival.nim` under the
  ## clauses that can hold there.

# --- (a) both resolutions parse ---------------------------------------------
block:
  checkEq("PLAYER_SCRIPTED=awu plays gone-sharkin on bc24",
    $baselineFor("bc24", "awu"), "gone-sharkin")
  checkEq("and so does anything unrecognised",
    $baselineFor("bc24", "whatever"), "gone-sharkin")
  checkEq("PLAYER_SCRIPTED=scaffold plays examplefuncsplayer24",
    $baselineFor("bc24", "scaffold"), "examplefuncsplayer24")
  checkEq("as does the long name", $baselineFor("bc24", "examplefuncsplayer24"),
    "examplefuncsplayer24")
  checkEq("as does `example`", $baselineFor("bc24", "example"),
    "examplefuncsplayer24")
  checkEq("a seat that says nothing plays the STRONG doctrine",
    $defaultBaselineFor("bc24"), "gone-sharkin")
  checkEq("and the year-neutral chassis names match",
    [$baselineChassis(blGoneSharkin), $baselineChassis(blExamplefuncsplayer24)],
    ["gone-sharkin", "examplefuncsplayer24"])

block:
  for kind in [blGoneSharkin, blExamplefuncsplayer24]:
    let s = baselineSheet("bc24", kind)
    checkEq($kind & ": the reply goes through the same validate",
      s.year, YearBc24)
    checkEq($kind & ": and needs no repair", s.defaultsApplied.len, 0)
    checkEq($kind & ": with no unknown fields", s.unknownFields.len, 0)
    checkEq($kind & ": it is the all-defaults sheet",
      $s.doctrine24, $defaultDoctrine24())
    check($kind & ": with a motto", s.motto.len > 0)
  checkEq("neither reply carries a `chassis` key (D1)",
    baselineReply(blGoneSharkin).contains("chassis"), false)

# --- (b), (c) and (d): played games -----------------------------------------
let strong = baselineSheet("bc24", blGoneSharkin)
let weak = baselineSheet("bc24", blExamplefuncsplayer24)

var wins = 0
var games = 0
var scaffoldSpawns = 0
var scaffoldMoves = 0
var scaffoldAttacks = 0
var refused = 0
var opsPeak = 0

for name in GateMaps:
  for sideAslot in 0 .. 1:
    let (w, outcome) = playGame(loadMap(name), [strong, weak],
      [ckGoneSharkin, ckExamplefuncsplayer24], 0, sideAslot, 2000, 0)
    games += 1
    if outcome.winnerSlot == 0: wins += 1
    refused += w.refusedActions
    opsPeak = max(opsPeak, w.opsUsedPeak)
    ## Seat 1 is the scaffold; which TEAM that is alternates with `sideAslot`.
    let weakTeam = if sideAslot == 0: 1 else: 0
    scaffoldSpawns += w.stats.ducksSpawned[weakTeam]
    scaffoldMoves += w.stats.crumbsCollected[weakTeam]
    scaffoldAttacks += w.stats.attacks[weakTeam]

checkEq("(b) not one action was refused by its own precondition, over six " &
  "whole games", refused, 0)
check("(b) and no duck ever exceeded its 2 500 DecisionOps budget",
  opsPeak <= DecisionOps)
check("(b) the budget really was exercised", opsPeak > 0)

check("(c) examplefuncsplayer24 SPAWNS", scaffoldSpawns >= 6)
check("(c) it walks crumbs off the floor", scaffoldMoves > 6 * 400)
check("(c) and it attacks after round 200", scaffoldAttacks >= 6)

checkEq("(d) gone-sharkin beats examplefuncsplayer24, six of six", wins, games)
checkEq("and there really were six games", games, 6)

finish("bc24 baselines")
