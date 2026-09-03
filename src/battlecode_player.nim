## `/bin/battlecode-player` — the thin seat registrar.
##
## Deliberately thin: it dials its seat, sends ONE registration blob and then
## only receives until the socket closes, then exits 0. Every decision happens
## inside the GAME container, because that is the only container the platform
## injects the `anthropic_api_key` coworld secret into, and because keeping
## the control layer server-side is what makes a recorded doctrine
## reproducible with no network in the loop.
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
import whisky

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

proc registrationBlob(slot: int, prompt, scripted, policy: string): string =
  var node = %*{
    "type": "register",
    "slot": slot,
    "prompt": prompt,
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
    scripted = getEnv("PLAYER_SCRIPTED").strip()
    label = block:
      let explicit = getEnv("PLAYER_POLICY_LABEL").strip()
      if explicit.len > 0: explicit
      elif prompt.len > 0: "prompt"
      elif scripted.len > 0: scripted
      else: "awu"
  echo "battlecode player: slot=", slot, " kind=",
    (if prompt.len > 0: "llm" else: "scripted"),
    " baseline=", (if scripted.len > 0: scripted else: "awu"),
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
      socket.send(registrationBlob(slot, prompt, scripted, label), BinaryMessage)
      var resends = 0
      while true:
        let received = socket.receiveMessage()
        if received.isNone:
          continue                  ## a read timeout, not a closed socket
        inc sessionFrames
        if resends < RegistrationResends and
            sessionFrames mod ResendEveryFrames == 1:
          inc resends
          socket.send(registrationBlob(slot, prompt, scripted, label),
            BinaryMessage)
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
