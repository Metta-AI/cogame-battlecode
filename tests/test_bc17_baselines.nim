## §Tests item 20 -- the two scripted baselines: BOUNDED ORDERS and LEGALITY.
##
## `orchard` is the strong published chassis and the champions' chassis;
## `examplefuncsplayer17` is the deliberately weak floor and the other side
## of the differential oracle. Both must exist in the same image from day
## one, both must produce a sheet the LLM path's own validator accepts, and
## neither may emit an order the sim refuses.
##
## **THE LEGALITY AUDIT IS `refused_actions`, and that is not a shortcut.**
## Every guard in `actions.nim` funnels through `refuse()`, which increments
## that counter -- the actor's type, one move and one attack a turn, the
## stride clamp, the emptiness test with its TANK/SCOUT split, the shot
## shape and its funding, the interaction distance, the build cooldown, the
## channel bounds and the donation's affordability. A game that ends with
## `refused_actions == 0` is a game in which every order either chassis
## emitted was legal for the acting robot at the moment it was emitted.
##
## **ONE CLAUSE OF THE DESIGN NOTE IS NOT MET AND IS RECORDED RATHER THAN
## DROPPED.** The note expects `refused_actions[weak] > 0`, on the reasoning
## that `examplefuncsplayer17` draws a uniform random direction and must
## therefore sometimes try to walk into a tree or off the map. **Measured: it
## is ZERO.** The reason is a property of the stock bot, not a fix to it: the
## 2017 `examplefuncsplayer`'s `tryMove` probes seven directions with
## `rc.canMove` before it moves, and its two build gates go through
## `rc.canBuildRobot`/`canHireGardener` first -- so the random draw chooses
## AMONG LEGAL ORDERS and never emits an illegal one. The shard asserts zero
## on both seats and says why here, so a future change that starts producing
## refusals is still a visible change.

import harness
import bc17_fixture
import battlecode/[baselines, sheet]
import battlecode/years/bc17/[constants, world, rules, maps]
import battlecode/years/bc17/chassis/examplefuncsplayer17

# --- (a) both PLAYER_SCRIPTED resolutions give a VALID sheet ---------------
block:
  ## An unrecognised name takes the year's STRONG chassis; the four weak
  ## aliases take the floor.
  checkEq("bc17's default baseline is orchard", defaultBaselineFor("bc17"),
    blOrchard)
  for name in ["orchard", "awu", "", "nonsense", "wololo"]:
    checkEq("PLAYER_SCRIPTED=" & name & " resolves to orchard",
      baselineFor("bc17", name), blOrchard)
  for name in ["scaffold", "example", "examplefuncsplayer",
               "examplefuncsplayer17", "  ExampleFuncsPlayer17  "]:
    checkEq("PLAYER_SCRIPTED=" & name & " resolves to the weak floor",
      baselineFor("bc17", name), blExamplefuncsplayer17)
  ## Both resolutions produce a sheet through the SAME validator the LLM
  ## path uses -- and both produce the SAME sheet, because the chassis and
  ## not the sheet is what makes the floor the floor (D0).
  for kind in [blOrchard, blExamplefuncsplayer17]:
    let s = baselineSheet("bc17", kind)
    checkEq($kind & "'s sheet is a bc17 sheet", s.year, "bc17")
    checkEq("and it applies no defaults -- every knob is stated",
      s.defaultsApplied.len, 0)
    checkEq("and carries no unknown fields", s.unknownFields.len, 0)
    check("its notes are non-empty", s.notes.len > 0)
    check("and its motto too", s.motto.len > 0)
  checkEq("the two baselines answer with the IDENTICAL sheet",
    baselineSheet("bc17", blOrchard).doctrine17,
    baselineSheet("bc17", blExamplefuncsplayer17).doctrine17)
  ## And it is the all-defaults sheet.
  checkEq("which is the all-defaults doctrine",
    baselineSheet("bc17", blOrchard).doctrine17,
    defaultSheet(YearBc17).doctrine17)

# --- the chassis vocabulary is year-neutral --------------------------------
block:
  checkEq("orchard maps to the bc17 kind",
    chassisKindFor(scOrchard), ck17Orchard)
  checkEq("examplefuncsplayer17 maps to the weak one",
    chassisKindFor(scExamplefuncsplayer17), ck17Examplefuncsplayer17)
  ## A name belonging to ANOTHER year falls back to THIS year's strong
  ## chassis, so a bc22 name on a bc17 game plays orchard rather than
  ## nothing.
  for other in [scWololo, scBulwark, scSaber, scAwu, scSpaark]:
    checkEq($other & " on a bc17 game plays orchard",
      chassisKindFor(other), ck17Orchard)
  checkEq("chassisFromName round-trips orchard",
    chassisFromName("orchard"), ck17Orchard)
  checkEq("and the weak floor", chassisFromName("examplefuncsplayer17"),
    ck17Examplefuncsplayer17)

# --- (b), (c), (d), (e): the six gate games --------------------------------
block:
  ## `orchard` on seat 0, `examplefuncsplayer17` on seat 1, over the six
  ## games `drawMaps("small", seed, 2)` gives for seeds 1, 2 and 3.
  let sheet = defaultSheet(YearBc17)
  var games = 0
  var orchardWins = 0
  var weakGardeners = 0
  var weakFighters = 0
  var weakShots = 0
  var weakMoves = 0
  var refusedStrong = 0
  var refusedWeak = 0
  var opsOverCap = 0
  for seed in [1, 2, 3]:
    for gi, name in drawMaps("small", seed, 2):
      let spec = loadMap(name)
      let (_, o) = playGame(spec, [sheet, sheet],
                            [ck17Orchard, ck17Examplefuncsplayer17], gi,
                            sideAslotFor(seed, gi), 3000, 0)
      inc games
      if o.winnerSlot == 0: inc orchardWins
      refusedStrong += o.refusedActions[0]
      refusedWeak += o.refusedActions[1]
      weakGardeners += o.gardenersBuilt[1]
      weakFighters += o.soldiersBuilt[1] + o.tanksBuilt[1] +
        o.scoutsBuilt[1] + o.lumberjacksBuilt[1]
      weakShots += o.bulletsFired[1]
      weakMoves += o.moves[1]
      for slot in 0 .. 1:
        if o.decisionOpsPeak[slot] >= ArchonOps: inc opsOverCap
      ## Every game must have a real end reason and a winner.
      check(name & " reported a real end reason",
        o.endReason in world.Bc17RungNames)
      check(name & " recorded a winner", o.winnerSlot >= 0)
  checkEq("six gate games were played", games, 6)
  ## (b) THE LEGALITY AUDIT.
  checkEq("`orchard` emitted NOT ONE illegal order across the six games",
    refusedStrong, 0)
  checkEq("and neither did `examplefuncsplayer17` -- see the header: its " &
    "`tryMove` probes with canMove before it moves, so the random draw " &
    "chooses among LEGAL orders (the note expected > 0 here; measured 0)",
    refusedWeak, 0)
  checkEq("no robot on either side exceeded its DecisionOps cap",
    opsOverCap, 0)
  ## (d) the weak floor ACTS -- but is not required to compete.
  check("the weak floor hired at least one gardener (" & $weakGardeners &
    ")", weakGardeners >= 1)
  check("built at least one fighter (" & $weakFighters & ")",
    weakFighters >= 1)
  check("fired at least one shot (" & $weakShots & ")", weakShots >= 1)
  check("and moved at least a hundred times (" & $weakMoves & ")",
    weakMoves >= 100)
  ## (e) and it LOSES, every time.
  checkEq("`orchard` beats `examplefuncsplayer17` on 3 seeds x 2 small " &
    "maps, 6 of 6", orchardWins, 6)
  echo "  orchard ", orchardWins, "/", games, "; weak floor hired ",
    weakGardeners, " gardeners, built ", weakFighters, " fighters, fired ",
    weakShots, " bullets and moved ", weakMoves, " times"

# --- the mirror is legal too ------------------------------------------------
block:
  ## The gate above pits the two chassis against each other. A mirror of
  ## each against itself exercises paths a one-sided game never reaches --
  ## two farms competing for the same ground, two weak floors wandering.
  for kind in [ck17Orchard, ck17Examplefuncsplayer17]:
    let (_, o) = mirror("CropCircles", chassis = [kind, kind], rounds = 600)
    checkEq($kind & " mirrors without an illegal order",
      o.refusedActions[0] + o.refusedActions[1], 0)
    check($kind & " played the whole 600 rounds or ended honestly",
      o.roundsPlayed > 0)
    check("and neither seat blew its op budget",
      o.decisionOpsPeak[0] < ArchonOps and o.decisionOpsPeak[1] < ArchonOps)

# --- a strike never costs more of its own than the enemy's -----------------
block:
  ## The note's clause, checked on the aggregate the sim records: over the
  ## gate games `orchard`'s own-tree damage must not swamp the damage it
  ## deals. (A lumberjack's strike hits its own trees BY RULE -- the clause
  ## bounds it, it does not forbid it.)
  let sheet = defaultSheet(YearBc17)
  var ownTrees = 0
  var dealt = 0
  for seed in [1, 2, 3]:
    for gi, name in drawMaps("small", seed, 2):
      let (_, o) = playGame(loadMap(name), [sheet, sheet],
                            [ck17Orchard, ck17Examplefuncsplayer17], gi,
                            sideAslotFor(seed, gi), 3000, 0)
      ownTrees += o.ownTreesDamagedTenths[0]
      dealt += o.damageDealtTenths[0]
  check("`orchard` dealt real damage", dealt > 0)
  check("and its own-tree damage is a small fraction of it (" &
    $ownTrees & " of " & $dealt & ")", ownTrees * 4 <= dealt)

# --- the TANK/SCOUT fall-through, the one branch no game reaches ----------
block:
  ## §Tests item 19's *"the TANK/SCOUT fall-through killing the robot on its
  ## first turn"*. Tier A" proves the weak floor's RNG stream differentially
  ## over nine whole 2 999-round games, which is stronger evidence than any
  ## unit test -- but it cannot reach THIS branch, because
  ## `examplefuncsplayer17` never builds a TANK or a SCOUT and the parity
  ## job's `types=` column never lists either. `build_oracle.sh` greps the
  ## Java copy for `RobotType.TANK` and `RobotType.SCOUT` and FAILS ON A HIT,
  ## so the branch can never be reached from a game and can only be reached
  ## synthetically (r1-F11).
  ##
  ## The rule is `RobotPlayer.java:8-10`: **"If this method returns, the
  ## robot dies!"** The switch has no `case` for either type, so `run()`
  ## returns on the robot's very first turn and the engine destroys it.
  for kind in [rtTank, rtScout]:
    var w = newWorld(loadMap("Alone"), gameDefaultRounds)
    let o = w.rect.origin
    let victim = w.spawnRobot(kind, loc(o.x + 50'f32, o.y + 50'f32), tA)
    let survivor = w.spawnRobot(rtSoldier, loc(o.x + 60'f32, o.y + 50'f32),
                                tA)
    let id = victim.id
    let before = victim.loc
    let lostBefore = w.stats.unitsLost[ord(tA)]
    check($kind & " is on the board before its turn", w.robots.hasKey(id))
    w.processBeginningOfTurn(victim)
    runExamplefuncsplayer17(w, victim)
    check("a " & $kind & " handed to the weak floor is DEAD on its first " &
      "turn -- the switch has no case for it and run() returns",
      not w.robots.hasKey(id))
    check("and the sim counted the loss", w.stats.unitsLost[ord(tA)] ==
      lostBefore + 1)
    check("it never moved first", before == victim.loc)
    checkEq("it fired nothing", w.stats.bulletsFired[ord(tA)], 0)
    checkEq("and broadcast nothing", w.stats.broadcasts[ord(tA)], 0)
    ## The contrast that makes the assertion mean something: a type the
    ## switch DOES handle survives the same call.
    w.processBeginningOfTurn(survivor)
    survivor.roundsAlive = 21
    runExamplefuncsplayer17(w, survivor)
    check("while a SOLDIER, which the switch does handle, survives the " &
      "same call", w.robots.hasKey(survivor.id))

finish("test_bc17_baselines")
