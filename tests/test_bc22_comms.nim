## The 64-slot shared array: FREE, UNRESTRICTED, and per-team.
##
## §Tests item 9, and the one place this year is SIMPLER than 2023: any robot
## may read and write at any time with no cooldown, no range test and no cost.
## The only price is bytecode, which this port charges as `DecisionOps`.

import harness
import bc22_fixture
import battlecode/years/bc22/chassis/comms

block:
  checkEq("the array is 64 slots", SharedArrayLength, 64)
  checkEq("and a slot holds 0..65535", MaxSharedArrayValue, 65535)
  check("index -1 is refused", not canWriteSharedArray(-1, 0))
  check("index 64 is refused", not canWriteSharedArray(64, 0))
  check("index 63 is fine", canWriteSharedArray(63, 0))
  check("value -1 is refused", not canWriteSharedArray(0, -1))
  check("value 65536 is refused", not canWriteSharedArray(0, 65536))
  check("value 65535 is fine", canWriteSharedArray(0, 65535))

block:
  var w = bare()
  ## A MINER at the far corner, with nothing at all nearby, writes freely —
  ## which is illegal in 2023 and legal here.
  let m = w.place(teamA, rtMiner, loc(0, 0))
  let before = m.actionCooldown
  check("the write is legal", w.writeSharedArray(m, 7, 4242))
  checkEq("and costs NO action cooldown", m.actionCooldown, before)
  checkEq("the value is there", w.readSharedArray(teamA, 7), 4242)
  checkEq("the OTHER team's array is untouched",
    w.readSharedArray(teamB, 7), 0)
  checkEq("and the write is counted", w.stats.arrayWrites[0], 1)

block:
  var w = bare()
  let m = w.place(teamB, rtMiner, loc(5, 5))
  discard w.writeSharedArray(m, 0, 9)
  checkEq("team B writes to team B's array", w.readSharedArray(teamB, 0), 9)
  checkEq("and cannot reach team A's", w.readSharedArray(teamA, 0), 0)
  let refusedBefore = w.refusedActions
  check("an out-of-range index is refused", not w.writeSharedArray(m, 99, 1))
  checkEq("and counted as a refusal", w.refusedActions - refusedBefore, 1)

block:
  ## The chassis's 16-bit slot packing round-trips for every slot class.
  var mismatches = 0
  for x in 0 .. 60:
    for y in 0 .. 60:
      for extra in 0 .. 15:
        let packed = packLoc(loc(x, y), extra)
        if packed > MaxSharedArrayValue: inc mismatches
        let back = unpackLoc(packed)
        if back.l != loc(x, y) or back.extra != extra: inc mismatches
  checkEq("packLoc/unpackLoc round-trip over the whole coordinate space",
    mismatches, 0)
  mismatches = 0
  for x in 0 .. 60:
    for y in 0 .. 60:
      for level in 1 .. 3:
        for alive in [true, false]:
          let packed = packArchon(loc(x, y), alive, level)
          if packed > MaxSharedArrayValue: inc mismatches
          let back = unpackArchon(packed)
          if back.l != loc(x, y) or back.alive != alive or
             back.level != level: inc mismatches
  checkEq("packArchon/unpackArchon round-trip likewise", mismatches, 0)

block:
  checkEq("a dead deposit buckets to zero", leadBucket(0), 0)
  check("and a live one never does", leadBucket(1) > 0)
  check("the bucket is monotone", (block:
    var ok = true
    for amount in 1 .. 300:
      if leadBucket(amount) < leadBucket(amount - 1): ok = false
    ok))
  checkEq("and tops out at fifteen", leadBucket(1000), 15)

block:
  ## A read and a write each cost exactly one `DecisionOps` credit, and the
  ## budget is what stops a chassis busy-looping the array.
  var w = bare()
  let m = w.place(teamA, rtMiner, loc(5, 5))
  m.opsLeft = 3
  check("three credits buy three writes", w.writeSlot(m, 0, 1))
  check("", w.writeSlot(m, 1, 1))
  check("", w.writeSlot(m, 2, 1))
  check("and the fourth is refused for budget, not for legality",
    not w.writeSlot(m, 3, 1))
  checkEq("slot 3 is still empty", w.readSharedArray(teamA, 3), 0)

finish("test_bc22_comms")
