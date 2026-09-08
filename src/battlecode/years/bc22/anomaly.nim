## The four anomalies — the year's signature rule, and the half of it the 2022
## metagame never spent.
##
## `GameWorld.causeAbyssGlobal / causeChargeGlobal / causeFuryGlobal /
## causeVortexGlobal` and their three sage counterparts, ported statement for
## statement. Every truncation is float32 and every one of them is measured
## rather than assumed (docs/RULES-BC22.md §Divergences items 5, 6, 7 and 8):
##
## * **ABYSS** removes `(int)(0.1f * metal)` from every square in the engine's
##   whole-map scan order, then `(int)(-1 * 0.1f * reserve)` from A's LEAD, B's
##   LEAD, A's GOLD and B's GOLD **in that order**. A square holding NINE OR
##   FEWER LOSES NOTHING, which is exactly why `mine_floor` has teeth.
## * **CHARGE** ranks the COMBINED droid population of BOTH teams, in
##   `robotsArray()` (trove hash) order, STABLE-sorts it descending by
##   friendly-robots-in-vision and destroys the first `(int)(0.05f * n)` — so
##   the side that clumps donates the victims, and **under twenty droids it
##   kills nobody**. The trove order is what breaks a tie at the cut, and a tie
##   straddles the cut in a measured 51-58 % of rounds, which is why `trove.nim`
##   exists at all (D2).
## * **FURY** deals `(int)(-1 * maxHealth * 0.05f)` to every robot whose mode is
##   TURRET — a level-1 watchtower loses **7**, not 8 — and **nothing at all**
##   to a building in PORTABLE mode or to a PROTOTYPE. It calls `addHealth` with
##   `checkArchonDeath = false`, so it then runs its OWN double-elimination
##   check, which is the ONLY path by which `more_gold_net_worth`,
##   `more_lead_net_worth` or `coin_flip` can fire before round 2000.
## * **VORTEX** permutes the RUBBLE ARRAY ONLY (never lead, never gold, never
##   the robots) per the map's DECLARED symmetry: `VERTICAL` flips vertically,
##   `HORIZONTAL` flips horizontally, and `ROTATIONAL` draws
##   `rand.nextInt(width == height ? 3 : 2)` — adding 1 on a non-square map —
##   from `GameWorld.rand`, a `java.util.Random` seeded with the MAP SEED. That
##   draw is the only place the 2022 round loop reads an RNG, and reproducing it
##   is a hard fidelity requirement (D4).

import std/algorithm
import ../../sim_types
import world

export world

type
  AnomalyReport* = object
    ## What one global anomaly did, for the `anomaly_struck` event and the
    ## per-game statistics. Never read by a rule.
    kind*: AnomalyKind
    droidsLost*: array[2, int]
    turretHpLost*: array[2, int]
    leadLost*: array[2, int]
    rubbleChanged*: bool

func nextAnomaly*(w: World): tuple[has: bool, round: int, kind: AnomalyKind] =
  ## `LiveMap.viewNextAnomaly`: the head of the schedule, unconsumed.
  if w.anomalyCursor >= w.map.anomalies.len:
    return (false, 0, anAbyss)
  let e = w.map.anomalies[w.anomalyCursor]
  (true, e.round, e.kind)

# ---------------------------------------------------------------------------
#  ABYSS
# ---------------------------------------------------------------------------

proc abyssGridUpdate(w: World, sage: bool, locs: seq[Loc],
                     report: var AnomalyReport) =
  for l in locs:
    let currentLead = w.getLead(l)
    let leadUpdate =
      if sage: abyssSageTake(currentLead) else: abyssGlobalTake(currentLead)
    w.setLead(l, currentLead - leadUpdate)
    let currentGold = w.getGold(l)
    let goldUpdate =
      if sage: abyssSageTake(currentGold) else: abyssGlobalTake(currentGold)
    w.setGold(l, currentGold - goldUpdate)

proc causeAbyssGlobal*(w: World, report: var AnomalyReport) =
  var locs: seq[Loc]
  for l in w.allLocations: locs.add(l)
  w.abyssGridUpdate(false, locs, report)
  ## The four reserve deltas, IN THIS ORDER: A lead, B lead, A gold, B gold.
  for t in [teamA, teamB]:
    let delta = abyssReserveDelta(w.teamLead(t))
    w.addLead(t, delta)
    report.leadLost[ord(t)] = -delta
    w.stats.anomalyLossesAbyssLead[ord(t)] += -delta
  for t in [teamA, teamB]:
    w.addGold(t, abyssReserveDelta(w.teamGold(t)))

proc causeAbyssSage*(w: World, r: Robot) =
  var locs: seq[Loc]
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtSage].actionRadiusSquared):
    locs.add(l)
  var report = AnomalyReport(kind: anAbyss)
  w.abyssGridUpdate(true, locs, report)

# ---------------------------------------------------------------------------
#  CHARGE
# ---------------------------------------------------------------------------

proc causeChargeGlobal*(w: World, report: var AnomalyReport) =
  ## `robotsArray()` order (D2), then a STABLE descending sort by
  ## `getNumVisibleFriendlyRobots(false)` — the CACHED value, refreshed for
  ## every droid on the way in.
  var droids: seq[Robot]
  for id in w.trove.valuesDescending:
    let r = w.robotById(id)
    if r == nil: continue
    if r.mode != rmDroid: continue
    droids.add(r)
    w.updateNumVisibleFriendlyRobots(r)
  ## `Collections.sort` is a STABLE merge sort, so equal counts keep their
  ## `robotsArray()` order — which is the whole reason `trove.nim` is a fidelity
  ## requirement and not a nicety.
  droids = droids.sortedByIt(-it.numVisibleFriendlyRobots)
  let limit = chargeCut(droids.len)
  for i in 0 ..< limit:
    let victim = droids[i]
    if not victim.alive: continue
    report.droidsLost[ord(victim.team)] += 1
    w.stats.anomalyLossesCharge[ord(victim.team)] += 1
    w.destroyRobot(victim.id)

proc causeChargeSage*(w: World, r: Robot) =
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtSage].actionRadiusSquared):
    let bot = w.getRobot(l)
    if bot != nil and bot.team != r.team and bot.mode == rmDroid:
      let before = bot.health
      w.addHealth(bot, chargeSageDelta(bot.maxHealth()))
      let after = if bot.alive: bot.health else: 0
      w.stats.damageDealt[ord(r.team)] += max(0, before - after)
      w.stats.sageDamage[ord(r.team)] += max(0, before - after)

# ---------------------------------------------------------------------------
#  FURY
# ---------------------------------------------------------------------------

proc furyDoubleEliminationCheck(w: World) =
  ## `causeFuryUpdate`'s own tail: because `addHealth` was called with
  ## `checkArchonDeath = false`, a fury that destroys archons does not fire
  ## `ANNIHILATION` from inside `destroyRobot`. If BOTH teams are eliminated in
  ## the same fury the engine goes straight to
  ## `setWinnerIfMoreGoldValue -> ...LeadValue -> setWinnerArbitrary`, SKIPPING
  ## `MORE_ARCHONS`. That is the only path by which the two net-worth rungs and
  ## the coin flip can fire before round 2000.
  let aOut = w.robotCountByType(teamA, rtArchon) == 0
  let bOut = w.robotCountByType(teamB, rtArchon) == 0
  if aOut and bOut:
    if w.setWinnerIfMoreGoldValue(): discard
    elif w.setWinnerIfMoreLeadValue(): discard
    else: w.setWinnerArbitrary()
  elif aOut:
    w.setWinner(teamB, dfAnnihilated)
  elif bOut:
    w.setWinner(teamA, dfAnnihilated)

proc furyUpdate(w: World, sage: bool, locs: seq[Loc],
                report: var AnomalyReport) =
  for l in locs:
    let r = w.getRobot(l)
    if r != nil and r.mode == rmTurret:
      let delta =
        if sage: furySageDelta(r.maxHealth()) else: furyGlobalDelta(r.maxHealth())
      let before = r.health
      w.addHealth(r, delta, false)
      let after = if r.alive: r.health else: 0
      report.turretHpLost[ord(r.team)] += max(0, before - after)
      w.stats.anomalyLossesFuryHp[ord(r.team)] += max(0, before - after)
  w.furyDoubleEliminationCheck()

proc causeFuryGlobal*(w: World, report: var AnomalyReport) =
  var locs: seq[Loc]
  for l in w.allLocations: locs.add(l)
  w.furyUpdate(false, locs, report)

proc causeFurySage*(w: World, r: Robot) =
  var locs: seq[Loc]
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtSage].actionRadiusSquared):
    locs.add(l)
  var report = AnomalyReport(kind: anFury)
  w.furyUpdate(true, locs, report)

# ---------------------------------------------------------------------------
#  VORTEX
# ---------------------------------------------------------------------------

proc rotateRubble(w: World) =
  ## `GameWorld.rotateRubble`, verbatim — including the fact that it uses the
  ## WIDTH for both dimensions, which is why it is only ever reached on a square
  ## map.
  let n = w.width
  for x in 0 ..< n div 2:
    for y in 0 ..< (n + 1) div 2:
      var curX = x
      var curY = y
      var lastRubble = w.rubble[curX + curY * n]
      for i in 0 ..< 4:
        let tempX = curX
        curX = curY
        curY = (n - 1) - tempX
        let idx = curX + curY * n
        let tempRubble = w.rubble[idx]
        w.rubble[idx] = lastRubble
        lastRubble = tempRubble

proc flipRubbleHorizontally(w: World) =
  let wd = w.width
  let ht = w.height
  for x in 0 ..< wd div 2:
    for y in 0 ..< ht:
      let idx = x + y * wd
      let newIdx = (wd - 1 - x) + y * wd
      let prev = w.rubble[idx]
      w.rubble[idx] = w.rubble[newIdx]
      w.rubble[newIdx] = prev

proc flipRubbleVertically(w: World) =
  let wd = w.width
  let ht = w.height
  for y in 0 ..< ht div 2:
    for x in 0 ..< wd:
      let idx = x + y * wd
      let newIdx = x + (ht - 1 - y) * wd
      let prev = w.rubble[idx]
      w.rubble[idx] = w.rubble[newIdx]
      w.rubble[newIdx] = prev

proc causeVortexGlobal*(w: World, report: var AnomalyReport): int
    {.discardable.} =
  ## Returns the engine's own `changeIdx` — 0 rotate, 1 flipH, 2 flipV — which
  ## is what the parity trace's `rubblechk` proves.
  var changeIdx = 0
  case w.symmetry
  of symVertical:
    w.flipRubbleVertically()
    changeIdx = 2
  of symHorizontal:
    w.flipRubbleHorizontally()
    changeIdx = 1
  of symRotation:
    let squareMap = w.width == w.height
    var randomNumber = int(w.rand.nextInt(if squareMap: 3 else: 2))
    if not squareMap: randomNumber += 1
    if randomNumber == 0: w.rotateRubble()
    elif randomNumber == 1: w.flipRubbleHorizontally()
    elif randomNumber == 2: w.flipRubbleVertically()
    changeIdx = randomNumber
  report.rubbleChanged = true
  changeIdx

# ---------------------------------------------------------------------------
#  The scheduled anomaly, and the sage's envision
# ---------------------------------------------------------------------------

proc runScheduledAnomaly*(w: World): tuple[fired: bool, report: AnomalyReport] =
  ## Rule 4c: EXACTLY ONE entry is consumed per matching round
  ## (`takeNextAnomaly`), and only when its round equals this one.
  let nxt = w.nextAnomaly()
  if not nxt.has or nxt.round != w.currentRound:
    return (false, AnomalyReport())
  w.anomalyCursor += 1
  var report = AnomalyReport(kind: nxt.kind)
  case nxt.kind
  of anAbyss: w.causeAbyssGlobal(report)
  of anCharge: w.causeChargeGlobal(report)
  of anFury: w.causeFuryGlobal(report)
  of anVortex: discard w.causeVortexGlobal(report)
  (true, report)

func canEnvision*(w: World, r: Robot, kind: AnomalyKind): bool =
  ## `assertCanEnvision`: action-ready, the type can envision, and the anomaly
  ## IS a sage anomaly — `VORTEX.isSageAnomaly == false`.
  r.canActCooldown() and canEnvisionType(r.kind) and
    AnomalySpecs[kind].isSageAnomaly

proc doEnvision*(w: World, r: Robot, kind: AnomalyKind): bool {.discardable.} =
  ## Charge `(int)((1 + rubble/10.0) * 200)` — twenty turns on flat ground —
  ## and THEN run the sage version over r2 <= 25.
  if not w.canEnvision(r, kind):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  case kind
  of anAbyss: w.causeAbyssSage(r)
  of anCharge: w.causeChargeSage(r)
  of anFury: w.causeFurySage(r)
  of anVortex: discard
  w.stats.envisions[ord(r.team)] += 1
  w.noteFirstAction(r, Bc22ActionEnvision)
  true
