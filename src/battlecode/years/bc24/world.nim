## The Battlecode 2024 "Breadwars" world: state, geometry and every legality
## rule.
##
## A behaviour-for-behaviour port of `battlecode/world/GameWorld.java`,
## `world/InternalRobot.java`, `world/RobotControllerImpl.java`,
## `world/TeamInfo.java`, `world/Flag.java`, `world/Trap.java`,
## `world/ObjectInfo.java` and `world/LiveMap.java` at commit
## `166c79bbf4156c866caf434062cb1f403c01695f` (spec 3.0.5/3.0.6), together with
## the pieces of `common/MapLocation.java` and `common/Direction.java` the
## rules depend on. The port is the authority at runtime; the Java engine
## survives only as the `parity-oracle-bc24` CI job (docs/PARITY.md).
##
## Six things in here look like details and are not:
##
## * **Ducks are never destroyed — death is a DESPAWN.** The 100 robots are
##   created `A0, B0, A1, B1, …, A49, B49` in the world's constructor and the
##   exec order never changes for the whole game. A jailed duck still takes a
##   turn: it still decays its cooldowns, and it may still read and write the
##   shared array.
## * **`spawn()` does NOT reset either cooldown.** The engine's two lines are
##   commented out. It is harmless only because 25 jail turns already decayed
##   them to 0; the port reproduces the engine, not the intent.
## * **`flag.getLoc() != flag.getStartLoc()` is a Java OBJECT IDENTITY test.**
##   It is true exactly when the flag has moved since the last time
##   `moveFlagSetStartLoc` set both to the same object. The port carries an
##   explicit `locIsStartRef` and never compares coordinates, so a flag dropped
##   exactly on its own start tile still runs a return timer.
## * **The kill bounty is paid on the ATTACKER's territory test**, computed
##   BEFORE the damage lands, from the pre-damage health.
## * **A build onto an enemy EXPLOSIVE spends the crumbs and the cooldown and
##   then places nothing**, queueing the trap as an *interact* trigger.
## * **`getAllLocationsWithinRadiusSquared`'s scan order is load-bearing**: x
##   ascending outer, y ascending inner. It fixes which tile the flag-broadcast
##   re-roll draws and which tiles a water trap floods.

import std/[math, strutils]
import ../../sim_types, ../../rng
import constants, skills

export constants, skills, rng

type
  Team* = enum
    teamA = 0
    teamB = 1

  Dir* = enum
    ## Ordinals match `common/Direction.java`; `allDirections()` is `values()`,
    ## so it INCLUDES `CENTER`.
    dNorth = 0
    dNortheast
    dEast
    dSoutheast
    dSouth
    dSouthwest
    dWest
    dNorthwest
    dCenter

  Symmetry* = enum
    ## The map file's own declared value: `schema/battlecode.fbs` says
    ## "0 for rotation, 1 for horizontal, 2 for vertical". The 2024 engine
    ## never reads it for a rule; the chassis steers by it and the map card
    ## reports it.
    symRotation = 0
    symHorizontal = 1
    symVertical = 2

  Loc* = object
    x*, y*: int

  Domination* = enum
    dfNone
    dfCapture = "capture"
    dfMoreFlagCaptures = "more_flag_captures"
    dfLevelSum = "level_sum"
    dfMoreBread = "more_bread"
    dfCoinFlip = "coin_flip"
      ## `WON_BY_DUBIOUS_REASONS`. `MORE_FLAGS_PICKED` and `RESIGNATION` are
      ## DEAD RUNGS in 2024 — `checkEndOfMatch` never calls the first and no
      ## action a doctrine can reach produces the second — so they are absent
      ## (docs/RULES-BC24.md §Divergences item 5).

  MapSpec* = object
    ## One converted `.map24`, as `data/maps/bc24/<name>.json` carries it.
    name*: string
    width*, height*: int
    randomSeed*: int
    symmetry*: Symmetry
    walls*: seq[bool]
    water*: seq[bool]
    dam*: seq[bool]
    crumbs*: seq[tuple[x, y, amount: int]]
    spawnLocations*: array[6, Loc]
      ## The file's own `spawnLocations` VecTable, alternating A,B — recorded
      ## for provenance.
    spawnCenters*: array[6, Loc]
      ## `LiveMap.getSpawnZoneCenters`, RE-DERIVED off the painted spawn-zone
      ## array in index-ascending order with A in the even slots. That order
      ## decides flag ids and therefore the broadcast re-roll order, so it is
      ## carried rather than recomputed from the file's table.

  Flag* = ref object
    id*: int              ## the tile index it was created at, as the engine does
    team*: Team
    loc*: Loc
    startLoc*: Loc
    broadcastLoc*: Loc
    carriedBy*: int       ## robot id, or -1
    droppedRounds*: int
    locIsStartRef*: bool
      ## Java's `flag.getLoc() == flag.getStartLoc()` object identity, made
      ## explicit. True only while `loc` IS the same object the start location
      ## points at: set by `moveFlagSetStartLoc`, cleared by every pickup,
      ## drop and reset.
    captured*: bool       ## removed from `allFlags`

  Trap* = ref object
    id*: int
    kind*: TrapKind
    loc*: Loc
    team*: Team

  Robot* = ref object
    id*: int
    team*: Team
    spawned*: bool
    loc*: Loc
    diedLocation*: Loc
    health*: int
    roundsAlive*: int
    actionCooldown*: int
    movementCooldown*: int
    spawnCooldown*: int
    attackExp*, buildExp*, healExp*: int
    everSpawned*: bool
    flag*: Flag
    trapsToTrigger*: seq[Trap]
    enteredTraps*: seq[bool]
    opsLeft*: int         ## the DecisionOps budget replacing the JVM limit
    execIndex*: int       ## 0..99, its slot in the fixed exec order

  TeamStats* = object
    ## `TeamInfo` plus the per-game counters `results.games[]` reports. The
    ## engine keeps only crumbs, captures, pickups, the shared array and the
    ## upgrades; everything else is telemetry and is never read by a rule.
    crumbs*: array[2, int]
    sharedArray*: array[2, array[SharedArrayLength, int]]
    flagsCaptured*: array[2, int]
    flagsPickedUp*: array[2, int]
    upgrades*: array[2, array[3, bool]]
      ## Index 0 = ATTACK (and its ACTION alias), 1 = CAPTURING, 2 = HEALING —
      ## `TeamInfo.makeGlobalUpgrade`'s own numbering, which `getDamage` and
      ## `getHeal` read by index.
    upgradePoints*: array[2, int]
    ## --- telemetry ---
    upgradeRound*: array[2, array[3, int]]
    upgradeFirstRound*: array[2, int]
    flagsDropped*: array[2, int]
    flagsReturned*: array[2, int]
    roundsCarrying*: array[2, int]
    crumbsCollected*: array[2, int]
    crumbsSpent*: array[2, int]
    crumbsSpentDig*: array[2, int]
    crumbsSpentFill*: array[2, int]
    crumbsSpentTraps*: array[2, int]
    crumbsBy700*: array[2, int]
    killCrumbs*: array[2, int]
    ducksSpawned*: array[2, int]
      ## DISTINCT ducks that ever spawned, not spawn events: the competence
      ## gate asks "spawned >= 45 distinct ducks", and a flock that respawns
      ## the same six ducks eight times each is exactly what that gate exists
      ## to fail.
    spawnEvents*: array[2, int]
    ducksJailed*: array[2, int]
    attacks*: array[2, int]
    damageDealt*: array[2, int]
    kills*: array[2, int]
    heals*: array[2, int]
    healDealt*: array[2, int]
    healToCarriers*: array[2, int]
    healToVeterans*: array[2, int]
    healsOffLowest*: array[2, int]
      ## Heals whose target was NOT the lowest-HP friendly duck in the
      ## healer's own heal radius. Under `heal_priority: wounded_first` this is
      ## STRUCTURALLY ZERO; under `attackers_first` or `carrier_first` it is
      ## positive, which is what makes the knob's teeth a fact rather than a
      ## statistic. Never read by a rule.
    trapsBuilt*: array[2, int]
    trapsBuiltByKind*: array[2, array[TrapKind, int]]
    trapsTriggered*: array[2, int]
    trapDamage*: array[2, int]
    tilesDug*: array[2, int]
    tilesFilled*: array[2, int]
    masteries*: array[2, int]
    pickupsBeforeRound700*: array[2, int]
    carriesLostToDeath*: array[2, int]
    escortCount*: array[2, int]
    escortClose*: array[2, int]
    escortSamples*: array[2, int]
    trapsNearOwnFlag*: array[2, int]
    trapsOnChoke*: array[2, int]
    setupFlagTeleports*: int
    roundsWithAnyCarry*: int

  World* = ref object
    map*: MapSpec
    width*, height*: int
    currentRound*: int
    maxRounds*: int
    running*: bool
    idGen*: IdGenerator
    rand*: JavaRandom
      ## `GameWorld.rand`, seeded from the MAP's own `randomSeed` exactly as
      ## the engine does. Used for the flag-broadcast re-roll and — replacing
      ## `setWinnerArbitrary`'s `Math.random()` — for the coin flip
      ## (docs/RULES-BC24.md §Divergences item 2).
    symmetry*: Symmetry
    walls*, water*, dam*: seq[bool]
    spawnZones*: seq[int8]      ## 0 none, 1 team A, 2 team B
    teamSides*: seq[int8]       ## 1 = A territory, 2 = B territory, 0 = dam
    crumbTiles*: seq[int32]
    occupant*: seq[Robot]
    trapLocations*: seq[Trap]
    trapTriggers*: seq[seq[Trap]]
    placedFlags*: seq[seq[Flag]]
    allFlags*: seq[Flag]
    trapId*: int
    robots*: seq[Robot]         ## the fixed exec order, 100 entries
    robotsById*: seq[Robot]     ## index by id - minId; see `robotById`
    minRobotId*: int
    spawnLocs*: array[2, seq[Loc]]
    stats*: TeamStats
    winner*: Team
    hasWinner*: bool
    domination*: Domination
    ## Replay/telemetry sinks — never read by a rule.
    events*: seq[tuple[round: int, kind: string, a, b, c: int, s: string]]
    hashChain*: uint64
    beatCount*: array[12, int]
    refusedActions*: int
      ## THE LEGALITY AUDIT. Every `do*` below re-checks its own `can*` and
      ## no-ops when it fails; this counts those no-ops. A chassis that emits
      ## an illegal order is a chassis whose orders were never checked, so
      ## `tests/test_bc24_baselines.nim` plays whole games and asserts this
      ## stays ZERO. Never read by a rule.
    opsUsedPeak*: int
      ## The most DecisionOps any duck spent in a single turn, sampled at the
      ## next beginning-of-turn. The same shard asserts it never exceeds the
      ## budget.
    trapWaveStep*: array[2, int]
    jailedAtRoundStart*: array[2, int]
    firstActionSeen*: array[2, array[2, bool]]
      ## [team][0 = during setup, 1 = after it]. `first_action` is emitted at
      ## most twice a clan, which is what keeps its per-game bound at four.
    masteryBeat*: array[2, array[SkillKind, array[3, bool]]]

const
  AllDirs* = [dNorth, dNortheast, dEast, dSoutheast,
              dSouth, dSouthwest, dWest, dNorthwest, dCenter]
  MoveDirs* = [dNorth, dNortheast, dEast, dSoutheast,
               dSouth, dSouthwest, dWest, dNorthwest]

# ---------------------------------------------------------------------------
#  Geometry
# ---------------------------------------------------------------------------

func dx*(d: Dir): int =
  case d
  of dNorth, dSouth, dCenter: 0
  of dNortheast, dEast, dSoutheast: 1
  of dSouthwest, dWest, dNorthwest: -1

func dy*(d: Dir): int =
  case d
  of dEast, dWest, dCenter: 0
  of dNorth, dNortheast, dNorthwest: 1
  of dSoutheast, dSouth, dSouthwest: -1

func opposite*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 4) mod 8)

func rotateLeft*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 7) mod 8)

func rotateRight*(d: Dir): Dir =
  if ord(d) >= 8: d else: Dir((ord(d) + 1) mod 8)

func loc*(x, y: int): Loc = Loc(x: x, y: y)
func `+`*(a: Loc, d: Dir): Loc = loc(a.x + d.dx, a.y + d.dy)
func `==`*(a, b: Loc): bool = a.x == b.x and a.y == b.y

func distanceSquaredTo*(a, b: Loc): int =
  let ddx = a.x - b.x
  let ddy = a.y - b.y
  ddx * ddx + ddy * ddy

func isWithinDistanceSquared*(a, b: Loc, r2: int): bool =
  a.distanceSquaredTo(b) <= r2

func chebyshev*(a, b: Loc): int =
  max(abs(a.x - b.x), abs(a.y - b.y))

func directionTo*(a, b: Loc): Dir =
  ## `MapLocation.directionTo`, ported with the engine's own 2.414 fan.
  let ddx = float64(b.x - a.x)
  let ddy = float64(b.y - a.y)
  if abs(ddx) >= 2.414 * abs(ddy):
    if ddx > 0: return dEast
    if ddx < 0: return dWest
    return dCenter
  elif abs(ddy) >= 2.414 * abs(ddx):
    if ddy > 0: return dNorth
    return dSouth
  elif ddx > 0:
    return (if ddy > 0: dNortheast else: dSoutheast)
  elif ddx < 0:
    return (if ddy > 0: dNorthwest else: dSouthwest)
  dCenter

func other*(t: Team): Team = (if t == teamA: teamB else: teamA)

func idx*(w: World, l: Loc): int = l.x + l.y * w.width
func indexToLoc*(w: World, i: int): Loc = loc(i mod w.width, i div w.width)
func onTheMap*(w: World, l: Loc): bool =
  l.x >= 0 and l.y >= 0 and l.x < w.width and l.y < w.height

iterator locationsWithinRadiusSquared*(w: World, center: Loc, r2: int): Loc =
  ## `GameWorld.getAllLocationsWithinRadiusSquaredWithoutMap`, verbatim: x
  ## ascending outer, y ascending inner, over the clamped `ceil(sqrt(r2)) + 1`
  ## box. THE ORDER IS LOAD-BEARING — it fixes which location the flag
  ## broadcast re-roll draws and the order a water trap floods in.
  let ceiled = int(ceil(sqrt(float64(max(0, r2))))) + 1
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

func isSetupPhase*(w: World): bool = w.currentRound <= SetupRounds

func getWall*(w: World, l: Loc): bool = w.walls[w.idx(l)]
func getWater*(w: World, l: Loc): bool = w.water[w.idx(l)]

func getDam*(w: World, l: Loc): bool =
  ## `GameWorld.getDam`: the dam only exists while the setup phase runs.
  if w.currentRound <= SetupRounds: w.dam[w.idx(l)] else: false

func isPassable*(w: World, l: Loc): bool =
  let i = w.idx(l)
  if w.currentRound <= SetupRounds:
    (not w.walls[i]) and (not w.water[i]) and (not w.dam[i])
  else:
    (not w.walls[i]) and (not w.water[i])

proc setWater*(w: World, l: Loc) = w.water[w.idx(l)] = true
proc setLand*(w: World, l: Loc) = w.water[w.idx(l)] = false

func getSpawnZone*(w: World, l: Loc): int = int(w.spawnZones[w.idx(l)])
func getTeamSide*(w: World, l: Loc): int = int(w.teamSides[w.idx(l)])
func getCrumbAmount*(w: World, l: Loc): int = int(w.crumbTiles[w.idx(l)])
proc removeCrumbs*(w: World, l: Loc) = w.crumbTiles[w.idx(l)] = 0

func inEnemyTerritory*(w: World, team: Team, l: Loc): bool =
  ## The kill-bounty test, spelled out: `getTeamSide(loc)` equals the value
  ## that names the OPPONENT's ground (A = 1, B = 2).
  w.getTeamSide(l) == (if team == teamA: 2 else: 1)

# ---------------------------------------------------------------------------
#  Robots
# ---------------------------------------------------------------------------

func getRobot*(w: World, l: Loc): Robot =
  if w.onTheMap(l): w.occupant[w.idx(l)] else: nil

func isLocationOccupied*(w: World, l: Loc): bool = w.getRobot(l) != nil

func robotById*(w: World, id: int): Robot =
  let i = id - w.minRobotId
  if i >= 0 and i < w.robotsById.len: w.robotsById[i] else: nil

func canSenseLocation*(w: World, r: Robot, l: Loc): bool =
  r.spawned and w.onTheMap(l) and
    r.loc.distanceSquaredTo(l) <= VisionRadiusSquared

func canActCooldown*(r: Robot): bool = r.actionCooldown < CooldownLimit
func canMoveCooldown*(r: Robot): bool = r.movementCooldown < CooldownLimit
func canSpawnCooldown*(r: Robot): bool = r.spawnCooldown < CooldownLimit

func hasFlag*(r: Robot): bool = r.flag != nil

func levelOf*(r: Robot, skill: SkillKind): int =
  case skill
  of skAttack: levelFor(skAttack, r.attackExp)
  of skBuild: levelFor(skBuild, r.buildExp)
  of skHeal: levelFor(skHeal, r.healExp)

func levelSumOf*(r: Robot): int =
  r.levelOf(skAttack) + r.levelOf(skBuild) + r.levelOf(skHeal)

func hasUpgrade*(w: World, team: Team, slot: int): bool =
  w.stats.upgrades[ord(team)][slot]

func getDamage*(w: World, r: Robot): int =
  damageFor(r.levelOf(skAttack), w.hasUpgrade(r.team, 0))

func getHeal*(w: World, r: Robot): int =
  healFor(r.levelOf(skHeal), w.hasUpgrade(r.team, 2))

# ---------------------------------------------------------------------------
#  Telemetry
# ---------------------------------------------------------------------------

proc emit*(w: World, kind: string, a = 0, b = 0, c = 0, s = "") =
  w.events.add((round: w.currentRound, kind: kind, a: a, b: b, c: c, s: s))

const
  BeatSetupEnd* = 0
  BeatFirstAction* = 1
  BeatFlagTaken* = 2
  BeatFlagDropped* = 3
  BeatFlagReturned* = 4
  BeatFlagCaptured* = 5
  BeatTrapWave* = 6
  BeatUpgrade* = 7
  BeatMastery* = 8
  BeatRout* = 9

  BeatBounds* = [2, 4, 24, 24, 24, 6, 20, 6, 9, 20, 0, 0]
    ## Per GAME, in the order above and in the design note's own event table.
    ## `tests/test_bc24_replay.nim` asserts every one of them against a real
    ## match, so a pathological game cannot produce a 20 MB replay.

proc beat*(w: World, slot: int, kind: string, a = 0, b = 0, c = 0,
           s = ""): bool {.discardable.} =
  if w.beatCount[slot] >= BeatBounds[slot]: return false
  w.beatCount[slot] += 1
  w.emit(kind, a, b, c, s)
  true

const Bc24ActionSpawn* = 0
const Bc24ActionMove* = 1
const Bc24ActionAttack* = 2
const Bc24ActionHeal* = 3
const Bc24ActionBuild* = 4
const Bc24ActionDig* = 5
const Bc24ActionFill* = 6
const Bc24ActionPickup* = 7
const Bc24ActionDrop* = 8
const Bc24ActionUpgrade* = 9
  ## The ordinals `years/dispatch.nim`'s `Bc24ActionNames` spells out, so
  ## `first_action.kind` has a DOCUMENTED VOCABULARY (the r1-F14 lesson).

proc noteFirstAction*(w: World, r: Robot, kind: int) =
  ## The first action each clan takes, once during the setup phase and once
  ## after it: four per game, which is the bound the replay test asserts.
  let phase = if w.isSetupPhase(): 0 else: 1
  if w.firstActionSeen[ord(r.team)][phase]: return
  w.firstActionSeen[ord(r.team)][phase] = true
  discard w.beat(BeatFirstAction, "first_action", ord(r.team), kind,
    w.currentRound)

proc mixHash*(w: World, v: int) =
  w.hashChain = (w.hashChain xor uint64(v and 0xFFFFFFFF)) *
    0x100000001B3'u64

# ---------------------------------------------------------------------------
#  Crumbs
# ---------------------------------------------------------------------------

proc addCrumbs*(w: World, team: Team, amount: int) =
  ## `TeamInfo.addBread`, which THROWS rather than clamping when a spend would
  ## take a team negative. Every caller checks first; a raise here means a
  ## legality bug, not a game state.
  if w.stats.crumbs[ord(team)] + amount < 0:
    raise newException(BattlecodeError, "bc24: invalid crumb change")
  w.stats.crumbs[ord(team)] += amount
  if amount > 0:
    w.stats.crumbsCollected[ord(team)] += amount
  else:
    w.stats.crumbsSpent[ord(team)] -= amount

func getCrumbs*(w: World, team: Team): int = w.stats.crumbs[ord(team)]

# ---------------------------------------------------------------------------
#  Flags — the raw state the actions and `flags.nim` both work through
# ---------------------------------------------------------------------------

proc addFlagAt*(w: World, l: Loc, f: Flag) =
  ## `GameWorld.addFlag`.
  w.placedFlags[w.idx(l)].add(f)
  f.loc = l
  f.locIsStartRef = false

proc removeFlagAt*(w: World, l: Loc, f: Flag) =
  let i = w.idx(l)
  for k in 0 ..< w.placedFlags[i].len:
    if w.placedFlags[i][k] == f:
      w.placedFlags[i].delete(k)
      return

func flagsAt*(w: World, l: Loc): seq[Flag] = w.placedFlags[w.idx(l)]
func hasFlagAt*(w: World, l: Loc): bool = w.placedFlags[w.idx(l)].len > 0

proc moveFlagSetStartLoc*(w: World, f: Flag, l: Loc) =
  ## `GameWorld.moveFlagSetStartLoc`: the carrier (if any) loses it first, the
  ## flag moves, and `startLoc` becomes THE SAME OBJECT as `loc` — which is
  ## what `locIsStartRef` records.
  if f.carriedBy >= 0:
    let carrier = w.robotById(f.carriedBy)
    if carrier != nil:
      carrier.flag = nil
    f.carriedBy = -1
    f.droppedRounds = 0
  w.removeFlagAt(f.loc, f)
  w.addFlagAt(l, f)
  f.startLoc = l
  f.locIsStartRef = true

# ---------------------------------------------------------------------------
#  Traps — the raw state
# ---------------------------------------------------------------------------

func getTrap*(w: World, l: Loc): Trap = w.trapLocations[w.idx(l)]
func hasTrap*(w: World, l: Loc): bool = w.trapLocations[w.idx(l)] != nil

proc placeTrapAt*(w: World, l: Loc, kind: TrapKind, team: Team) =
  ## `GameWorld.placeTrap`: register the trap on its own tile and in the
  ## trigger index over its `triggerRadius`.
  let trap = Trap(id: w.trapId, kind: kind, loc: l, team: team)
  w.trapId += 1
  w.trapLocations[w.idx(l)] = trap
  for adj in w.locationsWithinRadiusSquared(l, TrapSpecs[kind].triggerRadius):
    w.trapTriggers[w.idx(adj)].add(trap)

proc addTrapTrigger*(r: Robot, t: Trap, entered: bool) =
  r.trapsToTrigger.add(t)
  r.enteredTraps.add(entered)

# ---------------------------------------------------------------------------
#  Skills on a robot
# ---------------------------------------------------------------------------

proc incrementSkill*(w: World, r: Robot, skill: SkillKind) =
  ## `InternalRobot.incrementSkill`, verbatim — including THE MASTERY RULE: a
  ## skill stops gaining once its XP reaches its own level-3 threshold AND
  ## another skill has reached level 4.
  let before = r.levelOf(skill)
  case skill
  of skBuild:
    if r.buildExp < experienceFor(skBuild, 3) or
        (r.levelOf(skHeal) < 4 and r.levelOf(skAttack) < 4):
      r.buildExp += 1
  of skHeal:
    if r.healExp < experienceFor(skHeal, 3) or
        (r.levelOf(skBuild) < 4 and r.levelOf(skAttack) < 4):
      r.healExp += 1
  of skAttack:
    if r.attackExp < experienceFor(skAttack, 3) or
        (r.levelOf(skBuild) < 4 and r.levelOf(skHeal) < 4):
      r.attackExp += 1
  let after = r.levelOf(skill)
  if after >= 4 and before < 4:
    w.stats.masteries[ord(r.team)] += 1
  if after > before and after >= 4:
    let slot = after - 4
    if not w.masteryBeat[ord(r.team)][skill][slot]:
      w.masteryBeat[ord(r.team)][skill][slot] = true
      discard w.beat(BeatMastery, "mastery", ord(r.team), ord(skill), after)

proc jailedPenalty*(r: Robot) =
  ## `InternalRobot.jailedPenalty`: the duck's BEST skill loses experience on
  ## the way into jail, ties broken attack -> build -> heal, and the whole
  ## thing is skipped when all three experiences are 0.
  if r.buildExp == 0 and r.attackExp == 0 and r.healExp == 0: return
  let a = r.levelOf(skAttack)
  let b = r.levelOf(skBuild)
  let h = r.levelOf(skHeal)
  if a >= b and a >= h:
    r.attackExp = max(0, r.attackExp + penaltyFor(skAttack, a))
  elif b >= a and b >= h:
    r.buildExp = max(0, r.buildExp + penaltyFor(skBuild, b))
  else:
    r.healExp = max(0, r.healExp + penaltyFor(skHeal, h))

# ---------------------------------------------------------------------------
#  Spawning, despawning and damage
# ---------------------------------------------------------------------------

proc addRobotAt(w: World, l: Loc, r: Robot) = w.occupant[w.idx(l)] = r
proc removeRobotAt(w: World, l: Loc) = w.occupant[w.idx(l)] = nil

proc captureFlagFor*(w: World, r: Robot) =
  ## `TeamInfo.captureFlag` + the caller's own bookkeeping, which the engine
  ## repeats identically in `move` and in `pickupFlag`. The winner is set THE
  ## INSTANT the third flag lands — but `running` is only cleared at the end of
  ## the round, so every duck after the capturer still takes its turn.
  let f = r.flag
  let t = ord(r.team)
  w.stats.flagsCaptured[t] += 1
  f.captured = true
  for i in 0 ..< w.allFlags.len:
    if w.allFlags[i] == f:
      w.allFlags.delete(i)
      break
  r.flag = nil
  f.carriedBy = -1
  discard w.beat(BeatFlagCaptured, "flag_captured", t, f.id,
    w.stats.flagsCaptured[t])
  if w.stats.flagsCaptured[t] >= NumberFlags:
    w.winner = r.team
    w.hasWinner = true
    w.domination = dfCapture

proc despawnRobot*(w: World, r: Robot) =
  ## `GameWorld.despawnRobot` + `InternalRobot.despawn`: 250 spawn-cooldown
  ## turns (= 25 jail rounds), the jail penalty on the best skill, and any
  ## carried flag dropped ON THE DUCK'S OWN TILE.
  if not r.spawned: return
  w.removeRobotAt(r.loc)
  r.spawnCooldown = CooldownsPerTurn * JailedRounds
  r.jailedPenalty()
  if r.flag != nil:
    let f = r.flag
    w.addFlagAt(r.loc, f)
    f.carriedBy = -1
    f.droppedRounds = 0
    r.flag = nil
    w.stats.flagsDropped[ord(r.team)] += 1
    w.stats.carriesLostToDeath[ord(r.team)] += 1
    discard w.beat(BeatFlagDropped, "flag_dropped", ord(r.team), f.id,
      r.loc.x * 100 + r.loc.y, "killed")
  r.spawned = false
  r.diedLocation = r.loc
  w.stats.ducksJailed[ord(r.team)] += 1

proc addHealth*(w: World, r: Robot, amount: int) =
  ## `InternalRobot.addHealth`: capped at 1000 above, and a duck at or below
  ## zero DESPAWNS immediately.
  if not r.spawned: return
  r.health += amount
  r.health = min(r.health, DefaultHealth)
  if r.health <= 0:
    w.despawnRobot(r)

# ---------------------------------------------------------------------------
#  Rule 5 — the legal actions, with their exact preconditions
# ---------------------------------------------------------------------------

proc canSpawn*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanSpawn`.
  if r.spawned: return false
  if not r.canSpawnCooldown(): return false
  if not w.onTheMap(l): return false
  if w.getSpawnZone(l) != ord(r.team) + 1: return false
  if w.getRobot(l) != nil: return false
  w.isPassable(l)

proc doSpawn*(w: World, r: Robot, l: Loc) =
  ## `RobotControllerImpl.spawn` + `InternalRobot.spawn`. THE COOLDOWNS ARE NOT
  ## RESET: the engine's two lines are commented out.
  if not w.canSpawn(r, l):
    w.refusedActions += 1
    return
  w.addRobotAt(l, r)
  r.spawned = true
  r.loc = l
  r.roundsAlive = 0
  r.health = DefaultHealth
  w.stats.spawnEvents[ord(r.team)] += 1
  w.noteFirstAction(r, Bc24ActionSpawn)
  if not r.everSpawned:
    r.everSpawned = true
    w.stats.ducksSpawned[ord(r.team)] += 1

proc addMovementCooldownTurns*(w: World, r: Robot) =
  ## `InternalRobot.addMovementCooldownTurns`, which reads `hasFlag()` AT CALL
  ## TIME — which is why a drop charges a flat +10 (the flag is already gone by
  ## then) and a carry charges 20, or 12 with CAPTURING.
  if r.hasFlag() and w.hasUpgrade(r.team, 1):
    r.movementCooldown += FlagMovementCooldown +
      UpgradeSpecs[ugCapturing].movementDelayChange
  else:
    r.movementCooldown +=
      (if r.hasFlag(): FlagMovementCooldown else: MovementCooldown)

proc canMove*(w: World, r: Robot, d: Dir): bool =
  ## `assertCanMove`.
  if not r.spawned: return false
  if not r.canMoveCooldown(): return false
  if d == dCenter: return false
  let l = r.loc + d
  if not w.onTheMap(l): return false
  if w.isLocationOccupied(l): return false
  w.isPassable(l)

proc doMove*(w: World, r: Robot, d: Dir) =
  ## `RobotControllerImpl.move`, in the engine's own order: (a) the duck moves
  ## and a carried flag moves with it; (b) crumbs on the tile are banked and
  ## the pile is cleared; (c) the movement cooldown is charged; (d) every ENEMY
  ## trap registered on this tile is queued, ITERATED FROM THE END OF THE
  ## REGISTRATION LIST TO THE FRONT; (e) the capture check.
  if not w.canMove(r, d):
    w.refusedActions += 1
    return
  let next = r.loc + d
  w.removeRobotAt(r.loc)
  w.addRobotAt(next, r)
  r.loc = next
  if r.flag != nil:
    r.flag.loc = next
    r.flag.locIsStartRef = false

  let amount = w.getCrumbAmount(next)
  if amount != 0:
    w.addCrumbs(r.team, amount)
  w.removeCrumbs(next)
  w.addMovementCooldownTurns(r)

  w.noteFirstAction(r, Bc24ActionMove)

  let i = w.idx(next)
  for k in countdown(w.trapTriggers[i].len - 1, 0):
    let trap = w.trapTriggers[i][k]
    if trap.team == r.team: continue
    r.addTrapTrigger(trap, true)

  if r.flag != nil and r.flag.team != r.team and
      w.getSpawnZone(next) == ord(r.team) + 1:
    w.captureFlagFor(r)

proc canAttack*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanAttack`.
  if not r.spawned: return false
  if r.loc.distanceSquaredTo(l) > AttackRadiusSquared: return false
  if not w.onTheMap(l): return false
  if not r.canActCooldown(): return false
  let bot = w.getRobot(l)
  if bot == nil or bot.team == r.team: return false
  if r.hasFlag(): return false
  not w.isSetupPhase()

proc doAttack*(w: World, r: Robot, l: Loc) =
  ## `RobotControllerImpl.attack` + `InternalRobot.attack`: the cooldown is
  ## charged FIRST, the kill bounty is decided from the PRE-DAMAGE health and
  ## the ATTACKER's territory, then the damage lands.
  if not w.canAttack(r, l):
    w.refusedActions += 1
    return
  r.actionCooldown += attackCooldownFor(r.levelOf(skAttack))
  let bot = w.getRobot(l)
  let dmg = w.getDamage(r)
  let t = ord(r.team)
  w.stats.attacks[t] += 1
  if bot.health - dmg <= 0:
    if w.inEnemyTerritory(r.team, r.loc):
      w.addCrumbs(r.team, KillCrumbReward)
      w.stats.killCrumbs[t] += KillCrumbReward
    w.stats.kills[t] += 1
  w.stats.damageDealt[t] += min(dmg, bot.health)
  w.addHealth(bot, -dmg)
  w.incrementSkill(r, skAttack)
  w.noteFirstAction(r, Bc24ActionAttack)

proc canHeal*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanHeal`. Healing IS legal during setup; self-healing never is.
  if not r.spawned: return false
  if r.loc.distanceSquaredTo(l) > HealRadiusSquared: return false
  if not w.onTheMap(l): return false
  if not r.canActCooldown(): return false
  if r.loc == l: return false
  let bot = w.getRobot(l)
  if bot == nil: return false
  if bot.team != r.team: return false
  if bot.health == DefaultHealth: return false
  not r.hasFlag()

proc doHeal*(w: World, r: Robot, l: Loc) =
  if not w.canHeal(r, l):
    w.refusedActions += 1
    return
  let bot = w.getRobot(l)
  let amount = w.getHeal(r)
  r.actionCooldown += healCooldownFor(r.levelOf(skHeal))
  let t = ord(r.team)
  w.stats.heals[t] += 1
  w.stats.healDealt[t] += min(amount, DefaultHealth - bot.health)
  if bot.hasFlag():
    w.stats.healToCarriers[t] += min(amount, DefaultHealth - bot.health)
  if bot.levelOf(skAttack) >= 3:
    w.stats.healToVeterans[t] += min(amount, DefaultHealth - bot.health)
  block offLowest:
    var lowest = high(int)
    for adj in w.locationsWithinRadiusSquared(r.loc, HealRadiusSquared):
      let other = w.getRobot(adj)
      if other == nil or other.team != r.team or other.id == r.id: continue
      if other.health >= DefaultHealth: continue
      lowest = min(lowest, other.health)
    if lowest < high(int) and bot.health > lowest:
      w.stats.healsOffLowest[t] += 1
  w.addHealth(bot, amount)
  w.incrementSkill(r, skHeal)
  w.noteFirstAction(r, Bc24ActionHeal)

proc canDig*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanDig`.
  if not r.spawned: return false
  if r.loc.distanceSquaredTo(l) > InteractRadiusSquared: return false
  if not w.onTheMap(l): return false
  if not r.canActCooldown(): return false
  if w.getWater(l): return false
  if w.getWall(l): return false
  if w.getSpawnZone(l) != 0: return false
  if w.isLocationOccupied(l): return false
  if w.getCrumbs(r.team) < digCostFor(r.levelOf(skBuild)): return false
  if w.hasFlagAt(l): return false
  if r.hasFlag(): return false
  not (w.hasTrap(l) and w.getTrap(l).team == r.team)

proc doDig*(w: World, r: Robot, l: Loc) =
  if not w.canDig(r, l):
    w.refusedActions += 1
    return
  let level = r.levelOf(skBuild)
  let cost = digCostFor(level)
  r.actionCooldown += digCooldownFor(level)
  w.addCrumbs(r.team, -cost)
  w.setWater(l)
  w.stats.tilesDug[ord(r.team)] += 1
  w.stats.crumbsSpentDig[ord(r.team)] += cost
  w.noteFirstAction(r, Bc24ActionDig)
  if w.hasTrap(l) and w.getTrap(l).team != r.team and
      w.getTrap(l).kind == tkExplosive:
    r.addTrapTrigger(w.getTrap(l), false)
  w.incrementSkill(r, skBuild)

proc canFill*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanFill`.
  if not r.spawned: return false
  if r.loc.distanceSquaredTo(l) > InteractRadiusSquared: return false
  if not w.onTheMap(l): return false
  if not r.canActCooldown(): return false
  if not w.getWater(l): return false
  if w.getCrumbs(r.team) < fillCostFor(r.levelOf(skBuild)): return false
  not r.hasFlag()

proc doFill*(w: World, r: Robot, l: Loc) =
  ## FILLING EARNS NO BUILD XP (patch 1.1.0) — but it is still cheapened and
  ## hastened by build level.
  if not w.canFill(r, l):
    w.refusedActions += 1
    return
  let level = r.levelOf(skBuild)
  let cost = fillCostFor(level)
  r.actionCooldown += fillCooldownFor(level)
  w.addCrumbs(r.team, -cost)
  w.setLand(l)
  w.stats.tilesFilled[ord(r.team)] += 1
  w.stats.crumbsSpentFill[ord(r.team)] += cost
  w.noteFirstAction(r, Bc24ActionFill)
  if w.hasTrap(l) and w.getTrap(l).team != r.team and
      w.getTrap(l).kind == tkExplosive:
    r.addTrapTrigger(w.getTrap(l), false)

# ---------------------------------------------------------------------------
#  Shared array and global upgrades
# ---------------------------------------------------------------------------

func readSharedArray*(w: World, team: Team, index: int): int =
  ## No range requirement and NO SPAWNED REQUIREMENT: a jailed duck may read.
  if index < 0 or index >= SharedArrayLength: return 0
  w.stats.sharedArray[ord(team)][index]

proc writeSharedArray*(w: World, team: Team, index, value: int) =
  ## Writes take effect IMMEDIATELY and are visible to the same team's later
  ## ducks in the same round.
  if index < 0 or index >= SharedArrayLength: return
  if value < 0 or value > MaxSharedArrayValue: return
  w.stats.sharedArray[ord(team)][index] = value

func upgradeSlot*(u: UpgradeKind): int =
  ## `assertCanBuyGlobal`'s own numbering. `ACTION` is a backwards-compatible
  ## alias of `ATTACK` and shares its slot; the doctrine surface never offers
  ## it (docs/RULES-BC24.md §Divergences item 5).
  case u
  of ugAttack, ugAction: 0
  of ugCapturing: 1
  of ugHealing: 2

proc canBuyGlobal*(w: World, r: Robot, u: UpgradeKind): bool =
  if w.stats.upgrades[ord(r.team)][u.upgradeSlot()]: return false
  w.stats.upgradePoints[ord(r.team)] > 0

proc doBuyGlobal*(w: World, r: Robot, u: UpgradeKind) =
  if not canBuyGlobal(w, r, u):
    w.refusedActions += 1
    return
  let t = ord(r.team)
  let slot = u.upgradeSlot()
  w.stats.upgrades[t][slot] = true
  w.stats.upgradePoints[t] -= 1
  w.stats.upgradeRound[t][slot] = w.currentRound
  w.noteFirstAction(r, Bc24ActionUpgrade)
  if w.stats.upgradeFirstRound[t] == 0:
    w.stats.upgradeFirstRound[t] = w.currentRound
  discard w.beat(BeatUpgrade, "upgrade", t, slot, w.currentRound)

# ---------------------------------------------------------------------------
#  Turn scaffolding
# ---------------------------------------------------------------------------

proc processBeginningOfTurn*(w: World, r: Robot) =
  ## Rule 4. All three counters decay by 10 and floor at 0 — for a JAILED duck
  ## too — and the DecisionOps budget is reset.
  r.actionCooldown = max(0, r.actionCooldown - CooldownsPerTurn)
  r.movementCooldown = max(0, r.movementCooldown - CooldownsPerTurn)
  r.spawnCooldown = max(0, r.spawnCooldown - CooldownsPerTurn)
  w.opsUsedPeak = max(w.opsUsedPeak, DecisionOps - r.opsLeft)
  r.opsLeft = DecisionOps

# ---------------------------------------------------------------------------
#  Construction
# ---------------------------------------------------------------------------

proc floodFillTeam(w: World, teamVal: int8, start: Loc) =
  ## `GameWorld.floodFillTeam`, verbatim — including the fact that the START
  ## tile is marked unconditionally and that the frontier test is `teamSides ==
  ## 0 and not wall and not dam`.
  var queue = @[start]
  var head = 0
  while head < queue.len:
    let l = queue[head]
    head += 1
    let i = w.idx(l)
    if w.teamSides[i] != 0: continue
    w.teamSides[i] = teamVal
    for d in MoveDirs:
      let n = l + d
      if not w.onTheMap(n): continue
      let ni = w.idx(n)
      if w.teamSides[ni] == 0 and not w.walls[ni] and not w.dam[ni]:
        queue.add(n)

proc newWorld*(spec: MapSpec, maxRounds: int): World =
  let n = spec.width * spec.height
  result = World(
    map: spec,
    width: spec.width,
    height: spec.height,
    currentRound: 0,
    maxRounds: maxRounds,
    running: true,
    idGen: initIdGenerator(spec.randomSeed),
    rand: initJavaRandom(spec.randomSeed),
    symmetry: spec.symmetry,
    walls: spec.walls,
    water: spec.water,
    dam: spec.dam,
    spawnZones: newSeq[int8](n),
    teamSides: newSeq[int8](n),
    crumbTiles: newSeq[int32](n),
    occupant: newSeq[Robot](n),
    trapLocations: newSeq[Trap](n),
    trapTriggers: newSeq[seq[Trap]](n),
    placedFlags: newSeq[seq[Flag]](n),
    trapId: 0,
    winner: teamA,
    domination: dfNone,
    hashChain: 0xCBF29CE484222325'u64)

  for c in spec.crumbs:
    result.crumbTiles[c.x + c.y * spec.width] = int32(c.amount)

  ## `GameMapIO.Serial.deserialize` paints the six `spawnLocations` centres out
  ## to `r^2 <= 2` discs; the converter records the painted array's re-derived
  ## centres, and the zones themselves are repainted here from the same table.
  for i in 0 .. 5:
    let team: int8 = (if i mod 2 == 0: 1 else: 2)
    for l in result.locationsWithinRadiusSquared(spec.spawnLocations[i], 2):
      result.spawnZones[result.idx(l)] = team

  for i in 0 ..< n:
    let l = result.indexToLoc(i)
    if result.spawnZones[i] == 1: result.spawnLocs[0].add(l)
    elif result.spawnZones[i] == 2: result.spawnLocs[1].add(l)

  ## THE 100 DUCKS, created `A0, B0, A1, B1, …` exactly as the world's
  ## constructor does, each taking the next id out of `IDGenerator(mapSeed)`.
  ## They are never destroyed, so this order is the exec order for the whole
  ## game.
  var minId = high(int)
  var maxId = 0
  for i in 0 ..< RobotCapacity:
    for team in [teamA, teamB]:
      let id = result.idGen.nextId()
      minId = min(minId, id)
      maxId = max(maxId, id)
      result.robots.add(Robot(
        id: id, team: team, spawned: false,
        health: DefaultHealth,
        actionCooldown: CooldownLimit,
        movementCooldown: CooldownLimit,
        spawnCooldown: 0,
        execIndex: result.robots.len,
        opsLeft: DecisionOps))
  result.minRobotId = minId
  result.robotsById = newSeq[Robot](maxId - minId + 1)
  for r in result.robots:
    result.robotsById[r.id - minId] = r

  ## Flags: the six re-derived spawn-zone centres, A in the even slots, laid
  ## into a per-tile array and then created IN ASCENDING TILE-INDEX ORDER with
  ## `flag.id = tile index`. That order fixes the flag-broadcast re-roll order.
  var flagArray = newSeq[int8](n)
  for i in 0 .. 5:
    let c = spec.spawnCenters[i]
    flagArray[result.idx(c)] = (if i mod 2 == 0: 1 else: 2)
  for i in 0 ..< n:
    if flagArray[i] == 0: continue
    let l = result.indexToLoc(i)
    let f = Flag(id: i, team: (if flagArray[i] == 1: teamA else: teamB),
                 loc: l, startLoc: l, broadcastLoc: l,
                 carriedBy: -1, droppedRounds: 0, locIsStartRef: true)
    result.allFlags.add(f)
    result.placedFlags[i].add(f)

  for f in result.allFlags:
    result.floodFillTeam((if f.team == teamA: 1'i8 else: 2'i8), f.loc)

func mapDigest*(w: World): string =
  ## A stable identity for the loaded map, folded into the replay so a viewer
  ## cannot re-derive a match against a different terrain file.
  var h = 0xCBF29CE484222325'u64
  for i in 0 ..< w.walls.len:
    var v = 0
    if w.map.walls[i]: v = v or 1
    if w.map.water[i]: v = v or 2
    if w.map.dam[i]: v = v or 4
    v = v or (int(w.spawnZones[i]) shl 3)
    h = (h xor uint64(v)) * 0x100000001B3'u64
  toHex(h)
