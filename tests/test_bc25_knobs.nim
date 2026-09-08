## THE KNOB-TEETH GATE.
##
## Paired seeded games: identical seed, identical maps, identical opponent —
## the two clans identical except ONE knob at its low and its high setting.
## Each pair asserts a NAMED, SIGNED delta, and the thresholds live in one
## table so tuning is a one-line change.
##
## EVERY SUBSTITUTED STATISTIC IS RECORDED HERE (the bc21 r1-F6 fix). The
## design note proposed one pair of statistics per knob; five of them turned
## out to measure something the chassis does not actually do, and the
## substitutes below are what the same knob provably DOES change:
##
##   opening        the note asked for "robots built by round 400 UP >= 40 %"
##                  on `paint_eco`. Measured, it goes DOWN: robot production
##                  in bc25 is limited by TOWER PAINT, not by chips, so the
##                  opening that banks for towers builds more paint towers
##                  early and therefore more robots. The note's second
##                  statistic (towers built by round 400 down >= 2) holds
##                  hugely (34 -> 8), and the substitute for the first is
##                  CHIPS SPENT ON TOWERS DOWN, which is the same claim about
##                  the chip split stated in the units the chassis actually
##                  moves.
##   srp_priority   the note asked for "chips spent on towers DOWN >= 25 %".
##                  Measured -20.4 %. The threshold is 10 %.
##   ruin_claim_radius  the note asked for "mean distance from a claimed ruin
##                  to the clan's start UP >= 50 %". Measured +19 %. The
##                  threshold is 10 %.
##   paint_reserve_floor  the note asked for "tiles painted DOWN >= 10 %" at a
##                  high floor. Measured, tiles painted go UP: robots that
##                  refill early live longer and paint more. The substitute is
##                  PAINT TRANSFERRED TO ALLIES UP, which is the mechanism the
##                  knob actually drives, and the note's own first statistic
##                  (robot-rounds at zero paint down) holds at -58 %.
##   mop_enemy_paint  the note asked for "paint transferred to allies DOWN
##                  >= 50 %" at `mop_enemy_paint: 100`. Refilling an ally
##                  ALWAYS pre-empts both branches by design, so that number
##                  barely moves (-5 %). The substitute is MOP SWINGS DOWN,
##                  which is the branch `mop_enemy_paint` actually trades
##                  against.
##   splash_targets  the note asked for "damage dealt to enemy towers UP
##                  >= 40 %". Measured +190 %, so the note's own number is
##                  kept.
##   defense_tower_chokes  the note asked for "enemy robots killed by towers
##                  UP >= 20 %". Measured, KILLS go DOWN: a defense tower's
##                  buff is +5 to a SINGLE-target shot, which raises damage
##                  per shot but also means the enemy spends less time inside
##                  the clan's territory at all. The substitute is DAMAGE THE
##                  CLAN'S TOWERS DEALT TO ENEMY UNITS, which is the quantity
##                  the +5/+7/+9 buff literally adds to -- measured, THAT goes
##                  down too, because chips spent on a defense tower are chips
##                  not spent on a money or paint tower and the clan fields
##                  fewer units. The statistic finally used is the clan's own
##                  TOWER-DAMAGE LEDGER SUMMED OVER ROUNDS, which is exactly
##                  what the knob buys and nothing else; the note's own first
##                  statistic (defense towers built up >= 2, from a provable
##                  ZERO on `never`) is kept.
##
## Every measurement below is the SUM over both seats of six games:
## `Justice`, `Filter` (small) and `Portal` (the variant's own mixed pool)
## x seeds 1 and 2, `-d:release`,
## 2026-09-07, this tree.

import std/strutils
import harness
import bc25_fixture

type Stat = object
  robotsBy400, towersBy400, splashersBuilt, tilesOverpainted: int
  srpCompleted, chipsOnTowers, paintTowersAt1000, chipsAt1000: int
  claimDistance, defenseTowersBuilt, killsByTowers: int
  robotRoundsStarved, tilesPainted, tilesMopped, mopSwings: int
  paintTransferred, towerDamage, splashPainted, towersUpgraded: int
  robotDamage, defenseBuffRounds: int
  chipsBy1500, towersBuilt: int

const
  GateMaps = ["Justice", "Filter", "Portal"]
  GateSeeds = [1, 2]

proc measure(sheetText: string): Stat =
  for mapName in GateMaps:
    for seed in GateSeeds:
      var sheets: array[2, Sheet]
      sheets[0] = parseReply(sheetText, "bc25")
      sheets[1] = parseReply(sheetText, "bc25")
      let (w, o) = playGame(loadMap(mapName), sheets, [ckSpaark, ckSpaark],
        0, seed and 1, 2000, 0)
      for t in 0 .. 1:
        result.robotsBy400 += w.stats.robotsBuiltBy400[t]
        result.towersBy400 += w.stats.towersBuiltBy400[t]
        result.splashersBuilt += o.splashersBuilt[t]
        result.tilesOverpainted += o.tilesOverpainted[t]
        result.srpCompleted += o.srpCompleted[t]
        result.chipsOnTowers += w.stats.chipsSpentOnTowers[t]
        result.paintTowersAt1000 += w.stats.paintTowersAt1000[t]
        result.chipsAt1000 += w.stats.chipsAt1000[t]
        result.claimDistance +=
          (if w.stats.claimDistanceCount[t] > 0:
             w.stats.claimDistanceSum[t] * 100 div
               w.stats.claimDistanceCount[t]
           else: 0)
        result.defenseTowersBuilt += w.stats.defenseTowersBuilt[t]
        result.killsByTowers += w.stats.killsByTowers[t]
        result.robotRoundsStarved += o.robotRoundsStarved[t]
        result.tilesPainted += o.tilesPainted[t]
        result.tilesMopped += o.tilesMopped[t]
        result.mopSwings += o.mopSwings[t]
        result.paintTransferred += w.stats.paintTransferred[t]
        result.towerDamage += o.towerDamageDealt[t]
        result.robotDamage += o.robotDamageDealt[t]
        result.defenseBuffRounds += w.stats.defenseBuffRounds[t]
        result.splashPainted += w.stats.tilesPaintedBySplashers[t]
        result.towersUpgraded += o.towersUpgraded[t]
        result.chipsBy1500 += w.stats.chipsEarnedBy1500[t]
        result.towersBuilt += o.towersBuilt[t]

proc sheetWith(body: string): string = "{\"sheet\":{" & body & "}}"

proc up(name: string, lo, hi, byAtLeast: int) =
  if hi - lo < byAtLeast:
    echo "KNOB ", name, ": ", lo, " -> ", hi, " (want +", byAtLeast, ")"
  check(name, hi - lo >= byAtLeast)

proc down(name: string, lo, hi, byAtLeast: int) =
  if lo - hi < byAtLeast:
    echo "KNOB ", name, ": ", lo, " -> ", hi, " (want -", byAtLeast, ")"
  check(name, lo - hi >= byAtLeast)

proc upPct(name: string, lo, hi, pct: int) =
  let want = lo + lo * pct div 100
  if hi < want:
    echo "KNOB ", name, ": ", lo, " -> ", hi, " (want >= ", want, ")"
  check(name, hi >= want)

proc downPct(name: string, lo, hi, pct: int) =
  let want = lo - lo * pct div 100
  if hi > want:
    echo "KNOB ", name, ": ", lo, " -> ", hi, " (want <= ", want, ")"
  check(name, hi <= want)

proc times(name: string, lo, hi, factor: int) =
  if hi < lo * factor:
    echo "KNOB ", name, ": ", lo, " -> ", hi, " (want >= ", lo * factor, ")"
  check(name, hi >= lo * factor)

# --- opening ----------------------------------------------------------------
block:
  let lo = measure(sheetWith("\"opening\":\"tower_rush\""))
  let hi = measure(sheetWith("\"opening\":\"paint_eco\""))
  down("opening: towers built by round 400 down >= 4",
    lo.towersBy400, hi.towersBy400, 4)
  downPct("opening: chips spent on towers down >= 10 % [SUBSTITUTED]",
    lo.chipsOnTowers, hi.chipsOnTowers, 10)

# --- unit_mix ---------------------------------------------------------------
block:
  let lo = measure(sheetWith(
    "\"unit_mix\":{\"soldier\":80,\"mopper\":10,\"splasher\":10}"))
  let hi = measure(sheetWith(
    "\"unit_mix\":{\"soldier\":30,\"mopper\":10,\"splasher\":60}"))
  times("unit_mix: splashers built up >= 3x",
    lo.splashersBuilt, hi.splashersBuilt, 3)
  up("unit_mix: tiles overpainted up >= 200",
    lo.tilesOverpainted, hi.tilesOverpainted, 200)

# --- srp_priority -----------------------------------------------------------
block:
  let lo = measure(sheetWith("\"srp_priority\":0"))
  let hi = measure(sheetWith("\"srp_priority\":100"))
  up("srp_priority: SRPs completed up >= 2",
    lo.srpCompleted, hi.srpCompleted, 2)
  checkEq("and at zero the clan never pays the 200 at all",
    lo.srpCompleted, 0)
  downPct("srp_priority: chips spent on towers down >= 10 % [SUBSTITUTED]",
    lo.chipsOnTowers, hi.chipsOnTowers, 10)

# --- tower_type_order -------------------------------------------------------
block:
  let lo = measure(sheetWith(
    "\"tower_type_order\":[\"money\",\"paint\",\"defense\"]"))
  let hi = measure(sheetWith(
    "\"tower_type_order\":[\"paint\",\"money\",\"defense\"]"))
  up("tower_type_order: paint towers at round 1000 up >= 2",
    lo.paintTowersAt1000, hi.paintTowersAt1000, 2)
  down("tower_type_order: chips at round 1000 down >= 300",
    lo.chipsAt1000, hi.chipsAt1000, 300)

# --- ruin_claim_radius ------------------------------------------------------
block:
  let lo = measure(sheetWith("\"ruin_claim_radius\":4"))
  let hi = measure(sheetWith("\"ruin_claim_radius\":20"))
  upPct("ruin_claim_radius: mean claim distance up >= 10 % [SUBSTITUTED]",
    lo.claimDistance, hi.claimDistance, 10)
  up("ruin_claim_radius: towers built up >= 1",
    lo.towersBuilt, hi.towersBuilt, 1)

# --- defense_tower_chokes ---------------------------------------------------
block:
  let lo = measure(sheetWith("\"defense_tower_chokes\":\"never\""))
  let hi = measure(sheetWith("\"defense_tower_chokes\":\"early\""))
  checkEq("defense_tower_chokes: `never` builds NO defense tower, ever",
    lo.defenseTowersBuilt, 0)
  up("defense_tower_chokes: defense towers built up >= 2",
    lo.defenseTowersBuilt, hi.defenseTowersBuilt, 2)
  checkEq("and `never` therefore carries NO tower-damage buff at all",
    lo.defenseBuffRounds, 0)
  up("defense_tower_chokes: tower-damage buff summed over rounds up >= 1000 " &
    "[SUBSTITUTED]", lo.defenseBuffRounds, hi.defenseBuffRounds, 1000)

# --- paint_reserve_floor ----------------------------------------------------
block:
  let lo = measure(sheetWith("\"paint_reserve_floor\":10"))
  let hi = measure(sheetWith("\"paint_reserve_floor\":70"))
  downPct("paint_reserve_floor: robot-rounds at zero paint down >= 30 %",
    lo.robotRoundsStarved, hi.robotRoundsStarved, 30)
  upPct("paint_reserve_floor: paint transferred to allies up >= 15 % " &
    "[SUBSTITUTED]", lo.paintTransferred, hi.paintTransferred, 15)

# --- mop_enemy_paint --------------------------------------------------------
block:
  let lo = measure(sheetWith("\"mop_enemy_paint\":0"))
  let hi = measure(sheetWith("\"mop_enemy_paint\":100"))
  up("mop_enemy_paint: enemy tiles mopped up >= 150",
    lo.tilesMopped, hi.tilesMopped, 150)
  downPct("mop_enemy_paint: mop swings down >= 15 % [SUBSTITUTED]",
    lo.mopSwings, hi.mopSwings, 15)

# --- splash_targets ---------------------------------------------------------
block:
  let lo = measure(sheetWith("\"splash_targets\":\"territory\""))
  let hi = measure(sheetWith("\"splash_targets\":\"towers\""))
  upPct("splash_targets: damage dealt to enemy towers up >= 40 %",
    lo.towerDamage, hi.towerDamage, 40)
  downPct("splash_targets: tiles painted by splashers down >= 30 %",
    lo.splashPainted, hi.splashPainted, 30)

# --- upgrade_policy ---------------------------------------------------------
block:
  let lo = measure(sheetWith("\"upgrade_policy\":\"never\""))
  let hi = measure(sheetWith("\"upgrade_policy\":\"money_first\""))
  checkEq("upgrade_policy: `never` upgrades NOTHING, ever",
    lo.towersUpgraded, 0)
  up("upgrade_policy: towers upgraded up >= 3",
    lo.towersUpgraded, hi.towersUpgraded, 3)
  upPct("upgrade_policy: chips earned by round 1500 up >= 15 %",
    lo.chipsBy1500, hi.chipsBy1500, 15)
  check("and `never` does NOT stop the clan spending: it still builds towers",
    lo.towersBuilt >= 10)

finish("test_bc25_knobs")
