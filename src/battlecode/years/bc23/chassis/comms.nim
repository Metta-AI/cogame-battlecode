## `lemonade`'s 64-slot shared-array layout.
##
## Behaviour ported from `jmerle/battlecode-2023`
## `src/camel_case_v30_final/util/SharedArray.java` (MIT, head `e776fcb2`) and
## the `Comms` slot discipline of `vrangr1/BattleCode2023` `src/AFinalsBot/`
## (AGPL-3.0, head `244af40e`). BEHAVIOUR, NOT CODE.
##
## Sixteen bits a slot, and the layout is the CHASSIS's — a doctrine cannot
## redefine it (§Out of scope). `amplifier_use` steers WHO CAN SPEAK, not the
## encoding.
##
##   slots  0- 3  our headquarters      x:6 y:6 flags:4
##   slots  4-15  known wells           x:6 y:6 type:2 upgraded:1 taken:1
##   slots 16-27  islands               id:6 owner:2 healthBucket:4 claimed:1
##   slots 28-35  enemy sightings       x:6 y:6 age:4
##   slots 36-39  the elixir target     x:6 y:6 progressBucket:4
##   slots 40-47  rally points          x:6 y:6
##   slots 48-55  anchor claims         island:6 carrier:9 flag:1
##   slots 56-63  the per-type census   count:16
##
## A slot is written only by a robot inside a write window (`comms.nim` in the
## sim module owns that predicate) and every write is charged one
## `DecisionOps` credit.

import ../world, ../comms as simcomms, kit

export kit

const
  SlotHqBase* = 0
  SlotWellBase* = 4
  SlotIslandBase* = 16
  SlotSightingBase* = 28
  SlotElixirBase* = 36
  SlotRallyBase* = 40
  SlotAnchorClaimBase* = 48
  SlotCensusBase* = 56

func packLoc*(l: Loc): int =
  ## `x:6 y:6` — every 2023 map is at most 60x60, so six bits is exact.
  ((l.x and 0x3F) shl 6) or (l.y and 0x3F)

func unpackLoc*(v: int): Loc =
  loc((v shr 6) and 0x3F, v and 0x3F)

func packWell*(l: Loc, kind: Resource, upgraded, taken: bool): int =
  (packLoc(l) shl 4) or ((ord(kind) and 0x3) shl 2) or
    (if upgraded: 2 else: 0) or (if taken: 1 else: 0)

func packIsland*(id, owner, healthBucket: int, claimed: bool): int =
  ((id and 0x3F) shl 7) or ((owner and 0x3) shl 5) or
    ((healthBucket and 0xF) shl 1) or (if claimed: 1 else: 0)

func packSighting*(l: Loc, age: int): int =
  (packLoc(l) shl 4) or (age and 0xF)

func packAnchorClaim*(islandIdx, carrierId: int): int =
  ((islandIdx and 0x3F) shl 9) or ((carrierId and 0x1FF) shl 0)

proc writeSlot*(w: World, side: Side, r: Robot, index,
                value: int): bool {.discardable.} =
  ## One credit per write, then the sim's own window test. Reading is free of
  ## the window and costs one credit too.
  if not r.spend(1): return false
  simcomms.doWriteSharedArray(w, r, index, value and MaxSharedArrayValue)

proc readSlot*(w: World, side: Side, r: Robot, index: int): int =
  discard r.spend(1)
  simcomms.readSharedArray(w, side.team, index)

func canWriteSharedArrayFor*(w: World, r: Robot): bool =
  simcomms.canWriteSharedArray(w, r, 0, 0)

proc publish*(w: World, side: Side, r: Robot) =
  ## What a robot inside a write window says. A headquarters publishes its own
  ## position, the census and the anchor claims; anybody else publishes the
  ## most recent enemy sighting and whatever well or island it has just
  ## learned. Every write is bounded — at most four a turn — so the shared
  ## array is never a per-round dump.
  if not simcomms.canWriteSharedArray(w, r, 0, 0): return
  var writes = 0
  if r.kind == rtHeadquarters:
    ## A HEADQUARTERS PUBLISHES ON A CADENCE, not every round. It can always
    ## write, so publishing every round drowns out every other writer and
    ## `amplifier_use` loses its teeth on `array_writes` — which is the one
    ## statistic that knob actually buys.
    if w.currentRound mod 10 != 0: return
    for k in 0 ..< min(4, side.homeHqs.len):
      if writes >= 4: break
      discard w.writeSlot(side, r, SlotHqBase + k, packLoc(side.homeHqs[k]))
      writes += 1
    if writes < 4:
      discard w.writeSlot(side, r, SlotCensusBase, side.carriers)
      writes += 1
    if writes < 4:
      discard w.writeSlot(side, r, SlotCensusBase + 1, side.launchers)
      writes += 1
  else:
    if side.lastSightingRound == w.currentRound:
      discard w.writeSlot(side, r, SlotSightingBase,
        packSighting(side.lastSighting, 0))
      writes += 1
    if writes < 2 and side.knownWells.len > 0:
      let l = side.knownWells[side.knownWells.len - 1]
      discard w.writeSlot(side, r, SlotWellBase,
        packWell(l, w.wellAtLoc(l).kind, w.wellAtLoc(l).upgraded, false))
      writes += 1
