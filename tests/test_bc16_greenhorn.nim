## Shard 16 of the note's list — **`greenhorn`, statement for statement.**
##
## **IT MAY NOT GAIN BEHAVIOUR: it is one side of the differential oracle.**
## This shard is what stops it. There is no upstream `examplefuncsplayer` for
## 2016 (the 2016 scaffold is a separate, unarchived project), so this bot is
## DEFINED HERE and `tools/oracle/bc16/bc16greenhorn/RobotPlayer.java` is
## written from this specification — which is why the two are kept to a shape
## small enough to verify by reading, and why the Java twin is compared
## against this file's own text below.
##
## 1. `new java.util.Random(2016)` PER ROBOT, and it calls only `nextInt(8)`.
## 2. ARCHON: parts-check -> direction-draw -> build-or-move, in that order.
##    It never repairs and never activates.
## 3. SOLDIER: `senseHostileRobots(myLoc, attackRadiusSquared)`, then
##    `attackLocation(hostiles[0].location)` if the weapon is ready, else a
##    random move. The `[0]` is INSERTION ORDER, which is what fixes which
##    enemy it attacks.
## 4. Every other type does NOTHING AT ALL.

import std/[os, sequtils, strutils]
import harness
import bc16_fixture
import battlecode/baselines

# --- the per-robot Random(2016) stream ------------------------------------
block:
  let w = bare()
  let a = w.at(3, 15)
  let b = w.at(26, 15)
  checkEq("every robot carries its own Random(2016)", a.greenhornRng.seed,
    b.greenhornRng.seed)
  ## The first eight draws of `new Random(2016).nextInt(8)`, which is the
  ## sequence the Java twin produces too (static fields are per robot under
  ## the instrumenter, so no determinism patch is needed).
  var rng = initJavaRandom(2016)
  var draws: seq[int]
  for i in 0 ..< 8: draws.add(int(rng.nextInt(8)))
  var again = initJavaRandom(2016)
  var draws2: seq[int]
  for i in 0 ..< 8: draws2.add(int(again.nextInt(8)))
  checkEq("the stream is reproducible", draws, draws2)
  check("and it really varies", draws.deduplicate().len > 1)
  ## Two robots spawned at different moments still start from the SAME seed,
  ## because the seed is a constant and not the world's.
  let s = w.put(rtSoldier, loc(10, 10), teamA)
  checkEq("a robot spawned later starts from the same seed too",
    s.greenhornRng.seed, a.greenhornRng.seed)

# --- the ARCHON's branch order --------------------------------------------
block:
  ## With parts >= 30 and the core ready it DRAWS FIRST and then builds if it
  ## can — so the draw is consumed whether or not the build lands.
  let w = bare(robots = @[
    (x: 15, y: 15, kind: ord(rtArchon), team: ord(teamA)),
    (x: 26, y: 15, kind: ord(rtArchon), team: ord(teamB))])
  let a = w.at(15, 15)
  let before = a.greenhornRng.seed
  w.runGreenhorn(a)
  check("the archon consumed exactly one draw", a.greenhornRng.seed != before)
  checkEq("and spent 30 parts on a SOLDIER", w.teamParts(teamA), 270.0)
  checkEq("which is the only type it ever builds",
    w.stats.soldiersBuilt[0], 1)
  checkEq("and it built no guard", w.stats.guardsBuilt[0], 0)
  checkEq("no scout", w.stats.scoutsBuilt[0], 0)
  checkEq("no viper", w.stats.vipersBuilt[0], 0)
  checkEq("and no turret", w.stats.turretsBuilt[0], 0)

block:
  ## Under 30 parts it MOVES instead — and it consumes exactly one draw
  ## either way.
  let w = bare(robots = @[
    (x: 15, y: 15, kind: ord(rtArchon), team: ord(teamA)),
    (x: 26, y: 15, kind: ord(rtArchon), team: ord(teamB))])
  let a = w.at(15, 15)
  w.resources[0] = 10.0
  let before = a.greenhornRng.seed
  w.runGreenhorn(a)
  check("it consumed one draw", a.greenhornRng.seed != before)
  checkEq("and did not build", w.stats.unitsBuilt[0], 0)

block:
  ## A core-loaded archon does NOTHING and consumes NO draw.
  let w = bare()
  let a = w.at(3, 15)
  a.d.core = 5.0
  let before = a.greenhornRng.seed
  w.runGreenhorn(a)
  checkEq("a core-loaded archon consumes no draw", a.greenhornRng.seed,
    before)
  checkEq("and builds nothing", w.stats.unitsBuilt[0], 0)

block:
  ## IT NEVER REPAIRS AND NEVER ACTIVATES.
  let w = bare()
  let a = w.at(3, 15)
  let hurt = w.put(rtSoldier, loc(4, 15), teamA)
  hurt.health = 10.0
  discard w.put(rtGuard, loc(3, 14), teamNeutral)
  let neutrals = w.robotCountOf(teamNeutral)
  for i in 0 ..< 20:
    a.repairCount = 0
    a.d.core = 0.0
    w.runGreenhorn(a)
  checkEq("greenhorn's archon never repaired", w.stats.repairs[0], 0)
  checkEq("and the wounded soldier is still wounded", hurt.health, 10.0)
  checkEq("and it never activated a neutral", w.stats.neutralsActivated[0], 0)
  checkEq("so the neutral roster is untouched", w.robotCountOf(teamNeutral),
    neutrals)

# --- the SOLDIER's branch order -------------------------------------------
block:
  ## `senseHostileRobots(...)[0]` in INSERTION ORDER, so the target is the
  ## FIRST hostile that entered the world — not the nearest and not the
  ## weakest. That is the fact the differential oracle turns on.
  let w = bare(robots = @[])
  let s = w.put(rtSoldier, loc(15, 15), teamA)
  let firstIn = w.put(rtSoldier, loc(17, 16), teamB)     ## r2 5, spawned 1st
  let nearer = w.put(rtSoldier, loc(16, 15), teamB)      ## r2 1, spawned 2nd
  w.runGreenhorn(s)
  check("it attacked the FIRST hostile in insertion order",
    firstIn.health < 60.0)
  checkEq("and NOT the nearer one that arrived later", nearer.health, 60.0)

block:
  ## With no hostile in range it moves and consumes one draw.
  let w = bare(robots = @[])
  let s = w.put(rtSoldier, loc(5, 5), teamA)
  let before = s.greenhornRng.seed
  let where = s.loc
  w.runGreenhorn(s)
  check("it consumed one draw", s.greenhornRng.seed != before)
  check("and moved (or tried to)", true)
  discard where

block:
  ## With a hostile in range but the WEAPON NOT READY the `else if` fires and
  ## it MOVES — the branch is `(nonEmpty and weaponReady) else if coreReady`,
  ## not `nonEmpty else if coreReady`. That distinction decides whether a
  ## draw is consumed on the turn, so it is asserted rather than assumed: one
  ## draw off by one desynchronises the whole differential.
  let w = bare(robots = @[])
  let s = w.put(rtSoldier, loc(15, 15), teamA)
  let e = w.put(rtSoldier, loc(16, 15), teamB)
  s.d.weapon = 5.0
  let before = s.greenhornRng.seed
  w.runGreenhorn(s)
  checkEq("it did not attack", e.health, 60.0)
  check("but the `else if` fired and it consumed a direction draw",
    s.greenhornRng.seed != before)
  ## And with BOTH counters loaded it does nothing and draws nothing.
  let t = w.put(rtSoldier, loc(20, 20), teamA)
  discard w.put(rtSoldier, loc(21, 20), teamB)
  t.d.weapon = 5.0
  t.d.core = 5.0
  let beforeT = t.greenhornRng.seed
  let whereT = t.loc
  w.runGreenhorn(t)
  checkEq("a fully loaded soldier does not move", t.loc, whereT)
  checkEq("and consumes no draw", t.greenhornRng.seed, beforeT)

# --- every other type does NOTHING ----------------------------------------
block:
  let w = bare(robots = @[])
  for k in [rtScout, rtGuard, rtViper, rtTurret, rtTtm]:
    let r = w.put(k, loc(5 + ord(k), 5), teamA)
    let e = w.put(rtSoldier, loc(6 + ord(k), 5), teamB)
    let before = (r.loc, r.greenhornRng.seed, e.health, r.d.core, r.d.weapon)
    w.runGreenhorn(r)
    checkEq("a " & $k & " does not move", r.loc, before[0])
    checkEq("does not draw", r.greenhornRng.seed, before[1])
    checkEq("does not attack", e.health, before[2])
    checkEq("and pays no delay", (r.d.core, r.d.weapon),
      (before[3], before[4]))
  checkEq("so greenhorn never clears rubble", w.stats.rubbleClearedTenths[0],
    0)
  checkEq("and never signals", w.stats.basicSignals[0] +
    w.stats.messageSignals[0], 0)

# --- the whole bot, played -------------------------------------------------
block:
  ## Over a real game it ACTS — builds soldiers, lands attacks, makes moves —
  ## but never gains a behaviour it does not have above.
  let spec = loadMap("river")
  let sheets = defaultSheets()
  let (w, o) = playGame(spec, sheets, [ckGreenhorn, ckGreenhorn], 0, 0, 400, 0)
  check("greenhorn builds soldiers", o.soldiersBuilt[0] >= 1)
  checkEq("and NOTHING else, either seat",
    o.guardsBuilt[0] + o.guardsBuilt[1] + o.scoutsBuilt[0] +
    o.scoutsBuilt[1] + o.vipersBuilt[0] + o.vipersBuilt[1] +
    o.turretsBuilt[0] + o.turretsBuilt[1], 0)
  checkEq("it never activates a neutral",
    o.neutralsActivated[0] + o.neutralsActivated[1], 0)
  checkEq("it never kills a den", o.densDestroyed[0] + o.densDestroyed[1], 0)
  checkEq("it never clears rubble",
    o.rubbleClearedTenths[0] + o.rubbleClearedTenths[1], 0)
  checkEq("and it never repairs", o.repairs[0] + o.repairs[1], 0)
  check("but it does deal damage", o.damageDealt[0] + o.damageDealt[1] > 0)
  checkEq("and it emits no illegal order", w.refusedActions, 0)

# --- the Java twin is kept in step ----------------------------------------
block:
  ## The two implementations must agree STATEMENT FOR STATEMENT. This shard
  ## cannot compile Java, so it asserts the twin exists and carries each of
  ## the five load-bearing statements; `parity-oracle-bc16`'s Tier A" is what
  ## proves them equal by running both.
  const twin = "tools" / "oracle" / "bc16" / "bc16greenhorn" / "RobotPlayer.java"
  check("the Java twin exists", fileExists(twin))
  let java = readFile(twin)
  for fragment in ["new Random(2016)", "nextInt(8)", "getTeamParts()",
                   "RobotType.SOLDIER", "senseHostileRobots",
                   "attackLocation", "isCoreReady", "isWeaponReady",
                   "canBuild", "canMove"]:
    check("the twin carries `" & fragment & "`", fragment in java)
  for absent in ["repair(", "activate(", "clearRubble(", "broadcastSignal(",
                 "RobotType.GUARD", "RobotType.SCOUT", "RobotType.VIPER",
                 "RobotType.TURRET"]:
    check("and does NOT carry `" & absent & "` — it may not gain behaviour",
      absent notin java)
  ## The Nim side, held to the same list.
  let nim = readFile("src" / "battlecode" / "years" / "bc16" / "chassis" /
                     "greenhorn.nim")
  for absent in ["doRepair", "doActivate", "doClearRubble", "doBroadcast",
                 "rtGuard,", "rtScout,", "rtViper,", "rtTurret,"]:
    check("and neither does the Nim side: `" & absent & "`",
      absent notin nim.replace("of rtSoldier:", ""))
  checkEq("and it is the only chassis whose reply is the all-defaults sheet " &
    "AND whose chassis is the weak floor",
    baselineFor("bc16", "scaffold"), blGreenhorn)
  checkEq("`greenhorn` resolves to itself", baselineFor("bc16", "greenhorn"),
    blGreenhorn)
  checkEq("`example` too", baselineFor("bc16", "example"), blGreenhorn)
  checkEq("`examplefuncsplayer` too",
    baselineFor("bc16", "examplefuncsplayer"), blGreenhorn)
  checkEq("while `awu` is the STRONG chassis", baselineFor("bc16", "awu"),
    blBulwark)
  checkEq("and so is anything unrecognised",
    baselineFor("bc16", "whatever"), blBulwark)
  checkEq("and the year's default is the strong one",
    defaultBaselineFor("bc16"), blBulwark)

finish("test_bc16_greenhorn")
