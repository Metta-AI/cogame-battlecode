## bc25 scoring: the points formula with FLOAT32 narrowing and TRUNCATION, the
## 0-0 share returning 0.5, points in [0, 100] with the two seats summing to
## <= 100, a win on each of the five rungs coming with strictly higher points,
## and `results.scores` STRICTLY ordering the match winner above the loser on
## 500 random synthetic finals -- which is what the 200-per-game bonus buys
## over bc24's 100.

import std/[math, random]
import harness
import bc25_fixture
import battlecode/match

func points(area, towers, chips, paint, bots: array[2, int]): array[2, int] =
  for t in 0 .. 1:
    let o = 1 - t
    result[t] = int(55.0'f32 * share(area[t], area[o]) +
                    20.0'f32 * share(towers[t], towers[o]) +
                    10.0'f32 * share(chips[t], chips[o]) +
                    10.0'f32 * share(paint[t], paint[o]) +
                     5.0'f32 * share(bots[t], bots[o]))

# --- the shares ------------------------------------------------------------
block:
  checkEq("a 0-0 total shares 0.5", share(0, 0), 0.5'f32)
  checkEq("all of it", share(7, 0), 1.0'f32)
  checkEq("none of it", share(0, 7), 0.0'f32)
  checkEq("half of it", share(7, 7), 0.5'f32)
  check("and every share is a float32",
    share(1, 3) is float32)

# --- one vector per weight -------------------------------------------------
block:
  ## Everything tied is 55/2 + 20/2 + 10/2 + 10/2 + 5/2 = 50 exactly.
  let tied = points([10, 10], [3, 3], [500, 500], [100, 100], [4, 4])
  checkEq("a perfectly tied game is 50-50", tied, [50, 50])

block:
  ## Area alone: 55 + half of the other four = 55 + 22.5 = 77.5 -> 77.
  let a = points([10, 0], [3, 3], [5, 5], [7, 7], [2, 2])
  checkEq("all the area is 77 (TRUNCATED from 77.5)", a[0], 77)
  checkEq("and none of it is 22", a[1], 22)
  ## The truncation is what makes the two seats sum to 99, not 100.
  checkEq("truncation loses the half", a[0] + a[1], 99)

block:
  let t = points([1, 1], [4, 0], [5, 5], [7, 7], [2, 2])
  checkEq("all the towers is 60 (27.5 + 20 + 5 + 5 + 2.5)", t[0], 60)
  let c = points([1, 1], [1, 1], [9, 0], [7, 7], [2, 2])
  checkEq("all the chips is 55 (27.5 + 10 + 10 + 5 + 2.5)", c[0], 55)
  let p = points([1, 1], [1, 1], [1, 1], [9, 0], [2, 2])
  checkEq("all the paint is 55", p[0], 55)
  let b = points([1, 1], [1, 1], [1, 1], [1, 1], [9, 0])
  checkEq("all the robots is 52 (27.5 + 10 + 5 + 5 + 5, truncated)",
    b[0], 52)

block:
  ## Everything: 100. Nothing: 0.
  let all = points([9, 0], [9, 0], [9, 0], [9, 0], [9, 0])
  checkEq("every rung won is 100", all, [100, 0])

# --- the bounds, over random finals ----------------------------------------
block:
  var rng = initRand(9425)
  var bad = 0
  var sumOver = 0
  for i in 1 .. 2000:
    let area = [rng.rand(0 .. 400), rng.rand(0 .. 400)]
    let towers = [rng.rand(0 .. 25), rng.rand(0 .. 25)]
    let chips = [rng.rand(0 .. 50_000), rng.rand(0 .. 50_000)]
    let paint = [rng.rand(0 .. 20_000), rng.rand(0 .. 20_000)]
    let bots = [rng.rand(0 .. 60), rng.rand(0 .. 60)]
    let p = points(area, towers, chips, paint, bots)
    if p[0] < 0 or p[0] > 100 or p[1] < 0 or p[1] > 100: bad += 1
    if p[0] + p[1] > 100: sumOver += 1
  checkEq("points always land in [0, 100]", bad, 0)
  checkEq("and the two seats never sum above 100", sumOver, 0)

# --- a win on each rung comes with strictly higher points ------------------
block:
  ## A rung is only REACHED when every rung above it is tied, and a tie gives
  ## both seats exactly 0.5 on that term -- so the winner's weighted sum is
  ## always strictly above the loser's.
  var rng = initRand(31337)
  var bad = 0
  for i in 1 .. 500:
    let area = rng.rand(1 .. 400)
    let towers = rng.rand(0 .. 25)
    let chips = rng.rand(0 .. 50_000)
    let paint = rng.rand(0 .. 20_000)
    let bots = rng.rand(0 .. 60)
    ## rung 1
    var p = points([area + 1, area], [towers, towers], [chips, chips],
                   [paint, paint], [bots, bots])
    if p[0] <= p[1]: bad += 1
    ## rung 2 (area tied)
    p = points([area, area], [towers + 1, towers], [chips, chips],
               [paint, paint], [bots, bots])
    if p[0] <= p[1]: bad += 1
    ## rung 3
    p = points([area, area], [towers, towers], [chips + 1, chips],
               [paint, paint], [bots, bots])
    if p[0] <= p[1]: bad += 1
    ## rung 4
    p = points([area, area], [towers, towers], [chips, chips],
               [paint + 1, paint], [bots, bots])
    if p[0] <= p[1]: bad += 1
    ## rung 5
    p = points([area, area], [towers, towers], [chips, chips],
               [paint, paint], [bots + 1, bots])
    if p[0] <= p[1]: bad += 1
  checkEq("a win on any rung always scores strictly higher", bad, 0)

# --- the sim's own gamePoints agrees with the formula ----------------------
block:
  var w = bare()
  w.setPaint(loc(10, 10), primaryPaint(teamA))
  discard w.place(teamA, utSoldier, loc(12, 12))
  w.stats.money[0] += 500
  let got = w.gamePoints()
  let want = points([w.stats.livePainted[0], w.stats.livePainted[1]],
                    [w.stats.towers[0], w.stats.towers[1]],
                    [w.stats.money[0], w.stats.money[1]],
                    [w.paintInUnits(teamA), w.paintInUnits(teamB)],
                    [w.robotsAlive(teamA), w.robotsAlive(teamB)])
  checkEq("the sim's gamePoints is exactly the formula", got, want)

# --- 200 per game, and the ordering it buys --------------------------------
block:
  checkEq("bc25 pays 200 a game", winBonusFor("bc25"), 200.0)
  for year in ["bc26", "bc20", "bc21", "bc24"]:
    checkEq(year & " still pays 100", winBonusFor(year), 100.0)

block:
  ## 500 random synthetic THREE-GAME finals. With a 200 bonus the ordering of
  ## `results.scores` STRICTLY agrees with `results.wins`; with 100 the
  ## degenerate all-or-nothing case (0-100 points every game) ties.
  var rng = initRand(5150)
  var strict200 = 0
  var strict100 = 0
  var decided = 0
  for i in 1 .. 500:
    var games: seq[GameOutcome]
    var wins = [0, 0]
    for g in 0 .. 2:
      let winner = rng.rand(0 .. 1)
      let p0 = rng.rand(0 .. 100)
      let p1 = min(100 - p0, rng.rand(0 .. 100))
      wins[winner] += 1
      games.add(GameOutcome(index: g, winnerSlot: winner,
                            points: [p0, p1]))
    if wins[0] == wins[1]: continue
    decided += 1
    let lead = if wins[0] > wins[1]: 0 else: 1
    let s200 = scoresFor(games, "bc25")
    let s100 = scoresFor(games, "bc24")
    if s200[lead] > s200[1 - lead]: strict200 += 1
    if s100[lead] > s100[1 - lead]: strict100 += 1
  check("some finals were decided", decided > 400)
  checkEq("with 200 the score ordering ALWAYS matches the win ordering",
    strict200, decided)
  check("and with 100 it does not have to", strict100 <= decided)

block:
  ## The degenerate case, spelled out: a 2-1 winner who scored 0 points in
  ## every game against a 1-2 loser who scored 100 in every game.
  let games = @[
    GameOutcome(index: 0, winnerSlot: 0, points: [0, 100]),
    GameOutcome(index: 1, winnerSlot: 0, points: [0, 100]),
    GameOutcome(index: 2, winnerSlot: 1, points: [0, 100])]
  let s200 = scoresFor(games, "bc25")
  let s100 = scoresFor(games, "bc24")
  check("with 200 the 2-1 winner is strictly ahead", s200[0] > s200[1])
  check("with 100 the two TIE, which is the whole reason for the 200",
    abs(s100[0] - s100[1]) < 0.0001)

block:
  checkEq("no games played scores zero", scoresFor(@[], "bc25"), [0.0, 0.0])

finish("test_bc25_scoring")
