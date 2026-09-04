## The election: bid collection, the `compareTo` top-bidder rule, the auction
## settlement, and the buff-expiry ledger. Plus — because the engine does them
## inside the SAME `objectInfo.eachRobot` sweep — the passive influence and the
## camouflage of `InternalRobot.processEndOfRound`.
##
## THE SWEEP ORDER. The engine sweeps `objectInfo.eachRobot`, which is
## `TIntObjectHashMap.forEachValue` — hash order, and not reproducible outside
## the JVM. This port sweeps in ASCENDING ROBOT ID, and that is a provable
## non-divergence rather than a hope. The sweep does exactly four things:
##
##   (a) `resetBid` refunds a robot's OWN held influence — independent;
##   (b) top-bidder selection is a maximum under the total order
##       (bid desc, roundsAlive asc, id asc), which is exactly the engine's
##       update predicate, so the winner does not depend on visit order;
##   (c) passive influence is an ADDITION into a parent's counter —
##       commutative, EXCEPT at the `ROBOT_INFLUENCE_LIMIT = 1e8` clamp;
##   (d) camouflage depends only on the robot's own `roundsAlive`.
##
## (c) is the only exposure, `World.influenceClampHit` records it, and
## `rules.nim` raises a fault if it is ever reached.
## docs/RULES-BC21.md §Divergences item 4.

import std/algorithm
import world

proc betterBidder(a, b: Robot, bidA, bidB: int): bool =
  ## The engine's own update predicate, as a strict "a beats b":
  ##   bid descending, then `InternalRobot.compareTo` — roundsAlive ascending,
  ##   then id ascending. The spec calls this "lowest robot age then lowest
  ##   robot ID".
  if bidA != bidB: return bidA > bidB
  if a.roundsAlive != b.roundsAlive: return a.roundsAlive < b.roundsAlive
  a.id < b.id

proc sortedIds(w: World): seq[int] =
  for id in w.robotsById.keys: result.add(id)
  result.sort()

proc processEndOfRoundSweep*(w: World): tuple[bids: array[2, int],
                                              bidders: array[2, int]] =
  ## Rule 6.1. Returns each team's top bid and the id of the robot that placed
  ## it (-1 when the team has no Enlightenment Center at all).
  result.bidders = [-1, -1]
  var best: array[2, Robot]
  for id in w.sortedIds():
    if id notin w.robotsById: continue
    let r = w.robotsById[id]

    if r.team.isPlayer() and r.kind.canBidKind():
      let t = ord(r.team)
      let theBid = r.bid
      if best[t] == nil or betterBidder(r, best[t], theBid, result.bids[t]):
        result.bids[t] = theBid
        best[t] = r
      w.resetBid(r)

    ## `InternalRobot.processEndOfRound` — passive influence, then camouflage.
    let target =
      if r.parentId < 0: r
      elif r.parentId in w.robotsById: w.robotsById[r.parentId]
      else: nil
    let passive = passiveInfluenceFor(r.kind, r.influence, r.roundsAlive,
                                      w.currentRound)
    if passive > 0 and r.team.isPlayer() and target != nil:
      w.addInfluenceAndConviction(target, passive)
      w.stats.passiveEarned[ord(r.team)] += passive
      if r.kind == rtSlanderer:
        w.stats.slandererPassive[ord(r.team)] += passive

    if r.kind == rtSlanderer and r.roundsAlive == CamouflageNumRounds:
      w.typeCount[ord(r.team)][rtSlanderer] -= 1
      r.kind = rtPolitician
      w.typeCount[ord(r.team)][rtPolitician] += 1
      if r.team.isPlayer():
        w.stats.camouflaged[ord(r.team)] += 1
      w.emit("camouflage", r.id, ord(r.team), 0)

  for t in 0 .. 1:
    if best[t] != nil: result.bidders[t] = best[t].id

proc settleAuction*(w: World, bids: array[2, int], bidders: array[2, int]) =
  ## Rule 6.2. The single highest bidder IN THE GAME wins the vote for its team
  ## and pays in full; every team that did not win pays `(bid + 1) / 2` for
  ## nothing. Equal top bids (including both zero) give the vote to NOBODY and
  ## charge both teams half — which for two zero bids is zero.
  var teamVotes = [0, 0]
  if bids[0] > bids[1] and bids[0] > 0:
    teamVotes[0] = 1
    w.addInfluenceAndConviction(w.robotsById[bidders[0]], -bids[0])
    w.stats.votes[0] += 1
    w.stats.bidInfluenceSpent[0] += bids[0]
  elif bids[1] > bids[0] and bids[1] > 0:
    teamVotes[1] = 1
    w.addInfluenceAndConviction(w.robotsById[bidders[1]], -bids[1])
    w.stats.votes[1] += 1
    w.stats.bidInfluenceSpent[1] += bids[1]

  for t in 0 .. 1:
    if teamVotes[t] == 0 and bidders[t] >= 0:
      let halfBid = (bids[t] + 1) div 2
      w.addInfluenceAndConviction(w.robotsById[bidders[t]], -halfBid)
      w.stats.bidInfluenceSpent[t] += halfBid
    w.stats.topBid[t] = max(w.stats.topBid[t], bids[t])

  if bids[0] == bids[1]:
    w.stats.votesTied += 1
  if bids[0] == 0 and bids[1] == 0:
    w.stats.roundsNoBid += 1

proc applyExposeBuffs*(w: World) =
  ## Rule 6.3. `TeamInfo.addBuffs(nextRound, team, buffsToAdd)`: the buff is in
  ## effect IMMEDIATELY (so it first affects a speech on `currentRound + 1`)
  ## and expires at the start of round `currentRound + 1 + 50`.
  let nextRound = w.currentRound + 1
  for t in 0 .. 1:
    let adding = w.stats.buffsToAdd[t]
    if adding != 0:
      w.stats.numBuffs[t] += adding
      w.stats.buffExpiries[t].add(
        BuffBatch(expiresAt: nextRound + ExposeBuffNumRounds, count: adding))
      w.stats.buffPeak[t] = max(w.stats.buffPeak[t], w.stats.numBuffs[t])
    w.stats.buffsToAdd[t] = 0

proc updateNumBuffs*(w: World) =
  ## Rule 1's buff expiry. `TeamInfo.updateNumBuffs(currentRound)` drops every
  ## batch whose recorded expiry round is <= `currentRound`.
  for t in 0 .. 1:
    var kept: seq[BuffBatch]
    for batch in w.stats.buffExpiries[t]:
      if batch.expiresAt <= w.currentRound:
        w.stats.numBuffs[t] -= batch.count
      else:
        kept.add(batch)
    w.stats.buffExpiries[t] = kept
