## bc23's two cooldown counters, the FIVE-ACTION HEADQUARTERS, the carrier's
## weight-driven movement cooldown, and THE EXACT CHARGE ORDER PER ACTION —
## which is not uniform in this engine and matters whenever the tile
## multiplier changes.

import harness
import bc23_fixture

# --- the two counters -------------------------------------------------------
block:
  var w = bare()
  let r = w.spawnRobot(w.idGen.nextId(), rtLauncher, loc(10, 10), teamA)
  checkEq("a robot starts life with actionCooldown 10", r.actionCooldown,
    CooldownLimit)
  checkEq("and movementCooldown 10", r.movementCooldown, CooldownLimit)
  check("so it cannot act on its first turn", not r.isActionReady())
  check("and cannot move on its first turn", not r.isMovementReady())
  r.actionCooldown = max(0, r.actionCooldown - CooldownsPerTurn)
  r.movementCooldown = max(0, r.movementCooldown - CooldownsPerTurn)
  checkEq("both decay by exactly 10", r.actionCooldown, 0)
  check("and it is ready after the decay", r.isActionReady())
  r.actionCooldown = 5
  r.actionCooldown = max(0, r.actionCooldown - CooldownsPerTurn)
  checkEq("the decay floors at 0", r.actionCooldown, 0)
  r.actionCooldown = 9
  check("an action needs < 10, so 9 is ready", r.isActionReady())
  r.actionCooldown = 10
  check("and 10 is not", not r.isActionReady())

# --- FIVE actions in one turn ----------------------------------------------
block:
  ## A headquarters' action cooldown is 2 against a limit of 10, so
  ## 2+2+2+2+2 = 10 refuses the SIXTH and only the sixth.
  var w = bare()
  let hq = w.robotsById[2]
  hq.actionCooldown = 0
  hq.adamantium = 1000
  hq.mana = 1000
  w.stats.adamantium[0] = 1000
  w.stats.mana[0] = 1000
  ## Eight free tiles inside r2 <= 9 of (3, 15), so the ONLY thing that can
  ## stop the loop is the cooldown.
  const Targets = [loc(4, 15), loc(5, 15), loc(6, 15), loc(4, 16),
                   loc(4, 14), loc(3, 16), loc(3, 14), loc(3, 17)]
  for t in Targets:
    check("the build target is in range", w.canActLocation(hq, t))
  var built = 0
  for target in Targets:
    if not hq.isActionReady(): break
    if w.doBuildRobot(hq, rtCarrier, target) != nil: built += 1
  checkEq("a headquarters takes exactly five actions in one turn", built, 5)
  checkEq("and its cooldown is then exactly the limit", hq.actionCooldown,
    CooldownLimit)
  check("so the sixth is refused", not hq.isActionReady())

# --- the carrier's base movement cooldown at every weight -------------------
block:
  for weight in 0 .. 40:
    let want = int(float32(0.375) * float32(weight)) + 5
    checkEq("carrier move cd at weight " & $weight,
      carrierMoveCooldown(weight), want)
  checkEq("empty carrier", carrierMoveCooldown(0), 5)
  checkEq("weight 8", carrierMoveCooldown(8), 8)
  checkEq("weight 20", carrierMoveCooldown(20), 12)
  checkEq("a FULL carrier is 20 — four times an empty one",
    carrierMoveCooldown(40), 20)
  checkEq("baseMovementCooldown routes a launcher to its type value",
    baseMovementCooldown(rtLauncher, 0), 20)
  checkEq("and a headquarters to -1 (it cannot move)",
    baseMovementCooldown(rtHeadquarters, 0), -1)

# --- the charge order: `move` charges AFTER the move, at the DESTINATION ----
block:
  ## The destination is a cloud, so the 20 % is paid on the very step that
  ## enters it. If `move` charged before the move, or at the origin, the
  ## carrier would pay 5 instead of 6.
  var w = bare(clouds = @[loc(11, 10)])
  let r = w.place(teamA, rtCarrier, loc(10, 10))
  checkEq("the origin multiplier is 1.00", w.cooldownMultiplier(loc(10, 10),
    teamA), 100)
  checkEq("the destination multiplier is 1.20",
    w.cooldownMultiplier(loc(11, 10), teamA), 120)
  check("the move is legal", w.doMove(r, dEast))
  checkEq("and the charge is round(5 * 1.20) = 6, read at the destination",
    r.movementCooldown, 6)

# --- `boost` charges AFTER its own effect; `destabilize` does not benefit ---
block:
  var w = bare()
  let b = w.place(teamA, rtBooster, loc(10, 10))
  check("the boost is legal", w.doBoost(b))
  checkEq("the booster's own tile is boosted to 0.90",
    w.cooldownMultiplier(loc(10, 10), teamA), 90)
  checkEq("so its own 140 is DISCOUNTED: round(140 * 0.90) = 126",
    b.actionCooldown, 126)

block:
  var w = bare()
  let d = w.place(teamA, rtDestabilizer, loc(10, 10))
  check("the destabilisation is legal", w.doDestabilize(d, loc(11, 10)))
  checkEq("our own tile is untouched — it slows the ENEMY",
    w.cooldownMultiplier(loc(10, 10), teamA), 100)
  checkEq("the enemy's copy of the target tile is 1.10",
    w.cooldownMultiplier(loc(11, 10), teamB), 110)
  checkEq("so the destabilizer pays its full 70", d.actionCooldown, 70)

# --- `collectResource` and `transferResource` charge BEFORE their effect ----
block:
  var w = bare(wells = @[(l: loc(11, 10), kind: 1)])
  let r = w.place(teamA, rtCarrier, loc(10, 10))
  check("the collect is legal", w.doCollectResource(r, loc(11, 10), -1))
  checkEq("the charge is the flat 10", r.actionCooldown, 10)
  checkEq("and one kilogram landed", r.adamantium, 1)

# --- `placeAnchor` charges AFTER its effect --------------------------------
block:
  var w = bare(islands = @[(l: loc(10, 10), id: 1)])
  let r = w.place(teamA, rtCarrier, loc(10, 10))
  r.addAnchor(anStandard)
  check("the placement is legal", w.doPlaceAnchor(r))
  checkEq("the island is ours", w.islands[0].owner, 1)
  checkEq("and the charge is the flat 10", r.actionCooldown, 10)

finish("test_bc23_cooldown")
