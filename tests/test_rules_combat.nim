## Rule family: biting (with the cheese boost), ratnapping, throwing and its
## collateral, feeding a rat to a cat, both trap types, squeaks and the 64-int
## shared array, the cat state machine, and the backstab trigger from EACH of
## its four causes.

import harness
import battlecode/sheet
import battlecode/years/bc26/[cats, constants, maps, world]
import battlecode/years/bc26/chassis/kit

let spec = loadMap("DefaultSmall")
proc freshWorld(): World = newWorld(spec, GameMaxNumberOfRounds)

proc rat(w: World, id: int, x, y: int, team: Team, dir = dNorth): Robot =
  w.spawnRobot(id, utBabyRat, loc(x, y), dir, 0, team)
  result = w.robotsById[id]
  result.actionCooldown = 0
  result.movementCooldown = 0
  result.turningCooldown = 0

# --- biting -----------------------------------------------------------------
block:
  let w = freshWorld()
  let a = w.rat(97001, 10, 10, teamA, dNorth)
  let b = w.rat(97002, 10, 11, teamB, dSouth)
  check("an adjacent enemy in the cone is attackable", w.canAttack(a, b.loc))
  w.attack(a, b.loc)
  checkEq("a bite does RAT_BITE_DAMAGE", b.health,
    UnitSpecs[utBabyRat].health - RatBiteDamage)
  checkEq("and costs the attacker its action cooldown", a.actionCooldown,
    UnitSpecs[utBabyRat].actionCooldown)

block:
  ## The cheese boost: `ceil(sqrt(cheeseConsumed))` extra damage, paid for
  ## out of the biter's raw stash.
  let w = freshWorld()
  let a = w.rat(97003, 10, 10, teamA, dNorth)
  let b = w.rat(97004, 10, 11, teamB, dSouth)
  a.cheese = 16
  w.attack(a, b.loc, 16)
  checkEq("16 cheese adds 4 damage", b.health,
    UnitSpecs[utBabyRat].health - RatBiteDamage - 4)
  checkEq("and the cheese is spent", a.cheese, 0)

block:
  ## Biting a CAT credits the clan's cat damage, capped at the cat's health,
  ## and does NOT trip the backstab.
  let w = freshWorld()
  let a = w.rat(97005, 10, 10, teamA, dNorth)
  var cat: Robot
  for r in w.liveRobots:
    if r.unit == utCat: cat = r
  cat.loc = loc(10, 11)
  for l in w.allPartLocations(cat):
    if w.onTheMap(l): w.occupant[w.idx(l)] = cat
  w.attack(a, loc(10, 11))
  checkEq("cat damage is credited", w.teamInfo.damageToCats[0], RatBiteDamage)
  check("and the alliance holds", w.isCooperation)

# --- the four backstab triggers ---------------------------------------------
block:
  let w = freshWorld()
  let a = w.rat(97010, 10, 10, teamA, dNorth)
  let b = w.rat(97011, 10, 11, teamB, dSouth)
  check("the world starts in cooperation", w.isCooperation)
  w.attack(a, b.loc)
  check("a BITE flips the world", not w.isCooperation)
  checkEq("and names the biter", w.backstabber, teamA)
  checkEq("with the trigger recorded", w.backstabTrigger, "bite")

block:
  let w = freshWorld()
  let a = w.rat(97012, 10, 10, teamA, dNorth)
  let b = w.rat(97013, 10, 11, teamB, dSouth)
  b.health = 10                       ## weaker, so the grab is allowed
  check("a weaker adjacent enemy can be grabbed", w.canCarryRat(a, b.loc))
  w.carryRat(a, b.loc)
  check("a RATNAP flips the world", not w.isCooperation)
  checkEq("and the trigger is recorded", w.backstabTrigger, "ratnap")
  check("the grabber is carrying", a.carrying == b)

block:
  let w = freshWorld()
  let a = w.rat(97014, 10, 10, teamA, dNorth)
  let b = w.rat(97015, 10, 11, teamB, dSouth)
  b.health = 10
  w.carryRat(a, b.loc)
  w.isCooperation = true              ## reset to isolate the throw trigger
  w.hasBackstabber = false
  a.actionCooldown = 0
  a.dir = dEast
  check("a carrier with a clear tile ahead can throw", w.canThrowRat(a))
  w.throwRat(a)
  check("a THROW flips the world", not w.isCooperation)
  checkEq("and the trigger is recorded", w.backstabTrigger, "throw")

block:
  ## The fourth cause: the VICTIM walks into your rat trap. The trap's owner
  ## is not the one who moved, and the backstab is attributed to the owner.
  let w = freshWorld()
  let a = w.rat(97016, 10, 10, teamA, dNorth)
  w.teamInfo.globalCheese[0] = 1000
  check("a rat trap can be placed on an empty tile",
    w.canPlaceTrap(a, loc(10, 11), ttRatTrap))
  w.buildTrap(a, loc(10, 11), ttRatTrap)
  checkEq("the team's live rat traps go up", w.trapCount(ttRatTrap, teamA), 1)
  let b = w.rat(97017, 11, 12, teamB, dSouth)
  b.movementCooldown = 0
  w.move(b, dSouthwest)               ## steps onto (10, 11)
  check("a TRAP flips the world", not w.isCooperation)
  checkEq("attributed to the trap owner", w.backstabber, teamA)
  checkEq("with the trigger recorded", w.backstabTrigger, "trap")
  checkEq("the trap damages the victim", b.health,
    UnitSpecs[utBabyRat].health - TrapSpecs[ttRatTrap].damage)
  ## The stun is SET first and the move cooldown is added after — the
  ## engine's order in `RobotControllerImpl.move`, so a strafe onto a trap
  ## costs the stun plus the strafe.
  checkEq("stuns it", b.movementCooldown,
    TrapSpecs[ttRatTrap].stunTime + MoveStrafeCooldown)
  checkEq("and is consumed", w.trapCount(ttRatTrap, teamA), 0)

# --- traps ------------------------------------------------------------------
block:
  let w = freshWorld()
  let a = w.rat(97020, 10, 10, teamA, dNorth)
  w.teamInfo.globalCheese[0] = 100000
  check("cat traps are allowed while the alliance holds",
    w.catTrapsAllowed(teamA))
  ## Traps go on ADJACENT tiles only (BUILD_DISTANCE_SQUARED = 2) AND inside
  ## the rat's own 90-degree cone, so a north-facing rat can only lay them
  ## on the three tiles it is actually looking at.
  var placed = 0
  for d in NonCenterDirs:
    a.actionCooldown = 0
    if w.canPlaceTrap(a, a.loc + d, ttCatTrap):
      w.buildTrap(a, a.loc + d, ttCatTrap)
      inc placed
  checkEq("a north-facing rat lays exactly its three cone tiles", placed, 3)
  checkEq("and the live count tracks it", w.trapCount(ttCatTrap, teamA), placed)
  ## The per-team live cap is TrapType.maxCount, whatever a doctrine asks for.
  w.trapCounts[ttCatTrap][0] = TrapSpecs[ttCatTrap].maxCount
  a.actionCooldown = 0
  check("at maxCount no more cat traps may be placed",
    not w.canPlaceTrap(a, loc(12, 12), ttCatTrap))

block:
  ## After a backstab, only the VICTIM may place cat traps, and only for
  ## CAT_TRAP_ROUNDS_AFTER_BACKSTAB rounds.
  let w = freshWorld()
  w.currentRound = 500
  w.backstab(teamA, "bite")
  check("the backstabber may not place cat traps",
    not w.catTrapsAllowed(teamA))
  check("the victim may", w.catTrapsAllowed(teamB))
  w.currentRound = 500 + CatTrapRoundsAfterBackstab + 1
  check("but not forever", not w.catTrapsAllowed(teamB))

# --- squeaks and the shared array ------------------------------------------
block:
  let w = freshWorld()
  let a = w.rat(97030, 10, 10, teamA, dNorth)
  let ally = w.rat(97031, 12, 12, teamA, dSouth)
  let enemy = w.rat(97032, 11, 11, teamB, dSouth)
  check("a squeak is sent", w.squeak(a, 42))
  checkEq("an ally in range hears it", ally.inbox.len, 1)
  checkEq("with the content", ally.inbox[0].content, 42)
  checkEq("an enemy rat does NOT", enemy.inbox.len, 0)
  check("only MAX_MESSAGES_SENT_ROBOT per turn", not w.squeak(a, 43))
  let far = w.rat(97033, 25, 25, teamA, dSouth)
  checkEq("and nothing outside SQUEAK_RADIUS_SQUARED", far.inbox.len, 0)

block:
  let w = freshWorld()
  let king = w.rat(97040, 10, 10, teamA)
  king.unit = utRatKing
  w.writeSharedArray(king, 3, 999)
  checkEq("a king can write the shared array", w.readSharedArray(king, 3), 999)
  w.writeSharedArray(king, 3, CommArrayMaxValue + 1)
  checkEq("an out-of-range value is refused", w.readSharedArray(king, 3), 999)
  w.writeSharedArray(king, SharedArraySize, 5)
  checkEq("and an out-of-range index", w.readSharedArray(king, 3), 999)
  let babyRat = w.rat(97041, 12, 12, teamA)
  w.writeSharedArray(babyRat, 4, 7)
  checkEq("only kings may write", w.readSharedArray(babyRat, 4), 0)

# --- feeding a rat to a cat -------------------------------------------------
block:
  let w = freshWorld()
  var cat: Robot
  for r in w.liveRobots:
    if r.unit == utCat: cat = r
  ## Put the cat two tiles east of a carrier and throw into it.
  for l in w.allPartLocations(cat):
    if w.onTheMap(l): w.occupant[w.idx(l)] = nil
  cat.loc = loc(14, 10)
  for l in w.allPartLocations(cat):
    if w.onTheMap(l): w.occupant[w.idx(l)] = cat
  let carrier = w.rat(97050, 12, 10, teamA, dEast)
  let victim = w.rat(97051, 13, 10, teamA, dEast)
  check("an ally rat can be grabbed", w.canCarryRat(carrier, victim.loc))
  w.carryRat(carrier, victim.loc)
  check("grabbing an ALLY does not flip the world", w.isCooperation)
  carrier.actionCooldown = 0
  check("and can be thrown east", w.canThrowRat(carrier))
  w.throwRat(carrier)
  check("the fed rat dies", victim.dead or victim.health <= 0)
  checkEq("and the cat falls asleep", cat.sleepTimeRemaining, CatSleepTime)

# --- the cat state machine --------------------------------------------------
block:
  ## A cat with a waypoint walks toward it and never sits still forever.
  let w = freshWorld()
  var cat: Robot
  for r in w.liveRobots:
    if r.unit == utCat: cat = r
  check("cats start in EXPLORE", cat.catState == csExplore)
  check("cats carry waypoints", cat.catWaypoints.len > 0)
  let start = cat.loc
  var moved = false
  for round in 1 .. 60:
    w.currentRound = round
    w.processBeginningOfTurn(cat)
    runCatTurn(w, cat)
    if cat.loc != start: moved = true
  check("a cat patrols", moved)
  checkEq("and stays on the map", w.onTheMap(cat.loc), true)

# --- the five backstab_policy values are five behaviours --------------------
block:
  ## `never` and `retaliate_only` read alike while the alliance holds. They
  ## must NOT read alike after it breaks: `never` never takes an enemy rat as
  ## a target, `retaliate_only` finishes what the other clan started. Both
  ## returning true once the world flipped made two of the five sheet values
  ## behaviourally identical.
  proc clanWith(policy: string): Clan =
    newClan(teamA, parseReply(
      """{"sheet":{"backstab_policy":"""" & policy & """"}}""").doctrine)
  let never = clanWith("never")
  let retaliate = clanWith("retaliate_only")
  let first = clanWith("on_first_contact")
  let w = freshWorld()
  check("while the alliance holds, `never` holds fire",
    not never.hostilitiesOpen(w))
  check("and so does `retaliate_only`", not retaliate.hostilitiesOpen(w))
  check("while `on_first_contact` is already hostile",
    first.hostilitiesOpen(w))
  w.backstab(teamB, "bite")
  check("the world has flipped", not w.isCooperation)
  check("`retaliate_only` fights back", retaliate.hostilitiesOpen(w))
  check("`never` still does not", not never.hostilitiesOpen(w))

finish("test_rules_combat")
