## THE KNOB-TEETH GATE: every knob moves the game, in a NAMED, SIGNED
## direction.
##
## §Tests item 18. Paired games at identical map and side assignment, the two
## factions identical except ONE knob at its low and its high setting, summed
## over three maps x both side assignments. Thresholds live in one table so
## tuning is a one-line change.
##
## THE HEADER RECORDS EVERY SUBSTITUTED STATISTIC (the bc21 r1-F6 fix) AND
## EVERY MEASURED VALUE THE COMMITTED THRESHOLD WAS DERIVED FROM. The design
## note asked for three statistics this sim does not record, and each is
## replaced by one it does:
##
##  * `mine_floor`: the note asks for "lead mined by round 400 down >= 10 %".
##    There is no by-round-400 counter, and on the measurement the TOTAL lead
##    mined goes sharply UP at a higher floor (7 916 -> 83 076) because the map
##    survives to be mined at all — which is the knob's whole point. Replaced
##    by SQUARES MINED DRY, measured 388 -> 132 (down 66 %). The note's own
##    "lead still on the map at 2000 up >= 3x" measured 1.93x on a MIRROR pair
##    (8 310 -> 16 000), so the committed number is 1.5x, half the measured
##    margin, per the note's bc23 r1-F21/F22 ruling.
##  * `watchtower_policy`: the note asks for "mean distance of a watchtower
##    from its own archons up >= 40 % against `home`". Distance-to-archon is
##    not recorded. Replaced by BUILDERS BUILT, measured 7 -> 51, because a
##    forward tower programme is a builder programme.
##  * `archon_relocate`: the note asks for "mean rubble under the archons down
##    >= 15 %". Rubble-under-archon is not recorded. Replaced by TRANSFORMS,
##    measured 374 -> 994 on a mirror pair, because an archon cannot walk
##    without standing up first.
##
## Every other clause is the note's own, with the committed threshold at
## roughly half the measured margin.

import std/json
import harness
import bc22_fixture

proc sheetWith(pairs: openArray[(string, JsonNode)]): Sheet =
  var o = newJObject()
  for (k, v) in pairs: o[k] = v
  validate(%*{"sheet": o}, "bc22")

type Tally = object
  miners, soldiers, sages, gold, leadMined, dry: int
  labsFinished, towersFinished, mutationsL2, mutationsL3: int
  dodged, chargeLost, furyLost, relocations, lost, repaired: int
  leadSpentTransmuting, transforms, builders: int
  leadOnMap, robotsAlive: int

proc addSeat(t: var Tally, o: GameOutcome22, slot: int) =
  t.miners += o.minersBuilt[slot]
  t.soldiers += o.soldiersBuilt[slot]
  t.sages += o.sagesBuilt[slot]
  t.gold += o.goldTransmuted[slot]
  t.leadMined += o.leadMined[slot]
  t.dry += o.squaresMinedDry[slot]
  t.labsFinished += o.labsFinished[slot]
  t.towersFinished += o.watchtowersFinished[slot]
  t.mutationsL2 += o.mutationsL2[slot]
  t.mutationsL3 += o.mutationsL3[slot]
  t.dodged += o.anomaliesDodged[slot]
  t.chargeLost += o.anomalyLossesCharge[slot]
  t.furyLost += o.anomalyLossesFuryHp[slot]
  t.relocations += o.archonRelocations[slot]
  t.lost += o.robotsLost[slot]
  t.repaired += o.hpRepaired[slot]
  t.leadSpentTransmuting += o.leadSpentTransmuting[slot]
  t.transforms += o.transforms[slot]
  t.builders += o.buildersBuilt[slot]
  t.robotsAlive += o.robotsAlive[slot]

const Maps = ["chalice", "snowflake_redux", "maze"]

proc paired(lo, hi: Sheet): (Tally, Tally) =
  ## Seat 0 plays `lo`, seat 1 plays `hi`, on the same map and seed.
  for mapName in Maps:
    for sa in [0, 1]:
      let (w, o) = playGame(loadMap(mapName), [lo, hi], [ckWololo, ckWololo],
                            0, sa, 2000, 0)
      discard w
      result[0].addSeat(o, 0)
      result[1].addSeat(o, 1)

proc mirrored(s: Sheet): Tally =
  ## Both seats play the same sheet, so the PER-GAME SCALARS — the lead still
  ## on the map at round 2000 — are attributable.
  for mapName in Maps:
    for sa in [0, 1]:
      let (w, o) = playGame(loadMap(mapName), [s, s], [ckWololo, ckWololo], 0,
                            sa, 2000, 0)
      discard w
      result.addSeat(o, 0)
      result.addSeat(o, 1)
      result.leadOnMap += o.leadOnMapEnd

template up(name: string, lo, hi, pct: int) =
  check(name & " (measured " & $lo & " -> " & $hi & ")",
        hi * 100 >= lo * (100 + pct))
template down(name: string, lo, hi, pct: int) =
  check(name & " (measured " & $lo & " -> " & $hi & ")",
        hi * 100 <= lo * (100 - pct))
template upBy(name: string, lo, hi, amount: int) =
  check(name & " (measured " & $lo & " -> " & $hi & ")", hi - lo >= amount)
template downBy(name: string, lo, hi, amount: int) =
  check(name & " (measured " & $lo & " -> " & $hi & ")", lo - hi >= amount)

block:
  let (lo, hi) = paired(sheetWith({"opening": %"miner_eco"}),
                        sheetWith({"opening": %"soldier_rush"}))
  up("opening miner_eco -> soldier_rush: soldiers built up 20 %",
     lo.soldiers, hi.soldiers, 20)
  down("and miners built down 15 %", lo.miners, hi.miners, 15)

block:
  let (lo, hi) = paired(sheetWith({"opening": %"miner_eco"}),
                        sheetWith({"opening": %"sage_spam"}))
  upBy("opening miner_eco -> sage_spam: laboratories finished up 2",
       lo.labsFinished, hi.labsFinished, 2)
  upBy("and sages built up 2", lo.sages, hi.sages, 2)

block:
  let (lo, hi) = paired(sheetWith({"miner_count_curve": %"lean"}),
                        sheetWith({"miner_count_curve": %"heavy"}))
  up("miner_count_curve lean -> heavy: miners built up 50 %",
     lo.miners, hi.miners, 50)
  up("and lead mined up 8 %", lo.leadMined, hi.leadMined, 8)

block:
  ## MIRRORED, because the deciding statistic is a PER-GAME SCALAR.
  let lo = mirrored(sheetWith({"mine_floor": %0}))
  let hi = mirrored(sheetWith({"mine_floor": %3}))
  up("mine_floor 0 -> 3: lead still on the map at round 2000 up 50 %",
     lo.leadOnMap, hi.leadOnMap, 50)
  down("and squares mined dry down 50 %", lo.dry, hi.dry, 50)
  up("and the faction that keeps its map alive ends with more robots",
     lo.robotsAlive, hi.robotsAlive, 20)

block:
  let (lo, hi) = paired(sheetWith({"soldier_sage_ratio": %100}),
                        sheetWith({"soldier_sage_ratio": %0}))
  upBy("soldier_sage_ratio 100 -> 0: sages built up 3", lo.sages, hi.sages, 3)
  down("and soldiers built down 15 %", lo.soldiers, hi.soldiers, 15)
  upBy("and gold transmuted up 40", lo.gold, hi.gold, 40)

block:
  let (lo, hi) = paired(sheetWith({"lab_round": %1500}),
                        sheetWith({"lab_round": %100}))
  upBy("lab_round 1500 -> 100: laboratories finished up 2",
       lo.labsFinished, hi.labsFinished, 2)
  upBy("and sages built up 10 — the gold arrives in time to spend",
       lo.sages, hi.sages, 10)

block:
  ## Run with `lab_round: 150` on BOTH sides, since the knob is only reachable
  ## once a laboratory exists.
  let (lo, hi) = paired(
    sheetWith({"lab_round": %150, "lab_solitude": %40}),
    sheetWith({"lab_round": %150, "lab_solitude": %0}))
  let loRate = (if lo.gold == 0: 0 else: lo.leadSpentTransmuting * 100 div lo.gold)
  let hiRate = (if hi.gold == 0: 0 else: hi.leadSpentTransmuting * 100 div hi.gold)
  check("lab_solitude 40 -> 0: both sides actually transmuted",
    lo.gold > 0 and hi.gold > 0)
  down("and the mean lead spent per gold falls 25 % (in hundredths)",
       loRate, hiRate, 25)
  upBy("and the laboratory transforms at least once more to get away",
       lo.transforms, hi.transforms, 1)

block:
  let (lo, hi) = paired(sheetWith({"gold_use": %"sages"}),
                        sheetWith({"gold_use": %"mutations"}))
  upBy("gold_use sages -> mutations: level-three mutations up 2",
       lo.mutationsL3, hi.mutationsL3, 2)
  downBy("and sages built down 2", lo.sages, hi.sages, 2)

block:
  let (lo, hi) = paired(sheetWith({"watchtower_policy": %"never"}),
                        sheetWith({"watchtower_policy": %"forward"}))
  upBy("watchtower_policy never -> forward: watchtowers finished up 2",
       lo.towersFinished, hi.towersFinished, 2)
  checkEq("and `never` really builds NONE", lo.towersFinished, 0)
  up("and the builder programme grows with it (the substituted statistic)",
     lo.builders, hi.builders, 100)

block:
  let (lo, hi) = paired(sheetWith({"anomaly_play": %"ignore"}),
                        sheetWith({"anomaly_play": %"time_pushes"}))
  upBy("anomaly_play ignore -> time_pushes: anomalies dodged up 2",
       lo.dodged, hi.dodged, 2)
  checkEq("and `ignore` dodges NOTHING, because it never reads the schedule",
    lo.dodged, 0)
  down("droids lost to the CHARGE down 20 %", lo.chargeLost, hi.chargeLost, 20)
  down("and turret health lost to the FURY down 25 %",
       lo.furyLost, hi.furyLost, 25)

block:
  ## MIRRORED, because an archon that walks changes the whole board and the
  ## paired game hides it in the opponent's numbers.
  let lo = mirrored(sheetWith({"archon_relocate": %"never"}))
  let hi = mirrored(sheetWith({"archon_relocate": %"lead"}))
  upBy("archon_relocate never -> lead: relocations up 2",
       lo.relocations, hi.relocations, 2)
  checkEq("and `never` relocates NOT ONCE", lo.relocations, 0)
  up("and transforms up 50 % (the substituted statistic: an archon cannot " &
     "walk without standing up first)", lo.transforms, hi.transforms, 50)

block:
  let (lo, hi) = paired(sheetWith({"retreat_hp": %0}),
                        sheetWith({"retreat_hp": %80}))
  down("retreat_hp 0 -> 80: robots lost down 15 %", lo.lost, hi.lost, 15)
  upBy("and health repaired up 150", lo.repaired, hi.repaired, 150)

finish("test_bc22_knobs")
