## The bc19 six-row unit table and every derived predicate, against the
## committed arithmetic tables.
##
## The table itself is GENERATED from the pinned engine's own
## `coldbrew/specs.json` (`tools/gen_year_constants.py --year bc19`), so this
## shard checks the DERIVED reading of it — the guards `coldbrew/game.js`
## actually evaluates, including the three `null`/scalar coercions that are
## REAL RULES (D6) and the twelve `signalCost` values measured on the real
## engine in phase 20.

import std/os
import harness
import battlecode/years/bc19/units

block:
  ## The six rows, in the engine's own ordinal order. The ordinal is
  ## load-bearing: it is `build_unit` on the wire, the `SPECS.UNITS` index and
  ## the sprite-atlas index.
  checkEq("CASTLE is 0", ord(ukCastle), 0)
  checkEq("CHURCH is 1", ord(ukChurch), 1)
  checkEq("PILGRIM is 2", ord(ukPilgrim), 2)
  checkEq("CRUSADER is 3", ord(ukCrusader), 3)
  checkEq("PROPHET is 4", ord(ukProphet), 4)
  checkEq("PREACHER is 5", ord(ukPreacher), 5)
  for u in UnitKind:
    checkEq("the name round-trips for " & unitName(u), parseUnitKind(unitName(u)), u)

block:
  ## Build costs, health, capacities, speeds, fuel per r2 and vision.
  checkEq("a CASTLE cannot be built", buildKarboniteOf(ukCastle), 0)
  checkEq("a CHURCH is 50 karbonite", buildKarboniteOf(ukChurch), 50)
  checkEq("and 200 fuel", buildFuelOf(ukChurch), 200)
  checkEq("a PILGRIM is 10/50", buildKarboniteOf(ukPilgrim) * 1000 +
    buildFuelOf(ukPilgrim), 10050)
  checkEq("a CRUSADER is 15/50", buildKarboniteOf(ukCrusader) * 1000 +
    buildFuelOf(ukCrusader), 15050)
  checkEq("a PROPHET is 25/50", buildKarboniteOf(ukProphet) * 1000 +
    buildFuelOf(ukProphet), 25050)
  checkEq("a PREACHER is 30/50", buildKarboniteOf(ukPreacher) * 1000 +
    buildFuelOf(ukPreacher), 30050)
  checkEq("a CASTLE has 200 HP", startingHpOf(ukCastle), 200)
  checkEq("a CHURCH has 100", startingHpOf(ukChurch), 100)
  checkEq("a PILGRIM has 10", startingHpOf(ukPilgrim), 10)
  checkEq("a CRUSADER has 40", startingHpOf(ukCrusader), 40)
  checkEq("a PROPHET has 20", startingHpOf(ukProphet), 20)
  checkEq("a PREACHER has 60", startingHpOf(ukPreacher), 60)
  checkEq("THE CRUSADER IS THE ONLY FAST UNIT: speed r2 9",
    speedOf(ukCrusader), 9)
  for u in [ukPilgrim, ukProphet, ukPreacher]:
    checkEq("everything else that moves moves at r2 4", speedOf(u), 4)
  for u in [ukCastle, ukChurch]:
    checkEq("a structure has SPEED 0 and therefore cannot move",
      speedOf(u), 0)
    check("and `canMove` says so", not canMove(u))
  checkEq("a PREACHER pays 3 fuel per r2 -- the most in the game",
    fuelPerMoveOf(ukPreacher), 3)
  checkEq("a PROPHET pays 2", fuelPerMoveOf(ukProphet), 2)
  checkEq("a PILGRIM pays 1", fuelPerMoveOf(ukPilgrim), 1)
  checkEq("a CRUSADER pays 1", fuelPerMoveOf(ukCrusader), 1)
  checkEq("a PILGRIM carries 20 karbonite", karboniteCapacityOf(ukPilgrim), 20)
  checkEq("and 100 fuel", fuelCapacityOf(ukPilgrim), 100)
  ## D6.3: `Math.min(n, null) === 0`.
  for u in [ukCastle, ukChurch]:
    checkEq("a structure's karbonite capacity coerces to 0 (D6.3)",
      karboniteCapacityOf(u), 0)
    checkEq("and its fuel capacity too", fuelCapacityOf(u), 0)
  checkEq("THE PREACHER HAS THE SMALLEST EYES IN THE GAME: vision r2 16",
    visionRadiusOf(ukPreacher), 16)
  checkEq("a CRUSADER sees r2 49", visionRadiusOf(ukCrusader), 49)
  checkEq("a PROPHET sees r2 64", visionRadiusOf(ukProphet), 64)
  for u in [ukCastle, ukChurch, ukPilgrim]:
    checkEq("a castle, a church and a pilgrim see r2 100",
      visionRadiusOf(u), 100)
  checkEq("the bounded scan box for r2 100 is 10", visionBoxOf(ukCastle), 10)
  checkEq("for r2 64 it is 8", visionBoxOf(ukProphet), 8)
  checkEq("for r2 49 it is 7", visionBoxOf(ukCrusader), 7)
  checkEq("for r2 16 it is 4", visionBoxOf(ukPreacher), 4)
  for u in UnitKind:
    let box = visionBoxOf(u)
    check("and the box never clips a visible square for " & unitName(u),
      (box + 1) * (box + 1) > visionRadiusOf(u))

block:
  ## THE PROPHET'S r2 16 MINIMUM -- the most confusing rule in this year.
  check("a PROPHET is BLIND at r2 15", not attackRangeOk(ukProphet, 15))
  check("and accepted at exactly 16", attackRangeOk(ukProphet, 16))
  check("and accepted at 64", attackRangeOk(ukProphet, 64))
  check("and refused at 65", not attackRangeOk(ukProphet, 65))
  check("a CRUSADER reaches 1", attackRangeOk(ukCrusader, 1))
  check("and 16", attackRangeOk(ukCrusader, 16))
  check("and not 17", not attackRangeOk(ukCrusader, 17))
  check("a CASTLE reaches 64", attackRangeOk(ukCastle, 64))
  check("and not 65", not attackRangeOk(ukCastle, 65))
  check("a PREACHER reaches 16", attackRangeOk(ukPreacher, 16))
  check("and not 17", not attackRangeOk(ukPreacher, 17))
  ## D6.1: the CHURCH's ATTACK_RADIUS is the SCALAR 0, so `r > radius[1]` and
  ## `r < radius[0]` are both comparisons against `undefined` and both are
  ## false -- a CHURCH may legally attack ANY on-board square.
  checkEq("the CHURCH's ATTACK_RADIUS really is the scalar 0 in the JSON",
    Units[ukChurch].attackRadius, arScalarZero)
  for r2 in [0, 1, 16, 64, 100, 4000]:
    check("D6.1: a CHURCH attack is IN RANGE at r2 " & $r2,
      attackRangeOk(ukChurch, r2))
  checkEq("for 0 damage", attackDamageOf(ukChurch), 0)
  checkEq("and 0 fuel", attackFuelOf(ukChurch), 0)
  check("and it does NOT throw", not attackThrows(ukChurch))
  ## D6.2: the PILGRIM's is `null`, so `null[1]` throws a TypeError that
  ## `enactTurn` swallows -- a pilgrim attack is a VALIDATION FAILURE.
  checkEq("the PILGRIM's ATTACK_RADIUS really is null in the JSON",
    Units[ukPilgrim].attackRadius, arNull)
  check("D6.2: a PILGRIM attack THROWS", attackThrows(ukPilgrim))
  for u in [ukCastle, ukCrusader, ukProphet, ukPreacher]:
    check("and no other unit does: " & unitName(u), not attackThrows(u))

block:
  ## The damage and the blast.
  checkEq("a PREACHER hits for 20", attackDamageOf(ukPreacher), 20)
  checkEq("over DAMAGE_SPREAD 3 -- NINE SQUARES",
    damageSpreadOf(ukPreacher), 3)
  var nine = 0
  for dy in -2 .. 2:
    for dx in -2 .. 2:
      if dx * dx + dy * dy <= damageSpreadOf(ukPreacher): inc nine
  checkEq("and `rad <= 3` really is exactly nine squares", nine, 9)
  for u in [ukCastle, ukCrusader, ukProphet]:
    checkEq("every other attacker hits one square only: " & unitName(u),
      damageSpreadOf(u), 0)
    checkEq("for 10 damage", attackDamageOf(u), 10)
  checkEq("a PROPHET's shot costs 25 fuel -- the most", attackFuelOf(ukProphet), 25)
  checkEq("a PREACHER's costs 15", attackFuelOf(ukPreacher), 15)
  checkEq("a CASTLE's and a CRUSADER's cost 10",
    attackFuelOf(ukCastle) * 100 + attackFuelOf(ukCrusader), 1010)

block:
  ## The build predicates, as the engine's own guards express them.
  for u in [ukPilgrim, ukCastle, ukChurch]:
    check("a " & unitName(u) & " can build", canBuildAtAll(u))
  for u in [ukCrusader, ukProphet, ukPreacher]:
    check("a " & unitName(u) & " cannot", not canBuildAtAll(u))
  check("A PILGRIM MAY BUILD ONLY A CHURCH",
    buildPairLegal(ukPilgrim, ukChurch))
  for u in [ukPilgrim, ukCrusader, ukProphet, ukPreacher]:
    check("and never a " & unitName(u), not buildPairLegal(ukPilgrim, u))
  check("A NON-PILGRIM MAY NEVER BUILD A CHURCH",
    not buildPairLegal(ukCastle, ukChurch))
  for u in [ukPilgrim, ukCrusader, ukProphet, ukPreacher]:
    check("but a CASTLE may build a " & unitName(u),
      buildPairLegal(ukCastle, u))
    check("and so may a CHURCH", buildPairLegal(ukChurch, u))
  for b in [ukPilgrim, ukCastle, ukChurch]:
    check("NOBODY MAY EVER BUILD A CASTLE (builder " & unitName(b) & ")",
      not buildPairLegal(b, ukCastle))
  check("only a PILGRIM can mine", canMine(ukPilgrim))
  for u in [ukCastle, ukChurch, ukCrusader, ukProphet, ukPreacher]:
    check("and nothing else does: " & unitName(u), not canMine(u))
  check("only a CASTLE can trade", canTrade(ukCastle))
  for u in [ukChurch, ukPilgrim, ukCrusader, ukProphet, ukPreacher]:
    check("and nothing else does: " & unitName(u), not canTrade(u))

block:
  ## `signalCost(r2)` -- the twelve values MEASURED ON THE REAL ENGINE in
  ## phase 20, and the whole finite domain's bounds.
  checkEq("the maximum legal signal radius is 2*(64-1)^2",
    MaxSignalRadius, 7938)
  const want = [(0, 0), (1, 1), (2, 2), (3, 2), (4, 2), (5, 3), (9, 3),
                (10, 4), (16, 4), (64, 8), (100, 10), (7938, 90)]
  for pair in want:
    checkEq("signalCost(" & $pair[0] & ")", signalCost(pair[0]), pair[1])
  ## And the whole domain is monotone and never more than one above the
  ## exact square root, which is what `ceil(sqrt(.))` means.
  var prev = 0
  for r2 in 0 .. MaxSignalRadius:
    let c = signalCost(r2)
    check("signalCost is monotone at " & $r2, c >= prev)
    check("and c*c >= r2 at " & $r2, c * c >= r2)
    check("and (c-1)*(c-1) < r2 at " & $r2, c == 0 or (c - 1) * (c - 1) < r2)
    prev = c

block:
  ## The V1 clock constants, and THE THEOREM: the per-turn charge is the
  ## EXACT CONSTANT equal to the refill, so `chessOps` is invariant.
  checkEq("OpsPerMs", DecisionOpsPerMs, 20)
  checkEq("ChessInitialOps = CHESS_INITIAL * 20", ChessInitialOps, 2000)
  checkEq("ChessExtraOps = CHESS_EXTRA * 20", ChessExtraOps, 400)
  checkEq("TurnMaxOps = TURN_MAX_TIME * 20", TurnMaxOps, 4000)
  checkEq("AND TurnChargeOps IS EXACTLY ChessExtraOps -- the whole of V1",
    TurnChargeOps, ChessExtraOps)

block:
  ## The committed table really is on disk and really is the one the sim
  ## reads. (The REGENERATION byte-diff needs Node and lives in
  ## `parity-oracle-bc19`, not here.)
  check("data/bc19/tables.json is committed",
    fileExists(dataRoot() / "bc19" / "tables.json"))

finish("test_bc19_units")
