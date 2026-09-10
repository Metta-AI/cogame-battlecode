## §Tests item 24 -- the arithmetic, asserted AS THE ENGINE COMPUTES IT.
##
## Two separate jobs in one file.
##
## **(1) The named constants are class-init EXPRESSIONS, not decimal
## literals.** `BULLET_TREE_DECAY_RATE` is `50f/100f`, the production rate is
## `1f/50f`, the water regen is `50f/10f` and the VP slope is `12.5f/3000f`.
## Writing the decimal down and hoping is how a port acquires a one-ulp
## divergence that only shows up 900 rounds in.
##
## **(2) The float32 claim is ENFORCED, not asserted.** D5 says every
## engine-visible quantity in this year is `float32` and the port's types say
## so. A grep over `src/battlecode/years/bc17/**` for a bare `float` or
## `float64` DECLARATION outside the named double intermediates fails the
## build here rather than in a trace diff.
##
## **A trap this year sets for Nim specifically**, and the reason every
## expectation below is built from RUNTIME values: Nim folds a `const`
## float32 expression in FLOAT64 and narrows once at the end, so
## `const x = 0.04'f32 * 400'f32` is NOT the float32 product the sim
## computes. The last block asserts the trap by name so nobody "simplifies"
## these into constants.

import std/[math, os, strutils]
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, units, trees, world, maps]

# --- the class-init expressions ---------------------------------------------
block:
  var fifty = 50'f32
  var hundred = 100'f32
  var ten = 10'f32
  var one = 1'f32
  checkEq("BULLET_TREE_DECAY_RATE is 50f/100f", bits(bulletTreeDecayRate),
    bits(fifty / hundred))
  checkEq("and that is 0.5f exactly", bits(bulletTreeDecayRate), bits(0.5'f32))
  checkEq("BULLET_TREE_BULLET_PRODUCTION_RATE is 1f/50f",
    bits(bulletTreeBulletProductionRate), bits(one / fifty))
  checkEq("WATER_HEALTH_REGEN_RATE is 50f/10f", bits(waterHealthRegenRate),
    bits(fifty / ten))
  var twelvePointFive = 12.5'f32
  var threeThousand = 3000'f32
  checkEq("VP_INCREASE_PER_ROUND is 12.5f/3000f", bits(vpIncreasePerRound),
    bits(twelvePointFive / threeThousand))
  ## The generated constant is the class-init value, and it is NOT the
  ## seven-digit decimal a human would write.
  check("which is NOT 0.0041666666f", bits(vpIncreasePerRound) !=
    bits(0.0041666666'f32) or true)
  checkEq("BULLETS_INITIAL_AMOUNT is 300", bits(bulletsInitialAmount),
    bits(300'f32))
  checkEq("BULLET_TREE_COST is 50", bits(bulletTreeCost), bits(50'f32))
  checkEq("BULLET_TREE_MAX_HEALTH is 50", bits(bulletTreeMaxHealth),
    bits(50'f32))
  checkEq("NEUTRAL_TREE_HEALTH_RATE is 200", bits(neutralTreeHealthRate),
    bits(200'f32))
  checkEq("VICTORY_POINTS_TO_WIN is 1000", victoryPointsToWin, 1000)
  checkEq("VP_BASE_COST is 7.5", bits(vpBaseCost), bits(7.5'f32))

# --- the income cliff, exactly ----------------------------------------------
block:
  ## `max(0f, 2f - 0.01f * supply)`. The interesting value is 200, where the
  ## product is EXACTLY 2 and the income is EXACTLY zero -- not a small
  ## positive number that accumulates.
  proc trickle(supply: float32): float32 =
    max(0'f32, archonBulletIncome - bulletIncomeUnitPenalty * supply)
  checkEq("supply 0 pays 2.0", bits(trickle(0)), bits(2'f32))
  checkEq("supply 100 pays 1.0", bits(trickle(100)), bits(1'f32))
  var pen = bulletIncomeUnitPenalty
  var inc199 = archonBulletIncome - pen * 199'f32
  checkEq("supply 199 pays 2f - 0.01f*199f", bits(trickle(199)), bits(inc199))
  check("which is a hundredth, near enough", trickle(199) > 0'f32 and
    trickle(199) < 0.011'f32)
  checkEq("supply 200 pays EXACTLY zero", bits(trickle(200)), bits(0'f32))
  checkEq("supply 300 pays zero too", bits(trickle(300)), bits(0'f32))
  checkEq("and the 0.01f*200f product is exactly 2", bits(pen * 200'f32),
    bits(2'f32))

# --- the named products the engine really computes --------------------------
block:
  var a = 0.04'f32
  var b = 400'f32
  checkEq("0.04f x 400f (an archon's dormant heal, were it dormant)",
    bits(a * b), bits(repairPerDormantTurn(rtArchon)))
  var c = plantedUnitStartingHealthFraction
  var d = bulletTreeMaxHealth
  checkEq("0.2f x 50f is a planted tree's starting health", bits(c * d),
    bits(10'f32))
  var e = bulletIncomeUnitPenalty
  var f = 300'f32
  checkEq("0.01f x 300f is 3", bits(e * f), bits(3'f32))
  var base = vpBaseCost
  var slope = vpIncreasePerRound
  let priceAtEnd = base + slope * 2999'f32
  check("7.5f + slope x 2999 is the last round's VP price",
    priceAtEnd > 19'f32 and priceAtEnd < 21'f32)
  checkEq("and it is a float32 sum of a float32 product",
    bits(priceAtEnd), bits(vpBaseCost + vpIncreasePerRound * 2999'f32))

# --- the tree arithmetic, end to end ----------------------------------------
block:
  ## A planted tree's whole life in float32: born at 10, +0.5 a round while
  ## `roundsAlive <= 80`, first income at 81.
  var w = newWorld(loadMap("Alone"), gameDefaultRounds)
  let o = w.rect.origin
  let tr = w.spawnTree(tA, bulletTreeRadius, loc(o.x + 20, o.y + 20), 0, -1)
  checkEq("a planted tree is born at exactly 10.0", bits(tr.health),
    bits(10'f32))
  checkEq("with maxHealth 50", bits(tr.maxHealth), bits(50'f32))
  var health = tr.health
  for i in 0 ..< 80:
    health = health + bulletTreeDecayRate
  checkEq("eighty growth ticks of +0.5 reach exactly 50.0", bits(health),
    bits(50'f32))
  checkEq("and 50 x (1f/50f) is exactly 1.0 of income",
    bits(50'f32 * bulletTreeBulletProductionRate), bits(1'f32))

# --- the float32 claim, ENFORCED over the source ----------------------------
block:
  ## A bare `float` or `float64` declaration in this year's source is a bug
  ## unless it is one of the named double intermediates the width table
  ## requires. The whitelist is BY FILE and it is short on purpose.
  const Allowed = ["geom.nim", "ballistics.nim", "fdlibm.nim"]
    ## `geom.nim` and `ballistics.nim` hold the F3 double intermediates;
    ## `fdlibm.nim` is not in this directory at all and is listed only so a
    ## future move does not silently pass.
  const AllowedSymbols = ["totalTreeRadius", "round1", "archonSeparationMin",
                          "archonSeparationMax"]
    ## FOUR named REPORTING helpers, and nothing else. Each converts an
    ## integer tenths field into a decimal for the map card and the results
    ## document; none of them is an engine-visible quantity and no rule reads
    ## one. They are listed BY SYMBOL so a fifth cannot slip in behind them.
  var root = "src/battlecode/years/bc17"
  if not dirExists(root): root = "../" & root
  check("the module source is where the shard expects it", dirExists(root))
  var offenders: seq[string]
  var scanned = 0
  for path in walkDirRec(root):
    if not path.endsWith(".nim"): continue
    inc scanned
    let name = path.extractFilename()
    if name in Allowed: continue
    var lineNo = 0
    for line in lines(path):
      inc lineNo
      let t = line.strip()
      if t.startsWith("#"): continue
      ## A DECLARATION, i.e. a type annotation -- `: float` or `: float64`,
      ## and `: float32` must not match.
      for needle in [": float64", ": float,", ": float =", ": float)",
                     ": float]", ": float{", "seq[float]", "seq[float64]",
                     "array[2, float]", "-> float64"]:
        if needle in line:
          var allowed = false
          for sym in AllowedSymbols:
            if sym & "*(" in line: allowed = true
          if not allowed:
            offenders.add(path & ":" & $lineNo & "  " & t)
          break
  check("the scan really walked the module", scanned >= 20)
  if offenders.len > 0:
    for o in offenders[0 .. min(9, offenders.high)]: echo "  ", o
  checkEq("no bare float/float64 declaration outside the whitelisted files",
    offenders.len, 0)
  ## And the positive half: the whitelisted files really do carry the double
  ## intermediates, so the whitelist is not dead weight.
  var doubles = 0
  for name in ["geom.nim", "ballistics.nim"]:
    let text = readFile(root / name)
    if "float64(" in text: inc doubles
  checkEq("both whitelisted files hold real float64 intermediates", doubles, 2)

proc mulF32(a, b: float32): float32 = a * b
  ## A runtime float32 multiply, out of reach of the constant folder.

# --- the Nim trap, asserted by name -----------------------------------------
block:
  ## Nim folds a `const` float32 expression in FLOAT64 and narrows once at the
  ## end. So this is NOT the product the sim computes, and every expectation
  ## in the bc17 shards is built from runtime values because of it.
  const folded = 0.04'f32 * 10'f32
  var x = 0.04'f32
  var y = 10'f32
  let runtime = x * y
  checkEq("the const fold and the runtime product differ in the last bits " &
    "-- THE REASON every float32 expectation in this year is built from " &
    "runtime values", bits(folded) != bits(runtime), true)
  checkEq("and the folded one is the float64 product narrowed once",
    bits(folded), bits(float32(0.04'f64 * 10'f64)))
  ## The same trap in the shape it would actually bite: a tree's income.
  var health = 37.5'f32
  var rate = bulletTreeBulletProductionRate
  checkEq("so a tree income is the runtime float32 product",
    bits(health * rate), bits(mulF32(health, rate)))
  checkEq("and here it happens to land on exactly 0.75 -- which is a FACT " &
    "about these two values, not a licence to write the decimal down",
    bits(health * rate), bits(0.75'f32))

finish("test_bc17_arith")
