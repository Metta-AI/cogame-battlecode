## `orchard`'s use of the 10 000-channel per-team array -- laid out and
## documented, because a channel layout nobody wrote down is a channel layout
## nobody can debug.
##
##     0 .. 1    the rally point, x and y in tenths
##     2         the round the rally point was stamped (older than ten rounds
##               is ignored)
##     3 .. 8    enemy-archon sightings, x and y in tenths, up to three
##     9 .. 40   farm-slot claims (the gardener id holding each lane)
##     41 .. 60  a threat digest by grid cell
##
## **BROADCASTING REVEALS THE BROADCASTER'S POSITION TO BOTH TEAMS FOR ONE
## ROUND** (`GameWorld.updateBroadCastData` hands
## `senseBroadcastingRobotLocations()` the same array to everybody), so this
## is the one place in 2017 where communicating costs INFORMATION rather than
## bullets. `orchard` therefore broadcasts **at most once per unit per five
## rounds** and NEVER from a scout inside enemy territory.
##
## A doctrine cannot redefine a channel, cannot set the cadence and cannot add
## a message kind (§Out of scope): exposing the layout would expose a channel
## a doctrine could use to leak what it should not.

import ../constants, ../units, ../geom, ../world, ../actions, ../knobs
import kit

export kit

const
  ChRallyX* = 0
  ChRallyY* = 1
  ChRallyStamp* = 2
  ChEnemyArchon* = 3
  ChFarmClaims* = 9
  ChThreat* = 41
  RallyMaxAge* = 10
  BroadcastEvery* = 5

func mayBroadcast*(w: World, r: Robot): bool =
  w.currentRound - r.lastBroadcast >= BroadcastEvery

proc postRally*(w: World, s: Side, r: Robot, target: Loc) =
  ## An ARCHON's job: stamp the rally point so a fighter born forty rounds
  ## later knows where the war is without walking to find it.
  if not w.mayBroadcast(r): return
  r.lastBroadcast = w.currentRound
  discard w.broadcast(r, ChRallyX, int(target.x * 10'f32))
  discard w.broadcast(r, ChRallyY, int(target.y * 10'f32))
  discard w.broadcast(r, ChRallyStamp, w.currentRound)

proc readRally*(w: World, s: Side, r: Robot): Loc =
  ## The stamped rally point when it is fresh, else the enemy base -- which
  ## is public from round 1 anyway, so a chassis is never blind.
  let stamp = w.readChannel(r, ChRallyStamp)
  if stamp > 0 and w.currentRound - stamp <= RallyMaxAge:
    let x = float32(w.readChannel(r, ChRallyX)) / 10'f32
    let y = float32(w.readChannel(r, ChRallyY)) / 10'f32
    if x != 0'f32 or y != 0'f32:
      return loc(x, y)
  s.enemyBase(r.loc)

proc postThreat*(w: World, s: Side, r: Robot, here: Loc, count: int) =
  ## A picket's report: how many enemies it can see, in the cell it sees them
  ## from. Never from a scout deep in enemy territory (`scout.nim` checks
  ## that before calling).
  if not w.mayBroadcast(r): return
  r.lastBroadcast = w.currentRound
  let cell = (int(here.x) div 8) * 16 + (int(here.y) div 8)
  discard w.broadcast(r, ChThreat + (cell mod 20), count)
