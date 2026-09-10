## MT19937 as `mersenne-twister@1.1.0` implements it — bc19's ONE generator.
##
## The 2019 engine constructs `new MersenneTwister(this.seed)` at
## `coldbrew/game.js:53-54` and binds `generator.random` as `this.random`. That
## is the ONLY seeded randomness in the whole engine, and after the build-time
## map generator has run (V3) it has exactly ONE live draw site: `createItem`'s
## id rejection loop (`game.js:433-434`), plus at most one coin flip per game in
## `isOver`.
##
## YEAR-LOCAL, deliberately, and NOT in `src/battlecode/rng.nim`: that module's
## docstring scopes it to `java.util.Random` + `IDGenerator`, no other year
## needs MT19937, and bc19 needs to SAVE AND RESTORE the whole 624-word state
## (the committed post-`makeMap` state, V3/D1), which no other year's generator
## does.
##
## The underlying algorithm is Matsumoto and Nishimura's Mersenne Twister,
## distributed under the three-clause BSD notice reproduced here:
##
##   Copyright (C) 1997 - 2002, Makoto Matsumoto and Takuji Nishimura,
##   All rights reserved.
##   Redistribution and use in source and binary forms, with or without
##   modification, are permitted provided that the following conditions
##   are met:
##     1. Redistributions of source code must retain the above copyright
##        notice, this list of conditions and the following disclaimer.
##     2. Redistributions in binary form must reproduce the above copyright
##        notice, this list of conditions and the following disclaimer in the
##        documentation and/or other materials provided with the distribution.
##     3. The names of its contributors may not be used to endorse or promote
##        products derived from this software without specific prior written
##        permission.
##   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
##   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED.
##
## The JavaScript wrapper is `banksean`'s `mersenne-twister@1.1.0`
## (integrity `sha1-+RZhjuQ9cXnvz2Qb7EUx65Zwl4o=`), pinned in
## `tools/oracle/bc19/engine.lock`. Nothing here is copied from it: the
## arithmetic below is the published MT19937 reference with the wrapper's two
## observable choices reproduced exactly —
##   * `init_seed(s)` is `init_genrand` with `mt[0] = s >>> 0`
##     (`src/mersenne-twister.js:90-104`), and
##   * `random()` is `random_int() * (1.0 / 4294967296.0)`, i.e.
##     `genrand_int32() / 2^32` (`:189-192`).

const
  MtN* = 624
  MtM* = 397
  MatrixA* = 0x9908_b0df'u32
  UpperMask* = 0x8000_0000'u32
  LowerMask* = 0x7fff_ffff'u32

type
  Mt19937* = object
    ## The whole generator state, and it is COPYABLE BY VALUE on purpose: the
    ## committed map file carries the 624 words and `mti` immediately after
    ## `makeMap()` returned (V3), and the runtime restores them before the
    ## first `createItem`.
    mt*: array[MtN, uint32]
    mti*: int

proc initSeed*(g: var Mt19937, s: uint32) =
  ## `init_genrand`. `mt[0] = s >>> 0`, then the Knuth TAOCP 3.106 recurrence
  ## with the 16/16 split multiply the JavaScript does to stay inside float64
  ## — in Nim it is a plain `uint32` multiply, which is the same value.
  g.mt[0] = s
  for i in 1 ..< MtN:
    let prev = g.mt[i - 1] xor (g.mt[i - 1] shr 30)
    g.mt[i] = 1812433253'u32 * prev + uint32(i)
  g.mti = MtN

proc newMt19937*(seed: uint32): Mt19937 =
  result.initSeed(seed)

proc randomInt*(g: var Mt19937): uint32 =
  ## `genrand_int32` / `random_int`: the whole tempered output word.
  if g.mti >= MtN:
    if g.mti == MtN + 1:
      g.initSeed(5489'u32)
    var kk = 0
    while kk < MtN - MtM:
      let y = (g.mt[kk] and UpperMask) or (g.mt[kk + 1] and LowerMask)
      g.mt[kk] = g.mt[kk + MtM] xor (y shr 1) xor
        (if (y and 1'u32) != 0: MatrixA else: 0'u32)
      inc kk
    while kk < MtN - 1:
      let y = (g.mt[kk] and UpperMask) or (g.mt[kk + 1] and LowerMask)
      g.mt[kk] = g.mt[kk + (MtM - MtN)] xor (y shr 1) xor
        (if (y and 1'u32) != 0: MatrixA else: 0'u32)
      inc kk
    let y = (g.mt[MtN - 1] and UpperMask) or (g.mt[0] and LowerMask)
    g.mt[MtN - 1] = g.mt[MtM - 1] xor (y shr 1) xor
      (if (y and 1'u32) != 0: MatrixA else: 0'u32)
    g.mti = 0
  var y = g.mt[g.mti]
  inc g.mti
  y = y xor (y shr 11)
  y = y xor ((y shl 7) and 0x9d2c_5680'u32)
  y = y xor ((y shl 15) and 0xefc6_0000'u32)
  y = y xor (y shr 18)
  y

proc random*(g: var Mt19937): float64 =
  ## `random()`: `random_int() * (1.0 / 4294967296.0)`. `2^32` is exactly
  ## representable in float64 and every `uint32` is, so this is exact in both
  ## languages and the `<`/`>` comparisons the engine makes on it agree.
  float64(g.randomInt()) * (1.0 / 4294967296.0)

proc saveState*(g: Mt19937): seq[uint32] =
  ## The 624 words, for the committed map file and for the parity trace's `G`
  ## line. `mti` is carried beside it.
  result = newSeq[uint32](MtN)
  for i in 0 ..< MtN: result[i] = g.mt[i]

proc loadState*(g: var Mt19937, words: openArray[uint32], mti: int) =
  doAssert words.len == MtN,
    "bc19 MT19937 state must be exactly " & $MtN & " words, got " & $words.len
  doAssert mti >= 0 and mti <= MtN,
    "bc19 MT19937 mti out of range: " & $mti
  for i in 0 ..< MtN: g.mt[i] = words[i]
  g.mti = mti

proc stateFold*(g: Mt19937): uint64 =
  ## An FNV-1a 64 fold of the 624 state words, for the per-round hash chain and
  ## the trace's `G` line. Folding the generator state is bc19's own decision
  ## and it is the cheapest possible tripwire for a missed or extra id draw
  ## (D1.2) — which, given that the id stream is the only live randomness, is
  ## the single most likely way this port can desynchronise.
  result = 0xcbf2_9ce4_8422_2325'u64
  for w in g.mt:
    var v = w
    for _ in 0 .. 3:
      result = result xor uint64(v and 0xff'u32)
      result = result * 0x100_0000_01b3'u64
      v = v shr 8
