## `archon.nim` — an archon's turn, and `archon_relocate`.
##
## Behaviour ported from `iliao2345/Battlecode2022` `src/fury_fix_20/Archon.java`
## (AGPL-3.0): build what `econ.nim` asks for in the free adjacent square
## nearest the frontier (never boxing itself in), repair the weakest friendly
## droid in r2 <= 20 by the first-place bot's own priority (SAGE, then SOLDIER,
## then MINER — and miners only when they are not mining), write the census and
## the archon-alive bitmap to the shared array, and run `relocate()`.
## BEHAVIOUR, NOT CODE. `NOTICE` names the file.
##
## **LOSE YOUR LAST ARCHON AND YOU LOSE THE GAME IMMEDIATELY**, which is why the
## last clause of `relocate()` is unconditional at every knob setting: the
## chassis never lets its LAST archon enter PORTABLE mode while an enemy
## attacker is sensed within eight squares. An archon in PORTABLE mode cannot
## act, pays 100 movement cooldown to get up and another 100 to sit down, and is
## 600 HP of nothing in between.

import kit, econ, comms
import anomaly as chassisAnomaly

export kit

func relocatePolicy*(side: Side): ArchonRelocate = side.doctrine.archonRelocate

proc lastArchonPinned(w: World, side: Side, r: Robot): bool =
  ## THE UNCONDITIONAL FLOOR: never stand the LAST archon up with an enemy
  ## attacker inside eight squares.
  if side.archons > 1: return false
  for e in w.sortedEnemies(side, r, RobotSpecs[rtArchon].visionRadiusSquared):
    if canAttackType(e.kind) and chebyshev(r.loc, e.loc) <= 8:
      return true
  false

proc repairTarget(w: World, side: Side, r: Robot): Robot =
  ## The first-place bot's own priority: sage, then soldier, then a miner that
  ## is NOT mining. Ties go to the weakest.
  result = nil
  var best = high(int)
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtArchon].actionRadiusSquared):
    let b = w.getRobot(l)
    if b == nil or b.team != side.team: continue
    if b.kind.isBuilding(): continue
    if b.health >= b.maxHealth(): continue
    var rank = case b.kind
      of rtSage: 0
      of rtSoldier: 1
      of rtBuilder: 2
      of rtMiner: (if b.minedThisTurn: 4 else: 3)
      else: 5
    let score = rank * 100000 + b.health
    if score < best:
      best = score
      result = b

proc writeCensus(w: World, side: Side, r: Robot) =
  ## Slots 0-3: our archons, packed. Slots 56-63: the per-type census. Writes
  ## are FREE in this year (no cooldown, no range test), so the only price is
  ## one `DecisionOps` credit each.
  var slot = SlotArchons
  for _, a in w.robotsById:
    if a.team != side.team or a.kind != rtArchon: continue
    if slot >= SlotArchons + 4: break
    w.writeSlot(r, slot, packArchon(a.loc, true, a.level))
    slot += 1
  w.writeSlot(r, SlotCensus + 0, side.miners)
  w.writeSlot(r, SlotCensus + 1, side.soldiers)
  w.writeSlot(r, SlotCensus + 2, side.builders)
  w.writeSlot(r, SlotCensus + 3, side.sages)
  w.writeSlot(r, SlotCensus + 4, side.labsLive)
  w.writeSlot(r, SlotCensus + 5, side.watchtowersLive)
  if side.anomalyReq.active:
    w.writeSlot(r, SlotAnomaly, ord(side.anomalyReq.kind))
    w.writeSlot(r, SlotAnomaly + 1, max(0, side.anomalyReq.round))

proc relocateTarget(w: World, side: Side, r: Robot): Loc =
  ## Where this archon should walk, or its own square for "stay".
  case relocatePolicy(side)
  of arNever:
    r.loc
  of arSafety, arLead:
    var threat: Robot = nil
    for e in w.sortedEnemies(side, r, RobotSpecs[rtArchon].visionRadiusSquared):
      if canAttackType(e.kind):
        threat = e
        break
    if threat != nil:
      return loc(max(0, min(w.width - 1, r.loc.x + (r.loc.x - threat.loc.x))),
                 max(0, min(w.height - 1, r.loc.y + (r.loc.y - threat.loc.y))))
    ## Before a VORTEX, step off a square that is about to become high-rubble
    ## under the map's own symmetry. This is the ONE timed play the first-place
    ## bot actually made.
    if relocatingForVortex(side):
      let after = vortexRubbleAt(w, r.loc)
      if after >= w.getRubble(r.loc) + 20:
        let dest = lowestRubbleNear(w, side, r.loc, 8)
        if not (dest == r.loc):
          return dest
    if relocatePolicy(side) == arLead:
      ## Walk toward the richest remembered unmined cluster.
      var best = loc(-1, -1)
      var bestScore = low(int)
      for l in side.leadSites:
        let i = w.idx(l)
        if side.deadSquare[i]: continue
        let amount = int(side.knownLead[i])
        if amount <= 0: continue
        let steps = max(1, chebyshev(r.loc, l))
        let score = amount * 10 div steps
        if score > bestScore:
          bestScore = score
          best = l
      if best.x >= 0 and chebyshev(r.loc, best) > 6:
        return best
    r.loc

proc runArchon*(w: World, side: Side, r: Robot) =
  w.observe(side, r)
  ## 1. The shared array: free in this year, so it is written every turn.
  writeCensus(w, side, r)

  ## 2. THE FURY DODGE. A building in PORTABLE mode takes NOTHING from a fury,
  ##    and a level-1 archon in TURRET mode loses 30. `anomaly_play` is the knob
  ##    that reaches it; `archon_relocate: never` does NOT block it, because the
  ##    two are different decisions and the note says so.
  if r.mode == rmPortable and (side.anomalyReq.standDown or
                               not dodgingFury(side)):
    if w.canTransform(r):
      w.doTransform(r)
      return
  if r.mode == rmTurret and dodgingFury(side) and
     not lastArchonPinned(w, side, r) and w.canTransform(r):
    w.doTransform(r)
    noteDodge(w, side, "portable_before_fury", -furyGlobalDelta(r.maxHealth()))
    return

  ## 3. A PORTABLE archon walks and cannot act at all.
  if r.mode == rmPortable:
    let target = relocateTarget(w, side, r)
    if not (target == r.loc):
      let before = r.loc
      if w.moveToward(side, r, target):
        w.stats.archonRelocations[ord(side.team)] += 1
        discard w.beat(BeatArchonRelocated, "archon_relocated",
                       ord(side.team), before.x * 100 + before.y,
                       r.loc.x * 100 + r.loc.y,
                       $w.getRubble(before) & ":" & $w.getRubble(r.loc))
    return

  ## 4. Build what the plan asks for, in the free adjacent square nearest the
  ##    frontier — never boxing the archon in.
  let rate = if side.labsLive > 0: 6 else: 11
  let want = nextArchonBuild(w, side, rate)
  if want != rtArchon and r.canActCooldown():
    let toward = nearestEnemyHome(side, r.loc)
    let site = freeSquareNear(w, side, r.loc, toward)
    if site.x >= 0:
      let d = r.loc.directionTo(site)
      if w.canBuildRobot(r, want, d):
        reserveFor(w, side, want)
        w.doBuildRobot(r, want, d)
        return

  ## 5. Repair the weakest friendly droid in range.
  let hurt = repairTarget(w, side, r)
  if hurt != nil and w.canRepair(r, hurt.loc):
    w.doRepair(r, hurt.loc)
    return

  ## 6. Relocate, if the doctrine asks and it is safe to stand up.
  if relocatePolicy(side) != arNever and not lastArchonPinned(w, side, r):
    let target = relocateTarget(w, side, r)
    if not (target == r.loc) and chebyshev(r.loc, target) >= 3 and
       w.canTransform(r):
      w.doTransform(r)
