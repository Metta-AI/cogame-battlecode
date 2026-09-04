## bc24 scoring: the points formula with FLOAT32 narrowing and TRUNCATION, one
## vector per weight, `share` returning 0.5 on a 0-0 total, points inside
## [0, 100] with the two seats summing to at most 100, and the ordering of
## `results.scores` agreeing with the winner on 200 random synthetic finals.

import std/random
import harness
import bc24_fixture
import battlecode/years/bc24/rules
import battlecode/match

# --- share ------------------------------------------------------------------
block:
  checkEq("a 0-0 total pays half to each", share(0, 0), 0.5'f32)
  checkEq("all of it", share(3, 0), 1.0'f32)
  checkEq("none of it", share(0, 3), 0.0'f32)
  checkEq("half of it", share(2, 2), 0.5'f32)
  checkEq("and a third", share(1, 2), float32(1) / float32(3))

# --- one vector per weight --------------------------------------------------
proc pointsFor(caps, levels, crumbs: array[2, int]): array[2, int] =
  var w = bare()
  w.stats.flagsCaptured = caps
  w.stats.crumbs = crumbs
  ## Level sums are read off the roster, so give the ducks the experience.
  var give = [levels[0], levels[1]]
  for r in w.robots:
    let t = ord(r.team)
    while give[t] > 0:
      r.attackExp = experienceFor(skAttack, min(6, give[t]))
      give[t] -= min(6, give[t])
      break
  w.gamePoints()

block:
  var w = bare()
  w.stats.flagsCaptured = [0, 0]
  w.stats.crumbs = [0, 0]
  let even = w.gamePoints()
  checkEq("a dead-even game pays each seat 50", even, [50, 50])
  checkEq("and the two seats sum to 100", even[0] + even[1], 100)

block:
  var w = bare()
  w.stats.flagsCaptured = [3, 0]
  w.stats.crumbs = [0, 0]
  let p = w.gamePoints()
  checkEq("all three flags is 60 + 12.5 + 7.5 = 80", p[0], 80)
  checkEq("and the loser keeps the level and crumb halves", p[1], 20)

block:
  var w = bare()
  w.stats.flagsCaptured = [0, 0]
  w.stats.crumbs = [1000, 0]
  let p = w.gamePoints()
  checkEq("all the crumbs is 30 + 12.5 + 15 = 57 (truncated)", p[0], 57)

block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  r.attackExp = experienceFor(skAttack, 6)
  w.stats.crumbs = [0, 0]
  let p = w.gamePoints()
  checkEq("A holds every skill level: 30 + 25 + 7 = 62", p[0], 62)

block:
  ## The `int()` cast TRUNCATES; it does not round. A one-third crumb share
  ## contributes 5.0 exactly, and a one-third level share 8.333..., which the
  ## truncation must eat.
  var w = bare()
  w.stats.flagsCaptured = [0, 0]
  w.stats.crumbs = [100, 200]
  let p = w.gamePoints()
  checkEq("30 + 12.5 + 5 truncates to 47", p[0], 47)
  checkEq("and the other seat gets 30 + 12.5 + 10 -> 52", p[1], 52)
  check("truncation means the two need not sum to 100", p[0] + p[1] < 100)

# --- bounds -----------------------------------------------------------------
block:
  var rng = initRand(20240904)
  var bad = 0
  var disagreements = 0
  for trial in 0 ..< 200:
    var w = bare()
    let capsA = rng.rand(0 .. 3)
    let capsB = rng.rand(0 .. 3)
    w.stats.flagsCaptured = [capsA, capsB]
    w.stats.crumbs = [rng.rand(0 .. 40000), rng.rand(0 .. 40000)]
    w.postSetup()
    for i in 0 ..< rng.rand(0 .. 20):
      let r = w.placeDuck(teamA, loc(1 + i, 8))
      r.attackExp = rng.rand(0 .. 200)
    for i in 0 ..< rng.rand(0 .. 20):
      let r = w.placeDuck(teamB, loc(20 + (i mod 8), 8 + i div 8))
      r.attackExp = rng.rand(0 .. 200)
    let p = w.gamePoints()
    if p[0] < 0 or p[1] < 0 or p[0] > 100 or p[1] > 100: bad += 1
    if p[0] + p[1] > 100: bad += 1
    ## THE CLAIM THE NOTE MAKES, and the one that is true: the term matching
    ## the rung the ladder decided on is always above one half. It is NOT that
    ## the weighted total favours the winner -- a seat can win on the level
    ## rung by a hair and still score lower because the loser banked every
    ## crumb, which is exactly what the 100-per-game WIN BONUS in
    ## `results.scores` exists to settle.
    w.currentRound = 2000
    w.checkEndOfMatch()
    if w.hasWinner:
      let t = ord(w.winner)
      let o = 1 - t
      case w.domination
      of dfMoreFlagCaptures:
        if share(w.stats.flagsCaptured[t], w.stats.flagsCaptured[o]) <= 0.5'f32:
          disagreements += 1
      of dfLevelSum:
        if share(w.levelSum(Team(t)), w.levelSum(Team(o))) <= 0.5'f32:
          disagreements += 1
      of dfMoreBread:
        if share(w.stats.crumbs[t], w.stats.crumbs[o]) <= 0.5'f32:
          disagreements += 1
      else: discard
      ## And `results.scores` -- points PLUS the win bonus -- always orders
      ## the winner first.
      var games = @[GameOutcome(winnerSlot: t, points: p)]
      let s = scoresFor(games)
      if s[t] <= s[o]: disagreements += 1
  checkEq("points stay in [0, 100] and sum to at most 100 on 200 finals",
    bad, 0)
  checkEq("the deciding rung's own share is always above one half, and " &
    "`results.scores` always orders the winner first", disagreements, 0)

# --- the episode score ------------------------------------------------------
block:
  var games: seq[GameOutcome]
  games.add(GameOutcome(winnerSlot: 0, points: [70, 30]))
  games.add(GameOutcome(winnerSlot: 1, points: [40, 60]))
  games.add(GameOutcome(winnerSlot: 0, points: [55, 45]))
  let s = scoresFor(games)
  checkEq("100 per win plus the mean of the points", s[0],
    200.0 + (70.0 + 40.0 + 55.0) / 3.0)
  checkEq("and the same for the other seat", s[1],
    100.0 + (30.0 + 60.0 + 45.0) / 3.0)
  check("the win bonus dominates the points spread", s[0] > s[1])

finish("bc24 scoring")
