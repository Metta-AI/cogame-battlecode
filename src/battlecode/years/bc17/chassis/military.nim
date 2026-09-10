## `military.nim` -- `mix()`, `defend()` and the four-state machine
## `RALLY -> PUSH -> SCREEN -> ANSWER`.
##
## `mix()` serves the doctrine's three percentages OVER TIME rather than per
## build: it tracks bullets spent per type and builds the type whose spend is
## furthest below its share, which is the only way three percentages of one
## budget can be honoured when the units cost 80, 100, 100 and 300.
##
##     tanks       = soldier_tank_ratio        % of the military budget
##     lumberjacks = lumberjack_share          % of the REMAINDER
##     scouts      = scout_harass              % of what is left after those
##     soldiers    = everything still unspent
##
## At `lumberjack_share: 100` the faction has NO RANGED DAMAGE AT ALL, which
## the anti-inert floor allows because a lumberjack still kills -- and
## `micro.nim`'s own-HP rule still stops the swarm eating its own farm.

import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit, econ

export kit

func shares*(d: Doctrine17): array[RobotType, float32] =
  ## The four fighting types' shares of the military budget, from the three
  ## knobs, in the order the note's own arithmetic composes them.
  let tank = float32(d.soldierTankRatio) / 100'f32
  let rest = 1'f32 - tank
  let lumber = rest * float32(d.lumberjackShare) / 100'f32
  let rest2 = rest - lumber
  let scout = rest2 * float32(d.scoutHarass) / 100'f32
  let soldier = rest2 - scout
  result[rtTank] = tank
  result[rtLumberjack] = lumber
  result[rtScout] = scout
  result[rtSoldier] = soldier

func nextFighter*(w: World, s: Side, budget: float32): RobotType =
  ## The type whose spend is furthest below its share **AMONG THE TYPES THE
  ## FACTION CAN ACTUALLY PAY FOR RIGHT NOW** -- and never a type the doctrine
  ## gave a zero share, unless every share is zero (impossible: the four sum
  ## to 1).
  ##
  ## **THE AFFORDABILITY FILTER IS NOT AN OPTIMISATION, IT IS THE ANTI-INERT
  ## RULE.** Without it the deficit is always largest on the TANK -- 300
  ## bullets against a soldier's 100 -- so a faction on a 200-bullet farm
  ## income picks a tank it can never buy, builds nothing at all for 2 999
  ## rounds and donates the surplus instead. Measured on `HouseDivided`: zero
  ## fighters built in 400 rounds. With the filter it buys the soldier now and
  ## the tank when the farm can carry one, which is what
  ## `soldier_tank_ratio`'s percentages mean over a whole game.
  let want = shares(s.doctrine)
  var total = 0'f32
  for kind in [rtSoldier, rtTank, rtLumberjack, rtScout]:
    total = total + s.spentOn[kind]
  result = rtSoldier
  var worst = 2'f32
  var found = false
  for kind in [rtTank, rtLumberjack, rtScout, rtSoldier]:
    if want[kind] <= 0'f32: continue
    if bulletCostF(kind) > budget: continue
    let have = (if total <= 0'f32: 0'f32 else: s.spentOn[kind] / total)
    let deficit = have - want[kind]
    if deficit < worst:
      worst = deficit
      result = kind
      found = true
  if not found:
    ## Nothing is affordable: name the CHEAPEST body with a non-zero share so
    ## the caller's own affordability test is the one that refuses, and the
    ## refusal is counted rather than hidden.
    var cheapest = rtSoldier
    for kind in [rtScout, rtSoldier, rtLumberjack, rtTank]:
      if want[kind] > 0'f32:
        cheapest = kind
        break
    result = cheapest

proc noteSpend*(s: Side, kind: RobotType) =
  s.spentOn[kind] = s.spentOn[kind] + bulletCostF(kind)

func defendRadius*(s: Side): float32 = float32(s.doctrine.defendRadius)

proc threatNearOwnStuff*(w: World, s: Side, r: Robot): int =
  ## The ANSWER trigger: the nearest enemy that is within `defend_radius` of
  ## one of our archons, gardeners or trees. Charged through `senseRobots`.
  result = -1
  let enemies = w.senseRobots(r, -1'f32, ord(s.team.opponent()))
  for id in enemies:
    let e = w.robots.getOrDefault(id)
    if e == nil: continue
    if not r.chargeFor(1): break
    if w.ownStructuresNear(s, e.loc, s.defendRadius()) > 0:
      return id

func posture*(w: World, s: Side, r: Robot, answering: bool): Posture =
  ## **`tree_farm` SCREENS AND NEVER PUSHES, and that is the archetype, not
  ## timidity**: the note's own reading of it is "hire to `gardener_count`,
  ## plant to the `farm_layout`, water everything, and buy fighters only to
  ## satisfy `defend_radius`" -- the income curve that funds a 1 000-point
  ## purchase. Measured on the six `small` boards: a pushing farm trades its
  ## own archon away and BOTH mirrors end in `all_robots_destroyed` with
  ## nobody buying a single point; a screening farm reaches the round limit
  ## with 300..900 points bought. The three war openings push, which is what
  ## `tests/test_bc17_knobs.nim` measures as `opening`'s teeth.
  if answering: return poAnswer
  case s.doctrine.opening
  of op17TreeFarm: poScreen
  of op17TankRush, op17LumberjackSwarm: poPush
  of op17ScoutSquat:
    if r.kind == rtScout: poPush else: poScreen
