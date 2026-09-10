## `saber`'s infiltration: `infiltrate.nim schedule()`, per
## `church_saber_round`.
##
## The emergent qualifier play the 2019 season produced, made a doctrine
## choice: a PILGRIM plus a two-unit escort committed to building a CHURCH
## INSIDE THE ENEMY'S HALF. The infiltrating church then builds units in
## their economy, and because it is a STRUCTURE it is also a deposit point
## for anything the escort reclaims off their pilgrims.
##
## It costs 50 karbonite, 200 fuel, a pilgrim and two escorts, and the escort
## has to survive a walk across the mirror — so it is a real investment with
## a real failure mode, and the abort rule below is part of the design rather
## than an afterthought.

import ../constants, ../units, ../world, ../knobs
import kit

export kit

const
  RolePilgrimMiner* = 0
  RolePilgrimInfiltrator* = 1
  RoleMilitaryField* = 0
  RoleMilitaryEscort* = 1
  RoleMilitaryLattice* = 2

func scheduled*(s: Side, round: int): bool =
  ## 0 means NEVER.
  s.doctrine.churchSaberRound > 0 and round >= s.doctrine.churchSaberRound

proc launch*(w: World, s: Side, round: int): bool =
  ## Committed at most once per game, and only when the order can actually
  ## pay for the church it is walking across the board.
  if s.infiltrateLaunched: return false
  if not scheduled(s, round): return false
  if s.pilgrims < 2: return false
  if w.karbonite[ord(s.team)] < buildKarboniteOf(ukChurch): return false
  if w.fuel[ord(s.team)] < buildFuelOf(ukChurch): return false
  s.infiltrateLaunched = true
  s.infiltrateRound = round
  true

proc abortIfLost*(w: World, s: Side) =
  ## The abort rule: if the infiltrating pilgrim died on the way, the escort
  ## goes back to being an ordinary field unit rather than walking into the
  ## enemy's castles on its own.
  if not s.infiltrateLaunched: return
  var alive = false
  for r in w.robots:
    if r.team == s.team and r.unit == ukPilgrim and
        r.role == RolePilgrimInfiltrator:
      alive = true
      break
  if not alive:
    for r in w.robots:
      if r.team == s.team and r.role == RoleMilitaryEscort:
        r.role = RoleMilitaryField
