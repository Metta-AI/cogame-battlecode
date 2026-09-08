## Messages: the 5-round buffers, the robot<->tower send rule, the paint
## connectivity gate, and `broadcastMessage`.
##
## Ported from `world/RobotControllerImpl.java`'s `assertCanSendMessage`,
## `sendMessage`, `readMessages`, `assertCanBroadcastMessage` and
## `broadcastMessage`, plus `InternalRobot.cleanMessages`.
##
## Four things in here look like details and are not:
##
## * **ONLY robot<->tower.** `this.robot.getType().isRobotType() ==
##   getRobot(loc).getType().isRobotType()` is refused, so robot<->robot and
##   tower<->tower sends are both illegal. `broadcastMessage` is the ONLY
##   tower<->tower channel and it is a separate method with its own rules.
## * **A send needs a PAINT PATH.** `connectedByPaint(team, robotLoc,
##   towerLoc)` is a 4-neighbour BFS over the sending team's own colour that
##   REFUSES TO START if the robot is not standing on team paint. That is why
##   a competent chassis paints connected blobs rather than confetti: the blob
##   is the telephone line. A BROADCAST needs none of it.
## * **The caps are per TURN, not per round**: 1 for a robot, 20 for a tower,
##   reset in `processBeginningOfTurn`. A broadcast counts as ONE message
##   however many towers it reaches.
## * **`cleanMessages` runs at the start of the ROUND, not the turn**, and
##   drops everything whose round is `<= currentRound - 5`.

import world

export world

proc cleanMessages*(w: World, r: Robot) =
  ## `InternalRobot.cleanMessages`, called from `processBeginningOfRound`.
  ## The buffer is a FIFO and the engine pops from the front while the front
  ## is stale, so a `while` on the head is the faithful port.
  var head = 0
  while head < r.inbox.len and
      r.inbox[head].round <= w.currentRound - MessageRoundDuration:
    head += 1
  if head > 0:
    r.inbox = r.inbox[head .. ^1]

func readMessages*(r: Robot, roundNum = -1): seq[Message] =
  for m in r.inbox:
    if roundNum == -1 or m.round == roundNum:
      result.add(m)

proc canSendMessage*(w: World, r: Robot, l: Loc, charge: Robot = nil): bool =
  if not w.canActLocation(r, l, MessageRadiusSquared): return false
  let target = w.getRobot(l)
  if target == nil: return false
  if target.team != r.team: return false
  if r.kind.isRobotType() == target.kind.isRobotType(): return false
  if r.kind.isRobotType():
    if r.sentMessages >= MaxMessagesSentRobot: return false
  else:
    if r.sentMessages >= MaxMessagesSentTower: return false
  let robotLoc = if r.kind.isTowerType(): l else: r.loc
  let towerLoc = if r.kind.isTowerType(): r.loc else: l
  w.connectedByPaint(r.team, robotLoc, towerLoc, charge)

proc doSendMessage*(w: World, r: Robot, l: Loc, content: int) =
  if not w.canSendMessage(r, l):
    w.refusedActions += 1
    return
  let target = w.getRobot(l)
  target.inbox.add(Message(bytes: content, senderId: r.id,
                           round: w.currentRound))
  r.sentMessages += 1
  w.stats.messagesSent[ord(r.team)] += 1
  w.noteFirstAction(r, Bc25ActionMessage)

func canBroadcastMessage*(w: World, r: Robot): bool =
  if r.kind.isRobotType(): return false
  r.sentMessages < MaxMessagesSentTower

proc doBroadcastMessage*(w: World, r: Robot, content: int) =
  ## Every FRIENDLY TOWER within r2 <= 80, in engine scan order, with NO
  ## paint-connectivity requirement, counting as one message against the cap.
  if not w.canBroadcastMessage(r):
    w.refusedActions += 1
    return
  let message = Message(bytes: content, senderId: r.id, round: w.currentRound)
  for l in w.locationsWithinRadiusSquared(r.loc, BroadcastRadiusSquared):
    let target = w.getRobot(l)
    if target != nil and target.kind.isTowerType() and
        target.team == r.team and target.id != r.id:
      target.inbox.add(message)
  r.sentMessages += 1
  w.stats.messagesSent[ord(r.team)] += 1
  w.noteFirstAction(r, Bc25ActionBroadcast)

# ---------------------------------------------------------------------------
#  The chassis's own 32-bit word
# ---------------------------------------------------------------------------

type
  MessageKind* = enum
    ## `[kind:3][x:6][y:6][round8:8][payload:9]` — the chassis's encoding, not
    ## the engine's. A doctrine cannot redefine it: the knobs steer WHAT gets
    ## said, never the encoding (§Out of scope).
    mkFrontier = 0
    mkRuinClaimed
    mkTowerLost
    mkEnemyMass
    mkSrpHere
    mkRefillHere
    mkChoke
    mkRetreat

func packWord*(kind: MessageKind, x, y, round8, payload: int): int =
  ((ord(kind) and 7) shl 29) or
  ((x and 63) shl 23) or
  ((y and 63) shl 17) or
  ((round8 and 255) shl 9) or
  (payload and 511)

func unpackWord*(word: int): tuple[kind: MessageKind, x, y, round8,
                                   payload: int] =
  (kind: MessageKind((word shr 29) and 7),
   x: (word shr 23) and 63,
   y: (word shr 17) and 63,
   round8: (word shr 9) and 255,
   payload: word and 511)
