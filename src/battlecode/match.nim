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

import std/[json, monotimes, times]
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
      events.add(ev("first_action", game = gameIndex, round = e.c,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "action": Bc24ActionNames[e.b]}))
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
    of "rout":
      events.add(ev("rout", game = gameIndex, round = e.round,
        fields = %*{"alias": plan.aliasOfTeam(gameIndex, e.a),
                    "jailed": e.b}))
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

proc scoresFor*(games: seq[GameOutcome]): array[2, float] =
  ## `100 * gamesWon + mean(gamePoints over games actually played)`.
  ## Higher is better; the 100-per-game win bonus dominates, which is what
  ## makes "lose your HQ, lose the game" true in the ranking as well as in the
  ## rules.
  if games.len == 0:
    return [0.0, 0.0]
  var wins: array[2, int]
  var pointSum: array[2, int]
  for g in games:
    if g.winnerSlot >= 0: wins[g.winnerSlot] += 1
    pointSum[0] += g.points[0]
    pointSum[1] += g.points[1]
  for slot in 0 .. 1:
    result[slot] = 100.0 * float(wins[slot]) +
      float(pointSum[slot]) / float(games.len)
