## THE bc20 PERF GATE.
##
## A full 1499-round game on `CentralSoup` (48x48, the largest map in the
## `bc20` variant's pool) with both scripted chassis must complete in <= 55 s.
## The design note's sanctioned fix if this ever goes red is ONE config value —
## `gamesPerMatch: 3 -> 1` in the `bc20` variant — not a redesign.
##
## The budget arithmetic this protects: the match guard is 320 s for three
## games, so a single game must sit comfortably inside 100 s
## (`perGameBudgetSeconds`) or a hosted episode settles `deadline` instead of
## `complete`.

import std/[monotimes, times]
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc20/[maps, rules]

const Budget = 55.0

var largest = ""
var largestTiles = 0
for name in MixedPool:
  let spec = loadMap(name)
  if spec.width * spec.height > largestTiles:
    largestTiles = spec.width * spec.height
    largest = name
echo "largest map in the bc20 pool: ", largest, " (", largestTiles, " tiles)"
checkEq("and it is CentralSoup, as the design note pins", largest,
  "CentralSoup")

proc timeGame(sheets: array[2, Sheet],
              chassis: array[2, ChassisKind]): (float, GameOutcome20) =
  let started = getMonoTime()
  let (w, outcome) = playGame(loadMap(largest), sheets, chassis, 0, 0, 1500, 0)
  ((getMonoTime() - started).inMilliseconds.float / 1000.0, outcome)

let boc = baselineSheet("bc20", blBowlOfChowder)
let scaffold = baselineSheet("bc20", blExamplefuncsplayer)
let ckBoc = parseChassis("bowl-of-chowder")
let ckScaffold = parseChassis("examplefuncsplayer")

block:
  let (seconds, outcome) = timeGame([boc, boc], [ckBoc, ckBoc])
  echo "bowl-of-chowder mirror: ", outcome.roundsPlayed, " rounds in ",
    seconds, " s"
  check("the mirror plays a full game in <= 55 s (" & $seconds & " s)",
    seconds <= Budget)
  checkEq("and it really ran to the cap", outcome.roundsPlayed, 1499)

block:
  let (seconds, outcome) = timeGame([scaffold, scaffold],
    [ckScaffold, ckScaffold])
  echo "scaffold mirror: ", outcome.roundsPlayed, " rounds in ", seconds, " s"
  check("the scaffold mirror is inside the budget (" & $seconds & " s)",
    seconds <= Budget)

block:
  ## The mixed pair, which is what `docker-smoke`'s bc20 episode runs.
  let (seconds, outcome) = timeGame([boc, scaffold], [ckBoc, ckScaffold])
  echo "bowl-of-chowder vs scaffold: ", outcome.roundsPlayed, " rounds in ",
    seconds, " s"
  check("the mixed pair is inside the budget (" & $seconds & " s)",
    seconds <= Budget)

block:
  ## The `docker-smoke` bc20 episode itself: 300 rounds on the small pool,
  ## which must finish in seconds and still outlast the viewer's 10 s soak.
  let started = getMonoTime()
  let (w, outcome) = playGame(loadMap("maptestsmall"), [boc, scaffold],
    [ckBoc, ckScaffold], 0, 0, 300, 0)
  let seconds = (getMonoTime() - started).inMilliseconds.float / 1000.0
  echo "the smoke episode: ", outcome.roundsPlayed, " rounds in ", seconds, " s"
  check("the smoke game is under 10 s (" & $seconds & " s)", seconds <= 10.0)
  ## A 300-round game plays for ~12 s at 24 fps, so the recording outlasts the
  ## viewer smoke's 10 s soak (the ecos 2026-08-23 scar).
  check("and the recording outlasts the 10 s viewer soak",
    outcome.roundsPlayed.float / 24.0 > 10.0)

finish("test_bc20_perf")
