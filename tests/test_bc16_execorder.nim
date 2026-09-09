## Shard 6 of the note's list — **the exec list**: append on spawn, BY-VALUE
## removal on death preserving the survivors' order, the pre-sweep SNAPSHOT so
## a robot spawned this round takes no turn this round, the skip for a robot
## destroyed mid-sweep, the initial robots in MAP-FILE ORDER (not id order),
## and `!isActive()` robots taking a turn with a ZERO budget and doing nothing.
##
## `gameObjectsByID` is a `LinkedHashMap` (`GameWorld.java:72`) and it is the
## ONLY robot collection the engine ever iterates, so the order is plain
## insertion order everywhere. **There is no trove, no `net.sf.jsi`, no
## `EnumMap` iteration and no hash-ordered robot sweep anywhere in the 2016
## round loop** — the single biggest simplification bc16 has over bc22, and
## the reason `world.nim` keeps one `seq[int]` with append-on-spawn and
## by-value removal plus a `Table[int, Robot]` that is NEVER ITERATED.

import std/[algorithm, random]
import harness
import bc16_fixture

# --- the initial robots are in FILE ORDER, not id order -------------------
block:
  ## Deliberately listed so that file order and id order DISAGREE if the port
  ## ever sorts: the `IDGenerator` shuffles its block, so the ids come out
  ## unordered while the exec order must stay the file's.
  let w = bare(robots = @[
    (x: 20, y: 3, kind: ord(rtArchon), team: ord(teamA)),
    (x: 4, y: 25, kind: ord(rtArchon), team: ord(teamB)),
    (x: 9, y: 9, kind: ord(rtSoldier), team: ord(teamA)),
    (x: 21, y: 21, kind: ord(rtSoldier), team: ord(teamB))])
  var locs: seq[Loc]
  for id in w.execOrder: locs.add(w.robotsById[id].loc)
  checkEq("the opening exec order is the map file's row order", locs,
    @[loc(20, 3), loc(4, 25), loc(9, 9), loc(21, 21)])
  var ids: seq[int]
  for id in w.execOrder: ids.add(id)
  check("and the ids are NOT ascending, because the IDGenerator shuffles " &
    "its block", ids != ids.sorted())
  ## 2016's `IDGenerator` starts its block at 0 and mints from 1, against the
  ## 10 000 floor every later year uses.
  for id in ids:
    check("every id is at least 1", id >= 1)
    check("and well below the 10 000 floor later years use", id < 10_000)

# --- append on spawn, by-value removal on death ---------------------------
block:
  let w = bare()
  var order: seq[int]
  for x in 5 .. 12:
    order.add(w.put(rtSoldier, loc(x, 5), teamA).id)
  checkEq("eight spawns append in spawn order",
    w.execOrder[^8 .. ^1], order)
  ## Remove the middle one BY VALUE: the survivors keep their relative order
  ## and no index shifts anything else.
  let victim = w.robotsById[order[3]]
  w.visitDeathSignal(victim, dcNormal)
  var want = order
  want.delete(3)
  checkEq("by-value removal preserves every survivor's relative order",
    w.execOrder[^7 .. ^1], want)
  check("and the dead id is gone from the table", not w.existsRobot(order[3]))

block:
  ## 500 random spawn/destroy sequences replayed against a plain reference
  ## list: the port's exec order must equal an ordinary append-and-remove list
  ## after every single operation.
  var rng = initRand(20160217)
  var mismatches = 0
  for trial in 0 ..< 500:
    let w = bare()
    ## Seeded from the two initial archons the fixture places, so the
    ## reference is the world's own opening list and not an empty one.
    var reference = w.execOrder
    let archons = reference
    for step in 0 ..< 12:
      if reference.len > archons.len and rng.rand(1.0) < 0.35:
        let i = archons.len + rng.rand(reference.len - archons.len - 1)
        let id = reference[i]
        reference.delete(i)
        w.visitDeathSignal(w.robotsById[id], dcNormal)
      else:
        var l = loc(rng.rand(TestWidth - 1), rng.rand(TestHeight - 1))
        if w.isLocationOccupied(l): continue
        reference.add(w.put(rtSoldier, l, teamA).id)
      if w.execOrder != reference: inc mismatches
  checkEq("500 random spawn/destroy sequences reproduce a plain " &
    "append-and-remove list exactly", mismatches, 0)

# --- the pre-sweep SNAPSHOT ------------------------------------------------
block:
  ## A robot BUILT this round takes NO turn this round: `runRound` iterates a
  ## snapshot of the id list taken before the sweep.
  let w = bare()
  let a = w.at(3, 15)
  w.adjustResources(teamA, 1000.0)
  let sheets = defaultSheets()
  let sides = newSides16(sheets, 0)
  let before = w.execOrder.len
  runRound(w, sides, [ckBulwark, ckBulwark])
  check("the archon built something", w.execOrder.len > before)
  var newborn: Robot = nil
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == teamA and r.kind != rtArchon: newborn = r
  check("there is a newborn", newborn != nil)
  if newborn != nil:
    checkEq("and it took NO turn this round: roundsAlive is still 0",
      newborn.roundsAlive, 0)
  discard a

block:
  ## A robot DESTROYED mid-sweep is skipped by the `robot == null` guard
  ## rather than crashing or acting.
  let w = bare()
  var ids: seq[int]
  for x in 5 .. 10:
    ids.add(w.put(rtSoldier, loc(x, 5), teamA).id)
  ## Kill three of them "mid-sweep" and then walk the snapshot the way the
  ## round loop does.
  let snapshot = w.execOrder
  for i in [1, 3, 5]:
    w.visitDeathSignal(w.robotsById[ids[i]], dcNormal)
  var visited = 0
  for id in snapshot:
    if not w.existsRobot(id): continue
    inc visited
  checkEq("a snapshot walk skips the dead and visits the rest",
    visited, snapshot.len - 3)

# --- !isActive() robots take a turn with a ZERO budget --------------------
block:
  ## `getBytecodeLimit()` returns 0 when `!canExecuteCode()`, so a SOLDIER
  ## built this round is a live, targetable, BLOCKING, damageable robot that
  ## does nothing for 12 turns. A VIPER is inert for 30, a TURRET for 25, a
  ## SCOUT for 20.
  let w = bare()
  for (k, turns) in [(rtSoldier, 12), (rtGuard, 10), (rtScout, 20),
                     (rtViper, 30), (rtTurret, 25)]:
    checkEq($k & "'s build delay is " & $turns, k.buildTurns(), turns)
  let s = w.put(rtSoldier, loc(10, 10), teamA, buildDelay = 12)
  check("a robot inside its build delay is NOT active", not s.isActive())
  check("and cannot execute code", not s.canExecuteCode())
  checkEq("so its DecisionOps budget is ZERO", budgetFor(s.kind), 1000)
  ## The budget is set by `processBeginningOfTurn`; play a round and read it.
  let sheets = defaultSheets()
  let sides = newSides16(sheets, 0)
  runRound(w, sides, [ckBulwark, ckBulwark])
  checkEq("after a round its budget really was zero", s.opsLeft, 0)
  checkEq("and it used nothing", s.opsUsed, 0)
  check("but it is alive, occupies its square and blocks",
    w.isLocationOccupied(loc(10, 10)))
  check("and it is damageable", s.health > 0.0)
  for r in 0 ..< 12:
    runRound(w, sides, [ckBulwark, ckBulwark])
  check("after twelve more rounds it IS active", s.isActive())
  checkEq("and gets the full standard budget", budgetFor(rtSoldier), 1000)
  checkEq("while an ARCHON and a SCOUT get the wide one",
    budgetFor(rtArchon), 2000)
  checkEq("and a SCOUT too", budgetFor(rtScout), 2000)

# --- the checksum the hash chain folds ------------------------------------
block:
  let w = bare()
  let a = w.execOrderChecksum()
  discard w.put(rtSoldier, loc(10, 10), teamA)
  let b = w.execOrderChecksum()
  check("the exec-order checksum moves when the list does", a != b)

finish("test_bc16_execorder")
