## The replay: one UTF-8 JSON document that is SELF-SUFFICIENT by
## RE-DERIVATION, not by bulk.
##
## Names, config, seed, both doctrine sheets, the map identity (with a
## sha256 of the committed converted map the bundle also ships) and the
## event list are all in the file, and the wasm sim replays every round from
## them. No engine bytes, no per-round state dump, no server contacted except
## S3 for the `.replay` file. The per-game hash chain lets the viewer prove
## its re-derivation matches the recording (`bc_mismatch_round`).

import std/[json, strutils]
import crunchy/sha256
import sim_types, sheet, match, results
import years/bc26/maps

export match

const ChainHexLen* = 16
  ## `toHex(uint64)` — one round's hash chain, as recorded in
  ## `games[].hash_chain_rounds`.

type
  GameHeader* = object
    index*: int
    map*: string
    mapSha*: string
    sideAslot*: int
    rounds*: int
    hashChain*: string
    roundChains*: string
      ## 16 hex digits per round, in round order — the chain as it stood at
      ## the end of each round. The deriver compares EVERY round against it.

  ReplayDoc* = object
    gameVersion*: string
    year*: string
    config*: JsonNode
    seed*: int
    names*: array[2, string]
    seats*: array[2, SeatReport]
    games*: seq[GameHeader]
    events*: seq[MatchEvent]
    result*: JsonNode
    plan*: MatchPlan

proc sha256Hex*(data: string): string =
  ## The provenance tag on each converted map, so a viewer can prove it is
  ## re-deriving against the same map bytes the server played.
  for b in sha256(data):
    result.add(toHex(b, 2).toLowerAscii())

proc mapSha*(name: string): string =
  try:
    sha256Hex(readFile(mapPath(name)))
  except CatchableError:
    ""

proc seatJson(seat: SeatReport, slot: int): JsonNode =
  var applied = newJArray()
  for field in seat.sheet.defaultsApplied: applied.add(%field)
  var unknown = newJArray()
  for field in seat.sheet.unknownFields: unknown.add(%field)
  result = %*{
    "slot": slot,
    "alias": seat.alias,
    "name": seat.name,
    "policy": seat.policyKind,
    "sheet": seat.sheet.toJson(),
    "sheet_submitted": seat.sheet.submitted,
    "sheet_defaults_applied": applied,
    "sheet_unknown_fields": unknown,
    "notes": seat.sheet.notes,
    "motto": seat.sheet.motto,
    "decision_ms": seat.decisionMs
  }
  if seat.fallback.len > 0:
    result["fallback"] = %seat.fallback
  else:
    result["fallback"] = newJNull()

proc toJson*(doc: ReplayDoc): JsonNode =
  var seats = newJArray()
  for slot in 0 .. 1:
    seats.add(seatJson(doc.seats[slot], slot))
  var games = newJArray()
  for g in doc.games:
    games.add(%*{
      "index": g.index,
      "map": g.map,
      "map_json_sha256": g.mapSha,
      "sides": [(if g.sideAslot == 0: "A" else: "B"),
                (if g.sideAslot == 0: "B" else: "A")],
      "side_a_slot": g.sideAslot,
      "rounds": g.rounds,
      "hash_chain_sha256": g.hashChain,
      "hash_chain_rounds": g.roundChains
    })
  var events = newJArray()
  for e in doc.events:
    events.add(e.toJson())
  %*{
    "format": ReplayFormat,
    "version": ReplayFormatVersion,
    "protocol": ProtocolId,
    "game_version": doc.gameVersion,
    "year": doc.year,
    "config": doc.config,
    "seed": doc.seed,
    "aliases": [AliasA, AliasB],
    "names": [doc.names[0], doc.names[1]],
    "seats": seats,
    "games": games,
    "plan": %*{
      "maps": doc.plan.maps,
      "side_a_slots": doc.plan.sideAslots,
      "abandon_after": doc.plan.abandonAfter,
      "max_rounds": doc.plan.maxRounds
    },
    "events": events,
    "result": doc.result
  }

# ---------------------------------------------------------------------------
#  Reading, and the re-derivation driver the wasm viewer runs
# ---------------------------------------------------------------------------

type
  Deriver* = ref object
    ## Steps the SAME sim module the server ran, one round per frame, from
    ## the replay's config + seed + sheets. The viewer never re-implements a
    ## rule; it re-plays the match.
    doc*: ReplayDoc
    raw*: JsonNode
    gameIndex*: int
    roundInGame*: int
    frame*: int
    totalFrames*: int
    world*: World
    clans*: array[2, Clan]
    mismatchRound*: int
    frameGame*: seq[int]
    frameRound*: seq[int]

proc parseSeat(node: JsonNode): SeatReport =
  result.name = node{"name"}.getStr()
  result.alias = node{"alias"}.getStr()
  result.policyKind = node{"policy"}.getStr("scripted")
  result.decisionMs = node{"decision_ms"}.getInt()
  if node{"fallback"} != nil and node["fallback"].kind == JString:
    result.fallback = node["fallback"].getStr()
  var wrapper = newJObject()
  wrapper["sheet"] = node{"sheet"}
  wrapper["notes"] = %node{"notes"}.getStr()
  wrapper["motto"] = %node{"motto"}.getStr()
  result.sheet = validate(wrapper)
  result.sheet.notes = node{"notes"}.getStr()
  result.sheet.motto = node{"motto"}.getStr()
  result.sheet.submitted = node{"sheet_submitted"}.getStr("{}")

proc parseReplay*(text: string): ReplayDoc =
  let doc = parseJson(text)
  if doc{"format"}.getStr() != ReplayFormat:
    raise newException(BattlecodeError,
      "not a " & ReplayFormat & " document")
  let version = doc{"game_version"}.getStr()
  if version notin ReplayCompatibleGameVersions:
    raise newException(BattlecodeError,
      "replay game_version " & version & " cannot be re-derived by this " &
      "build (" & GameVersion & ")")
  result.gameVersion = version
  result.year = doc{"year"}.getStr("bc26")
  result.config = doc{"config"}
  result.seed = doc{"seed"}.getInt()
  for slot in 0 .. 1:
    result.names[slot] = doc["names"][slot].getStr()
    result.seats[slot] = parseSeat(doc["seats"][slot])
  for g in doc["games"]:
    result.games.add(GameHeader(
      index: g{"index"}.getInt(),
      map: g{"map"}.getStr(),
      mapSha: g{"map_json_sha256"}.getStr(),
      sideAslot: g{"side_a_slot"}.getInt(),
      rounds: g{"rounds"}.getInt(),
      hashChain: g{"hash_chain_sha256"}.getStr(),
      roundChains: g{"hash_chain_rounds"}.getStr()))
  for e in doc["events"]:
    var fields = newJObject()
    for key, value in e:
      if key notin ["kind", "ms", "game", "round"]:
        fields[key] = value
    result.events.add(MatchEvent(
      kind: e{"kind"}.getStr(),
      ms: (if e.hasKey("ms"): e["ms"].getInt() else: -1),
      game: (if e.hasKey("game"): e["game"].getInt() else: -1),
      round: (if e.hasKey("round"): e["round"].getInt() else: -1),
      fields: fields))
  result.result = doc{"result"}
  let plan = doc["plan"]
  result.plan.seed = result.seed
  result.plan.year = result.year
  result.plan.maxRounds = plan{"max_rounds"}.getInt(2000)
  for v in plan["maps"]: result.plan.maps.add(v.getStr())
  for v in plan["side_a_slots"]: result.plan.sideAslots.add(v.getInt())
  for v in plan["abandon_after"]: result.plan.abandonAfter.add(v.getInt())
  result.plan.sheets[0] = result.seats[0].sheet
  result.plan.sheets[1] = result.seats[1].sheet

proc startGame(d: Deriver, index: int) =
  d.gameIndex = index
  d.roundInGame = 0
  if index < d.doc.plan.maps.len:
    let spec = loadMap(d.doc.plan.maps[index])
    d.world = newWorld(spec, d.doc.plan.maxRounds)
    d.clans = newClans(d.doc.plan.sheets, d.doc.plan.sideAslots[index])

proc gameRecord*(doc: ReplayDoc, index: int):
    tuple[rounds: int, chain: string, rounds_chains: string] =
  ## How many rounds game `index` played, and the chain it ended on.
  ##
  ## A game that FINISHED carries its own header. The game the wall-clock
  ## deadline stopped does not: it is discarded from the scoring, so no
  ## `GameHeader` is written for it — and its stop round survives only as
  ## `plan.abandon_after[index]`, the one load-bearing record of a
  ## wall-clock fact. Read it here and playback stops exactly where the
  ## recorder stopped, instead of dropping the abandoned game from the
  ## replay altogether.
  for g in doc.games:
    if g.index == index:
      return (g.rounds, g.hashChain, g.roundChains)
  if index < doc.plan.abandonAfter.len and doc.plan.abandonAfter[index] > 0:
    return (doc.plan.abandonAfter[index], "", "")
  (0, "", "")

proc newDeriver*(doc: ReplayDoc): Deriver =
  result = Deriver(doc: doc, mismatchRound: -1)
  for index in 0 ..< doc.plan.maps.len:
    for r in 1 .. doc.gameRecord(index).rounds:
      result.frameGame.add(index)
      result.frameRound.add(r)
  result.totalFrames = result.frameGame.len
  result.frame = -1
  if result.totalFrames > 0:
    result.startGame(result.frameGame[0])

proc restart*(d: Deriver) =
  d.frame = -1
  d.mismatchRound = -1
  if d.totalFrames > 0:
    d.startGame(d.frameGame[0])

proc advance*(d: Deriver): bool {.discardable.} =
  ## One frame == one round. Returns false at the end of the recording.
  if d.frame + 1 >= d.totalFrames:
    return false
  let nextFrame = d.frame + 1
  let wantGame = d.frameGame[nextFrame]
  if wantGame != d.gameIndex or d.world == nil:
    d.startGame(wantGame)
  runRound(d.world, d.clans)
  d.roundInGame = d.world.currentRound
  d.frame = nextFrame
  ## The recorded hash chain proves the re-derivation matches the recording.
  ## EVERY round is compared, against the chain the recorder was on at the end
  ## of that round, so the round reported is the FIRST divergent one. The
  ## game's final chain is still checked on its own (it is all an older
  ## recording, or the abandoned game, carries).
  if d.mismatchRound < 0:
    let record = d.doc.gameRecord(wantGame)
    let at = (d.roundInGame - 1) * ChainHexLen
    let here = toHex(d.world.hashChain)
    if record.rounds_chains.len >= at + ChainHexLen and
        here != record.rounds_chains[at ..< at + ChainHexLen]:
      d.mismatchRound = d.roundInGame
    elif d.roundInGame == record.rounds and record.chain.len > 0 and
        here != record.chain:
      d.mismatchRound = d.roundInGame
  true

proc seek*(d: Deriver, frame: int) =
  ## Backward seeks restart and replay. A full match is a couple of thousand
  ## rounds and re-derives in about a second, which is cheaper and far safer
  ## than snapshotting a live sim.
  let target = clamp(frame, 0, max(0, d.totalFrames - 1))
  if target < d.frame:
    d.restart()
  while d.frame < target:
    if not d.advance(): break
