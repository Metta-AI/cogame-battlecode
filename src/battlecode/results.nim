## The closed results document.
##
## TRIPLE-SYNC TRIPWIRE: this key set, the manifest's `results_schema` and the
## key set `tools/ci/docker_smoke.sh` asserts are the same set, and
## `tests/test_manifest.nim` fails when any one of them drifts.

import std/[json, strutils]
import sim_types, sheet, match
import years/bc26/rules

type
  SeatReport* = object
    name*: string
    alias*: string
    policyKind*: string       ## "llm" | "scripted"
    sheet*: Sheet
    decisionMs*: int
    fallback*: string         ## "" when the seat's own doctrine was used
    fallbackDetail*: string   ## the provider's own words, <= 200 runes
    brief*: string            ## the prompt payload composed for this seat

proc gamesJson(games: seq[GameOutcome]): JsonNode =
  result = newJArray()
  for g in games:
    result.add(%*{
      "map": g.mapName,
      "side": [(if g.sideAslot == 0: "A" else: "B"),
               (if g.sideAslot == 0: "B" else: "A")],
      "rounds_played": g.roundsPlayed,
      "winner": g.winnerSlot,
      "end_reason": $g.endReason,
      "cooperation_at_end": g.cooperationAtEnd,
      "backstab_round": g.backstabRound,
      "backstab_by": g.backstabBySlot,
      "cat_damage": [g.catDamage[0], g.catDamage[1]],
      "cheese_transferred": [g.cheeseTransferred[0], g.cheeseTransferred[1]],
      "kings_alive": [g.kingsAlive[0], g.kingsAlive[1]],
      "kings_built": [g.kingsBuilt[0], g.kingsBuilt[1]],
      "rats_built": [g.ratsBuilt[0], g.ratsBuilt[1]],
      "rats_alive": [g.ratsAlive[0], g.ratsAlive[1]],
      "traps_placed": [g.trapsPlaced[0], g.trapsPlaced[1]],
      "dirt_placed": [g.dirtPlaced[0], g.dirtPlaced[1]]
    })

proc resultsJson*(
  seats: array[2, SeatReport],
  games: seq[GameOutcome],
  plan: MatchPlan,
  reason: EpisodeReason,
  simSeconds, wallClockSeconds: float
): JsonNode =
  let scores = scoresFor(games)
  var wins = [0, 0]
  var points = newJArray()
  for slot in 0 .. 1:
    var perGame = newJArray()
    for g in games:
      perGame.add(%g.points[slot])
    points.add(perGame)
  for g in games:
    if g.winnerSlot >= 0: wins[g.winnerSlot] += 1

  var defaultsApplied = newJArray()
  var fallbacks = newJArray()
  var decisionMs = newJArray()
  var policyKind = newJArray()
  var names = newJArray()
  var aliases = newJArray()
  for slot in 0 .. 1:
    var applied = newJArray()
    for field in seats[slot].sheet.defaultsApplied:
      applied.add(%field)
    defaultsApplied.add(applied)
    fallbacks.add(%(if seats[slot].fallback.len > 0: 1 else: 0))
    decisionMs.add(%seats[slot].decisionMs)
    policyKind.add(%seats[slot].policyKind)
    names.add(%seats[slot].name)
    aliases.add(%seats[slot].alias)

  %*{
    "names": names,
    "aliases": aliases,
    "scores": [scores[0], scores[1]],
    "wins": wins,
    "points": points,
    "games": gamesJson(games),
    "seed": plan.seed,
    "year": plan.year,
    "policy_kind": policyKind,
    "sheet_defaults_applied": defaultsApplied,
    "fallbacks": fallbacks,
    "decision_ms": decisionMs,
    "sim_seconds": simSeconds,
    "reason": $reason,
    "wall_clock_seconds": wallClockSeconds,
    "game_version": GameVersion
  }

const ResultsKeys* = [
  "names", "aliases", "scores", "wins", "points", "games", "seed", "year",
  "policy_kind", "sheet_defaults_applied", "fallbacks", "decision_ms",
  "sim_seconds", "reason", "wall_clock_seconds", "game_version"
]
  ## The closed key set. `tests/test_manifest.nim` asserts this equals the
  ## manifest's `results_schema.required` and the list `docker_smoke.sh`
  ## checks.

const GameKeys* = [
  "map", "side", "rounds_played", "winner", "end_reason",
  "cooperation_at_end", "backstab_round", "backstab_by", "cat_damage",
  "cheese_transferred", "kings_alive", "kings_built", "rats_built",
  "rats_alive", "traps_placed", "dirt_placed"
]

const EpisodeReasons* = ["complete", "deadline", "fault"]
