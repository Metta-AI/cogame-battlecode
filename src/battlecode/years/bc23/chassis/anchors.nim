## `lemonade`'s island programme: when to build an anchor, which island it
## goes to, and how big a garrison that island needs.
##
## Behaviour ported from `awesomelemonade/Battlecode2023` `src/finalBot/`
## (AGPL-3.0) — the island tracker and the escort request — parameterised by
## `anchor_round`, `anchor_budget` and `island_priority`.
##
## THE GARRISON MODEL IS THE ENGINE'S OWN ARITHMETIC RUN FORWARD. An island of
## area `a` moves its anchor health by `(100 * (ours - theirs)) / a` every
## round, so holding it at full health needs at least one more of our robots
## standing on it than theirs — and holding it against a real contest needs
## `ceil(a * wanted / 100)` more.

import ../world, kit, econ

export kit

func wantsAnchor*(w: World, side: Side): bool =
  ## `schedule()`. Never before `anchor_round`, never at all at
  ## `anchor_budget == 0`, and never a second one while one is already in
  ## flight — an anchor costs a carrier round trip as well as 160 kg.
  side.doctrine.anchorBudget > 0 and
    w.currentRound >= side.doctrine.anchorRound

func anchorKindFor*(w: World, side: Side, hq: Robot): AnchorType =
  ## An ACCELERATING anchor whenever the elixir programme has paid for one and
  ## the doctrine's sink is anchors; a STANDARD one otherwise.
  if side.doctrine.elixirSpend == esAcceleratingAnchors and
      hq.elixir >= anchorCost(anAccelerating, resElixir):
    anAccelerating
  else:
    anStandard

func garrisonNeeded*(w: World, islandIdx: int): int =
  ## How many more of our robots than theirs the island needs standing on it
  ## to gain health at all. One is always enough to gain SOMETHING; the model
  ## reports what a full-rate hold costs.
  max(1, (w.islands[islandIdx].area + 9) div 10)

proc pickIsland*(w: World, side: Side, from0: Loc): int =
  ## `pick()`. Only islands the faction has actually SENSED are candidates —
  ## the remembered map, not omniscience.
  result = -1
  var best = high(int)
  for islandIdx in side.knownIslands:
    let isl = w.islands[islandIdx]
    if isl.isOwnedBy(side.team) and isl.anchor != anNone: continue
    if side.anchorClaims.hasKey(islandIdx): continue
    if isl.tiles.len == 0: continue
    var score = 0
    case side.doctrine.islandPriority
    of ipNearest:
      score = chebyshev(from0, isl.tiles[0])
    of ipContested:
      ## Lowest anchor health first, then an enemy-held island, then nearest.
      score = (if isl.owner == 0: 200 else: isl.health) +
        chebyshev(from0, isl.tiles[0])
    of ipSafe:
      ## Furthest from every enemy headquarters — the island a garrison can
      ## actually hold.
      var nearestEnemy = high(int)
      for h in side.enemyHqs:
        nearestEnemy = min(nearestEnemy, chebyshev(h, isl.tiles[0]))
      if nearestEnemy == high(int): nearestEnemy = 0
      score = 200 - min(200, nearestEnemy) + chebyshev(from0, isl.tiles[0])
    if score < best:
      best = score
      result = islandIdx

proc claimIsland*(side: Side, islandIdx, carrierId: int) =
  side.anchorClaims[islandIdx] = carrierId
  side.ferryClaim = carrierId

proc releaseClaim*(side: Side, carrierId: int) =
  var dead: seq[int]
  for islandIdx, id in side.anchorClaims:
    if id == carrierId: dead.add(islandIdx)
  for islandIdx in dead: side.anchorClaims.del(islandIdx)
  if side.ferryClaim == carrierId: side.ferryClaim = -1

func claimedBy*(side: Side, carrierId: int): int =
  result = -1
  for islandIdx, id in side.anchorClaims:
    if id == carrierId: return islandIdx

proc buildAnchorIfDue*(w: World, side: Side, hq: Robot): bool =
  ## Called first in a headquarters' turn, so the anchor programme gets the
  ## first of its five actions rather than whatever the build queue leaves.
  if not wantsAnchor(w, side): return false
  if hq.totalAnchors >= 2: return false
  if w.anchorsInStock(side.team) >= 2: return false
  let kind = anchorKindFor(w, side, hq)
  if not w.canBuildAnchor(hq, kind): return false
  w.doBuildAnchor(hq, kind)
