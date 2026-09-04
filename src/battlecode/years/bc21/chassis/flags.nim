## The 24-bit flag word both bc21 chassis speak.
##
## `[kind:3][x:6][y:6][payload:9]` — 24 bits exactly, which is
## `GameConstants.MAX_FLAG_VALUE`. Coordinates are map-relative and 6 bits,
## which is exactly enough for a 64-wide map (the spec's own `MAP_MAX_WIDTH`).
##
## THE WORD FORMAT IS SHARED BY BOTH TEAMS, deliberately: flags are readable
## across teams at any range for an Enlightenment Center, so a shared encoding
## reproduces the year's flag-decoding metagame, and it is what lets the
## endcard decode both sides' traffic. A doctrine cannot redefine it (the
## knobs steer what gets said, not the encoding).
##
## Ported from the multi-Center flag protocol of `BSreenivas0713/Battlecode2021`
## `src/musketeerplayerfinal/` (AGPL-3.0, commit d24af14) — behaviour, not code.

import ../world

type
  FlagKind* = enum
    fkSilent = 0
    fkNeutralEcHere = 1
    fkEnemyEcHere = 2
    fkSlandererSeen = 3
    fkUnderAttack = 4
    fkScoutDone = 5
    fkEcInfluenceHint = 6
    fkNeedDefence = 7

  FlagWord* = object
    kind*: FlagKind
    x*, y*: int
    payload*: int      ## 9 bits, meaning depends on `kind`

const MaxPayload* = 511

proc encodeFlag*(kind: FlagKind, l: Loc, payload = 0): int =
  ## Always inside [0, 16 777 215], so `setFlag` never refuses it.
  let px = clamp(l.x, 0, 63)
  let py = clamp(l.y, 0, 63)
  let pl = clamp(payload, 0, MaxPayload)
  (ord(kind) shl 21) or (px shl 15) or (py shl 9) or pl

proc decodeFlag*(word: int): FlagWord =
  if word <= 0 or word > MaxFlagValue:
    return FlagWord(kind: fkSilent)
  FlagWord(
    kind: FlagKind((word shr 21) and 0x7),
    x: (word shr 15) and 0x3F,
    y: (word shr 9) and 0x3F,
    payload: word and 0x1FF)

proc influenceHint*(influence: int): int =
  ## Nine bits cannot hold an Enlightenment Center's conviction, so the hint is
  ## a COARSE bucket: units of 8, saturating at 4088. A capture politician
  ## sized from a saturated hint is under-sized and the Center survives, which
  ## is the honest failure mode.
  clamp(influence div 8, 0, MaxPayload)

proc influenceFromHint*(payload: int): int = payload * 8
