## `fdlibm`'s `exp`, ported bit for bit — YEAR-NEUTRAL.
##
## WHY THIS FILE EXISTS. bc21's slanderer income is
## `(int)(x * (1.0/50 + 0.03f * Math.exp(-0.001f * x)))`, and `Math.exp` is the
## ONE transcendental in the 2021 round loop. `Math.exp` is specified to be
## within 1 ulp of the correctly rounded result and is a HotSpot intrinsic, so
## it is allowed to differ between JVMs; `StrictMath.exp` is specified to be
## **exactly** the fdlibm algorithm, and in practice HotSpot's `Math.exp` agrees
## with it over the whole range this game can reach (the `parity-oracle-bc21`
## job proves that, and prints any disagreement).
##
## Nim's `math.exp` is the platform libm's, which is glibc's on the server and
## emscripten's musl-derived one in the browser. Those two are NOT the same
## function, and the sim is compiled twice from these sources and must produce
## the same integer both times or the viewer's re-derivation diverges from the
## recording. So the reference implementation is ported here and used instead.
##
## Source: `fdlibm` 5.3 `e_exp.c` (Sun Microsystems, 1993), the file
## `StrictMath.exp` is defined by. The algorithm, the constants and the
## bit-twiddling are reproduced verbatim; only the syntax is Nim's.

const
  One = 1.0
  HalF = [0.5, -0.5]
  Huge = 1.0e+300
  Twom1000 = 9.33263618503218878990e-302     ## 2^-1000
  OThreshold = 7.09782712893383973096e+02
  UThreshold = -7.45133219101941108420e+02
  Ln2HI = [6.93147180369123816490e-01, -6.93147180369123816490e-01]
  Ln2LO = [1.90821492927058770002e-10, -1.90821492927058770002e-10]
  InvLn2 = 1.44269504088896338700e+00
  P1 = 1.66666666666666019037e-01
  P2 = -2.77777777770155933842e-03
  P3 = 6.61375632143793436117e-05
  P4 = -1.65339022054652515390e-06
  P5 = 4.13813679705723846039e-08

func highWord(x: float64): uint32 =
  uint32(cast[uint64](x) shr 32)

func withHighWord(x: float64, hi: uint32): float64 =
  cast[float64]((cast[uint64](x) and 0x00000000FFFFFFFF'u64) or
                (uint64(hi) shl 32))

func fdlibmExp*(xIn: float64): float64 =
  ## `__ieee754_exp`, and therefore `StrictMath.exp`.
  var x = xIn
  var hi = 0.0
  var lo = 0.0
  var k = 0'i32
  var hx = highWord(x)
  let xsb = int((hx shr 31) and 1'u32)
  hx = hx and 0x7fffffff'u32

  # non-finite and out-of-range arguments
  if hx >= 0x40862E42'u32:
    if hx >= 0x7ff00000'u32:
      let lx = uint32(cast[uint64](x) and 0xFFFFFFFF'u64)
      if ((hx and 0xfffff'u32) or lx) != 0'u32:
        return x + x                     # NaN
      return (if xsb == 0: x else: 0.0)  # exp(+-inf) = {inf, 0}
    if x > OThreshold: return Huge * Huge
    if x < UThreshold: return Twom1000 * Twom1000

  # argument reduction
  if hx > 0x3fd62e42'u32:                # |x| > 0.5 ln2
    if hx < 0x3FF0A2B2'u32:              # and |x| < 1.5 ln2
      hi = x - Ln2HI[xsb]
      lo = Ln2LO[xsb]
      k = int32(1 - xsb - xsb)
    else:
      k = int32(InvLn2 * x + HalF[xsb])
      let t = float64(k)
      hi = x - t * Ln2HI[0]              # t*ln2HI is exact here
      lo = t * Ln2LO[0]
    x = hi - lo
  elif hx < 0x3e300000'u32:              # |x| < 2^-28
    if Huge + x > One: return One + x
  else:
    k = 0

  # x is now in the primary range
  let t = x * x
  let c = x - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))))
  if k == 0:
    return One - ((x * c) / (c - 2.0) - x)
  var y = One - ((lo - (x * c) / (2.0 - c)) - hi)
  if k >= -1021:
    y = withHighWord(y, highWord(y) + (cast[uint32](k) shl 20))
    y
  else:
    y = withHighWord(y, highWord(y) + (cast[uint32](k + 1000) shl 20))
    y * Twom1000
