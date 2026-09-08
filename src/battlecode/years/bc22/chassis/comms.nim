## The 64-slot shared-array layout `wololo` uses.
##
## Behaviour ported from `jmerle/battlecode-2022` `src/camel_case_v25_final/
## util/SharedArray.java` (MIT, head `f57d3549`) and
## `BSreenivas0713/Battlecode2022` `src/MPTempName/Comms.java` (AGPL-3.0, head
## `c388fe8a`). BEHAVIOUR, NOT CODE — rewritten in Nim. `NOTICE` names the
## files.
##
## In 2022 a shared-array write costs **nothing**: any robot, any time, no
## cooldown, no range test, no amplifier and no write window (rule 3.2.10 —
## this is the one place this year is SIMPLER than 2023). The only price is
## bytecode, which this port charges as one `DecisionOps` credit per read or
## write.
##
## Sixteen bits a slot, 64 slots:
##
## | slots | contents |
## |---|---|
## | 0-3   | our archons, packed `x:6 y:6 alive:1 level:2` |
## | 4-7   | the enemy-archon guess and its confidence |
## | 8-23  | remembered live lead clusters, `x:6 y:6 bucket:4` |
## | 24-27 | gold sightings |
## | 28-35 | enemy sightings with a 4-bit age |
## | 36-39 | the laboratory sites and their current rate |
## | 40-47 | rally points |
## | 48-55 | the anomaly programme (next type, round bucket, requested play) |
## | 56-63 | the per-type census |
##
## A doctrine cannot redefine this layout: it is the chassis's, not the cog's
## (§Out of scope).

import ../world

export world

const
  SlotArchons* = 0
  SlotEnemyArchons* = 4
  SlotLeadClusters* = 8
  SlotGoldSightings* = 24
  SlotEnemySightings* = 28
  SlotLabSites* = 36
  SlotRally* = 40
  SlotAnomaly* = 48
  SlotCensus* = 56

  MaxCoord* = 63
    ## Six bits. Every official map is at most 60 wide and 60 high, so a
    ## coordinate always fits.

func packLoc*(l: Loc, extra: int): int =
  ## `x:6 y:6 extra:4`, the layout every positional slot shares.
  ((min(max(l.x, 0), MaxCoord) and 0x3F) shl 10) or
  ((min(max(l.y, 0), MaxCoord) and 0x3F) shl 4) or
  (extra and 0xF)

func unpackLoc*(v: int): tuple[l: Loc, extra: int] =
  (loc((v shr 10) and 0x3F, (v shr 4) and 0x3F), v and 0xF)

func packArchon*(l: Loc, alive: bool, level: int): int =
  ## `x:6 y:6 alive:1 level:2`.
  ((min(max(l.x, 0), MaxCoord) and 0x3F) shl 10) or
  ((min(max(l.y, 0), MaxCoord) and 0x3F) shl 4) or
  ((if alive: 1 else: 0) shl 3) or
  ((level - 1) and 0x3)

func unpackArchon*(v: int): tuple[l: Loc, alive: bool, level: int] =
  (loc((v shr 10) and 0x3F, (v shr 4) and 0x3F),
   ((v shr 3) and 1) == 1,
   (v and 0x3) + 1)

func leadBucket*(amount: int): int =
  ## Four bits of "how much is left here": 0 means dead.
  if amount <= 0: 0
  elif amount >= 150: 15
  else: 1 + (amount * 14) div 150

proc readSlot*(w: World, r: Robot, index: int): int =
  if not r.spend(1): return 0
  w.readSharedArray(r.team, index)

proc writeSlot*(w: World, r: Robot, index, value: int): bool
    {.discardable.} =
  if not r.spend(1): return false
  w.writeSharedArray(r, index, max(0, min(value, MaxSharedArrayValue)))
