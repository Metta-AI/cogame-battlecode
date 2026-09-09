## Shard 8 of the note's list — **the parts economy**.
##
## `PARTS_INITIAL_AMOUNT = 300.0` credited ONCE PER TEAM by the constructor;
## income `max(0.0, 2.0 - 0.01 * robotCount)` added **A then B** at the end of
## every round, EXACTLY ZERO at 200 robots; `takeParts` zeroing the square and
## returning the WHOLE amount, called ONLY for an ARCHON spawning on or moving
## onto a parts square and for NO OTHER TYPE; the 200-part den bounty paid to
## the attacker's team ONLY when the den's health reaches `<= 0`; and
## `partsWorth` = `int(parts) + sum(partCost)` over live robots, computed in
## ONE exec-order pass exactly as rung 3 does.

import harness
import bc16_fixture

# --- 300 per team, once, by the constructor -------------------------------
block:
  let w = bare()
  checkEq("PARTS_INITIAL_AMOUNT is 300", PartsInitialAmount, 300.0)
  checkEq("team A starts with 300", w.teamParts(teamA), 300.0)
  checkEq("team B starts with 300", w.teamParts(teamB), 300.0)
  checkEq("and it is PER TEAM, not per archon — four archons a side is " &
    "still 300", bare(robots = @[
      (x: 3, y: 3, kind: ord(rtArchon), team: ord(teamA)),
      (x: 3, y: 5, kind: ord(rtArchon), team: ord(teamA)),
      (x: 26, y: 3, kind: ord(rtArchon), team: ord(teamB)),
      (x: 26, y: 5, kind: ord(rtArchon), team: ord(teamB))
    ]).teamParts(teamA), 300.0)
  checkEq("the horde has none", w.teamParts(teamZombie), 0.0)

# --- the income curve ------------------------------------------------------
block:
  let w = bare(robots = @[])
  checkEq("ARCHON_PART_INCOME is 2.0", ArchonPartIncome, 2.0)
  checkEq("PART_INCOME_UNIT_PENALTY is 0.01", PartIncomeUnitPenalty, 0.01)
  checkEq("with one robot the income is 1.99", w.incomeFor(teamA), 1.99)
  let before = w.teamParts(teamA)
  w.addPartsIncome()
  checkEq("and the stockpile really gains it", w.teamParts(teamA),
    before + 1.99)
  checkEq("and the tenths counter records it",
    w.stats.partsIncomeTenths[0], 19)

block:
  ## The curve reaches EXACTLY ZERO at 200 robots and never goes negative.
  ## This is the whole reason a 2016 army has a natural ceiling.
  let w = bare(robots = @[])
  for i in 0 ..< 199:
    discard w.put(rtSoldier, w.indexToLoc(i + 60), teamA)
  checkEq("a team of 200 robots", w.robotCountOf(teamA), 200)
  checkEq("earns EXACTLY zero", w.incomeFor(teamA), 0.0)
  discard w.put(rtSoldier, w.indexToLoc(300), teamA)
  checkEq("and 201 earns zero too, never negative", w.incomeFor(teamA), 0.0)

block:
  ## The engine's order: A's stockpile FIRST, then B's. Unobservable today
  ## (the two are independent) and kept anyway.
  let w = bare()
  discard w.put(rtSoldier, loc(10, 10), teamB)
  discard w.put(rtSoldier, loc(10, 12), teamB)
  w.addPartsIncome()
  checkEq("A has one robot and gains 1.99", w.teamParts(teamA), 301.99)
  checkEq("B has three and gains 1.97", w.teamParts(teamB), 301.97)

# --- takeParts: whole square, ARCHON only ---------------------------------
block:
  let w = bare(parts = @[(loc(4, 15), 137.5), (loc(10, 10), 60.0)])
  let a = w.at(3, 15)
  let before = w.teamParts(teamA)
  discard w.doMove(a, dEast)
  checkEq("an archon moving onto a parts square takes the WHOLE amount",
    w.teamParts(teamA), before + 137.5)
  checkEq("and the square is zeroed", w.getParts(loc(4, 15)), 0.0)
  checkEq("and the tenths counter records it",
    w.stats.partsCollectedTenths[0], 1375)
  checkEq("and the walk counter", w.stats.archonPartsWalks[0], 1)
  ## And NO OTHER TYPE collects.
  let s = w.put(rtSoldier, loc(9, 10), teamA)
  let mid = w.teamParts(teamA)
  discard w.doMove(s, dEast)
  checkEq("a SOLDIER walking onto 60 parts collects NOTHING",
    w.teamParts(teamA), mid)
  checkEq("and the square still holds them", w.getParts(loc(10, 10)), 60.0)

block:
  ## An archon SPAWNING on a parts square takes them too — the other of the
  ## two call sites.
  let w = bare(parts = @[(loc(3, 15), 42.0)])
  checkEq("the spawning archon took the square", w.getParts(loc(3, 15)), 0.0)
  checkEq("and its team is 342", w.teamParts(teamA), 342.0)

block:
  ## An ACTIVATED neutral archon spawns onto its own square and collects it,
  ## because `spawnRobot` runs the same path.
  let w = bare(parts = @[(loc(4, 15), 25.0)])
  let a = w.at(3, 15)
  discard w.put(rtArchon, loc(4, 15), teamNeutral)
  checkEq("a NEUTRAL archon spawning does NOT collect", w.getParts(loc(4, 15)),
    25.0)
  discard w.doActivate(a, loc(4, 15))
  checkEq("but the one that replaces it on OUR team does",
    w.getParts(loc(4, 15)), 0.0)

# --- the den bounty --------------------------------------------------------
block:
  let w = bare(robots = @[
    (x: 3, y: 15, kind: ord(rtArchon), team: ord(teamA)),
    (x: 26, y: 15, kind: ord(rtArchon), team: ord(teamB)),
    (x: 15, y: 15, kind: ord(rtZombieden), team: ord(teamZombie))],
    dens = @[DenSpec(x: 15, y: 15, spawnDir: 0, chirality: 1)])
  let d = w.at(15, 15)
  checkEq("DEN_PART_REWARD is 200", DenPartReward, 200.0)
  checkEq("a den has 2000 HP", d.health, 2000.0)
  let t = w.put(rtTurret, loc(15, 21), teamA)
  let before = w.teamParts(teamA)
  discard w.doAttack(t, d.loc)
  checkEq("a hit that does NOT kill it pays nothing", w.teamParts(teamA),
    before)
  checkEq("but it counts as den damage", w.stats.denDamageDealt[0], 13)
  d.health = 5.0
  t.d.weapon = 0.0
  discard w.doAttack(t, d.loc)
  checkEq("the killing blow pays exactly 200", w.teamParts(teamA),
    before + 200.0)
  checkEq("and the counter ticks", w.stats.densDestroyed[0], 1)
  check("and the den is gone", w.getRobot(loc(15, 15)) == nil)

# --- partsWorth and the rung-3 accumulator --------------------------------
block:
  ## `partsWorth` = `int(parts) + sum(partCost)` over that team's LIVE robots.
  ## An ARCHON's partCost is 0 (it cannot be built), and so is a zombie's and
  ## a den's.
  let w = bare()
  checkEq("an archon costs 0 parts", rtArchon.partCost(), 0)
  checkEq("a zombie den costs 0", rtZombieden.partCost(), 0)
  checkEq("a soldier 30", rtSoldier.partCost(), 30)
  checkEq("a guard 30", rtGuard.partCost(), 30)
  checkEq("a scout 25", rtScout.partCost(), 25)
  checkEq("a viper 120", rtViper.partCost(), 120)
  checkEq("a turret 130", rtTurret.partCost(), 130)
  checkEq("and a TTM 130 — packing does not refund", rtTtm.partCost(), 130)
  checkEq("A's worth with one archon and 300 parts", w.partsWorth(teamA), 300)
  discard w.put(rtSoldier, loc(10, 10), teamA)
  discard w.put(rtViper, loc(10, 12), teamA)
  checkEq("plus a soldier and a viper", w.partsWorth(teamA), 300 + 30 + 120)

block:
  ## Rung 3's accumulator is SEEDED with the parts difference and then walks
  ## every live robot of EITHER team ONCE, in insertion order — so it includes
  ## the zombies' and neutrals' cost, which is 0 for a den and a zombie and
  ## NON-ZERO for a neutral, and neutrals belong to neither team so they
  ## contribute NOTHING.
  let w = bare()
  discard w.put(rtSoldier, loc(10, 10), teamA)
  discard w.put(rtTurret, loc(20, 10), teamB)
  discard w.put(rtViper, loc(15, 10), teamNeutral)
  discard w.put(rtBigzombie, loc(15, 12), teamZombie)
  checkEq("the diff is (300-300) + 30 - 130 = -100", w.partsNetWorthDiff(),
    -100.0)
  checkEq("the NEUTRAL viper's 120 contributes to neither side",
    w.partsWorth(teamA) - w.partsWorth(teamB), 30 - 130)

# --- nothing creates parts after round 0 except a den bounty --------------
block:
  let w = bare(parts = @[(loc(4, 15), 10.0)])
  let start = w.partsOnMap()
  let sheets = defaultSheets()
  let sides = newSides16(sheets, 0)
  for i in 0 ..< 5:
    runRound(w, sides, [ckBulwark, ckBulwark])
  check("parts on the map never grow", w.partsOnMap() <= start)

finish("test_bc16_economy")
