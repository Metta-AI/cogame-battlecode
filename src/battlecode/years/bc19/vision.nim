## What a robot may see: the bounded vision box, the `visible`/`radioable`
## predicates, the field-stripping ladder of `getGameStateDump`, and the
## ASCENDING-`id` ordering that replaces the engine's unseeded shuffle (V2).
##
## Ported from `coldbrew/game.js:651-736` at the pinned commit.
##
## **THE PORT DOES NOT REPRODUCE `getVisible`'s FULL-BOARD MASK.** The engine
## allocates a `height x width` integer grid per turn and fills it with -1
## outside the vision radius (`:651-664`); the port scans only the bounded box
## `floor(sqrt(VISION_RADIUS))` around the robot, which is provably equivalent
## because the test is `(x-c)^2 + (y-r)^2 <= VISION_RADIUS` and no square
## outside the box can satisfy it. That is one of the engine's two hot spots
## and neither is a rule.
##
## **V2 — the `visible` array's order is NOT the engine's.**
## `getGameStateDump` shuffles it in place with a Fisher-Yates pass driven by
## the GLOBAL, UNSEEDED `Math.random()` (`:717-722`) — not `this.random()`.
## Measured in this sandbox: FIVE DISTINCT ORDERS IN SIX IDENTICAL RUNS of
## seed 1. There is nothing to be faithful to, so the port presents `visible`
## in ascending robot `id` and `tools/oracle/bc19/visible_order.patch` puts
## the SAME order on the ENGINE side, so the normalisation is symmetric and
## neither trace is massaged alone.

import std/algorithm
import constants, units, world

export world

type
  SeenRobot* = object
    ## One entry of the engine's `visible` array after its field-stripping
    ## ladder (rule 3.5-3.6). A deleted field is represented by its `has*`
    ## flag being `false`, never by a zero: `team` 0 is RED and `x` 0 is a
    ## real column.
    id*: int
    isSelf*: bool
    hasTeam*: bool
    team*: Team
    hasUnit*: bool
    unit*: UnitKind
    hasPos*: bool
    x*, y*: int
    signal*: int              ## -1 when not radioable
    signalRadius*: int        ## -1 when not radioable
    hasCastleTalk*: bool
    castleTalk*: int
    turn*: int
    ## Self-only, because `getGameStateDump` deletes them for anyone else
    ## (`:689-694`).
    health*: int
    karbonite*: int
    fuel*: int

func visionRadiusFor*(r: Robot): int = visionRadiusOf(r.unit)

func canSee*(viewer: Robot, x, y: int): bool =
  ## `(x - c)^2 + (y - r)^2 <= VISION_RADIUS`, INCLUSIVE at the boundary.
  distSq(viewer.x, viewer.y, x, y) <= visionRadiusOf(viewer.unit)

func isVisibleTo*(viewer, target: Robot): bool =
  distSq(viewer.x, viewer.y, target.x, target.y) <=
    visionRadiusOf(viewer.unit)

func isRadioableTo*(viewer, target: Robot): bool =
  ## `d <= robots[i].signal_radius` — the SENDER's currently-stored radius,
  ## from the SENDER's current position (`game.js:675`). A robot that
  ## broadcasts nothing has `signal_radius == 0`, so only a robot standing on
  ## the sender's own square is radioable, which is impossible.
  distSq(viewer.x, viewer.y, target.x, target.y) <= target.signalRadius

proc shadowValueFor*(w: World, viewer: Robot, x, y: int): int =
  ## `getVisible`'s cell: -1 outside vision, else 0 for empty or the id of the
  ## robot standing there.
  if not w.onBoard(x, y): return -1
  if not viewer.canSee(x, y): return -1
  w.shadowAt(x, y)

iterator visionBox*(w: World, r: Robot): (int, int) =
  ## Every on-board square that could be inside `r`'s vision, `y` ascending
  ## outer and `x` ascending inner — the engine's own walk order
  ## (`game.js:655-656`), which matters wherever a caller breaks early.
  let box = visionBoxOf(r.unit)
  let y0 = max(0, r.y - box)
  let y1 = min(w.height - 1, r.y + box)
  let x0 = max(0, r.x - box)
  let x1 = min(w.width - 1, r.x + box)
  for y in y0 .. y1:
    for x in x0 .. x1:
      if distSq(r.x, r.y, x, y) <= visionRadiusOf(r.unit):
        yield (x, y)

proc observationInto*(w: World, viewer: Robot, buf: var seq[SeenRobot]) =
  ## `getGameStateDump`'s `visible` array, rule 3.3 through 3.6, in the
  ## engine's own order of tests — then sorted by ascending `id` (V2).
  buf.setLen(0)
  let isCastle = viewer.unit == ukCastle
  for other in w.robots:
    let d = distSq(viewer.x, viewer.y, other.x, other.y)
    let visible = d <= visionRadiusOf(viewer.unit)
    let radioable = d <= other.signalRadius
    ## `:677` — a CASTLE is NOT skipped here, which is what makes castle talk
    ## work at any range.
    if not visible and not radioable and not isCastle: continue
    ## `:682` — but a castle still only keeps its OWN TEAM at any range.
    if not visible and not radioable and viewer.team != other.team: continue
    var e = SeenRobot(id: other.id, isSelf: other.id == viewer.id,
                      hasTeam: true, team: other.team,
                      hasUnit: true, unit: other.unit,
                      hasPos: true, x: other.x, y: other.y,
                      signal: other.signal, signalRadius: other.signalRadius,
                      hasCastleTalk: true, castleTalk: other.castleTalk,
                      turn: other.turn)
    if e.isSelf:
      e.health = other.health
      e.karbonite = other.karbonite
      e.fuel = other.fuel
    if not radioable:
      e.signal = -1
      e.signalRadius = -1
    if not visible: e.hasUnit = false
    if not visible and not radioable: e.hasPos = false
    ## `:708` — so a CASTLE learns the TEAM of every own-team robot on the
    ## board even without seeing it.
    if not isCastle and not visible: e.hasTeam = false
    ## `:710` — castle talk is readable ONLY by a castle, and only for its
    ## own team.
    if not isCastle or viewer.team != other.team: e.hasCastleTalk = false
    buf.add(e)
  buf.sort(proc (a, b: SeenRobot): int = cmp(a.id, b.id))

proc observationFor*(w: World, viewer: Robot): seq[SeenRobot] =
  observationInto(w, viewer, result)
