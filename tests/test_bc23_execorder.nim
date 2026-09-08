## bc23's exec order: APPEND ON SPAWN, BY-VALUE REMOVAL ON DEATH preserving
## the order of the survivors, the PRE-SWEEP SNAPSHOT so a robot built this
## round takes no turn this round, the `existsRobot` skip for a robot
## destroyed mid-sweep, and the initial headquarters in ASCENDING ID because
## `LiveMap` sorts them. 500 random build/destroy sequences against a
## reference list.

import std/random
import harness
import bc23_fixture

# --- the initial headquarters are in ASCENDING ID order --------------------
block:
  ## The fixture lists its two bodies id-DESCENDING, exactly as a real map
  ## file does, so this catches a port that trusted file order.
  var w = bare()
  checkEq("two headquarters", w.execOrder.len, 2)
  checkEq("the lower id goes first", w.execOrder[0], 2)
  checkEq("and the higher second", w.execOrder[1], 3)

block:
  var w = bare(hqs = @[(id: 9, x: 26, y: 15, team: 2),
                       (id: 4, x: 26, y: 20, team: 2),
                       (id: 7, x: 3, y: 15, team: 1),
                       (id: 2, x: 3, y: 20, team: 1)])
  checkEq("four headquarters, ascending id", w.execOrder, @[2, 4, 7, 9])

# --- append on spawn, by-value removal on death ---------------------------
block:
  var w = bare()
  let a = w.place(teamA, rtCarrier, loc(10, 10))
  let b = w.place(teamA, rtCarrier, loc(11, 10))
  let c = w.place(teamA, rtCarrier, loc(12, 10))
  checkEq("spawns APPEND", w.execOrder, @[2, 3, a.id, b.id, c.id])
  w.destroyRobot(b.id)
  checkEq("removal is BY VALUE and compacts the list",
    w.execOrder, @[2, 3, a.id, c.id])
  let d = w.place(teamA, rtCarrier, loc(13, 10))
  checkEq("and the next spawn appends at the end",
    w.execOrder, @[2, 3, a.id, c.id, d.id])

# --- the pre-sweep snapshot ------------------------------------------------
block:
  ## A robot built during the sweep does NOT take a turn in the same round:
  ## the array iterated is `dynamicBodyExecOrder.toArray()`, taken before the
  ## sweep starts. A carrier that took a turn would have `roundsAlive = 1`.
  var w = bare()
  var sides = newSides23(defaultSheets(), 0)
  runRound(w, sides, [ckLemonade, ckLemonade])
  var built = 0
  var tookATurn = 0
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.kind == rtHeadquarters: continue
    built += 1
    if r.roundsAlive > 0: tookATurn += 1
  check("round 1 built robots", built > 0)
  checkEq("and NONE of them took a turn in the round they were built in",
    tookATurn, 0)
  runRound(w, sides, [ckLemonade, ckLemonade])
  var moved = 0
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.kind == rtHeadquarters: continue
    if r.roundsAlive > 0: moved += 1
  check("they take their turns the round after", moved > 0)

# --- the existsRobot skip -------------------------------------------------
block:
  ## A robot destroyed mid-sweep is skipped rather than run: the loop's
  ## `existsRobot` guard is what makes an exec-order snapshot safe.
  var w = bare()
  let victim = w.place(teamA, rtCarrier, loc(10, 10))
  let snapshot = w.execOrder
  var ran = 0
  for id in snapshot:
    if not w.existsRobot(id): continue
    ran += 1
    if id == 2: w.destroyRobot(victim.id)
  checkEq("the destroyed robot never ran", ran, snapshot.len - 1)

# --- 500 random build/destroy sequences against a reference list ----------
block:
  var rng = initRand(1234567)
  var mismatches = 0
  for trial in 0 ..< 500:
    var w = bare()
    var reference = @[2, 3]
    var live = @[2, 3]
    for step in 0 ..< 30:
      if live.len > 2 and rng.rand(0 .. 2) == 0:
        let pick = live[2 + rng.rand(0 .. live.len - 3)]
        w.destroyRobot(pick)
        ## The reference removes the FIRST entry equal to the id.
        for k in 0 ..< reference.len:
          if reference[k] == pick:
            reference.delete(k)
            break
        for k in 0 ..< live.len:
          if live[k] == pick:
            live.delete(k)
            break
      else:
        let at = loc(6 + rng.rand(0 .. 18), 6 + rng.rand(0 .. 18))
        if w.isLocationOccupied(at): continue
        let r = w.place(teamA, rtCarrier, at)
        reference.add(r.id)
        live.add(r.id)
    if w.execOrder != reference: mismatches += 1
  checkEq("500 random build/destroy sequences reproduce the engine's list",
    mismatches, 0)

finish("test_bc23_execorder")
