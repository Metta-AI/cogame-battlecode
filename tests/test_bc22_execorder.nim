## The exec order: append on build, BY-VALUE removal on death, the pre-sweep
## snapshot, and the ASCENDING-ID initial archons.
##
## §Tests item 6. `dynamicBodyExecOrder` is a plain `TIntArrayList` and
## `remove(id)` removes the FIRST ENTRY EQUAL TO `id`, compacting the list and
## preserving the order of the survivors. Reproducing that literally is a
## correctness requirement, not a detail.

import std/random
import harness
import bc22_fixture

block:
  ## The map file's bodies are listed id-DESCENDING; `LiveMap`'s constructor
  ## sorts them ASCENDING, and that order IS the initial exec order. The
  ## official maps carry ids BELOW the 10 000 IDGenerator floor, so A and B
  ## alternate in the opening order.
  var w = bare(archons = @[(id: 9, x: 3, y: 3, team: 2),
                           (id: 2, x: 5, y: 5, team: 1),
                           (id: 7, x: 4, y: 4, team: 2),
                           (id: 3, x: 6, y: 6, team: 1)])
  checkEq("the initial exec order is ascending by id", w.execOrder,
    @[2, 3, 7, 9])
  var teams: seq[int]
  for id in w.execOrder: teams.add(ord(w.robotsById[id].team))
  checkEq("so A and B alternate as the map file makes them", teams,
    @[0, 0, 1, 1])

block:
  let spec = loadMap("maze")
  var ids: seq[int]
  for b in spec.initialBodies: ids.add(b.id)
  checkEq("the real `maze` ids are the measured 2, 3, 6, 7, 8, 9", ids,
    @[2, 3, 6, 7, 8, 9])
  var w = newWorld(spec, 2000)
  checkEq("and the exec order is exactly them", w.execOrder, ids)
  var teams: seq[int]
  for id in w.execOrder: teams.add(ord(w.robotsById[id].team))
  checkEq("A and B alternate", teams, @[0, 1, 0, 1, 0, 1])

block:
  ## Append on build.
  var w = bare()
  let arch = w.execOrder[0]
  let r = w.spawnRobot(w.idGen.nextId(), rtSoldier, loc(10, 10), teamA)
  checkEq("a new robot is APPENDED", w.execOrder[^1], r.id)
  checkEq("and the head is unchanged", w.execOrder[0], arch)

block:
  ## By-value removal, preserving the order of the survivors.
  var w = bare()
  var made: seq[int]
  for i in 0 ..< 6:
    made.add(w.spawnRobot(w.idGen.nextId(), rtSoldier,
                          loc(5 + i, 5), teamA).id)
  let before = w.execOrder
  w.destroyRobot(made[2])
  var want: seq[int]
  for id in before:
    if id != made[2]: want.add(id)
  checkEq("the dead id is removed and everything after shifts forward",
    w.execOrder, want)

block:
  ## The sweep iterates a SNAPSHOT taken before it starts, so a robot built
  ## this round does NOT take a turn this round, and a robot destroyed
  ## mid-sweep is skipped by the `existsRobot` guard.
  var w = bare()
  var sides = newSides22(defaultSheets(), 0)
  let chassis = [ckWololo, ckWololo]
  let before = w.execOrder.len
  runRound(w, sides, chassis)
  var newborns = 0
  for id in w.execOrder:
    if w.robotsById[id].roundsAlive == 0: inc newborns
  check("robots built this round have taken no turn", newborns > 0 or
    w.execOrder.len == before)
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.roundsAlive == 0:
      checkEq("a newborn's cooldowns are untouched by a turn it never took",
        r.actionCooldown + r.movementCooldown, 0)

block:
  ## 500 random build/destroy sequences against a straightforward reference
  ## implementation of the same list operations.
  var w = bare()
  var reference: seq[int] = w.execOrder
  var rnd = initRand(20220)
  var mismatches = 0
  for step in 0 ..< 500:
    if reference.len <= 1 or rnd.rand(100) < 60:
      var x = rnd.rand(TestWidth - 1)
      var y = rnd.rand(TestHeight - 1)
      if w.isLocationOccupied(loc(x, y)): continue
      let r = w.spawnRobot(w.idGen.nextId(), rtSoldier, loc(x, y), teamA)
      reference.add(r.id)
    else:
      let k = rnd.rand(reference.len - 1)
      let victim = reference[k]
      w.destroyRobot(victim)
      reference.delete(k)
    if w.execOrder != reference: inc mismatches
  checkEq("500 random spawn/destroy sequences agree with the list model",
    mismatches, 0)

finish("test_bc22_execorder")
