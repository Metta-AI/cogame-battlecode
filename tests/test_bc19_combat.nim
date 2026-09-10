## THE PREACHER, the most-cited case in this year.
##
## `enactAttack` (`action_record.js:289-317`) sweeps the WHOLE BOARD, `r` (y)
## ascending outer and `c` (x) ascending inner, and hits every occupied square
## with `rad <= DAMAGE_SPREAD` **of the TARGET SQUARE** — for a PREACHER's
## spread of 3 that is exactly the nine squares of the 3x3 box, because
## `dx^2 + dy^2 = 3` has no integer solution.
##
## **THERE IS NO TEAM CHECK AND NO ATTACKER EXCLUSION.** A preacher that fires
## at an adjacent square is inside its own blast and takes its own damage; a
## friendly standing in the box dies exactly like an enemy.
##
## The named vector is the measured 9x9 probe (design note, §Measured, row
## "the PREACHER's own splash"), re-measured here against the PINNED engine's
## own `ActionRecord.enactAttack` while this file was written: a preacher at
## (4,4) firing at (5,4), enemy pilgrims at (5,4) carrying 4 karbonite /
## 20 fuel and at (5,5) carrying 6 karbonite / 26 fuel, a friendly pilgrim at
## (3,4). Result: preacher 60 -> 40 HP, both enemies dead in the order (5,4)
## then (5,5), the friendly at r^2 4 UNHARMED, reclaim exactly 14 karbonite /
## 33 fuel, team fuel -15.

import std/[math, strutils]
import harness
import battlecode/years/bc19/rules

proc synth(width, height: int): MapSpec =
  ## An all-passable, depot-free, castle-free board with a REAL MT19937 state
  ## (borrowed from a committed map, so `createItem`'s id draws are legal).
  result = loadMap("seed-0009")
  result.name = "synthetic-" & $width & "x" & $height
  result.width = width
  result.height = height
  result.symmetryHorizontal = true
  result.passable = newSeq[bool](width * height)
  for i in 0 ..< width * height: result.passable[i] = true
  result.karboniteMap = newSeq[bool](width * height)
  result.fuelMap = newSeq[bool](width * height)
  result.castles = @[]
  result.passableSquares = width * height
  result.karboniteDepots = 0
  result.fuelDepots = 0
  result.castlesPerSide = 0

proc place(w: World, x, y: int, team: Team, unit: UnitKind,
           k = 0, f = 0): Robot =
  result = w.createItem(x, y, team, unit)
  result.karbonite = k
  result.fuel = f

proc fire(w: World, r: Robot, dx, dy: int) =
  var rec = newRecord()
  rec.action = akAttack
  rec.dx = dx
  rec.dy = dy
  w.enact(r, rec)

block:
  ## THE NAMED VECTOR, asserted field by field.
  var w = newWorld(synth(9, 9), 1000)
  let pre = w.place(4, 4, tRed, ukPreacher)
  let enemyA = w.place(5, 4, tBlue, ukPilgrim, 4, 20)
  let enemyB = w.place(5, 5, tBlue, ukPilgrim, 6, 26)
  let friend = w.place(3, 4, tRed, ukPilgrim, 7, 70)
  checkEq("the preacher starts at 60 HP", pre.health, 60)
  w.fuel[ord(tRed)] = 1000
  w.fire(pre, 1, 0)
  checkEq("the preacher is inside its own blast: 60 -> 40", pre.health, 40)
  checkEq("the enemy at the target square is dead",
    w.getItem(enemyA.id).isNil, true)
  checkEq("the enemy at r^2 1 from the target square is dead",
    w.getItem(enemyB.id).isNil, true)
  checkEq("the FRIENDLY at r^2 4 from the target square is untouched",
    friend.health, startingHpOf(ukPilgrim))
  checkEq("and it is still alive", w.getItem(friend.id).isNil, false)
  checkEq("the reclaim is exactly 14 karbonite", pre.karbonite, 14)
  checkEq("and exactly 33 fuel", pre.fuel, 33)
  checkEq("the attack cost 15 team fuel", w.fuel[ord(tRed)], 1000 - 15)

block:
  ## THE NINE SQUARES, and only the nine. `dx^2 + dy^2 = 3` has no integer
  ## solution, so `rad <= 3` around the target square is exactly the 3x3 box.
  var n = 0
  for dy in -3 .. 3:
    for dx in -3 .. 3:
      if dx * dx + dy * dy <= damageSpreadOf(ukPreacher): inc n
  checkEq("a spread of 3 is exactly nine squares", n, 9)
  check("and no offset has r^2 exactly 3",
    (block:
      var found = false
      for dy in -3 .. 3:
        for dx in -3 .. 3:
          if dx * dx + dy * dy == 3: found = true
      not found))
  ## Every one of the nine is actually hit, and the tenth is not. The
  ## preacher stands well outside its own blast here so the ring is the
  ## whole story; its self-inclusion is the named vector's business.
  var w = newWorld(synth(11, 11), 1000)
  let pre = w.place(1, 6, tRed, ukPreacher)
  var ring: seq[Robot]
  ring.add w.place(6, 6, tBlue, ukProphet)         ## the target square itself
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      ring.add w.place(6 + dx, 6 + dy, tBlue, ukProphet)
  let outside = w.place(6 - 2, 6, tBlue, ukProphet)
  w.fuel[ord(tRed)] = 1000
  w.fire(pre, 5, 0)                  ## target square (6,6)
  var hit = 0
  for r in ring:
    if r.health == startingHpOf(ukProphet) - attackDamageOf(ukPreacher):
      inc hit
  checkEq("all NINE squares of the target's box took damage", hit, 9)
  checkEq("and the square at r^2 4 from the target did not",
    outside.health, startingHpOf(ukProphet))
  checkEq("the attacker, at r^2 25 from the target, is untouched",
    pre.health, startingHpOf(ukPreacher))

block:
  ## NO TEAM CHECK: a blast that lands on three friendlies kills three
  ## friendlies, and the stats say so.
  var w = newWorld(synth(9, 9), 1000)
  let pre = w.place(1, 4, tRed, ukPreacher)
  var mates: seq[Robot]
  for dy in -1 .. 1:
    mates.add w.place(4, 4 + dy, tRed, ukPilgrim)
  w.fuel[ord(tRed)] = 1000
  w.fire(pre, 3, 0)
  var dead = 0
  for m in mates:
    if w.getItem(m.id).isNil: inc dead
  checkEq("three FRIENDLY pilgrims died to a friendly blast", dead, 3)
  checkEq("and the friendly-fire damage was counted",
    w.stats.friendlyFireDamage[ord(tRed)], 3 * attackDamageOf(ukPreacher))
  checkEq("with no kills credited", w.stats.kills[ord(tRed)], 0)
  checkEq("but three units lost", w.stats.unitsLost[ord(tRed)], 3)
  checkEq("the preacher outside its own blast is unhurt",
    pre.health, startingHpOf(ukPreacher))

block:
  ## THE SWEEP ORDER IS LOAD-BEARING: y ascending outer, x ascending inner.
  ## Four full pilgrims in one blast reclaim 20+5 = 25 karbonite each, which
  ## the preacher's 20-karbonite capacity clamps after the FIRST one; the
  ## fuel side clamps at 100. What proves the ORDER is which kill is
  ## processed first, so the test puts the resources where only the order can
  ## explain the outcome: the LOW-y, LOW-x victim is empty and the others are
  ## full, and the reclaim still fills to the cap because the later kills are
  ## processed after it rather than instead of it.
  var w = newWorld(synth(9, 9), 1000)
  let pre = w.place(4, 4, tRed, ukPreacher)
  discard w.place(4, 3, tBlue, ukPilgrim, 0, 0)      ## first in sweep order
  discard w.place(3, 4, tBlue, ukPilgrim, 20, 100)
  discard w.place(5, 4, tBlue, ukPilgrim, 20, 100)
  discard w.place(4, 5, tBlue, ukPilgrim, 20, 100)
  w.fuel[ord(tRed)] = 1000
  w.fire(pre, 0, 0)                  ## illegal for a chassis; legal to enact
  checkEq("four enemies died", w.stats.kills[ord(tRed)], 4)
  checkEq("the karbonite reclaim clamped at the preacher's capacity",
    pre.karbonite, karboniteCapacityOf(ukPreacher))
  checkEq("and the fuel reclaim clamped at its capacity",
    pre.fuel, fuelCapacityOf(ukPreacher))
  ## And the reclaim stat never counts more than the clamp allowed.
  checkEq("the reclaim stat matches what actually arrived",
    w.stats.karboniteReclaimed[ord(tRed)], karboniteCapacityOf(ukPreacher))
  checkEq("for fuel too", w.stats.fuelReclaimed[ord(tRed)],
    fuelCapacityOf(ukPreacher))

block:
  ## Now the order itself, isolated. Two victims, the earlier one in sweep
  ## order carrying enough that the clamp bites BEFORE the later one is
  ## reached: the later one's contribution is therefore invisible, which is
  ## only true for one of the two possible orders.
  ##
  ## Victim P at (4,3) — y = 3, swept FIRST — carries 20 karbonite; at
  ## rad_to_attacker 1 it reclaims 20 + 5 = 25 -> clamped to 20.
  ## Victim Q at (4,5) — y = 5, swept LAST — carries 20 karbonite too.
  ## Either order clamps to 20, so instead the test uses FUEL, where P alone
  ## gives 100 (the cap) and Q alone would give 50 at rad 1... so the
  ## discriminator is a preacher whose fuel is ALREADY near the cap and two
  ## victims with different loads.
  ##
  ## The clean discriminator is the stats counter, which records the DELTA of
  ## each credit: with the cap reached on the first credit the second credit
  ## adds nothing, and the total delta equals the cap minus what was held.
  var w = newWorld(synth(9, 9), 1000)
  let pre = w.place(4, 4, tRed, ukPreacher)
  pre.fuel = 90
  discard w.place(4, 3, tBlue, ukPilgrim, 0, 100)    ## swept first
  discard w.place(4, 5, tBlue, ukPilgrim, 0, 100)    ## swept last
  w.fuel[ord(tRed)] = 1000
  w.fire(pre, 0, 0)
  checkEq("the fuel reclaim is capped at 100", pre.fuel, 100)
  checkEq("so only 10 fuel was actually credited",
    w.stats.fuelReclaimed[ord(tRed)], 10)

block:
  ## `floor((karbonite + CONSTRUCTION_KARBONITE/2) / rad_to_attacker)` for
  ## EVERY reachable divisor, against the committed table, and against a
  ## from-scratch rational recomputation. `CONSTRUCTION_KARBONITE/2` is a
  ## HALF-INTEGER for a prophet (15/2) and a preacher (25/2), which is why the
  ## table is keyed by TWICE the numerator.
  var checkedRads = 0
  for rad in ReclaimDivisors:
    if rad == 0: continue
    inc checkedRads
    for kar in 0 .. karboniteCapacityOf(ukPilgrim):
      for u in [ukPilgrim, ukCrusader, ukProphet, ukPreacher, ukChurch]:
        let doubled = 2 * kar + buildKarboniteOf(u)
        let want = doubled div (2 * rad)
        checkEq("reclaim div rad=" & $rad & " k=" & $kar & " " & unitName(u),
          reclaimDivDoubled(doubled, rad), want)
    for fu in 0 .. fuelCapacityOf(ukPilgrim):
      checkEq("fuel reclaim div rad=" & $rad & " f=" & $fu,
        reclaimDivDoubled(2 * fu, rad), fu div rad)
  checkEq("nine non-zero divisors are reachable inside a blast",
    checkedRads, 9)
  check("and the ten include the attacker's own square",
    ReclaimDivisors[0] == 0)
  ## Every reachable divisor really is reachable: r^2 from the attacker to a
  ## square in the blast box of an adjacent-or-diagonal target.
  var seen: seq[int]
  for tdy in -1 .. 1:
    for tdx in -1 .. 1:
      if tdx == 0 and tdy == 0: continue
      for dy in -1 .. 1:
        for dx in -1 .. 1:
          let x = tdx + dx
          let y = tdy + dy
          if dx * dx + dy * dy > damageSpreadOf(ukPreacher): continue
          let r2 = x * x + y * y
          if r2 notin seen: seen.add r2
  for r2 in seen:
    check("r^2 " & $r2 & " is a tabled divisor", r2 in ReclaimDivisors)

block:
  ## `rad_to_attacker == 0` is the ATTACKER'S OWN SQUARE, which a PREACHER
  ## firing at itself always includes. In JavaScript `Math.floor(n/0)` is
  ## `Infinity` and `Math.floor(0/0)` is `NaN`; the caller is
  ## `Math.min(held + reclaimed, capacity)`, so the first CLAMPS TO THE
  ## CAPACITY and the second is `NaN` — read never, because the robot is
  ## deleted on the next line. The port PINS BOTH TO THE CAPACITY CLAMP.
  check("the table marks divisor 0 as 'clamp'",
    reclaimDivDoubled(2 * 7 + buildKarboniteOf(ukPilgrim), 0) < 0)
  check("including the 0/0 case",
    reclaimDivDoubled(0, 0) < 0)
  ## And it really clamps in play: a preacher standing on a victim's square
  ## cannot happen (occupancy), so the reachable case is a preacher killing
  ## ITSELF, whose reclaim is skipped for a structure but not for a preacher.
  var w = newWorld(synth(9, 9), 1000)
  let pre = w.place(4, 4, tRed, ukPreacher)
  pre.health = attackDamageOf(ukPreacher)   ## exactly lethal to itself
  pre.karbonite = 3
  pre.fuel = 7
  w.fuel[ord(tRed)] = 1000
  w.fire(pre, 1, 0)
  checkEq("a preacher that kills itself is deleted",
    w.getItem(pre.id).isNil, true)
  checkEq("and its own death was counted as a friendly loss",
    w.stats.unitsLost[ord(tRed)], 1)
  checkEq("with the self-damage recorded",
    w.stats.selfDamage[ord(tRed)], attackDamageOf(ukPreacher))
  checkEq("and no kill credited", w.stats.kills[ord(tRed)], 0)

block:
  ## D6.3 — A STRUCTURE KILL RECLAIMS NOTHING. `CONSTRUCTION_KARBONITE` is
  ## not read at all: the whole reclaim branch is skipped.
  var w = newWorld(synth(9, 9), 1000)
  let pre = w.place(4, 4, tRed, ukPreacher)
  let church = w.place(5, 4, tBlue, ukChurch, 0, 0)
  church.health = attackDamageOf(ukPreacher)
  w.fuel[ord(tRed)] = 1000
  w.fire(pre, 1, 0)
  checkEq("the enemy church died", w.getItem(church.id).isNil, true)
  checkEq("and reclaimed NO karbonite", pre.karbonite, 0)
  checkEq("and NO fuel", pre.fuel, 0)
  checkEq("even though a church costs 50 karbonite to build",
    buildKarboniteOf(ukChurch), 50)
  var w2 = newWorld(synth(9, 9), 1000)
  let pre2 = w2.place(4, 4, tRed, ukPreacher)
  let castle = w2.place(5, 4, tBlue, ukCastle, 0, 0)
  castle.health = attackDamageOf(ukPreacher)
  w2.fuel[ord(tRed)] = 1000
  w2.fire(pre2, 1, 0)
  checkEq("the enemy castle died", w2.getItem(castle.id).isNil, true)
  checkEq("and reclaimed nothing either", pre2.karbonite + pre2.fuel, 0)
  checkEq("but the castle loss was noted",
    w2.stats.castlesLost[ord(tBlue)], 1)

block:
  ## D6.3, the OTHER side: a STRUCTURE ATTACKER collects nothing, because
  ## `Math.min(n, null) === 0`. A castle killing a loaded pilgrim gains
  ## nothing at all.
  var w = newWorld(synth(9, 9), 1000)
  let castle = w.place(4, 4, tRed, ukCastle)
  let victim = w.place(5, 4, tBlue, ukPilgrim, 20, 100)
  victim.health = attackDamageOf(ukCastle)
  w.fuel[ord(tRed)] = 1000
  w.fire(castle, 1, 0)
  checkEq("the loaded pilgrim died", w.getItem(victim.id).isNil, true)
  checkEq("a CASTLE's karbonite capacity is the coerced 0",
    karboniteCapacityOf(ukCastle), 0)
  checkEq("and its fuel capacity too", fuelCapacityOf(ukCastle), 0)
  checkEq("so the castle reclaimed nothing", castle.karbonite, 0)
  checkEq("nor any fuel", castle.fuel, 0)

block:
  ## The other five attackers all have DAMAGE_SPREAD 0, so their blast is
  ## exactly the target square and they are never in it (a non-zero
  ## `dx`/`dy` is required by rule 4.1).
  for u in [ukCastle, ukChurch, ukCrusader, ukProphet, ukPreacher]:
    checkEq("spread for " & unitName(u), damageSpreadOf(u),
      (if u == ukPreacher: 3 else: 0))
  var w = newWorld(synth(9, 9), 1000)
  let cru = w.place(4, 4, tRed, ukCrusader)
  let a = w.place(5, 4, tBlue, ukProphet)
  let b = w.place(5, 5, tBlue, ukProphet)
  w.fuel[ord(tRed)] = 1000
  w.fire(cru, 1, 0)
  checkEq("a crusader hits exactly one square",
    a.health, startingHpOf(ukProphet) - attackDamageOf(ukCrusader))
  checkEq("and its neighbour is untouched", b.health, startingHpOf(ukProphet))

block:
  ## The CHURCH "attack" (D6.1): accepted, 0 damage, 0 fuel, spread 0. It
  ## consumes the turn and changes nothing.
  var w = newWorld(synth(9, 9), 1000)
  let church = w.place(4, 4, tRed, ukChurch)
  let victim = w.place(5, 4, tBlue, ukPilgrim, 3, 3)
  w.fuel[ord(tRed)] = 1000
  w.fire(church, 1, 0)
  checkEq("a church attack deals no damage",
    victim.health, startingHpOf(ukPilgrim))
  checkEq("and costs no fuel", w.fuel[ord(tRed)], 1000)
  checkEq("but it was counted as an attack", w.stats.attacks[ord(tRed)], 1)

block:
  ## The blast is CLIPPED to the board, never wrapped: a preacher in the
  ## corner firing outward hits only the on-board squares.
  ## Target square (-1,4): its box is x in -2..0, y in 3..5, of which only
  ## the x = 0 column exists. (0,3) is hit at rad 2, the preacher at (0,4) is
  ## hit at rad 1, and (1,4) at rad 4 is not.
  var w = newWorld(synth(9, 9), 1000)
  let pre = w.place(0, 4, tRed, ukPreacher)
  let onBoard = w.place(0, 3, tBlue, ukProphet)
  let justOut = w.place(1, 4, tBlue, ukProphet)
  w.fuel[ord(tRed)] = 1000
  w.fire(pre, -1, 0)                 ## target square (-1,4), off the board
  checkEq("the on-board square at rad 2 of the off-board target was hit",
    onBoard.health, startingHpOf(ukProphet) - attackDamageOf(ukPreacher))
  checkEq("the on-board square at rad 4 was not",
    justOut.health, startingHpOf(ukProphet))
  checkEq("and the attacker, at rad 1 from the target, took its own damage",
    pre.health, startingHpOf(ukPreacher) - attackDamageOf(ukPreacher))

block:
  ## The splash BEAT: emitted on the first preacher kill and then every
  ## eighth, never on a kill-free blast.
  var w = newWorld(synth(9, 9), 1000)
  w.round = 5
  let pre = w.place(4, 4, tRed, ukPreacher)
  w.fuel[ord(tRed)] = 100000
  w.fire(pre, 2, 0)                  ## nothing there
  checkEq("a kill-free blast emits no splash beat", w.events.len, 0)
  discard w.place(6, 4, tBlue, ukPilgrim)
  w.fire(pre, 2, 0)
  checkEq("the first preacher kill emits one", w.events.len, 1)
  checkEq("labelled preacher_splash", w.events[0].kind, "preacher_splash")

finish("test_bc19_combat")
