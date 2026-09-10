## WHAT A ROBOT MAY SEE, and the field-stripping ladder that decides it.
##
## Five vision radii, and the PREACHER's is the one that matters: **r^2 16**,
## a reach of four squares, against its own blast radius of three. A preacher
## is nearly blind and it is the unit whose mistake is most expensive.
##
## `getGameStateDump` (`game.js:651-736`) builds one entry per robot that is
## VISIBLE, RADIOABLE or (for a castle) OWN-TEAM, then DELETES fields:
##
##   * not self          -> no `health`, no `karbonite`, no `fuel`
##   * not radioable     -> `signal` and `signal_radius` read as absent
##   * not visible       -> no `unit`
##   * neither           -> no `x`, no `y`
##   * not a castle      -> no `team` unless visible
##   * not a castle, or a castle looking at the enemy -> no `castle_talk`
##
## and the three MAPS ride along on `turn == 1` only, with `last_offer` for a
## CASTLE only.
##
## **V2 — `visible` is returned in ASCENDING `id`**, not in the engine's
## unseeded shuffle, and `tools/oracle/bc19/visible_order.patch` puts the same
## order on the engine side so the normalisation is symmetric.

import harness
import battlecode/years/bc19/rules

proc board(name = "seed-0045", rounds = 1000): World =
  newWorld(loadMap(name), rounds)

proc castleOf(w: World, t: Team): Robot =
  for r in w.robots:
    if r.team == t and r.unit == ukCastle: return r
  nil

proc freeAt(w: World, x0, y0, r2: int): (int, int) =
  ## A free passable square at EXACTLY squared distance `r2` from (x0,y0).
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if distSq(x0, y0, x, y) != r2: continue
      if w.isPassable(x, y) and w.shadowAt(x, y) == 0: return (x, y)
  (-1, -1)

proc seenBy(w: World, viewer: Robot, id: int): SeenRobot =
  for e in w.observationFor(viewer):
    if e.id == id: return e
  SeenRobot(id: -1)

block:
  ## THE FIVE RADII, from `coldbrew/specs.json` through the generated table.
  checkEq("a CASTLE sees r^2 100", visionRadiusOf(ukCastle), 100)
  checkEq("a CHURCH sees r^2 100", visionRadiusOf(ukChurch), 100)
  checkEq("a PILGRIM sees r^2 100", visionRadiusOf(ukPilgrim), 100)
  checkEq("a PROPHET sees r^2 64", visionRadiusOf(ukProphet), 64)
  checkEq("a CRUSADER sees r^2 49", visionRadiusOf(ukCrusader), 49)
  checkEq("a PREACHER sees r^2 16 -- FOUR SQUARES",
    visionRadiusOf(ukPreacher), 16)
  ## And the scan box is `floor(sqrt(radius))`, written as a literal case
  ## because there is no transcendental on any runtime path (D5).
  checkEq("box for 100 is 10", visionBoxOf(ukCastle), 10)
  checkEq("box for 64 is 8", visionBoxOf(ukProphet), 8)
  checkEq("box for 49 is 7", visionBoxOf(ukCrusader), 7)
  checkEq("box for 16 is 4", visionBoxOf(ukPreacher), 4)
  ## The box really is a superset of the disc: no square outside it can
  ## satisfy `dx^2 + dy^2 <= radius`.
  for u in [ukCastle, ukProphet, ukCrusader, ukPreacher]:
    let box = visionBoxOf(u)
    let rad = visionRadiusOf(u)
    for dy in -(box + 3) .. box + 3:
      for dx in -(box + 3) .. box + 3:
        if dx * dx + dy * dy <= rad:
          check("(" & $dx & "," & $dy & ") is inside " & unitName(u) &
            "'s box", abs(dx) <= box and abs(dy) <= box)

block:
  ## INCLUSIVE AT THE BOUNDARY, for every one of the five, on both sides.
  var w = board()
  let castle = w.castleOf(tRed)
  check("a red castle exists", not castle.isNil)
  for u in [ukCastle, ukChurch, ukPilgrim, ukProphet, ukCrusader,
            ukPreacher]:
    let rad = visionRadiusOf(u)
    let probe = Robot(x: 20, y: 20, unit: u, team: tRed)
    var onEdge = false
    var justOut = true
    for dy in -12 .. 12:
      for dx in -12 .. 12:
        let d = dx * dx + dy * dy
        if d == rad:
          onEdge = true
          check(unitName(u) & " SEES r^2 == radius",
            probe.canSee(20 + dx, 20 + dy))
        if d == rad + 1:
          justOut = justOut and not probe.canSee(20 + dx, 20 + dy)
    check(unitName(u) & " has a square at exactly its radius", onEdge)
    check(unitName(u) & " sees NOTHING at radius + 1", justOut)

block:
  ## THE SHADOW: -1 outside vision, 0 for an empty visible square, the id
  ## otherwise. Off the board is -1 too.
  var w = board()
  let castle = w.castleOf(tRed)
  checkEq("its own square carries its own id",
    w.shadowValueFor(castle, castle.x, castle.y), castle.id)
  let (ex, ey) = w.freeAt(castle.x, castle.y, 4)
  check("a free square at r^2 4 exists", ex >= 0)
  checkEq("an empty visible square reads 0",
    w.shadowValueFor(castle, ex, ey), 0)
  let mate = w.createItem(ex, ey, tRed, ukPilgrim)
  checkEq("and now reads the occupant's id",
    w.shadowValueFor(castle, ex, ey), mate.id)
  let (fx, fy) = w.freeAt(castle.x, castle.y, 101)
  if fx >= 0:
    checkEq("a square at r^2 101 is OUTSIDE a castle's vision and reads -1",
      w.shadowValueFor(castle, fx, fy), -1)
  checkEq("off the board reads -1", w.shadowValueFor(castle, -1, 0), -1)
  checkEq("and off the far edge too",
    w.shadowValueFor(castle, w.width, castle.y), -1)

block:
  ## CASE 1 -- SELF. Everything, including the three fields deleted for
  ## everyone else.
  var w = board()
  let castle = w.castleOf(tRed)
  castle.castleTalk = 33
  let me = w.seenBy(castle, castle.id)
  check("the self entry is flagged", me.isSelf)
  checkEq("with health", me.health, castle.health)
  checkEq("with carried karbonite", me.karbonite, castle.karbonite)
  checkEq("with carried fuel", me.fuel, castle.fuel)
  check("with unit type", me.hasUnit)
  check("with position", me.hasPos)
  check("with team", me.hasTeam)
  check("and its own castle talk", me.hasCastleTalk)
  checkEq("read back", me.castleTalk, 33)

block:
  ## CASE 2 -- A VISIBLE ENEMY. Type, position and team, but NOT health,
  ## NOT its carried load, NOT its castle talk, and NOT its signal unless it
  ## is broadcasting far enough.
  var w = board()
  let castle = w.castleOf(tRed)
  let (ex, ey) = w.freeAt(castle.x, castle.y, 9)
  check("a free square at r^2 9 exists", ex >= 0)
  let foe = w.createItem(ex, ey, tBlue, ukPreacher)
  foe.castleTalk = 99
  foe.health = 17
  foe.karbonite = 5
  foe.fuel = 6
  let e = w.seenBy(castle, foe.id)
  checkEq("the enemy is in the observation", e.id, foe.id)
  check("it is not self", not e.isSelf)
  check("its TYPE is visible", e.hasUnit)
  checkEq("and correct", e.unit, ukPreacher)
  check("its POSITION is visible", e.hasPos)
  checkEq("and correct", (e.x, e.y), (ex, ey))
  check("its TEAM is visible", e.hasTeam)
  checkEq("and correct", e.team, tBlue)
  checkEq("its HEALTH is NOT", e.health, 0)
  checkEq("nor its carried karbonite", e.karbonite, 0)
  checkEq("nor its carried fuel", e.fuel, 0)
  check("nor its castle talk", not e.hasCastleTalk)
  checkEq("and its signal reads as ABSENT, not as zero", e.signal, -1)
  checkEq("with the radius too", e.signalRadius, -1)
  ## Now let it broadcast far enough to be radioable and the signal appears.
  foe.signal = 1234
  foe.signalRadius = 9
  let e2 = w.seenBy(castle, foe.id)
  checkEq("a radioable enemy's signal is readable", e2.signal, 1234)
  checkEq("with its radius", e2.signalRadius, 9)

block:
  ## CASE 3 -- RADIOABLE ONLY. Position and signal, and NOT the unit type.
  ## Whether the TEAM survives depends on the LISTENER: `:708` is
  ## `if (!is_castle && !visible) delete r.team`, so a CASTLE keeps the team
  ## of a broadcaster it cannot see and every other unit does not. That
  ## asymmetry is easy to miss and it is asserted both ways here.
  var w = board()
  let castle = w.castleOf(tRed)
  var foe: Robot = nil
  for r2 in 121 .. 400:
    if not foe.isNil: break
    let (fx, fy) = w.freeAt(castle.x, castle.y, r2)
    if fx >= 0:
      foe = w.createItem(fx, fy, tBlue, ukProphet)
      foe.signal = 4242
      foe.signalRadius = r2
  check("a broadcaster outside the castle's vision exists", not foe.isNil)
  check("and it really is outside vision",
    distSq(castle.x, castle.y, foe.x, foe.y) > visionRadiusOf(ukCastle))
  let e = w.seenBy(castle, foe.id)
  checkEq("it has an entry", e.id, foe.id)
  checkEq("its signal is readable", e.signal, 4242)
  check("its POSITION is readable", e.hasPos)
  checkEq("and correct", (e.x, e.y), (foe.x, foe.y))
  check("but NOT its unit type", not e.hasUnit)
  check("and NOT its castle talk", not e.hasCastleTalk)
  check("a CASTLE listener DOES keep the team (`:708`'s !is_castle)",
    e.hasTeam)
  checkEq("and it is the enemy's", e.team, tBlue)
  ## The same broadcaster, heard by a NON-castle: no team.
  let (px, py) = w.freeAt(castle.x, castle.y, 1)
  check("a square next to the castle exists", px >= 0)
  let pil = w.createItem(px, py, tRed, ukPilgrim)
  foe.signalRadius = distSq(pil.x, pil.y, foe.x, foe.y)
  check("and the pilgrim cannot SEE it",
    distSq(pil.x, pil.y, foe.x, foe.y) > visionRadiusOf(ukPilgrim))
  let e2 = w.seenBy(pil, foe.id)
  checkEq("the pilgrim hears it", e2.signal, 4242)
  check("and learns its position", e2.hasPos)
  check("but NOT its team", not e2.hasTeam)
  check("and not its unit type", not e2.hasUnit)
  ## Go silent and the entry disappears from the pilgrim's observation
  ## entirely -- and from the castle's too, because `:682` keeps a
  ## non-visible non-radioable robot only when it is the castle's OWN team.
  foe.signalRadius = 0
  checkEq("silence, and it vanishes for the pilgrim",
    w.seenBy(pil, foe.id).id, -1)
  checkEq("and for the castle, because `:682` keeps only its OWN team",
    w.seenBy(castle, foe.id).id, -1)

block:
  ## CASE 4 -- A CASTLE AND ITS OWN TEAM, at any range. `:677` does not skip
  ## a castle and `:682` keeps only its own team, so a castle learns the
  ## `team`, `id` and `turn` of every friendly unit on the board and its
  ## `castle_talk` too -- but not where it is.
  var w = board()
  let castle = w.castleOf(tRed)
  var mate: Robot = nil
  for r2 in 121 .. 900:
    if not mate.isNil: break
    let (mx, my) = w.freeAt(castle.x, castle.y, r2)
    if mx >= 0: mate = w.createItem(mx, my, tRed, ukCrusader)
  check("a distant friendly exists", not mate.isNil)
  mate.turn = 71
  mate.castleTalk = 200
  let e = w.seenBy(castle, mate.id)
  checkEq("it has an entry", e.id, mate.id)
  check("with its TEAM", e.hasTeam)
  checkEq("which is ours", e.team, tRed)
  checkEq("with its TURN", e.turn, 71)
  check("with its CASTLE TALK", e.hasCastleTalk)
  checkEq("read back", e.castleTalk, 200)
  check("but NOT its position", not e.hasPos)
  check("and NOT its unit type", not e.hasUnit)
  ## A CHURCH is not a castle: it gets none of that.
  let (cx, cy) = w.freeAt(castle.x, castle.y, 1)
  check("a square next to the castle exists", cx >= 0)
  let church = w.createItem(cx, cy, tRed, ukChurch)
  checkEq("a CHURCH cannot see the distant friendly at all",
    w.seenBy(church, mate.id).id, -1)

block:
  ## CASE 5 -- NEITHER. No entry at all, for an enemy, for a church's own
  ## distant friendly, and for a mobile unit's own distant friendly.
  var w = board()
  let castle = w.castleOf(tRed)
  var far: Robot = nil
  for r2 in 121 .. 900:
    if not far.isNil: break
    let (fx, fy) = w.freeAt(castle.x, castle.y, r2)
    if fx >= 0: far = w.createItem(fx, fy, tBlue, ukCrusader)
  check("a distant enemy exists", not far.isNil)
  checkEq("a castle cannot see a distant ENEMY",
    w.seenBy(castle, far.id).id, -1)
  let (px, py) = w.freeAt(castle.x, castle.y, 1)
  let pil = w.createItem(px, py, tRed, ukPilgrim)
  checkEq("nor can a pilgrim", w.seenBy(pil, far.id).id, -1)
  ## And the observation is exactly the visible set for a mobile unit.
  var expected = 0
  for r in w.robots:
    if pil.isVisibleTo(r) or r.signalRadius >= distSq(pil.x, pil.y, r.x, r.y):
      inc expected
  checkEq("a mobile unit's observation is exactly what it can see",
    w.observationFor(pil).len, expected)

block:
  ## V2 -- `visible` IS RETURNED IN ASCENDING `id`, which is the one place
  ## this port is not the published engine (the engine's own order is an
  ## unseeded shuffle) and which the committed engine patch mirrors.
  var w = board()
  let castle = w.castleOf(tRed)
  ## Put eight friendlies around it, then delete and re-create one so the
  ## insertion order and the id order differ.
  var made: seq[Robot]
  for r2 in [1, 2, 4, 5, 8, 9, 10, 13]:
    let (x, y) = w.freeAt(castle.x, castle.y, r2)
    if x >= 0: made.add w.createItem(x, y, tRed, ukPilgrim)
  check("at least four neighbours were placed", made.len >= 4)
  let victim = made[0]
  let vx = victim.x
  let vy = victim.y
  w.deleteRobot(victim)
  discard w.createItem(vx, vy, tRed, ukPilgrim)
  let obs = w.observationFor(castle)
  check("the observation is non-empty", obs.len > 0)
  var ascending = true
  for i in 1 ..< obs.len:
    if obs[i - 1].id >= obs[i].id: ascending = false
  check("EVERY entry is in strictly ascending id order", ascending)
  ## And insertion order really is different, so the sort is doing work.
  var insertion: seq[int]
  for r in w.robots:
    if castle.isVisibleTo(r): insertion.add r.id
  var sortedSame = true
  for i in 1 ..< insertion.len:
    if insertion[i - 1] > insertion[i]: sortedSame = false
  check("the underlying insertion order is NOT already sorted",
    not sortedSame)

block:
  ## The three MAPS ride along on `turn == 1` ONLY, and `last_offer` is for a
  ## CASTLE only. Both live in `decide.nim`'s per-seat observation rather than
  ## in `vision.nim`, so what is asserted here is the predicate each uses.
  var w = board()
  let castle = w.castleOf(tRed)
  checkEq("a fresh robot's turn counter is 0", castle.turn, 0)
  castle.turn = 1
  check("turn 1 is the map-bearing turn", castle.turn == 1)
  castle.turn = 2
  check("turn 2 is not", castle.turn != 1)
  checkEq("only a CASTLE may trade, so only a castle has a last_offer",
    canTrade(ukCastle), true)
  for u in [ukChurch, ukPilgrim, ukCrusader, ukProphet, ukPreacher]:
    checkEq("no last_offer for " & unitName(u), canTrade(u), false)

block:
  ## `isRadioableTo` reads the SENDER'S CURRENT radius from the SENDER'S
  ## CURRENT POSITION, so a robot that broadcasts nothing has radius 0 and
  ## only its own square is radioable -- which is unreachable, because two
  ## robots cannot share a square.
  var w = board()
  let castle = w.castleOf(tRed)
  let (ax, ay) = w.freeAt(castle.x, castle.y, 4)
  let a = w.createItem(ax, ay, tRed, ukPilgrim)
  checkEq("a fresh robot's radius is 0", a.signalRadius, 0)
  check("so nobody is radioable to it", not castle.isRadioableTo(a))
  check("and it is radioable to ITSELF only in the degenerate sense",
    a.isRadioableTo(a))
  a.signalRadius = 4
  check("at radius 4 the castle at r^2 4 hears it",
    castle.isRadioableTo(a))
  a.signalRadius = 3
  check("at radius 3 it does not", not castle.isRadioableTo(a))

block:
  ## `visionBox` walks y ASCENDING OUTER and x ASCENDING INNER, the engine's
  ## own order, which matters wherever a caller breaks early.
  var w = board()
  let castle = w.castleOf(tRed)
  var last = (-1, -1)
  var ordered = true
  var n = 0
  for (x, y) in w.visionBox(castle):
    inc n
    if last[1] > y or (last[1] == y and last[0] >= x): ordered = false
    last = (x, y)
  check("the walk visited something", n > 0)
  check("y ascending outer, x ascending inner", ordered)
  ## And it visits exactly the on-board squares inside the radius.
  var expected = 0
  for y in 0 ..< w.height:
    for x in 0 ..< w.width:
      if distSq(castle.x, castle.y, x, y) <= visionRadiusOf(ukCastle):
        inc expected
  checkEq("and exactly the disc, clipped to the board", n, expected)

finish("test_bc19_vision")
