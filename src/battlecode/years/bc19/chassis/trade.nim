## `saber`'s barter: `trade.nim plan()`, per `trade_policy`.
##
## THIS IS THIS YEAR'S LARGEST UNEXPLOITED MECHANIC. A CASTLE may
## `proposeTrade(karbonite, fuel)`; when the two orders' standing offers
## match element-wise the swap executes and both offers clear (rule 6.7,
## `action_record.js:228-247`). The engine's own documentation calls it
## "collaborate with the opposing team for mutual benefit" (`docs.js:149`).
##
## **THE SIGN CONVENTION IS THE ENGINE'S: POSITIVE MEANS THE RESOURCE MOVES
## RED TO BLUE.** The chassis thinks in "we/they" and converts here, once.
##
## **THE CHASSIS NEVER PROPOSES A MATCH IT CANNOT PAY**, because a matching
## pair that is not payable CLEARS BOTH STANDING OFFERS AND THEN THROWS — so
## an unpayable match is strictly worse than no offer at all.
##
## The rate is the engine's own: one `mine` action buys 2 karbonite or
## 10 fuel (`KARBONITE_YIELD` / `FUEL_YIELD`), so 1 karbonite = 5 fuel at the
## margin.

import ../constants, ../units, ../world, ../knobs
import kit, econ

export kit

const FuelPerKarbonite* = 5

func favourable*(w: World, s: Side, k, f: int): bool =
  ## Is the deal `(k, f)` — in ENGINE signs — in OUR favour at the engine's
  ## own 1 karbonite = 5 fuel rate? For RED, positive `k` means we GIVE
  ## karbonite.
  let sign = (if s.team == tRed: 1 else: -1)
  let weGiveK = sign * k
  let weGiveF = sign * f
  ## We come out ahead when what we give is worth less than what we get.
  (weGiveK * FuelPerKarbonite + weGiveF) < 0

func payableForUs*(w: World, s: Side, k, f: int): bool =
  let sign = (if s.team == tRed: 1 else: -1)
  let weGiveK = sign * k
  let weGiveF = sign * f
  w.karbonite[ord(s.team)] >= max(0, weGiveK) and
    w.fuel[ord(s.team)] >= max(0, weGiveF)

proc tradePlan*(w: World, s: Side, r: Robot): tuple[ok: bool, k, f: int] =
  ## The offer this castle proposes this turn, or nothing.
  result = (ok: false, k: 0, f: 0)
  if r.unit != ukCastle: return
  if s.doctrine.tradePolicy == tp19Never: return
  if not r.charge(20): return
  let us = ord(s.team)
  let them = 1 - us
  let sign = (if s.team == tRed: 1 else: -1)
  case s.doctrine.tradePolicy
  of tp19Never: discard
  of tp19Mirror:
    ## Re-offer the enemy's own standing offer back — which matches it and
    ## executes it — ONLY when the deal is in our favour and we can pay.
    let k = w.lastOffer[them][0]
    let f = w.lastOffer[them][1]
    if k == 0 and f == 0: return
    if not favourable(w, s, k, f): return
    if not payableForUs(w, s, k, f): return
    ## The enemy's side of the deal has to be payable too, or the match
    ## clears both offers and throws.
    if w.karbonite[0] < k or w.karbonite[1] < -k: return
    if w.fuel[0] < f or w.fuel[1] < -f: return
    result = (ok: true, k: k, f: f)
  of tp19OfferFuel:
    ## We SELL fuel and BUY karbonite: the right trade for a fuel-rich,
    ## depot-poor map. Sized by our fuel above `fuel_reserve`.
    let spare = w.fuel[us] - s.fuelGate()
    if spare < 5 * FuelPerKarbonite: return
    let sellF = min(spare div 2, (MaxTrade - 1) div 2)
    let buyK = sellF div FuelPerKarbonite
    if buyK <= 0: return
    ## In engine signs: we give fuel (+f for RED) and receive karbonite
    ## (-k for RED).
    result = (ok: true, k: sign * (-buyK), f: sign * sellF)
  of tp19OfferKarbonite:
    let spare = w.karbonite[us] - 40
    if spare <= 0: return
    let sellK = min(spare div 2, (MaxTrade - 1) div 2)
    if sellK <= 0: return
    let buyF = sellK * FuelPerKarbonite
    if buyF >= MaxTrade: return
    result = (ok: true, k: sign * sellK, f: sign * (-buyF))
  if result.ok and not payableForUs(w, s, result.k, result.f):
    result = (ok: false, k: 0, f: 0)
