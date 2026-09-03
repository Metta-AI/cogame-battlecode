## `java.util.Random` and `battlecode.world.IDGenerator`, ported exactly.
##
## The Battlecode engine seeds its world RNG from the map file's own
## `randomSeed` field and draws robot ids out of an `IDGenerator` seeded the
## same way. Both are `java.util.Random` underneath, so reproducing the
## 48-bit LCG bit for bit is what makes the Nim sim's cheese spawns, cat
## coin flips and **robot ids** line up with the Java engine's — which is in
## turn what makes the `parity-oracle` CI job able to diff a trace row for
## row (docs/PARITY.md).
##
## Nothing here is approximate. `nextInt(bound)` keeps both of Java's
## branches (the power-of-two shortcut and the rejection loop),
## `nextInt(origin, bound)` keeps `RandomSupport.boundedNextInt`'s three
## cases, and `nextFloat`/`nextDouble` keep the exact mantissa widths.

type
  JavaRandom* = object
    ## The 48-bit linear congruential generator behind `java.util.Random`.
    seed*: int64

  IdGenerator* = object
    ## `battlecode/world/IDGenerator.java`. Blocks of 4096 ids from 10000 up,
    ## Fisher-Yates shuffled with the same `nextInt(i+1)` call order.
    random*: JavaRandom
    reserved*: array[4096, int32]
    cursor*: int
    nextIdBlock*: int

const
  Multiplier = 0x5DEECE66D'i64
  Addend = 0xB'i64
  Mask = (1'i64 shl 48) - 1
  IdBlockSize* = 4096
  MinId* = 10000

proc initJavaRandom*(seed: int): JavaRandom =
  ## `new Random(seed)` — the constructor scrambles the seed. Java takes a
  ## `long`; every caller here passes a map/episode seed that arrived as a
  ## 32-bit `int`, so it is sign-extended exactly as Java does.
  result.seed = (int64(int32(seed)) xor Multiplier) and Mask

proc next(rng: var JavaRandom, bits: int): int32 =
  ## Java's `>>> (48 - bits)` on the 48-bit state, then narrowed to `int`.
  ## The narrowing is a CAST, not a range-checked conversion: `next(32)` is
  ## routinely negative as a Java `int` and a checked conversion would raise
  ## on exactly the draws that matter.
  ## The LCG step is done in uint64: `seed * 0x5DEECE66D` overflows a signed
  ## 64-bit int on most states, and Java's `long` wraps where Nim's `int64`
  ## would raise.
  rng.seed = cast[int64](
    (cast[uint64](rng.seed) * cast[uint64](Multiplier) +
      cast[uint64](Addend)) and cast[uint64](Mask))
  cast[int32](uint32(rng.seed shr (48 - bits)))

proc nextInt*(rng: var JavaRandom): int32 =
  rng.next(32)

proc wrapAddSub(u, r, m: int32): int32 =
  ## Java's `u - r + m` on `int`s: it OVERFLOWS on purpose, and that overflow
  ## IS the rejection test. Nim's checked int32 arithmetic would raise there,
  ## so the wrap is done in uint32 and reinterpreted.
  cast[int32](cast[uint32](u) - cast[uint32](r) + cast[uint32](m))

proc nextInt*(rng: var JavaRandom, bound: int): int32 =
  ## `Random.nextInt(bound)`. Both branches are load-bearing: the
  ## power-of-two shortcut consumes ONE draw, the general case may consume
  ## several through the rejection loop, and a port that keeps only the
  ## modulo form desynchronises the whole stream on the first
  ## non-power-of-two bound.
  doAssert bound > 0, "bound must be positive"
  let m = int32(bound - 1)
  var u = rng.next(31)
  if (bound and (bound - 1)) == 0:
    return int32((int64(bound) * int64(u)) shr 31)
  var r = u mod int32(bound)
  while wrapAddSub(u, r, m) < 0:
    u = rng.next(31)
    r = u mod int32(bound)
  r

proc nextInt*(rng: var JavaRandom, origin, bound: int): int32 =
  ## `Random.nextInt(origin, bound)` == `RandomSupport.boundedNextInt`.
  ## Half-open: `[origin, bound)`. The engine calls this as
  ## `nextInt(-4, 4)` for cheese-mine offsets, which lands in case (2).
  var r = rng.nextInt()
  if origin < bound:
    let
      n = bound - origin
      m = int32(n - 1)
    if (n and (n - 1)) == 0:
      r = cast[int32](cast[uint32](r) and cast[uint32](m)) + int32(origin)
    elif n > 0:
      var u = cast[int32](cast[uint32](r) shr 1)
      r = u mod int32(n)
      while wrapAddSub(u, r, m) < 0:
        u = cast[int32](cast[uint32](rng.nextInt()) shr 1)
        r = u mod int32(n)
      r = r + int32(origin)
    else:
      while r < int32(origin) or r >= int32(bound):
        r = rng.nextInt()
  r

proc nextFloat*(rng: var JavaRandom): float32 =
  ## 24 mantissa bits, exactly as Java. The cheese-mine spawn test is
  ## `rand.nextFloat() < probability`, so the mantissa width decides whether
  ## a mine fires on a given round.
  float32(rng.next(24)) / float32(1 shl 24)

proc nextDouble*(rng: var JavaRandom): float64 =
  let hi = int64(rng.next(26)) shl 27
  let lo = int64(rng.next(27))
  float64(hi + lo) * (1.0 / float64(1'i64 shl 53))

proc nextBoolean*(rng: var JavaRandom): bool =
  rng.next(1) != 0

# ---------------------------------------------------------------------------
#  IDGenerator
# ---------------------------------------------------------------------------

proc allocateNextBlock(gen: var IdGenerator) =
  gen.cursor = 0
  for i in 0 ..< IdBlockSize:
    gen.reserved[i] = int32(gen.nextIdBlock + i + 1)
  for i in countdown(IdBlockSize - 1, 1):
    let index = int(gen.random.nextInt(i + 1))
    let a = gen.reserved[index]
    gen.reserved[index] = gen.reserved[i]
    gen.reserved[i] = a
  gen.nextIdBlock += IdBlockSize

proc initIdGenerator*(seed: int): IdGenerator =
  result.random = initJavaRandom(seed)
  result.nextIdBlock = MinId
  result.allocateNextBlock()

proc nextId*(gen: var IdGenerator): int =
  result = int(gen.reserved[gen.cursor])
  inc gen.cursor
  if gen.cursor == IdBlockSize:
    gen.allocateNextBlock()
