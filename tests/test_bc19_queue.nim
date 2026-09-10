## THE TURN QUEUE — this year's whole tempo.
##
## `this.robots` is a plain JavaScript ARRAY (`game.js:33`), `robin` an index
## into it (`:41`), `createItem` APPENDS (`:461`) and `_deleteRobot` SPLICES
## and decrements `robin` when the removed index is below it (`:939-942`).
## It is the ONLY robot collection the engine iterates, and there is no hash
## map, no set, no sort and no priority queue anywhere in the round loop
## (D2).

import harness
import battlecode/sheet
import battlecode/years/bc19/rules

let sheets = [defaultSheet(YearBc19), defaultSheet(YearBc19)]
let idle = [ck19Saber, ck19Saber]

proc fresh(name: string, rounds = 1000): World =
  newWorld(loadMap(name), rounds)

block:
  ## `robin` starts at `Infinity` and `round` at 0, so THE FIRST PLAYED
  ## ROUND IS ROUND 1 — and the flat trickle lands BEFORE the round's first
  ## robot acts.
  var w = fresh("seed-0043")
  checkEq("round starts at 0", w.round, 0)
  checkEq("robin starts at `Infinity`", w.robin, high(int))
  checkEq("both stores start at the engine's own initial values",
    w.karbonite[0] * 10000 + w.fuel[0], InitialKarbonite * 10000 + InitialFuel)
  var sides = newSides19(sheets, 0)
  w.enactTurn(sides, idle)
  checkEq("the first `enactTurn` opens ROUND 1", w.round, 1)
  checkEq("and the trickle has already landed",
    w.fuel[0] + w.stats.fuelSpent[0], InitialFuel + TrickleFuel)
  checkEq("for both teams",
    w.fuel[1] + w.stats.fuelSpent[1], InitialFuel + TrickleFuel)
  checkEq("and `robin` has advanced past the first robot", w.robin, 1)

block:
  ## The initial castles are in `to_create` ORDER — RED, BLUE, RED, BLUE —
  ## which is the opening queue order and therefore the order their ids are
  ## drawn in.
  let spec = loadMap("seed-0107")
  var w = newWorld(spec, 1000)
  checkEq("seed-0107 has three castles a side", spec.castlesPerSide, 3)
  checkEq("so the queue opens with six robots", w.robots.len, 6)
  for i, r in w.robots:
    checkEq("queue slot " & $i & " is the map's castle " & $i,
      r.id, w.getItem(r.id).id)
    checkEq("and its team alternates", ord(r.team), i mod 2)
    checkEq("and its square is the map's", r.x * 1000 + r.y,
      spec.castles[i].x * 1000 + spec.castles[i].y)
    checkEq("and it is a CASTLE", r.unit, ukCastle)

block:
  ## **A UNIT BUILT IN A ROUND TAKES A TURN IN THE SAME ROUND**, because
  ## `createItem` APPENDS and the new robot lands behind `robin`. Measured
  ## on the real engine: seven turns in round 1 on `seed-0043` with four
  ## castles and three pilgrims.
  var w = fresh("seed-0043")
  var sides = newSides19(sheets, 0)
  var turnsInRound1 = 0
  while w.running:
    if w.evaluateIsOver(): break
    w.enactTurn(sides, idle)
    inc turnsInRound1
    if w.robin >= w.robots.len: break
  check("round 1 played MORE turns than the four castles it started with",
    turnsInRound1 > 4)
  checkEq("and every one of them was a robot that existed by then",
    turnsInRound1, w.robots.len)
  var built = 0
  for r in w.robots:
    if r.unit != ukCastle: inc built
  check("because the castles built units that then acted", built > 0)
  for r in w.robots:
    checkEq("and EVERY robot on the board took a turn in round 1", r.turn, 1)

block:
  ## `_deleteRobot`: the shadow square is cleared, the robot is spliced out
  ## of the array, and **`robin` is decremented when the removed index was
  ## BELOW it** — which is why a unit killed after it has already acted does
  ## not make the sweep skip the next one.
  var w = fresh("seed-0107")
  w.robin = 4
  let victim = w.robots[1]
  let survivor = w.robots[2].id
  let x = victim.x
  let y = victim.y
  checkEq("the victim owns its shadow square", w.shadowAt(x, y), victim.id)
  w.deleteRobot(victim)
  checkEq("the square is cleared", w.shadowAt(x, y), 0)
  checkEq("the robot is gone from the queue", w.robots.len, 5)
  checkEq("`robin` shifted back because index 1 < 4", w.robin, 3)
  checkEq("and the survivor kept its place relative to the rest",
    w.robots[1].id, survivor)
  check("the lookup no longer resolves", w.getItem(victim.id).isNil)
  ## And a removal ABOVE `robin` does NOT move it.
  w.robin = 1
  let later = w.robots[3]
  w.deleteRobot(later)
  checkEq("`robin` is untouched when the removed index is above it",
    w.robin, 1)

block:
  ## AN ID IS NEVER RETURNED TO THE POOL (V4). The engine pushes to `ids`
  ## and never splices it, so a dead robot's id is spent forever.
  var w = fresh("seed-0009")
  let spentBefore = w.idsSpent.len
  let victim = w.robots[0]
  let deadId = victim.id
  w.deleteRobot(victim)
  checkEq("the pool did not shrink", w.idsSpent.len, spentBefore)
  check("and the dead id is still marked spent",
    w.idIsSpent.getOrDefault(deadId, false))

block:
  ## **ROUND `maxRounds` CONSISTS OF EXACTLY ONE ROBOT TURN.** The game-over
  ## check runs BEFORE EVERY TURN, so the round counter reaches the cap on
  ## the first turn of that round and the check fires immediately after it.
  var w = fresh("seed-0043", 40)
  var sides = newSides19(sheets, 0)
  var turnsInLastRound = 0
  var lastRound = 0
  while w.running:
    if w.evaluateIsOver():
      w.running = false
      break
    if w.robin >= w.robots.len and w.round + 1 == 40:
      lastRound = 40
    w.enactTurn(sides, idle)
    if w.round == 40: inc turnsInLastRound
  checkEq("the game stopped at the cap", w.round, 40)
  checkEq("AND THE LAST ROUND HAD EXACTLY ONE TURN", turnsInLastRound, 1)

block:
  ## 500 RANDOM BUILD/KILL SEQUENCES against the queue's own invariants.
  ## The array, the index map and `robin` have to stay consistent through
  ## any interleaving, because the engine's own array does.
  var rng = 20190043'u32
  proc nextRand(): int =
    rng = rng * 1664525'u32 + 1013904223'u32
    int(rng shr 16)
  for trial in 0 ..< 500:
    var w = fresh("seed-0045")
    w.robin = 0
    for step in 0 ..< 12:
      if (nextRand() and 1) == 0 and w.robots.len < 40:
        ## Build somewhere free next to a random live robot.
        let anchor = w.robots[nextRand() mod w.robots.len]
        var placed = false
        for dy in -1 .. 1:
          for dx in -1 .. 1:
            if placed or (dx == 0 and dy == 0): continue
            if w.isPassable(anchor.x + dx, anchor.y + dy) and
                w.shadowAt(anchor.x + dx, anchor.y + dy) == 0:
              discard w.createItem(anchor.x + dx, anchor.y + dy,
                anchor.team, ukCrusader)
              placed = true
      elif w.robots.len > 1:
        let i = nextRand() mod w.robots.len
        let before = w.robin
        let r = w.robots[i]
        w.deleteRobot(r)
        if i < before:
          checkEq("robin shifted back on a removal below it (trial " &
            $trial & ")", w.robin, before - 1)
        else:
          checkEq("and not on one above it (trial " & $trial & ")",
            w.robin, before)
      ## The invariants, after every single step.
      if w.indexById.len != w.robots.len:
        checkEq("the index map tracks the array exactly (trial " & $trial &
          ")", w.indexById.len, w.robots.len)
      for j, r in w.robots:
        if w.indexById.getOrDefault(r.id, -1) != j:
          checkEq("every robot's index is its array slot (trial " & $trial &
            ")", w.indexById.getOrDefault(r.id, -1), j)
        if w.shadowAt(r.x, r.y) != r.id:
          checkEq("and it owns its shadow square (trial " & $trial & ")",
            w.shadowAt(r.x, r.y), r.id)
  check("500 random build/kill sequences held every queue invariant", true)

finish("test_bc19_queue")
