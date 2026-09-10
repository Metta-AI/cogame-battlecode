## The year registry. One repo, one coworld, ONE VARIANT PER BATTLECODE YEAR,
## selected by `game_config.year`.
##
## Everything year-specific lives under `years/<year>/` — constants, rules,
## cats, chassis, map pool, knob definitions and the sprite set name — behind
## a `YearSpec` registered here. Year-neutral machinery (`rng`, `sheet`,
## `decide`, `llm`, `broadcast`, `render`, `replay`, `results`, `server`)
## never branches on the year except through this table.
##
## Adding 2027 is: a new `years/bc27/` directory, a new converted map set, a
## new sprite atlas, ONE LINE here and one new manifest variant. No fork, no
## second coworld. The replay header records `year` so a viewer can never
## mis-derive an old recording.

import std/strutils
import ../sim_types

type
  YearSpec* = object
    id*: string
    title*: string
    maxRounds*: int
    pools*: seq[string]
    atlas*: string

const Years* = [
  YearSpec(id: "bc26", title: "Battlecode 2026 — Uneasy Alliances",
           maxRounds: 2000, pools: @["small", "mixed", "large"],
           atlas: "atlas"),
  YearSpec(id: "bc20", title: "Battlecode 2020 — Soup",
           maxRounds: 1500, pools: @["small", "mixed", "large"],
           atlas: "atlas_bc20"),
  YearSpec(id: "bc21", title: "Battlecode 2021 — Campaign",
           maxRounds: 1500, pools: @["small", "mixed", "large"],
           atlas: "atlas_bc21"),
  YearSpec(id: "bc24", title: "Battlecode 2024 — Breadwars",
           maxRounds: 2000, pools: @["small", "mixed", "large"],
           atlas: "atlas_bc24"),
  YearSpec(id: "bc25", title: "Battlecode 2025 — Chromatic Conflict",
           maxRounds: 2000, pools: @["small", "mixed", "large"],
           atlas: "atlas_bc25"),
  YearSpec(id: "bc23", title: "Battlecode 2023 — Tempest",
           maxRounds: 2000, pools: @["small", "mixed", "large"],
           atlas: "atlas_bc23"),
  YearSpec(id: "bc22", title: "Battlecode 2022 — Mutation",
           maxRounds: 2000, pools: @["small", "mixed", "large"],
           atlas: "atlas_bc22"),
  YearSpec(id: "bc16", title: "Battlecode 2016 — Zombie Invasion",
           maxRounds: 3000, pools: @["small", "mixed", "large"],
           atlas: "atlas_bc16"),
  YearSpec(id: "bc19", title: "Battlecode 2019 — Crusade",
           maxRounds: 1000, pools: @["small", "mixed", "large"],
           atlas: "atlas_bc19"),
  YearSpec(id: "bc17", title: "Battlecode 2017 — Robotic Wildlife Fund",
           maxRounds: 3000, pools: @["small", "mixed", "large"],
           atlas: "atlas_bc17")
]

proc yearSpec*(id: string): YearSpec =
  for spec in Years:
    if spec.id == id.strip().toLowerAscii():
      return spec
  var known: seq[string]
  for spec in Years: known.add(spec.id)
  raise newException(ConfigError,
    "unknown game_config.year " & id & "; registered years: " &
      known.join(", "))

proc isRegisteredYear*(id: string): bool =
  for spec in Years:
    if spec.id == id.strip().toLowerAscii():
      return true
  false
