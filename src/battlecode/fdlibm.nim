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

# ---------------------------------------------------------------------------
#  `sin`, `cos`, `atan` and `atan2` -- added by the bc17 year module
# ---------------------------------------------------------------------------
#
# WHY THESE FOUR EXIST, AND WHY THEY ARE ADDITIVE. Battlecode 2017 is the one
# continuous-space year: every coordinate is a `float32`, every gameplay class
# is `strictfp`, and the WHOLE transcendental surface of the 2017 rule set is
# `{sqrt, atan2, sin, cos}` -- 26 `Math.` call sites, no `pow`, no `exp`, no
# `log`, no `hypot` and no `Math.random` anywhere (docs/RULES-BC17.md F1).
# `sqrt` is exactly specified by IEEE-754 and needs no port; the other three
# are HotSpot intrinsics that MAY differ from `StrictMath` at double level and
# DO -- measured over 20 000 000 samples of the engine's own argument domains,
# `Math.sin` differs from `StrictMath.sin` in 3.9 % of samples and `Math.cos`
# in 3.3 %, while `Math.atan2` was bit-identical in every one.
#
# Nim's `math.sin`/`cos`/`arctan2` are the platform libm's -- glibc's on the
# server and emscripten's musl-derived one in the browser -- and those two are
# NOT the same function, so a sim compiled twice from these sources would
# diverge between the recorder and the viewer's re-derivation. So the fdlibm
# reference implementations are ported here and used instead, and
# `tools/oracle/bc17/strictmath.patch` rewrites the engine's eleven
# `Math.{atan2,sin,cos,sqrt}` call sites to `StrictMath` so the agreement is
# ENFORCED on both sides rather than assumed.
#
# Source: `fdlibm` 5.3 (Sun Microsystems, 1993) -- `s_sin.c`, `s_cos.c`,
# `k_sin.c`, `k_cos.c`, `e_rem_pio2.c`, `s_atan.c` and `e_atan2.c`, the files
# `StrictMath.sin`, `.cos`, `.atan` and `.atan2` are DEFINED by. The
# algorithms, the constants and the bit-twiddling are reproduced verbatim;
# only the syntax is Nim's. `data/bc17/fdlibm_vectors.json` pins them against
# the JVM's own output and `tests/test_bc17_fdlibm.nim` is the gate.
#
# `fdlibmExp` above is UNTOUCHED, so no bc16 recording's arithmetic moves.

const
  ## `k_sin.c`
  SinS1 = -1.66666666666666324348e-01
  SinS2 = 8.33333333332248946124e-03
  SinS3 = -1.98412698298579493134e-04
  SinS4 = 2.75573137070700676789e-06
  SinS5 = -2.50507602534068634195e-08
  SinS6 = 1.58969099521155010221e-10
  ## `k_cos.c`
  CosC1 = 4.16666666666666019037e-02
  CosC2 = -1.38888888888741095749e-03
  CosC3 = 2.48015872894767294178e-05
  CosC4 = -2.75573143513906633035e-07
  CosC5 = 2.08757232129817482790e-09
  CosC6 = -1.13596475577881948265e-11
  ## `e_rem_pio2.c`
  InvPio2 = 6.36619772367581382433e-01
  Pio21 = 1.57079632673412561417e+00
  Pio21t = 6.07710050650619224932e-11
  Pio22 = 6.07710050630396597660e-11
  Pio22t = 2.02226624879595063154e-21
  Pio23 = 2.02226624871116645580e-21
  Pio23t = 8.47842766036889956997e-32
  NPio2Hw: array[32, uint32] = [
    0x3FF921FB'u32, 0x400921FB'u32, 0x4012D97C'u32, 0x401921FB'u32,
    0x401F6A7A'u32, 0x4022D97C'u32, 0x4025FDBB'u32, 0x402921FB'u32,
    0x402C463A'u32, 0x402F6A7A'u32, 0x4031475C'u32, 0x4032D97C'u32,
    0x40346B9C'u32, 0x4035FDBB'u32, 0x40378FDB'u32, 0x403921FB'u32,
    0x403AB41B'u32, 0x403C463A'u32, 0x403DD85A'u32, 0x403F6A7A'u32,
    0x40407E4C'u32, 0x4041475C'u32, 0x4042106C'u32, 0x4042D97C'u32,
    0x4043A28C'u32, 0x40446B9C'u32, 0x404534AC'u32, 0x4045FDBB'u32,
    0x4046C6CB'u32, 0x40478FDB'u32, 0x404858EB'u32, 0x404921FB'u32]
    ## The high words of `n * pi/2` for `n = 1 .. 32`, verbatim from
    ## `e_rem_pio2.c`'s `npio2_hw`. The medium-size branch consults it to skip
    ## the cancellation check when it provably cannot bite.
  ## `s_atan.c`
  AtanHi: array[4, float64] = [
    4.63647609000806093515e-01, 7.85398163397448278999e-01,
    9.82793723247329054082e-01, 1.57079632679489655800e+00]
  AtanLo: array[4, float64] = [
    2.26987774529616870924e-17, 3.06161699786838301793e-17,
    1.39033110312309984516e-17, 6.12323399573676603587e-17]
  AtanT: array[11, float64] = [
    3.33333333333329318027e-01, -1.99999999998764832476e-01,
    1.42857142725034663711e-01, -1.11111104054623557880e-01,
    9.09088713343650656196e-02, -7.69187620504482999495e-02,
    6.66107313738753120669e-02, -5.83357013379057348645e-02,
    4.97687799461593236017e-02, -3.65315727442169155270e-02,
    1.62858201153657823623e-02]
  AtanHuge = 1.0e300
  ## `e_atan2.c`
  Atan2Tiny = 1.0e-300
  PiOver4 = 7.8539816339744827900e-01
  PiOver2 = 1.5707963267948965580e+00
  FdPi = 3.1415926535897931160e+00
  FdPiLo = 1.2246467991473531772e-16

func lowWord(x: float64): uint32 =
  uint32(cast[uint64](x) and 0xFFFFFFFF'u64)

func fdAbs(x: float64): float64 =
  cast[float64](cast[uint64](x) and 0x7FFFFFFFFFFFFFFF'u64)

func kernelSin(x, y: float64, iy: int): float64 =
  ## `__kernel_sin`, verbatim.
  let ix = highWord(x) and 0x7fffffff'u32
  if ix < 0x3e400000'u32:            # |x| < 2**-27
    if int(x) == 0: return x
  let z = x * x
  let v = z * x
  let r = SinS2 + z * (SinS3 + z * (SinS4 + z * (SinS5 + z * SinS6)))
  if iy == 0:
    x + v * (SinS1 + z * r)
  else:
    x - ((z * (0.5 * y - v * r) - y) - v * SinS1)

func kernelCos(x, y: float64): float64 =
  ## `__kernel_cos`, verbatim -- including the `qx` branch, which is where a
  ## paraphrase loses the last bit.
  let ix = highWord(x) and 0x7fffffff'u32
  if ix < 0x3e400000'u32:
    if int(x) == 0: return 1.0
  let z = x * x
  let r = z * (CosC1 + z * (CosC2 + z * (CosC3 + z * (CosC4 +
              z * (CosC5 + z * CosC6)))))
  if ix < 0x3FD33333'u32:            # |x| < 0.3
    return 1.0 - (0.5 * z - (z * r - x * y))
  var qx: float64
  if ix > 0x3fe90000'u32:            # |x| > 0.78125
    qx = 0.28125
  else:
    qx = cast[float64]((uint64(ix - 0x00200000'u32) shl 32))   # x/4, lo = 0
  let hz = 0.5 * z - qx
  let a = 1.0 - qx
  a - (hz - (z * r - x * y))

func remPio2Medium*(x: float64, y: var array[2, float64]): int =
  ## `__ieee754_rem_pio2`'s **medium-size** branch (`|x| <= 2^19 * pi/2`) plus
  ## its two small-argument shortcuts, verbatim.
  ##
  ## THE PAYNE-HANEK BRANCH IS DELIBERATELY NOT IMPLEMENTED and cannot be
  ## reached from any 2017 gameplay path: the engine calls `sin`/`cos` only on
  ## `Direction.radians`, which `reduce()` keeps in `(-pi, pi]` by
  ## construction (`Direction.java:41-44, 273-282` -- every constructor and
  ## every rotation goes through it). `fdlibmSin`/`fdlibmCos` raise a `Defect`
  ## outside `[-4, 4]` rather than guessing, so a future caller cannot
  ## silently take an unimplemented path (docs/RULES-BC17.md V6, F4).
  let hx = cast[int32](highWord(x))
  let ix = uint32(hx) and 0x7fffffff'u32
  if ix <= 0x3fe921fb'u32:           # |x| ~<= pi/4
    y[0] = x
    y[1] = 0.0
    return 0
  if ix < 0x4002d97c'u32:            # |x| < 3pi/4, n = +-1
    if hx > 0:
      var z = x - Pio21
      if ix != 0x3ff921fb'u32:
        y[0] = z - Pio21t
        y[1] = (z - y[0]) - Pio21t
      else:
        z = z - Pio22
        y[0] = z - Pio22t
        y[1] = (z - y[0]) - Pio22t
      return 1
    else:
      var z = x + Pio21
      if ix != 0x3ff921fb'u32:
        y[0] = z + Pio21t
        y[1] = (z - y[0]) + Pio21t
      else:
        z = z + Pio22
        y[0] = z + Pio22t
        y[1] = (z - y[0]) + Pio22t
      return -1
  if ix > 0x413921fb'u32:
    raise newException(Defect,
      "fdlibm: remPio2Medium was called with |x| > 2^19*pi/2, which the " &
      "Payne-Hanek branch handles and this port deliberately does not " &
      "implement (docs/RULES-BC17.md V6). No 2017 gameplay path can reach " &
      "it: Direction.radians is always in (-pi, pi].")
  let t = fdAbs(x)
  let n = int(t * InvPio2 + 0.5)
  let fn = float64(n)
  var r = t - fn * Pio21
  var w = fn * Pio21t                # 1st round, good to 85 bits
  if n < 32 and ix != NPio2Hw[n - 1]:
    y[0] = r - w                     # quick check: no cancellation
  else:
    let j = int(ix shr 20)
    y[0] = r - w
    var i = j - int((highWord(y[0]) shr 20) and 0x7ff'u32)
    if i > 16:                       # 2nd iteration, good to 118 bits
      let t2 = r
      w = fn * Pio22
      r = t2 - w
      w = fn * Pio22t - ((t2 - r) - w)
      y[0] = r - w
      i = j - int((highWord(y[0]) shr 20) and 0x7ff'u32)
      if i > 49:                     # 3rd iteration, 151 bits
        let t3 = r
        w = fn * Pio23
        r = t3 - w
        w = fn * Pio23t - ((t3 - r) - w)
        y[0] = r - w
  y[1] = (r - y[0]) - w
  if hx < 0:
    y[0] = -y[0]
    y[1] = -y[1]
    return -n
  n

func fdlibmSinUnchecked(x: float64): float64 =
  ## `s_sin.c` over the medium reduction. No domain guard, for the callers
  ## that have already established one (the vector generator's boundary rows).
  let ix = highWord(x) and 0x7fffffff'u32
  if ix <= 0x3fe921fb'u32:
    return kernelSin(x, 0.0, 0)
  if ix >= 0x7ff00000'u32:
    return x - x                     # sin(Inf or NaN) is NaN
  var y: array[2, float64]
  let n = remPio2Medium(x, y)
  case n and 3
  of 0: kernelSin(y[0], y[1], 1)
  of 1: kernelCos(y[0], y[1])
  of 2: -kernelSin(y[0], y[1], 1)
  else: -kernelCos(y[0], y[1])

func fdlibmCosUnchecked(x: float64): float64 =
  ## `s_cos.c` over the medium reduction.
  let ix = highWord(x) and 0x7fffffff'u32
  if ix <= 0x3fe921fb'u32:
    return kernelCos(x, 0.0)
  if ix >= 0x7ff00000'u32:
    return x - x
  var y: array[2, float64]
  let n = remPio2Medium(x, y)
  case n and 3
  of 0: kernelCos(y[0], y[1])
  of 1: -kernelSin(y[0], y[1], 1)
  of 2: -kernelCos(y[0], y[1])
  else: kernelSin(y[0], y[1], 1)

func fdlibmSin*(x: float64): float64 =
  ## `StrictMath.sin`, for arguments the 2017 engine can actually produce.
  ## **Raises outside `[-4, 4]`**: every call site in the engine passes
  ## `Direction.radians`, which is in `(-pi, pi]`, so a wider argument means a
  ## caller has invented one and the honest answer is a `Defect` rather than a
  ## silently unreduced result (F4, V6).
  if not (x >= -4.0 and x <= 4.0):
    raise newException(Defect,
      "fdlibmSin: |x| > 4 (" & $x & "). Direction.radians is always in " &
      "(-pi, pi], so this argument did not come from a 2017 rule; the " &
      "Payne-Hanek reduction branch is deliberately not implemented.")
  fdlibmSinUnchecked(x)

func fdlibmCos*(x: float64): float64 =
  ## `StrictMath.cos`, with the same domain guard as `fdlibmSin`.
  if not (x >= -4.0 and x <= 4.0):
    raise newException(Defect,
      "fdlibmCos: |x| > 4 (" & $x & "). Direction.radians is always in " &
      "(-pi, pi], so this argument did not come from a 2017 rule; the " &
      "Payne-Hanek reduction branch is deliberately not implemented.")
  fdlibmCosUnchecked(x)

func fdlibmAtan*(xIn: float64): float64 =
  ## `s_atan.c`, i.e. `StrictMath.atan`, in full: the four-way argument
  ## reduction and the eleven-coefficient odd/even split.
  var x = xIn
  let hx = cast[int32](highWord(x))
  let ix = uint32(hx) and 0x7fffffff'u32
  var id = 0
  if ix >= 0x44100000'u32:           # |x| >= 2^66
    if ix > 0x7ff00000'u32 or (ix == 0x7ff00000'u32 and lowWord(x) != 0'u32):
      return x + x                   # NaN
    return (if hx > 0: AtanHi[3] + AtanLo[3] else: -AtanHi[3] - AtanLo[3])
  if ix < 0x3fdc0000'u32:            # |x| < 0.4375
    if ix < 0x3e200000'u32:          # |x| < 2^-29
      if AtanHuge + x > 1.0: return x
    id = -1
  else:
    x = fdAbs(x)
    if ix < 0x3ff30000'u32:          # |x| < 1.1875
      if ix < 0x3fe60000'u32:        # 7/16 <= |x| < 11/16
        id = 0
        x = (2.0 * x - 1.0) / (2.0 + x)
      else:                          # 11/16 <= |x| < 19/16
        id = 1
        x = (x - 1.0) / (x + 1.0)
    else:
      if ix < 0x40038000'u32:        # |x| < 2.4375
        id = 2
        x = (x - 1.5) / (1.0 + 1.5 * x)
      else:                          # 2.4375 <= |x| < 2^66
        id = 3
        x = -1.0 / x
  let z = x * x
  let w = z * z
  let s1 = z * (AtanT[0] + w * (AtanT[2] + w * (AtanT[4] +
           w * (AtanT[6] + w * (AtanT[8] + w * AtanT[10])))))
  let s2 = w * (AtanT[1] + w * (AtanT[3] + w * (AtanT[5] +
           w * (AtanT[7] + w * AtanT[9]))))
  if id < 0:
    return x - x * (s1 + s2)
  let r = AtanHi[id] - ((x * (s1 + s2) - AtanLo[id]) - x)
  if hx < 0: -r else: r

func fdlibmAtan2*(y, x: float64): float64 =
  ## `e_atan2.c`, i.e. `StrictMath.atan2`, in full: the sign/zero/infinity
  ## table and the `atan(|y/x|)` core. The domain is UNRESTRICTED because the
  ## engine's `Direction(dx, dy)` constructor takes arbitrary float32 deltas,
  ## including +-0, denormals and equal magnitudes.
  let hx = cast[int32](highWord(x))
  let ix = uint32(hx) and 0x7fffffff'u32
  let lx = lowWord(x)
  let hy = cast[int32](highWord(y))
  let iy = uint32(hy) and 0x7fffffff'u32
  let ly = lowWord(y)
  ## `(lx | -lx) >> 31` is 1 for any non-zero low word, so the two tests below
  ## are "x is NaN" and "y is NaN" exactly as the C is.
  let xNan = (ix or ((lx or (0'u32 - lx)) shr 31)) > 0x7ff00000'u32
  let yNan = (iy or ((ly or (0'u32 - ly)) shr 31)) > 0x7ff00000'u32
  if xNan or yNan:
    return x + y
  if ((uint32(hx) - 0x3ff00000'u32) or lx) == 0'u32:
    return fdlibmAtan(y)             # x = 1.0
  let m = int(((uint32(hy) shr 31) and 1'u32) or
              ((uint32(hx) shr 30) and 2'u32))   # 2*sign(x) + sign(y)
  if (iy or ly) == 0'u32:            # y = 0
    case m
    of 0, 1: return y
    of 2: return FdPi + Atan2Tiny
    else: return -FdPi - Atan2Tiny
  if (ix or lx) == 0'u32:            # x = 0
    return (if hy < 0: -PiOver2 - Atan2Tiny else: PiOver2 + Atan2Tiny)
  if ix == 0x7ff00000'u32:           # x is +-Inf
    if iy == 0x7ff00000'u32:
      case m
      of 0: return PiOver4 + Atan2Tiny
      of 1: return -PiOver4 - Atan2Tiny
      of 2: return 3.0 * PiOver4 + Atan2Tiny
      else: return -3.0 * PiOver4 - Atan2Tiny
    else:
      case m
      of 0: return 0.0
      of 1: return -0.0
      of 2: return FdPi + Atan2Tiny
      else: return -FdPi - Atan2Tiny
  if iy == 0x7ff00000'u32:           # y is +-Inf
    return (if hy < 0: -PiOver2 - Atan2Tiny else: PiOver2 + Atan2Tiny)
  let k = (cast[int32](iy) - cast[int32](ix)) shr 20
  var z: float64
  if k > 60:
    z = PiOver2 + 0.5 * FdPiLo       # |y/x| > 2^60
  elif hx < 0 and k < -60:
    z = 0.0                          # |y|/x < -2^60
  else:
    z = fdlibmAtan(fdAbs(y / x))
  case m
  of 0: z
  of 1: cast[float64](cast[uint64](z) xor 0x8000000000000000'u64)
  of 2: FdPi - (z - FdPiLo)
  else: (z - FdPiLo) - FdPi
