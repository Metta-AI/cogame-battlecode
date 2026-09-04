## THE KING-SURVIVAL GATE (r2-D2).
##
## Round 1 of league bc26 was won by a clan that stood still: the awu chassis
## on the other side lost every king by round 1078 on one map and 362 on
## another, so an idle scaffold doctrine took two games on survival alone.
## A clan that plays the game must not hand the match to a clan that does not.
##
## awu-default against awu-default, on the five parity maps, 2000 rounds:
##
##   * NO game may lose a clan its LAST king before round 1500 — whatever the
##     end reason says. A mutual wipe records `round_limit`, so the gate reads
##     the king counts round by round rather than trusting the label;
##   * at least 4 of the 5 must reach round 2000 or end on points
##     (`cats_cleared` / `round_limit`).
##
## Pre-fix (45f4ead, GV03) this gate failed on both counts:
##
##   map            end            round   first clan wiped out
##   DefaultSmall   kings_destroyed 1012   1012
##   closeup        round_limit     1310   1310  (both — the buried kings)
##   toomuchcheese  kings_destroyed  436    436
##   cheesefarm     cats_cleared     421    never
##   dirtfulcat     kings_destroyed  314    314
##
## i.e. 4 of 5 games lost a clan before round 1500 and only 2 of 5 ended on
## points — 8 of these 11 checks failed. Every one of those kings starved: the
## dying kings took 590 of their 600 hp from an empty bank and 0-140 from a
## cat.
##
## After the D2 series all five games keep both clans crowned, the worst cat
## damage any king takes is 20 hp, and no clan's bank ever empties:
##
##   DefaultSmall 2000 round_limit | closeup 1484 cats_cleared
##   toomuchcheese 2000 round_limit | cheesefarm 1902 cats_cleared
##   dirtfulcat 702 cats_cleared

import std/strutils
import harness
import battlecode/[baselines, sheet, sim_types]
import battlecode/years/bc26/[maps, rules]

const
  Maps = ["DefaultSmall", "closeup", "toomuchcheese", "cheesefarm", "dirtfulcat"]
  Rounds = 2000
  WipeFloor = 1500

var onPoints = 0

for mapName in Maps:
  let sheets = [baselineSheet(blAwu), baselineSheet(blAwu)]
  var firstWipe = -1
  var wipedClan = -1
  let (w, o) = playGame(loadMap(mapName), sheets, 0, 0, Rounds, 0,
    proc (w: World, round: int) =
      if firstWipe >= 0: return
      for t in 0 .. 1:
        if w.teamInfo.numRatKings[t] == 0:
          firstWipe = round
          wipedClan = t)
  echo mapName, ": ", o.roundsPlayed, " rounds, ", o.endReason,
    ", kings ", o.kingsAlive, ", cat damage ", o.catDamage,
    ", cheese ", o.cheeseTransferred,
    (if firstWipe >= 0: ", clan " & $wipedClan & " wiped out at round " &
      $firstWipe else: ", both clans still crowned")

  check(mapName & ": no clan loses its last king before round " & $WipeFloor &
    " (" & (if firstWipe < 0: "never" else: "round " & $firstWipe) & ")",
    firstWipe < 0 or firstWipe >= WipeFloor)
  check(mapName & ": the game is not decided by an idle clan outlasting a " &
    "starved one", o.endReason != erKingsDestroyed or o.roundsPlayed >= WipeFloor)
  if o.roundsPlayed >= Rounds or
      o.endReason in {erCatsCleared, erRoundLimit}:
    inc onPoints

check("at least 4 of the 5 games reach round 2000 or end on points (" &
  $onPoints & " of " & $Maps.len & ")", onPoints >= 4)

finish("test_king_survival")
