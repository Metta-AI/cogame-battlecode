## The seat-join contract: whether a dialler may have the socket it asked for.
##
## The runner injects one connection token per seat into every episode's
## `game_config` and hands seat N its own token on the socket URL. That token
## is a CREDENTIAL, and `coworld certify`'s `smoke-episode` step probes it
## directly: it dials `/player?slot=0&token=bad` and fails the game with
##
##   game_contract_violation
##   Details: Bad player token was accepted: ws://…/player?slot=0&token=bad
##
## if the upgrade succeeds (cogame-battlecode 0.1.1, 2026-09-04 — the same
## class as the lux-ai Ping/Pong branch the triage table records).
##
## It lives in its own module, away from mummy, so `tests/test_seats.nim` can
## check every branch of it without a server or a socket.

proc seatJoinError*(tokens: openArray[string], slot: int, token: string): string =
  ## "" when the seat may join; otherwise the reason, which the server sends
  ## back as a 403 body BEFORE upgrading — a dialler must see a failed
  ## handshake, not a socket that is silently ignored.
  ##
  ## A config that declares NO tokens is a local run (a bare `docker run`, a
  ## hand-driven episode) and is left open: there is no credential to check
  ## against, and inventing one would only break local debugging.
  if tokens.len == 0:
    return ""
  if slot < 0 or slot >= tokens.len:
    return "no such seat: " & $slot
  if token.len == 0:
    return "seat " & $slot & " requires a connection token"
  if token != tokens[slot]:
    return "seat " & $slot & " was given the wrong connection token"
  ""
