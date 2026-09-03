## Rule family: cheese spawning and symmetric pairing, king consumption and
## starvation, the rat cost curve, dirt digging and placing, and the
## four-rat formation.

import harness
import battlecode/years/bc26/[constants, maps, rules, world]
import battlecode/sheet

let spec = loadMap("DefaultSmall")
proc freshWorld(): World = newWorld(spec, GameMaxNumberOfRounds)

# --- cheese ----------------------------------------------------------------
block:
  let w = freshWorld()
  checkEq("both teams start with INITIAL_TEAM_CHEESE",
    w.teamInfo.globalCheese, [InitialTeamCheese, InitialTeamCheese])
  for m in w.cheeseMines:
    check("every mine has a pair", m.pair != nil)
    checkEq("and the pair is its symmetry image", m.pair.loc,
      w.symmetryLocation(m.loc))

block:
  ## The spawn probability is `1 - (1 - 0.01f)^roundsSinceLastSpawn`, with
  ## the base widened from a Java FLOAT.
  let w = freshWorld()
  let mine = w.cheeseMines[0]
  mine.lastSpawnRound = 0
  checkEq("a mine that just fired has probability 0",
    mine.generationProbability(0), 0.0)
  check("one round later it is about 1 %",
    mine.generationProbability(1) > 0.0099 and
    mine.generationProbability(1) < 0.0101)
  check("a hundred rounds later it is about 63 %",
    mine.generationProbability(100) > 0.63 and
    mine.generationProbability(100) < 0.64)
  check("a thousand rounds later it is effectively certain",
    mine.generationProbability(1000) > 0.9999)

block:
  ## Cheese arrives in SYMMETRIC PAIRS: a spawn on one side is matched on the
  ## other, so neither clan gets a richer map.
  let w = freshWorld()
  var total = 0
  for round in 1 .. 800:
    w.currentRound = round
    w.hasRunCheeseMines = false
    w.runCheeseMines()
  for i in 0 ..< w.width * w.height:
    total += w.cheeseAmounts[i]
  check("800 rounds of mines produce cheese", total > 0)
  var symmetric = true
  for i in 0 ..< w.width * w.height:
    let l = w.indexToLoc(i)
    if w.cheeseAmounts[i] != w.getCheeseAmount(w.symmetryLocation(l)):
      symmetric = false
  check("and the board stays symmetric", symmetric)

# --- rat kings --------------------------------------------------------------
block:
  ## A fed king eats RAT_KING_CHEESE_CONSUMPTION; a starving one loses
  ## RAT_KING_HEALTH_LOSS hp instead.
  let w = freshWorld()
  var king: Robot
  for r in w.liveRobots:
    if r.unit == utRatKing and r.team == teamA: king = r
  let clans = newClans([defaultSheet(), defaultSheet()], 0)
  let before = w.teamInfo.globalCheese[0]
  endOfTurnFor(w, clans, king)
  checkEq("a fed king eats 2 cheese", w.teamInfo.globalCheese[0],
    before - RatKingCheeseConsumption)
  checkEq("and keeps its health", king.health, UnitSpecs[utRatKing].health)
  w.teamInfo.globalCheese[0] = 1
  endOfTurnFor(w, clans, king)
  checkEq("a starving king loses 10 hp", king.health,
    UnitSpecs[utRatKing].health - RatKingHealthLoss)
  checkEq("and does not go into cheese debt", w.teamInfo.globalCheese[0], 1)

block:
  ## The rat cost curve: 10 + 10 * (rats / 4).
  let w = freshWorld()
  checkEq("the first rat costs the base", w.currentRatCost(teamA),
    BuildRobotBaseCost)
  w.teamInfo.numBabyRats[0] = 3
  checkEq("three rats in, still the base", w.currentRatCost(teamA),
    BuildRobotBaseCost)
  w.teamInfo.numBabyRats[0] = 4
  checkEq("the fourth rat raises the cost", w.currentRatCost(teamA),
    BuildRobotBaseCost + BuildRobotCostIncrease)
  w.teamInfo.numBabyRats[0] = 40
  checkEq("forty rats in", w.currentRatCost(teamA),
    BuildRobotBaseCost + 10 * BuildRobotCostIncrease)

block:
  ## King count caps, before and after the cutoff round.
  let w = freshWorld()
  w.spawnRobot(98001, utBabyRat, loc(10, 10), dNorth, 0, teamA)
  let rat = w.robotsById[98001]
  rat.actionCooldown = 0
  w.teamInfo.numRatKings[0] = MaxNumberOfRatKings
  check("cannot crown past MAX_NUMBER_OF_RAT_KINGS", not w.canBecomeRatKing(rat))
  w.teamInfo.numRatKings[0] = MaxNumberOfRatKingsAfterCutoff
  w.currentRound = RatKingCutoffRound + 1
  check("nor past the post-cutoff cap", not w.canBecomeRatKing(rat))
  w.currentRound = 1
  w.teamInfo.globalCheese[0] = 0
  check("nor without RAT_KING_UPGRADE_CHEESE_COST",
    not w.canBecomeRatKing(rat))

block:
  ## The formation itself: eight allied rats in the ring, 50 cheese, and the
  ## eight neighbours merge into the crown.
  let w = freshWorld()
  var id = 98100
  for dx in -1 .. 1:
    for dy in -1 .. 1:
      w.spawnRobot(id, utBabyRat, loc(12 + dx, 12 + dy), dNorth, 0, teamA)
      inc id
  let centre = w.getRobot(loc(12, 12))
  centre.actionCooldown = 0
  w.teamInfo.globalCheese[0] = 1000
  check("nine rats in a 3x3 can crown a king", w.canBecomeRatKing(centre))
  let ratsBefore = w.teamInfo.numBabyRats[0]
  let kingsBefore = w.teamInfo.numRatKings[0]
  w.becomeRatKing(centre)
  checkEq("the clan gains a king", w.teamInfo.numRatKings[0], kingsBefore + 1)
  checkEq("the crowned rat is now a king", centre.unit, utRatKing)
  checkEq("and the eight neighbours are consumed",
    w.teamInfo.numBabyRats[0], ratsBefore - 9)
  checkEq("the crown costs 50 cheese", w.teamInfo.globalCheese[0],
    1000 - RatKingUpgradeCheeseCost)
  check("the king's health is the pooled health, capped",
    centre.health <= UnitSpecs[utRatKing].health and centre.health > 0)

# --- dirt -------------------------------------------------------------------
block:
  ## A team can only PLACE dirt it has already DUG.
  let w = freshWorld()
  w.spawnRobot(98200, utBabyRat, loc(6, 6), dNorth, 0, teamA)
  let rat = w.robotsById[98200]
  rat.actionCooldown = 0
  w.dirt[w.idx(loc(6, 7))] = true
  check("digging needs DIG_DIRT_CHEESE_COST", w.canRemoveDirt(rat, loc(6, 7)))
  checkEq("the team holds no spoil yet", w.teamInfo.dirtCounts[0], 0)
  w.removeDirt(rat, loc(6, 7))
  checkEq("digging banks one tile of spoil", w.teamInfo.dirtCounts[0], 1)
  check("and the tile is clear", not w.getDirt(loc(6, 7)))
  checkEq("digging costs DIG_COOLDOWN", rat.actionCooldown, DigCooldown)
  rat.actionCooldown = 0
  check("placing needs spoil in the bank", w.canPlaceDirt(rat, loc(6, 7)))
  w.placeDirt(rat, loc(6, 7))
  checkEq("placing spends the spoil", w.teamInfo.dirtCounts[0], 0)
  check("and the tile is dirt again", w.getDirt(loc(6, 7)))
  rat.actionCooldown = 0
  check("with an empty bank there is nothing to place",
    not w.canPlaceDirt(rat, loc(6, 5)))

finish("test_rules_economy")
