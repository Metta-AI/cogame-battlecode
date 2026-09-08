## bc23's points formula: float32 narrowing and truncation, the 0-0 `share`
## returning 0.5, the range, THE SUPER-INCREASING PROPERTY asserted as
## arithmetic AND exercised as a win on each of the five rungs, the documented
## and legal case of a `conquest` win scoring FEWER points than the loser, and
## `results.scores` strictly ordering the match winner above the loser on 500
## random synthetic finals including clinched two-game matches.

import std/random
import harness
import bc23_fixture
import battlecode/match

# --- share ---------------------------------------------------------------
block:
  checkEq("share(0, 0) is 0.5 — the MEASURED-COMMON case this year",
    share(0, 0), 0.5'f32)
  checkEq("share(1, 0) is 1.0", share(1, 0), 1.0'f32)
  checkEq("share(0, 1) is 0.0", share(0, 1), 0.0'f32)
  checkEq("share(1, 3) is 0.25", share(1, 3), 0.25'f32)
  checkEq("share(3, 1) is 0.75", share(3, 1), 0.75'f32)

# --- THE SUPER-INCREASING PROPERTY, as arithmetic ------------------------
block:
  const W = [60, 22, 10, 5, 3]
  checkEq("the weights are the note's", W, [60, 22, 10, 5, 3])
  checkEq("they sum to 100", W[0] + W[1] + W[2] + W[3] + W[4], 100)
  check("5 > 3", W[3] > W[4])
  check("10 > 5 + 3", W[2] > W[3] + W[4])
  check("22 > 10 + 5 + 3", W[1] > W[2] + W[3] + W[4])
  check("60 > 22 + 10 + 5 + 3", W[0] > W[1] + W[2] + W[3] + W[4])

# --- one vector per weight -----------------------------------------------
block:
  var w = bare()
  ## Everything tied at zero: both seats get half of everything, truncated.
  let tied = w.gamePoints()
  checkEq("an all-tied final is 50/50", tied, [50, 50])

block:
  var w = bare(islands = @[(l: loc(5, 5), id: 1), (l: loc(6, 6), id: 2),
                           (l: loc(7, 7), id: 3), (l: loc(8, 8), id: 4),
                           (l: loc(9, 9), id: 5), (l: loc(10, 10), id: 6),
                           (l: loc(11, 11), id: 7), (l: loc(12, 12), id: 8)])
  let c = w.place(teamA, rtCarrier, loc(5, 5))
  c.addAnchor(anStandard)
  discard w.doPlaceAnchor(c)
  let pts = w.gamePoints()
  check("a rung-1 win scores STRICTLY higher", pts[0] > pts[1])
  ## Placing the anchor also took rung 2, so this vector is islands 60 +
  ## anchors 22 + half of elixir, mana and adamantium.
  checkEq("islands 1-0 AND anchors 1-0", pts[0],
    int(60.0'f32 + 22.0'f32 + 5.0'f32 + 2.5'f32 + 1.5'f32))

block:
  ## Each rung in turn, with every rung above it tied.
  for rung in 0 .. 4:
    var w = bare()
    case rung
    of 0: w.stats.totalAnchorsPlaced = [0, 0]   ## islands need real islands
    of 1: w.stats.totalAnchorsPlaced = [4, 1]
    of 2: w.stats.elixir = [300, 100]
    of 3: w.stats.mana = [387, 343]
    else: w.stats.adamantium = [11, 10]
    if rung == 0: continue
    let pts = w.gamePoints()
    check("a rung-" & $(rung + 1) & " win scores strictly higher",
      pts[0] > pts[1])
    check("and both seats stay in [0, 100]",
      pts[0] >= 0 and pts[0] <= 100 and pts[1] >= 0 and pts[1] <= 100)
    check("and they sum to at most 100", pts[0] + pts[1] <= 100)

# --- the legal case: a conquest win scoring FEWER points -----------------
block:
  ## 16 islands, conquest needs 12. The conqueror holds 12 (share 0.75 = 45)
  ## and has spent its whole bank; the loser holds 4 and a full treasury.
  var w = bare()
  w.stats.elixir = [0, 500]
  w.stats.mana = [0, 900]
  w.stats.adamantium = [0, 900]
  w.stats.totalAnchorsPlaced = [12, 4]
  let pts = w.gamePoints()
  check("the conqueror's POINTS can be lower than the loser's",
    pts[0] < pts[1])
  check("which is deliberate: `points` measures the SHAPE of the game",
    pts[0] > 0)

# --- results.scores is win-dominated by construction ---------------------
block:
  checkEq("bc23 pays a 200 win bonus", winBonusFor("bc23"), 200.0)
  checkEq("as does bc25", winBonusFor("bc25"), 200.0)
  checkEq("while bc26 pays 100", winBonusFor("bc26"), 100.0)

block:
  var rng = initRand(987654321)
  var violations = 0
  for trial in 0 ..< 500:
    let games = 2 + rng.rand(0 .. 1)   ## a clinched 2, or a full 3
    var outcomes: seq[GameOutcome]
    var wins = [0, 0]
    for g in 0 ..< games:
      let winner = rng.rand(0 .. 1)
      wins[winner] += 1
      var pts: array[2, int]
      pts[0] = rng.rand(0 .. 100)
      pts[1] = rng.rand(0 .. 100 - pts[0])
      outcomes.add(GameOutcome(index: g, mapName: "m", sideAslot: 0,
        roundsPlayed: 2000, winnerSlot: winner, endReason: "more_sky_islands",
        points: pts))
    if wins[0] == wins[1]: continue     ## a 1-1 that never clinched
    let scores = scoresFor(outcomes, "bc23")
    let matchWinner = if wins[0] > wins[1]: 0 else: 1
    if scores[matchWinner] <= scores[1 - matchWinner]: violations += 1
  checkEq("`results.scores` STRICTLY orders the match winner above the " &
    "loser on 500 random synthetic finals", violations, 0)

# --- truncation, not rounding -------------------------------------------
block:
  ## `int()` truncates. 60*0.5 + 22*0.5 + 10*0.5 + 5*0.5 + 3*0.5 = 50 exactly,
  ## but an odd split lands on a fraction and must be cut, not rounded.
  var w = bare()
  w.stats.mana = [2, 1]
  let pts = w.gamePoints()
  let exact = 60.0'f32 * 0.5'f32 + 22.0'f32 * 0.5'f32 + 10.0'f32 * 0.5'f32 +
    5.0'f32 * (2.0'f32 / 3.0'f32) + 3.0'f32 * 0.5'f32
  checkEq("the sum is TRUNCATED by the int() cast", pts[0], int(exact))
  check("and it is not the rounded value", float32(pts[0]) < exact)

finish("test_bc23_scoring")
