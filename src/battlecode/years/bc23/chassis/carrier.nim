## `lemonade`'s carrier: mine, ferry, throw.
##
## Behaviour ported from `awesomelemonade/Battlecode2023` `src/finalBot/`
## (AGPL-3.0), with the elixir deposit loop from `vrangr1/BattleCode2023`
## `src/AFinalsBot/ElixirProducer.java` (AGPL-3.0). Parameterised by
## `well_priority`, `carrier_throw`, `elixir_tech` and the anchor programme.
##
## THE DEPOSIT IS THE POINT. A resource enters the TEAM total the moment it is
## mined, but a headquarters can only spend from its OWN stockpile — so a
## faction whose carriers never deposit looks rich and builds nothing. That is
## exactly the failure `-d:bc23BrokenChassis` reproduces and
## `tests/test_bc23_survival.nim`'s negative control must catch.

import ../world, kit, anchors, elixir, comms as chcomms

export kit

func anchorPending*(w: World, side: Side): bool =
  side.doctrine.anchorBudget > 0 and
    w.currentRound >= side.doctrine.anchorRound and
    w.anchorsInStock(side.team) == 0

func hqShortfall*(w: World, side: Side, t: Resource): int =
  ## How far the RICHEST of our headquarters still is from being able to pay
  ## for a standard anchor out of its OWN stockpile. The team total is not the
  ## question: only a headquarters can spend.
  var best = 0
  for id in w.headquarters[ord(side.team)]:
    if not w.existsRobot(id): continue
    best = max(best, w.robotsById[id].resourceOf(t))
  max(0, AnchorSpecs[anStandard].adamantiumCost - best)

const HaulThreshold* = 20
  ## The cargo at which a carrier turns for home. Measured against the
  ## competence gate: at 40 (a full load) the headquarters starves for forty
  ## turns a trip and the faction cannot answer a launcher push.

func wantsResource(side: Side, w: World, r: Robot): Resource =
  ## `wellTarget()`'s resource preference. Adamantium buys carriers (50),
  ## amplifiers (30) and half a standard anchor; mana buys launchers (45),
  ## amplifiers (15) and the other half.
  ##
  ## `balanced` SPLITS THE FLEET BY CARRIER ID rather than steering the whole
  ## fleet by the current team deficit. Measured: the deficit rule is a
  ## feedback loop — a faction spends adamantium faster than mana, so its
  ## adamantium total stays lower, so every carrier keeps mining adamantium,
  ## so it never has the 80 mana a standard anchor costs and never anchors an
  ## island at all. A fixed split is what makes `balanced` actually balanced.
  case side.doctrine.wellPriority
  of wpAdamantium: resAdamantium
  of wpMana: resMana
  of wpBalanced:
    ## While the anchor programme is WAITING on a resource, the whole fleet
    ## fetches it: an anchor is 80 adamantium AND 80 mana, and a fleet that
    ## keeps mining the one the headquarters already has never buys one.
    if anchorPending(w, side):
      if hqShortfall(w, side, resMana) >= hqShortfall(w, side, resAdamantium):
        resMana
      else:
        resAdamantium
    elif (r.id and 1) == 0: resAdamantium
    else: resMana

proc wellTarget*(w: World, side: Side, r: Robot): Loc =
  ## The well a free carrier walks to: the doctrine's preferred resource
  ## first, an UPGRADED well (rate 3) ahead of a plain one, and near ahead of
  ## far.
  result = loc(-1, -1)
  let want = wantsResource(side, w, r)
  var best = high(int)
  for l in side.knownWells:
    if not r.spend(1): break
    let well = w.wellAtLoc(l)
    if not well.present: continue
    var score = chebyshev(r.loc, l) * 4
    ## THE PREFERENCE HAS TO DOMINATE THE DISTANCE. A 14-point penalty is
    ## worth three and a half tiles, so a faction that needs mana walked to
    ## the nearer adamantium well every time and never built a launcher —
    ## measured, and the reason this number is 40.
    if well.kind != want: score += 40
    if well.kind == resElixir: score -= 10
    if well.upgraded: score -= 12
    if w.getCloud(l): score += 3
    if score < best:
      best = score
      result = l

proc tryThrow(w: World, side: Side, r: Robot): bool =
  ## `throwPlan()`. A lethal throw inside r² ≤ 9 is ALWAYS taken, at every
  ## setting, because refusing a free kill is not a strategy. Otherwise the
  ## knob decides, against a deterministic per-robot slot rather than an RNG.
  if r.weight == 0 or not r.isActionReady(): return false
  var lethal = loc(-1, -1)
  var any = loc(-1, -1)
  let damage = carrierThrowDamage(r.weight)
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtCarrier].actionRadiusSquared):
    if not r.spend(1): break
    let other = w.getRobot(l)
    if other == nil or other.team == r.team: continue
    if other.kind == rtHeadquarters: continue
    if any.x < 0: any = l
    if damage >= other.health and lethal.x < 0: lethal = l
  if lethal.x >= 0:
    return w.doAttack(r, lethal)
  if any.x < 0: return false
  if r.totalAnchors > 0: return false     ## never throw away an anchor
  let slot = (w.currentRound * 7 + r.id) mod 100
  if slot >= side.doctrine.carrierThrow: return false
  w.doAttack(r, any)

proc depositAt(w: World, side: Side, r: Robot): bool =
  ## Hand the whole cargo to the nearest friendly headquarters we are standing
  ## beside. THE BROKEN-CHASSIS NEGATIVE CONTROL SKIPS EXACTLY THIS.
  if w.brokenChassis: return false
  if not r.isActionReady(): return false
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtCarrier].actionRadiusSquared):
    if not r.loc.isAdjacentTo(l): continue
    if not w.isHeadquarters(l): continue
    if w.getRobot(l).team != r.team: continue
    for t in RealResources:
      let amount = r.resourceOf(t)
      if amount > 0:
        return w.doTransferResource(r, l, t, amount)
    return false
  false

proc pourElixir(w: World, side: Side, r: Robot): bool =
  ## The elixir programme's deposit: 40 kg loads of the OPPOSITE resource into
  ## the target well, until it flips.
  if not side.hasElixirTarget: return false
  if not r.isActionReady(): return false
  let target = side.elixirTarget
  let well = w.wellAtLoc(target)
  if well.kind != resMana: return false
  if r.adamantium <= 0: return false
  if not r.loc.isAdjacentTo(target): return false
  w.doTransferResource(r, target, resAdamantium, r.adamantium)

proc runFerry(w: World, side: Side, r: Robot): bool =
  ## Take an anchor from a headquarters, walk it to the island `anchors.nim`
  ## picked, and plant it. A ferrying carrier must be EMPTY — an anchor weighs
  ## the carrier's whole capacity — so this path never mixes with mining.
  if side.doctrine.anchorBudget <= 0: return false
  let claimed = side.claimedBy(r.id)

  if r.totalAnchors > 0:
    var islandIdx = claimed
    if islandIdx < 0:
      islandIdx = pickIsland(w, side, r.loc)
      if islandIdx >= 0: side.claimIsland(islandIdx, r.id)
    if islandIdx < 0: return false
    let isl = w.islands[islandIdx]
    if isl.tiles.len == 0: return false
    if w.islandAt(r.loc) == islandIdx and
        w.islands[islandIdx].canPlaceAnchor(side.team) and r.isActionReady():
      if w.doPlaceAnchor(r):
        side.releaseClaim(r.id)
        w.noteFirstAction(side.team, Bc23ActionPlaceAnchor)
        return true
      return false
    ## Head for the island tile nearest us.
    var target = isl.tiles[0]
    var best = chebyshev(r.loc, target)
    for tile in isl.tiles:
      let d = chebyshev(r.loc, tile)
      if d < best:
        best = d
        target = tile
    return w.moveToward(side, r, target)

  ## Not carrying one: only ONE carrier at a time is the ferry, and only when
  ## a headquarters actually holds an anchor.
  if side.ferryClaim >= 0 and side.ferryClaim != r.id: return false
  if w.anchorsInStock(side.team) <= 0: return false
  if r.weight > 0: return false          ## must be completely empty
  ## Walk to the nearest friendly headquarters that holds one, and take it.
  var target = loc(-1, -1)
  var best = high(int)
  for id in w.headquarters[ord(side.team)]:
    if not w.existsRobot(id): continue
    let hq = w.robotsById[id]
    if hq.totalAnchors == 0: continue
    let d = chebyshev(r.loc, hq.loc)
    if d < best:
      best = d
      target = hq.loc
  if target.x < 0: return false
  side.ferryClaim = r.id
  if r.loc.isAdjacentTo(target):
    let hq = w.getRobot(target)
    let kind = hq.typeAnchor()
    if kind != anNone and w.canTakeAnchor(r, target, kind) and
        w.doTakeAnchor(r, target, kind):
      w.noteFirstAction(side.team, Bc23ActionTakeAnchor)
      return true
    return false
  w.moveToward(side, r, target)

proc stepOffBadCurrent(w: World, side: Side, r: Robot, home: Loc): bool =
  ## The anti-inert rule's own clause: a LOADED carrier standing on a current
  ## that would carry it away from home steps off rather than riding it.
  if r.weight == 0: return false
  let d = w.getCurrent(r.loc)
  if d == dCenter: return false
  let after = r.loc + d
  if not w.onTheMap(after): return false
  if chebyshev(after, home) <= chebyshev(r.loc, home): return false
  w.moveToward(side, r, home)

proc runCarrier*(w: World, side: Side, r: Robot) =
  w.observe(side, r)
  if r.weight > 0:
    w.stats.carrierRoundsLoaded[ord(r.team)] += 1

  if tryThrow(w, side, r):
    w.noteFirstAction(side.team, Bc23ActionThrow)
    return

  if runFerry(w, side, r):
    return

  let home = side.nearestHome(r.loc)

  ## A carrier with a REAL LOAD goes home. Not a full one: a carrier mines one
  ## kilogram per action, so waiting for all forty is forty turns in which the
  ## headquarters cannot spend a single kilogram of it — the resource is on
  ## the team total and not in the stockpile that builds things.
  if r.weight >= HaulThreshold or
      (r.weight > 0 and not r.isActionReady() and
       chebyshev(r.loc, home) <= 2):
    ## ONE CARRIER IN THREE runs the elixir programme; the rest keep feeding
    ## the headquarters. A fleet that all pours into the well starves the
    ## build queue, which is the same failure the deposit rule exists to stop.
    if elixirRunning(w, side) and side.hasElixirTarget and
        r.adamantium > 0 and (r.id mod 3) == 0:
      if pourElixir(w, side, r): return
      discard w.moveToward(side, r, side.elixirTarget)
      return
    if depositAt(w, side, r):
      w.noteFirstAction(side.team, Bc23ActionTransfer)
      return
    if stepOffBadCurrent(w, side, r, home): return
    discard w.moveToward(side, r, home)
    return

  if (r.id mod 3) == 0 and r.weight >= HaulThreshold and
      elixirRunning(w, side) and side.hasElixirTarget and r.adamantium > 0:
    if pourElixir(w, side, r): return
    discard w.moveToward(side, r, side.elixirTarget)
    return

  ## Otherwise: mine. Collect from any adjacent well — INCLUDING THE ONE WE
  ## ARE STANDING ON, because `isAdjacentTo` includes the robot's own tile.
  if r.isActionReady():
    for l in w.locationsWithinRadiusSquared(
        r.loc, RobotSpecs[rtCarrier].actionRadiusSquared):
      if not r.loc.isAdjacentTo(l): continue
      if not w.isWell(l): continue
      if w.canCollectResource(r, l, -1):
        if w.doCollectResource(r, l, -1):
          w.noteFirstAction(side.team, Bc23ActionCollect)
          return

  if r.weight > 0 and chebyshev(r.loc, home) <= 1:
    if depositAt(w, side, r):
      w.noteFirstAction(side.team, Bc23ActionTransfer)
      return

  let well = wellTarget(w, side, r)
  if well.x >= 0:
    if stepOffBadCurrent(w, side, r, home): return
    discard w.moveToward(side, r, well)
  else:
    ## Nothing known to mine: explore toward the map centre rather than the
    ## enemy's headquarters. Walking a loaded carrier into the enemy's half
    ## is how a faction on a clouded map loses its whole fleet without ever
    ## finding a well.
    discard w.moveToward(side, r, mapCentre(w))

  if chcomms.canWriteSharedArrayFor(w, r):
    chcomms.publish(w, side, r)
