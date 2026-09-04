## The Battlecode 2020 "Soup" knob table: TEN knobs, and NO `chassis` key.
##
## D1 (sibling review finding, 2026-09-03): the chassis is not an
## LLM-selectable knob. The chassis a seat drives comes from `PLAYER_SCRIPTED`
## (scripted seats) or is the fixed champion chassis (LLM seats). A submitted
## `chassis` is therefore recorded as an UNKNOWN FIELD and never honoured, and
## `tests/test_bc20_sheet.nim` asserts exactly that — the test fails if anyone
## re-adds the knob.
##
## Unknown key, wrong type or out-of-range value takes THAT FIELD'S DEFAULT and
## the repair is recorded. A sheet can never be rejected, so a cog can never
## forfeit a match by answering badly — only by answering weakly.

import std/[json, tables]
import ../../sheet_common

export sheet_common

type
  Opening* = enum
    opRush = "rush"
    opLattice = "lattice"
    opPassiveLattice = "passive_lattice"
    opTurtle = "turtle"

  CountCurve* = enum
    ccLean = "lean"
    ccSteady = "steady"
    ccSwarm = "swarm"

  DroneRole* = enum
    drHarass = "harass"
    drWall = "wall"
    drBuster = "buster"
    drCarryLandscapers = "carry_landscapers"

  Doctrine20* = object
    ## The ten knobs, each with a named site in the bc20 chassis
    ## (docs/RULES-BC20.md §The doctrine sheet lists the site per knob).
    opening*: Opening
    terraformStartRound*: int
    latticeRadius*: int
    landscaperCountCurve*: CountCurve
    minerCountCurve*: CountCurve
    vaporatorBudget*: int
    droneRole*: DroneRole
    netGunRing*: int
    rushTrigger*: int
    wallHqRound*: int

const
  KnownKeys20* = [
    "opening", "terraform_start_round", "lattice_radius",
    "landscaper_count_curve", "miner_count_curve", "vaporator_budget",
    "drone_role", "net_gun_ring", "rush_trigger", "wall_hq_round"
  ]
    ## Exactly ten. `chassis` is deliberately NOT here (D1).

proc defaultDoctrine20*(): Doctrine20 =
  Doctrine20(
    opening: opPassiveLattice,
    terraformStartRound: 300,
    latticeRadius: 6,
    landscaperCountCurve: ccSteady,
    minerCountCurve: ccSteady,
    vaporatorBudget: 2,
    droneRole: drHarass,
    netGunRing: 2,
    rushTrigger: 0,
    wallHqRound: 250
  )

proc applyKnobs20*(seen: Table[string, JsonNode],
                   defaultsApplied: var seq[string]): Doctrine20 =
  result = defaultDoctrine20()

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

  enumKnob("opening", result.opening, Opening)
  intKnob("terraform_start_round", result.terraformStartRound, 1, 1500)
  intKnob("lattice_radius", result.latticeRadius, 2, 12)
  enumKnob("landscaper_count_curve", result.landscaperCountCurve, CountCurve)
  enumKnob("miner_count_curve", result.minerCountCurve, CountCurve)
  intKnob("vaporator_budget", result.vaporatorBudget, 0, 6)
  enumKnob("drone_role", result.droneRole, DroneRole)
  intKnob("net_gun_ring", result.netGunRing, 0, 6)
  intKnob("rush_trigger", result.rushTrigger, 0, 1500)
  intKnob("wall_hq_round", result.wallHqRound, 0, 1500)

proc toJson20*(d: Doctrine20): JsonNode =
  %*{
    "opening": $d.opening,
    "terraform_start_round": d.terraformStartRound,
    "lattice_radius": d.latticeRadius,
    "landscaper_count_curve": $d.landscaperCountCurve,
    "miner_count_curve": $d.minerCountCurve,
    "vaporator_budget": d.vaporatorBudget,
    "drone_role": $d.droneRole,
    "net_gun_ring": d.netGunRing,
    "rush_trigger": d.rushTrigger,
    "wall_hq_round": d.wallHqRound
  }

proc plainWords20*(d: Doctrine20): seq[string] =
  ## The endcard/`#bc20-doctrines` readout: the sheet in words a spectator can
  ## read without knowing the schema.
  case d.opening
  of opRush: result.add("rushes the enemy HQ")
  of opLattice: result.add("lattices outward")
  of opPassiveLattice: result.add("lattices inward first")
  of opTurtle: result.add("turtles")
  if d.rushTrigger > 0:
    result.add("commits at round " & $d.rushTrigger)
  else:
    result.add("never commits a rush")
  if d.wallHqRound > 0:
    result.add("walls at " & $d.wallHqRound)
  else:
    result.add("never walls its HQ")
  result.add("terraforms from " & $d.terraformStartRound)
  result.add("lattice radius " & $d.latticeRadius)
  result.add($d.landscaperCountCurve & " landscapers")
  result.add($d.minerCountCurve & " miners")
  if d.vaporatorBudget == 0:
    result.add("no vaporators")
  else:
    result.add($d.vaporatorBudget & " vaporators")
  case d.droneRole
  of drHarass: result.add("drones harass")
  of drWall: result.add("drones wall")
  of drBuster: result.add("drones bust walls")
  of drCarryLandscapers: result.add("drones ferry landscapers")
  if d.netGunRing == 0:
    result.add("no net guns")
  else:
    result.add($d.netGunRing & " net guns")

proc landscaperTarget*(d: Doctrine20, round: int): int =
  ## `hq.nim` / `designschool.nim`: `4 + round/220`, scaled 0.6 / 1.0 / 1.7 by
  ## `landscaper_count_curve` and capped at 40.
  let base = 4.0 + float(round) / 220.0
  let scale = case d.landscaperCountCurve
              of ccLean: 0.6
              of ccSteady: 1.0
              of ccSwarm: 1.7
  min(40, int(base * scale))

proc minerTarget*(d: Doctrine20, round: int): int =
  ## `hq.nim`: `6 + round/300`, scaled 0.6 / 1.0 / 1.7 by `miner_count_curve`
  ## and capped at 25.
  let base = 6.0 + float(round) / 300.0
  let scale = case d.minerCountCurve
              of ccLean: 0.6
              of ccSteady: 1.0
              of ccSwarm: 1.7
  min(25, max(1, int(base * scale)))
