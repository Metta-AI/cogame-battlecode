## bc23's shared arrays and the WRITE WINDOW: a headquarters or an amplifier
## may always write; anybody else needs a friendly amplifier within r2 <= 20,
## a friendly headquarters within r2 <= 9, or one of ITS OWN islands within
## r2 <= 4. Index and value bounds, reading always legal, no cooldown and no
## cost, the two teams isolated, and the chassis's 16-bit packing.

import harness
import bc23_fixture
import battlecode/years/bc23/chassis/comms as chcomms

# --- a headquarters and an amplifier may always write ----------------------
block:
  var w = bare()
  let hq = w.robotsById[2]
  check("a headquarters may always write", w.canWriteSharedArray(hq, 0, 1))
  let amp = w.place(teamA, rtAmplifier, loc(15, 25))
  check("and so may an amplifier, anywhere on the map",
    w.canWriteSharedArray(amp, 0, 1))

# --- the bounds -----------------------------------------------------------
block:
  var w = bare()
  let hq = w.robotsById[2]
  check("index 0 is legal", w.canWriteSharedArray(hq, 0, 0))
  check("index 63 is legal", w.canWriteSharedArray(hq, 63, 0))
  check("index -1 is not", not w.canWriteSharedArray(hq, -1, 0))
  check("index 64 is not", not w.canWriteSharedArray(hq, 64, 0))
  check("value 65535 is legal", w.canWriteSharedArray(hq, 0, 65535))
  check("value 65536 is not", not w.canWriteSharedArray(hq, 0, 65536))
  check("a negative value is not", not w.canWriteSharedArray(hq, 0, -1))
  checkEq("the array is 64 long", SharedArrayLength, 64)
  checkEq("and the maximum value is 65535", MaxSharedArrayValue, 65535)

# --- the three windows, one at a time -------------------------------------
block:
  ## A friendly HEADQUARTERS within r2 <= 9.
  var w = bare()
  let near = w.place(teamA, rtCarrier, loc(6, 15))
  checkEq("the carrier is at exactly r2 = 9",
    near.loc.distanceSquaredTo(loc(3, 15)), 9)
  check("so it may write", w.canWriteSharedArray(near, 0, 1))
  let far = w.place(teamA, rtCarrier, loc(7, 15))
  checkEq("one tile further is r2 = 16",
    far.loc.distanceSquaredTo(loc(3, 15)), 16)
  check("and it may not", not w.canWriteSharedArray(far, 0, 1))
  check("nor may it write near the ENEMY's headquarters",
    not w.canWriteSharedArray(w.place(teamA, rtCarrier, loc(25, 15)), 0, 1))

block:
  ## A friendly AMPLIFIER within r2 <= 20.
  var w = bare()
  discard w.place(teamA, rtAmplifier, loc(15, 15))
  let near = w.place(teamA, rtCarrier, loc(19, 17))
  checkEq("the carrier is at exactly r2 = 20",
    near.loc.distanceSquaredTo(loc(15, 15)), 20)
  check("so it may write", w.canWriteSharedArray(near, 0, 1))
  let far = w.place(teamA, rtCarrier, loc(20, 17))
  checkEq("one tile further is r2 = 29",
    far.loc.distanceSquaredTo(loc(15, 15)), 29)
  check("and it may not", not w.canWriteSharedArray(far, 0, 1))
  let enemy = w.place(teamB, rtCarrier, loc(19, 17))
  check("an ENEMY beside our amplifier may not write through it",
    not w.canWriteSharedArray(enemy, 0, 1))

block:
  ## One of OUR OWN islands within r2 <= 4.
  var w = bare(islands = @[(l: loc(15, 15), id: 1)])
  let near = w.place(teamA, rtCarrier, loc(17, 15))
  checkEq("the carrier is at exactly r2 = 4",
    near.loc.distanceSquaredTo(loc(15, 15)), 4)
  check("but a NEUTRAL island opens no window",
    not w.canWriteSharedArray(near, 0, 1))
  let planter = w.place(teamA, rtCarrier, loc(15, 15))
  planter.addAnchor(anStandard)
  discard w.doPlaceAnchor(planter)
  checkEq("the island is ours", w.islands[0].owner, 1)
  check("NOW it may write", w.canWriteSharedArray(near, 0, 1))
  let far = w.place(teamA, rtCarrier, loc(18, 15))
  check("and one tile further may not", not w.canWriteSharedArray(far, 0, 1))
  let enemy = w.place(teamB, rtCarrier, loc(17, 16))
  check("an enemy beside OUR island may not",
    not w.canWriteSharedArray(enemy, 0, 1))

# --- reading is always legal, and the two arrays are isolated -------------
block:
  var w = bare()
  let hq = w.robotsById[2]
  hq.actionCooldown = 0
  check("the write lands", w.doWriteSharedArray(hq, 7, 4242))
  checkEq("and reads back", w.readSharedArray(teamA, 7), 4242)
  checkEq("THE OTHER TEAM SEES NOTHING", w.readSharedArray(teamB, 7), 0)
  let far = w.place(teamA, rtCarrier, loc(25, 25))
  check("a robot outside every window may not write",
    not w.canWriteSharedArray(far, 7, 1))
  checkEq("but reading is always legal, at any distance",
    w.readSharedArray(teamA, 7), 4242)
  checkEq("an out-of-range index reads 0", w.readSharedArray(teamA, 99), 0)
  checkEq("the write cost NO COOLDOWN AND NO RESOURCE", hq.actionCooldown, 0)
  checkEq("and the write is counted", w.stats.arrayWrites[0], 1)

# --- the chassis's 16-bit slot packing round-trips -------------------------
block:
  for x in [0, 1, 30, 59, 63]:
    for y in [0, 1, 30, 59, 63]:
      let packed = chcomms.packLoc(loc(x, y))
      check("packLoc fits 16 bits at " & $x & "," & $y,
        packed >= 0 and packed <= MaxSharedArrayValue)
      checkEq("and round-trips at " & $x & "," & $y,
        chcomms.unpackLoc(packed), loc(x, y))
  check("a well slot fits",
    chcomms.packWell(loc(59, 59), resElixir, true, true) <=
      MaxSharedArrayValue)
  check("an island slot fits",
    chcomms.packIsland(35, 2, 15, true) <= MaxSharedArrayValue)
  check("a sighting slot fits",
    chcomms.packSighting(loc(59, 59), 15) <= MaxSharedArrayValue)
  check("an anchor claim fits",
    chcomms.packAnchorClaim(35, 511) <= MaxSharedArrayValue)
  checkEq("and the layout bases are the note's",
    [chcomms.SlotHqBase, chcomms.SlotWellBase, chcomms.SlotIslandBase,
     chcomms.SlotSightingBase, chcomms.SlotElixirBase, chcomms.SlotRallyBase,
     chcomms.SlotAnchorClaimBase, chcomms.SlotCensusBase],
    [0, 4, 16, 28, 36, 40, 48, 56])

finish("test_bc23_comms")
