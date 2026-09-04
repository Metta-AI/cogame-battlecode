## The bc20 PARITY ORACLE, Nim side. CI-ONLY.
##
## Emits exactly the vector file `tools/oracle/Bc20Oracle.java` emits from the
## pinned 2020 engine sources, so the `parity-oracle-bc20` job can diff the two
## byte for byte. Every line is arithmetic the port could get subtly wrong and
## never notice on its own: the water table, both pollution coefficients over
## the whole integer domain, `Math.round(float)`, the `IDGenerator` id streams
## that decide the `highest_id` tiebreak, the `java.util.Random` streams behind
## the transaction ids and the cows, the OVERFLOWING cow seed, and
## `Transaction.compareTo`'s three rungs.
##
##   nim c --hints:off -d:release --path:src -o:/tmp/parity_trace_bc20 \
##     tools/parity_trace_bc20.nim
##   /tmp/parity_trace_bc20 > /tmp/oracle/nim.vectors
##
## docs/PARITY.md §bc20 records what each tier proves.

import std/[algorithm, strformat, strutils]
import battlecode/rng
import battlecode/years/bc20/[blockchain, constants, cows, flood, pollution, world]

proc f32(v: float32): string =
  toHex(cast[uint32](v), 8).toLowerAscii()

proc bit(b: bool): int = (if b: 1 else: 0)

var vec = ""

# -- constants ---------------------------------------------------------------
vec.add("constants\n")
vec.add(&"MIN_WATER_ELEVATION {MinWaterElevation}\n")
vec.add(&"INITIAL_SOUP {InitialSoup}\n")
vec.add(&"BASE_INCOME_PER_ROUND {BaseIncomePerRound}\n")
vec.add(&"SOUP_MINING_RATE {SoupMiningRate}\n")
vec.add(&"MAX_DIRT_DIFFERENCE {MaxDirtDifference}\n")
vec.add(&"DELIVERY_DRONE_PICKUP_RADIUS_SQUARED {DeliveryDronePickupRadiusSquared}\n")
vec.add(&"NET_GUN_SHOOT_RADIUS_SQUARED {NetGunShootRadiusSquared}\n")
vec.add(&"BLOCKCHAIN_TRANSACTION_LENGTH {BlockchainTransactionLength}\n")
vec.add(&"NUMBER_OF_TRANSACTIONS_PER_BLOCK {NumberOfTransactionsPerBlock}\n")
vec.add(&"INITIAL_COOLDOWN_TURNS {InitialCooldownTurns}\n")

# -- the RobotType table -----------------------------------------------------
vec.add("robottypes\n")
for kind in RobotKind:
  let s = RobotSpecs[kind]
  vec.add(&"{$kind} {s.cost} {s.dirtLimit} {s.soupLimit} " &
    &"{f32(s.actionCooldown)} {s.sensorRadiusSquared} " &
    &"{s.pollutionRadiusSquared} {s.localPollutionAdditiveEffect} " &
    &"{f32(s.localPollutionMultiplicativeEffect)} {s.globalPollutionAmount} " &
    &"{s.maxSoupProduced} {bit(kind.isBuilding())} {bit(kind.canRefine())} " &
    &"{bit(kind.canAffectPollution())} {bit(kind.canMoveKind())} " &
    &"{bit(kind.canFly())} {bit(kind.canBePickedUp())} " &
    &"{bit(kind.canShootKind())} {bit(kind.canBeShot())}\n")

# -- Direction ---------------------------------------------------------------
const DirNames = ["NORTH", "NORTHEAST", "EAST", "SOUTHEAST", "SOUTH",
                  "SOUTHWEST", "WEST", "NORTHWEST", "CENTER"]
vec.add("directions\n")
for d in AllDirs:
  vec.add(&"{DirNames[ord(d)]} {d.dx} {d.dy} {DirNames[ord(d.opposite())]}\n")

# -- the water table ---------------------------------------------------------
vec.add("water\n")
for r in 0 .. 1500:
  vec.add(&"{r} {f32(waterLevelAt(r))}\n")

# -- both pollution coefficients, the whole integer domain -------------------
vec.add("pollution\n")
for p in 0 .. 65535:
  vec.add(&"{p} {f32(cooldownCoefficient(p))} {f32(sensorCoefficient(p))}\n")

# -- Math.round(float) -------------------------------------------------------
vec.add("round\n")
for v in [0.0'f32, 0.5'f32, -0.5'f32, 1.4999999'f32, 2.5'f32, -2.5'f32,
          35.0'f32, 27.65'f32, 6.9999995'f32, 1e7'f32, -1e7'f32]:
  vec.add(&"{f32(v)} {javaRoundF32(v)}\n")

const Seeds = [30, 432, 219, 9999, 43223, 118811, 198248, 4444, 6370]

# -- IDGenerator -------------------------------------------------------------
vec.add("ids\n")
for seed in Seeds:
  var gen = initIdGenerator(seed)
  vec.add($seed)
  for i in 0 ..< 24:
    vec.add(" " & $gen.nextId())
  vec.add("\n")

# -- java.util.Random --------------------------------------------------------
vec.add("random\n")
for seed in Seeds:
  var r = initJavaRandom(seed)
  vec.add($seed)
  for i in 0 ..< 8:
    vec.add(" " & $r.nextInt())
  vec.add("\n")

vec.add("cowseeds\n")
for seed in Seeds:
  for id in 0 ..< 6:
    let cowSeed = cowSeed(seed, id)
    var r = initJavaRandom(cowSeed)
    vec.add(&"{seed} {id} {cowSeed}")
    for i in 0 ..< 4:
      vec.add(" " & $cast[int64](r.nextDouble()))
    vec.add("\n")

# -- Transaction.compareTo ---------------------------------------------------
vec.add("transactions\n")
var corpus = initJavaRandom(20200101)
var pool: seq[Transaction]
for i in 0 ..< 200:
  var message: array[TransactionLength, int]
  for j in 0 ..< TransactionLength:
    message[j] = int(corpus.nextInt(50))
  let cost = 1 + int(corpus.nextInt(5))
  let id = corpus.nextInt(7)
  let t = newTransaction(cost, message, id, 0)
  pool.add(t)
  vec.add(&"in {cost} {id} {t.serialized}\n")
pool.sort(compareTransactions)
for t in pool:
  vec.add(&"out {t.cost} {t.serialized}\n")

stdout.write(vec)
