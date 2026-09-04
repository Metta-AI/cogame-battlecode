## Dirt work. Knob site: `dirt_wall_policy`.
##
## `none` does nothing, and NOTHING happens while the clan is in famine —
## digging costs cheese the crowns need to eat. `king_shell` digs dirt
## wherever it is found and
## re-lays it in the ring around the clan's own king. `choke` lays it on the
## narrowest passable corridor the rat can see on its own half. A team can
## only PLACE dirt it has already DUG (`TeamInfo.dirtCounts`), so both
## policies dig first — which is why `none` really is zero tiles placed.

import kit, king

proc kingRing(w: World, clan: Clan, r: Robot): seq[Loc] =
  for other in w.liveRobots:
    if other.team != clan.team or other.unit != utRatKing: continue
    if r.loc.distanceSquaredTo(other.loc) > r.visionRadiusSquared * 4: continue
    for dx in -2 .. 2:
      for dy in -2 .. 2:
        if abs(dx) == 2 or abs(dy) == 2:
          result.add(other.loc.translate(dx, dy))

proc chokeSpots(w: World, clan: Clan, r: Robot): seq[Loc] =
  ## A "choke" is a passable tile with walls on two opposite sides — the
  ## cheapest read of a corridor there is, and it costs one sense per tile.
  for d in [dNorth, dEast]:
    let a = r.loc + d
    let b = r.loc + d.opposite()
    if w.getWall(a) and w.getWall(b):
      result.add(r.loc)
  for d in NonCenterDirs:
    let spot = r.loc + d
    if not w.onTheMap(spot) or w.getWall(spot): continue
    if w.getWall(spot + dNorth) and w.getWall(spot + dSouth):
      result.add(spot)
    elif w.getWall(spot + dEast) and w.getWall(spot + dWest):
      result.add(spot)

proc tryDirt*(w: World, clan: Clan, r: Robot): bool =
  if clan.doctrine.dirtWallPolicy == dwNone: return false
  ## A DUG tile costs `DigDirtCheeseCost` and the wall is never finished, so
  ## on a dirt-rich map the shell is an unbounded drain on the same bank the
  ## crowns eat from: `closeup` clans dug 141 and 169 tiles — 700-850 cheese —
  ## and one of them starved at round 592 behind a wall it was still building
  ## (r2-D2). No dirt work while the crowns are short of food.
  if famine(w, clan): return false
  if not r.canActCooldown: return false
  if not r.spend(8): return false

  let wanted =
    case clan.doctrine.dirtWallPolicy
    of dwKingShell: kingRing(w, clan, r)
    of dwChoke: chokeSpots(w, clan, r)
    of dwNone: @[]

  ## Place first when the team is holding spoil, so a dug tile turns into a
  ## wall on the very next opportunity rather than sitting in the bank.
  if w.teamInfo.dirtCounts[ord(clan.team)] > 0:
    for spot in wanted:
      if not r.spend(1): break
      if w.canPlaceDirt(r, spot):
        w.placeDirt(r, spot)
        return true
    ## Holding spoil it cannot lay: dig no more. The team bank pays 5 cheese
    ## for every dug tile and holds the spoil indefinitely, so a rat that digs
    ## while the wall has nowhere to grow is burning the crowns' food to move
    ## dirt from one pile to another.
    return false

  ## Otherwise dig — but only when there is somewhere for the spoil to go.
  var openings = 0
  for spot in wanted:
    if not r.spend(1): break
    if w.onTheMap(spot) and not w.getWall(spot) and not w.getDirt(spot) and
        not w.hasCheeseMine(spot):
      inc openings
  if openings == 0: return false

  ## Any dirt in reach is spoil for the wall.
  for d in AllDirs:
    if not r.spend(1): break
    let spot = r.loc + d
    if w.getDirt(spot) and w.canRemoveDirt(r, spot):
      ## Never dig out a tile that is already part of the wall being built.
      if spot notin wanted:
        w.removeDirt(r, spot)
        return true
  false
