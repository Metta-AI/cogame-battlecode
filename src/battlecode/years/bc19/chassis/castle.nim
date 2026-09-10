## A CASTLE's turn, in the engine's own action order.
##
## Behaviour source: `m-schier/battlecode-2019-wololo@ebdd279`,
## `robot.js:53-58` (`CASTLE_STATE`), GPL-3.0.
##
## Castle talk first — it is FREE and it accompanies any action — then a
## build into the free adjacent square nearest the frontier, NEVER BOXING
## ITSELF IN, then, if there is nothing to build and an enemy is inside
## r2 64, an attack for 10 damage and 10 fuel.
##
## **LOSE YOUR LAST CASTLE AND YOU LOSE ON THE SPOT**, so a castle's
## priorities are not a matter of taste: the build queue is what replaces the
## units that die and the attack is free damage a structure can put out
## without moving.

import ../constants, ../units, ../world, ../knobs
import ../actions
import kit, econ, micro, military, trade, comms

export kit

proc economyFloorUnmet*(w: World, s: Side): bool =
  ## THE UNCONDITIONAL ECONOMY FLOOR: at least one PILGRIM on a karbonite
  ## depot and at least one on a fuel depot, from the first affordable
  ## build, at every knob setting. A fuel pilgrim returns +10 fuel a turn for
  ## 1 fuel, so it is the single most net-positive thing an order can buy —
  ## and an order without one starves with a full karbonite bank.
  ##
  ## **THE FLOOR IS NEVER DIVIDED.** Three castles that all want a miner on
  ## round 1 should all build one, whatever `castle_talk_use` says: measured
  ## on `seed-0107` with the floor divided, one side built EIGHT UNITS AND
  ## MINED FORTY KARBONITE IN A THOUSAND ROUNDS, because two of its three
  ## opening slots went to soldiers it could never feed.
  if w.brokenChassis: return s.pilgrims < 1
  s.pilgrims < 2 or karboniteWorkers(w, s) == 0 or fuelWorkers(w, s) == 0

proc wantsPilgrim*(w: World, s: Side, round: int, queued = 0): bool =
  if w.brokenChassis: return s.pilgrims < 1
  if economyFloorUnmet(w, s): return true
  s.pilgrims + queued < s.pilgrimsWanted(round)

func censusVisible*(s: Side): bool =
  ## THE CASTLE-TALK CENSUS, SPENT. Two structures that both decide on the
  ## same unit in the same round have wasted one of the two decisions: the
  ## order needed a miner AND an escort and it bought two miners.
  ##
  ## `castle_talk_use` decides whether they can tell. Under `census` and
  ## `full` the free 8-bit channel carries the per-unit census digit, so a
  ## structure COUNTS THIS ROUND'S QUEUE AS IF IT WERE ALREADY BUILT and its
  ## ladder therefore falls through to the next rung. Under `position` the
  ## channel carries nothing after the two opening position bytes, the
  ## structures are blind to each other, and they duplicate.
  s.doctrine.castleTalkUse != ct19Position

proc pickUnqueued*(w: World, s: Side, want: UnitKind): UnitKind =
  ## The last step of the division. A structure that can read the census
  ## NEVER queues a kind the round's queue already holds: it takes the next
  ## kind it can pay for, so N structures spend N slots on N DIFFERENT jobs
  ## instead of N slots on one. Under `position` it cannot read the census,
  ## so it returns `want` unchanged and the duplicate is built.
  if want == ukCastle or not s.censusVisible: return want
  if not s.alreadyQueued(want): return want
  ## The substitutes are the doctrine's OWN buildable set, in its own
  ## preference order, and a kind whose share the doctrine set to ZERO is not
  ## in it: dividing the queue may not smuggle in a unit the order refused to
  ## buy. `unit_mix: 0` therefore still means NO PROPHETS, ever.
  var alternatives = @[ukPilgrim]
  if s.doctrine.unitMix > 0: alternatives.add ukProphet
  if s.doctrine.preacherShare > 0: alternatives.add ukPreacher
  if s.doctrine.unitMix < 100: alternatives.add ukCrusader
  for alt in alternatives:
    if alt == want or s.alreadyQueued(alt): continue
    if alt != ukPilgrim and w.fuel[ord(s.team)] < MilitaryFuelFloor: continue
    if canSpend(w, s, buildKarboniteOf(alt), buildFuelOf(alt),
                essential = alt == ukPilgrim):
      return alt
  ## Nothing else is affordable, so the duplicate is better than an idle
  ## structure: yielding the slot costs a build a round and buys nothing.
  want

proc queueBuild*(w: World, s: Side, r: Robot, want: UnitKind,
                 countDuplicate = true) =
  ## The single place a structure's build enters this round's ledger.
  ##
  ## `countDuplicate` is false for a FLOOR build, which is not a wasted
  ## decision: the order genuinely wanted two miners, so two miners is not a
  ## duplicate. What `duplicateBuilds` counts is a DISCRETIONARY slot spent
  ## on a kind the round's queue already held — exactly the waste the
  ## castle-talk census exists to prevent.
  if countDuplicate and s.alreadyQueued(want):
    w.stats.duplicateBuilds[ord(s.team)] += 1
  s.commit(buildKarboniteOf(want), buildFuelOf(want))
  s.buildQueuedThisRound[r.id] = ord(want)
  if want == ukPilgrim: inc s.queuedPilgrims else: inc s.queuedMilitary

proc runCastle*(w: World, s: Side, r: Robot): Action =
  result = newAction()
  result.castleTalk = castleTalkFor(w, s, r)

  ## 1. The build queue. Pilgrims first while the economy floor is unmet,
  ##    then military up to the census target.
  ##
  ##    **THE BUILD QUEUE OUTRANKS THE BARTER, ALWAYS**, and that is the
  ##    anti-inert rule rather than a preference: a castle has ONE action a
  ##    turn, so a barter that pre-empts the build spends the whole game
  ##    proposing. Measured in phase 20 with the barter first: at
  ##    `trade_policy: offer_fuel` on `seed-0043` BOTH SEATS BUILT NOTHING
  ##    AT ALL for a thousand rounds. `last_offer` persists until it is
  ##    replaced, so an offer only has to be made ONCE to stand.
  let towards =
    block:
      let e = s.nearestEnemyStructure(r.x, r.y)
      if e.x >= 0: e else: mirrorTarget(w, r.x, r.y)
  let square = freeBuildSquare(w, s, r, towards)
  if square.ok and not s.buildQueuedThisRound.hasKey(r.id):
    ## THE BUILD PRIORITY, and every rung of it is one of the anti-inert
    ## floors: the two-military-per-structure floor first (an order with no
    ## army is farmed for reclaim), then the economy floor (an order with no
    ## fuel pilgrim starves with a full karbonite bank), then the pilgrim
    ## ramp up to HALF the `pilgrim_curve` target, then the military census,
    ## then the rest of the ramp. The interleave matters: without it a
    ## chassis whose pilgrims are being farmed rebuilds pilgrims for a
    ## thousand rounds and never fields an army (measured in phase 20: three
    ## military units in a whole game on `seed-0009`).
    var want = ukCastle          ## sentinel: nothing wanted
    var onFloor = false          ## a floor build: never divided
    let qp = (if s.censusVisible: s.queuedPilgrims else: 0)
    let qm = (if s.censusVisible: s.queuedMilitary else: 0)
    let militaryFloor = MilitaryPerStructureFloor *
      max(1, s.castles + s.churches)
    let fuelOkForWar = w.fuel[ord(s.team)] >= MilitaryFuelFloor
    template tryMilitary(isEssential: bool) =
      let pick = mix(s, w.round)
      if canSpend(w, s, buildKarboniteOf(pick), buildFuelOf(pick),
                  essential = bool(isEssential)):
        want = pick
      elif canSpend(w, s, buildKarboniteOf(ukCrusader),
                    buildFuelOf(ukCrusader), essential = bool(isEssential)):
        want = ukCrusader
    if economyFloorUnmet(w, s) and
        canSpend(w, s, buildKarboniteOf(ukPilgrim), buildFuelOf(ukPilgrim),
                 essential = true):
      ## FIRST, ALWAYS. Karbonite has NO passive income in this year, so an
      ## order that spends its opening hundred on four military units has
      ## nothing left to buy a miner with and nothing that will ever earn it
      ## another karbonite. Measured in phase 20 with the two rungs the
      ## other way round: four units built in a whole 1000-round game, zero
      ## mined, zero damage, on three of four maps.
      want = ukPilgrim
      onFloor = true
    elif s.military + qm < militaryFloor and fuelOkForWar:
      ## The MILITARY floor is divided: three castles that all need an escort
      ## want three DIFFERENT escorts, and a mixed three is strictly better
      ## than three of a kind in a year where the preacher's blast is
      ## friendly-fire-blind and the crusader is the only fast unit.
      tryMilitary(true)
    elif (s.pilgrims + qp) * 2 < s.pilgrimsWanted(w.round) and
        s.military + qm >= min(4, s.militaryWanted(w.round)) and
        canSpend(w, s, buildKarboniteOf(ukPilgrim), buildFuelOf(ukPilgrim),
                 essential = true):
      want = ukPilgrim
    elif s.military + qm < s.militaryWanted(w.round) and fuelOkForWar:
      tryMilitary(false)
    elif wantsPilgrim(w, s, w.round, qp) and
        canSpend(w, s, buildKarboniteOf(ukPilgrim), buildFuelOf(ukPilgrim),
                 essential = true):
      want = ukPilgrim
    if not onFloor: want = pickUnqueued(w, s, want)
    if want != ukCastle:
      queueBuild(w, s, r, want, countDuplicate = not onFloor)
      result.hasAction = true
      result.kind = akBuild
      result.dx = square.dx
      result.dy = square.dy
      result.buildUnit = want
      return

  ## 2. Nothing to build: the barter. A castle is the only unit that can
  ##    trade, and an unpayable match clears both offers and throws — so
  ##    `trade.nim` only ever returns an offer we can pay.
  let deal = tradePlan(w, s, r)
  if deal.ok:
    result.hasAction = true
    result.kind = akTrade
    result.tradeK = deal.k
    result.tradeF = deal.f
    return

  ## 3. Nothing to build and nothing to offer: shoot, if anything is in
  ##    range and the fuel gate allows it.
  let shot = chooseAttack(w, s, r)
  if shot.ok:
    result.hasAction = true
    result.kind = akAttack
    result.dx = shot.dx
    result.dy = shot.dy

proc runChurch*(w: World, s: Side, r: Robot): Action =
  ## A church's own build queue once it exists. It has NO ATTACK (its
  ## `ATTACK_DAMAGE` is 0) and cannot read castle talk, so its turn is the
  ## build and nothing else. The legal 0-damage CHURCH attack (D6.1) is
  ## never emitted.
  result = newAction()
  result.castleTalk = castleTalkFor(w, s, r)
  let towards =
    block:
      let e = s.nearestEnemyStructure(r.x, r.y)
      if e.x >= 0: e else: mirrorTarget(w, r.x, r.y)
  let square = freeBuildSquare(w, s, r, towards)
  if not square.ok or s.buildQueuedThisRound.hasKey(r.id): return
  var want = ukCastle
  let qp = (if s.censusVisible: s.queuedPilgrims else: 0)
  let qm = (if s.censusVisible: s.queuedMilitary else: 0)
  if wantsPilgrim(w, s, w.round, qp) and
      canSpend(w, s, buildKarboniteOf(ukPilgrim), buildFuelOf(ukPilgrim),
               essential = true):
    want = ukPilgrim
  elif s.military + qm < s.militaryWanted(w.round) and
      w.fuel[ord(s.team)] >= MilitaryFuelFloor:
    let pick = mix(s, w.round)
    if canSpend(w, s, buildKarboniteOf(pick), buildFuelOf(pick)):
      want = pick
  want = pickUnqueued(w, s, want)
  if want == ukCastle: return
  queueBuild(w, s, r, want)
  result.hasAction = true
  result.kind = akBuild
  result.dx = square.dx
  result.dy = square.dy
  result.buildUnit = want
