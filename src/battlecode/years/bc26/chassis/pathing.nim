## Movement: how a rat gets from where it is to where its role wants it.
##
## Charged against the robot's DECISION BUDGET (`kit.spend`) so a turn costs
## a bounded, machine-independent number of credits no matter the map — the
## replacement for the engine's bytecode meter.

import kit

proc stepToward*(w: World, clan: Clan, r: Robot, target: Loc): Dir =
  ## A greedy step with two sidesteps, then the world's own BFS. Greedy is
  ## tried first because it is cheap and right most of the time; the BFS is
  ## what gets a miner through a maze. Without it the rats on `closeup` left
  ## 11 500 cheese lying on the map while their kings starved (r2-D2) —
  ## a distilled awubot is supposed to path, and the note says so.
  if not r.spend(4): return dCenter
  let straight = r.loc.directionTo(target)
  if straight == dCenter: return dCenter
  if w.canMove(r, straight): return straight
  if not r.spend(4): return dCenter
  let left = straight.rotateLeft()
  if w.canMove(r, left): return left
  if not r.spend(4): return dCenter
  let right = straight.rotateRight()
  if w.canMove(r, right): return right
  if not r.spend(25): return dCenter
  ## The same BFS the cats use (`GameWorld.getBfsDir`), cached per target
  ## tile: it routes around walls, which no amount of sidestepping does.
  let bfs = w.getBfsDir(r.loc, target, r.chirality)
  if bfs != dCenter and w.canMove(r, bfs): return bfs
  if not r.spend(6): return dCenter
  ## Fully blocked: try the remaining directions in a stable order so the
  ## same world always produces the same escape.
  for d in NonCenterDirs:
    if w.canMove(r, d): return d
  dCenter

proc digThrough(w: World, clan: Clan, r: Robot, target: Loc): bool =
  ## A rat with no legal step is not stuck, it is standing in front of a
  ## shovel's worth of work: dirt is passable ground once dug. `closeup`
  ## starts both clans in a corner packed with the map's own dirt, and without
  ## this the whole clan is entombed — two rats filling the king's only two
  ## doorways, a king that can no longer build, no cheese, no cat damage and
  ## both crowns starved by round 1295 (r2-D2).
  if not r.canActCooldown: return false
  if not r.spend(4): return false
  let want = r.loc.directionTo(target)
  if want != dCenter:
    let ahead = r.loc + want
    if w.getDirt(ahead) and w.canRemoveDirt(r, ahead):
      w.removeDirt(r, ahead)
      return true
  for d in NonCenterDirs:
    if not r.spend(1): break
    let spot = r.loc + d
    if w.getDirt(spot) and w.canRemoveDirt(r, spot):
      w.removeDirt(r, spot)
      return true
  false

proc moveOrTurn*(w: World, clan: Clan, r: Robot, target: Loc) =
  ## Move toward `target` if the mover is ready, else spend the turn facing
  ## the right way — turning is on its own cooldown, so a rat that cannot
  ## step can still be pointed at the thing it is about to do.
  let d = stepToward(w, clan, r, target)
  if d != dCenter and w.canMove(r, d):
    w.move(r, d)
    return
  if r.canMoveCooldown and digThrough(w, clan, r, target):
    return
  if w.canTurn(r):
    let want = r.loc.directionTo(target)
    if want != dCenter and want != r.dir:
      w.turn(r, want)
