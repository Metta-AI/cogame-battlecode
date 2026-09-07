## bc24 global upgrades: one point a team at 600, 1200 and 1800 and at no other
## round; an upgrade bought once, needing a point, costing nothing else and
## applying to the whole team immediately; ATTACK's +60 and HEALING's +50
## flowing through the FLOAT32 rounding; CAPTURING changing THE OPPONENT's
## return delay and THIS team's carry cooldown; and `ACTION` never offered.

import harness
import bc24_fixture
import battlecode/years/bc24/[rules, flags, skills]
import battlecode/sheet

let sheets = [defaultSheet("bc24"), defaultSheet("bc24")]

block:
  ## Points land at 600/1200/1800 and nowhere else. The loop plays real rounds
  ## with the weak chassis on both sides so nothing spends them.
  var w = bare(2000, withDam = false)
  var sides = newSides24(sheets, 0)
  let chassis = [ckExamplefuncsplayer24, ckExamplefuncsplayer24]
  var granted: seq[int]
  var last = 0
  for round in 1 .. 1900:
    runRound(w, sides, chassis)
    let now = w.stats.upgradePoints[0] + w.stats.upgrades[0][0].int +
              w.stats.upgrades[0][1].int + w.stats.upgrades[0][2].int
    if now > last:
      granted.add(round)
      last = now
  checkEq("points land at exactly 600, 1200 and 1800", granted,
    @[600, 1200, 1800])

block:
  var w = bare()
  w.postSetup()
  let r = w.placeDuck(teamA, loc(5, 5))
  check("no point, no upgrade", not w.canBuyGlobal(r, ugAttack))
  w.stats.upgradePoints[0] = 1
  check("with a point it is legal", w.canBuyGlobal(r, ugAttack))
  let crumbs = w.getCrumbs(teamA)
  let cd = r.actionCooldown
  w.doBuyGlobal(r, ugAttack)
  check("bought", w.hasUpgrade(teamA, 0))
  checkEq("the point is spent", w.stats.upgradePoints[0], 0)
  checkEq("it costs no crumbs", w.getCrumbs(teamA), crumbs)
  checkEq("and no cooldown", r.actionCooldown, cd)
  w.stats.upgradePoints[0] = 1
  check("and it cannot be bought twice", not w.canBuyGlobal(r, ugAttack))
  check("the OTHER team got nothing", not w.hasUpgrade(teamB, 0))

block:
  ## `ACTION` is a backwards-compatibility alias of `ATTACK` and shares its
  ## slot; the doctrine surface never offers it.
  checkEq("ACTION and ATTACK share slot 0", ugAction.upgradeSlot(),
    ugAttack.upgradeSlot())
  checkEq("CAPTURING is slot 1", ugCapturing.upgradeSlot(), 1)
  checkEq("HEALING is slot 2", ugHealing.upgradeSlot(), 2)
  var offered: seq[string]
  for c in UpgradeChoice: offered.add($c)
  checkEq("the doctrine surface offers exactly three, and no ACTION",
    offered, @["attack", "heal", "capture"])

block:
  ## The upgrade applies to the WHOLE TEAM immediately, and the effect goes
  ## through the float32 table.
  var w = bare()
  w.postSetup()
  let a = w.placeDuck(teamA, loc(5, 5))
  let b = w.placeDuck(teamB, loc(6, 5))
  checkEq("before: 150", w.getDamage(a), 150)
  w.stats.upgradePoints[0] = 1
  let other = w.placeDuck(teamA, loc(5, 6))
  w.doBuyGlobal(other, ugAttack)
  checkEq("after: 210, for every duck on the team", w.getDamage(a), 210)
  checkEq("and for the buyer", w.getDamage(other), 210)
  checkEq("the enemy is unchanged", w.getDamage(b), 150)
  a.attackExp = experienceFor(skAttack, 4)
  checkEq("+ATTACK at level 4 is the float32 273", w.getDamage(a), 273)

block:
  var w = bare()
  w.postSetup()
  let a = w.placeDuck(teamA, loc(5, 5))
  checkEq("before: 80", w.getHeal(a), 80)
  w.stats.upgradePoints[0] = 1
  w.doBuyGlobal(a, ugHealing)
  checkEq("after: 130", w.getHeal(a), 130)
  a.healExp = experienceFor(skHeal, 6)
  checkEq("+HEALING at level 6 is the float32 163", w.getHeal(a), 163)

block:
  ## CAPTURING does two things and they point at DIFFERENT teams: it stretches
  ## the OPPONENT's dropped-flag return delay and shortens THIS team's carry
  ## cooldown.
  var w = bare()
  w.postSetup()
  w.stats.upgradePoints[0] = 1
  let a = w.placeDuck(teamA, loc(5, 5))
  w.doBuyGlobal(a, ugCapturing)
  let f = w.ownFlags(teamB)[0]
  w.removeFlagAt(f.loc, f)
  a.flag = f
  f.carriedBy = a.id
  f.loc = a.loc
  w.doMove(a, dEast)
  checkEq("this team's carry cooldown is 12, not 20", a.movementCooldown, 12)
  a.actionCooldown = 0
  w.dropFlag(a, a.loc)
  var ticks = 0
  while not f.locIsStartRef and ticks < 40:
    w.resetDroppedFlags()
    ticks += 1
  checkEq("and the OPPONENT's flag takes 26 end-of-rounds to fly home",
    ticks, 26)

finish("bc24 upgrades")
