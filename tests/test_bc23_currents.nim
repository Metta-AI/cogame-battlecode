## bc23's currents: the forecast, the three ways a robot is IMMEDIATELY
## blocked, the transitive closure asserted against a reference fixed point
## over 500 random layouts, the lift-and-set-down, the fact that A
## HEADQUARTERS ON A CURRENT IS PUSHED (engine behaviour), and the measured
## fact that NO COMMITTED MAP LETS THAT HAPPEN.

import std/[random, sets, tables]
import harness
import bc23_fixture

const
  East = 5      ## `DIRECTION_ORDER` index of EAST
  West = 1
  North = 3

# --- the forecast and the lift ---------------------------------------------
block:
  var w = bare(currents = @[(l: loc(10, 10), dir: East)])
  let r = w.place(teamA, rtCarrier, loc(10, 10))
  w.applyCurrents()
  checkEq("a robot on a current is shoved one square along it", r.loc.x, 11)
  checkEq("and its y is unchanged", r.loc.y, 10)
  checkEq("the old tile is free", int(w.getRobot(loc(10, 10)) == nil), 1)
  checkEq("and the new one holds it", w.getRobot(loc(11, 10)).id, r.id)
  checkEq("the ride is counted", w.stats.currentRides[0], 1)
  w.applyCurrents()
  checkEq("a robot NOT on a current does not move", r.loc.x, 11)

# --- immediately blocked: impassable, off the map, contested ---------------
block:
  var w = bare(walls = @[loc(11, 10)],
               currents = @[(l: loc(10, 10), dir: East)])
  let r = w.place(teamA, rtCarrier, loc(10, 10))
  w.applyCurrents()
  checkEq("a current into a wall blocks the robot", r.loc.x, 10)

block:
  var w = bare(currents = @[(l: loc(29, 10), dir: East)])
  let r = w.place(teamA, rtCarrier, loc(29, 10))
  w.applyCurrents()
  checkEq("a current off the map blocks the robot", r.loc.x, 29)

block:
  ## Two robots forecast onto the SAME tile: both are immediately blocked.
  var w = bare(currents = @[(l: loc(10, 10), dir: East),
                            (l: loc(12, 10), dir: West)])
  let a = w.place(teamA, rtCarrier, loc(10, 10))
  let b = w.place(teamB, rtCarrier, loc(12, 10))
  w.applyCurrents()
  checkEq("the first is blocked", a.loc.x, 10)
  checkEq("and so is the second", b.loc.x, 12)

# --- the transitive closure ------------------------------------------------
block:
  ## A conveyor of three: the leader is blocked by a wall, so ALL THREE stay.
  var w = bare(walls = @[loc(13, 10)],
               currents = @[(l: loc(10, 10), dir: East),
                            (l: loc(11, 10), dir: East),
                            (l: loc(12, 10), dir: East)])
  let a = w.place(teamA, rtCarrier, loc(10, 10))
  let b = w.place(teamA, rtCarrier, loc(11, 10))
  let c = w.place(teamA, rtCarrier, loc(12, 10))
  w.applyCurrents()
  checkEq("the leader is blocked", c.loc.x, 12)
  checkEq("and so is the one behind it", b.loc.x, 11)
  checkEq("transitively", a.loc.x, 10)

block:
  ## The same conveyor with nothing in the way: ALL THREE advance in one
  ## round, because the engine clears every mover from the board before it
  ## sets any of them down.
  var w = bare(currents = @[(l: loc(10, 10), dir: East),
                            (l: loc(11, 10), dir: East),
                            (l: loc(12, 10), dir: East)])
  let a = w.place(teamA, rtCarrier, loc(10, 10))
  let b = w.place(teamA, rtCarrier, loc(11, 10))
  let c = w.place(teamA, rtCarrier, loc(12, 10))
  w.applyCurrents()
  checkEq("the leader advanced", c.loc.x, 13)
  checkEq("the middle advanced", b.loc.x, 12)
  checkEq("and the tail advanced", a.loc.x, 11)

# --- the closure against a reference fixed point, 500 random layouts -------
proc referenceClosure(w: World): HashSet[int] =
  ## The engine's own recursion, written the slow obvious way: forecast every
  ## robot, mark the immediately blocked, then close under "forecast onto the
  ## tile of a robot that is not moving" until nothing changes.
  var forecast = initTable[int, int]()    ## robot id -> forecast tile, -1 off
  var owners = initTable[int, seq[int]]()
  for id in w.execOrder:
    let r = w.robotsById[id]
    let dest = r.loc + w.getCurrent(r.loc)
    if not w.onTheMap(dest):
      forecast[id] = -1
    else:
      forecast[id] = w.idx(dest)
      if not owners.hasKey(w.idx(dest)): owners[w.idx(dest)] = @[]
      owners[w.idx(dest)].add(id)
  result = initHashSet[int]()
  for id, f in forecast:
    if f < 0:
      result.incl(id)
    elif (not w.isPassable(w.indexToLoc(f))) or owners[f].len > 1:
      result.incl(id)
  var changed = true
  while changed:
    changed = false
    for id in w.execOrder:
      if id in result: continue
      if forecast[id] >= 0:
        for other in w.execOrder:
          if other == id: continue
          if w.idx(w.robotsById[other].loc) == forecast[id] and
              other in result:
            result.incl(id)
            changed = true

block:
  var rng = initRand(20230908)
  var mismatches = 0
  for trial in 0 ..< 500:
    var currents: seq[tuple[l: Loc, dir: int]]
    var walls: seq[Loc]
    for k in 0 ..< 12:
      currents.add((l: loc(5 + rng.rand(0 .. 9), 5 + rng.rand(0 .. 9)),
                    dir: [East, West, North][rng.rand(0 .. 2)]))
    for k in 0 ..< 3:
      walls.add(loc(5 + rng.rand(0 .. 11), 5 + rng.rand(0 .. 11)))
    var w = bare(walls = walls, currents = currents)
    var placed: seq[int]
    for k in 0 ..< 10:
      let at = loc(5 + rng.rand(0 .. 9), 5 + rng.rand(0 .. 9))
      if w.isLocationOccupied(at) or not w.isPassable(at): continue
      placed.add(w.place(teamA, rtCarrier, at).id)
    let reference = referenceClosure(w)
    var before = initTable[int, Loc]()
    for id in w.execOrder: before[id] = w.robotsById[id].loc
    w.applyCurrents()
    for id in placed:
      if not w.existsRobot(id): continue
      let moved = w.robotsById[id].loc != before[id]
      let shouldMove = (id notin reference) and
        w.getCurrent(before[id]) != dCenter
      if moved != shouldMove: mismatches += 1
  checkEq("the worklist closure equals the reference fixed point on 500 " &
    "random layouts", mismatches, 0)

# --- a headquarters on a current IS pushed (engine behaviour) --------------
block:
  var w = bare(currents = @[(l: loc(3, 15), dir: North)],
               hqs = @[(id: 3, x: 26, y: 15, team: 2),
                       (id: 2, x: 3, y: 15, team: 1)])
  let hq = w.robotsById[2]
  w.applyCurrents()
  checkEq("`applyCurrents` iterates EVERY robot, headquarters included",
    hq.loc.y, 16)

# --- and no committed map lets that happen --------------------------------
block:
  var offenders = 0
  var maps = 0
  for pool in ["small", "mixed", "large"]:
    for name in poolNames(pool):
      let spec = loadMap(name)
      maps += 1
      for b in spec.initialBodies:
        if spec.currents[b.x + b.y * spec.width] != 0: offenders += 1
      ## Two further map-generation guarantees the prose states and the engine
      ## does not enforce, MEASURED across every committed map.
      for i in 0 ..< spec.width * spec.height:
        if spec.clouds[i] and spec.currents[i] != 0: offenders += 1
  check("every pool map was read", maps >= 22)
  checkEq("NO HEADQUARTERS SITS ON A CURRENT on any committed map, and no " &
    "tile is both cloud and current", offenders, 0)

# --- currents fire EVERY round, after every robot's turn ------------------
block:
  checkEq("CURRENT_STRENGTH is 1, so `round % 1 == 0` is always",
    CurrentStrength, 1)
  ## Every tile the scaffold carrier can reach in one step is a current, so
  ## wherever it wanders the shove must fire.
  var patch: seq[tuple[l: Loc, dir: int]]
  for x in 8 .. 12:
    for y in 8 .. 12:
      patch.add((l: loc(x, y), dir: East))
  var w = bare(currents = patch)
  var sides = newSides23(defaultSheets(), 0)
  ## Round 1 is the +200/+200 round and the engine THROWS if any round-1 body
  ## is not a headquarters, so the carrier joins in round 2.
  runRound(w, sides, [ckExamplefuncsplayer23, ckExamplefuncsplayer23])
  discard w.place(teamA, rtCarrier, loc(10, 10))
  runRound(w, sides, [ckExamplefuncsplayer23, ckExamplefuncsplayer23])
  check("the round loop applied the current after every robot's turn",
    w.stats.currentRides[0] > 0)

finish("test_bc23_currents")
