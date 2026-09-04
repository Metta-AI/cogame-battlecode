## The year boundary: the ONE place the year-neutral machinery meets a year
## module.
##
## `game_config.year` selects a `YearSpec` in `registry.nim`; everything
## downstream — `match`, `results`, `replay`, `render`, `broadcast`, `decide`,
## `server` — holds a `Session` from here and never names `years/bc26/…` or
## `years/bc20/…` itself. Adding 2027 is a new `years/bc27/` directory, one
## registry line, one variant, and one arm in each `case` below.
##
## A `Session` is a Nim object VARIANT, not a `case year: string`: the compiler
## checks that every year has an arm, so a half-added year does not compile.

import std/[json, strutils]
import ../sim_types, ../sheet
import registry
import bc26/maps as maps26
import bc26/rules as rules26
import bc26/world as world26
import bc20/maps as maps20
import bc20/rules as rules20
import bc20/world as world20
import bc20/chassis/kit as kit20
import bc20/flood as flood20
import bc21/maps as maps21
import bc21/economy as economy21
import bc21/rules as rules21
import bc21/world as world21
import bc21/chassis/kit as kit21

export registry

type
  YearId* = enum
    yBc26 = "bc26"
    yBc20 = "bc20"
    yBc21 = "bc21"

  Session* = ref object
    ## One game in progress, in whichever year's sim. `stepRound` advances it;
    ## the renderer and the chrome builder read it through the variant.
    mapName*: string
    gameIndex*: int
    sideAslot*: int
    case year*: YearId
    of yBc26:
      w26*: world26.World
      clans26*: array[2, rules26.Clan]
    of yBc20:
      w20*: world20.World
      sides20*: array[2, kit20.Side]
      chassis20*: array[2, rules20.ChassisKind]
    of yBc21:
      w21*: world21.World
      sides21*: array[2, kit21.Side]
      chassis21*: array[2, rules21.ChassisKind21]

  GameOutcome* = object
    ## The YEAR-NEUTRAL per-game outcome. `results.games[]`'s five required
    ## keys come from the named fields; `stats` carries that year's optional
    ## siblings, already in SEAT order.
    index*: int
    mapName*: string
    sideAslot*: int
    roundsPlayed*: int
    winnerSlot*: int
    endReason*: string
    points*: array[2, int]
    hashChain*: string
    roundChains*: string
    aborted*: bool
    stats*: JsonNode

const Bc20UnitNames* = [
  "hq", "miner", "refinery", "vaporator", "design_school",
  "fulfillment_center", "landscaper", "delivery_drone", "net_gun", "cow"
]
  ## `RobotKind` ordinals as the replay's `first_build.unit` spells them.

const Bc21UnitNames* = [
  "enlightenment_center", "politician", "slanderer", "muckraker"
]
  ## bc21's `RobotKind` ordinals, likewise: `first_build.unit` has a documented
  ## vocabulary in every year (the r1-F14 lesson).

proc yearIdOf*(year: string): YearId =
  case year.strip().toLowerAscii()
  of "bc20": yBc20
  of "bc21": yBc21
  else: yBc26

proc strongChassisFor*(year: string): ScriptedChassis =
  ## The chassis an LLM seat drives, and the fallback for a scripted name that
  ## belongs to a different year. D1: never a sheet field.
  case yearIdOf(year)
  of yBc26: scAwu
  of yBc20: scBowlOfChowder
  of yBc21: scCaliforniaRoll

proc parseScriptedChassis*(name: string): ScriptedChassis =
  ## Year-free reading of a recorded `seats[].chassis` string. An unrecognised
  ## name is `awu`; `newSession` then maps it onto the year's own strong
  ## chassis, so an old recording never fails to re-derive.
  let key = name.strip().toLowerAscii()
  for value in ScriptedChassis:
    if $value == key: return value
  scAwu

# ---------------------------------------------------------------------------
#  Year-neutral map access
# ---------------------------------------------------------------------------

proc poolNamesFor*(year, pool: string): seq[string] =
  case yearIdOf(year)
  of yBc26: maps26.poolNames(pool)
  of yBc20: maps20.poolNames(pool)
  of yBc21: maps21.poolNames(pool)

proc drawMapsFor*(year, pool: string, seed, count: int): seq[string] =
  case yearIdOf(year)
  of yBc26: maps26.drawMaps(pool, seed, count)
  of yBc20: maps20.drawMaps(pool, seed, count)
  of yBc21: maps21.drawMaps(pool, seed, count)

proc sideAslotFor*(year: string, seed, gameIndex: int): int =
  case yearIdOf(year)
  of yBc26: maps26.sideAslotFor(seed, gameIndex)
  of yBc20: maps20.sideAslotFor(seed, gameIndex)
  of yBc21: maps21.sideAslotFor(seed, gameIndex)

proc mapPathFor*(year, name: string): string =
  case yearIdOf(year)
  of yBc26: maps26.mapPath(name)
  of yBc20: maps20.mapPath(name)
  of yBc21: maps21.mapPath(name)

proc mapCardFor*(year, name: string, slot, sideAslot, rounds: int): JsonNode =
  ## The per-map facts a seat may legitimately know before writing its
  ## doctrine. Both seats see numerically identical cards; `you_are` is the
  ## only asymmetry, because every map is symmetric.
  case yearIdOf(year)
  of yBc26:
    let spec = maps26.loadMap(name)
    %*{
      "map": spec.name,
      "width": spec.width,
      "height": spec.height,
      "symmetry": ($spec.symmetry).replace("sym", "").toLowerAscii(),
      "cheese_mines": spec.cheeseMines.len,
      "cats": spec.catWaypointIds.len,
      "rounds": rounds,
      "you_are": (if sideAslot == slot: "A" else: "B")
    }
  of yBc20:
    var card = maps20.mapCard(maps20.loadMap(name), slot, sideAslot)
    card["rounds"] = %rounds
    card
  of yBc21:
    var card = maps21.mapCard(maps21.loadMap(name), slot, sideAslot)
    card["rounds"] = %rounds
    card

# ---------------------------------------------------------------------------
#  Sessions
# ---------------------------------------------------------------------------

proc newSession*(year: string, mapName: string, sheets: array[2, Sheet],
                 sideAslot, maxRounds: int,
                 chassis: array[2, ScriptedChassis],
                 gameIndex = 0): Session =
  case yearIdOf(year)
  of yBc26:
    let spec = maps26.loadMap(mapName)
    result = Session(year: yBc26, mapName: mapName, sideAslot: sideAslot,
                     gameIndex: gameIndex)
    result.w26 = world26.newWorld(spec, maxRounds)
    result.clans26 = rules26.newClans(sheets, sideAslot)
  of yBc20:
    let spec = maps20.loadMap(mapName)
    result = Session(year: yBc20, mapName: mapName, sideAslot: sideAslot,
                     gameIndex: gameIndex)
    result.w20 = world20.newWorld(spec, maxRounds)
    let kinds20 = [rules20.chassisKindFor(chassis[0]),
                   rules20.chassisKindFor(chassis[1])]
    result.chassis20 = [kinds20[sideAslot], kinds20[1 - sideAslot]]
    result.sides20 = rules20.newSides(sheets, kinds20, sideAslot)
  of yBc21:
    let spec = maps21.loadMap(mapName)
    result = Session(year: yBc21, mapName: mapName, sideAslot: sideAslot,
                     gameIndex: gameIndex)
    result.w21 = world21.newWorld(spec, maxRounds)
    let kinds21 = [rules21.chassisKindFor(chassis[0]),
                   rules21.chassisKindFor(chassis[1])]
    result.chassis21 = [kinds21[sideAslot], kinds21[1 - sideAslot]]
    result.sides21 = rules21.newSides21(sheets, sideAslot)

proc stepRound*(s: Session) =
  case s.year
  of yBc26: rules26.runRound(s.w26, s.clans26)
  of yBc20: rules20.runRound(s.w20, s.sides20, s.chassis20)
  of yBc21: rules21.runRound(s.w21, s.sides21, s.chassis21)

proc currentRound*(s: Session): int =
  case s.year
  of yBc26: s.w26.currentRound
  of yBc20: s.w20.currentRound
  of yBc21: s.w21.currentRound

proc running*(s: Session): bool =
  case s.year
  of yBc26: s.w26.running
  of yBc20: s.w20.running
  of yBc21: s.w21.running

proc hashChainHex*(s: Session): string =
  case s.year
  of yBc26: toHex(s.w26.hashChain)
  of yBc20: toHex(s.w20.hashChain)
  of yBc21: toHex(s.w21.hashChain)

proc mapWidth*(s: Session): int =
  case s.year
  of yBc26: s.w26.width
  of yBc20: s.w20.width
  of yBc21: s.w21.width

proc mapHeight*(s: Session): int =
  case s.year
  of yBc26: s.w26.height
  of yBc20: s.w20.height
  of yBc21: s.w21.height

# ---------------------------------------------------------------------------
#  Playing a game, and converting the year's outcome to the neutral one
# ---------------------------------------------------------------------------

proc statsJson26(o: rules26.GameOutcome26): JsonNode =
  %*{
    "cooperation_at_end": o.cooperationAtEnd,
    "backstab_round": o.backstabRound,
    "backstab_by": o.backstabBySlot,
    "cat_damage": [o.catDamage[0], o.catDamage[1]],
    "cheese_transferred": [o.cheeseTransferred[0], o.cheeseTransferred[1]],
    "kings_alive": [o.kingsAlive[0], o.kingsAlive[1]],
    "kings_built": [o.kingsBuilt[0], o.kingsBuilt[1]],
    "rats_built": [o.ratsBuilt[0], o.ratsBuilt[1]],
    "rats_alive": [o.ratsAlive[0], o.ratsAlive[1]],
    "traps_placed": [o.trapsPlaced[0], o.trapsPlaced[1]],
    "dirt_placed": [o.dirtPlaced[0], o.dirtPlaced[1]]
  }

proc statsJson20*(o: rules20.GameOutcome20): JsonNode =
  %*{
    "hq_alive": [o.hqAlive[0], o.hqAlive[1]],
    "hq_lost_round": [o.hqLostRound[0], o.hqLostRound[1]],
    "hq_lost_cause": [o.hqLostCause[0], o.hqLostCause[1]],
    "soup_mined": [o.soupMined[0], o.soupMined[1]],
    "soup_refined": [o.soupRefined[0], o.soupRefined[1]],
    "net_worth": [o.netWorth[0], o.netWorth[1]],
    "units_alive": [o.unitsAlive[0], o.unitsAlive[1]],
    "units_built": [o.unitsBuilt[0], o.unitsBuilt[1]],
    "miners_built": [o.minersBuilt[0], o.minersBuilt[1]],
    "landscapers_built": [o.landscapersBuilt[0], o.landscapersBuilt[1]],
    "drones_built": [o.dronesBuilt[0], o.dronesBuilt[1]],
    "vaporators_built": [o.vaporatorsBuilt[0], o.vaporatorsBuilt[1]],
    "net_guns_built": [o.netGunsBuilt[0], o.netGunsBuilt[1]],
    "dirt_moved": [o.dirtMoved[0], o.dirtMoved[1]],
    "drone_pickups": [o.dronePickups[0], o.dronePickups[1]],
    "drone_water_drops": [o.droneWaterDrops[0], o.droneWaterDrops[1]],
    "net_gun_kills": [o.netGunKills[0], o.netGunKills[1]],
    "transactions_sent": [o.transactionsSent[0], o.transactionsSent[1]],
    "transactions_minted": [o.transactionsMinted[0], o.transactionsMinted[1]],
    "blockchain_soup_spent":
      [o.blockchainSoupSpent[0], o.blockchainSoupSpent[1]],
    "global_pollution_peak": o.globalPollutionPeak,
    "flooded_tiles_end": o.floodedTilesEnd,
    "water_level_end": o.waterLevelEnd
  }

proc statsJson21*(o: rules21.GameOutcome21): JsonNode =
  %*{
    "centers_owned": [o.centersOwned[0], o.centersOwned[1]],
    "centers_captured": [o.centersCaptured[0], o.centersCaptured[1]],
    "centers_lost": [o.centersLost[0], o.centersLost[1]],
    "neutrals_captured": [o.neutralsCaptured[0], o.neutralsCaptured[1]],
    "votes": [o.votes[0], o.votes[1]],
    "bids_placed": [o.bidsPlaced[0], o.bidsPlaced[1]],
    "bid_influence_spent": [o.bidInfluenceSpent[0], o.bidInfluenceSpent[1]],
    "top_bid": [o.topBid[0], o.topBid[1]],
    "influence_spent": [o.influenceSpent[0], o.influenceSpent[1]],
    "influence_end": [o.influenceEnd[0], o.influenceEnd[1]],
    "income_end": [o.incomeEnd[0], o.incomeEnd[1]],
    "units_built": [o.unitsBuilt[0], o.unitsBuilt[1]],
    "politicians_built": [o.politiciansBuilt[0], o.politiciansBuilt[1]],
    "slanderers_built": [o.slanderersBuilt[0], o.slanderersBuilt[1]],
    "muckrakers_built": [o.muckrakersBuilt[0], o.muckrakersBuilt[1]],
    "units_alive": [o.unitsAlive[0], o.unitsAlive[1]],
    "politicians_alive": [o.politiciansAlive[0], o.politiciansAlive[1]],
    "slanderers_alive": [o.slanderersAlive[0], o.slanderersAlive[1]],
    "muckrakers_alive": [o.muckrakersAlive[0], o.muckrakersAlive[1]],
    "empowers": [o.empowers[0], o.empowers[1]],
    "empower_conviction": [o.empowerConviction[0], o.empowerConviction[1]],
    "conversions": [o.conversions[0], o.conversions[1]],
    "exposes": [o.exposes[0], o.exposes[1]],
    "buff_peak": [o.buffPeak[0], o.buffPeak[1]],
    "camouflaged": [o.camouflaged[0], o.camouflaged[1]],
    "robots_lost": [o.robotsLost[0], o.robotsLost[1]],
    "votes_tied": o.votesTied,
    "rounds_no_bid": o.roundsNoBid
  }

proc playGameFor*(
  year, mapName: string, sheets: array[2, Sheet],
  chassis: array[2, ScriptedChassis],
  index, sideAslot, maxRounds, budgetSeconds: int
): (GameOutcome, seq[tuple[round: int, kind: string, a, b, c: int, s: string]]) =
  ## Plays one game and returns the neutral outcome plus the year's own event
  ## stream, so `match.nim` can map the beats without knowing the year's world.
  case yearIdOf(year)
  of yBc26:
    let spec = maps26.loadMap(mapName)
    let (w, o) = rules26.playGame(spec, sheets, index, sideAslot, maxRounds,
      budgetSeconds)
    (GameOutcome(index: o.index, mapName: o.mapName, sideAslot: o.sideAslot,
      roundsPlayed: o.roundsPlayed, winnerSlot: o.winnerSlot,
      endReason: $o.endReason, points: o.points, hashChain: o.hashChain,
      roundChains: o.roundChains, aborted: o.aborted,
      stats: statsJson26(o)), w.events)
  of yBc20:
    let spec = maps20.loadMap(mapName)
    let (w, o) = rules20.playGame(spec, sheets,
      [rules20.chassisKindFor(chassis[0]), rules20.chassisKindFor(chassis[1])],
      index, sideAslot, maxRounds, budgetSeconds)
    (GameOutcome(index: o.index, mapName: o.mapName, sideAslot: o.sideAslot,
      roundsPlayed: o.roundsPlayed, winnerSlot: o.winnerSlot,
      endReason: o.endReason, points: o.points, hashChain: o.hashChain,
      roundChains: o.roundChains, aborted: o.aborted,
      stats: statsJson20(o)), w.events)
  of yBc21:
    let spec = maps21.loadMap(mapName)
    let (w, o) = rules21.playGame(spec, sheets,
      [rules21.chassisKindFor(chassis[0]), rules21.chassisKindFor(chassis[1])],
      index, sideAslot, maxRounds, budgetSeconds)
    (GameOutcome(index: o.index, mapName: o.mapName, sideAslot: o.sideAslot,
      roundsPlayed: o.roundsPlayed, winnerSlot: o.winnerSlot,
      endReason: o.endReason, points: o.points, hashChain: o.hashChain,
      roundChains: o.roundChains, aborted: o.aborted,
      stats: statsJson21(o)), w.events)

proc bc21Breakpoints*(): seq[int] =
  ## The slanderer influence breakpoints, for the bc21 doctrine brief. Read
  ## from the committed JDK-generated table, never typed in.
  economy21.slandererBreakpoints()

proc floodTableJson*(): JsonNode =
  ## The round each integer elevation floods at — the single most important
  ## fact a bc20 doctrine has to plan around, so it goes in the observation.
  ##
  ## Level 7 reports `WaterTableMaxRound + 1` (1501), the "never inside the
  ## cap" sentinel `roundWaterReaches` returns: the uncapped curve reaches
  ## elevation 7 at round 1546, which no 1500-round game can play. Said in
  ## `docs/PROTOCOL.md` §The bc20 observation.
  result = newJObject()
  for level in 1 .. 7:
    result[$level] = %flood20.roundWaterReaches(level)
