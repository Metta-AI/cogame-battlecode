## The match: three games, alternating sides, one sealed doctrine per seat.
##
## YEAR-NEUTRAL. The games are played through `years/dispatch.nim`, which is
## the only module that names a year's world; the beats collected below are
## mapped from the year's own event stream by kind, so a new year adds event
## kinds and nothing here changes shape.
##
## Everything wall-clock-driven is recorded as ONE load-bearing record and
## applied by the SAME proc on record and on playback (`abandonAfter`), which
## is the particle-worlds 2026-08-26 scar: a `deadline` stop derived from the
## recorder's clock and re-derived from the viewer's clock is not the same
## match.

import std/[json, monotimes, strutils, times]
import sim_types, sheet
import years/dispatch

export dispatch

type
  MatchEvent* = object
    ## One replay event. Pre-match events carry `ms`; in-match events carry
    ## `game` and `round`.
    kind*: string
    ms*: int
    game*: int
    round*: int
    fields*: JsonNode

  MatchPlan* = object
    ## Everything needed to re-derive the whole match in the browser.
    seed*: int
    year*: string
    maps*: seq[string]
    sideAslots*: seq[int]
    sheets*: array[2, Sheet]
    chassis*: array[2, ScriptedChassis]
      ## Which chassis each SEAT drives. Never a sheet field (D1): it comes
      ## from `PLAYER_SCRIPTED`, or is the fixed champion chassis.
    maxRounds*: int
    ## The wall-clock stop, RECORDED: round `abandonAfter[g]` is the last
    ## round game `g` played. -1 means the game ran to its own end.
    abandonAfter*: seq[int]

  MatchOutcome* = object
    plan*: MatchPlan
    games*: seq[GameOutcome]
    events*: seq[MatchEvent]
    reason*: EpisodeReason
    simSeconds*: float

proc ev*(kind: string, game = -1, round = -1, ms = -1,
         fields: JsonNode = nil): MatchEvent =
  MatchEvent(kind: kind, ms: ms, game: game, round: round,
    fields: (if fields == nil: newJObject() else: fields))

proc toJson*(e: MatchEvent): JsonNode =
  result = newJObject()
  result["kind"] = %e.kind
  if e.ms >= 0: result["ms"] = %e.ms
  if e.game >= 0: result["game"] = %e.game
  if e.round >= 0: result["round"] = %e.round
  for key, value in e.fields:
    result[key] = value

func intOrZero(text: string): int =
  ## The event stream's `s` field carries a few packed integers; a malformed
  ## one is a zero, never an exception.
  try: parseInt(text) except CatchableError: 0

proc buildPlan*(config: GameConfig, sheets: array[2, Sheet],
                seed: int): MatchPlan =
  result.seed = seed
  result.year = config.year
  result.maxRounds = config.maxRounds
  result.sheets = sheets
  result.chassis = [strongChassisFor(config.year),
                    strongChassisFor(config.year)]
  let count = max(1, config.gamesPerMatch)
  result.maps = drawMapsFor(config.year, config.pool, seed, count)
  for g in 0 ..< result.maps.len:
    result.sideAslots.add(sideAslotFor(config.year, seed, g))
    result.abandonAfter.add(-1)

proc winsNeeded*(games: int): int = games div 2 + 1

proc aliasOfTeam(plan: MatchPlan, gameIndex, teamOrdinal: int): string =
  ## `teamOrdinal` is 0 for A and 1 for B; which SEAT that is alternates per
  ## game.
  let slot = if teamOrdinal == 0: plan.sideAslots[gameIndex]
             else: 1 - plan.sideAslots[gameIndex]
  aliasFor(slot)

proc collectGameEvents(
  raw: seq[tuple[round: int, kind: string, a, b, c: int, s: string]],
  gameIndex: int, plan: MatchPlan, events: var seq[MatchEvent]
) =
  ## The year's own event stream, filtered to the beats the chrome draws.
  ## Everything else stays in the sim; the replay re-derives it.
  var firstBuildSeen: seq[string]
  for e in raw:
    case e.kind
    of "anchor_built":
      events.add(ev("anchor_built", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "anchor": Bc23AnchorNames[e.b], "total_held": e.c}))
    of "island_captured":
      ## `e.s` carries `<anchorOrdinal>:<tiles>:<islandsToWin>`, so the feed
      ## line can say "9 of the 15 it needs" without the viewer re-deriving
      ## the float32 threshold.
      let parts = e.s.split(':')
      var anchorOrd = 0
      var tiles = 0
      var toWin = 0
      if parts.len > 0: anchorOrd = intOrZero(parts[0])
      if parts.len > 1: tiles = intOrZero(parts[1])
      if parts.len > 2: toWin = intOrZero(parts[2])
      events.add(ev("island_captured", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "island": e.b, "held_now": e.c,
                    "anchor": Bc23AnchorNames[max(0, min(2, anchorOrd))],
                    "tiles": tiles, "to_win": toWin}))
    of "island_lost":
      events.add(ev("island_lost", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "island": e.b, "held_for": e.c,
                    "held_now": intOrZero(e.s)}))
    of "conquest_progress":
      events.add(ev("conquest_progress", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "held": e.b, "to_win": e.c}))
    of "well_transformed":
      events.add(ev("well_transformed", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "from": Bc23ResourceNames[e.c],
                    "poured": 600}))
    of "well_upgraded":
      events.add(ev("well_upgraded", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "type": Bc23ResourceNames[e.c], "rate": 3}))
    of "first_elixir_unit":
      events.add(ev("first_elixir_unit", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "unit": Bc23ElixirUnitNames[e.b]}))
    of "boost_field":
      events.add(ev("boost_field", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100, "stacks": e.c}))
    of "destabilize_hit":
      events.add(ev("destabilize_hit", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "victims": 1, "damage": e.c}))
    of "tree_planted":
      events.add(ev("tree_planted", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": float(e.b div 100000) / 10.0,
                    "y": float(e.b mod 100000) / 10.0,
                    "trees": e.c}))
    of "tree_lost":
      events.add(ev("tree_lost", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": float(e.b div 100000) / 10.0,
                    "y": float(e.b mod 100000) / 10.0,
                    "trees": e.c, "cause": e.s}))
    of "farm_online":
      events.add(ev("farm_online", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "mature_trees": e.b, "income_tenths": e.c}))
    of "gardener_lost":
      events.add(ev("gardener_lost", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": float(e.b div 100000) / 10.0,
                    "y": float(e.b mod 100000) / 10.0,
                    "gardeners_left": e.c}))
    of "donation":
      events.add(ev("donation", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "bullets_tenths": e.b,
                    "vp_gained": e.c div 100000,
                    "vp_total": e.c mod 100000,
                    "price_tenths": intOrZero(e.s)}))
    of "shake":
      events.add(ev("shake", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "bullets_tenths": e.b,
                    "x": float(e.c div 100000) / 10.0,
                    "y": float(e.c mod 100000) / 10.0}))
    of "chop_reveal":
      events.add(ev("chop_reveal", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": float(e.b div 100000) / 10.0,
                    "y": float(e.b mod 100000) / 10.0,
                    "unit": e.s}))
    of "strike":
      events.add(ev("strike", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "enemy_hit": e.b div 1000,
                    "friendly_hit": e.b mod 1000,
                    "trees_hit": e.c div 1000,
                    "own_trees_hit": e.c mod 1000,
                    "at": e.s}))
    of "volley":
      events.add(ev("volley", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "bullets_fired": e.b, "shape": e.s}))
    of "duel":
      ## `lost` is a 2-array in TEAM order (A then B), mapped to seat order by
      ## the game's own side assignment.
      let aSlot = plan.sideAslots[gameIndex]
      var lost = [0, 0]
      lost[aSlot] = e.a
      lost[1 - aSlot] = e.b
      events.add(ev("duel", game = gameIndex, round = e.round,
        fields = %*{"lost": [lost[0], lost[1]]}))
    of "lab_built":
      events.add(ev("lab_built", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "finished": e.c == 1, "rate": intOrZero(e.s)}))
    of "first_sage":
      events.add(ev("first_sage", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "gold_spent_total": e.b}))
    of "watchtower_built":
      events.add(ev("watchtower_built", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "finished": e.c == 1}))
    of "mutation":
      ## `e.s` carries `<leadCost>:<goldCost>`.
      let parts = e.s.split(':')
      events.add(ev("mutation", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "target": Bc22UnitNames[max(0, min(6, e.b))],
                    "level": e.c,
                    "cost_lead": (if parts.len > 0: intOrZero(parts[0])
                                  else: 0),
                    "cost_gold": (if parts.len > 1: intOrZero(parts[1])
                                  else: 0)}))
    of "gold_milestone":
      events.add(ev("gold_milestone", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "gold_total": e.b, "rate": e.c}))
    of "anomaly_struck":
      ## `e.b` packs the two droid counts, `e.c` the two turret-HP losses and
      ## `e.s` is `<leadLostA>:<leadLostB>:<rubbleChanged>`, all in TEAM order.
      let aSlot = plan.sideAslots[gameIndex]
      var droids = [0, 0]
      droids[aSlot] = e.b div 1000
      droids[1 - aSlot] = e.b mod 1000
      var turret = [0, 0]
      turret[aSlot] = e.c div 100000
      turret[1 - aSlot] = e.c mod 100000
      let parts = e.s.split(':')
      var leadLost = [0, 0]
      if parts.len > 1:
        leadLost[aSlot] = intOrZero(parts[0])
        leadLost[1 - aSlot] = intOrZero(parts[1])
      events.add(ev("anomaly_struck", game = gameIndex, round = e.round,
        fields = %*{"type": Bc22AnomalyNames[max(0, min(3, e.a))],
                    "droids_lost": [droids[0], droids[1]],
                    "turret_hp_lost": [turret[0], turret[1]],
                    "lead_lost": [leadLost[0], leadLost[1]],
                    "rubble_changed": parts.len > 2 and parts[2] == "1"}))
    of "anomaly_dodged":
      events.add(ev("anomaly_dodged", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "type": Bc22AnomalyNames[max(0, min(3, e.b))],
                    "how": e.s, "saved": e.c}))
    of "archon_lost":
      ## bc22 carries `gold_dropped`; bc16 carries a `cause`
      ## (`zombie` | `enemy` | `infection` | `den_proximity` | `disintegrate`),
      ## which is the field a bc16 spectator actually needs. Both ride the
      ## same event kind and THE YEAR ON THE REPLAY HEADER SAYS WHICH FIELD TO
      ## READ — the same shape `rout` and `duel` already use.
      if plan.year == "bc16":
        events.add(ev("archon_lost", game = gameIndex, round = e.round,
          fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                      "archons_left": e.b, "cause": e.s}))
      else:
        events.add(ev("archon_lost", game = gameIndex, round = e.round,
          fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                      "archons_left": e.b, "gold_dropped": e.c}))
    of "archon_relocated":
      ## `e.s` carries `<rubbleBefore>:<rubbleAfter>`.
      let parts = e.s.split(':')
      events.add(ev("archon_relocated", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "from_x": e.b div 100, "from_y": e.b mod 100,
                    "to_x": e.c div 100, "to_y": e.c mod 100,
                    "rubble_before": (if parts.len > 0: intOrZero(parts[0])
                                      else: 0),
                    "rubble_after": (if parts.len > 1: intOrZero(parts[1])
                                     else: 0)}))
    of "singularity":
      ## `e.b` packs the two archon counts, `e.c` the two gold net worths and
      ## `e.s` is `<leadA>:<leadB>`, all in TEAM order.
      let aSlot = plan.sideAslots[gameIndex]
      var archons = [0, 0]
      archons[aSlot] = e.b div 100
      archons[1 - aSlot] = e.b mod 100
      var gold = [0, 0]
      gold[aSlot] = e.c div 100000
      gold[1 - aSlot] = e.c mod 100000
      let parts = e.s.split(':')
      var lead = [0, 0]
      if parts.len > 1:
        lead[aSlot] = intOrZero(parts[0])
        lead[1 - aSlot] = intOrZero(parts[1])
      events.add(ev("singularity", game = gameIndex, round = e.round,
        fields = %*{"rung": Bc22RungNames[max(0, min(5, e.a))],
                    "archons": [archons[0], archons[1]],
                    "gold": [gold[0], gold[1]],
                    "lead": [lead[0], lead[1]]}))
    of "backstab":
      events.add(ev("backstab", game = gameIndex, round = e.round,
        fields = %*{"by_alias": plan.aliasOfTeam(gameIndex, e.a),
                    "by_slot": (if e.a == 0: plan.sideAslots[gameIndex]
                                else: 1 - plan.sideAslots[gameIndex]),
                    "trigger": e.s}))
    of "king_built":
      events.add(ev("king_built", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.b),
                    "kings_now": e.c}))
    of "cat_fed":
      events.add(ev("cat_fed", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.c)}))
    of "flood_stage":
      events.add(ev("flood_stage", game = gameIndex, round = e.c,
        fields = %*{"level": e.a, "flooded_tiles": e.b}))
    of "first_build":
      let key = $e.a & ":" & $e.b
      if key in firstBuildSeen: continue
      firstBuildSeen.add(key)
      ## `first_build.unit` has a DOCUMENTED VOCABULARY in every year (the
      ## r1-F14 lesson): the year's own `RobotKind` ordinals, spelled out.
      let unit =
        if plan.year == "bc21": Bc21UnitNames[e.b] else: Bc20UnitNames[e.b]
      events.add(ev("first_build", game = gameIndex, round = e.c,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "unit": unit}))
    of "center_taken":
      events.add(ev("center_taken", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "from": e.s,
                    "x": e.c div 100, "y": e.c mod 100,
                    "influence": e.b}))
    of "vote_lead":
      events.add(ev("vote_lead", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "votes": e.b, "opponent_votes": e.c}))
    of "bid_spike":
      events.add(ev("bid_spike", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "bid": e.b, "influence_before": e.c}))
    of "expose_wave":
      events.add(ev("expose_wave", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "exposed_total": e.b,
                    "buff_pct": float(e.c) / 10.0}))
    of "empower_big":
      events.add(ev("empower_big", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "conviction": e.b, "victims": e.c,
                    "converted": e.s}))
    of "annihilated":
      events.add(ev("annihilated", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a)}))
    of "wall_closed":
      events.add(ev("wall_closed", game = gameIndex, round = e.c,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "min_ring_elevation": e.b}))
    of "rush_launched":
      events.add(ev("rush_launched", game = gameIndex, round = e.c,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "units": e.b}))
    of "setup_end":
      ## "The dam falls." `teleported` is how many clans failed the six-tile
      ## spacing rule and had all three of their flags sent home.
      events.add(ev("setup_end", game = gameIndex, round = e.round,
        fields = %*{"traps": [e.b, e.c], "teleported": e.a}))
    of "first_action":
      ## `first_action.action` names the ACTION, not the unit: bc24 has one
      ## unit type, and an event field with an undocumented vocabulary is an
      ## event field nobody can draw (the r1-F14 lesson).
      ##
      ## THE FIELD IS `action`, NOT THE DESIGN NOTE'S `kind`. `MatchEvent`
      ## flattens `fields` into the same object as the event's own `kind` key,
      ## so a field called `kind` SILENTLY OVERWRITES THE EVENT KIND and the
      ## replay comes back carrying events of kind "move" and "spawn".
      ## bc20 and bc21 avoided it by calling their field `unit`; bc24 calls
      ## its field `action`.
      let action =
        if plan.year == "bc25": Bc25ActionNames[e.b]
        elif plan.year == "bc23": Bc23ActionNames[e.b]
        elif plan.year == "bc22": Bc22ActionNames[e.b]
        elif plan.year == "bc16": Bc16ActionNames[e.b]
        elif plan.year == "bc19": Bc19ActionNames[max(0, min(7, e.b))]
        elif plan.year == "bc17": Bc17ActionNames[max(0, min(15, e.b))]
        else: Bc24ActionNames[e.b]
      events.add(ev("first_action", game = gameIndex, round = e.c,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "action": action}))
    of "flag_taken":
      events.add(ev("flag_taken", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "flag": e.b, "x": e.c div 100, "y": e.c mod 100}))
    of "flag_dropped":
      events.add(ev("flag_dropped", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "flag": e.b, "x": e.c div 100, "y": e.c mod 100,
                    "cause": e.s}))
    of "flag_returned":
      events.add(ev("flag_returned", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, 1 - e.a),
                    "flag": e.b}))
    of "flag_captured":
      events.add(ev("flag_captured", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "flag": e.b, "total": e.c}))
    of "trap_wave":
      events.add(ev("trap_wave", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "triggered_total": e.b, "damage_total": e.c}))
    of "upgrade":
      events.add(ev("upgrade", game = gameIndex, round = e.c,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "upgrade": Bc24UpgradeNames[e.b]}))
    of "mastery":
      events.add(ev("mastery", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "skill": Bc24SkillNames[e.b], "level": e.c}))
    of "unit_milestone":
      ## bc16, bc19 AND bc17. The first of each buildable type per side, so a
      ## spectator sees "Clan Ash commissions its first PREACHER" rather
      ## than a census that moved. The three years have DIFFERENT unit
      ## vocabularies -- twelve values, six and six -- so the table is chosen
      ## by the year on the replay header.
      let unitName =
        if plan.year == "bc19": Bc19UnitNames[max(0, min(5, e.b))]
        elif plan.year == "bc17": Bc17UnitNames[max(0, min(5, e.b))]
        else: Bc16UnitNames[max(0, min(11, e.b))]
      events.add(ev("unit_milestone", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "unit": unitName,
                    "total": e.c}))
    of "rout":
      ## bc24 spells the count `jailed` (its ducks go to jail); bc25 spells it
      ## `lost` (its robots die). Both ride the same event kind and the year
      ## on the replay header says which field to read. bc16 spells it `lost`
      ## too, and its threshold is its own (five robots in one round).
      if plan.year == "bc25" or plan.year == "bc23" or plan.year == "bc22" or
          plan.year == "bc16" or plan.year == "bc19":
        events.add(ev("rout", game = gameIndex, round = e.round,
          fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                      "lost": e.b}))
      else:
        events.add(ev("rout", game = gameIndex, round = e.round,
          fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                      "jailed": e.b}))
    of "tower_built":
      events.add(ev("tower_built", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "tower": Bc25TowerNames[e.b],
                    "x": e.c div 100, "y": e.c mod 100,
                    "total": (try: parseInt(e.s) except CatchableError: 0)}))
    of "tower_upgraded":
      events.add(ev("tower_upgraded", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "tower": Bc25TowerNames[
                      (try: parseInt(e.s) except CatchableError: 0)],
                    "level": e.b,
                    "x": e.c div 100, "y": e.c mod 100}))
    of "tower_lost":
      ## `remaining` is how many towers the clan has left, counted after the
      ## loss by the sim itself and carried on `e.s` -- the feed line is
      ## "TOWER LOST" and the number that makes it matter.
      events.add(ev("tower_lost", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "tower": Bc25TowerNames[e.b],
                    "x": e.c div 100, "y": e.c mod 100,
                    "remaining": (try: parseInt(e.s) except CatchableError: 0)}))
    of "srp_completed":
      events.add(ev("srp_completed", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100, "pending": e.c}))
    of "srp_active":
      events.add(ev("srp_active", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "active_total": (try: parseInt(e.s) except CatchableError: 0),
                    "income_bonus": e.c}))
    of "srp_broken":
      events.add(ev("srp_broken", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100, "age": e.c}))
    of "coverage":
      events.add(ev("coverage", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "permille": e.b, "tiles_from_win": e.c}))
    of "starved":
      events.add(ev("starved", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "robots": e.b}))
    of "drone_water_drop":
      ## A drone drops whatever it is holding, which may be its own unit or a
      ## neutral cow, so the victim's TEAM rides on the event (`e.s`) rather
      ## than being assumed to be the other clan.
      let victimAlias =
        case e.s
        of "0": plan.aliasOfTeam(gameIndex, 0)
        of "1": plan.aliasOfTeam(gameIndex, 1)
        else: "neutral"
      events.add(ev("drone_water_drop", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.b),
                    "victim_alias": victimAlias,
                    "victim_unit": Bc20UnitNames[e.c]}))

    # --- bc16 -------------------------------------------------------------
    of "zombie_wave":
      ## `e.s` carries `<standard>:<ranged>:<fast>:<big>` — the four counts in
      ## RobotType ordinal order, which is also `ZombieCount.compareTo`'s.
      var counts = [0, 0, 0, 0]
      let parts = e.s.split(':')
      for i in 0 .. min(3, parts.len - 1): counts[i] = intOrZero(parts[i])
      events.add(ev("zombie_wave", game = gameIndex, round = e.round,
        fields = %*{"counts": [counts[0], counts[1], counts[2], counts[3]],
                    "total": e.a, "dens_spawning": e.b,
                    "outbreak_level": e.c}))
    of "outbreak":
      events.add(ev("outbreak", game = gameIndex, round = e.round,
        fields = %*{"level": e.a, "multiplier_permille": e.b}))
    of "den_destroyed":
      ## `e.s` carries `<bounty>:<queueDeleted>`.
      let parts = e.s.split(':')
      events.add(ev("den_destroyed", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "dens_left": e.c,
                    "bounty": (if parts.len > 0: intOrZero(parts[0]) else: 0),
                    "queue_deleted": (if parts.len > 1: intOrZero(parts[1])
                                      else: 0)}))
    of "neutral_activated":
      events.add(ev("neutral_activated", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "unit": Bc16UnitNames[max(0, min(11, e.b))],
                    "x": e.c div 100, "y": e.c mod 100,
                    "total": intOrZero(e.s)}))
    of "infection":
      events.add(ev("infection", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "victim_unit": Bc16UnitNames[max(0, min(11, e.b))],
                    "source": (if e.c == 0: "viper" else: "zombie"),
                    "turns": intOrZero(e.s)}))
    of "turned":
      ## `e.s` carries `<becameName>:<outbreakLevel>`.
      let parts = e.s.split(':')
      events.add(ev("turned", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "unit": Bc16UnitNames[max(0, min(11, e.b))],
                    "became": (if parts.len > 0: parts[0] else: ""),
                    "x": e.c div 100, "y": e.c mod 100,
                    "outbreak_level": (if parts.len > 1: intOrZero(parts[1])
                                       else: 0)}))
    of "tiebreak":
      ## bc16 packs the two archon counts and parts worths; bc19 packs the
      ## two CASTLE counts, the two net worths and `<healthRed>:<healthBlue>`.
      ## Both are in TEAM order and both are re-indexed to SEAT order here.
      if plan.year == "bc19":
        let aSlot = plan.sideAslots[gameIndex]
        var castles = [0, 0]
        castles[aSlot] = e.b div 100
        castles[1 - aSlot] = e.b mod 100
        var worth = [0, 0]
        worth[aSlot] = e.c div 100000
        worth[1 - aSlot] = e.c mod 100000
        var health = [0, 0]
        let hparts = e.s.split(':')
        if hparts.len > 1:
          health[aSlot] = intOrZero(hparts[0])
          health[1 - aSlot] = intOrZero(hparts[1])
        events.add(ev("tiebreak", game = gameIndex, round = e.round,
          fields = %*{"rung": Bc19RungNames[max(0, min(4, e.a))],
                      "castles": [castles[0], castles[1]],
                      "health": [health[0], health[1]],
                      "worth": [worth[0], worth[1]]}))
        continue
      ## `e.b` packs the two archon counts, `e.c` the two parts net worths and
      ## `e.s` is `<archonHealthTenthsA>:<...B>`, all in TEAM order.
      let aSlot = plan.sideAslots[gameIndex]
      var archons = [0, 0]
      archons[aSlot] = e.b div 100
      archons[1 - aSlot] = e.b mod 100
      var worth = [0, 0]
      worth[aSlot] = e.c div 100000
      worth[1 - aSlot] = e.c mod 100000
      var hp = [0, 0]
      let parts = e.s.split(':')
      if parts.len > 1:
        hp[aSlot] = intOrZero(parts[0])
        hp[1 - aSlot] = intOrZero(parts[1])
      events.add(ev("tiebreak", game = gameIndex, round = e.round,
        fields = %*{"rung": Bc16RungNames[max(0, min(5, e.a))],
                    "archons": [archons[0], archons[1]],
                    "archon_health_tenths": [hp[0], hp[1]],
                    "parts_worth": [worth[0], worth[1]]}))
    # --- bc19 -------------------------------------------------------------
    of "church_built":
      events.add(ev("church_built", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "churches": e.c,
                    "enemy_half": intOrZero(e.s)}))
    of "church_lost":
      events.add(ev("church_lost", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "churches": e.c}))
    of "castle_lost":
      events.add(ev("castle_lost", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "x": e.b div 100, "y": e.b mod 100,
                    "castles_left": e.c, "cause": e.s}))
    of "depot_claimed":
      events.add(ev("depot_claimed", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "resource": e.s,
                    "x": e.b div 100, "y": e.b mod 100,
                    "worked": e.c}))
    of "famine":
      ## bc19 runs out of one of TWO resources and bc17 of its only one, so
      ## the resource name is chosen by the year on the replay header: a
      ## bc17 spectator must never be told a faction is out of `karbonite`.
      events.add(ev("famine", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "resource":
                      (if plan.year == "bc17": "bullets"
                       elif e.b == 0: "karbonite" else: "fuel")}))
    of "trade":
      ## The barter's sign convention is the ENGINE's: POSITIVE MEANS THE
      ## RESOURCE MOVES RED TO BLUE. The event carries the raw signed pair
      ## plus whether the matched deal was payable.
      events.add(ev("trade", game = gameIndex, round = e.round,
        fields = %*{"karbonite": e.a, "fuel": e.b, "payable": e.c}))
    of "preacher_splash":
      let parts = e.s.split(':')
      events.add(ev("preacher_splash", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "enemy_killed": e.b div 100,
                    "friendly_killed": e.b mod 100,
                    "self_damage": e.c,
                    "x": (if parts.len > 0: intOrZero(parts[0]) else: 0),
                    "y": (if parts.len > 1: intOrZero(parts[1]) else: 0)}))
    else: discard

proc bc20HqEvents(outcome: GameOutcome, gameIndex: int,
                  events: var seq[MatchEvent]) =
  ## `hq_buried` / `hq_drowned` are CHAPTER MARKERS, derived from the recorded
  ## per-game statistics rather than from a sim event, so the same two facts
  ## drive the endcard, the scrubber and `results.games[]`.
  if outcome.stats.isNil: return
  if not outcome.stats.hasKey("hq_lost_round"): return
  for slot in 0 .. 1:
    let round = outcome.stats["hq_lost_round"][slot].getInt(-1)
    if round < 0: continue
    let cause = outcome.stats["hq_lost_cause"][slot].getStr("none")
    if cause == "buried":
      events.add(ev("hq_buried", game = gameIndex, round = round,
        fields = %*{"alias": aliasFor(slot), "by_alias": aliasFor(1 - slot),
                    "dirt": 50}))
    elif cause == "drowned":
      events.add(ev("hq_drowned", game = gameIndex, round = round,
        fields = %*{"alias": aliasFor(slot),
                    "water_level": outcome.stats{"water_level_end"}.getFloat()}))

proc playMatch*(config: GameConfig, plan: var MatchPlan,
                events: var seq[MatchEvent]): (seq[GameOutcome], EpisodeReason) =
  ## Plays the planned games in order, stopping early once a seat has taken
  ## the majority. Returns the games that FINISHED plus the episode reason.
  var outcomes: seq[GameOutcome]
  var wins: array[2, int]
  var reason = epComplete
  let need = winsNeeded(plan.maps.len)
  let matchStart = getMonoTime()
  let matchBudget = initDuration(seconds = max(1, config.matchBudgetSeconds))

  for g in 0 ..< plan.maps.len:
    if wins[0] >= need or wins[1] >= need:
      break
    let elapsed = getMonoTime() - matchStart
    if elapsed >= matchBudget:
      reason = epDeadline
      break
    let remaining = (matchBudget - elapsed).inSeconds.int
    let perGame = max(1, min(config.perGameBudgetSeconds, remaining))
    let card = mapCardFor(config.year, plan.maps[g], plan.sideAslots[g],
      plan.sideAslots[g], plan.maxRounds)
    events.add(ev("game_start", game = g, round = 0, fields = %*{
      "map": plan.maps[g],
      "width": card{"width"}.getInt(), "height": card{"height"}.getInt(),
      "sides": [aliasFor(plan.sideAslots[g]), aliasFor(1 - plan.sideAslots[g])]
    }))
    let (outcome, raw) = playGameFor(config.year, plan.maps[g], plan.sheets,
      plan.chassis, g, plan.sideAslots[g], plan.maxRounds, perGame)
    collectGameEvents(raw, g, plan, events)
    if outcome.aborted:
      ## The unfinished game is DISCARDED, and the round it stopped at is
      ## recorded so the viewer's re-derivation stops in the same place.
      plan.abandonAfter[g] = outcome.roundsPlayed
      reason = epDeadline
      events.add(ev("game_abandoned", game = g, round = outcome.roundsPlayed,
        fields = %*{"map": plan.maps[g]}))
      break
    bc20HqEvents(outcome, g, events)
    outcomes.add(outcome)
    if outcome.winnerSlot >= 0:
      wins[outcome.winnerSlot] += 1
    var endFields = %*{
      "winner_alias": (if outcome.winnerSlot >= 0:
                         aliasFor(outcome.winnerSlot) else: "nobody"),
      "winner_slot": outcome.winnerSlot,
      "end_reason": outcome.endReason,
      "points": [outcome.points[0], outcome.points[1]]
    }
    if outcome.stats != nil and outcome.stats.hasKey("cooperation_at_end"):
      endFields["cooperation_at_end"] = outcome.stats["cooperation_at_end"]
    events.add(ev("game_end", game = g, round = outcome.roundsPlayed,
      fields = endFields))
  (outcomes, reason)

func winBonusFor*(year: string): float =
  ## The per-game win bonus, PER YEAR. bc26, bc20, bc21 and bc24 pay 100 and
  ## nothing about them changes.
  ##
  ## bc25 pays 200, and the difference is deliberate: `points` is a mean in
  ## [0, 100], so a 100-per-game bonus makes a 2-1 result THEORETICALLY tie on
  ## `scores` in the degenerate all-or-nothing case, while 200 makes the
  ## ordering of `results.scores` PROVABLY agree with `results.wins`.
  ## `tests/test_bc25_scoring.nim` asserts that agreement on 500 random
  ## synthetic finals — with 100 it would be a `>=`; with 200 it is a `>`.
  ## bc23 pays 200 for the same reason, and its 60/22/10/5/3 weights are
  ## strictly super-increasing so the tiebreak property is provable as well.
  ## bc22 pays 200 for the third time and for a reason of its own: its
  ## `points` can legitimately favour the LOSER on a narrow archon margin
  ## (docs/RULES-BC22.md, Scoring), so only a bonus that dominates the whole
  ## [0, 100] range keeps `results.scores` ordered with `results.wins`.
  ## bc16 pays 200 for EXACTLY bc22's reason -- it is the other archon year,
  ## its 64/24/12 weights read the same ladder, and `4/7 - 3/7 = 0.143` of 64
  ## is 9.1 points against 36 available below, so its `points` can favour the
  ## loser too (docs/RULES-BC16.md, Scoring; `tests/test_bc16_scoring.nim`
  ## asserts that case explicitly rather than leaving it to be found).
  ## bc19 pays 200 for EXACTLY bc22's and bc16's reason: its 64/24/12
  ## weights read the engine's own two deciding rungs, and a one-castle
  ## margin on a 3-vs-2 board is `3/5 - 2/5 = 0.2` of 64 = 12.8 points
  ## against 36 available below, so its `points` can favour the LOSER too
  ## (docs/RULES-BC19.md, Scoring; `tests/test_bc19_scoring.nim` asserts
  ## that case explicitly rather than leaving it to be found).
  ## bc17 pays 200 for EXACTLY that reason a fifth time: its 64/24/12 weights
  ## read the engine's own three deciding rungs, and a 501-to-499
  ## victory-point margin is `501/1000 - 499/1000 = 0.002` of 64 = 0.128 of a
  ## point against 36 available below, so its `points` can favour the LOSER
  ## too (docs/RULES-BC17.md, Scoring; `tests/test_bc17_scoring.nim` asserts
  ## that case explicitly rather than leaving it to be found).
  if yearIdOf(year) in {yBc25, yBc23, yBc22, yBc16, yBc19, yBc17}: 200.0
  else: 100.0

proc scoresFor*(games: seq[GameOutcome],
                year = "bc26"): array[2, float] =
  ## `winBonus * gamesWon + mean(gamePoints over games actually played)`.
  ## Higher is better; the win bonus dominates, which is what makes "lose the
  ## map, lose the game" true in the ranking as well as in the rules.
  if games.len == 0:
    return [0.0, 0.0]
  var wins: array[2, int]
  var pointSum: array[2, int]
  for g in games:
    if g.winnerSlot >= 0: wins[g.winnerSlot] += 1
    pointSum[0] += g.points[0]
    pointSum[1] += g.points[1]
  let bonus = winBonusFor(year)
  for slot in 0 .. 1:
    result[slot] = bonus * float(wins[slot]) +
      float(pointSum[slot]) / float(games.len)
