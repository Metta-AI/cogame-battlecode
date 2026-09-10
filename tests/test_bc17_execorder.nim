## §Tests item 9 -- the execution order (D4).
##
## The 2017 engine's turn order is an ARRAY and that is all it is:
## `ObjectInfo` keeps a `TIntArrayList` of dynamic-body ids, appends robots,
## INSERTS a bullet at `indexOf(parent)` -- i.e. immediately BEFORE the robot
## that fired it -- removes BY VALUE, and `GameWorld.updateDynamicBodies`
## SNAPSHOTS the list before each round's sweep.
##
## Two consequences that shape the whole year:
##
##   * a body spawned during round R is NOT in round R's snapshot and does
##     not act until R+1 -- which is what makes rule 4.2's twenty-round
##     dormancy a *separate* rule rather than the same one;
##   * a bullet first moves the round AFTER it is fired, and always just
##     before its parent's next turn.

import std/[algorithm, sequtils]
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom, units, world, maps, ballistics]

# --- the opening order is MAP-FILE ID ORDER ---------------------------------
block:
  ## `LiveMap`'s constructor sorts all initial bodies by id
  ## (`LiveMap.java:67`), and TREES ARE NOT IN THE EXEC ORDER -- they are
  ## updated by their own phase. So the opening exec order is the map file's
  ## robots, id-ascending.
  var w = newWorld(loadMap("HouseDivided"), gameDefaultRounds)
  checkEq("HouseDivided opens with exactly two bodies in the exec order",
    w.execOrder.len, 2)
  checkEq("and they are id 54 then id 55", w.execOrder, @[54, 55])
  checkEq("id 54 is TEAM B's archon", w.robots[54].team, tB)
  checkEq("id 55 is TEAM A's", w.robots[55].team, tA)
  check("so B's archon acts FIRST on this map -- the order is the file's, " &
    "not the team's", w.execOrder[0] == 54)
  checkEq("its forty-one neutral trees are NOT in the exec order",
    w.trees.len, 41)

# --- Chess: four archons interleaving B, A, B, A ---------------------------
block:
  var w = newWorld(loadMap("Chess"), gameDefaultRounds)
  checkEq("Chess opens with four archons", w.execOrder.len, 4)
  checkEq("in map-file id order 1028..1031", w.execOrder,
    @[1028, 1029, 1030, 1031])
  var teams: seq[Team]
  for id in w.execOrder: teams.add(w.robots[id].team)
  checkEq("whose teams interleave B, A, B, A", teams, @[tB, tA, tB, tA])
  check("which is NOT all of one team then the other",
    teams != @[tA, tA, tB, tB] and teams != @[tB, tB, tA, tA])

# --- robots are APPENDED on spawn -------------------------------------------
block:
  var w = newWorld(loadMap("HouseDivided"), gameDefaultRounds)
  let o = w.rect.origin
  let before = w.execOrder
  let a = w.spawnRobot(rtGardener, loc(o.x + 5, o.y + 5), tA)
  let b = w.spawnRobot(rtGardener, loc(o.x + 8, o.y + 5), tB)
  checkEq("a spawned robot goes on the END", w.execOrder,
    before & @[a.id, b.id])
  check("even when its id is lower than the ones already there",
    a.id > 55 or w.execOrder[^2] == a.id)

# --- a bullet is inserted immediately BEFORE its parent ---------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  proc at(dx, dy: float32): Loc = loc(o.x + dx, o.y + dy)
  let first = w.spawnRobot(rtSoldier, at(20, 20), tA)
  let firer = w.spawnRobot(rtSoldier, at(40, 50), tA)
  let last = w.spawnRobot(rtSoldier, at(60, 60), tB)
  let baseline = w.execOrder
  let bid = w.spawnBullet(tA, 2'f32, 2'f32, at(42, 50), dirRads(0), firer.id)
  let at1 = w.execOrder.find(bid)
  checkEq("the bullet lands immediately before its parent",
    w.execOrder[at1 + 1], firer.id)
  checkEq("nothing else moved", w.execOrder.filterIt(it != bid), baseline)
  ## A second bullet from the same parent goes in front of the first.
  let bid2 = w.spawnBullet(tA, 2'f32, 2'f32, at(42, 52), dirRads(0), firer.id)
  checkEq("a second bullet from the same firer lands at indexOf(parent) " &
    "again, i.e. AFTER the first one", w.execOrder.find(bid2), at1 + 1)
  checkEq("so the order is [b1, b2, parent] -- firing order preserved",
    @[w.execOrder[at1], w.execOrder[at1 + 1], w.execOrder[at1 + 2]],
    @[bid, bid2, firer.id])
  check("and the other two robots are untouched",
    w.execOrder.find(first.id) >= 0 and w.execOrder.find(last.id) >= 0)

# --- an orphan bullet appends -----------------------------------------------
block:
  ## `indexOf` returns -1 for a parent that is gone, and the engine's
  ## `insert(-1, ...)` would throw -- so the port appends, which is the same
  ## observable position for a body whose parent has already acted.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let firer = w.spawnRobot(rtSoldier, loc(o.x + 40, o.y + 50), tA)
  let bid = w.spawnBullet(tA, 2'f32, 2'f32, loc(o.x + 42, o.y + 50),
                          dirRads(0), 999999)
  checkEq("a bullet with no live parent goes on the end",
    w.execOrder[^1], bid)
  check("and the firer is still in the list", w.execOrder.find(firer.id) >= 0)

# --- removal is BY VALUE ----------------------------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  var ids: seq[int]
  for i in 0 ..< 5:
    ids.add(w.spawnRobot(rtSoldier, loc(o.x + float32(20 + i * 4),
                                        o.y + 20), tA).id)
  let before = w.execOrder.len
  w.destroyRobot(ids[2])
  checkEq("one body left the list", w.execOrder.len, before - 1)
  check("the removed id is gone", w.execOrder.find(ids[2]) < 0)
  check("and the survivors kept their relative order",
    w.execOrder.find(ids[1]) < w.execOrder.find(ids[3]))
  ## Removing something that is not there is a no-op, not a shift.
  let snapshot = w.execOrder
  w.destroyRobot(ids[2])
  checkEq("removing it twice changes nothing", w.execOrder, snapshot)

# --- the per-round SNAPSHOT --------------------------------------------------
block:
  ## `updateDynamicBodies` copies the list before sweeping it, so a body
  ## spawned during the sweep does not act in the same round.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let snapshot = w.execOrder
  let newcomer = w.spawnRobot(rtSoldier, loc(o.x + 30, o.y + 30), tA)
  check("the newcomer IS in the live list", w.execOrder.find(newcomer.id) >= 0)
  check("but it is NOT in the snapshot taken before it existed",
    snapshot.find(newcomer.id) < 0)
  checkEq("which is exactly one entry shorter", snapshot.len,
    w.execOrder.len - 1)

# --- a body killed after acting shifts nothing ------------------------------
block:
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  var ids: seq[int]
  for i in 0 ..< 4:
    ids.add(w.spawnRobot(rtSoldier, loc(o.x + float32(20 + i * 4),
                                        o.y + 20), tA).id)
  let snapshot = w.execOrder
  ## Sweep the snapshot, killing the second body as it acts. The remaining
  ## entries of the snapshot are still walked, and the dead one is simply
  ## skipped by the `hasKey` guard the round loop uses.
  var acted: seq[int]
  for id in snapshot:
    if not w.robots.hasKey(id) and not w.bullets.hasKey(id): continue
    acted.add(id)
    if id == ids[1]: w.destroyRobot(id)
  checkEq("every body in the snapshot acted exactly once", acted, snapshot)
  check("and the dead one is out of the live list",
    w.execOrder.find(ids[1]) < 0)

# --- the fold the parity trace carries --------------------------------------
block:
  var w = newWorld(loadMap("HouseDivided"), gameDefaultRounds)
  let a = w.execOrderFold()
  checkEq("the fold is stable", a, w.execOrderFold())
  ## The wire format, written out here so the shard does not merely call the
  ## same function twice: one whole int per iteration, masked to 32 bits.
  proc foldIds(values: openArray[int]): uint64 =
    result = 0xcbf29ce484222325'u64
    for v in values:
      result = (result xor uint64(uint32(v))) * 0x100000001B3'u64
  checkEq("and it is fnv1a64 over the list", a, foldIds(w.execOrder))
  let o = w.rect.origin
  discard w.spawnRobot(rtSoldier, loc(o.x + 10, o.y + 10), tA)
  check("it moves when the list does", w.execOrderFold() != a)
  check("a reordering changes it", foldIds(@[55, 54]) != foldIds(@[54, 55]))
  checkEq("and the empty fold is the offset basis", foldIds([]),
    0xcbf29ce484222325'u64)

finish("test_bc17_execorder")
