## `bulwark`'s target selection — the war's "what do I shoot" half.
##
## Priority, in order, and it is the same for every unit that can attack:
##
## 1. a target THIS ATTACK WILL KILL (refusing a free kill is not a strategy,
##    and it is what makes `retreat_hp` and `zombie_kiting` safe at every
##    setting);
## 2. a ZOMBIEDEN inside range, but only once `dens.nim` has committed;
## 3. the lowest-health hostile, with ties broken by threat: vipers first
##    (a 20-turn infection is 40 damage and an enemy zombie), then soldiers,
##    then guards, then unpacked turrets, then zombies by descending damage.
##
## **IT NEVER SELECTS A FRIENDLY SQUARE.** Friendly fire is legal in 2016
## (rule 3.2.3: there is no team check on the attack path at all) and this
## chassis never uses it; `tests/test_bc16_baselines.nim` asserts that over
## whole games.

import ../world
import kit

export kit

func threatRank*(k: RobotType): int =
  ## Higher is more urgent.
  case k
  of rtViper: 90
  of rtSoldier: 80
  of rtTurret: 75
  of rtGuard: 60
  of rtBigzombie: 55
  of rtFastzombie: 50
  of rtRangedzombie: 45
  of rtStandardzombie: 40
  of rtTtm: 30
  of rtScout: 20
  of rtArchon: 70
  of rtZombieden: 10

proc pickTarget*(w: World, s: Side, r: Robot,
                 denCommitted: bool): tuple[ok: bool, at: Loc] =
  ## One pass over the hostiles this robot can sense, in INSERTION ORDER —
  ## which is the order the engine returns them in, so two identical
  ## situations resolve identically.
  result = (ok: false, at: loc(-1, -1))
  if not canAttack(r.kind): return
  if not r.d.isWeaponReady(): return
  var bestScore = -1.0e18
  for other in w.senseHostileRobots(r, -1):
    if not r.spend(1): break
    if not w.canAttackLocation(r, other.loc): continue
    let rate = guardRate(r.kind, other.kind)
    let dealt = damageToTarget(r.attackPower * rate, other.kind)
    var score = float64(threatRank(other.kind))
    ## A GUARD deals DOUBLE damage to a zombie and blocks 4 off any hit above
    ## 10, so it is the anti-horde unit and ranks the horde first.
    if r.kind == rtGuard and other.team == teamZombie: score += 60.0
    ## A kill dominates everything below it.
    if dealt >= other.health: score += 10_000.0
    if other.kind == rtZombieden:
      if denCommitted: score += 200.0 else: score -= 5_000.0
    ## Among survivors, prefer the one closest to death.
    score += max(0.0, 400.0 - other.health)
    if score > bestScore:
      bestScore = score
      result = (ok: true, at: other.loc)
  if result.ok and bestScore <= -1000.0:
    ## Only an uncommitted den was in range: hold fire rather than waking it
    ## for nothing.
    result = (ok: false, at: loc(-1, -1))
