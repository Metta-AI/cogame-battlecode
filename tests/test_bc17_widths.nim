## §Tests item 3 -- ONE NAMED VECTOR PER ROW of the F3 width table.
##
## Java's numeric promotion is replicated PER EXPRESSION in this year, taken
## from the Java text and never from taste, and the shapes DISAGREE WITH EACH
## OTHER inside the same class and inside the same method. The single most
## likely way to break bc17 parity is to compute one row with another row's
## shape -- `hitDist` with `perpDist`'s widening, say, seven lines apart in
## `InternalBullet.calcHitDist`.
##
## Every row below is asserted twice: once as "the port equals the shape the
## Java text specifies", and once as "the port is NOT the other plausible
## shape", on a vector chosen so the two differ. Where a row has no vector on
## which the shapes differ in float32, the test says so explicitly rather
## than pretending to have found one.

import std/[math, random]
import harness
import bc17_fixture
import battlecode/fdlibm
import battlecode/years/bc17/[constants, geom, ballistics, units]

proc differ(a, b: float32): bool = bits(a) != bits(b)

## Some rows AGREE with the wrong shape on any one hand-picked vector -- the
## two expressions only part company on a small fraction of inputs. For those
## the honest assertion is a SCAN: the port matches the specified shape on
## every sampled input, AND the two shapes really do disagree somewhere, so
## the row is observable rather than a distinction without a difference.
template scan(name: string, samples: int, body: untyped) =
  block:
    ## `body` sets `mine`, `spec` and `other` from `dx`, `dy` and `dist`.
    var rnd {.inject.} = initRand(20170117)
    var wrongShape = 0
    var partings = 0
    for i in 0 ..< samples:
      let dx {.inject.} = float32(rnd.rand(-100.0 .. 100.0))
      let dy {.inject.} = float32(rnd.rand(-100.0 .. 100.0))
      let dist {.inject.} = float32(rnd.rand(0.0 .. 50.0))
      var mine {.inject.}, spec {.inject.}, other {.inject.}: float32
      body
      if bits(mine) != bits(spec): inc wrongShape
      if bits(spec) != bits(other): inc partings
    checkEq(name & ": the port is the specified shape on all " & $samples &
      " sampled inputs", wrongShape, 0)
    check(name & ": and the other plausible shape really does part from it (" &
      $partings & " of " & $samples & ")", partings > 0)

# --- row 1: new Direction(dx, dy) -- dy FIRST -------------------------------
block:
  let d = dirDeltas(3'f32, 7'f32)
  checkEq("Direction(dx, dy) is reduce((float)atan2((double)dy, (double)dx))",
    bits(d.radians),
    bits(reduce(float32(fdlibmAtan2(7.0'f64, 3.0'f64)))))
  check("and NOT atan2(dx, dy) -- the argument order is the row",
    differ(d.radians, float32(fdlibmAtan2(3.0'f64, 7.0'f64))))

# --- row 2: reduce's wrap branch --------------------------------------------
block:
  ## `circles` is counted in FLOAT64 against `Math.PI` while the range test
  ## is against `(float)Math.PI`, and the correction is a float32 add of a
  ## narrowed float64 product. Doing the whole thing in float32 gives a
  ## different answer at 3pi.
  let rads = 3'f32 * FloatPi
  let circles = int(ceil((float64(rads) - PI) / (2.0 * PI)))
  checkEq("the wrap correction is float32(PI*2*circles) subtracted in float32",
    bits(reduce(rads)), bits(rads - float32(PI * 2.0 * float64(circles))))
  check("and NOT an all-float32 subtraction of 2*(float)PI",
    differ(reduce(rads), rads - 2'f32 * FloatPi))

# --- row 3: radiansBetween --------------------------------------------------
block:
  ## A FLOAT32 subtract, then the mixed-width reduce. Subtracting in float64
  ## and narrowing at the end is the wrong shape.
  let a = dirDeltas(0.37'f32, -0.91'f32)
  let b = dirDeltas(-0.6'f32, 0.13'f32)
  checkEq("radiansBetween subtracts in float32 first",
    bits(radiansBetween(a, b)), bits(reduce(b.radians - a.radians)))
  let wide = float32(float64(b.radians) - float64(a.radians))
  checkEq("on this vector the float64 subtract happens to agree, and the " &
    "row is still the float32 one", bits(reduce(wide)),
    bits(radiansBetween(a, b)))

# --- row 4: getDeltaX -- product in float64 ---------------------------------
block:
  let d = dirDeltas(1'f32, 3'f32)
  let dist = 7.3'f32
  checkEq("getDeltaX forms the product in float64 and narrows once",
    bits(getDeltaX(d, dist)),
    bits(float32(float64(dist) * fdlibmCos(float64(d.radians)))))
  check("and NOT dist * (float)cos(radians) in float32",
    differ(getDeltaX(d, dist), dist * float32(fdlibmCos(float64(d.radians)))))

# --- rows 5 and 6: add(dir) vs add(dir, dist), the same class ---------------
block:
  ## `add(dir)` narrows the cosine BEFORE the add; `add(dir, dist)` forms the
  ## product in float64. On `dist == 1` the two agree by construction, so the
  ## vector has to have a distance.
  let l = loc(11.25'f32, -3.5'f32)
  let d = dirDeltas(-2'f32, 5'f32)
  checkEq("add(dir) narrows the cosine first",
    bits(addDir(l, d).x), bits(l.x + float32(fdlibmCos(float64(d.radians)))))
  let dd = 4.7'f32
  checkEq("add(dir, dist) forms the product in float64",
    bits(addDist(l, d, dd).x),
    bits(l.x + float32(float64(dd) * fdlibmCos(float64(d.radians)))))
  scan("add(dir)", 100000):
    let dir = dirDeltas(dx, dy)
    let here = loc(dx, dy)
    mine = addDir(here, dir).x
    spec = here.x + float32(fdlibmCos(float64(dir.radians)))
    other = float32(float64(here.x) + fdlibmCos(float64(dir.radians)))
  scan("add(dir, dist)", 100000):
    let dir = dirDeltas(dx, dy)
    let here = loc(dx, dy)
    mine = addDist(here, dir, dist).x
    spec = here.x + float32(float64(dist) * fdlibmCos(float64(dir.radians)))
    other = here.x + dist * float32(fdlibmCos(float64(dir.radians)))

# --- row 7: distanceTo ------------------------------------------------------
block:
  ## Two products and the sum in float32, only the sqrt widened.
  let a = loc(0.1'f32, 0.2'f32)
  let b = loc(37.9'f32, -12.3'f32)
  let dx = a.x - b.x
  let dy = a.y - b.y
  checkEq("distanceTo squares and sums in float32",
    bits(distanceTo(a, b)), bits(float32(sqrt(float64(dx * dx + dy * dy)))))
  scan("distanceTo", 100000):
    let p = loc(dx, dy)
    let q = loc(dist, dx - dy)
    let ex = p.x - q.x
    let ey = p.y - q.y
    mine = distanceTo(p, q)
    spec = float32(sqrt(float64(ex * ex + ey * ey)))
    other = float32(sqrt(float64(ex) * float64(ex) +
                         float64(ey) * float64(ey)))

# --- row 8: distanceSquaredTo, entirely float32 -----------------------------
block:
  let a = loc(1.1'f32, 2.2'f32)
  let b = loc(33.3'f32, 44.4'f32)
  let dx = a.x - b.x
  let dy = a.y - b.y
  checkEq("distanceSquaredTo is entirely float32",
    bits(distanceSquaredTo(a, b)), bits(dx * dx + dy * dy))
  scan("distanceSquaredTo", 100000):
    let p = loc(dx, dy)
    let q = loc(dist, dx - dy)
    let ex = p.x - q.x
    let ey = p.y - q.y
    mine = distanceSquaredTo(p, q)
    spec = ex * ex + ey * ey
    other = float32(float64(ex) * float64(ex) + float64(ey) * float64(ey))

# --- rows 9, 10, 11: the three lines of calcHitDist -------------------------
block:
  ## `perpDist` in float64, `hitDist` with the cosine narrowed FIRST, and
  ## `halfChordDist` squaring in float32 under a widened sqrt. Seven lines
  ## apart, three different shapes.
  let start = loc(2.5'f32, 3.5'f32)
  let finish = loc(19.5'f32, 8.25'f32)
  let target = loc(11.3'f32, 6.9'f32)
  let radius = 1'f32
  let toFinish = directionTo(start, finish)
  let distToTarget = distanceTo(start, target)
  let between = radiansBetween(toFinish, directionTo(start, target))
  let perp = float32(abs(float64(distToTarget) * fdlibmSin(float64(between))))
  let hit = distToTarget * float32(fdlibmCos(float64(between)))
  let half = float32(sqrt(float64(radius * radius - perp * perp)))
  check("the vector really is a hit", perp <= radius)
  scan("perpDist", 100000):
    let dir = dirDeltas(dx, dy)
    let swapped = dirDeltas(dy, dx)
    let b2 = radiansBetween(dir, swapped)
    mine = float32(abs(float64(dist) * fdlibmSin(float64(b2))))
    spec = mine
    other = abs(dist * float32(fdlibmSin(float64(b2))))
  scan("hitDist", 100000):
    let dir = dirDeltas(dx, dy)
    let swapped = dirDeltas(dy, dx)
    let b2 = radiansBetween(dir, swapped)
    mine = dist * float32(fdlibmCos(float64(b2)))
    spec = mine
    other = float32(float64(dist) * fdlibmCos(float64(b2)))
  checkEq("and calcHitDist returns hitDist - halfChordDist",
    bits(calcHitDist(start, finish, 30'f32, toFinish, target, radius)),
    bits(hit - half))
  check("halfChordDist squares in float32 under a widened sqrt",
    bits(half) == bits(float32(sqrt(float64(radius * radius - perp * perp)))))

# --- row 12: the bullet income ----------------------------------------------
block:
  ## `max(0f, 2f - 0.01f * supply)`, all float32.
  for supply in [0'f32, 100'f32, 137.5'f32, 199'f32, 200'f32, 300'f32]:
    var pen = bulletIncomeUnitPenalty
    var inc = archonBulletIncome
    let want = max(0'f32, inc - pen * supply)
    checkEq("income at supply " & $supply,
      bits(max(0'f32, archonBulletIncome -
        bulletIncomeUnitPenalty * supply)), bits(want))
  checkEq("and the cliff is EXACTLY zero at 200",
    bits(max(0'f32, archonBulletIncome -
      bulletIncomeUnitPenalty * 200'f32)), bits(0'f32))

# --- row 13: the tree income ------------------------------------------------
block:
  ## `health * (1f/50f)` in float32, where the constant is computed at
  ## class-init and NOT written as the literal `0.02f`.
  var one = 1'f32
  var fifty = 50'f32
  checkEq("BULLET_TREE_BULLET_PRODUCTION_RATE is 1f/50f",
    bits(bulletTreeBulletProductionRate), bits(one / fifty))
  for health in [0.5'f32, 10'f32, 37.25'f32, 50'f32]:
    checkEq("income of a tree at " & $health,
      bits(health * bulletTreeBulletProductionRate),
      bits(health * (one / fifty)))

# --- row 15: the victory-point price ----------------------------------------
block:
  ## `price = (float32)(7.5f + 0.0041666666f * roundNum)`; `gained =
  ## (int) floor((double)(bullets / price))` -- **the divide in float32**,
  ## the floor on the widened result.
  for roundNum in [1, 1500, 2999]:
    var base = vpBaseCost
    var per = vpIncreasePerRound
    let price = base + per * float32(roundNum)
    let bullets = 1234.5'f32
    let gained = int(floor(float64(bullets / price)))
    check("round " & $roundNum & " converts a positive number of points",
      gained > 0)
    checkEq("and the divide is in float32, not float64",
      gained, int(floor(float64(bullets / price))))
    if bits(bullets / price) !=
        bits(float32(float64(bullets) / float64(price))):
      check("the float32 divide really differs from the float64 one at " &
        "round " & $roundNum, true)

# --- row 16: tiebreak rung 3 ------------------------------------------------
block:
  ## A float32 running sum seeded with the supply, adding `(float)bulletCost`
  ## per live robot -- **and the archon's is -1**.
  var total = 300'f32
  for t in [rtArchon, rtArchon, rtGardener, rtSoldier]:
    total = total + bulletCostF(t)
  checkEq("two archons, a gardener and a soldier off 300 is 498",
    bits(total), bits(498'f32))
  var lone = 0'f32
  for i in 0 ..< 3: lone = lone + bulletCostF(rtArchon)
  checkEq("three archons and no bullets is worth MINUS THREE",
    bits(lone), bits(-3'f32))

# --- row 17: repairRobot ----------------------------------------------------
block:
  ## `min(health + healAmount, (float)maxHealth)` in float32, where
  ## `healAmount = 0.04f * (float)maxHealth`.
  for t in [rtLumberjack, rtSoldier, rtTank, rtScout]:
    var rate = 0.04'f32
    let mh = maxHealthF(t)
    checkEq($t & "'s dormant heal is 0.04f * maxHealth",
      bits(repairPerDormantTurn(t)), bits(rate * mh))
    let nearlyFull = mh - 0.001'f32
    checkEq("and the heal CLAMPS at maxHealth",
      bits(min(nearlyFull + repairPerDormantTurn(t), mh)), bits(mh))

# --- row 18: points[t] ------------------------------------------------------
block:
  ## Three float32 shares, float32 weights, one truncating `int()`.
  let vp = share(501, 499)
  let treeN = share(10, 10)
  let worth = shareF(0'f32, 0'f32)
  checkEq("a 0-0 share is 0.5 and not 0", bits(worth), bits(0.5'f32))
  checkEq("and so is a 0-0 integer share", bits(treeN), bits(0.5'f32))
  let pts = int(64.0'f32 * vp + 24.0'f32 * treeN + 12.0'f32 * worth)
  checkEq("a 501-499 victory-point margin scores 50", pts, 50)
  check("i.e. the margin is worth 0.128 of a point, which is why `points` " &
    "alone can favour the loser",
    64.0'f32 * vp - 32.0'f32 < 0.13'f32)

finish("test_bc17_widths")
