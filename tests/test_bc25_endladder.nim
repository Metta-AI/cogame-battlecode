## bc25's end conditions: `paint_enough_area` firing MID-ACTION inside a
## splasher's AoE loop with the round still finishing, `destroy_all_units`
## firing the moment a team's last UNIT dies, `timeLimitReached` being
## `round >= 2000` so round 2000 IS played, the five tiebreak rungs firing in
## the engine's order, `coin_flip` being reachable and seeded from the world
## RNG, and `RESIGNATION` being provably unreachable.

import harness
import bc25_fixture

proc fillTo(w: World, team: Team, target: int) =
  ## Paint tiles until `team` holds `target` of them, skipping the tile a
  ## caller wants to keep free.
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if w.stats.livePainted[ord(team)] >= target: return
      let l = loc(x, y)
      if not w.isPaintable(l): continue
      if w.getPaint(l) != PaintNone: continue
      if w.getRobot(l) != nil: continue
      if l.distanceSquaredTo(loc(15, 15)) <= 4: continue
      w.setPaint(l, primaryPaint(team))

block:
  ## The win fires INSIDE the splasher's AoE loop, and the round still runs to
  ## its end.
  var w = bare()
  let r = w.place(teamA, utSplasher, loc(15, 15))
  w.fillTo(teamA, tilesToWin(w.areaWithoutWalls) - 3)
  check("three tiles short, no winner", not w.hasWinner)
  w.doAttackRobot(r, loc(15, 15))
  check("the splash crossed the line", w.hasWinner)
  checkEq("with PAINT_ENOUGH_AREA", w.domination, dfPaintEnoughArea)
  checkEq("and A is the winner", w.winner, teamA)
  check("but the round is NOT over: `running` is only cleared at step 6d",
    w.running)
  ## Every unit after the winner still takes its turn.
  var sides = newSides25(defaultSheets(), 0)
  runRound(w, sides, [ckSpaark, ckSpaark])
  check("and the end-of-round check then stops the game", not w.running)

block:
  ## `destroy_all_units` fires the moment a team's last UNIT — robot OR tower
  ## — dies, mid-sweep.
  var w = bare()
  var ids: seq[int]
  for id in w.execOrder: ids.add(id)
  for id in ids:
    if w.robotsById[id].team != teamB: continue
    check("no winner while B still has a unit", not w.hasWinner)
    w.destroyRobot(id)
  check("the last one sets it", w.hasWinner)
  checkEq("with DESTROY_ALL_UNITS", w.domination, dfDestroyAllUnits)
  checkEq("and the OPPONENT wins", w.winner, teamA)

block:
  ## A team with towers but no robots has NOT lost.
  var w = bare()
  let r = w.place(teamB, utSoldier, loc(10, 10))
  w.destroyRobot(r.id)
  check("killing a robot while towers stand is not a loss", not w.hasWinner)

block:
  ## `timeLimitReached` is `>=`, so round 2000 IS played.
  var w = bare(rounds = 2000)
  w.currentRound = 1999
  check("1999 is not the limit", not w.timeLimitReached())
  w.currentRound = 2000
  check("2000 is", w.timeLimitReached())

block:
  ## The five rungs, in the engine's order, one vector each.
  proc ladder(setup: proc (w: World)): Domination =
    var w = bare(rounds = 1)
    setup(w)
    w.currentRound = 1
    w.checkEndOfMatch()
    w.domination

  checkEq("rung 1: more squares painted", ladder(proc (w: World) =
    w.setPaint(loc(10, 10), primaryPaint(teamA))), dfMoreSquaresPainted)

  checkEq("rung 2: more towers alive", ladder(proc (w: World) =
    discard w.place(teamA, utLevelOneMoneyTower, loc(10, 10))),
    dfMoreTowersAlive)

  checkEq("rung 3: more chips", ladder(proc (w: World) =
    w.stats.money[0] += 1), dfMoreMoney)

  checkEq("rung 4: more paint in units", ladder(proc (w: World) =
    for id in w.execOrder:
      if w.robotsById[id].team == teamB: w.robotsById[id].paint -= 1),
    dfMorePaintInUnits)

  checkEq("rung 5: more robots alive", ladder(proc (w: World) =
    discard w.place(teamA, utSoldier, loc(10, 10))
    ## The extra soldier's own paint would decide rung 4 first, so give B the
    ## same amount back.
    for id in w.execOrder:
      if w.robotsById[id].team == teamB and w.robotsById[id].kind.isTowerType():
        w.robotsById[id].paint += UnitSpecs[utSoldier].paintCapacity
        break),
    dfMoreRobotsAlive)

  checkEq("everything tied: the coin flip", ladder(proc (w: World) = discard),
    dfCoinFlip)

block:
  ## The coin flip is drawn from the WORLD RNG, seeded from the map's own
  ## `randomSeed`, so it is reproducible — which `Math.random()` is not.
  var a = bare(rounds = 1)
  var b = bare(rounds = 1)
  a.currentRound = 1
  b.currentRound = 1
  a.checkEndOfMatch()
  b.checkEndOfMatch()
  checkEq("two worlds on the same seed flip the same way", a.winner, b.winner)
  checkEq("and both call it a coin flip", a.domination, dfCoinFlip)

block:
  ## `RESIGNATION` is provably unreachable from any chassis: it is not a value
  ## of `Domination` at all, and no action in `world.nim`, `towers.nim` or
  ## `comms.nim` sets a winner outside the six the ladder and the two instant
  ## conditions use.
  var seen: seq[string]
  for d in Domination:
    if d != dfNone: seen.add($d)
  checkEq("eight end reasons, and resignation is not one of them", seen,
    @["paint_enough_area", "destroy_all_units", "more_squares_painted",
      "more_towers_alive", "more_money", "more_paint_in_units",
      "more_robots_alive", "coin_flip"])

finish("test_bc25_endladder")
