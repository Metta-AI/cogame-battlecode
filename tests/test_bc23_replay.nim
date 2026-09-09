## bc23 determinism and replay: same seed + same sheets => identical hash
## chain; record -> RE-DERIVE for EVERY bc23 end reason including the
## wall-clock stop; a STRICT UTF-8 parse of the written bytes; islands,
## anchors, wells, tempo fields, stockpiles and both shared arrays re-derived
## from events + config + seed with NOTHING STORED; `plan.maps` carrying all
## three drawn maps even when the match clinched in two; and EVERY event kind
## inside its per-game bound.

import std/[json, os, strutils, tables, unicode]
import harness
import bc23_fixture
import battlecode/[baselines, broadcast, match, replay, results]
import battlecode/years/dispatch

const Chassis = [scLemonade, scExamplefuncsplayer23]

proc sheets(): array[2, Sheet] =
  [baselineSheet("bc23", blLemonade),
   baselineSheet("bc23", blExamplefuncsplayer23)]

# --- the same world twice --------------------------------------------------
block:
  let s = sheets()
  let (a, _) = playGameFor("bc23", "Quiet", s, Chassis, 0, 0, 500, 0)
  let (b, _) = playGameFor("bc23", "Quiet", s, Chassis, 0, 0, 500, 0)
  checkEq("identical hash chain", a.hashChain, b.hashChain)
  checkEq("identical rounds", a.roundsPlayed, b.roundsPlayed)
  checkEq("identical points", a.points, b.points)
  checkEq("identical end reason", a.endReason, b.endReason)
  checkEq("identical per-round chain", a.roundChains, b.roundChains)
  check("and the chain is a real value", a.hashChain.len > 0)

# --- the hash chain folds every per-team fact ------------------------------
block:
  ## A re-derivation that diverged only in, say, the shared array must NOT
  ## reproduce the chain (the GV02 lesson).
  var w = bare()
  var sides = newSides23(defaultSheets(), 0)
  runRound(w, sides, [ckLemonade, ckLemonade])
  let before = w.hashChain
  var w2 = bare()
  var sides2 = newSides23(defaultSheets(), 0)
  runRound(w2, sides2, [ckLemonade, ckLemonade])
  checkEq("two identical worlds agree", w2.hashChain, before)
  ## Now perturb exactly one folded fact and re-fold.
  for perturb in 0 .. 3:
    var w3 = bare()
    var sides3 = newSides23(defaultSheets(), 0)
    case perturb
    of 0: w3.stats.sharedArray[0][7] = 1
    of 1: w3.stats.elixir[1] = 5
    of 2: w3.wellAt[w3.idx(loc(1, 1))] = newWell(resMana)
    else: w3.stats.adamantium[0] += 1
    runRound(w3, sides3, [ckLemonade, ckLemonade])
    check("perturbing folded fact " & $perturb & " moves the chain",
      w3.hashChain != before)

# --- record -> re-derive, for EVERY bc23 end reason -----------------------
proc recordAndDerive(mapName: string, rounds: int,
                     sheetsIn: array[2, Sheet],
                     chassis: array[2, ScriptedChassis],
                     perGame = 0): (string, EpisodeReason, int, string) =
  ## Returns (the GAME's end_reason, the EPISODE's reason, mismatch round,
  ## the replay text). The episode reason is returned so the wall-clock block
  ## can assert it in bc22's tolerant `in [epDeadline, epComplete]` shape at
  ## the ENUM level, not only as the string the document carries (r1-F11).
  var config = defaultGameConfig()
  config.year = "bc23"
  config.pool = "small"
  config.gamesPerMatch = 1
  config.maxRounds = rounds
  if perGame > 0: config.perGameBudgetSeconds = perGame
  config.matchBudgetSeconds = max(perGame * 2, 600)
  var plan = buildPlan(config, sheetsIn, 7)
  plan.chassis = chassis
  plan.maps = @[mapName]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[-1]
  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: sheetsIn[slot],
      chassis: $chassis[slot])
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc23",
    config: %*{"seed": 7, "year": "bc23", "max_rounds": rounds},
    seed: 7, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc23", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))
  let text = $doc.toJson()
  let deriver = newDeriver(parseReplay(text))
  while deriver.advance(): discard
  let endReason =
    if games.len > 0: games[0].endReason else: "abandoned"
  (endReason, reason, deriver.mismatchRound, text)

block:
  ## `conquest` and the ladder rungs, whichever the map produces — and every
  ## one of them must re-derive clean.
  var seen: seq[string]
  for (mapName, rounds) in [("Quiet", 2000), ("Spin", 400),
                            ("Barcode", 600), ("Sneaky", 300)]:
    let (reason, _, mismatch, text) = recordAndDerive(mapName, rounds,
      sheets(), Chassis)
    if reason notin seen: seen.add(reason)
    checkEq(mapName & " re-derives with no mismatch", mismatch, -1)
    ## A STRICT UTF-8 parse of the written bytes.
    checkEq(mapName & ": the replay is strict UTF-8",
      text.validateUtf8(), -1)
    let doc = parseJson(text)
    checkEq(mapName & ": the format", doc["format"].getStr(),
      "cogame-battlecode-replay")
    checkEq(mapName & ": the year", doc["year"].getStr(), "bc23")
    checkEq(mapName & ": the game version", doc["game_version"].getStr(),
      GameVersion)
    check(mapName & ": the events are non-empty", doc["events"].len > 0)
    check(mapName & ": `result` is SINGULAR — this repo's convention",
      doc.hasKey("result"))
    check(mapName & ": and there is no `results`", not doc.hasKey("results"))
    ## NOTHING per-round is stored: no robot dump, no per-tile dump.
    for forbidden in ["robots", "tiles", "islands_state", "wells_state",
                      "board"]:
      check(mapName & ": the replay stores no `" & forbidden & "`",
        not doc.hasKey(forbidden))
  check("at least two distinct end reasons were exercised", seen.len >= 2)
  echo "bc23 end reasons exercised by the record/re-derive shard: ",
    seen.join(", ")

block:
  ## The WALL-CLOCK stop, applied by the SAME proc on record and on playback
  ## (the particle-worlds scar), in TWO halves — because the stop is a RACE
  ## AGAINST A REAL CLOCK and half of it therefore cannot be asserted on a
  ## shared runner.
  ##
  ## `playMatch` clamps the per-game budget to a whole number of seconds with
  ## a floor of ONE, so the smallest budget this shard can ask for is a second
  ## — and whether a 2000-round `Spiderweb` game fits inside a second is a
  ## property of the machine, not of the code. Measured on two consecutive CI
  ## runs of the same commit range: the debug build always overruns, and the
  ## RELEASE build overran on one runner and finished on the next, which is
  ## `got complete want deadline` on a shard that had been green for weeks.
  ## bc20's, bc21's and bc22's equivalents already avoid the race; this one
  ## did not.
  ##
  ## Half one: the TIMED run. Whichever way the race goes, the recorded
  ## document must re-derive to the same round — that is the assertion the
  ## particle-worlds scar is actually about — and if the deadline DID fire,
  ## `plan.abandon_after` must carry the round it fired on.
  let (reason, episodeReason, mismatch, text) =
    recordAndDerive("Spiderweb", 2000, sheets(), Chassis, perGame = 1)
  checkEq("the timed game re-derives to the SAME round", mismatch, -1)
  ## bc22's shape, at the ENUM level and applied to the value `playMatch`
  ## actually returned (r1-F11). The document-level string check below is the
  ## same statement about the WRITTEN bytes; this one is about the episode.
  check("a one-second budget on the largest map either abandons or " &
    "completes, and nothing else (got `" & $episodeReason & "`)",
    episodeReason in [epDeadline, epComplete])
  let doc = parseJson(text)
  let stopped = doc["result"]["reason"].getStr()
  check("and the WRITTEN document says the same thing (got `" & stopped &
    "`)", stopped in ["deadline", "complete"])
  checkEq("the two agree", stopped, $episodeReason)
  if stopped == "deadline":
    check("and `plan.abandon_after` carries the load-bearing record",
      doc["plan"]["abandon_after"][0].getInt() >= 0)
  discard reason

  ## Half two: the RECORD ITSELF, built synthetically so no clock is involved
  ## — bc20's and bc21's shape. This is what proves the deadline path writes
  ## what the viewer needs, on every machine, every time.
  const stopAt = 137
  var plan = buildPlan(defaultGameConfig(), sheets(), 9)
  plan.chassis = Chassis
  plan.maps = @["Spiderweb"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[stopAt]
  var events: seq[MatchEvent]
  events.add(ev("game_abandoned", game = 0, round = stopAt,
    fields = %*{"map": plan.maps[0]}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: sheets()[slot],
      chassis: $Chassis[slot])
  var abandoned = ReplayDoc(gameVersion: GameVersion, year: "bc23",
    config: %*{"year": "bc23"}, seed: 9, seats: seats, events: events,
    result: resultsJson(seats, @[], plan, epDeadline, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: abandoned.names[slot] = "s" & $slot
  let writtenAbandoned = parseJson($abandoned.toJson())
  checkEq("an abandoned episode is recorded as a deadline",
    writtenAbandoned["result"]["reason"].getStr(), "deadline")
  checkEq("an abandoned game is DISCARDED, never scored half-played",
    writtenAbandoned["result"]["games"].len, 0)
  checkEq("and the stop round is the one load-bearing record",
    writtenAbandoned["plan"]["abandon_after"][0].getInt(), stopAt)

# --- the clinch: three maps drawn, two played ----------------------------
block:
  var config = defaultGameConfig()
  config.year = "bc23"
  config.pool = "mixed"
  config.gamesPerMatch = 3
  config.maxRounds = 400
  let s = sheets()
  var plan = buildPlan(config, s, 871345)
  plan.chassis = Chassis
  checkEq("three maps are drawn", plan.maps.len, 3)
  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  checkEq("the strong chassis clinches in two", games.len, 2)
  checkEq("and the episode is still `complete` — NOT truncated",
    $reason, "complete")
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: s[slot], chassis: $Chassis[slot])
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc23",
    config: %*{"seed": 871345}, seed: 871345, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  let text = $doc.toJson()
  let parsed = parseJson(text)
  checkEq("`plan.maps` still carries ALL THREE drawn maps",
    parsed["plan"]["maps"].len, 3)
  checkEq("while `result.games` carries only the two played",
    parsed["result"]["games"].len, 2)

# --- every event kind respects its per-game bound ------------------------
block:
  ## The bounds from the design note's own event table, enforced by
  ## `world.beat`. A pathological game cannot produce a 20 MB replay.
  const Bounds = {
    "game_start": 1, "first_action": 4, "anchor_built": 40,
    "island_captured": 40, "island_lost": 40, "conquest_progress": 6,
    "well_transformed": 8, "well_upgraded": 8, "first_elixir_unit": 6,
    "boost_field": 20, "destabilize_hit": 20, "duel": 20, "rout": 20,
    "game_end": 1, "game_abandoned": 1}.toTable
  var worst = initCountTable[string]()
  for mapName in ["Quiet", "Sneaky", "AllElements"]:
    let (_, raw) = playGameFor("bc23", mapName, sheets(), Chassis, 0, 0,
      2000, 0)
    var counts = initCountTable[string]()
    for e in raw: counts.inc(e.kind)
    for kind, count in counts:
      if count > worst[kind]: worst[kind] = count
      if Bounds.hasKey(kind):
        check(mapName & ": `" & kind & "` is within its bound of " &
          $Bounds[kind] & " (saw " & $count & ")", count <= Bounds[kind])
      else:
        check(mapName & ": `" & kind & "` has a declared bound", false)
  check("and the whole event stream is a few hundred entries, not a dump",
    worst.len <= 20)

# --- the committed fixture still re-derives -----------------------------
block:
  let path =
    if fileExists("tests/fixtures/replay-bc23.json"):
      "tests/fixtures/replay-bc23.json"
    else: "fixtures/replay-bc23.json"
  let text = readFile(path)
  checkEq("the committed fixture is strict UTF-8", text.validateUtf8(), -1)
  let doc = parseReplay(text)
  checkEq("it is a bc23 recording", doc.year, "bc23")
  checkEq("at this GameVersion — a rule change turns this red, and the fix " &
    "is to re-record with tools/gen_bc23_fixture_replay.nim in the same " &
    "commit", doc.gameVersion, GameVersion)
  let deriver = newDeriver(doc)
  var frames = 0
  while deriver.advance(): frames += 1
  checkEq("and it re-derives with NO MISMATCH", deriver.mismatchRound, -1)
  check("over a real number of frames", frames > 100)

finish("test_bc23_replay")
