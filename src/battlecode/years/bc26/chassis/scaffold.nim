## The `scaffold` chassis: `example-bots/src/main/examplefuncsplayer`, ported
## statement for statement.
##
##     if (rc.canMoveForward()) rc.moveForward();
##     else { int d = rng.nextInt(8); if (rc.canTurn()) rc.turn(directions[d]); }
##
## That is the WHOLE bot, and the fidelity is the point: `parity-oracle` runs
## the Java engine driving the real examplefuncsplayer against itself and
## diffs it row for row against this (docs/PARITY.md). A "helpful" addition
## here — picking up cheese, biting a neighbour — would break the only test
## that proves the ported rule set is the same rule set.
##
## `rng` is `new Random(6147)` PER ROBOT: Battlecode gives every robot its own
## class loader, so the bot's `static final` field is not shared. `kit.Brain`
## reproduces that.

import kit

const Directions = [dNorth, dNortheast, dEast, dSoutheast,
                    dSouth, dSouthwest, dWest, dNorthwest]
  ## `examplefuncsplayer.RobotPlayer.directions`, in its own order — the
  ## random index means the order is part of the behaviour.

proc runScaffold*(w: World, clan: Clan, r: Robot) =
  if r.unit == utCat: return
  let brain = clan.brainFor(r)
  brain.turnCount += 1
  if w.canMove(r, r.dir):
    w.move(r, r.dir)
  else:
    let randomDirection = int(brain.rng.nextInt(8))
    if w.canTurn(r):
      w.turn(r, Directions[randomDirection])
