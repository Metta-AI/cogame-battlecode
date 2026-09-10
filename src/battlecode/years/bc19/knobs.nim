## The Battlecode 2019 "Crusade" knob table: ELEVEN knobs, and NO `chassis`
## key.
##
## D1 (the standing review finding): the chassis is not an LLM-selectable
## knob. The chassis a seat drives comes from `PLAYER_SCRIPTED` (scripted
## seats) or is the fixed champion chassis (LLM seats). A submitted `chassis`
## is therefore recorded as an UNKNOWN FIELD and never honoured, and
## `tests/test_bc19_sheet.nim` asserts exactly that — the test fails if
## anyone re-adds the knob.
##
## Unknown key, wrong type or out-of-range value takes THAT FIELD'S DEFAULT
## and the repair is recorded — except the FIVE INTEGER knobs, which CLAMP to
## their range rather than defaulting, so "as many as possible" still means
## something. A sheet can never be rejected, so a cog can never forfeit a
## match by answering badly — only by answering weakly.
##
## **THE ENVELOPE PIN, ITEM 2 (LEARNINGS 2026-09-08).** `applyKnobs19` adds an
## **ABSENT** known key to `defaultsApplied` as well as a repaired one, so
## `sheet_defaults_applied` for a bc19 seat is `[]` only when the cog really
## set all eleven knobs. This is deliberately **not** done year-neutrally in
## `sheet.nim`: doing so would change what a
## bc16/bc20/bc21/bc22/bc23/bc24/bc25/bc26 episode records in that array.
## `tests/test_bc19_sheet.nim` asserts a bc19 empty sheet reports all eleven
## names AND that a bc23 empty sheet still reports none, so the change is
## provably scoped.
##
## THE ANTI-INERT RULE, stated as a rule every knob is held against: NO
## SETTING OF ANY KNOB, AND NO COMBINATION OF SETTINGS, MAY PRODUCE AN INERT
## OR SELF-STARVING ORDER. The strategy surface lives inside ONE competent
## chassis. Independently of every knob, `saber` always: keeps at least one
## PILGRIM on a karbonite depot and at least one on a fuel depot from the
## first affordable build, and never lets a pilgrim idle loaded within reach
## of a deposit point; builds a military unit whenever karbonite and fuel
## allow and the military census is below its target, and NEVER FEWER THAN
## TWO MILITARY UNITS PER STRUCTURE; answers any enemy unit sensed within
## `defend_radius` of one of its own structures; never leaves a castle
## without an adjacent free square to build into; NEVER FIRES A PREACHER WHEN
## THE BLAST WOULD KILL MORE OF ITS OWN UNITS THAN THE ENEMY'S; and NEVER
## `give`s TO AN ENEMY STRUCTURE (legal, rule 6.6, and never a strategy).
## Every knob moves HOW MUCH OF WHAT, WHEN — never WHETHER IT PLAYS.
## `tests/test_bc19_knobs.nim` proves each knob has teeth and
## `tests/test_bc19_survival.nim` proves the floor holds, WITH A NEGATIVE
## CONTROL THAT MUST FAIL (`-d:bc19BrokenChassis`).
##
## THE CHASSIS FILE LAYOUT this table's "what it changes" column points at:
## `chassis/kit.nim`, `chassis/econ.nim`, `chassis/castle.nim`,
## `chassis/church.nim`, `chassis/pilgrim.nim`, `chassis/military.nim`,
## `chassis/micro.nim`, `chassis/lattice.nim`, `chassis/comms.nim`,
## `chassis/trade.nim`, `chassis/infiltrate.nim`, `chassis/saber.nim`,
## `chassis/examplefuncsplayer19.nim` and `chassis/scenario19.nim`. All
## FOURTEEN exist; `NOTICE` and `docs/RULES-BC19.md` name the same paths.

import std/[json, tables]
import ../../sheet_common

export sheet_common

type
  Opening19* = enum
    ## `econ.nim plan()` — the first-300-round budget split and posture, and
    ## the three archetypes the 2019 season actually produced.
    op19Turtle = "turtle"
    op19PreacherRush = "preacher_rush"
    op19PilgrimEco = "pilgrim_eco"

  ChurchExpansion19* = enum
    ## `church.nim plan()` — when a PILGRIM spends 50 karbonite / 200 fuel on
    ## a CHURCH.
    ce19Never = "never"
    ce19Mid = "mid"
    ce19Early = "early"

  SymmetryWall19* = enum
    ## `lattice.nim plan()` — what the order builds on the mirror line, which
    ## BOTH SIDES KNOW FROM ROUND 1.
    sw19Off = "off"
    sw19Screen = "screen"
    sw19Wall = "wall"

  CastleTalkUse19* = enum
    ## `comms.nim castleTalk()` — what the 8-bit, free, unlimited-range,
    ## castle-only channel carries.
    ct19Position = "position"
    ct19Census = "census"
    ct19Full = "full"

  TradePolicy19* = enum
    ## `trade.nim plan()` — THIS YEAR'S LARGEST UNEXPLOITED MECHANIC. A
    ## CASTLE may `proposeTrade(karbonite, fuel)`; when both orders' standing
    ## offers match element-wise the swap executes and both offers clear.
    tp19Never = "never"
    tp19Mirror = "mirror"
    tp19OfferFuel = "offer_fuel"
    tp19OfferKarbonite = "offer_karbonite"

  Doctrine19* = object
    opening*: Opening19
    pilgrimCurve*: int
    churchExpansion*: ChurchExpansion19
    fuelReserve*: int
    unitMix*: int
    preacherShare*: int
    churchSaberRound*: int
    symmetryWall*: SymmetryWall19
    castleTalkUse*: CastleTalkUse19
    defendRadius*: int
    tradePolicy*: TradePolicy19

const
  KnownKeys19* = [
    "opening", "pilgrim_curve", "church_expansion", "fuel_reserve",
    "unit_mix", "preacher_share", "church_saber_round", "symmetry_wall",
    "castle_talk_use", "defend_radius", "trade_policy"
  ]
    ## Exactly eleven. `chassis` is deliberately NOT here (D1).

  PilgrimCurveLo* = 0
  PilgrimCurveHi* = 24
  FuelReserveLo* = 0
  FuelReserveHi* = 2000
  UnitMixLo* = 0
  UnitMixHi* = 100
  PreacherShareLo* = 0
  PreacherShareHi* = 100
  ChurchSaberRoundLo* = 0
  ChurchSaberRoundHi* = 1000
  DefendRadiusLo* = 1
  DefendRadiusHi* = 400

  MilitaryPerStructureFloor* = 2
    ## The unconditional minimum, at EVERY knob setting.
  PilgrimPerStructureFloor* = 1
    ## `pilgrim_curve: 0` still builds ONE pilgrim per structure — the floor
    ## that keeps 0 from starving.

proc defaultDoctrine19*(): Doctrine19 =
  Doctrine19(
    opening: op19PilgrimEco,
    pilgrimCurve: 9,
    churchExpansion: ce19Mid,
    fuelReserve: 300,
    unitMix: 45,
    preacherShare: 20,
    churchSaberRound: 0,
    symmetryWall: sw19Screen,
    castleTalkUse: ct19Census,
    defendRadius: 100,
    tradePolicy: tp19Mirror)

proc applyKnobs19*(seen: Table[string, JsonNode],
                   defaultsApplied: var seq[string]): Doctrine19 =
  result = defaultDoctrine19()

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

  enumKnob("opening", result.opening, Opening19)
  clampedIntKnob("pilgrim_curve", result.pilgrimCurve,
                 PilgrimCurveLo, PilgrimCurveHi)
  enumKnob("church_expansion", result.churchExpansion, ChurchExpansion19)
  clampedIntKnob("fuel_reserve", result.fuelReserve,
                 FuelReserveLo, FuelReserveHi)
  clampedIntKnob("unit_mix", result.unitMix, UnitMixLo, UnitMixHi)
  clampedIntKnob("preacher_share", result.preacherShare,
                 PreacherShareLo, PreacherShareHi)
  clampedIntKnob("church_saber_round", result.churchSaberRound,
                 ChurchSaberRoundLo, ChurchSaberRoundHi)
  enumKnob("symmetry_wall", result.symmetryWall, SymmetryWall19)
  enumKnob("castle_talk_use", result.castleTalkUse, CastleTalkUse19)
  clampedIntKnob("defend_radius", result.defendRadius,
                 DefendRadiusLo, DefendRadiusHi)
  enumKnob("trade_policy", result.tradePolicy, TradePolicy19)

proc toJson19*(d: Doctrine19): JsonNode =
  %*{
    "opening": $d.opening,
    "pilgrim_curve": d.pilgrimCurve,
    "church_expansion": $d.churchExpansion,
    "fuel_reserve": d.fuelReserve,
    "unit_mix": d.unitMix,
    "preacher_share": d.preacherShare,
    "church_saber_round": d.churchSaberRound,
    "symmetry_wall": $d.symmetryWall,
    "castle_talk_use": $d.castleTalkUse,
    "defend_radius": d.defendRadius,
    "trade_policy": $d.tradePolicy
  }

proc bc19SheetSchema*(): JsonNode =
  ## The knob surface as the doctrine prompt carries it. Generated from THIS
  ## table rather than re-typed, so a knob cannot exist in the sim and be
  ## missing from the brief.
  let d = defaultDoctrine19()
  var openings = newJArray()
  for v in Opening19: openings.add(%($v))
  var expansions = newJArray()
  for v in ChurchExpansion19: expansions.add(%($v))
  var walls = newJArray()
  for v in SymmetryWall19: walls.add(%($v))
  var talks = newJArray()
  for v in CastleTalkUse19: talks.add(%($v))
  var trades = newJArray()
  for v in TradePolicy19: trades.add(%($v))
  %*{
    "opening": {"values": openings, "default": $d.opening,
                "note": "the three archetypes the 2019 season produced. " &
                        "turtle still builds pilgrims and still works " &
                        "depots -- the economy target is HALVED, never " &
                        "zeroed"},
    "pilgrim_curve": {"range": [PilgrimCurveLo, PilgrimCurveHi],
                      "default": d.pilgrimCurve,
                      "note": "pilgrims wanted PER STRUCTURE at round 100, " &
                              "ramped linearly from 1 at round 1 and held " &
                              "after. A pilgrim is 10 karbonite / 50 fuel " &
                              "and returns +2 karbonite or +10 fuel a turn " &
                              "while it stands on a depot, so the payback " &
                              "is about five turns of karbonite mining and " &
                              "the ceiling is the number of depots (4-13 " &
                              "karbonite and 2-16 fuel a side on the " &
                              "played pool). At 0 the order still builds " &
                              "ONE pilgrim per structure"},
    "church_expansion": {"values": expansions, "default": $d.churchExpansion,
                         "note": "a CHURCH is 50 karbonite / 200 fuel, can " &
                                 "only be built by a PILGRIM, and is a " &
                                 "second spawn point AND a second deposit " &
                                 "point -- and a free 100 HP gift to a " &
                                 "raider"},
    "fuel_reserve": {"range": [FuelReserveLo, FuelReserveHi],
                     "default": d.fuelReserve,
                     "note": "the global fuel floor below which the order " &
                             "funds ONLY mine and move. Fuel is the thing " &
                             "that stops a bc19 army dead: the only " &
                             "passive income is 25 a round, an attack is " &
                             "10-25 and a preacher's move is 3 per " &
                             "range-squared"},
    "unit_mix": {"range": [UnitMixLo, UnitMixHi], "default": d.unitMix,
                 "note": "percent of the MILITARY karbonite budget spent " &
                         "on PROPHETs rather than CRUSADERs. A prophet is " &
                         "25 karbonite, 20 HP, hits for 10 at " &
                         "range-squared 16-64 and CANNOT HIT ANYTHING " &
                         "INSIDE 16; a crusader is 15 karbonite, 40 HP, " &
                         "hits at 1-16 and moves at range-squared 9 -- " &
                         "twice as far per turn as anything else. Reach or " &
                         "legs"},
    "preacher_share": {"range": [PreacherShareLo, PreacherShareHi],
                       "default": d.preacherShare,
                       "note": "percent of the REMAINDER AFTER PROPHETS " &
                               "spent on PREACHERs, so the crusader share " &
                               "is (100-unit_mix)*(100-preacher_share)/100. " &
                               "A preacher puts 20 damage on EVERY " &
                               "OCCUPIED SQUARE within range-squared 3 of " &
                               "the target -- nine squares -- WITH NO TEAM " &
                               "CHECK, including its own square when it " &
                               "fires closer than range-squared 4. The " &
                               "chassis refuses a shot that would kill " &
                               "more of its own units than the enemy's at " &
                               "EVERY setting"},
    "church_saber_round": {"range": [ChurchSaberRoundLo, ChurchSaberRoundHi],
                           "default": d.churchSaberRound,
                           "note": "0 means NEVER; otherwise the round at " &
                                   "which a PILGRIM plus a two-unit escort " &
                                   "is committed to building a CHURCH " &
                                   "INSIDE THE ENEMY'S HALF"},
    "symmetry_wall": {"values": walls, "default": $d.symmetryWall,
                      "note": "off: no static line. screen: a SPARSE " &
                              "prophet lattice occupying every other " &
                              "square, so pilgrims still pass and a " &
                              "preacher blast can only catch one prophet. " &
                              "wall: a DENSE lattice, which stops crusaders " &
                              "cold and also blocks your own pilgrims and " &
                              "turns one enemy preacher shot into three " &
                              "dead prophets"},
    "castle_talk_use": {"values": talks, "default": $d.castleTalkUse,
                        "note": "the 8-bit, free, unlimited-range, " &
                                "castle-only channel: one byte per unit " &
                                "per turn and the only global channel in " &
                                "the game"},
    "defend_radius": {"range": [DefendRadiusLo, DefendRadiusHi],
                      "default": d.defendRadius,
                      "note": "the SQUARED radius around a friendly " &
                              "structure inside which a military unit " &
                              "breaks off to answer an enemy. 100 is a " &
                              "castle's own vision radius"},
    "trade_policy": {"values": trades, "default": $d.tradePolicy,
                     "note": "a CASTLE may propose a karbonite-for-fuel " &
                             "swap to the ENEMY's castles; when both " &
                             "standing offers match element-wise the swap " &
                             "executes and both offers clear. Positive " &
                             "means the resource moves RED to BLUE. One " &
                             "mining turn is 2 karbonite or 10 fuel, so " &
                             "five fuel to a karbonite is the fair rate"}
  }

proc plainWords19*(d: Doctrine19): seq[string] =
  ## The endcard / doctrine-overlay readout: the sheet in words a spectator
  ## can read without knowing the schema. EVERY VALUE MAPS TO A COMPLETE
  ## CLAUSE and there is NO ARTICLE CONCATENATION anywhere — the endcard fix
  ## that stops "a accelerating"-class grammar.
  result.add(case d.opening
    of op19Turtle: "turtles behind a prophet lattice and wins on castles"
    of op19PreacherRush: "rushes preachers at their castles from round one"
    of op19PilgrimEco: "mines first and fights later")
  result.add("wants " & $d.pilgrimCurve & " pilgrims per structure by " &
    "round one hundred")
  result.add(case d.churchExpansion
    of ce19Never: "never sends a pilgrim out to raise a church"
    of ce19Mid: "expands to a church once the depots run short"
    of ce19Early: "raises a church at the first good depot cluster")
  result.add("keeps " & $d.fuelReserve & " fuel in the bank before it " &
    "spends on war")
  result.add("spends " & $d.unitMix & " percent of its army karbonite on " &
    "prophets")
  result.add("spends " & $d.preacherShare & " percent of what is left on " &
    "preachers")
  result.add(if d.churchSaberRound == 0:
      "never sends a church into their half"
    else:
      "commits a church inside their half at round " & $d.churchSaberRound)
  result.add(case d.symmetryWall
    of sw19Off: "leaves the midline open and walks at their castles"
    of sw19Screen: "screens the midline without closing it"
    of sw19Wall: "walls the midline shut, its own pilgrims included")
  result.add(case d.castleTalkUse
    of ct19Position: "tells its castles where every structure stands"
    of ct19Census: "tells its castles the census"
    of ct19Full: "tells its castles the census and every alarm")
  result.add("answers anything within range-squared " & $d.defendRadius &
    " of a structure")
  result.add(case d.tradePolicy
    of tp19Never: "never barters with the enemy"
    of tp19Mirror: "matches a barter only when the rate favours it"
    of tp19OfferFuel: "stands an offer to sell fuel for karbonite"
    of tp19OfferKarbonite: "stands an offer to sell karbonite for fuel")
