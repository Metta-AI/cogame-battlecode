## The Battlecode 2017 "Robotic Wildlife Fund" knob table: ELEVEN knobs, and
## NO `chassis` key.
##
## D0 (the standing review finding): the chassis is not an LLM-selectable
## knob. The chassis a seat drives comes from `PLAYER_SCRIPTED` (scripted
## seats) or is the fixed champion chassis (LLM seats). A submitted `chassis`
## is therefore recorded as an UNKNOWN FIELD and never honoured, and
## `tests/test_bc17_sheet.nim` asserts exactly that -- the test fails if
## anyone re-adds the knob.
##
## Unknown key, wrong type or out-of-range value takes THAT FIELD'S DEFAULT
## and the repair is recorded -- except the FIVE INTEGER knobs plus
## `bullet_reserve`, which CLAMP to their range rather than defaulting, so "as
## many as possible" still means something. A sheet can never be rejected, so
## a cog can never forfeit a match by answering badly -- only by answering
## weakly.
##
## **THE ENVELOPE PIN, ITEM 2 (LEARNINGS 2026-09-08).** `applyKnobs17` adds an
## **ABSENT** known key to `defaultsApplied` as well as a repaired one, so
## `sheet_defaults_applied` for a bc17 seat is `[]` only when the cog really
## set all eleven knobs. This is deliberately **not** done year-neutrally in
## `sheet.nim`: doing so would change what a bc16/bc19..bc26 episode records
## in that array. `tests/test_bc17_sheet.nim` asserts a bc17 empty sheet
## reports all eleven names AND that a bc19 empty sheet still reports none, so
## the change is provably scoped.
##
## THE ANTI-INERT RULE, stated as a rule every knob is held against: NO
## SETTING OF ANY KNOB, AND NO COMBINATION OF SETTINGS, MAY PRODUCE AN INERT
## OR SELF-STARVING FACTION. The strategy surface lives inside ONE competent
## chassis. Independently of every knob, `orchard` always: hires at least one
## GARDENER per archon and replaces a dead one; plants its first tree by round
## 60 and keeps at least three alive whenever it can afford them; waters the
## lowest-health own tree in reach every turn a gardener has nothing better to
## do; builds a fighter whenever bullets allow and the census is below target,
## never fewer than two per gardener; answers any enemy sensed within
## `defend_radius` of its own gardeners, archons or trees; NEVER FIRES A
## LUMBERJACK `strike()` WHOSE OWN-HP COST EXCEEDS THE ENEMY'S (it hits its own
## trees, and its own trees are its income); never walks a TANK onto its own
## tree; and never donates below `bullet_reserve` unless `vp_donate_policy` is
## `rush_1000`. Every knob moves HOW MUCH OF WHAT, WHEN -- never WHETHER IT
## PLAYS. `tests/test_bc17_knobs.nim` proves each knob has teeth and
## `tests/test_bc17_survival.nim` proves the floor holds, WITH A NEGATIVE
## CONTROL THAT MUST FAIL (`-d:bc17BrokenChassis`).
##
## THE CHASSIS FILE LAYOUT this table's "what it changes" column points at:
## `chassis/kit.nim`, `chassis/econ.nim`, `chassis/archon.nim`,
## `chassis/gardener.nim`, `chassis/farm.nim`, `chassis/military.nim`,
## `chassis/micro.nim`, `chassis/lumberjack.nim`, `chassis/scout.nim`,
## `chassis/donate.nim`, `chassis/comms.nim`, `chassis/orchard.nim`,
## `chassis/examplefuncsplayer17.nim` and `chassis/scenario17.nim`. All
## FOURTEEN exist; `NOTICE` and `docs/RULES-BC17.md` name the same paths.

import std/[json, tables]
import ../../sheet_common

export sheet_common

type
  Opening17* = enum
    ## `econ.nim plan()` -- the first-400-round budget split and posture, and
    ## the four archetypes the 2017 season actually produced.
    op17TreeFarm = "tree_farm"
    op17TankRush = "tank_rush"
    op17LumberjackSwarm = "lumberjack_swarm"
    op17ScoutSquat = "scout_squat"

  FarmLayout17* = enum
    ## `farm.nim slots()` -- where the trees go, and a real geometry choice
    ## because trees are also walls.
    fl17Hex = "hex"
    fl17Line = "line"
    fl17Ring = "ring"

  VpDonatePolicy17* = enum
    ## `donate.nim plan()` -- the knob this year is actually about.
    vp17Never = "never"
    vp17WhenAhead = "when_ahead"
    vp17Rush1000 = "rush_1000"
    vp17EndgameDump = "endgame_dump"

  ShakeNeutralTrees17* = enum
    ## `scout.nim shake()` + `gardener.nim` -- `shake()` is free, takes one
    ## turn, works for ANY robot at distance 1 and hands over every bullet
    ## inside the tree.
    sn17Never = "never"
    sn17Opportunistic = "opportunistic"
    sn17Dedicated = "dedicated"

  ChopPolicy17* = enum
    ## `lumberjack.nim plan()` -- a chop is the ONLY action that releases a
    ## neutral tree's contents, and one played map has 406 trees each holding
    ## a robot.
    cp17Never = "never"
    cp17ClearPath = "clear_path"
    cp17Harvest = "harvest"

  Doctrine17* = object
    opening*: Opening17
    gardenerCount*: int
    farmLayout*: FarmLayout17
    soldierTankRatio*: int
    lumberjackShare*: int
    scoutHarass*: int
    vpDonatePolicy*: VpDonatePolicy17
    shakeNeutralTrees*: ShakeNeutralTrees17
    chopPolicy*: ChopPolicy17
    bulletReserve*: int
    defendRadius*: int

const
  KnownKeys17* = [
    "opening", "gardener_count", "farm_layout", "soldier_tank_ratio",
    "lumberjack_share", "scout_harass", "vp_donate_policy",
    "shake_neutral_trees", "chop_policy", "bullet_reserve", "defend_radius"
  ]
    ## Exactly eleven. `chassis` is deliberately NOT here (D0).

  GardenerCountLo* = 1
  GardenerCountHi* = 8
  SoldierTankRatioLo* = 0
  SoldierTankRatioHi* = 100
  LumberjackShareLo* = 0
  LumberjackShareHi* = 100
  ScoutHarassLo* = 0
  ScoutHarassHi* = 100
  BulletReserveLo* = 0
  BulletReserveHi* = 2000
  DefendReachLo* = 1
  DefendReachHi* = 40
    ## The `defend_radius` bounds. NOT named `DefendRadius*`: bc19's knobs
    ## already export those two symbols with different values, and a shard
    ## that imports both years through the year-neutral sheet arm would see
    ## an ambiguous identifier.

  GardenerPerArchonFloor* = 1
    ## The unconditional minimum, at EVERY knob setting.
  TreesAliveFloor* = 3
    ## `orchard` keeps three trees alive whenever it can afford them, at every
    ## setting of every knob -- a farm is what pays for anything else.
  FirstTreeByRound* = 60
  FightersPerGardenerFloor* = 2

proc defaultDoctrine17*(): Doctrine17 =
  Doctrine17(
    opening: op17TreeFarm,
    gardenerCount: 3,
    farmLayout: fl17Hex,
    soldierTankRatio: 25,
    lumberjackShare: 20,
    scoutHarass: 15,
    vpDonatePolicy: vp17WhenAhead,
    shakeNeutralTrees: sn17Opportunistic,
    chopPolicy: cp17ClearPath,
    bulletReserve: 200,
    defendRadius: 12)

proc applyKnobs17*(seen: Table[string, JsonNode],
                   defaultsApplied: var seq[string]): Doctrine17 =
  result = defaultDoctrine17()

  template repair(name: string) =
    defaultsApplied.add(name)

  template enumKnob(name: string, field: untyped, T: typedesc) =
    if name in seen:
      if seen[name].kind == JString:
        let text = normalizeKey(seen[name].getStr())
        var found = false
        for value in T:
          if normalizeKey($value) == text:
            field = value
            found = true
        if not found: repair(name)
      else:
        repair(name)
    else:
      ## THE ENVELOPE PIN, ITEM 2: an ABSENT known key is counted too, so a
      ## seat that played the schema defaults is machine-visible.
      repair(name)

  template clampedIntKnob(name: string, field: untyped, lo, hi: int) =
    ## AN INTEGER KNOB IS CLAMPED, NEVER DEFAULTED, so "as many as possible"
    ## still means something. A NON-INTEGER takes the default.
    if name in seen:
      let n = readNumber(seen[name])
      if n.ok:
        let v = int(n.value)
        if v < lo or v > hi:
          field = max(lo, min(hi, v))
          repair(name)
        else:
          field = v
      else:
        repair(name)
    else:
      repair(name)

  enumKnob("opening", result.opening, Opening17)
  clampedIntKnob("gardener_count", result.gardenerCount,
                 GardenerCountLo, GardenerCountHi)
  enumKnob("farm_layout", result.farmLayout, FarmLayout17)
  clampedIntKnob("soldier_tank_ratio", result.soldierTankRatio,
                 SoldierTankRatioLo, SoldierTankRatioHi)
  clampedIntKnob("lumberjack_share", result.lumberjackShare,
                 LumberjackShareLo, LumberjackShareHi)
  clampedIntKnob("scout_harass", result.scoutHarass,
                 ScoutHarassLo, ScoutHarassHi)
  enumKnob("vp_donate_policy", result.vpDonatePolicy, VpDonatePolicy17)
  enumKnob("shake_neutral_trees", result.shakeNeutralTrees,
           ShakeNeutralTrees17)
  enumKnob("chop_policy", result.chopPolicy, ChopPolicy17)
  clampedIntKnob("bullet_reserve", result.bulletReserve,
                 BulletReserveLo, BulletReserveHi)
  clampedIntKnob("defend_radius", result.defendRadius,
                 DefendReachLo, DefendReachHi)

proc toJson17*(d: Doctrine17): JsonNode =
  %*{
    "opening": $d.opening,
    "gardener_count": d.gardenerCount,
    "farm_layout": $d.farmLayout,
    "soldier_tank_ratio": d.soldierTankRatio,
    "lumberjack_share": d.lumberjackShare,
    "scout_harass": d.scoutHarass,
    "vp_donate_policy": $d.vpDonatePolicy,
    "shake_neutral_trees": $d.shakeNeutralTrees,
    "chop_policy": $d.chopPolicy,
    "bullet_reserve": d.bulletReserve,
    "defend_radius": d.defendRadius
  }

proc bc17SheetSchema*(): JsonNode =
  ## The knob surface as the doctrine prompt carries it. Generated from THIS
  ## table rather than re-typed, so a knob cannot exist in the sim and be
  ## missing from the brief.
  let d = defaultDoctrine17()
  var openings = newJArray()
  for v in Opening17: openings.add(%($v))
  var layouts = newJArray()
  for v in FarmLayout17: layouts.add(%($v))
  var donates = newJArray()
  for v in VpDonatePolicy17: donates.add(%($v))
  var shakes = newJArray()
  for v in ShakeNeutralTrees17: shakes.add(%($v))
  var chops = newJArray()
  for v in ChopPolicy17: chops.add(%($v))
  %*{
    "opening": {"values": openings, "default": $d.opening,
                "note": "the four archetypes the 2017 season produced. " &
                        "Each of them still plants trees and still hires " &
                        "gardeners -- the economy target is HALVED, never " &
                        "zeroed"},
    "gardener_count": {"range": [GardenerCountLo, GardenerCountHi],
                       "default": d.gardenerCount,
                       "note": "GARDENERs wanted PER LIVING ARCHON. A " &
                               "gardener is 100 bullets and is the only " &
                               "unit that can plant a tree (50) or water " &
                               "one (+5 a turn), and its ten-turn build " &
                               "cooldown is SHARED between planting and " &
                               "building -- so this is literally how many " &
                               "parallel ten-turn slots the faction owns"},
    "farm_layout": {"values": layouts, "default": $d.farmLayout,
                    "note": "hex packs up to six radius-1 trees around one " &
                            "gardener, which waters all six without moving " &
                            "and loses all six to one lumberjack strike; " &
                            "line makes the farm a wall across the " &
                            "approach and spreads the strike damage; ring " &
                            "keeps the archon's spawn ring clear and lets " &
                            "fighters through"},
    "soldier_tank_ratio": {"range": [SoldierTankRatioLo, SoldierTankRatioHi],
                           "default": d.soldierTankRatio,
                           "note": "percent of the MILITARY bullet budget " &
                                   "spent on TANKs rather than SOLDIERs. A " &
                                   "tank is 300 bullets, 200 health, " &
                                   "bullet speed 4 and 5 damage a bullet, " &
                                   "and it damages a tree just by trying " &
                                   "to walk onto it; a soldier is 100, 50, " &
                                   "speed 2 and 2 damage. One tank is " &
                                   "three soldiers' bullets at 1.5x the " &
                                   "health and 2.5x the per-bullet damage, " &
                                   "in one body a lumberjack swarm can " &
                                   "surround"},
    "lumberjack_share": {"range": [LumberjackShareLo, LumberjackShareHi],
                         "default": d.lumberjackShare,
                         "note": "percent of the REMAINDER AFTER TANKS " &
                                 "spent on LUMBERJACKs -- the knob that " &
                                 "decides whether the faction can open a " &
                                 "tree-dense map at all (Chess has 924 " &
                                 "neutral trees) and whether it can answer " &
                                 "an enemy farm. At 100 the faction has no " &
                                 "ranged damage at all, which the " &
                                 "anti-inert floor allows because a " &
                                 "lumberjack still kills"},
    "scout_harass": {"range": [ScoutHarassLo, ScoutHarassHi],
                     "default": d.scoutHarass,
                     "note": "percent of the remainder after tanks and " &
                             "lumberjacks spent on SCOUTs, and how deep " &
                             "they go: below 34 they screen own trees and " &
                             "shake on the way, 34-66 they squat the " &
                             "enemy's neutral trees, above 66 they hunt " &
                             "gardeners and never come home. A scout has " &
                             "TEN health"},
    "vp_donate_policy": {"values": donates, "default": $d.vpDonatePolicy,
                         "note": "a victory point costs 7.5 bullets on " &
                                 "round 1 and 19.996 on round 2999, so the " &
                                 "same 13750 bullets buys 1000 points " &
                                 "early or 690 late. never plays for " &
                                 "annihilation and the tree tiebreak; " &
                                 "when_ahead compounds a lead at the " &
                                 "cheapest price it can afford; rush_1000 " &
                                 "buys the win from round one and has " &
                                 "almost no army; endgame_dump banks " &
                                 "everything and wins the " &
                                 "bullets-plus-robot-cost tiebreak"},
    "shake_neutral_trees": {"values": shakes,
                            "default": $d.shakeNeutralTrees,
                            "note": "shake() is free, takes one turn and " &
                                    "works for ANY robot at distance 1. A " &
                                    "bc17 map carries 0 to 1282 neutral " &
                                    "trees and Chess alone has 892 holding " &
                                    "bullets; Alone has none at all, where " &
                                    "dedicated is a wasted scout"},
    "chop_policy": {"values": chops, "default": $d.chopPolicy,
                    "note": "a chop is 5 damage to one tree and the ONLY " &
                            "action that releases a neutral tree's " &
                            "contents. clear_path chops what blocks the " &
                            "rally lane; harvest prefers trees that " &
                            "contain a ROBOT (Maniple has 406 of them) at " &
                            "200 x radius health each"},
    "bullet_reserve": {"range": [BulletReserveLo, BulletReserveHi],
                       "default": d.bulletReserve,
                       "note": "the bullet floor below which the faction " &
                               "funds ONLY gardeners, trees and water. THE " &
                               "DEFAULT IS 200 FOR A MEASURED REASON: the " &
                               "passive trickle is max(0, 2 - 0.01 x " &
                               "bullets), which is EXACTLY ZERO at 200 and " &
                               "above, so a faction sitting on 200 earns " &
                               "nothing from it while a faction at 100 " &
                               "earns 1 a round"},
    "defend_radius": {"range": [DefendReachLo, DefendReachHi],
                      "default": d.defendRadius,
                      "note": "the radius (in units, NOT squared -- 2017 " &
                              "sensing is a Euclidean distance) around a " &
                              "friendly ARCHON, GARDENER or bullet tree " &
                              "inside which a fighter breaks off to answer " &
                              "an enemy. 12 is a little under twice a " &
                              "soldier's sensor radius of 7"}
  }

proc plainWords17*(d: Doctrine17): seq[string] =
  ## The endcard / doctrine-overlay readout: the sheet in words a spectator
  ## can read without knowing the schema. EVERY VALUE MAPS TO A COMPLETE
  ## CLAUSE and there is NO ARTICLE CONCATENATION anywhere -- the endcard fix
  ## that stops "a accelerating"-class grammar.
  result.add(case d.opening
    of op17TreeFarm: "farms first and fights later"
    of op17TankRush: "walks tanks at their archon from the first bullets"
    of op17LumberjackSwarm: "sends lumberjacks in threes to delete the farm"
    of op17ScoutSquat: "parks scouts on their trees where nothing can reach")
  result.add("wants " & $d.gardenerCount & " gardeners for every archon")
  result.add(case d.farmLayout
    of fl17Hex: "packs its trees six to a gardener"
    of fl17Line: "plants its trees in a line across the approach"
    of fl17Ring: "rings its archon with trees and leaves four lanes")
  result.add("spends " & $d.soldierTankRatio &
    " percent of its army money on tanks")
  result.add("spends " & $d.lumberjackShare &
    " percent of what is left on lumberjacks")
  result.add("spends " & $d.scoutHarass & " percent of the rest on scouts")
  result.add(case d.vpDonatePolicy
    of vp17Never: "never buys a victory point and plays for annihilation"
    of vp17WhenAhead: "donates whenever it is ahead on points"
    of vp17Rush1000: "buys victory points from round one"
    of vp17EndgameDump: "banks every bullet and converts at the end")
  result.add(case d.shakeNeutralTrees
    of sn17Never: "never spends a turn shaking a neutral tree"
    of sn17Opportunistic: "shakes any tree it happens to stand beside"
    of sn17Dedicated: "sends a scout on a shaking circuit")
  result.add(case d.chopPolicy
    of cp17Never: "never chops, and only strikes"
    of cp17ClearPath: "chops only what blocks the lane"
    of cp17Harvest: "chops the trees with robots inside them")
  result.add("keeps " & $d.bulletReserve & " bullets in the bank before it " &
    "spends on war")
  result.add("answers anything within " & $d.defendRadius &
    " of a gardener, an archon or a tree")
