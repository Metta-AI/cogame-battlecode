## The slanderer — the money, and the thing the whole muckraker story is about.
##
## A slanderer NEVER acts: its action radius is 0 and it has nothing to do with
## its cooldown. It moves away from the nearest sensed enemy and toward its own
## Center's "safe side" (the direction with the fewest sensed enemies within
## `r^2 <= 20`), keeping a diagonal lattice spacing so a single enemy
## politician cannot catch two of them.
##
## After camouflage at `roundsAlive == 300` it IS a politician and runs
## `politician.nim`; nothing here needs to know that.
##
## Fog note: a slanderer cannot true-sense, so what it flees from is whatever
## it can see — and an enemy slanderer looks exactly like an enemy politician
## to it. That is the year's rule, and fleeing from a harmless slanderer is a
## real cost of it.

import kit, pathing

proc lattice(l: Loc): bool =
  ## The diagonal lattice: only tiles where `(x + y)` is even are "parking
  ## spots", so two slanderers are never orthogonally adjacent and one
  ## politician's `r^2 = 2` speech cannot catch a whole row.
  ((l.x + l.y) and 1) == 0

proc runSlanderer*(w: World, side: Side, r: Robot) =
  observe(w, side, r)

  var threatAt = loc(-1, -1)
  var threatD = high(int)
  var enemies = 0
  for l in w.sensedTilesWithin(r, 20):
    let bot = w.getRobot(l)
    if bot == nil: continue
    if bot.team == side.team or bot.team == teamNeutral: continue
    enemies += 1
    let dist = r.loc.distanceSquaredTo(l)
    if dist < threatD:
      threatD = dist
      threatAt = l

  if not isReady(r): return

  if threatAt.x >= 0:
    if moveAwayFrom(w, side, r, threatAt):
      setFlag(r, encodeFlag(fkUnderAttack, r.loc, min(511, enemies)))
      return

  ## No threat in sight: settle onto the lattice near the nearest own Center,
  ## at a comfortable stand-off so the Center's own build tiles stay free.
  if side.ownCenters.len > 0:
    let home = side.nearestOwnCenter(r.loc)
    let dist = r.loc.distanceSquaredTo(home)
    if dist < 8:
      var best = dCenter
      var bestD = dist
      for d in MoveDirs:
        if not spend(r, 1): break
        if not w.canMove(r, d): continue
        let l = r.loc + d
        let nd = l.distanceSquaredTo(home)
        if nd > bestD:
          bestD = nd
          best = d
      if best != dCenter:
        w.move(r, best)
        return
    elif dist > 40 or not lattice(r.loc):
      ## Walk back toward home until we are both close enough and on the
      ## lattice; `moveToward` carries the no-repeat history that stops a
      ## slanderer oscillating between two lattice tiles for ever.
      if dist > 40:
        moveToward(w, side, r, home)
      else:
        for d in MoveDirs:
          if not spend(r, 1): break
          if not w.canMove(r, d): continue
          if lattice(r.loc + d):
            w.move(r, d)
            break
  setFlag(r, encodeFlag(fkSilent, r.loc))
