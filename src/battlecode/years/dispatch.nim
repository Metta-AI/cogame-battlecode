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
import bc23/maps as maps23
import bc23/rules as rules23
import bc23/world as world23
import bc23/chassis/kit as kit23
import bc22/maps as maps22
import bc22/rules as rules22
import bc22/world as world22
import bc22/chassis/kit as kit22
import bc16/maps as maps16
import bc16/rules as rules16
import bc16/world as world16
import bc16/chassis/kit as kit16

export registry

type
  YearId* = enum
    yBc26 = "bc26"
    yBc20 = "bc20"
    yBc21 = "bc21"
    yBc24 = "bc24"
    yBc25 = "bc25"
    yBc23 = "bc23"
    yBc22 = "bc22"
    yBc16 = "bc16"

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
    of yBc23:
      w23*: world23.World
      sides23*: array[2, kit23.Side]
      chassis23*: array[2, rules23.ChassisKind23]
    of yBc22:
      w22*: world22.World
      sides22*: array[2, kit22.Side]
      chassis22*: array[2, rules22.ChassisKind22]
    of yBc16:
      w16*: world16.World
      sides16*: array[2, kit16.Side]
      chassis16*: array[2, rules16.ChassisKind16]

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

const Bc23ActionNames* = [
  "move", "build_robot", "build_anchor", "attack", "throw", "destabilize",
  "boost", "collect", "transfer", "withdraw", "take_anchor", "return_anchor",
  "place_anchor", "write_array", "disintegrate"
]
  ## bc23 has SIX unit types and fifteen distinct actions, so its
  ## `first_action` names the ACTION rather than the unit — the same r1-F14
  ## lesson, one year on: an event field with an undocumented vocabulary is an
  ## event field nobody can draw.

const Bc23AnchorNames* = ["-", "standard", "accelerating"]
  ## `AnchorType`'s ordinals, for `anchor_built` / `island_captured`.

const Bc23ResourceNames* = ["none", "adamantium", "mana", "elixir"]
  ## `Resource`'s ordinals, for `well_transformed` / `well_upgraded`.

const Bc23ElixirUnitNames* = ["destabilizer", "booster",
                              "accelerating_anchor"]
  ## `first_elixir_unit.unit`.

const Bc22ActionNames* = [
  "move", "build_robot", "attack", "envision", "repair", "mine_lead",
  "mine_gold", "mutate", "transmute", "transform", "write_array",
  "disintegrate"
]
  ## bc22 has SEVEN unit types and twelve distinct actions, so its
  ## `first_action` names the ACTION rather than the unit — the same r1-F14
  ## lesson, one year on: an event field with an undocumented vocabulary is an
  ## event field nobody can draw. And the field is `action`, never `kind`: a
  ## field named `kind` is flattened into the same object as the event's own
  ## `kind` key and silently overwrites it (the bc23 r1-F25 finding).

const Bc22UnitNames* = [
  "archon", "laboratory", "watchtower", "miner", "builder", "soldier", "sage"
]
  ## `RobotType`'s ordinals, for `mutation.target`.

const Bc22AnomalyNames* = ["abyss", "charge", "fury", "vortex"]
  ## `AnomalyKind`'s ordinals, for `anomaly_struck` / `anomaly_dodged`.

const Bc22RungNames* = ["-", "annihilated", "more_archons",
                        "more_gold_net_worth", "more_lead_net_worth",
                        "coin_flip"]
  ## `Domination`'s ordinals, for `singularity.rung`.

const Bc16ActionNames* = [
  "clear_rubble", "move", "attack", "broadcast", "broadcast_message",
  "build", "activate", "repair", "pack", "unpack", "disintegrate"
]
  ## bc16 has TWELVE unit types and eleven distinct actions, so its
  ## `first_action` names the ACTION rather than the unit. And the field is
  ## `action`, never `kind`: a field named `kind` is flattened into the same
  ## object as the event's own `kind` key and silently overwrites it (the
  ## bc23 r1-F25 finding).

const Bc16UnitNames* = [
  "zombieden", "standardzombie", "rangedzombie", "fastzombie", "bigzombie",
  "archon", "scout", "soldier", "guard", "viper", "turret", "ttm"
]
  ## `RobotType`'s ordinals, for `unit_milestone.unit`, `turned.unit` and
  ## `neutral_activated.unit`.

const Bc16RungNames* = ["-", "archons_destroyed", "more_archons",
                        "more_archon_health", "more_parts_net_worth",
                        "highest_id"]
  ## `Domination`'s ordinals, for `tiebreak.rung`.

const Bc25TowerNames* = ["paint", "money", "defense"]
  ## `TowerKind`'s ordinals, for `tower_built` / `tower_upgraded` /
  ## `tower_lost`.

proc yearIdOf*(year: string): YearId =
  case year.strip().toLowerAscii()
  of "bc20": yBc20
  of "bc21": yBc21
  of "bc24": yBc24
  of "bc25": yBc25
  of "bc23": yBc23
  of "bc22": yBc22
  of "bc16": yBc16
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
  of yBc23: scLemonade
  of yBc22: scWololo
  of yBc16: scBulwark

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
  of yBc23: maps23.poolNames(pool)
  of yBc22: maps22.poolNames(pool)
  of yBc16: maps16.poolNames(pool)

proc drawMapsFor*(year, pool: string, seed, count: int): seq[string] =
  case yearIdOf(year)
  of yBc26: maps26.drawMaps(pool, seed, count)
  of yBc20: maps20.drawMaps(pool, seed, count)
  of yBc21: maps21.drawMaps(pool, seed, count)
  of yBc24: maps24.drawMaps(pool, seed, count)
  of yBc25: maps25.drawMaps(pool, seed, count)
  of yBc23: maps23.drawMaps(pool, seed, count)
  of yBc22: maps22.drawMaps(pool, seed, count)
  of yBc16: maps16.drawMaps(pool, seed, count)

proc sideAslotFor*(year: string, seed, gameIndex: int): int =
  case yearIdOf(year)
  of yBc26: maps26.sideAslotFor(seed, gameIndex)
  of yBc20: maps20.sideAslotFor(seed, gameIndex)
  of yBc21: maps21.sideAslotFor(seed, gameIndex)
  of yBc24: maps24.sideAslotFor(seed, gameIndex)
  of yBc25: maps25.sideAslotFor(seed, gameIndex)
  of yBc23: maps23.sideAslotFor(seed, gameIndex)
  of yBc22: maps22.sideAslotFor(seed, gameIndex)
  of yBc16: maps16.sideAslotFor(seed, gameIndex)

proc mapPathFor*(year, name: string): string =
  case yearIdOf(year)
  of yBc26: maps26.mapPath(name)
  of yBc20: maps20.mapPath(name)
  of yBc21: maps21.mapPath(name)
  of yBc24: maps24.mapPath(name)
  of yBc25: maps25.mapPath(name)
  of yBc23: maps23.mapPath(name)
  of yBc22: maps22.mapPath(name)
  of yBc16: maps16.mapPath(name)

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
  of yBc23:
    var card = maps23.mapCard(maps23.loadMap(name), slot, sideAslot)
    card["rounds"] = %rounds
    card
  of yBc22:
    var card = maps22.mapCard(maps22.loadMap(name), slot, sideAslot)
    card["rounds"] = %rounds
    card
  of yBc16:
    var card = maps16.mapCard(maps16.loadMap(name), slot, sideAslot)
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
  of yBc23:
    let spec = maps23.loadMap(mapName)
    result = Session(year: yBc23, mapName: mapName, sideAslot: sideAslot,
                     gameIndex: gameIndex)
    result.w23 = world23.newWorld(spec, maxRounds)
    let kinds23 = [rules23.chassisKindFor(chassis[0]),
                   rules23.chassisKindFor(chassis[1])]
    result.chassis23 = [kinds23[sideAslot], kinds23[1 - sideAslot]]
    result.sides23 = rules23.newSides23(sheets, sideAslot)
  of yBc22:
    let spec = maps22.loadMap(mapName)
    result = Session(year: yBc22, mapName: mapName, sideAslot: sideAslot,
                     gameIndex: gameIndex)
    result.w22 = world22.newWorld(spec, maxRounds)
    result.w22.loadTransmuteTable()
    let kinds22 = [rules22.chassisKindFor(chassis[0]),
                   rules22.chassisKindFor(chassis[1])]
    result.chassis22 = [kinds22[sideAslot], kinds22[1 - sideAslot]]
    result.sides22 = rules22.newSides22(sheets, sideAslot)
  of yBc16:
    let spec = maps16.loadMap(mapName)
    result = Session(year: yBc16, mapName: mapName, sideAslot: sideAslot,
                     gameIndex: gameIndex)
    result.w16 = world16.newWorld(spec, maxRounds)
    let kinds16 = [rules16.chassisKindFor(chassis[0]),
                   rules16.chassisKindFor(chassis[1])]
    result.chassis16 = [kinds16[sideAslot], kinds16[1 - sideAslot]]
    result.sides16 = rules16.newSides16(sheets, sideAslot)

proc stepRound*(s: Session) =
  case s.year
  of yBc26: rules26.runRound(s.w26, s.clans26)
  of yBc20: rules20.runRound(s.w20, s.sides20, s.chassis20)
  of yBc21: rules21.runRound(s.w21, s.sides21, s.chassis21)
  of yBc24: rules24.runRound(s.w24, s.sides24, s.chassis24)
  of yBc25: rules25.runRound(s.w25, s.sides25, s.chassis25)
  of yBc23: rules23.runRound(s.w23, s.sides23, s.chassis23)
  of yBc22: rules22.runRound(s.w22, s.sides22, s.chassis22)
  of yBc16: rules16.runRound(s.w16, s.sides16, s.chassis16)

proc currentRound*(s: Session): int =
  case s.year
  of yBc26: s.w26.currentRound
  of yBc20: s.w20.currentRound
  of yBc21: s.w21.currentRound
  of yBc24: s.w24.currentRound
  of yBc25: s.w25.currentRound
  of yBc23: s.w23.currentRound
  of yBc22: s.w22.currentRound
  of yBc16: s.w16.currentRound

proc running*(s: Session): bool =
  case s.year
  of yBc26: s.w26.running
  of yBc20: s.w20.running
  of yBc21: s.w21.running
  of yBc24: s.w24.running
  of yBc25: s.w25.running
  of yBc23: s.w23.running
  of yBc22: s.w22.running
  of yBc16: s.w16.running

proc hashChainHex*(s: Session): string =
  case s.year
  of yBc26: toHex(s.w26.hashChain)
  of yBc20: toHex(s.w20.hashChain)
  of yBc21: toHex(s.w21.hashChain)
  of yBc24: toHex(s.w24.hashChain)
  of yBc25: toHex(s.w25.hashChain)
  of yBc23: toHex(s.w23.hashChain)
  of yBc22: toHex(s.w22.hashChain)
  of yBc16: toHex(s.w16.hashChain)

proc mapWidth*(s: Session): int =
  case s.year
  of yBc26: s.w26.width
  of yBc20: s.w20.width
  of yBc21: s.w21.width
  of yBc24: s.w24.width
  of yBc25: s.w25.width
  of yBc23: s.w23.width
  of yBc22: s.w22.width
  of yBc16: s.w16.width

proc mapHeight*(s: Session): int =
  case s.year
  of yBc26: s.w26.height
  of yBc20: s.w20.height
  of yBc21: s.w21.height
  of yBc24: s.w24.height
  of yBc25: s.w25.height
  of yBc23: s.w23.height
  of yBc22: s.w22.height
  of yBc16: s.w16.height

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

proc statsJson23*(o: rules23.GameOutcome23): JsonNode =
  %*{
    "islands_held_end": [o.islandsHeldEnd[0], o.islandsHeldEnd[1]],
    "islands_captured": [o.islandsCaptured[0], o.islandsCaptured[1]],
    "islands_lost": [o.islandsLost[0], o.islandsLost[1]],
    "rounds_holding_any_island":
      [o.roundsHoldingAnyIsland[0], o.roundsHoldingAnyIsland[1]],
    "longest_hold_streak":
      [o.longestHoldStreak[0], o.longestHoldStreak[1]],
    "anchors_built": [o.anchorsBuilt[0], o.anchorsBuilt[1]],
    "anchors_placed": [o.anchorsPlaced[0], o.anchorsPlaced[1]],
    "anchors_lost": [o.anchorsLost[0], o.anchorsLost[1]],
    "accelerating_anchors_placed":
      [o.acceleratingAnchorsPlaced[0], o.acceleratingAnchorsPlaced[1]],
    "adamantium_end": [o.adamantiumEnd[0], o.adamantiumEnd[1]],
    "mana_end": [o.manaEnd[0], o.manaEnd[1]],
    "elixir_end": [o.elixirEnd[0], o.elixirEnd[1]],
    "adamantium_mined": [o.adamantiumMined[0], o.adamantiumMined[1]],
    "mana_mined": [o.manaMined[0], o.manaMined[1]],
    "elixir_mined": [o.elixirMined[0], o.elixirMined[1]],
    "resources_thrown": [o.resourcesThrown[0], o.resourcesThrown[1]],
    "resources_banked": [o.resourcesBanked[0], o.resourcesBanked[1]],
    "wells_transformed": [o.wellsTransformed[0], o.wellsTransformed[1]],
    "wells_upgraded": [o.wellsUpgraded[0], o.wellsUpgraded[1]],
    "units_built": [o.unitsBuilt[0], o.unitsBuilt[1]],
    "carriers_built": [o.carriersBuilt[0], o.carriersBuilt[1]],
    "launchers_built": [o.launchersBuilt[0], o.launchersBuilt[1]],
    "amplifiers_built": [o.amplifiersBuilt[0], o.amplifiersBuilt[1]],
    "destabilizers_built": [o.destabilizersBuilt[0], o.destabilizersBuilt[1]],
    "boosters_built": [o.boostersBuilt[0], o.boostersBuilt[1]],
    "robots_alive": [o.robotsAlive[0], o.robotsAlive[1]],
    "robots_lost": [o.robotsLost[0], o.robotsLost[1]],
    "damage_dealt": [o.damageDealt[0], o.damageDealt[1]],
    "throw_damage": [o.throwDamage[0], o.throwDamage[1]],
    "destabilize_damage": [o.destabilizeDamage[0], o.destabilizeDamage[1]],
    "hq_damage": [o.hqDamage[0], o.hqDamage[1]],
    "anchor_heals": [o.anchorHeals[0], o.anchorHeals[1]],
    "array_writes": [o.arrayWrites[0], o.arrayWrites[1]],
    "boosts_cast": [o.boostsCast[0], o.boostsCast[1]],
    "destabilizes_cast": [o.destabilizesCast[0], o.destabilizesCast[1]],
    "carrier_rounds_loaded":
      [o.carrierRoundsLoaded[0], o.carrierRoundsLoaded[1]],
    "current_rides": [o.currentRides[0], o.currentRides[1]],
    "first_anchor_round": [o.firstAnchorRound[0], o.firstAnchorRound[1]],
    "captured_distance_mean":
      [o.capturedDistanceMean[0], o.capturedDistanceMean[1]],
    "strike_distance_mean":
      [o.strikeDistanceMean[0], o.strikeDistanceMean[1]],
    "carrier_damage_taken":
      [o.carrierDamageTaken[0], o.carrierDamageTaken[1]],
    "launchers_built_by_400":
      [o.launchersBuiltBy400[0], o.launchersBuiltBy400[1]],
    "carriers_built_by_400":
      [o.carriersBuiltBy400[0], o.carriersBuiltBy400[1]],
    "islands_on_map": o.islandsOnMap,
    "islands_to_win": o.islandsToWin,
    "headquarters_per_side": o.headquartersPerSide,
    "cloud_tiles": o.cloudTiles,
    "current_tiles": o.currentTiles,
    "wells_total": o.wellsTotal
  }

proc statsJson22*(o: rules22.GameOutcome22): JsonNode =
  %*{
    "archons_start": [o.archonsStart[0], o.archonsStart[1]],
    "archons_end": [o.archonsEnd[0], o.archonsEnd[1]],
    "archons_lost": [o.archonsLost[0], o.archonsLost[1]],
    "archon_relocations": [o.archonRelocations[0], o.archonRelocations[1]],
    "lead_mined": [o.leadMined[0], o.leadMined[1]],
    "gold_mined": [o.goldMined[0], o.goldMined[1]],
    "lead_end": [o.leadEnd[0], o.leadEnd[1]],
    "gold_end": [o.goldEnd[0], o.goldEnd[1]],
    "lead_net_worth_end": [o.leadNetWorthEnd[0], o.leadNetWorthEnd[1]],
    "gold_net_worth_end": [o.goldNetWorthEnd[0], o.goldNetWorthEnd[1]],
    "lead_reclaimed": [o.leadReclaimed[0], o.leadReclaimed[1]],
    "gold_reclaimed": [o.goldReclaimed[0], o.goldReclaimed[1]],
    "squares_mined_dry": [o.squaresMinedDry[0], o.squaresMinedDry[1]],
    "units_built": [o.unitsBuilt[0], o.unitsBuilt[1]],
    "miners_built": [o.minersBuilt[0], o.minersBuilt[1]],
    "builders_built": [o.buildersBuilt[0], o.buildersBuilt[1]],
    "soldiers_built": [o.soldiersBuilt[0], o.soldiersBuilt[1]],
    "sages_built": [o.sagesBuilt[0], o.sagesBuilt[1]],
    "labs_built": [o.labsBuilt[0], o.labsBuilt[1]],
    "labs_finished": [o.labsFinished[0], o.labsFinished[1]],
    "watchtowers_built": [o.watchtowersBuilt[0], o.watchtowersBuilt[1]],
    "watchtowers_finished":
      [o.watchtowersFinished[0], o.watchtowersFinished[1]],
    "mutations_l2": [o.mutationsL2[0], o.mutationsL2[1]],
    "mutations_l3": [o.mutationsL3[0], o.mutationsL3[1]],
    "transmutes": [o.transmutes[0], o.transmutes[1]],
    "gold_transmuted": [o.goldTransmuted[0], o.goldTransmuted[1]],
    "lead_spent_transmuting":
      [o.leadSpentTransmuting[0], o.leadSpentTransmuting[1]],
    "repairs": [o.repairs[0], o.repairs[1]],
    "hp_repaired": [o.hpRepaired[0], o.hpRepaired[1]],
    "envisions": [o.envisions[0], o.envisions[1]],
    "damage_dealt": [o.damageDealt[0], o.damageDealt[1]],
    "sage_damage": [o.sageDamage[0], o.sageDamage[1]],
    "soldier_damage": [o.soldierDamage[0], o.soldierDamage[1]],
    "watchtower_damage": [o.watchtowerDamage[0], o.watchtowerDamage[1]],
    "array_writes": [o.arrayWrites[0], o.arrayWrites[1]],
    "transforms": [o.transforms[0], o.transforms[1]],
    "rounds_with_a_lab": [o.roundsWithALab[0], o.roundsWithALab[1]],
    "robots_alive": [o.robotsAlive[0], o.robotsAlive[1]],
    "robots_lost": [o.robotsLost[0], o.robotsLost[1]],
    "anomaly_losses_charge":
      [o.anomalyLossesCharge[0], o.anomalyLossesCharge[1]],
    "anomaly_losses_fury_hp":
      [o.anomalyLossesFuryHp[0], o.anomalyLossesFuryHp[1]],
    "anomaly_losses_abyss_lead":
      [o.anomalyLossesAbyssLead[0], o.anomalyLossesAbyssLead[1]],
    "anomalies_dodged": [o.anomaliesDodged[0], o.anomaliesDodged[1]],
    "archons_per_side": o.archonsPerSide,
    "lead_on_map_start": o.leadOnMapStart,
    "lead_on_map_end": o.leadOnMapEnd,
    "lead_squares_start": o.leadSquaresStart,
    "rubble_mean": o.rubbleMean,
    "anomalies_scheduled": o.anomaliesScheduled,
    "vortexes_scheduled": o.vortexesScheduled,
    "singularity_round": o.singularityRound
  }

proc statsJson16*(o: rules16.GameOutcome16): JsonNode =
  %*{
    "archons_start": [o.archonsStart[0], o.archonsStart[1]],
    "archons_end": [o.archonsEnd[0], o.archonsEnd[1]],
    "archons_lost": [o.archonsLost[0], o.archonsLost[1]],
    "archon_health_end_tenths":
      [o.archonHealthEndTenths[0], o.archonHealthEndTenths[1]],
    "parts_end_tenths": [o.partsEndTenths[0], o.partsEndTenths[1]],
    "parts_worth_end": [o.partsWorthEnd[0], o.partsWorthEnd[1]],
    "parts_collected_tenths":
      [o.partsCollectedTenths[0], o.partsCollectedTenths[1]],
    "parts_income_tenths": [o.partsIncomeTenths[0], o.partsIncomeTenths[1]],
    "parts_spent_tenths": [o.partsSpentTenths[0], o.partsSpentTenths[1]],
    "units_built": [o.unitsBuilt[0], o.unitsBuilt[1]],
    "scouts_built": [o.scoutsBuilt[0], o.scoutsBuilt[1]],
    "soldiers_built": [o.soldiersBuilt[0], o.soldiersBuilt[1]],
    "guards_built": [o.guardsBuilt[0], o.guardsBuilt[1]],
    "vipers_built": [o.vipersBuilt[0], o.vipersBuilt[1]],
    "turrets_built": [o.turretsBuilt[0], o.turretsBuilt[1]],
    "turret_packs": [o.turretPacks[0], o.turretPacks[1]],
    "robots_alive": [o.robotsAlive[0], o.robotsAlive[1]],
    "robots_lost": [o.robotsLost[0], o.robotsLost[1]],
    "robots_turned": [o.robotsTurned[0], o.robotsTurned[1]],
    "neutrals_activated": [o.neutralsActivated[0], o.neutralsActivated[1]],
    "neutral_archons_activated":
      [o.neutralArchonsActivated[0], o.neutralArchonsActivated[1]],
    "dens_destroyed": [o.densDestroyed[0], o.densDestroyed[1]],
    "den_damage_dealt": [o.denDamageDealt[0], o.denDamageDealt[1]],
    "damage_dealt": [o.damageDealt[0], o.damageDealt[1]],
    "zombie_damage_dealt":
      [o.zombieDamageDealt[0], o.zombieDamageDealt[1]],
    "zombie_damage_taken":
      [o.zombieDamageTaken[0], o.zombieDamageTaken[1]],
    "enemy_damage_dealt": [o.enemyDamageDealt[0], o.enemyDamageDealt[1]],
    "enemy_damage_taken": [o.enemyDamageTaken[0], o.enemyDamageTaken[1]],
    "infections_suffered":
      [o.infectionsSuffered[0], o.infectionsSuffered[1]],
    "infections_inflicted":
      [o.infectionsInflicted[0], o.infectionsInflicted[1]],
    "viper_infection_damage":
      [o.viperInfectionDamage[0], o.viperInfectionDamage[1]],
    "repairs": [o.repairs[0], o.repairs[1]],
    "hp_repaired": [o.hpRepaired[0], o.hpRepaired[1]],
    "rubble_cleared_tenths":
      [o.rubbleClearedTenths[0], o.rubbleClearedTenths[1]],
    "rubble_created_tenths":
      [o.rubbleCreatedTenths[0], o.rubbleCreatedTenths[1]],
    "squares_opened": [o.squaresOpened[0], o.squaresOpened[1]],
    "basic_signals": [o.basicSignals[0], o.basicSignals[1]],
    "message_signals": [o.messageSignals[0], o.messageSignals[1]],
    "archon_parts_walks": [o.archonPartsWalks[0], o.archonPartsWalks[1]],
    "archons_alive_at_2000":
      [o.archonsAliveAt2000[0], o.archonsAliveAt2000[1]],
    "archons_per_side": o.archonsPerSide,
    "dens_per_side": o.densPerSide,
    "dens_on_map": o.densOnMap,
    "parts_on_map_start": o.partsOnMapStart,
    "parts_squares_start": o.partsSquaresStart,
    "rubble_mean_tenths": o.rubbleMeanTenths,
    "impassable_squares_start": o.impassableSquaresStart,
    "impassable_squares_end": o.impassableSquaresEnd,
    "neutrals_on_map_start": o.neutralsOnMapStart,
    "zombies_spawned": o.zombiesSpawned,
    "zombies_alive_end": o.zombiesAliveEnd,
    "zombies_killed": o.zombiesKilled,
    "outbreak_level_end": o.outbreakLevelEnd,
    "schedule_rounds": o.scheduleRounds,
    "tiebreak_round": o.tiebreakRound
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
  of yBc23:
    let spec = maps23.loadMap(mapName)
    let (w, o) = rules23.playGame(spec, sheets,
      [rules23.chassisKindFor(chassis[0]), rules23.chassisKindFor(chassis[1])],
      index, sideAslot, maxRounds, budgetSeconds)
    (GameOutcome(index: o.index, mapName: o.mapName, sideAslot: o.sideAslot,
      roundsPlayed: o.roundsPlayed, winnerSlot: o.winnerSlot,
      endReason: o.endReason, points: o.points, hashChain: o.hashChain,
      roundChains: o.roundChains, aborted: o.aborted,
      stats: statsJson23(o)), w.events)
  of yBc22:
    let spec = maps22.loadMap(mapName)
    let (w, o) = rules22.playGame(spec, sheets,
      [rules22.chassisKindFor(chassis[0]), rules22.chassisKindFor(chassis[1])],
      index, sideAslot, maxRounds, budgetSeconds)
    (GameOutcome(index: o.index, mapName: o.mapName, sideAslot: o.sideAslot,
      roundsPlayed: o.roundsPlayed, winnerSlot: o.winnerSlot,
      endReason: o.endReason, points: o.points, hashChain: o.hashChain,
      roundChains: o.roundChains, aborted: o.aborted,
      stats: statsJson22(o)), w.events)
  of yBc16:
    let spec = maps16.loadMap(mapName)
    let (w, o) = rules16.playGame(spec, sheets,
      [rules16.chassisKindFor(chassis[0]), rules16.chassisKindFor(chassis[1])],
      index, sideAslot, maxRounds, budgetSeconds)
    (GameOutcome(index: o.index, mapName: o.mapName, sideAslot: o.sideAslot,
      roundsPlayed: o.roundsPlayed, winnerSlot: o.winnerSlot,
      endReason: o.endReason, points: o.points, hashChain: o.hashChain,
      roundChains: o.roundChains, aborted: o.aborted,
      stats: statsJson16(o)), w.events)

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
