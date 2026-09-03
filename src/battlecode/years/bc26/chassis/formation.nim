## Four-rat formation into a rat king. Knob site: `king_count_target` — a
## formation only upgrades while the clan has fewer kings than it wants, so
## the knob really does decide how many crowns are on the board.

import kit

proc wantsMoreKings*(w: World, clan: Clan): bool =
  w.teamInfo.numRatKings[ord(clan.team)] < clan.doctrine.kingCountTarget

proc tryFormation*(w: World, clan: Clan, r: Robot): bool =
  if r.unit != utBabyRat: return false
  if not wantsMoreKings(w, clan): return false
  if not r.spend(10): return false
  if w.canBecomeRatKing(r):
    w.becomeRatKing(r)
    return true
  false

proc muster*(w: World, clan: Clan, r: Robot): (bool, Loc) =
  ## Where a rat should stand to help a crowning: the tile beside the densest
  ## friendly cluster it can see. Only consulted when the clan still wants a
  ## king, so `king_count_target 1` leaves the roster spread out.
  if not wantsMoreKings(w, clan): return (false, r.loc)
  if not r.spend(8): return (false, r.loc)
  var best = 0
  var bestLoc = r.loc
  for other in w.senseNearbyRobots(r):
    if not r.spend(1): break
    if other.team != clan.team or other.unit != utBabyRat: continue
    var neighbours = 0
    for d in NonCenterDirs:
      let n = w.getRobot(other.loc + d)
      if n != nil and n.team == clan.team and n.unit == utBabyRat:
        inc neighbours
    if neighbours > best:
      best = neighbours
      bestLoc = other.loc
  (best >= 2, bestLoc)
