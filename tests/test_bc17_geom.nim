## §Tests item 2 -- `MapLocation` and `Direction`.
##
## Every assertion here is on RAW IEEE-754 BITS where a float is compared,
## because a float32 needs nine significant digits to round-trip and a
## formatter mismatch would masquerade as a divergence (docs/RULES-BC17.md
## F3). The named vectors that came off the JVM live in
## `data/bc17/fdlibm_vectors.json` and are checked by `test_bc17_fdlibm.nim`;
## this shard pins the BEHAVIOUR the engine's own code depends on.

import std/math
import harness
import bc17_fixture
import battlecode/years/bc17/[constants, geom]

# --- the eight cardinals, and (0,0) -----------------------------------------
block:
  ## `new Direction(dx, dy)` takes `dy` FIRST into atan2.
  checkEq("east is 0", dirDeltas(1, 0).radians, 0'f32)
  checkEq("north is +pi/2", dirDeltas(0, 1).radians, float32(PI / 2.0))
  checkEq("west is +pi (reduce keeps the closed end)",
    dirDeltas(-1, 0).radians, FloatPi)
  checkEq("south is -pi/2", dirDeltas(0, -1).radians, float32(-PI / 2.0))
  checkEq("north-east is +pi/4", dirDeltas(1, 1).radians,
    float32(PI / 4.0))
  checkEq("north-west is +3pi/4", dirDeltas(-1, 1).radians,
    float32(3.0 * PI / 4.0))
  checkEq("south-west is -3pi/4", dirDeltas(-1, -1).radians,
    float32(-3.0 * PI / 4.0))
  checkEq("south-east is -pi/4", dirDeltas(1, -1).radians,
    float32(-PI / 4.0))
  ## `Direction.java:83-85`: a zero vector becomes NORTH, not east and not a
  ## throw.
  checkEq("(0,0) becomes NORTH", dirDeltas(0, 0).radians,
    dirDeltas(0, 1).radians)
  checkEq("and not east", dirDeltas(0, 0).radians != 0'f32, true)

# --- reduce -----------------------------------------------------------------
block:
  ## The comparison is `<= -(float)PI` and `> (float)PI`, so +pi survives and
  ## -pi does not.
  checkEq("+(float)pi is INSIDE the range", reduce(FloatPi), FloatPi)
  checkEq("-(float)pi is wrapped to +(float)pi", reduce(-FloatPi), FloatPi)
  let justUnder = cast[float32](cast[uint32](FloatPi) - 1'u32)
  checkEq("one ulp below +pi passes through", reduce(justUnder), justUnder)
  let justOver = cast[float32](cast[uint32](FloatPi) + 1'u32)
  check("one ulp above +pi is wrapped", reduce(justOver) != justOver)
  check("and lands near -pi", reduce(justOver) < 0'f32)
  ## The `circles` correction, computed in float64 and narrowed once.
  let three = 3'f32 * FloatPi
  let got = reduce(three)
  check("reduce(3pi) is negative", got < 0'f32)
  ## **NOT EXACTLY RANGE-PRESERVING.** `circles` is counted against
  ## `Math.PI` while the range test is against `(float)Math.PI`, so the
  ## answer is ONE ULP BELOW -(float)pi -- i.e. `reduce` can return a value
  ## its own guard would have rejected. The port reproduces that rather than
  ## "fixing" it.
  check("reduce(3pi) lands one ulp OUTSIDE the range reduce enforces",
    got <= -FloatPi)
  checkEq("and it is exactly one ulp below -(float)pi", cast[uint32](got),
    cast[uint32](-FloatPi) + 1'u32)
  check("reducing that value again lands strictly inside",
    reduce(got) > -FloatPi and reduce(got) <= FloatPi)
  checkEq("by the same float32-narrowed correction",
    reduce(got), got + float32(PI * 2.0))

# --- the triad and pentad angles --------------------------------------------
block:
  ## `rotateLeftDegrees(i * 20)` and `(i * 15)` are how a triad and a pentad
  ## spread become radians, through `(float) Math.toRadians`.
  let east = dirRads(0)
  for (deg, hexL, hexR) in [(20'f32, 0x3eb2b8c2'u32, 0xbeb2b8c2'u32),
                            (15'f32, 0x3e860a92'u32, 0xbe860a92'u32),
                            (40'f32, 0x3f32b8c2'u32, 0xbf32b8c2'u32),
                            (30'f32, 0x3f060a92'u32, 0xbf060a92'u32)]:
    checkEq("rotateLeftDegrees(" & $int(deg) & ") off east",
      bits(east.rotateLeftDegrees(deg).radians), hexL)
    checkEq("rotateRightDegrees(" & $int(deg) & ") off east",
      bits(east.rotateRightDegrees(deg).radians), hexR)
  checkEq("rotateRight is rotateLeft of the NEGATED float32",
    east.rotateRightDegrees(20).radians,
    east.rotateLeftRads(-toRadians32(20'f32)).radians)
  checkEq("opposite is rotateLeftRads((float)pi)", dirRads(0).opposite.radians,
    FloatPi)
  checkEq("and applying it twice is the identity on east",
    dirRads(0).opposite.opposite.radians, 0'f32)

# --- distanceTo vs distanceSquaredTo ----------------------------------------
block:
  let a = loc(0, 0)
  let b = loc(3, 4)
  checkEq("distanceSquaredTo is entirely float32",
    distanceSquaredTo(a, b), 25'f32)
  checkEq("distanceTo widens only the sqrt", distanceTo(a, b), 5'f32)
  check("isWithinDistance is INCLUSIVE", isWithinDistance(a, b, 5'f32))
  let epsAbove = cast[float32](cast[uint32](5'f32) - 1'u32)
  check("and excludes one ulp under", not isWithinDistance(a, b, epsAbove))
  ## The two disagree at the boundary once the sqrt has rounded, which is why
  ## the engine's own test is on `distanceTo` and this port's is too.
  checkEq("directionTo is Direction(finish - start)",
    directionTo(a, b).radians, dirDeltas(3, 4).radians)
  checkEq("an identical location gives NORTH, unguarded",
    directionTo(a, a).radians, dirDeltas(0, 1).radians)

# --- add(dir) vs add(dir, dist) ---------------------------------------------
block:
  ## The two shapes seven lines apart in `MapLocation`: `add(dir)` narrows the
  ## cosine BEFORE the add, `add(dir, dist)` forms the product in float64.
  let origin = loc(0, 0)
  let d = dirDeltas(1, 2)
  checkEq("add(dir) is a unit step", addDir(origin, d),
    loc(float32(cos(float64(d.radians))), float32(sin(float64(d.radians)))))
  checkEq("add(dir, 1) is NOT the same expression, only the same value here",
    addDist(origin, d, 1'f32),
    loc(float32(1.0 * cos(float64(d.radians))),
        float32(1.0 * sin(float64(d.radians)))))
  checkEq("getDeltaX(dist) matches add(dir, dist)'s x",
    getDeltaX(d, 3.5'f32), addDist(origin, d, 3.5'f32).x)
  checkEq("getDeltaY(dist) matches its y",
    getDeltaY(d, 3.5'f32), addDist(origin, d, 3.5'f32).y)
  checkEq("translate is a plain float32 add", translate(loc(1, 2), 0.5, -0.25),
    loc(1.5'f32, 1.75'f32))

# --- radiansBetween ---------------------------------------------------------
block:
  let east = dirRads(0)
  let north = dirDeltas(0, 1)
  checkEq("east to north is +pi/2", radiansBetween(east, north),
    float32(PI / 2.0))
  checkEq("north to east is -pi/2", radiansBetween(north, east),
    float32(-PI / 2.0))
  checkEq("a direction to itself is 0", radiansBetween(north, north), 0'f32)
  checkEq("east to west comes back as +pi, the closed end",
    radiansBetween(east, dirDeltas(-1, 0)), FloatPi)

# --- getAngleDegrees --------------------------------------------------------
block:
  checkEq("east is 0 degrees", getAngleDegrees(dirRads(0)), 0'f32)
  checkEq("north is 90", getAngleDegrees(dirDeltas(0, 1)), 90'f32)
  checkEq("west is 180", getAngleDegrees(dirDeltas(-1, 0)), 180'f32)
  checkEq("south is -90", getAngleDegrees(dirDeltas(0, -1)), -90'f32)

# --- onTheMap ---------------------------------------------------------------
block:
  let m = MapRect(origin: loc(0, 0), width: 30, height: 30)
  check("the origin corner is ON the map", m.onTheMap(loc(0, 0)))
  check("the far corner is too", m.onTheMap(loc(30, 30)))
  check("and all four edges", m.onTheMap(loc(0, 15)) and
    m.onTheMap(loc(30, 15)) and m.onTheMap(loc(15, 0)) and
    m.onTheMap(loc(15, 30)))
  check("one ulp outside is off", not m.onTheMap(
    loc(cast[float32](cast[uint32](30'f32) + 1'u32), 15)))
  ## **The radius form tests ONLY the four cardinal extreme points, each
  ## built by a FLOAT32 `translate`.** Against a rectangle those points are
  ## the disc's extremes, so the test is exact containment in exact
  ## arithmetic -- but the adds round first, and a radius below half an ulp
  ## of the centre coordinate vanishes into it.
  check("a radius-1 circle at (1,1) fits", m.onTheMap(loc(1, 1), 1'f32))
  check("one at (0.5,1) does not", not m.onTheMap(loc(0.5, 1), 1'f32))
  let tiny = 5e-7'f32
  checkEq("a 5e-7 radius is below half an ulp at x=30",
    30'f32 + tiny, 30'f32)
  check("so a circle ON the right edge with that radius is ON the map -- " &
    "the engine's float32 translate, not a fix", m.onTheMap(loc(30, 15), tiny))
  check("while ten ulps of radius is refused",
    not m.onTheMap(loc(30, 15), 1e-4'f32))

# --- NaN passes through -----------------------------------------------------
block:
  ## `MapLocation`'s constructor writes `x == Float.NaN ? 0 : x`, and
  ## `x == Float.NaN` is ALWAYS false in Java, so the guard is a no-op and
  ## NaN survives. The port must not "fix" it.
  let nan32 = cast[float32](0x7fc00000'u32)
  let l = loc(nan32, 5'f32)
  check("NaN survives the constructor", l.x != l.x)
  checkEq("and the other coordinate is untouched", l.y, 5'f32)
  check("equality on a NaN coordinate is false", not (l == l))

finish("test_bc17_geom")
