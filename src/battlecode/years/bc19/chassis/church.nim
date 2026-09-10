## `saber`'s church expansion: when a PILGRIM spends 50 karbonite / 200 fuel
## on a CHURCH, and where.
##
## Behaviour source: `m-schier/battlecode-2019-wololo@ebdd279`,
## `robot.js:76-82` (`STRUCTURE_MINING_INFLUENCE`,
## `MINIMUM_CHURCH_DISTANCE`) and `:1237-1398`
## (`findBestConstructSpotWithScore`), GPL-3.0.
##
## A church is a second SPAWN point AND a second DEPOSIT point, which is what
## turns a remote depot cluster from a long walk into a local economy. It has
## 100 HP and no attack, so it is also a free 100 HP gift to a raider — which
## is why `church_expansion: early` is a real trade and not a free upgrade.

import ../constants, ../units, ../world, ../knobs
import kit, econ

export kit

const MinimumChurchDistance* = 3
  ## Chebyshev, wololo's own `MINIMUM_CHURCH_DISTANCE`.

func clusterScore*(w: World, s: Side, x, y: int): int =
  ## How many depots sit within `STRUCTURE_MINING_INFLUENCE` of this square.
  ## wololo scores a construction spot by exactly this and then rejects any
  ## spot too close to an existing structure.
  for d in s.depots:
    if distSq(d.x, d.y, x, y) <= 16: inc result

func farEnoughFromStructures(s: Side, x, y: int): bool =
  for l in s.structures:
    if max(abs(l.x - x), abs(l.y - y)) < MinimumChurchDistance: return false
  true

proc wantsChurch*(w: World, s: Side, round: int): bool =
  ## `church.nim plan()`, per `church_expansion`.
  case s.doctrine.churchExpansion
  of ce19Never: false
  of ce19Early: true
  of ce19Mid:
    ## Only after round 200, and only when karbonite income is below the
    ## `pilgrim_curve` target — i.e. the depots nearby are already worked.
    round >= 200 and karboniteWorkers(w, s) < s.pilgrimTarget(round)

proc bestChurchSite*(w: World, s: Side, r: Robot): tuple[ok: bool, x, y: int] =
  ## The best passable square within the pilgrim's own vision that scores at
  ## least two depots and sits at Chebyshev >= 3 from every own structure.
  result = (ok: false, x: 0, y: 0)
  if not r.charge(200): return
  var best = 1
  for (x, y) in w.visionBox(r):
    if not w.isPassable(x, y): continue
    if not farEnoughFromStructures(s, x, y): continue
    let score = clusterScore(w, s, x, y)
    if score > best:
      best = score
      result = (ok: true, x: x, y: y)

proc infiltrationSite*(w: World, s: Side, r: Robot): tuple[ok: bool, x, y: int] =
  ## `infiltrate.nim`'s target, computed here because it is the same siting
  ## question with the halves swapped: a passable square in the ENEMY HALF at
  ## Chebyshev >= 3 from every known enemy structure and within 2 of a depot.
  result = (ok: false, x: 0, y: 0)
  if not r.charge(200): return
  var best = high(int)
  for d in s.depots:
    if not w.inEnemyHalf(s.team, d.x, d.y): continue
    for dy in -2 .. 2:
      for dx in -2 .. 2:
        let x = d.x + dx
        let y = d.y + dy
        if not w.isPassable(x, y): continue
        if w.shadowAt(x, y) != 0: continue
        var ok = true
        for l in s.enemyStructuresKnown:
          if max(abs(l.x - x), abs(l.y - y)) < MinimumChurchDistance:
            ok = false
            break
        if not ok: continue
        let cost = distSq(r.x, r.y, x, y)
        if cost < best:
          best = cost
          result = (ok: true, x: x, y: y)
