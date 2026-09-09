## `bulwark`'s `infect.nim plan()` — this year's largest unexploited play, and
## the knob no 2016 archetype the idea names ever spent deliberately.
##
## An infected robot that dies leaves NO rubble and STANDS BACK UP as a zombie
## of its own `turnsInto` at the current outbreak multiplier, on the horde's
## team, on the square where it fell — and zombies hunt the NEAREST
## player-controlled robot of EITHER faction. So where a doomed unit dies is a
## real decision:
##
## * `ignore`     — never read `getInfectedTurns()`; wounded infected units
##                  die where they stand, next to their own archons, and hand
##                  the horde a fresh zombie inside the home ring. This is
##                  what happens by default, and it is exactly what
##                  `-d:bc16BrokenChassis` forces.
## * `quarantine` — walk AWAY from every friendly archon and hold at
##                  >= r2 50 until the counter runs out (10 turns for a zombie
##                  bite, 20 AND 2 damage a turn for a viper bite, which
##                  usually kills a 60-HP soldier).
## * `suicide_squad` — walk AT the nearest enemy archon and die there,
##                  turning a doomed 30-part soldier into a STANDARDZOMBIE
##                  inside the enemy's ring and a doomed archon into a
##                  BIGZOMBIE that hunts THEM.

import ../world
import kit

export kit

func infectionMoveWanted*(w: World, s: Side, r: Robot): bool =
  if w.brokenChassis: return false        ## the negative control ignores it
  if s.doctrine.infectionPolicy == ipIgnore: return false
  r.inf.isInfected()

proc plan*(w: World, s: Side, r: Robot): bool {.discardable.} =
  ## Returns whether this robot's movement is spoken for this turn. Every
  ## other module honours that answer, which is what keeps the policy from
  ## fighting the navigator.
  if not infectionMoveWanted(w, s, r): return false
  case s.doctrine.infectionPolicy
  of ipIgnore: false
  of ipQuarantine:
    let home = s.nearestArchon(r.loc)
    if home.x < 0: return false
    if home.distanceSquaredTo(r.loc) >= 50:
      ## Far enough: hold, so the zombie it becomes spawns in empty ground.
      return true
    w.stepToward(r, home, away = true)
    true
  of ipSuicideSquad:
    let target = s.nearestEnemyArchon(r.loc)
    if target.x < 0: return false
    w.stepToward(r, target)
    true
