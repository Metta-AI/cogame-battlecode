## The Battlecode 2023 "Tempest" knob table: TWELVE knobs, and NO `chassis`
## key.
##
## D1 (sibling review finding, 2026-09-03): the chassis is not an
## LLM-selectable knob. The chassis a seat drives comes from `PLAYER_SCRIPTED`
## (scripted seats) or is the fixed champion chassis (LLM seats). A submitted
## `chassis` is therefore recorded as an UNKNOWN FIELD and never honoured, and
## `tests/test_bc23_sheet.nim` asserts exactly that — the test fails if anyone
## re-adds the knob.
##
## Unknown key, wrong type or out-of-range value takes THAT FIELD'S DEFAULT
## and the repair is recorded — except the four INTEGER knobs, which CLAMP to
## their range rather than defaulting, so "as much as possible" still means
## something. A sheet can never be rejected, so a cog can never forfeit a
## match by answering badly — only by answering weakly.
##
## THE LEARNINGS PIN, stated as a rule every knob is held against: NO SETTING
## OF ANY KNOB, AND NO COMBINATION OF SETTINGS, MAY PRODUCE AN INERT OR
## SELF-STARVING FACTION. The strategy surface lives inside ONE competent
## chassis. Independently of every knob the chassis always: keeps at least
## THREE CARRIERS PER HEADQUARTERS mining and DEPOSITING; builds a launcher
## whenever mana allows and the launcher census is below its target; spends a
## headquarters' spare actions rather than banking them (a headquarters may
## act five times a turn); answers an enemy launcher sensed within r² ≤ 16 of
## one of its own headquarters; steps off a current that would carry a loaded
## carrier away from home; and, from `anchor_round` onward, keeps at least one
## anchor in flight whenever `anchor_budget > 0`.
## `tests/test_bc23_knobs.nim` proves each knob has teeth and
## `tests/test_bc23_survival.nim` proves the floor holds, WITH A NEGATIVE
## CONTROL THAT MUST FAIL (`-d:bc23BrokenChassis`).
##
## THE CHASSIS FILE LAYOUT this table's `what it changes` column points at:
## `chassis/kit.nim` (shared memory, the symmetry guess, navigation and the
## `DecisionOps` charging), `chassis/econ.nim` (`plan`, `nextBuild`,
## `budget`), `chassis/hq.nim`, `chassis/carrier.nim` (`wellTarget`,
## `throwPlan`), `chassis/launcher.nim`, `chassis/micro.nim` (`commit`,
## `retreat`), `chassis/anchors.nim` (`schedule`, `pick`),
## `chassis/elixir.nim` (`program`, `sink`), `chassis/amplifier.nim`,
## `chassis/comms.nim`, `chassis/lemonade.nim` (the turn dispatcher),
## `chassis/scaffold23.nim` and `chassis/scenario23.nim`. All THIRTEEN exist;
## `NOTICE` and `docs/RULES-BC23.md` name the same paths.

import std/[json, tables]
import ../../sheet_common
import units

export sheet_common

type
  Opening23* = enum
    ## `econ.nim plan()` — the resource split for the first 400 rounds.
    opLauncherRush = "launcher_rush"
    opCarrierEco = "carrier_eco"
    opBalanced = "balanced"

  WellPriority* = enum
    ## `carrier.nim wellTarget()`. THE IDEA'S CANDIDATE VALUE `elixir` IS
    ## DELIBERATELY ABSENT: no official map contains an elixir well at round 0
    ## (measured across all 103), elixir exists only by transforming a well,
    ## and that transformation is exactly what `elixir_tech` governs — a third
    ## value here would be a second, conflicting control of one decision.
    wpAdamantium = "adamantium"
    wpMana = "mana"
    wpBalanced = "balanced"

  ElixirTech* = enum
    ## `elixir.nim program()`.
    etNever = "never"
    etMid = "mid"
    etEarly = "early"

  ElixirSpend* = enum
    ## `elixir.nim sink()`.
    esAcceleratingAnchors = "accelerating_anchors"
    esBoosters = "boosters"
    esDestabilizers = "destabilizers"

  IslandPriority* = enum
    ## `anchors.nim pick()`.
    ipNearest = "nearest"
    ipContested = "contested"
    ipSafe = "safe"

  AmplifierUse* = enum
    ## `amplifier.nim plan()`.
    auNever = "never"
    auOne = "one"
    auEscort = "escort"

  DestabilizerUse* = enum
    ## `micro.nim commit()` — where the faction's STRIKE GROUP goes.
    duHold = "hold"
    duDefend = "defend"
    duSiege = "siege"

  RetreatPolicy* = enum
    ## `micro.nim retreat()` — the year's signature knob.
    rpNever = "never"
    rpRegroup = "regroup"
    rpHome = "home"

  Doctrine23* = object
    opening*: Opening23
    launcherRatio*: int
    wellPriority*: WellPriority
    elixirTech*: ElixirTech
    elixirSpend*: ElixirSpend
    anchorRound*: int
    anchorBudget*: int
    islandPriority*: IslandPriority
    amplifierUse*: AmplifierUse
    destabilizerUse*: DestabilizerUse
    retreatOnLauncherLoss*: RetreatPolicy
    carrierThrow*: int

const
  KnownKeys23* = [
    "opening", "launcher_ratio", "well_priority", "elixir_tech",
    "elixir_spend", "anchor_round", "anchor_budget", "island_priority",
    "amplifier_use", "destabilizer_use", "retreat_on_launcher_loss",
    "carrier_throw"
  ]
    ## Exactly twelve. `chassis` is deliberately NOT here (D1).

  LauncherRatioLo* = 20
  LauncherRatioHi* = 80
    ## THE ANTI-INERT FLOOR on the build stream. No doctrine can express "no
    ## launchers" (20 % of a real build stream is still a fighting force) or
    ## "only launchers" (the carrier floor is unconditional).
  AnchorRoundLo* = 1
  AnchorRoundHi* = 1800
  AnchorBudgetLo* = 0
  AnchorBudgetHi* = 100
  CarrierThrowLo* = 0
  CarrierThrowHi* = 100

  CarrierFloorPerHq* = 3
    ## The unconditional minimum, at EVERY knob setting.

proc defaultDoctrine23*(): Doctrine23 =
  Doctrine23(
    opening: opBalanced,
    launcherRatio: 45,
    wellPriority: wpBalanced,
    elixirTech: etMid,
    elixirSpend: esAcceleratingAnchors,
    anchorRound: 400,
    anchorBudget: 35,
    islandPriority: ipNearest,
    amplifierUse: auOne,
    destabilizerUse: duDefend,
    retreatOnLauncherLoss: rpRegroup,
    carrierThrow: 25)

proc applyKnobs23*(seen: Table[string, JsonNode],
                   defaultsApplied: var seq[string]): Doctrine23 =
  result = defaultDoctrine23()

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

  template clampedIntKnob(name: string, field: untyped, lo, hi: int) =
    ## AN INTEGER KNOB IS CLAMPED, NEVER DEFAULTED, so "as much as possible"
    ## still means something. A NON-INTEGER takes the default.
    if name in seen:
      let n = readNumber(seen[name])
      if n.ok:
        let v = int(n.value)
        if v < lo or v > hi:
          field = max(lo, min(hi, v))
          repair(name)
        else:
          field = v
      else:
        repair(name)

  enumKnob("opening", result.opening, Opening23)
  clampedIntKnob("launcher_ratio", result.launcherRatio,
                 LauncherRatioLo, LauncherRatioHi)
  enumKnob("well_priority", result.wellPriority, WellPriority)
  enumKnob("elixir_tech", result.elixirTech, ElixirTech)
  enumKnob("elixir_spend", result.elixirSpend, ElixirSpend)
  clampedIntKnob("anchor_round", result.anchorRound,
                 AnchorRoundLo, AnchorRoundHi)
  clampedIntKnob("anchor_budget", result.anchorBudget,
                 AnchorBudgetLo, AnchorBudgetHi)
  enumKnob("island_priority", result.islandPriority, IslandPriority)
  enumKnob("amplifier_use", result.amplifierUse, AmplifierUse)
  enumKnob("destabilizer_use", result.destabilizerUse, DestabilizerUse)
  enumKnob("retreat_on_launcher_loss", result.retreatOnLauncherLoss,
           RetreatPolicy)
  clampedIntKnob("carrier_throw", result.carrierThrow,
                 CarrierThrowLo, CarrierThrowHi)

proc toJson23*(d: Doctrine23): JsonNode =
  %*{
    "opening": $d.opening,
    "launcher_ratio": d.launcherRatio,
    "well_priority": $d.wellPriority,
    "elixir_tech": $d.elixirTech,
    "elixir_spend": $d.elixirSpend,
    "anchor_round": d.anchorRound,
    "anchor_budget": d.anchorBudget,
    "island_priority": $d.islandPriority,
    "amplifier_use": $d.amplifierUse,
    "destabilizer_use": $d.destabilizerUse,
    "retreat_on_launcher_loss": $d.retreatOnLauncherLoss,
    "carrier_throw": d.carrierThrow
  }

proc bc23SheetSchema*(): JsonNode =
  ## The knob surface as the doctrine prompt carries it. Generated from THIS
  ## table rather than re-typed, so a knob cannot exist in the sim and be
  ## missing from the brief.
  let d = defaultDoctrine23()
  var openings = newJArray()
  for v in Opening23: openings.add(%($v))
  var wells = newJArray()
  for v in WellPriority: wells.add(%($v))
  var techs = newJArray()
  for v in ElixirTech: techs.add(%($v))
  var spends = newJArray()
  for v in ElixirSpend: spends.add(%($v))
  var islands = newJArray()
  for v in IslandPriority: islands.add(%($v))
  var amps = newJArray()
  for v in AmplifierUse: amps.add(%($v))
  var destab = newJArray()
  for v in DestabilizerUse: destab.add(%($v))
  var retreats = newJArray()
  for v in RetreatPolicy: retreats.add(%($v))
  %*{
    "opening": {"values": openings, "default": $d.opening},
    "launcher_ratio": {"range": [LauncherRatioLo, LauncherRatioHi],
                       "default": d.launcherRatio,
                       "note": "percent of build decisions that resolve to " &
                               "a launcher once the carrier floor is met; " &
                               "clamped, never zeroed"},
    "well_priority": {"values": wells, "default": $d.wellPriority},
    "elixir_tech": {"values": techs, "default": $d.elixirTech,
                    "note": "when to pour 600kg of the OPPOSITE resource " &
                            "into a well to turn it into elixir"},
    "elixir_spend": {"values": spends, "default": $d.elixirSpend},
    "anchor_round": {"range": [AnchorRoundLo, AnchorRoundHi],
                     "default": d.anchorRound},
    "anchor_budget": {"range": [AnchorBudgetLo, AnchorBudgetHi],
                      "default": d.anchorBudget,
                      "note": "percent of income reserved for anchors and " &
                              "the carriers that ferry them"},
    "island_priority": {"values": islands, "default": $d.islandPriority},
    "amplifier_use": {"values": amps, "default": $d.amplifierUse},
    "destabilizer_use": {"values": destab, "default": $d.destabilizerUse,
                         "note": "where the strike group lives"},
    "retreat_on_launcher_loss": {"values": retreats,
                                 "default": $d.retreatOnLauncherLoss},
    "carrier_throw": {"range": [CarrierThrowLo, CarrierThrowHi],
                      "default": d.carrierThrow,
                      "note": "a lethal throw inside r2<=9 is ALWAYS taken, " &
                              "at every setting"}
  }

proc plainWords23*(d: Doctrine23): seq[string] =
  ## The endcard / `#bc23-doctrines` readout: the sheet in words a spectator
  ## can read without knowing the schema.
  case d.opening
  of opLauncherRush: result.add("rushes launchers")
  of opCarrierEco: result.add("opens on carrier economy")
  of opBalanced: result.add("opens balanced")
  result.add($d.launcherRatio & " % of its builds are launchers")
  case d.wellPriority
  of wpAdamantium: result.add("mines adamantium first")
  of wpMana: result.add("mines mana first")
  of wpBalanced: result.add("mines whichever it is short of")
  case d.elixirTech
  of etNever: result.add("no elixir programme, so its sink never opens")
  of etMid: result.add("converts a well to elixir from round 500")
  of etEarly: result.add("converts a well to elixir from round 200")
  if d.elixirTech != etNever:
    case d.elixirSpend
    of esAcceleratingAnchors: result.add("spends elixir on accelerating anchors")
    of esBoosters: result.add("spends elixir on boosters")
    of esDestabilizers: result.add("spends elixir on destabilizers")
  if d.anchorBudget == 0:
    result.add("never anchors — plays for the deeper tiebreaks")
  else:
    result.add("first anchor at round " & $d.anchorRound & " with " &
      $d.anchorBudget & " % of income reserved")
  case d.islandPriority
  of ipNearest: result.add("goes for the nearest islands")
  of ipContested: result.add("goes for the contested islands")
  of ipSafe: result.add("goes for the safest islands")
  case d.amplifierUse
  of auNever: result.add("builds no amplifiers")
  of auOne: result.add("one amplifier per headquarters")
  of auEscort: result.add("an amplifier escorting every launcher group")
  case d.destabilizerUse
  of duHold: result.add("its strike group holds its own wells and islands")
  of duDefend: result.add("its strike group intercepts inside its own half")
  of duSiege: result.add("its strike group sieges the nearest enemy headquarters")
  case d.retreatOnLauncherLoss
  of rpNever: result.add("presses on when a launcher dies")
  of rpRegroup: result.add("regroups when a launcher dies")
  of rpHome: result.add("withdraws wounded launchers to heal on its own islands")
  if d.carrierThrow == 0:
    result.add("carriers never throw")
  elif d.carrierThrow >= 60:
    result.add("carriers throw freely")
  else:
    result.add("carriers rarely throw")
