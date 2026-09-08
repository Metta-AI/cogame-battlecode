## The bc23 time-bending layer: per-tile, per-team cooldown multipliers.
##
## A behaviour port of the `boosts` / `cooldownMultipliers` machinery in
## `world/GameWorld.java` (`addBoost`, `addDestabilize`, `addBoostFromAnchor`,
## `removeBoostFromAnchor` and the expiry half of `processEndOfRound`) at
## commit `af42086ecd09709dc603b2aaa9e9b98312c9ef79`.
##
## THE MULTIPLIER IS STORED IN INTEGER HUNDREDTHS. The engine keeps a `double`
## and re-quantises it with `Math.round(x*100.0)/100.0` after EVERY change, so
## over the whole reachable range (`1.00` + cloud `0.20` − `0.10` per boost
## stack + `0.10` per destabilise stack − `0.15` per accelerating anchor) the
## value is exactly a hundredth and the ladder is bit-identical. The
## APPLICATION stays in float64 — see `units.applyMultiplier`.
##
## THE STACK GUARDS ARE ASYMMETRIC AND THE PORT KEEPS THEM. `addBoost` adjusts
## the multiplier only when the tile's list is **shorter than**
## `MAX_BOOST_STACKS`, while the expiry sweep adjusts it when the list is **at
## most** `MAX_BOOST_STACKS`, each evaluated against the list size at that
## moment. Over the life of a tile the two balance; a clamped counter would
## drift on a tile that ever exceeded the cap
## (docs/RULES-BC23.md §Divergences, prose item 5).

import units

export units

type
  TempoField* = object
    ## Indices are `[tile][team]`, exactly as `GameWorld.boosts` is
    ## `[map position][team][boost|destabilize|anchor]`.
    hundredths*: array[2, seq[int]]
    boosts*: array[2, seq[seq[int]]]
      ## The rounds each boost on that tile expires at, in push order.
    destabilizes*: array[2, seq[seq[int]]]
    anchors*: array[2, seq[seq[int]]]
      ## The ISLAND IDS of the accelerating anchors covering that tile; the
      ## engine stores the island id so `removeBoostFromAnchor` can remove by
      ## value.

proc initTempoField*(size: int): TempoField =
  for t in 0 .. 1:
    result.hundredths[t] = newSeq[int](size)
    for i in 0 ..< size:
      result.hundredths[t][i] = BaseMultiplier
    result.boosts[t] = newSeq[seq[int]](size)
    result.destabilizes[t] = newSeq[seq[int]](size)
    result.anchors[t] = newSeq[seq[int]](size)

func multiplier*(f: TempoField, i: int, t: Team): int =
  f.hundredths[ord(t)][i]

proc bakeCloud*(f: var TempoField, i: int) =
  ## `GameWorld`'s constructor adds `CLOUD_MULTIPLIER` to BOTH teams on every
  ## cloud tile, once, at world construction. A cloud is never created or
  ## destroyed during a game, so this is the only place it is applied.
  for t in 0 .. 1:
    f.hundredths[t][i] += CloudHundredths

proc addBoost*(f: var TempoField, i: int, t: Team, lastRound: int) =
  ## `GameWorld.addBoost`, per tile.
  let o = ord(t)
  if f.boosts[o][i].len < MaxBoostStacks:
    f.hundredths[o][i] += BoostHundredths
  f.boosts[o][i].add(lastRound)

proc addDestabilize*(f: var TempoField, i: int, victim: Team,
                     lastRound: int) =
  ## `GameWorld.addDestabilize`, per tile. NOTE the team: the engine pushes
  ## onto `team.opponent()`'s list — `victim` here is already that opponent.
  let o = ord(victim)
  if f.destabilizes[o][i].len < MaxDestabilizeStacks:
    f.hundredths[o][i] += DestabilizeHundredths
  f.destabilizes[o][i].add(lastRound)

proc addAnchorBoost*(f: var TempoField, i: int, t: Team, islandId: int) =
  ## `GameWorld.addBoostFromAnchor`, per tile.
  let o = ord(t)
  if f.anchors[o][i].len < MaxAnchorStacks:
    f.hundredths[o][i] += AnchorHundredths
  f.anchors[o][i].add(islandId)

proc removeAnchorBoost*(f: var TempoField, i: int, t: Team, islandId: int) =
  ## `GameWorld.removeBoostFromAnchor`, per tile: `<=` on the size, and the
  ## removal is BY VALUE (`ArrayList.remove(Integer)` removes the FIRST entry
  ## equal to the island id, or nothing at all).
  let o = ord(t)
  if f.anchors[o][i].len <= MaxAnchorStacks:
    f.hundredths[o][i] -= AnchorHundredths
  for k in 0 ..< f.anchors[o][i].len:
    if f.anchors[o][i][k] == islandId:
      f.anchors[o][i].delete(k)
      break

proc expireBoosts*(f: var TempoField, i: int, t: Team, round: int) =
  ## The boost half of `processEndOfRound`: scan the list FROM THE BACK and
  ## drop every entry `<= round + 1`, adjusting the multiplier under the
  ## asymmetric `<=` guard against the size AT THAT MOMENT.
  let o = ord(t)
  var j = f.boosts[o][i].len - 1
  while j >= 0:
    if f.boosts[o][i][j] <= round + 1:
      if f.boosts[o][i].len <= MaxBoostStacks:
        f.hundredths[o][i] -= BoostHundredths
      f.boosts[o][i].delete(j)
    dec j

proc expireDestabilizes*(f: var TempoField, i: int, t: Team,
                         round: int): int =
  ## The destabilise half. Returns HOW MANY entries expired on this tile for
  ## this team, because each one deals `RobotType.DESTABILIZER.damage` to
  ## whatever robot of that team is standing there — so a robot can be hit
  ## twice in one round if two entries expire together.
  let o = ord(t)
  var j = f.destabilizes[o][i].len - 1
  while j >= 0:
    if f.destabilizes[o][i][j] <= round + 1:
      result += 1
      if f.destabilizes[o][i].len <= MaxDestabilizeStacks:
        f.hundredths[o][i] -= DestabilizeHundredths
      f.destabilizes[o][i].delete(j)
    dec j

func checksum*(f: TempoField, width, height: int): uint64 =
  ## An FNV-1a 64 over the per-tile per-team multiplier hundredths, y
  ## ascending outer and x ascending inner — the `M` line of the parity trace,
  ## which is what makes a single wrong tempo tile visible without printing
  ## 3 600 tiles a round.
  result = 0xCBF29CE484222325'u64
  for y in 0 ..< height:
    for x in 0 ..< width:
      let i = x + y * width
      for t in 0 .. 1:
        result = (result xor uint64(f.hundredths[t][i] and 0xFFFF)) *
          0x100000001B3'u64
