## bc24 communications: 64 slots, values 0..65 535, writes visible IMMEDIATELY
## to later ducks in the same round, reads and writes legal for a JAILED duck,
## out-of-range index or value refused, and the chassis's word packing round-
## tripping for every field.

import harness
import bc24_fixture
import battlecode/years/bc24/chassis/comms

block:
  var w = bare()
  checkEq("sixty-four slots", SharedArrayLength, 64)
  checkEq("and the ceiling is 65 535", MaxSharedArrayValue, 65535)
  for i in 0 ..< SharedArrayLength:
    checkEq("slot " & $i & " starts empty", w.readSharedArray(teamA, i), 0)

block:
  var w = bare()
  w.writeSharedArray(teamA, 0, 65535)
  checkEq("the ceiling is writable", w.readSharedArray(teamA, 0), 65535)
  w.writeSharedArray(teamA, 0, 65536)
  checkEq("one above is refused, leaving the old value",
    w.readSharedArray(teamA, 0), 65535)
  w.writeSharedArray(teamA, 0, -1)
  checkEq("and so is a negative", w.readSharedArray(teamA, 0), 65535)
  w.writeSharedArray(teamA, 64, 7)
  checkEq("an out-of-range index writes nothing",
    w.readSharedArray(teamA, 64), 0)
  checkEq("and reads zero", w.readSharedArray(teamA, -1), 0)

block:
  var w = bare()
  w.writeSharedArray(teamA, 5, 1234)
  checkEq("A wrote", w.readSharedArray(teamA, 5), 1234)
  checkEq("B's array is a DIFFERENT array", w.readSharedArray(teamB, 5), 0)

block:
  ## Writes take effect immediately and are visible to the same team's later
  ## ducks in the same round; there is no per-round snapshot in 2024.
  var w = bare()
  w.postSetup()
  let early = w.placeDuck(teamA, loc(5, 5))
  let late = w.placeDuck(teamA, loc(6, 6))
  check("(both are on the board)", early.spawned and late.spawned)
  w.writeSharedArray(teamA, 9, 4242)
  checkEq("a later duck reads it in the SAME round",
    w.readSharedArray(teamA, 9), 4242)

block:
  ## There is NO SPAWNED REQUIREMENT on the shared array: a jailed duck may
  ## read and write.
  var w = bare()
  w.postSetup()
  let r = w.robots[0]
  check("the duck is not spawned", not r.spawned)
  w.writeSharedArray(r.team, 12, 99)
  checkEq("a jailed duck's write lands", w.readSharedArray(r.team, 12), 99)

# --- the chassis word format ------------------------------------------------
block:
  for x in 0 .. 59:
    for y in 0 .. 59:
      for tag in 0 .. 15:
        let word = packLoc(loc(x, y), tag)
        if word < 0 or word > MaxSharedArrayValue:
          check("packLoc stays inside a 16-bit word", false)
        let back = unpackLoc(word)
        if back.l != loc(x, y) or back.tag != tag:
          check("packLoc round-trips " & $x & "," & $y & "," & $tag, false)
  check("packLoc round-trips every coordinate and tag a 60x60 map can hold",
    true)

block:
  checkEq("the slot map has no overlaps: own flags at 0", SlotOwnFlag, 0)
  checkEq("enemy flags at 3", SlotEnemyFlag, 3)
  checkEq("distress at 6", SlotDistress, 6)
  checkEq("the upgrade ledger at 9", SlotUpgrades, 9)
  checkEq("congestion at 10", SlotCongestion, 10)
  checkEq("rally points at 13", SlotRally, 13)
  checkEq("the sighting grid at 16", SlotSightings, 16)
  checkEq("role claims at 48", SlotRoles, 48)
  check("and the last claim slot is inside the array",
    SlotRoles + 6 <= SharedArrayLength)

block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  var side = newSide(teamA, defaultDoctrine24())
  w.refreshFields(side)
  w.publishOwnFlags(side, r)
  let word = w.readSharedArray(teamA, SlotOwnFlag)
  let back = unpackLoc(word)
  checkEq("the first own flag's location round-trips through the array",
    back.l, w.ownFlags(teamA)[0].loc)
  checkEq("and its state reads `home`", back.tag, 0)
  w.publishUpgrades(side, r)
  checkEq("the upgrade ledger starts empty",
    w.readSharedArray(teamA, SlotUpgrades), 0)
  w.stats.upgrades[0][1] = true
  w.publishUpgrades(side, r)
  checkEq("and records CAPTURING as bit 1",
    w.readSharedArray(teamA, SlotUpgrades), 2)

block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  var side = newSide(teamA, defaultDoctrine24())
  w.refreshFields(side)
  for i in 0 .. 400:
    w.noteSighting(side, r, loc(1, 1))
  let slot = SlotSightings
  check("the sighting grid saturates rather than overflowing the word",
    w.readSharedArray(teamA, slot) <= MaxSharedArrayValue)
  check("and it counted something", w.readSharedArray(teamA, slot) > 0)

finish("bc24 comms")
