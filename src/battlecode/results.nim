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
  let scores = scoresFor(games, plan.year)
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
  ## `sheet_envelope` is NEW, OPTIONAL and YEAR-NEUTRAL (LEARNINGS
  ## 2026-09-08): which envelope rule `sheet.validate` had to apply to find
  ## each seat's knobs, or `""` when the payload itself was the sheet. It makes
  ## the finding machine-visible in the results document as well as on the
  ## doctrine card.
  var envelopes = newJArray()
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
    envelopes.add(%seats[slot].sheet.envelope)

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
    "sheet_envelope": envelopes,
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

const Bc24GameKeys* = [
  "flags_captured", "flags_picked_up", "flags_dropped", "flags_returned",
  "rounds_carrying", "crumbs_end", "crumbs_collected", "crumbs_spent",
  "kill_crumbs", "ducks_spawned", "ducks_jailed", "alive_end", "attacks",
  "damage_dealt", "kills", "heals", "heal_dealt", "traps_built",
  "traps_triggered", "trap_damage", "tiles_dug", "tiles_filled", "levels_end",
  "attack_levels_end", "build_levels_end", "heal_levels_end", "masteries",
  "upgrades_taken", "upgrade_first_round", "setup_flag_teleports",
  "rounds_with_any_carry"
]
  ## bc24 shares NOTHING with the other years' optional siblings: one unit
  ## type, one resource and a flag game. `setup_flag_teleports` and
  ## `rounds_with_any_carry` are the two scalars.

const Bc25GameKeys* = [
  "squares_painted", "coverage_permille", "peak_coverage_permille",
  "tiles_painted", "tiles_mopped", "tiles_overpainted", "chips_end",
  "chips_earned", "chips_spent", "paint_in_units_end", "paint_mined",
  "paint_spent", "robots_built", "soldiers_built", "splashers_built",
  "moppers_built", "robots_alive", "robots_lost", "robot_rounds_starved",
  "towers_built", "towers_upgraded", "towers_alive", "towers_lost",
  "money_towers_end", "paint_towers_end", "defense_towers_end",
  "srp_completed", "srp_active_end", "srp_rounds_active", "splash_attacks",
  "mop_swings", "tower_damage_dealt", "robot_damage_dealt", "messages_sent",
  "markers_placed", "paintable_tiles", "area_without_walls", "tiles_to_win",
  "ruins", "rounds_with_any_srp"
]
  ## bc25 shares NOTHING with the other years' optional siblings: a paint war
  ## has no flags, no crumbs and no soup. `paintable_tiles`,
  ## `area_without_walls`, `tiles_to_win`, `ruins` and `rounds_with_any_srp`
  ## are the five scalars.

const Bc23GameKeys* = [
  "islands_held_end", "islands_captured", "islands_lost",
  "rounds_holding_any_island", "longest_hold_streak", "anchors_built",
  "anchors_placed", "anchors_lost", "accelerating_anchors_placed",
  "adamantium_end", "mana_end", "elixir_end", "adamantium_mined",
  "mana_mined", "elixir_mined", "resources_thrown", "resources_banked",
  "wells_transformed", "wells_upgraded", "carriers_built",
  "launchers_built", "amplifiers_built", "destabilizers_built",
  "boosters_built", "throw_damage", "destabilize_damage", "hq_damage",
  "anchor_heals", "array_writes", "boosts_cast", "destabilizes_cast",
  "carrier_rounds_loaded", "current_rides", "first_anchor_round",
  "captured_distance_mean", "strike_distance_mean", "carrier_damage_taken",
  "launchers_built_by_400", "carriers_built_by_400",
  "islands_on_map", "islands_to_win", "headquarters_per_side",
  "cloud_tiles", "current_tiles", "wells_total"
]
  ## bc23's own optional siblings. It REUSES `units_built`, `damage_dealt`,
  ## `robots_alive` and `robots_lost` from bc20/bc24/bc25 rather than
  ## duplicating them -- same meaning, same type -- and everything else is
  ## its own. `islands_on_map`, `islands_to_win`, `headquarters_per_side`,
  ## `cloud_tiles`, `current_tiles` and `wells_total` are the six scalars.

const Bc22GameKeys* = [
  "archons_start", "archons_end", "archons_lost", "archon_relocations",
  "lead_mined", "gold_mined", "lead_end", "gold_end", "lead_net_worth_end",
  "gold_net_worth_end", "lead_reclaimed", "gold_reclaimed",
  "squares_mined_dry", "miners_built", "builders_built", "soldiers_built",
  "sages_built", "labs_built", "labs_finished", "watchtowers_built",
  "watchtowers_finished", "mutations_l2", "mutations_l3", "transmutes",
  "gold_transmuted", "lead_spent_transmuting", "repairs", "hp_repaired",
  "envisions", "sage_damage", "soldier_damage", "watchtower_damage",
  "array_writes", "transforms", "rounds_with_a_lab",
  "anomaly_losses_charge", "anomaly_losses_fury_hp",
  "anomaly_losses_abyss_lead", "anomalies_dodged",
  "archons_per_side", "lead_on_map_start", "lead_on_map_end",
  "lead_squares_start", "rubble_mean", "anomalies_scheduled",
  "vortexes_scheduled", "singularity_round"
]
  ## bc22's own optional siblings. It REUSES `units_built`, `damage_dealt`,
  ## `robots_alive` and `robots_lost` from bc20/bc23/bc24/bc25 rather than
  ## duplicating them -- same meaning, same type -- and everything else is its
  ## own. `archons_per_side`, `lead_on_map_start`, `lead_on_map_end`,
  ## `lead_squares_start`, `rubble_mean` (IN TENTHS, so the document carries an
  ## integer), `anomalies_scheduled`, `vortexes_scheduled` and
  ## `singularity_round` are the eight scalars.

const Bc16GameKeys* = [
  "archon_health_end_tenths", "parts_end_tenths", "parts_worth_end",
  "parts_collected_tenths", "parts_income_tenths", "parts_spent_tenths",
  "scouts_built", "guards_built", "vipers_built", "turrets_built",
  "turret_packs", "robots_turned", "neutrals_activated",
  "neutral_archons_activated", "dens_destroyed", "den_damage_dealt",
  "zombie_damage_dealt", "zombie_damage_taken", "enemy_damage_dealt",
  "enemy_damage_taken", "infections_suffered", "infections_inflicted",
  "viper_infection_damage", "rubble_cleared_tenths", "rubble_created_tenths",
  "squares_opened", "basic_signals", "message_signals", "archon_parts_walks",
  "archons_alive_at_2000",
  "dens_per_side", "dens_on_map", "parts_on_map_start", "parts_squares_start",
  "rubble_mean_tenths", "impassable_squares_start", "impassable_squares_end",
  "neutrals_on_map_start", "zombies_spawned", "zombies_alive_end",
  "zombies_killed", "outbreak_level_end", "schedule_rounds", "tiebreak_round"
]
  ## bc16's own optional siblings. It REUSES TEN keys that already exist with
  ## the same meaning and the same type rather than duplicating them, and those
  ## ten are deliberately NOT in this list: `units_built`, `damage_dealt`,
  ## `robots_alive` and `robots_lost` (bc20/bc23/bc24/bc25), and
  ## `archons_start`, `archons_end`, `archons_lost`, `archons_per_side`,
  ## `soldiers_built`, `repairs` and `hp_repaired` (bc22 -- 2016 and 2022 are
  ## the two archon years and mean exactly the same thing by all of them).
  ## `dens_per_side`, `dens_on_map`, `parts_on_map_start`,
  ## `parts_squares_start`, `rubble_mean_tenths` (IN TENTHS, so the document
  ## carries an integer), `impassable_squares_start`, `impassable_squares_end`,
  ## `neutrals_on_map_start`, `zombies_spawned`, `zombies_alive_end`,
  ## `zombies_killed`, `outbreak_level_end`, `schedule_rounds` and
  ## `tiebreak_round` are the fourteen scalars.

const EndReasons* = [
  "kings_destroyed", "cats_cleared", "round_limit", "abandoned",
  "hq_destroyed", "quantity", "quality", "broadcasts", "highest_id",
  "coin_flip", "annihilated", "more_votes", "more_enlightenment_centers",
  "more_influence", "capture", "more_flag_captures", "level_sum",
  "more_bread", "paint_enough_area", "destroy_all_units",
  "more_squares_painted", "more_towers_alive", "more_money",
  "more_paint_in_units", "more_robots_alive",
  "conquest", "more_sky_islands", "more_reality_anchors",
  "more_elixir_net_worth", "more_mana_net_worth",
  "more_adamantium_net_worth",
  "more_archons", "more_gold_net_worth", "more_lead_net_worth",
  "archons_destroyed", "more_archon_health", "more_parts_net_worth"
]
  ## The union of all SIX years' `DominationFactor` renderings plus our own
  ## wall-clock `abandoned`. bc24's `MORE_FLAGS_PICKED` and `RESIGNATION` are
  ## deliberately absent: the first is unreachable in the engine's own
  ## `checkEndOfMatch` and the second has no action a doctrine can produce
  ## (docs/RULES-BC24.md section Divergences item 5). bc25's `RESIGNATION` is
  ## absent for the same reason and is recorded as UNREACHABLE HERE rather
  ## than ABSENT UPSTREAM (docs/RULES-BC25.md section Divergences item 6);
  ## `coin_flip` is bc25's `WON_BY_DUBIOUS_REASONS` and already present.
  ## bc23's six are the last row: `resignation` is absent (unreachable from a
  ## JSON doctrine) and bc23 contributes no `destroy_all_units`, because THERE
  ## IS NO ELIMINATION CONDITION in the 2023 rule set at all
  ## (docs/RULES-BC23.md section Divergences item 7).
  ##
  ## bc16 adds EXACTLY THREE -- `archons_destroyed` (`DESTROYED`),
  ## `more_archon_health` (`OWNED`) and `more_parts_net_worth`
  ## (`BARELY_BEAT`) -- and REUSES `more_archons` (bc22's `PWNED`, the same
  ## words), `highest_id` (bc20's `WON_BY_DUBIOUS_REASONS`) and `abandoned`.
  ## `annihilated` is deliberately NOT reused for `DESTROYED` even though the
  ## semantics match bc21's and bc22's, because docs/RULES-BC2x.md already
  ## documents `annihilated` as THOSE years' factor and a bc16 replay must
  ## trace to `DESTROYED`. `zombified` and `cleansed` are NOT added: both are
  ## reachable only on armageddon maps, which are out of scope (bc16 V4).

const ResultsKeys* = [
  "names", "aliases", "scores", "wins", "points", "games", "seed", "year",
  "policy_kind", "sheet_defaults_applied", "sheet_envelope", "fallbacks",
  "decision_ms", "sim_seconds", "reason", "wall_clock_seconds", "game_version"
]
  ## The closed key set. `tests/test_manifest.nim` asserts this equals the
  ## manifest's `results_schema.required` and the list `docker_smoke.sh`
  ## checks.

const GameKeys* = @RequiredGameKeys & @Bc26GameKeys
  ## The key set a bc26 game emits, unchanged: the five required keys plus
  ## bc26's eleven. `tests/test_manifest.nim` checks both years against the
  ## manifest's `results_schema`.

const EpisodeReasons* = ["complete", "deadline", "fault"]
