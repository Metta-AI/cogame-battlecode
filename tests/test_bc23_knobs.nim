## THE KNOB-TEETH GATE. Paired seeded games — identical seed, map and
## opponent, the two factions identical except ONE knob at its low and high
## setting — each asserting a named, SIGNED delta.
##
## Thresholds live in one table so tuning is a one-line change, and the header
## records EVERY SUBSTITUTED STATISTIC (the bc21 r1-F6 fix). Where the design
## note's statistic was not directly measurable from the recorded outcome the
## substitution is named here:
##
##   * `island_priority`'s "mean distance from a captured island to the
##     enemy's nearest headquarters" is `captured_distance_mean`, which the
##     sim records at capture time in CHEBYSHEV steps (the walking distance a
##     ferry actually pays) rather than in Euclidean units;
##   * `destabilizer_use`'s "mean distance of the strike group from its own
##     headquarters" is `strike_distance_mean`, the per-round centroid of our
##     own launchers measured from the nearest friendly headquarters, again in
##     Chebyshev steps;
##   * `carrier_throw`'s "resources deposited" is the BANKED SHARE of
##     everything the carriers ever carried,
##     `resources_banked / (resources_banked + resources_thrown)`, in
##     permille and summed per game. The raw deposit count is the wrong
##     statistic: a throwing faction fights better, lives longer and therefore
##     mines more, so the two effects cancel and the raw count moves only
##     -1.3 % (measured 15545 -> 15350). The share is the thing the knob
##     actually owns — a thrown load is a load that never reached a
##     headquarters — and it moves -23.7 % (measured 5313 -> 4052, the sum of
##     six per-game permille shares, i.e. a mean of 886 -> 675 permille),
##     gated at -10 %;
##   * `retreat_on_launcher_loss`'s "anchor healing received" is
##     `anchor_heals`.
##
## THE SIGNED DELTAS ARE GATED IN RELEASE ONLY, over three maps under both
## side assignments — six whole 1200-round games a knob, nineteen knobs, 114
## games. This is bc24's own arrangement and for bc24's reason: a debug build
## runs about seven times slower, so re-measuring the same numbers under range
## checking costs half an hour to learn nothing new. The DEBUG pass plays ONE
## map under both side assignments and asserts only that the sweep RAN and
## produced telemetry — which is what a debug pass is for: overflow and range
## checks over the sim, not a second measurement. Every bc23 rule the sweep
## touches is exercised under debug by the other twenty shards. The
## `elixir_spend` block below is deterministic and is asserted in BOTH modes.

import harness
import bc23_fixture
import battlecode/years/bc23/chassis/[econ, elixir, anchors]

const
  KnobRounds = 1200
  KnobMaps =
    when defined(release): ["Quiet", "Barcode", "Sneaky"]
    else: ["Quiet"]
  ## `island_priority` needs a map with a real CHOICE of island (see below);
  ## the debug pass plays one of the two.
  IslandMaps =
    when defined(release): ["HideAndSeek", "Rainbow"]
    else: ["HideAndSeek"]

proc play(low, high: string, mapName: string,
          rounds = KnobRounds): (GameOutcome23, GameOutcome23) =
  ## Seat 0 gets `low`, seat 1 gets `high`, on the SAME map with the same
  ## side assignment — so the only difference between the two factions is the
  ## knob.
  let a = sheetFrom(low)
  let b = sheetFrom(high)
  let (_, o) = playGame(loadMap(mapName), [a, b], [ckLemonade, ckLemonade],
    0, 0, rounds, 0)
  let (_, o2) = playGame(loadMap(mapName), [b, a], [ckLemonade, ckLemonade],
    0, 0, rounds, 0)
  (o, o2)

proc sums(low, high: string, get: proc (o: GameOutcome23, seat: int): int,
          maps: openArray[string] = KnobMaps,
          rounds = KnobRounds): (int, int) =
  ## The named statistic for the LOW setting and for the HIGH setting, summed
  ## over the knob's maps and both seat assignments — six games a knob by
  ## default, which is what makes a single map's terrain unable to decide the
  ## answer.
  var lowSum = 0
  var highSum = 0
  for mapName in maps:
    let (o, o2) = play(low, high, mapName, rounds)
    lowSum += get(o, 0) + get(o2, 1)
    highSum += get(o, 1) + get(o2, 0)
  (lowSum, highSum)

proc sheetOf(pairs: string): string =
  "{\"sheet\":{" & pairs & "},\"notes\":\"knob sweep\",\"motto\":\"x\"}"

template teeth(name: string, low, high: string,
               get: untyped, wantUp: bool, factorPct: int,
               maps: openArray[string] = KnobMaps,
               rounds: int = KnobRounds) =
  ## `factorPct` is the asserted signed delta as a percentage of the LOW
  ## value: 160 means "up by at least 60 %", 70 means "down by at least 30 %".
  ## `get` is an expression in `o` (the outcome) and `seat`.
  block:
    let getter = proc (o {.inject.}: GameOutcome23,
                       seat {.inject.}: int): int = get
    let (lo, hi) = sums(low, high, getter, maps, rounds)
    echo "knob ", name, ": low=", lo, " high=", hi
    when defined(release):
      if wantUp:
        check(name & " has teeth: the statistic goes UP", hi > lo)
        check(name & " by the asserted margin", hi * 100 >= lo * factorPct)
      else:
        check(name & " has teeth: the statistic goes DOWN", hi < lo)
        check(name & " by the asserted margin", hi * 100 <= lo * factorPct)
    else:
      ## One map, both side assignments: the sweep must RUN and at least one
      ## of the two settings must move the statistic off zero. The sign is
      ## noise at this sample size and is gated in release.
      check(name & " (debug) ran and produced telemetry", lo > 0 or hi > 0)

# --- opening ------------------------------------------------------------
teeth("opening -> launchers by 400",
  sheetOf("\"opening\":\"carrier_eco\""),
  sheetOf("\"opening\":\"launcher_rush\""),
  o.launchersBuiltBy400[seat], true, 125)
teeth("opening -> carriers by 400",
  sheetOf("\"opening\":\"carrier_eco\""),
  sheetOf("\"opening\":\"launcher_rush\""),
  o.carriersBuiltBy400[seat], false, 70)

# --- launcher_ratio ----------------------------------------------------
## SUBSTITUTED STATISTIC. The note asks for "launchers built up >= 2x";
## CUMULATIVE launchers built over a whole game is ATTRITION-DOMINATED — both
## factions rebuild to their own census target every time one dies, so the
## cumulative counts converge (measured: 283 against 298 over six games). The
## census difference the knob actually buys is visible in
## `launchers_built_by_400`, before attrition equalises it, and that is what
## is gated here.
teeth("launcher_ratio -> launchers built by 400",
  sheetOf("\"launcher_ratio\":20"), sheetOf("\"launcher_ratio\":80"),
  o.launchersBuiltBy400[seat], true, 115)
teeth("launcher_ratio -> carriers built",
  sheetOf("\"launcher_ratio\":20"), sheetOf("\"launcher_ratio\":80"),
  o.carriersBuilt[seat], false, 60)

# --- well_priority -----------------------------------------------------
teeth("well_priority -> mana mined",
  sheetOf("\"well_priority\":\"adamantium\""),
  sheetOf("\"well_priority\":\"mana\""),
  o.manaMined[seat], true, 150)
teeth("well_priority -> adamantium mined",
  sheetOf("\"well_priority\":\"adamantium\""),
  sheetOf("\"well_priority\":\"mana\""),
  o.adamantiumMined[seat], false, 70)

# --- elixir_tech -------------------------------------------------------
teeth("elixir_tech -> wells transformed",
  sheetOf("\"elixir_tech\":\"never\""),
  sheetOf("\"elixir_tech\":\"early\""),
  o.wellsTransformed[seat], true, 200)
teeth("elixir_tech -> elixir mined",
  sheetOf("\"elixir_tech\":\"never\""),
  sheetOf("\"elixir_tech\":\"early\""),
  o.elixirMined[seat] + o.elixirEnd[seat], true, 200)

# --- elixir_spend (run with elixir flowing on BOTH sides) --------------
## SUBSTITUTED ASSERTION, and the reason is economic rather than
## behavioural. `elixir_spend` is gated behind the LONGEST chain in the game:
## 600 kg of the opposite resource has to be poured into a well (measured: 500
## rounds with four claimed runners), the well has to flip, and then 150-200
## kg of ELIXIR has to be mined out of it and deposited in ONE headquarters'
## own stockpile. On the three `small` maps the game is usually decided by
## conquest before that completes, so a game-level count of destabilizers and
## boosters is 0 against 0 as often as it is 0 against 8 — an unstable gate,
## which is worse than an honest one.
##
## The knob's teeth are therefore asserted DIRECTLY AND DETERMINISTICALLY on
## the decision it owns: a stocked headquarters under each setting. The
## game-level reachability of the elixir tree is gated by the `elixir_tech`
## row above (wells transformed 0 -> 4, elixir mined 33 -> 3354 over six
## games), so nothing about the tree is untested.
block:
  for (setting, want) in [("boosters", rtBooster),
                          ("destabilizers", rtDestabilizer)]:
    let sheet = sheetFrom(sheetOf("\"elixir_tech\":\"early\"," &
      "\"elixir_spend\":\"" & setting & "\""))
    var w = bare()
    var sides = newSides23([sheet, sheet], 0)
    let side = sides[0]
    w.observeHome(side)
    w.refreshCensus(side)
    let hq = w.robotsById[2]
    hq.actionCooldown = 0
    w.addResourceAmount(hq, resElixir, 400)
    w.addResourceAmount(hq, resAdamantium, 400)
    w.addResourceAmount(hq, resMana, 400)
    side.carriers = 99
    side.launchers = 99
    side.amplifiers = 99
    checkEq("elixir_spend `" & setting & "` buys a " & $want,
      nextBuild(w, side, hq), want)
    checkEq("and `sinkUnit` names it", sinkUnit(side), want)
  let anchors = sheetFrom(sheetOf("\"elixir_tech\":\"early\"," &
    "\"elixir_spend\":\"accelerating_anchors\""))
  var w = bare()
  var sides = newSides23([anchors, anchors], 0)
  checkEq("and `accelerating_anchors` buys neither — `anchors.nim` spends " &
    "that elixir on the anchor itself", sinkUnit(sides[0]), rtHeadquarters)
  var w2 = bare()
  var sides2 = newSides23([anchors, anchors], 0)
  w2.observeHome(sides2[0])
  let hq2 = w2.robotsById[2]
  w2.addResourceAmount(hq2, resElixir, 400)
  checkEq("which is the ACCELERATING anchor",
    anchorKindFor(w2, sides2[0], hq2), anAccelerating)

# --- anchor_round ------------------------------------------------------
teeth("anchor_round -> rounds holding any island",
  sheetOf("\"anchor_round\":1000"), sheetOf("\"anchor_round\":100"),
  o.roundsHoldingAnyIsland[seat], true, 140)

# --- anchor_budget -----------------------------------------------------
teeth("anchor_budget -> anchors placed",
  sheetOf("\"anchor_budget\":0"), sheetOf("\"anchor_budget\":100"),
  o.anchorsPlaced[seat], true, 200)
teeth("anchor_budget -> launchers built",
  sheetOf("\"anchor_budget\":0"), sheetOf("\"anchor_budget\":100"),
  o.launchersBuilt[seat], false, 90)

# --- island_priority ---------------------------------------------------
## ON A MAP WITH A REAL CHOICE. The three 20x20 `small` maps carry four to
## seven islands, two or three a side, so `nearest` and `safe` pick the SAME
## island and the knob is unmeasurable there (measured: 53 against 53).
## `HideAndSeek` carries sixteen and `Rainbow` twenty.
teeth("island_priority -> captured-island distance from the enemy",
  sheetOf("\"island_priority\":\"nearest\",\"anchor_round\":100"),
  sheetOf("\"island_priority\":\"safe\",\"anchor_round\":100"),
  o.capturedDistanceMean[seat], true, 105, IslandMaps, 1200)

# --- amplifier_use -----------------------------------------------------
teeth("amplifier_use -> amplifiers built",
  sheetOf("\"amplifier_use\":\"never\""),
  sheetOf("\"amplifier_use\":\"escort\""),
  o.amplifiersBuilt[seat], true, 200)
teeth("amplifier_use -> shared-array writes",
  sheetOf("\"amplifier_use\":\"never\""),
  sheetOf("\"amplifier_use\":\"escort\""),
  o.arrayWrites[seat], true, 120)

# --- destabilizer_use --------------------------------------------------
teeth("destabilizer_use -> strike-group distance from home",
  sheetOf("\"destabilizer_use\":\"hold\""),
  sheetOf("\"destabilizer_use\":\"siege\""),
  o.strikeDistanceMean[seat], true, 140)
teeth("destabilizer_use -> damage dealt to enemy carriers",
  sheetOf("\"destabilizer_use\":\"hold\""),
  sheetOf("\"destabilizer_use\":\"siege\""),
  o.carrierDamageTaken[1 - seat], true, 115)

# --- retreat_on_launcher_loss -----------------------------------------
teeth("retreat_on_launcher_loss -> anchor healing received",
  sheetOf("\"retreat_on_launcher_loss\":\"never\",\"anchor_round\":150"),
  sheetOf("\"retreat_on_launcher_loss\":\"home\",\"anchor_round\":150"),
  o.anchorHeals[seat], true, 110)

# --- carrier_throw -----------------------------------------------------
teeth("carrier_throw -> resources thrown",
  sheetOf("\"carrier_throw\":0"), sheetOf("\"carrier_throw\":100"),
  o.resourcesThrown[seat], true, 200)
proc bankedShare(o: GameOutcome23, seat: int): int =
  ## Permille of everything this faction's carriers ever carried that
  ## actually reached a headquarters. Zero when nothing was carried.
  let carried = o.resourcesBanked[seat] + o.resourcesThrown[seat]
  if carried == 0: 0 else: o.resourcesBanked[seat] * 1000 div carried

teeth("carrier_throw -> banked share of everything carried",
  sheetOf("\"carrier_throw\":0"), sheetOf("\"carrier_throw\":100"),
  bankedShare(o, seat), false, 90)

finish("test_bc23_knobs")
