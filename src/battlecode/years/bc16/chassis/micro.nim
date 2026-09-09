## `bulwark`'s movement micro: `kite()` (per `zombie_kiting`) and `retreat()`
## (per `retreat_hp`).
##
## Both have teeth because the 2016 delay table is asymmetric: a
## STANDARDZOMBIE pays movementDelay 3 and a BIGZOMBIE 4 while a SOLDIER pays
## 2 and a SCOUT 1.4, so a soldier can outrun both and shoot from r2 <= 13
## which is outside their r2 2 reach — but a FASTZOMBIE pays 1.4 AND ignores
## rubble, so it cannot be kited and must be blocked or eaten.
##
## At EVERY setting of either knob the chassis still takes an attack that
## KILLS its target (`combat.nim`) and still fights when cornered, because
## refusing a free kill is not a strategy.

import ../world
import kit

export kit

func healthPct*(r: Robot): int =
  if r.maxHealth <= 0.0: 100 else: int((r.health * 100.0) / r.maxHealth)

func kites*(s: Side, k: RobotType): bool =
  ## `never`: nothing kites. `ranged_only`: soldiers, vipers and turrets do —
  ## guards do not, because the guard IS the block. `always`: guards too.
  case s.doctrine.zombieKiting
  of zkNever: false
  of zkRangedOnly: k == rtSoldier or k == rtViper
  of zkAlways: k == rtSoldier or k == rtViper or k == rtGuard

proc closingZombie*(w: World, r: Robot): tuple[ok: bool, at: Loc] =
  ## The nearest zombie that can already reach us, or is one step from it,
  ## and that we are FASTER than. A FASTZOMBIE (1.4) and a BIGZOMBIE (4, but
  ## it ignores rubble) are handled by their delays, not by a special case.
  result = (ok: false, at: loc(-1, -1))
  var best = high(int)
  for other in w.senseHostileRobots(r, 25):
    if not r.spend(1): break
    if other.team != teamZombie: continue
    if RobotSpecs[other.kind].movementDelay <=
        RobotSpecs[r.kind].movementDelay: continue
    let d = other.loc.distanceSquaredTo(r.loc)
    if d <= best:
      best = d
      result = (ok: true, at: other.loc)

proc kite*(w: World, s: Side, r: Robot): bool {.discardable.} =
  ## Back off a closing zombie instead of trading — but only while we are
  ## still able to shoot it from outside its reach.
  if not kites(s, r.kind): return false
  let threat = w.closingZombie(r)
  if not threat.ok: return false
  let d = threat.at.distanceSquaredTo(r.loc)
  if d > r.kind.attackRadiusSquared(): return false
  if d > 5: return false                  ## already outside its reach
  w.stepToward(r, threat.at, away = true)

proc retreat*(w: World, s: Side, r: Robot): bool {.discardable.} =
  ## Disengage toward the nearest friendly archon — the only healing in the
  ## game, 1 health a turn, free. At 0 nothing retreats; at 100 a unit
  ## withdraws on the first damage it takes.
  if s.doctrine.retreatHp <= 0: return false
  if r.kind == rtArchon: return false
  if healthPct(r) >= s.doctrine.retreatHp: return false
  let home = s.nearestArchon(r.loc)
  if home.x < 0: return false
  if home.distanceSquaredTo(r.loc) <= 4: return false
  w.stepToward(r, home)
