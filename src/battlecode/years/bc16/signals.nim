## The bc16 signal layer: the per-robot FIFO queue, the per-turn counters, the
## broadcast walk over ALL FOUR TEAMS and the two-counter delay charge.
##
## Ported from `world/InternalRobot.java:339-357` (the queue and the two
## counters), `world/RobotControllerImpl.java:590-634` (`readSignal`,
## `emptySignalQueue`, `broadcastSignal`, `broadcastMessageSignal`) and
## `world/GameWorld.java:798-822` (`visitBroadcastSignal`) at commit
## `11a0b09f26a70da19f33a61ebec4ceaf6e161aa3`.
##
## **THIS IS THE ONE PLACE 2016 IS HARDER THAN EVERY OTHER YEAR THIS REPO
## SHIPS: THERE IS NO SHARED ARRAY.** A robot may send 5 BASIC signals a turn
## (position + id + team, any type) and an ARCHON or a SCOUT may send 20
## MESSAGE signals (two 32-bit ints). Each costs
## `0.05 + 0.03 * max(0, r2/sightR2 - 2)` ON BOTH COUNTERS — a flat 0.05
## inside twice your own sight radius — and **EVERY SIGNAL IS HEARD BY THE
## ENEMY TOO**: the recipient walk keeps every robot of every team inside the
## radius except the sender.
##
## The queue is capped at `SIGNAL_QUEUE_MAX_SIZE = 1000` with THE OLDEST
## DROPPED (`signalqueue.remove(0)`), `readSignal` pops the head, and
## `emptySignalQueue` drains in order.
##
## ONE ORDERING NOTE. The engine picks its recipients through
## `getAllRobotsWithinRadiusSq`, which has three branches (`radius == 0`,
## `radius < 16` box scan, `radius >= 16` full insertion-order walk). THE SET
## IS THE SAME IN ALL THREE and each recipient receives exactly once, so only
## the order in which the queues are appended to differs — and no rule and no
## chassis can observe that, because each queue is per robot. This port uses
## the insertion-order walk for all radii and says so here rather than
## reproducing three branches with one behaviour.

import world

export world

proc receiveSignal*(r: Robot, s: Signal) =
  ## `InternalRobot.receiveSignal`: append, then drop the OLDEST if the queue
  ## is now over 1000.
  r.signalQueue.add(s)
  if r.signalQueue.len > SignalQueueMaxSize:
    r.signalQueue.delete(0)

proc readSignal*(r: Robot): tuple[ok: bool, signal: Signal] =
  ## `retrieveNextSignal`: pops the head, or nothing on an empty queue.
  if r.signalQueue.len == 0:
    return (ok: false, signal: Signal())
  let head = r.signalQueue[0]
  r.signalQueue.delete(0)
  (ok: true, signal: head)

proc emptySignalQueue*(r: Robot): seq[Signal] =
  ## `retrieveAllSignals`: drains in order.
  result = r.signalQueue
  r.signalQueue.setLen(0)

func canBroadcast*(w: World, r: Robot, radiusSquared: int): bool =
  ## `broadcastSignal`: a NEGATIVE radius is refused, and the per-turn count
  ## is capped at 5. There is no readiness test — a broadcast costs delay, it
  ## does not require the absence of it.
  radiusSquared >= 0 and r.basicSignalCount < BasicSignalsPerTurn

func canBroadcastMessage*(w: World, r: Robot, radiusSquared: int): bool =
  ## `broadcastMessageSignal`: ARCHON and SCOUT only, non-negative radius,
  ## and at most 20 a turn.
  canMessageSignal(r.kind) and radiusSquared >= 0 and
    r.messageSignalCount < MessageSignalsPerTurn

proc deliver(w: World, r: Robot, radiusSquared: int, s: Signal) =
  for id in w.execOrder:
    if not w.robotsById.hasKey(id): continue
    let other = w.robotsById[id]
    if other.id == r.id: continue
    if other.loc.distanceSquaredTo(r.loc) <= radiusSquared:
      other.receiveSignal(s)
  ## `x = radius / (double) sensorRadiusSquared - 2`, then
  ## `0.05 + 0.03 * max(0, x)` added to BOTH counters. A ZOMBIE's
  ## `sensorRadiusSquared` is -1, which makes `x` negative and the charge the
  ## flat base — and no zombie ever broadcasts anyway.
  let increase = broadcastDelayIncrease(radiusSquared,
                                        r.kind.sightRadiusSquared())
  r.d.addCoreDelay(increase)
  r.d.addWeaponDelay(increase)

proc doBroadcast*(w: World, r: Robot, radiusSquared: int): bool
    {.discardable.} =
  if not w.canBroadcast(r, radiusSquared):
    w.refusedActions += 1
    return false
  w.deliver(r, radiusSquared,
            Signal(x: r.loc.x, y: r.loc.y, senderId: r.id, team: r.team,
                   hasMessage: false))
  r.basicSignalCount += 1
  if r.team.isPlayer():
    w.stats.basicSignals[ord(r.team)] += 1
  w.noteFirstAction(r, Bc16ActionBroadcast)
  true

proc doBroadcastMessage*(w: World, r: Robot, m1, m2,
                         radiusSquared: int): bool {.discardable.} =
  if not w.canBroadcastMessage(r, radiusSquared):
    w.refusedActions += 1
    return false
  w.deliver(r, radiusSquared,
            Signal(x: r.loc.x, y: r.loc.y, senderId: r.id, team: r.team,
                   hasMessage: true, m1: m1, m2: m2))
  r.messageSignalCount += 1
  if r.team.isPlayer():
    w.stats.messageSignals[ord(r.team)] += 1
  w.noteFirstAction(r, Bc16ActionBroadcastMessage)
  true
