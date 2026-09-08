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
import bc24/maps as maps24
import bc24/rules as rules24
import bc24/world as world24
import bc24/chassis/kit as kit24
import bc25/maps as maps25
import bc25/rules as rules25
import bc25/world as world25
import bc25/chassis/kit as kit25

export registry

type
  YearId* = enum
    yBc26 = "bc26"
    yBc20 = "bc20"
    yBc21 = "bc21"
    yBc24 = "bc24"
    yBc25 = "bc25"

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
    of yBc24:
      w24*: world24.World
      sides24*: array[2, kit24.Side]
      chassis24*: array[2, rules24.ChassisKind24]
    of yBc25:
      w25*: world25.World
      sides25*: array[2, kit25.Side]
      chassis25*: array[2, rules25.ChassisKind25]

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

const Bc24ActionNames* = [
  "spawn", "move", "attack", "heal", "build", "dig", "fill", "pickup",
  "drop", "upgrade"
]
  ## bc24 has ONE unit type, so its `first_action.kind` names the ACTION
  ## rather than the unit — the same r1-F14 lesson, one year on: an event
  ## field with an undocumented vocabulary is an event field nobody can draw.

const Bc24UpgradeNames* = ["attack", "capture", "heal"]
  ## `TeamInfo.makeGlobalUpgrade`'s own slot numbering: 0 ATTACK, 1 CAPTURING,
  ## 2 HEALING. The doctrine spells CAPTURING "capture".

const Bc24SkillNames* = ["attack", "build", "heal"]
  ## `SkillKind`'s ordinals, for `mastery.skill`.

const Bc25ActionNames* = [
  "move", "paint", "splash", "mop", "mop_swing", "transfer", "withdraw",
  "build_robot", "mark", "mark_tower_pattern", "mark_srp",
  "complete_tower_pattern", "complete_srp", "upgrade_tower", "tower_attack",
  "tower_aoe", "message", "broadcast", "disintegrate"
]
  ## bc25 has SIX unit types and nineteen distinct actions, so its
  ## `first_action` names the ACTION rather than the unit — the same r1-F14
  ## lesson, one year on: an event field with an undocumented vocabulary is an
  ## event field nobody can draw.

const Bc25TowerNames* = ["paint", "money", "defense"]
  ## `TowerKind`'s ordinals, for `tower_built` / `tower_upgraded` /
  ## `tower_lost`.

proc yearIdOf*(year: string): YearId =
  case year.strip().toLowerAscii()
  of "bc20": yBc20
  of "bc21": yBc21
  of "bc24": yBc24
  of "bc25": yBc25
  else: yBc26

proc strongChassisFor*(year: string): ScriptedChassis =
  ## The chassis an LLM seat drives, and the fallback for a scripted name that
  ## belongs to a different year. D1: never a sheet field.
  case yearIdOf(year)
  of yBc26: scAwu
  of yBc20: scBowlOfChowder
  of yBc21: scCaliforniaRoll
  of yBc24: scGoneSharkin
  of yBc25: scSpaark

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
  of yBc24: maps24.poolNames(pool)
  of yBc25: maps25.poolNames(pool)

proc drawMapsFor*(year, pool: string, seed, count: int): seq[string] =
  case yearIdOf(year)
  of yBc26: maps26.drawMaps(pool, seed, count)
  of yBc20: maps20.drawMaps(pool, seed, count)
  of yBc21: maps21.drawMaps(pool, seed, count)
  of yBc24: maps24.drawMaps(pool, seed, count)
  of yBc25: maps25.drawMaps(pool, seed, count)

proc sideAslotFor*(year: string, seed, gameIndex: int): int =
  case yearIdOf(year)
  of yBc26: maps26.sideAslotFor(seed, gameIndex)
  of yBc20: maps20.sideAslotFor(seed, gameIndex)
  of yBc21: maps21.sideAslotFor(seed, gameIndex)
  of yBc24: maps24.sideAslotFor(seed, gameIndex)
  of yBc25: maps25.sideAslotFor(seed, gameIndex)

proc mapPathFor*(year, name: string): string =
  case yearIdOf(year)
  of yBc26: maps26.mapPath(name)
  of yBc20: maps20.mapPath(name)
  of yBc21: maps21.mapPath(name)
  of yBc24: maps24.mapPath(name)
  of yBc25: maps25.mapPath(name)

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
  of yBc24:
    var card = maps24.mapCard(maps24.loadMap(name), slot, sideAslot)
    card["rounds"] = %rounds
    card
  of yBc25:
    var card = maps25.mapCard(maps25.loadMap(name), slot, sideAslot)
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
  of yBc24:
    let spec = maps24.loadMap(mapName)
    result = Session(year: yBc24, mapName: mapName, sideAslot: sideAslot,
                     gameIndex: gameIndex)
    result.w24 = world24.newWorld(spec, maxRounds)
    let kinds24 = [rules24.chassisKindFor(chassis[0]),
                   rules24.chassisKindFor(chassis[1])]
    result.chassis24 = [kinds24[sideAslot], kinds24[1 - sideAslot]]
    result.sides24 = rules24.newSides24(sheets, sideAslot)
  of yBc25:
    let spec = maps25.loadMap(mapName)
    result = Session(year: yBc25, mapName: mapName, sideAslot: sideAslot,
                     gameIndex: gameIndex)
    result.w25 = world25.newWorld(spec, maxRounds)
    let kinds25 = [rules25.chassisKindFor(chassis[0]),
                   rules25.chassisKindFor(chassis[1])]
    result.chassis25 = [kinds25[sideAslot], kinds25[1 - sideAslot]]
    result.sides25 = rules25.newSides25(sheets, sideAslot)

proc stepRound*(s: Session) =
  case s.year
  of yBc26: rules26.runRound(s.w26, s.clans26)
  of yBc20: rules20.runRound(s.w20, s.sides20, s.chassis20)
  of yBc21: rules21.runRound(s.w21, s.sides21, s.chassis21)
  of yBc24: rules24.runRound(s.w24, s.sides24, s.chassis24)
  of yBc25: rules25.runRound(s.w25, s.sides25, s.chassis25)

proc currentRound*(s: Session): int =
  case s.year
  of yBc26: s.w26.currentRound
  of yBc20: s.w20.currentRound
  of yBc21: s.w21.currentRound
  of yBc24: s.w24.currentRound
  of yBc25: s.w25.currentRound

proc running*(s: Session): bool =
  case s.year
  of yBc26: s.w26.running
  of yBc20: s.w20.running
  of yBc21: s.w21.running
  of yBc24: s.w24.running
  of yBc25: s.w25.running

proc hashChainHex*(s: Session): string =
  case s.year
  of yBc26: toHex(s.w26.hashChain)
  of yBc20: toHex(s.w20.hashChain)
  of yBc21: toHex(s.w21.hashChain)
  of yBc24: toHex(s.w24.hashChain)
  of yBc25: toHex(s.w25.hashChain)

proc mapWidth*(s: Session): int =
  case s.year
  of yBc26: s.w26.width
  of yBc20: s.w20.width
  of yBc21: s.w21.width
  of yBc24: s.w24.width
  of yBc25: s.w25.width

proc mapHeight*(s: Session): int =
  case s.year
  of yBc26: s.w26.height
  of yBc20: s.w20.height
  of yBc21: s.w21.height
  of yBc24: s.w24.height
  of yBc25: s.w25.height

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

proc statsJson24*(o: rules24.GameOutcome24): JsonNode =
  %*{
    "flags_captured": [o.flagsCaptured[0], o.flagsCaptured[1]],
    "flags_picked_up": [o.flagsPickedUp[0], o.flagsPickedUp[1]],
    "flags_dropped": [o.flagsDropped[0], o.flagsDropped[1]],
    "flags_returned": [o.flagsReturned[0], o.flagsReturned[1]],
    "rounds_carrying": [o.roundsCarrying[0], o.roundsCarrying[1]],
    "crumbs_end": [o.crumbsEnd[0], o.crumbsEnd[1]],
    "crumbs_collected": [o.crumbsCollected[0], o.crumbsCollected[1]],
    "crumbs_spent": [o.crumbsSpent[0], o.crumbsSpent[1]],
    "kill_crumbs": [o.killCrumbs[0], o.killCrumbs[1]],
    "ducks_spawned": [o.ducksSpawned[0], o.ducksSpawned[1]],
    "ducks_jailed": [o.ducksJailed[0], o.ducksJailed[1]],
    "alive_end": [o.aliveEnd[0], o.aliveEnd[1]],
    "attacks": [o.attacks[0], o.attacks[1]],
    "damage_dealt": [o.damageDealt[0], o.damageDealt[1]],
    "kills": [o.kills[0], o.kills[1]],
    "heals": [o.heals[0], o.heals[1]],
    "heal_dealt": [o.healDealt[0], o.healDealt[1]],
    "traps_built": [o.trapsBuilt[0], o.trapsBuilt[1]],
    "traps_triggered": [o.trapsTriggered[0], o.trapsTriggered[1]],
    "trap_damage": [o.trapDamage[0], o.trapDamage[1]],
    "tiles_dug": [o.tilesDug[0], o.tilesDug[1]],
    "tiles_filled": [o.tilesFilled[0], o.tilesFilled[1]],
    "levels_end": [o.levelsEnd[0], o.levelsEnd[1]],
    "attack_levels_end": [o.attackLevelsEnd[0], o.attackLevelsEnd[1]],
    "build_levels_end": [o.buildLevelsEnd[0], o.buildLevelsEnd[1]],
    "heal_levels_end": [o.healLevelsEnd[0], o.healLevelsEnd[1]],
    "masteries": [o.masteries[0], o.masteries[1]],
    "upgrades_taken": [o.upgradesTaken[0], o.upgradesTaken[1]],
    "upgrade_first_round": [o.upgradeFirstRound[0], o.upgradeFirstRound[1]],
    "setup_flag_teleports": o.setupFlagTeleports,
    "rounds_with_any_carry": o.roundsWithAnyCarry
  }

proc statsJson25*(o: rules25.GameOutcome25): JsonNode =
  %*{
    "squares_painted": [o.squaresPainted[0], o.squaresPainted[1]],
    "coverage_permille": [o.coveragePermille[0], o.coveragePermille[1]],
    "peak_coverage_permille":
      [o.peakCoveragePermille[0], o.peakCoveragePermille[1]],
    "tiles_painted": [o.tilesPainted[0], o.tilesPainted[1]],
    "tiles_mopped": [o.tilesMopped[0], o.tilesMopped[1]],
    "tiles_overpainted": [o.tilesOverpainted[0], o.tilesOverpainted[1]],
    "chips_end": [o.chipsEnd[0], o.chipsEnd[1]],
    "chips_earned": [o.chipsEarned[0], o.chipsEarned[1]],
    "chips_spent": [o.chipsSpent[0], o.chipsSpent[1]],
    "paint_in_units_end": [o.paintInUnitsEnd[0], o.paintInUnitsEnd[1]],
    "paint_mined": [o.paintMined[0], o.paintMined[1]],
    "paint_spent": [o.paintSpent[0], o.paintSpent[1]],
    "robots_built": [o.robotsBuilt[0], o.robotsBuilt[1]],
    "soldiers_built": [o.soldiersBuilt[0], o.soldiersBuilt[1]],
    "splashers_built": [o.splashersBuilt[0], o.splashersBuilt[1]],
    "moppers_built": [o.moppersBuilt[0], o.moppersBuilt[1]],
    "robots_alive": [o.robotsAlive[0], o.robotsAlive[1]],
    "robots_lost": [o.robotsLost[0], o.robotsLost[1]],
    "robot_rounds_starved":
      [o.robotRoundsStarved[0], o.robotRoundsStarved[1]],
    "towers_built": [o.towersBuilt[0], o.towersBuilt[1]],
    "towers_upgraded": [o.towersUpgraded[0], o.towersUpgraded[1]],
    "towers_alive": [o.towersAlive[0], o.towersAlive[1]],
    "towers_lost": [o.towersLost[0], o.towersLost[1]],
    "money_towers_end": [o.moneyTowersEnd[0], o.moneyTowersEnd[1]],
    "paint_towers_end": [o.paintTowersEnd[0], o.paintTowersEnd[1]],
    "defense_towers_end": [o.defenseTowersEnd[0], o.defenseTowersEnd[1]],
    "srp_completed": [o.srpCompleted[0], o.srpCompleted[1]],
    "srp_active_end": [o.srpActiveEnd[0], o.srpActiveEnd[1]],
    "srp_rounds_active": [o.srpRoundsActive[0], o.srpRoundsActive[1]],
    "splash_attacks": [o.splashAttacks[0], o.splashAttacks[1]],
    "mop_swings": [o.mopSwings[0], o.mopSwings[1]],
    "tower_damage_dealt": [o.towerDamageDealt[0], o.towerDamageDealt[1]],
    "robot_damage_dealt": [o.robotDamageDealt[0], o.robotDamageDealt[1]],
    "messages_sent": [o.messagesSent[0], o.messagesSent[1]],
    "markers_placed": [o.markersPlaced[0], o.markersPlaced[1]],
    "paintable_tiles": o.paintableTiles,
    "area_without_walls": o.areaWithoutWalls,
    "tiles_to_win": o.tilesToWin,
    "ruins": o.ruins,
    "rounds_with_any_srp": o.roundsWithAnySrp
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
  of yBc24:
    let spec = maps24.loadMap(mapName)
    let (w, o) = rules24.playGame(spec, sheets,
      [rules24.chassisKindFor(chassis[0]), rules24.chassisKindFor(chassis[1])],
      index, sideAslot, maxRounds, budgetSeconds)
    (GameOutcome(index: o.index, mapName: o.mapName, sideAslot: o.sideAslot,
      roundsPlayed: o.roundsPlayed, winnerSlot: o.winnerSlot,
      endReason: o.endReason, points: o.points, hashChain: o.hashChain,
      roundChains: o.roundChains, aborted: o.aborted,
      stats: statsJson24(o)), w.events)
  of yBc25:
    let spec = maps25.loadMap(mapName)
    let (w, o) = rules25.playGame(spec, sheets,
      [rules25.chassisKindFor(chassis[0]), rules25.chassisKindFor(chassis[1])],
      index, sideAslot, maxRounds, budgetSeconds)
    (GameOutcome(index: o.index, mapName: o.mapName, sideAslot: o.sideAslot,
      roundsPlayed: o.roundsPlayed, winnerSlot: o.winnerSlot,
      endReason: o.endReason, points: o.points, hashChain: o.hashChain,
      roundChains: o.roundChains, aborted: o.aborted,
      stats: statsJson25(o)), w.events)

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
