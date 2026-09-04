## The Battlecode 2024 "Breadwars" knob table: TEN knobs, and NO `chassis` key.
##
## D1 (sibling review finding, 2026-09-03): the chassis is not an
## LLM-selectable knob. The chassis a seat drives comes from `PLAYER_SCRIPTED`
## (scripted seats) or is the fixed champion chassis (LLM seats). A submitted
## `chassis` is therefore recorded as an UNKNOWN FIELD and never honoured, and
## `tests/test_bc24_sheet.nim` asserts exactly that — the test fails if anyone
## re-adds the knob.
##
## Unknown key, wrong type or out-of-range value takes THAT FIELD'S DEFAULT and
## the repair is recorded. A sheet can never be rejected, so a cog can never
## forfeit a match by answering badly — only by answering weakly.
##
## THE LEARNINGS PIN, stated as a rule every knob is held against: NO SETTING
## OF ANY KNOB MAY PRODUCE AN INERT OR SELF-STARVING FLOCK. The strategy
## surface lives inside ONE competent chassis. Independently of every knob the
## chassis always spawns every duck it can, always walks crumbs off the floor,
## always keeps >= 3 builders and >= 18 attackers in the census, always defends
## a flag it senses under threat (out of a reserved 100-crumb floor even at
## `trap_budget: 0`), always answers a sensed enemy in its own territory, and
## always commits to an enemy flag by `flag_rush_round`, whose range CANNOT
## EXPRESS "never". `tests/test_bc24_knobs.nim` proves each knob has teeth and
## `tests/test_bc24_survival.nim` proves the floor holds.

import std/[json, strutils, tables]
import ../../sheet_common

export sheet_common

type
  Split24* = enum
    ## `roles.nim census()` — how the 50 duck sequence-slots are cut.
    spAttack = "attack"
    spHeal = "heal"
    spBuild = "build"
    spBalanced = "balanced"

  TrapPlacement* = enum
    ## `builder.nim trapTargets()`.
    tpChoke = "choke"
    tpFlagRing = "flag_ring"
    tpSpawnRing = "spawn_ring"

  TrapMix* = enum
    ## `builder.nim trapKind()`.
    tmStun = "stun"
    tmExplosive = "explosive"
    tmMixed = "mixed"

  HealPriority* = enum
    ## `micro.nim healTarget()`.
    hpWoundedFirst = "wounded_first"
    hpAttackersFirst = "attackers_first"
    hpCarrierFirst = "carrier_first"

  WaterDigPolicy* = enum
    ## `builder.nim terraform()`.
    wdNone = "none"
    wdChokeDig = "choke_dig"
    wdMoat = "moat"
    wdFillPaths = "fill_paths"

  UpgradeChoice* = enum
    ## The three entries `upgrade_order` may hold, in the doctrine's spelling.
    ucAttack = "attack"
    ucHeal = "heal"
    ucCapture = "capture"

  Doctrine24* = object
    specialisationSplit*: Split24
    flagRushRound*: int
    trapBudget*: int
    trapPlacement*: TrapPlacement
    trapMix*: TrapMix
    healPriority*: HealPriority
    waterDigPolicy*: WaterDigPolicy
    upgradeOrder*: array[3, UpgradeChoice]
    retreatHp*: int
    flagCarryEscort*: int

const
  KnownKeys24* = [
    "specialisation_split", "flag_rush_round", "trap_budget",
    "trap_placement", "trap_mix", "heal_priority", "water_dig_policy",
    "upgrade_order", "retreat_hp", "flag_carry_escort"
  ]
    ## Exactly ten. `chassis` is deliberately NOT here (D1).

  DefaultUpgradeOrder* = [ucAttack, ucHeal, ucCapture]

proc defaultDoctrine24*(): Doctrine24 =
  Doctrine24(
    specialisationSplit: spBalanced,
    flagRushRound: 450,
    trapBudget: 30,
    trapPlacement: tpFlagRing,
    trapMix: tmMixed,
    healPriority: hpWoundedFirst,
    waterDigPolicy: wdChokeDig,
    upgradeOrder: DefaultUpgradeOrder,
    retreatHp: 400,
    flagCarryEscort: 2)

proc applyKnobs24*(seen: Table[string, JsonNode],
                   defaultsApplied: var seq[string]): Doctrine24 =
  result = defaultDoctrine24()

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

  enumKnob("specialisation_split", result.specialisationSplit, Split24)
  intKnob("flag_rush_round", result.flagRushRound, 201, 1200)
  intKnob("trap_budget", result.trapBudget, 0, 60)
  enumKnob("trap_placement", result.trapPlacement, TrapPlacement)
  enumKnob("trap_mix", result.trapMix, TrapMix)
  enumKnob("heal_priority", result.healPriority, HealPriority)
  enumKnob("water_dig_policy", result.waterDigPolicy, WaterDigPolicy)
  intKnob("retreat_hp", result.retreatHp, 100, 900)
  intKnob("flag_carry_escort", result.flagCarryEscort, 0, 6)

  ## `upgrade_order` is the one knob whose value is a structure. A malformed,
  ## short, long, duplicated or unknown-valued array takes the WHOLE default
  ## array and is recorded ONCE — never half-applied.
  if "upgrade_order" in seen:
    let node = seen["upgrade_order"]
    var parsed: array[3, UpgradeChoice]
    var ok = node.kind == JArray and node.len == 3
    if ok:
      for i in 0 .. 2:
        if node[i].kind != JString:
          ok = false
          break
        let text = normalizeKey(node[i].getStr())
        var found = false
        for value in UpgradeChoice:
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
      result.upgradeOrder = parsed
    else:
      repair("upgrade_order")

proc toJson24*(d: Doctrine24): JsonNode =
  var order = newJArray()
  for u in d.upgradeOrder: order.add(%($u))
  %*{
    "specialisation_split": $d.specialisationSplit,
    "flag_rush_round": d.flagRushRound,
    "trap_budget": d.trapBudget,
    "trap_placement": $d.trapPlacement,
    "trap_mix": $d.trapMix,
    "heal_priority": $d.healPriority,
    "water_dig_policy": $d.waterDigPolicy,
    "upgrade_order": order,
    "retreat_hp": d.retreatHp,
    "flag_carry_escort": d.flagCarryEscort
  }

# ---------------------------------------------------------------------------
#  Derived quantities the chassis reads. Kept here so the knob and the
#  behaviour it drives are one file apart at most.
# ---------------------------------------------------------------------------

proc census*(d: Doctrine24): tuple[builders, healers, attackers: int] =
  ## How the 50 sequence slots are cut. EVERY value keeps >= 3 builders,
  ## >= 10 healers and >= 18 attackers: no split can produce a flock that
  ## cannot dig, cannot mend or cannot fight. `balanced` generalises Gone
  ## Sharkin's shipped 3 / 20 / 27.
  case d.specialisationSplit
  of spBalanced: (6, 16, 28)
  of spAttack: (4, 10, 36)
  of spHeal: (5, 24, 21)
  of spBuild: (10, 14, 26)

const DefenceReserve* = 100
  ## The crumb floor the builders never spend below after round 200, kept for
  ## a stun trap the moment an own flag is sensed under threat. Independent of
  ## `trap_budget`, which is what stops `trap_budget: 0` producing an
  ## undefended flag (D2).

proc bc24SheetSchema*(): JsonNode =
  ## The knob surface as the doctrine prompt carries it. Generated from THIS
  ## table rather than re-typed, so a knob cannot exist in the sim and be
  ## missing from the brief.
  let d = defaultDoctrine24()
  var split = newJArray()
  for v in Split24: split.add(%($v))
  var placement = newJArray()
  for v in TrapPlacement: placement.add(%($v))
  var mix = newJArray()
  for v in TrapMix: mix.add(%($v))
  var heal = newJArray()
  for v in HealPriority: heal.add(%($v))
  var water = newJArray()
  for v in WaterDigPolicy: water.add(%($v))
  var upgrades = newJArray()
  for v in UpgradeChoice: upgrades.add(%($v))
  var defaultOrder = newJArray()
  for v in d.upgradeOrder: defaultOrder.add(%($v))
  %*{
    "specialisation_split": {"values": split,
                             "default": $d.specialisationSplit},
    "flag_rush_round": {"range": [201, 1200], "default": d.flagRushRound},
    "trap_budget": {"range": [0, 60], "default": d.trapBudget,
                    "note": "percent of crumb income spent on traps"},
    "trap_placement": {"values": placement, "default": $d.trapPlacement},
    "trap_mix": {"values": mix, "default": $d.trapMix},
    "heal_priority": {"values": heal, "default": $d.healPriority},
    "water_dig_policy": {"values": water, "default": $d.waterDigPolicy},
    "upgrade_order": {"values": upgrades, "length": 3, "distinct": true,
                      "default": defaultOrder},
    "retreat_hp": {"range": [100, 900], "default": d.retreatHp},
    "flag_carry_escort": {"range": [0, 6], "default": d.flagCarryEscort}
  }

proc plainWords24*(d: Doctrine24): seq[string] =
  ## The endcard / `#bc24-doctrines` readout: the sheet in words a spectator
  ## can read without knowing the schema.
  case d.specialisationSplit
  of spAttack: result.add("all-in on attack")
  of spHeal: result.add("leans on healers")
  of spBuild: result.add("leans on builders")
  of spBalanced: result.add("a balanced flock")
  result.add("rushes the flags at round " & $d.flagRushRound)
  if d.trapBudget == 0:
    result.add("builds no traps beyond the defensive reserve")
  else:
    result.add("spends " & $d.trapBudget & " % of its crumbs on traps")
  case d.trapPlacement
  of tpChoke: result.add("traps at the chokes")
  of tpFlagRing: result.add("traps ringing its own flags")
  of tpSpawnRing: result.add("traps around its spawn zones")
  case d.trapMix
  of tmStun: result.add("stun traps only")
  of tmExplosive: result.add("explosive traps only")
  of tmMixed: result.add("stun and explosive traps in turn")
  case d.healPriority
  of hpWoundedFirst: result.add("heals the most wounded")
  of hpAttackersFirst: result.add("heals its veterans first")
  of hpCarrierFirst: result.add("heals the flag carrier first")
  case d.waterDigPolicy
  of wdNone: result.add("never digs or fills")
  of wdChokeDig: result.add("digs water across the approaches")
  of wdMoat: result.add("moats its own flags")
  of wdFillPaths: result.add("fills a path through the water")
  var order: seq[string]
  for u in d.upgradeOrder: order.add($u)
  result.add("takes " & order.join(", then ") & " upgrades")
  result.add("trades down to " & $d.retreatHp & " HP")
  if d.flagCarryEscort == 0:
    result.add("sends a carrier home alone")
  else:
    result.add("sends " & $d.flagCarryEscort & " escorts with a carrier")
