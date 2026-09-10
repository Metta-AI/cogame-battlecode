## `saber`'s economy: the opening posture, the pilgrim curve, the fuel gate
## and the per-structure commitment ledger.
##
## Behaviour source: `m-schier/battlecode-2019-wololo@ebdd279`,
## `robot.js:88-140` (`STRATEGY_OPTIONAL_TANK_RUSH`, `STRATEGY_BOOM_RED`,
## `STRATEGY_BOOM_BLUE`, `STRATEGY_BOOM_DEFENSIVE`), GPL-3.0.
##
## **THIS IS THE ONLY PLACE KARBONITE OR FUEL IS EVER COMMITTED**, so two
## castles cannot promise the same 15 karbonite in one round, and it holds
## the two unconditional floors the anti-inert rule names: at least one
## karbonite pilgrim and one fuel pilgrim, and at least two military units
## per structure.

import ../constants, ../units, ../world, ../knobs
import kit

export kit

type
  Posture* = enum
    poEco       ## ramp pilgrims, buy military only to satisfy `defend_radius`
    poTurtle    ## prophets behind a lattice, economy target HALVED
    poRush      ## the whole military budget on preachers, from round 1

func posture*(s: Side, round: int): Posture =
  ## `econ.nim plan()` (from `opening`). The three archetypes the 2019 season
  ## actually produced, and the reason `opening` is a knob rather than the
  ## chassis's default: the dev nerf of the preacher rush is exactly this
  ## axis.
  case s.doctrine.opening
  of op19PilgrimEco: (if round <= 250: poEco else: poEco)
  of op19Turtle: poTurtle
  of op19PreacherRush: (if round <= 300: poRush else: poEco)

func pilgrimTarget*(s: Side, round: int): int =
  ## Pilgrims wanted PER STRUCTURE, ramped linearly from 1 at round 1 to
  ## `pilgrim_curve` at round 100 and held after. At `pilgrim_curve == 0` the
  ## order still wants ONE per structure — the floor that keeps 0 from
  ## starving — and at 24 it wants more pilgrims than there are depots, which
  ## wastes karbonite and crowds the castle's build squares.
  let peak = max(PilgrimPerStructureFloor, s.doctrine.pilgrimCurve)
  var want =
    if round >= 100: peak
    else: 1 + ((peak - 1) * max(0, round - 1)) div 99
  if s.doctrine.opening == op19Turtle:
    ## `turtle` HALVES the economy target, never zeroes it.
    want = max(PilgrimPerStructureFloor, want div 2)
  if s.doctrine.opening == op19PreacherRush and round <= 300:
    want = max(PilgrimPerStructureFloor, want div 2)
  max(PilgrimPerStructureFloor, want)

func depotsInReach*(s: Side): int =
  ## The ceiling on a useful pilgrim census: THE NUMBER OF DEPOTS. A pilgrim
  ## with nowhere to mine burns 10 karbonite and 50 fuel and then stands
  ## there, and `pilgrim_curve: 24` on a 4-depot board would build twelve of
  ## them. The knob still moves the target — it is capped, not overridden.
  max(2, s.depots.len div 2 + 2)

func pilgrimsWanted*(s: Side, round: int): int =
  max(2, min(s.pilgrimTarget(round) * max(1, s.castles + s.churches),
             s.depotsInReach()))

func militaryWanted*(s: Side, round: int): int =
  ## Never fewer than two military units per structure, at every knob
  ## setting. Above that the target grows with the round so a 1000-round game
  ## does not end with a mining colony and no army.
  let floor0 = MilitaryPerStructureFloor * max(1, s.castles + s.churches)
  var want = floor0 + (round div 60)
  case s.doctrine.opening
  of op19Turtle: want += 6
  of op19PreacherRush: want += (if round <= 300: 8 else: 2)
  of op19PilgrimEco: discard
  max(floor0, want)

func fuelGate*(s: Side): int =
  ## The global fuel floor below which the order funds ONLY `mine` and
  ## `move`: no attack, no build, no signal. Fuel is the thing that stops a
  ## bc19 army dead.
  s.doctrine.fuelReserve

proc canSpend*(w: World, s: Side, kCost, fCost: int,
               essential = false): bool =
  ## The commitment ledger. `essential` marks the spends that are funded
  ## THROUGH the fuel gate.
  ##
  ## **THE GATE IS A WAR GATE, NOT A BUDGET FREEZE**, and that is a decision
  ## with a reason: `fuel_reserve` is "the global fuel floor below which the
  ## order funds only `mine` and `move`", and a PILGRIM is the thing that
  ## MAKES fuel — +10 a turn for 1, against a flat passive income of 25 a
  ## round for the whole order. Gating the economy behind the reserve
  ## deadlocks an order at exactly the reserve: it cannot afford the miner
  ## that would lift it over the line, and it stands there with a full
  ## karbonite bank until round 1000. Measured on `seed-0043` and
  ## `seed-0048` in phase 20: 3 280 karbonite banked, four military units,
  ## zero damage. So the gate applies to MILITARY builds, attacks and
  ## military MOVEMENT; economy builds are funded whenever the order can pay
  ## for them. `fuel_reserve`'s teeth are unchanged and are exactly the two
  ## the knob test asserts: rounds at zero fuel down, attacks down.
  let t = ord(s.team)
  if w.karbonite[t] - s.committedK < kCost: return false
  if w.fuel[t] - s.committedF < fCost: return false
  if not essential and w.fuel[t] - s.committedF - fCost < s.fuelGate():
    return false
  true

proc commit*(s: Side, kCost, fCost: int) =
  s.committedK += kCost
  s.committedF += fCost

const MilitaryFuelFloor* = 150
  ## Even the two-military-per-structure floor is not funded below this:
  ## an order that spends its last hundred fuel on a prophet cannot move it,
  ## cannot shoot with it and cannot walk a pilgrim to a depot, and in this
  ## year THAT IS HOW AN ORDER DIES — it does not get eaten, IT RUNS OUT.

proc canAct*(w: World, s: Side, fCost: int, essential = false): bool =
  ## Whether a non-build action (an attack, a broadcast) is funded. `mine`
  ## and `move` are never gated: an order that cannot move cannot recover.
  let t = ord(s.team)
  if w.fuel[t] - s.committedF < fCost: return false
  if not essential and w.fuel[t] - s.committedF - fCost < s.fuelGate():
    return false
  true

func karboniteWorkers*(w: World, s: Side): int =
  for i in 0 ..< s.depots.len:
    if s.depots[i].kind == dkKarbonite and s.depots[i].claimedBy != 0:
      inc result

func fuelWorkers*(w: World, s: Side): int =
  for i in 0 ..< s.depots.len:
    if s.depots[i].kind == dkFuel and s.depots[i].claimedBy != 0:
      inc result
