## The four anomalies, their measured float32 truncations, and the ORDER.
##
## §Tests item 4. Every number in here was measured on the JVM against the
## released jar's own classes and is cross-checked against
## `data/bc22/tables.json`.

import std/[json, os, strutils]
import harness
import bc22_fixture

let tables = parseJson(readFile(dataRoot() / "bc22" / "tables.json"))

# --- the schedule -----------------------------------------------------------
block:
  ## ONE ENTRY IS CONSUMED PER MATCHING ROUND AND NEVER TWO. The engine calls
  ## `takeNextAnomaly` once inside `processEndOfRound`, so the property is
  ## asserted through the round loop rather than by calling the body twice.
  var w = bare(anomalies = @[(round: 5, kind: anAbyss),
                             (round: 5, kind: anCharge)])
  var sides = newSides22(defaultSheets(), 0)
  let chassis = [ckWololo, ckWololo]
  for round in 1 .. 4:
    runRound(w, sides, chassis)
  checkEq("nothing fires early", w.anomalyCursor, 0)
  let nxt = w.nextAnomaly()
  check("and the schedule is readable at all times", nxt.has)
  checkEq("naming the next entry", nxt.kind, anAbyss)
  checkEq("with its round", nxt.round, 5)
  runRound(w, sides, chassis)
  checkEq("round five consumes EXACTLY ONE", w.anomalyCursor, 1)
  runRound(w, sides, chassis)
  checkEq("and round six consumes no more, because it is not round five",
    w.anomalyCursor, 1)

# --- ABYSS ------------------------------------------------------------------
block:
  checkEq("a square holding 9 loses NOTHING", abyssGlobalTake(9), 0)
  checkEq("10 loses 1", abyssGlobalTake(10), 1)
  checkEq("25 loses 2", abyssGlobalTake(25), 2)
  checkEq("99 loses 9", abyssGlobalTake(99), 9)
  checkEq("100 loses 10", abyssGlobalTake(100), 10)
  checkEq("300 loses 30", abyssGlobalTake(300), 30)
  var mismatches = 0
  for m in 0 .. 1000:
    if abyssGlobalTake(m) != tables["abyss_global"][m].getInt():
      inc mismatches
    if abyssSageTake(m) != tables["abyss_sage"][m].getInt():
      inc mismatches
  checkEq("and the whole 0..1000 domain is the JVM's", mismatches, 0)

block:
  ## The four reserve deltas, IN THIS ORDER: A lead, B lead, A gold, B gold.
  var w = bare(lead = @[(l: loc(4, 4), amount: 9),
                        (l: loc(5, 5), amount: 25)],
               anomalies = @[(round: 3, kind: anAbyss)])
  w.setGold(loc(6, 6), 40)
  w.addLead(teamA, 55)     ## 255
  w.addGold(teamA, 25)
  w.addGold(teamB, 7)
  w.currentRound = 3
  let fired = w.runScheduledAnomaly()
  check("the abyss fired", fired.fired)
  checkEq("a nine-lead square is immune", w.getLead(loc(4, 4)), 9)
  checkEq("a 25-lead square loses two", w.getLead(loc(5, 5)), 23)
  checkEq("a 40-gold square loses four", w.getGold(loc(6, 6)), 36)
  checkEq("A's 255 lead loses 25", w.teamLead(teamA), 230)
  checkEq("B's 200 lead loses 20", w.teamLead(teamB), 180)
  checkEq("A's 25 gold loses 2", w.teamGold(teamA), 23)
  checkEq("B's 7 gold loses nothing", w.teamGold(teamB), 7)

# --- CHARGE -----------------------------------------------------------------
block:
  checkEq("19 droids: the cut is ZERO", chargeCut(19), 0)
  checkEq("20 droids: one dies", chargeCut(20), 1)
  checkEq("39", chargeCut(39), 1)
  checkEq("40", chargeCut(40), 2)
  checkEq("59", chargeCut(59), 2)
  checkEq("60", chargeCut(60), 3)
  var mismatches = 0
  for n in 0 .. 500:
    if chargeCut(n) != tables["charge_cut"][n].getInt(): inc mismatches
  checkEq("and the whole 0..500 domain is the JVM's", mismatches, 0)

block:
  ## Under twenty droids a global charge kills NOBODY, and it can never touch a
  ## building or a prototype.
  var w = bare(anomalies = @[(round: 2, kind: anCharge)])
  for i in 0 ..< 8:
    discard w.place(teamA, rtSoldier, loc(5 + i, 5))
    discard w.place(teamB, rtSoldier, loc(5 + i, 7))
  discard w.place(teamA, rtLaboratory, loc(3, 3))
  let before = w.robotsById.len
  w.currentRound = 2
  discard w.runScheduledAnomaly()
  checkEq("sixteen droids and nobody dies", w.robotsById.len, before)

block:
  var w = bare(anomalies = @[(round: 2, kind: anCharge)])
  ## Twenty-four droids: the cut is 1. The victim is the droid that sees the
  ## most friends, and the ranking is over BOTH TEAMS TOGETHER.
  for i in 0 ..< 20:
    discard w.place(teamA, rtSoldier, loc(5 + (i mod 5), 5 + (i div 5)))
  for i in 0 ..< 4:
    discard w.place(teamB, rtSoldier, loc(25, 20 + i))
  let before = w.robotsById.len
  w.currentRound = 2
  discard w.runScheduledAnomaly()
  checkEq("twenty-four droids and exactly one dies",
    before - w.robotsById.len, 1)
  checkEq("and the CLUMPED side donated the victim",
    w.stats.anomalyLossesCharge[0], 1)
  checkEq("the spread one lost none", w.stats.anomalyLossesCharge[1], 0)

block:
  ## The sage charge: 22 % of MAX health on every ENEMY droid within r2 <= 25.
  var w = bare()
  let sage = w.place(teamA, rtSage, loc(15, 15))
  let enemy = w.place(teamB, rtSoldier, loc(16, 16))
  let friend = w.place(teamA, rtSoldier, loc(14, 14))
  let building = w.placeLive(teamB, rtWatchtower, loc(17, 15))
  w.doEnvision(sage, anCharge)
  checkEq("the enemy droid loses 22 % of 50, truncated",
    enemy.health, 50 + chargeSageDelta(50))
  checkEq("which is eleven", 50 - enemy.health, 11)
  checkEq("a friendly droid is untouched", friend.health, 50)
  checkEq("and a building is untouched", building.health,
    maxHealthOf(rtWatchtower, 1))

# --- FURY -------------------------------------------------------------------
block:
  checkEq("a level-1 watchtower loses 7, not 8", furyGlobalDelta(150), -7)
  checkEq("a level-2 watchtower loses 13", furyGlobalDelta(270), -13)
  checkEq("a level-3 archon loses 97", furyGlobalDelta(1944), -97)
  checkEq("a level-1 archon loses 30", furyGlobalDelta(600), -30)
  checkEq("a level-1 laboratory loses 5", furyGlobalDelta(100), -5)
  for key, row in tables["fury_damage"]:
    let hp = parseInt(key)
    checkEq("global fury on " & key, furyGlobalDelta(hp), row[0].getInt())
    checkEq("sage fury on " & key, furySageDelta(hp), row[1].getInt())

block:
  ## FURY spares PORTABLE and PROTOTYPE entirely. This is the year's largest
  ## unexploited play.
  var w = bare(anomalies = @[(round: 2, kind: anFury)])
  let turret = w.placeLive(teamA, rtWatchtower, loc(5, 5))
  let portable = w.placeLive(teamA, rtWatchtower, loc(7, 5))
  portable.mode = rmPortable
  let proto = w.place(teamA, rtWatchtower, loc(9, 5))
  let droid = w.place(teamA, rtSoldier, loc(11, 5))
  w.currentRound = 2
  discard w.runScheduledAnomaly()
  checkEq("a TURRET loses seven", turret.health, 150 - 7)
  checkEq("a PORTABLE loses nothing", portable.health, 150)
  checkEq("a PROTOTYPE loses nothing", proto.health, 120)
  checkEq("and a droid is not a building at all", droid.health, 50)

block:
  ## Divergence 7: a fury that eliminates BOTH teams' archons skips
  ## `MORE_ARCHONS` and goes straight to the gold rung. It is the only path by
  ## which a net-worth rung can fire before round 2000.
  var w = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                           (id: 3, x: 25, y: 5, team: 2)],
               anomalies = @[(round: 2, kind: anFury)])
  for _, r in w.robotsById:
    if r.kind == rtArchon: r.health = 20
  w.addGold(teamA, 40)
  w.currentRound = 2
  discard w.runScheduledAnomaly()
  check("a winner was set", w.hasWinner)
  checkEq("on the GOLD rung, not on archons", w.domination, dfMoreGoldNetWorth)
  checkEq("and it is the richer team", w.winner, teamA)

# --- VORTEX -----------------------------------------------------------------
block:
  ## VERTICAL: flip vertically, NO draw.
  var w = bare(rubble = @[(l: loc(3, 0), amount: 40)],
               anomalies = @[(round: 2, kind: anVortex)],
               symmetry = symVertical)
  let leadBefore = w.getLead(loc(3, 0))
  let stateBefore = w.rand.seed
  w.currentRound = 2
  discard w.runScheduledAnomaly()
  checkEq("the rubble moved to the mirrored row",
    w.getRubble(loc(3, TestHeight - 1)), 40)
  checkEq("and left the original", w.getRubble(loc(3, 0)), 0)
  checkEq("the lead array is untouched", w.getLead(loc(3, 0)), leadBefore)
  checkEq("and NO draw was taken", w.rand.seed, stateBefore)

block:
  ## HORIZONTAL: flip horizontally, NO draw.
  var w = bare(rubble = @[(l: loc(0, 4), amount: 40)],
               anomalies = @[(round: 2, kind: anVortex)],
               symmetry = symHorizontal)
  let stateBefore = w.rand.seed
  w.currentRound = 2
  discard w.runScheduledAnomaly()
  checkEq("the rubble moved to the mirrored column",
    w.getRubble(loc(TestWidth - 1, 4)), 40)
  checkEq("and NO draw was taken", w.rand.seed, stateBefore)

block:
  ## ROTATIONAL on a SQUARE map: `rand.nextInt(3)`, so all three arms are
  ## reachable and a draw IS taken.
  var w = bare(rubble = @[(l: loc(1, 2), amount: 40)],
               anomalies = @[(round: 2, kind: anVortex)],
               symmetry = symRotation)
  let stateBefore = w.rand.seed
  w.currentRound = 2
  discard w.runScheduledAnomaly()
  check("a draw WAS taken", w.rand.seed != stateBefore)
  var total = 0
  for v in w.rubble: total += v
  checkEq("and the rubble is only PERMUTED, never created", total, 40)

block:
  ## A sage can envision ABYSS, CHARGE and FURY — and NOT a VORTEX.
  var w = bare()
  let sage = w.place(teamA, rtSage, loc(15, 15))
  check("abyss is envisionable", w.canEnvision(sage, anAbyss))
  check("charge is envisionable", w.canEnvision(sage, anCharge))
  check("fury is envisionable", w.canEnvision(sage, anFury))
  check("VORTEX IS NOT", not w.canEnvision(sage, anVortex))
  let soldier = w.place(teamA, rtSoldier, loc(10, 10))
  check("and only a sage envisions at all",
    not w.canEnvision(soldier, anAbyss))

block:
  ## The sage abyss takes 99 % of the metal on every square within r2 <= 25.
  var w = bare(lead = @[(l: loc(15, 16), amount: 100),
                        (l: loc(15, 25), amount: 100)])
  let sage = w.place(teamA, rtSage, loc(15, 15))
  w.doEnvision(sage, anAbyss)
  checkEq("a square in range keeps one per cent", w.getLead(loc(15, 16)), 1)
  checkEq("a square ten away is untouched", w.getLead(loc(15, 25)), 100)

block:
  ## The sage fury takes 10 % of a TURRET's max health within r2 <= 25.
  var w = bare()
  let sage = w.place(teamA, rtSage, loc(15, 15))
  let turret = w.placeLive(teamB, rtWatchtower, loc(16, 16))
  w.doEnvision(sage, anFury)
  checkEq("ten per cent of 150, truncated, is 15", turret.health, 135)

finish("test_bc22_anomaly")
