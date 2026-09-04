## Signalling: the seven-int blockchain messages the chassis speaks, their fee
## model, and the plain-words table the endcard decodes them with.
##
## A message is `[SIGNAL_KEY, teamOrdinal, code, p0, p1, p2, p3]`, submitted at
## a fee of `max(1, teamSoup / 200)` and only when `teamSoup > 120`, so the
## blockchain never starves the build.
##
## `SIGNAL_KEY` is a FIXED CONSTANT SHARED BY BOTH TEAMS, and that is
## deliberate: it reproduces the year's famous meta-gaming vector (both teams
## read every block) and it is what lets the endcard decode both sides'
## traffic. A team that wants privacy has to pay for it in obscurity, exactly
## as in 2020.

import kit

const
  SignalKey* = 0x50415041      ## "PAPA" — Bowl of Chowder's own convention
  SigHqLocation* = 1
  SigAnnounceSoup* = 2
  SigWallIn* = 3
  SigHqUnderAttack* = 4
  SigNeedDrones* = 5
    ## RESERVED. Nothing broadcasts it and `readBlocks` does not act on it: the
    ## Fulfillment Center builds off its own roster count. The code point is
    ## kept so the table's numbering — which every recorded message carries —
    ## does not move. §Divergences item 15 in `docs/RULES-BC20.md`.
  SigRushNow* = 6
  SigWallClosed* = 7

  SignalNames*: array[1 .. 7, string] = [
    "HQ_LOCATION", "ANNOUNCE_SOUP", "WALL_IN", "HQ_UNDER_ATTACK",
    "NEED_DRONES", "RUSH_NOW", "WALL_CLOSED"
  ]

proc signalName*(code: int): string =
  if code >= 1 and code <= 7: SignalNames[code] else: "CODE_" & $code

proc fee(w: World, side: Side): int =
  max(1, w.stats.soup[ord(side.team)] div 200)

proc broadcast*(w: World, side: Side, r: Robot, code: int,
                p0 = 0, p1 = 0, p2 = 0, p3 = 0): bool {.discardable.} =
  ## Submitting a transaction is NOT an action: no cooldown, no `isReady`
  ## check. It still costs soup, so it is gated on a healthy pool.
  if w.stats.soup[ord(side.team)] <= 120: return false
  let cost = fee(w, side)
  let message: array[TransactionLength, int] =
    [SignalKey, ord(side.team), code, p0, p1, p2, p3]
  if not w.canSubmitTransaction(r, cost): return false
  w.submitTransaction(r, message, cost)
  true

proc readBlocks*(w: World, side: Side, r: Robot) =
  ## Every block minted since this side last looked. Charged one credit per
  ## block read, exactly like a sense.
  while side.nextBlockToRead < w.currentRound:
    if not r.spend(1): return
    let minted = w.getBlock(side.nextBlockToRead)
    side.nextBlockToRead += 1
    for t in minted:
      if t.message[0] != SignalKey: continue
      if t.message[1] != ord(side.team): continue
      case t.message[2]
      of SigHqLocation:
        side.hqLoc = loc(t.message[3], t.message[4])
        side.hasHq = true
      of SigAnnounceSoup:
        let tip = loc(t.message[3], t.message[4])
        var known = false
        for existing in side.soupTips:
          if existing == tip: known = true
        if not known and side.soupTips.len < 8:
          side.soupTips.add(tip)
      of SigWallClosed:
        if not side.wallClosed:
          side.wallClosed = true
          side.wallClosedRound = w.currentRound
      of SigRushNow:
        side.rushLaunched = true
      else: discard
