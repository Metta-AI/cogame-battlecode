## `saber`'s lattice: what the order builds on the mirror line.
##
## Behaviour source: `m-schier/battlecode-2019-wololo@ebdd279`,
## `robot.js:97-131` (`LATTICE_DENSE`, `LATTICE_INTERWEAVE`), GPL-3.0.
##
## Both sides know the mirror line from round 1, because every robot is
## handed the whole terrain map on its first turn (`game.js:728-730`). The
## shortest line between the two orders is therefore public, and whoever
## fortifies it first owns the midline — which is why `symmetry_wall` is a
## knob and not a constant.
##
## `screen` occupies EVERY OTHER square, so pilgrims still pass and a
## preacher blast can only catch one prophet. `wall` is dense, which stops
## crusaders cold and also BLOCKS YOUR OWN PILGRIMS and turns one enemy
## preacher shot into three dead prophets. The trade-off is the point.

import ../constants, ../units, ../world, ../knobs
import kit

export kit

proc buildLatticeSlots*(w: World, s: Side) =
  ## The own-half side of the mirror line, at the lattice's parity. Computed
  ## once per game and cached on the `Side`.
  if s.latticeSlots.len > 0: return
  if s.doctrine.symmetryWall == sw19Off: return
  let dense = s.doctrine.symmetryWall == sw19Wall
  if w.map.symmetryHorizontal:
    ## Mirrored across the VERTICAL midline: the line is a COLUMN.
    let mid = w.width div 2
    let col = (if s.team == tRed: max(0, mid - 3) else: min(w.width - 1, mid + 2))
    for y in 0 ..< w.height:
      if not w.isPassable(col, y): continue
      if not dense and (y and 1) == 1: continue
      s.latticeSlots.add(Loc(x: col, y: y))
  else:
    let mid = w.height div 2
    let row = (if s.team == tRed: max(0, mid - 3) else: min(w.height - 1, mid + 2))
    for x in 0 ..< w.width:
      if not w.isPassable(x, row): continue
      if not dense and (x and 1) == 1: continue
      s.latticeSlots.add(Loc(x: x, y: row))

proc claimLatticeSlot*(w: World, s: Side, r: Robot): tuple[ok: bool, x, y: int] =
  ## The nearest unclaimed slot. A unit that holds one stands on it and does
  ## not wander, which is what makes the line a line.
  result = (ok: false, x: 0, y: 0)
  buildLatticeSlots(w, s)
  if s.latticeSlots.len == 0: return
  if r.latticeSlot >= 0 and r.latticeSlot < s.latticeSlots.len:
    let l = s.latticeSlots[r.latticeSlot]
    return (ok: true, x: l.x, y: l.y)
  if not r.charge(s.latticeSlots.len): return
  var best = high(int)
  var pick = -1
  for i in 0 ..< s.latticeSlots.len:
    let holder = s.latticeTaken.getOrDefault(i, 0)
    if holder != 0 and holder != r.id:
      let h = w.getItem(holder)
      if not h.isNil and h.team == s.team: continue
    let d = distSq(s.latticeSlots[i].x, s.latticeSlots[i].y, r.x, r.y)
    if d < best:
      best = d
      pick = i
  if pick < 0: return
  s.latticeTaken[pick] = r.id
  r.latticeSlot = pick
  result = (ok: true, x: s.latticeSlots[pick].x,
            y: s.latticeSlots[pick].y)

func latticeWanted*(s: Side): bool = s.doctrine.symmetryWall != sw19Off
