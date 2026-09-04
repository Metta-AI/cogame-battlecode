## THE CERTIFICATION CONTRACT.
##
## `coworld certify`'s `smoke-episode` step probes the game container's HTTP
## surface directly and fails the whole release with
## `game_contract_violation` on any of these. Each one below cost a release
## dispatch to find, so each one is pinned here:
##
##   0.1.1  "Bad player token was accepted: …/player?slot=0&token=bad"
##   0.1.2  "Global viewer websocket did not produce a message from …/global"

import std/strutils
import harness
import battlecode/seats

const Tokens = ["token-0", "token-1"]

checkEq("the right token for the right seat joins",
  seatJoinError(Tokens, 0, "token-0"), "")
checkEq("and so does the other seat",
  seatJoinError(Tokens, 1, "token-1"), "")

check("a WRONG token is refused",
  seatJoinError(Tokens, 0, "bad").len > 0)
check("the other seat's token is a wrong token",
  seatJoinError(Tokens, 0, "token-1").len > 0)
check("a MISSING token is refused",
  seatJoinError(Tokens, 0, "").len > 0)
check("an out-of-range seat is refused",
  seatJoinError(Tokens, 2, "token-0").len > 0)
check("and a negative seat",
  seatJoinError(Tokens, -1, "token-0").len > 0)

## The refusal has to SAY something: it becomes the 403 body, and a dialler
## that cannot tell "wrong token" from "no such seat" cannot be debugged.
check("a wrong token names the seat", "seat 0" in seatJoinError(Tokens, 0, "bad"))
check("a missing token says so",
  "requires a connection token" in seatJoinError(Tokens, 0, ""))

## No tokens declared at all is a LOCAL run: there is no credential to check
## against, and inventing one would break a bare `docker run`.
var none: seq[string]
checkEq("an unconfigured game is open", seatJoinError(none, 0, ""), "")
checkEq("however it is dialled", seatJoinError(none, 3, "whatever"), "")

# --- the rest of the contract, at the source level -------------------------
# These are read off `server.nim` rather than driven through a socket: the
# test shards run without `--threads:on`, so mummy cannot be imported here,
# and a missing branch is exactly what the two failures above were.
block:
  let server = readFile("src/battlecode/server.nim")

  ## The seat token must be checked BEFORE the upgrade — a socket that is
  ## upgraded and then ignored still counts as "accepted".
  let refusal = server.find("joinError")
  let upgrade = server.find("upgradeToWebSocket")
  check("the token is checked before any upgrade", refusal >= 0 and refusal < upgrade)
  check("and the refusal is a 403", "request.respond(403" in server)

  ## `/global` must answer a WebSocket upgrade with a message, not just a GET.
  check("/global is routed", "\"/global\", handleGlobal" in server)
  check("and it upgrades", "wantsWebSocket" in server)
  check("and sends the first frame on connect, not on the next phase",
    "websocket.send(payload, TextMessage)" in server)
  check("and keeps a heartbeat for a socket opened between phases",
    "proc heartbeat(" in server)

  ## A spectator does not get to use a seat's credentials.
  check("/global refuses an upgrade carrying player credentials",
    "takes no player credentials" in server)

  ## The manifest declares a STATIC replay bundle, so certification must
  ## report "Replay liveness: skipped (static replay bundle declared…)".
  ## Serving a live /client/replay route is what turns that into a real
  ## liveness check against a pod this coworld does not have.
  check("no /client/replay route is served",
    "\"/client/replay\"" notin server)

  ## The lux-ai scar: a lost Ping -> Pong branch fails certification.
  check("the websocket handler answers a Ping with a Pong",
    "websocket.send(\"\", Pong)" in server)
  ## The lux-ai / snake-royale scar: the seat registers with a BINARY frame.
  check("and does not filter non-text frames",
    "NOT filtered by frame kind" in server)

finish("test_seats")
