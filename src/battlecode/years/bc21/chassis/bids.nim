## `bids.nim` — the auction, driven by `bid_policy`.
##
## There are exactly 1500 votes on offer and the LOSER of each auction still
## pays `ceil(bid/2)` for nothing, so bidding is the one part of a 2021
## doctrine that can lose a match without ever meeting the enemy.
##
## The `proportional` ladder is California Roll's
## (`StoneT2000/Battlecode2021` `src/maxecosushi/`, AGPL-3.0, commit 5c2a7ee):
## start at 2; after a won auction divide by 1.25 with a floor of 1; after a
## lost one double, and clamp the result to 2.5 % of the Center's influence.
##
## TWO ADDITIONS THAT ARE OURS, both chassis behaviour rather than rules, and
## both recorded in docs/RULES-BC21.md §Divergences item 11:
##
##   * a 0..2 influence JITTER, `(id*7 + round*3) mod 3`. A perfect mirror
##     match on a symmetric map otherwise produces IDENTICAL bids on both sides
##     for hundreds of rounds, equal top bids give the vote to NOBODY, and the
##     auction — the clock of the whole game — stops meaning anything. It costs
##     at most two influence a round and is deterministic in the Center's id
##     and the round;
##   * a BID BANK (`bidBank`): unless `bid_policy` is `never`, an Enlightenment
##     Center keeps `20 + round/5` influence (capped at 300) out of the build
##     budget, because a Center that spends to zero every round can only ever
##     bid 1 and the ladder has nothing to climb.

import std/math
import kit

proc ladderFor(side: Side, r: Robot): int =
  if r.id notin side.ladder:
    side.ladder[r.id] = 2
  side.ladder[r.id]

proc noteAuction*(w: World, side: Side) =
  ## Called once per team per round, before the Centers bid: did we win the
  ## last vote? A TIE counts as a loss for both sides, which is what makes the
  ## ladder climb out of a stalemate.
  let votes = w.stats.votes[ord(side.team)]
  let won = votes > side.lastVotes
  side.lastVotes = votes
  for id in side.ladder.keys:
    var value = side.ladder[id]
    if won:
      value = max(1, int(float64(value) / 1.25))
    else:
      value = min(1_000_000, value * 2)
    side.ladder[id] = value

proc plannedBid*(w: World, side: Side, r: Robot, reserve: int): int =
  ## What this Center will bid this round, or 0 for no bid. `reserve` is the
  ## influence the Center is holding back for defence and construction.
  let d = side.doctrine
  let spendable = r.influence - reserve
  if spendable <= 0: return 0
  ## A HASH, not a sum: `(id + round) mod 3` has a CONSTANT difference between
  ## two Centers, so two ids congruent mod 3 tie in every single round of the
  ## game. Mixing the two through a multiplicative hash makes the two
  ## sequences independent.
  let h = (uint32(r.id) xor (uint32(w.currentRound) * 0x9E3779B1'u32)) *
          0x85EBCA6B'u32
  let jitter = int((h shr 13) mod 3'u32)

  case d.bidPolicy
  of bpNever:
    0
  of bpFixed:
    if r.influence >= 200: min(spendable, 2 + jitter) else: 0
  of bpProportional, bpEscalateWhenAhead:
    var value = ladderFor(side, r)
    let cap = int(ceil(0.025 * float64(r.influence)))
    if value > cap: value = max(1, cap)
    if d.bidPolicy == bpEscalateWhenAhead:
      let mine = w.stats.votes[ord(side.team)]
      let theirs = w.stats.votes[ord(other(side.team))]
      if mine > theirs:
        value = value * 2
      elif theirs - mine > 100:
        value = max(1, value div 2)
    ## From `eco_exponential_round` the Center is allowed to spend down to a
    ## 200-influence floor; before it, it protects its build budget.
    let floorInfluence = if d.compounding(w.currentRound): 400 else: 200
    if r.influence >= floorInfluence:
      min(spendable, value + jitter)
    elif r.influence >= 50:
      min(spendable, 1 + jitter)
    else:
      0

proc bidBank*(side: Side, round: int): int =
  ## What a Center holds back from the build budget so the auction stays alive.
  if side.doctrine.bidPolicy == bpNever: 0
  else: min(150, 15 + round div 10)

proc placeBid*(w: World, side: Side, r: Robot, reserve: int) =
  let amount = plannedBid(w, side, r, reserve)
  if amount <= 0: return
  if not canBid(r, amount): return
  let before = r.influence
  w.bid(r, amount)
  ## The largest bid in each 100-round window per team becomes a `bid_spike`
  ## beat at the end of the window (`rules.nim`); everything else is a
  ## statistic.
  let t = ord(side.team)
  if amount > w.windowTopBid[t]:
    w.windowTopBid[t] = amount
    w.windowTopBidder[t] = r.id
    w.windowInfluence[t] = before
