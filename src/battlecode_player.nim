## `/bin/battlecode-player` — one ordinary doctrine policy per seat.
## The game sends a private brief and accepts a complete JSON doctrine reply.
##
##   PLAYER_PROMPT        a doctrine brief in plain English -> an LLM seat
##   PLAYER_SCRIPTED      awu | scaffold                    -> a scripted seat
##   PLAYER_POLICY_LABEL  a free label for the replay's seat record
##
## A seat that sets neither is `awu`. To field your own policy, reuse this
## image and set PLAYER_PROMPT:
##
##   coworld upload-policy <image> --name my-battlecode \
##     --run /bin/battlecode-player --secret-env PLAYER_PROMPT="<doctrine>"

import std/[json, options, os, strutils]
import bitworld/spriteprotocol
import curly
import whisky
import battlecode/[baselines, llm, sim_types]

const
  ConnectAttempts = 240        ## 240 x 500 ms = 2 minutes of dialling.
  ConnectRetryMs = 500
  RegistrationResends = 10
  ResendEveryFrames = 24
  ReconnectAttempts = 6

proc slotFromUrl(url: string): int =
  ## The seat number the runner put on the socket URL. It rides in the
  ## registration blob so the server never has to guess which socket is
  ## which — deriving it from connection order is what makes two seats race
  ## for one identity.
  let q = url.find("slot=")
  if q < 0: return 0
  var digits = ""
  for ch in url[q + 5 .. ^1]:
    if ch in '0' .. '9': digits.add(ch) else: break
  if digits.len == 0: return 0
  try: clamp(parseInt(digits), 0, 15) except CatchableError: 0

proc registrationBlob(slot: int, scripted, policy: string): string =
  var node = %*{
    "type": "register",
    "slot": slot,
    "policy": policy
  }
  if scripted.len > 0:
    node["scripted"] = %scripted
  else:
    node["scripted"] = newJNull()
  blobFromSpriteChat($node)

proc readyBlob(): string =
  result = newString(1)
  result[0] = char(0x85)

when isMainModule:
  let url = getEnv("COWORLD_PLAYER_WS_URL", getEnv("COGAMES_ENGINE_WS_URL"))
  if url.len == 0:
    quit("COWORLD_PLAYER_WS_URL is not set", 1)
  let
    slot = slotFromUrl(url)
    prompt = getEnv("PLAYER_PROMPT").strip()
    configuredScripted = getEnv("PLAYER_SCRIPTED").strip()
    scripted =
      if prompt.len > 0: ""
      elif configuredScripted.len > 0: configuredScripted
      else: "default"
    label = block:
      let explicit = getEnv("PLAYER_POLICY_LABEL").strip()
      if explicit.len > 0: explicit
      elif prompt.len > 0: "prompt"
      elif scripted.len > 0: scripted
      else: "default"
  echo "battlecode player: slot=", slot, " kind=",
    (if prompt.len > 0: "prompt" else: "scripted"),
    " baseline=", (if scripted.len > 0: scripted else: "default"),
    " label=", label

  proc dial(attempts: int): WebSocket =
    ## Bounded dialling: the runner starts the game and the players at the
    ## same instant, so the first dial always lands on a closed port.
    for attempt in 0 ..< attempts:
      try:
        return newWebSocket(url)
      except CatchableError as error:
        if attempt == 0:
          echo "battlecode player: game not listening yet (", error.msg,
            "); retrying"
        sleep(ConnectRetryMs)
    nil

  var socket = dial(ConnectAttempts)
  if socket == nil:
    quit("battlecode player: game never accepted a connection", 1)
  echo "battlecode player: connected"

  ## The registration is RE-SENT, not sent once: joins are slot-sequential
  ## and the lobby sends frames to a socket before it is admitted, so a
  ## single registration can land while the seat has no index yet (the
  ## paintball round-3 scar). Registering twice is harmless.
  var reconnects = 0
  while true:
    var sessionFrames = 0
    try:
      socket.send(registrationBlob(slot, scripted, label), BinaryMessage)
      var resends = 0
      while true:
        let received = socket.receiveMessage()
        if received.isNone:
          continue                  ## a read timeout, not a closed socket
        inc sessionFrames
        if resends < RegistrationResends and
            sessionFrames mod ResendEveryFrames == 1:
          inc resends
          socket.send(registrationBlob(slot, scripted, label),
            BinaryMessage)
        let data = received.get().data
        if data.len > 0 and data[0] == '{':
          let observation = parseJson(data)
          if observation{"type"}.getStr() == "final":
            quit(0)
          if observation{"type"}.getStr() == "observation":
            let year = observation["year"].getStr()
            var reply: string
            var cause = ""
            if prompt.len == 0:
              let baseline =
                if scripted == "default": defaultBaselineFor(year)
                else: baselineFor(year, scripted)
              reply = baselineReply(baseline)
            else:
              var config = defaultGameConfig()
              config.model = getEnv("PLAYER_MODEL").strip()
              config.maxOutputTokens = observation["max_output_tokens"].getInt()
              let client = newLlmClient(config, slot)
              if client.disabled:
                reply = baselineReply(defaultBaselineFor(year))
                cause = "no_credentials"
              else:
                let request = client.requestFor(observation["preamble"].getStr(),
                  userMessage(prompt, $observation["brief"]))
                var batch: RequestBatch
                batch.post(request.url, request.headers, request.body, $slot)
                let responses = client.curl.makeRequests(batch,
                  max(1, observation["deadline_ms"].getInt() div 1000))
                let response = responses[0]
                if response.error.len > 0:
                  cause =
                    if "timeout" in response.error.toLowerAscii(): "timeout"
                    else: "transport"
                elif response.response.code == 429:
                  cause = "throttled"
                elif response.response.code == 401 or response.response.code == 403:
                  cause = "auth"
                elif response.response.code < 200 or response.response.code >= 300:
                  cause = "transport"
                else:
                  reply = client.textOf(response.response, "", request.url)
            socket.send($(%*{"type": "action",
              "request_id": observation["request_id"].getInt(),
              "reply": reply, "cause": cause}), TextMessage)
        socket.send(readyBlob(), BinaryMessage)
    except CatchableError as error:
      echo "battlecode player: socket closed (", error.msg, ")"
    ## A dead socket exits 0, never raises (the raid 0.1.4 scar): mummy's
    ## send only QUEUES, so the game's own quit(0) can outrun the flushed
    ## frame and a naive player would fail certification intermittently.
    if sessionFrames == 0 or reconnects >= ReconnectAttempts:
      break
    inc reconnects
    echo "battlecode player: re-dialling the seat (attempt ", reconnects, ")"
    socket = dial(ReconnectAttempts)
    if socket == nil:
      echo "battlecode player: game is no longer listening, exiting cleanly"
      break
    echo "battlecode player: reconnected, re-registering"
  quit(0)
