## The two derived pollution coefficients, in Java `float`.
##
## `common/GameConstants.java`:
##
##     getSensorRadiusPollutionCoefficient(p) = (float)(1.0 / Math.pow(1.0 + p/4000.0, 2))
##     getCooldownPollutionCoefficient(p)     = (float)(1.0 + p/2000.0)
##
## Both are computed in `double` and narrowed to `float` on return, exactly as
## Java does; `Math.pow(x, 2)` is bit-identical to `x * x` over the whole
## integer domain `p in [0, 65535]` (checked against the JDK by the
## `parity-oracle` job's coefficient step, which is BLOCKING), so the closed
## form here needs no `pow` and therefore no libm.
##
## The per-robot local effect registry lives in `world.nim`, because it is
## world state; this module is pure arithmetic so `world.nim` can import it.

import std/math

func javaRoundF32*(x: float32): int =
  ## `Math.round(float)` — `(int)floor(a + 0.5f)`, with Java's saturating
  ## behaviour at the extremes. Used for the sensed radius and for the
  ## pollution reading, both of which are `Math.round` of a `float` in the
  ## engine.
  if x != x: return 0                      # NaN rounds to 0 in Java
  let shifted = floor(float64(x) + 0.5)
  if shifted >= 2147483647.0: return 2147483647
  if shifted <= -2147483648.0: return -2147483648
  int(shifted)

func sensorCoefficient*(pollution: int): float32 =
  let base = 1.0 + float64(pollution) / 4000.0
  float32(1.0 / (base * base))

func cooldownCoefficient*(pollution: int): float32 =
  float32(1.0 + float64(pollution) / 2000.0)
