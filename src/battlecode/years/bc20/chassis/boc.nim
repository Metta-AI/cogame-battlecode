## `bowl-of-chowder` — the strong bc20 baseline and the champion chassis.
##
## Behaviour ported from `StoneT2000/Battlecode2020` `src/FinalChowBotStable/`
## (AGPL-3.0; see NOTICE), parameterised by the ten doctrine knobs. None of its
## Java is copied, compiled or shipped: the passive-lattice build order, the
## wall-then-terraform landscaper priority, the builder-miner election, the
## drone roles and the signal-code discipline are its IDEAS, rewritten in Nim.
##
## This file is only the dispatcher; the roles live one per module, exactly as
## the design note lays them out.

import kit, hq, miner, designschool, landscaper, fulfillment, drone, netgun

export kit

proc openingPlan*(side: Side): string =
  ## The build order and role split for the first 400 rounds, in one word —
  ## read by the endcard and by `tests/test_bc20_knobs.nim`.
  case side.doctrine.opening
  of opRush: "rush"
  of opLattice: "lattice"
  of opPassiveLattice: "passive_lattice"
  of opTurtle: "turtle"

proc applyOpening*(side: Side) =
  ## `opening` is a preset over the other knobs, applied ONCE when the side is
  ## created. Every knob the cog set explicitly still wins where it is more
  ## specific; the preset only moves the pacing the opening is named for.
  case side.doctrine.opening
  of opRush:
    ## Get there before their wall does: terraform late, lattice small.
    side.doctrine.terraformStartRound =
      max(side.doctrine.terraformStartRound, 500)
    if side.doctrine.rushTrigger == 0:
      side.doctrine.rushTrigger = 250
  of opLattice:
    ## Contest the middle while terraforming outward.
    side.doctrine.terraformStartRound =
      min(side.doctrine.terraformStartRound, 260)
  of opPassiveLattice:
    discard                     ## the defaults ARE the Bowl of Chowder build
  of opTurtle:
    ## Wall immediately, minimum miners, maximum net guns.
    side.doctrine.wallHqRound =
      (if side.doctrine.wallHqRound == 0: 0
       else: min(side.doctrine.wallHqRound, 120))
    side.doctrine.netGunRing = max(side.doctrine.netGunRing, 4)
    side.doctrine.latticeRadius = min(side.doctrine.latticeRadius, 4)

proc runBowlOfChowder*(w: World, side: Side, r: Robot) =
  case r.kind
  of rtHq: w.runHq(side, r)
  of rtMiner: w.runMiner(side, r)
  of rtDesignSchool: w.runDesignSchool(side, r)
  of rtLandscaper: w.runLandscaper(side, r)
  of rtFulfillmentCenter: w.runFulfillmentCenter(side, r)
  of rtDeliveryDrone: w.runDrone(side, r)
  of rtNetGun: w.runNetGun(side, r)
  of rtRefinery, rtVaporator, rtCow: discard
