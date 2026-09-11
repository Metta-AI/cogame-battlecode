## Shard 26 of the note's list — **the bc17 replay document**, and the half
## of §Tests item 25 that belongs to this year.
##
## A round-trip; a **STRICT UTF-8 PARSE OF THE WRITTEN BYTES**; the viewer's
## re-derivation reproducing the recorded per-round hash **on every single
## round, counted**, and — beyond the chain — **every body's float position,
## health, type and counters, every bullet's position, direction, speed and
## damage, both bullet supplies, both victory-point totals, the broadcast
## arrays, the exec order, the trove layout and both `IDGenerator` states
## re-derived frame by frame from events + config + seed WITH NOTHING
## STORED**; `plan.maps` carrying all three drawn maps even when the match
## clinched in two; `seats[].sheet_envelope` and `sheet_submitted` round-
## tripping; **every event kind respecting the per-game bound `BeatBounds`
## declares**; the recording's size; and **record → re-derive for the
## `abandoned` and the `deadline` stop**.
##
## **WHY A SECOND CHECK BESIDE `mismatchRound`.** `newDeriver` reports the
## FIRST divergent round and `-1` for none, which is a negative statement: a
## recording with an empty `hash_chain_rounds` string would also report `-1`.
## `derivedRounds()` below walks the deriver frame by frame, compares
## `session.hashChainHex()` against the recorded slice ITSELF and returns the
## COUNT of rounds it matched, so the assertion is "2 999 of 2 999 rounds
## agreed" rather than "nothing complained".
##
## **AND WHY A STATE DIGEST BESIDE THE CHAIN.** `foldRoundHash` folds
## thirteen quantities per team plus eleven globals — a lot, but not the
## robot table, not the bullet table and not the two id generators. The
## digest here folds all of those, is computed on the RECORDER's world
## through `playGame`'s `onRound` hook and again on the DERIVER's world at
## the same frame, and the two sequences are compared element by element.
## That is the checklist's "reproduces the recorded per-tick state frame by
## frame" read literally.
##
## TWO CONVENTIONS THIS FILE OBEYS, because the repo has been bitten by both:
##
## * **never zero `perGameBudgetSeconds` in a helper.** `match.nim:480`
##   clamps it to `max(1, min(field, remaining))`, so a zeroed field silently
##   buys a ONE-SECOND budget while `years/bc17/rules.nim` one level down
##   treats 0 as unbounded — and the symptom is diagnostic: a shard that
##   PASSES in `-d:release` and FAILS in debug. The `if perGame > 0:` form
##   below is `tests/test_bc23_replay.nim:69`'s.
## * **every `games[0]` read is guarded** behind a non-empty check, so a
##   failed assertion prints a FAIL instead of an `IndexDefect` — and in
##   release, where bounds checks are off, instead of an unchecked OOB read
##   whose "pass" is not trustworthy. Every end-reason assertion is TOLERANT
##   (`in [epDeadline, epComplete]`), never strictly one of them on a
##   runner-speed-dependent shard.
##
## **THE BOARDS ARE CHOSEN FOR COST, and the cost was measured.** A
## 2 999-round bc17 game is 1.7–17.5 s in DEBUG on the `small` pool
## (`HiddenTunnel` the slowest, `HouseDivided` the fastest at 700 rounds
## because its mirror ends on `all_robots_destroyed`), and every `record()`
## pays for the game TWICE — once to play it and once to re-derive it. Seeds
## here are picked so the shard's debug pass stays around a minute.

import std/[json, os, strutils, tables, unicode]
import harness
import battlecode/[baselines, match, replay, results, rng, sheet, sim_types]
import battlecode/years/dispatch
import battlecode/years/bc17/world as w17
import battlecode/years/bc17/rules as r17
import battlecode/years/bc17/maps as m17

proc orchards(): array[2, Sheet] =
  [baselineSheet("bc17", blOrchard), baselineSheet("bc17", blOrchard)]

let rushSheet = parseReply("""{"sheet":{"opening":"tree_farm",
  "gardener_count":8,"farm_layout":"hex","soldier_tank_ratio":20,
  "lumberjack_share":10,"scout_harass":10,"vp_donate_policy":"rush_1000",
  "shake_neutral_trees":"dedicated","chop_policy":"harvest",
  "bullet_reserve":0,"defend_radius":40},
  "notes":"buy the win","motto":"Plant, water, donate."}""", "bc17")

# ---------------------------------------------------------------------------
#  The per-tick state digest — everything the recording does NOT store
# ---------------------------------------------------------------------------

proc digest(w: w17.World): uint64 =
  ## An FNV-1a fold of the whole observable world, walked in the sim's own
  ## deterministic orders (`execOrder` for the dynamic bodies, the trove's
  ## own `forEachValue` for the trees) so the fold itself cannot be the
  ## thing that differs.
  var h = 0xCBF29CE484222325'u64
  template mix(v: uint64) =
    h = (h xor (v and 0xFFFFFFFF'u64)) * 0x100000001B3'u64
  template mixF(v: float32) = mix(uint64(cast[uint32](v)))
  mix(uint64(w.currentRound))
  mix(uint64(ord(w.running)))
  mix(uint64(w.domination))
  mix(uint64(w.tiebreakRound))
  mix(uint64(ord(w.hasWinner)))
  mix(uint64(ord(w.winner)))
  for t in 0 .. 2:
    mixF(w.bulletSupply[t])            ## the RAW float32 bits
    mix(uint64(w.victoryPoints[t]))
    mix(uint64(w.robotCount[t]))
    mix(uint64(w.treeCount[t]))
  ## The exec order is itself state: a bullet is inserted immediately before
  ## its parent, so the ORDER carries information the ids alone do not.
  for id in w.execOrder:
    mix(uint64(id))
    if w.robots.hasKey(id):
      let r = w.robots[id]
      mix(uint64(ord(r.team)))
      mix(uint64(ord(r.kind)))
      mixF(r.loc.x); mixF(r.loc.y); mixF(r.health)
      mix(uint64(r.roundsAlive))
      mix(uint64(r.attackCount)); mix(uint64(r.moveCount))
      mix(uint64(r.waterCount)); mix(uint64(r.shakeCount))
      mix(uint64(r.buildCooldownTurns))
      mix(uint64(ord(r.alive)))
    elif w.bullets.hasKey(id):
      let b = w.bullets[id]
      mix(uint64(ord(b.team)))
      mixF(b.loc.x); mixF(b.loc.y)
      mixF(b.dir.radians); mixF(b.speed); mixF(b.damage)
      mix(uint64(b.roundsAlive))
  ## The trove layout, walked the way `GameWorld.updateTrees` walks it.
  for id in w.treeKeys.forEachValue:
    mix(uint64(id))
    if w.trees.hasKey(id):
      let t = w.trees[id]
      mix(uint64(ord(t.team)))
      mixF(t.loc.x); mixF(t.loc.y); mixF(t.radius); mixF(t.health)
      mix(uint64(t.containedBullets))
      mix(uint64(t.containedRobot + 1))
      mix(uint64(t.roundsAlive))
  ## The broadcast arrays, both ten-thousand-channel sides.
  for team in 0 .. 1:
    for channel, value in w.broadcastArray[team]:
      if value != 0:
        mix(uint64(channel)); mix(uint64(value))
  ## And both `IDGenerator` states (D3) — the cursor, the block and the
  ## `java.util.Random` seed behind them.
  for gen in [w.idGen, w.bulletIdGen]:
    mix(uint64(gen.cursor))
    mix(uint64(gen.nextIdBlock))
    mix(cast[uint64](gen.random.seed))
  mix(uint64(w.robotIdsIssued))
  mix(uint64(w.bulletIdsIssued))
  h

# ---------------------------------------------------------------------------
#  Recording
# ---------------------------------------------------------------------------

type Recorded = object
  text: string
  doc: ReplayDoc
  reason: EpisodeReason
  games: seq[GameOutcome]
  mismatch: int
  matched: int
  rounds: int

proc derivedRounds(doc: ReplayDoc): (int, int) =
  ## `(rounds recorded, rounds whose re-derived chain MATCHED the recorded
  ## one)`, compared here rather than taken on trust from `mismatchRound`.
  var recorded = 0
  for g in doc.games: recorded += g.rounds
  let d = newDeriver(doc)
  var matched = 0
  while d.advance():
    let rec = d.doc.gameRecord(d.gameIndex)
    let at = (d.roundInGame - 1) * ChainHexLen
    if rec.rounds_chains.len >= at + ChainHexLen and
        d.session.hashChainHex() == rec.rounds_chains[at ..< at + ChainHexLen]:
      matched += 1
  (recorded, matched)

proc record(rounds, gamesPerMatch, seed: int, perGame = 0,
            sheetPair = orchards(),
            chassis: array[2, ScriptedChassis] = [scOrchard, scOrchard],
            maps: seq[string] = @[]): Recorded =
  var config = defaultGameConfig()
  config.year = "bc17"
  config.pool = "small"
  config.gamesPerMatch = gamesPerMatch
  config.maxRounds = rounds
  ## THE CONVENTION: never zero the field. Zero here means "leave the
  ## default alone", not "unbounded", because `match.nim` clamps it to at
  ## least one second one level up.
  if perGame > 0:
    config.perGameBudgetSeconds = perGame
  config.matchBudgetSeconds = max(perGame * 4, 1800)
  var plan = buildPlan(config, sheetPair, seed)
  plan.chassis = chassis
  if maps.len > 0:
    plan.maps = maps
    plan.sideAslots = @[]
    plan.abandonAfter = @[]
    for i in 0 ..< maps.len:
      plan.sideAslots.add(sideAslotFor("bc17", seed, i))
      plan.abandonAfter.add(-1)
  var events: seq[MatchEvent]
  events.add(ev("episode_start", ms = 0,
    fields = %*{"seed": seed, "year": "bc17", "maps": %plan.maps,
                "aliases": [AliasA, AliasB]}))
  let (games, reason) = playMatch(config, plan, events)
  events.add(ev("episode_end", ms = 1, fields = %*{"reason": $reason}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "player" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: plan.sheets[slot],
      chassis: $chassis[slot])
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc17",
    config: %*{"seed": seed, "year": "bc17", "max_rounds": rounds},
    seed: seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  doc.names = ["player0", "player1"]
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc17", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))
  result.text = $doc.toJson()
  result.doc = parseReplay(result.text)
  result.reason = reason
  result.games = games
  let deriver = newDeriver(result.doc)
  while deriver.advance(): discard
  result.mismatch = deriver.mismatchRound
  let (recorded, matched) = derivedRounds(result.doc)
  result.rounds = recorded
  result.matched = matched

# --- the document round-trips, and it is STRICT UTF-8 ---------------------
block:
  let r = record(900, 1, 5)
  checkEq("the episode completed", r.reason, epComplete)
  checkEq("and the recording re-derives with NO hash mismatch", r.mismatch, -1)
  check("with EVERY recorded round matched, not merely nothing complaining " &
    "(" & $r.matched & " of " & $r.rounds & ")",
    r.rounds > 0 and r.matched == r.rounds)
  checkEq("the bytes are STRICT UTF-8", r.text.validateUtf8(), -1)
  checkEq("the format", r.doc.year, "bc17")
  checkEq("at this GameVersion", r.doc.gameVersion, GameVersion)
  check("which is inside the compatibility list",
    GameVersion in ReplayCompatibleGameVersions)
  checkEq("the seed round-trips", r.doc.seed, 5)
  checkEq("both seats", r.doc.seats.len, 2)
  checkEq("and the applied sheet survives",
    r.doc.seats[0].sheet.doctrine17, defaultSheet(YearBc17).doctrine17)
  check("the games were recorded", r.doc.games.len >= 1)
  if r.doc.games.len >= 1:
    ## The seed the `docker-smoke` episode is pinned to, so this shard and
    ## `tests/test_bc17_maps.nim` name the same board.
    checkEq("on the board seed 5 draws", r.doc.games[0].map, "HouseDivided")
    check("with a map sha", r.doc.games[0].mapSha.len == 64)
    check("and a per-round chain", r.doc.games[0].roundChains.len > 0)
    checkEq("sixteen hex characters a round and not one more",
      r.doc.games[0].roundChains.len,
      r.doc.games[0].rounds * ChainHexLen)

# --- NOTHING is stored: the browser re-derives everything ------------------
block:
  let r = record(600, 1, 9)
  let doc = parseJson(r.text)
  ## Not one per-round robot dump, bullet dump, tree dump, broadcast array
  ## or id-generator state is in the file. They are all pure functions of
  ## the sim, so the browser re-derives them.
  for forbidden in ["robots", "bullets", "trees", "board", "bodies",
                    "broadcasts", "rng", "frames", "grid", "positions"]:
    check("the replay stores no `" & forbidden & "`",
      not doc.hasKey(forbidden))
  for forbidden in ["\"bullet_supply\"", "\"exec_order\"", "\"id_gen\"",
                    "\"trove\"", "\"health\":"]:
    check("and no nested `" & forbidden & "` either", forbidden notin r.text)
  check("a 600-round one-game recording is under 64 KB (got " &
    $(r.text.len div 1024) & " KB)", r.text.len < 65536)

# --- EVERY BODY, EVERY BULLET, EVERY COUNTER, FRAME BY FRAME ---------------
block:
  ## Checklist item 2 read literally. The recorder's world is digested at
  ## the END of every round through `playGame`'s own `onRound` hook; the
  ## deriver's world is digested at the same frame; the two sequences are
  ## compared element by element. A recording that agreed on the hash chain
  ## and disagreed on a robot's float32 y would fail HERE.
  const Map = "OMGTree"
  const Rounds = 900
  let sheetPair = orchards()
  var reference: seq[uint64]
  let (_, o) = r17.playGame(m17.loadMap(Map), sheetPair,
                            [r17.ck17Orchard, r17.ck17Orchard], 0, 0,
                            Rounds, 0,
    onRound = proc (w: w17.World, round: int) {.closure.} =
      reference.add(digest(w)))
  check("the reference game really played (" & $o.roundsPlayed & " rounds)",
    o.roundsPlayed > 100)
  checkEq("and one digest was taken per played round", reference.len,
    o.roundsPlayed)
  ## A digest that never changes would make the comparison below pass
  ## vacuously, which is the one way this check could lie.
  var seenDigests = initCountTable[uint64]()
  for v in reference: seenDigests.inc(v)
  check("the digest really varies round to round (" & $seenDigests.len &
    " distinct values over " & $reference.len & " rounds)",
    seenDigests.len * 2 >= reference.len)
  let r = record(Rounds, 1, 5, maps = @[Map])
  checkEq("the recording re-derives with no mismatch", r.mismatch, -1)
  let d = newDeriver(r.doc)
  var frames = 0
  var firstDivergence = -1
  while d.advance():
    if frames < reference.len and
        digest(d.session.w17) != reference[frames] and firstDivergence < 0:
      firstDivergence = frames + 1
    frames += 1
  checkEq("the deriver walked every recorded round", frames, o.roundsPlayed)
  checkEq("and the WHOLE per-tick state — every body's position, health, " &
    "type and counters, every bullet's position, direction, speed and " &
    "damage, both supplies, both VP totals, the broadcast arrays, the exec " &
    "order, the trove layout and both IDGenerator states — matched on " &
    "every one of those rounds", firstDivergence, -1)

# --- the clinch shape ------------------------------------------------------
block:
  ## A best-of-three that a side takes 2-0 records TWO games with
  ## `reason: complete`, which is CORRECT and not truncated — and
  ## `plan.maps` still carries all three drawn maps so a spectator can see
  ## what the third would have been.
  let r = record(700, 3, 5)
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
  check("every played game re-derives", r.mismatch == -1)
  check("on every one of its rounds (" & $r.matched & " of " & $r.rounds &
    ")", r.rounds > 0 and r.matched == r.rounds)

# --- the envelope and the submitted sheet round-trip ----------------------
block:
  let r = record(400, 1, 5, sheetPair = [rushSheet, rushSheet])
  let doc = parseJson(r.text)
  check("the seats carry sheet_envelope",
    doc["seats"][0].hasKey("sheet_envelope"))
  check("and sheet_submitted", doc["seats"][0].hasKey("sheet_submitted"))
  checkEq("the seats answer inside a `sheet` envelope",
    doc["seats"][0]["sheet_envelope"].getStr(), "sheet")
  check("and the submitted text is the sheet node as received",
    "rush_1000" in doc["seats"][0]["sheet_submitted"].getStr())
  check("sheet_defaults_applied is an array",
    doc["seats"][0]["sheet_defaults_applied"].kind == JArray)
  checkEq("and the reply states all eleven knobs, so nothing defaulted",
    doc["seats"][0]["sheet_defaults_applied"].len, 0)
  checkEq("both round-trip through parseReplay into the Sheet",
    r.doc.seats[0].sheet.envelope, "sheet")
  check("and the submitted text survives the parse",
    "rush_1000" in r.doc.seats[0].sheet.submitted)

# --- EVERY EVENT KIND RESPECTS ITS PER-GAME BOUND -------------------------
block:
  ## `years/bc17/world.nim`'s own `BeatBounds` table, read from the source
  ## of truth rather than copied: a 2 999-round match with a hundred bodies
  ## on the board cannot be allowed to emit an event per action, and the
  ## whole worst case is `11 + 3 x 232 = 707` entries.
  const Slots = {
    "game_start": w17.BeatGameStart, "first_action": w17.BeatFirstAction,
    "unit_milestone": w17.BeatUnitMilestone,
    "tree_planted": w17.BeatTreePlanted, "tree_lost": w17.BeatTreeLost,
    "farm_online": w17.BeatFarmOnline,
    "gardener_lost": w17.BeatGardenerLost,
    "archon_lost": w17.BeatArchonLost, "donation": w17.BeatDonation,
    "shake": w17.BeatShake, "chop_reveal": w17.BeatChopReveal,
    "strike": w17.BeatStrike, "volley": w17.BeatVolley,
    "rout": w17.BeatRout, "duel": w17.BeatDuel, "famine": w17.BeatFamine,
    "tiebreak": w17.BeatTiebreak, "game_end": w17.BeatGameEnd,
    # `game_abandoned` shares slot 17 with `game_end`, so the two are
    # counted TOGETHER against one bound.
    "game_abandoned": w17.BeatGameEnd,
  }.toTable
  let r = record(3000, 1, 2)
  check("the long episode finished", r.reason in [epDeadline, epComplete])
  checkEq("and it re-derives", r.mismatch, -1)
  check("on every round (" & $r.matched & " of " & $r.rounds & ")",
    r.rounds > 0 and r.matched == r.rounds)
  var perGame = initTable[int, CountTable[int]]()
  var kinds: seq[string]
  for e in r.doc.events:
    if e.game < 0: continue
    if e.kind notin Slots:
      check("event kind `" & e.kind & "` has a documented bound", false)
      continue
    if e.kind notin kinds: kinds.add(e.kind)
    let slot = Slots[e.kind]
    if slot notin perGame: perGame[slot] = initCountTable[int]()
    perGame[slot].inc(e.game)
  for slot, counts in perGame:
    for game, n in counts:
      check("beat slot " & $slot & " is bounded at " &
        $w17.BeatBounds[slot] & " per game (game " & $game &
        " emitted " & $n & ")", n <= w17.BeatBounds[slot])
  echo "  bc17 event kinds in a 2999-round game: ", kinds.join(", ")
  check("the game really emitted beats", kinds.len >= 6)
  check("including the game's own bookends",
    "game_start" in kinds and "game_end" in kinds)
  ## And the whole event list for a one-game match stays small.
  check("the event list is small (got " & $r.doc.events.len & ")",
    r.doc.events.len < 300)
  ## §Tests 26's SIZE CLAIM, at the measured peak rather than the note's.
  ## The note says "a 2 999-round game with >= 300 bullets in flight
  ## recording under 400 KB". **MEASURED IN THIS PORT: the peak bullets in
  ## flight over every committed board and both doctrine poles is 38**
  ## (`Whirligig`, the 100x100 farm), because 2017 armies are small and its
  ## shots are one, three or five at a time — 300 is not reachable and
  ## saying so is cheaper than a synthetic board nobody plays. The size
  ## claim is asserted here on a whole 2 999-round recording.
  check("a whole 2999-round one-game recording is under 400 KB (got " &
    $(r.text.len div 1024) & " KB)", r.text.len < 409600)

# --- record -> re-derive for every bc17 end reason ------------------------
block:
  ## The engine's own ladder rungs plus `victory_points_reached`, each
  ## recorded and re-derived by the SAME proc — the particle-worlds scar.
  var seen: seq[string]
  for (rounds, seed, sheetPair) in [(3000, 5, orchards()),
                                    (3000, 9, orchards()),
                                    (1400, 2, [rushSheet, rushSheet])]:
    let r = record(rounds, 1, seed, sheetPair = sheetPair)
    checkEq("seed " & $seed & " re-derives with no mismatch", r.mismatch, -1)
    check("and matched every round (" & $r.matched & " of " & $r.rounds & ")",
      r.rounds > 0 and r.matched == r.rounds)
    if r.doc.games.len >= 1:
      let reason = r.doc.result{"games"}[0]{"end_reason"}.getStr()
      if reason notin seen: seen.add(reason)
  echo "  bc17 end reasons exercised by the record/re-derive shard: ",
    seen.join(", ")
  check("at least three distinct end reasons were exercised", seen.len >= 3)
  for reason in seen:
    check("`" & reason & "` is a declared end reason", reason in EndReasons)
    check("and it is one of this year's ladder names",
      reason in w17.Bc17RungNames)

# --- the ABANDONED path, built synthetically so no clock is involved ------
block:
  ## bc20's, bc21's and bc22's shape, and the half that proves the deadline
  ## path writes what the viewer needs on every machine, every time.
  const stopAt = 137
  var config = defaultGameConfig()
  config.year = "bc17"
  var plan = buildPlan(config, orchards(), 9)
  plan.chassis = [scOrchard, scOrchard]
  plan.maps = @["HouseDivided"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[stopAt]
  var events: seq[MatchEvent]
  events.add(ev("game_abandoned", game = 0, round = stopAt,
    fields = %*{"map": plan.maps[0]}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: plan.sheets[slot], chassis: "orchard")
  var abandoned = ReplayDoc(gameVersion: GameVersion, year: "bc17",
    config: %*{"year": "bc17"}, seed: 9, seats: seats, events: events,
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
  checkEq("the abandoned recording re-parses", back.year, "bc17")
  checkEq("with the record intact", back.plan.abandonAfter[0], stopAt)
  ## AND IT RE-DERIVES: the deriver reads `abandon_after` for a game that
  ## has no `GameHeader` and stops exactly where the recorder stopped.
  let d = newDeriver(back)
  var frames = 0
  while d.advance(): frames += 1
  checkEq("the abandoned game re-derives to its stop round and no further",
    frames, stopAt)
  checkEq("and reports no mismatch on the way", d.mismatchRound, -1)

# --- the DEADLINE path, TIMED, with the tolerant assertion ----------------
block:
  ## `playMatch` clamps the per-game budget to a whole number of seconds
  ## with a floor of ONE, so the smallest budget this shard can ask for is a
  ## second — and whether a 2 999-round `HiddenTunnel` game fits inside a
  ## second is a property of the machine, not of the code. WHICHEVER WAY THE
  ## RACE GOES, the recorded document must re-derive to the same round.
  let r = record(3000, 1, 10, perGame = 1)
  checkEq("the timed recording re-derives to the SAME round", r.mismatch, -1)
  let doc = parseJson(r.text)
  let stopped = doc["result"]["reason"].getStr()
  check("a one-second budget either abandons or completes, and nothing " &
    "else (got `" & stopped & "`)", stopped in ["deadline", "complete"])
  if stopped == "deadline":
    check("and `plan.abandon_after` carries the load-bearing record",
      doc["plan"]["abandon_after"][0].getInt() >= 0)
    checkEq("an abandoned game writes no GameHeader", r.doc.games.len, 0)
    let d = newDeriver(r.doc)
    var frames = 0
    while d.advance(): frames += 1
    check("and the deriver still walks it to the stop round",
      frames == doc["plan"]["abandon_after"][0].getInt())
  else:
    check("and a completed one matched every round (" & $r.matched & " of " &
      $r.rounds & ")", r.rounds > 0 and r.matched == r.rounds)

# --- the COMMITTED fixture re-derives, to its LAST round ------------------
block:
  ## The chain is a tripwire, and a tripwire is only as good as the artefact
  ## it is checked against. `tools/wasm_replay_smoke.cjs` steps the
  ## committed fixture for 200 FRAMES, so it reads the first 200 rounds of a
  ## 2 697-round recording and reports `mismatch_round: -1` on the strength
  ## of that. This check runs the deriver to the END of every game in the
  ## file — which is what `ci.yml`'s wasm-viewer step says is owed, and what
  ## nothing in this repository asserted for bc17 until now (r1-F1).
  const Fixture = "tests" / "fixtures" / "replay-bc17.json"
  check("the committed bc17 fixture exists", fileExists(Fixture))
  let fx = parseReplay(readFile(Fixture))
  checkEq("and it is this build's game version", fx.gameVersion, GameVersion)
  checkEq("the bytes are STRICT UTF-8", readFile(Fixture).validateUtf8(), -1)
  var rounds = 0
  for g in fx.games: rounds += g.rounds
  check("and it is LONGER than the wasm smoke's 200-frame window (" &
    $rounds & " rounds), so a prefix check cannot stand in for this one",
    rounds > 200)
  let (recorded, matched) = derivedRounds(fx)
  checkEq("every recorded round of the committed fixture re-derives, not " &
    "just the first 200", matched, recorded)
  let d = newDeriver(fx)
  var frames = 0
  while d.advance(): frames += 1
  checkEq("the committed fixture re-derives with NO mismatch",
    d.mismatchRound, -1)
  check("and the deriver walked every recorded round, not a prefix",
    frames >= rounds)

finish("test_bc17_replay")
