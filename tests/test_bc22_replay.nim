## The bc22 replay document: record -> RE-DERIVE, a STRICT UTF-8 parse of the
## written bytes, and EVERY event kind inside its per-game bound.
##
## §Tests item 21. Nothing about robots, resources, buildings or anomalies is
## stored: the wasm sim re-derives every round from events + config + seed, and
## the per-round hash chain is what proves it. This is the bc22 half of
## `tests/test_determinism.nim` and `tests/test_replay.nim`, a separate shard
## for the same reason bc20's, bc21's, bc23's, bc24's and bc25's are: those two
## are written against bc26's own world type.

import std/[json, strutils, tables, unicode]
import harness
import battlecode/[baselines, match, replay, results, sheet, sim_types]
import battlecode/years/dispatch

const Chassis = [scWololo, scExamplefuncsplayer22]

proc sheets(): array[2, Sheet] =
  [baselineSheet("bc22", blWololo),
   baselineSheet("bc22", blExamplefuncsplayer22)]

proc bc22Config(rounds = 700, games = 1, pool = "small",
                perGame = 0): GameConfig =
  ## `perGame = 0` means "leave `defaultGameConfig()`'s 90 s alone", NOT "no
  ## per-game budget": `playMatch` computes
  ## `max(1, min(config.perGameBudgetSeconds, remaining))`, so a zero here is
  ## clamped up to a ONE-SECOND per-game budget and the 2000-round blocks
  ## abort on wall clock in a debug build (~4 s a game) while squeaking
  ## through in release (~0 s). Same convention as
  ## `tests/test_bc23_replay.nim`.
  result = defaultGameConfig()
  result.year = "bc22"
  result.pool = pool
  result.gamesPerMatch = games
  result.maxRounds = rounds
  if perGame > 0: result.perGameBudgetSeconds = perGame
  result.matchBudgetSeconds = max(perGame * 2, 600)

proc record(config: GameConfig, doctrines: array[2, Sheet], seed: int,
            onMaps: seq[string] = @[]):
              tuple[reason: EpisodeReason, ok: bool, games: seq[GameOutcome],
                    doc: ReplayDoc, text: string] =
  var plan = buildPlan(config, doctrines, seed)
  plan.chassis = Chassis
  if onMaps.len > 0:
    plan.maps = onMaps
    plan.sideAslots = @[]
    plan.abandonAfter = @[]
    for m in onMaps:
      plan.sideAslots.add(0)
      plan.abandonAfter.add(-1)
  var events: seq[MatchEvent]
  events.add(ev("episode_start", ms = 0, fields = %*{
    "seed": seed, "year": config.year, "maps": %plan.maps,
    "aliases": [AliasA, AliasB]}))
  let (games, reason) = playMatch(config, plan, events)
  events.add(ev("episode_end", ms = 1, fields = %*{"reason": $reason}))
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: doctrines[slot],
      chassis: (if slot == 0: "wololo" else: "examplefuncsplayer22"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": seed, "year": config.year}, seed: seed, seats: seats,
    events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc22", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))
  let text = $doc.toJson()
  ## Re-derive FROM THE WRITTEN BYTES, exactly as the wasm viewer does.
  let reparsed = parseReplay(text)
  let deriver = newDeriver(reparsed)
  while deriver.advance(): discard
  (reason, deriver.mismatchRound < 0, games, reparsed, text)

proc haveGame[T](name: string, games: seq[T]): bool =
  ## A guard, not a convenience. When an episode aborts, `playMatch` returns
  ## NO finished games, and every `games[0]` below then reads an empty seq:
  ## an IndexDefect that kills the shard before the remaining assertions run
  ## in a debug build, and an UNCHECKED out-of-bounds read in release. Assert
  ## the seq first so a regression reads as a FAIL line, not as a crash.
  check(name, games.len > 0)
  games.len > 0

# --- the written bytes ------------------------------------------------------
block:
  let r = record(bc22Config(700), sheets(), 2029)
  checkEq("the episode completed", r.reason, epComplete)
  check("and it re-derives with NO hash mismatch", r.ok)
  checkEq("the bytes are strict UTF-8", r.text.validateUtf8(), -1)
  ## The RECORDED version is whatever this build stamps, and this shard's job
  ## is to prove it is (a) the build's own headline, (b) a REAL version and
  ## not an empty string, and (c) inside the compatibility list — so a future
  ## year's bump moves the number without weakening the assertion. The
  ## literal `"GV10"` that used to be here made the bc16 run's authorised
  ## GV10 -> GV11 bump look like a bc22 regression, which it is not.
  checkEq("and it is what the build claims", r.doc.gameVersion, GameVersion)
  check("which is a real version headline",
    r.doc.gameVersion.len >= 4 and r.doc.gameVersion.startsWith("GV"))
  check("and it is inside ReplayCompatibleGameVersions",
    r.doc.gameVersion in ReplayCompatibleGameVersions)
  check("as is every version this build claims to keep rendering",
    ReplayCompatibleGameVersions.len >= 8 and
    "GV04" in ReplayCompatibleGameVersions)
  checkEq("the year", r.doc.year, "bc22")
  checkEq("the seed", r.doc.seed, 2029)
  checkEq("both seats", r.doc.seats.len, 2)
  checkEq("the applied sheet survives", r.doc.seats[0].sheet.doctrine22,
    sheets()[0].doctrine22)
  let recorded = sheets()
  checkEq("`sheet_envelope` round-trips", r.doc.seats[0].sheet.envelope,
    recorded[0].envelope)
  checkEq("and `sheet_submitted` too", r.doc.seats[0].sheet.submitted,
    recorded[0].submitted)
  let raw = parseJson(r.text)
  check("the result block is `result`, SINGULAR", raw.hasKey("result"))
  check("and never `results`", not raw.hasKey("results"))
  check("`sheet_envelope` is on the seat record",
    raw["seats"][0].hasKey("sheet_envelope"))
  check("and `sheet_envelope` is in the results document",
    raw["result"].hasKey("sheet_envelope"))
  if haveGame("a game header was recorded", r.doc.games):
    checkEq("the map sha is recorded so a viewer can prove its map bytes",
      r.doc.games[0].mapSha.len, 64)

block:
  ## A best-of-three that CLINCHES in two records TWO games with
  ## `reason: complete` — that is correct, not truncated — and `plan.maps`
  ## still carries all three drawn maps so a spectator can see what the third
  ## would have been.
  let r = record(bc22Config(2000, 3), sheets(), 2029)
  checkEq("the episode completed", r.reason, epComplete)
  checkEq("plan.maps carries all three drawn maps", r.doc.plan.maps.len, 3)
  check("even though the match may have played fewer",
    r.games.len <= 3 and r.games.len >= 2)
  check("and it still re-derives", r.ok)
  var wins = [0, 0]
  for g in r.games:
    if g.winnerSlot >= 0: wins[g.winnerSlot] += 1
  check("a side took the majority", wins[0] >= 2 or wins[1] >= 2)

# --- the per-game event bounds ----------------------------------------------
block:
  let r = record(bc22Config(2000, 3), sheets(), 2029)
  const Bounds = {
    "game_start": 1, "first_action": 4, "lab_built": 12, "first_sage": 2,
    "watchtower_built": 16, "mutation": 24, "gold_milestone": 20,
    "anomaly_struck": 14, "anomaly_dodged": 20, "archon_lost": 8,
    "archon_relocated": 16, "rout": 20, "duel": 20, "singularity": 1,
    "game_end": 1, "game_abandoned": 1}.toTable
  var perGame = initTable[string, CountTable[int]]()
  for e in r.doc.events:
    if e.game < 0: continue
    if not perGame.hasKey(e.kind):
      perGame[e.kind] = initCountTable[int]()
    perGame[e.kind].inc(e.game)
  for kind, counts in perGame:
    check("the event kind " & kind & " has a declared bound",
      Bounds.hasKey(kind))
    if Bounds.hasKey(kind):
      for game, n in counts:
        check(kind & " stays inside its per-game bound of " & $Bounds[kind] &
          " (saw " & $n & " in game " & $game & ")", n <= Bounds[kind])
  check("`anomaly_struck`'s bound covers the MEASURED maximum schedule " &
    "length of 13", Bounds["anomaly_struck"] >= 14)
  check("and a three-game match's whole event list stays small",
    r.doc.events.len < 600)
  ## NO EVENT HAS A FIELD NAMED `kind`: a field called `kind` is flattened into
  ## the same object as the event's own `kind` key and silently overwrites it
  ## (the bc23 r1-F25 finding).
  let raw = parseJson(r.text)
  var badField = 0
  for e in raw["events"]:
    var keys = 0
    for key, _ in e:
      if key == "kind": inc keys
    if keys != 1: inc badField
  checkEq("every event carries exactly one `kind`", badField, 0)
  ## And `first_action`'s vocabulary is DOCUMENTED.
  for e in raw["events"]:
    if e["kind"].getStr() == "first_action":
      check("first_action.action is in Bc22ActionNames",
        e["action"].getStr() in Bc22ActionNames)

# --- determinism, and every end reason --------------------------------------
block:
  let a = record(bc22Config(400), sheets(), 2029, @["chalice"])
  let b = record(bc22Config(400), sheets(), 2029, @["chalice"])
  let okA = haveGame("the first determinism run played a game", a.games)
  let okB = haveGame("and so did the second", b.games)
  if okA and okB:
    checkEq("identical hash chain", a.games[0].hashChain, b.games[0].hashChain)
    checkEq("identical per-round chain", a.games[0].roundChains,
      b.games[0].roundChains)
    check("and the chain records EVERY round",
      a.games[0].roundChains.len == a.games[0].roundsPlayed * ChainHexLen)

block:
  var s = sheets()
  let a = record(bc22Config(400), s, 5, @["chalice"])
  s[0] = parseReply("""{"sheet":{"opening":"soldier_rush",
    "mine_floor":0,"lab_round":80}}""", YearBc22)
  let b = record(bc22Config(400), s, 5, @["chalice"])
  let okA = haveGame("the stock-knob run played a game", a.games)
  let okB = haveGame("and so did the changed-knob run", b.games)
  if okA and okB:
    check("changing a knob changes the hash chain",
      a.games[0].hashChain != b.games[0].hashChain)

block:
  ## The MAP seed, not the episode seed, drives the world RNG.
  let s = sheets()
  let a = record(bc22Config(300), s, 3, @["chalice"])
  let b = record(bc22Config(300), s, 3, @["maze"])
  let okA = haveGame("the chalice run played a game", a.games)
  let okB = haveGame("and so did the maze run", b.games)
  if okA and okB:
    check("different maps produce different chains",
      a.games[0].hashChain != b.games[0].hashChain)

var reDerived: seq[string]
block:
  ## `annihilated`: `wololo` really does kill the scaffold's last archon.
  let r = record(bc22Config(2000), sheets(), 3, @["chalice"])
  checkEq("the game completed", r.reason, epComplete)
  check("and re-derives", r.ok)
  if haveGame("the annihilation run played a game", r.games):
    checkEq("ending on an annihilation", r.games[0].endReason, "annihilated")
    reDerived.add(r.games[0].endReason)

block:
  ## The Singularity rungs: a MIRROR that no side can break inside the cap.
  let mirrorPair = [baselineSheet("bc22", blWololo),
                    baselineSheet("bc22", blWololo)]
  var config = bc22Config(2000)
  var plan = buildPlan(config, mirrorPair, 11)
  plan.chassis = [scWololo, scWololo]
  plan.maps = @["chalice"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[-1]
  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  checkEq("the mirror completed", reason, epComplete)
  if haveGame("the mirror played a game", games):
    check("on a Singularity rung",
      games[0].endReason in ["more_archons", "more_gold_net_worth",
                             "more_lead_net_worth", "coin_flip"])
    reDerived.add(games[0].endReason)

block:
  ## THE WALL-CLOCK STOP is a load-bearing RECORD, applied by the same proc on
  ## record and on playback. A one-second budget abandons the first game —
  ## and one second is the FLOOR `playMatch` clamps to, which is why the
  ## other blocks must not ask for zero.
  var config = bc22Config(2000)
  config.perGameBudgetSeconds = 1
  config.matchBudgetSeconds = 1
  var plan = buildPlan(config, sheets(), 13)
  plan.chassis = Chassis
  plan.maps = @["vortex"]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[-1]
  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  check("a one-second budget on the 60x60 map stops the episode",
    reason in [epDeadline, epComplete])
  if reason == epDeadline:
    check("and the round it stopped at is RECORDED",
      plan.abandonAfter[0] >= 0)
    reDerived.add("abandoned")

block:
  check("the shard proved `annihilated`", "annihilated" in reDerived)
  check("and at least one Singularity rung",
    reDerived.len >= 2)

finish("test_bc22_replay")
