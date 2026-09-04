## The whole speech, with a vector per branch of `InternalRobot.empower` /
## `empowered`: the scan order and the ids it produces, the two "nobody is
## affected but the politician still dies" cases, the split including allies
## and neutrals in the divisor, the unbuffed friendly Center, the capped heal,
## the buffed-until-conversion enemy Center formula, conversion influence and
## conviction, the parent pointer, and `(int)` truncation toward zero.

import harness
import battlecode/rng
import battlecode/years/bc21/[constants, world, empower]

proc flat(width, height: int): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.origin = [0, 0]
  result.randomSeed = 4242
  result.symmetry = symRotational
  result.symmetries = @[symRotational]
  for i in 0 ..< width * height:
    result.passability.add(1.0)

proc bare(): World = newWorld(flat(15, 15), 1500)

# --- the scan order is x ascending outer, y ascending inner -----------------
block:
  var w = bare()
  var seen: seq[Loc]
  for l in w.locationsWithinRadiusSquared(loc(5, 5), 2):
    seen.add(l)
  checkEq("the r^2 <= 2 neighbourhood has 9 tiles", seen.len, 9)
  checkEq("and starts at the lowest x then the lowest y", seen[0], loc(4, 4))
  checkEq("second is (4,5)", seen[1], loc(4, 5))
  checkEq("third is (4,6)", seen[2], loc(4, 6))
  checkEq("fourth is (5,4)", seen[3], loc(5, 4))
  checkEq("last is (6,6)", seen[8], loc(6, 6))

block:
  ## The order fixes the order conversions are QUEUED and therefore the ids
  ## they are re-spawned with: the lower-x victim gets the earlier id.
  var w = bare()
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 300)
  let west = w.spawnRobot(-1, rtPolitician, loc(4, 5), teamB, 20)
  let east = w.spawnRobot(-1, rtPolitician, loc(6, 5), teamB, 20)
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  checkEq("both were converted", w.robotCount[ord(teamA)], 2)
  ## Ids come out of a SHUFFLED `IDGenerator`, so the west victim's new id is
  ## not numerically lower — it is the one the generator produced FIRST, which
  ## is what the exec order records.
  checkEq("two robots are in the exec order", w.execOrder.len, 2)
  checkEq("the west victim was re-spawned FIRST",
    w.robotsById[w.execOrder[0]].loc, loc(4, 5))
  checkEq("and the east victim second",
    w.robotsById[w.execOrder[1]].loc, loc(6, 5))
  check("and both ids are new",
    w.execOrder[0] != west and w.execOrder[1] != east)

# --- nobody in range, and conviction <= 10 ----------------------------------
block:
  var w = bare()
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 300)
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 9)
  check("with numBots == 0 nobody is affected", w.robotsById.len == 0)
  check("and the politician STILL DIES", a notin w.robotsById)

block:
  var w = bare()
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 10)
  let v = w.spawnRobot(-1, rtPolitician, loc(5, 6), teamB, 50)
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  checkEq("conviction 10 gives nothing away", w.robotsById[v].conviction, 50)
  check("and the politician still dies", a notin w.robotsById)

# --- the divisor includes allies and neutrals -------------------------------
block:
  var w = bare()
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 110)
  discard w.spawnRobot(-1, rtMuckraker, loc(4, 5), teamA, 100)  # ally
  let enemy = w.spawnRobot(-1, rtPolitician, loc(6, 5), teamB, 100)
  discard w.spawnRobot(-1, rtEnlightenmentCenter, loc(5, 4), teamNeutral, 300)
  ## r^2 = 2 collects 4 robots (self + 3), so numBots = 3 and the split is
  ## (110 - 10) / 3 = 33.333..., truncated to 33 per target.
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  checkEq("the enemy politician lost exactly the truncated split",
    w.robotsById[enemy].conviction, 67)

# --- a friendly Enlightenment Center is fed UNBUFFED -------------------------
block:
  var w = bare()
  let ec = w.spawnRobot(-1, rtEnlightenmentCenter, loc(5, 4), teamA, 100)
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 60)
  w.stats.numBuffs[ord(teamA)] = 1000       # buff = 2.0
  w.robotsById[a].cooldownTurns = 0.0
  checkEq("the buff really is 2x", w.getBuff(teamA), 2.0)
  w.doEmpower(w.robotsById[a], 2)
  checkEq("a friendly Center takes the split UNBUFFED",
    w.robotsById[ec].influence, 150)
  checkEq("and its conviction follows its influence",
    w.robotsById[ec].conviction, 150)

# --- a friendly unit heals, capped, with the excess lost ---------------------
block:
  var w = bare()
  let friend = w.spawnRobot(-1, rtPolitician, loc(5, 4), teamA, 100)
  w.robotsById[friend].conviction = 20
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 300)
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  checkEq("healing stops at the cap, and the excess is lost",
    w.robotsById[friend].conviction, 100)

# --- the enemy Center formula ------------------------------------------------
block:
  ## buff = 1.5, the Center has 60 conviction, the split is 100.
  ## convNeeded = 60 / 1.5 = 40; 100 > 40, so
  ## conv = 60 + (100 - 40) = 120 — the buff applies only up to conversion and
  ## the overflow crosses UNBUFFED.
  var w = bare()
  let ec = w.spawnRobot(-1, rtEnlightenmentCenter, loc(5, 4), teamB, 60)
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 110)
  w.stats.numBuffs[ord(teamA)] = 500        # buff = 1.5
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  var newEc: Robot
  for _, r in w.robotsById:
    if r.kind == rtEnlightenmentCenter: newEc = r
  check("the Center changed hands", newEc != nil and newEc.team == teamA)
  checkEq("a converted Center keeps |influence| as its influence",
    newEc.influence, 60)
  checkEq("and its conviction is snapped equal to it", newEc.conviction, 60)

block:
  ## Under the conversion point the whole split IS buffed.
  var w = bare()
  let ec = w.spawnRobot(-1, rtEnlightenmentCenter, loc(5, 4), teamB, 1000)
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 110)
  w.stats.numBuffs[ord(teamA)] = 500        # buff = 1.5
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  checkEq("100 * 1.5 came off the enemy Center",
    w.robotsById[ec].influence, 850)

# --- slanderers and muckrakers are destroyed, never converted ---------------
block:
  var w = bare()
  let s = w.spawnRobot(-1, rtSlanderer, loc(5, 4), teamB, 30)
  let m = w.spawnRobot(-1, rtMuckraker, loc(5, 6), teamB, 30)
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 300)
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  check("the slanderer is gone", s notin w.robotsById)
  check("the muckraker is gone", m notin w.robotsById)
  checkEq("and nothing came back for team A", w.robotCount[ord(teamA)], 0)

# --- a conversion keeps the OLD PARENT pointer ------------------------------
block:
  var w = bare()
  let parent = w.spawnRobot(-1, rtEnlightenmentCenter, loc(1, 1), teamB, 500)
  let victim = w.spawnRobotWithId(w.idGen.nextId(), parent, rtPolitician,
                                  loc(5, 4), teamB, 40)
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 300)
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  var converted: Robot
  for _, r in w.robotsById:
    if r.team == teamA and r.kind == rtPolitician: converted = r
  check("the politician converted", converted != nil)
  checkEq("and kept the destroyed robot's parent pointer",
    converted.parentId, parent)
  check("the victim's id is gone", victim notin w.robotsById)

# --- (int) truncation toward zero on a fractional split ---------------------
block:
  var w = bare()
  ## conviction 24, tax 10, numBots 3 -> 14/3 = 4.666..., truncated to 4.
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 24)
  let e1 = w.spawnRobot(-1, rtPolitician, loc(4, 5), teamB, 50)
  let e2 = w.spawnRobot(-1, rtPolitician, loc(6, 5), teamB, 50)
  let e3 = w.spawnRobot(-1, rtPolitician, loc(5, 6), teamB, 50)
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  for e in [e1, e2, e3]:
    checkEq("each enemy lost the TRUNCATED 4, not 5",
      w.robotsById[e].conviction, 46)

# --- a converted politician's conviction is -oldConviction, capped ----------
block:
  var w = bare()
  let victim = w.spawnRobot(-1, rtPolitician, loc(5, 4), teamB, 40)
  let a = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 110)
  ## split = 100, victim conviction 40 -> -60 -> converted at
  ## influence 40, conviction min(60, cap 40) = 40.
  w.robotsById[a].cooldownTurns = 0.0
  w.doEmpower(w.robotsById[a], 2)
  var conv: Robot
  for _, r in w.robotsById:
    if r.team == teamA: conv = r
  check("it converted", conv != nil)
  checkEq("influence is |old influence|", conv.influence, 40)
  checkEq("conviction is -oldConviction CAPPED by the new cap",
    conv.conviction, 40)

finish("bc21 empower")
