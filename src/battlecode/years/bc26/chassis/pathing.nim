## Movement: how a rat gets from where it is to where its role wants it.
##
## Charged against the robot's DECISION BUDGET (`kit.spend`) so a turn costs
## a bounded, machine-independent number of credits no matter the map — the
## replacement for the engine's bytecode meter.

import kit

proc stepToward*(w: World, clan: Clan, r: Robot, target: Loc): Dir =
  ## A greedy step with two sidesteps. Cheap on purpose: a rat's whole turn
  ## must fit inside `DecisionOpsBabyRat` credits, and the expensive exact
  ## path is the cats' business, not the rats'.
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
  if not r.spend(6): return dCenter
  ## Fully blocked: try the remaining directions in a stable order so the
  ## same world always produces the same escape.
  for d in NonCenterDirs:
    if w.canMove(r, d): return d
  dCenter

proc moveOrTurn*(w: World, clan: Clan, r: Robot, target: Loc) =
  ## Move toward `target` if the mover is ready, else spend the turn facing
  ## the right way — turning is on its own cooldown, so a rat that cannot
  ## step can still be pointed at the thing it is about to do.
  let d = stepToward(w, clan, r, target)
  if d != dCenter and w.canMove(r, d):
    w.move(r, d)
    return
  if w.canTurn(r):
    let want = r.loc.directionTo(target)
    if want != dCenter and want != r.dir:
      w.turn(r, want)
