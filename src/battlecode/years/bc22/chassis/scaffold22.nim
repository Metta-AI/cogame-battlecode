## `examplefuncsplayer22` — the weak floor and the parity oracle's other side.
##
## Ported **statement for statement** from
## `battlecode22/example-bots/src/main/examplefuncsplayer/RobotPlayer.java` at
## the pinned commit. **IT MAY NOT GAIN BEHAVIOUR: it is one side of the
## differential oracle**, and `tests/test_bc22_scaffold.nim` asserts every
## statement below against a recorded oracle trace.
##
## What upstream actually does, and therefore what this does:
##
## * an ARCHON picks `directions[rng.nextInt(8)]` and THEN, on
##   `rng.nextBoolean()`, tries to build a MINER, else a SOLDIER — the direction
##   is drawn BEFORE the coin flip, which fixes the whole RNG stream;
## * a MINER loops `dx, dy in {-1, 0, 1}` in THAT order and, per square, runs
##   `while (canMineGold) mineGold` and THEN `while (canMineLead) mineLead`,
##   then moves in `directions[rng.nextInt(8)]` if it can. Because a miner's
##   action cooldown is 2 against a limit of 10, the inner loops really do fire
##   up to five times a turn on flat ground;
## * a SOLDIER senses `senseNearbyRobots(actionRadiusSquared, opponent)`,
##   attacks `enemies[0].location` if it can, then moves in
##   `directions[rng.nextInt(8)]`;
## * a BUILDER, a SAGE, a LABORATORY and a WATCHTOWER do **nothing at all** —
##   which is why this bot never makes a gold, never puts up a building and
##   always ends at round 2000 on `MORE_LEAD_NET_WORTH` (measured: all eight
##   full-game mirrors ended exactly that way).
##
## It seeds its own `java.util.Random(6147)` and never calls `Math.random()`, so
## — as in bc23, bc24 and bc25 — it needs no determinism patch and the oracle's
## Java side is upstream's file byte for byte apart from its `package` line.
## Static fields are PER ROBOT under the instrumenter, so every unit carries its
## own stream: `Robot.scaffoldRng` is initialised in `spawnRobot`.
##
## The `DecisionOps` charge is deliberately light and mirrors what the bot
## actually looks at: nine squares for the miner's scan, the sensed set for the
## soldier's, one per draw. Measured on the real engine, this bot peaks at
## 680-760 bytecodes — 6-7 % of its 10 000 limit — so it can never be cut off,
## and the parity job asserts that rather than assuming it.

import ../../../sim_types
import ../world, ../economy

export world

proc runScaffold22*(w: World, r: Robot) =
  case r.kind
  of rtArchon:
    if not r.spend(2): return
    let dir = MoveDirs[int(r.scaffoldRng.nextInt(8))]
    if r.scaffoldRng.nextBoolean():
      if w.canBuildRobot(r, rtMiner, dir):
        w.doBuildRobot(r, rtMiner, dir)
    else:
      if w.canBuildRobot(r, rtSoldier, dir):
        w.doBuildRobot(r, rtSoldier, dir)
  of rtMiner:
    let me = r.loc
    for dx in -1 .. 1:
      for dy in -1 .. 1:
        if not r.spend(1): break
        let mineLocation = loc(me.x + dx, me.y + dy)
        while w.canMineGold(r, mineLocation):
          w.doMineGold(r, mineLocation)
        while w.canMineLead(r, mineLocation):
          w.doMineLead(r, mineLocation)
    if not r.spend(1): return
    let dir = MoveDirs[int(r.scaffoldRng.nextInt(8))]
    if w.canMove(r, dir):
      w.doMove(r, dir)
  of rtSoldier:
    let radius = RobotSpecs[rtSoldier].actionRadiusSquared
    var first: Robot = nil
    for other in w.senseNearbyRobots(r, radius):
      if not r.spend(1): break
      if other.team != r.team:
        first = other
        break
    if first != nil:
      let toAttack = first.loc
      if w.canAttack(r, toAttack):
        w.doAttack(r, toAttack)
    if not r.spend(1): return
    let dir = MoveDirs[int(r.scaffoldRng.nextInt(8))]
    if w.canMove(r, dir):
      w.doMove(r, dir)
  else:
    ## LABORATORY, WATCHTOWER, BUILDER and SAGE: upstream's `break`. Nothing.
    discard
