## `lab.nim` — `schedule()`, `site()` and `solitude()`: the gold economy.
##
## Behaviour ported from `BSreenivas0713/Battlecode2022` `src/MPTempName/`
## (AGPL-3.0, head `c388fe8a`; 7th place, and the bot whose own directory
## history — `MPLaboratory`, `MPMoreLabs` — shows it actually iterated on the
## gold economy): the laboratory siting, the solitude gate and the transmute
## discipline. BEHAVIOUR, NOT CODE. `NOTICE` names the files.
##
## **A LABORATORY IS THE ONLY SOURCE OF GOLD IN THE GAME** other than the 20 %
## reclaim a dying robot drops, and its price in lead per gold is
## `floor(20 - 18 * exp(-k*n))` in the number `n` of friendly robots it can see
## inside r2 <= 53: **two lead a gold standing alone, eleven with forty friends
## nearby.** So `lab_solitude` is not a nicety — at 0 the faction makes gold at
## under three per cent of a sage's crowded lead-equivalent price.
##
## `lab_solitude: 12` is exactly the first-place bot's own gate
## (`transmute_cost < 6` is `n <= 12`, measured against the jar's own table).

import kit, econ

export kit

func labScheduleRound*(side: Side): int =
  ## `lab_round`, with `opening: sage_spam`'s pull-forward already applied.
  effectiveLabRound(side)

func armyReserve*(side: Side): int =
  ## The lead the laboratory LEAVES IN THE BANK for the army.
  ##
  ## Measured in phase 20 and it is not a nicety: a laboratory transmutes every
  ## turn it can, so without a reserve it drains the team to under a soldier's
  ## 75 Pb every round and the archon never affords one — on `chalice` the
  ## mirror built THREE soldiers in two thousand rounds while making 1 588
  ## gold. `soldier_sage_ratio` is a split of the ATTACK BUDGET, so the split
  ## has to hold on both sides of the tap: at 100 the reserve is 200 Pb (a
  ## soldier and a margin) and the lab effectively never fires; at 0 it is
  ## nothing and the lab takes everything.
  side.doctrine.soldierSageRatio * 2

func goldOverServed*(w: World, side: Side): bool =
  ## `soldier_sage_ratio` is a split of the ATTACK BUDGET IN LEAD-EQUIVALENT,
  ## and the laboratory is the OTHER side of that tap. Without this test the
  ## lab transmutes every turn it can and takes whatever share of the income it
  ## physically reaches — measured on `chalice`, 42 % of the faction's whole
  ## income at a ratio of 65, which is the knob having no teeth in the
  ## direction that matters. The test is against what has ACTUALLY been spent:
  ## transmute only while the gold share is at or under target. At 0 it always
  ## fires; at 100 it fires once and never again.
  let ratio = side.doctrine.soldierSageRatio
  let t = ord(side.team)
  let soldierLead =
    w.stats.soldiersBuilt[t] * RobotSpecs[rtSoldier].buildCostLead
  let goldLead = w.stats.leadSpentTransmuting[t]
  goldLead * ratio > soldierLead * (100 - ratio)

func solitudeGate*(side: Side): int =
  ## The most friendly robots the laboratory tolerates inside its r2 <= 53
  ## before it stops transmuting.
  side.doctrine.labSolitude

proc labSite*(w: World, side: Side, builderAt: Loc): Loc =
  ## The lowest-rubble square at least six squares from EVERY archon and from
  ## every remembered lead cluster — because the transmute price is a function
  ## of company and a laboratory built in the middle of the mining camp prices
  ## its own gold out of the game.
  if side.hasLabSite and not w.isLocationOccupied(side.labSite):
    return side.labSite
  var best = loc(-1, -1)
  var bestScore = high(int)
  for l in w.locationsWithinRadiusSquared(builderAt, 34):
    if not w.onTheMap(l) or w.isLocationOccupied(l): continue
    var tooClose = false
    for h in side.homeArchons:
      if chebyshev(l, h) < 6: tooClose = true
    if tooClose: continue
    var crowd = 0
    for s in side.leadSites:
      if chebyshev(l, s) <= 4: crowd += 1
    let score = navCost(w, side, l) * 40 + crowd * 25 +
      chebyshev(l, builderAt)
    if score < bestScore:
      bestScore = score
      best = l
  if best.x < 0:
    ## Nowhere far enough: take the lowest-rubble free neighbour rather than
    ## refuse to build at all. A laboratory at eleven lead a gold still makes
    ## gold; no laboratory makes none.
    best = freeSquareNear(w, side, builderAt, nearestEnemyHome(side, builderAt))
  side.labSite = best
  side.hasLabSite = best.x >= 0
  best

proc runLaboratory*(w: World, side: Side, r: Robot) =
  ## A laboratory's turn: transmute while the price is at or under the gate,
  ## and in TURRET mode transform to PORTABLE and walk away when the crowd
  ## arrives.
  w.observe(side, r)
  if r.mode == rmPrototype: return
  let friends = w.updateNumVisibleFriendlyRobots(r)
  if r.mode == rmTurret:
    ## THE FURY DODGE takes priority: a laboratory in TURRET mode loses 5 % of
    ## its max health to every fury, and in PORTABLE mode it loses nothing.
    if friends <= solitudeGate(side):
      if not goldOverServed(w, side) and
         w.teamLead(side.team) >=
           w.transmutationRate(r) + armyReserve(side) and
         w.canTransmute(r):
        w.doTransmute(r)
        return
      return
    else:
      ## Too crowded to be worth transmuting: stand up and walk.
      if w.canTransform(r):
        w.doTransform(r)
        return
    return
  ## PORTABLE: walk away from the crowd, then sit back down.
  if friends <= max(1, solitudeGate(side)):
    if w.canTransform(r):
      w.doTransform(r)
      return
  var sumX = 0
  var sumY = 0
  var n = 0
  for l in w.locationsWithinRadiusSquared(r.loc, 53):
    let f = w.getRobot(l)
    if f != nil and f.id != r.id and f.team == side.team:
      sumX += l.x
      sumY += l.y
      n += 1
  if n == 0:
    if w.canTransform(r): w.doTransform(r)
    return
  let cx = sumX div n
  let cy = sumY div n
  let away = loc(max(0, min(w.width - 1, r.loc.x + (r.loc.x - cx))),
                 max(0, min(w.height - 1, r.loc.y + (r.loc.y - cy))))
  w.moveToward(side, r, away)
