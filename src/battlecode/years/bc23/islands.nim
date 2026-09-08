## The bc23 sky islands: the record and the PURE half of its turn.
##
## A behaviour port of `world/Island.java` at commit
## `af42086ecd09709dc603b2aaa9e9b98312c9ef79`. An island is a fixed set of
## tiles (at most `MAX_ISLAND_AREA = 20`) with an owner, an anchor type and an
## anchor health. Everything about it that does NOT need to reach into the
## robot table lives here; the sweep that counts occupants, heals the garrison
## and registers or removes an accelerating anchor's tempo boost lives in
## `world.nim` beside the state it changes (docs/RULES-BC23.md §Divergences
## item 14).
##
## Three engine facts the port keeps literally:
##
## * **`advanceTurn` returns immediately on a NEUTRAL island** — no occupancy
##   count, no healing, nothing;
## * **the health move is `min(total, health + diff)`** with `diff` the
##   truncated-toward-zero `(100 * (own - enemy)) / area`, so it can be
##   negative and an unheld island bleeds;
## * **a just-neutralised island heals nobody**, because `getLocsAffected()`
##   returns the empty set once the anchor is gone, which is exactly why the
##   engine's `anchorPlanted.healingFrequency` dereference cannot fault.

import units

export units

type
  Island* = object
    id*: int
    tiles*: seq[Loc]
      ## In the engine's own discovery order: ascending TILE INDEX, because
      ## `GameWorld`'s constructor walks `islandIds` from index 0 upward.
    owner*: int              ## 0 neutral, 1 team A, 2 team B
    anchor*: AnchorType
    health*: int
    ## --- telemetry, never read by a rule ---
    capturedRound*: int
    heldRounds*: array[2, int]

func area*(isl: Island): int = isl.tiles.len

func ownerTeam*(isl: Island): Team =
  ## Only meaningful when `owner != 0`; callers check first, exactly as the
  ## engine's `teamOwning != NEUTRAL` guard does.
  if isl.owner == 1: teamA else: teamB

func isOwnedBy*(isl: Island, t: Team): bool = isl.owner == ord(t) + 1

func minDistTo*(isl: Island, l: Loc): int =
  ## `Island.minDistTo`: the SQUARED distance to the nearest island tile.
  result = high(int)
  for tile in isl.tiles:
    result = min(result, tile.distanceSquaredTo(l))

func canPlaceAnchor*(isl: Island, placing: Team): bool =
  ## `Island.assertCanPlaceAnchor`: refused only when an anchor is planted AND
  ## it is not ours. Overriding our OWN anchor is legal, including with a
  ## different type.
  isl.anchor == anNone or isl.owner == ord(placing) + 1

func advanceHealth*(isl: Island, ownerTiles, enemyTiles: int): int =
  ## The health an island's anchor moves to this round, before the
  ## neutralisation test.
  min(AnchorSpecs[isl.anchor].totalHealth,
      isl.health + occupancyDiff(ownerTiles, enemyTiles, isl.area))

func healthPips*(isl: Island): int =
  ## 0..4, for the viewer's per-island health pip. Never read by a rule.
  if isl.anchor == anNone: 0
  else:
    let total = max(1, AnchorSpecs[isl.anchor].totalHealth)
    max(1, min(4, (isl.health * 4 + total - 1) div total))
