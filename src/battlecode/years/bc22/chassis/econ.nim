## `econ.nim` — the build plan and the ONLY place lead or gold is committed.
##
## Behaviour ported from `iliao2345/Battlecode2022` `src/fury_fix_20/Archon.java`
## (AGPL-3.0): the build-rate and urgency model, its own saturation caps
## (`SOLDIER_SATURATION_CAP = 400`, `WATCHTOWER_SATURATION_CAP = 500`) and its
## 20-round miner-employment ring buffer, which is what stops it building miners
## for a mined-out map. BEHAVIOUR, NOT CODE. `NOTICE` names the file.
##
## The three knob sites this file owns:
##
## * `plan()` reads `opening` — the lead split for the first 400 rounds;
## * `minerTarget()` reads `miner_count_curve` — the miner census per archon as
##   a function of the round and the REMEMBERED LIVE LEAD SQUARES;
## * `attackMix()` reads `soldier_sage_ratio` — the percentage of the attack
##   budget, in LEAD-EQUIVALENT, that goes to soldiers rather than to gold for
##   sages, where a sage's lead-equivalent is `20 x the lab's current transmute
##   rate` (2 Pb/Au alone, 11 Pb/Au crowded).
##
## THE ANTI-INERT FLOOR IS UNCONDITIONAL AND LIVES HERE: at every value of every
## knob the faction keeps at least `MinerFloorPerArchon` (3) miners per archon
## and builds a soldier whenever lead allows and the soldier census is under its
## target. `opening: miner_eco` HALVES the soldier target, it never zeroes it;
## `soldier_sage_ratio: 0` still builds a soldier whenever no laboratory exists.

import kit

export kit

const
  SoldierSaturationCap* = 400
  WatchtowerSaturationCap* = 500
    ## `fury_fix_20/Archon.java`'s own caps: past these lead totals another
    ## soldier (or watchtower) buys less than the lead it costs.
  EarlyRounds* = 400

func liveLeadSquares*(w: World, side: Side): int =
  ## The remembered squares that still hold lead. `minerTarget` is a function of
  ## THIS, not of the map's opening inventory, which is what makes `mine_floor`
  ## visible to the build plan.
  for l in side.leadSites:
    let i = w.idx(l)
    if not side.deadSquare[i] and side.knownLead[i] > 0:
      result += 1

func minerTarget*(w: World, side: Side): int =
  ## The miner census the faction wants, TOTAL (not per archon). The floor of
  ## three per archon is unconditional at every value.
  let archons = max(1, side.archons)
  let squares = liveLeadSquares(w, side)
  var perArchon =
    case side.doctrine.minerCountCurve
    of mcLean: min(6, MinerFloorPerArchon + squares div 4)
    of mcSteady: min(12, MinerFloorPerArchon + squares div 2)
    of mcHeavy: min(20, 4 + squares)
  perArchon = max(perArchon, MinerFloorPerArchon)
  if side.doctrine.opening == opMinerEco and w.currentRound <= EarlyRounds:
    perArchon = max(perArchon, min(8, MinerFloorPerArchon + squares div 2))
  ## The employment brake: if barely any miner actually mined over the last
  ## twenty rounds the map is worked out and more miners are lead thrown away.
  if w.currentRound > 60 and side.minerEmploymentRate() * 2 < side.miners:
    perArchon = max(MinerFloorPerArchon, perArchon div 2)
  perArchon * archons

func soldierTarget*(w: World, side: Side): int =
  ## The soldier census the faction wants. NEVER ZERO.
  let archons = max(1, side.archons)
  var target = 2 * archons + w.currentRound div 60
  case side.doctrine.opening
  of opSoldierRush:
    if w.currentRound <= EarlyRounds: target = target * 2 + 4
  of opMinerEco:
    if w.currentRound <= EarlyRounds: target = max(1, target div 2)
  of opSageSpam:
    if w.currentRound <= EarlyRounds: target = max(1, (target * 2) div 3)
  ## The saturation cap: past 400 lead in the bank another soldier is worth
  ## less than the lead, so the census stops growing on income alone.
  if w.teamLead(side.team) > SoldierSaturationCap:
    target += 4
  max(1, target)

func attackMix*(side: Side): int =
  ## The percentage of the attack budget that goes to soldiers. Clamped by the
  ## sheet to 0..100, so no doctrine can express "no attackers": the value only
  ## moves the SPLIT, and the soldier floor below it is unconditional.
  side.doctrine.soldierSageRatio

func effectiveLabRound*(side: Side): int =
  ## `opening: sage_spam` pulls the laboratory forward to at most 150 — the
  ## value is a GOLD PROGRAMME, not a round-1 build order, because sages cost
  ## gold and the faction starts with none.
  if side.doctrine.opening == opSageSpam:
    min(side.doctrine.labRound, 150)
  else:
    side.doctrine.labRound

func sageLeadEquivalent*(w: World, side: Side, rate: int): int =
  ## A sage costs 20 gold; a gold costs `rate` lead. So a sage's lead-equivalent
  ## is `20 * rate` — 40 Pb for a lonely lab, 220 Pb in a crowd, against a
  ## soldier's 75.
  20 * max(2, rate)

func bankForGold*(w: World, side: Side, rate: int): bool =
  ## Should the faction HOLD lead at the transmute price instead of spending it
  ## on another soldier?
  ##
  ## `soldier_sage_ratio` is a SPLIT OF THE ATTACK BUDGET IN LEAD-EQUIVALENT,
  ## so the test is against what the faction has ACTUALLY SPENT, not against
  ## how rich it happens to be: bank only while the realised soldier share is
  ## already at or above the target. At 100 this never fires (the faction never
  ## banks); at 0 it fires from the first soldier onward, and the unconditional
  ## soldier floor below it is what keeps 0 from being inert.
  if side.labsLive == 0: return false
  let ratio = side.doctrine.soldierSageRatio
  if ratio >= 100: return false
  if w.teamLead(side.team) < rate: return false
  let t = ord(side.team)
  let soldierLead = w.stats.soldiersBuilt[t] * RobotSpecs[rtSoldier].buildCostLead
  let goldLead = w.stats.leadSpentTransmuting[t]
  ## Spend on a soldier while the soldier share is still under target.
  soldierLead * 100 >=
    ratio * (soldierLead + goldLead + RobotSpecs[rtSoldier].buildCostLead)

# ---------------------------------------------------------------------------
#  The commitment ledger — two archons cannot promise the same 75 Pb
# ---------------------------------------------------------------------------

proc availableLead*(w: World, side: Side): int =
  max(0, w.teamLead(side.team) - side.committedLead)

proc availableGold*(w: World, side: Side): int =
  max(0, w.teamGold(side.team) - side.committedGold)

proc commit*(side: Side, lead, gold: int) =
  side.committedLead += lead
  side.committedGold += gold

proc canAfford*(w: World, side: Side, kind: RobotType): bool =
  availableLead(w, side) >= RobotSpecs[kind].buildCostLead and
    availableGold(w, side) >= RobotSpecs[kind].buildCostGold

proc reserveFor*(w: World, side: Side, kind: RobotType) =
  side.commit(RobotSpecs[kind].buildCostLead, RobotSpecs[kind].buildCostGold)

proc nextArchonBuild*(w: World, side: Side, rate: int): RobotType =
  ## What an archon should build this turn, or `rtArchon` for "nothing"
  ## (an archon can never be built, so it is the natural sentinel).
  ##
  ## THE ORDER IS THE PLAN: the miner floor first, then a builder when the
  ## laboratory or the watchtower programme wants one, then a sage when gold
  ## allows and the doctrine wants sages, then a soldier, then a miner up to the
  ## curve. An archon SPENDS ITS ACTION rather than banking it.
  let d = side.doctrine
  ## 1. the unconditional miner floor
  let floorMiners = MinerFloorPerArchon * max(1, side.archons)
  if side.miners < floorMiners and canAfford(w, side, rtMiner):
    return rtMiner
  ## 2. a builder, when the lab or the tower programme needs one and none is out
  let wantsLab = w.currentRound >= effectiveLabRound(side) and
    side.labs == 0
  let wantsTower = d.watchtowerPolicy != wpNever and
    side.watchtowers < max(1, side.archons)
  if (wantsLab or wantsTower) and side.builders == 0 and
      not side.builderClaimed and not w.brokenChassis and
      canAfford(w, side, rtBuilder):
    side.builderClaimed = true
    return rtBuilder
  ## 3. a sage, when the doctrine wants gold spent on sages and gold is there
  if d.goldUse == guSages and availableGold(w, side) >= 20 and
      d.soldierSageRatio < 100:
    return rtSage
  ## 4. a soldier, whenever lead allows and the census is under target
  let soldiers = side.soldiers
  if soldiers < soldierTarget(w, side) and canAfford(w, side, rtSoldier):
    ## The gold programme may ask the faction to HOLD lead at the transmute
    ## price instead — but never below the soldier floor of one per archon.
    if soldiers >= max(1, side.archons) and bankForGold(w, side, rate):
      discard
    else:
      return rtSoldier
  ## 5. a miner, up to the curve
  if side.miners < minerTarget(w, side) and canAfford(w, side, rtMiner):
    if bankForGold(w, side, rate) and side.miners >= floorMiners:
      discard
    else:
      return rtMiner
  ## 6. a soldier anyway, if the faction is rich and has nothing else to buy —
  ##    an archon spends its action rather than banking it.
  if availableLead(w, side) > SoldierSaturationCap and
      canAfford(w, side, rtSoldier):
    return rtSoldier
  rtArchon
