## `saber`'s war: the unit mix, the defend radius and the military state
## machine.
##
## Behaviour source: `m-schier/battlecode-2019-wololo@ebdd279`,
## `robot.js:60-66` (`MILITARY_STATE`: `TARGET_MIRROR`, `HOLD`,
## `TARGET_TARGETS`, `HOME`, `CHARGE`), `:84-86` (`CHARGE_DURATION`) and
## `:1749-1770`, GPL-3.0.

import ../constants, ../units, ../world, ../knobs
import kit, econ, micro, lattice, infiltrate

export kit

const ChargeDuration* = 6
  ## wololo's own `CHARGE_DURATION`.

func mix*(s: Side, round: int): UnitKind =
  ## `military.nim mix()` — which military unit the next slice of the budget
  ## buys. `unit_mix` is the PROPHET share of the military karbonite budget;
  ## `preacher_share` is the PREACHER share OF THE REMAINDER, so the crusader
  ## share is `(100 - unit_mix) * (100 - preacher_share) / 100`.
  ##
  ## The rotation is deterministic and driven by the round number rather than
  ## by a draw, because the chassis has no RNG at all.
  if s.doctrine.opening == op19PreacherRush and round <= 300:
    return ukPreacher
  let phase = (s.crusaders + s.prophets + s.preachers) mod 100
  if phase < s.doctrine.unitMix: return ukProphet
  let rest = phase - s.doctrine.unitMix
  let restSpan = max(1, 100 - s.doctrine.unitMix)
  if rest * 100 < restSpan * s.doctrine.preacherShare: return ukPreacher
  ukCrusader

func defendRadius*(s: Side): int = s.doctrine.defendRadius

proc threatenedStructure*(w: World, s: Side, r: Robot): Loc =
  ## The nearest own structure with an enemy inside `defend_radius` of it.
  ## A military unit breaks off whatever it is doing to answer that enemy —
  ## the anti-inert floor for `defend_radius: 1`, where the order never
  ## defends and its pilgrims are farmed for reclaim.
  result = Loc(x: -1, y: -1)
  var best = high(int)
  for l in s.structures:
    for e in s.enemySeen:
      if distSq(l.x, l.y, e.x, e.y) <= s.defendRadius():
        let d = distSq(l.x, l.y, r.x, r.y)
        if d < best:
          best = d
          result = Loc(x: e.x, y: e.y)
        break

proc militaryTarget*(w: World, s: Side, r: Robot): Loc =
  ## The state machine, in priority order:
  ##   1. an enemy inside `defend_radius` of one of our structures  (HOME)
  ##   2. the slot this unit holds on the lattice                   (HOLD)
  ##   3. the escort's pilgrim, while an infiltration is running    (CHARGE)
  ##   4. the nearest enemy unit we can see                (TARGET_TARGETS)
  ##   5. the MIRROR of our own nearest structure          (TARGET_MIRROR)
  let defend = threatenedStructure(w, s, r)
  if defend.x >= 0: return defend
  if r.role == RoleMilitaryEscort and s.infiltrateLaunched:
    for other in w.robots:
      if other.team == s.team and other.unit == ukPilgrim and
          other.role == RolePilgrimInfiltrator:
        return Loc(x: other.x, y: other.y)
  if latticeWanted(s) and r.unit == ukProphet:
    let slot = claimLatticeSlot(w, s, r)
    if slot.ok: return Loc(x: slot.x, y: slot.y)
  let near = s.nearestEnemyUnit(r.x, r.y)
  if near.x >= 0 and r.charge(4):
    return near
  let home = s.nearestStructure(r.x, r.y)
  if home.x >= 0:
    let m = mirrorTarget(w, home.x, home.y)
    return m
  let es = s.nearestEnemyStructure(r.x, r.y)
  if es.x >= 0: return es
  Loc(x: r.x, y: r.y)
