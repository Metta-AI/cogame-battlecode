## bc21 cooldowns: `actionCooldown / passability` charged at the tile being
## LEFT, the beginning-of-turn decay, `isReady` strictly below 1, the per-type
## initial cooldowns, conversion arriving at 0, and the frozen robot a
## passability-0.0 tile produces.

import std/math
import harness
import battlecode/years/bc21/[constants, world, empower]

proc flat(width, height: int, passability = 1.0): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.origin = [0, 0]
  result.randomSeed = 4242
  result.symmetry = symRotational
  result.symmetries = @[symRotational]
  for i in 0 ..< width * height:
    result.passability.add(passability)

proc bare(passability = 1.0): World = newWorld(flat(15, 15, passability), 1500)

# --- the divisor is the tile being LEFT -------------------------------------
block:
  var w = bare()
  w.passability[w.idx(loc(5, 5))] = 0.5
  w.passability[w.idx(loc(6, 5))] = 1.0
  let id = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 30)
  let r = w.robotsById[id]
  r.cooldownTurns = 0.0
  w.move(r, dEast)
  checkEq("a move is charged at the tile it LEAVES", r.cooldownTurns, 2.0)
  checkEq("and the robot did move", r.loc, loc(6, 5))

block:
  var w = bare()
  let id = w.spawnRobot(-1, rtMuckraker, loc(5, 5), teamA, 10)
  let r = w.robotsById[id]
  r.cooldownTurns = 0.0
  w.passability[w.idx(loc(5, 5))] = 0.25
  w.addCooldownTurns(r)
  checkEq("muckraker 1.5 / 0.25", r.cooldownTurns, 6.0)

# --- decay and readiness ----------------------------------------------------
block:
  var w = bare()
  let id = w.spawnRobot(-1, rtPolitician, loc(3, 3), teamA, 30)
  let r = w.robotsById[id]
  r.cooldownTurns = 2.5
  processBeginningOfTurn(r)
  checkEq("the decay is exactly 1", r.cooldownTurns, 1.5)
  check("1.5 is not ready", not isReady(r))
  processBeginningOfTurn(r)
  checkEq("and again", r.cooldownTurns, 0.5)
  check("0.5 IS ready — `isReady` is cooldown < 1, strictly", isReady(r))
  processBeginningOfTurn(r)
  checkEq("the decay floors at 0", r.cooldownTurns, 0.0)
  processBeginningOfTurn(r)
  checkEq("and stays there", r.cooldownTurns, 0.0)
  r.cooldownTurns = 1.0
  check("exactly 1.0 is NOT ready", not isReady(r))

# --- initial cooldowns by type ----------------------------------------------
block:
  var w = bare()
  let ec = w.spawnRobot(-1, rtEnlightenmentCenter, loc(7, 7), teamA, 1000)
  let center = w.robotsById[ec]
  checkEq("a map-placed Center starts ready", center.cooldownTurns, 0.0)
  for (kind, want) in [(rtPolitician, 10.0), (rtSlanderer, 0.0),
                       (rtMuckraker, 10.0)]:
    center.cooldownTurns = 0.0
    let dir = (case kind
               of rtPolitician: dNorth
               of rtSlanderer: dEast
               else: dSouth)
    let id = w.buildRobot(center, kind, dir, 20)
    check("built " & $kind, id >= 0)
    checkEq("initial cooldown for " & $kind, w.robotsById[id].cooldownTurns,
      want)
  checkEq("the Center itself is charged 2.0 / 1.0", center.cooldownTurns, 2.0)

# --- a CONVERTED robot arrives at cooldown 0 --------------------------------
block:
  var w = bare()
  let attacker = w.spawnRobot(-1, rtPolitician, loc(5, 5), teamA, 200)
  let victimId = w.spawnRobot(-1, rtPolitician, loc(5, 6), teamB, 20)
  let a = w.robotsById[attacker]
  a.cooldownTurns = 0.0
  w.doEmpower(a, 2)
  check("the victim was converted", w.robotCount[ord(teamA)] == 1)
  var converted: Robot
  for _, r in w.robotsById:
    if r.team == teamA: converted = r
  check("a converted robot exists", converted != nil)
  checkEq("and it arrives with cooldown 0, not initialCooldown",
    converted.cooldownTurns, 0.0)
  check("with a NEW id", converted.id != victimId)

# --- passability 0.0 freezes a robot for ever -------------------------------
block:
  ## `Misdirection` really has two such tiles; the port reproduces the engine
  ## rather than defending against it, and the map is excluded from the pool
  ## for exactly this reason (docs/RULES-BC21.md).
  var w = bare()
  w.passability[w.idx(loc(4, 4))] = 0.0
  let id = w.spawnRobot(-1, rtPolitician, loc(4, 4), teamA, 30)
  let r = w.robotsById[id]
  r.cooldownTurns = 0.0
  w.addCooldownTurns(r)
  check("a 0.0-passability tile gives an INFINITE cooldown",
    r.cooldownTurns == Inf)
  for _ in 0 .. 2000:
    processBeginningOfTurn(r)
  check("and a thousand decays never bring it back", not isReady(r))
  check("the robot is frozen where it stands", r.cooldownTurns == Inf)

finish("bc21 cooldown")
