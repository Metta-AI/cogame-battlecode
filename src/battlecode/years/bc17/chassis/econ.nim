## `orchard`'s economy: the opening's budget split, the gardener target, the
## tree target and the bullet gate -- and the ONE place bullets are ever
## committed.
##
## **THE UNCONDITIONAL FLOOR LIVES HERE, and it is what makes the anti-inert
## rule a rule rather than a hope**: at EVERY setting of every knob the
## faction hires at least one GARDENER per living archon and replaces a dead
## one, plants its first tree by round 60, keeps at least three trees alive
## whenever it can afford them, and builds at least two fighters per
## gardener. Every knob moves how much of what, when -- never whether it
## plays.
##
## **THE INCOME CLIFF IS THE YEAR'S BIGGEST SURPRISE AND IT IS PRICED IN
## HERE.** The passive trickle is `max(0, 2 - 0.01 x supply)`, which is
## EXACTLY ZERO at any supply of 200 or more, and both sides start at 300 --
## measured, a 2 999-round game with no player action ends with exactly
## 300.000000000 bullets. So the entire economy is trees, and *spending below
## 200* is what turns the trickle on. `bullet_reserve`'s default of 200 is
## that number and not a taste.

import ../constants, ../units, ../world, ../knobs
import kit

export kit

func gardenerTarget*(w: World, s: Side): int =
  ## GARDENERs wanted per LIVING archon, from `gardener_count`, with the
  ## opening's halving for the three war openings -- HALVED, NEVER ZEROED.
  let archons = w.unitCount(s.team, rtArchon)
  if archons == 0: return 0
  var perArchon = s.doctrine.gardenerCount
  case s.doctrine.opening
  of op17TreeFarm: discard
  of op17TankRush, op17LumberjackSwarm, op17ScoutSquat:
    perArchon = max(GardenerPerArchonFloor, (perArchon + 1) div 2)
  max(GardenerPerArchonFloor, perArchon) * archons

func treeTarget*(w: World, s: Side): int =
  ## Trees wanted, from the opening and the gardener count. A war opening
  ## still farms: the target is halved, and the floor of three stands at
  ## every setting.
  let gardeners = max(1, w.unitCount(s.team, rtGardener))
  var perGardener = 6
  case s.doctrine.opening
  of op17TreeFarm: perGardener = 6
  of op17TankRush, op17LumberjackSwarm: perGardener = 3
  of op17ScoutSquat: perGardener = 4
  max(TreesAliveFloor, gardeners * perGardener)

func bulletGate*(w: World, s: Side): float32 =
  ## The floor below which the faction funds ONLY gardeners, trees and water:
  ## no fighters, no donations, no pentads. `bullet_reserve`, as an f32.
  float32(s.doctrine.bulletReserve)

func canSpend*(w: World, s: Side, amount: float32,
               essential = false): bool =
  ## The single affordability test. `essential` is the floor's escape hatch:
  ## a gardener the faction does not have, or its first three trees, are
  ## funded THROUGH the reserve, because a reserve that starves the farm is
  ## a reserve that loses the game.
  let free = w.uncommitted(s)
  if free < amount: return false
  if essential: return true
  free - amount >= w.bulletGate(s)

func wantsGardener*(w: World, s: Side): bool =
  w.unitCount(s.team, rtGardener) < w.gardenerTarget(s)

func gardenerIsEssential*(w: World, s: Side): bool =
  ## The floor: at least one gardener per living archon, always -- and a
  ## SECOND one funded through the reserve as well, because a single gardener
  ## is a single ten-turn slot for the whole faction and one lumberjack
  ## strike away from an economy that cannot restart. Two is the smallest
  ## number that survives a raid; everything above it is `gardener_count`'s
  ## business and pays the reserve.
  let archons = max(1, w.unitCount(s.team, rtArchon))
  w.unitCount(s.team, rtGardener) <
    min(w.gardenerTarget(s), archons * (GardenerPerArchonFloor + 1))

func wantsTree*(w: World, s: Side): bool =
  w.treesAlive(s.team) < w.treeTarget(s)

func treeIsEssential*(w: World, s: Side): bool =
  ## The first three trees, and the first tree by round 60, are funded
  ## through the reserve at every knob setting.
  w.treesAlive(s.team) < TreesAliveFloor or
    (w.treesAlive(s.team) == 0 and w.currentRound <= FirstTreeByRound)

func militaryTarget*(w: World, s: Side): int =
  ## Fighters wanted: two per gardener as the floor, plus the opening's own
  ## appetite. `orchard` never runs an army it cannot feed, so the target is
  ## also bounded by the income the farm actually produces.
  let gardeners = max(1, w.unitCount(s.team, rtGardener))
  var perGardener = FightersPerGardenerFloor
  case s.doctrine.opening
  of op17TreeFarm: perGardener = 3
  of op17TankRush: perGardener = 10
  of op17LumberjackSwarm: perGardener = 10
  of op17ScoutSquat: perGardener = 6
  let mature = w.matureTrees(s.team)
  ## **THE ARMY IS BOUNDED BY THE FARM THAT FEEDS IT.** A faction whose
  ## target is its appetite rather than its income spends its trees on
  ## soldiers, stops watering, and dies to the decay -- measured. A mature
  ## tree pays 1 bullet a round, so `4 + mature x 2` is the census the income
  ## can replace, and the two-per-gardener floor stands under it at every
  ## knob setting.
  max(FightersPerGardenerFloor * gardeners,
      min(perGardener * gardeners, 4 + mature * 2))

func fightersAlive*(w: World, s: Side): int =
  w.unitCount(s.team, rtSoldier) + w.unitCount(s.team, rtTank) +
    w.unitCount(s.team, rtLumberjack) + w.unitCount(s.team, rtScout)

func wantsFighter*(w: World, s: Side): bool =
  w.fightersAlive(s) < w.militaryTarget(s)

func fighterIsEssential*(w: World, s: Side): bool =
  ## The floor `orchard` holds at EVERY knob setting: **two fighters per
  ## gardener**. A farm nobody guards is a farm a single scout takes apart,
  ## and the anti-inert rule is what makes this a floor rather than a
  ## preference -- so these are funded before the next tree and through the
  ## reserve.
  w.fightersAlive(s) <
    FightersPerGardenerFloor * max(1, w.unitCount(s.team, rtGardener))
