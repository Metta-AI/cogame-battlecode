## `bulwark`'s `dens.nim schedule()` — when the faction commits a strike group
## to killing a ZOMBIEDEN, and which one.
##
## A den is 2000 HP and pays 200 parts on death, and killing it deletes that
## den's share of EVERY FUTURE WAVE for the rest of the game (measured: a
## played-pool den holds 51 to 138 queued zombies across a game). But 2000 HP
## at a soldier's 4 damage is FIVE HUNDRED attacks, and a den damages every
## adjacent non-zombie for 10 a round whenever it has a queue. Early is a real
## investment; late is a real concession — which is exactly what
## `den_clear_round` is asking the cog to decide.
##
## The target is the den with the largest remaining queue and the cheapest
## approach, and every member of the strike group is kept OUT of the eight
## adjacent squares except while attacking.

import std/algorithm
import ../world
import kit

export kit

const
  DenStrikeGroup* = 4
    ## THE STANDING STRIKE GROUP, sized to break 2000 HP. A SOLDIER deals 4 at
    ## attackDelay 2 (**2 a round**), a GUARD 1.5 at attackDelay 1 — and
    ## **3.0 against a ZOMBIE, which a DEN is** — and a VIPER 2 at attackDelay
    ## 3. Four mixed attackers standing on a den are therefore **8-12 damage a
    ## round**, i.e. a 2000-HP den in **165-250 rounds**, which is the first
    ## number in this year that makes `den_clear_round` a real investment
    ## rather than a wish.
    ##
    ## **Four and not six, and the number is MEASURED.** The bounded
    ## den-breaking iteration swept group/garrison over
    ## (6,3) (4,6) (8,4) (5,5) (6,6) (4,4) (4,3) (4,8) (3,6) on the
    ## all-defaults mirror across the six `small` maps, and (4,4) is the only
    ## pair that both breaks dens and keeps the ring: it reaches **3 of 6**
    ## games ending other than `archons_destroyed` with **20 dens killed** and
    ## a **median of 2147 rounds**, against 1/6, 6 dens and 936 rounds for the
    ## chassis before the iteration. A LARGER group breaks more dens per
    ## commitment and loses the archons behind it ((8,4): 1/6, 9 dens, median
    ## 746); a smaller one is out-attritioned by the queue it is standing next
    ## to. The whole table is in `tests/test_bc16_survival.nim`'s header and in
    ## `docs/RULES-BC16.md` §Divergences.
  DenGarrison* = 4
    ## Kept OUT of the strike group at every setting, so committing to a den is
    ## never the same thing as abandoning the archons: the group forms only
    ## when the faction has `DenStrikeGroup + DenGarrison` = **8** attackers
    ## standing, and the nearest four go while the rest hold the ring.
  DenPressureFloor* = 220
    ## **THE `den_clear_round` FLOOR THAT COMMITS WHILE ATTACKERS ARE STILL
    ## ALIVE.** A cog can set `den_clear_round` as late as 2800, but the horde
    ## does not wait: measured on the all-defaults mirror over the six `small`
    ## maps, four of the six games were already over (`archons_destroyed`) at
    ## rounds 605-1158, i.e. BEFORE the default `den_clear_round: 900` even
    ## came due on three of them — so on those maps the knob could not be
    ## spent at all and the den field was never broken.
    ##
    ## So a faction that is **visibly losing to the horde** commits early:
    ## once it has taken `DenPressureDamage` of zombie damage it stops waiting
    ## for its own schedule and goes at the source, but never before this
    ## floor (a round-1 den rush with three soldiers is not a strike group, it
    ## is a donation). A cog who asked for an EARLIER round still gets it —
    ## `den_clear_round` below the floor is honoured verbatim — so the knob
    ## keeps its teeth in the direction it is asking for, and only the
    ## "never" end of it is bounded by the horde's own arithmetic.
  DenPressureDamage* = 900
    ## Measured: the all-defaults mirror crosses this between rounds ~250 and
    ## ~700 on the `small` pool, i.e. while the faction still has its opening
    ## army, and does not cross it at all on a map where the horde never
    ## reaches (which is exactly when waiting is right).

proc effectiveDenClearRound*(w: World, s: Side): int =
  ## `den_clear_round`, floored by horde pressure (above).
  let taken = w.stats.zombieDamageTaken[ord(s.team)]
  if taken >= DenPressureDamage:
    min(s.doctrine.denClearRound, DenPressureFloor)
  else:
    s.doctrine.denClearRound

proc schedule*(w: World, s: Side) =
  ## Run once a round, before the exec sweep.
  s.hasDenTarget = false
  s.denCommitted = false
  s.strikeGroup.setLen(0)
  if w.brokenChassis:
    s.denTarget = loc(-1, -1)
    return                                ## the negative control never commits
  if w.currentRound < effectiveDenClearRound(w, s):
    s.denTarget = loc(-1, -1)
    return
  ## STICKINESS. A den is 110-165 rounds of work, so the target may not be
  ## re-chosen every round on a score that moves as queues drain: once a den
  ## is picked, the group stays on it until it dies or is no longer on the
  ## board. Re-targeting every round was the second reason the earlier
  ## measurement never broke a den: the group walked between two dens.
  var stillThere = false
  if s.denTarget.x >= 0:
    for den in w.liveDens():
      if den.loc == s.denTarget:
        stillThere = true
        break
  if not stillThere:
    var bestScore = -1.0e18
    s.denTarget = loc(-1, -1)
    for den in w.liveDens():
      let queue = w.denQueueRemaining(den)
      var approach = high(int)
      for a in s.archons:
        approach = min(approach, a.distanceSquaredTo(den.loc))
      if approach == high(int): approach = 0
      let score = float64(queue * 40) - float64(approach)
      if score > bestScore:
        bestScore = score
        s.denTarget = den.loc
  if s.denTarget.x < 0: return
  s.hasDenTarget = true
  ## THE GROUP. Form it from the attackers nearest the den, keeping
  ## `DenGarrison` of them at home, and only when a group that can actually
  ## break 2000 HP can be formed. A group that would be under `DenStrikeGroup`
  ## does not go: an under-strength group is attrition for the den, not damage.
  var candidates: seq[tuple[d: int, id: int]]
  for id in w.execOrder:
    if not w.robotsById.hasKey(id): continue
    let r = w.robotsById[id]
    if r.team != s.team: continue
    if r.kind notin {rtSoldier, rtGuard, rtViper}: continue
    candidates.add((r.loc.distanceSquaredTo(s.denTarget), id))
  if candidates.len < DenStrikeGroup + DenGarrison: return
  candidates.sort(proc (a, b: tuple[d: int, id: int]): int =
    if a.d != b.d: cmp(a.d, b.d) else: cmp(a.id, b.id))
  for i in 0 ..< min(DenStrikeGroup, candidates.len - DenGarrison):
    s.strikeGroup.add(candidates[i].id)
  s.denCommitted = s.strikeGroup.len >= DenStrikeGroup

func inStrikeGroup*(s: Side, r: Robot): bool =
  ## The one unit class that outranks the defensive floor, and only while the
  ## group is committed.
  if not s.denCommitted: return false
  for id in s.strikeGroup:
    if id == r.id: return true
  false

func denApproachSquare*(w: World, s: Side, r: Robot): Loc =
  ## Where a strike-group member wants to stand: inside its own attack radius
  ## of the den but OUTSIDE the eight adjacent squares, so it never pays the
  ## 10-damage proximity charge while it works.
  result = loc(-1, -1)
  if not s.hasDenTarget: return
  let den = s.denTarget
  if r.kind.attackRadiusSquared() <= 2:
    ## A GUARD's reach is r2 2, which IS adjacent: it has to stand in the
    ## damage ring, and that is the price of a melee unit on a den.
    return den
  var bestScore = -1.0e18
  for l in w.locationsWithinRadiusSquared(den, r.kind.attackRadiusSquared()):
    if not r.spend(1): break
    if l.distanceSquaredTo(den) <= 2: continue
    if w.isLocationOccupied(l) and not (l == r.loc): continue
    if rubbleBlocks(w.getRubble(l), r.kind): continue
    let score = -float64(l.distanceSquaredTo(r.loc)) - w.getRubble(l) / 10.0
    if score > bestScore:
      bestScore = score
      result = l
