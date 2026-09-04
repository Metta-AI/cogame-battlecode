## The game container: mummy + `bitworld/runtime`.
##
## Routes: `/healthz`, the `/player` seat websocket, `/global` (and
## `/client/global`) for a spectator, and the artifact writes. The episode is
## one sealed doctrine turn followed by the match, so the server is small on
## purpose — everything watchable is the recorded replay re-derived in the
## browser, not a live pod.
##
## Two scars are load-bearing here:
##  * `/healthz` and `/global` keep answering for a ~20 s shutdown grace
##    AFTER the artifacts are written (the lantern 0.1.3 scar), and
##  * the websocket handler keeps its `Ping -> Pong` branch and does NOT
##    filter non-text frames — the player registers with a BINARY message
##    (the lux-ai / snake-royale scar).

import std/[json, locks, monotimes, os, strutils, times]
import mummy, mummy/routers
import bitworld/[runtime, spriteprotocol]
import seats, sim_types, sheet, baselines, decide, match, replay, results
import years/[registry, dispatch]

type
  AppState = object
    lock: Lock
    registered: array[2, bool]
    policy: array[2, SeatPolicy]
    phase: string
    resultsDoc: string

var app: AppState

var
  viewerLock: Lock
  viewers: seq[WebSocket]
    ## Every live `/global` spectator socket. Guarded by `viewerLock`;
    ## mummy's `send` only enqueues, so pushing from the episode thread and
    ## from the heartbeat is safe.
  viewersRunning: bool

proc initAppState() =
  initLock(app.lock)
  app.phase = "waiting for seats"
  app.resultsDoc = "{}"
  for slot in 0 .. 1:
    app.policy[slot].label = "awu"

proc globalJson(): string {.gcsafe.}

proc pushGlobal() {.gcsafe.} =
  ## One frame of the global channel to every spectator. Sent as TEXT (the
  ## same JSON document `GET /global` returns) and again as a Sprite v1 chat
  ## blob, so a bitworld client and a plain websocket client both get
  ## something they can read.
  {.gcsafe.}:
    let payload = globalJson()
    let blob = blobFromSpriteChat(payload)
    withLock viewerLock:
      for viewer in viewers:
        viewer.send(payload, TextMessage)
        viewer.send(blob, BinaryMessage)

proc setPhase(text: string) =
  {.gcsafe.}:
    withLock app.lock:
      app.phase = text
  echo "battlecode: ", text
  pushGlobal()

proc globalJson(): string {.gcsafe.} =
  {.gcsafe.}:
    withLock app.lock:
      return $(%*{
        "game": GameName,
        "protocol": ProtocolId,
        "game_version": GameVersion,
        "phase": app.phase,
        "seats": [app.registered[0], app.registered[1]],
        "result": parseJson(app.resultsDoc)
      })

proc slotOfRequest(request: Request): int =
  let raw = request.queryParams.getOrDefault("slot", "0")
  try: clamp(parseInt(raw), 0, 1) except CatchableError: 0

var seatTokens: seq[string]
  ## Set ONCE from the resolved config, before the listener opens, and only
  ## read after — so every handler thread shares an immutable value.

proc joinError(slot: int, token: string): string {.gcsafe.} =
  {.gcsafe.}:
    return seatJoinError(seatTokens, slot, token)

proc applyRegistration(slot: int, payload: string) =
  var node: JsonNode
  try:
    node = parseJson(payload)
  except CatchableError:
    echo "battlecode: seat ", slot, " sent an unreadable registration"
    return
  if node{"type"}.getStr() != "register":
    return
  {.gcsafe.}:
    withLock app.lock:
      if app.registered[slot]:
        return
      app.registered[slot] = true
      let prompt = node{"prompt"}.getStr().strip()
      let scripted =
        if node{"scripted"} != nil and node["scripted"].kind == JString:
          node["scripted"].getStr().strip()
        else: ""
      app.policy[slot].registered = true
      app.policy[slot].prompt = prompt
      app.policy[slot].isLlm = prompt.len > 0
      app.policy[slot].scripted = scripted
      app.policy[slot].label = block:
        let explicit = node{"policy"}.getStr().strip()
        if explicit.len > 0: explicit
        elif prompt.len > 0: "prompt"
        elif scripted.len > 0: scripted
        else: "awu"
  echo "battlecode: seat ", slot, " registered kind=",
    (if node{"prompt"}.getStr().strip().len > 0: "llm" else: "scripted"),
    " label=", node{"policy"}.getStr()

# ---------------------------------------------------------------------------
#  HTTP / websocket surface
# ---------------------------------------------------------------------------

proc handleHealth(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(200, headers, "ok\n")

proc wantsWebSocket(request: Request): bool =
  ## mummy has no `isWebSocketUpgrade` on the request, so read the header the
  ## handshake is defined by.
  request.headers["Upgrade"].strip().toLowerAscii() == "websocket"

proc handleGlobal(request: Request) =
  ## `/global` answers BOTH ways on purpose. `coworld certify`'s
  ## `smoke-episode` upgrades it and fails the game with
  ## "Global viewer websocket did not produce a message" if nothing arrives
  ## (cogame-battlecode 0.1.2, 2026-09-04), while the platform's status probe
  ## and `docs/PROTOCOL.md` both want a plain JSON GET.
  if request.wantsWebSocket():
    ## A spectator socket carrying a seat's credentials is a player socket
    ## wearing a viewer's hat; coworld-ctf refuses it and so does this.
    if request.queryParams.getOrDefault("slot", "").len > 0 or
        request.queryParams.getOrDefault("token", "").len > 0:
      var forbidden: HttpHeaders
      forbidden["Content-Type"] = "text/plain"
      request.respond(403, forbidden,
        "/global is a spectator channel and takes no player credentials\n")
      echo "battlecode: refused a /global socket carrying seat credentials"
      return
    let websocket = request.upgradeToWebSocket()
    ## mummy documents send() as callable immediately after the upgrade, and
    ## the first frame goes out HERE rather than waiting for the next phase
    ## change: a spectator that connects during a one-second certification
    ## episode would otherwise see nothing at all.
    {.gcsafe.}:
      let payload = globalJson()
      websocket.send(payload, TextMessage)
      websocket.send(blobFromSpriteChat(payload), BinaryMessage)
      withLock viewerLock:
        viewers.add(websocket)
    echo "battlecode: a spectator joined /global"
    return
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  headers["Cache-Control"] = "no-cache"
  request.respond(200, headers, globalJson())

proc handleClient(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html; charset=utf-8"
  request.respond(200, headers,
    "<!doctype html><meta charset=utf-8><title>battlecode</title>" &
    "<p>This coworld's watchable artifact is the recorded replay, " &
    "re-derived in the browser by the static wasm bundle. There is no " &
    "live viewer pod.</p>")

proc handlePlayerSocket(request: Request) =
  let slot = request.slotOfRequest()
  let token = request.queryParams.getOrDefault("token", "")
  let refusal = joinError(slot, token)
  if refusal.len > 0:
    ## Refused BEFORE the upgrade, so the dialler sees a failed handshake
    ## rather than a socket that is silently ignored.
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain"
    request.respond(403, headers, refusal & "\n")
    echo "battlecode: refused a seat-", slot, " connection: ", refusal
    return
  discard request.upgradeToWebSocket()
  echo "battlecode: seat ", slot, " connected"

proc websocketHandler(
  websocket: WebSocket, event: WebSocketEvent, message: mummy.Message
) {.gcsafe.} =
  case event
  of OpenEvent: discard
  of MessageEvent:
    ## NOT filtered by frame kind: the seat registers with a Sprite v1 chat
    ## blob sent as a BINARY message.
    if message.kind == Ping:
      ## The Pong must ECHO the Ping's application data — RFC 6455 §5.5.3,
      ## and `coworld certify` checks it: an empty Pong reads as
      ## "did not answer a WebSocket Ping with Pong" (0.1.3, 2026-09-04).
      websocket.send(message.data, Pong)
      return
    let text = readSpriteInputText(message.data)
    let payload = if text.len > 0: text else: message.data
    if not payload.contains("\"register\""):
      return
    ## The seat number rides IN the registration blob, read by the player
    ## from its own `COWORLD_PLAYER_WS_URL` query. Deriving it from socket
    ## bookkeeping instead is what makes two seats race for one identity.
    var slot = 0
    try:
      let node = parseJson(payload)
      slot = clamp(node{"slot"}.getInt(0), 0, 1)
    except CatchableError:
      slot = 0
    applyRegistration(slot, payload)
  of ErrorEvent, CloseEvent:
    {.gcsafe.}:
      withLock viewerLock:
        for i in countdown(viewers.high, 0):
          if $viewers[i] == $websocket:
            viewers.delete(i)

# ---------------------------------------------------------------------------
#  The episode
# ---------------------------------------------------------------------------

proc waitForSeats(config: GameConfig) =
  ## Bounded: `connectTimeoutMs`, then play anyway. A seat that never
  ## registers plays the scripted doctrine, and the server says so LOUDLY
  ## rather than defaulting in silence (the grf-football scar).
  let deadline = getMonoTime() + initDuration(
    milliseconds = max(1000, config.connectTimeoutMs))
  while getMonoTime() < deadline:
    var ready = true
    {.gcsafe.}:
      withLock app.lock:
        for slot in 0 .. 1:
          if not app.registered[slot]: ready = false
    if ready: return
    sleep(100)
  {.gcsafe.}:
    withLock app.lock:
      for slot in 0 .. 1:
        if not app.registered[slot]:
          echo "::warning::battlecode: seat ", slot,
            " never registered within ", config.connectTimeoutMs,
            " ms; it plays the scripted doctrine"
          let uri = getEnv("COGAME_PLAYER_FAILURE_URI")
          if uri.len > 0:
            try:
              writeCogameUri(uri, $(%*{"slot": slot,
                "reason": "seat never registered"}), "application/json",
                "COGAME_PLAYER_FAILURE_URI")
            except CatchableError as error:
              echo "battlecode: could not report the seat failure: ", error.msg

proc parseConfig*(text: string): GameConfig =
  result = defaultGameConfig()
  if text.len == 0: return
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as error:
    raise newException(ConfigError, "game_config is not JSON: " & error.msg)
  if node.kind != JObject:
    raise newException(ConfigError, "game_config is not an object")
  template opt(key: string, field: untyped, kind: untyped) =
    if node.hasKey(key): field = kind
  opt("year", result.year, node["year"].getStr())
  opt("pool", result.pool, node["pool"].getStr())
  opt("seed", result.seed, node["seed"].getInt())
  opt("gamesPerMatch", result.gamesPerMatch, node["gamesPerMatch"].getInt())
  opt("maxRounds", result.maxRounds, node["maxRounds"].getInt())
  opt("num_agents", result.numAgents, node["num_agents"].getInt())
  opt("attempt1Ms", result.attempt1Ms, node["attempt1Ms"].getInt())
  opt("retryMs", result.retryMs, node["retryMs"].getInt())
  opt("doctrineBudgetMs", result.doctrineBudgetMs, node["doctrineBudgetMs"].getInt())
  opt("perGameBudgetSeconds", result.perGameBudgetSeconds,
      node["perGameBudgetSeconds"].getInt())
  opt("matchBudgetSeconds", result.matchBudgetSeconds,
      node["matchBudgetSeconds"].getInt())
  opt("connectTimeoutMs", result.connectTimeoutMs, node["connectTimeoutMs"].getInt())
  opt("model", result.model, node["model"].getStr())
  opt("maxOutputTokens", result.maxOutputTokens, node["maxOutputTokens"].getInt())
  if node.hasKey("tokens"):
    result.tokens = @[]
    for t in node["tokens"]:
      result.tokens.add(t.getStr())
  if node.hasKey("players"):
    result.playerNames = @[]
    for p in node["players"]:
      result.playerNames.add(p{"name"}.getStr(AliasA))
  if not isRegisteredYear(result.year):
    raise newException(ConfigError,
      "unknown game_config.year " & result.year)
  if result.numAgents != 2:
    raise newException(ConfigError,
      "battlecode is a two-seat game; num_agents was " & $result.numAgents)
  if poolNamesFor(result.year, result.pool).len == 0:
    raise newException(ConfigError, "unknown pool " & result.pool)
  result.maxRounds = min(result.maxRounds, yearSpec(result.year).maxRounds)

proc randomSeed(): int =
  ## A 31-bit seed from the OS when the config does not pin one. With a
  ## public fixed seed the map draw would be pre-computable by an opponent.
  var buf: array[4, byte]
  when defined(windows):
    buf = [byte(getTime().toUnix() and 0xFF), 0, 0, 0]
  else:
    let f = open("/dev/urandom")
    discard f.readBuffer(addr buf[0], 4)
    f.close()
  (int(buf[0]) shl 24 or int(buf[1]) shl 16 or
    int(buf[2]) shl 8 or int(buf[3])) and 0x7FFF_FFFF

proc runEpisode*(runtimeConfig: RuntimeConfig, config: GameConfig) =
  let episodeStart = getMonoTime()
  var reason = epComplete
  var seats: array[2, SeatReport]
  var games: seq[GameOutcome]
  var events: seq[MatchEvent]
  var plan: MatchPlan
  var simSeconds = 0.0

  setPhase("waiting for seats")
  waitForSeats(config)

  var policy: array[2, SeatPolicy]
  {.gcsafe.}:
    withLock app.lock:
      policy = app.policy

  let seed = if config.seed != 0: config.seed else: randomSeed()
  plan = buildPlan(config, [defaultSheet(config.year),
                            defaultSheet(config.year)], seed)
  ## D1: the chassis is fixed by the OPERATOR, never by the sheet. A scripted
  ## seat drives the chassis its `PLAYER_SCRIPTED` names; an LLM seat drives
  ## the fixed champion chassis.
  for slot in 0 .. 1:
    plan.chassis[slot] = chassisForSeat(config.year, policy[slot])
  events.add(ev("episode_start", ms = 0, fields = %*{
    "seed": seed, "year": config.year, "maps": plan.maps,
    "aliases": [AliasA, AliasB]}))

  setPhase("doctrine")
  let decision = decide(config, plan, policy)
  for e in decision.events: events.add(e)
  plan.sheets = decision.sheets

  setPhase("match")
  let simStart = getMonoTime()
  try:
    let (played, matchReason) = playMatch(config, plan, events)
    games = played
    reason = matchReason
  except CatchableError as error:
    ## A sim invariant tripped. A partial replay and [0, 0] are still
    ## written — a fault must never mean "no artifacts".
    echo "::error::battlecode: sim fault: ", error.msg
    reason = epFault
    games = @[]
  simSeconds = (getMonoTime() - simStart).inMilliseconds.float / 1000.0

  for slot in 0 .. 1:
    seats[slot] = SeatReport(
      name: (if slot < config.playerNames.len: config.playerNames[slot]
             else: aliasFor(slot)),
      alias: aliasFor(slot),
      policyKind: decision.policyKind[slot],
      sheet: decision.sheets[slot],
      decisionMs: decision.decisionMs[slot],
      fallback: decision.fallback[slot],
      fallbackDetail: decision.fallbackDetail[slot],
      brief: decision.briefs[slot],
      chassis: chassisNameFor(config.year, policy[slot],
                              decision.sheets[slot]))

  events.add(ev("episode_end", ms = 0, fields = %*{"reason": $reason}))
  let wallClock = (getMonoTime() - episodeStart).inMilliseconds.float / 1000.0
  let resultsDoc = resultsJson(seats, games, plan, reason, simSeconds, wallClock)

  var doc = ReplayDoc(
    gameVersion: GameVersion, year: config.year,
    config: %*{
      "year": config.year, "pool": config.pool, "seed": seed,
      "gamesPerMatch": config.gamesPerMatch, "maxRounds": config.maxRounds,
      "num_agents": config.numAgents},
    seed: seed, seats: seats, events: events, result: resultsDoc, plan: plan,
    promptPreamble: (if decision.briefs[0].len > 0 or
                        decision.briefs[1].len > 0: preambleFor(config.year)
                     else: ""))
  for slot in 0 .. 1:
    doc.names[slot] = seats[slot].name
  for g in games:
    doc.games.add(GameHeader(index: g.index, map: g.mapName,
      mapSha: mapSha(config.year, g.mapName), sideAslot: g.sideAslot,
      rounds: g.roundsPlayed, hashChain: g.hashChain,
      roundChains: g.roundChains))

  {.gcsafe.}:
    withLock app.lock:
      app.resultsDoc = $resultsDoc
  setPhase("settled: " & $reason)

  try:
    runtimeConfig.writeResults($resultsDoc)
  except CatchableError as error:
    echo "::error::battlecode: could not write results: ", error.msg
  try:
    runtimeConfig.writeReplay($doc.toJson())
  except CatchableError as error:
    echo "::error::battlecode: could not write the replay: ", error.msg

  echo "battlecode: reason=", reason, " games=", games.len,
    " scores=", scoresFor(games), " sim=", simSeconds, "s wall=", wallClock, "s"

proc heartbeat(interval: int) {.thread.} =
  ## A spectator that connects between phases still gets frames. Bounded by
  ## `viewersRunning`, which `runServer` clears before it closes the server.
  while true:
    {.gcsafe.}:
      if not viewersRunning: break
    sleep(interval)
    {.gcsafe.}:
      if not viewersRunning: break
      var any = false
      withLock viewerLock:
        any = viewers.len > 0
      if any:
        pushGlobal()

proc runServer*(runtimeConfig: RuntimeConfig, config: GameConfig) =
  initAppState()
  initLock(viewerLock)
  seatTokens = config.tokens
  var router: Router
  router.get("/healthz", handleHealth)
  router.get("/health", handleHealth)
  router.get("/global", handleGlobal)
  router.get("/client/global", handleClient)
  router.get("/client/player", handleClient)
  router.get("/player", handlePlayerSocket)
  let server = newServer(router, websocketHandler)
  var thread: Thread[tuple[s: Server, host: string, port: int]]
  proc serve(args: tuple[s: Server, host: string, port: int]) {.thread.} =
    args.s.serve(Port(args.port), args.host)
  createThread(thread, serve, (server, runtimeConfig.host, runtimeConfig.port))
  echo "battlecode: listening on ", runtimeConfig.host, ":", runtimeConfig.port
  sleep(200)

  viewersRunning = true
  var heartbeatThread: Thread[int]
  createThread(heartbeatThread, heartbeat, 500)

  runEpisode(runtimeConfig, config)

  ## The ~20 s shutdown grace: `/healthz` and `/global` keep answering after
  ## the artifacts are written, so a probe that arrives a beat late does not
  ## see a dead pod (the lantern 0.1.3 scar).
  let graceMs = try: parseInt(getEnv("BATTLECODE_SHUTDOWN_GRACE_MS", "20000"))
                except CatchableError: 20000
  sleep(max(0, graceMs))
  viewersRunning = false
  server.close()
