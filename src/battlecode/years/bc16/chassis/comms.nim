## `bulwark`'s signal layer — and the one place 2016 is harder than every
## other year this repo ships: THERE IS NO SHARED ARRAY.
##
## A robot may send 5 BASIC signals a turn (position + id + team, any type)
## and an ARCHON or SCOUT may send 20 MESSAGE signals (two 32-bit ints), each
## costing 0.05 on BOTH counters inside twice its own sight radius and
## `0.05 + 0.03 * (r2/sightR2 - 2)` beyond it. **AND EVERY SIGNAL IS HEARD BY
## THE ENEMY TOO**, which is why this chassis encodes only what it is willing
## to disclose.
##
## The layout: word 1 packs `kind:4 | x:7 | y:7 | payload:14`, word 2 packs
## `round:12 | value:20`. Kinds: 0 den-sighting, 1 den-health,
## 2 neutral-sighting, 3 neutral-claim, 4 enemy-archon-sighting, 5 rally,
## 6 census, 7 clear-request, 8 quarantine-lane, 9 suicide-target.
##
## The chassis sends AT MOST one message signal per archon per turn and one
## basic signal per scout per five turns, at `r2 = 2 * sightR2` so the cost is
## the flat 0.05, and it never encodes anything whose disclosure to the enemy
## costs more than the coordination is worth: den health and rally points yes,
## archon posture no.
##
## A doctrine cannot redefine this layout, cannot set the radius and cannot
## add a kind (§Out of scope): in this year every signal is heard by the
## enemy, so exposing the layout would be exposing a channel a doctrine could
## use to leak information it should not have.

import ../world, ../signals
import kit

export kit

const
  KindDenSighting* = 0
  KindDenHealth* = 1
  KindNeutralSighting* = 2
  KindNeutralClaim* = 3
  KindEnemyArchonSighting* = 4
  KindRally* = 5
  KindCensus* = 6
  KindClearRequest* = 7
  KindQuarantineLane* = 8
  KindSuicideTarget* = 9

func packWord1*(kind: int, l: Loc, payload: int): int =
  ((kind and 0xF) shl 28) or ((l.x and 0x7F) shl 21) or
    ((l.y and 0x7F) shl 14) or (payload and 0x3FFF)

func packWord2*(round, value: int): int =
  ((round and 0xFFF) shl 20) or (value and 0xFFFFF)

func unpackKind*(word1: int): int = (word1 shr 28) and 0xF
func unpackLoc*(word1: int): Loc =
  loc((word1 shr 21) and 0x7F, (word1 shr 14) and 0x7F)
func unpackPayload*(word1: int): int = word1 and 0x3FFF

proc broadcastRally*(w: World, s: Side, r: Robot) =
  ## One message signal per archon per turn, at exactly twice its own sight
  ## radius so the charge is the flat 0.05 on both counters.
  if not canMessageSignal(r.kind): return
  if r.messageSignalCount >= 1: return
  if not r.spend(2): return
  let radius = 2 * r.kind.sightRadiusSquared()
  let rally = if s.hasDenTarget: s.denTarget else: s.frontier
  if rally.x < 0: return
  w.doBroadcastMessage(r, packWord1(KindRally, rally, s.attackers),
                       packWord2(w.currentRound, s.counts[rtGuard]), radius)

proc scoutPing*(w: World, s: Side, r: Robot) =
  ## One basic signal per scout per five rounds: a position ping, which is
  ## all a basic signal carries anyway.
  if r.kind != rtScout: return
  if (w.currentRound mod 5) != 0: return
  if r.basicSignalCount >= 1: return
  if not r.spend(1): return
  w.doBroadcast(r, 2 * r.kind.sightRadiusSquared())

proc drainQueue*(w: World, s: Side, r: Robot) =
  ## Read the queue so it cannot overflow the 1000-entry cap, and take the
  ## rally point out of it. One credit per signal read.
  while r.signalQueue.len > 0:
    if not r.spend(1): break
    let got = r.readSignal()
    if not got.ok: break
    if not got.signal.hasMessage: continue
    if unpackKind(got.signal.m1) == KindRally:
      let at = unpackLoc(got.signal.m1)
      if at.x >= 0 and w.onTheMap(at):
        r.taskLoc = at
        r.hasTask = true
