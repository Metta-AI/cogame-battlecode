## `siege.nim` — the choke plan and the tower-breaking plan.
##
## Behaviour ported from `erikji/battlecode25` `src/SPAARK/` (AGPL-3.0, head
## `63165da`): the choke measurement and the converge-on-one-tower rule.
##
## The chokepoints are the narrowest passable cuts on the line between the two
## clans' starting money towers, measured ONCE at round 1 by a width test
## along that line — not a full min-cut, which no unit could afford inside its
## `DecisionOps` budget and which the doctrine does not need: what
## `defense_tower_chokes` actually wants to know is "where does the corridor
## between us narrow", and the line scan answers exactly that.

import kit, econ

export kit, econ

proc measureChokes*(w: World, side: Side) =
  ## Walk the straight line from our home to the enemy's and, at each step,
  ## count how many tiles of the perpendicular cut through that point are
  ## passable. The narrowest few points are the chokes. Deterministic, O(path
  ## length x map dimension), and run ONCE per side per game — never inside a
  ## unit's `DecisionOps` budget.
  if side.chokesMeasured: return
  side.chokesMeasured = true
  if side.homeTowers.len == 0: return
  let home = side.homeTowers[0]
  let away = side.enemyHome
  let steps = max(abs(away.x - home.x), abs(away.y - home.y))
  if steps <= 0: return
  ## The cut runs perpendicular to the dominant axis of the path.
  let horizontal = abs(away.x - home.x) >= abs(away.y - home.y)
  var scored: seq[tuple[width: int, at: Loc]]
  for step in 1 ..< steps:
    let at = loc(home.x + (away.x - home.x) * step div steps,
                 home.y + (away.y - home.y) * step div steps)
    var open = 0
    if horizontal:
      for y in 0 ..< w.height:
        if w.isPassable(loc(at.x, y)): open += 1
    else:
      for x in 0 ..< w.width:
        if w.isPassable(loc(x, at.y)): open += 1
    scored.add((width: open, at: at))
  if scored.len == 0: return
  ## Insertion sort by width ascending; the list is at most 60 long.
  for i in 1 ..< scored.len:
    var j = i
    while j > 0 and scored[j - 1].width > scored[j].width:
      swap(scored[j - 1], scored[j])
      dec j
  let keep = min(3, scored.len)
  for i in 0 ..< keep:
    side.chokes.add(scored[i].at)

proc nearestChoke*(w: World, side: Side, from0: Loc): Loc =
  result = loc(-1, -1)
  var best = high(int)
  for c in side.chokes:
    let d = c.distanceSquaredTo(from0)
    if d < best:
      best = d
      result = c

proc siegeTarget*(w: World, side: Side, r: Robot): Loc =
  ## Which enemy tower the splashers converge on: lowest HP, then nearest,
  ## then DEFENSE TOWERS FIRST because a defense tower buffs every other
  ## tower the enemy owns.
  result = loc(-1, -1)
  var best = high(int)
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not r.spend(1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team == side.team: continue
    if not bot.kind.isTowerType(): continue
    var score = bot.health + l.distanceSquaredTo(r.loc)
    if isDefenseTower(bot.kind): score -= 800
    if score < best:
      best = score
      result = l

proc chokePlan*(w: World, side: Side, r: Robot): Loc =
  ## The ruin a defense tower should rise on: the unclaimed, tower-free ruin
  ## nearest a measured choke, and only once `defense_tower_chokes` has
  ## opened. Returns `(-1, -1)` when the policy says no.
  result = loc(-1, -1)
  if not chokesOpen(side, w.currentRound): return
  if side.chokes.len == 0: return
  ## THREE defense towers is the plan, not a wall of them: each one buffs
  ## every other tower the clan owns, and the fourth buys much less than the
  ## money or paint tower those 1000 chips would otherwise be.
  if w.towerCountByKind(side.team, tkDefense) >= 3: return
  ## THE REMEMBERED RUIN LIST, not a sense sweep: a choke is a place the clan
  ## walks to on purpose, and a chassis that only ever noticed a choke ruin it
  ## happened to be standing next to would give `defense_tower_chokes` no
  ## teeth at all.
  var best = high(int)
  for l in side.knownRuins:
    if not r.spend(1): break
    if w.hasTower(l): continue
    if side.claims.hasKey(w.idx(l)): continue
    if not w.isValidPatternCenter(l, true): continue
    if overlapsProtected(side, l, 4): continue
    let c = nearestChoke(w, side, l)
    if c.x < 0: continue
    ## The soldier still has to be able to reach it: `ruin_claim_radius`
    ## bounds how far the clan spreads, on this branch as on every other.
    if l.distanceSquaredTo(r.loc) >
        claimRadiusSquared(side, w.currentRound): continue
    ## Among the ruins it CAN reach, the one nearest a measured choke.
    let d = c.distanceSquaredTo(l)
    if d < best:
      best = d
      result = l
