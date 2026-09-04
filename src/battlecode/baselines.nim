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

proc defaultBaselineFor*(year: string): Baseline =
  ## A seat that says nothing useful plays the year's STRONG published
  ## doctrine, not the deliberately weak floor.
  case yearIdOf(year)
  of yBc20: blBowlOfChowder
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

proc baselineChassis*(kind: Baseline): ChassisKind =
  ## The same selection for bc20, whose chassis is a `ChassisKind` on the seat
  ## record rather than a field on the doctrine.
  case kind
  of blExamplefuncsplayer: parseChassisKind("examplefuncsplayer")
  else: parseChassisKind("bowl-of-chowder")

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

proc baselineSheet*(year: string, kind: Baseline): Sheet =
  result = parseReply(baselineReply(kind), year)
  ## bc26 carries its chassis ON the doctrine, so the filler path sets it here
  ## rather than through the sheet. bc20 carries it on the seat record instead.
  if yearIdOf(year) == yBc26:
    result.doctrine.chassis = chassisFor(kind)

proc baselineSheet*(kind: Baseline): Sheet =
  baselineSheet("bc26", kind)

proc baselineName*(kind: Baseline): string = $kind
