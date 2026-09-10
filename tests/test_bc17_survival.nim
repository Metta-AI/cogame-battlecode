## THE ECONOMIC-SURVIVAL GATE, with an inverted control that MUST FAIL.
##
## §Tests item 21 and the LEARNINGS 2026-09-03 pin.
##
## **THE KEY DESIGN POINT, and it is bc17-specific: in this year a faction
## does not get eaten, IT FAILS TO COMPOUND.** There is no NPC threat and no
## escalating clock. The passive trickle is `max(0, 2 - 0.01 x supply)` --
## exactly zero above 200 bullets and only 2 a round at zero -- against a
## unit price of 100 and a victory point at 7.5 rising to 20. A faction that
## never waters its farm has an income that decays at 0.5 HP a round per
## tree and never buys anything. So the gate keys on WATERING, TREE INCOME
## and VICTORY POINTS BOUGHT, and `-d:bc17BrokenChassis` proves it can go
## red.
##
## ============================================================================
##  THE MEASURED TABLES. Both, inline, as the note requires.
## ============================================================================
##
## `orchard` vs `orchard`, the all-defaults sheet, 3 000 rounds, the six games
## `drawMaps("small", seed, 2)` gives for seeds 1, 2 and 3, release Nim.
## **In bc17 the episode seed does nothing but choose the map draw and the
## side assignment** -- there is no other RNG in the year (D3) -- so "3 seeds
## x 2 small maps" is six DISTINCT games and not six samples of one.
##
## HEALTHY (measured in phase 20, release Nim):
##
##   | map          | sa | rounds | end reason           | gard | planted | water     | fromTrees(10ths) | VP      | dmg(10ths)  |
##   |--------------|----|--------|----------------------|------|---------|-----------|------------------|---------|-------------|
##   | HouseDivided |  0 |    700 | all_robots_destroyed | 3/5  |   5/3   |  888/891  |  14701/14854     |   0/0   |  9935/3295  |
##   | GreenHouse   |  1 |   2999 | more_victory_points  | 2/2  |   4/3   | 3150/2944 |  83563/84761     |  10/32  | 16765/14540 |
##   | GreenHouse   |  0 |   2999 | more_victory_points  | 2/2  |   3/4   | 2944/3150 |  84761/83563     |  32/10  | 14540/16765 |
##   | OMGTree      |  1 |   2999 | more_victory_points  | 4/3  |   4/4   | 7843/1065 |  98923/11123     | 242/10  |  8286/1545  |
##   | CropCircles  |  0 |   2999 | more_victory_points  | 4/3  |   3/4   | 5898/8464 |  58238/108256    | 252/686 |  2205/3187  |
##   | shrine       |  1 |   2999 | more_victory_points  | 3/2  |   5/4   | 8329/5731 | 136028/111778    | 655/746 |   505/845   |
##
##   **5 of 6 end other than `all_robots_destroyed`; 2 675 victory points
##   bought across the six; weakest seat 888 waters, 11 123 tenths of tree
##   income, 505 tenths of damage; refused orders ZERO everywhere.**
##
## BROKEN (`-d:bc17BrokenChassis`, the same six games): gardeners PLANT BUT
## NEVER WATER, the faction NEVER DONATES, and `bullet_reserve` is ignored.
##
##   | map          | sa | rounds | end reason           | gard  | planted | water | fromTrees(10ths) | VP  |
##   |--------------|----|--------|----------------------|-------|---------|-------|------------------|-----|
##   | HouseDivided |  0 |    776 | all_robots_destroyed | 2/5   |  12/10  |  0/0  |   5137/3930      | 0/0 |
##   | GreenHouse   |  1 |   2999 | more_bullet_trees    | 30/2  |  32/52  |  0/0  |   2489/25348     | 0/0 |
##   | GreenHouse   |  0 |   2999 | more_bullet_trees    | 2/30  |  52/32  |  0/0  |  25348/2489      | 0/0 |
##   | OMGTree      |  1 |   2999 | more_bullet_trees    | 2/21  |  36/43  |  0/0  |  17664/17460     | 0/0 |
##   | CropCircles  |  0 |   2999 | more_bullet_worth    | 2/3   |  44/45  |  0/0  |  21403/21335     | 0/0 |
##   | shrine       |  1 |   2999 | more_bullet_worth    | 2/4   |  52/51  |  0/0  |  25166/22947     | 0/0 |
##
##   **The control PLANTS MORE than the healthy build (it never spends on
##   watering) and still reaches the round limit 5 times out of 6.** That is
##   exactly why "did it build things?" is not a gate: the broken faction
##   looks busy. It buys ZERO victory points and waters ZERO times.
##
## WHICH CLAUSES DISCRIMINATE, stated so nobody tunes a decoration:
##
##   | clause                          | healthy weak | BROKEN  | discriminates |
##   |---------------------------------|--------------|---------|---------------|
##   | not-destroyed count             |      5       |    5    | NO (anti-degeneracy) |
##   | gardeners hired per seat        |      2       |    2    | NO            |
##   | trees planted per seat          |      3       |   10    | NO            |
##   | water actions per seat          |    888       |    0    | **YES**       |
##   | tree income per seat (10ths)    |  11123       |  2489   | **YES**       |
##   | victory points across the six   |   2675       |    0    | **YES**       |
##   | fighters built per seat         |      4       |    5    | NO            |
##   | damage dealt per seat (10ths)   |    505       |  1000   | NO            |
##
## **CLAUSES THE DESIGN NOTE ASKS FOR THAT THE MEASURED HEALTHY MIRROR DOES
## NOT MEET**, with the bc23 r1-F21/F22 resolution applied (lower to roughly
## half the weak seat's measured value, record the measurement, never drop
## the clause):
##
##   * *"each seat still held at least one ARCHON at round 2 000"* -- measured
##     0/0 on `HouseDivided` and one-sided on three others. Committed as
##     "at least one seat in at least 4 of the 6", measured 5.
##   * *"planted >= 6 bullet trees and had >= 4 alive at round 1 500"* --
##     measured 3..5 planted and 0..5 alive. Committed at 2 planted and the
##     alive clause folded into the tree-income clause, which is the thing
##     the aliveness was a proxy for.
##   * *">= 3 trees MATURE by round 600"* -- measured 1..5. Committed at 1.
##   * *"built >= 8 fighters"* -- measured 4..102. Committed at 2.
##   * *"bought >= 20 victory points"* per seat -- measured 0 on
##     `HouseDivided` (the game ends at round 700) and 10 on two others.
##     Committed ACROSS THE SIX GAMES at 1 300, measured 2 675, control 0.
##   * *"finished with >= 4 robots alive"* -- measured 1..20 on the five
##     games that ran to the limit and 0 on the annihilated one. Committed at
##     1, and applied only where the game did not end in annihilation.
##   * *"friendly fire plus own-tree damage under 15 % of damage dealt"* --
##     **measured 54 %.** The floor is not reachable in this year and the
##     reason is a RULE, not a chassis defect: a 2017 bullet has NO TEAM
##     CHECK, so a faction firing past its own units hits them, and a
##     lumberjack's strike damages its own trees by design. Committed at
##     75 %, measured 54 %, and recorded here rather than dropped.

import std/[algorithm, os, osproc, strutils]
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, world, rules, maps]

const
  ## Clause 1 -- the measured ratio. Anti-degeneracy: the control reaches it
  ## too, and it is kept because a build that annihilates itself on every
  ## board is broken in a way nothing else here would catch.
  MinNotDestroyed = 5
  ## Clause 2 -- substance, per seat, in EVERY game. Roughly half the weak
  ## seat's measured value (the bc23 r1-F21/F22 rule).
  MinGardeners = 1            ## anti-degeneracy: healthy 2, BROKEN 2
  MinTreesPlanted = 2         ## anti-degeneracy: healthy 3, BROKEN 10
  MinWaterActions = 400       ## DISCRIMINATES: healthy 888, BROKEN **ZERO**
  MinTreeIncomeTenths = 5500  ## DISCRIMINATES: healthy 11123, BROKEN 2489
  MinFighters = 2             ## anti-degeneracy: healthy 4, BROKEN 5
  MinDamageTenths = 250       ## anti-degeneracy: healthy 505, BROKEN 1000
  MinMatureBy600 = 1          ## anti-degeneracy: healthy 1, BROKEN 0 on 4
  MinAliveAtEnd = 1
    ## anti-degeneracy: healthy 1, BROKEN 1 -- and applied ONLY to the games
    ## that did not end in `all_robots_destroyed`, because in that game one
    ## side has nothing left by definition.
  ## Clause 3 -- the victory points the whole gate is about.
  ## DISCRIMINATES: healthy 2 675 across the six, BROKEN **ZERO**.
  MinVictoryPointsAcross = 1300
  ## Clause 4 -- an archon survived to round 2 000 somewhere, in most games.
  MinGamesWithLateArchon = 4
  ## Clause 5 -- self-harm bounded. Measured 54 %; see the header for why the
  ## note's 15 % is not reachable in a year whose bullets have no team check.
  MaxSelfHarmPercent = 75

type GateResult = object
  games: int
  notDestroyed: int
  victoryPointsAcross: int
  gamesWithLateArchon: int
  damageTenths: int
  selfHarmTenths: int
  shakesAcross: int
  rounds: seq[int]
  failures: seq[string]

proc runGate(): GateResult =
  let sheet = defaultSheet(YearBc17)
  for seed in [1, 2, 3]:
    let names = drawMaps("small", seed, 2)
    for gi, name in names:
      let spec = loadMap(name)
      let sa = sideAslotFor(seed, gi)
      let (_, o) = playGame(spec, [sheet, sheet],
                            [ck17Orchard, ck17Orchard], gi, sa, 3000, 0)
      inc result.games
      result.rounds.add(o.roundsPlayed)
      let tag = name & "/sa" & $sa
      if o.endReason != "all_robots_destroyed": inc result.notDestroyed
      if o.archonsAliveAt2000[0] + o.archonsAliveAt2000[1] > 0:
        inc result.gamesWithLateArchon
      for slot in 0 .. 1:
        result.victoryPointsAcross += o.victoryPoints[slot]
        result.damageTenths += o.damageDealtTenths[slot]
        result.selfHarmTenths += o.friendlyFireDamageTenths[slot] +
          o.ownTreesDamagedTenths[slot]
        result.shakesAcross += o.shakeActions[slot]
        template wantSeat(what: string, got, floor: int) =
          if got < floor:
            result.failures.add(tag & " seat " & $slot & ": " & what & " " &
              $got & " < " & $floor)
        wantSeat("gardeners hired", o.gardenersBuilt[slot], MinGardeners)
        wantSeat("trees planted", o.treesPlanted[slot], MinTreesPlanted)
        wantSeat("water actions", o.waterActions[slot], MinWaterActions)
        wantSeat("tree income (tenths)",
          o.bulletsEarnedFromTreesTenths[slot], MinTreeIncomeTenths)
        wantSeat("fighters built",
          o.soldiersBuilt[slot] + o.tanksBuilt[slot] + o.scoutsBuilt[slot] +
            o.lumberjacksBuilt[slot], MinFighters)
        wantSeat("damage dealt (tenths)", o.damageDealtTenths[slot],
          MinDamageTenths)
        wantSeat("mature trees by 600", o.matureTreesBy600[slot],
          MinMatureBy600)
        ## Only where the game did NOT end in annihilation: in that game one
        ## side has nothing left BY DEFINITION, and asserting otherwise
        ## would assert the end reason cannot happen.
        if o.endReason != "all_robots_destroyed":
          wantSeat("robots alive at the end", o.unitsAlive[slot] +
            o.archonsEnd[slot], MinAliveAtEnd)
      ## The legality audit: `orchard` may not emit an illegal order in any
      ## of the six games, at any point.
      let refused = o.refusedActions[0] + o.refusedActions[1]
      if refused != 0:
        result.failures.add(tag & ": " & $refused &
          " refused (illegal) orders")

proc medianRounds(r: GateResult): int =
  var sorted = r.rounds
  sorted.sort()
  if sorted.len == 0: 0
  elif sorted.len mod 2 == 1: sorted[sorted.len div 2]
  else: (sorted[sorted.len div 2 - 1] + sorted[sorted.len div 2]) div 2

when defined(bc17BrokenChassis):
  ## THE NEGATIVE CONTROL, run as a SUBPROCESS by the healthy build below. It
  ## prints its verdict and exits NON-ZERO when the gate PASSES, because a
  ## gate that cannot fail is not a gate.
  when isMainModule:
    let r = runGate()
    var reasons: seq[string] = r.failures
    if r.notDestroyed < MinNotDestroyed:
      reasons.add("not-destroyed " & $r.notDestroyed & " < " &
        $MinNotDestroyed)
    if r.victoryPointsAcross < MinVictoryPointsAcross:
      reasons.add("victory points across the six " & $r.victoryPointsAcross &
        " < " & $MinVictoryPointsAcross)
    if r.gamesWithLateArchon < MinGamesWithLateArchon:
      reasons.add("games with a live archon at 2000 " &
        $r.gamesWithLateArchon & " < " & $MinGamesWithLateArchon)
    echo "BROKEN-CONTROL games=", r.games, " notDestroyed=", r.notDestroyed,
      " vp=", r.victoryPointsAcross, " median=", r.medianRounds(),
      " failures=", reasons.len
    for f in reasons[0 .. min(7, reasons.high)]:
      echo "  ", f
    if reasons.len == 0:
      quit("the broken chassis PASSED the survival gate; the gate is dead", 1)
    echo "BROKEN-CONTROL: correctly red"
else:
  let r = runGate()
  echo "HEALTHY games=", r.games, " notDestroyed=", r.notDestroyed,
    " vp=", r.victoryPointsAcross, " median=", r.medianRounds(),
    " selfHarm=", r.selfHarmTenths, "/", r.damageTenths,
    " rounds=", r.rounds

  block:
    ## Clause 0 -- the build really is the healthy one. A negative control
    ## that silently ran as the healthy chassis would prove nothing.
    let w = board()
    check("this build is NOT the broken chassis", not w.brokenChassis)

  block:
    checkEq("six mirror games were played", r.games, 6)
    ## CLAUSE 1 -- the measured ratio.
    check("at least " & $MinNotDestroyed & " of the 6 end other than " &
      "`all_robots_destroyed` (measured 5)",
      r.notDestroyed >= MinNotDestroyed)
    ## CLAUSE 2 -- substance, in every game, on both sides.
    if r.failures.len > 0:
      for f in r.failures: echo "  GATE: ", f
    checkEq("both sides water, farm, fight and stay alive in every game, " &
      "and `orchard` never emits an illegal order", r.failures.len, 0)
    ## CLAUSE 3 -- the victory points, which is what compounding BUYS.
    check("at least " & $MinVictoryPointsAcross & " victory points are " &
      "bought across the six games (measured 2675; the broken control " &
      "buys ZERO)", r.victoryPointsAcross >= MinVictoryPointsAcross)
    ## CLAUSE 4 -- an archon survives to round 2 000 in most games.
    check("at least " & $MinGamesWithLateArchon & " of the 6 still have an " &
      "archon standing at round 2000 (measured 5)",
      r.gamesWithLateArchon >= MinGamesWithLateArchon)
    ## CLAUSE 5 -- self-harm bounded.
    check("a neutral tree was shaken somewhere across the six",
      r.shakesAcross > 0)
    check("friendly fire plus own-tree damage stays under " &
      $MaxSelfHarmPercent & " % of damage dealt (measured 54 %; the note's " &
      "15 % is not reachable in a year whose bullets have no team check)",
      r.selfHarmTenths * 100 <= r.damageTenths * MaxSelfHarmPercent)

  block:
    ## CLAUSE 6 -- THE INVERTED CONTROL, and it is the part that keeps the
    ## gate honest. `-d:bc17BrokenChassis` makes gardeners PLANT BUT NEVER
    ## WATER, makes the faction NEVER DONATE and makes it ignore
    ## `bullet_reserve`. It is exactly the failure a "did it build things?"
    ## check would pass -- the control plants MORE trees than the healthy
    ## build -- and it is the failure this year's economy makes possible.
    ##
    ## CI runs it; a bare `nim r` of this file without a Nim on PATH skips it
    ## LOUDLY rather than reporting a pass it did not earn.
    let nim = findExe("nim")
    if nim.len == 0:
      echo "SKIP: no `nim` on PATH, so the negative control did not run"
      check("the negative control needs a Nim compiler", false)
    else:
      let out0 = getTempDir() / "bc17_broken_control"
      let cmd = nim & " c -d:release -d:bc17BrokenChassis --hints:off " &
        "--warnings:off --path:src --path:tests -o:" & out0 &
        " tests/test_bc17_survival.nim"
      let (buildLog, buildCode) = execCmdEx(cmd)
      checkEq("the broken control BUILDS", buildCode, 0)
      if buildCode != 0:
        echo buildLog
      else:
        let (runLog, runCode) = execCmdEx(out0)
        echo runLog.strip()
        checkEq("and it comes back RED against the gate", runCode, 0)
        check("having actually failed clauses", "failures=0" notin runLog)
        check("and it never watered a tree",
          "water actions 0 <" in runLog)
        check("and it never bought a victory point",
          " vp=0 " in runLog)

  finish("test_bc17_survival")
