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

func carrierCap*(w: World, side: Side): int =
  ## The census past which the faction stops spending SPARE adamantium on
  ## carriers. `launcher_ratio` moves it, so the knob has teeth on the carrier
  ## count and not only on the launcher count — and it can never fall below
  ## the unconditional floor.
  ##
  ## IT GROWS WITH THE ROUND, because the economy does: a fixed cap froze the
  ## fleet at eight carriers for two thousand rounds and the competence gate's
  ## "built at least twelve" floor could never be met.
  max(side.carrierFloor(),
      side.carrierFloor() * (160 - side.doctrine.launcherRatio) div 40 +
        w.currentRound div 150)

func launcherTarget*(w: World, side: Side): int =
  ## The launcher census the faction is building toward. `launcher_ratio`
  ## scales it around its own default of 45, so 20 asks for well under half
  ## and 80 for well over one and a half — which is what gives the knob teeth
  ## on the census as well as on the build stream. `carrier_eco` HALVES it,
  ## never zeroes it (the anti-inert rule); `launcher_rush` doubles it.
  let base = (4 + w.currentRound div 120 + side.enemyLaunchers) *
    side.doctrine.launcherRatio div 45
  case side.doctrine.opening
  of opLauncherRush:
    if w.currentRound <= 400: base * 2 else: base + 4
  of opCarrierEco:
    ## A QUARTER, not a half, for the first four hundred rounds — and never
    ## below two, which is the anti-inert floor. Measured: at a half the
    ## opening knob moved `launchers_built_by_400` by 21 %, well under the
    ## note's 60 %, because the initial 200 mana and the passive income
    ## dominate the first four hundred rounds on a one-headquarters map.
    if w.currentRound <= 400: max(2, base div 4) else: base
  of opBalanced: base

func openingCarrierBias*(side: Side): int =
  ## `carrier_eco` buys carriers early and `launcher_rush` does not, which is
  ## the delta `tests/test_bc23_knobs.nim` measures by round 400.
  case side.doctrine.opening
  of opCarrierEco: 2
  of opLauncherRush: 0
  of opBalanced: 1

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

  ## 1. THE ELIXIR SINK GOES FIRST, once elixir has actually reached this
  ##    headquarters' own stockpile. The doctrine paid 600 kg of the wrong
  ##    resource and a well's whole output for it; spending it behind the
  ##    carrier floor means never spending it at all.
  if hq.elixir > 0:
    case d.elixirSpend
    of esDestabilizers:
      if hq.elixir >= buildCost(rtDestabilizer, resElixir):
        return rtDestabilizer
    of esBoosters:
      if hq.elixir >= buildCost(rtBooster, resElixir):
        return rtBooster
    of esAcceleratingAnchors:
      discard  ## `anchors.nim` builds the accelerating anchor itself

  ## 2. The floor: carriers, always, before anything else.
  if side.carriers < side.carrierFloor():
    if freeAd >= buildCost(rtCarrier, resAdamantium): return rtCarrier
  ## 3. An amplifier, if the doctrine wants one and we are short.
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
  if freeAd >= buildCost(rtCarrier, resAdamantium) and
      side.carriers < carrierCap(w, side):
    return rtCarrier
  if freeMn >= buildCost(rtLauncher, resMana) and
      side.launchers < launcherTarget(w, side):
    return rtLauncher
  rtHeadquarters
