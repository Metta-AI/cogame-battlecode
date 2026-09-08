## bc25's DYNAMIC exec order: append on build, BY-VALUE removal on destroy
## preserving the order of the survivors, the pre-sweep snapshot so a unit
## built this round takes no turn this round, and the `existsRobot` skip for a
## unit destroyed mid-sweep.
##
## 500 random build/destroy sequences are replayed against a reference list
## built with exactly the operations `TIntArrayList` performs — `add(id)` and
## `remove(value)`, which removes the FIRST occurrence and compacts.

import std/random
import harness
import bc25_fixture

block:
  ## `LiveMap` SORTS `initialBodies` by ascending id before the world sees
  ## them, and every real map file lists them id-DESCENDING — so file order
  ## and exec order are exactly reversed (docs/RULES-BC25.md Divergences 15).
  var w = bare()
  checkEq("the four starting towers are in ASCENDING id order",
    w.execOrder, @[1, 2, 3, 4])
  checkEq("which is the reverse of the file's own order",
    w.map.initialBodies[0].id, 4)

block:
  var w = bare()
  let a = w.spawnRobot(utSoldier, loc(10, 10), teamA)
  let b = w.spawnRobot(utSoldier, loc(11, 10), teamA)
  let c = w.spawnRobot(utSoldier, loc(12, 10), teamA)
  checkEq("a built unit is APPENDED", w.execOrder,
    @[1, 2, 3, 4, a.id, b.id, c.id])
  w.destroyRobot(b.id)
  checkEq("a destroyed unit is removed BY VALUE and the survivors keep " &
    "their order", w.execOrder, @[1, 2, 3, 4, a.id, c.id])
  w.destroyRobot(1)
  checkEq("including one from the front", w.execOrder, @[2, 3, 4, a.id, c.id])

block:
  ## 500 random build/destroy sequences against a reference list.
  var rng = initRand(20250907)
  var w = bare()
  var reference = @[1, 2, 3, 4]
  var free: seq[Loc]
  for y in 5 ..< 25:
    for x in 5 ..< 25: free.add(loc(x, y))
  var cursor = 0
  var mismatches = 0
  for step in 1 .. 500:
    if reference.len > 4 and rng.rand(1.0) < 0.4:
      let pick = reference[rng.rand(reference.len - 1)]
      w.destroyRobot(pick)
      let at = reference.find(pick)
      reference.delete(at)
    else:
      if cursor >= free.len: cursor = 0
      var spot = free[cursor]
      cursor += 1
      if w.getRobot(spot) != nil or not w.isPassable(spot): continue
      let r = w.spawnRobot(utSoldier, spot, teamA)
      reference.add(r.id)
    if w.execOrder != reference: mismatches += 1
  checkEq("500 random build/destroy sequences reproduce the list exactly",
    mismatches, 0)
  check("and the sequence really exercised both operations",
    reference.len > 4)

block:
  ## The sweep iterates a SNAPSHOT: a unit built this round takes no turn this
  ## round. A tower built by `runRound` on round 1 has `roundsAlive == 0`
  ## after round 1 and 1 after round 2.
  var w = bare()
  var sides = newSides25(defaultSheets(), 0)
  runRound(w, sides, [ckSpaark, ckSpaark])
  var built: seq[int]
  for id in w.execOrder:
    if id > 4: built.add(id)
  check("the first round built something", built.len > 0)
  for id in built:
    checkEq("a unit built this round has taken no turn",
      w.robotsById[id].roundsAlive, 0)
  runRound(w, sides, [ckSpaark, ckSpaark])
  var tookATurn = 0
  for id in built:
    if w.existsRobot(id) and w.robotsById[id].roundsAlive >= 1:
      tookATurn += 1
  check("and takes one on the NEXT round", tookATurn > 0)

block:
  ## A unit destroyed mid-sweep is skipped by the `existsRobot` guard rather
  ## than crashing the sweep.
  var w = bare()
  let victim = w.spawnRobot(utSoldier, loc(10, 10), teamA)
  let id = victim.id
  let snapshot = w.execOrder
  w.destroyRobot(id)
  var visited = 0
  for entry in snapshot:
    if not w.existsRobot(entry): continue
    visited += 1
  checkEq("the snapshot still names it", snapshot.len, 5)
  checkEq("but the guard skips it", visited, 4)

finish("test_bc25_execorder")
