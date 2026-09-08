## PROTOTYPE / TURRET / PORTABLE, `transform` and `mutate` — the three rules
## that make a bc22 building a moving part rather than a fixture.
##
## Split out of `world.nim` because the design note's file table names it
## separately; `NOTICE`, `knobs.nim`'s doc comments and `docs/RULES-BC22.md`
## all point at this path.
##
## TWO RESOLUTIONS AGAINST THE SPEC'S PROSE LIVE HERE (docs/RULES-BC22.md
## §Divergences items 1 and 3):
##
## * **a transform charges exactly ONE cooldown counter, not both.** The prose
##   says transforming "increases both of the Building's cooldowns by 100".
##   `RobotControllerImpl.transform()` flips the mode FIRST and then charges
##   `TRANSFORM_COOLDOWN` to the ACTION counter if the new mode is TURRET and to
##   the MOVEMENT counter otherwise. The untouched counter is invisible because
##   the new mode gates it (`TURRET.canMove == false`,
##   `PORTABLE.canAct == false`) and `canTransformCooldown()` reads the
##   MODE-APPROPRIATE counter — so the engine is self-consistent and the prose
##   is wrong;
## * **a mutation charges the BUILDER at the builder's square and the BUILDING
##   100 on BOTH of its counters at the building's square**, each through its
##   own rubble multiplier. It is also a full heal of the level difference.

import ../../sim_types
import world

export world

func canTransform*(w: World, r: Robot): bool =
  ## `assertIsTransformReady`: the MODE must allow transforming and the
  ## mode-appropriate counter must be under 10.
  r.mode.canTransform and r.canTransformCooldown()

proc doTransform*(w: World, r: Robot): bool {.discardable.} =
  ## `RobotControllerImpl.transform`: flip the mode, THEN charge 100 to the
  ## counter the NEW mode makes meaningful.
  if not w.canTransform(r):
    w.refusedActions += 1
    return false
  r.mode = if r.mode == rmTurret: rmPortable else: rmTurret
  if r.mode == rmTurret:
    w.addActionCooldownTurns(r, TransformCooldown)
  else:
    w.addMovementCooldownTurns(r, TransformCooldown)
  w.stats.transforms[ord(r.team)] += 1
  w.noteFirstAction(r, Bc22ActionTransform)
  true

func leadMutateCostOf*(r: Robot): int = leadMutateCost(r.kind, r.level + 1)
func goldMutateCostOf*(r: Robot): int = goldMutateCost(r.kind, r.level + 1)

func canMutate*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanMutate`: in the builder's r2 <= 5 and on the map, action-ready,
  ## a FRIENDLY BUILDING is there whose mode is neither DROID nor PROTOTYPE and
  ## whose level is under 3, and the TEAM holds both costs.
  if not w.canActLocation(r, l): return false
  if not r.canActCooldown(): return false
  let bot = w.getRobot(l)
  if bot == nil: return false
  if not canMutateType(r.kind, bot.kind): return false
  if bot.team != r.team: return false
  if not bot.canMutateSelf(): return false
  if w.teamLead(r.team) < bot.leadMutateCostOf(): return false
  if w.teamGold(r.team) < bot.goldMutateCostOf(): return false
  true

proc doMutate*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  if not w.canMutate(r, l):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  let bot = w.getRobot(l)
  let leadNeeded = bot.leadMutateCostOf()
  let goldNeeded = bot.goldMutateCostOf()
  w.addLead(r.team, -leadNeeded)
  w.addGold(r.team, -goldNeeded)
  let before = maxHealthOf(bot.kind, bot.level)
  bot.level += 1
  bot.health += maxHealthOf(bot.kind, bot.level) - before
  ## `MUTATE_COOLDOWN` on BOTH of the building's counters, each through the
  ## BUILDING's own square's rubble.
  w.addActionCooldownTurns(bot, MutateCooldown)
  w.addMovementCooldownTurns(bot, MutateCooldown)
  let t = ord(r.team)
  if bot.level == 2: w.stats.mutationsL2[t] += 1
  elif bot.level == 3: w.stats.mutationsL3[t] += 1
  discard w.beat(BeatMutation, "mutation", t, ord(bot.kind), bot.level,
                 $leadNeeded & ":" & $goldNeeded)
  w.noteFirstAction(r, Bc22ActionMutate)
  true
