## The published scripted baselines, YEAR-AWARE.
##
## `PLAYER_SCRIPTED=<name>` selects BOTH the reply sheet and the chassis. The
## chassis is never a sheet field (D1): a submitted `chassis` key is recorded
## as an unknown field and never honoured, so the filler path below is the ONLY
## way `scaffold` or `examplefuncsplayer` is ever driven.
##
## Every reply goes through the SAME `sheet.validate()` the LLM path uses,
## which is what makes `tests/test_baselines.nim`'s and
## `tests/test_bc20_baselines.nim`'s bounded-orders checks meaningful and an
## LLM doctrine and a scripted one strictly comparable — which is why a reply
## carries only keys the LLM surface also has, and never `chassis`.

import std/strutils
import sheet
import years/dispatch

type
  Baseline* = enum
    blAwu = "awu"
    blScaffold = "scaffold"
    blBowlOfChowder = "bowl-of-chowder"
    blExamplefuncsplayer = "examplefuncsplayer"
    blCaliforniaRoll = "california-roll"
    blExamplefuncsplayer21 = "examplefuncsplayer21"
    blGoneSharkin = "gone-sharkin"
    blExamplefuncsplayer24 = "examplefuncsplayer24"
    blSpaark = "spaark"
    blExamplefuncsplayer25 = "examplefuncsplayer25"
    blLemonade = "lemonade"
    blExamplefuncsplayer23 = "examplefuncsplayer23"
    blWololo = "wololo"
    blExamplefuncsplayer22 = "examplefuncsplayer22"
    blBulwark = "bulwark"
    blGreenhorn = "greenhorn"

proc defaultBaselineFor*(year: string): Baseline =
  ## A seat that says nothing useful plays the year's STRONG published
  ## doctrine, not the deliberately weak floor.
  case yearIdOf(year)
  of yBc20: blBowlOfChowder
  of yBc21: blCaliforniaRoll
  of yBc24: blGoneSharkin
  of yBc25: blSpaark
  of yBc23: blLemonade
  of yBc22: blWololo
  of yBc16: blBulwark
  of yBc26: blAwu

proc baselineFor*(year, name: string): Baseline =
  ## `PLAYER_SCRIPTED` values, per year. An unrecognised name takes the year's
  ## default.
  let key = name.strip().toLowerAscii()
  case yearIdOf(year)
  of yBc20:
    case key
    of "examplefuncsplayer", "scaffold", "example": blExamplefuncsplayer
    else: blBowlOfChowder
  of yBc21:
    case key
    of "scaffold", "examplefuncsplayer", "examplefuncsplayer21", "example":
      blExamplefuncsplayer21
    else: blCaliforniaRoll
  of yBc24:
    case key
    of "scaffold", "examplefuncsplayer", "examplefuncsplayer24", "example":
      blExamplefuncsplayer24
    else: blGoneSharkin
  of yBc25:
    case key
    of "scaffold", "examplefuncsplayer", "examplefuncsplayer25", "example":
      blExamplefuncsplayer25
    else: blSpaark
  of yBc23:
    case key
    of "scaffold", "examplefuncsplayer", "examplefuncsplayer23", "example":
      blExamplefuncsplayer23
    else: blLemonade
  of yBc22:
    case key
    of "scaffold", "examplefuncsplayer", "examplefuncsplayer22", "example":
      blExamplefuncsplayer22
    else: blWololo
  of yBc16:
    ## `awu`, `bulwark` or anything unrecognised is the STRONG doctrine
    ## chassis; `scaffold`, `greenhorn`, `example` and `examplefuncsplayer`
    ## are the deliberately weak floor and the parity oracle's other side.
    case key
    of "scaffold", "greenhorn", "example", "examplefuncsplayer":
      blGreenhorn
    else: blBulwark
  of yBc26:
    case key
    of "scaffold", "examplefuncsplayer", "example": blScaffold
    else: blAwu

proc parseBaseline*(text: string): Baseline =
  ## Year-free reading, kept for the bc26 call sites that predate the year
  ## module boundary. bc26's own two names are the only ones it can return.
  baselineFor("bc26", text)

proc chassisFor*(kind: Baseline): Chassis =
  ## The bc26 filler path's chassis selection, and the ONLY one there is. It
  ## is not a sheet key: an LLM doctrine cannot reach it (see
  ## `sheet.KnownKeys`), so `scaffold` is selectable only by
  ## `PLAYER_SCRIPTED=scaffold`.
  case kind
  of blScaffold: chScaffold
  else: chAwu

proc baselineChassis*(kind: Baseline): ScriptedChassis =
  ## The same selection for bc20 and bc21, whose chassis is a year-neutral
  ## `ScriptedChassis` on the seat record rather than a field on the doctrine.
  ## `years/dispatch.nim`'s `newSession` maps it into the year's own kind, so a
  ## name belonging to another year plays THAT year's strong chassis.
  case kind
  of blScaffold: scScaffold
  of blExamplefuncsplayer: scExamplefuncsplayer
  of blCaliforniaRoll: scCaliforniaRoll
  of blExamplefuncsplayer21: scExamplefuncsplayer21
  of blBowlOfChowder: scBowlOfChowder
  of blGoneSharkin: scGoneSharkin
  of blExamplefuncsplayer24: scExamplefuncsplayer24
  of blSpaark: scSpaark
  of blExamplefuncsplayer25: scExamplefuncsplayer25
  of blLemonade: scLemonade
  of blExamplefuncsplayer23: scExamplefuncsplayer23
  of blWololo: scWololo
  of blExamplefuncsplayer22: scExamplefuncsplayer22
  of blBulwark: scBulwark
  of blGreenhorn: scGreenhorn
  of blAwu: scAwu

proc baselineReply*(kind: Baseline): string =
  ## The exact JSON a scripted seat "answers" with. Emitted as text and then
  ## parsed by the same tolerant validator, so a scripted seat is
  ## indistinguishable from an LLM seat downstream — which is why it carries
  ## only keys the LLM surface also has, and never `chassis`.
  ##
  ## The bc20 replies are the all-defaults sheet: the passive-lattice build,
  ## which is also the fallback sheet §Decisions prints verbatim.
  case kind
  of blAwu:
    """{"sheet":{},"notes":"default awu doctrine",
        "motto":"Cheese first."}"""
  of blScaffold:
    """{"sheet":{},"notes":"scaffold baseline",
        "motto":"Forward."}"""
  of blBowlOfChowder:
    """{"sheet":{"opening":"passive_lattice","terraform_start_round":300,
                 "lattice_radius":6,"landscaper_count_curve":"steady",
                 "miner_count_curve":"steady","vaporator_budget":2,
                 "drone_role":"harass","net_gun_ring":2,"rush_trigger":0,
                 "wall_hq_round":250},
        "notes":"default bowl-of-chowder doctrine","motto":"Soup first."}"""
  of blExamplefuncsplayer:
    """{"sheet":{"opening":"passive_lattice","terraform_start_round":300,
                 "lattice_radius":6,"landscaper_count_curve":"steady",
                 "miner_count_curve":"steady","vaporator_budget":2,
                 "drone_role":"harass","net_gun_ring":2,"rush_trigger":0,
                 "wall_hq_round":250},
        "notes":"scaffold baseline (2020)","motto":"Forward."}"""
  of blCaliforniaRoll, blExamplefuncsplayer21:
    ## The all-defaults bc21 sheet, which is ALSO the fallback sheet
    ## §Decisions prints verbatim. `examplefuncsplayer21` reads no knob, so it
    ## answers with the same sheet: the chassis, not the sheet, is what makes
    ## it the weak floor (D1).
    """{"sheet":{"opening":"balanced","slanderer_ratio":45,"muck_ratio":25,
                 "politician_size_curve":"ramp","bid_policy":"proportional",
                 "expansion":"neutral_centers_first",
                 "flank_policy":"hunt_slanderers","empower_threshold":60,
                 "convert_over_kill":true,"eco_exponential_round":700},
        "notes":"default california-roll doctrine",
        "motto":"Vote early, vote often."}"""
  of blGoneSharkin, blExamplefuncsplayer24:
    ## The all-defaults bc24 sheet, which is ALSO the fallback sheet
    ## §Decisions prints verbatim. `examplefuncsplayer24` reads no knob, so it
    ## answers with the same sheet: the chassis, not the sheet, is what makes
    ## it the weak floor (D1).
    """{"sheet":{"specialisation_split":"balanced","flag_rush_round":450,
                 "trap_budget":30,"trap_placement":"flag_ring",
                 "trap_mix":"mixed","heal_priority":"wounded_first",
                 "water_dig_policy":"choke_dig",
                 "upgrade_order":["attack","heal","capture"],
                 "retreat_hp":400,"flag_carry_escort":2},
        "notes":"default gone-sharkin doctrine",
        "motto":"Bread first, blood after."}"""
  of blSpaark, blExamplefuncsplayer25:
    ## The all-defaults bc25 sheet, which is ALSO the fallback sheet
    ## §Decisions prints verbatim. `examplefuncsplayer25` reads no knob, so it
    ## answers with the same sheet: the chassis, not the sheet, is what makes
    ## it the weak floor (D1).
    """{"sheet":{"opening":"balanced",
                 "unit_mix":{"soldier":60,"mopper":25,"splasher":15},
                 "srp_priority":35,
                 "tower_type_order":["money","paint","defense"],
                 "ruin_claim_radius":10,"defense_tower_chokes":"late",
                 "paint_reserve_floor":30,"mop_enemy_paint":40,
                 "splash_targets":"mixed","upgrade_policy":"money_first"},
        "notes":"default spaark doctrine",
        "motto":"Paint it and hold it."}"""
  of blLemonade, blExamplefuncsplayer23:
    ## The all-defaults bc23 sheet, which is ALSO the fallback sheet
    ## §Decisions prints verbatim. `examplefuncsplayer23` reads no knob, so it
    ## answers with the same sheet: the chassis, not the sheet, is what makes
    ## it the weak floor (D1).
    """{"sheet":{"opening":"balanced","launcher_ratio":45,
                 "well_priority":"balanced","elixir_tech":"mid",
                 "elixir_spend":"accelerating_anchors",
                 "anchor_round":400,"anchor_budget":35,
                 "island_priority":"nearest","amplifier_use":"one",
                 "destabilizer_use":"defend",
                 "retreat_on_launcher_loss":"regroup","carrier_throw":25},
        "notes":"default lemonade doctrine","motto":"Anchor the sky."}"""
  of blWololo, blExamplefuncsplayer22:
    ## The all-defaults bc22 sheet, which is ALSO the fallback sheet
    ## §Decisions prints verbatim. `examplefuncsplayer22` reads no knob, so it
    ## answers with the same sheet: the chassis, not the sheet, is what makes
    ## it the weak floor (D1).
    """{"sheet":{"opening":"miner_eco","miner_count_curve":"steady",
                 "mine_floor":1,"soldier_sage_ratio":65,"lab_round":300,
                 "lab_solitude":12,"gold_use":"sages",
                 "watchtower_policy":"home","anomaly_play":"time_pushes",
                 "archon_relocate":"safety","retreat_hp":40},
        "notes":"default wololo doctrine","motto":"Leave one lead behind."}"""
  of blBulwark, blGreenhorn:
    ## The all-defaults bc16 sheet, which is ALSO the fallback sheet
    ## §Decisions prints verbatim. `greenhorn` reads no knob, so it answers
    ## with the same sheet: the chassis, not the sheet, is what makes it the
    ## weak floor (D1).
    """{"sheet":{"opening":"turtle","turret_count":3,"guard_ratio":45,
                 "zombie_kiting":"ranged_only","den_clear_round":900,
                 "parts_priority":"units","archon_spread":"spread",
                 "neutral_activation":"opportunistic","retreat_hp":35,
                 "rubble_clear":"paths","infection_policy":"quarantine"},
        "notes":"default bulwark doctrine","motto":"The wall holds."}"""

proc baselineSheet*(year: string, kind: Baseline): Sheet =
  result = parseReply(baselineReply(kind), year)
  ## bc26 carries its chassis ON the doctrine, so the filler path sets it here
  ## rather than through the sheet. bc20 carries it on the seat record instead.
  if yearIdOf(year) == yBc26:
    result.doctrine.chassis = chassisFor(kind)

proc baselineSheet*(kind: Baseline): Sheet =
  baselineSheet("bc26", kind)

proc baselineName*(kind: Baseline): string = $kind
