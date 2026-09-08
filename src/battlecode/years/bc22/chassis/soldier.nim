## `soldier.nim` — the general-purpose attacker, and the sage.
##
## The 2022 metagame in one unit: a soldier costs 75 lead, has 50 health and
## deals 3 damage at r2 <= 13. A sage costs 20 GOLD, has 100 health and deals
## **45** — fifteen soldiers' worth — once every twenty turns, and is the only
## unit that can ENVISION an anomaly.
##
## Behaviour ported from `iliao2345/Battlecode2022` `src/fury_fix_20/` (AGPL-3.0)
## for the spearhead's target selection and the sage's `0.6 x cooldown` advance
## gate. BEHAVIOUR, NOT CODE. `NOTICE` names the file.
##
## The sage's envision choice is the chassis's, NOT a doctrine knob (§Out of
## scope: exposing it as a twelfth knob would let a doctrine pick the value that
## does nothing on the board in front of it, which the anti-inert rule forbids).
## The rule is nearest-value-first: **FURY** against a visible turret cluster,
## **CHARGE** against a visible enemy droid clump, **ABYSS** otherwise.

import ../anomaly as simAnomaly
import kit, micro
import anomaly as chassisAnomaly

export kit, micro

const SageAdvanceFraction* = 60
  ## `roundsSinceShot >= 0.6 * actionCooldown`, in percent — the first-place
  ## bot's own rule. A sage that walks into range with 150 turns of cooldown
  ## left is a 100-HP gift.

proc bestEnvision(w: World, side: Side, r: Robot): tuple[go: bool,
                                                         kind: AnomalyKind] =
  ## Nearest-value-first over what the sage can actually see.
  var turrets = 0
  var droidClump = 0
  var metal = 0
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtSage].actionRadiusSquared):
    if not r.spend(1): break
    let e = w.getRobot(l)
    if e != nil and e.team != side.team:
      if e.mode == rmTurret: turrets += 1
      elif e.mode == rmDroid: droidClump += 1
    metal += w.getLead(l) + w.getGold(l)
  if turrets >= 2: return (true, anFury)
  if droidClump >= 4: return (true, anCharge)
  if metal >= 200: return (true, anAbyss)
  (false, anAbyss)

proc runSoldier*(w: World, side: Side, r: Robot) =
  w.observe(side, r)
  if scatteringForCharge(side):
    let target = scatterTarget(w, side, r)
    if not (target == r.loc) and pickTarget(w, side, r) == nil:
      w.moveToward(side, r, target)
      return
  ## The spearhead: with `opening: soldier_rush` the first soldiers leave for
  ## the enemy's nearest archon at round 1; otherwise they hold the frontier
  ## between the two halves until an enemy is sensed.
  if pickTarget(w, side, r) == nil and side.lastSightingRound < 0:
    let goal =
      if side.doctrine.opening == opSoldierRush or pushingAfterCharge(side):
        nearestEnemyHome(side, r.loc)
      else:
        loc((r.loc.x + nearestEnemyHome(side, r.loc).x) div 2,
            (r.loc.y + nearestEnemyHome(side, r.loc).y) div 2)
    w.moveToward(side, r, goal)
    return
  fightOrFlee(w, side, r)

proc runSage*(w: World, side: Side, r: Robot) =
  w.observe(side, r)
  r.roundsSinceShot += 1
  ## Envision first: it is the same action slot as an attack, and 200 cooldown
  ## either way, so a sage that can hit three turrets should never spend the
  ## turn on 45 damage to one soldier.
  if r.canActCooldown():
    let choice = bestEnvision(w, side, r)
    if choice.go and w.canEnvision(r, choice.kind):
      let target = pickTarget(w, side, r)
      if target == nil or choice.kind != anAbyss:
        w.doEnvision(r, choice.kind)
        r.roundsSinceShot = 0
        return
  let target = pickTarget(w, side, r)
  if target != nil and w.canAttack(r, target.loc):
    w.doAttack(r, target.loc)
    r.roundsSinceShot = 0
    return
  ## The advance gate: a sage only walks toward the fight once its cooldown is
  ## most of the way back.
  let ready = r.roundsSinceShot * 100 >=
    RobotSpecs[rtSage].actionCooldown * SageAdvanceFraction div 10
  if not ready:
    let home = nearestLiveArchon(w, side, r.loc)
    if home != nil and chebyshev(r.loc, home.loc) > 3:
      w.moveToward(side, r, home.loc)
    return
  fightOrFlee(w, side, r)

proc runWatchtower*(w: World, side: Side, r: Robot) =
  ## A watchtower in TURRET mode shoots and never moves. In PORTABLE mode it
  ## walks, which is what the pre-FURY dodge and `watchtower_policy: forward`
  ## use it for.
  w.observe(side, r)
  if r.mode == rmPrototype: return
  if r.mode == rmTurret:
    let target = pickTarget(w, side, r)
    if target != nil and w.canAttack(r, target.loc):
      w.doAttack(r, target.loc)
    ## THE FURY DODGE: a building in PORTABLE mode takes NOTHING from a fury,
    ## and a level-1 watchtower standing in TURRET mode loses 7.
    if dodgingFury(side) and w.canTransform(r):
      w.doTransform(r)
      noteDodge(w, side, "portable_before_fury",
                -furyGlobalDelta(r.maxHealth()))
    return
  ## PORTABLE: come back down when the fury has passed, otherwise walk to where
  ## the doctrine wants the tower.
  if side.anomalyReq.standDown or not dodgingFury(side):
    if w.canTransform(r):
      w.doTransform(r)
      return
  if side.doctrine.watchtowerPolicy == wpForward:
    w.moveToward(side, r, nearestEnemyHome(side, r.loc))
