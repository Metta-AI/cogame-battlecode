## The bc16 zombie AI, ported VERBATIM from
## `world/control/ZombieControlProvider.java` (398 lines) at commit
## `11a0b09f26a70da19f33a61ebec4ceaf6e161aa3`.
##
## **THIS FILE IS THE SIM, NOT A CHASSIS.** The zombie half of this game is
## engine-side: a den and a zombie cost nothing against any `DecisionOps`
## budget, take no doctrine, and are the same for both factions. It is also
## the half a doctrine has to plan around, so it is specified action for
## action — and it is the reason Tier A of the parity oracle is a large tier
## even with an idle player bot.
##
## Three things in here are the most order-sensitive code in the module:
##
## * **A den's turn** (`processZombieDen`, `:140-176`): add THIS DEN'S OWN
##   share of this round's schedule into its persistent queue,
##   `spawnAllPossible`, and then — ONLY IF ANY TYPE IS STILL QUEUED — damage
##   every non-zombie robot on the eight adjacent squares for
##   `DEN_SPAWN_PROXIMITY_DAMAGE = 10.0` and call `spawnAllPossible` AGAIN.
##   So a den spawns at most 8 per call and AT MOST 16 PER ROUND.
## * **`spawnAllPossible`** (`:184-218`): walk the ring
##   `DIRECTIONS[floorMod(start + dirOffset * chir, 8)]` for `dirOffset`
##   0..7, and per direction pick the next type as **the LAST type in
##   {STANDARD, RANGED, FAST, BIG} with a non-zero count** — the loop has NO
##   `break`, so the priority is really BIGZOMBIE, then FASTZOMBIE, then
##   RANGEDZOMBIE, then STANDARDZOMBIE. `start` and `chir` are
##   `getSpawnDirection` / `getSpawnChirality`, both memoised per location in
##   the engine and both RESOLVED AT BUILD TIME here (D3/D4) and carried in
##   the converted map file.
## * **A zombie's turn** (`processZombie`, `:220-300`) — eight steps with
##   every early return in place, and TWO RNG DRAWS whose preconditions are
##   exact (D2c): `random.nextInt(8)` ONLY when no player robot is alive at
##   all, and `random.nextBoolean()` ONLY when the zombie got past the attack
##   branch, past the `!isCoreReady()` branch and past the
##   move-in-the-preferred-direction branch. `getNearestPlayerControlled`
##   consumes a draw from the OTHER stream on every call (D2b).

import world, signals

export world

proc addScheduledZombies*(w: World, den: Robot) =
  ## `processZombieDen` step (a): this round's counts from THIS DEN'S OWN
  ## split schedule (`getZombieSpawnSchedule(den.getLocation())`), added into
  ## the den's persistent queue. The per-den split was computed at build time
  ## (D3) and the runtime sim hashes nothing.
  if den.denIndex < 0: return
  for row in w.map.dens[den.denIndex].schedule:
    if row.round == w.currentRound:
      for i in 0 .. 3:
        den.denQueue[i] += row.counts[i]

func nextQueuedType(den: Robot): int =
  ## The engine's own type loop, with NO `break`: it keeps the LAST non-zero
  ## entry, so the effective priority is BIGZOMBIE, FASTZOMBIE, RANGEDZOMBIE,
  ## STANDARDZOMBIE. Returns an index into `ZombieSpawnTypes`, or -1.
  result = -1
  for i in 0 .. 3:
    if den.denQueue[i] != 0:
      result = i

proc spawnAllPossible*(w: World, den: Robot) =
  ## `spawnAllPossible` (`:184-218`).
  if den.denIndex < 0: return
  let start = w.map.dens[den.denIndex].spawnDir
  let chir = w.map.dens[den.denIndex].chirality
  for dirOffset in 0 .. 7:
    ## `Math.floorMod(startingDirection + dirOffset * chirality, 8)`.
    let raw = start + dirOffset * chir
    let d = MoveDirs[((raw mod 8) + 8) mod 8]
    let next = den.nextQueuedType()
    if next < 0:
      break
    let kind = ZombieSpawnTypes[next]
    if w.canBuild(den, d, kind):
      w.doBuild(den, d, kind)
      den.denQueue[next] -= 1

proc processZombieDen*(w: World, den: Robot) =
  ## `processZombieDen` (`:140-176`), in its three steps.
  w.addScheduledZombies(den)
  w.spawnAllPossible(den)
  if den.nextQueuedType() >= 0:
    ## A queue remains: damage every adjacent NON-ZOMBIE robot for 10.0 —
    ## which reaches NEUTRALS and both factions alike — and then try again.
    ## `takeDamage(double)` passes a null attacker type, so the death cause is
    ## the normal one and a corpse here still leaves rubble.
    for i in 0 .. 7:
      let block0 = w.getRobot(den.loc + MoveDirs[i])
      if block0 != nil and block0.team != teamZombie:
        if block0.team.isPlayer():
          w.stats.zombieDamageTaken[ord(block0.team)] +=
            int(DenSpawnProximityDamage)
          w.lastDamageSource[ord(block0.team)] = "den_proximity"
        w.changeHealthLevel(block0, -DenSpawnProximityDamage, dcNormal)
    w.spawnAllPossible(den)

proc processZombie*(w: World, z: Robot) =
  ## `processZombie` (`:220-300`), the eight-step ladder with every early
  ## return in place. The armageddon daytime clause of step (c) is not ported
  ## (V4).
  let closest = w.getNearestPlayerControlled(z.loc)   # D2b: one draw
  if closest != nil and w.canAttackLocation(z, closest.loc):
    ## (b) In range: attack if the weapon is ready — AND RETURN EITHER WAY.
    if z.d.isWeaponReady():
      w.doAttack(z, closest.loc)
    return
  if not z.d.isCoreReady():
    ## (c) Nothing else is possible this turn.
    return
  var preferred: Dir
  if closest != nil:
    ## (d) Walk at it.
    preferred = z.loc.directionTo(closest.loc)
    if w.canMove(z, preferred):
      w.doMove(z, preferred)
      return
  else:
    ## D2c, site 1: `random.nextInt(8)` ONLY when there is no player robot
    ## alive anywhere on the map.
    preferred = MoveDirs[int(w.zombieRand.nextInt(8))]
  ## (e) D2c, site 2: `random.nextBoolean()`, consumed ONLY here.
  let newLeft = w.zombieRand.nextBoolean()
  let nextDir = if newLeft: preferred.rotateLeft() else: preferred.rotateRight()
  if w.canMove(z, nextDir):
    w.doMove(z, nextDir)
    return
  ## (f) The other 45 degrees.
  let finalDir = if newLeft: preferred.rotateRight()
                 else: preferred.rotateLeft()
  if w.canMove(z, finalDir):
    w.doMove(z, finalDir)
    return
  ## (g) Dig, but only into an UNOCCUPIED on-map square at rubble >= 100. A
  ## FASTZOMBIE or a BIGZOMBIE ignores rubble and so never reaches here with
  ## an empty square in front of it; a STANDARDZOMBIE or a RANGEDZOMBIE digs.
  let preferredTarget = z.loc + preferred
  if (not w.isLocationOccupied(preferredTarget)) and
      w.onTheMap(preferredTarget) and
      w.senseRubble(z, preferredTarget) >= RubbleObstructionThresh:
    w.doClearRubble(z, preferred)
    return
  ## (h) Eat the NEUTRAL standing in the way — which is what happens to a
  ## neutral a faction did not activate in time.
  if w.isLocationOccupied(preferredTarget):
    let occupant = w.getRobot(preferredTarget)
    if occupant != nil and occupant.team == teamNeutral:
      if z.d.isWeaponReady():
        w.doAttack(z, preferredTarget)
        return

proc runZombieController*(w: World, r: Robot) =
  ## `ZombieControlProvider.runRobot`. A NEUTRAL robot reaches the "somehow
  ## controlling a non-zombie robot -> kill it" branch in the engine ONLY
  ## because the reference server registers the zombie provider for
  ## `Team.NEUTRAL`; the driver in `tools/oracle/bc16/Bc16Trace.java`
  ## registers a `NullControlProvider` for NEUTRAL instead, which is the
  ## behaviour a match really has (a neutral robot never acts), and this port
  ## does the same: A NEUTRAL ROBOT TAKES ITS TURN AND DOES NOTHING.
  ## `docs/PARITY.md` §bc16 records that requirement.
  if r.kind == rtZombieden:
    w.processZombieDen(r)
  elif isZombieType(r.kind):
    w.processZombie(r)
  else:
    discard
