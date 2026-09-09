## `bulwark`'s `rubble.nim plan()` — rubble is this year's terrain and its
## economy is exact.
##
## `r -> max(0, 0.95r - 10)` per action; >= 100 is impassable to everything
## but a SCOUT, a FASTZOMBIE and a BIGZOMBIE; >= 50 DOUBLES every movement and
## cooldown charge; and every uninfected corpse adds its own max health, so a
## battle line bricks itself up. Measured on the played pool: `caverns` starts
## with 1 078 of 1 892 squares impassable, `boxy` has squares at 55 555 and
## `collision` at 9 999 — clearing a 100 to 0 takes FOURTEEN actions, a 1000
## takes about 55, and a 55 555 is not worth touching, which is what the
## "never above 200" rule below encodes.
##
## A TURRET and a TTM cannot clear at any setting (`canClearRubble()`), and a
## SCOUT is preferred wherever one is available: movementDelay 1.4 is the
## cheapest digger in the game.

import ../world
import kit

export kit

const NeverClearAbove* = 200.0
  ## Above this a clear is 55+ actions for one square and the navigator would
  ## rather walk around. `zigzag`'s 10^6 and `boxy`'s 55 555 are the reason
  ## this rule exists rather than a "clear the highest" heuristic.

func clearsAtAll*(s: Side, k: RobotType): bool =
  canClearRubble(k) and s.doctrine.rubbleClear != rcNever

proc plan*(w: World, s: Side, r: Robot): bool {.discardable.} =
  ## Clear one square if this robot should. Returns whether the action was
  ## taken (it costs the core, so the caller must not also move).
  if not clearsAtAll(s, r.kind): return false
  if not r.d.isCoreReady(): return false
  let home = s.nearestArchon(r.loc)
  let aggressive = s.doctrine.rubbleClear == rcAggressive
  var bestDir = dNone
  var bestScore = 0.0
  for d in MoveDirs:
    if not r.spend(1): break
    let target = r.loc + d
    if not w.onTheMap(target): continue
    if w.isLocationOccupied(target): continue
    let rubble = w.getRubble(target)
    if rubble <= 0.0 or rubble > NeverClearAbove: continue
    ## `paths`: only what actually blocks — a square at or above 100 — and
    ## only near home or on the way somewhere. `aggressive`: additionally
    ## flatten anything at or above 50 inside the archon ring, which is what
    ## makes a `turtle` opening fast rather than merely safe.
    var wanted = rubble >= RubbleObstructionThresh
    if aggressive and rubble >= RubbleSlowThresh and home.x >= 0 and
        home.distanceSquaredTo(target) <= 100:
      wanted = true
    if not wanted: continue
    ## Prefer the square that opens with the fewest actions.
    let score = 1000.0 - rubble
    if score > bestScore:
      bestScore = score
      bestDir = d
  if bestDir == dNone: return false
  w.doClearRubble(r, bestDir)
