## The seat-join contract. `coworld certify` probes it directly, and a fork
## that loses it fails the whole release at `smoke-episode` with
## `game_contract_violation: Bad player token was accepted`.

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

finish("test_seats")
