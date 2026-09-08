## The Battlecode 2025 "Chromatic Conflict" knob table: TEN knobs, and NO
## `chassis` key.
##
## D1 (sibling review finding, 2026-09-03): the chassis is not an
## LLM-selectable knob. The chassis a seat drives comes from `PLAYER_SCRIPTED`
## (scripted seats) or is the fixed champion chassis (LLM seats). A submitted
## `chassis` is therefore recorded as an UNKNOWN FIELD and never honoured, and
## `tests/test_bc25_sheet.nim` asserts exactly that — the test fails if anyone
## re-adds the knob.
##
## Unknown key, wrong type or out-of-range value takes THAT FIELD'S DEFAULT and
## the repair is recorded. A sheet can never be rejected, so a cog can never
## forfeit a match by answering badly — only by answering weakly.
##
## THE LEARNINGS PIN, stated as a rule every knob is held against: NO SETTING
## OF ANY KNOB MAY PRODUCE AN INERT OR SELF-STARVING CLAN. The strategy surface
## lives inside ONE competent chassis. Independently of every knob the chassis
## always builds robots whenever a tower can pay for one; paints the tile under
## a soldier standing on bare or enemy ground; sends a robot below
## `paint_reserve_floor` to the nearest friendly paint tower or mopper; claims
## the nearest unclaimed ruin inside `ruin_claim_radius` and paints its
## pattern; upgrades a tower when the chip balance is above twice the next
## level's cost; keeps at least 2 moppers and 1 splasher in the census once the
## chip income allows it; and answers an enemy robot sensed inside its own
## paint. `tests/test_bc25_knobs.nim` proves each knob has teeth and
## `tests/test_bc25_survival.nim` proves the floor holds.
##
## THE CHASSIS FILE LAYOUT this table's `what it changes` column points at:
## `chassis/kit.nim` (shared memory, navigation, `needsRefill`),
## `chassis/econ.nim` (`plan`, `nextBuild`, `srpBudget`, `towerKindFor`,
## `upgradePick`), `chassis/tower.nim`, `chassis/soldier.nim`,
## `chassis/splasher.nim`, `chassis/mopper.nim`, `chassis/siege.nim`,
## `chassis/comms.nim`, `chassis/spaark.nim` (the turn dispatcher),
## `chassis/scaffold25.nim` and `chassis/scenario25.nim`. All eleven exist;
## `NOTICE` and `docs/RULES-BC25.md` name the same paths.

import std/[json, strutils, tables]
import ../../sheet_common
import units

export sheet_common

type
  Opening25* = enum
    ## `econ.nim plan()` — the chip/paint split for the first 400 rounds.
    opPaintEco = "paint_eco"
    opTowerRush = "tower_rush"
    opBalanced = "balanced"

  ChokePolicy* = enum
    ## `siege.nim chokePlan()`.
    cpNever = "never"
    cpLate = "late"
    cpEarly = "early"

  SplashTargets* = enum
    ## `splasher.nim aim()`.
    stTowers = "towers"
    stTerritory = "territory"
    stMixed = "mixed"

  UpgradePolicy* = enum
    ## `econ.nim upgradePick()`.
    upNever = "never"
    upPaintFirst = "paint_first"
    upMoneyFirst = "money_first"
    upDefenseFirst = "defense_first"

  UnitMix* = object
    soldier*, mopper*, splasher*: int

  Doctrine25* = object
    opening*: Opening25
    unitMix*: UnitMix
    srpPriority*: int
    towerTypeOrder*: array[3, TowerKind]
    ruinClaimRadius*: int
    defenseTowerChokes*: ChokePolicy
    paintReserveFloor*: int
    mopEnemyPaint*: int
    splashTargets*: SplashTargets
    upgradePolicy*: UpgradePolicy

const
  KnownKeys25* = [
    "opening", "unit_mix", "srp_priority", "tower_type_order",
    "ruin_claim_radius", "defense_tower_chokes", "paint_reserve_floor",
    "mop_enemy_paint", "splash_targets", "upgrade_policy"
  ]
    ## Exactly ten. `chassis` is deliberately NOT here (D1).

  DefaultTowerOrder* = [tkMoney, tkPaint, tkDefense]
  DefaultUnitMix* = UnitMix(soldier: 60, mopper: 25, splasher: 15)

  MinSoldierShare* = 30
  MinMopperShare* = 10
  MinSplasherShare* = 10
    ## THE ANTI-INERT FLOOR. No mix can produce a clan with no moppers (it
    ## could never reclaim ground) or no splashers (it could never fight over
    ## painted ground).

proc defaultDoctrine25*(): Doctrine25 =
  Doctrine25(
    opening: opBalanced,
    unitMix: DefaultUnitMix,
    srpPriority: 35,
    towerTypeOrder: DefaultTowerOrder,
    ruinClaimRadius: 10,
    defenseTowerChokes: cpLate,
    paintReserveFloor: 30,
    mopEnemyPaint: 40,
    splashTargets: stMixed,
    upgradePolicy: upMoneyFirst)

proc normalisedMix*(mix: UnitMix): UnitMix =
  ## Clamp each share up to its floor, then renormalise to sum 100 with the
  ## remainder going to soldiers — so the three always sum to exactly 100 and
  ## no rounding can strand a share at zero.
  var s = max(mix.soldier, MinSoldierShare)
  var m = max(mix.mopper, MinMopperShare)
  var p = max(mix.splasher, MinSplasherShare)
  let total = s + m + p
  m = m * 100 div total
  p = p * 100 div total
  m = max(m, MinMopperShare)
  p = max(p, MinSplasherShare)
  s = 100 - m - p
  if s < MinSoldierShare:
    ## Only reachable from an extreme mopper/splasher-heavy sheet; the soldier
    ## floor wins and the overflow comes off whichever of the other two is
    ## larger.
    let deficit = MinSoldierShare - s
    if m >= p: m -= deficit else: p -= deficit
    s = MinSoldierShare
  UnitMix(soldier: s, mopper: m, splasher: p)

proc applyKnobs25*(seen: Table[string, JsonNode],
                   defaultsApplied: var seq[string]): Doctrine25 =
  result = defaultDoctrine25()

  template repair(name: string) =
    defaultsApplied.add(name)

  template enumKnob(name: string, field: untyped, T: typedesc) =
    if name in seen:
      if seen[name].kind == JString:
        let text = normalizeKey(seen[name].getStr())
        var found = false
        for value in T:
          if normalizeKey($value) == text:
            field = value
            found = true
        if not found: repair(name)
      else:
        repair(name)

  template intKnob(name: string, field: untyped, lo, hi: int) =
    if name in seen:
      let n = readNumber(seen[name])
      if n.ok and n.value >= float(lo) and n.value <= float(hi):
        field = int(n.value)
      else:
        repair(name)

  enumKnob("opening", result.opening, Opening25)
  intKnob("srp_priority", result.srpPriority, 0, 100)
  intKnob("ruin_claim_radius", result.ruinClaimRadius, 4, 20)
  enumKnob("defense_tower_chokes", result.defenseTowerChokes, ChokePolicy)
  intKnob("paint_reserve_floor", result.paintReserveFloor, 10, 70)
  intKnob("mop_enemy_paint", result.mopEnemyPaint, 0, 100)
  enumKnob("splash_targets", result.splashTargets, SplashTargets)
  enumKnob("upgrade_policy", result.upgradePolicy, UpgradePolicy)

  ## `unit_mix` is an OBJECT of exactly three integer keys. A missing key, a
  ## negative value, a non-integer or a non-object takes the WHOLE default
  ## object and is recorded ONCE — never half-applied.
  if "unit_mix" in seen:
    let node = seen["unit_mix"]
    var parsed = UnitMix()
    var ok = node.kind == JObject and node.len == 3
    if ok:
      for key in ["soldier", "mopper", "splasher"]:
        if not node.hasKey(key):
          ok = false
          break
        let n = readNumber(node[key])
        if not n.ok or n.value < 0.0 or n.value > 100.0:
          ok = false
          break
        case key
        of "soldier": parsed.soldier = int(n.value)
        of "mopper": parsed.mopper = int(n.value)
        else: parsed.splasher = int(n.value)
    if ok and parsed.soldier + parsed.mopper + parsed.splasher <= 0:
      ok = false
    if ok:
      result.unitMix = parsed
    else:
      repair("unit_mix")

  ## `tower_type_order` is an array of exactly THREE DISTINCT strings. A
  ## malformed, short, long, duplicated or unknown-valued array takes the
  ## WHOLE default array and is recorded ONCE.
  if "tower_type_order" in seen:
    let node = seen["tower_type_order"]
    var parsed: array[3, TowerKind]
    var ok = node.kind == JArray and node.len == 3
    if ok:
      for i in 0 .. 2:
        if node[i].kind != JString:
          ok = false
          break
        let text = normalizeKey(node[i].getStr())
        var found = false
        for value in TowerKind:
          if normalizeKey($value) == text:
            parsed[i] = value
            found = true
        if not found:
          ok = false
          break
    if ok:
      for i in 0 .. 2:
        for j in i + 1 .. 2:
          if parsed[i] == parsed[j]: ok = false
    if ok:
      result.towerTypeOrder = parsed
    else:
      repair("tower_type_order")

proc toJson25*(d: Doctrine25): JsonNode =
  var order = newJArray()
  for k in d.towerTypeOrder: order.add(%($k))
  %*{
    "opening": $d.opening,
    "unit_mix": {"soldier": d.unitMix.soldier, "mopper": d.unitMix.mopper,
                 "splasher": d.unitMix.splasher},
    "srp_priority": d.srpPriority,
    "tower_type_order": order,
    "ruin_claim_radius": d.ruinClaimRadius,
    "defense_tower_chokes": $d.defenseTowerChokes,
    "paint_reserve_floor": d.paintReserveFloor,
    "mop_enemy_paint": d.mopEnemyPaint,
    "splash_targets": $d.splashTargets,
    "upgrade_policy": $d.upgradePolicy
  }

proc bc25SheetSchema*(): JsonNode =
  ## The knob surface as the doctrine prompt carries it. Generated from THIS
  ## table rather than re-typed, so a knob cannot exist in the sim and be
  ## missing from the brief.
  let d = defaultDoctrine25()
  var openings = newJArray()
  for v in Opening25: openings.add(%($v))
  var chokes = newJArray()
  for v in ChokePolicy: chokes.add(%($v))
  var splash = newJArray()
  for v in SplashTargets: splash.add(%($v))
  var upgrades = newJArray()
  for v in UpgradePolicy: upgrades.add(%($v))
  var towers = newJArray()
  for v in TowerKind: towers.add(%($v))
  var defaultOrder = newJArray()
  for v in d.towerTypeOrder: defaultOrder.add(%($v))
  %*{
    "opening": {"values": openings, "default": $d.opening},
    "unit_mix": {"keys": ["soldier", "mopper", "splasher"],
                 "range": [0, 100],
                 "clamps": {"soldier": MinSoldierShare,
                            "mopper": MinMopperShare,
                            "splasher": MinSplasherShare},
                 "note": "normalised to sum 100 after clamping",
                 "default": {"soldier": d.unitMix.soldier,
                             "mopper": d.unitMix.mopper,
                             "splasher": d.unitMix.splasher}},
    "srp_priority": {"range": [0, 100], "default": d.srpPriority,
                     "note": "percent of chip income reserved for resource " &
                             "patterns"},
    "tower_type_order": {"values": towers, "length": 3, "distinct": true,
                         "default": defaultOrder},
    "ruin_claim_radius": {"range": [4, 20], "default": d.ruinClaimRadius},
    "defense_tower_chokes": {"values": chokes,
                             "default": $d.defenseTowerChokes},
    "paint_reserve_floor": {"range": [10, 70],
                            "default": d.paintReserveFloor,
                            "note": "percent of a robot's paint capacity"},
    "mop_enemy_paint": {"range": [0, 100], "default": d.mopEnemyPaint},
    "splash_targets": {"values": splash, "default": $d.splashTargets},
    "upgrade_policy": {"values": upgrades, "default": $d.upgradePolicy}
  }

proc plainWords25*(d: Doctrine25): seq[string] =
  ## The endcard / `#bc25-doctrines` readout: the sheet in words a spectator
  ## can read without knowing the schema.
  case d.opening
  of opPaintEco: result.add("opens on paint economy")
  of opTowerRush: result.add("rushes towers")
  of opBalanced: result.add("opens balanced")
  let mix = normalisedMix(d.unitMix)
  result.add("builds " & $mix.soldier & " % soldiers, " & $mix.mopper &
    " % moppers, " & $mix.splasher & " % splashers")
  if d.srpPriority == 0:
    result.add("never pays for a resource pattern")
  else:
    result.add("banks " & $d.srpPriority &
      " % of its chips for resource patterns")
  var order: seq[string]
  for k in d.towerTypeOrder: order.add($k)
  result.add("builds " & order.join(", then ") & " towers")
  result.add("claims ruins within " & $d.ruinClaimRadius & " tiles")
  case d.defenseTowerChokes
  of cpNever: result.add("builds no defense towers")
  of cpLate: result.add("builds defense towers at the chokes from round 900")
  of cpEarly: result.add("builds defense towers at the chokes from round 200")
  result.add("refills at " & $d.paintReserveFloor & " % paint")
  if d.mopEnemyPaint == 0:
    result.add("moppers strip robots rather than tiles")
  else:
    result.add("moppers spend " & $d.mopEnemyPaint &
      " % of their turns erasing enemy paint")
  case d.splashTargets
  of stTowers: result.add("splashers aim at towers")
  of stTerritory: result.add("splashers aim at territory")
  of stMixed: result.add("splashers aim at whichever pays")
  case d.upgradePolicy
  of upNever: result.add("never upgrades — spreads wide instead")
  of upPaintFirst: result.add("upgrades paint towers first")
  of upMoneyFirst: result.add("upgrades money towers first")
  of upDefenseFirst: result.add("upgrades defense towers first")
