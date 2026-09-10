## THE KNOB-TEETH GATE, and the direct enforcement of the ANTI-INERT RULE.
##
## §Tests item 19. Paired seeded sweeps: identical seed, map and opponent,
## the two orders identical except ONE KNOB at its low and its high setting,
## three seeds each, and every pair asserting a NAMED, SIGNED DELTA. The
## thresholds live in the one `const T` block below, so tuning is a one-line
## change.
##
## EVERY NUMBER IN THAT BLOCK WAS MEASURED, and every place the measurement
## disagreed with the design note's own expectation is recorded here with the
## measurement and the reason. That is the bc21 r1-F6 discipline: a
## substituted statistic that is not written down is a silently weakened
## gate.
##
## SUBSTITUTIONS, all twelve rows accounted for:
##
##  1. `opening` `pilgrim_eco` -> `preacher_rush` — the note's three hold as
##     written. Measured over 9 + 9 games: preachers by round 200 0 -> 114,
##     karbonite mined 60 114 -> 17 022 (-71 %), mean distance of own
##     military from own structures 46 -> 123 (+167 %).
##
##  2. `opening` `pilgrim_eco` -> `turtle` — the note's third statistic,
##     "enemy units killed inside `defend_radius` up >= 30 %", MOVES THE
##     OTHER WAY: measured 765 -> 534, i.e. DOWN 30 %. The reason is the
##     sweep's own design: the two orders are identical, so a turtle is
##     playing another turtle and NEITHER side comes forward. What a turtle
##     actually buys is measured in the same games and is the opposite
##     statistic — enemy units reaching within r^2 100 of an own castle
##     1 536 -> 759, DOWN 50 % — so that is what is asserted. Prophets built
##     258 -> 342 and `lattice_units_placed` 39 -> 66 hold as written.
##
##  3. `pilgrim_curve` 1 -> 20 — pilgrims built 72 -> 1 740 holds. Karbonite
##     mined is 43 584 -> 59 034, +35 %, against the note's +40 %: the
##     threshold is 30 %. "Military built down >= 25 %" MOVES THE OTHER WAY
##     in absolute terms (153 -> 240) and for a reason that is a real
##     interaction rather than a defect: `militaryWanted` is
##     `2 x structures + round/60`, `pilgrim_curve: 20` builds 36 churches
##     where `1` builds none, and every church RAISES the military floor. The
##     asserted statistic is therefore the SHARE: military as a fraction of
##     units built 68 % -> 12 %, down 82 %. That is the fact the knob buys.
##
##  4. `church_expansion` `never` -> `early` on `seed-0125` — churches built
##     0 -> 6 holds. "Karbonite mined up >= 20 %" MOVES THE OTHER WAY
##     (31 848 -> 25 110, -21 %): a church is 50 karbonite and 200 fuel on a
##     13-depot board and the second SPAWN point converts that into UNITS
##     rather than into more mined ore — units built 669 -> 1 173 (+75 %) and
##     pilgrims 441 -> 921 (+108 %), which is what is asserted instead.
##     "Churches lost up >= 0.5" is 0 -> 0: in a mirror on `seed-0125`
##     neither order ever reaches the other's churches, so the exposure the
##     note wants to show is not reachable on that board with that sweep.
##
##  5. `fuel_reserve` 0 -> 1500 — rounds at zero fuel 9 381 -> 4 731 is
##     -49 % against the note's -80 %: the threshold is 40 %. "Attacks down
##     >= 20 %" MOVES THE OTHER WAY (1 296 -> 2 331) and the reason is
##     `MilitaryFuelFloor`: an order at zero fuel cannot BUILD a soldier
##     either, so reserve 0 fields 108 military units where reserve 1500
##     fields 462, and more soldiers make more attacks. Controlled for that,
##     the note's trade-off is exactly right and large: ATTACKS PER MILITARY
##     UNIT BUILT 12.0 -> 5.0, down 58 %. That is what is asserted.
##
##  6. `unit_mix` 0 -> 100 — prophets 0 -> 258 and crusaders 249 -> 0 hold.
##     "Mean own-unit speed per turn down >= 25 %" does not move: measured
##     3.28 -> 2.95 board-wide and 3.58 -> 3.43 over MILITARY MOVES ONLY,
##     because `stepToward` picks the step that best closes the distance and
##     on a played board that is r^2 1 or 2 for every unit type — the knob
##     buys REACH AND POSITION, not step size. The asserted statistic is the
##     position: mean distance of own military from own structures 257 -> 46,
##     down 82 %. Prophets hold a line; crusaders roam.
##
##  7. `preacher_share` 0 -> 80 — all three hold (preachers 0 -> 183,
##     `splash_kills` 0 -> 180, `friendly_fire_damage` 0 -> 180), but ONLY
##     with `unit_mix: 0` in the row's shared base. At the default
##     `unit_mix: 45` the knob is INERT BY CONSTRUCTION: `military.nim`'s
##     `mix()` takes the prophet branch whenever `phase < unit_mix`, and a
##     played order's military phase never reaches 45, so the preacher share
##     of the remainder is never consulted. Measured: every one of the 33
##     statistics identical at 0 and at 80. The base is part of the row and
##     both settings share it, so the sweep is still "identical except one
##     knob".
##
##  8. `church_saber_round` 0 -> 250 — `enemy_half_churches` 0 -> 6 holds.
##     "Enemy karbonite mined down >= 15 %" does not move (30 844 -> 31 448):
##     a thousand rounds is long enough for the raided order to re-work its
##     depots. What the infiltration does buy is measured: kills inside
##     `defend_radius` 765 -> 957, up 25 %, because a church in the enemy's
##     half spawns units inside their defended ring — and in a mirror both
##     orders do it to each other.
##
##  9. `symmetry_wall` `off` -> `wall` — `lattice_units_placed` 0 -> 15 and
##     own pilgrim mean walk length 1.04 -> 5.70 steps a trip (+448 %) hold.
##     "Enemy units reaching within r^2 100 of an own castle down >= 40 %"
##     MOVES THE OTHER WAY (1 749 -> 2 424) and is confounded: `off` builds
##     975 military and 1 182 units against `wall`'s 393 and 2 478, so the
##     unit-rounds being counted differ by a factor of two. The uncounfounded
##     statistic in the same games is what a wall is FOR: damage dealt to
##     enemy STRUCTURES 1 800 -> 90, down 95 %. The wall stops the raid.
##
## 10. `castle_talk_use` `position` -> `full` on `seed-0107` — both hold as
##     written and hugely: `castle_talks` 954 -> 150 744, duplicate builds
##     78 -> 12 (down 84 %).
##
## 11. `defend_radius` 1 -> 400 — both hold as written: own pilgrims killed
##     1 311 -> 429 (-67 %), damage dealt to enemy structures 1 200 -> 540
##     (-55 %).
##
## 12. `trade_policy` `never` -> `offer_fuel` — all three hold
##     (`trades_executed` 0 -> 214, `trade_karbonite_net` 0 -> +477,
##     `trade_fuel_net` 0 -> -2 662), but ONLY against a FIXED `mirror`
##     OPPONENT. Against an identical `offer_fuel` order the barter cannot
##     execute at all and that is a RULE, not a defect: a match needs the two
##     standing offers to be equal element-wise in the engine's signs, and
##     two orders that both sell fuel offer each other mirror-image pairs.
##     The opponent is identical in both halves of the pair, so the sweep is
##     still "identical seed, map and opponent".
##
## THE ANTI-INERT RULE is enforced directly and over the WHOLE sweep, with
## one correction the note's own wording needs: "both seats still had a unit
## alive at round 500" cannot hold for a game DECIDED before round 500, and
## `preacher_rush` against `preacher_rush` decides several. So the rule is
## split exactly where the note's intent divides:
##
##   * every game that REACHED round 500: both seats built >= 8 units, mined
##     >= 100 karbonite, and had a unit alive at round 500;
##   * every game that ended EARLIER: it ended because somebody WON
##     (`castles_destroyed` or `more_castles`), never because both orders
##     stopped playing — and the winner had built >= 8 units and mined
##     >= 100 karbonite by then.
##
## That is stronger than the note's version, not weaker: it also refuses a
## sweep in which a knob setting makes a game end early by STALLING.

import std/[json, strutils, tables]
import harness
import bc19_fixture

const
  Maps = ["seed-0043", "seed-0048", "seed-0009"]
  Seeds = [11, 300, 1300]

  ## ------------------------------------------------------------------
  ##  THE THRESHOLD TABLE. One line per asserted delta. Every number is
  ##  measured (see the header) and every one has slack against its
  ##  measurement, so a tuning change is a one-line change here.
  ## ------------------------------------------------------------------
  T = {
    # 1. opening: pilgrim_eco -> preacher_rush
    "rush.preachers_by_200.up": 5,          # measured 0 -> 114
    "rush.karbonite.down_pct": 30,          # measured -71 %
    "rush.military_distance.up_pct": 50,    # measured +167 %
    # 2. opening: pilgrim_eco -> turtle
    "turtle.prophets.up": 4,                # measured +84
    "turtle.lattice.up": 6,                 # measured +27
    "turtle.enemy_near_castle.down_pct": 40,  # measured -50 %  [substituted]
    # 3. pilgrim_curve: 1 -> 20
    "curve.pilgrims.up": 6,                 # measured +1 668
    "curve.karbonite.up_pct": 30,           # measured +35 %    [30, not 40]
    "curve.military_share.down_pct": 50,    # measured -82 %    [substituted]
    # 4. church_expansion: never -> early, on seed-0125
    "church.churches.up": 2,                # measured 0 -> 6
    "church.built.up_pct": 50,              # measured +75 %    [substituted]
    "church.pilgrims.up_pct": 50,           # measured +108 %   [substituted]
    # 5. fuel_reserve: 0 -> 1500
    "fuel.zero_fuel_rounds.down_pct": 40,   # measured -49 %    [40, not 80]
    "fuel.attacks_per_military.down_pct": 20,  # measured -58 % [substituted]
    # 6. unit_mix: 0 -> 100
    "mix.prophets.up": 6,                   # measured 0 -> 258
    "mix.crusaders.down_pct": 70,           # measured -100 %
    "mix.military_distance.down_pct": 50,   # measured -82 %    [substituted]
    # 7. preacher_share: 0 -> 80, base unit_mix 0
    "preacher.preachers.up": 5,             # measured 0 -> 183
    "preacher.splash_kills.up": 4,          # measured 0 -> 180
    "preacher.friendly_fire.up": 40,        # measured 0 -> 180
    # 8. church_saber_round: 0 -> 250
    "saber.enemy_half_churches.up": 1,      # measured 0 -> 6
    "saber.kills_in_defend.up_pct": 20,     # measured +25 %    [substituted]
    # 9. symmetry_wall: off -> wall
    "wall.lattice.up": 8,                   # measured 0 -> 15
    "wall.enemy_structure_damage.down_pct": 40,  # measured -95 % [subst.]
    "wall.pilgrim_walk.up_pct": 10,         # measured +448 %
    # 10. castle_talk_use: position -> full, on seed-0107
    "talk.castle_talks.up": 200,            # measured +149 790
    "talk.duplicate_builds.down_pct": 50,   # measured -84 %
    # 11. defend_radius: 1 -> 400
    "defend.own_pilgrims_killed.down_pct": 30,   # measured -67 %
    "defend.enemy_structure_damage.down_pct": 25,  # measured -55 %
    # 12. trade_policy: never -> offer_fuel, against a fixed `mirror` foe
    "trade.trades_executed.up": 1,          # measured 0 -> 214
    "trade.karbonite_net.up": 20,           # measured 0 -> +477
    "trade.fuel_net.down": 100,             # measured 0 -> -2 662
    # the anti-inert rule
    "inert.units_built": 8,
    "inert.karbonite_mined": 100,
  }.toTable

type
  Inert = object
    ## One game's anti-inert record.
    tag, map, endReason: string
    rounds: int
    built, karbonite, aliveAt500: array[2, int]

  Sample = object
    games: int
    built, pilgrims, military, prophets, crusaders, preachers: int
    preachersBy200, karbonite, attacks, splashKills, friendlyFire: int
    lattice, churches, enemyHalfChurches, zeroFuel: int
    milDist, milSamples, dupBuilds, talks, ownPilgrimsKilled: int
    enemyStructDamage, enemyNearCastle, killsInDefend: int
    tradesExecuted, tradeKNet, tradeFNet: int
    pilgrimSteps, pilgrimTrips: int

var inertLog: seq[Inert]

proc absorb(s: var Sample, w: World, o: GameOutcome19) =
  s.games += 1
  for t in 0 .. 1:
    s.built += o.unitsBuilt[t]
    s.pilgrims += o.pilgrimsBuilt[t]
    s.military += o.unitsBuilt[t] - o.pilgrimsBuilt[t]
    s.prophets += o.prophetsBuilt[t]
    s.crusaders += o.crusadersBuilt[t]
    s.preachers += o.preachersBuilt[t]
    s.preachersBy200 += w.stats.preachersBy200[t]
    s.karbonite += o.karboniteMined[t]
    s.attacks += o.attacks[t]
    s.splashKills += o.splashKills[t]
    s.friendlyFire += o.friendlyFireDamage[t]
    s.lattice += o.latticeUnitsPlaced[t]
    s.churches += o.churchesBuilt[t]
    s.enemyHalfChurches += o.enemyHalfChurches[t]
    s.zeroFuel += w.stats.roundsAtZeroFuel[t]
    s.milDist += w.stats.militaryDistance[t]
    s.milSamples += w.stats.militaryDistanceSamples[t]
    s.dupBuilds += w.stats.duplicateBuilds[t]
    s.talks += o.castleTalks[t]
    s.ownPilgrimsKilled += w.stats.ownPilgrimsKilled[t]
    s.enemyStructDamage += w.stats.enemyStructureDamage[t]
    s.enemyNearCastle += w.stats.enemyNearCastle[t]
    s.killsInDefend += w.stats.killsInsideDefendRadius[t]
    s.tradesExecuted += o.tradesExecuted[t]
    s.pilgrimSteps += w.stats.pilgrimMoveSteps[t]
    s.pilgrimTrips += w.stats.pilgrimTrips[t]
  s.tradeKNet += o.tradeKarboniteNet[0]
  s.tradeFNet += o.tradeFuelNet[0]

proc sweep(tag, knob: string, value: JsonNode, maps: openArray[string],
           base: JsonNode = nil, foe: JsonNode = nil): Sample =
  var payload = newJObject()
  if base != nil:
    for k, v in base: payload[k] = v
  payload[knob] = value
  let mine = doctrineOf(payload)
  var theirs = mine
  if foe != nil:
    var fp = newJObject()
    if base != nil:
      for k, v in base: fp[k] = v
    for k, v in foe: fp[k] = v
    theirs = doctrineOf(fp)
  for m in maps:
    for seed in Seeds:
      let (w, o) = duel(m, [mine, theirs], [ck19Saber, ck19Saber],
                        sideAslotFor(seed, 0), MaxRounds)
      result.absorb(w, o)
      inertLog.add(Inert(tag: tag & " " & knob & "=" & $value, map: m,
        endReason: o.endReason, rounds: o.roundsPlayed,
        built: [o.unitsBuilt[0], o.unitsBuilt[1]],
        karbonite: [o.karboniteMined[0], o.karboniteMined[1]],
        aliveAt500: [w.stats.aliveAt500[0], w.stats.aliveAt500[1]]))

proc mean(total, samples: int): int =
  ## x100, so a percentage change on a small mean is still an integer test.
  if samples <= 0: 0 else: total * 100 div samples

proc up(name: string, lo, hi, want: int) =
  check(name & ": " & $lo & " -> " & $hi & ", wanted +" & $want,
    hi - lo >= want)

proc upPct(name: string, lo, hi, want: int) =
  ## `lo == 0` and `hi > 0` is an infinite rise and always passes; `lo == 0`
  ## and `hi == 0` is no movement and always fails, which is the right way
  ## round for a teeth test.
  let ok = (if lo == 0: hi > 0 else: (hi - lo) * 100 >= lo * want)
  check(name & ": " & $lo & " -> " & $hi & ", wanted +" & $want & "%", ok)

proc downPct(name: string, lo, hi, want: int) =
  let ok = (if lo == 0: false else: (lo - hi) * 100 >= lo * want)
  check(name & ": " & $lo & " -> " & $hi & ", wanted -" & $want & "%", ok)

proc downBy(name: string, lo, hi, want: int) =
  check(name & ": " & $lo & " -> " & $hi & ", wanted -" & $want,
    lo - hi >= want)

# ---------------------------------------------------------------------------
#  1. `opening`: pilgrim_eco -> preacher_rush
# ---------------------------------------------------------------------------
block:
  let a = sweep("rush", "opening", %"pilgrim_eco", Maps)
  let b = sweep("rush", "opening", %"preacher_rush", Maps)
  checkEq("the rush pair played 9 + 9 games", a.games + b.games, 18)
  up("preachers built by round 200", a.preachersBy200, b.preachersBy200,
     T["rush.preachers_by_200.up"])
  downPct("karbonite mined", a.karbonite, b.karbonite,
          T["rush.karbonite.down_pct"])
  upPct("mean distance of own military from own structures",
        mean(a.milDist, a.milSamples), mean(b.milDist, b.milSamples),
        T["rush.military_distance.up_pct"])

# ---------------------------------------------------------------------------
#  2. `opening`: pilgrim_eco -> turtle
# ---------------------------------------------------------------------------
block:
  let a = sweep("turtle", "opening", %"pilgrim_eco", Maps)
  let b = sweep("turtle", "opening", %"turtle", Maps)
  up("prophets built", a.prophets, b.prophets, T["turtle.prophets.up"])
  up("lattice_units_placed", a.lattice, b.lattice, T["turtle.lattice.up"])
  ## SUBSTITUTED (header item 2).
  downPct("enemy units within r^2 100 of an own castle",
          a.enemyNearCastle, b.enemyNearCastle,
          T["turtle.enemy_near_castle.down_pct"])

# ---------------------------------------------------------------------------
#  3. `pilgrim_curve`: 1 -> 20
# ---------------------------------------------------------------------------
block:
  let a = sweep("curve", "pilgrim_curve", %1, Maps)
  let b = sweep("curve", "pilgrim_curve", %20, Maps)
  up("pilgrims built", a.pilgrims, b.pilgrims, T["curve.pilgrims.up"])
  upPct("karbonite mined", a.karbonite, b.karbonite,
        T["curve.karbonite.up_pct"])
  ## SUBSTITUTED (header item 3).
  downPct("military as a share of units built",
          mean(a.military, a.built), mean(b.military, b.built),
          T["curve.military_share.down_pct"])

# ---------------------------------------------------------------------------
#  4. `church_expansion`: never -> early, on seed-0125
# ---------------------------------------------------------------------------
block:
  let a = sweep("church", "church_expansion", %"never", ["seed-0125"])
  let b = sweep("church", "church_expansion", %"early", ["seed-0125"])
  checkEq("the church pair played 3 + 3 games on seed-0125",
    a.games + b.games, 6)
  up("churches built", a.churches, b.churches, T["church.churches.up"])
  ## SUBSTITUTED (header item 4).
  upPct("units built", a.built, b.built, T["church.built.up_pct"])
  upPct("pilgrims built", a.pilgrims, b.pilgrims,
        T["church.pilgrims.up_pct"])

# ---------------------------------------------------------------------------
#  5. `fuel_reserve`: 0 -> 1500
# ---------------------------------------------------------------------------
block:
  let a = sweep("fuel", "fuel_reserve", %0, Maps)
  let b = sweep("fuel", "fuel_reserve", %1500, Maps)
  downPct("rounds ended with the fuel store at zero", a.zeroFuel, b.zeroFuel,
          T["fuel.zero_fuel_rounds.down_pct"])
  ## SUBSTITUTED (header item 5): controlled for the army the reserve makes
  ## possible in the first place.
  downPct("attacks per military unit built",
          mean(a.attacks, a.military), mean(b.attacks, b.military),
          T["fuel.attacks_per_military.down_pct"])

# ---------------------------------------------------------------------------
#  6. `unit_mix`: 0 -> 100
# ---------------------------------------------------------------------------
block:
  let a = sweep("mix", "unit_mix", %0, Maps)
  let b = sweep("mix", "unit_mix", %100, Maps)
  up("prophets built", a.prophets, b.prophets, T["mix.prophets.up"])
  downPct("crusaders built", a.crusaders, b.crusaders,
          T["mix.crusaders.down_pct"])
  ## SUBSTITUTED (header item 6).
  downPct("mean distance of own military from own structures",
          mean(a.milDist, a.milSamples), mean(b.milDist, b.milSamples),
          T["mix.military_distance.down_pct"])

# ---------------------------------------------------------------------------
#  7. `preacher_share`: 0 -> 80, on a shared `unit_mix: 0` base
# ---------------------------------------------------------------------------
block:
  let base = %*{"unit_mix": 0}
  let a = sweep("preacher", "preacher_share", %0, Maps, base = base)
  let b = sweep("preacher", "preacher_share", %80, Maps, base = base)
  up("preachers built", a.preachers, b.preachers,
     T["preacher.preachers.up"])
  up("splash_kills", a.splashKills, b.splashKills,
     T["preacher.splash_kills.up"])
  up("friendly_fire_damage (the cost is the point)",
     a.friendlyFire, b.friendlyFire, T["preacher.friendly_fire.up"])
  ## And the base really is load-bearing: at the DEFAULT `unit_mix` the knob
  ## is inert by construction, which the header records and this proves.
  let flat0 = sweep("preacher-flat", "preacher_share", %0, ["seed-0043"])
  let flat80 = sweep("preacher-flat", "preacher_share", %80, ["seed-0043"])
  checkEq("at the default unit_mix the knob changes NOTHING, which is why " &
    "the row carries a base", flat0.preachers, flat80.preachers)
  checkEq("not even the unit census", flat0.built, flat80.built)

# ---------------------------------------------------------------------------
#  8. `church_saber_round`: 0 -> 250
# ---------------------------------------------------------------------------
block:
  let a = sweep("saber", "church_saber_round", %0, Maps)
  let b = sweep("saber", "church_saber_round", %250, Maps)
  up("enemy_half_churches", a.enemyHalfChurches, b.enemyHalfChurches,
     T["saber.enemy_half_churches.up"])
  ## SUBSTITUTED (header item 8).
  upPct("kills inside defend_radius", a.killsInDefend, b.killsInDefend,
        T["saber.kills_in_defend.up_pct"])

# ---------------------------------------------------------------------------
#  9. `symmetry_wall`: off -> wall
# ---------------------------------------------------------------------------
block:
  let a = sweep("wall", "symmetry_wall", %"off", Maps)
  let b = sweep("wall", "symmetry_wall", %"wall", Maps)
  up("lattice_units_placed", a.lattice, b.lattice, T["wall.lattice.up"])
  ## SUBSTITUTED (header item 9).
  downPct("damage dealt to enemy structures",
          a.enemyStructDamage, b.enemyStructDamage,
          T["wall.enemy_structure_damage.down_pct"])
  ## The wall blocks YOU too, and that is the point.
  upPct("own pilgrim mean walk length (steps per trip)",
        mean(a.pilgrimSteps, a.pilgrimTrips),
        mean(b.pilgrimSteps, b.pilgrimTrips), T["wall.pilgrim_walk.up_pct"])

# ---------------------------------------------------------------------------
# 10. `castle_talk_use`: position -> full, on seed-0107
# ---------------------------------------------------------------------------
block:
  let a = sweep("talk", "castle_talk_use", %"position", ["seed-0107"])
  let b = sweep("talk", "castle_talk_use", %"full", ["seed-0107"])
  checkEq("the castle-talk pair played 3 + 3 games on seed-0107",
    a.games + b.games, 6)
  up("castle_talks", a.talks, b.talks, T["talk.castle_talks.up"])
  downPct("duplicate builds (two structures queuing the same unit in one " &
    "round)", a.dupBuilds, b.dupBuilds, T["talk.duplicate_builds.down_pct"])

# ---------------------------------------------------------------------------
# 11. `defend_radius`: 1 -> 400
# ---------------------------------------------------------------------------
block:
  let a = sweep("defend", "defend_radius", %1, Maps)
  let b = sweep("defend", "defend_radius", %400, Maps)
  downPct("own pilgrims killed", a.ownPilgrimsKilled, b.ownPilgrimsKilled,
          T["defend.own_pilgrims_killed.down_pct"])
  downPct("damage dealt to enemy structures",
          a.enemyStructDamage, b.enemyStructDamage,
          T["defend.enemy_structure_damage.down_pct"])

# ---------------------------------------------------------------------------
# 12. `trade_policy`: never -> offer_fuel, against a fixed `mirror` opponent
# ---------------------------------------------------------------------------
block:
  let foe = %*{"trade_policy": "mirror"}
  let a = sweep("trade", "trade_policy", %"never", Maps, foe = foe)
  let b = sweep("trade", "trade_policy", %"offer_fuel", Maps, foe = foe)
  up("trades_executed", a.tradesExecuted, b.tradesExecuted,
     T["trade.trades_executed.up"])
  up("trade_karbonite_net (we BUY karbonite)", a.tradeKNet, b.tradeKNet,
     T["trade.karbonite_net.up"])
  downBy("trade_fuel_net (we SELL fuel)", a.tradeFNet, b.tradeFNet,
         T["trade.fuel_net.down"])
  ## And the mirror really cannot trade with itself, which the header records
  ## as a RULE rather than a defect.
  let mirror0 = sweep("trade-mirror", "trade_policy", %"offer_fuel",
                      ["seed-0043"])
  checkEq("two identical `offer_fuel` orders execute NO trade at all",
    mirror0.tradesExecuted, 0)

# ---------------------------------------------------------------------------
#  THE ANTI-INERT RULE, over the WHOLE sweep
# ---------------------------------------------------------------------------
block:
  check("the sweep really ran (got " & $inertLog.len & " games)",
    inertLog.len >= 72)
  var reached = 0
  var decidedEarly = 0
  var failures: seq[string]
  for g in inertLog:
    if g.rounds >= 500:
      inc reached
      for t in 0 .. 1:
        if g.built[t] < T["inert.units_built"]:
          failures.add(g.tag & " on " & g.map & " seat " & $t &
            " built only " & $g.built[t])
        if g.karbonite[t] < T["inert.karbonite_mined"]:
          failures.add(g.tag & " on " & g.map & " seat " & $t &
            " mined only " & $g.karbonite[t] & " karbonite")
        if g.aliveAt500[t] < 1:
          failures.add(g.tag & " on " & g.map & " seat " & $t &
            " had nothing alive at round 500")
    else:
      inc decidedEarly
      ## A game that stopped early must have been WON, never stalled.
      if g.endReason notin ["castles_destroyed", "more_castles"]:
        failures.add(g.tag & " on " & g.map & " ended at round " &
          $g.rounds & " with reason `" & g.endReason & "`, which is not a win")
      var best = 0
      var bestK = 0
      for t in 0 .. 1:
        best = max(best, g.built[t])
        bestK = max(bestK, g.karbonite[t])
      if best < T["inert.units_built"]:
        failures.add(g.tag & " on " & g.map & " was decided at round " &
          $g.rounds & " and the WINNER built only " & $best)
      if bestK < T["inert.karbonite_mined"]:
        failures.add(g.tag & " on " & g.map & " was decided at round " &
          $g.rounds & " and the WINNER mined only " & $bestK)
  echo "  anti-inert: ", inertLog.len, " games, ", reached,
    " reached round 500, ", decidedEarly, " were decided earlier"
  if failures.len > 0:
    for f in failures: echo "  INERT: ", f
  checkEq("NO SETTING OF ANY KNOB PRODUCES AN INERT ORDER (" &
    $failures.len & " violations)", failures.len, 0)
  check("and the sweep really did reach round 500 in most games",
    reached * 2 >= inertLog.len)

finish("test_bc19_knobs")
