## `california-roll` — the strong published doctrine and the champion chassis.
##
## Behaviour ported from `StoneT2000/Battlecode2021` `src/maxecosushi/`
## (AGPL-3.0, commit 5c2a7ee), with the muck-spam opening from
## `iliao2345/Battlecode2021` `src/muckspam/` and `src/membrane3/` (AGPL-3.0,
## commit d620569) and the multi-Center flag protocol from
## `BSreenivas0713/Battlecode2021` `src/musketeerplayerfinal/` (AGPL-3.0,
## commit d24af14). BEHAVIOUR, NOT CODE: rewritten in Nim and parameterised by
## this coworld's ten-knob doctrine sheet.
##
## This file is only the dispatcher. Every role is its own module, and the one
## rule that spans them all is D2's: the chassis always builds, always defends
## its own Centers, always paths, and always ends its games, whatever the
## knobs say.
##
## `-d:bc21BrokenChassis` compiles the DELIBERATELY BROKEN control the survival
## gate inverts against (`tests/test_bc21_survival.nim`): a chassis that stops
## building after round 50. A gate that cannot fail is not a gate.

import kit, ec, politician, slanderer, muckraker

export kit

proc runCaliforniaRoll*(w: World, side: Side, r: Robot) =
  when defined(bc21BrokenChassis):
    if w.currentRound > 50 and r.kind == rtEnlightenmentCenter:
      ## The inverted control: the Center stops building (and stops bidding)
      ## after round 50 and just sits there.
      setFlag(r, encodeFlag(fkSilent, r.loc))
      return
  case r.kind
  of rtEnlightenmentCenter: runEnlightenmentCenter(w, side, r)
  of rtPolitician: runPolitician(w, side, r)
  of rtSlanderer: runSlanderer(w, side, r)
  of rtMuckraker: runMuckraker(w, side, r)
