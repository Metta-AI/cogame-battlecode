## §Tests item 11 -- the trove iteration order (D1).
##
## `gnu.trove.map.hash.TIntObjectHashMap` (trove4j 3.0.3) is observable in
## exactly two places in 2017 and both decide games: `updateTrees`'s FLOAT32
## income accumulation, and the `previousBroadcasters` array
## `senseBroadcastingRobotLocations()` hands EVERY chassis of BOTH teams. The
## 1.6.2 spec says of the first *"The ordering of this phase is not important
## to the outcome of a match"*. The sentence is false; this shard is why the
## port does not trust it.
##
## The oracle for the ORDER is `tests/fixtures/trove-bc22.txt`, recorded off
## the JAR'S OWN `gnu.trove` classes for the bc22 module -- **the same library
## at the same version**, so the two ports must agree on it value for value.
## Running bc17's copy against bc22's recorded oracle is the strongest check
## available in the sandbox and it is the one this shard makes.

import std/[algorithm, os, random, strutils, tables]
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, trove, world, maps, trees]
from battlecode/years/bc22/trove as trove22 import nil

# --- the ladder and the constructor -----------------------------------------
block:
  checkEq("nextPrime(20) is 23", nextPrime(20), 23)
  checkEq("nextPrime(23) is 23", nextPrime(23), 23)
  checkEq("nextPrime(24) is 31", nextPrime(24), 31)
  checkEq("fastCeil rounds a fraction up", fastCeil(10.0'f32 / 0.5'f32), 20)
  var m = initTroveIntMap()
  checkEq("a fresh map has capacity 23", m.capacity, 23)
  checkEq("its maxSize is min(22, floor(23*0.5)) = 11", m.maxSize, 11)
  checkEq("its free count is the whole table", m.free, 23)
  checkEq("and its auto-compaction counter is (int)(20*0.5+0.5) = 10",
    m.autoCompactRemovesRemaining, 10)

# --- the two MEASURED id sets -----------------------------------------------
block:
  ## Read out of the live engine's own `eachRobot` output in the sandbox.
  var a = initTroveIntMap()
  for id in [2, 3, 4, 5]: a.put(id)
  checkEq("ids {2,3,4,5} walk 5 4 3 2", a.valuesArray(), @[5, 4, 3, 2])
  var b = initTroveIntMap()
  for id in [14, 15, 16, 17, 34, 35]: b.put(id)
  checkEq("ids {14,15,16,17,34,35} walk 17 16 15 14 35 34",
    b.valuesArray(), @[17, 16, 15, 14, 35, 34])
  check("which is NOT insertion order",
    b.valuesArray() != @[14, 15, 16, 17, 34, 35])
  check("and NOT descending id order",
    b.valuesArray() != @[35, 34, 17, 16, 15, 14])

# --- the recorded oracle order, replayed through THIS port ------------------
block:
  let path = "tests/fixtures/trove-bc22.txt"
  check("the recorded oracle order ships", fileExists(path))
  if fileExists(path):
    var m = initTroveIntMap()
    var dumps = 0
    var mismatches = 0
    for line in lines(path):
      if line.len == 0 or line[0] == '#': continue
      if line[0] == 'P': m.put(parseInt(line[2 .. ^1]))
      elif line[0] == 'R': m.remove(parseInt(line[2 .. ^1]))
      elif line[0] == 'D':
        inc dumps
        var got: seq[string]
        for id in m.valuesDescending: got.add($id)
        if got.join(" ") != line[2 .. ^1]:
          inc mismatches
          if mismatches == 1:
            echo "  first divergence at dump ", dumps
            echo "    want ", line[2 .. ^1]
            echo "    got  ", got.join(" ")
    check("the fixture carries a real number of dumps", dumps >= 500)
    checkEq("and bc17's copy reproduces the JVM's order at every one of them",
      mismatches, 0)

# --- the two ports agree, which is what makes the copy safe -----------------
block:
  ## 500 random put/remove sequences off the REAL id stream, compared between
  ## `years/bc17/trove.nim` and `years/bc22/trove.nim` step for step.
  var seventeen = initTroveIntMap()
  var twentytwo = trove22.initTroveIntMap()
  var gen = initIdGenerator(937)
  var live: seq[int]
  var rnd = initRand(2017)
  var disagreements = 0
  for step in 0 ..< 500:
    if live.len == 0 or rnd.rand(100) < 60:
      let id = gen.nextId()
      seventeen.put(id)
      trove22.put(twentytwo, id)
      live.add(id)
    else:
      let k = rnd.rand(live.len - 1)
      seventeen.remove(live[k])
      trove22.remove(twentytwo, live[k])
      live.delete(k)
    if seventeen.valuesArray() != trove22.valuesArray(twentytwo):
      inc disagreements
  checkEq("bc17's and bc22's ports agree on values(V[]) at every one of " &
    "500 steps", disagreements, 0)
  checkEq("and on the size", seventeen.size, twentytwo.size)

# --- clear() RETAINS the capacity -------------------------------------------
block:
  ## `THash.clear()` does not recompute `_maxSize` and does not shrink, which
  ## is why a round-R broadcaster's slot depends on the historical PEAK
  ## broadcaster count.
  var m = initTroveIntMap()
  for i in 0 ..< 300: m.put(10000 + i * 7)
  let grown = m.capacity
  check("the table grew well past its initial 23", grown > 23)
  m.clear()
  checkEq("clear() retains the capacity", m.capacity, grown)
  checkEq("empties it", m.size, 0)
  checkEq("and frees every slot", m.free, grown)
  checkEq("valuesArray is empty", m.valuesArray().len, 0)
  ## The consequence: the same three ids land in a DIFFERENT order in a table
  ## that once held 300 than in a fresh one.
  var fresh = initTroveIntMap()
  for id in [10001, 10002, 10003]:
    m.put(id)
    fresh.put(id)
  check("so the layout after a clear is the PEAK layout, not a fresh one",
    m.valuesArray() != fresh.valuesArray() or m.capacity != fresh.capacity)

# --- the pre-compaction snapshot --------------------------------------------
block:
  ## A `remove` that triggers auto-compaction REPLACES `keys` and `states`,
  ## and a live `forEachValue` keeps walking the OLD pair. Measured on the
  ## jar: 40 of 40 values visited while 20 were removed.
  var m = initTroveIntMap()
  var ids: seq[int]
  for i in 0 ..< 40:
    let id = 10000 + i * 3
    ids.add(id)
    m.put(id)
  let before = m.capacity
  var visited = 0
  var removedDuring = 0
  for id in m.forEachValue:
    inc visited
    if removedDuring < 20 and id != ids[0]:
      m.remove(id)
      inc removedDuring
  checkEq("every one of the 40 values was visited", visited, 40)
  checkEq("while 20 were removed mid-walk", removedDuring, 20)
  check("and the table really did shrink underneath the walk",
    m.capacity < before)
  checkEq("the survivors are what is left", m.size, 20)

# --- a body killed by its own visit is simply not seen again ----------------
block:
  var m = initTroveIntMap()
  for i in 0 ..< 12: m.put(20000 + i)
  var seen: seq[int]
  for id in m.forEachValue:
    seen.add(id)
    m.remove(id)
  checkEq("a walk that kills every value it visits still visits each once",
    seen.len, 12)
  var sortedSeen = seen
  sortedSeen.sort()
  var duplicates = 0
  for i in 1 ..< sortedSeen.len:
    if sortedSeen[i] == sortedSeen[i - 1]: inc duplicates
  checkEq("with no repeats", duplicates, 0)
  checkEq("and the table is empty afterwards", m.size, 0)

# --- the proof updateTrees depends on ---------------------------------------
block:
  ## `GameWorld.updateTrees` kills a tree during the very pass that sums its
  ## income. The port's claim is that the pass visits every tree EXACTLY ONCE
  ## even when a third of them die in one round -- a proof, not a hope.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  var planted: seq[int]
  for i in 0 ..< 45:
    let tr = w.spawnTree(tA, 1'f32, loc(float32(10 + (i mod 15) * 3),
                                        float32(10 + (i div 15) * 3)), 0, -1)
    planted.add(tr.id)
  ## Bring a third of them to exactly one decay tick from death, so the
  ## income pass kills them as it walks.
  for k in 0 ..< 15:
    w.trees[planted[k]].health = bulletTreeDecayRate
    w.trees[planted[k]].roundsAlive = TreeGrowthRounds + 1
  for k in 15 ..< 45:
    w.trees[planted[k]].roundsAlive = TreeGrowthRounds + 1
  var visits = initTable[int, int]()
  for id in w.treeKeys.forEachValue:
    visits.mgetOrPut(id, 0) += 1
  checkEq("the tree walk visits every tree", visits.len, 45)
  var multiple = 0
  for id, n in visits:
    if n != 1: inc multiple
  checkEq("exactly once", multiple, 0)
  let before = w.treesAlive(tA)
  w.updateTrees()
  checkEq("and the real income pass fells the fifteen that ran out",
    before - w.treesAlive(tA), 15)
  check("while the other thirty paid income",
    w.bulletSupplyOf(tA) > 0'f32)

# --- the fold the parity trace carries --------------------------------------
block:
  var m = initTroveIntMap()
  for id in [14, 15, 16, 17, 34, 35]: m.put(id)
  let a = trove.fnv1a64(m.valuesArray())
  checkEq("the fold is stable", a, trove.fnv1a64(m.valuesArray()))
  checkEq("it is the same wire format bc22 uses", a,
    trove22.fnv1a64(m.valuesArray()))
  check("and it moves when the order does",
    trove.fnv1a64(@[17, 16, 15, 14, 34, 35]) != a)
  checkEq("fnv1a64 of nothing is the offset basis", trove.fnv1a64([]),
    0xcbf29ce484222325'u64)

finish("test_bc17_trove")
