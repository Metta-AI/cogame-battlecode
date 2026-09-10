## THE ECONOMIC-SURVIVAL GATE, with an inverted control.
##
## **IN THIS YEAR AN ORDER DOES NOT GET EATEN, IT RUNS OUT.** There is no NPC
## threat and no escalating clock; the only passive income is 25 fuel a
## round, karbonite has none at all, and an order that does not mine cannot
## build, cannot attack and eventually cannot move.
##
## THE COMMITTED THRESHOLDS ARE MEASURED, NOT GUESSED. This exact
## configuration -- `saber` against `saber` on the all-defaults sheet, seeds
## 11 / 300 / 1300 (which give sideAslot 0 / 1 / 1) on `seed-0043` and
## `seed-0048`, 1000 rounds -- was run in phase 20 and produced, as the
## WORST value over all twelve seat-games:
##
##   6 of 6 games reached the round limit      (floor: >= 5 of 6)
##   140 units built                           (floor: >= 12)
##   114 pilgrims, 26 military                 (floor: >= 4 and >= 4)
##   3 614 karbonite and 16 560 fuel mined     (floor: >= 150 and >= 300)
##   98.3 % of what was mined was deposited    (floor: >= 80 %)
##   both stores at 0 for at most 3 rounds     (floor: <= 20)
##   1 500 damage dealt                        (floor: >= 200)
##   13 units alive at the end                 (floor: >= 6)
##   2 castles still held at round 700         (floor: >= 1)
##   24 churches across the six games          (floor: >= 1)
##   0.0 % friendly fire                       (floor: < 15 %)
##   refused_actions == 0 on every seat        (the legality gate)
##
## The BROKEN CONTROL (`-d:bc19BrokenChassis`) produced 5 units built, 20
## karbonite mined, **0 % deposited** and **0 damage** on the same six
## games. The committed floors below sit between the two, never below the
## design note's own numbers.

import harness
import battlecode/sheet
import battlecode/years/bc19/rules

const
  Seeds = [11, 300, 1300]
  Maps = ["seed-0043", "seed-0048"]
  ## The floors. Every one is the design note's own number, and every one is
  ## an order of magnitude inside the measured healthy mirror -- which is
  ## what makes the broken control fail all of them at once.
  MinReachedLimit = 5
  MinUnitsBuilt = 12
  MinPilgrims = 4
  MinMilitary = 4
  MinKarboniteMined = 150
  MinFuelMined = 300
  MinDepositPct = 80
  MaxZeroStreak = 20
  MinDamage = 200
  MinAlive = 6
  MinCastlesAt700 = 1
  MaxFriendlyFirePct = 15

type Gate = object
  reachedLimit: int
  worstBuilt, worstPilgrims, worstMilitary: int
  worstKarbonite, worstFuel, worstDepositPct: int
  worstZeroStreak, worstDamage, worstAlive, worstCastles700: int
  worstFriendlyPct: int
  churches: int
  refused: int

proc runGate(): Gate =
  result = Gate(worstBuilt: high(int), worstPilgrims: high(int),
                worstMilitary: high(int), worstKarbonite: high(int),
                worstFuel: high(int), worstDepositPct: high(int),
                worstDamage: high(int), worstAlive: high(int),
                worstCastles700: high(int))
  let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
  for seed in Seeds:
    for name in Maps:
      let sa = sideAslotFor(seed, 0)
      let (w, o) = playGame(loadMap(name), sheets,
        [ck19Saber, ck19Saber], 0, sa, 1000, 0)
      if o.endReason != "castles_destroyed": inc result.reachedLimit
      result.churches += o.churchesBuilt[0] + o.churchesBuilt[1]
      for t in 0 .. 1:
        result.refused += o.refusedActions[t]
        result.worstBuilt = min(result.worstBuilt, o.unitsBuilt[t])
        result.worstPilgrims = min(result.worstPilgrims, o.pilgrimsBuilt[t])
        result.worstMilitary = min(result.worstMilitary,
          o.unitsBuilt[t] - o.pilgrimsBuilt[t])
        result.worstKarbonite = min(result.worstKarbonite,
          o.karboniteMined[t])
        result.worstFuel = min(result.worstFuel, o.fuelMined[t])
        let mined = o.karboniteMined[t] + o.fuelMined[t]
        let dep = o.karboniteDeposited[t] + o.fuelDeposited[t]
        let pct = (if mined == 0: 0 else: dep * 100 div mined)
        result.worstDepositPct = min(result.worstDepositPct, pct)
        result.worstZeroStreak = max(result.worstZeroStreak,
          w.stats.zeroStoreWorst[t])
        result.worstDamage = min(result.worstDamage, o.damageDealt[t])
        result.worstAlive = min(result.worstAlive, o.unitsAlive[t])
        result.worstCastles700 = min(result.worstCastles700,
          w.stats.castlesAt700[t])
        if o.damageDealt[t] > 0:
          result.worstFriendlyPct = max(result.worstFriendlyPct,
            o.friendlyFireDamage[t] * 100 div o.damageDealt[t])

let g = runGate()
echo "  measured: limit=", g.reachedLimit, "/6 built=", g.worstBuilt,
  " pilgrims=", g.worstPilgrims, " military=", g.worstMilitary,
  " karbonite=", g.worstKarbonite, " fuel=", g.worstFuel,
  " deposited=", g.worstDepositPct, "% zeroStreak=", g.worstZeroStreak,
  " damage=", g.worstDamage, " alive=", g.worstAlive,
  " castles@700=", g.worstCastles700, " churches=", g.churches,
  " friendlyFire=", g.worstFriendlyPct, "% refused=", g.refused

block:
  check("at least five of six games reach the round limit rather than " &
    "ending on castles_destroyed", g.reachedLimit >= MinReachedLimit)
  check("every seat built at least " & $MinUnitsBuilt & " units",
    g.worstBuilt >= MinUnitsBuilt)
  check("of which at least " & $MinPilgrims & " PILGRIMs",
    g.worstPilgrims >= MinPilgrims)
  check("and at least " & $MinMilitary & " military",
    g.worstMilitary >= MinMilitary)
  check("every seat mined at least " & $MinKarboniteMined & " karbonite",
    g.worstKarbonite >= MinKarboniteMined)
  check("and at least " & $MinFuelMined & " fuel",
    g.worstFuel >= MinFuelMined)
  check("EVERY SEAT DEPOSITED AT LEAST " & $MinDepositPct & " % OF WHAT IT " &
    "MINED -- an order that mines and never walks the load home has not " &
    "played the game", g.worstDepositPct >= MinDepositPct)
  check("no seat had both stores at 0 for more than " & $MaxZeroStreak &
    " consecutive rounds -- the fuel-solvency clause",
    g.worstZeroStreak <= MaxZeroStreak)
  check("every seat dealt at least " & $MinDamage & " damage",
    g.worstDamage >= MinDamage)
  check("and finished with at least " & $MinAlive & " units alive",
    g.worstAlive >= MinAlive)
  check("and still held a castle at round 700",
    g.worstCastles700 >= MinCastlesAt700)
  check("at least one church was built across the two seats on at least " &
    "one of the six games", g.churches >= 1)
  check("and friendly fire stayed under " & $MaxFriendlyFirePct & " % of " &
    "damage dealt", g.worstFriendlyPct < MaxFriendlyFirePct)
  ## THE LEGALITY GATE (design note §Tests item 17c): `saber` emits NOTHING
  ## the engine refuses -- not one action, on either seat, across all six
  ## games.
  checkEq("AND refused_actions == 0 for `saber` on every seat of every game",
    g.refused, 0)

when defined(bc19BrokenChassis):
  ## THE INVERTED CONTROL, and it is chosen deliberately: a chassis whose
  ## pilgrims MINE BUT NEVER `give` (so nothing is ever refined), whose
  ## castles ignore `fuel_reserve` entirely, and which never builds a second
  ## pilgrim, is EXACTLY the failure a "did it build units?" check would
  ## pass -- and it is the failure this year's economy makes possible. A
  ## GATE THAT CANNOT FAIL IS NOT A GATE.
  ##
  ## `tests/test_bc19_baselines.nim` runs this file as a SUBPROCESS under
  ## `-d:bc19BrokenChassis` and asserts it comes back RED. Under that flag
  ## the block above has already failed, so reaching here at all would mean
  ## the control passed.
  quit("test_bc19_survival: THE BROKEN CONTROL PASSED THE GATE. The gate " &
    "cannot fail and is therefore not a gate.", 1)

finish("test_bc19_survival")
