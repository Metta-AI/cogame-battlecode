## The `awu` chassis: a distilled awubot (github.com/awu7/battlecode-2026,
## branch `final`, AGPL-3.0 — credited in NOTICE). Behaviour, not code:
## miner/skirmisher roles, king spawn thresholding, trap laying, dirt shells,
## formation upgrades, squeak-shared mine locations.
##
## Every one of the eleven doctrine knobs reaches play through this file or
## one of the modules it calls, and `tests/test_knob_sensitivity.nim` proves
## each of them changes a named, signed statistic.

import kit, king, rat

proc runAwu*(w: World, clan: Clan, r: Robot) =
  case r.unit
  of utRatKing: runKing(w, clan, r)
  of utBabyRat: runRat(w, clan, r)
  of utCat: discard
