## `examplefuncsplayer24` — the deliberately weak floor and the parity oracle's
## other side.
##
## Ported STATEMENT FOR STATEMENT from
## `battlecode24/example-bots/src/main/examplefuncsplayer/RobotPlayer.java` at
## the pinned commit. IT MAY NOT GAIN BEHAVIOUR: it is one side of the
## differential oracle, and any improvement here makes the oracle prove
## something other than "the ported rule set is the same rule set".
##
## UNLIKE 2021'S, THIS BOT NEEDS NO DETERMINISM PATCH. It declares
## `static final Random rng = new Random(6147)` and never calls
## `Math.random()`, so the oracle's Java side is upstream's file BYTE FOR BYTE.
## Static fields are per robot under the instrumenter, so every duck gets its
## own `Random(6147)` stream; this file reproduces exactly that, in exactly
## that call order:
##
##   * NOT SPAWNED: one `rng.nextInt(spawnLocs.length)` (the length is 27),
##     then `canSpawn`/`spawn`, and the turn ENDS — the `else` branch does not
##     run on a turn the duck spawned.
##   * SPAWNED: `canPickupFlag(getLocation())` then pickup; if holding a flag
##     and `roundNum >= 200`, one step toward `spawnLocs[0]`; then ONE
##     `rng.nextInt(8)` for a direction, a move if legal and otherwise an
##     attack on the tile ahead; then, ONLY IF `canBuild(EXPLOSIVE, prevLoc)`
##     is already true, ONE `rng.nextInt()` and a build when it is `1 mod 37`;
##     then the enemy sweep, which writes `sharedArray[0]`.
##
## `&&` SHORT-CIRCUITS, so the `rng.nextInt()` in the trap clause is drawn only
## when `canBuild` is true. Getting that wrong desynchronises the whole stream
## and is the sort of thing the whole-game Tier A window exists to catch.
##
## `-d:bc24Scenario` compiles the Tier A-prime SCENARIO SCRIPT instead: a
## deterministic, RNG-free bot that forces the rare paths — traps of all three
## kinds, every trigger mode, mastery, the jail penalty, a carry and a capture,
## all three upgrades and the round-200 teleport — early enough for the oracle
## to compare them (§Tests, and Fleet card 1218171523823317).

import kit
import scenario24

export kit

const ScaffoldSeed* = 6147
  ## `static final Random rng = new Random(6147)` — the same constant for
  ## every duck, and a SEPARATE STREAM for each of them, because static fields
  ## are per robot under the instrumenter.

const ScaffoldDirections = [dNorth, dNortheast, dEast, dSoutheast,
                            dSouth, dSouthwest, dWest, dNorthwest]
  ## `RobotPlayer.directions`, in the file's own order.

proc updateEnemyRobots(w: World, side: Side, r: Robot) =
  ## `updateEnemyRobots`: sense every enemy in vision and, if there is at
  ## least one, write the count into slot 0.
  var count = 0
  for l in w.locationsWithinRadiusSquared(r.loc, VisionRadiusSquared):
    if not spend(r, 1): break
    let bot = w.getRobot(l)
    if bot == nil: continue
    if bot.id == r.id: continue
    if bot.team == r.team: continue
    count += 1
  if count != 0:
    w.writeSharedArray(side.team, 0, count)

proc runScaffold24*(w: World, side: Side, r: Robot) =
  when defined(bc24Scenario):
    runScenario24(w, side, r)
  else:
    let me = seqIdOf(r)
    side.scaffoldTurns[me] += 1

    if not r.spawned:
      let spawnLocs = w.spawnLocs[ord(r.team)]
      if spawnLocs.len == 0: return
      let pick = int(side.scaffoldRng[me].nextInt(spawnLocs.len))
      let target = spawnLocs[pick]
      if w.canSpawn(r, target):
        w.doSpawn(r, target)
      return

    if w.canPickupFlag(r, r.loc):
      w.pickupFlag(r, r.loc)

    if r.hasFlag() and w.currentRound >= SetupRounds:
      let spawnLocs = w.spawnLocs[ord(r.team)]
      if spawnLocs.len > 0:
        let dir = r.loc.directionTo(spawnLocs[0])
        if w.canMove(r, dir): w.doMove(r, dir)

    let dir = ScaffoldDirections[int(side.scaffoldRng[me].nextInt(8))]
    let nextLoc = r.loc + dir
    if w.canMove(r, dir):
      w.doMove(r, dir)
    elif w.canAttack(r, nextLoc):
      w.doAttack(r, nextLoc)

    ## `getLocation().subtract(dir)` — read AFTER the possible move.
    let prevLoc = loc(r.loc.x - dir.dx, r.loc.y - dir.dy)
    if w.onTheMap(prevLoc) and w.canBuildTrap(r, tkExplosive, prevLoc):
      ## `&&` short-circuits: the draw happens only here.
      let draw = int(side.scaffoldRng[me].nextInt())
      if draw mod 37 == 1:
        w.buildTrap(r, tkExplosive, prevLoc)

    updateEnemyRobots(w, side, r)
