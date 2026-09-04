## Same seed + same sheets ⇒ identical hash chain, twice in one process and
## across a save/load, and RECORD → RE-DERIVE for EVERY end reason.
##
## The wall-clock `deadline` stop is the one fact a re-derivation cannot
## recompute, so it is recorded as one load-bearing value
## (`plan.abandon_after[g]`) and applied by the same code on both paths — the
## particle-worlds 2026-08-26 scar.

import std/[json, strutils]
import harness
import battlecode/[baselines, match, replay, results, sheet, sim_types]
import battlecode/years/bc26/[constants, maps, rules, world]

proc play(mapName: string, sheets: array[2, Sheet], rounds: int,
          sideAslot = 0): GameOutcome =
  let (w, outcome) = playGame(loadMap(mapName), sheets, 0, sideAslot, rounds, 0)
  outcome

# --- the same world twice ---------------------------------------------------
block:
  let sheets = [baselineSheet(blAwu), baselineSheet(blScaffold)]
  let a = play("DefaultSmall", sheets, 400)
  let b = play("DefaultSmall", sheets, 400)
  checkEq("identical hash chain", a.hashChain, b.hashChain)
  checkEq("identical rounds", a.roundsPlayed, b.roundsPlayed)
  checkEq("identical points", a.points, b.points)
  checkEq("identical end reason", a.endReason, b.endReason)
  checkEq("identical cheese", a.cheeseTransferred, b.cheeseTransferred)
  checkEq("identical cat damage", a.catDamage, b.catDamage)

# --- a different doctrine really is a different world -----------------------
block:
  let sheets = [baselineSheet(blAwu), baselineSheet(blScaffold)]
  var swarm = sheets
  swarm[0] = parseReply("""{"sheet":{"spawn_curve":"swarm"}}""")
  let a = play("DefaultSmall", sheets, 300)
  let b = play("DefaultSmall", swarm, 300)
  check("changing a knob changes the hash chain", a.hashChain != b.hashChain)

# --- the map seed, not the episode seed, drives the world RNG ---------------
block:
  ## Two different maps have different `randomSeed`s and therefore different
  ## cheese spawns and robot ids.
  let sheets = [baselineSheet(blAwu), baselineSheet(blAwu)]
  let a = play("DefaultSmall", sheets, 200)
  let b = play("arrows", sheets, 200)
  check("different maps produce different chains", a.hashChain != b.hashChain)

# --- record → re-derive, for EVERY end reason -------------------------------
proc deriveAndCompare(config: GameConfig, sheets: array[2, Sheet],
                      seed: int, onMaps: seq[string] = @[]):
                        tuple[reason: EpisodeReason, ok: bool,
                              outcomes: seq[GameOutcome]] =
  var plan = buildPlan(config, sheets, seed)
  if onMaps.len > 0:
    ## A specific map, when the end reason under test needs one: the draw is
    ## by seed, and no seed is guaranteed to land on the map that produces it.
    plan.maps = onMaps
    plan.sideAslots = @[]
    plan.abandonAfter = @[]
    for m in onMaps:
      plan.sideAslots.add(0)
      plan.abandonAfter.add(-1)
  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: sheets[slot])
  var doc = ReplayDoc(gameVersion: GameVersion, year: config.year,
    config: %*{"seed": seed}, seed: seed, seats: seats, events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha(g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain))
  ## Re-derive from the written bytes, exactly as the wasm viewer does.
  let reparsed = parseReplay($doc.toJson())
  let deriver = newDeriver(reparsed)
  while deriver.advance(): discard
  (reason, deriver.mismatchRound < 0, games)

var seenReasons: seq[EndReason]
block:
  ## `round_limit`: a short game that neither side can finish.
  var config = defaultGameConfig()
  config.pool = "small"
  config.gamesPerMatch = 1
  config.maxRounds = 120
  let sheets = [baselineSheet(blScaffold), baselineSheet(blScaffold)]
  let r = deriveAndCompare(config, sheets, 7)
  checkEq("a short scaffold game completes", r.reason, epComplete)
  check("and re-derives with no hash mismatch", r.ok)
  checkEq("one game was recorded", r.outcomes.len, 1)
  checkEq("and it ended on the round limit", r.outcomes[0].endReason,
    erRoundLimit)
  seenReasons.add(r.outcomes[0].endReason)

block:
  ## `kings_destroyed`: awu starves scaffold's crowns out.
  var config = defaultGameConfig()
  config.pool = "small"
  config.gamesPerMatch = 1
  config.maxRounds = 2000
  let sheets = [baselineSheet(blAwu), baselineSheet(blScaffold)]
  let r = deriveAndCompare(config, sheets, 3)
  checkEq("a full game completes", r.reason, epComplete)
  check("and re-derives with no hash mismatch", r.ok)
  checkEq("one game was recorded", r.outcomes.len, 1)
  checkEq("and it ended on the kings", r.outcomes[0].endReason,
    erKingsDestroyed)
  seenReasons.add(r.outcomes[0].endReason)

block:
  ## `cats_cleared`: every cat dead WHILE the alliance holds ends the game on
  ## the tiebreak ladder rather than on kings. Cats have 4 000 hp, so this is
  ## driven at the world level rather than waited for.
  let w = newWorld(loadMap("DefaultSmall"), 2000)
  w.teamInfo.damageToCats = [10, 0]
  for r in w.liveRobots:
    if r.unit == utCat:
      w.destroyRobot(r.id)
  checkEq("every cat is gone", w.numCats, 0)
  check("the world stops running", not w.running or w.hasWinner)
  check("and a winner was set", w.hasWinner)
  check("on points, not on kings", w.domination != dfKillAllRatKings)

  ## And the same reason RECORDED and RE-DERIVED, from a match that really
  ## reaches it: two cat-hunting clans that never turn on each other clear
  ## `cheesefarm`'s cats around round 420. Before r1-N13b this end reason was
  ## the only one with no record -> re-derive at all.
  var config = defaultGameConfig()
  config.pool = "small"
  config.gamesPerMatch = 1
  config.maxRounds = 2000
  let hunter = parseReply("""{"sheet":{"cat_engagement":"hunt",
    "cat_trap_budget":200,"backstab_policy":"never"}}""")
  let r = deriveAndCompare(config, [hunter, hunter], 11, @["cheesefarm"])
  checkEq("the cat hunt completes", r.reason, epComplete)
  checkEq("one game was recorded", r.outcomes.len, 1)
  checkEq("and it ended with the cats cleared", r.outcomes[0].endReason,
    erCatsCleared)
  check("and re-derives with no hash mismatch", r.ok)
  seenReasons.add(r.outcomes[0].endReason)

block:
  ## `deadline`: the wall-clock stop is RECORDED, and the re-derivation
  ## replays to exactly the round the recorder stopped at. This is the
  ## particle-worlds scar: a stop derived from the recorder's clock and
  ## re-derived from the viewer's clock is not the same match.
  ##
  ## The document is built in the shape THE RECORDER ACTUALLY WRITES: when
  ## `playMatch` abandons a game it records `plan.abandonAfter[g]` and breaks
  ## BEFORE `outcomes.add`, so the abandoned game never reaches
  ## `server.nim`'s `for g in games: doc.games.add(...)` and the replay
  ## carries NO `GameHeader` for it. `plan.abandon_after` is then the only
  ## record of how far that game got, and the deriver has to plan its frames
  ## from it — before r1-N4 it planned frames from `doc.games` alone and
  ## dropped the abandoned game (and, in a one-game match, the whole replay)
  ## on the floor. (The stop is not driven by the real clock here: a game
  ## plays in milliseconds and the smallest budget `playGame` accepts is a
  ## whole second.)
  let sheets = [baselineSheet(blAwu), baselineSheet(blAwu)]
  let full = play("DefaultSmall", sheets, 2000)
  check("the full game runs past 200 rounds", full.roundsPlayed > 200)
  let stoppedAt = 200
  var config = defaultGameConfig()
  config.pool = "small"
  config.gamesPerMatch = 1
  var plan = buildPlan(config, sheets, 5)
  plan.maps = @["DefaultSmall"]
  plan.sideAslots = @[0]
  plan.maxRounds = 2000
  plan.abandonAfter[0] = stoppedAt        # what playMatch records on abort
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: sheets[slot])
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc26", config: %*{},
    seed: 5, seats: seats, plan: plan, result: %*{})
  for slot in 0 .. 1: doc.names[slot] = "s" & $slot
  checkEq("the abandoned game has no header, as the recorder writes it",
    doc.games.len, 0)
  let deriver = newDeriver(parseReplay($doc.toJson()))
  checkEq("the deriver plans exactly the recorded rounds",
    deriver.totalFrames, stoppedAt)
  var frames = 0
  while deriver.advance(): inc frames
  checkEq("and stops exactly there", frames, stoppedAt)
  checkEq("at the recorded round", deriver.world.currentRound, stoppedAt)
  checkEq("with no hash mismatch", deriver.mismatchRound, -1)
  ## `abandoned` is the one end reason that never reaches `results.games[]`
  ## (playMatch discards the game); its record -> re-derive is this block.
  seenReasons.add(erAbandoned)

block:
  ## The scoring of a deadline episode is honest: only the games that
  ## FINISHED are scored, and an episode where none did scores zero.
  var noGames: seq[GameOutcome]
  checkEq("no finished game scores zero", scoresFor(noGames), [0.0, 0.0])
  checkEq("episode reasons are the closed enum", EpisodeReasons.len, 3)

# --- a save/load round trip keeps the chain ---------------------------------
block:
  let sheets = [baselineSheet(blAwu), baselineSheet(blScaffold)]
  let outcome = play("closeup", sheets, 300)
  var plan = MatchPlan(seed: 1, year: "bc26", maxRounds: 300,
    maps: @["closeup"], sideAslots: @[0], abandonAfter: @[-1], sheets: sheets)
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "s" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: sheets[slot])
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc26",
    config: %*{}, seed: 1, seats: seats, plan: plan,
    result: %*{}, games: @[GameHeader(index: 0, map: "closeup",
      mapSha: mapSha("closeup"), sideAslot: 0, rounds: outcome.roundsPlayed,
      hashChain: outcome.hashChain)])
  for slot in 0 .. 1: doc.names[slot] = "s" & $slot
  let text = $doc.toJson()
  let deriver = newDeriver(parseReplay(text))
  while deriver.advance(): discard
  checkEq("the re-derived chain matches the recorded one",
    toHex(deriver.world.hashChain), outcome.hashChain)
  checkEq("and no mismatch round is reported", deriver.mismatchRound, -1)
  ## And once more from the same bytes, to prove the reader is pure.
  let again = newDeriver(parseReplay(text))
  while again.advance(): discard
  checkEq("re-reading the same bytes gives the same chain",
    toHex(again.world.hashChain), outcome.hashChain)

# --- EVERY end reason was covered above -------------------------------------
block:
  ## `seenReasons` was declared and never used, so "record -> re-derive for
  ## every end reason" was a claim no assertion made (r1-N13b). Now the
  ## blocks fill it and this fails if one is ever dropped.
  for reason in EndReason:
    check("record -> re-derive covered " & $reason, reason in seenReasons)

finish("test_determinism")
