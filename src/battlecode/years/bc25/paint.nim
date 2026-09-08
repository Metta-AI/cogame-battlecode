## The bc25 paint alphabet and the two tile predicates, PURE.
##
## Colour encoding is exactly the engine's `colorLocations` alphabet
## (`world/GameWorld.java`):
##
##     0  bare        1  A primary    2  A secondary
##                    3  B primary    4  B secondary
##
## `teamFromPaint` maps 1,2 -> A and 3,4 -> B and everything else to NEITHER.
## Markers use a SEPARATE per-team 0/1/2 alphabet (0 none, 1 primary, 2
## secondary) held in two arrays, so a marker is invisible to the enemy and
## affects nothing but sensing.
##
## `isPaintable` IS `isPassable` in 2025 (`GameWorld.isPaintable` is a one-line
## delegate), and both are `!(wall || ruin)`. Every tower sits on a ruin, so a
## tower tile is impassable for THAT reason and not by a separate rule — which
## is why a tower's tile is also unpaintable and why the 70 % denominator
## counts tiles nobody can ever colour.
##
## THE STATEFUL HALF — `setPaint` with its live-count bookkeeping and its
## mid-action 70 % win check, and the charged `connectedByPaint` BFS — lives in
## `world.nim` beside the arrays it mutates (docs/RULES-BC25.md §Divergences
## item 14).

import units

export units

const
  PaintNone* = 0
  PaintAPrimary* = 1
  PaintASecondary* = 2
  PaintBPrimary* = 3
  PaintBSecondary* = 4

  MarkerNone* = 0
  MarkerPrimary* = 1
  MarkerSecondary* = 2

func primaryPaint*(t: Team): int =
  if t == teamA: PaintAPrimary else: PaintBPrimary

func secondaryPaint*(t: Team): int =
  if t == teamA: PaintASecondary else: PaintBSecondary

func paintFor*(t: Team, secondary: bool): int =
  if secondary: secondaryPaint(t) else: primaryPaint(t)

func isPrimaryPaint*(paint: int): bool =
  paint == PaintAPrimary or paint == PaintBPrimary

func hasPaintTeam*(paint: int): bool =
  paint >= PaintAPrimary and paint <= PaintBSecondary

func teamFromPaint*(paint: int): Team =
  ## Only meaningful when `hasPaintTeam(paint)`; callers ask that first,
  ## exactly as the engine's `Team.NEUTRAL` third case forces them to.
  if paint == PaintAPrimary or paint == PaintASecondary: teamA else: teamB

func paintIsTeam*(paint: int, t: Team): bool =
  hasPaintTeam(paint) and teamFromPaint(paint) == t

func passableTile*(wall, ruin: bool): bool = not (wall or ruin)

func paintableTile*(wall, ruin: bool): bool = passableTile(wall, ruin)
