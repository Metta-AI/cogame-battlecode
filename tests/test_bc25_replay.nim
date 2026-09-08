## bc25 determinism and replay: same seed + same sheets => identical hash
## chain; record -> RE-DERIVE for EVERY bc25 end reason including the
## wall-clock stop; a STRICT UTF-8 parse of the written bytes; paint, markers,
## towers, SRPs and chips re-derived from events + config + seed with NOTHING
## STORED; and EVERY event kind inside its per-game bound.

import std/[json, strutils, tables, unicode]
import harness
import bc25_fixture
import battlecode/[baselines, broadcast, match, replay, results]
import battlecode/years/dispatch

const Chassis = [scSpaark, scExamplefuncsplayer25]

proc sheets(): array[2, Sheet] =
  [baselineSheet("bc25", blSpaark),
   baselineSheet("bc25", blExamplefuncsplayer25)]

# --- the same world twice ---------------------------------------------------
block:
  let s = sheets()
  let (a, _) = playGameFor("bc25", "Filter", s, Chassis, 0, 0, 400, 0)
  let (b, _) = playGameFor("bc25", "Filter", s, Chassis, 0, 0, 400, 0)
  checkEq("identical hash chain", a.hashChain, b.hashChain)
  checkEq("identical rounds", a.roundsPlayed, b.roundsPlayed)
  checkEq("identical points", a.points, b.points)
  checkEq("identical end reason", a.endReason, b.endReason)
  checkEq("identical per-round chain", a.roundChains, b.roundChains)

block:
  ## A different doctrine really is a different world.
  var s = sheets()
  let a = playGameFor("bc25", "Justice", s, Chassis, 0, 0, 400, 0)[0]
  s[0] = parseReply("""{"sheet":{"opening":"tower_rush",
    "ruin_claim_radius":20}}""", YearBc25)
  let b = playGameFor("bc25", "Justice", s, Chassis, 0, 0, 400, 0)[0]
  check("changing a knob changes the hash chain", a.hashChain != b.hashChain)

block:
  ## The MAP seed, not the episode seed, drives the id generator.
  let s = sheets()
  let a = playGameFor("bc25", "Filter", s, Chassis, 0, 0, 300, 0)[0]
  let b = playGameFor("bc25", "Justice", s, Chassis, 0, 0, 300, 0)[0]
  check("different maps produce different chains", a.hashChain != b.hashChain)

# --- record -> re-derive, for every end reason ------------------------------
proc record(mapName: string, rounds: int, s: array[2, Sheet],
            abandonAfter = -1): (ReplayDoc, string) =
  var config = defaultGameConfig()
  config.year = "bc25"
  config.pool = "small"
  config.gamesPerMatch = 1
  config.maxRounds = rounds
  var plan = buildPlan(config, s, 3)
  plan.chassis = Chassis
  plan.maps = @[mapName]
  plan.sideAslots = @[0]
  plan.abandonAfter = @[abandonAfter]
  var events: seq[MatchEvent]
  let (games, reason) = playMatch(config, plan, events)
  var seats: array[2, SeatReport]
  for slot in 0 .. 1:
    seats[slot] = SeatReport(name: "seat" & $slot, alias: aliasFor(slot),
      policyKind: "scripted", sheet: s[slot],
      chassis: (if slot == 0: "spaark" else: "examplefuncsplayer25"))
  var doc = ReplayDoc(gameVersion: GameVersion, year: "bc25",
    config: %*{"seed": 3, "year": "bc25"}, seed: 3, seats: seats,
    events: events,
    result: resultsJson(seats, games, plan, reason, 0.0, 0.0), plan: plan)
  for slot in 0 .. 1: doc.names[slot] = "seat" & $slot
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha("bc25", g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))
  (doc, $doc.toJson())

proc rederives(text: string): int =
  let d = newDeriver(parseReplay(text))
  while d.advance(): discard
  d.mismatchRound

block:
  ## Every end reason a bc25 game can reach, recorded and re-derived.
  var seen: seq[string]
  for (mapName, rounds, s) in [
      ("Filter", 400, sheets()),
      ("Justice", 900, sheets()),
      ("DefaultSmall", 2000, sheets()),
      ("Filter", 2000, [baselineSheet("bc25", blSpaark),
                        baselineSheet("bc25", blSpaark)])]:
    let (doc, text) = record(mapName, rounds, s)
    let reason = doc.result{"games"}[0]{"end_reason"}.getStr()
    if reason notin seen: seen.add(reason)
    checkEq(mapName & "/" & $rounds & " (" & reason & ") re-derives clean",
      rederives(text), -1)
  check("and more than one end reason was actually exercised", seen.len >= 2)

block:
  ## The wall-clock stop is ONE LOAD-BEARING RECORD applied by the same proc
  ## on record and on playback -- the particle-worlds scar.
  let (doc, text) = record("Filter", 400, sheets(), abandonAfter = 120)
  let back = parseReplay(text)
  checkEq("`abandon_after` survives the round trip",
    back.plan.abandonAfter, doc.plan.abandonAfter)

block:
  ## A STRICT UTF-8 parse of the written bytes, with astral-plane text in the
  ## free-text fields.
  var s = sheets()
  s[0].notes = "Portal \u2192 \U0001F3A8 \u00e9\u00e8\u00ea their money tower"
  s[0].motto = "\U0001F3A8 two colours, one map"
  let (_, text) = record("Filter", 200, s)
  checkEq("the recording is valid UTF-8", text.validateUtf8(), -1)
  let doc = parseJson(text)
  checkEq("and it parses", doc["format"].getStr(), ReplayFormat)
  checkEq("with the year on the header", doc["year"].getStr(), "bc25")
  checkEq("and the GameVersion", doc["game_version"].getStr(), GameVersion)
  check("the astral-plane note survived",
    doc["seats"][0]["notes"].getStr().contains("\U0001F3A8"))

block:
  ## NOTHING about paint, markers, towers, SRPs or chips is stored: the wasm
  ## sim re-derives every round. The proof is that the recording carries no
  ## per-round state at all.
  let (_, text) = record("Filter", 200, sheets())
  let doc = parseJson(text)
  for forbidden in ["paint_array", "marker_array", "colour_array", "board",
                    "grid", "towers_by_round", "per_round", "tile_array"]:
    check("the replay stores no " & forbidden, forbidden notin text)
  check("it is a few kilobytes, not a few megabytes", text.len < 200_000)
  checkEq("and the only per-round bytes are the hash chain",
    doc["games"][0]["hash_chain_rounds"].getStr().len, 200 * 16)

block:
  ## The re-derivation reproduces the recorded per-round hashes, and the
  ## chrome document built off it names the re-derived totals.
  let (_, text) = record("Filter", 300, sheets())
  let back = parseReplay(text)
  let d = newDeriver(back)
  var frames = 0
  while d.advance(): frames += 1
  checkEq("300 frames", frames, 300)
  checkEq("no mismatch", d.mismatchRound, -1)
  let chrome = parseJson(sessionChromeJson(back, d.session,
    initViewerState(), frames - 1, frames, 0, 0, newJArray(), newJArray(),
    true))
  checkEq("the chrome says bc25", chrome["year"].getStr(), "bc25")
  check("it carries the coverage readout", chrome.hasKey("bc25_coverage"))
  check("the tower readout", chrome.hasKey("bc25_towers"))
  check("the economy readout", chrome.hasKey("bc25_econ"))
  check("and the war panel", chrome.hasKey("bc25_war"))
  check("coverage is re-derived, not stored",
    chrome["bc25_coverage"]["clans"][0]["tiles"].getInt() > 0)
  checkEq("the denominator is the engine's own",
    chrome["bc25_coverage"]["area_without_walls"].getInt(),
    newWorld(loadMap("Filter"), 300).areaWithoutWalls)

# --- the event bounds -------------------------------------------------------
block:
  ## EVERY event kind respects its per-game bound, so a pathological game
  ## cannot produce a 20 MB replay.
  const Bounds = {
    "game_start": 1, "first_action": 4, "tower_built": 50,
    "tower_upgraded": 50, "tower_lost": 50, "srp_completed": 20,
    "srp_active": 20, "srp_broken": 20, "coverage": 14, "starved": 20,
    "rout": 20, "game_end": 1, "game_abandoned": 1}.toTable
  for mapName in ["Filter", "Justice", "DefaultSmall"]:
    let (doc, _) = record(mapName, 2000, sheets())
    var counts = initTable[string, int]()
    for e in doc.events:
      if e.game < 0: continue
      counts[e.kind] = counts.getOrDefault(e.kind, 0) + 1
    for kind, n in counts:
      if kind notin Bounds:
        check(mapName & ": event kind `" & kind & "` has a documented bound",
          false)
      else:
        check(mapName & ": " & kind & " x" & $n & " is inside its bound of " &
          $Bounds[kind], n <= Bounds[kind])
    check(mapName & ": the whole event list is a few hundred entries",
      doc.events.len < 400)
    check(mapName & ": and it is not empty", doc.events.len > 5)

block:
  ## `first_action.action` has a documented vocabulary, and the field is
  ## called `action` and NOT `kind` -- a field called `kind` would silently
  ## overwrite the event's own kind (the bc24 scar).
  let (doc, _) = record("Filter", 400, sheets())
  var saw = 0
  for e in doc.events:
    if e.kind != "first_action": continue
    saw += 1
    let action = e.fields{"action"}.getStr()
    check("`" & action & "` is in Bc25ActionNames", action in Bc25ActionNames)
    check("and the event kind survived", e.kind == "first_action")
  check("first_action really fired", saw > 0)

block:
  ## The note's event table, field for field, for the two kinds that were
  ## short of it (r1-F11): `tower_lost` names how many towers the clan has
  ## LEFT, and `srp_active` names how many patterns are live, not just the
  ## bonus one of them pays.
  var sawLost, sawActive = 0
  for mapName in ["Filter", "Justice"]:
    let (doc, _) = record(mapName, 2000, sheets())
    for e in doc.events:
      case e.kind
      of "tower_lost":
        sawLost += 1
        for field in ["alias", "tower", "x", "y", "remaining"]:
          check("tower_lost carries `" & field & "`", e.fields.hasKey(field))
        check("and `remaining` counts what is left, after the loss",
          e.fields{"remaining"}.getInt() >= 0)
      of "srp_active":
        sawActive += 1
        for field in ["alias", "x", "y", "active_total", "income_bonus"]:
          check("srp_active carries `" & field & "`", e.fields.hasKey(field))
        checkEq("and the bonus is 3 chips a tower per live pattern",
          e.fields{"income_bonus"}.getInt(),
          e.fields{"active_total"}.getInt() * 3)
      of "coverage":
        for field in ["alias", "permille", "tiles_from_win"]:
          check("coverage carries `" & field & "`", e.fields.hasKey(field))
      else: discard
  check("a tower was really lost in one of those games", sawLost > 0)
  check("and a resource pattern really went live", sawActive > 0)

block:
  ## The committed fixture still re-derives at this GameVersion.
  let text = readFile("tests/fixtures/replay-bc25.json")
  let doc = parseReplay(text)
  checkEq("the fixture is bc25", doc.year, "bc25")
  checkEq("at the current GameVersion", doc.gameVersion, GameVersion)
  checkEq("and it re-derives clean", rederives(text), -1)

finish("test_bc25_replay")
