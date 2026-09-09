## The Battlecode 2016 "Zombie Invasion" knob table: ELEVEN knobs, and NO
## `chassis` key.
##
## D1 (the standing review finding): the chassis is not an LLM-selectable
## knob. The chassis a seat drives comes from `PLAYER_SCRIPTED` (scripted
## seats) or is the fixed champion chassis (LLM seats). A submitted `chassis`
## is therefore recorded as an UNKNOWN FIELD and never honoured, and
## `tests/test_bc16_sheet.nim` asserts exactly that — the test fails if anyone
## re-adds the knob.
##
## Unknown key, wrong type or out-of-range value takes THAT FIELD'S DEFAULT
## and the repair is recorded — except the FOUR INTEGER knobs, which CLAMP to
## their range rather than defaulting, so "as many as possible" still means
## something. A sheet can never be rejected, so a cog can never forfeit a
## match by answering badly — only by answering weakly.
##
## **THE ENVELOPE PIN, ITEM 2 (LEARNINGS 2026-09-08).** `applyKnobs16` adds an
## **ABSENT** known key to `defaultsApplied` as well as a repaired one, so
## `sheet_defaults_applied` for a bc16 seat is `[]` only when the cog really
## set all eleven knobs. This is deliberately **not** done year-neutrally in
## `sheet.nim`: doing so would change what a bc20/bc21/bc23/bc24/bc25/bc26
## episode records in that array, which is the one thing "prior years'
## semantics unchanged" forbids. `tests/test_bc16_sheet.nim` asserts a bc16
## empty sheet reports all eleven names AND that a bc23 empty sheet still
## reports none, so the change is provably scoped.
##
## THE ANTI-INERT RULE, stated as a rule every knob is held against: NO
## SETTING OF ANY KNOB, AND NO COMBINATION OF SETTINGS, MAY PRODUCE AN INERT
## OR SELF-STARVING FACTION. The strategy surface lives inside ONE competent
## chassis. Independently of every knob, `bulwark` always: keeps at least one
## archon collecting parts and never lets the stockpile idle above 200 without
## a build order; builds an attacker (soldier or guard) whenever parts allow
## and the attacker census is below its target, and NEVER FEWER THAN THREE
## ATTACKERS PER ARCHON; answers any hostile robot sensed within r2 <= 24 of
## one of its own archons; spends every archon's free repair every turn on the
## weakest damaged friendly in r2 <= 24; never walks its last archon into a
## square adjacent to a den that has zombies queued; and NEVER ATTACKS A
## FRIENDLY SQUARE (friendly fire is legal in 2016 and the chassis never uses
## it). Every knob moves HOW MUCH OF WHAT, WHEN — never WHETHER IT PLAYS.
## `tests/test_bc16_knobs.nim` proves each knob has teeth and
## `tests/test_bc16_survival.nim` proves the floor holds, WITH A NEGATIVE
## CONTROL THAT MUST FAIL (`-d:bc16BrokenChassis`).
##
## THE CHASSIS FILE LAYOUT this table's "what it changes" column points at:
## `chassis/kit.nim` (the shared side memory, the remembered map, the den and
## neutral rosters, the rubble-weighted navigator and the `DecisionOps`
## charging), `chassis/econ.nim` (`plan`, `attackMix`, `queue`),
## `chassis/archon.nim` (`posture`), `chassis/combat.nim`,
## `chassis/micro.nim` (`kite`, `retreat`), `chassis/turret.nim` (`target`,
## `site`), `chassis/dens.nim` (`schedule`), `chassis/neutral.nim` (`plan`),
## `chassis/rubble.nim` (`plan`), `chassis/infect.nim` (`plan`),
## `chassis/comms.nim`, `chassis/bulwark.nim` (the turn dispatcher),
## `chassis/greenhorn.nim` and `chassis/scenario16.nim`. All FOURTEEN exist;
## `NOTICE` and `docs/RULES-BC16.md` name the same paths.

import std/[json, tables]
import ../../sheet_common
import units

export sheet_common

type
  Opening16* = enum
    ## `econ.nim plan()` — the parts split and the posture for the first 600
    ## rounds, and the three archetypes the 2016 finals actually produced.
    opTurtle = "turtle"
    opSoldierViperAggro = "soldier_viper_aggro"
    opScoutZombiePull = "scout_zombie_pull"

  ZombieKiting16* = enum
    ## `micro.nim kite()` — whether a unit backs off a closing zombie instead
    ## of trading. It has teeth because the delay table is asymmetric.
    zkNever = "never"
    zkRangedOnly = "ranged_only"
    zkAlways = "always"

  PartsPriority16* = enum
    ## `econ.nim queue()` — what the stockpile buys first when it cannot buy
    ## everything.
    ppUnits = "units"
    ppTurrets = "turrets"
    ppVipers = "vipers"

  ArchonSpread16* = enum
    ## `archon.nim posture()` — where the archons stand relative to each
    ## other.
    asHuddle = "huddle"
    asSpread = "spread"
    asSplit = "split"

  NeutralActivation16* = enum
    ## `neutral.nim plan()` — whether an archon detours to activate NEUTRALs.
    naNever = "never"
    naOpportunistic = "opportunistic"
    naHunt = "hunt"

  RubbleClear16* = enum
    ## `rubble.nim plan()` — this year's terrain, made a spendable choice.
    rcNever = "never"
    rcPaths = "paths"
    rcAggressive = "aggressive"

  InfectionPolicy16* = enum
    ## `infect.nim plan()` — this year's largest unexploited play.
    ipIgnore = "ignore"
    ipQuarantine = "quarantine"
    ipSuicideSquad = "suicide_squad"

  Doctrine16* = object
    opening*: Opening16
    turretCount*: int
    guardRatio*: int
    zombieKiting*: ZombieKiting16
    denClearRound*: int
    partsPriority*: PartsPriority16
    archonSpread*: ArchonSpread16
    neutralActivation*: NeutralActivation16
    retreatHp*: int
    rubbleClear*: RubbleClear16
    infectionPolicy*: InfectionPolicy16

const
  KnownKeys16* = [
    "opening", "turret_count", "guard_ratio", "zombie_kiting",
    "den_clear_round", "parts_priority", "archon_spread",
    "neutral_activation", "retreat_hp", "rubble_clear", "infection_policy"
  ]
    ## Exactly eleven. `chassis` is deliberately NOT here (D1).

  TurretCountLo* = 0
  TurretCountHi* = 12
  GuardRatioLo* = 0
  GuardRatioHi* = 100
  DenClearRoundLo* = 1
  DenClearRoundHi* = 2800
  RetreatHpLo* = 0
  RetreatHpHi* = 100

  AttackersPerArchonFloor* = 3
    ## The unconditional minimum, at EVERY knob setting.

proc defaultDoctrine16*(): Doctrine16 =
  Doctrine16(
    opening: opTurtle,
    turretCount: 3,
    guardRatio: 45,
    zombieKiting: zkRangedOnly,
    denClearRound: 900,
    partsPriority: ppUnits,
    archonSpread: asSpread,
    neutralActivation: naOpportunistic,
    retreatHp: 35,
    rubbleClear: rcPaths,
    infectionPolicy: ipQuarantine)

proc applyKnobs16*(seen: Table[string, JsonNode],
                   defaultsApplied: var seq[string]): Doctrine16 =
  result = defaultDoctrine16()

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
      ## seat that played the schema defaults is machine-visible. bc16 and
      ## bc22 only.
      repair(name)

  template clampedIntKnob(name: string, field: untyped, lo, hi: int) =
    ## AN INTEGER KNOB IS CLAMPED, NEVER DEFAULTED, so "as many as possible"
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

  enumKnob("opening", result.opening, Opening16)
  clampedIntKnob("turret_count", result.turretCount,
                 TurretCountLo, TurretCountHi)
  clampedIntKnob("guard_ratio", result.guardRatio,
                 GuardRatioLo, GuardRatioHi)
  enumKnob("zombie_kiting", result.zombieKiting, ZombieKiting16)
  clampedIntKnob("den_clear_round", result.denClearRound,
                 DenClearRoundLo, DenClearRoundHi)
  enumKnob("parts_priority", result.partsPriority, PartsPriority16)
  enumKnob("archon_spread", result.archonSpread, ArchonSpread16)
  enumKnob("neutral_activation", result.neutralActivation,
           NeutralActivation16)
  clampedIntKnob("retreat_hp", result.retreatHp, RetreatHpLo, RetreatHpHi)
  enumKnob("rubble_clear", result.rubbleClear, RubbleClear16)
  enumKnob("infection_policy", result.infectionPolicy, InfectionPolicy16)

proc toJson16*(d: Doctrine16): JsonNode =
  %*{
    "opening": $d.opening,
    "turret_count": d.turretCount,
    "guard_ratio": d.guardRatio,
    "zombie_kiting": $d.zombieKiting,
    "den_clear_round": d.denClearRound,
    "parts_priority": $d.partsPriority,
    "archon_spread": $d.archonSpread,
    "neutral_activation": $d.neutralActivation,
    "retreat_hp": d.retreatHp,
    "rubble_clear": $d.rubbleClear,
    "infection_policy": $d.infectionPolicy
  }

proc bc16SheetSchema*(): JsonNode =
  ## The knob surface as the doctrine prompt carries it. Generated from THIS
  ## table rather than re-typed, so a knob cannot exist in the sim and be
  ## missing from the brief.
  let d = defaultDoctrine16()
  var openings = newJArray()
  for v in Opening16: openings.add(%($v))
  var kitings = newJArray()
  for v in ZombieKiting16: kitings.add(%($v))
  var priorities = newJArray()
  for v in PartsPriority16: priorities.add(%($v))
  var spreads = newJArray()
  for v in ArchonSpread16: spreads.add(%($v))
  var activations = newJArray()
  for v in NeutralActivation16: activations.add(%($v))
  var clears = newJArray()
  for v in RubbleClear16: clears.add(%($v))
  var infections = newJArray()
  for v in InfectionPolicy16: infections.add(%($v))
  %*{
    "opening": {"values": openings, "default": $d.opening,
                "note": "the three archetypes the 2016 finals produced. " &
                        "turtle still builds soldiers -- the attacker " &
                        "census target is halved, never zeroed"},
    "turret_count": {"range": [TurretCountLo, TurretCountHi],
                     "default": d.turretCount,
                     "note": "a turret is 130 parts and 25 turns of a " &
                             "FROZEN archon, cannot shoot inside " &
                             "range-squared 6, reaches 40, and must PACK " &
                             "(10 delay on both counters) to move at all"},
    "guard_ratio": {"range": [GuardRatioLo, GuardRatioHi],
                    "default": d.guardRatio,
                    "note": "percent of the ATTACKER budget spent on " &
                            "GUARDs rather than SOLDIERs (both 30 parts). A " &
                            "guard has 145 health against 60, deals DOUBLE " &
                            "damage to zombies and blocks 4 off any hit " &
                            "above 10; a soldier hits for 4 at " &
                            "range-squared 13. At 100 the chassis still " &
                            "builds a soldier whenever no guard is " &
                            "affordable"},
    "zombie_kiting": {"values": kitings, "default": $d.zombieKiting,
                      "note": "a STANDARDZOMBIE pays movement delay 3 and a " &
                              "BIGZOMBIE 4 while a SOLDIER pays 2 -- but a " &
                              "FASTZOMBIE pays 1.4 and ignores rubble, so " &
                              "it cannot be kited. The chassis still takes " &
                              "any attack that KILLS its target at every " &
                              "setting"},
    "den_clear_round": {"range": [DenClearRoundLo, DenClearRoundHi],
                        "default": d.denClearRound,
                        "note": "a den is 2000 health and pays 200 parts, " &
                                "and killing it deletes its share of every " &
                                "future wave; it also damages every " &
                                "adjacent non-zombie for 10 a round while " &
                                "it has a queue"},
    "parts_priority": {"values": priorities, "default": $d.partsPriority},
    "archon_spread": {"values": spreads, "default": $d.archonSpread,
                      "note": "archons are the only thing that decides the " &
                              "game, the only repair source and the only " &
                              "parts collectors"},
    "neutral_activation": {"values": activations,
                           "default": $d.neutralActivation,
                           "note": "an ARCHON activates a NEUTRAL within " &
                                   "range-squared 2 for ZERO parts and 2 " &
                                   "core delay; some maps place neutral " &
                                   "ARCHONS, which are a whole extra " &
                                   "tiebreak rung"},
    "retreat_hp": {"range": [RetreatHpLo, RetreatHpHi],
                   "default": d.retreatHp,
                   "note": "percent of max health at which a damaged unit " &
                           "disengages toward the nearest friendly archon " &
                           "-- the only healing in the game, 1 health a " &
                           "turn, free. At every setting the chassis still " &
                           "takes an attack that KILLS its target"},
    "rubble_clear": {"values": clears, "default": $d.rubbleClear,
                     "note": "one clear turns r into max(0, 0.95r - 10); " &
                             "100 or more is impassable to everything but a " &
                             "SCOUT, a FASTZOMBIE and a BIGZOMBIE; 50 or " &
                             "more DOUBLES every movement and cooldown " &
                             "charge; and every uninfected corpse adds its " &
                             "own max health"},
    "infection_policy": {"values": infections, "default": $d.infectionPolicy,
                         "note": "anything that dies while infected leaves " &
                                 "NO rubble and stands back up as a zombie " &
                                 "of its own type on the horde's team, and " &
                                 "then hunts whoever is nearest"}
  }

proc plainWords16*(d: Doctrine16): seq[string] =
  ## The endcard / `#bc16-doctrines` readout: the sheet in words a spectator
  ## can read without knowing the schema.
  ##
  ## EVERY CLAUSE IS A COMPLETE PHRASE. bc23 shipped `"a accelerating"`
  ## because it concatenated `"a "` with an enum string; there is NO ARTICLE
  ## CONCATENATION anywhere in this proc, and `tests/test_bc16_sheet.nim`
  ## asserts each clause is non-empty and article-free.
  case d.opening
  of opTurtle:
    result.add("holds its archons together behind a guard wall")
  of opSoldierViperAggro:
    result.add("sends a soldier spearhead at the nearest enemy archon")
  of opScoutZombiePull:
    result.add("parks scouts between the dens and itself to pull the horde")
  if d.turretCount == 0:
    result.add("wants no turrets standing, and stays all-mobile")
  elif d.turretCount == 1:
    result.add("wants one turret standing")
  else:
    result.add("wants " & $d.turretCount & " turrets standing")
  if d.guardRatio == 0:
    result.add("builds an all-soldier army")
  elif d.guardRatio >= 100:
    result.add("builds guards whenever it can afford one")
  else:
    result.add($d.guardRatio & " % of its army is guards")
  case d.zombieKiting
  of zkNever: result.add("trades with every zombie where it stands")
  of zkRangedOnly: result.add("kites zombies with everything ranged")
  of zkAlways: result.add("kites zombies with guards too")
  result.add("breaks a zombie den at round " & $d.denClearRound)
  case d.partsPriority
  of ppUnits: result.add("spends parts on soldiers and guards first")
  of ppTurrets: result.add("fills its turret count before any attacker")
  of ppVipers: result.add("buys a viper before the third soldier")
  case d.archonSpread
  of asHuddle: result.add("keeps its archons inside one repair field")
  of asSpread: result.add("spreads its archons behind their own screens")
  of asSplit: result.add("sends one archon away to farm the far map")
  case d.neutralActivation
  of naNever: result.add("never detours to activate a neutral")
  of naOpportunistic: result.add("activates a neutral it passes")
  of naHunt: result.add("routes its archons along the neutral roster")
  if d.retreatHp == 0:
    result.add("never pulls a wounded unit out of a fight")
  elif d.retreatHp >= 100:
    result.add("withdraws a unit on the first damage it takes")
  else:
    result.add("pulls a unit out at " & $d.retreatHp & " % health")
  case d.rubbleClear
  of rcNever: result.add("clears no rubble and plays the map it was given")
  of rcPaths: result.add("clears rubble to open the routes it needs")
  of rcAggressive: result.add("flattens its whole home area to full speed")
  case d.infectionPolicy
  of ipIgnore: result.add("never reads its own infection counters")
  of ipQuarantine:
    result.add("walks its infected units away from its own archons")
  of ipSuicideSquad:
    result.add("walks its infected units at the enemy archons to die there")
