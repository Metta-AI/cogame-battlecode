## The baby rat's turn: role assignment and the order it tries things in.
##
## Knob site: `cheese_ferry_ratio` — `ferry(id) = (id * 2654435761) mod 100 <
## ratio*100` splits the roster into miners (carry cheese home) and
## skirmishers (fight) at spawn, in `kit.brainFor`. The split is suspended
## while the clan is in FAMINE (`king.famine`): a skirmisher is no use to a
## crown that is about to starve.

import kit, king, targets, traps, dirt, combat, formation, pathing

const MineCampRadiusSquared* = 8
  ## How close is "at the mine": a miner inside this stays and sweeps its
  ## cone, a miner outside it walks back.

proc nearestFriendlyKing(w: World, clan: Clan, r: Robot): (bool, Loc) =
  var best = high(int)
  var bestLoc = r.loc
  var found = false
  for other in w.liveRobots:
    if other.team != clan.team or other.unit != utRatKing: continue
    let d = r.loc.distanceSquaredTo(other.loc)
    if d < best:
      best = d
      bestLoc = other.loc
      found = true
  (found, bestLoc)

proc runRat*(w: World, clan: Clan, r: Robot) =
  let brain = clan.brainFor(r)
  brain.turnCount += 1

  ## 1. Combat first: a bite that lands is worth more than a step.
  if tryBite(w, clan, r):
    return
  if tryFeedCat(w, clan, r):
    return
  if tryRatnap(w, clan, r):
    return

  ## 2. Crown a king if the doctrine still wants one and the ring is ready.
  if tryFormation(w, clan, r):
    return

  ## 3. Infrastructure: traps, then dirt. Both spend the action cooldown, so
  ##    at most one of them happens on a turn.
  if tryPlaceTraps(w, clan, r):
    return
  if tryDirt(w, clan, r):
    return

  ## 4. Economy / aggression, by role. A clan whose bank has fallen under the
  ##    floor its crowns need puts EVERY rat on the cheese: the skirmishers
  ##    are chasing points their kings will not live to score (r2-D2).
  if brain.ferry or famine(w, clan):
    if r.cheese > 0:
      let (haveKing, kingLoc) = nearestFriendlyKing(w, clan, r)
      if haveKing:
        if w.canTransferCheese(r, kingLoc, r.cheese):
          w.transferCheese(r, kingLoc, r.cheese)
          return
        ## Transfer needs the king INSIDE the rat's 90-degree cone, so a
        ## miner that has arrived but is looking the wrong way spends its
        ## turn turning rather than shuffling around the crown forever.
        if r.loc.distanceSquaredTo(kingLoc) <= CheeseTransferRadiusSquared:
          let want = r.loc.directionTo(kingLoc)
          if want != dCenter and want != r.dir and w.canTurn(r):
            w.turn(r, want)
            return
        moveOrTurn(w, clan, r, kingLoc)
        return
    for d in AllDirs:
      if not r.spend(1): break
      let spot = r.loc + d
      if w.canPickUpCheese(r, spot):
        w.pickUpCheese(r, spot)
        return
    let cheese = nearestCheese(w, clan, r)
    if cheese.kind == tkCheese:
      moveOrTurn(w, clan, r, cheese.loc)
      return
    ## Nothing loose in sight. A MINE is worth walking back to: it is a fixed
    ## tile that drops 20 cheese within four tiles of itself every dozen
    ## rounds for the whole game, so a miner that remembers one has an income
    ## instead of a wander.
    let mine = nearestCheeseMine(w, clan, r)
    if mine.kind == tkCheese:
      brain.knownMine = mine.loc
      brain.hasKnownMine = true
    if brain.hasKnownMine:
      if r.loc.distanceSquaredTo(brain.knownMine) > MineCampRadiusSquared:
        moveOrTurn(w, clan, r, brain.knownMine)
        return
      ## CAMP IT. Cheese spawns within four tiles of a mine every dozen rounds
      ## or so, all game, and a 90-degree cone sees a quarter of that at a
      ## time — so a miner that has arrived sweeps instead of wandering off.
      ## Wandering off is why 12 630 cheese was lying on `closeup` at round 900
      ## while both clans' banks were empty (r2-D2).
      if w.canTurn(r):
        w.turn(r, r.dir.rotateRight())
        return
    ## Nothing in sight: walk toward the mine the king squeaked about.
    let shared = w.readSharedArray(r, 0)
    if shared > 0 and shared < w.width * w.height:
      moveOrTurn(w, clan, r, w.indexToLoc(shared))
      return
  else:
    var best = 0
    var bestLoc = r.loc
    for t in visibleTargets(w, clan, r):
      if not r.spend(1): break
      let weight =
        case t.kind
        of tkCat: clan.catWeight()
        of tkKing: 7
        of tkEnemy: 5
        else: 0
      if weight > best:
        best = weight
        bestLoc = t.loc
    if best > 0:
      moveOrTurn(w, clan, r, bestLoc)
      return
    let (wantMuster, musterLoc) = muster(w, clan, r)
    if wantMuster:
      moveOrTurn(w, clan, r, musterLoc)
      return

  ## 5. Nothing to do: patrol away from home so the clan spreads out.
  let (haveKing, kingLoc) = nearestFriendlyKing(w, clan, r)
  var away = loc(w.width div 2, w.height div 2)
  if haveKing:
    away = loc(clamp(2 * r.loc.x - kingLoc.x, 0, w.width - 1),
               clamp(2 * r.loc.y - kingLoc.y, 0, w.height - 1))
  moveOrTurn(w, clan, r, away)
