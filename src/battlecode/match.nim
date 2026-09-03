## The match: three games, alternating sides, one sealed doctrine per seat.
##
## Everything wall-clock-driven is recorded as ONE load-bearing record and
## applied by the SAME proc on record and on playback (`abandonAfter`), which
## is the particle-worlds 2026-08-26 scar: a `deadline` stop derived from the
## recorder's clock and re-derived from the viewer's clock is not the same
## match.

import std/[json, monotimes, strutils, times]
import sim_types, sheet
import years/bc26/[constants, maps, rules, world]

export rules, maps

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
  let count = max(1, config.gamesPerMatch)
  result.maps = drawMaps(config.pool, seed, count)
  for g in 0 ..< result.maps.len:
    result.sideAslots.add(sideAslotFor(seed, g))
    result.abandonAfter.add(-1)

proc winsNeeded*(games: int): int = games div 2 + 1

proc collectGameEvents(w: World, gameIndex: int, plan: MatchPlan,
                       events: var seq[MatchEvent]) =
  ## The engine's own event stream, filtered to the beats the chrome draws.
  ## Everything else stays in the sim; the replay re-derives it.
  for e in w.events:
    case e.kind
    of "backstab":
      let slot = if Team(e.a) == teamA: plan.sideAslots[gameIndex]
                 else: 1 - plan.sideAslots[gameIndex]
      events.add(ev("backstab", game = gameIndex, round = e.round,
        fields = %*{"by_alias": aliasFor(slot), "by_slot": slot,
                    "trigger": e.s}))
    of "king_built":
      let slot = if Team(e.b) == teamA: plan.sideAslots[gameIndex]
                 else: 1 - plan.sideAslots[gameIndex]
      events.add(ev("king_built", game = gameIndex, round = e.round,
        fields = %*{"alias": aliasFor(slot), "kings_now": e.c}))
    of "cat_fed":
      let slot = if Team(e.c) == teamA: plan.sideAslots[gameIndex]
                 else: 1 - plan.sideAslots[gameIndex]
      events.add(ev("cat_fed", game = gameIndex, round = e.round,
        fields = %*{"alias": aliasFor(slot)}))
    else: discard

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
    let spec = loadMap(plan.maps[g])
    events.add(ev("game_start", game = g, round = 0, fields = %*{
      "map": plan.maps[g],
      "width": spec.width, "height": spec.height,
      "sides": [aliasFor(plan.sideAslots[g]), aliasFor(1 - plan.sideAslots[g])]
    }))
    let (w, outcome) = playGame(spec, plan.sheets, g, plan.sideAslots[g],
      plan.maxRounds, perGame)
    collectGameEvents(w, g, plan, events)
    if outcome.aborted:
      ## The unfinished game is DISCARDED, and the round it stopped at is
      ## recorded so the viewer's re-derivation stops in the same place.
      plan.abandonAfter[g] = outcome.roundsPlayed
      reason = epDeadline
      events.add(ev("game_abandoned", game = g, round = outcome.roundsPlayed,
        fields = %*{"map": plan.maps[g]}))
      break
    outcomes.add(outcome)
    if outcome.winnerSlot >= 0:
      wins[outcome.winnerSlot] += 1
    events.add(ev("game_end", game = g, round = outcome.roundsPlayed,
      fields = %*{
        "winner_alias": (if outcome.winnerSlot >= 0:
                           aliasFor(outcome.winnerSlot) else: "nobody"),
        "winner_slot": outcome.winnerSlot,
        "end_reason": $outcome.endReason,
        "points": [outcome.points[0], outcome.points[1]],
        "cooperation_at_end": outcome.cooperationAtEnd
      }))
  (outcomes, reason)

proc scoresFor*(games: seq[GameOutcome]): array[2, float] =
  ## `100 * gamesWon + mean(gamePoints over games actually played)`.
  ## Higher is better; the 100-per-game win bonus dominates, which is what
  ## makes "losing every rat king loses the game outright" true.
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
