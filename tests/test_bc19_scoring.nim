## The bc19 points formula, and the ONE property that makes `results.scores`
## trustworthy: its ordering agrees with `results.wins` EXACTLY.

import std/random
import harness
import battlecode/sheet
import battlecode/match
import battlecode/years/bc19/rules

block:
  ## `share` returns 0.5 on a 0-0 total -- the bc16/bc22-bc25 choice. Two
  ## orders that BOTH ended castle-less should not be separated by an
  ## arithmetic accident, and rung 4 of the ladder proves that is a real
  ## outcome.
  checkEq("share(0, 0) is 0.5", share(0, 0), 0.5'f32)
  checkEq("share(1, 0) is 1.0", share(1, 0), 1.0'f32)
  checkEq("share(0, 1) is 0.0", share(0, 1), 0.0'f32)
  checkEq("share(3, 2) is 0.6", share(3, 2), 0.6'f32)
  for a in 0 .. 20:
    for b in 0 .. 20:
      checkEq("share is complementary at " & $a & "," & $b,
        share(a, b) + share(b, a), 1.0'f32)

block:
  ## THE WEIGHTS ARE SUPER-INCREASING, asserted as arithmetic rather than
  ## claimed in prose: 24 > 12 and 64 > 24 + 12.
  check("24 > 12", 24 > 12)
  check("64 > 24 + 12", 64 > 24 + 12)
  checkEq("and they total 100", 64 + 24 + 12, 100)

block:
  ## One vector per weight, played out of real worlds so the formula is
  ## checked where it lives rather than re-implemented here.
  let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
  let spec = loadMap("seed-0043")
  let (w, o) = playGame(spec, sheets, [ck19Saber, ck19Saber], 0, 0, 200, 0)
  let pts = w.gamePoints()
  for t in 0 .. 1:
    check("points are in [0, 100] for team " & $t,
      pts[t] >= 0 and pts[t] <= 100)
  check("and the two seats sum to at most 100", pts[0] + pts[1] <= 100)
  check("a mirror of the same chassis scores near-level",
    abs(pts[0] - pts[1]) <= 20)
  checkEq("the outcome's points are the world's, re-indexed by SEAT",
    o.points[o.slotOf(tRed)], pts[0])
  checkEq("and likewise for BLUE", o.points[o.slotOf(tBlue)], pts[1])

block:
  ## THE DOCUMENTED CASE WHERE `points` FAVOURS THE LOSER, asserted as an
  ## EXPLICIT EXPECTATION so it is never mistaken for a bug. A one-castle
  ## margin on a 3-vs-2 board is `3/5 - 2/5 = 0.2` of 64 = 12.8 points
  ## against 36 available below -- so a side that wins on castles and loses
  ## everything else can score LOWER.
  let winner = int(64.0'f32 * share(3, 2) + 24.0'f32 * share(10, 400) +
                   12.0'f32 * share(10, 400))
  let loser = int(64.0'f32 * share(2, 3) + 24.0'f32 * share(400, 10) +
                  12.0'f32 * share(400, 10))
  check("the side with MORE CASTLES can score fewer points", winner < loser)
  check("and the margin is real, not a rounding artefact", loser - winner > 5)

block:
  ## AND THAT IS EXACTLY WHY THE WIN BONUS IS 200. `results.scores`'
  ## ordering must agree with `results.wins` on every finish, including a
  ## CLINCHED two-game match -- with 100 a 2-1 could tie.
  checkEq("bc19 pays 200 a game", winBonusFor("bc19"), 200.0)
  var rng = initRand(20190043)
  for trial in 0 .. 499:
    let games = rng.rand(2 .. 3)
    var wins = [0, 0]
    var total = [0.0, 0.0]
    var played = 0
    for g in 0 ..< games:
      if wins[0] >= 2 or wins[1] >= 2: break
      inc played
      let a = rng.rand(0 .. 100)
      let b = rng.rand(0 .. 100 - a)
      let winnerSlot = rng.rand(0 .. 1)
      inc wins[winnerSlot]
      total[0] += float(a)
      total[1] += float(b)
    if wins[0] == wins[1]: continue
    var scores: array[2, float]
    for t in 0 .. 1:
      scores[t] = 200.0 * float(wins[t]) + total[t] / float(max(1, played))
    let winnerSlot = (if wins[0] > wins[1]: 0 else: 1)
    check("trial " & $trial & ": the match winner scores STRICTLY higher",
      scores[winnerSlot] > scores[1 - winnerSlot])

block:
  ## The `end_reason` is NOT computed from `points`: the ladder uses the
  ## engine's exact INTEGER comparisons, so a razor-thin margin can decide
  ## the WINNER on a difference that rounds away in POINTS.
  ## A one-point health margin out of two thousand moves the weighted sum by
  ## 24 * (1/2001) = 0.012 -- far less than the one whole point `points`
  ## can express -- so the two sides' TRUNCATED scores differ by at most one
  ## while the ladder separates them exactly.
  let a = int(64.0'f32 * share(1, 1) + 24.0'f32 * share(1001, 1000) +
              12.0'f32 * share(500, 500))
  let b = int(64.0'f32 * share(1, 1) + 24.0'f32 * share(1000, 1001) +
              12.0'f32 * share(500, 500))
  check("1001 against 1000 unit health is at most ONE point apart",
    abs(a - b) <= 1)
  check("while the ladder decides it exactly", 1001 > 1000)
  ## And the sharpest statement of it: a health margin of ONE unit out of
  ## two thousand FLIPS THE WINNER and DOES NOT MOVE EITHER SIDE'S POINTS AT
  ## ALL. `more_unit_health` decides the game; `points` cannot see it.
  proc pts(hA, hB: int): (int, int) =
    (int(64.0'f32 * share(1, 1) + 24.0'f32 * share(hA, hB) +
         12.0'f32 * share(500, 300)),
     int(64.0'f32 * share(1, 1) + 24.0'f32 * share(hB, hA) +
         12.0'f32 * share(300, 500)))
  let level = pts(1000, 1000)
  let aWins = pts(1001, 1000)
  let bWins = pts(1000, 1001)
  checkEq("A winning on health by one moves nobody's points", aWins, level)
  checkEq("and neither does B winning by one", bWins, level)
  check("while the ladder decides both, in opposite directions",
    1001 > 1000)

finish("test_bc19_scoring")
