## `wololo` — the strong baseline and the champion chassis: the turn dispatcher.
##
## Behaviour ported from the BEHAVIOUR of three licensed bots and nothing else:
##
## * `iliao2345/Battlecode2022` `src/fury_fix_20/` (AGPL-3.0, head `c42645a0`;
##   the 1st-place bot "wololo", whose `fury_fix_20` directory is the
##   highest-numbered and therefore final iteration) — the rubble-weighted
##   navigator, the miner's `mine_until` floor and its mine-move-mine turn
##   shape, the archon's build-rate model with its saturation caps and its
##   20-round miner-employment ring buffer, the archon repair priority, the
##   soldier and sage micro with the sage's advance gate, and the pre-vortex
##   archon relocation;
## * `BSreenivas0713/Battlecode2022` `src/MPTempName/` (AGPL-3.0, head
##   `c388fe8a`) — the laboratory and builder programme and the mutation
##   ladder's marginal-value ordering;
## * `jmerle/battlecode-2022` `src/camel_case_v25_final/` (MIT, head `f57d3549`)
##   — the 64-slot shared-array layout and the per-radius navigators.
##
## **`IvanGeffner/BC22` was not cloned, not read and contributes nothing**: it
## carries no licence anywhere. `5 Musketeers` is not published on GitHub and
## likewise contributes nothing.
##
## BEHAVIOUR, NOT CODE — every line here is Nim written against this coworld's
## own `World`, and every strategic choice is parameterised by the eleven-knob
## doctrine sheet. `NOTICE` names each source file and what derives from it.

import kit, econ, archon, miner, builder, soldier, lab
import anomaly as chassisAnomaly

export kit

proc beginRound*(w: World, side: Side) =
  ## The chassis's round-level bookkeeping, run BEFORE the exec sweep so every
  ## robot this round reads the same census and the same anomaly programme.
  w.ensureMemory(side)
  w.observeHome(side)
  w.refreshCensus(side)
  planAnomaly(w, side)
  if side.labsLive > 0:
    w.stats.roundsWithALab[ord(side.team)] += 1

proc runWololo*(w: World, side: Side, r: Robot) =
  r.minedThisTurn = false
  case r.kind
  of rtArchon: runArchon(w, side, r)
  of rtMiner: runMiner(w, side, r)
  of rtBuilder: runBuilder(w, side, r)
  of rtSoldier: runSoldier(w, side, r)
  of rtSage: runSage(w, side, r)
  of rtLaboratory: runLaboratory(w, side, r)
  of rtWatchtower: runWatchtower(w, side, r)
