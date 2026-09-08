## `econ.nim` — the chip and paint plan, and the ONLY place chips are ever
## committed. Five of the ten knobs land here.
##
## Behaviour ported from `erikji/battlecode25` `src/SPAARK/` (AGPL-3.0, head
## `63165da`): the tower-driven build order and the ruin claim table.
##
##   plan()          <- opening
##   nextBuild()     <- unit_mix
##   srpBudget()     <- srp_priority
##   towerKindFor()  <- tower_type_order + defense_tower_chokes
##   upgradePick()   <- upgrade_policy
##
## THE ANTI-INERT FLOOR IS HERE, not in the knob table: `nextBuild` always
## returns a type a tower can pay for, `towerKindFor` always returns a kind,
## and `srpBudget` can never stop a tower spending its own paint stash on
## robots. `paint_eco` and `tower_rush` differ in WHAT they buy and WHEN, never
## in WHETHER they buy.

import kit

export kit

type
  Plan* = object
    ## What `opening` means for the first 400 rounds, as two percentages of
    ## the chip balance. After round 400 every opening converges on the
    ## `balanced` split, because an opening is an opening.
    robotShare*: int          ## chips willing to go to robots
    towerShare*: int          ## chips banked for `completeTowerPattern`
    claimFromRound*: int      ## the round soldiers start walking to ruins
    srpFromRound*: int        ## the round the clan will pay 200 for an SRP

proc plan*(side: Side, round: int): Plan =
  ## `paint_eco`: 70 % of chips to robots, ruins claimed only when a soldier
  ## is already adjacent, first SRP attempted by round 150.
  ## `tower_rush`: 70 % banked for towers, soldiers pushed to the two nearest
  ## ruins from round 1, no SRP before round 400.
  ## `balanced`: 50/50, ruins claimed opportunistically.
  ## ALL THREE BUILD ROBOTS AND ALL THREE PAINT FROM ROUND 1.
  if round > 400:
    return Plan(robotShare: 50, towerShare: 50, claimFromRound: 1,
                srpFromRound: 1)
  case side.doctrine.opening
  of opPaintEco:
    Plan(robotShare: 70, towerShare: 30, claimFromRound: 1, srpFromRound: 150)
  of opTowerRush:
    Plan(robotShare: 30, towerShare: 70, claimFromRound: 1, srpFromRound: 400)
  of opBalanced:
    Plan(robotShare: 50, towerShare: 50, claimFromRound: 1, srpFromRound: 250)

func claimRadiusSquared*(side: Side, round: int): int =
  ## `paint_eco` claims a ruin only when a soldier is already beside it for
  ## the first 400 rounds; every other opening walks up to the knob's radius.
  let r = side.doctrine.ruinClaimRadius
  if side.doctrine.opening == opPaintEco and round <= 400: 8
  else: r * r

# ---------------------------------------------------------------------------
#  What a tower builds next
# ---------------------------------------------------------------------------

proc nextBuild*(w: World, side: Side, tower: Robot): UnitType =
  ## The target census a tower builds toward, from `unit_mix` — with the
  ## floor stated in the design note held independently of every knob: at
  ## least 2 moppers and 1 splasher once the chip income allows it.
  ##
  ## Returns `utSoldier` when nothing is affordable; the caller checks
  ## `canBuildRobot` and simply does not build.
  refreshCensus(w, side)
  let total = max(1, side.soldiers + side.moppers + side.splashers)
  let mix = side.mix
  let chips = w.getMoney(side.team)

  ## The anti-inert floor first, and only once the economy can carry it.
  if chips >= UnitSpecs[utMopper].moneyCost + 200 and side.moppers < 2 and
      side.soldiers >= 2:
    return utMopper
  if chips >= UnitSpecs[utSplasher].moneyCost + 400 and
      side.splashers < 1 and side.soldiers >= 3:
    return utSplasher

  ## Otherwise: whichever type is furthest below its share of the census.
  let wantSoldier = mix.soldier * total div 100
  let wantMopper = mix.mopper * total div 100
  let wantSplasher = mix.splasher * total div 100
  var best = utSoldier
  var worst = side.soldiers - wantSoldier
  if side.moppers - wantMopper < worst:
    worst = side.moppers - wantMopper
    best = utMopper
  if side.splashers - wantSplasher < worst:
    worst = side.splashers - wantSplasher
    best = utSplasher
  ## A tower that cannot pay for the ideal type builds the cheapest thing it
  ## can, because an idle tower is the one thing no knob may produce.
  if tower.paint < UnitSpecs[best].paintCost or
      chips < UnitSpecs[best].moneyCost:
    for fallback in [utSoldier, utMopper, utSplasher]:
      if tower.paint >= UnitSpecs[fallback].paintCost and
          chips >= UnitSpecs[fallback].moneyCost:
        return fallback
  best

# ---------------------------------------------------------------------------
#  Towers
# ---------------------------------------------------------------------------

proc chokesOpen*(side: Side, round: int): bool =
  ## `defense_tower_chokes`: `never` drops `defense` from the cycle outright;
  ## `late` opens at round 900 OR the moment the clan has lost a tower;
  ## `early` opens at round 200.
  case side.doctrine.defenseTowerChokes
  of cpNever: false
  of cpLate: round >= 900 or side.lostTowerRound >= 0
  of cpEarly: round >= 200

proc towerKindFor*(w: World, side: Side): TowerKind =
  ## The cyclic preference from `tower_type_order`. `defense` is skipped
  ## whenever `defense_tower_chokes` has not opened, and the cycle continues —
  ## so a `never` clan spends those chips on money and paint towers instead of
  ## on nothing.
  let order = side.doctrine.towerTypeOrder
  let open = chokesOpen(side, w.currentRound)
  for step in 0 .. 2:
    let kind = order[(side.towerCursor + step) mod 3]
    if kind == tkDefense and not open: continue
    return kind
  ## Every entry was `defense` and the chokes are shut — impossible with a
  ## three-DISTINCT-entry array, but the fallback keeps the clan building.
  tkMoney

proc commitTowerKind*(w: World, side: Side) =
  side.towerCursor = (side.towerCursor + 1) mod 3

proc towerBudgetOk*(w: World, side: Side): bool =
  ## A tower costs 1000. Bank it only when the opening says to and the clan is
  ## not starving its robot production to do it.
  let p = plan(side, w.currentRound)
  let chips = w.getMoney(side.team)
  chips >= UnitSpecs[utLevelOneMoneyTower].moneyCost and
    (p.towerShare >= 50 or chips >= 1400)

# ---------------------------------------------------------------------------
#  Upgrades
# ---------------------------------------------------------------------------

proc upgradePick*(w: World, side: Side, r: Robot): Loc =
  ## Which friendly tower in reach gets the next 2500 or 5000 chips.
  ## `never` does not stop the clan spending — those chips go to new towers
  ## and new robots instead, which is the "spread wide" answer to "build
  ## tall". The other three name the family that gets priority; ties break
  ## toward the tower nearest the front.
  result = loc(-1, -1)
  if side.doctrine.upgradePolicy == upNever: return
  let wanted =
    case side.doctrine.upgradePolicy
    of upPaintFirst: tkPaint
    of upMoneyFirst: tkMoney
    of upDefenseFirst: tkDefense
    of upNever: tkMoney
  ## Only spend on an upgrade when the balance is above TWICE the cost, so an
  ## upgrade never eats the chips a tower or a robot was already promised.
  var best = low(int)
  for l in w.locationsWithinRadiusSquared(r.loc, BuildTowerRadiusSquared):
    if not r.spend(1): break
    let tower = w.getRobot(l)
    if tower == nil or not tower.kind.isTowerType(): continue
    if tower.team != side.team: continue
    if not tower.kind.canUpgradeType(): continue
    let cost = UnitSpecs[tower.kind.nextLevel()].moneyCost
    if w.getMoney(side.team) < cost * 2: continue
    var score = 100 - tower.loc.distanceSquaredTo(frontierFor(w, side))
    if towerKindOf(tower.kind) == wanted: score += 10_000
    if score > best:
      best = score
      result = l

# ---------------------------------------------------------------------------
#  Special Resource Patterns
# ---------------------------------------------------------------------------

proc srpBudget*(w: World, side: Side): bool =
  ## The percentage of chip INCOME reserved for `completeResourcePattern`
  ## (200 chips each) and for the soldier-turns that paint the 25 tiles.
  ##
  ## At 0 the clan never pays the 200 and spends everything on towers and
  ## robots — a real strategy on a ruin-dense map, not an idle one. At 100 it
  ## still builds robots out of the tower paint stashes, which `srp_priority`
  ## cannot touch.
  let d = side.doctrine
  if d.srpPriority <= 0: return false
  let p = plan(side, w.currentRound)
  if w.currentRound < p.srpFromRound: return false
  ## The reserve scales with the knob: at 100 a bare 200 chips is enough, at
  ## 10 the clan wants a comfortable cushion first.
  let cushion = CompleteResourcePatternCost +
    (100 - d.srpPriority) * 18
  w.getMoney(side.team) >= cushion

proc pickSrpCentre*(w: World, side: Side, r: Robot): Loc =
  ## The nearest REMEMBERED legal centre that does not overlap one of the
  ## clan's own live patterns. The overlap test is what stops the second
  ## pattern repainting the first: two 5x5s whose centres are within four
  ## tiles of each other share tiles, and the resource pattern is a
  ## two-colour picture, so the overlap breaks BOTH.
  ## Measured from HOME, not from the robot: a pattern has to survive fifty
  ## undisturbed rounds, so it belongs in the clan's own ground and not in the
  ## contested middle where the first enemy mopper through erases it.
  result = loc(-1, -1)
  let anchor = if side.homeTowers.len > 0: side.homeTowers[0] else: r.loc
  var best = high(int)
  for l in side.knownCentres:
    if not r.spend(1): break
    let d = l.distanceSquaredTo(anchor)
    if d >= best: continue
    if w.hasResourcePatternCenter(l, side.team): continue
    if overlapsProtected(side, l, 4): continue
    if not w.isValidPatternCenter(l, false): continue
    best = d
    result = l
