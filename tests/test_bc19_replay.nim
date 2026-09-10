## Shard 23 of the note's list — **the bc19 replay document**.
##
## A round-trip; a STRICT UTF-8 PARSE of the written bytes; the viewer's
## re-derivation reproducing the recorded per-round hashes with NOTHING
## STORED; `plan.maps` carrying all three drawn maps even when the match
## clinched in two; `seats[].sheet_envelope` and `sheet_submitted` round-
## tripping; and **every event kind respecting its per-game bound**.
##
## **WHAT "NOTHING STORED" MEANS IN THIS YEAR IS LONGER THAN IN ANY OTHER**,
## because bc19's whole state is robot state: unit positions, health, types,
## carried karbonite and fuel, `turn` counters, `signal`, `signal_radius`,
## `castle_talk`, the occupancy shadow, both team stockpiles, the 2x2
## `last_offer` barter matrix, the SPENT ID SET and **the MT19937 state
## itself** all re-derive from events + config + seed. Nothing about the
## generator is stored either: the committed board carries the 624-word state
## `makeMap()` left behind (V3), and every id after the opening castles is
## drawn from it in order.
##
## TWO CONVENTIONS THIS FILE OBEYS, because the repo has been bitten by both:
##
## * **never zero `perGameBudgetSeconds` in a helper.** `match.nim` clamps it
##   to `max(1, min(field, remaining))`, so a zeroed field silently buys a
##   ONE-SECOND budget while `years/bc19/rules.nim` one level down treats 0
##   as unbounded — and the symptom is diagnostic: a shard that PASSES in
##   `-d:release` and FAILS in debug.
## * **every `games[0]` read is guarded** behind a non-empty check, so a
##   failed assertion prints a FAIL instead of an `IndexDefect` — and in
##   release, where bounds checks are off, instead of an unchecked OOB read
##   whose "pass" is not trustworthy. And every end-reason assertion is
##   TOLERANT, never strictly one value on a runner-speed-dependent shard.

import std/[json, os, strutils, tables, unicode]
import harness
import battlecode/[baselines, match, replay, results, sheet, sim_types]
import battlecode/years/dispatch
import battlecode/years/bc19/rules as r19

proc sheets(): array[2, Sheet] =
  [baselineSheet("bc19", blSaber), baselineSheet("bc19", blSaber)]

type Recorded = object
  text: string
  doc: ReplayDoc
  reason: EpisodeReason
  games: seq[GameOutcome]
  mismatch: int

proc record(rounds, gamesPerMatch, seed: int, perGame = 0): Recorded =
  var config = defaultGameConfig()
  config.year = "bc19"
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
  plan.chassis = [scSaber, scSaber]
  var events: seq[MatchEvent]
  events.add(ev("episode_start", ms = 0,
    fields = %*{"seed": seed, "year": "bc19", "maps": %plan.maps,
                "aliases": [AliasA, AliasB]}))
  let (games, reason) = playMatch(config, plan, events)
  events.add(ev("episode_end", ms = 1, fields = %*{"reason": $reason}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "player" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: plan.sheets[slot], chassis: "saber")
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc19",
    config: %*{"seed": seed, "year": "bc19", "max_rounds": rounds},
    seed: seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  doc.names = ["player0", "player1"]
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc19", g.mapName), sideAslot: g.sideAslot,
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
  let r = record(400, 1, 2019004)
  check("the episode finished", r.reason in [epDeadline, epComplete])
  checkEq("and the recording re-derives with NO hash mismatch", r.mismatch, -1)
  checkEq("the bytes are STRICT UTF-8", r.text.validateUtf8(), -1)
  checkEq("the format", r.doc.year, "bc19")
  checkEq("at this GameVersion", r.doc.gameVersion, GameVersion)
  check("which is inside the compatibility list",
    GameVersion in ReplayCompatibleGameVersions)
  checkEq("the seed round-trips", r.doc.seed, 2019004)
  checkEq("both seats", r.doc.seats.len, 2)
  checkEq("and the applied sheet survives",
    r.doc.seats[0].sheet.doctrine19, sheets()[0].doctrine19)
  check("the games were recorded", r.doc.games.len >= 1)
  if r.doc.games.len >= 1:
    check("on a board from the small pool",
      r.doc.games[0].map in r19.SmallPool)
    check("with a map sha", r.doc.games[0].mapSha.len == 64)
    check("and a per-round chain", r.doc.games[0].roundChains.len > 0)
    ## `roundChains` is the per-round FNV-1a chain CONCATENATED as hex, 16
    ## characters (one uint64) per round, so its length is the round count
    ## times sixteen and nothing else. Sixteen is the width the wasm
    ## re-deriver slices on.
    checkEq("one 16-hex-character chain entry per played round",
      r.doc.games[0].roundChains.len, r.doc.games[0].rounds * 16)

# --- NOTHING is stored: the browser re-derives everything ------------------
block:
  let r = record(400, 1, 2019004)
  let doc = parseJson(r.text)
  ## Not one per-round robot dump, per-square dump, shadow, stockpile series,
  ## barter matrix or generator state is in the file. They are all pure
  ## functions of the sim, so the browser re-derives them.
  for forbidden in ["robots", "shadow", "board", "squares", "karbonite_map",
                    "fuel_map", "rng", "frames", "grid", "mt", "last_offer",
                    "ids_spent"]:
    check("the replay stores no `" & forbidden & "`",
      not doc.hasKey(forbidden))
  for forbidden in ["\"shadow\":", "\"mt_state\"", "\"occupancy\"",
                    "\"last_offer\":", "\"karbonite_map\"",
                    "\"id_pool\"", "\"chess_ops\""]:
    check("and no nested `" & forbidden & "` either", forbidden notin r.text)
  ## The whole document for a one-game 400-round episode is small, because
  ## self-sufficiency is by RE-DERIVATION rather than by bulk.
  check("a 400-round one-game recording is under 32 KB (got " &
    $(r.text.len div 1024) & " KB)", r.text.len < 32768)

# --- the re-derivation really reconstructs THE WHOLE WORLD ----------------
block:
  ## The claim above is only worth what it is checked against, so this plays
  ## the same game twice — once as the recorder and once as the deriver would
  ## — and compares EVERY field of EVERY robot, both stockpiles, the barter
  ## matrix, the spent-id set, the occupancy shadow and the MT19937 state.
  let sheetPair = sheets()
  let spec = r19.loadMap("seed-0043")
  let (a, _) = r19.playGame(spec, sheetPair, [r19.ck19Saber, r19.ck19Saber],
                            0, 0, 400, 0)
  let (b, _) = r19.playGame(spec, sheetPair, [r19.ck19Saber, r19.ck19Saber],
                            0, 0, 400, 0)
  checkEq("the two runs end on the same round", a.round, b.round)
  checkEq("with the same hash chain", a.hashChainHexOf(), b.hashChainHexOf())
  checkEq("the same queue length", a.robots.len, b.robots.len)
  var fields = 0
  for i in 0 ..< min(a.robots.len, b.robots.len):
    let x = a.robots[i]
    let y = b.robots[i]
    inc fields
    checkEq("robot " & $i & " id", x.id, y.id)
    checkEq("robot " & $i & " position", (x.x, x.y), (y.x, y.y))
    checkEq("robot " & $i & " unit", x.unit, y.unit)
    checkEq("robot " & $i & " team", x.team, y.team)
    checkEq("robot " & $i & " health", x.health, y.health)
    checkEq("robot " & $i & " carried karbonite", x.karbonite, y.karbonite)
    checkEq("robot " & $i & " carried fuel", x.fuel, y.fuel)
    checkEq("robot " & $i & " turn counter", x.turn, y.turn)
    checkEq("robot " & $i & " signal", x.signal, y.signal)
    checkEq("robot " & $i & " signal radius", x.signalRadius, y.signalRadius)
    checkEq("robot " & $i & " castle talk", x.castleTalk, y.castleTalk)
  check("the comparison covered a real board", fields >= 10)
  checkEq("both stockpiles", (a.karbonite, a.fuel), (b.karbonite, b.fuel))
  checkEq("the barter matrix", a.lastOffer, b.lastOffer)
  checkEq("the SPENT ID SET, in order", a.idsSpent, b.idsSpent)
  checkEq("the occupancy shadow, square for square",
    a.shadowChecksum(), b.shadowChecksum())
  checkEq("the queue order", a.queueChecksum(), b.queueChecksum())
  ## The MT19937 state itself: the id pool is drawn from it and never
  ## refilled, so a one-word drift shows up as a different id forever after.
  checkEq("and the MT19937 state, all 625 words",
    a.gen.saveState(), b.gen.saveState())

# --- the clinch shape ------------------------------------------------------
block:
  ## A best-of-three that a side takes 2-0 records TWO games with
  ## `reason: complete`, which is CORRECT and not truncated — and `plan.maps`
  ## still carries all three drawn maps so a spectator can see what the third
  ## would have been.
  let r = record(400, 3, 2019004)
  check("the reason is tolerant", r.reason in [epDeadline, epComplete])
  checkEq("plan.maps carries all THREE drawn maps", r.doc.plan.maps.len, 3)
  check("and the games actually played are two or three",
    r.doc.games.len in 2 .. 3)
  if r.doc.games.len == 2:
    checkEq("a clinched match still reports `complete`", r.reason, epComplete)
  for g in r.doc.games:
    check("every played map is one of the drawn three",
      g.map in r.doc.plan.maps)
  check("and the three drawn maps are distinct",
    r.doc.plan.maps[0] != r.doc.plan.maps[1] and
    r.doc.plan.maps[1] != r.doc.plan.maps[2] and
    r.doc.plan.maps[0] != r.doc.plan.maps[2])
  ## bc19 draws WITHOUT replacement from a pool of six small boards, so the
  ## three are drawn names and every one of them is in the pool.
  for m in r.doc.plan.maps:
    check("`" & m & "` is a committed small-pool board", m in r19.SmallPool)
  checkEq("the sides alternate across the three games",
    r.doc.plan.sideAslots.len, 3)

# --- the envelope and the submitted sheet round-trip ----------------------
block:
  let r = record(300, 1, 2019004)
  let doc = parseJson(r.text)
  check("the seats carry sheet_envelope",
    doc["seats"][0].hasKey("sheet_envelope"))
  check("and sheet_submitted", doc["seats"][0].hasKey("sheet_submitted"))
  checkEq("the scripted seats answer inside a `sheet` envelope",
    doc["seats"][0]["sheet_envelope"].getStr(), "sheet")
  check("and the submitted text is the sheet node as received",
    "opening" in doc["seats"][0]["sheet_submitted"].getStr())
  check("sheet_defaults_applied is an array",
    doc["seats"][0]["sheet_defaults_applied"].kind == JArray)
  checkEq("and the baseline reply sets all eleven knobs, so nothing " &
    "defaulted", doc["seats"][0]["sheet_defaults_applied"].len, 0)
  check("no `chassis` key was honoured",
    doc["seats"][0]["sheet_unknown_fields"].len == 0)

# --- EVERY EVENT KIND RESPECTS ITS PER-GAME BOUND -------------------------
block:
  ## The design note's own table, which is also `years/bc19/world.nim`'s
  ## `BeatBounds`. A 1000-round match with 240 robots on the board cannot be
  ## allowed to emit an event per action, so every kind is bounded PER GAME
  ## and this is what proves it. The whole worst case is
  ## `3 x (1+2+8+16+16+6+20+4+20+20+20+20+1+2) = 468` in-match entries plus
  ## eleven pre-match.
  const Bounds = {
    "game_start": 1, "first_action": 2, "unit_milestone": 8,
    "church_built": 16, "church_lost": 16, "castle_lost": 6,
    "depot_claimed": 20, "famine": 4, "trade": 20, "preacher_splash": 20,
    "rout": 20, "duel": 20, "tiebreak": 1, "game_end": 2,
    "game_abandoned": 2,
  }.toTable
  ## The bounds table and the sim's own array must agree, or this test is
  ## checking a copy of the truth rather than the truth.
  checkEq("game_start", Bounds["game_start"],
    r19.BeatBounds[r19.BeatGameStart])
  checkEq("first_action", Bounds["first_action"],
    r19.BeatBounds[r19.BeatFirstAction])
  checkEq("unit_milestone", Bounds["unit_milestone"],
    r19.BeatBounds[r19.BeatUnitMilestone])
  checkEq("church_built", Bounds["church_built"],
    r19.BeatBounds[r19.BeatChurchBuilt])
  checkEq("church_lost", Bounds["church_lost"],
    r19.BeatBounds[r19.BeatChurchLost])
  checkEq("castle_lost", Bounds["castle_lost"],
    r19.BeatBounds[r19.BeatCastleLost])
  checkEq("depot_claimed", Bounds["depot_claimed"],
    r19.BeatBounds[r19.BeatDepotClaimed])
  checkEq("famine", Bounds["famine"], r19.BeatBounds[r19.BeatFamine])
  checkEq("trade", Bounds["trade"], r19.BeatBounds[r19.BeatTrade])
  checkEq("preacher_splash", Bounds["preacher_splash"],
    r19.BeatBounds[r19.BeatPreacherSplash])
  checkEq("rout", Bounds["rout"], r19.BeatBounds[r19.BeatRout])
  checkEq("duel", Bounds["duel"], r19.BeatBounds[r19.BeatDuel])
  checkEq("tiebreak", Bounds["tiebreak"], r19.BeatBounds[r19.BeatTiebreak])
  checkEq("game_end", Bounds["game_end"], r19.BeatBounds[r19.BeatGameEnd])
  var worst = 0
  for slot in 0 ..< 14: worst += r19.BeatBounds[slot]
  checkEq("the note's own worst case per game is 156", worst, 156)

  let r = record(1000, 3, 2019004)
  check("the long match finished", r.reason in [epDeadline, epComplete])
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
  check("the match really produced depot beats", "depot_claimed" in perGame)
  check("and a game start per game", "game_start" in perGame)
  ## And the whole event list for a three-game match stays inside the note's
  ## own 468 + 11 worst case.
  check("the event list is inside the note's worst case (got " &
    $r.doc.events.len & " of 479)", r.doc.events.len <= 479)

# --- record -> re-derive for EVERY bc19 end reason ------------------------
block:
  ## The engine's own four reachable rungs, plus our wall-clock `abandoned`,
  ## each recorded and re-derived by the SAME proc — the particle-worlds
  ## scar. THE ASSERTION IS TOLERANT: which rung a given seed reaches is a
  ## property of the board, and the shard's job is that whatever is recorded
  ## re-derives.
  var seen: seq[string]
  for (rounds, seed) in [(1000, 2019004), (1000, 1), (1000, 7), (600, 5),
                         (400, 99), (1000, 42), (1000, 13), (1000, 300)]:
    let r = record(rounds, 1, seed)
    checkEq("seed " & $seed & " re-derives with no mismatch", r.mismatch, -1)
    if r.doc.games.len >= 1:
      let reason = r.doc.result{"games"}[0]{"end_reason"}.getStr()
      if reason notin seen: seen.add(reason)
  echo "  bc19 end reasons exercised by the record/re-derive shard: ",
    seen.join(", ")
  check("at least two distinct end reasons were exercised", seen.len >= 2)
  for reason in seen:
    check("`" & reason & "` is a declared end reason", reason in EndReasons)
    check("and it is one of bc19's five",
      reason in ["castles_destroyed", "more_castles", "more_unit_health",
                 "coin_flip", "abandoned"])
    ## V6: win conditions 3 and 4 are unreachable in this port and their
    ## reasons must never appear.
    check("and never an initialisation reason (V6)",
      reason notin ["opponent_failed_to_initialize",
                    "both_failed_to_initialize"])

block:
  ## THE WALL-CLOCK STOP, built SYNTHETICALLY so no clock is involved — the
  ## half that proves the deadline path writes what the viewer needs on every
  ## machine, every time.
  const stopAt = 137
  var config = defaultGameConfig()
  config.year = "bc19"
  var plan = buildPlan(config, sheets(), 9)
  plan.chassis = [scSaber, scSaber]
  plan.maps = @["seed-0043"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[stopAt]
  var events: seq[MatchEvent]
  events.add(ev("game_abandoned", game = 0, round = stopAt,
    fields = %*{"map": plan.maps[0]}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: plan.sheets[slot], chassis: "saber")
  var abandoned = ReplayDoc(gameVersion: GameVersion, year: "bc19",
    config: %*{"year": "bc19"}, seed: 9, seats: seats, events: events,
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
  let back = parseReplay(text)
  checkEq("the abandoned recording re-parses", back.year, "bc19")
  checkEq("with the record intact", back.plan.abandonAfter[0], stopAt)

# --- the deadline path, TIMED, with the tolerant assertion ----------------
block:
  ## `playMatch` clamps the per-game budget to a whole number of seconds with
  ## a floor of ONE, so the smallest budget this shard can ask for is a
  ## second — and whether a 1000-round `seed-0043` game fits inside a second
  ## is a property of the machine, not of the code. WHICHEVER WAY THE RACE
  ## GOES, the recorded document must re-derive to the same round.
  let r = record(1000, 1, 2019004, perGame = 1)
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
  ## fixture for 200 FRAMES, so a prefix check cannot stand in for this one:
  ## this runs the deriver to the END of every game in the file.
  const Fixture = "tests" / "fixtures" / "replay-bc19.json"
  check("the committed bc19 fixture exists", fileExists(Fixture))
  let fx = parseReplay(readFile(Fixture))
  checkEq("and it is this build's game version", fx.gameVersion, GameVersion)
  checkEq("and it is a bc19 recording", fx.year, "bc19")
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
  ## `plan.maps` in the committed fixture carries all three, and the recorded
  ## games are a prefix of them.
  checkEq("the fixture's plan carries three maps", fx.plan.maps.len, 3)
  for g in fx.games:
    check("and every recorded game is on one of them", g.map in fx.plan.maps)

finish("test_bc19_replay")
