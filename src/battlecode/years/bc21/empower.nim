## The speech and the exposure — `InternalRobot.empower`, `empowered`, and
## `expose`, ported branch for branch.
##
## EMPOWER IS THE WHOLE GAME, so its order of operations is written out here
## rather than inlined into `world.nim`:
##
##   1. charge the cooldown (`RobotControllerImpl.empower` does this first,
##      "for the sake of consistency" — the politician dies anyway);
##   2. collect every robot within `r^2` in MAP-SCAN ORDER (x ascending outer,
##      y ascending inner). This order is load-bearing: it fixes the order
##      conversions are queued and therefore the ids they are re-spawned with;
##   3. `numBots = |collected| - 1`; if 0, nobody is affected — but the
##      politician still dies;
##   4. `convictionToGive = conviction - 10` as a DOUBLE; if <= 0, nobody is
##      affected — but the politician still dies;
##   5. `convictionPerBot = convictionToGive / numBots`, and `buff` read ONCE;
##   6. per target: a friendly Center takes the split UNBUFFED; any other
##      Center takes it buffed only up to the point of conversion, with the
##      overflow crossing unbuffed; everything else takes it buffed;
##   7. `empowered(caller, (int) conv, ownTeam)` — TRUNCATION TOWARD ZERO;
##   8. the queued conversions are spawned in queue order, on the caller's
##      team, each keeping the destroyed robot's OLD PARENT POINTER, with a new
##      id and cooldown 0.
##
## The 2021.3.0.0 patch is in step 6 and nowhere else: the buff is LINEAR
## (`1 + 0.001*n`, not `1.001^n`), it does not apply to friendly Enlightenment
## Centers, and the 10-influence tax is taken BEFORE the buff is applied.

import world

proc getBuff*(w: World, team: Team): float64 =
  ## `TeamInfo.getBuff`: `1 + EXPOSE_BUFF_FACTOR * numBuffs`, a Java `double`
  ## multiplication against a `double` constant.
  if not team.isPlayer(): return 1.0
  1.0 + ExposeBuffFactor * float64(w.stats.numBuffs[ord(team)])

proc empowered(w: World, caller, bot: Robot, amountIn: int, newTeam: Team) =
  ## `InternalRobot.empowered`. Negative for a robot NOT on the empowering
  ## team; a Center takes influence-and-conviction, everything else takes
  ## conviction; a negative result converts or destroys.
  var amount = amountIn
  if bot.team != newTeam:
    amount = -amount

  if bot.kind == rtEnlightenmentCenter:
    w.addInfluenceAndConviction(bot, amount)
  else:
    addConviction(bot, amount)

  if bot.conviction < 0:
    if bot.kind.canBeConverted():
      w.conversionQueue.add(Conversion(
        parentId: bot.parentId,
        oldId: bot.id,
        oldTeam: bot.team,
        kind: bot.kind,
        influence: abs(bot.influence),
        conviction: -bot.conviction,
        loc: bot.loc))
    w.destroyRobot(bot.id)

proc empower*(w: World, caller: Robot, radiusSquared: int) =
  ## `InternalRobot.empower`. Does NOT self-destruct: the caller does that.
  w.conversionQueue.setLen(0)
  var collected: seq[Robot]
  for l in w.locationsWithinRadiusSquared(caller.loc, radiusSquared):
    let bot = w.getRobot(l)
    if bot != nil: collected.add(bot)

  let numBots = collected.len - 1        # excluding self
  if numBots == 0: return

  let convictionToGive = float64(caller.conviction) - float64(EmpowerTax)
  if convictionToGive <= 0: return

  var removedThisSpeech = 0
  let convictionPerBot = convictionToGive / float64(numBots)
  let buff = w.getBuff(caller.team)
  let callerTeam = caller.team
  let callerId = caller.id

  for bot in collected:
    if bot.id == callerId: continue
    if bot.dead: continue
    var conv = convictionPerBot
    if bot.kind == rtEnlightenmentCenter and bot.team == callerTeam:
      discard                            # unbuffed, do nothing
    elif bot.kind == rtEnlightenmentCenter:
      let convNeededToConvert = float64(bot.conviction) / buff
      if conv <= convNeededToConvert:
        conv = conv * buff
      else:
        conv = float64(bot.conviction) + (conv - convNeededToConvert)
    else:
      conv = conv * buff
    if callerTeam.isPlayer() and bot.team != callerTeam:
      w.stats.empowerConviction[ord(callerTeam)] += int(conv)
      removedThisSpeech += int(conv)
    w.empowered(caller, bot, int(conv), callerTeam)

  ## Step 8: the queued conversions, in queue order.
  var removed = 0
  var centersTaken = 0
  for c in w.conversionQueue:
    if c.kind == rtEnlightenmentCenter: inc centersTaken
  for c in w.conversionQueue:
    let id = w.spawnRobot(c.parentId, c.kind, c.loc, callerTeam, c.influence)
    let newBot = w.robotsById[id]
    if newBot.kind != rtEnlightenmentCenter:
      addConviction(newBot, c.conviction - newBot.conviction)
    else:
      ## `addInfluenceAndConviction(0)` snaps conviction to influence.
      w.addInfluenceAndConviction(newBot, 0)
      if callerTeam.isPlayer():
        w.stats.centersCaptured[ord(callerTeam)] += 1
        if not c.oldTeam.isPlayer():
          w.stats.neutralsCaptured[ord(callerTeam)] += 1
        ## "Clan Ash takes the 400-influence centre at 24,24"
        discard w.beat(BeatCenterTaken, "center_taken", ord(callerTeam),
          newBot.influence, c.loc.x * 100 + c.loc.y,
          (if c.oldTeam.isPlayer(): "opponent" else: "neutral"))
    if callerTeam.isPlayer():
      w.stats.conversions[ord(callerTeam)] += 1
      if c.kind == rtPolitician:
        w.stats.politiciansConverted[ord(callerTeam)] += 1
    w.emit("converted", id, ord(callerTeam), ord(c.kind), $c.oldId)
  ## An empower that CONVERTED A CENTRE or removed >= 200 enemy conviction is
  ## a beat; everything smaller stays a statistic.
  if callerTeam.isPlayer() and (centersTaken > 0 or removedThisSpeech >= 200):
    discard w.beat(BeatEmpowerBig, "empower_big", ord(callerTeam),
      caller.conviction, removedThisSpeech,
      $(numBots) & "/" & $(w.conversionQueue.len))
  removed = removedThisSpeech
  discard removed
  w.conversionQueue.setLen(0)

proc canEmpower*(r: Robot, radiusSquared: int): bool =
  if not isReady(r): return false
  if not r.kind.canEmpowerKind(): return false
  radiusSquared <= RobotSpecs[r.kind].actionRadiusSquared

proc doEmpower*(w: World, r: Robot, radiusSquared: int) =
  ## `RobotControllerImpl.empower`: charge the cooldown, empower, self-destruct.
  ## The self-destruct is UNCONDITIONAL — a politician that finds nobody in
  ## range, or that has 10 or less conviction, still dies.
  if not canEmpower(r, radiusSquared): return
  w.addCooldownTurns(r)
  if r.team.isPlayer():
    w.stats.empowers[ord(r.team)] += 1
  let conviction = r.conviction
  w.empower(r, radiusSquared)
  w.emit("empower", r.id, ord(r.team), conviction, $radiusSquared)
  w.destroyRobot(r.id)

# ---------------------------------------------------------------------------
#  Expose
# ---------------------------------------------------------------------------

proc canExpose*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanExpose(MapLocation)`: ready, a muckraker, the location on the
  ## map and inside `r^2 <= 12`, a robot there, of a type that can be exposed,
  ## on the enemy team. A camouflaged slanderer is a POLITICIAN by then and can
  ## no longer be exposed.
  if not isReady(r): return false
  if not r.kind.canExposeKind(): return false
  if not w.onTheMap(l): return false
  if not w.canSenseLocation(r, l): return false
  if not canActLocation(r, l): return false
  let bot = w.getRobot(l)
  if bot == nil: return false
  if not bot.kind.canBeExposed(): return false
  bot.team != r.team

proc expose*(w: World, r: Robot, l: Loc) =
  ## `RobotControllerImpl.expose` + `InternalRobot.expose`: charge the
  ## cooldown, add the slanderer's INFLUENCE to this team's pending buffs, and
  ## destroy the slanderer. The buff is applied at the end of the round and
  ## first affects speeches on the NEXT round.
  if not w.canExpose(r, l): return
  let bot = w.getRobot(l)
  w.addCooldownTurns(r)
  if r.team.isPlayer():
    w.stats.buffsToAdd[ord(r.team)] += bot.influence
    w.stats.exposes[ord(r.team)] += 1
  w.emit("expose", r.id, ord(r.team), bot.influence, $bot.id)
  w.destroyRobot(bot.id)
