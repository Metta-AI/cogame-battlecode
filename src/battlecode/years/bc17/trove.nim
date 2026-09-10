## `gnu.trove.map.hash.TIntObjectHashMap` (trove4j **3.0.3**), ported for its
## OBSERVABLE ITERATION ORDER -- and in 2017 it is observable in exactly two
## places, both of which decide the game (docs/RULES-BC17.md D1).
##
## **WHY A COPY AND NOT AN IMPORT OF `years/bc22/trove.nim`.** Two deliberate
## differences, and they are why bc17 ships its own file:
##
##   (a) bc22 only ever calls `values(V[])` on a SNAPSHOT, so it never had to
##       model iteration over a MUTATING table. bc17's `forEachValue` walks a
##       table that `destroyTree`/`destroyRobot` mutate from inside the walk --
##       `GameWorld.updateTrees` kills a tree during the very pass that sums
##       its income -- and MEASURED on the jar's own classes, a removal that
##       triggers auto-compaction leaves the walk on the PRE-COMPACTION
##       ARRAYS: 40 of 40 values were visited while 20 were removed and the
##       capacity shrank 97 -> 67. So `keys` and `states` here are `ref seq`
##       and `rehash` ALLOCATES NEW ONES, exactly as Java assigns new arrays
##       and leaves the live iterator's references on the old ones.
##   (b) bc22's file has no `clear()`. bc17 needs one, and needs it to RETAIN
##       THE TABLE'S CAPACITY (measured: 397 -> 397), because
##       `GameWorld.updateBroadCastData` clears `currentBroadcasters` every
##       round and the layout in round R therefore depends on the historical
##       PEAK broadcaster count.
##
## **THE TWO OBSERVABLE CONSEQUENCES IN 2017**, both from
## `ObjectInfo.eachRobot/eachTree/eachBullet` being trove's `forEachValue`
## (`ObjectInfo.java:90-120`, whose own comment at `:110` says it out loud --
## *"ordered based on robot ID hash (effectively random)"*):
##
##   1. **`updateTrees`'s FLOAT32 ACCUMULATION.**
##      `totalTreeSupply[team] += tree.updateTree()` (`GameWorld.java:121-124`)
##      sums in float32 over trove order, and that sum lands in the bullet
##      supply that `donate`'s integer floor and every affordability
##      comparison read. The 1.6.2 spec says of this phase *"The ordering of
##      this phase is not important to the outcome of a match"* -- THE
##      SENTENCE IS FALSE, and this file is why the port does not trust it.
##   2. **`previousBroadcasters`.**
##      `currentBroadcasters.values(new RobotInfo[size])` (`:455-457`) is the
##      array `senseBroadcastingRobotLocations()` hands a chassis, FOR BOTH
##      TEAMS -- so the order is visible to the bot and therefore to the game.
##
## Measured on the jar's own classes and cross-checked against the live
## engine's own `eachRobot` output: a fresh map has capacity **23**,
## `HashFunctions.hash(int)` is the IDENTITY, the slot is `hash % length`, and
## `forEachValue` walks **high index -> low**; ids `{2,3,4,5}` give `5 4 3 2`
## and ids `{14,15,16,17,34,35}` give `17 16 15 14 35 34`.
##
## Where the order is NOT observable, said explicitly so nobody ports it for
## safety: `processBeginningOfRound`'s `healthChanged = false` sweeps,
## `processEndOfRound`'s replay-only sweeps and the tree `roundsAlive`
## increment. **And the compaction-during-iteration effect is itself
## unobservable in `updateTrees`**, because during that pass a tree is only
## ever removed by ITS OWN visit and therefore never revisited -- a proof, not
## a hope, and `tests/test_bc17_trove.nim` asserts the pass visits every tree
## exactly once even when a third of them die in one round.
##
## Everything below was read out of the jar's own classes with `javap -c`, not
## remembered; the mechanism notes are `years/bc22/trove.nim`'s and are kept
## verbatim because it is the same library at the same version.
##
## LICENCE: trove4j is **LGPL-2.1**. This file vendors no trove source and no
## trove bytecode; it reproduces the *observable behaviour* of a documented
## open-addressing scheme, hand-written in Nim. `NOTICE` records the dependency
## and its licence, because reproducing a library's iteration order is a
## derivation of its behaviour and saying so plainly is cheaper than leaving it
## implicit.

const
  TroveFree* = 0'i8
  TroveFull* = 1'i8
  TroveRemoved* = 2'i8

  TroveDefaultCapacity* = 10
  TroveLoadFactor* = 0.5'f32

  PrimeCapacities*: array[245, int] = [
    3, 5, 7, 11, 17, 23, 31, 37, 43, 47, 67, 79, 89, 97, 137, 163, 179, 197,
    277, 311, 331, 359, 379, 397, 433, 557, 599, 631, 673, 719, 761, 797, 877,
    953, 1039, 1117, 1201, 1277, 1361, 1439, 1523, 1597, 1759, 1907, 2081,
    2237, 2411, 2557, 2729, 2879, 3049, 3203, 3527, 3821, 4177, 4481, 4831,
    5119, 5471, 5779, 6101, 6421, 7057, 7643, 8363, 8963, 9677, 10243, 10949,
    11579, 12203, 12853, 14143, 15287, 16729, 17929, 19373, 20507, 21911,
    23159, 24407, 25717, 28289, 30577, 33461, 35863, 38747, 41017, 43853,
    46327, 48817, 51437, 56591, 61169, 66923, 71741, 77509, 82037, 87719,
    92657, 97649, 102877, 113189, 122347, 133853, 143483, 155027, 164089,
    175447, 185323, 195311, 205759, 226379, 244703, 267713, 286973, 310081,
    328213, 350899, 370661, 390647, 411527, 452759, 489407, 535481, 573953,
    620171, 656429, 701819, 741337, 781301, 823117, 905551, 978821, 1070981,
    1147921, 1240361, 1312867, 1403641, 1482707, 1562611, 1646237, 1811107,
    1957651, 2141977, 2295859, 2480729, 2625761, 2807303, 2965421, 3125257,
    3292489, 3622219, 3915341, 4283963, 4591721, 4961459, 5251529, 5614657,
    5930887, 6250537, 6584983, 7244441, 7830701, 8567929, 9183457, 9922933,
    10503061, 11229331, 11861791, 12501169, 13169977, 14488931, 15661423,
    17135863, 18366923, 19845871, 21006137, 22458671, 23723597, 25002389,
    26339969, 28977863, 31322867, 34271747, 36733847, 39691759, 42012281,
    44917381, 47447201, 50004791, 52679969, 57955739, 62645741, 68543509,
    73467739, 79383533, 84024581, 89834777, 94894427, 100009607, 105359939,
    115911563, 125291483, 137087021, 146935499, 158767069, 168049163,
    179669557, 189788857, 200019221, 210719881, 231823147, 250582987,
    274174111, 293871013, 317534141, 336098327, 359339171, 379577741,
    400038451, 421439783, 463646329, 501165979, 548348231, 587742049,
    635068283, 672196673, 718678369, 759155483, 800076929, 842879579,
    927292699, 1002331963, 1096696463, 1175484103, 1270136683, 1344393353,
    1437356741, 1518310967, 1600153859, 1685759167, 1854585413, 2004663929,
    2147483647]
    ## `gnu.trove.impl.PrimeFinder.primeCapacities`, read out of the jar by
    ## reflection. **The first entry in the Java array is 2147483647** and the
    ## rest ascend from 3; `nextPrime` runs `Arrays.binarySearch` over it, which
    ## only behaves for the ASCENDING tail, so the table is stored here in the
    ## ascending order the search actually walks and `nextPrime` reproduces the
    ## same answer for every reachable capacity.

type
  TroveIntMap* = object
    ## `TIntObjectHashMap<V>` with the VALUE dropped: the port only ever needs
    ## the key ORDER, and `world.nim`'s `Table[int, ...]` payloads already own
    ## the bodies.
    ##
    ## `keys` and `states` are `ref seq` and `rehash` allocates NEW ones, so a
    ## `forEachValue` walk that is holding the old pair keeps walking it --
    ## which is exactly what the JVM does and exactly what a mid-pass
    ## `destroyTree` depends on (difference (a) in this file's header).
    keys*: ref seq[int]
    states*: ref seq[int8]
    size*: int
    free*: int
    maxSize*: int
    autoCompactRemovesRemaining*: int

func nextPrime*(desired: int): int =
  ## `PrimeFinder.nextPrime` — the smallest capacity in the ladder that is
  ## `>= desired`.
  for p in PrimeCapacities:
    if p >= desired: return p
  PrimeCapacities[PrimeCapacities.high]

func fastCeil*(v: float32): int =
  ## `HashFunctions.fastCeil`: `int i = (int) v; if (v - i > 0) i++;`
  var i = int(v)
  if v - float32(i) > 0'f32: inc i
  i

proc computeMaxSize(m: var TroveIntMap, capacity: int) =
  m.maxSize = min(capacity - 1, int(float32(capacity) * TroveLoadFactor))
  m.free = capacity - m.size

proc computeNextAutoCompactionAmount(m: var TroveIntMap, size: int) =
  m.autoCompactRemovesRemaining =
    int(float32(size) * TroveLoadFactor + 0.5'f32)

proc setUp(m: var TroveIntMap, initialCapacity: int): int =
  let capacity = nextPrime(initialCapacity)
  m.keys = new(seq[int])
  m.keys[] = newSeq[int](capacity)
  m.states = new(seq[int8])
  m.states[] = newSeq[int8](capacity)
  m.computeMaxSize(capacity)
  m.computeNextAutoCompactionAmount(initialCapacity)
  capacity

proc initTroveIntMap*(): TroveIntMap =
  ## `new TIntObjectHashMap<>()` == `THash(10, 0.5f)`.
  discard result.setUp(fastCeil(float32(TroveDefaultCapacity) /
                                TroveLoadFactor))

func capacity*(m: TroveIntMap): int = m.states[].len

func troveHash(key: int): int = key and 0x7FFFFFFF
  ## `HashFunctions.hash(int)` is the identity; the mask is `GameWorld`'s.

func index*(m: TroveIntMap, key: int): int =
  ## `TIntHash.index` + `indexRehashed`, verbatim. `-1` when absent.
  let length = m.states[].len
  let hash = troveHash(key)
  var idx = hash mod length
  var state = m.states[][idx]
  if state == TroveFree: return -1
  if state == TroveFull and m.keys[][idx] == key: return idx
  let probe = 1 + (hash mod (length - 2))
  let loopIndex = idx
  while true:
    idx -= probe
    if idx < 0: idx += length
    state = m.states[][idx]
    if state == TroveFree: return -1
    if m.keys[][idx] == key and state != TroveRemoved: return idx
    if idx == loopIndex: break
  -1

func contains*(m: TroveIntMap, key: int): bool = m.index(key) >= 0

proc insertKeyAt(m: var TroveIntMap, idx, key: int) =
  m.keys[][idx] = key
  m.states[][idx] = TroveFull

proc insertKey(m: var TroveIntMap, key: int,
               consumeFreeSlot: var bool): int =
  ## `TIntHash.insertKey` + `insertKeyRehash`. A NEGATIVE result is
  ## `-index - 1` and means "already stored".
  let hash = troveHash(key)
  var idx = hash mod m.states[].len
  var state = m.states[][idx]
  consumeFreeSlot = false
  if state == TroveFree:
    consumeFreeSlot = true
    m.insertKeyAt(idx, key)
    return idx
  if state == TroveFull and m.keys[][idx] == key:
    return -idx - 1
  let length = m.keys[].len
  let probe = 1 + (hash mod (length - 2))
  let loopIndex = idx
  var firstRemoved = -1
  while true:
    if state == TroveRemoved and firstRemoved == -1:
      firstRemoved = idx
    idx -= probe
    if idx < 0: idx += length
    state = m.states[][idx]
    if state == TroveFree:
      if firstRemoved != -1:
        m.insertKeyAt(firstRemoved, key)
        return firstRemoved
      consumeFreeSlot = true
      m.insertKeyAt(idx, key)
      return idx
    if state == TroveFull and m.keys[][idx] == key:
      return -idx - 1
    if idx == loopIndex: break
  if firstRemoved != -1:
    m.insertKeyAt(firstRemoved, key)
    return firstRemoved
  raise newException(ValueError,
    "trove: no free or removed slots available; key set full")

proc rehash(m: var TroveIntMap, newCapacity: int) =
  ## `TIntObjectHashMap.rehash`: walk the OLD table from `oldCapacity - 1` down
  ## to 0 and re-insert every `FULL` key. The descending walk is what makes the
  ## post-rehash layout — and therefore `values()`'s order — reproducible.
  ##
  ## THE NEW ARRAYS ARE FRESH ALLOCATIONS, as Java's are: an iterator created
  ## before the rehash keeps walking the old pair (this file's header, (a)).
  let oldKeys = m.keys
  let oldStates = m.states
  m.keys = new(seq[int])
  m.keys[] = newSeq[int](newCapacity)
  m.states = new(seq[int8])
  m.states[] = newSeq[int8](newCapacity)
  var i = oldStates[].len
  while i > 0:
    dec i
    if oldStates[][i] != TroveFull: continue
    var used = false
    discard m.insertKey(oldKeys[][i], used)

proc compact(m: var TroveIntMap) =
  ## `THash.compact`, verbatim:
  ## `rehash(nextPrime(max(_size + 1, fastCeil(size() / _loadFactor) + 1)))`.
  let want = max(m.size + 1,
                 fastCeil(float32(m.size) / TroveLoadFactor) + 1)
  m.rehash(nextPrime(want))
  m.computeMaxSize(m.capacity)
  m.computeNextAutoCompactionAmount(m.size)

proc postInsertHook(m: var TroveIntMap, usedFreeSlot: bool) =
  if usedFreeSlot: dec m.free
  inc m.size
  if m.size > m.maxSize or m.free == 0:
    let newCapacity =
      if m.size > m.maxSize: nextPrime(m.capacity shl 1) else: m.capacity
    m.rehash(newCapacity)
    m.computeMaxSize(m.capacity)

proc put*(m: var TroveIntMap, key: int) =
  ## `TIntObjectHashMap.put` with the value dropped.
  var consumeFreeSlot = false
  let idx = m.insertKey(key, consumeFreeSlot)
  if idx < 0: return          ## already stored: no `postInsertHook`
  m.postInsertHook(consumeFreeSlot)

proc remove*(m: var TroveIntMap, key: int) =
  ## `TIntObjectHashMap.remove` -> `removeAt` -> `TPrimitiveHash.removeAt`
  ## (state := REMOVED) -> `THash.removeAt` (size--, AUTO-COMPACTION).
  let idx = m.index(key)
  if idx < 0: return
  m.states[][idx] = TroveRemoved
  dec m.size
  dec m.autoCompactRemovesRemaining
  if m.autoCompactRemovesRemaining <= 0:
    m.compact()

iterator valuesDescending*(m: TroveIntMap): int =
  ## `values(V[])`: `for (int i = states.length, j = 0; i-- > 0;)`, appending
  ## every `FULL`. THE HIGH-INDEX-TO-LOW WALK IS THE WHOLE POINT OF THIS FILE.
  var i = m.states[].len
  while i > 0:
    dec i
    if m.states[][i] == TroveFull:
      yield m.keys[][i]

proc valuesArray*(m: TroveIntMap): seq[int] =
  result = newSeqOfCap[int](m.size)
  for id in m.valuesDescending: result.add(id)

func fnv1a64*(values: openArray[int]): uint64 =
  ## The fold every parity-trace checksum line uses, on both sides of the
  ## oracle. ONE WHOLE INT PER ITERATION, masked to 32 bits — byte for byte
  ## what `Bc22Trace.fnv` does in Java:
  ##   h = (h ^ (values[i] & 0xFFFFFFFFL)) * 0x100000001B3L
  ## It is deliberately NOT the canonical byte-wise FNV-1a: the value is
  ## compared across the two implementations, so the fold is wire format.
  result = 0xcbf29ce484222325'u64
  for v in values:
    result = (result xor uint64(uint32(v))) * 0x100000001B3'u64


proc clear*(m: var TroveIntMap) =
  ## `TIntObjectHashMap.clear()` -> `THash.clear()`, verbatim: every slot goes
  ## back to `FREE`, `_size = 0`, `_free = capacity()` -- **AND THE CAPACITY
  ## IS RETAINED** (measured on the jar: 397 -> 397). `_maxSize` and
  ## `_autoCompactRemovesRemaining` are NOT recomputed, because `THash.clear`
  ## does not call `computeMaxSize` or `computeNextAutoCompactionAmount`.
  ##
  ## That retention is a rule here: `GameWorld.updateBroadCastData` clears
  ## `currentBroadcasters` every single round, so the table a round-R
  ## broadcaster lands in is laid out by the historical PEAK broadcaster count,
  ## and the order `senseBroadcastingRobotLocations()` hands a chassis follows
  ## from it.
  for i in 0 ..< m.states[].len:
    m.keys[][i] = 0
    m.states[][i] = TroveFree
  m.size = 0
  m.free = m.capacity()

iterator forEachValue*(m: TroveIntMap): int =
  ## `TIntObjectHashMap.forEachValue`, which is what `ObjectInfo.eachRobot`,
  ## `eachTree` and `eachBullet` are:
  ##
  ##     for (int i = states.length; i-- > 0;)
  ##         if (states[i] == FULL && !procedure.execute(values[i]))
  ##             return false;
  ##
  ## i.e. the SAME high-index-to-low walk `values(V[])` does, but reading the
  ## table LIVE. This iterator therefore pins `keys` and `states` on entry:
  ## a `remove` during the walk marks a slot `REMOVED` in the array this loop
  ## is reading (so a body killed by its own visit is simply not seen again),
  ## while a `remove` that triggers auto-compaction REPLACES the arrays and
  ## leaves this walk on the old pair -- measured, and the reason `keys` and
  ## `states` are `ref seq`.
  let keys = m.keys
  let states = m.states
  var i = states[].len
  while i > 0:
    dec i
    if states[][i] == TroveFull:
      yield keys[][i]
