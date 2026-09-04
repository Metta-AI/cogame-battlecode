## The economy: the Enlightenment Center's `ceil(0.2f * sqrt(t))` against the
## committed JDK table for all 1500 rounds, the slanderer's 51 payments (the
## first on its SPAWN round), the parent-Center cut-off, camouflage at exactly
## 300, the generated breakpoint table, and the 1e8 clamp that the end-of-round
## sweep's order-independence argument rests on.

import std/[json, os, math]
import harness
import battlecode/years/bc21/[constants, economy, world, votes]

proc flat(width, height: int): MapSpec =
  result.name = "flat"
  result.width = width
  result.height = height
  result.origin = [0, 0]
  result.randomSeed = 4242
  result.symmetry = symRotational
  result.symmetries = @[symRotational]
  for i in 0 ..< width * height:
    result.passability.add(1.0)

proc bare(): World = newWorld(flat(15, 15), 1500)

# --- the Center curve against the committed table ---------------------------
block:
  let doc = parseJson(readFile(bc21DataRoot() / "bc21" / "ec_passive.json"))
  checkEq("the table covers 1500 rounds", doc["income"].len, 1500)
  var total = 0
  var drift = 0
  for i in 0 ..< 1500:
    let round = i + 1
    let want = doc["income"][i].getInt()
    total += want
    if ecPassive(round) != want: inc drift
    if ecPassiveAt(round) != want: inc drift
  checkEq("the committed table and both computations agree on all 1500 rounds",
    drift, 0)
  checkEq("and the whole game is worth 8507 influence per Center", total, 8507)
  checkEq("the table's own total agrees", doc["total"].getInt(), 8507)
  checkEq("round 1 pays 1", ecPassive(1), 1)
  ## THE WIDTH IS THE POINT. `0.2f` widens to 0.20000000298023224, so
  ## `0.2f * sqrt(25)` is 1.0000000149011612 and ceils to TWO. Under a naive
  ## transcription that reads the constant as the double 0.2 it is exactly 1.0
  ## and ceils to one — a silent divergence on every perfect square of 25.
  checkEq("round 25 pays 2, not 1 — the float32 widening", ecPassive(25), 2)
  checkEq("round 24 still pays 1", ecPassive(24), 1)
  checkEq("round 1500 pays ceil(0.2*sqrt(1500)) = 8", ecPassive(1500), 8)
  checkEq("round 0 pays nothing", ecPassive(0), 0)

# --- the embezzle curve and the breakpoints ---------------------------------
block:
  let doc = parseJson(readFile(bc21DataRoot() / "bc21" / "embezzle.json"))
  checkEq("the table covers influence 1..4096", doc["income"].len, 4096)
  var drift = 0
  for i in 0 ..< 4096:
    let x = i + 1
    if embezzle(x) != doc["income"][i].getInt(): inc drift
    if embezzleAt(x) != doc["income"][i].getInt(): inc drift
  checkEq("the committed table and the fdlibm computation agree everywhere",
    drift, 0)
  let bp = slandererBreakpoints()
  ## Exactly the table California Roll shipped in
  ## `src/maxecosushi/EnlightmentCenter.java:21` — the cross-check that the
  ## port reproduced the FORMULA and not a lookalike.
  const Want = [21, 41, 63, 85, 107, 130, 154, 178, 203, 228, 255, 282, 310,
                339, 368, 399, 431, 463, 497, 532, 568, 605, 643, 683, 724,
                766, 810, 855, 902, 949, 999]
  check("there are at least as many breakpoints as California Roll shipped",
    bp.len >= Want.len)
  var bpDrift = 0
  for i, want in Want:
    if bp[i] != want: inc bpDrift
  checkEq("and the first 31 are byte for byte hers", bpDrift, 0)
  checkEq("a 130-influence slanderer pays 6 a round", embezzle(130), 6)
  checkEq("a 20-influence one pays nothing", embezzle(20), 0)
  checkEq("21 is the first that pays", embezzle(21), 1)
  checkEq("bestSlandererInfluence(20) cannot afford one", bestSlandererInfluence(20), 0)
  checkEq("bestSlandererInfluence(130) takes the 130 breakpoint",
    bestSlandererInfluence(130), 130)
  checkEq("bestSlandererInfluence(150) still takes 130",
    bestSlandererInfluence(150), 130)

# --- 51 payments, the first on the SPAWN round ------------------------------
block:
  var w = bare()
  let ec = w.spawnRobot(-1, rtEnlightenmentCenter, loc(5, 5), teamA, 1000)
  let s = w.spawnRobotWithId(50_000, ec, rtSlanderer, loc(5, 6), teamA, 130)
  var payments = 0
  var lastRound = 0
  for round in 1 .. 400:
    w.currentRound = round
    let before = w.robotsById[ec].influence
    discard w.processEndOfRoundSweep()
    ## The Center's own passive rides in the same sweep; subtract it.
    let gained = w.robotsById[ec].influence - before - ecPassive(round)
    if gained > 0:
      inc payments
      lastRound = round
      checkEq("each payment is 6", gained, 6)
    if round <= 400:
      w.robotsById[s].roundsAlive += 1
  checkEq("a slanderer pays 51 times, not 50", payments, 51)
  checkEq("the first payment lands on its SPAWN round, before it ever moves",
    lastRound, 51)

# --- a captured parent Center cuts the income off ---------------------------
block:
  var w = bare()
  let ec = w.spawnRobot(-1, rtEnlightenmentCenter, loc(5, 5), teamA, 1000)
  discard w.spawnRobotWithId(50_000, ec, rtSlanderer, loc(5, 6), teamA, 130)
  w.currentRound = 10
  let other0 = w.spawnRobot(-1, rtEnlightenmentCenter, loc(1, 1), teamA, 100)
  let before = w.robotsById[other0].influence
  w.destroyRobot(ec)
  discard w.processEndOfRoundSweep()
  checkEq("with its parent gone the slanderer pays NOBODY",
    w.robotsById[other0].influence, before + ecPassive(10))

# --- camouflage at exactly roundsAlive == 300 -------------------------------
block:
  var w = bare()
  let ec = w.spawnRobot(-1, rtEnlightenmentCenter, loc(5, 5), teamA, 1000)
  let s = w.spawnRobotWithId(50_000, ec, rtSlanderer, loc(5, 6), teamA, 130)
  w.robotsById[s].flag = 12345
  w.currentRound = 1
  for ra in 0 .. 299:
    w.robotsById[s].roundsAlive = ra
    discard w.processEndOfRoundSweep()
    if ra < 299:
      checkEq("still a slanderer at " & $ra, w.robotsById[s].kind, rtSlanderer)
  w.robotsById[s].roundsAlive = 300
  discard w.processEndOfRoundSweep()
  let r = w.robotsById[s]
  checkEq("at exactly 300 it becomes a politician", r.kind, rtPolitician)
  checkEq("keeping its id", r.id, s)
  checkEq("its influence", r.influence, 130)
  checkEq("its parent", r.parentId, ec)
  checkEq("and its flag", r.flag, 12345)
  checkEq("the type counts moved with it",
    w.typeCount[ord(teamA)][rtSlanderer], 0)
  checkEq("onto the politicians", w.typeCount[ord(teamA)][rtPolitician], 1)

# --- the 1e8 clamp -----------------------------------------------------------
block:
  var w = bare()
  let ec = w.spawnRobot(-1, rtEnlightenmentCenter, loc(5, 5), teamA, 1000)
  check("no gate game ever reaches the clamp", not w.influenceClampHit)
  w.addInfluenceAndConviction(w.robotsById[ec], RobotInfluenceLimit)
  ## Reaching it is RECORDED, because it is the one place the end-of-round
  ## sweep order could matter.
  check("and reaching it is recorded", w.influenceClampHit)
  checkEq("the influence is clamped", w.robotsById[ec].influence,
    RobotInfluenceLimit)

finish("bc21 economy")
