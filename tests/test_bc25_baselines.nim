## bc25 baselines: both `PLAYER_SCRIPTED` resolutions going through the SAME
## `validate` the LLM path uses; EVERY ACTION EITHER CHASSIS EMITS BEING LEGAL
## AT THE MOMENT IT IS EMITTED and no unit exceeding its `DecisionOps` budget;
## `examplefuncsplayer25` ACTING but not being required to survive; and
## `spaark` beating it 6/6.

import harness
import std/strutils
import bc25_fixture
import battlecode/baselines

block:
  ## The reply sheets go through the same tolerant validator.
  for name in ["awu", "spaark", "nonsense", ""]:
    checkEq("`" & name & "` resolves to spaark on bc25",
      baselineFor("bc25", name), blSpaark)
  for name in ["scaffold", "examplefuncsplayer", "examplefuncsplayer25",
               "example"]:
    checkEq("`" & name & "` resolves to the weak floor",
      baselineFor("bc25", name), blExamplefuncsplayer25)
  checkEq("a seat that says nothing plays the STRONG doctrine",
    defaultBaselineFor("bc25"), blSpaark)
  checkEq("spaark's chassis", baselineChassis(blSpaark), scSpaark)
  checkEq("the floor's chassis", baselineChassis(blExamplefuncsplayer25),
    scExamplefuncsplayer25)
  checkEq("and dispatch maps it into bc25's own kind",
    chassisKindFor(scExamplefuncsplayer25), ckExamplefuncsplayer25)
  checkEq("a name belonging to ANOTHER year plays bc25's strong chassis",
    chassisKindFor(scGoneSharkin), ckSpaark)

block:
  ## (a) Both replies parse to a LEGAL sheet with nothing repaired, and BOTH
  ## are the all-defaults sheet -- the chassis, not the sheet, is what makes
  ## one of them the weak floor (D1).
  for kind in [blSpaark, blExamplefuncsplayer25]:
    let s = baselineSheet("bc25", kind)
    checkEq($kind & " repairs nothing", s.defaultsApplied.len, 0)
    checkEq($kind & " has no unknown field", s.unknownFields.len, 0)
    checkEq($kind & " is the all-defaults sheet", s.doctrine25,
      defaultDoctrine25())
    check($kind & " says something", s.notes.len > 0 and s.motto.len > 0)
  check("and neither reply mentions a chassis",
    not baselineReply(blSpaark).contains("chassis") and
    not baselineReply(blExamplefuncsplayer25).contains("chassis"))

block:
  ## THE FALLBACK SHEET IS THE SPAARK REPLY, verbatim -- so a seat that never
  ## answers plays exactly the doctrine the design note prints.
  let fallback = parseReply(baselineReply(blSpaark), "bc25")
  checkEq("the fallback sheet is the all-defaults doctrine",
    fallback.doctrine25, defaultDoctrine25())

block:
  ## (b) In played games EVERY action either chassis emits is legal at the
  ## moment it is emitted -- every `do*` re-checks its own `can*` and counts a
  ## no-op in `refusedActions` -- and no unit exceeds its budget.
  for (a, b) in [(ckSpaark, ckSpaark),
                 (ckSpaark, ckExamplefuncsplayer25),
                 (ckExamplefuncsplayer25, ckExamplefuncsplayer25)]:
    for mapName in ["DefaultSmall", "Filter"]:
      let (w, o) = playGame(loadMap(mapName), defaultSheets(), [a, b],
        0, 0, 600, 0)
      let label = $a & " vs " & $b & " on " & mapName
      checkEq(label & ": NO illegal order was ever emitted",
        w.refusedActions, 0)
      check(label & ": no unit exceeded the robot budget",
        w.opsUsedPeak <= DecisionOpsRobot)
      ## A game that ended early ended on a REAL end condition, not on a
      ## refused order: spaark can paint 70 % of `Filter` inside 600 rounds
      ## against the weak floor.
      check(label & ": the game really played",
        o.roundsPlayed >= 600 or o.endReason == "paint_enough_area" or
        o.endReason == "destroy_all_units")
      check(label & ": and it played long enough to mean something",
        o.roundsPlayed >= 200)
      var negative = 0
      for id in w.execOrder:
        let r = w.robotsById[id]
        if r.paint < 0 or r.health <= 0: negative += 1
        if r.paint > UnitSpecs[r.kind].paintCapacity: negative += 1
        if r.health > UnitSpecs[r.kind].health: negative += 1
      checkEq(label & ": no unit is out of bounds", negative, 0)
      check(label & ": chips never went negative",
        w.stats.money[0] >= 0 and w.stats.money[1] >= 0)
      check(label & ": neither clan holds more than 25 towers",
        w.stats.towers[0] <= MaxNumberOfTowers and
        w.stats.towers[1] <= MaxNumberOfTowers)

block:
  ## (c) `examplefuncsplayer25` ACTS -- and is NOT required to survive or to
  ## compete. It is the deliberate weak floor and the oracle's other side, and
  ## it MAY NOT GAIN BEHAVIOUR.
  let (w, o) = playGame(loadMap("DefaultSmall"), defaultSheets(),
    [ckExamplefuncsplayer25, ckExamplefuncsplayer25], 0, 0, 800, 0)
  check("it builds robots", o.robotsBuilt[0] >= 1 and o.robotsBuilt[1] >= 1)
  check("it paints tiles", o.tilesPainted[0] >= 1 and o.tilesPainted[1] >= 1)
  check("and it swings its mops",
    o.mopSwings[0] >= 1 and o.mopSwings[1] >= 1)
  checkEq("it never builds a splasher -- the branch is commented out " &
    "upstream and stays commented out here",
    o.splashersBuilt[0] + o.splashersBuilt[1], 0)
  checkEq("it never completes a resource pattern",
    o.srpCompleted[0] + o.srpCompleted[1], 0)
  checkEq("and it never upgrades a tower",
    o.towersUpgraded[0] + o.towersUpgraded[1], 0)

block:
  ## (d) `spaark` beats `examplefuncsplayer25` on 3 seeds x 2 `small` maps.
  var wins = 0
  var played = 0
  for mapName in ["DefaultSmall", "Filter"]:
    for seed in [1, 2, 3]:
      let sideAslot = seed and 1
      ## Seat 0 always drives spaark; `sideAslot` decides which ENGINE side
      ## that is, so the sweep plays spaark from both sides of the board.
      let (w, o) = playGame(loadMap(mapName), defaultSheets(),
        [ckSpaark, ckExamplefuncsplayer25], 0, sideAslot, 2000, 0)
      played += 1
      if o.winnerSlot == 0: wins += 1
      else:
        echo "BASELINE ", mapName, " s", seed, ": spaark lost (",
          o.endReason, " at round ", o.roundsPlayed, ", paint ",
          o.squaresPainted, ")"
  checkEq("spaark beats the weak floor 6 of 6", wins, played)
  checkEq("on six games", played, 6)

finish("test_bc25_baselines")
