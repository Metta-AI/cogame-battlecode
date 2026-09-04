## The blockchain: the fee model, the seven-int message, the comparator, the
## per-round mint of at most seven, the eternal pool, and the re-seeded
## transaction-id RNG.

import harness
import battlecode/rng
import battlecode/years/bc20/[blockchain, constants, world]

proc flat(width, height: int): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.symmetry = symRotational
  result.randomSeed = 4242
  for i in 0 ..< width * height:
    result.elevation.add(0)
    result.water.add(false)
    result.pollution.add(0)
    result.soup.add(0)

proc msg(v: int): array[TransactionLength, int] =
  for i in 0 ..< TransactionLength: result[i] = v

block:
  checkEq("a message is exactly seven ints", BlockchainTransactionLength, 7)
  checkEq("and the Nim record agrees", TransactionLength, 7)
  checkEq("seven transactions a block", NumberOfTransactionsPerBlock, 7)

block:
  ## `cost > 0`, `cost <= team soup`, and the soup is deducted AT SUBMIT TIME.
  var w = newWorld(flat(9, 9), 1500)
  let id = w.spawnRobot(rtMiner, loc(4, 4), teamA)
  let r = w.robotsById[id]
  w.stats.soup[0] = 100
  check("a zero-cost transaction is refused", not w.canSubmitTransaction(r, 0))
  check("a negative cost is refused", not w.canSubmitTransaction(r, -5))
  check("a cost above the pool is refused",
    not w.canSubmitTransaction(r, 101))
  check("and one the pool can pay is allowed", w.canSubmitTransaction(r, 40))
  w.submitTransaction(r, msg(1), 40)
  checkEq("the soup came out at submit time", w.stats.soup[0], 60)
  checkEq("and the pool holds one transaction", w.txPool.len, 1)
  checkEq("submitted is counted", w.stats.transactionsSent[0], 1)
  checkEq("minted is NOT yet", w.stats.blockchainsSent[0], 0)

block:
  ## Comparator order: cost DESC, then id DESC, then the serialized message
  ## ASCENDING. `serializedMessage` is the seven ints joined by `_`.
  var pool: seq[Transaction]
  pool.add(newTransaction(5, msg(9), 100'i32, 0))
  pool.add(newTransaction(9, msg(1), 1'i32, 0))
  pool.add(newTransaction(5, msg(8), 200'i32, 1))
  let minted = mintBlock(pool, 7)
  checkEq("every transaction minted", minted.len, 3)
  checkEq("the highest cost is first", minted[0].cost, 9)
  checkEq("then the higher id among equal costs", minted[1].id, 200'i32)
  checkEq("and the lower id last", minted[2].id, 100'i32)
  checkEq("the pool is drained", pool.len, 0)

  var tie: seq[Transaction]
  var lo = msg(1)
  var hi = msg(1)
  hi[6] = 2
  tie.add(newTransaction(3, hi, 7'i32, 0))
  tie.add(newTransaction(3, lo, 7'i32, 0))
  let tied = mintBlock(tie, 7)
  checkEq("a full id tie breaks on the lexicographically earlier message",
    tied[0].serialized, "1_1_1_1_1_1_1")

block:
  ## At most seven a round; the rest STAY ELIGIBLE FOR EVER, and
  ## `blockchainsSent` counts MINTED, not submitted.
  var w = newWorld(flat(9, 9), 1500)
  let id = w.spawnRobot(rtMiner, loc(4, 4), teamA)
  let r = w.robotsById[id]
  w.stats.soup[0] = 10_000
  for i in 1 .. 10:
    w.submitTransaction(r, msg(i), i)
  checkEq("ten submitted", w.stats.transactionsSent[0], 10)
  w.currentRound = 1
  w.processBlockchain()
  checkEq("seven minted this round", w.stats.blockchainsSent[0], 7)
  checkEq("three still in the pool", w.txPool.len, 3)
  checkEq("and the block carries seven", w.blockchain[0].len, 7)
  checkEq("the most expensive went first", w.blockchain[0][0].cost, 10)
  w.currentRound = 2
  w.processBlockchain()
  checkEq("the leftovers mint next round", w.stats.blockchainsSent[0], 10)
  checkEq("and the pool is empty", w.txPool.len, 0)

block:
  ## `getBlock` refuses non-positive rounds and the CURRENT round.
  var w = newWorld(flat(9, 9), 1500)
  w.currentRound = 3
  w.blockchain = @[@[], @[], @[]]
  checkEq("round 0 is refused", w.getBlock(0).len, 0)
  checkEq("the current round is refused", w.getBlock(3).len, 0)
  checkEq("a past round is allowed", w.getBlock(1).len, 0)

block:
  ## THE QUIRK. `RobotControllerImpl.random` is a Java `private static Random`
  ## assigned `new Random(gameWorld.getMapSeed())` IN THE CONSTRUCTOR, so it is
  ## re-seeded on EVERY SPAWN. This vector fails if the RNG is seeded once.
  var w = newWorld(flat(9, 9), 1500)
  w.stats.soup[0] = 10_000
  let a = w.spawnRobot(rtMiner, loc(1, 1), teamA)
  ## Draw the first id from a fresh stream, for reference.
  var reference = initJavaRandom(w.map.randomSeed)
  let firstDraw = reference.nextInt()
  w.submitTransaction(w.robotsById[a], msg(1), 1)
  checkEq("the first transaction id is the first draw of a fresh stream",
    w.txPool[0].id, firstDraw)

  ## Now spawn another robot; the static RNG is re-seeded, so the NEXT
  ## transaction id is the FIRST draw again, not the second.
  discard w.spawnRobot(rtMiner, loc(2, 2), teamA)
  w.submitTransaction(w.robotsById[a], msg(2), 1)
  checkEq("a spawn RE-SEEDS the transaction RNG", w.txPool[1].id, firstDraw)

  ## And with no spawn in between the stream advances normally.
  let secondDraw = reference.nextInt()
  w.submitTransaction(w.robotsById[a], msg(3), 1)
  checkEq("without a spawn the stream advances", w.txPool[2].id, secondDraw)
  check("which is a different value", secondDraw != firstDraw)

finish("test_bc20_blockchain")
