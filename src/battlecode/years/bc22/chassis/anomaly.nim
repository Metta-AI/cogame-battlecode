## `chassis/anomaly.nim` — `plan()`, the axis the idea is actually asking about.
##
## `anomaly_play: ignore` never reads `getAnomalySchedule()` at all; the faction
## plays as if the world were stable, which is what the whole 2022 human meta
## did. `anomaly_play: time_pushes` reads the schedule at the start of every
## round and raises five requests, each of which the engine ACTUALLY rewards and
## each of which was measured (§The game, divergences 5-8):
##
## (a) **before a FURY** — which only damages TURRET-mode buildings and
##     truncates — transform every building whose transform counter is ready to
##     PORTABLE on round `r - 11` and back on `r + 1`. The archons lose about
##     twenty turns of building and take **zero**;
## (b) **before a CHARGE**, scatter droids so no friendly robot sees more than
##     four others, because the ranking is over the COMBINED droid population
##     and the clumped side donates the victims;
## (c) **immediately after a CHARGE**, push with the strike group, into an enemy
##     that just lost its densest 5 %;
## (d) **before an ABYSS**, spend the reserve down rather than hold it (10 % of
##     the bank, gone) and stop mining squares above 9 Pb, which lose nothing;
## (e) **before a VORTEX**, relocate any archon whose square is about to become
##     high-rubble under the map's own symmetry — computable exactly, because
##     the reflection is deterministic for HORIZONTAL and VERTICAL maps and one
##     of three known permutations for ROTATIONAL.
##
## The first-place bot does only (e). Behaviour sourced from
## `iliao2345/Battlecode2022` `src/fury_fix_20/` (AGPL-3.0) for the pre-vortex
## relocation; the other four are this coworld's own reading of the measured
## engine, and `docs/RULES-BC22.md` says so.
##
## EVERY REQUEST IS ADVISORY. No module is ever forced into an illegal or inert
## action by one, which is what keeps `anomaly_play` inside the anti-inert rule.

import ../anomaly as simAnomaly
import kit

export kit

const
  FuryLead* = 11
    ## Ten of a building's own turns of transform cooldown, plus one to be sure.
  ChargeLead* = 6
  AbyssLead* = 8
  VortexLead* = 20
  PushWindow* = 25

proc planAnomaly*(w: World, side: Side) =
  ## Refreshed once a round by `wololo.nim beginRound`.
  var req = AnomalyRequest(kind: anAbyss, round: -1, active: false)
  if side.doctrine.anomalyPlay == apIgnore:
    side.anomalyReq = req
    return
  let nxt = w.nextAnomaly()
  if nxt.has:
    req.kind = nxt.kind
    req.round = nxt.round
    req.active = true
    let away = nxt.round - w.currentRound
    case nxt.kind
    of anFury:
      req.standUp = away in 1 .. FuryLead
    of anCharge:
      req.scatter = away in 0 .. ChargeLead
    of anAbyss:
      req.spendDown = away in 0 .. AbyssLead
    of anVortex:
      req.relocate = away in 0 .. VortexLead
  ## Coming DOWN from a fury dodge, and pushing after a charge, both read the
  ## anomaly that just fired rather than the next one.
  if w.anomalyCursor > 0:
    let last = w.map.anomalies[w.anomalyCursor - 1]
    let since = w.currentRound - last.round
    if last.kind == anFury and since in 1 .. 3:
      req.standDown = true
    if last.kind == anCharge and since in 0 .. PushWindow:
      req.push = true
  side.anomalyReq = req

func dodgingFury*(side: Side): bool =
  side.doctrine.anomalyPlay == apTimePushes and side.anomalyReq.standUp

func scatteringForCharge*(side: Side): bool =
  side.doctrine.anomalyPlay == apTimePushes and side.anomalyReq.scatter

func pushingAfterCharge*(side: Side): bool =
  side.doctrine.anomalyPlay == apTimePushes and side.anomalyReq.push

func spendingDownForAbyss*(side: Side): bool =
  side.doctrine.anomalyPlay == apTimePushes and side.anomalyReq.spendDown

func relocatingForVortex*(side: Side): bool =
  side.doctrine.anomalyPlay == apTimePushes and side.anomalyReq.relocate

func abyssImmuneSquare*(amount: int): bool =
  ## `(int)(0.1f * amount)` is ZERO for any square holding nine or fewer, so a
  ## square at or under nine loses nothing to a global abyss. A faction spending
  ## down before one leaves those alone and mines the rich squares first.
  amount <= 9

proc vortexRubbleAt*(w: World, l: Loc): int =
  ## What the rubble at `l` becomes after the NEXT vortex, when that is
  ## computable. For a HORIZONTAL or a VERTICAL map the permutation is fixed; on
  ## a ROTATIONAL map it is one of two or three draws, so the chassis takes the
  ## WORST of them, which is the safe reading.
  case w.symmetry
  of symVertical:
    w.getRubble(loc(l.x, w.height - 1 - l.y))
  of symHorizontal:
    w.getRubble(loc(w.width - 1 - l.x, l.y))
  of symRotation:
    var worst = w.getRubble(loc(w.width - 1 - l.x, l.y))
    worst = max(worst, w.getRubble(loc(l.x, w.height - 1 - l.y)))
    if w.width == w.height:
      ## The 90-degree rotation the engine's `rotateRubble` performs.
      let rx = l.y
      let ry = (w.width - 1) - l.x
      if w.onTheMap(loc(rx, ry)):
        worst = max(worst, w.getRubble(loc(rx, ry)))
    worst

proc scatterTarget*(w: World, side: Side, r: Robot): Loc =
  ## Before a CHARGE: step away from the densest friendly cluster this robot can
  ## see. The ranking is over the COMBINED droid population, so a droid that
  ## sees four friends or fewer is never near the cut.
  var sumX = 0
  var sumY = 0
  var n = 0
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[r.kind].visionRadiusSquared):
    let other = w.getRobot(l)
    if other != nil and other.id != r.id and other.team == r.team and
       other.mode == rmDroid:
      sumX += l.x
      sumY += l.y
      n += 1
  if n <= 4: return r.loc
  let cx = sumX div n
  let cy = sumY div n
  loc(max(0, min(w.width - 1, r.loc.x + (r.loc.x - cx))),
      max(0, min(w.height - 1, r.loc.y + (r.loc.y - cy))))

proc noteDodge*(w: World, side: Side, how: string, saved: int) =
  w.stats.anomaliesDodged[ord(side.team)] += 1
  discard w.beat(BeatAnomalyDodged, "anomaly_dodged", ord(side.team),
                 ord(side.anomalyReq.kind), saved, how)
