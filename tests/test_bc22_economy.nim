## Mining, the two lead increases and their ORDER, and the laboratory curve.
##
## §Tests item 3. The rule that decides this year's whole economy is here: the
## map adds +5 every 20 rounds **only to a square whose value is `> 0`**, so a
## square mined to zero is dead for the rest of the game.
##
## The laboratory rate is the year's ONE transcendental and its domain is
## finite, so the committed table is compared against a fresh `fdlibmExp`
## regeneration for all 3 x 177 pairs — which is what keeps the committed file
## honest without putting an `exp` on the hot path.

import std/[json, os, strutils]
import harness
import bc22_fixture
import battlecode/fdlibm

let tables = parseJson(readFile(dataRoot() / "bc22" / "tables.json"))

# --- mining -----------------------------------------------------------------
block:
  var w = bare(lead = @[(l: loc(10, 10), amount: 3), (l: loc(11, 11), amount: 3),
                        (l: loc(13, 10), amount: 3)])
  let m = w.place(teamA, rtMiner, loc(10, 10))
  check("a miner mines its OWN square", w.canMineLead(m, loc(10, 10)))
  check("and a DIAGONAL neighbour at r2 = 2", w.canMineLead(m, loc(11, 11)))
  check("but not a square three away", not w.canMineLead(m, loc(13, 10)))
  let before = w.teamLead(teamA)
  w.doMineLead(m, loc(11, 11))
  checkEq("one unit moves to the reserve", w.teamLead(teamA) - before, 1)
  checkEq("and off the square", w.getLead(loc(11, 11)), 2)
  w.setLead(loc(10, 10), 0)
  check("an empty square cannot be mined", not w.canMineLead(m, loc(10, 10)))

block:
  var w = bare()
  w.setGold(loc(10, 10), 2)
  let m = w.place(teamA, rtMiner, loc(10, 10))
  let before = w.teamGold(teamA)
  w.doMineGold(m, loc(10, 10))
  checkEq("gold mines one unit at a time", w.teamGold(teamA) - before, 1)
  check("and a non-miner cannot mine at all",
    not canMineType(rtSoldier))

# --- the two increases, and their order -------------------------------------
block:
  var w = bare(lead = @[(l: loc(5, 5), amount: 4), (l: loc(6, 5), amount: 0)])
  let before = [w.teamLead(teamA), w.teamLead(teamB)]
  w.addPassiveLead()
  checkEq("+2 to A", w.teamLead(teamA) - before[0], 2)
  checkEq("+2 to B", w.teamLead(teamB) - before[1], 2)

block:
  var w = bare(lead = @[(l: loc(5, 5), amount: 4)])
  w.currentRound = 19
  w.regenerateMapLead()
  checkEq("no regeneration off a multiple of twenty", w.getLead(loc(5, 5)), 4)
  w.currentRound = 20
  w.regenerateMapLead()
  checkEq("and +5 on one", w.getLead(loc(5, 5)), 9)

block:
  ## THE NAMED REGRESSION: a square taken to ZERO never recovers. Measured on
  ## the real engine, the example-bot mirror ran the whole `charge` map to zero
  ## lead at round 934 — which is what `mine_floor` exists to prevent.
  var w = bare(lead = @[(l: loc(5, 5), amount: 1)])
  let m = w.place(teamA, rtMiner, loc(5, 5))
  w.doMineLead(m, loc(5, 5))
  checkEq("the square is at zero", w.getLead(loc(5, 5)), 0)
  for round in 1 .. 200:
    w.currentRound = round
    w.regenerateMapLead()
  checkEq("and two hundred rounds of regeneration leave it dead",
    w.getLead(loc(5, 5)), 0)
  checkEq("the faction is charged one mined-dry square",
    w.stats.squaresMinedDry[0], 1)

block:
  ## The ORDERING test: the passive +2 lands BEFORE the anomaly and the map +5
  ## AFTER it, asserted on a round where an ABYSS and a multiple of 20 coincide.
  var w = bare(lead = @[(l: loc(5, 5), amount: 100)],
               anomalies = @[(round: 20, kind: anAbyss)])
  w.addLead(teamA, 98)      ## 200 + 98 = 298
  w.currentRound = 20
  w.addPassiveLead()        ## 300 exactly, so the abyss takes 30 not 29
  checkEq("the reserve includes this round's +2", w.teamLead(teamA), 300)
  let fired = w.runScheduledAnomaly()
  check("the abyss fired", fired.fired)
  checkEq("and ate 10 % of a reserve that ALREADY had the +2",
    w.teamLead(teamA), 270)
  checkEq("the square lost 10 of its 100", w.getLead(loc(5, 5)), 90)
  w.regenerateMapLead()
  checkEq("and the +5 lands AFTER, on the reduced square",
    w.getLead(loc(5, 5)), 95)

# --- the laboratory curve ----------------------------------------------------
block:
  var w = bare()
  w.loadTransmuteTable()
  let row = tables["transmute_rate"]
  var mismatches = 0
  for level in 1 .. 3:
    for n in 0 .. TransmuteMaxFriends:
      if w.transmutationRateFor(level, n) != row[$level][n].getInt():
        inc mismatches
  checkEq("the committed table is the JVM's, all 3 x 177 pairs",
    mismatches, 0)
  var fdlibmMismatches = 0
  for level in 1 .. 3:
    for n in 0 .. TransmuteMaxFriends:
      if computeTransmuteRate(level, n) != row[$level][n].getInt():
        inc fdlibmMismatches
  checkEq("and fdlibmExp regenerates it exactly", fdlibmMismatches, 0)
  ## The measured spot values from the design note.
  checkEq("n=0 is two lead a gold", w.transmutationRateFor(1, 0), 2)
  checkEq("n=3", w.transmutationRateFor(1, 3), 3)
  checkEq("n=6", w.transmutationRateFor(1, 6), 4)
  checkEq("n=10", w.transmutationRateFor(1, 10), 5)
  checkEq("n=13", w.transmutationRateFor(1, 13), 6)
  checkEq("n=21", w.transmutationRateFor(1, 21), 8)
  checkEq("n=30", w.transmutationRateFor(1, 30), 10)
  checkEq("n=40 is eleven", w.transmutationRateFor(1, 40), 11)
  check("and the curve never decreases in n",
    (block:
      var ok = true
      for level in 1 .. 3:
        for n in 1 .. TransmuteMaxFriends:
          if w.transmutationRateFor(level, n) <
             w.transmutationRateFor(level, n - 1): ok = false
      ok))

block:
  ## A transmute in the world: the lab's own cooldown, the lead off the
  ## reserve, and EXACTLY ONE gold on.
  var w = bare()
  w.loadTransmuteTable()
  let lab = w.placeLive(teamA, rtLaboratory, loc(10, 10))
  w.addLead(teamA, 100)
  let rate = w.transmutationRate(lab)
  checkEq("a lonely laboratory charges two lead a gold", rate, 2)
  let leadBefore = w.teamLead(teamA)
  let goldBefore = w.teamGold(teamA)
  w.doTransmute(lab)
  checkEq("one gold", w.teamGold(teamA) - goldBefore, 1)
  checkEq("for `rate` lead", leadBefore - w.teamLead(teamA), rate)
  checkEq("and ten cooldown", lab.actionCooldown, 10)

block:
  ## `n` is recomputed ON THE SPOT and counts friendly robots EXCLUDING itself
  ## inside r2 <= 53.
  var w = bare()
  w.loadTransmuteTable()
  let lab = w.placeLive(teamA, rtLaboratory, loc(15, 15))
  for i in 0 ..< 10:
    discard w.place(teamA, rtMiner, loc(10 + i, 20))
  let crowded = w.transmutationRate(lab)
  check("a crowded laboratory charges more", crowded > 2)
  checkEq("and the count is the friendly robots it can see, minus itself",
    crowded, w.transmutationRateFor(1, w.updateNumVisibleFriendlyRobots(lab)))

finish("test_bc22_economy")
