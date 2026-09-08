## `lemonade`'s build plan and the ONE place a resource is ever committed.
##
## Behaviour ported from `awesomelemonade/Battlecode2023` `src/finalBot/`
## (AGPL-3.0) — the headquarters build order and the carrier floor —
## parameterised by `opening`, `launcher_ratio` and `anchor_budget`.
##
## THE ANTI-INERT FLOOR IS HERE AND IT IS UNCONDITIONAL: `carrierFloor()` is
## at least `CarrierFloorPerHq` (3) carriers per headquarters at EVERY knob
## setting, and `launcher_ratio` is clamped to 20…80 by `knobs.nim`, so no
## doctrine can express "no launchers" or "no economy".

import ../world, kit

export kit

func carrierFloor*(side: Side): int =
  ## Carriers per headquarters, and never below the unconditional floor.
  let perHq =
    case side.doctrine.opening
    of opLauncherRush: 3
    of opCarrierEco: 6
    of opBalanced: 4
  max(CarrierFloorPerHq, perHq) * max(1, side.hqCount)

func launcherTarget*(w: World, side: Side): int =
  ## The launcher census the faction is building toward. `carrier_eco` HALVES
  ## it, never zeroes it (the anti-inert rule); `launcher_rush` doubles it and
  ## puts every kilogram of mana into it.
  let base = 4 + w.currentRound div 120 + side.enemyLaunchers
  case side.doctrine.opening
  of opLauncherRush:
    if w.currentRound <= 400: base * 2 else: base + 4
  of opCarrierEco:
    if w.currentRound <= 400: max(2, base div 2) else: base
  of opBalanced: base

func anchorReserve*(w: World, side: Side, resource: Resource): int =
  ## `budget()`: the stockpile a headquarters keeps back for the anchor
  ## programme, as a share of the 80 Ad + 80 Mn a standard anchor costs.
  ##
  ## IT IS ZERO BEFORE `anchor_round`. Reserving against a purchase the
  ## doctrine has not scheduled yet is exactly how a faction starves itself
  ## in the opening, and the anti-inert rule forbids it.
  ##
  ## UNTIL THE FIRST ANCHOR IS PLACED THE RESERVE IS THE WHOLE 80. A
  ## percentage reserve cannot accumulate a purchase that costs more than a
  ## launcher: measured, a faction reserving 28 mana against a 45-mana
  ## launcher never reached 80 and never anchored an island in an
  ## 800-round game. Once the programme is running the reserve falls back to
  ## the doctrine's own share, so `anchor_budget` still moves how MANY
  ## anchors get built.
  if side.doctrine.anchorBudget <= 0: 0
  elif w.currentRound < side.doctrine.anchorRound: 0
  else:
    let full = AnchorSpecs[anStandard].adamantiumCost
    case resource
    of resAdamantium, resMana:
      if w.stats.totalAnchorsPlaced[ord(side.team)] == 0: full
      else: full * side.doctrine.anchorBudget div 100
    else: 0

proc plan*(w: World, side: Side) =
  ## Refresh everything a build decision reads. Called once a round from the
  ## dispatcher, never inside a robot's turn.
  w.refreshCensus(side)

func nextBuild*(w: World, side: Side, hq: Robot): RobotType =
  ## The unit this headquarters should build now, or `rtHeadquarters` for
  ## "nothing this action". The carrier floor is unconditional; past it,
  ## `launcher_ratio` decides what share of the BUILD DECISIONS resolve to a
  ## launcher.
  let d = side.doctrine
  ## THE ANCHOR RESERVE APPLIES TO EVERY PATH except true starvation. A
  ## reserve the carrier floor and the duel both bypass is not a reserve:
  ## measured, a faction whose carriers die every round rebuilt them out of
  ## the anchor's 80 adamantium for two thousand rounds and never anchored an
  ## island. `starving` is the one exemption, and it is what keeps the
  ## anti-inert rule true.
  let starving = side.carriers == 0 or side.launchers == 0
  let keepAd = if starving: 0 else: anchorReserve(w, side, resAdamantium)
  let keepMn = if starving: 0 else: anchorReserve(w, side, resMana)
  let freeAd = hq.adamantium - keepAd
  let freeMn = hq.mana - keepMn

  ## 1. The floor: carriers, always, before anything else.
  if side.carriers < side.carrierFloor():
    if freeAd >= buildCost(rtCarrier, resAdamantium): return rtCarrier
  ## 2. An amplifier, if the doctrine wants one and we are short.
  let ampTarget =
    case d.amplifierUse
    of auNever: 0
    of auOne: max(1, side.hqCount)
    of auEscort: max(1, side.launchers div 4)
  ## The amplifier is bought only once the duel is answered: an amplifier
  ## that shares targets for a faction with no launchers shares nothing.
  if side.amplifiers < ampTarget and side.launchers >= 2 and
      freeAd >= buildCost(rtAmplifier, resAdamantium) and
      freeMn >= buildCost(rtAmplifier, resMana) + 45:
    return rtAmplifier
  ## 3. The elixir sink, once elixir actually flows.
  if hq.elixir > 0:
    case d.elixirSpend
    of esDestabilizers:
      if hq.elixir >= buildCost(rtDestabilizer, resElixir):
        return rtDestabilizer
    of esBoosters:
      if hq.elixir >= buildCost(rtBooster, resElixir):
        return rtBooster
    of esAcceleratingAnchors:
      discard  ## handled by `anchors.nim`, which builds the anchor itself
  ## 4. The duel. `launcher_ratio` is a share of build DECISIONS, resolved
  ##    against a deterministic per-headquarters counter rather than an RNG,
  ##    because this sim has no randomness a chassis may reach.
  let slot = (w.currentRound + hq.id) mod 100
  var wantsLauncher = slot < d.launcherRatio
  ## THE ANTI-INERT CLAUSE, and the one that decides this year: a faction
  ## whose launcher census has fallen below two, or below the enemy's, answers
  ## the duel WHATEVER `launcher_ratio` says. Refusing to rebuild the only
  ## unit in the game that deals real damage is not a doctrine, it is a
  ## forfeit — and the 2023 metagame is exactly that snowball.
  if side.launchers < 2: wantsLauncher = true
  if wantsLauncher and side.launchers < launcherTarget(w, side) and
      freeMn >= buildCost(rtLauncher, resMana):
    return rtLauncher
  if freeAd >= buildCost(rtCarrier, resAdamantium):
    return rtCarrier
  if freeMn >= buildCost(rtLauncher, resMana) and
      side.launchers < launcherTarget(w, side):
    return rtLauncher
  rtHeadquarters
