## Battlecode 2017's continuous-space primitives: `MapLocation`, `Direction`
## and the map's own `onTheMap` tests.
##
## **EVERY PROC IN THIS FILE IS A TRANSCRIPTION OF ONE JAVA METHOD WITH ITS
## WIDTHS**, from `common/MapLocation.java` and `common/Direction.java` of
## `battlecode/battlecode-server-2017` at commit `165d8a8e`, and the widths are
## the whole point. Both classes are `strictfp`, so IEEE-754 `+ - * /` and
## comparison are exactly specified in float32 and float64 and every algebraic
## expression here is bit-exact by construction PROVIDED the widths and the
## order match. They do not all match each other: Java's numeric promotion is
## replicated PER EXPRESSION, taken from the Java text and never from taste
## (docs/RULES-BC17.md F3).
##
## The three shapes that differ from each other in the same codebase, and the
## single easiest way to break bc17 parity:
##
##   * `add(dir)`        `dx = (float) cos(radians)`; `x + dx` in float32
##                       -- THE COSINE IS NARROWED BEFORE THE ADD;
##   * `add(dir, dist)`  `dx = (float)(dist * cos(radians))`
##                       -- THE PRODUCT IS FORMED IN FLOAT64 and narrowed once;
##   * `distanceTo`      `dx = x - loc.x` and `dx*dx + dy*dy` in FLOAT32, only
##                       the `sqrt` widened.
##
## And in `ballistics.nim`, seven lines apart in the same Java method,
## `perpDist` forms its product in float64 while `hitDist` narrows the cosine
## first. `tests/test_bc17_widths.nim` pins one named vector per row of the F3
## table so a port that swaps two shapes fails a unit test rather than a
## 2 999-round trace diff.
##
## The transcendentals are `src/battlecode/fdlibm.nim`'s fdlibm ports, never
## the platform libm's: the sim is compiled twice from these sources (native
## for the server, wasm for the viewer) and glibc's `sin` and emscripten's are
## not the same function. `tools/oracle/bc17/strictmath.patch` rewrites the
## engine's eleven `Math.{atan2,sin,cos,sqrt}` call sites to `StrictMath` so
## the agreement is enforced on both sides rather than assumed (F1, F2).

import std/math
import ../../fdlibm

const
  FloatPi* = float32(PI)
    ## `(float) Math.PI`. **This is a DIFFERENT VALUE from `Math.PI`** and the
    ## engine keeps the two apart exactly where it does: `reduce` compares
    ## against `(float)Math.PI` and then corrects with `Math.PI * 2 * circles`
    ## in float64.

type
  Loc* = object
    ## `common/MapLocation.java`. A value type, as the Java class is
    ## immutable. The constructor's `x == Float.NaN ? 0 : x` is a no-op --
    ## `x == Float.NaN` is ALWAYS false in Java -- so NaN passes through, and
    ## the port must not "fix" that (`MapLocation.java:33-34`).
    x*, y*: float32

  Dir* = object
    ## `common/Direction.java`. One float32, always in `(-pi, pi]` because
    ## every constructor and every rotation goes through `reduce`.
    radians*: float32

func loc*(x, y: float32): Loc = Loc(x: x, y: y)

func `==`*(a, b: Loc): bool = a.x == b.x and a.y == b.y
  ## `MapLocation.equals`: an exact float comparison on both coordinates,
  ## which is what makes `directionTo` return null for an identical location.

func reduce*(rads: float32): float32 =
  ## `Direction.reduce` (`:663-672`), with its mixed widths intact: the
  ## comparison is against `(float)Math.PI`, the `circles` count is computed
  ## in FLOAT64 (`-(rads + Math.PI) / (2 * Math.PI)`) and truncated toward
  ## zero by Java's `(int)` cast, and the correction is a float32 add of a
  ## float32-narrowed float64 product.
  if rads <= -FloatPi:
    let circles = int(ceil(-(float64(rads) + PI) / (2.0 * PI)))
    rads + float32(PI * 2.0 * float64(circles))
  elif rads > FloatPi:
    let circles = int(ceil((float64(rads) - PI) / (2.0 * PI)))
    rads - float32(PI * 2.0 * float64(circles))
  else:
    rads

func dirRads*(radians: float32): Dir =
  ## `new Direction(float radians)`. The engine throws on NaN and infinity
  ## (`assertValid`); every internal caller passes a finite value, and the
  ## chassis layer never constructs one from arithmetic it has not bounded.
  Dir(radians: reduce(radians))

func dirDeltas*(dx, dy: float32): Dir =
  ## `new Direction(float dx, float dy)` (`:470-477`): **`(0, 0)` becomes
  ## `(0, 1)`**, i.e. NORTH, and the atan2 takes `dy` FIRST and both arguments
  ## widened to float64.
  var yy = dy
  if dx == 0'f32 and dy == 0'f32:
    yy = 1'f32
  Dir(radians: reduce(float32(fdlibmAtan2(float64(yy), float64(dx)))))

func directionTo*(start, finish: Loc): Dir =
  ## `MapLocation.directionTo` (`:216-224`) == `new Direction(start, finish)`
  ## == `new Direction(finish.x - start.x, finish.y - start.y)`, with the two
  ## subtractions in float32.
  ##
  ## **UNGUARDED, DELIBERATELY.** The Java method returns `null` when the two
  ## locations are `equals`, and two callers behave differently on that null
  ## (`calcHitDist` returns 0 for a null `toTarget` and THROWS for a null
  ## `toFinish`), so the null test belongs at the call site and every caller
  ## in this module makes it explicitly with `==`.
  dirDeltas(finish.x - start.x, finish.y - start.y)

func distanceTo*(a, b: Loc): float32 =
  ## `MapLocation.distanceTo` (`:131-135`): the two products and the sum in
  ## FLOAT32, only the `sqrt` widened. `sqrt` is correctly rounded by IEEE-754
  ## in both languages, so this needs no fdlibm port (F1, class (a)).
  let dx = a.x - b.x
  let dy = a.y - b.y
  float32(sqrt(float64(dx * dx + dy * dy)))

func distanceSquaredTo*(a, b: Loc): float32 =
  ## `MapLocation.distanceSquaredTo` (`:146-150`): entirely float32.
  let dx = a.x - b.x
  let dy = a.y - b.y
  dx * dx + dy * dy

func isWithinDistance*(a, b: Loc, dist: float32): bool =
  ## `MapLocation.isWithinDistance` (`:162-164`) -- INCLUSIVE, and computed
  ## from `distanceTo` rather than from the squared distance, because the two
  ## disagree at the boundary once the `sqrt` has rounded.
  distanceTo(a, b) <= dist

func addDir*(l: Loc, d: Dir): Loc =
  ## `MapLocation.add(Direction)` (`:236-243`): **the cosine is narrowed to
  ## float32 BEFORE the add.**
  let dx = float32(fdlibmCos(float64(d.radians)))
  let dy = float32(fdlibmSin(float64(d.radians)))
  Loc(x: l.x + dx, y: l.y + dy)

func addDist*(l: Loc, d: Dir, dist: float32): Loc =
  ## `MapLocation.add(Direction, float)` (`:272-279`): **the product is formed
  ## in FLOAT64 and narrowed once** -- a different shape from `add(dir)` in
  ## the same class.
  let dx = float32(float64(dist) * fdlibmCos(float64(d.radians)))
  let dy = float32(float64(dist) * fdlibmSin(float64(d.radians)))
  Loc(x: l.x + dx, y: l.y + dy)

func translate*(l: Loc, dx, dy: float32): Loc =
  ## `MapLocation.translate` (`:378-380`), float32.
  Loc(x: l.x + dx, y: l.y + dy)

func getDeltaX*(d: Dir, travelDist: float32): float32 =
  ## `Direction.getDeltaX` (`:539-541`): the product in float64, narrowed once.
  float32(float64(travelDist) * fdlibmCos(float64(d.radians)))

func getDeltaY*(d: Dir, travelDist: float32): float32 =
  float32(float64(travelDist) * fdlibmSin(float64(d.radians)))

func getAngleDegrees*(d: Dir): float32 =
  ## `Direction.getAngleDegrees` (`:561-563`). `Math.toDegrees` IS
  ## `angrad * 180.0 / PI`, two exactly specified float64 operations.
  float32(float64(d.radians) * 180.0 / PI)

func rotateLeftRads*(d: Dir, angleRads: float32): Dir =
  ## `Direction.rotateLeftRads` (`:607-609`): a float32 add, then the
  ## constructor's `reduce`.
  dirRads(d.radians + angleRads)

func rotateRightRads*(d: Dir, angleRads: float32): Dir =
  ## `rotateRightRads(a) = rotateLeftRads(-a)`, and the negation is on the
  ## FLOAT32 value.
  d.rotateLeftRads(-angleRads)

func toRadians32*(angleDegrees: float32): float32 =
  ## `(float) Math.toRadians(angleDegrees)` == `(float)(angdeg / 180.0 * PI)`.
  ## **This one is load-bearing**: it is how `rotateLeftDegrees(i * 20)` and
  ## `(i * 15)` turn a triad and a pentad spread into radians.
  float32(float64(angleDegrees) / 180.0 * PI)

func rotateLeftDegrees*(d: Dir, angleDegrees: float32): Dir =
  d.rotateLeftRads(toRadians32(angleDegrees))

func rotateRightDegrees*(d: Dir, angleDegrees: float32): Dir =
  d.rotateRightRads(toRadians32(angleDegrees))

func opposite*(d: Dir): Dir =
  ## `Direction.opposite` == `rotateLeftRads((float) Math.PI)`.
  d.rotateLeftRads(FloatPi)

func radiansBetween*(a, b: Dir): float32 =
  ## `a.radiansBetween(b)` (`:634-636`) == `reduce(b.radians - a.radians)`:
  ## a FLOAT32 subtract, then the mixed-width `reduce`.
  reduce(b.radians - a.radians)

# ---------------------------------------------------------------------------
#  The map rectangle -- `world/LiveMap.java`
# ---------------------------------------------------------------------------

type
  MapRect* = object
    ## `LiveMap`'s width, height and origin. Float32, like everything else in
    ## this year.
    origin*: Loc
    width*, height*: float32

func onTheMap*(m: MapRect, l: Loc): bool =
  ## `LiveMap.onTheMap(MapLocation)` (`:152-154`) -- a POINT test, INCLUSIVE
  ## on all four edges, with `origin.x + width` computed in float32.
  l.x >= m.origin.x and l.y >= m.origin.y and
    l.x <= m.origin.x + m.width and l.y <= m.origin.y + m.height

func onTheMap*(m: MapRect, l: Loc, radius: float32): bool =
  ## `LiveMap.onTheMap(MapLocation, float)` (`:175-180`) -- it tests **ONLY
  ## THE FOUR CARDINAL EXTREME POINTS** of the circle, each one built by
  ## `MapLocation.translate`, i.e. **a float32 add**.
  ##
  ## Against an axis-aligned rectangle those four points are the disc's
  ## extremes in x and y, so the test is exact containment *in exact
  ## arithmetic* -- but it is NOT performed in exact arithmetic. `x - radius`
  ## and `x + radius` round to float32 first, so a circle whose radius is
  ## below half an ulp of its centre coordinate is judged to be ON the map
  ## even when it sits exactly on an edge. That is the engine's own
  ## behaviour, and `tests/test_bc17_geom.nim` pins it with a named vector
  ## rather than letting a "fix" creep in.
  m.onTheMap(l.translate(-radius, 0'f32)) and
    m.onTheMap(l.translate(radius, 0'f32)) and
    m.onTheMap(l.translate(0'f32, -radius)) and
    m.onTheMap(l.translate(0'f32, radius))
