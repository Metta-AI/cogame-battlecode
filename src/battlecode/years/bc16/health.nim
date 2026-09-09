## bc16 health, infection and what a death leaves behind — the PURE half.
##
## Ported from `world/InternalRobot.java:228-293` (the infection counters,
## `processBeingInfected` and `changeHealthLevel`'s cap) and
## `world/GameWorld.java:857-903` (`visitDeathSignal`'s ordered consequences)
## at commit `11a0b09f26a70da19f33a61ebec4ceaf6e161aa3`.
##
## **A LAYOUT NOTE, and it is a divergence from the design note's file table
## (recorded in `docs/RULES-BC16.md` §Divergences item 14).** The note asks for
## a `health.nim` carrying "the single `changeHealthLevel` mutation point with
## its cap, its `source == TURRET` flag, its death path, the rubble deposit,
## the infection->zombie conversion and the mid-turn `DESTROYED` check". The
## MUTATION half of that list has to reach world state — the rubble array, the
## occupancy index, the exec list, `spawnRobot` for the zombie that stands up
## — so in Nim it must live beside that state, in `world.nim`, or the two files
## import each other. So the split is:
##
## * **here**: the two infection counters and their independence, the viper
##   tick's damage, the health cap, and `deathConsequence` — the ORDERED
##   DECISION a death makes (does it leave rubble, how much, does it stand back
##   up, and as what);
## * **`world.nim`**: `changeHealthLevel`, which applies exactly that decision
##   once, and is still the ONE mutation point for health.
##
## Nothing else moved: `NOTICE`, `knobs.nim`'s pointer and
## `docs/RULES-BC16.md` all name this pair.
##
## **The two infection counters are INDEPENDENT and `isInfected()` is their
## OR** (`:236-246`). A VIPER hit sets `viperInfectedTurns = 20`; ANY zombie
## hit sets `zombieInfectedTurns = 10`; a viper hit does NOT touch the zombie
## counter and vice versa. `processBeingInfected` (`:248-256`) runs inside
## `processEndOfTurn` AND ONLY WHEN `health > 0` (`GameWorld.java:173-175`):
## the viper strain deals EXACTLY 2.0 damage — which can kill, and a robot
## that dies that way IS infected, so it becomes a zombie — and each counter
## that is above zero is then decremented.

import units

export units

type
  Infection* = object
    zombieTurns*: int
    viperTurns*: int

  DeathConsequence* = object
    ## `visitDeathSignal`'s two mutually exclusive outcomes, decided once.
    ## THE TWO ARE EXCLUSIVE BY CONSTRUCTION: an infected corpse leaves no
    ## wall, and an uninfected one never stands up. That single `if`
    ## (`GameWorld.java:869`) is why `infection_policy` is a real knob.
    rubbleAdded*: float64
    becomesZombie*: bool
    zombieType*: RobotType

func isInfected*(inf: Infection): bool =
  inf.zombieTurns > 0 or inf.viperTurns > 0

func infectedTurns*(inf: Infection): int =
  ## `RobotControllerImpl.getInfectedTurns` == `max` of the two.
  max(inf.zombieTurns, inf.viperTurns)

proc setInfected*(inf: var Infection, attacker: RobotType) =
  ## `InternalRobot.setInfected`: a VIPER sets the viper counter to ITS OWN
  ## `infectTurns` (20); any zombie sets the zombie counter to its own (10).
  ## Anything else does nothing — and the caller only reaches here when
  ## `attacker.canInfect() and target.isInfectable()`.
  if attacker == rtViper:
    inf.viperTurns = RobotSpecs[rtViper].infectTurns
  elif RobotSpecs[attacker].isZombie:
    inf.zombieTurns = RobotSpecs[attacker].infectTurns

proc tickInfection*(inf: var Infection): float64 =
  ## `processBeingInfected`, split so the caller can apply the damage through
  ## the one mutation point. Returns the damage to take (2.0 or 0.0) and
  ## decrements each live counter.
  ##
  ## THE ENGINE'S ORDER IS LOAD-BEARING: it takes the damage FIRST and then
  ## decrements the viper counter, so a 20-turn viper infection deals 40 total
  ## — not enough on its own to kill a full 60-HP soldier.
  result = 0.0
  if inf.viperTurns > 0:
    result = ViperInfectionDamage
    inf.viperTurns -= 1
  if inf.zombieTurns > 0:
    inf.zombieTurns -= 1

func cappedHealth*(health, maxHealth: float64): float64 =
  ## `changeHealthLevel`'s cap: `if (healthLevel > maxHealth) healthLevel =
  ## maxHealth`. Strictly greater, so the cap is idempotent.
  if health > maxHealth: maxHealth else: health

func isDead*(health: float64): bool = health <= 0.0
  ## `changeHealthLevel`'s death test is `<= 0`, so a robot at
  ## 0.0000000001 health is alive.

func deathConsequence*(kind: RobotType, maxHealth: float64,
                       cause: DeathCause, infected: bool): DeathConsequence =
  ## `visitDeathSignal` (`:857-903`) in exactly the engine's order, minus the
  ## state mutation:
  ##
  ##   (b) if the cause is NOT `ACTIVATION` and the robot is NOT infected ->
  ##       `rubble += rubbleFactor * maxHealth`, where `rubbleFactor` is 1.0
  ##       normally and 1/3 when a TURRET landed the killing blow;
  ##   (d) if the robot WAS infected and the cause is not `ACTIVATION` ->
  ##       spawn `type.turnsInto` on `Team.ZOMBIE` at the same square.
  ##
  ## `maxHealth` is the DYING ROBOT'S OWN max (outbreak-scaled for a zombie),
  ## so a level-9 BIGZOMBIE leaves 1500 rubble and an archon 1000.
  result = DeathConsequence(rubbleAdded: 0.0, becomesZombie: false,
                            zombieType: kind)
  if cause == dcActivation:
    return
  if not infected:
    result.rubbleAdded = rubbleFactorFor(cause) * maxHealth
  elif hasTurnsInto(kind):
    result.becomesZombie = true
    result.zombieType = kind.turnsInto()
