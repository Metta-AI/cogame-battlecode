## `ANNIHILATION` mid-turn, the double elimination, the Singularity ladder, and
## the fact that `resign()` is unreachable here.
##
## §Tests item 10.

import harness
import bc22_fixture

block:
  ## `ANNIHILATION` fires MID-TURN inside `destroyRobot`, and `running` is only
  ## cleared at step 4g — so every robot after the killer in the exec order
  ## still takes its turn.
  var w = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                           (id: 3, x: 25, y: 5, team: 2)])
  let victim = w.robotsById[3]
  w.destroyRobot(victim.id)
  check("a winner is set the instant the last archon dies", w.hasWinner)
  checkEq("by annihilation", w.domination, dfAnnihilated)
  checkEq("and it is the other team", w.winner, teamA)
  check("but the round is still RUNNING", w.running)

block:
  ## BOTH teams annihilated in one round: outside a fury the SECOND death
  ## simply overwrites the winner, so the ordering of the two deaths inside one
  ## round is load-bearing.
  var w = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                           (id: 3, x: 25, y: 5, team: 2)])
  w.destroyRobot(3)
  checkEq("A wins on B's death", w.winner, teamA)
  w.destroyRobot(2)
  checkEq("and then B wins on A's", w.winner, teamB)
  checkEq("still by annihilation", w.domination, dfAnnihilated)

block:
  ## Inside a FURY it is different: `addHealth(..., false)` means
  ## `destroyRobot` never fires the rung, and `causeFuryUpdate`'s own check
  ## goes straight to the gold/lead/coin ladder, SKIPPING `MORE_ARCHONS`. That
  ## is the ONLY way a net-worth rung fires before round 2000.
  var w = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                           (id: 3, x: 25, y: 5, team: 2)],
               anomalies = @[(round: 2, kind: anFury)])
  for _, r in w.robotsById:
    if r.kind == rtArchon: r.health = 10
  w.addLead(teamB, 500)
  w.currentRound = 2
  discard w.runScheduledAnomaly()
  check("a winner is set", w.hasWinner)
  checkEq("gold is tied at 0-0 so the LEAD rung decides",
    w.domination, dfMoreLeadNetWorth)
  checkEq("and the richer team wins", w.winner, teamB)

block:
  ## And when everything is tied inside a fury, the coin flip — seeded from the
  ## world RNG, not from the wall clock (D3).
  var w = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                           (id: 3, x: 25, y: 5, team: 2)],
               anomalies = @[(round: 2, kind: anFury)])
  for _, r in w.robotsById:
    if r.kind == rtArchon: r.health = 10
  w.currentRound = 2
  discard w.runScheduledAnomaly()
  check("a winner is set", w.hasWinner)
  checkEq("by coin flip", w.domination, dfCoinFlip)
  ## Reproducible: the same world twice gives the same flip.
  var w2 = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                            (id: 3, x: 25, y: 5, team: 2)],
                anomalies = @[(round: 2, kind: anFury)])
  for _, r in w2.robotsById:
    if r.kind == rtArchon: r.health = 10
  w2.currentRound = 2
  discard w2.runScheduledAnomaly()
  checkEq("and it is REPRODUCIBLE, unlike Math.random()", w2.winner, w.winner)

# --- the Singularity ladder --------------------------------------------------
block:
  var w = bare()
  discard w.place(teamA, rtArchon, loc(8, 8))
  w.currentRound = 2000
  w.checkEndOfMatch()
  check("round 2000 ends the game", not w.running)
  checkEq("rung one: more archons", w.domination, dfMoreArchons)
  checkEq("and A has two to B's one", w.winner, teamA)

block:
  var w = bare()
  w.addGold(teamA, 5)
  w.currentRound = 2000
  w.checkEndOfMatch()
  checkEq("archons level, so rung two: gold net worth",
    w.domination, dfMoreGoldNetWorth)
  checkEq("A wins", w.winner, teamA)

block:
  var w = bare()
  w.addLead(teamB, 5)
  w.currentRound = 2000
  w.checkEndOfMatch()
  checkEq("archons and gold level, so rung three: lead net worth",
    w.domination, dfMoreLeadNetWorth)
  checkEq("B wins", w.winner, teamB)

block:
  var w = bare()
  w.currentRound = 2000
  w.checkEndOfMatch()
  checkEq("everything level, so the coin flip", w.domination, dfCoinFlip)

block:
  ## NET WORTH is the reserve PLUS `get*Worth(level)` over every live robot, so
  ## a level-3 archon is worth 300 Pb and 180 Au while it lives.
  var w = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                           (id: 3, x: 25, y: 5, team: 2)])
  let arch = w.robotsById[2]
  arch.level = 3
  checkEq("a level-3 archon's lead worth", leadWorth(rtArchon, 3), 300)
  checkEq("and its gold worth", goldWorth(rtArchon, 3), 180)
  checkEq("A's lead net worth is its reserve plus that",
    w.leadNetWorth(teamA), 200 + 300)
  checkEq("A's gold net worth likewise", w.goldNetWorth(teamA), 0 + 180)
  checkEq("B's is a level-1 archon", w.goldNetWorth(teamB), 100)

block:
  ## A faction with ONE archon and no other robot plays on to round 2000 and
  ## keeps earning 2 Pb a round: losing every DROID ends nothing in this year.
  var w = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                           (id: 3, x: 25, y: 5, team: 2)])
  var sides = newSides22(defaultSheets(), 0)
  let chassis = [ckWololo, ckWololo]
  for round in 1 .. 50:
    runRound(w, sides, chassis)
  check("fifty rounds in and the game is still running", w.running)
  check("and the +2 a round is real income, spent or banked",
    w.teamLead(teamA) + w.stats.unitsBuilt[0] * 50 > 200)
  var idle = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                              (id: 3, x: 25, y: 5, team: 2)])
  for round in 1 .. 50:
    inc idle.currentRound
    idle.addPassiveLead()
  checkEq("an idle faction banks exactly 2 a round", idle.teamLead(teamA),
    200 + 100)

block:
  ## `resign()` is a real engine method and is UNREACHABLE HERE: a doctrine is
  ## a JSON sheet, neither chassis calls it, and the port has no `resign` at
  ## all. The assertion is that no whole game ever ends on it — the manifest's
  ## `end_reason` enum has no `resignation` value, so an episode that somehow
  ## produced one would fail the schema.
  let (w, o) = mirror(300, "chalice")
  check("a played game's end reason is one of the six",
    o.endReason in ["annihilated", "more_archons", "more_gold_net_worth",
                    "more_lead_net_worth", "coin_flip", "abandoned"])
  check("and never a resignation", o.endReason != "resignation")
  discard w

finish("test_bc22_endladder")
