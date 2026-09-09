## The bc16 delay pair: `coreDelay` / `weaponDelay`, their four mutators, the
## pinned `decrementDelays` (V1) and the TWO COMPOSITE HELPERS whose pairing is
## the single easiest way to break this year.
##
## Ported from `world/InternalRobot.java:297-337` and `:378-392` at commit
## `11a0b09f26a70da19f33a61ebec4ceaf6e161aa3`. Pure: a `Delays` value knows
## nothing about a `World`, which is why this is its own file.
##
## **The pairing, stated because getting it backwards is invisible until a
## parity trace diverges 400 rounds later:**
##
##     activateCoreAction(attackDelay, movementDelay):
##         setWeaponDelayUpTo(attackDelay);  addCoreDelay(movementDelay)
##     activateAttack(attackDelay, movementDelay):
##         addWeaponDelay(attackDelay);      setCoreDelayUpTo(movementDelay)
##
## They are OPPOSITE in both the set/add choice AND in which counter gets
## which argument. `clearRubble`, `move`, `build` and `activate` go through
## the first; `attackLocation` goes through the second; `repair` goes through
## NEITHER and costs nothing at all.
##
## **Readiness is strictly `< 1` on a float64** (`RobotControllerImpl.java:417,
## 422`), so a unit at exactly 1.0 core delay is NOT ready.
##
## **V1 — `decrementDelays` is pinned to `amountToDecrement = 1.0`.** The
## engine computes
## `1.0 - 0.3 * pow(max(0, 8000 - currentBytecodeLimit + prevBytecodesUsed)/8000, 1.5)`,
## which is a function of LAST TURN'S BYTECODE COUNT. There is no JVM here and
## no bytecode counter, and deriving the term from the chassis's own
## `DecisionOps` would make the chassis's implementation a RULES INPUT — every
## refactor of `bulwark` would change what a round resolves to and would have
## to bump `GameVersion`. `1.0` is exactly what the engine produces for any
## robot inside `limit - 8000` bytecodes (2000 for a 10 000-limit unit, 12 000
## for an archon or a scout), so the divergence is "every unit behaves like a
## frugal 2016 bot". The engine's whole formula is nevertheless tabled over its
## complete finite domain in `data/bc16/tables.json` and asserted by
## `tests/table_bc16_delay.nim`, and the oracle's own bots assert they stay
## inside the 1.0 branch, so the comparison is defined for the whole game.

import std/math
import constants

export constants

type
  Delays* = object
    core*: float64
    weapon*: float64

const
  PinnedDecrement* = 1.0
    ## V1. The value `decrementDelays` produces whenever
    ## `prevBytecodesUsed <= bytecodeLimit - 8000`.

func initDelays*(): Delays = Delays(core: 0.0, weapon: 0.0)

func isCoreReady*(d: Delays): bool = d.core < 1.0
func isWeaponReady*(d: Delays): bool = d.weapon < 1.0

proc addCoreDelay*(d: var Delays, time: float64) = d.core += time
proc addWeaponDelay*(d: var Delays, time: float64) = d.weapon += time

proc setCoreDelayUpTo*(d: var Delays, delay: float64) =
  d.core = max(d.core, delay)

proc setWeaponDelayUpTo*(d: var Delays, delay: float64) =
  d.weapon = max(d.weapon, delay)

proc decrementDelays*(d: var Delays) =
  ## `InternalRobot.decrementDelays` with `amountToDecrement` pinned to 1.0
  ## (V1). BOTH counters are decremented and EACH is floored at 0.0
  ## separately, exactly as the engine's two independent `if`s do.
  d.weapon -= PinnedDecrement
  d.core -= PinnedDecrement
  if d.weapon < 0.0: d.weapon = 0.0
  if d.core < 0.0: d.core = 0.0

proc activateCoreAction*(d: var Delays, attackDelay, movementDelay: float64) =
  ## `clearRubble`, `move`, `build`, `activate`.
  d.setWeaponDelayUpTo(attackDelay)
  d.addCoreDelay(movementDelay)

proc activateAttack*(d: var Delays, attackDelay, movementDelay: float64) =
  ## `attackLocation`, and NOTHING else.
  d.addWeaponDelay(attackDelay)
  d.setCoreDelayUpTo(movementDelay)

proc transformDelay*(d: var Delays) =
  ## `InternalRobot.transform`: `TURRET_TRANSFORM_DELAY = 10.0` ADDED TO BOTH
  ## counters, and there is NO READINESS CHECK on `pack`/`unpack` at all.
  d.core += float64(TurretTransformDelay)
  d.weapon += float64(TurretTransformDelay)

func engineDecrement*(bytecodeLimit, prevBytecodesUsed: int): float64 =
  ## The engine's WHOLE formula, for the table and the tests only. NO RULE IN
  ## THIS PORT CALLS IT (V1): it exists so the divergence is measured rather
  ## than asserted. `pow(x, 1.5)` is evaluated here in Nim only inside
  ## `tests/table_bc16_delay.nim`, against the JDK-generated table.
  let raw = max(0.0, float64(8000 - bytecodeLimit + prevBytecodesUsed)) / 8000.0
  1.0 - (0.3 * pow(raw, 1.5))

when isMainModule:
  discard
