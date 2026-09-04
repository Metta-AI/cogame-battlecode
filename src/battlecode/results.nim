## The closed results document.
##
## TRIPLE-SYNC TRIPWIRE: this key set, the manifest's `results_schema` and the
## key set `tools/ci/docker_smoke.sh` asserts are the same set, and
## `tests/test_manifest.nim` fails when any one of them drifts.

import std/json
import sim_types, sheet, match

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
    chassis*: string          ## D1: fixed by the operator, never a sheet field

proc gamesJson(games: seq[GameOutcome]): JsonNode =
  ## The five YEAR-NEUTRAL keys are always present and always required; the
  ## year's own statistics ride beside them as optional siblings. Deliberately
  ## NOT a nested `stats` object: nesting would change the bytes every shipped
  ## bc26 replay's `result` block carries and force a compatibility shim in the
  ## endcard. Relaxing `required` changes nothing that already exists.
  result = newJArray()
  for g in games:
    var entry = %*{
      "map": g.mapName,
      "side": [(if g.sideAslot == 0: "A" else: "B"),
               (if g.sideAslot == 0: "B" else: "A")],
      "rounds_played": g.roundsPlayed,
      "winner": g.winnerSlot,
      "end_reason": g.endReason
    }
    if g.stats != nil and g.stats.kind == JObject:
      for key, value in g.stats:
        entry[key] = value
    result.add(entry)

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

const RequiredGameKeys* = [
  "map", "side", "rounds_played", "winner", "end_reason"
]
  ## The year-neutral keys `results.games[].required` names.

const Bc26GameKeys* = [
  "cooperation_at_end", "backstab_round", "backstab_by", "cat_damage",
  "cheese_transferred", "kings_alive", "kings_built", "rats_built",
  "rats_alive", "traps_placed", "dirt_placed"
]

const Bc20GameKeys* = [
  "hq_alive", "hq_lost_round", "hq_lost_cause", "soup_mined", "soup_refined",
  "net_worth", "units_alive", "units_built", "miners_built",
  "landscapers_built", "drones_built", "vaporators_built", "net_guns_built",
  "dirt_moved", "drone_pickups", "drone_water_drops", "net_gun_kills",
  "transactions_sent", "transactions_minted", "blockchain_soup_spent",
  "global_pollution_peak", "flooded_tiles_end", "water_level_end"
]

const Bc21GameKeys* = [
  "centers_owned", "centers_captured", "centers_lost", "neutrals_captured",
  "votes", "bids_placed", "bid_influence_spent", "top_bid", "influence_spent",
  "influence_end", "income_end", "units_built", "politicians_built",
  "slanderers_built", "muckrakers_built", "units_alive", "politicians_alive",
  "slanderers_alive", "muckrakers_alive", "empowers", "empower_conviction",
  "conversions", "exposes", "buff_peak", "camouflaged", "robots_lost",
  "votes_tied", "rounds_no_bid"
]
  ## bc21 REUSES `units_built` and `units_alive`, which already exist with the
  ## same meaning and type; the rest are new optional siblings.

const EndReasons* = [
  "kings_destroyed", "cats_cleared", "round_limit", "abandoned",
  "hq_destroyed", "quantity", "quality", "broadcasts", "highest_id",
  "coin_flip", "annihilated", "more_votes", "more_enlightenment_centers",
  "more_influence"
]
  ## The union of all three years' `DominationFactor` renderings plus our own
  ## wall-clock `abandoned`.

const ResultsKeys* = [
  "names", "aliases", "scores", "wins", "points", "games", "seed", "year",
  "policy_kind", "sheet_defaults_applied", "fallbacks", "decision_ms",
  "sim_seconds", "reason", "wall_clock_seconds", "game_version"
]
  ## The closed key set. `tests/test_manifest.nim` asserts this equals the
  ## manifest's `results_schema.required` and the list `docker_smoke.sh`
  ## checks.

const GameKeys* = @RequiredGameKeys & @Bc26GameKeys
  ## The key set a bc26 game emits, unchanged: the five required keys plus
  ## bc26's eleven. `tests/test_manifest.nim` checks both years against the
  ## manifest's `results_schema`.

const EpisodeReasons* = ["complete", "deadline", "fault"]
