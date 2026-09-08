## `lemonade` — the strong baseline, the champion chassis, and the turn
## dispatcher.
##
## Behaviour ported from `awesomelemonade/Battlecode2023` `src/finalBot/`
## (AGPL-3.0, head `2e231f31`, the 1st-place bot "Producing Perfection"), with
## the elixir programme from `vrangr1/BattleCode2023` `src/AFinalsBot/`
## (AGPL-3.0, head `244af40e`) and the shared-array layout and symmetry
## guesser from `jmerle/battlecode-2023` `src/camel_case_v30_final/util/`
## (MIT, head `e776fcb2`). BEHAVIOUR, NOT CODE — rewritten in Nim and
## parameterised by the twelve knobs. `NOTICE` names every file.
##
## This module is the dispatcher only: one arm per robot type, plus the
## once-a-round bookkeeping the whole faction shares.

import ../world, kit, econ, hq, carrier, launcher, micro, elixir

export kit

proc beginRound*(w: World, side: Side) =
  ## Once a round, before any robot of this faction takes its turn.
  w.observeHome(side)
  plan(w, side)
  updateStrikeCentre(w, side)
  noteLosses(w, side)
  if elixirRunning(w, side):
    chooseTarget(w, side)

proc runLemonade*(w: World, side: Side, r: Robot) =
  case r.kind
  of rtHeadquarters: runHeadquarters(w, side, r)
  of rtCarrier: runCarrier(w, side, r)
  of rtLauncher: runLauncher(w, side, r)
  of rtDestabilizer: runDestabilizer(w, side, r)
  of rtBooster: runBooster(w, side, r)
  of rtAmplifier: runAmplifier(w, side, r)
