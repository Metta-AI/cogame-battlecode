## bc23's time-bending layer: the multiplier as integer hundredths, the
## ASYMMETRIC stack guards reproduced literally, the whole-map expiry sweep in
## the engine's own order, the destabilisation firing at the end of round
## `cast + 4` and hitting AT MOST ONE ROBOT PER TILE, the boost covering
## `cast .. cast + 9`, and THE FLOAT64 REPRODUCTION TEST including the
## `base 5 x 0.70 -> 3` case an integer formula gets wrong.

import std/[algorithm, json, math, os, strutils]
import harness
import bc23_fixture

# --- the float64 application, over the whole reachable lattice --------------
block:
  ## `Math.round(base * (hundredths / 100.0))` in FLOAT64, exactly as Java
  ## evaluates it — `hundredths/100.0` first, then the multiply, then
  ## `floor(x + 0.5)`.
  ## THE DESIGN NOTE'S NAMED VECTOR IS WRONG AND THE ENGINE IS RIGHT.
  ## §Sim module claims `base = 5, hundredths = 70` gives a float64 product of
  ## 3.4999999999999996 that Java rounds to 3. Measured against Temurin 8:
  ## `5 * (70/100.0)` is EXACTLY 3.5 in float64 (the true product is the tie
  ## between 3.4999999999999996 and 3.5, and ties round to even), so
  ## `Math.round` gives 4. The port reproduces the engine, and
  ## docs/RULES-BC23.md records the correction.
  checkEq("base 5 at 0.70 is 4 in Java, not the note's 3",
    applyMultiplier(5, 70), 4)
  ## The note's POINT stands, and here is the vector that actually shows it:
  ## the integer form disagrees with Java at base 45 and at base 50.
  checkEq("base 45 at 0.70: Java gives 31", applyMultiplier(45, 70), 31)
  checkEq("and an integer (45*70 + 50) div 100 would give 32",
    (45 * 70 + 50) div 100, 32)
  checkEq("base 50 at 1.15: Java gives 57", applyMultiplier(50, 115), 57)
  checkEq("and the integer form would give 58",
    (50 * 115 + 50) div 100, 58)
  checkEq("base 10 at 1.20", applyMultiplier(10, 120), 12)
  checkEq("base 140 at 0.90", applyMultiplier(140, 90), 126)
  checkEq("base 70 at 1.00", applyMultiplier(70, 100), 70)
  checkEq("base 2 at 1.20", applyMultiplier(2, 120), 2)
  checkEq("base 2 at 0.85", applyMultiplier(2, 85), 2)
  ## Every reachable multiplier: 1.00 + cloud 0.20 - 0.10 per boost stack
  ## (0..3) + 0.10 per destabilise stack (0..2) - 0.15 for the anchor.
  var lattice: seq[int]
  for cloud in [0, 1]:
    for boosts in 0 .. MaxBoostStacks:
      for destab in 0 .. MaxDestabilizeStacks:
        for anchor in 0 .. MaxAnchorStacks:
          lattice.add(BaseMultiplier + cloud * CloudHundredths +
            boosts * BoostHundredths + destab * DestabilizeHundredths +
            anchor * AnchorHundredths)
  checkEq("the lattice is every reachable combination", lattice.len, 48)
  ## Sixteen DISTINCT hundredths values are reachable: 55 .. 140 in steps of
  ## five, minus 60 and 135, which no combination produces.
  var seen: seq[int]
  for h in lattice:
    if h notin seen: seen.add(h)
  checkEq("over sixteen distinct multipliers", seen.len, 16)
  for h in lattice:
    for base in [2, 10, 15, 20, 25, 70, 140]:
      let want = int(floor(float64(base) * (float64(h) / 100.0) + 0.5))
      checkEq("lattice " & $base & " x " & $h, applyMultiplier(base, h), want)
    for base in 5 .. 20:
      let want = int(floor(float64(base) * (float64(h) / 100.0) + 0.5))
      checkEq("carrier base " & $base & " x " & $h,
        applyMultiplier(base, h), want)

# --- the cloud is baked in at construction, for BOTH teams -----------------
block:
  var w = bare(clouds = @[loc(10, 10)])
  checkEq("a cloud is +20 for team A",
    w.cooldownMultiplier(loc(10, 10), teamA), 120)
  checkEq("and +20 for team B",
    w.cooldownMultiplier(loc(10, 10), teamB), 120)
  checkEq("a clear tile is 1.00", w.cooldownMultiplier(loc(9, 10), teamA), 100)

# --- boost stacking to three, and the asymmetric guards --------------------
block:
  var f = initTempoField(4)
  for k in 1 .. 5:
    f.addBoost(0, teamA, 10)
  checkEq("five boosts on one tile, but only THREE moved the multiplier",
    f.multiplier(0, teamA), BaseMultiplier + 3 * BoostHundredths)
  checkEq("and the list really holds five", f.boosts[0][0].len, 5)
  ## The expiry sweep's guard is `<=`, evaluated against the size AT THAT
  ## MOMENT, so the first two removals (sizes 5 and 4) adjust nothing and the
  ## last three (sizes 3, 2, 1) each give back 0.10. Over the life of the tile
  ## the two guards balance exactly.
  f.expireBoosts(0, teamA, 9)
  checkEq("every entry expired", f.boosts[0][0].len, 0)
  checkEq("AND THE MULTIPLIER IS BACK TO 1.00 — the guards balance",
    f.multiplier(0, teamA), BaseMultiplier)

block:
  var f = initTempoField(4)
  for k in 1 .. 4:
    f.addDestabilize(0, teamB, 5)
  checkEq("four destabilisations, only TWO moved the multiplier",
    f.multiplier(0, teamB), BaseMultiplier + 2 * DestabilizeHundredths)
  let hits = f.expireDestabilizes(0, teamB, 4)
  checkEq("all four expired at round + 1", hits, 4)
  checkEq("and the multiplier is back", f.multiplier(0, teamB),
    BaseMultiplier)

block:
  var f = initTempoField(4)
  f.addAnchorBoost(0, teamA, 7)
  checkEq("an accelerating anchor is -0.15", f.multiplier(0, teamA),
    BaseMultiplier + AnchorHundredths)
  f.addAnchorBoost(0, teamA, 9)
  checkEq("a second one does NOT stack (MAX_ANCHOR_STACKS = 1)",
    f.multiplier(0, teamA), BaseMultiplier + AnchorHundredths)
  f.removeAnchorBoost(0, teamA, 9)
  checkEq("removal is BY VALUE", f.anchors[0][0].len, 1)
  f.removeAnchorBoost(0, teamA, 7)
  checkEq("and the tile is clean again", f.multiplier(0, teamA),
    BaseMultiplier)

# --- a boost covers rounds cast .. cast + 9 --------------------------------
block:
  var w = bare()
  let b = w.place(teamA, rtBooster, loc(10, 10))
  w.currentRound = 100
  check("the boost is cast", w.doBoost(b))
  checkEq("its expiry round is cast + 10",
    w.tempo.boosts[0][w.idx(loc(10, 10))][0], 110)
  ## The sweep drops `entry <= round + 1`, so the entry survives every round
  ## up to and including 108 and is dropped at the end of 109.
  for round in 100 .. 108:
    w.tempo.expireBoosts(w.idx(loc(10, 10)), teamA, round)
    checkEq("still boosted at round " & $round,
      w.cooldownMultiplier(loc(10, 10), teamA), 90)
  w.tempo.expireBoosts(w.idx(loc(10, 10)), teamA, 109)
  checkEq("and it expires at the end of round 109 — ten rounds inclusive",
    w.cooldownMultiplier(loc(10, 10), teamA), 100)

# --- the destabilisation fires at the end of round cast + 4 ---------------
block:
  var w = bare()
  let d = w.place(teamA, rtDestabilizer, loc(10, 10))
  let victim = w.place(teamB, rtLauncher, loc(11, 10))
  let ally = w.place(teamA, rtCarrier, loc(9, 10))
  w.currentRound = 200
  check("the destabilisation is cast", w.doDestabilize(d, loc(11, 10)))
  checkEq("its expiry round is cast + 5",
    w.tempo.destabilizes[1][w.idx(loc(11, 10))][0], 205)
  var fired = -1
  for round in 200 .. 210:
    w.currentRound = round
    let before = victim.health
    var sides = newSides23(defaultSheets(), 0)
    ## Only the expiry half of the round, so the test is about the sweep.
    for x in 0 ..< w.width:
      for y in 0 ..< w.height:
        let i = w.idx(loc(x, y))
        for t in 0 .. 1:
          w.tempo.expireBoosts(i, Team(t), round)
          let hits = w.tempo.expireDestabilizes(i, Team(t), round)
          for k in 0 ..< hits:
            let r = w.getRobot(loc(x, y))
            if r != nil and ord(r.team) == t:
              w.addHealth(r, -RobotSpecs[rtDestabilizer].damage)
    if victim.health != before and fired < 0: fired = round
    discard sides
  checkEq("THE 50 LANDS AT THE END OF ROUND cast + 4", fired, 204)
  checkEq("for exactly 50", victim.health, 150)
  checkEq("and the ALLY standing inside the patch takes nothing",
    ally.health, 150)

block:
  ## Two destabilisations expiring together hit the same robot TWICE.
  var w = bare()
  let victim = w.place(teamB, rtLauncher, loc(11, 10))
  w.currentRound = 300
  let i = w.idx(loc(11, 10))
  w.tempo.addDestabilize(i, teamB, 305)
  w.tempo.addDestabilize(i, teamB, 305)
  let hits = w.tempo.expireDestabilizes(i, teamB, 304)
  checkEq("both entries expire in the same sweep", hits, 2)
  for k in 0 ..< hits:
    w.addHealth(victim, -RobotSpecs[rtDestabilizer].damage)
  checkEq("so the robot takes 100", victim.health, 100)

# --- the checksum ---------------------------------------------------------
block:
  var w = bare(clouds = @[loc(1, 1)])
  let a = w.tempo.checksum(w.width, w.height)
  var w2 = bare(clouds = @[loc(2, 1)])
  let b = w2.tempo.checksum(w.width, w.height)
  check("one wrong tempo tile changes the checksum", a != b)

# --- TIER B, NATIVELY: the port against the JAR'S OWN TABLE ---------------
block:
  ## `data/bc23/tables.json` is regenerated by `tools/JavaBc23Tables.java`
  ## under the CI Temurin 8 straight out of the released jar's classes and
  ## byte-diffed by the `parity-oracle-bc23` job. THIS block is the other
  ## half: the Nim port asserted against those same bytes, natively, on every
  ## test run — so a rounding regression is caught by the `test` job and not
  ## only by the oracle.
  let path =
    if fileExists("data/bc23/tables.json"): "data/bc23/tables.json"
    else: "../data/bc23/tables.json"
  let doc = parseJson(readFile(path))

  ## The whole RobotType table, ten fields x six types.
  for kind in RobotType:
    let row = doc["robot_types"][$kind]
    let spec = RobotSpecs[kind]
    checkEq($kind & " buildCostAdamantium", spec.buildCostAdamantium,
      row[0].getInt())
    checkEq($kind & " buildCostMana", spec.buildCostMana, row[1].getInt())
    checkEq($kind & " buildCostElixir", spec.buildCostElixir, row[2].getInt())
    checkEq($kind & " actionCooldown", spec.actionCooldown, row[3].getInt())
    checkEq($kind & " movementCooldown", spec.movementCooldown,
      row[4].getInt())
    checkEq($kind & " health", spec.health, row[5].getInt())
    checkEq($kind & " damage", spec.damage, row[6].getInt())
    checkEq($kind & " actionRadiusSquared", spec.actionRadiusSquared,
      row[7].getInt())
    checkEq($kind & " visionRadiusSquared", spec.visionRadiusSquared,
      row[8].getInt())
    checkEq($kind & " bytecodeLimit", spec.bytecodeLimit, row[9].getInt())

  ## The whole Anchor table, eight fields x two.
  for kind in [anStandard, anAccelerating]:
    let row = doc["anchors"][$kind]
    let spec = AnchorSpecs[kind]
    checkEq($kind & " totalHealth", spec.totalHealth, row[0].getInt())
    checkEq($kind & " unitsAffected", spec.unitsAffected, row[1].getInt())
    checkEq($kind & " accelerationFactor", spec.accelerationFactor,
      float32(row[2].getFloat()))
    checkEq($kind & " healingFrequency", spec.healingFrequency,
      row[3].getInt())
    checkEq($kind & " healingAmount", spec.healingAmount, row[4].getInt())
    checkEq($kind & " manaCost", spec.manaCost, row[5].getInt())
    checkEq($kind & " adamantiumCost", spec.adamantiumCost, row[6].getInt())
    checkEq($kind & " elixirCost", spec.elixirCost, row[7].getInt())

  ## The carrier's two weight tables, every reachable weight 0..40.
  checkEq("the move-cooldown table has 41 entries",
    doc["carrier_move_cooldown"].len, 41)
  for w in 0 .. 40:
    checkEq("carrier move cd at " & $w, carrierMoveCooldown(w),
      doc["carrier_move_cooldown"][w].getInt())
    checkEq("carrier throw damage at " & $w, carrierThrowDamage(w),
      doc["carrier_throw_damage"][w].getInt())

  ## THE REACHABLE MULTIPLIERS, as the ENGINE'S OWN quantised accumulation
  ## produces them — sixteen values, 55 .. 140.
  var jarHundredths: seq[int]
  for v in doc["reachable_multipliers"]: jarHundredths.add(v.getInt())
  checkEq("sixteen reachable multipliers", jarHundredths.len, 16)
  var mine: seq[int]
  for cloud in [0, 1]:
    for boosts in 0 .. MaxBoostStacks:
      for destab in 0 .. MaxDestabilizeStacks:
        for anchor in 0 .. MaxAnchorStacks:
          let h = BaseMultiplier + cloud * CloudHundredths +
            boosts * BoostHundredths + destab * DestabilizeHundredths +
            anchor * AnchorHundredths
          if h notin mine: mine.add(h)
  mine.sort()
  checkEq("THE PORT'S INTEGER-HUNDREDTHS LADDER IS THE ENGINE'S OWN " &
    "QUANTISED ACCUMULATION, value for value", mine, jarHundredths)

  ## THE ENTIRE COOLDOWN LATTICE, as the JVM itself computed it.
  var cells = 0
  for baseKey, row in doc["cooldown_lattice"]:
    let base = parseInt(baseKey)
    for i in 0 ..< row.len:
      checkEq("lattice base " & baseKey & " x " & $jarHundredths[i],
        applyMultiplier(base, jarHundredths[i]), row[i].getInt())
      cells += 1
  check("the lattice is the whole domain, not a sample", cells >= 300)

  ## The float32 conquest threshold, every island count 4..35.
  for totalKey, need in doc["islands_to_win"]:
    checkEq("islandsToWin(" & totalKey & ")", islandsToWin(parseInt(totalKey)),
      need.getInt())

  ## The island occupancy formula, every (a, b) pair up to area 20.
  for areaKey, row in doc["occupancy_diff"]:
    let area = parseInt(areaKey)
    var i = 0
    for own in 0 .. area:
      for enemy in 0 .. area - own:
        checkEq("occupancy " & $own & "/" & $enemy & "/" & areaKey,
          occupancyDiff(own, enemy, area), row[i].getInt())
        i += 1
    checkEq("area " & areaKey & " covered every pair", i, row.len)

finish("test_bc23_tempo")
