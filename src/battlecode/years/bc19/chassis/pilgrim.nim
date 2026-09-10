## A PILGRIM's turn: the mine / construct / dropoff state machine.
##
## Behaviour source: `m-schier/battlecode-2019-wololo@ebdd279`,
## `robot.js:68-74` (`WORKER_STATE`), GPL-3.0.
##
## Claim the nearest unclaimed depot, mine to capacity (NEVER PAST IT — a
## mine at capacity burns 1 fuel for nothing and is counted as
## `mine_actions_wasted`), walk to the nearest own structure, `give`
## everything, repeat; and take the `infiltrate.nim` job when it is
## scheduled.
##
## **THE PILGRIM IS THE WHOLE ECONOMY.** It is the only unit that can mine
## and the only unit that can build a CHURCH, it cannot attack at all
## (D6.2), and unrefined karbonite and fuel are UNSPENDABLE until a robot
## `give`s them to an adjacent CASTLE or CHURCH. An order whose pilgrims mine
## and never walk the load home has not played the game — which is exactly
## what `-d:bc19BrokenChassis` does, and exactly what the survival gate's
## `deposited >= 80 % of mined` clause catches.

import ../constants, ../units, ../world, ../knobs
import ../actions
import kit, econ, church, comms, infiltrate

export kit

const
  TaskMine* = 0
  TaskDeposit* = 1
  TaskChurch* = 2

proc adjacentStructure(w: World, s: Side, r: Robot): tuple[ok: bool, dx, dy: int] =
  ## An OWN castle or church next to us. The chassis NEVER `give`s to an
  ## enemy structure: it is legal (rule 6.6, no team check) and it is never a
  ## strategy.
  result = (ok: false, dx: 0, dy: 0)
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      let t = w.robotAt(r.x + dx, r.y + dy)
      if t.isNil: continue
      if t.team != s.team: continue
      if t.unit == ukCastle or t.unit == ukChurch:
        return (ok: true, dx: dx, dy: dy)

proc runPilgrim*(w: World, s: Side, r: Robot): Action =
  result = newAction()
  result.castleTalk = castleTalkFor(w, s, r)
  let radio = radioFor(w, s, r)
  result.signal = radio.value
  result.signalRadius = radio.radius

  let kFull = r.karbonite >= karboniteCapacityOf(ukPilgrim)
  let fFull = r.fuel >= fuelCapacityOf(ukPilgrim)
  let loaded = r.karbonite > 0 or r.fuel > 0

  ## --- the infiltration job ------------------------------------------------
  if r.role == RolePilgrimInfiltrator:
    if r.taskX < 0:
      let site = infiltrationSite(w, s, r)
      if site.ok:
        r.taskX = site.x
        r.taskY = site.y
    if r.taskX >= 0:
      if max(abs(r.x - r.taskX), abs(r.y - r.taskY)) <= 1 and
          canSpend(w, s, buildKarboniteOf(ukChurch), buildFuelOf(ukChurch),
                   essential = true):
        let square = freeBuildSquare(w, s, r, Loc(x: r.taskX, y: r.taskY))
        if square.ok:
          s.commit(buildKarboniteOf(ukChurch), buildFuelOf(ukChurch))
          r.role = RolePilgrimMiner
          r.taskX = -1
          r.taskY = -1
          result.hasAction = true
          result.kind = akBuild
          result.dx = square.dx
          result.dy = square.dy
          result.buildUnit = ukChurch
          return
      else:
        let step = stepToward(w, r, r.taskX, r.taskY, navFastest)
        if step.ok:
          result.hasAction = true
          result.kind = akMove
          result.dx = step.dx
          result.dy = step.dy
          return

  ## --- raise a church ------------------------------------------------------
  if r.task == TaskChurch and r.taskX >= 0:
    if max(abs(r.x - r.taskX), abs(r.y - r.taskY)) <= 1:
      let square = freeBuildSquare(w, s, r, Loc(x: r.taskX, y: r.taskY))
      if square.ok and
          canSpend(w, s, buildKarboniteOf(ukChurch), buildFuelOf(ukChurch),
                   essential = true):
        s.commit(buildKarboniteOf(ukChurch), buildFuelOf(ukChurch))
        r.task = TaskMine
        r.taskX = -1
        r.taskY = -1
        result.hasAction = true
        result.kind = akBuild
        result.dx = square.dx
        result.dy = square.dy
        result.buildUnit = ukChurch
        return
      r.task = TaskMine
      r.taskX = -1
      r.taskY = -1
    else:
      let step = stepToward(w, r, r.taskX, r.taskY, navEconomic)
      if step.ok:
        result.hasAction = true
        result.kind = akMove
        result.dx = step.dx
        result.dy = step.dy
        return

  ## --- deposit -------------------------------------------------------------
  if (kFull or fFull or (loaded and r.task == TaskDeposit)) and
      not w.brokenChassis:
    r.task = TaskDeposit
    let adj = adjacentStructure(w, s, r)
    if adj.ok:
      r.task = TaskMine
      result.hasAction = true
      result.kind = akGive
      result.dx = adj.dx
      result.dy = adj.dy
      result.giveK = min(r.karbonite, MaxGiveAmount)
      result.giveF = min(r.fuel, MaxGiveAmount)
      return
    let home = s.nearestStructure(r.x, r.y)
    if home.x >= 0:
      let step = stepToward(w, r, home.x, home.y, navEconomic)
      if step.ok:
        w.stats.pilgrimWalk[ord(s.team)] += 1
        result.hasAction = true
        result.kind = akMove
        result.dx = step.dx
        result.dy = step.dy
        return

  ## --- consider raising a church instead -----------------------------------
  if r.task == TaskMine and not loaded and wantsChurch(w, s, w.round) and
      canSpend(w, s, buildKarboniteOf(ukChurch), buildFuelOf(ukChurch),
               essential = true):
    let site = bestChurchSite(w, s, r)
    if site.ok:
      r.task = TaskChurch
      r.taskX = site.x
      r.taskY = site.y

  ## --- mine ----------------------------------------------------------------
  let here = s.depotAt(r.x, r.y)
  if here >= 0:
    let wantK = s.depots[here].kind == dkKarbonite
    ## `mine` costs 1 fuel and the engine REFUSES it when the team cannot
    ## pay — and a refused action is a refused action, which is what the
    ## `refused_actions == 0` gate on this chassis measures.
    if w.fuel[ord(s.team)] >= MineFuelCost and
        ((wantK and not kFull) or (not wantK and not fFull)):
      result.hasAction = true
      result.kind = akMine
      return
    ## At capacity: walk the load home rather than burn a fuel for nothing.
    r.task = TaskDeposit
    let home = s.nearestStructure(r.x, r.y)
    if home.x >= 0:
      let step = stepToward(w, r, home.x, home.y, navEconomic)
      if step.ok:
        result.hasAction = true
        result.kind = akMove
        result.dx = step.dx
        result.dy = step.dy
        return

  ## --- walk to a depot -----------------------------------------------------
  var idx = -1
  if r.taskX >= 0 and r.task == TaskMine:
    idx = s.depotAt(r.taskX, r.taskY)
    if idx >= 0 and s.depots[idx].claimedBy != 0 and
        s.depots[idx].claimedBy != r.id:
      idx = -1
  if idx < 0:
    ## The economy floor: the first pilgrim takes karbonite, the second takes
    ## fuel, and after that the side alternates by the workers it already
    ## has — so an order ALWAYS has at least one of each once it has two
    ## pilgrims.
    let kw = karboniteWorkers(w, s)
    let fw = fuelWorkers(w, s)
    ## FUEL IS THE TIGHTER CONSTRAINT IN THIS YEAR. Karbonite has no passive
    ## income at all but it also has nothing to spend itself on once the
    ## build queue is satisfied, while fuel is burned by every move, every
    ## attack, every broadcast and every mine. So the roster tips toward
    ## fuel whenever the karbonite bank is already deep or the fuel store is
    ## inside three reserves of the floor.
    let fuelShort = w.fuel[ord(s.team)] < 3 * s.fuelGate() or
                    w.karbonite[ord(s.team)] > 200
    let want = if kw == 0: dkKarbonite
               elif fw == 0: dkFuel
               elif fuelShort and fw <= kw: dkFuel
               elif kw <= fw: dkKarbonite
               else: dkFuel
    idx = claimDepot(w, s, r, want, ownHalfOnly = true)
    if idx < 0:
      idx = claimDepot(w, s, r, (if want == dkKarbonite: dkFuel
                                 else: dkKarbonite), ownHalfOnly = true)
    if idx < 0:
      idx = claimDepot(w, s, r, want)
  if idx >= 0:
    r.taskX = s.depots[idx].x
    r.taskY = s.depots[idx].y
    let step = stepToward(w, r, r.taskX, r.taskY, navEconomic)
    if step.ok:
      result.hasAction = true
      result.kind = akMove
      result.dx = step.dx
      result.dy = step.dy
      return

  ## --- nothing better: stay out of the way of the castle's build squares ---
  let home = s.nearestStructure(r.x, r.y)
  if home.x >= 0 and distSq(r.x, r.y, home.x, home.y) <= 2:
    let step = stepToward(w, r, home.x + 3, home.y + 3, navEconomic)
    if step.ok:
      result.hasAction = true
      result.kind = akMove
      result.dx = step.dx
      result.dy = step.dy
