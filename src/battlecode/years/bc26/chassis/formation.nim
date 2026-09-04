## Four-rat formation into a rat king. Knob site: `king_count_target` — a
## formation only upgrades while the clan has fewer kings than it wants, so
## the knob really does decide how many crowns are on the board.

import kit, king

proc wantsMoreKings*(w: World, clan: Clan): bool =
  ## The knob says how many crowns the doctrine WANTS. The bank says how many
  ## it can feed: every crown eats 2 cheese a round for the rest of the game,
  ## and in r1 a clan that crowned its third king on `toomuchcheese` emptied
  ## its bank by round 357 and lost all three by 436 (r2-D2). A crown the
  ## income cannot carry is not a stronger clan, it is a faster famine.
  let team = ord(clan.team)
  let kings = w.teamInfo.numRatKings[team]
  if kings >= clan.doctrine.kingCountTarget: return false
  if kings == 0: return true
  ## CAN THIS CLAN FEED IT TO THE END OF THE GAME? Bank, plus what the
  ## clan's own ferrying rate will bring in over the rounds that are left,
  ## against what the enlarged court will eat over those rounds. The opening
  ## 2 500 cheese makes any clan look rich enough for five crowns on round 35
  ## — `toomuchcheese` crowned its third there and was dead by 436 (r2-D2) —
  ## so the bank alone is not the test, and income alone would refuse the
  ## first crown of every game.
  let remaining = max(1, w.maxRounds - w.currentRound)
  let projected =
    w.teamInfo.cheeseTransferred[team] * remaining div max(1, w.currentRound)
  let burn = RatKingCheeseConsumption * (kings + 1) * remaining
  ## The projection is discounted by a quarter and the answer has to clear
  ## the starvation floor on top of the burn: a clan that crowns on a burst of
  ## income and then eats through the bank has still lost its kings.
  w.teamInfo.globalCheese[team] >=
      StarvationReserve * (kings + 1) + RatKingUpgradeCheeseCost and
    w.teamInfo.globalCheese[team] + projected * 3 div 4 >=
      burn + StarvationReserve * (kings + 1) + RatKingUpgradeCheeseCost

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
