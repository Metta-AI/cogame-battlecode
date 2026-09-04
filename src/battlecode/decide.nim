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
import years/dispatch

type
  SeatPolicy* = object
    ## What one seat registered as. A seat that registers with neither field
    ## — or never registers at all — is `awu`.
    isLlm*: bool
    prompt*: string
    scripted*: string
      ## The raw `PLAYER_SCRIPTED` value. Resolved to a `Baseline` PER YEAR at
      ## episode time by `baselineForSeat`, because `bowl-of-chowder` means
      ## nothing to bc26 and `awu` means nothing to bc20. Storing a parsed
      ## `Baseline` on the seat would be resolving it before the year is known.
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

proc baselineForSeat*(year: string, seat: SeatPolicy): Baseline =
  if seat.scripted.len > 0: baselineFor(year, seat.scripted)
  else: defaultBaselineFor(year)

proc chassisForSeat*(year: string, seat: SeatPolicy): ScriptedChassis =
  ## D1: the chassis is fixed by the OPERATOR. A scripted seat drives the
  ## chassis its `PLAYER_SCRIPTED` names; an LLM seat drives the year's fixed
  ## champion chassis — `bowl-of-chowder` on bc20, `california-roll` on bc21.
  if seat.isLlm: strongChassisFor(year)
  else: baselineChassis(baselineForSeat(year, seat))

proc chassisNameFor*(year: string, seat: SeatPolicy, sheet: Sheet): string =
  case yearIdOf(year)
  of yBc20, yBc21:
    (if seat.isLlm: $strongChassisFor(year)
     else: baselineName(baselineForSeat(year, seat)))
  of yBc26: $sheet.doctrine.chassis

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

Your clan is driven by the `awu` chassis. That is not yours to choose: there
is no `chassis` knob, and a reply that sends one has it ignored.
"""

const Bc20Preamble* = """
You command a clan in Battlecode 2020 "Soup": a two-clan grid war on a
symmetric map where THE WATER RISES EVERY ROUND, 1500 rounds a game, best of
three.

You do not move a single robot. Before the war you write ONE DOCTRINE — a JSON
sheet of ten named knobs — and a deterministic simulation then plays the whole
match from it while you watch.

THE CLOCK IS THE WATER
- The water level rises on a fixed curve and floods outward ONE RING PER ROUND
  from every already-flooded tile whose neighbour sits below the level.
  Anything that is not a delivery drone dies on a flooding tile.
- Your HQ starts at a low elevation and CANNOT BE RAISED: dirt dropped on a
  building buries it. The only thing that keeps an HQ dry is a ring of eight
  adjacent tiles the water can never cross. An HQ that is never walled drowns
  on a schedule.

THE WORLD
- MINERS (70 soup) mine SOUP (7 per action, carry 100) and deposit it at the HQ
  or a REFINERY (200), which refines up to 20 per round into the team pool.
- DESIGN SCHOOLS (150) build LANDSCAPERS (150), which dig and dump dirt: raise
  the ground into a lattice, wall the HQ in, or bury the enemy HQ under FIFTY
  dirt. A landscaper carries 25.
- FULFILLMENT CENTERS (150) build DELIVERY DRONES (150), which pick up any unit
  within r^2 <= 3 — including enemy landscapers — and drop them in the water.
- VAPORATORS (500) print 2 soup a round and scrub pollution. NET GUNS (250)
  shoot drones within r^2 <= 15; so does the HQ.
- Pollution slows every action and shrinks every sensor. Cows pollute heavily.
- The only global channel is a blockchain: seven ints a message, seven messages
  a round, paid for in soup, and BOTH TEAMS READ EVERY BLOCK.

HOW A GAME ENDS
Round 1499, or when an HQ is buried or drowned. The ladder, first hit wins:
HQ destroyed; more robots alive (buildings included); greater net worth; more
transactions minted; highest living robot id; coin flip.
  points = int(60 * HQ-survival share + 25 * unit share + 15 * net-worth share)
Winning a game is worth 100 and points are worth at most 100, so the game bonus
dominates: lose your HQ, lose the game.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; you cannot forfeit by answering badly, only by answering weakly):
  opening                 "rush" | "lattice" | "passive_lattice" | "turtle"
                                                          default "passive_lattice"
  terraform_start_round   1..1500                          default 300
  lattice_radius          2..12                            default 6
  landscaper_count_curve  "lean" | "steady" | "swarm"      default "steady"
  miner_count_curve       "lean" | "steady" | "swarm"      default "steady"
  vaporator_budget        0..6                             default 2
  drone_role              "harass" | "wall" | "buster" | "carry_landscapers"
                                                          default "harass"
  net_gun_ring            0..6                             default 2
  rush_trigger            0..1500 (0 = never)              default 0
  wall_hq_round           0..1500 (0 = never)              default 250
"""

const Bc21Preamble* = """
You command a party in Battlecode 2021 "Campaign": a two-clan grid war on a
symmetric map where EVERY ROUND AUCTIONS ONE CITIZEN'S VOTE, 1500 rounds a
game, best of three.

You do not move a single robot. Before the war you write ONE DOCTRINE - a JSON
sheet of ten named knobs - and a deterministic simulation then plays the whole
match from it while you watch.

THE CLOCK IS THE ELECTION
- Every round each Enlightenment Center may bid influence. The single highest
  bidder IN THE GAME wins the vote for its team and pays its bid; the other
  team's top bidder pays ceil(bid/2) FOR NOTHING. Equal top bids: nobody wins,
  both pay half. At round 1500 the team with more votes wins.
- A team that loses EVERY robot loses immediately, at any round.

INFLUENCE IS THE ONLY RESOURCE, AND IT IS NOT A POOL
It sits inside each Enlightenment Center and does three incompatible jobs: it
buys units, it buys votes, and it is what an enemy politician steals when it
converts your Center. Each Center earns ceil(0.2*sqrt(round)) per round (about
8500 over a whole game) on top of its starting 150.

THE TRIANGLE
- SLANDERERS are the multiplier: one built for x influence pays its parent
  Center floor(x*(1/50 + 0.03*e^(-0.001x))) per round for its first 51 rounds
  - a ~2.35x return for x in 21..130 - and at 300 rounds old silently becomes
  a politician. It cannot act and dies to a single muckraker.
- MUCKRAKERS cost 1 influence, see furthest, and EXPOSE enemy slanderers: the
  slanderer dies and your team gets +0.001 x (that slanderer's influence) on
  every speech for 50 rounds.
- POLITICIANS are walking bombs. Empowering splits (conviction - 10) equally
  among EVERY other robot in the chosen radius (r^2 <= 9) - healing friends,
  feeding friendly Centers, converting or killing everything else - and then
  the politician dies. A Center with conviction c is captured by a politician
  of c + 11.

HOW A GAME ENDS
Round 1500, or the moment a team loses every robot. The ladder, first hit wins:
one team annihilated; more votes; more Enlightenment Centers; greater total
influence; coin flip (drawn from the map's own seed, not the wall clock).
  points = int(40*survival + 35*vote share + 15*centre share + 10*influence share)
Winning a game is worth 100 and points are worth at most 100, so the game bonus
dominates: lose the election, lose the match.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; you cannot forfeit by answering badly, only by answering weakly):
  opening                "muck_spam" | "slanderer_turtle" | "balanced"
                                                          default "balanced"
  slanderer_ratio        0..100 (% of post-opening spend) default 45
  muck_ratio             0..100 (% of post-opening spend) default 25
  politician_size_curve  "cheap" | "ramp" | "fat"         default "ramp"
  bid_policy             "never" | "fixed" | "proportional"
                         | "escalate_when_ahead"          default "proportional"
  expansion              "neutral_centers_first" | "defend_home"
                                                default "neutral_centers_first"
  flank_policy           "screen_home" | "hunt_slanderers" | "flank_wide"
                                                   default "hunt_slanderers"
  empower_threshold      0..300 (percent)                 default 60
  convert_over_kill      true | false                     default true
  eco_exponential_round  1..1500                          default 700

Politicians take 100 - slanderer_ratio - muck_ratio. If the two sum above 100
they are renormalised. Your party is driven by the `california-roll` chassis.
That is not yours to choose: there is no `chassis` knob, and a reply that sends
one has it ignored.
"""

proc preambleFor*(year: string): string =
  case yearIdOf(year)
  of yBc20: Bc20Preamble
  of yBc21: Bc21Preamble
  of yBc26: SystemPreamble

proc briefFor*(
  config: GameConfig, plan: MatchPlan, slot: int
): string =
  ## Everything this seat may legitimately know: its own alias and side, all
  ## the map cards, the seed, the scoring weights, the deadlines. NOT in here,
  ## ever: the opponent's doctrine, sheet, notes, motto, real player name or
  ## fallback status. Sealed and simultaneous.
  var games = newJArray()
  for g in 0 ..< plan.maps.len:
    games.add(mapCardFor(plan.year, plan.maps[g], slot, plan.sideAslots[g],
      plan.maxRounds))
  var payload = %*{
    "protocol": ProtocolId,
    "game_version": GameVersion,
    "year": plan.year,
    "slot": slot,
    "alias": aliasFor(slot),
    "opponent_alias": aliasFor(1 - slot),
    "team": (if plan.sideAslots[0] == slot: "A" else: "B"),
    "seed": plan.seed,
    "games": games,
    "budget": {
      "attempt1_ms": config.attempt1Ms,
      "retry_ms": config.retryMs,
      "one_shot": true
    }
  }
  case yearIdOf(plan.year)
  of yBc20:
    payload["flood_table"] = floodTableJson()
    payload["scoring"] = %*{
      "weights": {"hq_survival": 60, "unit_share": 25, "net_worth_share": 15},
      "win_bonus_per_game": 100,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer"
    }
  of yBc21:
    var breakpoints = newJArray()
    for value in bc21Breakpoints():
      if breakpoints.len >= 30: break
      breakpoints.add(%value)
    payload["economy"] = %*{
      "center_passive":
        "ceil(0.2*sqrt(round)) per center per round; 8507 total over 1500 rounds",
      "center_start_influence": 150,
      "slanderer_breakpoints": breakpoints,
      "slanderer_payments": 51,
      "camouflage_round": 300,
      "expose_buff": "+0.001 x slanderer influence, for 50 rounds",
      "empower_tax": 10,
      "votes_on_offer": plan.maxRounds,
      "losing_bid_cost": "ceil(bid/2)"
    }
    payload["sheet_schema"] = bc21SheetSchema()
    payload["scoring"] = %*{
      "weights": {"survival": 40, "vote_share": 35, "center_share": 15,
                  "influence_share": 10},
      "win_bonus_per_game": 100,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer"
    }
  of yBc26:
    payload["scoring"] = %*{
      "cooperation": {"cat_damage": 0.5, "kings": 0.3, "cheese": 0.2},
      "backstab": {"cat_damage": 0.3, "kings": 0.5, "cheese": 0.2},
      "win_bonus_per_game": 100,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer"
    }
  $payload

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
    result.sheets[slot] = baselineSheet(config.year,
      baselineForSeat(config.year, seats[slot]))
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
        preambleFor(config.year), userMessage(seats[slot].prompt, user))
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
        result.sheets[slot] = parseReply(text, config.year)
        result.decisionMs[slot] = latency
        result.fallback[slot] = ""
        ## `chassis` is not a knob (sheet.KnownKeys). A reply that still sends
        ## one is already recorded in `unknownFields` and ignored — the clan
        ## runs the chassis the OPERATOR fixed — but a silent ignore is how
        ## round 1's champion came to idle three games, so the seat that tried
        ## is named in the log, along with the chassis it actually drives.
        if "chassis" in result.sheets[slot].unknownFields:
          echo "battlecode llm: seat ", slot,
            " sent `chassis`, which is not a doctrine knob: ignored, the clan",
            " runs the ",
            chassisNameFor(config.year, seats[slot], result.sheets[slot]),
            " chassis"
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
    result.sheets[slot] = baselineSheet(config.year,
      baselineForSeat(config.year, seats[slot]))
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
