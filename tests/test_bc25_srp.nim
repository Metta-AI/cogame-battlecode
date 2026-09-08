## bc25 Special Resource Patterns: `completeResourcePattern`'s legality and
## effect, the lifetime incrementing once a round, the bonus starting at
## lifetime >= 50 AND NOT AT 49, the RESET TO ZERO on a break, the bonus being
## per MINING TOWER rather than per team, and an enemy centre on the same tile
## being a separate registration.

import harness
import bc25_fixture

proc tick(w: World) =
  ## One `updateResourcePatterns` sweep, which is step 1b of a round.
  w.currentRound += 1
  w.updateResourcePatterns()

block:
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  check("an unpainted centre is refused",
    not w.canCompleteResourcePattern(r, loc(10, 10)))
  w.paintArea(pkResource, teamA, loc(10, 10))
  check("an exact one is legal",
    w.canCompleteResourcePattern(r, loc(10, 10)))
  w.stats.money[0] = 199
  check("199 chips is not enough",
    not w.canCompleteResourcePattern(r, loc(10, 10)))
  w.stats.money[0] = 200
  check("200 is", w.canCompleteResourcePattern(r, loc(10, 10)))
  w.doCompleteResourcePattern(r, loc(10, 10))
  checkEq("the team paid 200", w.getMoney(teamA), 0)
  checkEq("the centre is registered", w.srpCentres.len, 1)
  checkEq("at lifetime ZERO", int(w.srpLifetimes[w.idx(loc(10, 10))]), 0)
  checkEq("and it is not active yet",
    w.numActiveResourcePatterns(teamA), 0)
  check("and completing the SAME centre again is refused",
    not w.canCompleteResourcePattern(r, loc(10, 10)))

block:
  ## The bonus starts at lifetime >= 50 and NOT AT 49.
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  w.paintArea(pkResource, teamA, loc(10, 10))
  w.doCompleteResourcePattern(r, loc(10, 10))
  for i in 1 .. 49:
    w.tick()
  checkEq("after 49 sweeps the lifetime is 49",
    int(w.srpLifetimes[w.idx(loc(10, 10))]), 49)
  checkEq("and the pattern is still inactive",
    w.numActiveResourcePatterns(teamA), 0)
  w.tick()
  checkEq("the fiftieth takes it to 50",
    int(w.srpLifetimes[w.idx(loc(10, 10))]), 50)
  checkEq("and NOW it is active", w.numActiveResourcePatterns(teamA), 1)
  checkEq("worth +3", w.extraResourcesFromPatterns(teamA),
    ExtraResourcesFromPattern)

block:
  ## A broken pattern is dropped and its lifetime RESET to zero, so repainting
  ## it restarts the whole fifty-round clock.
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  w.paintArea(pkResource, teamA, loc(10, 10))
  w.doCompleteResourcePattern(r, loc(10, 10))
  for i in 1 .. 60: w.tick()
  checkEq("it is live", w.numActiveResourcePatterns(teamA), 1)
  w.setPaint(loc(11, 11), PaintNone)
  w.tick()
  checkEq("one wrong tile drops it", w.srpCentres.len, 0)
  checkEq("and RESETS the lifetime to zero",
    int(w.srpLifetimes[w.idx(loc(10, 10))]), 0)
  checkEq("so the bonus is gone", w.extraResourcesFromPatterns(teamA), 0)
  ## Repaint and re-complete: the clock starts again from zero.
  w.paintArea(pkResource, teamA, loc(10, 10))
  w.stats.money[0] = 1000
  w.doCompleteResourcePattern(r, loc(10, 10))
  for i in 1 .. 49: w.tick()
  checkEq("49 rounds after the REPAINT it is still inactive",
    w.numActiveResourcePatterns(teamA), 0)

block:
  ## THE BONUS IS PER MINING TOWER, NOT PER TEAM.
  var w = bare()
  let r = w.place(teamA, utSoldier, loc(10, 10))
  w.paintArea(pkResource, teamA, loc(10, 10))
  w.doCompleteResourcePattern(r, loc(10, 10))
  for i in 1 .. 50: w.tick()
  checkEq("one active pattern", w.numActiveResourcePatterns(teamA), 1)
  let a = w.place(teamA, utLevelOneMoneyTower, loc(20, 20))
  let b = w.place(teamA, utLevelOneMoneyTower, loc(22, 22))
  let chips = w.getMoney(teamA)
  w.mine(a)
  w.mine(b)
  checkEq("BOTH money towers get the +3", w.getMoney(teamA),
    chips + 2 * (UnitSpecs[utLevelOneMoneyTower].moneyPerTurn +
                 ExtraResourcesFromPattern))
  let p = w.place(teamA, utLevelOnePaintTower, loc(24, 24))
  p.paint = 0
  w.mine(p)
  checkEq("and so does a paint tower, into its own stash", p.paint,
    UnitSpecs[utLevelOnePaintTower].paintPerTurn + ExtraResourcesFromPattern)

block:
  ## An enemy centre on the same tile is a SEPARATE registration.
  var w = bare()
  let a = w.place(teamA, utSoldier, loc(10, 10))
  w.paintArea(pkResource, teamA, loc(10, 10))
  w.doCompleteResourcePattern(a, loc(10, 10))
  checkEq("A owns the centre", int(w.srpTeamByLoc[w.idx(loc(10, 10))]), 1)
  ## B repaints the whole 5x5 in its own colours and completes it.
  let b = w.place(teamB, utSoldier, loc(12, 10))
  w.paintArea(pkResource, teamB, loc(10, 10))
  w.stats.money[1] = 1000
  check("A's pattern no longer matches", not w.checkResourcePattern(teamA,
    loc(10, 10)))
  check("B's does", w.checkResourcePattern(teamB, loc(10, 10)))
  w.tick()
  checkEq("so A's registration is dropped at the top of the round",
    int(w.srpTeamByLoc[w.idx(loc(10, 10))]), 0)
  checkEq("and the list is empty", w.srpCentres.len, 0)
  check("now B may complete the same tile", w.canCompleteResourcePattern(b,
    loc(10, 10)))
  w.doCompleteResourcePattern(b, loc(10, 10))
  checkEq("the centre is now B's", int(w.srpTeamByLoc[w.idx(loc(10, 10))]), 2)
  checkEq("as a SEPARATE registration", w.srpCentres.len, 1)
  checkEq("with its own clock started at zero",
    int(w.srpLifetimes[w.idx(loc(10, 10))]), 0)

block:
  ## A centre whose 5x5 contains a wall or ruin is never valid.
  var w = bare(ruins = @[loc(11, 11)])
  let r = w.place(teamA, utSoldier, loc(10, 10))
  check("an SRP centre needs all 25 tiles paintable",
    not w.canCompleteResourcePattern(r, loc(10, 10)))

finish("test_bc25_srp")
