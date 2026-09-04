## THE PERF GATE.
##
## A full 2000-round game on the largest map in the `bc26` variant's pool,
## with both scripted chassis, must complete in <= 45 s. The design note's
## sanctioned fix if this ever goes red is ONE config value —
## `gamesPerMatch: 3 -> 1` in the `bc26` variant — not a redesign.
##
## The budget arithmetic this protects: the match guard is 330 s for three
## games, so a single game must sit comfortably inside 90 s
## (`perGameBudgetSeconds`) or a hosted episode settles `deadline` instead of
## `complete`.

import std/[algorithm, monotimes, times]
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc26/[maps, rules]

const Budget = 45.0

## The largest map the `bc26` variant can draw. `large` is reserved for a
## later variant, so the gate measures what actually ships.
var largest = ""
var largestTiles = 0
for name in MixedPool:
  let spec = loadMap(name)
  if spec.width * spec.height > largestTiles:
    largestTiles = spec.width * spec.height
    largest = name
echo "largest map in the bc26 pool: ", largest, " (", largestTiles, " tiles)"

proc timeGame(sheets: array[2, Sheet]): (float, GameOutcome26) =
  let started = getMonoTime()
  let (w, outcome) = playGame(loadMap(largest), sheets, 0, 0, 2000, 0)
  ((getMonoTime() - started).inMilliseconds.float / 1000.0, outcome)

block:
  let (seconds, outcome) = timeGame(
    [baselineSheet(blAwu), baselineSheet(blAwu)])
  echo "awu vs awu: ", outcome.roundsPlayed, " rounds in ", seconds, " s"
  check("awu vs awu plays a full game in <= 45 s (" & $seconds & " s)",
    seconds <= Budget)
  check("and actually played a match", outcome.roundsPlayed > 100)

block:
  let (seconds, outcome) = timeGame(
    [baselineSheet(blScaffold), baselineSheet(blScaffold)])
  echo "scaffold vs scaffold: ", outcome.roundsPlayed, " rounds in ",
    seconds, " s"
  check("scaffold vs scaffold plays a full game in <= 45 s (" & $seconds &
    " s)", seconds <= Budget)

block:
  ## The mixed pair, which is what certification and docker-smoke run.
  let (seconds, outcome) = timeGame(
    [baselineSheet(blAwu), baselineSheet(blScaffold)])
  echo "awu vs scaffold: ", outcome.roundsPlayed, " rounds in ", seconds, " s"
  check("awu vs scaffold plays a full game in <= 45 s (" & $seconds & " s)",
    seconds <= Budget)

block:
  ## The certification fixture itself: one 400-round game on the small pool,
  ## which must finish well inside `coworld certify`'s 60 s default.
  let started = getMonoTime()
  let (w, outcome) = playGame(loadMap("DefaultSmall"),
    [baselineSheet(blAwu), baselineSheet(blScaffold)], 0, 0, 400, 0)
  let seconds = (getMonoTime() - started).inMilliseconds.float / 1000.0
  echo "certification fixture: ", outcome.roundsPlayed, " rounds in ",
    seconds, " s"
  check("the certification game is under 10 s (" & $seconds & " s)",
    seconds <= 10.0)
  ## A 400-round game plays for ~16 s at 24 fps, so the recording outlasts
  ## the viewer smoke's 10 s soak (the ecos 2026-08-23 scar).
  check("and the recording outlasts the 10 s viewer soak",
    outcome.roundsPlayed.float / 24.0 > 10.0)

finish("test_perf")
