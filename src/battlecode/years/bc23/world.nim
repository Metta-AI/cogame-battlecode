## The Battlecode 2023 "Tempest" world: state, geometry and every legality rule
## a ROBOT can reach.
##
## A behaviour-for-behaviour port of `battlecode/world/GameWorld.java`,
## `world/InternalRobot.java`, `world/robots/InternalCarrier.java`,
## `world/RobotControllerImpl.java`, `world/TeamInfo.java`, `world/Island.java`,
## `world/Well.java`, `world/Inventory.java`, `world/ObjectInfo.java` and
## `world/LiveMap.java` at commit
## `af42086ecd09709dc603b2aaa9e9b98312c9ef79`, together with the pieces of
## `common/MapLocation.java` and `common/Direction.java` the rules depend on.
## The port is the authority at runtime; the Java engine survives only as the
## `parity-oracle-bc23` CI job (docs/PARITY.md).
##
## `currents.nim` and `comms.nim` import this file; `units.nim`, `tempo.nim`,
## `wells.nim` and `islands.nim` are pure and are imported BY it.
##
## Seven things in here look like details and are not:
##
## * **The exec order is DYNAMIC and mutated BY VALUE.** `ObjectInfo`'s
##   `dynamicBodyExecOrder` is a plain append-ordered `TIntArrayList`; a robot
##   built is appended, a robot destroyed is removed from wherever it sits and
##   everything after it shifts forward. The sweep iterates a SNAPSHOT taken
##   before it starts, so a robot built this round does not take a turn this
##   round, and a robot destroyed mid-sweep is skipped by the `existsRobot`
##   guard.
## * **A conquest win fires MID-TURN.** `TeamInfo.placeAnchor` runs the
##   threshold test the instant a carrier plants an anchor, and `running` is
##   only cleared at the end of the round, so every robot after that carrier
##   in the exec order still takes its turn.
## * **A headquarters can act FIVE TIMES in one turn.** Its action cooldown is
##   2 against a `COOLDOWN_LIMIT` of 10 and `isActionReady` is
##   `actionCooldown < 10`, so 2+2+2+2+2 = 10 refuses only the sixth.
## * **A carrier's throw empties it whether it hits or not**, and the
##   resources come off the TEAM total, not just the carrier's.
## * **The charge order is NOT uniform.** `move` charges AFTER the move at the
##   DESTINATION tile; `buildRobot`, `buildAnchor`, `attack`,
##   `collectResource` and `transferResource` charge BEFORE their effect;
##   `boost`, `destabilize`, `takeAnchor`, `returnAnchor` and `placeAnchor`
##   charge AFTER it — so a booster's own 140 is discounted by the boost it
##   just cast, and a destabilizer's 70 is not.
## * **An attack needs no vision.** `assertCanAttack` checks the action radius
##   and the map, never `canSenseLocation`, which is how launchers fight
##   through clouds.
## * **`getAllLocationsWithinRadiusSquared`'s scan order is load-bearing**: x
##   ascending outer, y ascending inner over the clamped
##   `ceil(sqrt(r2)) + 1` box. It fixes which enemy a headquarters' 4 damage
##   reaches first, the order tiles are pushed onto boost and destabilise
##   lists, and the order every sense sweep returns.

import std/[algorithm, tables]
import ../../sim_types, ../../rng
import units, tempo, wells, islands

export units, tempo, wells, islands, rng, tables

type
  MapSpec* = object
    ## One converted `.map23`, as `data/maps/bc23/<name>.json` carries it.
    name*: string
    width*, height*: int
    randomSeed*: int
    symmetry*: Symmetry
    rounds*: int
    walls*: seq[bool]
    clouds*: seq[bool]
    currents*: seq[int]        ## `DIRECTION_ORDER` index per tile, 0 = none
    islandIds*: seq[int]       ## island id per tile, 0 = none
    resources*: seq[int]       ## `ResourceType` id per tile, 0 = none
    initialBodies*: seq[tuple[id, x, y, team, kind: int]]
      ## SORTED ASCENDING BY ID by the converter, because `LiveMap`'s
      ## constructor sorts by id and that order IS the initial exec order.

  Robot* = ref object
    id*: int
    team*: Team
    kind*: RobotType
    loc*: Loc
    health*: int
    ## --- `world/Inventory.java` ---
    adamantium*: int
    mana*: int
    elixir*: int
    standardAnchors*: int
    acceleratingAnchors*: int
    ## ---
    roundsAlive*: int
    actionCooldown*: int
    movementCooldown*: int
    alive*: bool
    disintegrated*: bool
    opsLeft*: int              ## the DecisionOps budget replacing the JVM limit
    opsUsed*: int
    ## --- chassis-side memory, never read by a rule ---
    scaffoldRng*: JavaRandom
      ## `static final Random rng = new Random(6147)`. Static fields are PER
      ## ROBOT under the instrumenter, so every unit gets its own stream and
      ## the example bot needs no determinism patch.
    scaffoldTurns*: int
    noRepeat*: seq[Loc]
    homeHq*: Loc
    hasHome*: bool
    task*: int
    taskLoc*: Loc
    hasTask*: bool
    groupCentre*: Loc
    regroupUntil*: int

  TeamStats* = object
    ## `TeamInfo` plus the per-game counters `results.games[]` reports. The
    ## engine keeps only the three resource totals, the two anchor counters
    ## and the shared arrays; everything else is telemetry and is never read
    ## by a rule.
    adamantium*: array[2, int]
    mana*: array[2, int]
    elixir*: array[2, int]
    totalAnchorsPlaced*: array[2, int]
    currentAnchorsPlaced*: array[2, int]
    sharedArray*: array[2, array[64, int]]
    ## --- telemetry ---
    islandsCaptured*: array[2, int]
    islandsLost*: array[2, int]
    roundsHoldingAnyIsland*: array[2, int]
    holdStreak*: array[2, int]
    longestHoldStreak*: array[2, int]
      ## The longest run of CONSECUTIVE rounds this faction held at least one
      ## island. The competence gate keys on this rather than on the
      ## cumulative count, because "anchored an island once and lost it a
      ## hundred times" is not holding one.
    anchorsBuilt*: array[2, int]
    acceleratingAnchorsPlaced*: array[2, int]
    anchorsLost*: array[2, int]
    adamantiumMined*: array[2, int]
    manaMined*: array[2, int]
    elixirMined*: array[2, int]
    resourcesThrown*: array[2, int]
    resourcesBanked*: array[2, int]
      ## Cargo a carrier actually DEPOSITED into one of its own headquarters.
      ## THE SIGNATURE OF A FACTION THAT IS PLAYING: a resource enters the team
      ## total the moment it is mined, but a headquarters can only spend from
      ## its OWN stockpile, so a faction whose carriers never deposit looks
      ## rich and builds nothing (§Tests item 16).
    wellsTransformed*: array[2, int]
    wellsUpgraded*: array[2, int]
    unitsBuilt*: array[2, int]
    carriersBuilt*: array[2, int]
    launchersBuilt*: array[2, int]
    amplifiersBuilt*: array[2, int]
    destabilizersBuilt*: array[2, int]
    boostersBuilt*: array[2, int]
    robotsLost*: array[2, int]
    launchersLost*: array[2, int]
    damageDealt*: array[2, int]
    throwDamage*: array[2, int]
    destabilizeDamage*: array[2, int]
    hqDamage*: array[2, int]
    anchorHeals*: array[2, int]
    arrayWrites*: array[2, int]
    boostsCast*: array[2, int]
    destabilizesCast*: array[2, int]
    carrierRoundsLoaded*: array[2, int]
    currentRides*: array[2, int]
    firstAnchorRound*: array[2, int]
    capturedDistanceSum*: array[2, int]
    capturedDistanceCount*: array[2, int]
    strikeDistanceSum*: array[2, int]
    strikeDistanceCount*: array[2, int]
    carrierDamageTaken*: array[2, int]
    launchersBuiltBy400*: array[2, int]
    carriersBuiltBy400*: array[2, int]

  World* = ref object
    map*: MapSpec
    width*, height*: int
    currentRound*: int
    maxRounds*: int
    running*: bool
    idGen*: IdGenerator
    rand*: JavaRandom
      ## `GameWorld.rand` is constructed from the map seed and NEVER READ by
      ## the 2023 engine. It is constructed here for one purpose only:
      ## replacing `setWinnerArbitrary`'s wall-clock `Math.random()` with a
      ## reproducible draw (docs/RULES-BC23.md §Divergences item 2).
    symmetry*: Symmetry
    walls*: seq[bool]
    clouds*: seq[bool]
    currents*: seq[Dir]
    islandIdAt*: seq[int]
    wellAt*: seq[Well]
    occupant*: seq[Robot]
    robotsById*: Table[int, Robot]
    execOrder*: seq[int]
    islands*: seq[Island]        ## ASCENDING ISLAND ID (D2)
    islandIndex*: Table[int, int]
    tempo*: TempoField
    headquarters*: array[2, seq[int]]
    stats*: TeamStats
    winner*: Team
    hasWinner*: bool
    domination*: Domination
    ## Replay/telemetry sinks — never read by a rule.
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    hashChain*: uint64
    beatCount*: array[16, int]
    refusedActions*: int
      ## THE LEGALITY AUDIT. Every `do*` re-checks its own `can*` and no-ops
      ## when it fails; this counts those no-ops. A chassis that emits an
      ## illegal order is a chassis whose orders were never checked, so
      ## `tests/test_bc23_baselines.nim` plays whole games and asserts this
      ## stays ZERO.
    opsUsedPeak*: int
    firstActionSeen*: array[2, bool]
    conquestStage*: array[2, int]
    elixirUnitSeen*: array[2, array[3, bool]]
    lostThisRound*: array[2, int]
    launchersLostThisRound*: array[2, int]
    brokenChassis*: bool
      ## Set by `-d:bc23BrokenChassis`: the NEGATIVE CONTROL for the
      ## competence gate (§Tests item 16). Carriers mine and never deposit.

# ---------------------------------------------------------------------------
#  Beats
# ---------------------------------------------------------------------------

const
  BeatGameStart* = 0
  BeatFirstAction* = 1
  BeatAnchorBuilt* = 2
  BeatIslandCaptured* = 3
  BeatIslandLost* = 4
  BeatConquestProgress* = 5
  BeatWellTransformed* = 6
  BeatWellUpgraded* = 7
  BeatFirstElixirUnit* = 8
  BeatBoostField* = 9
  BeatDestabilizeHit* = 10
  BeatDuel* = 11
  BeatRout* = 12

  BeatBounds* = [1, 4, 40, 40, 40, 6, 8, 8, 6, 20, 20, 20, 20, 0, 0, 0]
    ## Per GAME, in the order above and in the design note's own event table.
    ## `tests/test_bc23_replay.nim` asserts every one of them against a real
    ## match, so a pathological game cannot produce a 20 MB replay.

const
  Bc23ActionMove* = 0
  Bc23ActionBuildRobot* = 1
  Bc23ActionBuildAnchor* = 2
  Bc23ActionAttack* = 3
  Bc23ActionThrow* = 4
  Bc23ActionDestabilize* = 5
  Bc23ActionBoost* = 6
  Bc23ActionCollect* = 7
  Bc23ActionTransfer* = 8
  Bc23ActionWithdraw* = 9
  Bc23ActionTakeAnchor* = 10
  Bc23ActionReturnAnchor* = 11
  Bc23ActionPlaceAnchor* = 12
  Bc23ActionWriteArray* = 13
  Bc23ActionDisintegrate* = 14
    ## The ordinals `years/dispatch.nim`'s `Bc23ActionNames` spells out, so
    ## `first_action.action` has a DOCUMENTED VOCABULARY (the r1-F14 lesson).

proc emit*(w: World, kind: string, a = 0, b = 0, c = 0, s = "") =
  w.events.add((round: w.currentRound, kind: kind, a: a, b: b, c: c, s: s))

proc beat*(w: World, slot: int, kind: string, a = 0, b = 0, c = 0,
           s = ""): bool {.discardable.} =
  if w.beatCount[slot] >= BeatBounds[slot]: return false
  w.beatCount[slot] += 1
  w.emit(kind, a, b, c, s)
  true

proc mixHash*(w: World, v: int) =
  w.hashChain = (w.hashChain xor uint64(v and 0xFFFFFFFF)) *
    0x100000001B3'u64

proc mixHashU*(w: World, v: uint64) =
  ## The same step for a value that is ALREADY a 64-bit hash. It exists
  ## because `mixHash(int(h and 0xFFFFFFFF'u64))` is a 64-bit-only expression:
  ## `int` is 32 bits under wasm32, the masked value runs to 4294967295, and
  ## the conversion raises RangeDefect the moment the browser re-derives round
  ## 1 — while the native test suite, on amd64, is green.
  w.hashChain = (w.hashChain xor (v and 0xFFFFFFFF'u64)) *
    0x100000001B3'u64

# ---------------------------------------------------------------------------
#  Geometry
# ---------------------------------------------------------------------------

func idx*(w: World, l: Loc): int = l.x + l.y * w.width
func indexToLoc*(w: World, i: int): Loc = loc(i mod w.width, i div w.width)
func onTheMap*(w: World, l: Loc): bool =
  l.x >= 0 and l.y >= 0 and l.x < w.width and l.y < w.height

iterator locationsWithinRadiusSquared*(w: World, center: Loc, r2: int): Loc =
  ## `GameWorld.getAllLocationsWithinRadiusSquaredWithoutMap`, verbatim: x
  ## ascending outer, y ascending inner, over the clamped
  ## `ceil(sqrt(r2)) + 1` box. `ceil(sqrt())` comes from the precomputed table
  ## in `units.nim`, so the port has no `sqrt` and no `fdlibm` path.
  let clamped = max(0, min(r2, CeilSqrtTable.high))
  let ceiled = CeilSqrtTable[clamped] + 1
  let minX = max(center.x - ceiled, 0)
  let minY = max(center.y - ceiled, 0)
  let maxX = min(center.x + ceiled, w.width - 1)
  let maxY = min(center.y + ceiled, w.height - 1)
  for x in minX .. maxX:
    for y in minY .. maxY:
      let l = loc(x, y)
      if center.isWithinDistanceSquared(l, r2):
        yield l

func symmetricLoc*(w: World, l: Loc): Loc =
  case w.symmetry
  of symVertical: loc(w.width - 1 - l.x, l.y)
  of symHorizontal: loc(l.x, w.height - 1 - l.y)
  of symRotation: loc(w.width - 1 - l.x, w.height - 1 - l.y)

# ---------------------------------------------------------------------------
#  Terrain
# ---------------------------------------------------------------------------

func getWall*(w: World, l: Loc): bool = w.walls[w.idx(l)]
func isPassable*(w: World, l: Loc): bool = not w.walls[w.idx(l)]
func getCloud*(w: World, l: Loc): bool =
  if not w.onTheMap(l): false else: w.clouds[w.idx(l)]
func getCurrent*(w: World, l: Loc): Dir = w.currents[w.idx(l)]

func isWell*(w: World, l: Loc): bool =
  w.onTheMap(l) and w.wellAt[w.idx(l)].present

func wellAtLoc*(w: World, l: Loc): Well = w.wellAt[w.idx(l)]

func islandIdOf*(w: World, l: Loc): int =
  if w.onTheMap(l): w.islandIdAt[w.idx(l)] else: 0

func islandAt*(w: World, l: Loc): int =
  ## The INDEX into `w.islands` of the island covering `l`, or -1.
  let id = w.islandIdOf(l)
  if id == 0: -1
  elif w.islandIndex.hasKey(id): w.islandIndex[id]
  else: -1

func getRobot*(w: World, l: Loc): Robot =
  if w.onTheMap(l): w.occupant[w.idx(l)] else: nil

func isLocationOccupied*(w: World, l: Loc): bool = w.getRobot(l) != nil

func robotById*(w: World, id: int): Robot =
  if w.robotsById.hasKey(id): w.robotsById[id] else: nil

func existsRobot*(w: World, id: int): bool = w.robotsById.hasKey(id)

func isHeadquarters*(w: World, l: Loc): bool =
  let r = w.getRobot(l)
  r != nil and r.kind == rtHeadquarters

func canSenseLocation*(w: World, r: Robot, l: Loc): bool =
  ## `InternalRobot.canSenseLocation`: THE CLOUD COLLAPSE IS SYMMETRIC — if
  ## EITHER the sensing robot's tile OR the sensed tile is a cloud, the radius
  ## collapses to 4. That is the whole fog mechanic.
  if not w.onTheMap(l): return false
  var r2 = RobotSpecs[r.kind].visionRadiusSquared
  if w.getCloud(l) or w.getCloud(r.loc):
    r2 = CloudVisionRadiusSquared
  r.loc.distanceSquaredTo(l) <= r2

func canActLocation*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanActLocation`: within the action radius AND on the map. No
  ## vision test — which is exactly how a launcher shoots into a cloud.
  w.onTheMap(l) and
    r.loc.distanceSquaredTo(l) <= RobotSpecs[r.kind].actionRadiusSquared

func isActionReady*(r: Robot): bool = r.actionCooldown < CooldownLimit
func isMovementReady*(r: Robot): bool = r.movementCooldown < CooldownLimit

# ---------------------------------------------------------------------------
#  DecisionOps — the budget that replaces the JVM bytecode limit
# ---------------------------------------------------------------------------

proc spend*(r: Robot, n: int): bool {.discardable.} =
  ## Charged BEFORE each primitive and never inside one, so a primitive's
  ## RESULT is never a function of the remaining budget — only whether the
  ## chassis got to ask. When the budget runs out the robot's turn ends where
  ## it stands; it is not resumed mid-computation next turn, which is the one
  ## place this differs from the JVM (docs/RULES-BC23.md §Divergences item 1).
  if r.opsLeft < n: return false
  r.opsLeft -= n
  r.opsUsed += n
  true

# ---------------------------------------------------------------------------
#  The inventory
# ---------------------------------------------------------------------------

func totalAnchors*(r: Robot): int = r.standardAnchors + r.acceleratingAnchors

func weight*(r: Robot): int =
  r.totalAnchors * AnchorWeight + r.adamantium + r.mana + r.elixir

func capacity*(k: RobotType): int =
  ## `InternalRobot`'s constructor: a headquarters gets an UNBOUNDED
  ## inventory (`maxCapacity = -1`), a carrier 40, everything else 0.
  case k
  of rtHeadquarters: -1
  of rtCarrier: CarrierCapacity
  else: 0

func canAdd*(r: Robot, amount: int): bool =
  let cap = capacity(r.kind)
  if cap == -1: true else: r.weight + amount <= cap

func resourceOf*(r: Robot, t: Resource): int =
  case t
  of resAdamantium: r.adamantium
  of resMana: r.mana
  of resElixir: r.elixir
  of resNone: 0

func numAnchors*(r: Robot, a: AnchorType): int =
  case a
  of anStandard: r.standardAnchors
  of anAccelerating: r.acceleratingAnchors
  of anNone: 0

func typeAnchor*(r: Robot): AnchorType =
  ## `InternalRobot.getTypeAnchor`: STANDARD first, then ACCELERATING.
  if r.standardAnchors > 0: anStandard
  elif r.acceleratingAnchors > 0: anAccelerating
  else: anNone

proc addAnchor*(r: Robot, a: AnchorType) =
  case a
  of anStandard: r.standardAnchors += 1
  of anAccelerating: r.acceleratingAnchors += 1
  of anNone: discard

proc releaseAnchor*(r: Robot, a: AnchorType) =
  case a
  of anStandard: r.standardAnchors -= 1
  of anAccelerating: r.acceleratingAnchors -= 1
  of anNone: discard

# ---------------------------------------------------------------------------
#  Team resources
# ---------------------------------------------------------------------------

func teamResource*(w: World, t: Team, r: Resource): int =
  case r
  of resAdamantium: w.stats.adamantium[ord(t)]
  of resMana: w.stats.mana[ord(t)]
  of resElixir: w.stats.elixir[ord(t)]
  of resNone: 0

proc addTeamResource*(w: World, t: Team, r: Resource, amount: int) =
  ## `TeamInfo.addResource`, which THROWS rather than clamping when a spend
  ## would take a team negative. Every caller checks first; a raise here means
  ## a legality bug, not a game state, and the server turns it into
  ## `results.reason = fault`.
  if r == resNone:
    if amount != 0:
      raise newException(BattlecodeError, "bc23: can't add no resource")
    return
  let o = ord(t)
  case r
  of resAdamantium:
    if w.stats.adamantium[o] + amount < 0:
      raise newException(BattlecodeError, "bc23: invalid adamantium change")
    w.stats.adamantium[o] += amount
  of resMana:
    if w.stats.mana[o] + amount < 0:
      raise newException(BattlecodeError, "bc23: invalid mana change")
    w.stats.mana[o] += amount
  of resElixir:
    if w.stats.elixir[o] + amount < 0:
      raise newException(BattlecodeError, "bc23: invalid elixir change")
    w.stats.elixir[o] += amount
  of resNone: discard

proc addResourceAmount*(w: World, r: Robot, t: Resource, amount: int) =
  ## `InternalRobot.addResourceAmount`: the TEAM total moves first, then the
  ## robot's own inventory. Both, always — which is why a resource counts
  ## toward the tiebreak the moment a carrier mines it and disappears from the
  ## team total the moment that carrier is destroyed.
  w.addTeamResource(r.team, t, amount)
  case t
  of resAdamantium: r.adamantium += amount
  of resMana: r.mana += amount
  of resElixir: r.elixir += amount
  of resNone: discard

# ---------------------------------------------------------------------------
#  Cooldowns
# ---------------------------------------------------------------------------

func cooldownMultiplier*(w: World, l: Loc, t: Team): int =
  w.tempo.multiplier(w.idx(l), t)

func cooldownWithMultiplier*(w: World, base: int, l: Loc, t: Team): int =
  applyMultiplier(base, w.cooldownMultiplier(l, t))

proc addActionCooldownTurns*(w: World, r: Robot, base: int) =
  r.actionCooldown += w.cooldownWithMultiplier(base, r.loc, r.team)

proc addMovementCooldownTurns*(w: World, r: Robot) =
  ## The base is read from the robot's CURRENT cargo weight and the multiplier
  ## from the tile it is standing on — which, because `move` calls this AFTER
  ## `setLocation`, is the DESTINATION.
  let base = baseMovementCooldown(r.kind, r.weight)
  r.movementCooldown += w.cooldownWithMultiplier(base, r.loc, r.team)

# ---------------------------------------------------------------------------
#  Spawning and destruction
# ---------------------------------------------------------------------------

proc placeRobot(w: World, r: Robot) =
  w.occupant[w.idx(r.loc)] = r

proc clearTile(w: World, l: Loc) =
  w.occupant[w.idx(l)] = nil

proc spawnRobot*(w: World, id: int, kind: RobotType, l: Loc,
                 t: Team): Robot {.discardable.} =
  var r = Robot(id: id, team: t, kind: kind, loc: l,
                health: maxHealth(kind), alive: true,
                actionCooldown: CooldownLimit,
                movementCooldown: CooldownLimit,
                opsLeft: budgetFor(kind))
  r.scaffoldRng = initJavaRandom(6147)
  w.robotsById[id] = r
  w.execOrder.add(id)
  w.placeRobot(r)
  if kind == rtHeadquarters:
    w.headquarters[ord(t)].add(id)
  r

proc destroyRobot*(w: World, id: int) =
  ## `GameWorld.destroyRobot`: the tile is cleared, the id is removed from the
  ## exec order BY VALUE (the first entry equal to it, preserving the order of
  ## the survivors) and every resource the robot was carrying comes OFF THE
  ## TEAM TOTAL.
  if not w.robotsById.hasKey(id): return
  let r = w.robotsById[id]
  if w.getRobot(r.loc) == r:
    w.clearTile(r.loc)
  for k in 0 ..< w.execOrder.len:
    if w.execOrder[k] == id:
      w.execOrder.delete(k)
      break
  for t in RealResources:
    w.addResourceAmount(r, t, -r.resourceOf(t))
  r.alive = false
  w.robotsById.del(id)
  w.stats.robotsLost[ord(r.team)] += 1
  w.lostThisRound[ord(r.team)] += 1
  if r.kind == rtLauncher:
    w.stats.launchersLost[ord(r.team)] += 1
    w.launchersLostThisRound[ord(r.team)] += 1

proc addHealth*(w: World, r: Robot, amount: int) =
  ## `InternalRobot.addHealth`. A HEADQUARTERS IS IMMUNE — the method returns
  ## immediately, so its nominal 1 HP is never touched and there is no
  ## elimination condition in this year at all.
  if r.kind == rtHeadquarters: return
  r.health += amount
  r.health = min(r.health, maxHealth(r.kind))
  if r.health <= 0:
    w.destroyRobot(r.id)

# ---------------------------------------------------------------------------
#  The winner
# ---------------------------------------------------------------------------

proc setWinner*(w: World, t: Team, d: Domination) =
  w.winner = t
  w.hasWinner = true
  w.domination = d

func islandsOwned*(w: World, t: Team): int =
  for isl in w.islands:
    if isl.isOwnedBy(t): result += 1

proc registerAnchorPlaced(w: World, t: Team) =
  ## `TeamInfo.placeAnchor`: both counters move and THE CONQUEST TEST FIRES
  ## IMMEDIATELY, mid-turn. The engine then re-counts the islands owned and
  ## throws `InternalError` if the two disagree; the port keeps that
  ## assertion as a `fault` invariant.
  let o = ord(t)
  w.stats.totalAnchorsPlaced[o] += 1
  w.stats.currentAnchorsPlaced[o] += 1
  if conquestReached(w.stats.currentAnchorsPlaced[o], w.islands.len):
    if not conquestReached(w.islandsOwned(t), w.islands.len):
      raise newException(BattlecodeError, "bc23: reporting incorrect win")
    if not w.hasWinner:
      w.setWinner(t, dfConquest)

# ---------------------------------------------------------------------------
#  Islands — the world-level half of `Island.advanceTurn`
# ---------------------------------------------------------------------------

iterator locsAffected*(w: World, islandIdx: int): Loc =
  ## `Island.getLocsAffected`: every tile within `DISTANCE_SQUARED_FROM_ISLAND`
  ## of ANY island tile, and THE EMPTY SET when no anchor is planted. The
  ## engine's set is a `HashSet`, so a tile in range of two island tiles is
  ## yielded once; the port de-duplicates the same way and walks in ascending
  ## tile index so the sweep is deterministic (D2).
  if w.islands[islandIdx].anchor != anNone:
    var seen = newSeq[bool](w.width * w.height)
    var order: seq[int]
    for tile in w.islands[islandIdx].tiles:
      for l in w.locationsWithinRadiusSquared(tile, DistanceSquaredFromIsland):
        let i = w.idx(l)
        if not seen[i]:
          seen[i] = true
          order.add(i)
    order.sort()
    for i in order:
      yield w.indexToLoc(i)

proc addAnchorBoostFor(w: World, islandIdx: int) =
  let t = w.islands[islandIdx].ownerTeam()
  let id = w.islands[islandIdx].id
  for l in w.locsAffected(islandIdx):
    w.tempo.addAnchorBoost(w.idx(l), t, id)

proc removeAnchorBoostFor(w: World, islandIdx: int) =
  let t = w.islands[islandIdx].ownerTeam()
  let id = w.islands[islandIdx].id
  for l in w.locsAffected(islandIdx):
    w.tempo.removeAnchorBoost(w.idx(l), t, id)

proc islandAdvanceTurn*(w: World, islandIdx: int) =
  ## `Island.advanceTurn`, statement for statement.
  if w.islands[islandIdx].owner == 0: return
  let owner = w.islands[islandIdx].ownerTeam()
  var occupied: array[2, int]
  for tile in w.islands[islandIdx].tiles:
    let r = w.getRobot(tile)
    if r != nil: occupied[ord(r.team)] += 1
  let next = w.islands[islandIdx].advanceHealth(
    occupied[ord(owner)], occupied[ord(owner.other())])
  w.islands[islandIdx].health = next
  if next <= 0:
    w.stats.currentAnchorsPlaced[ord(owner)] -= 1
    w.stats.anchorsLost[ord(owner)] += 1
    w.stats.islandsLost[ord(owner)] += 1
    if w.islands[islandIdx].anchor == anAccelerating:
      w.removeAnchorBoostFor(islandIdx)
    discard w.beat(BeatIslandLost, "island_lost", ord(owner),
      w.islands[islandIdx].id,
      w.currentRound - w.islands[islandIdx].capturedRound,
      $(w.islandsOwned(owner) - 1))
    w.islands[islandIdx].owner = 0
    w.islands[islandIdx].anchor = anNone
    w.islands[islandIdx].health = 0
  ## A just-neutralised island heals nobody: `getLocsAffected()` is empty once
  ## the anchor is gone, which is why the engine's `anchorPlanted` dereference
  ## cannot fault. The port keeps that shape.
  let heal = AnchorSpecs[w.islands[islandIdx].anchor].healingAmount
  let freq = AnchorSpecs[w.islands[islandIdx].anchor].healingFrequency
  if w.islands[islandIdx].anchor != anNone and freq > 0 and
      w.currentRound mod freq == 0:
    for l in w.locsAffected(islandIdx):
      let r = w.getRobot(l)
      if r != nil and r.team == owner:
        let before = r.health
        w.addHealth(r, heal)
        if r.alive:
          w.stats.anchorHeals[ord(owner)] += r.health - before

proc doPlaceAnchor*(w: World, r: Robot): bool {.discardable.} =
  ## `RobotControllerImpl.placeAnchor` + `Island.placeAnchor`. The cooldown is
  ## charged AFTER the effect.
  if not r.isActionReady() or r.kind != rtCarrier:
    w.refusedActions += 1
    return false
  let islandIdx = w.islandAt(r.loc)
  if islandIdx < 0 or r.totalAnchors == 0:
    w.refusedActions += 1
    return false
  let held = r.typeAnchor()
  if not w.islands[islandIdx].canPlaceAnchor(r.team):
    w.refusedActions += 1
    return false
  let prevOwned = w.islands[islandIdx].isOwnedBy(r.team)
  w.islands[islandIdx].owner = ord(r.team) + 1
  if w.islands[islandIdx].anchor != anAccelerating and held == anAccelerating:
    w.islands[islandIdx].anchor = held
    w.addAnchorBoostFor(islandIdx)
  ## A STANDARD anchor placed over our own ACCELERATING one leaves the
  ## `-0.15` boost registered forever, because the removal path only fires for
  ## an anchor that is still ACCELERATING. Engine behaviour, ported literally
  ## (docs/RULES-BC23.md §Divergences item 15).
  w.islands[islandIdx].anchor = held
  w.islands[islandIdx].health = AnchorSpecs[held].totalHealth
  if not prevOwned:
    w.islands[islandIdx].capturedRound = w.currentRound
    w.stats.islandsCaptured[ord(r.team)] += 1
    if held == anAccelerating:
      w.stats.acceleratingAnchorsPlaced[ord(r.team)] += 1
    if w.stats.firstAnchorRound[ord(r.team)] == 0:
      w.stats.firstAnchorRound[ord(r.team)] = w.currentRound
    for hqId in w.headquarters[ord(r.team.other())]:
      if w.existsRobot(hqId):
        w.stats.capturedDistanceSum[ord(r.team)] +=
          chebyshev(r.loc, w.robotsById[hqId].loc)
        w.stats.capturedDistanceCount[ord(r.team)] += 1
        break
    w.registerAnchorPlaced(r.team)
    discard w.beat(BeatIslandCaptured, "island_captured", ord(r.team),
      w.islands[islandIdx].id, w.islandsOwned(r.team),
      $ord(held) & ":" & $w.islands[islandIdx].area & ":" &
        $islandsToWin(w.islands.len))
  r.releaseAnchor(held)
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  true

# ---------------------------------------------------------------------------
#  Rule 3.2 — the legal actions, in the engine's own order
# ---------------------------------------------------------------------------

proc canMove*(w: World, r: Robot, d: Dir): bool =
  if not r.isMovementReady(): return false
  if r.kind == rtHeadquarters: return false
  let l = r.loc + d
  if not w.onTheMap(l): return false
  if w.isLocationOccupied(l): return false
  w.isPassable(l)

proc doMove*(w: World, r: Robot, d: Dir): bool {.discardable.} =
  if not w.canMove(r, d):
    w.refusedActions += 1
    return false
  let dest = r.loc + d
  w.clearTile(r.loc)
  r.loc = dest
  w.placeRobot(r)
  ## The multiplier is read at the DESTINATION, after the move.
  w.addMovementCooldownTurns(r)
  true

proc canBuildRobot*(w: World, r: Robot, kind: RobotType, l: Loc): bool =
  if not w.canActLocation(r, l): return false
  if not r.isActionReady(): return false
  if r.kind != rtHeadquarters: return false
  if kind == rtHeadquarters: return false
  for t in RealResources:
    if r.resourceOf(t) < buildCost(kind, t): return false
  if w.isLocationOccupied(l): return false
  w.isPassable(l)

proc doBuildRobot*(w: World, r: Robot, kind: RobotType,
                   l: Loc): Robot {.discardable.} =
  if not w.canBuildRobot(r, kind, l):
    w.refusedActions += 1
    return nil
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  for t in RealResources:
    w.addResourceAmount(r, t, -buildCost(kind, t))
  let built = w.spawnRobot(w.idGen.nextId(), kind, l, r.team)
  let o = ord(r.team)
  w.stats.unitsBuilt[o] += 1
  case kind
  of rtCarrier:
    w.stats.carriersBuilt[o] += 1
    if w.currentRound <= 400: w.stats.carriersBuiltBy400[o] += 1
  of rtLauncher:
    w.stats.launchersBuilt[o] += 1
    if w.currentRound <= 400: w.stats.launchersBuiltBy400[o] += 1
  of rtAmplifier: w.stats.amplifiersBuilt[o] += 1
  of rtDestabilizer:
    w.stats.destabilizersBuilt[o] += 1
    if not w.elixirUnitSeen[o][0]:
      w.elixirUnitSeen[o][0] = true
      discard w.beat(BeatFirstElixirUnit, "first_elixir_unit", o, 0)
  of rtBooster:
    w.stats.boostersBuilt[o] += 1
    if not w.elixirUnitSeen[o][1]:
      w.elixirUnitSeen[o][1] = true
      discard w.beat(BeatFirstElixirUnit, "first_elixir_unit", o, 1)
  else: discard
  built

proc canBuildAnchor*(w: World, r: Robot, a: AnchorType): bool =
  if not r.isActionReady(): return false
  if r.kind != rtHeadquarters: return false
  if a == anNone: return false
  for t in RealResources:
    if r.resourceOf(t) < anchorCost(a, t): return false
  true

proc doBuildAnchor*(w: World, r: Robot, a: AnchorType): bool {.discardable.} =
  if not w.canBuildAnchor(r, a):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  for t in RealResources:
    w.addResourceAmount(r, t, -anchorCost(a, t))
  r.addAnchor(a)
  w.stats.anchorsBuilt[ord(r.team)] += 1
  discard w.beat(BeatAnchorBuilt, "anchor_built", ord(r.team), ord(a),
    r.numAnchors(a))
  true

proc canAttack*(w: World, r: Robot, l: Loc): bool =
  if not w.canActLocation(r, l): return false
  if not r.isActionReady(): return false
  if not canAttackType(r.kind): return false
  if r.kind == rtCarrier and r.weight == 0: return false
  true

proc emptyCarrier(w: World, r: Robot) =
  ## `InternalCarrier.emptyResources`: every resource comes off the CARRIER
  ## and off the TEAM, and every anchor it was carrying is destroyed.
  for t in RealResources:
    let amount = r.resourceOf(t)
    if amount != 0:
      w.stats.resourcesThrown[ord(r.team)] += amount
      w.addResourceAmount(r, t, -amount)
  r.standardAnchors = 0
  r.acceleratingAnchors = 0

proc doAttack*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  if not w.canAttack(r, l):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  let target = w.getRobot(l)
  let hits = target != nil and target.team != r.team and
    target.kind != rtHeadquarters
  if hits:
    let dmg =
      if r.kind == rtCarrier: carrierThrowDamage(r.weight)
      else: RobotSpecs[r.kind].damage
    let before = target.health
    w.addHealth(target, -dmg)
    let dealt = before - (if target.alive: target.health else: 0)
    w.stats.damageDealt[ord(r.team)] += dealt
    if r.kind == rtCarrier:
      w.stats.throwDamage[ord(r.team)] += dealt
    if target.kind == rtCarrier:
      w.stats.carrierDamageTaken[ord(target.team)] += dealt
  if r.kind == rtCarrier:
    ## The cargo is gone whether it hit or not.
    w.emptyCarrier(r)
  true

proc canBoost*(w: World, r: Robot): bool =
  r.isActionReady() and r.kind == rtBooster

proc doBoost*(w: World, r: Robot): bool {.discardable.} =
  ## `RobotControllerImpl.boost`: the field is registered FIRST and the 140 is
  ## charged AFTER, so a booster's own cooldown is discounted by the boost it
  ## just cast.
  if not w.canBoost(r):
    w.refusedActions += 1
    return false
  let lastRound = w.currentRound + BoosterDuration
  for l in w.locationsWithinRadiusSquared(r.loc, BoosterRadiusSquared):
    w.tempo.addBoost(w.idx(l), r.team, lastRound)
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  w.stats.boostsCast[ord(r.team)] += 1
  if w.stats.boostsCast[ord(r.team)] == 1 or
      w.stats.boostsCast[ord(r.team)] mod 20 == 0:
    discard w.beat(BeatBoostField, "boost_field", ord(r.team),
      r.loc.x * 100 + r.loc.y,
      w.tempo.boosts[ord(r.team)][w.idx(r.loc)].len)
  true

proc canDestabilize*(w: World, r: Robot, l: Loc): bool =
  w.canActLocation(r, l) and r.isActionReady() and r.kind == rtDestabilizer

proc doDestabilize*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  ## `RobotControllerImpl.destabilize`: the field is registered FIRST and the
  ## 70 is charged AFTER — but on the DESTABILIZER'S OWN tile and against its
  ## own team's multiplier, which the destabilisation does not touch (it slows
  ## the ENEMY), so the discount a booster gets does not apply here.
  if not w.canDestabilize(r, l):
    w.refusedActions += 1
    return false
  let lastRound = w.currentRound + DestabilizerDuration
  let victim = r.team.other()
  for tile in w.locationsWithinRadiusSquared(l, DestabilizerRadiusSquared):
    w.tempo.addDestabilize(w.idx(tile), victim, lastRound)
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  w.stats.destabilizesCast[ord(r.team)] += 1
  true

proc canCollectResource*(w: World, r: Robot, l: Loc, amount: int): bool =
  if not w.canActLocation(r, l): return false
  if not r.isActionReady(): return false
  if amount < -1: return false
  if r.kind != rtCarrier: return false
  if not w.isWell(l): return false
  if not r.loc.isAdjacentTo(l): return false
  let rate = w.wellAt[w.idx(l)].rate()
  let want = if amount == -1: rate else: amount
  if want > rate: return false
  r.canAdd(want)

proc doCollectResource*(w: World, r: Robot, l: Loc,
                        amount: int): bool {.discardable.} =
  if not w.canCollectResource(r, l, amount):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  let well = w.wellAt[w.idx(l)]
  let kind = well.kind
  let rate = well.rate()
  let want = if amount == -1: rate else: amount
  w.addResourceAmount(r, kind, want)
  let o = ord(r.team)
  case kind
  of resAdamantium: w.stats.adamantiumMined[o] += want
  of resMana: w.stats.manaMined[o] += want
  of resElixir: w.stats.elixirMined[o] += want
  of resNone: discard
  true

proc canTransferResource*(w: World, r: Robot, l: Loc, t: Resource,
                          amount: int): bool =
  if not w.canActLocation(r, l): return false
  if not r.isActionReady(): return false
  if r.kind != rtCarrier: return false
  if amount == 0: return false
  if amount > 0 and r.resourceOf(t) < amount: return false
  if not r.loc.isAdjacentTo(l): return false
  if amount < 0:
    if not r.canAdd(-amount): return false
    if not w.isHeadquarters(l): return false
    if w.getRobot(l).team != r.team: return false
    if w.getRobot(l).resourceOf(t) < -amount: return false
  w.isWell(l) or w.isHeadquarters(l)

proc doTransferResource*(w: World, r: Robot, l: Loc, t: Resource,
                         amount: int): bool {.discardable.} =
  if not w.canTransferResource(r, l, t, amount):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  if w.isWell(l):
    let i = w.idx(l)
    let before = w.wellAt[i].kind
    let wasUpgraded = w.wellAt[i].upgraded
    w.wellAt[i].addResourceAmount(t, amount)
    if before != resElixir and w.wellAt[i].kind == resElixir:
      w.stats.wellsTransformed[ord(r.team)] += 1
      discard w.beat(BeatWellTransformed, "well_transformed", ord(r.team),
        l.x * 100 + l.y, ord(before))
    if not wasUpgraded and w.wellAt[i].upgraded:
      w.stats.wellsUpgraded[ord(r.team)] += 1
      discard w.beat(BeatWellUpgraded, "well_upgraded", ord(r.team),
        l.x * 100 + l.y, ord(w.wellAt[i].kind))
    ## A positive transfer into a well REMOVES the resource from the team
    ## total for good: the well swallows it and `addResourceAmount(-amount)`
    ## below is the only bookkeeping there is.
  elif w.isHeadquarters(l):
    let hq = w.getRobot(l)
    w.addResourceAmount(hq, t, amount)
    if amount > 0 and hq.team == r.team:
      w.stats.resourcesBanked[ord(r.team)] += amount
  w.addResourceAmount(r, t, -amount)
  true

proc canTakeAnchor*(w: World, r: Robot, l: Loc, a: AnchorType): bool =
  if not w.canActLocation(r, l): return false
  if not r.isActionReady(): return false
  if r.kind != rtCarrier: return false
  if a == anNone: return false
  if not w.isHeadquarters(l): return false
  if w.getRobot(l).team != r.team: return false
  if not r.loc.isAdjacentTo(l): return false
  if w.getRobot(l).numAnchors(a) < 1: return false
  ## An anchor weighs the carrier's WHOLE capacity, so the carrier must be
  ## completely empty.
  r.canAdd(AnchorWeight)

proc doTakeAnchor*(w: World, r: Robot, l: Loc,
                   a: AnchorType): bool {.discardable.} =
  if not w.canTakeAnchor(r, l, a):
    w.refusedActions += 1
    return false
  let hq = w.getRobot(l)
  hq.releaseAnchor(a)
  r.addAnchor(a)
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  true

proc canReturnAnchor*(w: World, r: Robot, l: Loc): bool =
  if not w.canActLocation(r, l): return false
  if not r.isActionReady(): return false
  if r.kind != rtCarrier: return false
  if not w.isHeadquarters(l): return false
  if w.getRobot(l).team != r.team: return false
  if not r.loc.isAdjacentTo(l): return false
  r.typeAnchor() != anNone

proc doReturnAnchor*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  if not w.canReturnAnchor(r, l):
    w.refusedActions += 1
    return false
  let hq = w.getRobot(l)
  let a = r.typeAnchor()
  hq.addAnchor(a)
  r.releaseAnchor(a)
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  true

proc disintegrate*(w: World, r: Robot) =
  ## `RobotControllerImpl.disintegrate` throws `RobotDeathException`, which
  ## the control provider turns into a terminated flag; `updateRobot` then
  ## destroys the robot at the END of its own turn.
  r.disintegrated = true

# ---------------------------------------------------------------------------
#  Sensing — free against `DecisionOps` only
# ---------------------------------------------------------------------------

iterator senseNearbyRobots*(w: World, r: Robot, r2: int,
                            team: int = -1): Robot =
  ## `GameWorld.getAllRobotsWithinRadiusSquared` filtered by
  ## `canSenseLocation`, in the engine's own scan order. `team` is -1 for
  ## "either", 0 for A and 1 for B.
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    let other = w.getRobot(l)
    if other != nil and w.canSenseLocation(r, l):
      if team < 0 or ord(other.team) == team:
        yield other

iterator senseNearbyWells*(w: World, r: Robot, r2: int): Loc =
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    if w.isWell(l) and w.canSenseLocation(r, l):
      yield l

iterator senseNearbyIslands*(w: World, r: Robot, r2: int): int =
  ## `GameWorld.getAllIslandsWithinVision`, de-duplicated by island index and
  ## yielded in the scan order the engine's list would carry.
  var seen: seq[int]
  for l in w.locationsWithinRadiusSquared(r.loc, r2):
    let i = w.islandAt(l)
    if i >= 0 and w.canSenseLocation(r, l) and i notin seen:
      seen.add(i)
      yield i

# ---------------------------------------------------------------------------
#  Construction
# ---------------------------------------------------------------------------

proc newWorld*(spec: MapSpec, maxRounds: int): World =
  let size = spec.width * spec.height
  var w = World(
    map: spec, width: spec.width, height: spec.height,
    currentRound: 0, maxRounds: maxRounds, running: true,
    idGen: initIdGenerator(spec.randomSeed),
    rand: initJavaRandom(spec.randomSeed),
    symmetry: spec.symmetry,
    walls: spec.walls, clouds: spec.clouds,
    islandIdAt: spec.islandIds,
    winner: teamA, hasWinner: false, domination: dfNone,
    hashChain: 0xCBF29CE484222325'u64)
  w.currents = newSeq[Dir](size)
  for i in 0 ..< size:
    w.currents[i] = DirectionOrder[max(0, min(spec.currents[i], 8))]
  w.wellAt = newSeq[Well](size)
  for i in 0 ..< size:
    let kind = spec.resources[i]
    if kind != 0:
      w.wellAt[i] = newWell(Resource(kind))
  w.occupant = newSeq[Robot](size)
  w.robotsById = initTable[int, Robot]()
  w.islandIndex = initTable[int, int]()
  w.tempo = initTempoField(size)

  ## The initial headquarters, in the map file's ASCENDING ID order — which is
  ## the order `LiveMap`'s constructor imposes and therefore the initial exec
  ## order.
  for b in spec.initialBodies:
    let team = if b.team == 1: teamA else: teamB
    w.spawnRobot(b.id, RobotType(b.kind), loc(b.x, b.y), team)

  ## The island table, built by walking `islandIds` from index 0 upward, then
  ## sorted ASCENDING BY ISLAND ID so every sweep over it is deterministic
  ## (D2: the engine's `islandIdToIsland.values()` is a HashMap sweep).
  var ids: seq[int]
  var tilesById = initTable[int, seq[Loc]]()
  for i in 0 ..< size:
    let id = spec.islandIds[i]
    if id == 0: continue
    if not tilesById.hasKey(id):
      tilesById[id] = @[]
      ids.add(id)
    tilesById[id].add(w.indexToLoc(i))
  ids.sort()
  for id in ids:
    w.islandIndex[id] = w.islands.len
    w.islands.add(Island(id: id, tiles: tilesById[id], owner: 0,
                         anchor: anNone, health: 0))

  ## The cloud multiplier is baked in at world construction, for both teams,
  ## exactly as `GameWorld`'s constructor does it. Clouds are never created or
  ## destroyed during a game.
  for i in 0 ..< size:
    if w.clouds[i]:
      w.tempo.bakeCloud(i)

  when defined(bc23BrokenChassis):
    w.brokenChassis = true
  w

# ---------------------------------------------------------------------------
#  Per-team readouts the round loop, the renderer and the chrome all use
# ---------------------------------------------------------------------------

func robotsAlive*(w: World, t: Team): int =
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == t and r.kind != rtHeadquarters: result += 1

func robotCountByType*(w: World, t: Team, k: RobotType): int =
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == t and r.kind == k: result += 1

func totalHealth*(w: World, t: Team): int =
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == t and r.kind != rtHeadquarters: result += r.health

func cargoWeight*(w: World, t: Team): int =
  for id in w.execOrder:
    let r = w.robotsById[id]
    if r.team == t: result += r.weight

func anchorsInStock*(w: World, t: Team): int =
  for id in w.headquarters[ord(t)]:
    if w.existsRobot(id): result += w.robotsById[id].totalAnchors

func islandsHeld*(w: World, t: Team): int = w.islandsOwned(t)

func islandsNeutral*(w: World): int =
  for isl in w.islands:
    if isl.owner == 0: result += 1

func islandChecksum*(w: World): uint64 =
  result = 0xCBF29CE484222325'u64
  for isl in w.islands:
    for v in [isl.id, isl.owner, ord(isl.anchor), isl.health]:
      result = (result xor uint64(v and 0xFFFF)) * 0x100000001B3'u64

func wellChecksum*(w: World): uint64 =
  result = 0xCBF29CE484222325'u64
  for i in 0 ..< w.wellAt.len:
    if not w.wellAt[i].present: continue
    for v in [i, ord(w.wellAt[i].kind), w.wellAt[i].rate(),
              w.wellAt[i].adamantium, w.wellAt[i].mana, w.wellAt[i].elixir]:
      result = (result xor uint64(v and 0xFFFFFF)) * 0x100000001B3'u64

func sharedArrayChecksum*(w: World): uint64 =
  result = 0xCBF29CE484222325'u64
  for t in 0 .. 1:
    for i in 0 ..< SharedArrayLength:
      result = (result xor uint64(w.stats.sharedArray[t][i] and 0xFFFF)) *
        0x100000001B3'u64

proc noteFirstAction*(w: World, t: Team, action: int) =
  if w.firstActionSeen[ord(t)]: return
  w.firstActionSeen[ord(t)] = true
  discard w.beat(BeatFirstAction, "first_action", ord(t), action,
    w.currentRound)
