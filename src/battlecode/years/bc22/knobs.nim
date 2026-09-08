## The Battlecode 2022 "Mutation" knob table: ELEVEN knobs, and NO `chassis`
## key.
##
## D1 (the standing review finding): the chassis is not an LLM-selectable knob.
## The chassis a seat drives comes from `PLAYER_SCRIPTED` (scripted seats) or is
## the fixed champion chassis (LLM seats). A submitted `chassis` is therefore
## recorded as an UNKNOWN FIELD and never honoured, and
## `tests/test_bc22_sheet.nim` asserts exactly that — the test fails if anyone
## re-adds the knob.
##
## Unknown key, wrong type or out-of-range value takes THAT FIELD'S DEFAULT and
## the repair is recorded — except the five INTEGER knobs, which CLAMP to their
## range rather than defaulting, so "as much as possible" still means something.
## A sheet can never be rejected, so a cog can never forfeit a match by
## answering badly — only by answering weakly.
##
## **THE ENVELOPE PIN, ITEM 2 (LEARNINGS 2026-09-08).** `applyKnobs22` adds an
## **ABSENT** known key to `defaultsApplied` as well as a repaired one, so
## `sheet_defaults_applied` for a bc22 seat is `[]` only when the cog really set
## all eleven knobs. This is deliberately **not** done year-neutrally in
## `sheet.nim`: doing so would change what a bc26/bc20/bc21/bc23/bc24/bc25
## episode records in that array, which is the one thing "prior years' semantics
## unchanged" forbids. `tests/test_bc22_sheet.nim` asserts a bc22 empty sheet
## reports all eleven names AND that a bc23 empty sheet still reports none, so
## the change is provably scoped.
##
## THE ANTI-INERT RULE, stated as a rule every knob is held against: NO SETTING
## OF ANY KNOB, AND NO COMBINATION OF SETTINGS, MAY PRODUCE AN INERT OR
## SELF-STARVING FACTION. The strategy surface lives inside ONE competent
## chassis. Independently of every knob the chassis always: keeps at least
## THREE MINERS PER ARCHON digging the nearest lead; builds a soldier whenever
## lead allows and the soldier census is below its target; spends an archon's
## action rather than banking it; answers an enemy attacker sensed within
## r2 <= 20 of one of its own archons; repairs a damaged droid standing in an
## archon's r2 <= 20; and never lets its LAST archon enter PORTABLE mode while
## an enemy attacker is sensed within eight squares.
## `tests/test_bc22_knobs.nim` proves each knob has teeth and
## `tests/test_bc22_survival.nim` proves the floor holds, WITH A NEGATIVE
## CONTROL THAT MUST FAIL (`-d:bc22BrokenChassis`).
##
## THE CHASSIS FILE LAYOUT this table's `what it changes` column points at:
## `chassis/kit.nim` (shared memory, the symmetry guess, the rubble-weighted
## navigator and the `DecisionOps` charging), `chassis/econ.nim` (`plan`,
## `minerTarget`, `attackMix`), `chassis/archon.nim` (`relocate`),
## `chassis/miner.nim` (`mineUntil`), `chassis/builder.nim` (`towers`),
## `chassis/soldier.nim`, `chassis/micro.nim` (`retreat`), `chassis/lab.nim`
## (`schedule`, `site`, `solitude`), `chassis/gold.nim` (`sink`),
## `chassis/anomaly.nim` (`plan`), `chassis/comms.nim`, `chassis/wololo.nim`
## (the turn dispatcher), `chassis/scaffold22.nim` and
## `chassis/scenario22.nim`. All FOURTEEN exist; `NOTICE` and
## `docs/RULES-BC22.md` name the same paths.

import std/[json, tables]
import ../../sheet_common
import units

export sheet_common

type
  Opening22* = enum
    ## `econ.nim plan()` — the lead split for the first 400 rounds.
    opSoldierRush = "soldier_rush"
    opMinerEco = "miner_eco"
    opSageSpam = "sage_spam"

  MinerCurve* = enum
    ## `econ.nim minerTarget()` — the miner census per archon.
    mcLean = "lean"
    mcSteady = "steady"
    mcHeavy = "heavy"

  GoldUse* = enum
    ## `gold.nim sink()` — what gold buys once it flows.
    guSages = "sages"
    guMutations = "mutations"

  WatchtowerPolicy* = enum
    ## `builder.nim towers()`.
    wpNever = "never"
    wpHome = "home"
    wpForward = "forward"

  AnomalyPlay* = enum
    ## `anomaly.nim plan()` — the axis the idea is actually asking about.
    apIgnore = "ignore"
    apTimePushes = "time_pushes"

  ArchonRelocate* = enum
    ## `archon.nim relocate()`.
    arNever = "never"
    arSafety = "safety"
    arLead = "lead"

  Doctrine22* = object
    opening*: Opening22
    minerCountCurve*: MinerCurve
    mineFloor*: int
    soldierSageRatio*: int
    labRound*: int
    labSolitude*: int
    goldUse*: GoldUse
    watchtowerPolicy*: WatchtowerPolicy
    anomalyPlay*: AnomalyPlay
    archonRelocate*: ArchonRelocate
    retreatHp*: int

const
  KnownKeys22* = [
    "opening", "miner_count_curve", "mine_floor", "soldier_sage_ratio",
    "lab_round", "lab_solitude", "gold_use", "watchtower_policy",
    "anomaly_play", "archon_relocate", "retreat_hp"
  ]
    ## Exactly eleven. `chassis` is deliberately NOT here (D1).

  MineFloorLo* = 0
  MineFloorHi* = 5
    ## THE YEAR'S SIGNATURE KNOB, and it is measured, not invented. The map adds
    ## +5 every 20 rounds to every square holding >= 1, so mining to 0 destroys
    ## that deposit permanently; and the global ABYSS removes
    ## `floor(0.1 * square)`, which is 0 for any square holding <= 9.
  SoldierSageRatioLo* = 0
  SoldierSageRatioHi* = 100
  LabRoundLo* = 1
  LabRoundHi* = 1800
  LabSolitudeLo* = 0
  LabSolitudeHi* = 40
  RetreatHpLo* = 0
  RetreatHpHi* = 100

  MinerFloorPerArchon* = 3
    ## The unconditional minimum, at EVERY knob setting.

proc defaultDoctrine22*(): Doctrine22 =
  Doctrine22(
    opening: opMinerEco,
    minerCountCurve: mcSteady,
    mineFloor: 1,
    soldierSageRatio: 65,
    labRound: 300,
    labSolitude: 12,
    goldUse: guSages,
    watchtowerPolicy: wpHome,
    anomalyPlay: apTimePushes,
    archonRelocate: arSafety,
    retreatHp: 40)

proc applyKnobs22*(seen: Table[string, JsonNode],
                   defaultsApplied: var seq[string]): Doctrine22 =
  result = defaultDoctrine22()

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
    else:
      ## THE ENVELOPE PIN, ITEM 2: an ABSENT known key is counted too, so a
      ## seat that played the schema defaults is machine-visible. bc22 only.
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
    else:
      repair(name)

  enumKnob("opening", result.opening, Opening22)
  enumKnob("miner_count_curve", result.minerCountCurve, MinerCurve)
  clampedIntKnob("mine_floor", result.mineFloor, MineFloorLo, MineFloorHi)
  clampedIntKnob("soldier_sage_ratio", result.soldierSageRatio,
                 SoldierSageRatioLo, SoldierSageRatioHi)
  clampedIntKnob("lab_round", result.labRound, LabRoundLo, LabRoundHi)
  clampedIntKnob("lab_solitude", result.labSolitude,
                 LabSolitudeLo, LabSolitudeHi)
  enumKnob("gold_use", result.goldUse, GoldUse)
  enumKnob("watchtower_policy", result.watchtowerPolicy, WatchtowerPolicy)
  enumKnob("anomaly_play", result.anomalyPlay, AnomalyPlay)
  enumKnob("archon_relocate", result.archonRelocate, ArchonRelocate)
  clampedIntKnob("retreat_hp", result.retreatHp, RetreatHpLo, RetreatHpHi)

proc toJson22*(d: Doctrine22): JsonNode =
  %*{
    "opening": $d.opening,
    "miner_count_curve": $d.minerCountCurve,
    "mine_floor": d.mineFloor,
    "soldier_sage_ratio": d.soldierSageRatio,
    "lab_round": d.labRound,
    "lab_solitude": d.labSolitude,
    "gold_use": $d.goldUse,
    "watchtower_policy": $d.watchtowerPolicy,
    "anomaly_play": $d.anomalyPlay,
    "archon_relocate": $d.archonRelocate,
    "retreat_hp": d.retreatHp
  }

proc bc22SheetSchema*(): JsonNode =
  ## The knob surface as the doctrine prompt carries it. Generated from THIS
  ## table rather than re-typed, so a knob cannot exist in the sim and be
  ## missing from the brief.
  let d = defaultDoctrine22()
  var openings = newJArray()
  for v in Opening22: openings.add(%($v))
  var curves = newJArray()
  for v in MinerCurve: curves.add(%($v))
  var golds = newJArray()
  for v in GoldUse: golds.add(%($v))
  var towers = newJArray()
  for v in WatchtowerPolicy: towers.add(%($v))
  var plays = newJArray()
  for v in AnomalyPlay: plays.add(%($v))
  var relocs = newJArray()
  for v in ArchonRelocate: relocs.add(%($v))
  %*{
    "opening": {"values": openings, "default": $d.opening,
                "note": "sage_spam is a GOLD programme, not a round-1 build " &
                        "order: sages cost gold and you start with none"},
    "miner_count_curve": {"values": curves, "default": $d.minerCountCurve,
                          "note": "the floor of 3 miners per archon is " &
                                  "unconditional at every value"},
    "mine_floor": {"range": [MineFloorLo, MineFloorHi], "default": d.mineFloor,
                   "note": "how much lead a miner leaves on a square. The " &
                           "map adds 5 every 20 rounds ONLY to a square that " &
                           "still holds at least 1, so 0 strip-mines the map " &
                           "dead; and the abyss takes 10% rounded down, so a " &
                           "square holding 9 or fewer loses nothing"},
    "soldier_sage_ratio": {"range": [SoldierSageRatioLo, SoldierSageRatioHi],
                           "default": d.soldierSageRatio,
                           "note": "percent of the attack budget, in " &
                                   "lead-equivalent, that goes to soldiers " &
                                   "rather than to gold for sages; clamped, " &
                                   "never zeroed"},
    "lab_round": {"range": [LabRoundLo, LabRoundHi], "default": d.labRound},
    "lab_solitude": {"range": [LabSolitudeLo, LabSolitudeHi],
                     "default": d.labSolitude,
                     "note": "the most friendly robots a lab tolerates in " &
                             "its r2<=53 before it stops transmuting and " &
                             "walks away; the price is floor(20 - " &
                             "18*exp(-0.02n)), so 12 is exactly 6 lead a gold"},
    "gold_use": {"values": golds, "default": $d.goldUse},
    "watchtower_policy": {"values": towers, "default": $d.watchtowerPolicy},
    "anomaly_play": {"values": plays, "default": $d.anomalyPlay,
                     "note": "time_pushes reads the public schedule and " &
                             "stands buildings up before a fury, scatters " &
                             "before a charge, pushes after one, spends down " &
                             "before an abyss and relocates before a vortex"},
    "archon_relocate": {"values": relocs, "default": $d.archonRelocate},
    "retreat_hp": {"range": [RetreatHpLo, RetreatHpHi], "default": d.retreatHp,
                   "note": "a droid still takes an attack that KILLS its " &
                           "target at every setting"}
  }

proc plainWords22*(d: Doctrine22): seq[string] =
  ## The endcard / `#bc22-doctrines` readout: the sheet in words a spectator can
  ## read without knowing the schema.
  ##
  ## EVERY CLAUSE IS A COMPLETE PHRASE. bc23 shipped `"a accelerating"` because
  ## it concatenated `"a "` with an enum string; there is NO ARTICLE
  ## CONCATENATION anywhere in this proc, and `tests/test_bc22_sheet.nim`
  ## asserts each clause is non-empty and article-free.
  case d.opening
  of opSoldierRush: result.add("rushes soldiers from round one")
  of opMinerEco: result.add("opens on miner economy")
  of opSageSpam: result.add("banks lead for a laboratory and spams sages")
  case d.minerCountCurve
  of mcLean: result.add("keeps its miner count lean")
  of mcSteady: result.add("grows miners steadily with the lead it can see")
  of mcHeavy: result.add("saturates the map with miners")
  if d.mineFloor == 0:
    result.add("strip-mines every square to zero and kills the deposit")
  elif d.mineFloor == 1:
    result.add("leaves one lead on every square so it regenerates for ever")
  else:
    result.add("leaves " & $d.mineFloor &
               " lead on every square so it regenerates")
  if d.soldierSageRatio >= 90:
    result.add("spends its whole attack budget on soldiers")
  elif d.soldierSageRatio <= 15:
    result.add("turns almost all of its attack budget into gold for sages")
  else:
    result.add($d.soldierSageRatio &
               " % of its attack budget goes to soldiers, the rest to gold")
  result.add("commissions its first laboratory at round " & $d.labRound)
  if d.labSolitude <= 4:
    result.add("transmutes only when the laboratory is nearly alone, at two " &
               "or three lead a gold")
  elif d.labSolitude >= 30:
    result.add("transmutes at any price, however crowded the laboratory is")
  else:
    result.add("stops transmuting once " & $d.labSolitude &
               " friendly robots crowd the laboratory")
  case d.goldUse
  of guSages: result.add("spends gold on sages")
  of guMutations: result.add("spends gold on level-three mutations")
  if d.soldierSageRatio >= 100:
    result.add("no gold programme, so its sink never opens")
  case d.watchtowerPolicy
  of wpNever: result.add("builds no watchtowers")
  of wpHome: result.add("puts one watchtower beside each archon")
  of wpForward: result.add("builds watchtowers at the frontier")
  case d.anomalyPlay
  of apIgnore: result.add("ignores the anomaly schedule entirely")
  of apTimePushes:
    result.add("reads the anomaly schedule and times its play around it")
  case d.archonRelocate
  of arNever: result.add("never walks an archon off its opening square")
  of arSafety: result.add("walks an archon away from danger")
  of arLead: result.add("walks its archons toward the richest lead")
  if d.retreatHp == 0:
    result.add("never pulls a wounded droid out of a fight")
  elif d.retreatHp >= 90:
    result.add("withdraws a droid on the first damage it takes")
  else:
    result.add("pulls a droid out at " & $d.retreatHp & " % health")
