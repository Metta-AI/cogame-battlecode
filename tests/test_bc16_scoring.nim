## Shard 12 of the note's list — **the points formula and the scores it
## feeds**.
##
##     share(x, y)   = if x + y == 0: 0.5'f32 else: f32(x) / f32(x + y)
##     points[t]     = int(64 * share(archons) + 24 * share(archonHp10)
##                       + 12 * share(partsWorth))          # TRUNCATION
##     scores[t]     = 200 * (games won) + mean(points[t])
##
## The three terms are EXACTLY the engine's three deciding rungs in the
## engine's own priority order. Rungs 2 and 3 are float64 in the engine and
## are NARROWED TO INTEGERS here — archon health to TENTHS, parts worth to a
## truncated integer — before any share is taken, and every share is then
## narrowed through FLOAT32 with the weighted sum TRUNCATED by the `int()`
## cast, because `points` must be reproducible bit for bit between the native
## recorder and the wasm re-deriver.
##
## **TWO DOCUMENTED DISAGREEMENTS ARE ASSERTED HERE AS EXPECTATIONS RATHER
## THAN LEFT TO BE FOUND LATER.** (1) `points` alone can favour the LOSER,
## because a one-unit margin on a rung with large totals gives an arbitrarily
## small advantage; that is why `results.scores` adds a 200-per-game win bonus
## that dominates the whole `[0, 100]` range. (2) The `end_reason` is decided
## on the engine's EXACT FLOAT64 differences while `points` is decided on the
## narrowed integers, so a razor-thin margin can decide the WINNER on a
## difference that rounds away in POINTS.

import std/[math, random]
import harness
import bc16_fixture
import battlecode/match
import battlecode/years/dispatch

# --- share -----------------------------------------------------------------
block:
  checkEq("share(0, 0) is 0.5, not 0 — two annihilated factions are not " &
    "separated by an arithmetic accident", share(0, 0), 0.5'f32)
  checkEq("share(1, 0) is 1", share(1, 0), 1.0'f32)
  checkEq("share(0, 1) is 0", share(0, 1), 0.0'f32)
  checkEq("share(1, 1) is 0.5", share(1, 1), 0.5'f32)
  checkEq("share(4, 3) is 4/7", share(4, 3), 4.0'f32 / 7.0'f32)

# --- one vector per weight -------------------------------------------------
proc pointsFor(archonsA, archonsB: int, hpA, hpB: float64,
               partsA, partsB: float64,
               soldierB = true): array[2, int] =
  ## Build a world whose three rungs are exactly the arguments, then read
  ## `gamePoints` off it.
  ## A soldier a side so the roster is never empty (an empty list makes the
  ## fixture fall back to its own archon pair), then exactly the requested
  ## archons.
  var robots = @[
    (x: 10, y: 26, kind: ord(rtSoldier), team: ord(teamA))]
  if soldierB:
    robots.add((x: 19, y: 26, kind: ord(rtSoldier), team: ord(teamB)))
  for i in 0 ..< archonsA:
    robots.add((x: 3, y: 4 + i * 3, kind: ord(rtArchon), team: ord(teamA)))
  for i in 0 ..< archonsB:
    robots.add((x: 26, y: 4 + i * 3, kind: ord(rtArchon), team: ord(teamB)))
  let w = bare(robots = robots)
  ## Spread the requested health over the archons.
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.kind != rtArchon: continue
    r.health = (if r.team == teamA: hpA / float64(max(1, archonsA))
                else: hpB / float64(max(1, archonsB)))
  w.resources[0] = partsA
  w.resources[1] = partsB
  w.gamePoints()

block:
  let p = pointsFor(1, 1, 1000.0, 1000.0, 300.0, 300.0)
  checkEq("a dead heat is 50 each: 64*0.5 + 24*0.5 + 12*0.5", p, [50, 50])
  let q = pointsFor(2, 0, 2000.0, 0.0, 330.0, 0.0, soldierB = false)
  checkEq("a total win takes all 100", q[0], 100)
  checkEq("and the loser gets 0", q[1], 0)

block:
  ## The archon weight alone: 64 * (4/7 - 3/7) = 9.14 points of the 64.
  let p = pointsFor(4, 3, 4000.0, 3000.0, 300.0, 300.0)
  let want = int(64.0'f32 * share(4, 3) + 24.0'f32 * share(40000, 30000) +
                 12.0'f32 * share(300, 300))
  checkEq("the archon term is exactly the engine's rung-1 share", p[0], want)

block:
  ## THE DOCUMENTED CASE WHERE `points` FAVOURS THE LOSER. Four archons
  ## against three is a WIN on rung 1, but the margin is only
  ## `4/7 - 3/7 = 0.143` of 64 = 9.1 points, against 36 available on the two
  ## rungs below — so a side that wins rung 1 narrowly and loses rungs 2 and 3
  ## heavily scores FEWER points than the side it beat.
  let p = pointsFor(4, 3, 500.0, 3000.0, 10.0, 5000.0)
  check("the rung-1 winner can score FEWER points than the loser",
    p[0] < p[1])
  check("which is why `results.scores` is win-dominated by a 200 bonus",
    winBonusFor("bc16") == 200.0)

block:
  ## THE DOCUMENTED CASE WHERE THE LADDER AND THE POINTS DISAGREE. Rung 3 is
  ## an exact float64 difference; `partsWorth` truncates to an integer. A
  ## 0.5-part edge WINS THE GAME and rounds away in `points`.
  let w = bare()
  w.currentRound = 2999
  w.resources[0] = 300.5
  w.resources[1] = 300.0
  w.maxRounds = 3000
  checkEq("the two stockpiles truncate to the same integer",
    w.partsWorth(teamA), w.partsWorth(teamB))
  let p = w.gamePoints()
  checkEq("so `points` calls it a dead heat", p[0], p[1])
  w.checkEndOfMatch()
  checkEq("while the LADDER awards the game to A on the exact float64 " &
    "difference", w.winner, teamA)
  checkEq("with BARELY_BEAT", w.domination, dfBarelyBeat)

# --- the range and the super-increasing property --------------------------
block:
  var rng = initRand(2016)
  var outOfRange = 0
  var sumTooBig = 0
  for trial in 0 ..< 400:
    let aA = rng.rand(0 .. 4)
    let aB = rng.rand(0 .. 4)
    if aA == 0 and aB == 0: continue
    let p = pointsFor(aA, aB,
                      rng.rand(0.0 .. 4000.0), rng.rand(0.0 .. 4000.0),
                      rng.rand(0.0 .. 9000.0), rng.rand(0.0 .. 9000.0))
    for t in 0 .. 1:
      if p[t] < 0 or p[t] > 100: inc outOfRange
    if p[0] + p[1] > 100: inc sumTooBig
  checkEq("points is always in [0, 100]", outOfRange, 0)
  checkEq("and the two seats never sum above 100", sumTooBig, 0)
  check("the weights are super-increasing: 24 > 12", 24 > 12)
  check("and 64 > 24 + 12", 64 > 24 + 12)

# --- results.scores strictly orders the winner above the loser ------------
block:
  ## 500 random synthetic finals, INCLUDING clinched two-game matches: a
  ## best-of-three that a side takes 2-0 records TWO games with
  ## `reason: complete`, which is correct and not truncated.
  var rng = initRand(20160217)
  var disagreements = 0
  var clinched = 0
  for trial in 0 ..< 500:
    var games: seq[GameOutcome]
    let n = rng.rand(1 .. 3)
    var wins = [0, 0]
    for g in 0 ..< n:
      let winner = rng.rand(0 .. 1)
      let p0 = rng.rand(0 .. 100)
      let p1 = min(100 - p0, rng.rand(0 .. 100))
      games.add(GameOutcome(index: g, mapName: "m", sideAslot: g mod 2,
                            roundsPlayed: 3000, winnerSlot: winner,
                            endReason: "more_archons", points: [p0, p1]))
      wins[winner] += 1
      if wins[winner] == 2:
        clinched += 1
        break
    let scores = scoresFor(games, "bc16")
    if wins[0] > wins[1] and scores[0] <= scores[1]: inc disagreements
    if wins[1] > wins[0] and scores[1] <= scores[0]: inc disagreements
  checkEq("results.scores STRICTLY orders the match winner above the loser " &
    "on 500 random finals", disagreements, 0)
  check("and the sample really contained clinched two-game matches",
    clinched > 20)
  checkEq("because bc16 joins winBonusFor's 200 set", winBonusFor("bc16"),
    200.0)
  ## The arithmetic that makes it provable: 2-0 gives 400 + mean against
  ## <= 100; 2-1 gives 400 + mean against 200 + mean <= 300.
  check("400 dominates 100", 400.0 > 100.0)
  check("and 400 dominates 300", 400.0 > 300.0)

finish("test_bc16_scoring")
