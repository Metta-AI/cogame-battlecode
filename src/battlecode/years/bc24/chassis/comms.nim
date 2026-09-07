## The 64-slot shared array, as this chassis packs it.
##
## One 16-bit word per slot, and the format is SHARED BY BOTH TEAMS —
## deliberately, because it makes the endcard able to decode both sides'
## traffic and because the array is per team anyway (there is no cross-team
## read in 2024).
##
##   0..2    own flag i as [x:6][y:6][state:4]   state 0 home, 1 dropped,
##                                               2 carried by us, 3 lost
##   3..5    enemy flag i last known as [x:6][y:6][age:4]
##   6..8    own-flag distress counters
##   9       the upgrade ledger (a 3-bit mask)
##   10..12  spawn-zone congestion
##   13..15  rally points as [x:6][y:6]
##   16..47  a coarse 8x8 enemy-sighting grid with saturating counts
##   48..63  role claims
##
## A doctrine cannot redefine this: the knobs steer what gets said, not the
## encoding (§Out of scope). Reads and writes are free against the game's own
## rules and are charged only against `DecisionOps`.

import kit

export kit

const
  SlotOwnFlag* = 0
  SlotEnemyFlag* = 3
  SlotDistress* = 6
  SlotUpgrades* = 9
  SlotCongestion* = 10
  SlotRally* = 13
  SlotSightings* = 16
  SlotRoles* = 48

func packLoc*(l: Loc, tag: int): int =
  ## `[x:6][y:6][tag:4]`. Coordinates are 0..59, which fits six bits.
  ((l.x and 63) shl 10) or ((l.y and 63) shl 4) or (tag and 15)

func unpackLoc*(word: int): tuple[l: Loc, tag: int] =
  (loc((word shr 10) and 63, (word shr 4) and 63), word and 15)

proc writeWord*(w: World, side: Side, r: Robot, slot, value: int) =
  if not spend(r, 1): return
  w.writeSharedArray(side.team, slot, value)

proc readWord*(w: World, side: Side, r: Robot, slot: int): int =
  if not spend(r, 1): return 0
  w.readSharedArray(side.team, slot)

proc publishOwnFlags*(w: World, side: Side, r: Robot) =
  ## Written by the first duck of the team to act each round, so the rest of
  ## the flock plans against one shared picture.
  var i = 0
  for f in w.allFlags:
    if f.team != side.team: continue
    if i > 2: break
    var state = 0
    if f.carriedBy >= 0:
      let carrier = w.robotById(f.carriedBy)
      state = if carrier != nil and carrier.team == side.team: 2 else: 3
    elif not f.locIsStartRef:
      state = 1
    w.writeWord(side, r, SlotOwnFlag + i, packLoc(f.loc, state))
    i += 1

proc publishEnemyFlags*(w: World, side: Side, r: Robot) =
  for i in 0 .. 2:
    let note = side.knownEnemyFlag[i]
    if note.round < 0: continue
    let age = min(15, (w.currentRound - note.round) div 8)
    w.writeWord(side, r, SlotEnemyFlag + i, packLoc(note.loc, age))

proc publishDistress*(w: World, side: Side, r: Robot) =
  for i in 0 .. 2:
    w.writeWord(side, r, SlotDistress + i, min(MaxSharedArrayValue,
      side.distress[i]))

proc publishUpgrades*(w: World, side: Side, r: Robot) =
  var mask = 0
  for slot in 0 .. 2:
    if w.hasUpgrade(side.team, slot): mask = mask or (1 shl slot)
  w.writeWord(side, r, SlotUpgrades, mask)

proc publishRoles*(w: World, side: Side, r: Robot) =
  for i in 0 .. 5:
    w.writeWord(side, r, SlotRoles + i, min(MaxSharedArrayValue,
      side.roleCount[i]))

proc noteSighting*(w: World, side: Side, r: Robot, l: Loc) =
  ## The coarse 8x8 enemy-sighting grid, with saturating counts, so a duck
  ## that has never seen the enemy still knows which quarter of the map they
  ## came from.
  let gx = min(7, l.x * 8 div max(1, w.width))
  let gy = min(7, l.y * 8 div max(1, w.height))
  let slot = SlotSightings + gy * 4 + (gx div 2)
  if slot >= SlotRoles: return
  let word = w.readSharedArray(side.team, slot)
  let half = if (gx and 1) == 0: 0 else: 8
  var count = (word shr half) and 0xFF
  if count < 0xFF: count += 1
  let cleared = word and (if half == 0: 0xFF00 else: 0x00FF)
  w.writeWord(side, r, slot, cleared or (count shl half))
