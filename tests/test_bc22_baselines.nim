## Bounded orders and legality.
##
## §Tests item 16. The whole-game assertion is `refusedActions == 0`: every
## `do*` in `world.nim` re-checks its own `can*` and no-ops when it fails, and
## a chassis that emits an illegal order is a chassis whose orders were never
## checked. The counter is what makes that a gate rather than a hope.

import harness
import bc22_fixture
import battlecode/baselines

block:
  ## (a) Both `PLAYER_SCRIPTED` resolutions produce a sheet that passes the
  ## SAME `validate` the LLM path uses.
  checkEq("`awu` on bc22 resolves to wololo", baselineFor("bc22", "awu"),
    blWololo)
  checkEq("and so does anything unrecognised",
    baselineFor("bc22", "not-a-bot"), blWololo)
  checkEq("`scaffold` resolves to examplefuncsplayer22",
    baselineFor("bc22", "scaffold"), blExamplefuncsplayer22)
  checkEq("as does `examplefuncsplayer`",
    baselineFor("bc22", "examplefuncsplayer"), blExamplefuncsplayer22)
  checkEq("and `examplefuncsplayer22`",
    baselineFor("bc22", "examplefuncsplayer22"), blExamplefuncsplayer22)
  checkEq("a seat that says nothing plays the STRONG doctrine",
    defaultBaselineFor("bc22"), blWololo)
  checkEq("wololo's chassis", baselineChassis(blWololo), scWololo)
  checkEq("and the scaffold's", baselineChassis(blExamplefuncsplayer22),
    scExamplefuncsplayer22)
  checkEq("the year-neutral name maps into bc22's own kind",
    chassisKindFor(scWololo), ckWololo)
  checkEq("and so does the weak one",
    chassisKindFor(scExamplefuncsplayer22), ckExamplefuncsplayer22)
  checkEq("a name belonging to ANOTHER year falls back to bc22's strong one",
    chassisKindFor(scLemonade), ckWololo)

block:
  for kind in [blWololo, blExamplefuncsplayer22]:
    let sheet = baselineSheet("bc22", kind)
    checkEq($kind & "'s reply is the all-defaults sheet",
      sheet.doctrine22, defaultDoctrine22())
    checkEq($kind & "'s reply needs no repair", sheet.defaultsApplied.len, 0)
    check($kind & "'s reply carries no `chassis` key",
      "chassis" notin sheet.unknownFields)
    check($kind & " has a motto", sheet.motto.len > 0)
  ## The fallback sheet §Decisions prints verbatim IS the wololo reply.
  checkEq("the fallback motto", baselineSheet("bc22", blWololo).motto,
    "Leave one lead behind.")

block:
  ## (b) In PLAYED GAMES, every action either chassis emits is legal for the
  ## acting robot at the moment it is emitted, and NO ROBOT EXCEEDS ITS
  ## `DecisionOps` BUDGET.
  for mapName in ["chalice", "maze", "snowflake_redux"]:
    for pair in [[ckWololo, ckWololo],
                 [ckWololo, ckExamplefuncsplayer22],
                 [ckExamplefuncsplayer22, ckWololo]]:
      let (w, o) = playGame(loadMap(mapName), defaultSheets(),
        [pair[0], pair[1]], 0, 0, 800, 0)
      checkEq(mapName & " " & $pair[0] & " vs " & $pair[1] &
        ": no illegal order", w.refusedActions, 0)
      check("and no robot exceeded its budget",
        w.opsUsedPeak <= DecisionOpsArchon)
      check("the game actually played", o.roundsPlayed > 0)

block:
  ## The budget ceiling, per type, is enforced by the SIM and not by the bot.
  checkEq("an archon gets 2000", budgetFor(rtArchon), 2000)
  checkEq("a miner 1250", budgetFor(rtMiner), 1250)
  checkEq("a soldier 1250", budgetFor(rtSoldier), 1250)
  checkEq("a sage 1250", budgetFor(rtSage), 1250)
  checkEq("a watchtower 1250", budgetFor(rtWatchtower), 1250)
  checkEq("a builder 750", budgetFor(rtBuilder), 750)
  checkEq("and a laboratory 500", budgetFor(rtLaboratory), 500)
  ## A tenth of the Java limit for the archon, the builder and the laboratory
  ## — and 1 250 rather than 1 000 for the four types on the 10 000 limit,
  ## which the design note pins explicitly and `docs/RULES-BC22.md`
  ## §Divergences item 1 records as deliberate: a bc22 miner's nine-square
  ## scan plus its mine-move-mine turn is the busiest primitive sequence in
  ## the year, and 1 000 cut it short on the measured maps.
  checkEq("the archon is exactly a tenth", budgetFor(rtArchon) * 10,
    RobotSpecs[rtArchon].bytecodeLimit)
  checkEq("the builder is exactly a tenth", budgetFor(rtBuilder) * 10,
    RobotSpecs[rtBuilder].bytecodeLimit)
  checkEq("the laboratory is exactly a tenth", budgetFor(rtLaboratory) * 10,
    RobotSpecs[rtLaboratory].bytecodeLimit)
  for kind in RobotType:
    check($kind & "'s budget is at least a tenth of the Java limit",
      budgetFor(kind) * 10 >= RobotSpecs[kind].bytecodeLimit)
    check($kind & "'s budget is well under the Java limit itself",
      budgetFor(kind) < RobotSpecs[kind].bytecodeLimit)
  var w = bare()
  let r = w.place(teamA, rtBuilder, loc(5, 5))
  r.opsLeft = 2
  check("two credits buy two primitives", r.spend(1) and r.spend(1))
  check("and the third is refused", not r.spend(1))
  checkEq("the budget is never negative", r.opsLeft, 0)

block:
  ## (c) `examplefuncsplayer22` ACTS but is not required to survive, to build a
  ## building or to compete. Asserted across the pair, because whether an
  ## individual seat gets to build a soldier depends on a coin flip and on how
  ## long it lives.
  var miners = 0
  var soldiers = 0
  var lead = 0
  var damage = 0
  for sideAslot in 0 .. 1:
    let (w, o) = playGame(loadMap("chalice"), defaultSheets(),
      [ckExamplefuncsplayer22, ckExamplefuncsplayer22], 0, sideAslot, 600, 0)
    for slot in 0 .. 1:
      miners += o.minersBuilt[slot]
      soldiers += o.soldiersBuilt[slot]
      lead += o.leadMined[slot]
      damage += o.damageDealt[slot]
    discard w
  check("the weak floor builds miners", miners >= 1)
  check("and soldiers", soldiers >= 1)
  check("and mines lead", lead >= 1)
  check("and lands attacks", damage >= 1)

block:
  ## (d) `wololo` beats `examplefuncsplayer22` on 3 seeds x 2 small maps, 6/6.
  ## MEASURED IN PHASE 20: every one of the six is an `annihilated`, with the
  ## strong chassis at 97-99 points against 0-2.
  var wins = 0
  var games = 0
  for mapName in ["chalice", "maze"]:
    for seed in [0, 1, 2]:
      let sideAslot = sideAslotFor(seed, 0)
      ## Seat 0 is always wololo; which TEAM that is alternates with the seed.
      let (w, o) = playGame(loadMap(mapName), defaultSheets(),
        [ckWololo, ckExamplefuncsplayer22], 0, sideAslot, 2000, 0)
      inc games
      if o.winnerSlot == 0: inc wins
      checkEq(mapName & " seed " & $seed & ": no illegal order",
        w.refusedActions, 0)
  checkEq("six games played", games, 6)
  checkEq("and the strong chassis won all six", wins, 6)

finish("test_bc22_baselines")
