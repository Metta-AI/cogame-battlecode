## `chassis/comms.nim` — what the clan actually SAYS over the engine's
## message channel.
##
## The engine gives us a 32-bit word, a 5-round buffer, robot<->tower only,
## one message per robot turn and twenty per tower turn — and a robot may only
## speak to a tower it is CONNECTED TO BY ITS OWN PAINT. Towers may broadcast
## to friendly towers within r2 <= 80 with no paint at all.
##
## The word format is the chassis's and A DOCTRINE CANNOT REDEFINE IT (§Out of
## scope): the knobs steer what gets said, never the encoding. The packer and
## the eight kinds live in `years/bc25/comms.nim` beside the engine's own
## message rules; this file is the policy that uses them.
##
## Behaviour ported from `erikji/battlecode25` `src/SPAARK/` (AGPL-3.0, head
## `63165da`): the ruin-claim word and the tower relay.

import kit, econ

export kit, econ

proc soldierReport*(w: World, side: Side, r: Robot) =
  ## One message per robot turn, and only when we are standing on our own
  ## paint with a path to a tower — which is exactly why the chassis paints
  ## connected blobs. The BFS behind `canSendMessage` is charged one
  ## `DecisionOps` credit per node expanded, so a chatty clan pays for its own
  ## chatter.
  if r.sentMessages >= MaxMessagesSentRobot: return
  if not paintIsTeam(w.getPaint(r.loc), side.team): return
  if not r.spend(20): return
  let word =
    if r.hasClaim:
      packWord(mkRuinClaimed, r.claimed.x, r.claimed.y,
               w.currentRound mod 256, ord(r.claimedKind))
    else:
      let front = frontierFor(w, side)
      packWord(mkFrontier, front.x, front.y, w.currentRound mod 256, 0)
  for l in w.locationsWithinRadiusSquared(r.loc, MessageRadiusSquared):
    if not r.spend(1): break
    let bot = w.getRobot(l)
    if bot == nil or bot.team != side.team: continue
    if not bot.kind.isTowerType(): continue
    if not w.canSendMessage(r, l, r): continue
    w.doSendMessage(r, l, word)
    return

proc towerRelay*(w: World, side: Side, r: Robot) =
  ## A tower relays the clan's frontier to every friendly tower within
  ## r2 <= 80 — no paint required, one message against the twenty-per-turn
  ## cap. It is what keeps two halves of a split clan building toward the same
  ## place.
  if r.sentMessages >= MaxMessagesSentTower: return
  if w.currentRound mod 8 != 0: return
  if not r.spend(4): return
  if not w.canBroadcastMessage(r): return
  let front = frontierFor(w, side)
  w.doBroadcastMessage(r,
    packWord(mkFrontier, front.x, front.y, w.currentRound mod 256,
             min(511, w.stats.towers[ord(side.team)])))

proc readFrontier*(w: World, side: Side, r: Robot): Loc =
  ## The most recent frontier word in this unit's buffer, if any. A unit that
  ## has heard nothing keeps its own reading.
  result = loc(-1, -1)
  var newest = -1
  for m in readMessages(r):
    if not r.spend(1): break
    let parts = unpackWord(m.bytes)
    if parts.kind != mkFrontier: continue
    if m.round > newest:
      newest = m.round
      result = loc(parts.x, parts.y)
