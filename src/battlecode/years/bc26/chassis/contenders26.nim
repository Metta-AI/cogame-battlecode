## Source-informed king economies, with the existing native rat tactics.
## This deliberately does not claim Java, neural-policy, or tournament parity.
import kit, king, rat, targets, pathing

proc gravySpawn*(round, cost, cheese: int): bool =
  if round >= 1900: return cheese - cost >= 400
  let cap = if round >= 400: 1000 elif round > 150: 80 else: 30
  let reserve = if cost <= 20: 0 elif cost <= 30: 500
                elif cost <= 60: 1000 else: 1500
  cost <= cap and cheese >= reserve

proc merlinSpawn*(round, cost, cheese, mines: int): bool =
  if cost > 100: return false
  if round <= 20: return true
  if (cost <= 10 and cheese >= 20) or (cost <= 20 and cheese >= 40) or
      (cost <= 30 and cheese >= 100) or (cost <= 40 and cheese >= 200):
    return true
  for i in 0 .. 12:
    if cost <= 30 + i * 10 and cheese >= max(750, 1800 - round + i * 50) and
        round >= 125 + i * 4 and (i < 4 or mines > 2 + i div 2):
      return true
  false

proc oldGoldSpawn*(round, cost, cheese, mines: int): bool =
  let maxCost = if mines <= 4: 30 else: 40
  if cost <= maxCost: cheese > 5 * cost
  else: cheese - 2100 + round >= 5 * cost

proc tspaarkTarget*(round, cheese, kings, mines: int): int =
  result = if round < 50: 12 elif cheese < 500: 8 elif cheese < 1000: 12
           else: 12 + ((cheese - 2000) div 1000) * 4 + mines
  result += max(0, kings - 1) * 8

proc powerpuffSpawn*(round, rats, cost, cheese, kings: int, gain: float): bool =
  if round <= 100: return rats <= 16
  if cheese < 125: return rats <= 4
  if cheese < 500: return rats <= 8
  if cheese < 1700:
    if cheese >= 1400: return rats <= 24
    if gain >= float(4 * kings): return false
    let limit = if cheese < 800: 12 elif cheese < 1200: 16 else: 20
    return rats <= limit
  cheese - cost > 1700

proc spaarkCostLimit*(round, cost, cheese, kings: int, average: float,
                      threatened: bool): int =
  let threshold = float(200 * kings + (10 + cost) * (cost div 10) * 2 +
                         max(0, 1500 - round)) -
                  max(0.0, average - float(cost)) * float(cost) / 4.0
  result = int(average)
  if float(cheese) > threshold:
    if round > 100 or result < 30: result += 10
  else:
    result = cheese div 100 + 25
  if round < 200: result = min(result, 30)
  if threatened: result += 10

proc teamCheese(w: World, clan: Clan, r: Robot): int =
  ## getAllCheese is a team-wide statistic in the original API.
  result = w.teamInfo.globalCheese[ord(clan.team)]
  for other in w.liveRobots:
    if not r.spend(1): break
    if other.team == clan.team: result += other.cheese

proc runContender26*(w: World, clan: Clan, r: Robot) =
  if r.unit == utBabyRat:
    runRat(w, clan, r)
    return
  if r.unit != utRatKing: return
  let brain = clan.brainFor(r)
  let round = w.currentRound
  let cost = w.currentRatCost(clan.team)
  let cheese = w.teamInfo.globalCheese[ord(clan.team)]
  let kings = max(1, w.teamInfo.numRatKings[ord(clan.team)])
  let rats = w.teamInfo.numBabyRats[ord(clan.team)]
  let totalCheese = teamCheese(w, clan, r)
  if not brain.contenderInitialized:
    brain.contenderInitialized = true
    brain.previousCheese = InitialTeamCheese
    brain.breedAllowed = true
    # Preserve the source's unusual 99 initialized slots / divisor of 50.
    for i in 0 .. 98: brain.costSamples[i] = 30
    brain.costTotal = 1500
    brain.gainSamples = newSeq[int](max(1, (w.width + w.height) div 8))
  brain.turnCount += 1

  # Mine discovery remains private to this king, rather than reading hidden map
  # tiles. The Java teams' communications and symmetry inference are not ported.
  for l in w.allLocationsWithinRadiusSquared(r.loc, r.visionRadiusSquared, r.chirality):
    if not r.spend(1): break
    if r.canSenseLocation(l) and w.hasCheeseMine(l) and l notin brain.contenderMines:
      brain.contenderMines.add(l)
  let mines = brain.contenderMines.len
  var haveThreat = false
  var threat = r.loc
  var threatDist = high(int)
  for other in w.senseNearbyRobots(r):
    if not r.spend(1): break
    if other.team == clan.team: continue
    if other.unit != utCat and not clan.hostilitiesOpen(w): continue
    let dist = r.loc.distanceSquaredTo(other.loc)
    if dist < threatDist:
      haveThreat = true
      threat = other.loc
      threatDist = dist

  var allowed = false
  case clan.doctrine.chassis
  of chGravy:
    allowed = gravySpawn(round, cost, cheese)
  of chComplexMerlin:
    allowed = merlinSpawn(round, cost, cheese, mines)
  of chOldButGold:
    allowed = oldGoldSpawn(round, cost, cheese, mines)
  of chTspaark:
    allowed = rats < tspaarkTarget(round, cheese, kings, mines)
  of chPowerpuffGirls:
    let index = brain.gainIndex
    if brain.gainCount == brain.gainSamples.len:
      brain.gainTotal -= brain.gainSamples[index]
    else: inc brain.gainCount
    brain.gainSamples[index] = totalCheese - brain.previousCheese
    brain.gainTotal += brain.gainSamples[index]
    brain.gainIndex = (index + 1) mod brain.gainSamples.len
    allowed = powerpuffSpawn(round, rats, cost, totalCheese, kings,
                            float(brain.gainTotal) / float(brain.gainCount))
  of chSpaark2026:
    let index = round mod 100
    brain.costTotal += cost - brain.costSamples[index]
    brain.costSamples[index] = cost
    allowed = cost <= spaarkCostLimit(round, cost, cheese, kings,
                                     float(brain.costTotal) / 50.0,
                                     haveThreat and threatDist <= 30)
  of chProofOfConcept:
    if brain.turnCount mod 4 == 0:
      let rate = (totalCheese - brain.previousCheese) div 4
      brain.breedAllowed = totalCheese - cost + rate >= kings * 2000
      brain.previousCheese = totalCheese
    # This is only the archived generated bot's king economy; its neural baby
    # policy and training-time resignation at 1200 are deliberately not run.
    allowed = brain.breedAllowed and not haveThreat
  else: discard

  runKing(w, clan, r, customSpawn = true, spawnAllowed = allowed)
  if clan.doctrine.chassis == chPowerpuffGirls:
    brain.previousCheese = teamCheese(w, clan, r)

  # Mobile kings are an adaptation of the archives' flee/collect modes. They
  # use native pathing and vision; original tie order and micro are not claimed.
  if haveThreat and threatDist <= 25:
    let away = loc(clamp(2 * r.loc.x - threat.x, 0, w.width - 1),
                   clamp(2 * r.loc.y - threat.y, 0, w.height - 1))
    moveOrTurn(w, clan, r, away)
  elif not allowed:
    let target = nearestCheese(w, clan, r)
    if target.kind == tkCheese:
      moveOrTurn(w, clan, r, target.loc)
    elif brain.contenderMines.len > 0:
      moveOrTurn(w, clan, r, brain.contenderMines[0])
