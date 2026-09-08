## `lemonade`'s headquarters turn — AND IT USES ALL FIVE OF ITS ACTIONS.
##
## Behaviour ported from `awesomelemonade/Battlecode2023` `src/finalBot/`
## (AGPL-3.0): the anchor first, then the unit `econ.nim` asks for at the free
## passable tile nearest the frontier, then the census and the anchor claim on
## the shared array (a headquarters may always write).
##
## A HEADQUARTERS' ACTION COOLDOWN IS 2 AGAINST A `COOLDOWN_LIMIT` OF 10, so
## `isActionReady` (`< 10`) lets it act five times in one turn and refuses the
## sixth. A rich faction with two headquarters can therefore put ten robots on
## the board in a single round, and this file is where that actually happens:
## the loop runs while the headquarters is action-ready, not once.

import ../world, kit, econ, anchors, elixir, comms as chcomms

export kit

proc runHeadquarters*(w: World, side: Side, hq: Robot) =
  w.observe(side, hq)
  ## The anchor programme gets the FIRST action, not what the build queue
  ## leaves over.
  if hq.isActionReady():
    discard buildAnchorIfDue(w, side, hq)

  var built = 0
  while hq.isActionReady() and built < 8:
    if not hq.spend(4): break
    let kind = nextBuild(w, side, hq)
    if kind == rtHeadquarters: break
    let toward =
      if side.enemyHqs.len > 0: side.nearestEnemyHome(hq.loc) else: hq.loc
    let target = w.freeTileNear(side, hq.loc, toward)
    if target.x < 0: break
    if w.doBuildRobot(hq, kind, target) == nil: break
    built += 1
    side.carriers = w.robotCountByType(side.team, rtCarrier)
    side.launchers = w.robotCountByType(side.team, rtLauncher)
    side.amplifiers = w.robotCountByType(side.team, rtAmplifier)
    if built == 1:
      w.noteFirstAction(side.team, Bc23ActionBuildRobot)

  ## A headquarters may always write, and it is the cheapest broadcaster the
  ## faction has.
  chcomms.publish(w, side, hq)
