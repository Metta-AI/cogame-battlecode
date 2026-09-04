## Expose and the buff ledger: the preconditions, the camouflaged slanderer
## that can no longer be exposed, the buff's value (the slanderer's INFLUENCE),
## its one-round delay, its expiry at `emit + 51`, independent accumulation,
## and the 2021.3.0.0 LINEAR form `1 + 0.001*n` rather than `1.001^n`.

import harness
import battlecode/years/bc21/[constants, world, empower, votes]

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

# --- preconditions ----------------------------------------------------------
block:
  var w = bare()
  let mId = w.spawnRobot(-1, rtMuckraker, loc(5, 5), teamA, 1)
  let m = w.robotsById[mId]
  m.cooldownTurns = 0.0
  discard w.spawnRobot(-1, rtSlanderer, loc(5, 6), teamB, 40)
  check("an adjacent enemy slanderer is exposable", w.canExpose(m, loc(5, 6)))
  m.cooldownTurns = 1.0
  check("but not while cooling down", not w.canExpose(m, loc(5, 6)))
  m.cooldownTurns = 0.0
  check("an empty tile is not", not w.canExpose(m, loc(5, 7)))
  discard w.spawnRobot(-1, rtSlanderer, loc(4, 5), teamA, 40)
  check("a FRIENDLY slanderer is not", not w.canExpose(m, loc(4, 5)))
  discard w.spawnRobot(-1, rtPolitician, loc(6, 5), teamB, 40)
  check("an enemy politician is not", not w.canExpose(m, loc(6, 5)))
  ## r^2 <= 12: (3,2) is 9 + 4 = 13 away.
  discard w.spawnRobot(-1, rtSlanderer, loc(8, 7), teamB, 40)
  check("r^2 = 13 is out of range", not w.canExpose(m, loc(8, 7)))
  discard w.spawnRobot(-1, rtSlanderer, loc(8, 6), teamB, 40)
  check("r^2 = 10 is in range", w.canExpose(m, loc(8, 6)))

block:
  var w = bare()
  let mId = w.spawnRobot(-1, rtMuckraker, loc(5, 5), teamA, 1)
  let m = w.robotsById[mId]
  m.cooldownTurns = 0.0
  let sId = w.spawnRobot(-1, rtSlanderer, loc(5, 6), teamB, 40)
  ## Camouflage: at `roundsAlive == 300` the slanderer IS a politician.
  w.robotsById[sId].kind = rtPolitician
  check("a camouflaged slanderer can no longer be exposed",
    not w.canExpose(m, loc(5, 6)))

# --- the buff is the slanderer's INFLUENCE, one round later -----------------
block:
  var w = bare()
  w.currentRound = 100
  let mId = w.spawnRobot(-1, rtMuckraker, loc(5, 5), teamA, 1)
  let m = w.robotsById[mId]
  m.cooldownTurns = 0.0
  let sId = w.spawnRobot(-1, rtSlanderer, loc(5, 6), teamB, 137)
  w.expose(m, loc(5, 6))
  check("the slanderer died", sId notin w.robotsById)
  checkEq("the buff is PENDING, not yet applied", w.stats.numBuffs[0], 0)
  checkEq("and it is the slanderer's influence", w.stats.buffsToAdd[0], 137)
  checkEq("so the buff this round is still 1.0", w.getBuff(teamA), 1.0)
  w.applyExposeBuffs()
  checkEq("after the end-of-round step it is in force", w.stats.numBuffs[0], 137)
  checkEq("1 + 0.001 * 137 EXACTLY — the LINEAR 2021.3.0.0 form, not 1.001^137",
    w.getBuff(teamA), 1.0 + 0.001 * 137.0)
  check("and 1.001^137 would have been visibly different",
    abs(w.getBuff(teamA) - 1.146837) > 0.008)

# --- expiry at emit + 51 -----------------------------------------------------
block:
  var w = bare()
  w.currentRound = 100
  w.stats.buffsToAdd[0] = 10
  w.applyExposeBuffs()
  checkEq("in force from round 101", w.stats.numBuffs[0], 10)
  for r in 101 .. 150:
    w.currentRound = r
    w.updateNumBuffs()
  checkEq("still in force at round 150", w.stats.numBuffs[0], 10)
  w.currentRound = 151
  w.updateNumBuffs()
  checkEq("and dropped at the start of round 100 + 51", w.stats.numBuffs[0], 0)

block:
  ## Overlapping buffs accumulate and expire INDEPENDENTLY.
  var w = bare()
  w.currentRound = 100
  w.stats.buffsToAdd[0] = 10
  w.applyExposeBuffs()
  w.currentRound = 120
  w.updateNumBuffs()
  w.stats.buffsToAdd[0] = 7
  w.applyExposeBuffs()
  checkEq("both batches are counted", w.stats.numBuffs[0], 17)
  w.currentRound = 151
  w.updateNumBuffs()
  checkEq("the first expires alone", w.stats.numBuffs[0], 7)
  w.currentRound = 171
  w.updateNumBuffs()
  checkEq("and the second twenty rounds later", w.stats.numBuffs[0], 0)

# --- the buff never touches the OTHER team ----------------------------------
block:
  var w = bare()
  w.currentRound = 5
  w.stats.buffsToAdd[0] = 50
  w.applyExposeBuffs()
  checkEq("team A is buffed", w.getBuff(teamA), 1.05)
  checkEq("team B is not", w.getBuff(teamB), 1.0)
  checkEq("and neutral never is", w.getBuff(teamNeutral), 1.0)

finish("bc21 expose")
