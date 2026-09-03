## BOUNDED ORDERS / LEGALITY on the scripted baselines.
##
## Both `PLAYER_SCRIPTED` values must produce a sheet that passes the SAME
## `sheet.validate()` the LLM path uses — every key known, every value in
## range, `notes`/`motto` under cap — and, in a played game, every action the
## scripted chassis emits must be legal for the acting robot.

import std/unicode
import harness
import battlecode/[baselines, sheet, sim_types]
import battlecode/years/bc26/[constants, maps, rules, world]

for kind in [blAwu, blScaffold]:
  let s = baselineSheet(kind)
  checkEq($kind & ": no field was repaired", s.defaultsApplied.len, 0)
  checkEq($kind & ": no unknown key", s.unknownFields.len, 0)
  check($kind & ": notes under cap", s.notes.runeLen <= MaxNoteRunes)
  check($kind & ": motto under cap", s.motto.runeLen <= MaxMottoRunes)
  check($kind & ": backstab_round in range",
    s.doctrine.backstabRound >= 1 and s.doctrine.backstabRound <= 2000)
  check($kind & ": cat_trap_budget in range",
    s.doctrine.catTrapBudget >= 0 and s.doctrine.catTrapBudget <= 200)
  check($kind & ": rat_trap_budget in range",
    s.doctrine.ratTrapBudget >= 0 and s.doctrine.ratTrapBudget <= 200)
  check($kind & ": ferry ratio in range",
    s.doctrine.cheeseFerryRatio >= 0.0 and s.doctrine.cheeseFerryRatio <= 1.0)
  check($kind & ": king_count_target in range",
    s.doctrine.kingCountTarget >= 1 and s.doctrine.kingCountTarget <= 5)

checkEq("awu selects the awu chassis",
  baselineSheet(blAwu).doctrine.chassis, chAwu)
checkEq("scaffold selects the scaffold chassis",
  baselineSheet(blScaffold).doctrine.chassis, chScaffold)
checkEq("an unknown PLAYER_SCRIPTED is awu, not a forfeit",
  parseBaseline("something-else"), blAwu)
checkEq("scaffold is selectable by its own name",
  parseBaseline("scaffold"), blScaffold)
checkEq("and by the upstream bot's name",
  parseBaseline("examplefuncsplayer"), blScaffold)

# --- legality of every action the chassis emits ------------------------------
# The sim is the referee: `canMove` / `canAttack` / `canPlaceTrap` etc. are
# checked inside the chassis before each action, so an illegal order cannot
# be issued. This walks a real game and asserts the INVARIANTS an illegal
# order would break.
proc playAndAudit(sheets: array[2, Sheet], mapName: string,
                  rounds: int): tuple[ok: bool, why: string] =
  let spec = loadMap(mapName)
  var w = newWorld(spec, rounds)
  let clans = newClans(sheets, 0)
  for round in 1 .. rounds:
    if not w.running: break
    runRound(w, clans)
    for r in w.liveRobots:
      if not w.onTheMap(r.loc):
        return (false, "robot " & $r.id & " left the map at round " & $round)
      if r.health <= 0:
        return (false, "robot " & $r.id & " is alive at 0 hp")
      if r.health > UnitSpecs[r.unit].health:
        return (false, "robot " & $r.id & " is over its max health")
      if r.actionCooldown < 0 or r.movementCooldown < 0 or
          r.turningCooldown < 0:
        return (false, "robot " & $r.id & " has a negative cooldown")
      for l in w.allPartLocations(r):
        if not w.onTheMap(l):
          return (false, "part of robot " & $r.id & " is off the map")
        if w.walls[w.idx(l)]:
          return (false, "robot " & $r.id & " is standing in a wall")
        if r.unit != utCat and w.dirt[w.idx(l)]:
          return (false, "rat " & $r.id & " is standing in dirt")
    for t in 0 .. 1:
      if w.teamInfo.globalCheese[t] < 0:
        return (false, "team " & $t & " is in cheese debt")
      if w.trapCount(ttRatTrap, Team(t)) > TrapSpecs[ttRatTrap].maxCount:
        return (false, "team " & $t & " is over the rat-trap cap")
      if w.trapCount(ttCatTrap, Team(t)) > TrapSpecs[ttCatTrap].maxCount:
        return (false, "team " & $t & " is over the cat-trap cap")
      if w.teamInfo.numRatKings[t] > MaxNumberOfRatKings:
        return (false, "team " & $t & " is over the king cap")
      if w.teamInfo.dirtCounts[t] < 0:
        return (false, "team " & $t & " placed dirt it never dug")
  (true, "")

for mapName in ["DefaultSmall", "cheesefarm", "dirtfulcat"]:
  block:
    let both = [baselineSheet(blAwu), baselineSheet(blAwu)]
    let audit = playAndAudit(both, mapName, 400)
    check("awu vs awu on " & mapName & " emits only legal orders: " & audit.why,
      audit.ok)
  block:
    let mixed = [baselineSheet(blAwu), baselineSheet(blScaffold)]
    let audit = playAndAudit(mixed, mapName, 400)
    check("awu vs scaffold on " & mapName & " emits only legal orders: " &
      audit.why, audit.ok)

# --- the decision budget is respected ---------------------------------------
block:
  ## No robot may finish a turn with a NEGATIVE budget by more than the
  ## single charge that exhausted it: the chassis checks `spend` before every
  ## loop, so the overshoot is bounded by one primitive.
  let spec = loadMap("DefaultSmall")
  var w = newWorld(spec, 200)
  let clans = newClans([baselineSheet(blAwu), baselineSheet(blAwu)], 0)
  var worst = 0
  for round in 1 .. 200:
    if not w.running: break
    runRound(w, clans)
    for r in w.liveRobots:
      if r.opsLeft < worst: worst = r.opsLeft
  check("the decision budget overshoot is bounded (" & $worst & ")",
    worst > -100)

finish("test_baselines")
