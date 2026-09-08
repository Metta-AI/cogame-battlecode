## `examplefuncsplayer23`, reproduced statement for statement — IT MAY NOT
## GAIN BEHAVIOUR, because it is one side of the differential oracle.
##
## The `Random(6147)` call sequence, the eight `directions` in the file's own
## order, THE LAUNCHER ATTACKING THE SQUARE ONE STEP EAST OF ITSELF rather
## than the enemy it just sensed, the nine-tile coin-flip collect loop, the
## `wells[1]` step, and the `HashSet<MapLocation>` iteration order its
## (unreachable) anchor branch depends on.

import harness
import bc23_fixture
import battlecode/rng
import battlecode/years/bc23/chassis/scaffold23

# --- the eight directions, in the file's own order -----------------------
block:
  checkEq("`directions` is NORTH, NORTHEAST, EAST, SOUTHEAST, SOUTH, " &
    "SOUTHWEST, WEST, NORTHWEST — the order `rng.nextInt(8)` indexes",
    @ScaffoldDirections,
    @[dNorth, dNortheast, dEast, dSoutheast, dSouth, dSouthwest, dWest,
      dNorthwest])

# --- the Random(6147) stream, per robot ---------------------------------
block:
  ## `static final Random rng = new Random(6147)` — and static fields are PER
  ## ROBOT under the instrumenter, so every robot gets its own stream from the
  ## same seed and this bot needs NO determinism patch.
  var a = initJavaRandom(6147)
  var b = initJavaRandom(6147)
  for k in 0 ..< 20:
    checkEq("two fresh streams agree at draw " & $k, a.nextInt(8),
      b.nextInt(8))
  var w = bare()
  let r1 = w.place(teamA, rtCarrier, loc(10, 10))
  let r2 = w.place(teamA, rtCarrier, loc(11, 10))
  checkEq("every spawned robot carries its own Random(6147)",
    r1.scaffoldRng.nextInt(8), r2.scaffoldRng.nextInt(8))

block:
  ## The exact first draws of the seeded stream, so a change to `rng.nim`
  ## cannot silently move the bot.
  var rng = initJavaRandom(6147)
  let first = rng.nextInt(8)
  let second = rng.nextBoolean()
  let third = rng.nextInt(20)
  let fourth = rng.nextInt(3)
  check("nextInt(8) is in range", first >= 0 and first < 8)
  check("nextInt(20) is in range", third >= 0 and third < 20)
  check("nextInt(3) is in range", fourth >= 0 and fourth < 3)
  var again = initJavaRandom(6147)
  checkEq("and the stream is reproducible", again.nextInt(8), first)
  checkEq("draw 2", again.nextBoolean(), second)
  checkEq("draw 3", again.nextInt(20), third)
  checkEq("draw 4", again.nextInt(3), fourth)

# --- a headquarters: buildAnchor, then a coin flip between the two units --
block:
  var w = bare()
  let hq = w.robotsById[2]
  hq.actionCooldown = 0
  w.addResourceAmount(hq, resAdamantium, 400)
  w.addResourceAmount(hq, resMana, 400)
  ## Predict the two draws the bot will take.
  var predict = initJavaRandom(6147)
  let dirIdx = predict.nextInt(8)
  let wantsCarrier = predict.nextBoolean()
  let expected = if wantsCarrier: rtCarrier else: rtLauncher
  runScaffold23(w, hq)
  checkEq("the anchor is built first, whenever it can afford one",
    w.stats.anchorsBuilt[0], 1)
  var built = rtHeadquarters
  for id in w.execOrder:
    if id == 2 or id == 3: continue
    built = w.robotsById[id].kind
  checkEq("and then the coin flip's own unit", built, expected)
  let target = hq.loc + ScaffoldDirections[dirIdx]
  check("built at `getLocation().add(dir)`", w.getRobot(target) != nil)

# --- a launcher attacks the square ONE STEP EAST OF ITSELF ---------------
block:
  ## `toAttack = rc.getLocation().add(Direction.EAST)`; the sensible line is
  ## commented out upstream, and reproducing the bug is the whole point.
  var w = bare()
  let l = w.place(teamA, rtLauncher, loc(10, 10))
  let east = w.place(teamB, rtCarrier, loc(11, 10))
  let west = w.place(teamB, rtCarrier, loc(9, 10))
  runScaffold23(w, l)
  checkEq("the robot ONE STEP EAST took the 20", east.health, 130)
  checkEq("and the one to the WEST took nothing", west.health, 150)

block:
  ## And it fires at an EMPTY square east of itself just the same — the
  ## `enemies.length >= 0` guard is always true.
  var w = bare()
  let l = w.place(teamA, rtLauncher, loc(10, 10))
  runScaffold23(w, l)
  checkEq("the launcher still paid its cooldown for the empty shot",
    l.actionCooldown, 10)

# --- the carrier's nine-tile coin-flip collect loop ----------------------
block:
  ## `for dx in -1..1, for dy in -1..1` — nine tiles INCLUDING the robot's
  ## own — and `rng.nextBoolean()` is drawn only for a tile it CAN collect
  ## from.
  var w = bare(wells = @[(l: loc(10, 10), kind: 1)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  var predict = initJavaRandom(6147)
  let collects = predict.nextBoolean()
  runScaffold23(w, c)
  if collects:
    checkEq("the coin flip said collect, so one kilogram landed",
      c.adamantium, 1)
  else:
    checkEq("the coin flip said no, so nothing was collected", c.adamantium, 0)
  check("either way the bot acted", c.scaffoldTurns == 1)

# --- the HashSet<MapLocation> iteration order --------------------------
block:
  ## `MapLocation.hashCode() = (y + 0x8000) & 0xffff | (x << 16)`, spread by
  ## `h ^ (h >>> 16)`, bucketed by `(cap - 1) & hash`. It is DEAD CODE in
  ## practice — the bot never calls `takeAnchor` — and it is reproduced anyway
  ## because a parity oracle whose two sides differ on an unreachable branch
  ## is one refactor away from differing on a reachable one.
  checkEq("the hash of (0, 0)", javaHashCode(loc(0, 0)), int32(0x8000))
  checkEq("the hash of (1, 0)", javaHashCode(loc(1, 0)), int32(0x18000))
  checkEq("the hash of (0, 1)", javaHashCode(loc(0, 1)), int32(0x8001))
  checkEq("an empty set has no first element", javaHashSetFirst(@[]),
    loc(-1, -1))
  let one = @[loc(5, 7)]
  checkEq("a single-element set returns it", javaHashSetFirst(one), loc(5, 7))
  ## A known table: five tiles, capacity 16. The bucket of each is
  ## `(spread(hash) & 15)`, and the lowest bucket wins.
  ## MEASURED against Temurin 8 with a `MapLocation`-equivalent key: these
  ## five tiles bucket as (3,3) -> 0, (4,4) -> 0, (5,5) -> 0, (3,4) -> 7,
  ## (4,3) -> 7 at capacity 16, and `HashSet`'s iteration order is
  ## [(3,3), (4,4), (5,5), (3,4), (4,3)] inserted forward and
  ## [(5,5), (4,4), (3,3), (4,3), (3,4)] inserted in reverse — because a
  ## bucket's chain is in INSERTION ORDER.
  let five = @[loc(3, 3), loc(3, 4), loc(4, 3), loc(4, 4), loc(5, 5)]
  checkEq("the first element inserted forward is (3, 3), as in Java",
    javaHashSetFirst(five), loc(3, 3))
  var reversed: seq[Loc]
  for i in countdown(five.high, 0): reversed.add(five[i])
  checkEq("and inserted in reverse it is (5, 5) — the chain within a " &
    "bucket is in insertion order, exactly as Java's is",
    javaHashSetFirst(reversed), loc(5, 5))
  let first = javaHashSetFirst(five)
  checkEq("and it is deterministic", javaHashSetFirst(five), first)
  ## Duplicates are dropped, exactly as a HashSet drops them.
  var dupes = five
  for l in five: dupes.add(l)
  checkEq("duplicates change nothing", javaHashSetFirst(dupes), first)

# --- it may not gain behaviour -----------------------------------------
block:
  ## BOOSTER, DESTABILIZER and AMPLIFIER all `break` without doing anything.
  var w = bare()
  for kind in [rtBooster, rtDestabilizer, rtAmplifier]:
    let r = w.place(teamA, kind, loc(10 + ord(kind), 10))
    let beforeAction = r.actionCooldown
    let beforeLoc = r.loc
    runScaffold23(w, r)
    checkEq($kind & " does nothing at all", r.actionCooldown, beforeAction)
    checkEq($kind & " does not even move", r.loc, beforeLoc)
  ## And it never writes the shared array.
  var sides = newSides23(defaultSheets(), 0)
  var w2 = bare()
  for round in 1 .. 60:
    runRound(w2, sides, [ckExamplefuncsplayer23, ckExamplefuncsplayer23])
  checkEq("`examplefuncsplayer23` never writes the shared array",
    w2.stats.arrayWrites[0] + w2.stats.arrayWrites[1], 0)
  checkEq("and never transfers a resource to a headquarters",
    w2.stats.resourcesBanked[0] + w2.stats.resourcesBanked[1], 0)
  checkEq("and never takes an anchor from one — so its carriers never hold " &
    "one and the anchor branch is unreachable",
    w2.stats.totalAnchorsPlaced[0] + w2.stats.totalAnchorsPlaced[1], 0)
  check("but it DOES build", w2.stats.unitsBuilt[0] > 0)
  check("and it DOES build anchors it can never ferry",
    w2.stats.anchorsBuilt[0] > 0)

finish("test_bc23_scaffold")
