## `spaark` — the strong baseline, the champion chassis, and the ONE competent
## chassis the whole doctrine surface lives inside.
##
## Behaviour ported from `erikji/battlecode25` `src/SPAARK/` (AGPL-3.0, head
## `63165da`; the High-School 1st-place bot, whose `SPAARK` directory is the
## final submission), with the mopper and splasher micro from
## `ecoArcGaming/battlecode25` `java/src/v3/` (AGPL-3.0, branch `newMopper`,
## head `8f17e87`; the Novice 2nd-place bot) — all parameterised by the ten
## knobs. BEHAVIOUR, NOT CODE: nothing upstream is vendored, compiled or read
## into any file here, and `NOTICE` names exactly which behaviour derives from
## which repository.
##
## This file is only the turn dispatcher. Everything it dispatches to is in
## `kit.nim`, `econ.nim`, `tower.nim`, `soldier.nim`, `splasher.nim`,
## `mopper.nim`, `siege.nim` and `comms.nim`.
##
## `-d:bc25BrokenChassis` compiles the NEGATIVE CONTROL for the competence
## gate: a variant whose soldiers stop painting the tile under themselves, so
## the clan bleeds paint on neutral ground and starves.
## `tests/test_bc25_survival.nim` runs the gate against it as a subprocess and
## REQUIRES IT TO COME BACK RED. A gate that cannot fail is not a gate.

import kit, econ, siege, tower, soldier, splasher, mopper
import comms as chassiscomms

export kit, econ, siege, tower, soldier, splasher, mopper

proc runSpaark*(w: World, side: Side, r: Robot) =
  observeHome(w, side)
  measureChokes(w, side)
  refreshCensus(w, side)
  noteTowerLoss(w, side)

  if r.kind.isTowerType():
    runTower(w, side, r)
    return

  ## An upgrade is free of cooldown and paint, so it is taken before the
  ## turn's action rather than instead of it.
  let up = upgradePick(w, side, r)
  if up.x >= 0 and w.canUpgradeTower(r, up):
    w.doUpgradeTower(r, up)

  when defined(bc25BrokenChassis):
    ## THE NEGATIVE CONTROL. Soldiers never paint the ground they stand on, so
    ## every turn on neutral or enemy colour costs paint the clan never earns
    ## back. Compiled only under `-d:bc25BrokenChassis`; the competence gate
    ## asserts this variant FAILS.
    if r.kind == utSoldier:
      w.stepToward(side, r, frontierFor(w, side))
      chassiscomms.soldierReport(w, side, r)
      return

  case r.kind
  of utSoldier: runSoldier(w, side, r)
  of utSplasher: runSplasher(w, side, r)
  of utMopper: runMopper(w, side, r)
  else: discard

  chassiscomms.soldierReport(w, side, r)
