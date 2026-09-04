## The election: `compareTo`'s top-bidder rule, the full/half payments, the
## tie that gives the vote to NOBODY and charges both, the bid held hostage
## from the moment it is placed, the second bid replacing the first, and the
## neutral Center that never bids.

import harness
import battlecode/years/bc21/[constants, world, votes]

proc flat(width, height: int): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.origin = [0, 0]
  result.randomSeed = 4242
  result.symmetry = symRotational
  result.symmetries = @[symRotational]
  for i in 0 ..< width * height:
    result.passability.add(1.0)

proc bare(): World = newWorld(flat(15, 15), 1500)

proc settle(w: World) =
  let (bids, bidders) = w.processEndOfRoundSweep()
  w.settleAuction(bids, bidders)

# --- the bid is deducted immediately and held hostage -----------------------
block:
  var w = bare()
  let id = w.spawnRobot(-1, rtEnlightenmentCenter, loc(5, 5), teamA, 100)
  let ec = w.robotsById[id]
  w.bid(ec, 30)
  checkEq("the influence is gone the moment the bid is placed",
    ec.influence, 70)
  checkEq("and the conviction with it", ec.conviction, 70)
  check("so it cannot be spent on a build this turn",
    not w.canBuildRobot(ec, rtPolitician, dNorth, 80))
  check("but 70 of it can", w.canBuildRobot(ec, rtPolitician, dNorth, 70))
  w.bid(ec, 10)
  checkEq("a second bid REPLACES the first and refunds it", ec.influence, 90)
  checkEq("and the recorded bid is the new one", ec.bid, 10)
  check("a bid above the Center's influence is refused", not canBid(ec, 200))
  check("and a zero bid is not a bid", not canBid(ec, 0))

# --- the winner pays in full, the loser pays half ---------------------------
block:
  var w = bare()
  let a = w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 1000)
  let b = w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 1000)
  w.bid(w.robotsById[a], 40)
  w.bid(w.robotsById[b], 25)
  w.settle()
  checkEq("A won the vote", w.stats.votes[0], 1)
  checkEq("B did not", w.stats.votes[1], 0)
  checkEq("A paid its bid in full", w.robotsById[a].influence, 960)
  checkEq("B paid ceil(25/2) = 13 for NOTHING",
    w.robotsById[b].influence, 987)

block:
  ## `(bid + 1) / 2` in integers: an even bid halves exactly.
  var w = bare()
  let a = w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 1000)
  let b = w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 1000)
  w.bid(w.robotsById[a], 40)
  w.bid(w.robotsById[b], 24)
  w.settle()
  checkEq("an even losing bid costs exactly half",
    w.robotsById[b].influence, 988)

# --- equal top bids: NOBODY wins and both pay half --------------------------
block:
  var w = bare()
  let a = w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 1000)
  let b = w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 1000)
  w.bid(w.robotsById[a], 31)
  w.bid(w.robotsById[b], 31)
  w.settle()
  checkEq("nobody won the vote", w.stats.votes[0] + w.stats.votes[1], 0)
  checkEq("A paid half", w.robotsById[a].influence, 984)
  checkEq("B paid half", w.robotsById[b].influence, 984)
  checkEq("and the round is recorded as tied", w.stats.votesTied, 1)

block:
  ## Both bidding ZERO is still a tie, and costs nothing.
  var w = bare()
  let a = w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 1000)
  let b = w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 1000)
  w.settle()
  checkEq("no votes", w.stats.votes[0] + w.stats.votes[1], 0)
  checkEq("no cost to A", w.robotsById[a].influence, 1000)
  checkEq("no cost to B", w.robotsById[b].influence, 1000)
  checkEq("and the round is counted as a no-bid round", w.stats.roundsNoBid, 1)

block:
  ## A positive bid against a zero bid still wins.
  var w = bare()
  let a = w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 1000)
  let b = w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 1000)
  w.bid(w.robotsById[a], 1)
  w.settle()
  checkEq("one influence buys the vote", w.stats.votes[0], 1)
  checkEq("A paid it", w.robotsById[a].influence, 999)
  checkEq("B's zero bid costs zero", w.robotsById[b].influence, 1000)

# --- the top bidder is the maximum under (bid desc, age asc, id asc) --------
block:
  var w = bare()
  let low = w.spawnRobotWithId(20_000, -1, rtEnlightenmentCenter, loc(2, 2),
                               teamA, 1000)
  let high = w.spawnRobotWithId(30_000, -1, rtEnlightenmentCenter, loc(4, 4),
                                teamA, 1000)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(12, 12), teamB, 1000)
  w.robotsById[low].roundsAlive = 10
  w.robotsById[high].roundsAlive = 10
  w.bid(w.robotsById[low], 20)
  w.bid(w.robotsById[high], 20)
  let (bids, bidders) = w.processEndOfRoundSweep()
  checkEq("the tie on bid and age breaks on the LOWER id", bidders[0], low)
  checkEq("and it is that bid", bids[0], 20)

block:
  var w = bare()
  let old0 = w.spawnRobotWithId(20_000, -1, rtEnlightenmentCenter, loc(2, 2),
                                teamA, 1000)
  let young = w.spawnRobotWithId(30_000, -1, rtEnlightenmentCenter, loc(4, 4),
                                 teamA, 1000)
  w.robotsById[old0].roundsAlive = 40
  w.robotsById[young].roundsAlive = 3
  w.bid(w.robotsById[old0], 20)
  w.bid(w.robotsById[young], 20)
  let (_, bidders) = w.processEndOfRoundSweep()
  checkEq("age outranks id: the YOUNGER Center is the top bidder",
    bidders[0], young)

block:
  ## A team with any Enlightenment Center always HAS a top bidder, even when
  ## every Center bid zero.
  var w = bare()
  let a = w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 1000)
  let (bids, bidders) = w.processEndOfRoundSweep()
  checkEq("the top bidder exists", bidders[0], a)
  checkEq("with a zero bid", bids[0], 0)
  checkEq("and team B has none", bidders[1], -1)

# --- neutral Centers never bid ----------------------------------------------
block:
  var w = bare()
  let n = w.spawnRobot(-1, rtEnlightenmentCenter, loc(7, 7), teamNeutral, 500)
  w.bid(w.robotsById[n], 100)
  let (_, bidders) = w.processEndOfRoundSweep()
  checkEq("a neutral Center is not a bidder for A", bidders[0], -1)
  checkEq("nor for B", bidders[1], -1)

# --- the refund happens before the settlement, so the bid can be re-earned --
block:
  var w = bare()
  let a = w.spawnRobot(-1, rtEnlightenmentCenter, loc(2, 2), teamA, 100)
  w.bid(w.robotsById[a], 100)
  checkEq("the Center is empty while the bid is held",
    w.robotsById[a].influence, 0)
  w.settle()
  checkEq("A won and paid the whole 100", w.robotsById[a].influence, 0)
  checkEq("and it did win", w.stats.votes[0], 1)

finish("bc21 votes")
