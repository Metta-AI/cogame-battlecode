## `saber`'s two communication channels.
##
## Behaviour source: `m-schier/battlecode-2019-wololo@ebdd279`,
## `robot.js:36-51` (`RADIO_PRIO`, `CASTLETALK_PRIO`) and `:206-391` (the
## encoders), GPL-3.0.
##
## **THIS YEAR IS HARDER THAN THE OTHERS: THERE IS NO SHARED ARRAY.** The
## RADIO is a 16-bit value whose fuel cost is `ceil(sqrt(r2))`, and EVERY
## UNIT OF BOTH TEAMS inside the radius reads it along with the sender's id
## and position but NOT its team (`docs.js:164`). So the layout has to be
## worth leaking, and the chassis broadcasts AT MOST ONE RADIO MESSAGE PER
## UNIT PER FIVE TURNS and sizes the radius to the smallest that reaches the
## intended listener.
##
## CASTLE TALK is 8 bits, FREE, unlimited range and readable only by
## own-team CASTLES, one value per unit per turn.

import ../constants, ../units, ../world, ../knobs
import kit, econ

export kit

const
  RadioHold* = 0
  RadioScoutReport* = 1
  RadioTarget* = 2
  RadioCharge* = 3
  RadioRepulse* = 4
  RadioDepotClaim* = 5
  RadioLatticeSlot* = 6
  RadioSaberGo* = 7
    ## wololo's own `RADIO_PRIO` set minus anything whose disclosure costs
    ## more than the coordination is worth.

  RadioCooldown* = 5

func encodeRadio*(kind, x, y, flag: int): int =
  ## `kind:3 | x:6 | y:6 | flag:1` — sixteen bits exactly.
  ((kind and 7) shl 13) or ((x and 63) shl 7) or ((y and 63) shl 1) or
    (flag and 1)

func radioKind*(value: int): int = (value shr 13) and 7
func radioX*(value: int): int = (value shr 7) and 63
func radioY*(value: int): int = (value shr 1) and 63
func radioFlag*(value: int): int = value and 1

func encodeCastleTalkPosition*(axis, v: int): int =
  ## Turn 1 and turn 2 carry `0b10 | x:6` then `0b11 | y:6`, so every castle
  ## learns every friendly structure's coordinates and can derive the
  ## enemy's by mirroring.
  ((2 or (axis and 1)) shl 6) or (v and 63)

func encodeCastleTalkCensus*(unit, bucket: int): int =
  ## `0b0 | unit:3 | bucket:4` — the rotating census digit that lets two
  ## castles divide one build queue without duplicating it.
  ((unit and 7) shl 4) or (bucket and 15)

func encodeCastleTalkAlert*(alert: int): int =
  ## `0b01 | alert:6` — under-attack and castle-destroyed flags, which is
  ## what lets the surviving castles re-plan when one falls.
  (1 shl 6) or (alert and 63)

func isCastleTalkPosition*(v: int): bool = (v shr 7) == 1
func isCastleTalkAlert*(v: int): bool = (v shr 6) == 1
func isCastleTalkCensus*(v: int): bool = (v shr 7) == 0 and (v shr 6) != 1

proc castleTalkFor*(w: World, s: Side, r: Robot): int =
  ## `comms.nim castleTalk()`, laid out per `castle_talk_use`. It is FREE and
  ## it accompanies any action, so every unit sends one every turn.
  if r.turn == 1:
    return encodeCastleTalkPosition(0, r.x)
  if r.turn == 2:
    return encodeCastleTalkPosition(1, r.y)
  case s.doctrine.castleTalkUse
  of ct19Position:
    ## Nothing after the two position bytes: the channel stays quiet, which
    ## is the cheapest thing a doctrine can do with it.
    0
  of ct19Census:
    encodeCastleTalkCensus(ord(r.unit),
                           min(15, (case r.unit
                                    of ukPilgrim: s.pilgrims
                                    of ukCrusader: s.crusaders
                                    of ukProphet: s.prophets
                                    of ukPreacher: s.preachers
                                    else: s.castles + s.churches)))
  of ct19Full:
    ## The alert slot pre-empts the census on the turns it fires.
    let threatened =
      r.unit == ukCastle and s.enemySeen.len > 0 or
      r.health * 2 < startingHpOf(r.unit)
    if threatened:
      encodeCastleTalkAlert(min(63, s.enemySeen.len * 8 +
                                (if r.unit == ukCastle: 1 else: 0)))
    else:
      encodeCastleTalkCensus(ord(r.unit),
                             min(15, (case r.unit
                                      of ukPilgrim: s.pilgrims
                                      of ukCrusader: s.crusaders
                                      of ukProphet: s.prophets
                                      of ukPreacher: s.preachers
                                      else: s.castles + s.churches)))

proc radioFor*(w: World, s: Side, r: Robot): tuple[value, radius: int] =
  ## At most one radio message per unit per five turns, and the radius is the
  ## smallest that reaches the intended listener — because every enemy unit
  ## inside it reads the value too.
  result = (value: 0, radius: 0)
  if r.turn - r.lastRadio < RadioCooldown: return
  if s.enemySeen.len == 0: return
  let near = s.nearestEnemyUnit(r.x, r.y)
  if near.x < 0: return
  let home = s.nearestStructure(r.x, r.y)
  if home.x < 0: return
  let radius = min(MaxSignalRadius, distSq(r.x, r.y, home.x, home.y))
  let cost = signalCost(radius)
  if w.fuel[ord(s.team)] - s.fuelGate() < cost: return
  r.lastRadio = r.turn
  result = (value: encodeRadio(RadioScoutReport, near.x, near.y, 1),
            radius: radius)
