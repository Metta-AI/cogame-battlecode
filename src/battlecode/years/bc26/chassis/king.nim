## The rat king's turn. Knob site: `spawn_curve` — how much banked cheese a
## king insists on before it builds another rat.

import kit, targets

const StarvationReserve* = 150
  ## A king eats `RAT_KING_CHEESE_CONSUMPTION` every round and loses 10 hp a
  ## round once the bank is empty, so a clan that spends its last cheese on
  ## one more rat kills its own crowns about sixty rounds later. Mines
  ## generate roughly 0.6 cheese a round per team, well under a single
  ## king's 2/round burn, which is why every curve keeps a floor and the
  ## knob only decides how much MORE than the floor a king insists on.

proc ratCap*(clan: Clan): int =
  ## The population the curve is willing to pay the cost ladder for. The
  ## ladder is `10 + 10 * (rats / 4)`, so the 30th rat costs 80 cheese —
  ## roughly 130 rounds of a king's income. Capping the roster is what turns
  ## `spawn_curve` into a real economic choice instead of "spend everything".
  case clan.doctrine.spawnCurve
  of scLean: 8
  of scSteady: 16
  of scSwarm: 28

proc spawnThreshold*(w: World, clan: Clan): int =
  ## The bank a king insists on BEFORE it pays for another rat: the
  ## starvation floor for every crown it has to feed, plus the rat's cost.
  let base = w.currentRatCost(clan.team)
  let kings = max(1, w.teamInfo.numRatKings[ord(clan.team)])
  let floorCheese = StarvationReserve * kings
  case clan.doctrine.spawnCurve
  of scLean: floorCheese * 2 + (base * 14 + 9) div 10
  of scSteady: floorCheese + base
  of scSwarm: floorCheese div 2 + (base * 7 + 9) div 10

proc runKing*(w: World, clan: Clan, r: Robot) =
  ## Kings do four things: eat what is underfoot, bite what is adjacent,
  ## build, and tell the clan where the cheese is.
  if r.spend(4):
    for d in AllDirs:
      let spot = r.loc + d
      if w.canPickUpCheese(r, spot):
        w.pickUpCheese(r, spot)
        break

  let t = bestAttackTarget(w, clan, r)
  if t.kind != tkNone and w.canAttack(r, t.loc):
    w.attack(r, t.loc)

  ## Build while the bank is over the curve's threshold AND there is room.
  if r.canActCooldown and r.spend(8):
    let want = spawnThreshold(w, clan)
    if w.teamInfo.numBabyRats[ord(clan.team)] < ratCap(clan) and
        w.teamInfo.globalCheese[ord(clan.team)] >= want:
      for d in NonCenterDirs:
        let spot = r.loc + d + d
        if w.canBuildRat(r, spot):
          w.buildRat(r, spot)
          break
      if r.canActCooldown:
        for d in NonCenterDirs:
          let spot = r.loc + d
          if w.canBuildRat(r, spot):
            w.buildRat(r, spot)
            break

  ## One squeak a turn: the tile index of the best cheese in sight, so
  ## miners have somewhere to go. Cats hear squeaks too — that is the trade.
  if r.spend(6):
    let cheese = nearestCheese(w, clan, r)
    if cheese.kind == tkCheese:
      discard w.squeak(r, w.idx(cheese.loc) mod (CommArrayMaxValue + 1))
      w.writeSharedArray(r, 0, w.idx(cheese.loc) mod (CommArrayMaxValue + 1))
