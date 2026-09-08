## `miner.nim` — mine and walk, and the year's signature knob.
##
## Behaviour ported from `iliao2345/Battlecode2022` `src/fury_fix_20/Miner.java`
## (AGPL-3.0): the `mine_until` floor and its losing-position override, the
## nine-square scan that takes GOLD FIRST (gold is scarcer than lead and enters
## the map only by reclaim), and the mine-move-mine turn shape — `try_to_mine`
## is called BEFORE AND AFTER the move, because a miner's action cooldown of 2
## against a limit of 10 lets it mine, move and mine again in one turn.
## BEHAVIOUR, NOT CODE. `NOTICE` names the file.
##
## `mineUntil()` IS `mine_floor`, and it is the one knob that decides whether
## the map survives the game: the map adds `+5` every 20 rounds to every square
## holding at least 1, so a miner that takes a square to zero has destroyed that
## deposit for the rest of the game. THE CHASSIS OVERRIDES THE FLOOR TO ZERO
## WHEN IT IS LOSING ON ARCHONS — the first-place bot's own rule, because a
## doomed faction does not need a farm.

import kit, econ
import anomaly as chassisAnomaly

export kit

func mineUntil*(w: World, side: Side): int =
  ## How much lead a miner leaves on a square.
  if w.brokenChassis:
    ## THE NEGATIVE CONTROL (`-d:bc22BrokenChassis`): strip-mine everything.
    return 0
  if side.archons < side.enemyArchonCount:
    ## Losing on archons: the farm is worth nothing, take it all.
    return 0
  side.doctrine.mineFloor

proc tryToMine(w: World, side: Side, r: Robot): bool {.discardable.} =
  ## The nine-square scan, gold first, in the engine's own scan order over
  ## r2 <= 2 — which is exactly the miner's own square and its eight
  ## neighbours.
  let floorLead = mineUntil(w, side)
  var acted = false
  for l in w.locationsWithinRadiusSquared(r.loc, 2):
    if not r.spend(1): break
    while w.canMineGold(r, l):
      w.doMineGold(r, l)
      acted = true
    while w.getLead(l) > floorLead and w.canMineLead(r, l):
      ## Before an ABYSS a square at or under nine loses nothing, so the timed
      ## play mines the RICH squares first and leaves the immune ones alone.
      if spendingDownForAbyss(side) and abyssImmuneSquare(w.getLead(l)):
        break
      w.doMineLead(r, l)
      acted = true
  if acted: side.minersMinedThisRound += 1
  acted

proc bestDeposit(w: World, side: Side, r: Robot): Loc =
  ## The remembered live deposit with the best amount-per-step. A DEAD SQUARE is
  ## never a target: the map never puts lead back on one.
  result = loc(-1, -1)
  var best = low(int)
  for l in side.leadSites:
    if not r.spend(1): break
    let i = w.idx(l)
    if side.deadSquare[i]: continue
    let amount = int(side.knownLead[i])
    if amount <= mineUntil(w, side): continue
    let steps = max(1, chebyshev(r.loc, l))
    let score = amount * 10 div steps - navCost(w, side, l)
    if score > best:
      best = score
      result = l
  if result.x < 0:
    ## Nothing remembered: walk toward the map centre, which on a symmetric map
    ## is where the two halves' unexplored deposits meet.
    result = mapCentre(w)

proc runMiner*(w: World, side: Side, r: Robot) =
  w.observe(side, r)
  ## Gold on the ground beats everything: it exists only where something died.
  for g in side.goldSites:
    if chebyshev(r.loc, g) <= 4 and w.getGold(g) > 0:
      if r.loc == g or w.canMineGold(r, g):
        discard
      else:
        w.moveToward(side, r, g)
      break
  discard tryToMine(w, side, r)
  ## Scatter before a CHARGE — a miner that sees four friends or fewer is never
  ## near the 5 % cut.
  if scatteringForCharge(side):
    let target = scatterTarget(w, side, r)
    if not (target == r.loc):
      w.moveToward(side, r, target)
      discard tryToMine(w, side, r)
      return
  ## Retreat from an attacker: a miner has 40 HP and no attack at all.
  var threat: Robot = nil
  for e in w.sortedEnemies(side, r, RobotSpecs[rtMiner].visionRadiusSquared):
    if canAttackType(e.kind) and e.mode.canAct:
      threat = e
      break
  if threat != nil and r.health * 100 <= maxHealthOf(rtMiner, 1) * 100:
    if chebyshev(r.loc, threat.loc) <= 3:
      w.moveAwayFrom(side, r, threat.loc)
      discard tryToMine(w, side, r)
      return
  let target = bestDeposit(w, side, r)
  if not (target == r.loc):
    w.moveToward(side, r, target)
  discard tryToMine(w, side, r)
