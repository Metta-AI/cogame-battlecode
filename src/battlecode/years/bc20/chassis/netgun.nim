## The Net Gun: shoot the closest enemy drone within `r² <= 15`, preferring one
## that is CARRYING a unit — the carried unit dies with it if the drop would
## have been over water.
##
## Behaviour, not code, from `StoneT2000/Battlecode2020` (AGPL-3.0; see NOTICE).

import kit, hq

proc runNetGun*(w: World, side: Side, r: Robot) =
  let brain = side.brainFor(r)
  brain.turnCount += 1
  discard w.shootNearestDrone(side, r)
