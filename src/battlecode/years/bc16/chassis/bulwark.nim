## `bulwark` — the strong baseline and the champion chassis: the turn
## dispatcher.
##
## Written for this run from the ENGINE's own mechanics and from the three
## archetypes the run's idea text itself names (turret turtle, aggressive
## soldier/viper, scout zombie-pull). **`TheDuck314/battlecode2016` and
## `bshimanuki/battlecode2016` carry NO LICENCE, were not cloned, not read,
## not copied, not vendored, not compiled and not translated, and contribute
## nothing.** Where this repo's documents say "the play the 2016 meta made",
## that is a statement about the idea's own characterisation of the 2016
## finals, not a claim about any repository's contents.
##
## Parameterised by all eleven knobs, and NO KNOB CAN MAKE IT INERT: the
## floors live in `econ.nim` (three attackers per archon, a build order above
## 200 parts), `archon.nim` (the free repair every turn, the last archon out
## of a den's ring) and `combat.nim` (always take a kill, never friendly
## fire).

import ../world
import kit, econ, combat, micro, infect, rubble, neutral, turret, dens, comms
import archon as archonModule

export kit

proc beginRound*(w: World, s: Side) =
  ## The chassis's round-level bookkeeping, run BEFORE the exec sweep so every
  ## robot this round reads the same census and the same den programme.
  w.refreshCensus(s)
  s.claimedNeutrals.setLen(0)
  dens.schedule(w, s)

proc objectiveFor(w: World, s: Side, r: Robot): Loc =
  ## Where a fighting unit wants to be when it has nothing to shoot.
  ##
  ## THE DEFENSIVE FLOOR COMES FIRST, at every knob setting and in every
  ## opening: a hostile inside r2 64 of one of our archons is answered before
  ## any plan, because the only thing that ends this game is an archon dying.
  ## Measured on `caverns` (1 078 impassable squares, two archons a side):
  ## without this, a mirror match ended in `archons_destroyed` at round 756
  ## with 44 of the loser's own units standing back up as zombies inside its
  ## own ring.
  ##
  ## THE ONE EXCEPTION IS THE STANDING STRIKE GROUP (`dens.nim`), and it is
  ## the whole of the den-breaking iteration: the horde arrives on a schedule,
  ## so a defensive floor that outranks everything reclaims the entire army
  ## every round and the den field is never touched — which is what the first
  ## measurement showed (1 of 6 games reached the round limit, 6 dens killed
  ## across the six maps, and three of the six games were over before the
  ## default `den_clear_round: 900` came due). `DenStrikeGroup` attackers are
  ## therefore named, and only they ignore the floor; `DenGarrison` attackers
  ## are held out of the group at every setting, so committing to a den is
  ## never the same thing as abandoning the archons.
  if s.inStrikeGroup(r):
    let approach = denApproachSquare(w, s, r)
    if approach.x >= 0: return approach
  let threat = s.nearestThreat(r.loc)
  if threat.x >= 0:
    let home = s.nearestArchon(r.loc)
    if home.x < 0 or home.distanceSquaredTo(threat) <= 36:
      return threat
  if s.hasDenTarget and s.denCommitted:
    let approach = denApproachSquare(w, s, r)
    if approach.x >= 0: return approach
  case s.doctrine.opening
  of opSoldierViperAggro:
    let enemy = s.nearestEnemyArchon(r.loc)
    if enemy.x >= 0: return enemy
  of opTurtle:
    ## Hold the ring, AND FACE THE DEN. A turtle that wanders is not a
    ## turtle: a unit beyond r2 36 of its nearest archon walks back. Inside
    ## that radius it stands between the archon and THE NEAREST DEN, not the
    ## enemy — because the horde is what arrives on a schedule and every
    ## zombie walks at the NEAREST player-controlled robot, so the wall has
    ## to be on the horde's side of the archon or the archon IS the wall.
    let home = s.nearestArchon(r.loc)
    if home.x >= 0:
      if home.distanceSquaredTo(r.loc) > 36:
        return home
      var face = s.frontier
      var best = high(int)
      for den in w.liveDens():
        let d = den.loc.distanceSquaredTo(home)
        if d < best:
          best = d
          face = den.loc
      if face.x >= 0:
        return loc((home.x * 2 + face.x) div 3, (home.y * 2 + face.y) div 3)
  of opScoutZombiePull:
    if s.frontier.x >= 0: return s.frontier
  if s.frontier.x >= 0: return s.frontier
  loc(-1, -1)

proc runFighter(w: World, s: Side, r: Robot) =
  ## SOLDIER, GUARD and VIPER. The order is: shoot what is worth shooting,
  ## then honour the infection policy, then retreat, then kite, then walk at
  ## the objective. A GUARD closes to r2 <= 2 and holds, because it is the
  ## block.
  let pick = pickTarget(w, s, r, s.denCommitted)
  if pick.ok:
    w.doAttack(r, pick.at)
  if infect.plan(w, s, r): return
  if micro.retreat(w, s, r): return
  if micro.kite(w, s, r): return
  if rubble.plan(w, s, r): return
  let objective = objectiveFor(w, s, r)
  if objective.x >= 0:
    if w.stepToward(r, objective): return
  discard w.stepAnywhere(r)

proc runScout(w: World, s: Side, r: Robot) =
  ## A SCOUT costs 25 parts, has 80 health, sees r2 <= 53, IGNORES RUBBLE
  ## ENTIRELY and cannot attack — so it is the cheapest legal bait in the
  ## game, and the cheapest digger (movementDelay 1.4).
  scoutPing(w, s, r)
  if infect.plan(w, s, r): return
  if s.doctrine.opening == opScoutZombiePull:
    ## Stand on the FAR side of the nearest den — the side away from our own
    ## archons — so that the nearest player-controlled robot to that den is
    ## OURS and standing where the wave walks at us and then at them.
    ## `getNearestPlayerControlled` is the whole zombie targeting rule.
    var bestDen = loc(-1, -1)
    var best = high(int)
    for den in w.liveDens():
      let d = den.loc.distanceSquaredTo(r.loc)
      if d < best:
        best = d
        bestDen = den.loc
    if bestDen.x >= 0:
      let home = s.nearestArchon(r.loc)
      var bait = bestDen
      if home.x >= 0:
        bait = loc(bestDen.x + (bestDen.x - home.x) div 4,
                   bestDen.y + (bestDen.y - home.y) div 4)
      if not w.onTheMap(bait): bait = bestDen
      if bait.distanceSquaredTo(r.loc) > 4:
        if w.stepToward(r, bait): return
      return
  if rubble.plan(w, s, r): return
  let enemy = s.nearestEnemyArchon(r.loc)
  if enemy.x >= 0 and w.stepToward(r, enemy): return
  discard w.stepAnywhere(r)

proc runBulwark*(w: World, s: Side, r: Robot) =
  drainQueue(w, s, r)
  case r.kind
  of rtArchon: archonModule.runArchon(w, s, r)
  of rtScout: runScout(w, s, r)
  of rtSoldier, rtGuard, rtViper: runFighter(w, s, r)
  of rtTurret: runTurret(w, s, r)
  of rtTtm: runTtm(w, s, r)
  else: discard
