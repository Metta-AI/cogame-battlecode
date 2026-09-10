## BOUNDED ORDERS AND LEGALITY — the gate that says `saber` never emits an
## action the engine refuses, and the exemption that says
## `examplefuncsplayer19` MUST.

import std/[os, osproc, strutils]
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc19/rules
import battlecode/years/bc19/chassis/saber

block:
  ## (a) BOTH `PLAYER_SCRIPTED` resolutions produce a sheet that passes the
  ## SAME `sheet.validate` the LLM path uses -- which is what makes this
  ## gate meaningful and an LLM doctrine and a scripted one strictly
  ## comparable.
  checkEq("`awu` resolves to saber on bc19", baselineFor("bc19", "awu"),
    blSaber)
  checkEq("so does `saber`", baselineFor("bc19", "saber"), blSaber)
  checkEq("so does `wololo` -- bc22's name falls back to THIS year's strong " &
    "chassis", baselineFor("bc19", "wololo"), blSaber)
  checkEq("and so does anything unrecognised",
    baselineFor("bc19", "nonsense"), blSaber)
  checkEq("`scaffold` resolves to the weak floor",
    baselineFor("bc19", "scaffold"), blExamplefuncsplayer19)
  for name in ["example", "examplefuncsplayer", "examplefuncsplayer19"]:
    checkEq("and so does " & name, baselineFor("bc19", name),
      blExamplefuncsplayer19)
  checkEq("a seat that says nothing useful plays the STRONG doctrine",
    defaultBaselineFor("bc19"), blSaber)
  for kind in [blSaber, blExamplefuncsplayer19]:
    let s = baselineSheet("bc19", kind)
    checkEq($kind & "'s reply parses as a bc19 sheet", s.year, YearBc19)
    checkEq("with nothing defaulted", s.defaultsApplied.len, 0)
    checkEq("and no unknown field -- never `chassis`", s.unknownFields.len, 0)
    check("and a motto", s.motto.len > 0)
  checkEq("the weak floor answers the SAME all-defaults sheet -- the " &
    "CHASSIS, not the sheet, is what makes it weak (D1)",
    baselineSheet("bc19", blSaber).doctrine19,
    baselineSheet("bc19", blExamplefuncsplayer19).doctrine19)
  checkEq("and the chassis really is different",
    baselineChassis(blSaber) != baselineChassis(blExamplefuncsplayer19), true)
  checkEq("`saber` maps to bc19's strong kind",
    chassisKindFor(baselineChassis(blSaber)), ck19Saber)
  checkEq("and the weak floor to bc19's weak kind",
    chassisKindFor(baselineChassis(blExamplefuncsplayer19)),
    ck19Examplefuncsplayer19)

block:
  ## (b)/(c) THE LEGALITY GATE. `refused_actions` counts every action the
  ## engine refused at validation time OR threw on at enact time, so
  ## `refused_actions == 0` says every order `saber` emitted was legal for
  ## the acting robot at the moment it was emitted -- the right type, an
  ## adjacent passable empty affordable build square, a move inside SPEED
  ## onto a free square it could pay for, an attack inside the unit's own
  ## radius pair, a `mine` only by a pilgrim on a depot under capacity, a
  ## `give` only to an adjacent occupied square of amounts it holds, a
  ## trade only by a castle, and a radio radius it could afford.
  let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
  var strongWins = 0
  var games = 0
  var weakBuilt = 0
  var weakMoves = 0
  var weakRefused = 0
  var churchAttacks = 0
  for seed in [11, 300, 1300]:
    for name in ["seed-0043", "seed-0009"]:
      let sa = sideAslotFor(seed, 0)
      ## saber against saber: the legality gate proper.
      let (_, mirrorOut) = playGame(loadMap(name), sheets,
        [ck19Saber, ck19Saber], 0, sa, 400, 0)
      for t in 0 .. 1:
        checkEq("saber emits NOTHING the engine refuses on " & name &
          " seat " & $t, mirrorOut.refusedActions[t], 0)
        checkEq("and never trips the id-pool guard",
          mirrorOut.buildsRefused[t], 0)
        check("and no robot exceeded TurnMaxOps",
          mirrorOut.decisionOpsPeak[t] < TurnMaxOps)
      ## (e) saber beats the weak floor.
      let (_, o) = playGame(loadMap(name), sheets,
        [ck19Saber, ck19Examplefuncsplayer19], 0, sa, 1000, 0)
      inc games
      if o.winnerSlot == 0: inc strongWins
      checkEq("and saber is still legal against the weak floor on " & name,
        o.refusedActions[0], 0)
      weakBuilt += o.unitsBuilt[1]
      weakMoves += o.moves[1]
      weakRefused += o.refusedActions[1]
      churchAttacks += o.churchesBuilt[0] + o.churchesBuilt[1]
  checkEq("saber beats examplefuncsplayer19 on every pair", strongWins, games)
  checkEq("and there really were six of them", games, 6)

  ## (d) THE WEAK FLOOR ACTS -- and is NOT required to survive, to mine, to
  ## build a church, to trade or to compete.
  check("examplefuncsplayer19 built at least one crusader", weakBuilt >= 6)
  check("and moved", weakMoves >= 100)

  ## (c) AND ITS EXEMPTION IS ASSERTED AS SUCH. It draws a UNIFORM RANDOM
  ## DIRECTION, so it MUST sometimes walk into rock or into another unit
  ## (observed on the real engine: "Cannot move onto impassable terrain").
  ## `refused_actions == 0` on it would assert that the weak floor is not
  ## the weak floor, so a future "fix" to the oracle's other side fails
  ## loudly here.
  check("EXEMPT: examplefuncsplayer19's refused_actions is > 0, and that " &
    "is the point", weakRefused > 0)

block:
  ## THE CHASSIS NEVER EMITS A CHURCH ATTACK. It is LEGAL upstream (D6.1 --
  ## the CHURCH's `ATTACK_RADIUS` is the scalar 0, so every on-board square
  ## is in range for 0 fuel and 0 damage) and it is never a strategy.
  let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
  var churchTurns = 0
  var churchAttacks = 0
  var w = newWorld(loadMap("seed-0043"), 600)
  var sides = newSides19(sheets, 0)
  var rounds = 0
  while w.running and rounds < 600:
    runRound(w, sides, [ck19Saber, ck19Saber])
    inc rounds
    for r in w.robots:
      if r.unit != ukChurch: continue
      inc churchTurns
      let a = runSaber(w, sides[ord(r.team)], r)
      if a.hasAction and a.kind == akAttack: inc churchAttacks
  check("the gate game really fielded churches", churchTurns > 0)
  checkEq("AND NOT ONE CHURCH ATTACK WAS EVER EMITTED", churchAttacks, 0)

block:
  ## THE NEGATIVE CONTROL, run as a SUBPROCESS. `-d:bc19BrokenChassis` makes
  ## `saber`'s pilgrims MINE BUT NEVER `give` and its castles never build a
  ## second pilgrim -- exactly the failure a "did it build units?" check
  ## would pass -- and the survival gate MUST COME BACK RED.
  ##
  ## A GATE THAT CANNOT FAIL IS NOT A GATE.
  if not fileExists("tests" / "test_bc19_survival.nim"):
    check("the survival gate exists to be inverted", false)
  else:
    let cmd = "nim r -d:release -d:bc19BrokenChassis --hints:off " &
      "--verbosity:0 --path:src tests/test_bc19_survival.nim"
    let (output, code) = execCmdEx(cmd)
    check("THE BROKEN CHASSIS FAILS THE SURVIVAL GATE (exit " & $code & ")",
      code != 0)
    check("and it fails on the economy, not on a compile error",
      output.contains("FAIL") and
      (output.contains("deposited") or output.contains("mined") or
       output.contains("units")))

finish("test_bc19_baselines")
