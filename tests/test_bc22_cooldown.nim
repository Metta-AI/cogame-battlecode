## The two cooldown counters, the FIVE-MINES-A-TURN miner, and the FLOAT64
## truncating rubble multiplier.
##
## §Tests item 1. Three things in here are the year, not details:
##
## * **both cooldowns start a robot's life at ZERO** (`InternalRobot`'s
##   constructor sets them to 0, not to `COOLDOWN_LIMIT`), so a droid built on
##   round *r* takes its first turn on round *r+1* and can act AND move on it.
##   This is the OPPOSITE of bc23 and it is why bc22 armies grow so fast;
## * **a MINER's action cooldown of 2 against a limit of 10 means five mines in
##   one turn on rubble-free ground** — 2+2+2+2+2 = 10 and `canActCooldown` is
##   `< 10`, so only the sixth is refused — and exactly ONE on rubble 60;
## * **the multiplier is `(int)((1 + r/10.0) * base)` in FLOAT64**, which is NOT
##   the integer form: the 22 measured disagreements are named below.

import std/[json, os, strutils]
import harness
import bc22_fixture

# --- the counters -----------------------------------------------------------
block:
  var w = bare()
  let r = w.place(teamA, rtSoldier, loc(10, 10))
  checkEq("a fresh robot's action cooldown is 0", r.actionCooldown, 0)
  checkEq("and its movement cooldown is 0", r.movementCooldown, 0)
  check("so it can act at once", r.canActCooldown())
  check("and move at once", r.canMoveCooldown())
  r.actionCooldown = 25
  r.movementCooldown = 4
  r.actionCooldown = max(0, r.actionCooldown - CooldownsPerTurn)
  r.movementCooldown = max(0, r.movementCooldown - CooldownsPerTurn)
  checkEq("a counter decays by exactly 10", r.actionCooldown, 15)
  checkEq("and floors at 0", r.movementCooldown, 0)
  r.actionCooldown = 10
  check("an action needs the counter UNDER ten", not r.canActCooldown())
  r.actionCooldown = 9
  check("nine is ready", r.canActCooldown())

block:
  ## The MODE gate is the other half of both predicates.
  var w = bare()
  let lab = w.place(teamA, rtLaboratory, loc(10, 10))
  checkEq("a fresh building is a PROTOTYPE", lab.mode, rmPrototype)
  check("a prototype cannot act", not lab.canActCooldown())
  check("and cannot move", not lab.canMoveCooldown())
  lab.mode = rmTurret
  check("a turret can act", lab.canActCooldown())
  check("and cannot move", not lab.canMoveCooldown())
  lab.mode = rmPortable
  check("a portable cannot act", not lab.canActCooldown())
  check("and can move", lab.canMoveCooldown())

# --- five mines a turn ------------------------------------------------------
block:
  var w = bare(lead = @[(l: loc(10, 10), amount: 50)])
  let m = w.place(teamA, rtMiner, loc(10, 10))
  var mined = 0
  while w.canMineLead(m, loc(10, 10)):
    w.doMineLead(m, loc(10, 10))
    inc mined
  checkEq("a miner mines FIVE times in one turn on rubble 0", mined, 5)
  checkEq("and the sixth is refused", w.canMineLead(m, loc(10, 10)), false)
  checkEq("its action cooldown is exactly 10", m.actionCooldown, 10)

block:
  var w = bare(rubble = @[(l: loc(10, 10), amount: 60)],
               lead = @[(l: loc(10, 10), amount: 50)])
  let m = w.place(teamA, rtMiner, loc(10, 10))
  var mined = 0
  while w.canMineLead(m, loc(10, 10)):
    w.doMineLead(m, loc(10, 10))
    inc mined
  checkEq("and exactly ONCE on rubble 60", mined, 1)
  checkEq("paying (int)((1+6.0)*2) = 14", m.actionCooldown, 14)

# --- the float64 multiplier and the 22 measured disagreements ---------------
block:
  checkEq("base 25, rubble 36 is 114 and not 115",
    cooldownWithMultiplier(25, 36), 114)
  checkEq("base 100, rubble 13 is 229 and not 230",
    cooldownWithMultiplier(100, 13), 229)
  checkEq("base 200, rubble 92 is 2039 and not 2040",
    cooldownWithMultiplier(200, 92), 2039)
  checkEq("rubble 0 is the base", cooldownWithMultiplier(16, 0), 16)
  checkEq("rubble 100 is eleven times it",
    cooldownWithMultiplier(16, 100), 176)

block:
  ## The WHOLE lattice against `data/bc22/tables.json`, which the JVM itself
  ## generated — and the count of disagreements with the integer form, which
  ## is what makes the float64 expression mandatory rather than tidy.
  let path = dataRoot() / "bc22" / "tables.json"
  check("data/bc22/tables.json ships", fileExists(path))
  if fileExists(path):
    let doc = parseJson(readFile(path))
    var pairs = 0
    var differ = 0
    for baseKey, row in doc["rubble_cooldown"]:
      let base = parseInt(baseKey)
      for r in 0 .. 100:
        inc pairs
        if cooldownWithMultiplier(base, r) != row[r].getInt():
          check("the port matches the JVM at base " & baseKey & " rubble " & $r,
                false)
        if cooldownWithMultiplier(base, r) != ((10 + r) * base) div 10:
          inc differ
    checkEq("the lattice is 808 pairs", pairs, 808)
    checkEq("and 22 of them differ from the integer form", differ, 22)
    checkEq("which is what the generated file flags",
      doc["rubble_cooldown_float_differs"].len, 22)

# --- WHERE the multiplier is read -------------------------------------------
block:
  ## A MOVE charges at the DESTINATION, after the move. The engine's own
  ## comment says so ("this has to happen after robot's location changed
  ## because rubble").
  var w = bare(rubble = @[(l: loc(11, 10), amount: 50)])
  let s = w.place(teamA, rtSoldier, loc(10, 10))
  w.doMove(s, dEast)
  checkEq("a move charges at the DESTINATION's rubble",
    s.movementCooldown, cooldownWithMultiplier(16, 50))
  check("and not at the origin's",
    s.movementCooldown != cooldownWithMultiplier(16, 0))

block:
  ## Every other action charges at the ACTOR's own unchanged square.
  var w = bare(rubble = @[(l: loc(10, 10), amount: 30)],
               lead = @[(l: loc(11, 10), amount: 5)])
  let m = w.place(teamA, rtMiner, loc(10, 10))
  w.doMineLead(m, loc(11, 10))
  checkEq("mining charges at the MINER's square",
    m.actionCooldown, cooldownWithMultiplier(2, 30))

block:
  ## A MUTATION charges the BUILDER at the builder's square and the BUILDING's
  ## 100+100 at the building's square.
  var w = bare(rubble = @[(l: loc(10, 10), amount: 20),
                          (l: loc(11, 10), amount: 40)])
  let b = w.place(teamA, rtBuilder, loc(10, 10))
  let tower = w.placeLive(teamA, rtWatchtower, loc(11, 10))
  w.addLead(teamA, 400)
  check("the mutation is legal", w.canMutate(b, loc(11, 10)))
  w.doMutate(b, loc(11, 10))
  checkEq("the builder pays at ITS square",
    b.actionCooldown, cooldownWithMultiplier(10, 20))
  checkEq("the building pays 100 on its ACTION counter at ITS square",
    tower.actionCooldown, cooldownWithMultiplier(100, 40))
  checkEq("and 100 on its MOVEMENT counter too",
    tower.movementCooldown, cooldownWithMultiplier(100, 40))
  checkEq("and it is level 2", tower.level, 2)

finish("test_bc22_cooldown")
