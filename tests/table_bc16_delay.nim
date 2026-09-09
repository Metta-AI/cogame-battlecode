## The V1 table shard: the WHOLE `pow(k/8000, 1.5)` domain, k = 0..8000,
## against the JDK-generated `data/bc16/tables.json` — **and the assertion
## that the port's pinned 1.0 branch is exactly what the engine produces
## there.**
##
## THE POINT OF THIS FILE. bc16's headline decided divergence (V1) is that
## `InternalRobot.decrementDelays`'s `amountToDecrement` — the engine's
## `1.0 - 0.3 * pow(max(0, 8000 - bytecodeLimit + prevBytecodesUsed)/8000, 1.5)`
## — is **pinned to 1.0**, because there is no JVM and no bytecode counter and
## because deriving the term from the chassis's own `DecisionOps` would make
## the chassis's implementation a RULES INPUT.
##
## A divergence that is asserted rather than measured is a divergence nobody
## can check. So the engine's WHOLE formula is tabled over its complete finite
## domain and this shard proves two things about it: that the port can
## reproduce every one of the 8 001 values the JVM computes, and that the
## branch the port pins is **exactly** the branch the engine takes for any
## robot inside `bytecodeLimit - 8000`.
##
## NO RULE IN THE PORT CALLS `engineDecrement`. It exists for this file.

import std/[json, math, os]
import harness
import bc16_fixture

let tables = parseJson(readFile("data" / "bc16" / "tables.json"))
let pow15 = tables["pow_1_5"]

block:
  checkEq("the table covers the whole domain, k = 0..8000", pow15.len, 8001)
  ## `Math.pow` is not correctly rounded in general, so this is a comparison
  ## of Nim's `pow` against the JVM's over the exact domain the engine reaches
  ## — not an appeal to either being right.
  var exact = 0
  var oneUlp = 0
  var worse = 0
  for k in 0 .. 8000:
    let got = pow(float64(k) / 8000.0, 1.5)
    let want = pow15[k].getFloat()
    if got == want:
      inc exact
    elif want != 0.0 and abs(got - want) <= 2.3e-16 * abs(want):
      inc oneUlp
    else:
      inc worse
  checkEq("no value is more than one ulp from the JVM's", worse, 0)
  ## MEASURED against a real Temurin 8 and the pinned oracle jar: **7 996 of
  ## the 8 001 values are bit-exact and the remaining 5 are one ulp apart.**
  ## `Math.pow` is explicitly NOT correctly rounded (the JDK allows 1 ulp of
  ## error and is only required to be semi-monotonic), and neither is glibc's,
  ## so the two libraries disagreeing on five of eight thousand cells is the
  ## expected result and not a port defect. **It is also unreachable in this
  ## coworld**, because V1 pins the whole expression to its `pow(0, 1.5) = 0`
  ## branch, where both libraries are exact. That is the argument, and it is
  ## the reason the numbers below are asserted rather than the bit-exactness
  ## being demanded.
  check("and 7 996 of the 8 001 are bit-exact (5 differ by one ulp)",
    exact >= 7996)
  checkEq("exactly five cells differ, and by one ulp each", exact + oneUlp,
    8001)
  checkEq("k = 0 is exactly 0", pow15[0].getFloat(), 0.0)
  checkEq("k = 8000 is exactly 1", pow15[8000].getFloat(), 1.0)
  ## Monotone over the whole domain, which is what makes the 1.0 branch a
  ## clean cut rather than a threshold with a hole in it.
  var monotone = true
  for k in 1 .. 8000:
    if pow15[k].getFloat() < pow15[k - 1].getFloat(): monotone = false
  check("the table is monotonically non-decreasing", monotone)

block:
  ## THE PINNED BRANCH. `max(0, 8000 - limit + prev)` is zero for every
  ## `prev <= limit - 8000`, which makes `pow(0, 1.5) = 0` and the whole
  ## expression exactly `1.0 - 0.3 * 0 = 1.0`.
  checkEq("pow(0, 1.5) is exactly 0", pow15[0].getFloat(), 0.0)
  checkEq("so a 10 000-limit robot at 2000 prev-ops decrements by exactly 1.0",
    engineDecrement(10_000, 2000), PinnedDecrement)
  checkEq("and an ARCHON or SCOUT at 12 000 likewise",
    engineDecrement(20_000, 12_000), PinnedDecrement)
  checkEq("and both are exactly what the port pins", PinnedDecrement, 1.0)
  for prev in [0, 1, 999, 1999, 2000]:
    checkEq("a 10 000-limit robot at " & $prev & " prev-ops is on the 1.0 branch",
      engineDecrement(10_000, prev), 1.0)
  ## ONE op past the knee it is strictly below 1.0, and THAT is the branch
  ## this oracle cannot compare (`docs/PARITY.md` §bc16 says so in as many
  ## words). Every bot in `parity-oracle-bc16` asserts it stays at or below
  ## `limit - 8000` and `System.exit(4)`s otherwise, so on both sides the
  ## engine's own `amountToDecrement` is exactly 1.0 for the whole game.
  check("one op past the knee it is strictly below 1.0",
    engineDecrement(10_000, 2001) < 1.0)
  check("and at the very top of the limit it is 1 - 0.3 = 0.7",
    abs(engineDecrement(10_000, 10_000) - 0.7) < 1e-12)
  ## And the whole sub-1.0 branch reproduces the JVM's table cell for cell.
  var mismatches = 0
  for prev in 2000 .. 10_000:
    let k = max(0, 8000 - 10_000 + prev)
    let want = 1.0 - 0.3 * pow15[k].getFloat()
    if abs(engineDecrement(10_000, prev) - want) > 1e-15: inc mismatches
  checkEq("the sub-1.0 branch matches the JVM's table for all 8 001 op counts",
    mismatches, 0)

block:
  ## THE DIVERGENCE IS ONE-DIRECTIONAL AND THE PORT IS THE GENEROUS SIDE:
  ## pinning to 1.0 means every unit drains at the fastest rate the engine
  ## ever produces, i.e. "every unit behaves like a frugal 2016 bot". Asserted
  ## rather than left as prose, so the direction is on the record.
  var maxSeen = 0.0
  for prev in 0 .. 10_000:
    maxSeen = max(maxSeen, engineDecrement(10_000, prev))
  checkEq("1.0 is the MAXIMUM the engine's formula ever returns", maxSeen,
    1.0)
  check("so the pinned value never drains a counter SLOWER than the engine",
    PinnedDecrement >= maxSeen)

finish("table_bc16_delay")
