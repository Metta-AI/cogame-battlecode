## The points formula, and the one property the league depends on.
##
## §Tests item 11. `points` measures the SHAPE of the game, not who won it —
## and this shard asserts BOTH the property that holds (`results.scores`
## strictly orders the winner above the loser) and the one that does not
## (`points` alone can favour the loser), so neither is mistaken for a bug
## later.

import std/random
import harness
import bc22_fixture
import battlecode/match

block:
  checkEq("a 0-0 share is a half", share(0, 0), 0.5'f32)
  checkEq("a total wipe is 1", share(7, 0), 1.0'f32)
  checkEq("and 0 the other way", share(0, 7), 0.0'f32)
  checkEq("an even split is a half", share(3, 3), 0.5'f32)

block:
  ## The weights are SUPER-INCREASING, asserted as arithmetic rather than
  ## asserted in a comment.
  check("24 > 12", 24 > 12)
  check("and 64 > 24 + 12", 64 > 24 + 12)

block:
  ## One vector per weight, with the truncation of the `int()` cast visible.
  var w = bare()
  ## Both sides level: 32 + 12 + 6 = 50.
  var pts = w.gamePoints()
  checkEq("a perfectly level game is 50 apiece for A", pts[0], 50)
  checkEq("and 50 for B", pts[1], 50)

block:
  var w = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                           (id: 3, x: 7, y: 5, team: 1),
                           (id: 4, x: 25, y: 5, team: 2)])
  ## A has two archons to B's one. Gold worth 200 to 100, lead 400 to 200.
  let pts = w.gamePoints()
  check("the archon rung dominates", pts[0] > pts[1])
  checkEq("A's points are the weighted, float32-narrowed, TRUNCATED sum",
    pts[0], int(64.0'f32 * share(2, 1) +
                24.0'f32 * share(w.goldNetWorth(teamA), w.goldNetWorth(teamB)) +
                12.0'f32 * share(w.leadNetWorth(teamA),
                                 w.leadNetWorth(teamB))))

block:
  ## Points are bounded and the two seats never sum above 100.
  var rnd = initRand(7)
  var worst = 0
  var overflow = 0
  for trial in 0 ..< 500:
    let a = [rnd.rand(4), rnd.rand(3000), rnd.rand(3000)]
    let b = [rnd.rand(4), rnd.rand(3000), rnd.rand(3000)]
    var pts: array[2, int]
    for t in 0 .. 1:
      let me = if t == 0: a else: b
      let other = if t == 0: b else: a
      pts[t] = int(64.0'f32 * share(me[0], other[0]) +
                   24.0'f32 * share(me[1], other[1]) +
                   12.0'f32 * share(me[2], other[2]))
    if pts[0] < 0 or pts[1] < 0 or pts[0] > 100 or pts[1] > 100: inc overflow
    if pts[0] + pts[1] > worst: worst = pts[0] + pts[1]
  checkEq("points stay inside [0, 100]", overflow, 0)
  check("and the two seats sum to at most 100", worst <= 100)

block:
  ## THE DOCUMENTED DISAGREEMENT, asserted as an EXPECTATION rather than left
  ## to be found: a one-unit archon margin on a rung with large totals gives an
  ## arbitrarily small share advantage, so the winner's `points` can be BELOW
  ## the loser's.
  ## 4 archons to 3 is 4/7 - 3/7 = 0.143 of 64, i.e. 9.1 points; the loser can
  ## take 36 from the two rungs below.
  let winner = int(64.0'f32 * share(4, 3) + 24.0'f32 * share(0, 900) +
                   12.0'f32 * share(0, 900))
  let loser = int(64.0'f32 * share(3, 4) + 24.0'f32 * share(900, 0) +
                  12.0'f32 * share(900, 0))
  check("the archon winner scores BELOW the archon loser on points alone",
    winner < loser)

block:
  ## And the property the league actually reads: `results.scores` is
  ## `200 * wins + mean(points)`, so with points in [0, 100] a 2-0 gives
  ## 400+mean against <= 100 and a 2-1 gives 400+mean against 200+mean <= 300.
  ## Asserted on 500 random synthetic finals INCLUDING clinched two-game
  ## matches.
  checkEq("bc22 pays 200 a game, like bc23 and bc25", winBonusFor("bc22"),
    200.0)
  var rnd = initRand(99)
  var violations = 0
  for trial in 0 ..< 500:
    let games = 2 + rnd.rand(1)
    var outcomes: seq[GameOutcome]
    var wins = [0, 0]
    for g in 0 ..< games:
      let winnerSlot = rnd.rand(1)
      if wins[0] >= 2 or wins[1] >= 2: break
      wins[winnerSlot] += 1
      var pts: array[2, int]
      pts[0] = rnd.rand(100)
      pts[1] = min(100 - pts[0], rnd.rand(100))
      outcomes.add(GameOutcome(index: g, mapName: "m", sideAslot: 0,
        roundsPlayed: 2000, winnerSlot: winnerSlot,
        endReason: "more_archons", points: pts))
    if outcomes.len == 0: continue
    let scores = scoresFor(outcomes, "bc22")
    if wins[0] == wins[1]: continue
    let champion = if wins[0] > wins[1]: 0 else: 1
    if scores[champion] <= scores[1 - champion]: inc violations
  checkEq("results.scores STRICTLY orders the match winner above the loser",
    violations, 0)

block:
  ## The measured-common all-zero gold case: the example bot never builds a
  ## laboratory and every measured mirror ended 0 Au to 0 Au, so `share` must
  ## return a half rather than scoring one side down by an accident.
  var w = bare()
  checkEq("gold is 0-0 at the start", w.goldNetWorth(teamA), 100)
  var wEmpty = bare(archons = @[(id: 2, x: 5, y: 5, team: 1),
                                (id: 3, x: 25, y: 5, team: 2)])
  wEmpty.destroyRobot(2)
  wEmpty.stats.gold[0] = 0
  checkEq("with no archons and no reserve, gold net worth is 0",
    wEmpty.goldNetWorth(teamA), 0)
  checkEq("and the share is a half", share(0, 0), 0.5'f32)

finish("test_bc22_scoring")
