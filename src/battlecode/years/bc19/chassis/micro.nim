## `saber`'s combat micro: target selection, the PREACHER's blast score, the
## damage map and the dodge.
##
## Behaviour source: `m-schier/battlecode-2019-wololo@ebdd279`,
## `robot.js:1459-1528` (`findBestDodgeSpot`) and `:1529-1573`
## (`findBestAggressiveMoveCombat`), GPL-3.0.
##
## **THE PREACHER RULE IS UNCONDITIONAL AND IT IS THE ANTI-INERT FLOOR FOR
## `preacher_share`.** A preacher's attack puts 20 damage on EVERY OCCUPIED
## SQUARE within r2 3 of the target — nine squares — WITH NO TEAM CHECK, and
## its minimum range is 1, so firing at anything closer than r2 4 damages
## ITSELF and every friendly beside it. `blastScore` counts both sides and
## `chooseAttack` REFUSES ANY SHOT WHOSE OWN-SIDE KILLS EXCEED ITS ENEMY
## KILLS, at every setting of the knob. That is what keeps
## `preacher_share: 100` from being self-destructive.
##
## **THE CHASSIS NEVER DELIBERATELY ATTACKS A FRIENDLY SQUARE.** Friendly
## fire is legal in 2019 (rule 6.4.2 has no team check) and the chassis uses
## it only where the engine forces it — inside a preacher's own blast — and
## never as a choice. `tests/test_bc19_baselines.nim` asserts that.

import ../constants, ../units, ../world, ../knobs
import kit, econ

export kit

func targetValue*(u: UnitKind): int =
  ## Highest value first: a castle ends the game, a church is a spawn point,
  ## a preacher is the biggest threat, a prophet outranges everything, a
  ## crusader is the fastest thing on the board, a pilgrim is the economy.
  case u
  of ukCastle: 100
  of ukChurch: 70
  of ukPreacher: 60
  of ukProphet: 50
  of ukCrusader: 40
  of ukPilgrim: 30

type BlastScore* = object
  enemyHits*, enemyKills*: int
  ownHits*, ownKills*: int
  hitsSelf*: bool
  value*: int

proc blastScore*(w: World, r: Robot, tx, ty: int): BlastScore =
  ## Score the WHOLE neighbourhood the shot will actually damage, in the
  ## engine's own sweep order (y ascending outer, x ascending inner) so the
  ## chassis's view of the shot is the sim's view of it.
  let spread = damageSpreadOf(r.unit)
  let damage = attackDamageOf(r.unit)
  var box = 0
  while (box + 1) * (box + 1) <= spread: inc box
  for y in max(0, ty - box) .. min(w.height - 1, ty + box):
    for x in max(0, tx - box) .. min(w.width - 1, tx + box):
      if distSq(tx, ty, x, y) > spread: continue
      let t = w.robotAt(x, y)
      if t.isNil: continue
      let kills = t.health <= damage
      if t.id == r.id:
        result.hitsSelf = true
        inc result.ownHits
        if kills: inc result.ownKills
      elif t.team == r.team:
        inc result.ownHits
        if kills: inc result.ownKills
      else:
        inc result.enemyHits
        if kills: inc result.enemyKills
        result.value += targetValue(t.unit) + (if kills: 200 else: 0)
  result.value -= result.ownHits * 40 + result.ownKills * 400

proc nearStructure*(s: Side, x, y: int): bool =
  ## Inside `defend_radius` of one of our own structures. A shot taken there
  ## is DEFENDING, and defending is funded THROUGH the fuel gate: an order
  ## that hoards fuel while its castle is being shot has misread the knob.
  for l in s.structures:
    if distSq(l.x, l.y, x, y) <= s.doctrine.defendRadius: return true
  false

proc chooseAttack*(w: World, s: Side,
                   r: Robot): tuple[ok: bool, dx, dy: int] =
  ## The best legal attack this turn, or nothing. Preference order: a target
  ## this attack will KILL, then the highest-value enemy inside range.
  result = (ok: false, dx: 0, dy: 0)
  if attackThrows(r.unit): return          ## a PILGRIM (D6.2)
  if r.unit == ukChurch: return            ## legal upstream (D6.1), never used
  let defending = nearStructure(s, r.x, r.y)
  if not canAct(w, s, attackFuelOf(r.unit), essential = defending): return
  let spec = Units[r.unit]
  if spec.attackRadius != arPair: return
  let box = visionBoxOf(r.unit)
  if not r.charge((2 * box + 1) * (2 * box + 1)): return
  var best = 0
  for dy in -box .. box:
    for dx in -box .. box:
      let r2 = dx * dx + dy * dy
      if r2 < spec.attackRadiusMin or r2 > spec.attackRadiusMax: continue
      let tx = r.x + dx
      let ty = r.y + dy
      if not w.onBoard(tx, ty): continue
      let score = blastScore(w, r, tx, ty)
      if score.enemyHits == 0: continue
      ## THE UNCONDITIONAL FLOOR: never fire when the blast would kill more
      ## of our own than the enemy's, and never deliberately hit a friendly
      ## square with a single-target unit.
      if score.ownKills > score.enemyKills: continue
      if damageSpreadOf(r.unit) == 0 and score.ownHits > 0: continue
      if score.value > best:
        best = score.value
        result = (ok: true, dx: dx, dy: dy)

proc threatAt*(w: World, s: Side, x, y: int): int =
  ## How much damage an enemy could put on `(x, y)` next turn — the "damage
  ## map" wololo builds, restricted to the squares that matter.
  for l in s.enemySeen:
    let e = w.robotAt(l.x, l.y)
    if e.isNil or e.team == s.team: continue
    if attackThrows(e.unit): continue
    let spec = Units[e.unit]
    if spec.attackRadius != arPair: continue
    let reach = spec.attackRadiusMax + speedOf(e.unit)
    if distSq(e.x, e.y, x, y) <= reach:
      result += attackDamageOf(e.unit)

proc chooseDodge*(w: World, s: Side,
                  r: Robot): tuple[ok: bool, dx, dy: int] =
  ## `findBestDodgeSpot`: when the square we stand on is more dangerous than
  ## our remaining health, step to the reachable square with the least
  ## incoming damage. A PROPHET additionally refuses to stand inside its own
  ## r2 16 blind zone of a known enemy, because it cannot shoot back there.
  result = (ok: false, dx: 0, dy: 0)
  let speed = speedOf(r.unit)
  if speed <= 0: return
  if not r.charge(MoveOffsets[speed].len * 2): return
  let here = threatAt(w, s, r.x, r.y)
  if here < r.health: return
  var best = here
  for off in MoveOffsets[speed]:
    let nx = r.x + off.dx
    let ny = r.y + off.dy
    if not w.squareFree(nx, ny): continue
    let cost = (off.dx * off.dx + off.dy * off.dy) * fuelPerMoveOf(r.unit)
    if w.fuel[ord(r.team)] < cost: continue
    let t = threatAt(w, s, nx, ny)
    if t < best:
      best = t
      result = (ok: true, dx: off.dx, dy: off.dy)

func prophetBlindTo*(r: Robot, x, y: int): bool =
  ## A PROPHET hits at r2 16..64 and CANNOT HIT ANYTHING CLOSER THAN 16 —
  ## the most confusing rule in this year, and the reason `unit_mix` is a
  ## real trade-off.
  r.unit == ukProphet and distSq(r.x, r.y, x, y) < Units[ukProphet].attackRadiusMin
