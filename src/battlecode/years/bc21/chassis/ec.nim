## The Enlightenment Center — the whole of a bc21 doctrine's economy.
##
## Every round, in this order:
##   1. sense the neighbourhood and fold every sensed enemy politician's
##      conviction into `nearbyEnemyFirePower`;
##   2. read every own robot's flag through the Center's UNLIMITED flag access
##      and update the shared maps of known neutral Centers, enemy Centers and
##      enemy slanderer sightings;
##   3. place a bid per `bid_policy`, AFTER reserving
##      `nearbyEnemyFirePower + 25` influence for defence;
##   4. if a target Center's conviction is known and affordable, build the
##      `c + 11` capture politician toward it; else build from `spendMix()`
##      under `phase()`;
##   5. set its own flag to the compressed `[kind, x, y, payload]` word.
##
## DEFENCE IS UNCONDITIONAL AND KNOB-INDEPENDENT (D2): whenever a sensed enemy
## politician's conviction exceeds this Center's own conviction, the Center
## spends its next build on a defender politician of
## `min(influence, thatConviction + 11)` regardless of every ratio knob. That
## is the rule that stops any knob setting from producing a bot that stands
## still and dies.
##
## Behaviour from `StoneT2000/Battlecode2021` `src/maxecosushi/` (the neutral
## Center scoring function, the slanderer breakpoint discipline and the build
## ratio caps) and `iliao2345/Battlecode2021` `src/muckspam/` + `src/membrane3/`
## (the muck-spam opening and its scouting fan-out), both AGPL-3.0.

import std/math
import kit, bids

type
  Threat* = object
    firePower*: int      ## summed conviction of sensed enemy politicians
    worst*: int          ## the single largest sensed enemy politician
    hasThreat*: bool
    at*: Loc

proc scanThreat(w: World, side: Side, r: Robot): Threat =
  for l in w.sensedTiles(r):
    let bot = w.getRobot(l)
    if bot == nil: continue
    if bot.team == side.team: continue
    if bot.kind == rtEnlightenmentCenter:
      side.noteCenter(l, bot.influence, bot.team.isPlayer(), w.currentRound)
      continue
    ## A Center true-senses, so a slanderer really is a slanderer here.
    if bot.kind == rtSlanderer:
      side.noteSlanderer(l, w.currentRound)
      continue
    if bot.kind == rtPolitician:
      result.firePower += bot.conviction
      if bot.conviction > result.worst:
        result.worst = bot.conviction
        result.at = l
        result.hasThreat = true

proc readOwnFlags(w: World, side: Side, r: Robot) =
  ## An Enlightenment Center may read the flag of ANY robot on the map, at any
  ## range. Bounded by the budget, one credit per flag.
  for id, bot in w.robotsById:
    if r.opsLeft <= 0: break
    if bot.team != side.team: continue
    if bot.id == r.id: continue
    r.opsLeft -= 1
    let word = decodeFlag(bot.flag)
    case word.kind
    of fkNeutralEcHere:
      side.noteCenter(loc(word.x, word.y), influenceFromHint(word.payload),
                      false, w.currentRound)
    of fkEnemyEcHere:
      side.noteCenter(loc(word.x, word.y), influenceFromHint(word.payload),
                      true, w.currentRound)
    of fkSlandererSeen:
      side.noteSlanderer(loc(word.x, word.y), w.currentRound)
    else: discard

proc bestTarget*(w: World, side: Side, from0: Loc): tuple[ok: bool, note: CenterNote] =
  ## `targetPolicy()`. `neutral_centers_first` picks the neutral Center
  ## minimising `distance^2 + 100 * lastKnownConviction` before ever aiming at
  ## an enemy Center; `defend_home` only ever answers a Center inside
  ## `r^2 <= 100` of an own Center.
  var best = -1
  var bestScore = high(int)
  let wantNeutralFirst = side.doctrine.expansion == exNeutralCentersFirst
  for pass in 0 .. 1:
    for i, note in side.knownCenters:
      let isNeutral = not note.hostile
      if wantNeutralFirst:
        if pass == 0 and not isNeutral: continue
        if pass == 1 and isNeutral: continue
      else:
        if pass == 1: continue
        var near = false
        for own in side.ownCenters:
          if own.distanceSquaredTo(note.loc) <= 100: near = true
        if not near: continue
      let known = if note.influence >= 0: note.influence else: 200
      let score = from0.distanceSquaredTo(note.loc) + 100 * known
      if score < bestScore:
        bestScore = score
        best = i
    if best >= 0: break
  if best < 0: return (false, CenterNote())
  (true, side.knownCenters[best])

proc buildDirToward(w: World, r: Robot, target: Loc): Dir =
  ## The free adjacent tile that most reduces the distance to `target`.
  var best = dCenter
  var bestD = high(int)
  for d in MoveDirs:
    if not spend(r, 1): break
    let l = r.loc + d
    if not w.onTheMap(l): continue
    if w.isLocationOccupied(l): continue
    let dist = l.distanceSquaredTo(target)
    if dist < bestD:
      bestD = dist
      best = d
  best

proc anyFreeDir(w: World, r: Robot, start: int): Dir =
  for k in 0 ..< 8:
    let d = MoveDirs[(start + k) mod 8]
    if not spend(r, 1): break
    let l = r.loc + d
    if w.onTheMap(l) and not w.isLocationOccupied(l): return d
  dCenter

proc tryBuild(w: World, side: Side, r: Robot, kind: RobotKind,
              influence: int, dir: Dir, bank = 0): int {.discardable.} =
  ## The id of the robot built, or -1. `bank` is influence the Center will not
  ## spend: the bid bank plus the DEFENCE RESERVE, because an Enlightenment
  ## Center's conviction IS its influence and a Center that spends to zero is
  ## captured by the next politician that walks past.
  if influence <= 0: return -1
  if dir == dCenter: return -1
  let amount = min(influence, max(0, r.influence - bank))
  if amount <= 0: return -1
  if not w.canBuildRobot(r, kind, dir, amount): return -1
  result = w.buildRobot(r, kind, dir, amount)
  w.firstBuild(side, kind)

proc defenceReserve*(side: Side, round: int): int =
  ## The conviction a Center keeps standing in it. Unconditional and
  ## knob-independent (D2): every knob setting still guards its own Centers.
  min(250, 25 + round div 8)

proc openingBuild(w: World, side: Side, r: Robot, bank: int): bool =
  ## `openingPlan()` — the build order for rounds 1...150.
  let d = side.doctrine
  let brain = side.brainFor(r)
  case d.opening
  of opMuckSpam:
    ## wololo's lineage: one 21-influence slanderer, then a 1-influence
    ## muckraker in a rotating direction every time the Center is ready, with
    ## the first eight told to scout.
    if side.opened == 0 and r.influence >= 21:
      if 0 <= tryBuild(w, side, r, rtSlanderer, 21,
                  anyFreeDir(w, r, side.nextScoutDir), bank):
        side.opened += 1
        return true
    let dir = anyFreeDir(w, r, side.nextScoutDir)
    side.nextScoutDir = (side.nextScoutDir + 3) mod 8
    if 0 <= tryBuild(w, side, r, rtMuckraker, 1,
                  dir, bank):
      side.opened += 1
      if side.scoutsSent < 8:
        side.scoutsSent += 1
      return true
    false
  of opSlandererTurtle:
    ## The babyducks pole: slanderers at the largest breakpoint the Center can
    ## afford, plus one 20-conviction defender politician per four slanderers,
    ## and no muckrakers before round 80.
    if side.opened > 0 and side.opened mod 4 == 0:
      if 0 <= tryBuild(w, side, r, rtPolitician, 20,
                  anyFreeDir(w, r, side.nextScoutDir), bank):
        side.opened += 1
        side.nextScoutDir = (side.nextScoutDir + 5) mod 8
        return true
    let want = bestSlandererInfluence(r.influence)
    if want >= 21:
      if 0 <= tryBuild(w, side, r, rtSlanderer, want,
                  anyFreeDir(w, r, side.nextScoutDir), bank):
        side.opened += 1
        side.nextScoutDir = (side.nextScoutDir + 5) mod 8
        return true
    if w.currentRound >= 80:
      if 0 <= tryBuild(w, side, r, rtMuckraker, 1,
                  anyFreeDir(w, r, side.nextScoutDir), bank):
        side.opened += 1
        return true
    false
  of opBalanced:
    ## California Roll's opening: alternate slanderer / 1-influence muckraker,
    ## with a single 16-influence politician on the seventh build.
    if side.opened == 6:
      if 0 <= tryBuild(w, side, r, rtPolitician, 16,
                  anyFreeDir(w, r, side.nextScoutDir), bank):
        side.opened += 1
        return true
    if side.opened mod 2 == 0:
      let want = max(21, bestSlandererInfluence(min(r.influence, 130)))
      if r.influence >= want and
          0 <= tryBuild(w, side, r, rtSlanderer, want,
                  anyFreeDir(w, r, side.nextScoutDir), bank):
        side.opened += 1
        return true
    let dir = anyFreeDir(w, r, side.nextScoutDir)
    side.nextScoutDir = (side.nextScoutDir + 3) mod 8
    if 0 <= tryBuild(w, side, r, rtMuckraker, 1,
                  dir, bank):
      side.opened += 1
      if side.scoutsSent < 8: side.scoutsSent += 1
      return true
    false

proc mixBuild(w: World, side: Side, r: Robot, bank: int): bool =
  ## The post-opening split. `spendMix()` gives the percentages;
  ## `eco_exponential_round` stops slanderer production entirely and
  ## redistributes its share to politicians and muckrakers in proportion.
  let d = side.doctrine
  var (slan, muck, pol) = d.spendMix()
  if not d.compounding(w.currentRound):
    let rest = muck + pol
    if rest <= 0:
      muck = 50
      pol = 50
    else:
      muck = muck + slan * muck div rest
      pol = 100 - muck
    slan = 0
  let roll = (w.currentRound * 7 + r.id) mod 100
  let dir0 = anyFreeDir(w, r, side.nextScoutDir)
  side.nextScoutDir = (side.nextScoutDir + 3) mod 8
  if dir0 == dCenter: return false

  if roll < slan:
    let want = bestSlandererInfluence(min(r.influence, 130))
    if want >= 21 and 0 <= tryBuild(w, side, r, rtSlanderer, want,
                  dir0, bank):
      return true
  if roll < slan + muck:
    if 0 <= tryBuild(w, side, r, rtMuckraker, 1,
                  dir0, bank):
      return true
  let want = d.politicianInfluence(w.currentRound)
  ## THE SIZE IS THE POINT. A "fat politicians" doctrine that shipped an
  ## 18-influence body because that is all it had spare would not be a fat
  ## doctrine, so the Center builds the curve's size when it can, HALF of it
  ## when it can only half afford it, and otherwise saves for a round.
  let avail = max(0, r.influence - bank)
  let amount =
    if avail >= want: want
    elif avail >= max(18, want div 2): avail
    else: 0
  let made =
    if amount > 0: tryBuild(w, side, r, rtPolitician, amount, dir0, bank)
    else: -1
  if made >= 0:
    ## Telemetry the knob gate reads: the politicians the SPEND MIX built, as
    ## opposed to the defence and capture bodies whose size the map dictates.
    ## `politician_size_curve` steers exactly these.
    w.stats.mixPoliticians[ord(r.team)] += 1
    w.stats.mixPoliticianInfluence[ord(r.team)] +=
      w.robotsById[made].influence
    return true
  ## THE SIZE CURVE HAS TO BIND. `fat` asks for 40..400 influence, which a
  ## Center rarely has spare in one round; spending the difference on a
  ## 1-influence muckraker instead would make `fat` and `cheap` produce the
  ## same politicians and the knob would have no teeth. So when the mix picked
  ## a politician and the Center cannot yet afford the curve's size, it SAVES:
  ## it takes no build this turn (it still bids, still senses, still defends)
  ## and comes back richer. `cheap` is 18 flat and never waits.
  if roll >= slan + muck and want > 18:
    return false
  ## Otherwise a 1-influence muckraker is always affordable and always useful,
  ## so the Center never stands idle.
  0 <= tryBuild(w, side, r, rtMuckraker, 1, dir0, bank)

proc runEnlightenmentCenter*(w: World, side: Side, r: Robot) =
  let d = side.doctrine
  let threat = scanThreat(w, side, r)
  readOwnFlags(w, side, r)

  ## 3. Bid, after reserving defence money.
  let reserve = threat.firePower + 25
  placeBid(w, side, r, reserve)

  ## 4. Build. Defence first, unconditionally — the bank is for the
  ## auction, and an emergency outranks both the auction and the reserve.
  let bank = max(bidBank(side, w.currentRound),
                 defenceReserve(side, w.currentRound))
  var built = false
  if isReady(r):
    if threat.hasThreat and threat.worst > r.conviction div 2:
      let want = min(r.influence, threat.worst + 11)
      let dir = buildDirToward(w, r, threat.at)
      let id = tryBuild(w, side, r, rtPolitician, want, dir)
      if id >= 0:
        side.markDefender(id)
        built = true
    if not built:
      let (ok, note) = bestTarget(w, side, r.loc)
      if ok and note.influence >= 0 and
          r.influence >= note.influence + 11 + bank:
        ## The cheapest guaranteed capture: the Center's conviction plus the
        ## 10-influence empower tax plus one.
        let dir = buildDirToward(w, r, note.loc)
        built = tryBuild(w, side, r, rtPolitician, note.influence + 11, dir,
                         bank) >= 0
    if not built and w.currentRound <= 150:
      built = openingBuild(w, side, r, bank)
    if not built:
      built = mixBuild(w, side, r, bank)

  ## 5. Say something useful.
  var word = encodeFlag(fkSilent, r.loc)
  if threat.hasThreat:
    word = encodeFlag(fkNeedDefence, r.loc, influenceHint(threat.worst))
  else:
    let (ok, note) = bestTarget(w, side, r.loc)
    if ok:
      word = encodeFlag(
        (if note.hostile: fkEnemyEcHere else: fkNeutralEcHere), note.loc,
        influenceHint(max(0, note.influence)))
    elif side.slandererSightings.len > 0:
      let sighting = side.slandererSightings[^1]
      word = encodeFlag(fkSlandererSeen, sighting.loc)
    else:
      word = encodeFlag(fkEcInfluenceHint, r.loc, influenceHint(r.influence))
  setFlag(r, word)
  discard d
