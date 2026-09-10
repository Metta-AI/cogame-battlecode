## `donate.nim plan()` -- the knob this year is actually about.
##
## A victory point costs `7.5 + (12.5/3000) x round` bullets: **7.5 on round 1
## and 19.996 on round 2 999**, so the same 13 750 bullets buys 1 000 points
## early or 690 late, and **1 000 points ends the game the instant the
## donation lands**.
##
## **THE EXACT-MULTIPLE RULE.** `donate(bullets)` deducts the WHOLE amount and
## grants `floor(bullets / price)` points, so the remainder is destroyed --
## the spec calls it "extra generosity". `orchard` therefore always donates
## `floor(surplus / price) * price` and never the raw surplus; the difference
## is up to 20 bullets a donation.

import std/math
import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit, econ

export kit

func exactMultiple*(w: World, surplus: float32): float32 =
  ## `floor(surplus / price) * price`, so nothing is thrown away.
  let price = w.victoryPointCost()
  if surplus < price: return 0'f32
  let points = float32(floor(float64(surplus / price)))
  points * price

proc plan*(w: World, s: Side, r: Robot): float32 =
  ## How much this robot should donate right now, in bullets. Zero means "not
  ## yet", and the broken-chassis control never donates at all.
  when defined(bc17BrokenChassis):
    return 0'f32
  let us = ord(s.team)
  let them = ord(s.team.opponent())
  let stock = w.bulletSupplyOf(s.team)
  ## **THE BUILD BUFFER, and it is the anti-inert rule in arithmetic.** A
  ## point bought is a point kept, but a faction that donates every surplus
  ## bullet the round it arrives never buys a second gardener, a third tree
  ## or a single fighter -- and `orchard`'s floor says it always does all
  ## three. So while the farm or the army is still below target the surplus
  ## is held back on top of the reserve; once both are met, everything above
  ## the reserve goes to the Fund.
  let buffer = (if w.wantsFighter(s) or w.wantsTree(s) or
                   w.wantsGardener(s): 400'f32 else: 0'f32)
  let reserve = w.bulletGate(s) + buffer
  case s.doctrine.vpDonatePolicy
  of vp17Never:
    ## Never -- except the one case where holding bullets cannot help: the
    ## last round, where a bullet is worth nothing and a point is worth the
    ## first rung of the ladder.
    if w.currentRound >= w.maxRounds - 2:
      return w.exactMultiple(stock)
    0'f32
  of vp17WhenAhead:
    if w.victoryPoints[us] >= w.victoryPoints[them] and stock > reserve:
      return w.exactMultiple(stock - reserve)
    if w.currentRound >= w.maxRounds - 2:
      return w.exactMultiple(stock)
    0'f32
  of vp17Rush1000:
    ## Every bullet above 100 from round 1 -- the reserve does not apply,
    ## because the whole doctrine is the purchase.
    if stock > 100'f32:
      return w.exactMultiple(stock - 100'f32)
    0'f32
  of vp17EndgameDump:
    ## Bank everything and convert at round 2 900 -- deliberately the
    ## expensive price, because rung 3 of the ladder is bullets PLUS robot
    ## cost and a 20 000-bullet bank wins it outright.
    if w.currentRound >= min(2900, w.maxRounds - 100):
      return w.exactMultiple(stock)
    0'f32

proc tryDonate*(w: World, s: Side, r: Robot): bool {.discardable.} =
  let amount = w.plan(s, r)
  if amount <= 0'f32: return false
  w.donate(r, amount)
