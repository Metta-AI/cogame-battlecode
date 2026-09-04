## The decision layer: ONE sealed, simultaneous doctrine turn per episode.
##
## Both seats are asked at the same moment and their two provider calls go out
## as ONE PARALLEL BATCH (`curly.makeRequests`, coworld-ctf's `decide.nim`
## shape) with the same deadline. Seats are never queried one after another.
##
## DEGRADE, NEVER HANG. Every wait is bounded: attempt 1 gets `attempt1Ms`,
## the single retry gets `retryMs`, and the whole phase is wrapped in a
## monotonic `doctrineBudgetMs` deadline. A provider throttle with no other
## candidate model skips the retry outright (it cannot land). On a second
## failure the seat plays its scripted doctrine and a `doctrine_fallback`
## event names the cause. No failure mode leaves a seat without a doctrine.

import std/[json, monotimes, strutils, times]
import curly
import sim_types, sheet, baselines, llm, match
import years/bc26/maps

type
  SeatPolicy* = object
    ## What one seat registered as. A seat that registers with neither field
    ## — or never registers at all — is `awu`.
    isLlm*: bool
    prompt*: string
    baseline*: Baseline
    label*: string
    registered*: bool

  DecisionResult* = object
    sheets*: array[2, Sheet]
    decisionMs*: array[2, int]
    fallback*: array[2, string]
    fallbackDetail*: array[2, string]
      ## The provider's own last words for this seat, one line, capped at
      ## `MaxFallbackDetailRunes`. Recorded in the replay beside the one-word
      ## cause so a fallback can be read after the fact.
    briefs*: array[2, string]
      ## The prompt payload composed for this seat, verbatim — the "observation"
      ## of a game whose decisions are taken server-side. Recorded in the replay.
    policyKind*: array[2, string]
    events*: seq[MatchEvent]

const SystemPreamble* = """
You command a clan of robot rats in Battlecode 2026, "Uneasy Alliances": a
two-clan grid war on a symmetric map, 2000 rounds a game, best of three.

You do not move a single rat. Before the war you write ONE DOCTRINE — a JSON
sheet of named knobs — and a deterministic simulation then plays the whole
match from it while you watch.

THE WORLD
- Each clan starts with one 3x3 RAT KING (600 hp). A king eats 2 cheese every
  round and loses 10 hp a round when the bank is empty. Losing every rat king
  loses the game outright.
- Baby rats (100 hp) forage cheese from mines, bite, dig and place dirt, lay
  rat traps and cat traps, ratnap and throw each other. Four rats in a ring
  can be crowned into a new king for 50 cheese; five kings maximum, dropping
  to two after round 1200.
- Cheese mines spawn 20 cheese on symmetric pairs of tiles. Income is roughly
  half a cheese per round per clan: an over-built roster starves its own
  crowns about sixty rounds later.
- Neutral NPC CATS (4000 hp) patrol waypoints, chase rats, pounce and scratch
  for 20. They are the shared enemy while the alliance holds.

THE MOTIVE
Both clans start in COOPERATION and the points formula is cat-damage
weighted. The moment either clan takes a hostile action against the other —
a bite, a ratnap, a throw, or the victim walking into your rat trap — the
world flips to BACKSTAB and the formula reweights toward king survival.
  cooperation: points = int(50 * cat-damage share + 30 * king share + 20 * cheese share)
  backstab:    points = int(30 * cat-damage share + 50 * king share + 20 * cheese share)
Winning a game is worth 100; points are worth at most 100 and the two clans'
points sum to about 100. So the game bonus dominates, and killing every enemy
king wins outright. Cat traps cannot be placed after a backstab unless you
were the victim, and then only for 100 rounds.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; you cannot forfeit by answering badly, only by answering weakly):
  chassis                "awu" | "scaffold"                      default "awu"
  backstab_policy        "never" | "when_ahead" | "at_round_N"
                         | "on_first_contact" | "retaliate_only" default "retaliate_only"
  backstab_round         1..2000 (read only for at_round_N)      default 600
  cat_engagement         "avoid" | "opportunistic" | "hunt" | "feed"
                                                                  default "opportunistic"
  cat_trap_budget        0..200                                   default 40
  rat_trap_budget        0..200                                   default 60
  spawn_curve            "lean" | "steady" | "swarm"              default "steady"
  cheese_ferry_ratio     0.0..1.0 (miners vs skirmishers)         default 0.5
  king_count_target      1..5                                     default 3
  dirt_wall_policy       "none" | "king_shell" | "choke"          default "king_shell"
  throw_rats_to_feed_cats  true | false                           default false
"""

proc briefFor*(
  config: GameConfig, plan: MatchPlan, slot: int
): string =
  ## Everything this seat may legitimately know: its own alias and side, all
  ## the map cards, the seed, both weight sets, the deadlines. NOT in here,
  ## ever: the opponent's doctrine, sheet, notes, motto, real player name or
  ## fallback status. Sealed and simultaneous.
  var games = newJArray()
  for g in 0 ..< plan.maps.len:
    let spec = loadMap(plan.maps[g])
    games.add(%*{
      "map": spec.name,
      "width": spec.width,
      "height": spec.height,
      "symmetry": ($spec.symmetry).replace("sym", "").toLowerAscii(),
      "cheese_mines": spec.cheeseMines.len,
      "cats": spec.catWaypointIds.len,
      "rounds": plan.maxRounds,
      "you_are": (if plan.sideAslots[g] == slot: "A" else: "B")
    })
  $(%*{
    "protocol": ProtocolId,
    "game_version": GameVersion,
    "year": plan.year,
    "slot": slot,
    "alias": aliasFor(slot),
    "opponent_alias": aliasFor(1 - slot),
    "team": (if plan.sideAslots[0] == slot: "A" else: "B"),
    "seed": plan.seed,
    "games": games,
    "scoring": {
      "cooperation": {"cat_damage": 0.5, "kings": 0.3, "cheese": 0.2},
      "backstab": {"cat_damage": 0.3, "kings": 0.5, "cheese": 0.2},
      "win_bonus_per_game": 100,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer"
    },
    "budget": {
      "attempt1_ms": config.attempt1Ms,
      "retry_ms": config.retryMs,
      "one_shot": true
    }
  })

proc decide*(
  config: GameConfig, plan: MatchPlan, seats: array[2, SeatPolicy]
): DecisionResult =
  ## The one decision turn. Returns a legal sheet for both seats no matter
  ## what the provider does.
  let client = newLlmClient(config)
  let started = getMonoTime()
  let budget = initDuration(milliseconds = max(1, config.doctrineBudgetMs))

  var open: seq[int]
  for slot in 0 .. 1:
    result.sheets[slot] = baselineSheet(seats[slot].baseline)
    result.policyKind[slot] = if seats[slot].isLlm: "llm" else: "scripted"
    if seats[slot].isLlm and not client.disabled:
      open.add(slot)
      result.events.add(ev("doctrine_requested", ms = 0, fields = %*{
        "slot": slot, "attempt": 1, "deadline_ms": config.attempt1Ms}))
    elif seats[slot].isLlm:
      ## An LLM seat that CANNOT call the provider is a FALLBACK, not a
      ## scripted policy. Recording it is what makes the two countable.
      result.fallback[slot] = "no_credentials"
      result.events.add(ev("doctrine_fallback", ms = 0, fields = %*{
        "slot": slot, "cause": "no_credentials"}))
      echo "battlecode llm: seat ", slot,
        " falling back to the scripted doctrine (no_credentials)"

  var attempt = 0
  while open.len > 0 and attempt < 2:
    if client.disabled: break
    if getMonoTime() - started >= budget:
      ## The phase budget is spent. These seats fall back with the cause that
      ## actually stopped them, and `open` is CLEARED: the tail loop below
      ## records one `doctrine_fallback` per still-open seat, so leaving them
      ## open recorded a second event for the same seat and overwrote the
      ## surviving cause with "parse" — a budget timeout that reads as a
      ## malformed reply in both the replay and the log.
      for slot in open:
        result.fallback[slot] = "timeout"
        result.events.add(ev("doctrine_fallback", ms = 0, fields = %*{
          "slot": slot, "cause": "timeout"}))
        ## "falling back" is the phrase phase 60 greps the GAME log for.
        echo "battlecode llm: seat ", slot,
          " falling back to the scripted doctrine (timeout)"
      open.setLen(0)
      break
    let deadlineMs =
      if attempt == 0: config.attempt1Ms else: config.retryMs
    var batch: RequestBatch
    for slot in open:
      var user = briefFor(config, plan, slot)
      ## The observation, as sent. `SystemPreamble` (the rules digest and the
      ## sheet schema the note's payload lists) is the same for both seats and
      ## is recorded once, at the document level.
      if result.briefs[slot].len == 0: result.briefs[slot] = user
      if attempt > 0:
        user.add("\n\nYour previous reply was not usable. Reply with ONLY " &
          "the JSON object described above, starting with '{'.")
      let request = client.requestFor(
        SystemPreamble, userMessage(seats[slot].prompt, user))
      batch.post(request.url, request.headers, request.body, $slot)
    let batchStart = getMonoTime()
    ## ONE parallel batch. curly hands the deadline to CURLOPT_TIMEOUT, whose
    ## granularity is WHOLE SECONDS, so this conversion floors — which is why
    ## the config values are all whole seconds.
    let responses = client.curl.makeRequests(batch, max(1, deadlineMs div 1000))
    let latency = (getMonoTime() - batchStart).inMilliseconds.int
    var stillOpen: seq[int]
    for position, slot in open:
      var cause = "parse"
      try:
        let text = client.textOf(responses[position].response,
          responses[position].error, batch[position].url)
        result.sheets[slot] = parseReply(text)
        result.decisionMs[slot] = latency
        result.fallback[slot] = ""
        result.events.add(ev("doctrine_received", ms = latency, fields = %*{
          "slot": slot, "attempt": attempt + 1, "latency_ms": latency,
          "defaults_applied": result.sheets[slot].defaultsApplied.len,
          "unknown_fields": result.sheets[slot].unknownFields.len}))
      except CatchableError as error:
        if responses[position].error.len > 0:
          cause = if "timeout" in responses[position].error.toLowerAscii():
                    "timeout" else: "transport"
        elif error.msg.startsWith("llm throttled"):
          cause = "throttled"
        result.fallbackDetail[slot] =
          sanitizeLine(error.msg, MaxFallbackDetailRunes)
        result.events.add(ev("doctrine_retry", ms = latency, fields = %*{
          "slot": slot, "cause": cause}))
        echo "battlecode llm: seat ", slot, " attempt ", attempt + 1,
          " failed, will retry: ", error.msg.truncateRunes(MaxFallbackDetailRunes)
        stillOpen.add(slot)
    open = stillOpen
    inc attempt
    if client.throttled and open.len > 0:
      ## FAIL FAST: the only model left answered 429, so the retry batch
      ## would be refused the same way.
      echo "battlecode llm: provider throttled with no other candidate; ",
        open.len, " seat(s) fall back"
      break

  for slot in open:
    result.sheets[slot] = baselineSheet(seats[slot].baseline)
    let cause =
      if client.disabled or client.transport == ltNone: "no_credentials"
      elif client.throttled: "throttled"
      else: "parse"
    result.fallback[slot] = cause
    result.events.add(ev("doctrine_fallback", ms = 0, fields = %*{
      "slot": slot, "cause": cause}))
    ## "falling back" is the phrase phase 60 greps the GAME log for.
    echo "battlecode llm: seat ", slot,
      " falling back to the scripted doctrine (", cause, ")"
