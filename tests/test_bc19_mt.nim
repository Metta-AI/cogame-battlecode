## MT19937 — bc19's ONE generator, and its ONE live draw site.
##
## The vectors are the pinned `mersenne-twister@1.1.0`'s own output,
## generated in this sandbox by `npm pack mersenne-twister@1.1.0` and read
## from `src/mersenne-twister.js` — the package `coldbrew/game.js:53-54`
## constructs from the map seed and the ONLY seeded randomness in the engine.

import harness
import battlecode/years/bc19/[mt19937, world, maps, units]

block:
  ## `init_seed(s)` = `init_genrand` with `mt[0] = s >>> 0`, and `random_int`
  ## is `genrand_int32`. The first eight outputs for five seeds, verbatim
  ## from the npm package.
  const Vectors = [
    (0'u32, [2357136044'u32, 2546248239'u32, 3071714933'u32, 3626093760'u32,
             2588848963'u32, 3684848379'u32, 2340255427'u32, 3638918503'u32]),
    (1'u32, [1791095845'u32, 4282876139'u32, 3093770124'u32, 4005303368'u32,
             491263'u32, 550290313'u32, 1298508491'u32, 4290846341'u32]),
    (43'u32, [494155588'u32, 2134003008'u32, 2615920895'u32, 442015537'u32,
              572909845'u32, 638974010'u32, 1033324560'u32, 739303731'u32]),
    (2147483647'u32, [1689602031'u32, 3831148394'u32, 2820341149'u32,
                      2744746572'u32, 370616153'u32, 3004629480'u32,
                      4141996784'u32, 3942456616'u32]),
    # `0x80cf1cc5 mod 2^31` -- the pinned engine commit's own prefix, so the
    # vector set cannot be mistaken for a copy of somebody else's.
    (13573317'u32, [3352246537'u32, 1702106067'u32, 1150665675'u32,
                    515736280'u32, 1421042118'u32, 140708556'u32,
                    2169373326'u32, 1939267223'u32])]
  for v in Vectors:
    var g = newMt19937(v[0])
    for i in 0 .. 7:
      checkEq("initSeed(" & $v[0] & ") draw " & $i, g.randomInt(), v[1][i])

block:
  ## `random()` is `random_int() * (1.0 / 4294967296.0)` — divided by 2^32,
  ## which is exactly representable in float64, so the comparison
  ## `random() > 0.5` the coin flips make is exact in both languages.
  var a = newMt19937(43)
  var b = newMt19937(43)
  for i in 0 .. 999:
    let want = float64(a.randomInt()) * (1.0 / 4294967296.0)
    checkEq("random() == randomInt() / 2^32 at " & $i, b.random(), want)
  var c = newMt19937(7)
  for i in 0 .. 999:
    let r = c.random()
    check("and it is in [0, 1) at " & $i, r >= 0.0 and r < 1.0)

block:
  ## Save and restore of the whole 624-word state and `mti`, which is what
  ## the committed map files carry (V3) and what the per-round hash chain
  ## folds (D1.2).
  var g = newMt19937(43)
  for _ in 0 .. 900: discard g.randomInt()      ## past one reload of the block
  let words = g.saveState()
  let mti = g.mti
  checkEq("the state is 624 words", words.len, MtN)
  var h: Mt19937
  h.loadState(words, mti)
  checkEq("and `mti` round-trips", h.mti, mti)
  for i in 0 .. 199:
    checkEq("a restored generator draws identically at " & $i,
      h.randomInt(), g.randomInt())
  var k: Mt19937
  k.loadState(words, mti)
  checkEq("the fold of a restored state matches", k.stateFold(), h.stateFold())
  var different = newMt19937(44)
  check("and two different states fold differently",
    different.stateFold() != k.stateFold())

block:
  ## THE ID DRAW LOOP: exactly ONE draw per attempt, rejected only on a
  ## collision with an already-spent id, and the id is `1 + floor(4095 *
  ## random())` so it is in 1..4095 and NEVER 0 and never 4096.
  let spec = loadMap("seed-0043")
  var w = newWorld(spec, 1000)
  ## The world restored the committed post-`makeMap` state and then drew one
  ## id per initial castle.
  checkEq("the initial castles are all there",
    w.robots.len, spec.castles.len)
  checkEq("and exactly that many ids are spent", w.idsSpent.len, spec.castles.len)
  for id in w.idsSpent:
    check("every drawn id is in 1..4095", id >= 1 and id <= MaxId - 1)
  var seen: seq[int]
  for id in w.idsSpent:
    check("and no id is drawn twice", id notin seen)
    seen.add(id)
  ## A fresh world from the same committed state draws THE SAME ids — which
  ## is the whole point of committing the state.
  var w2 = newWorld(spec, 1000)
  for i in 0 ..< w.idsSpent.len:
    checkEq("the id stream is a pure function of the committed state at " & $i,
      w2.idsSpent[i], w.idsSpent[i])

block:
  ## V4 — THE GUARD THE ENGINE LACKS. The engine's rejection loop
  ## (`game.js:433-434`) never terminates once all 4 095 ids are spent: it
  ## draws, finds the id spent, and draws again, forever. **THIS TEST
  ## DOCUMENTS THAT THE ENGINE WOULD HANG HERE.** The port refuses the build
  ## instead, because "degrade, never hang" outranks fidelity to a hang.
  let spec = loadMap("seed-0009")
  var w = newWorld(spec, 1000)
  check("a fresh world is nowhere near the floor", not w.idPoolExhausted())
  for id in 1 .. MaxId - 1:
    if not w.idIsSpent.getOrDefault(id, false):
      w.idsSpent.add(id)
      w.idIsSpent[id] = true
  checkEq("with every id spent the pool holds 4095", w.idsSpent.len, MaxId - 1)
  check("and the guard fires", w.idPoolExhausted())

finish("test_bc19_mt")
