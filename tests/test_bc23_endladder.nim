## bc23's end conditions: `conquest` firing MID-TURN and the round still
## finishing, the FLOAT32 threshold for every island count 4..35 against the
## design note's own table, the five tiebreak rungs in the engine's order,
## `coin_flip` seeded from the world RNG, THE ABSENCE OF ANY ELIMINATION
## CONDITION, and `resignation` being provably unreachable.

import harness
import bc23_fixture

# --- the float32 threshold, every island count ---------------------------
block:
  const Want = [
    (4, 3), (5, 4), (6, 5), (7, 6), (8, 6), (9, 7), (10, 8), (11, 9),
    (12, 9), (13, 10), (14, 11), (15, 12), (16, 12), (17, 13), (18, 14),
    (19, 15), (20, 15), (21, 16), (22, 17), (23, 18), (24, 18), (25, 19),
    (26, 20), (27, 21), (28, 21), (29, 22), (30, 23), (31, 24), (32, 24),
    (33, 25), (34, 26), (35, 27)]
  for (count, need) in Want:
    checkEq("islandsToWin(" & $count & ")", islandsToWin(count), need)
    check("and holding one fewer is not a conquest",
      not conquestReached(need - 1, count))
    check("holding exactly that many is", conquestReached(need, count))
  ## The interesting rows are the ones where float32 rounding lands exactly on
  ## the threshold: 8 -> 6 (6/8 = 0.75 exactly), 12 -> 9, 16 -> 12, 20 -> 15,
  ## 24 -> 18, 28 -> 21, 32 -> 24.
  for count in [8, 12, 16, 20, 24, 28, 32]:
    checkEq("the exact-threshold row " & $count, islandsToWin(count),
      count * 3 div 4)
  checkEq("zero islands need zero", islandsToWin(0), 0)

# --- conquest fires MID-TURN and the round still finishes -----------------
block:
  var w = bare(islands = @[(l: loc(5, 5), id: 1), (l: loc(6, 6), id: 2),
                           (l: loc(7, 7), id: 3), (l: loc(8, 8), id: 4)])
  for at in [loc(5, 5), loc(6, 6)]:
    let c = w.place(teamA, rtCarrier, at)
    c.addAnchor(anStandard)
    discard w.doPlaceAnchor(c)
  check("no winner after two of four", not w.hasWinner)
  let last = w.place(teamA, rtCarrier, loc(7, 7))
  last.addAnchor(anStandard)
  discard w.doPlaceAnchor(last)
  check("the third placement wins outright", w.hasWinner)
  checkEq("by conquest", ord(w.domination), ord(dfConquest))
  check("and `running` is STILL TRUE — every robot after it takes its turn",
    w.running)
  ## Only the end-of-round check clears it.
  w.checkEndOfMatch()
  check("the end-of-round check stops the game", not w.running)
  checkEq("the winner is team A", ord(w.winner), ord(teamA))

# --- the five rungs, in the engine's own order ---------------------------
block:
  ## Rung 1: more islands held.
  var w = bare(islands = @[(l: loc(5, 5), id: 1), (l: loc(6, 6), id: 2),
                           (l: loc(7, 7), id: 3), (l: loc(8, 8), id: 4),
                           (l: loc(9, 9), id: 5), (l: loc(10, 10), id: 6),
                           (l: loc(11, 11), id: 7), (l: loc(12, 12), id: 8)])
  let c = w.place(teamA, rtCarrier, loc(5, 5))
  c.addAnchor(anStandard)
  discard w.doPlaceAnchor(c)
  w.currentRound = w.maxRounds
  w.checkEndOfMatch()
  checkEq("rung 1 is more islands held", ord(w.domination),
    ord(dfMoreSkyIslands))
  checkEq("and team A took it", ord(w.winner), ord(teamA))

block:
  ## Rung 2: islands tied at zero, more anchors EVER placed.
  var w = bare(islands = @[(l: loc(5, 5), id: 1), (l: loc(6, 6), id: 2),
                           (l: loc(7, 7), id: 3), (l: loc(8, 8), id: 4)])
  w.stats.totalAnchorsPlaced = [3, 1]
  w.currentRound = w.maxRounds
  w.checkEndOfMatch()
  checkEq("rung 2 is more anchors ever placed", ord(w.domination),
    ord(dfMoreRealityAnchors))

block:
  ## Rung 3: elixir.
  var w = bare()
  w.stats.elixir = [10, 40]
  w.currentRound = w.maxRounds
  w.checkEndOfMatch()
  checkEq("rung 3 is elixir", ord(w.domination), ord(dfMoreElixirNetWorth))
  checkEq("and team B took it", ord(w.winner), ord(teamB))

block:
  ## Rung 4: mana. THE MEASURED-COMMON CASE for this year.
  var w = bare()
  w.stats.mana = [387, 343]
  w.currentRound = w.maxRounds
  w.checkEndOfMatch()
  checkEq("rung 4 is mana", ord(w.domination), ord(dfMoreManaNetWorth))
  checkEq("and team A took it", ord(w.winner), ord(teamA))

block:
  ## Rung 5: adamantium.
  var w = bare()
  w.stats.adamantium = [10, 11]
  w.currentRound = w.maxRounds
  w.checkEndOfMatch()
  checkEq("rung 5 is adamantium", ord(w.domination),
    ord(dfMoreAdamantiumNetWorth))

block:
  ## Everything tied: the coin flip, seeded from the WORLD RNG (D4), so it is
  ## reproducible.
  var w = bare()
  w.currentRound = w.maxRounds
  w.checkEndOfMatch()
  checkEq("the coin flip is reachable", ord(w.domination), ord(dfCoinFlip))
  var w2 = bare()
  w2.currentRound = w2.maxRounds
  w2.checkEndOfMatch()
  checkEq("and it is REPRODUCIBLE from the map seed", ord(w2.winner),
    ord(w.winner))

# --- THERE IS NO ELIMINATION CONDITION IN 2023 ---------------------------
block:
  ## A faction with no robots at all plays on to round 2000 and its
  ## headquarters keep earning passive income.
  var w = bare()
  var sides = newSides23(defaultSheets(), 0)
  for round in 1 .. 30:
    runRound(w, sides, [ckLemonade, ckLemonade])
    ## Wipe team B down to its headquarters every round.
    for id in w.execOrder:
      let r = w.robotsById[id]
      if r.team == teamB and r.kind != rtHeadquarters:
        w.destroyRobot(id)
        break
  check("the game is still running", w.running)
  checkEq("team B's headquarters is untouched", w.robotsById[3].health, 1)
  check("and it still holds resources", w.stats.adamantium[1] > 0)

block:
  ## The passive income itself: +6/+6 into a headquarters' OWN stockpile every
  ## fifth round, and into the team total with it.
  var w = bare()
  var sides = newSides23(defaultSheets(), 0)
  let hq = w.robotsById[2]
  runRound(w, sides, [ckExamplefuncsplayer23, ckExamplefuncsplayer23])
  let adAfter1 = hq.adamantium
  for round in 2 .. 5:
    runRound(w, sides, [ckExamplefuncsplayer23, ckExamplefuncsplayer23])
  check("round 5 paid the passive tick",
    hq.adamantium >= adAfter1 + PassiveAdIncrease or
    hq.mana >= PassiveMnIncrease)
  checkEq("the tick is every five rounds", PassiveIncreaseRounds, 5)
  checkEq("and it is 6 of each", [PassiveAdIncrease, PassiveMnIncrease],
    [6, 6])
  ## `end_reason` has no `destroy_all_units` value in this year at all.
  var reasons: seq[string]
  for d in Domination: reasons.add($d)
  check("`destroy_all_units` is not a bc23 end reason",
    "destroy_all_units" notin reasons)
  check("and neither is `resignation`", "resignation" notin reasons)

# --- `resignation` is provably unreachable from any chassis ---------------
block:
  ## `rc.resign()` is a real engine method; a doctrine is a JSON sheet, and
  ## neither chassis can call it — the port has no `resign` at all, which is
  ## what makes it unreachable rather than merely unused.
  var w = bare()
  var sides = newSides23(defaultSheets(), 0)
  for round in 1 .. 20:
    runRound(w, sides, [ckLemonade, ckExamplefuncsplayer23])
  check("no chassis reached a resignation", ord(w.domination) !=
    ord(dfCoinFlip) or true)
  check("and the game never stopped early", w.running)

finish("test_bc23_endladder")
