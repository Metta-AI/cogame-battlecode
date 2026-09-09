## Shard 23 of the note's list — **the bc16 replay document**.
##
## A round-trip; a STRICT UTF-8 PARSE of the written bytes; the viewer's
## re-derivation reproducing the recorded per-round hashes with NOTHING
## STORED (robot positions, health, types, delays, infection counters,
## `roundsAlive`, the rubble and parts arrays, the stockpiles, the signal
## queues, the den queues and all three RNG states are pure functions of the
## sim); `plan.maps` carrying all three drawn maps even when the match
## clinched in two; `seats[].sheet_envelope` and `sheet_submitted` round-
## tripping; and **every event kind respecting its per-game bound**.
##
## TWO CONVENTIONS THIS FILE OBEYS, because the repo has been bitten by both:
##
## * **never zero `perGameBudgetSeconds` in a helper.** `match.nim:480` clamps
##   it to `max(1, min(field, remaining))`, so a zeroed field silently buys a
##   ONE-SECOND budget while `years/bc16/rules.nim` one level down treats 0 as
##   unbounded — and the symptom is diagnostic: a shard that PASSES in
##   `-d:release` and FAILS in debug. The `if perGame > 0:` form below is
##   `tests/test_bc23_replay.nim:69`'s.
## * **every `games[0]` read is guarded** behind a non-empty check, so a
##   failed assertion prints a FAIL instead of an `IndexDefect` — and in
##   release, where bounds checks are off, instead of an unchecked OOB read
##   whose "pass" is not trustworthy. And every end-reason assertion is
##   TOLERANT (`in [epDeadline, epComplete]`), never strictly one of them on a
##   runner-speed-dependent shard.

import std/[json, os, strutils, tables, unicode]
import harness
import battlecode/[baselines, match, replay, results, sheet, sim_types]
import battlecode/years/dispatch
import battlecode/years/bc16/world as w16

proc sheets(): array[2, Sheet] =
  [baselineSheet("bc16", blBulwark), baselineSheet("bc16", blGreenhorn)]

type Recorded = object
  text: string
  doc: ReplayDoc
  reason: EpisodeReason
  games: seq[GameOutcome]
  mismatch: int

proc record(rounds, gamesPerMatch, seed: int, perGame = 0): Recorded =
  var config = defaultGameConfig()
  config.year = "bc16"
  config.pool = "small"
  config.gamesPerMatch = gamesPerMatch
  config.maxRounds = rounds
  ## THE CONVENTION: never zero the field. Zero here means "leave the default
  ## alone", not "unbounded", because `match.nim` clamps it to at least one
  ## second one level up.
  if perGame > 0:
    config.perGameBudgetSeconds = perGame
  config.matchBudgetSeconds = max(perGame * 4, 600)
  var plan = buildPlan(config, sheets(), seed)
  plan.chassis = [scBulwark, scGreenhorn]
  var events: seq[MatchEvent]
  events.add(ev("episode_start", ms = 0,
    fields = %*{"seed": seed, "year": "bc16", "maps": %plan.maps,
                "aliases": [AliasA, AliasB]}))
  let (games, reason) = playMatch(config, plan, events)
  events.add(ev("episode_end", ms = 1, fields = %*{"reason": $reason}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "player" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: plan.sheets[slot],
      chassis: (if slot == 0: "bulwark" else: "greenhorn"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc16",
    config: %*{"seed": seed, "year": "bc16", "max_rounds": rounds},
    seed: seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  doc.names = ["player0", "player1"]
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc16", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))
  result.text = $doc.toJson()
  result.doc = parseReplay(result.text)
  result.reason = reason
  result.games = games
  let deriver = newDeriver(result.doc)
  while deriver.advance(): discard
  result.mismatch = deriver.mismatchRound

# --- the document round-trips, and it is STRICT UTF-8 ---------------------
block:
  let r = record(500, 1, 2016004)
  checkEq("the episode completed", r.reason, epComplete)
  checkEq("and the recording re-derives with NO hash mismatch", r.mismatch, -1)
  checkEq("the bytes are STRICT UTF-8", r.text.validateUtf8(), -1)
  checkEq("the format", r.doc.year, "bc16")
  checkEq("at this GameVersion", r.doc.gameVersion, GameVersion)
  check("which is inside the compatibility list",
    GameVersion in ReplayCompatibleGameVersions)
  checkEq("the seed round-trips", r.doc.seed, 2016004)
  checkEq("both seats", r.doc.seats.len, 2)
  checkEq("and the applied sheet survives",
    r.doc.seats[0].sheet.doctrine16, defaultDoctrine16())
  check("the games were recorded", r.doc.games.len >= 1)
  if r.doc.games.len >= 1:
    checkEq("on a real map", r.doc.games[0].map, "river")
    check("with a map sha", r.doc.games[0].mapSha.len == 64)
    check("and a per-round chain", r.doc.games[0].roundChains.len > 0)

# --- NOTHING is stored: the browser re-derives everything ------------------
block:
  let r = record(400, 1, 2016004)
  let doc = parseJson(r.text)
  ## Not one per-round robot dump, per-square dump, rubble array, parts array,
  ## signal queue, den queue or RNG state is in the file. They are all pure
  ## functions of the sim, so the browser re-derives them.
  for forbidden in ["robots", "rubble", "parts", "board", "squares",
                    "signals", "den_queues", "rng", "frames", "grid"]:
    check("the replay stores no `" & forbidden & "`",
      not doc.hasKey(forbidden))
  var text = r.text
  for forbidden in ["\"rubble\":", "\"parts_grid\"", "\"occupancy\""]:
    check("and no nested `" & forbidden & "` either", forbidden notin text)
  ## The whole document for a one-game 400-round episode is small, because
  ## self-sufficiency is by RE-DERIVATION rather than by bulk.
  check("a 400-round one-game recording is under 64 KB (got " &
    $(r.text.len div 1024) & " KB)", r.text.len < 65536)

# --- the clinch shape ------------------------------------------------------
block:
  ## A best-of-three that a side takes 2-0 records TWO games with
  ## `reason: complete`, which is CORRECT and not truncated — and `plan.maps`
  ## still carries all three drawn maps so a spectator can see what the third
  ## would have been.
  let r = record(500, 3, 2016004)
  check("the reason is tolerant", r.reason in [epDeadline, epComplete])
  checkEq("plan.maps carries all THREE drawn maps", r.doc.plan.maps.len, 3)
  check("and the games actually played are two or three",
    r.doc.games.len in 2 .. 3)
  if r.doc.games.len == 2:
    checkEq("a clinched match still reports `complete`", r.reason, epComplete)
  var maps: seq[string]
  for g in r.doc.games: maps.add(g.map)
  for m in maps:
    check("every played map is one of the drawn three", m in r.doc.plan.maps)
  check("and the three drawn maps are distinct",
    r.doc.plan.maps[0] != r.doc.plan.maps[1] and
    r.doc.plan.maps[1] != r.doc.plan.maps[2] and
    r.doc.plan.maps[0] != r.doc.plan.maps[2])

# --- the envelope and the submitted sheet round-trip ----------------------
block:
  let r = record(300, 1, 2016004)
  let doc = parseJson(r.text)
  check("the seats carry sheet_envelope", doc["seats"][0].hasKey("sheet_envelope"))
  check("and sheet_submitted", doc["seats"][0].hasKey("sheet_submitted"))
  checkEq("the scripted seats answer inside a `sheet` envelope",
    doc["seats"][0]["sheet_envelope"].getStr(), "sheet")
  check("and the submitted text is the sheet node as received",
    "opening" in doc["seats"][0]["sheet_submitted"].getStr())
  check("sheet_defaults_applied is an array",
    doc["seats"][0]["sheet_defaults_applied"].kind == JArray)
  checkEq("and the baseline reply sets all eleven knobs, so nothing defaulted",
    doc["seats"][0]["sheet_defaults_applied"].len, 0)

# --- EVERY EVENT KIND RESPECTS ITS PER-GAME BOUND -------------------------
block:
  ## The design note's own table. A 3000-round match with 300 robots on the
  ## board cannot be allowed to emit an event per action, so every kind is
  ## bounded PER GAME and this is what proves it.
  const Bounds = {
    "game_start": 1, "first_action": 2, "unit_milestone": 10,
    "zombie_wave": 30, "outbreak": 10, "den_destroyed": 12,
    "neutral_activated": 20, "infection": 20, "turned": 24,
    "archon_lost": 8, "rout": 20, "duel": 20, "tiebreak": 1,
    "game_end": 1, "game_abandoned": 1,
  }.toTable
  let r = record(3000, 1, 2016004)
  check("the long episode finished", r.reason in [epDeadline, epComplete])
  checkEq("and it re-derives", r.mismatch, -1)
  var perGame = initTable[string, CountTable[int]]()
  for e in r.doc.events:
    if e.game < 0: continue
    if e.kind notin perGame: perGame[e.kind] = initCountTable[int]()
    perGame[e.kind].inc(e.game)
  for kind, counts in perGame:
    if kind notin Bounds:
      check("event kind `" & kind & "` has a documented bound", false)
      continue
    for game, n in counts:
      check("`" & kind & "` is bounded at " & $Bounds[kind] & " per game " &
        "(game " & $game & " emitted " & $n & ")", n <= Bounds[kind])
  ## `zombie_wave <= 30` against the MEASURED maximum schedule length of 29
  ## (`wormy`), which is why the bound is 30 and not 29.
  check("the schedule really produced waves",
    "zombie_wave" in perGame)
  ## And the whole event list for a three-game match stays at a few hundred
  ## entries.
  check("the event list is small (got " & $r.doc.events.len & ")",
    r.doc.events.len < 700)

# --- record -> re-derive for EVERY bc16 end reason ------------------------
block:
  ## The engine's own five, plus our wall-clock `abandoned`, each recorded and
  ## re-derived by the SAME proc — the particle-worlds scar.
  var seen: seq[string]
  for (rounds, seed) in [(3000, 2016004), (3000, 1), (3000, 7), (900, 5),
                         (400, 99), (3000, 42)]:
    let r = record(rounds, 1, seed)
    checkEq("seed " & $seed & " re-derives with no mismatch", r.mismatch, -1)
    if r.doc.games.len >= 1:
      let reason = r.doc.result{"games"}[0]{"end_reason"}.getStr()
      if reason notin seen: seen.add(reason)
  echo "bc16 end reasons exercised by the record/re-derive shard: ",
    seen.join(", ")
  check("at least two distinct end reasons were exercised", seen.len >= 2)
  for reason in seen:
    check("`" & reason & "` is a declared end reason",
      reason in EndReasons)

block:
  ## THE WALL-CLOCK STOP, built SYNTHETICALLY so no clock is involved —
  ## bc20's, bc21's and bc22's shape, and the half that proves the deadline
  ## path writes what the viewer needs on every machine, every time.
  const stopAt = 137
  var config = defaultGameConfig()
  config.year = "bc16"
  var plan = buildPlan(config, sheets(), 9)
  plan.chassis = [scBulwark, scGreenhorn]
  plan.maps = @["river"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[stopAt]
  var events: seq[MatchEvent]
  events.add(ev("game_abandoned", game = 0, round = stopAt,
    fields = %*{"map": plan.maps[0]}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: plan.sheets[slot],
      chassis: (if slot == 0: "bulwark" else: "greenhorn"))
  var abandoned = ReplayDoc(gameVersion: GameVersion, year: "bc16",
    config: %*{"year": "bc16"}, seed: 9, seats: seats, events: events,
    result: resultsJson(seats, @[], plan, epDeadline, 0.0, 0.0), plan: plan)
  abandoned.names = ["s0", "s1"]
  let text = $abandoned.toJson()
  checkEq("an abandoned recording is strict UTF-8", text.validateUtf8(), -1)
  let doc = parseJson(text)
  checkEq("`plan.abandon_after` carries the LOAD-BEARING record",
    doc["plan"]["abandon_after"][0].getInt(), stopAt)
  checkEq("and the results reason is deadline",
    doc["result"]["reason"].getStr(), "deadline")
  checkEq("with zero scores", doc["result"]["scores"][0].getFloat(), 0.0)
  ## And it re-parses.
  let back = parseReplay(text)
  checkEq("the abandoned recording re-parses", back.year, "bc16")
  checkEq("with the record intact", back.plan.abandonAfter[0], stopAt)

# --- the deadline path, TIMED, with the tolerant assertion ----------------
block:
  ## `playMatch` clamps the per-game budget to a whole number of seconds with
  ## a floor of ONE, so the smallest budget this shard can ask for is a
  ## second — and whether a 3000-round `river` game fits inside a second is a
  ## property of the machine, not of the code. WHICHEVER WAY THE RACE GOES,
  ## the recorded document must re-derive to the same round.
  let r = record(3000, 1, 2016004, perGame = 1)
  checkEq("the timed recording re-derives to the SAME round", r.mismatch, -1)
  let doc = parseJson(r.text)
  let stopped = doc["result"]["reason"].getStr()
  check("a one-second budget either abandons or completes, and nothing " &
    "else (got `" & stopped & "`)", stopped in ["deadline", "complete"])
  if stopped == "deadline":
    check("and `plan.abandon_after` carries the load-bearing record",
      doc["plan"]["abandon_after"][0].getInt() >= 0)

# --- the COMMITTED fixture re-derives, to its LAST round ------------------
block:
  ## The chain is a tripwire, and a tripwire is only as good as the artefact
  ## it is checked against. `tools/wasm_replay_smoke.cjs` steps the committed
  ## fixture for 200 FRAMES, so it reads the first 200 rounds of a 3025-round
  ## recording and reports `mismatch_round: -1` on the strength of that. This
  ## check runs the deriver to the END of every game in the file, which is
  ## what proves the recording and the sim still agree after F7 widened the
  ## per-type census fields out of their packed base-100 slots.
  const Fixture = "tests" / "fixtures" / "replay-bc16.json"
  check("the committed bc16 fixture exists", fileExists(Fixture))
  let fx = parseReplay(readFile(Fixture))
  checkEq("and it is this build's game version", fx.gameVersion, GameVersion)
  var rounds = 0
  for g in fx.games: rounds += g.rounds
  check("and it is LONGER than the wasm smoke's 200-frame window (" &
    $rounds & " rounds), so a prefix check cannot stand in for this one",
    rounds > 200)
  let d = newDeriver(fx)
  var frames = 0
  while d.advance(): frames += 1
  checkEq("the committed fixture re-derives to its LAST round, not just " &
    "the first 200", d.mismatchRound, -1)
  check("and the deriver walked every recorded round, not a prefix",
    frames >= rounds)

finish("test_bc16_replay")
