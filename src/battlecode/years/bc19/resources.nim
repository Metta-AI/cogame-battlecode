## The bc19 economy: the trickle, mining, `give`, the reclaim on a kill, the
## inter-team barter, and the `worth` sum the score reads.
##
## Ported from `coldbrew/action_record.js` (`enactMine` :213-225,
## `enactTrade` :228-247, `enactGive` :256-277, the reclaim inside
## `enactAttack` :301-311) and `coldbrew/game.js:751-752` (the trickle) at the
## pinned commit.
##
## **THERE IS EXACTLY ONE PASSIVE INCOME IN THIS GAME AND IT IS FLAT.**
## `TRICKLE_FUEL = 25` fuel per team per round, credited at the top of every
## round, NOT SCALED BY STRUCTURES. Karbonite has no passive income at all.
## Everything else is pilgrim mining (+2 karbonite or +10 fuel a turn for 1
## fuel), the reclaim on a kill, and the castle barter.

import ../../sim_types
import constants, units, world

export world

proc addTrickle*(w: World) =
  ## `game.js:751-752`, at the top of every round, BEFORE the round's first
  ## robot acts.
  for t in 0 .. 1:
    w.fuel[t] += TrickleFuel
    w.stats.fuelTrickled[t] += TrickleFuel

proc spendKarbonite*(w: World, t: Team, amount: int) =
  w.karbonite[ord(t)] -= amount
  if amount > 0: w.stats.karboniteSpent[ord(t)] += amount

proc spendFuel*(w: World, t: Team, amount: int) =
  w.fuel[ord(t)] -= amount
  if amount > 0: w.stats.fuelSpent[ord(t)] += amount

proc enactMine*(w: World, r: Robot) =
  ## `action_record.js:213-225`. KARBONITE FIRST, and the two branches are
  ## exclusive: a square on both maps is impossible (the generator's `c_in`
  ## rejection, `game.js:258,269`) but the karbonite branch would win anyway.
  ##
  ## Two consequences, both ported: **mining at capacity still costs the 1
  ## fuel and yields nothing** (a wasted turn, counted), and a `mine` off a
  ## depot THROWS — a validation-time no-op, because the engine deliberately
  ## does not check the square until enact time (rule 4.9).
  let t = ord(r.team)
  if w.hasKarbonite(r.x, r.y):
    let before = r.karbonite
    r.karbonite = min(r.karbonite + KarboniteYield,
                      karboniteCapacityOf(ukPilgrim))
    w.spendFuel(r.team, MineFuelCost)
    w.stats.mineActions[t] += 1
    w.stats.karboniteMined[t] += r.karbonite - before
    if r.karbonite == before: w.stats.mineActionsWasted[t] += 1
  elif w.hasFuel(r.x, r.y):
    let before = r.fuel
    r.fuel = min(r.fuel + FuelYield, fuelCapacityOf(ukPilgrim))
    w.spendFuel(r.team, MineFuelCost)
    w.stats.mineActions[t] += 1
    w.stats.fuelMined[t] += r.fuel - before
    if r.fuel == before: w.stats.mineActionsWasted[t] += 1
  else:
    raise newException(BattlecodeError,
      "Could not mine, as was not on resource point.")

proc enactGive*(w: World, r: Robot, dx, dy, giveK, giveF: int) =
  ## `action_record.js:256-277`. Two branches, and the docs are WRONG about
  ## the second one (`docs.js:260`: "the excess is loss to the void"): the
  ## record's own amount is REDUCED FIRST and only the reduced amount is
  ## deducted from the giver, so nothing is lost.
  ##
  ## **NO TEAM CHECK.** Giving to an ENEMY structure credits the ENEMY's
  ## global store. It is legal and the chassis never does it.
  let at = w.shadowAt(r.x + dx, r.y + dy)
  if at == 0:
    raise newException(BattlecodeError, "Cannot give to empty square.")
  let target = w.getItem(at)
  if target.isNil:
    raise newException(BattlecodeError, "Cannot give to empty square.")
  var k = giveK
  var f = giveF
  if target.unit == ukCastle or target.unit == ukChurch:
    w.karbonite[ord(target.team)] += k
    w.fuel[ord(target.team)] += f
    if target.team == r.team:
      w.stats.karboniteDeposited[ord(r.team)] += k
      w.stats.fuelDeposited[ord(r.team)] += f
  else:
    k = min(k, karboniteCapacityOf(target.unit) - target.karbonite)
    f = min(f, fuelCapacityOf(target.unit) - target.fuel)
    target.karbonite += k
    target.fuel += f
  r.karbonite -= k
  r.fuel -= f
  w.stats.giveActions[ord(r.team)] += 1

proc reclaimFrom*(w: World, attacker, target: Robot, radToAttacker: int) =
  ## `action_record.js:301-311`. A structure kill reclaims NOTHING (its
  ## `CONSTRUCTION_KARBONITE` is not read at all — the branch is skipped) and
  ## a STRUCTURE attacker collects nothing either, because
  ## `Math.min(n, null) === 0` (D6.3).
  ##
  ## `rad_to_attacker == 0` is the attacker's own square, which a PREACHER
  ## always includes. In JavaScript `Math.floor(n/0)` is `Infinity` and the
  ## caller is `Math.min(held + reclaimed, capacity)`, so it CLAMPS TO THE
  ## CAPACITY; when the numerator is also 0 it is `NaN`, but the robot is
  ## deleted on the very next line so the value is never read. The port pins
  ## both to the capacity clamp.
  if target.unit == ukCastle or target.unit == ukChurch: return
  let kCap = karboniteCapacityOf(attacker.unit)
  let fCap = fuelCapacityOf(attacker.unit)
  let kNum2 = 2 * target.karbonite + buildKarboniteOf(target.unit)
  let fNum2 = 2 * target.fuel
  let kGain = reclaimDivDoubled(kNum2, radToAttacker)
  let fGain = reclaimDivDoubled(fNum2, radToAttacker)
  let beforeK = attacker.karbonite
  let beforeF = attacker.fuel
  attacker.karbonite =
    if kGain < 0: kCap else: min(attacker.karbonite + kGain, kCap)
  attacker.fuel =
    if fGain < 0: fCap else: min(attacker.fuel + fGain, fCap)
  w.stats.karboniteReclaimed[ord(attacker.team)] +=
    max(0, attacker.karbonite - beforeK)
  w.stats.fuelReclaimed[ord(attacker.team)] += max(0, attacker.fuel - beforeF)

proc enactTrade*(w: World, r: Robot, tradeK, tradeF: int) =
  ## `action_record.js:228-247`. Both quirks are ported:
  ##
  ##   * the initial `last_offer` is `[[0,0],[0,0]]`, so the FIRST castle to
  ##     offer `(0,0)` "matches" and executes a zero trade;
  ##   * a matching pair that is NOT payable clears BOTH standing offers and
  ##     THEN throws, so the offers are gone and nothing moved.
  ##
  ## The sign convention is the engine's: POSITIVE MEANS THE RESOURCE MOVES
  ## RED TO BLUE.
  let t = ord(r.team)
  w.lastOffer[t] = [tradeK, tradeF]
  w.stats.tradesProposed[t] += 1
  if w.lastOffer[0][0] == w.lastOffer[1][0] and
      w.lastOffer[0][1] == w.lastOffer[1][1]:
    w.lastOffer = [[0, 0], [0, 0]]
    let payable = w.karbonite[0] >= tradeK and w.karbonite[1] >= -tradeK and
                  w.fuel[0] >= tradeF and w.fuel[1] >= -tradeF
    discard w.beat(BeatTrade, "trade", tradeK, tradeF,
                   (if payable: 1 else: 0))
    if payable:
      w.karbonite[0] -= tradeK
      w.karbonite[1] += tradeK
      w.fuel[0] -= tradeF
      w.fuel[1] += tradeF
      for s in 0 .. 1: w.stats.tradesExecuted[s] += 1
      w.stats.tradeKarboniteNet[0] -= tradeK
      w.stats.tradeKarboniteNet[1] += tradeK
      w.stats.tradeFuelNet[0] -= tradeF
      w.stats.tradeFuelNet[1] += tradeF
    else:
      raise newException(BattlecodeError, "Agreed trade deal is not payable.")

proc noteFamine*(w: World, t: Team, resource: int) =
  ## The first round the side's store hits 0 with a build or an attack
  ## pending, once per resource per side. `resource` is 0 karbonite, 1 fuel.
  if w.famineSeen[ord(t)][resource]: return
  w.famineSeen[ord(t)][resource] = true
  discard w.beat(BeatFamine, "famine", ord(t), resource)
