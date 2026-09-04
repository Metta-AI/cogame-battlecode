## The bc21 baselines: both `PLAYER_SCRIPTED` resolutions through the SAME
## validate the LLM path uses, bounded and legal orders in played games, the
## `DecisionOps` budget the sim (not the bot) enforces, `examplefuncsplayer21`
## acting without being required to survive, and `california-roll` beating it
## 6/6.

import std/[json, strutils]
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc21/[constants, maps, rules, world]

const GateMaps = ["Bog", "Star"]
const GateSeeds = [1, 256, 768]
  ## The episode seed only chooses the map and the side assignment — the world
  ## RNG comes from the MAP's own `randomSeed` — so these six games are the two
  ## maps under both side assignments, which is every distinct game those
  ## inputs can produce.

proc crollSheet(): Sheet = baselineSheet("bc21", blCaliforniaRoll)
proc scaffoldSheet(): Sheet = baselineSheet("bc21", blExamplefuncsplayer21)

# --- (a) both replies pass the SAME validate the LLM path uses --------------
block:
  for kind in [blCaliforniaRoll, blExamplefuncsplayer21]:
    let sheet = baselineSheet("bc21", kind)
    checkEq($kind & " repairs nothing", sheet.defaultsApplied.len, 0)
    checkEq($kind & " sends no unknown key", sheet.unknownFields.len, 0)
    check($kind & " never sends `chassis` (D1)",
      "chassis" notin sheet.unknownFields)
    check($kind & " notes are under cap", sheet.notes.len <= 280)
    check($kind & " motto is under cap", sheet.motto.len <= 48)
    let doc = sheet.toJson()
    checkEq($kind & " fills all ten knobs", doc.len, 10)

block:
  ## `PLAYER_SCRIPTED` resolves PER YEAR, and the manifest still declares only
  ## `awu` and `scaffold`.
  checkEq("awu on bc21 is california-roll",
    $baselineFor("bc21", "awu"), "california-roll")
  checkEq("california-roll is itself",
    $baselineFor("bc21", "california-roll"), "california-roll")
  checkEq("anything unrecognised is california-roll",
    $baselineFor("bc21", "bowl-of-chowder"), "california-roll")
  checkEq("scaffold on bc21 is examplefuncsplayer21",
    $baselineFor("bc21", "scaffold"), "examplefuncsplayer21")
  checkEq("and so is examplefuncsplayer",
    $baselineFor("bc21", "examplefuncsplayer"), "examplefuncsplayer21")
  checkEq("and examplefuncsplayer21", $baselineFor("bc21",
    "examplefuncsplayer21"), "examplefuncsplayer21")
  checkEq("the default is the STRONG doctrine, not the weak floor",
    $defaultBaselineFor("bc21"), "california-roll")
  checkEq("bc20's own resolution is untouched",
    $baselineFor("bc20", "awu"), "bowl-of-chowder")
  checkEq("and bc26's", $baselineFor("bc26", "awu"), "awu")

# --- (b) legality and the DecisionOps budget --------------------------------
proc auditRound(w: World, violations: var seq[string]) =
  var occupied = 0
  for i, r in w.occupant:
    if r == nil: continue
    inc occupied
    if r.dead: violations.add("a dead robot is still on the grid")
    if w.idx(r.loc) != i: violations.add("a robot's tile disagrees with its loc")
  if occupied != w.robotsById.len:
    violations.add("the grid and the id table disagree: " & $occupied &
      " vs " & $w.robotsById.len)
  if w.execOrder.len != w.robotsById.len:
    violations.add("the exec order and the id table disagree")
  var counted: array[3, int]
  for id, r in w.robotsById:
    counted[ord(r.team)] += 1
    if not w.onTheMap(r.loc): violations.add("a robot is off the map")
    if r.conviction > r.convictionCap:
      violations.add("conviction above the cap")
    if r.influence < 0: violations.add("negative influence")
    if r.influence > RobotInfluenceLimit: violations.add("influence over 1e8")
    if r.cooldownTurns < 0.0: violations.add("negative cooldown")
    if r.opsLeft < 0: violations.add("a robot overspent its DecisionOps budget")
    if r.kind == rtSlanderer and r.roundsAlive > CamouflageNumRounds:
      violations.add("a slanderer outlived camouflage")
    if r.flag < MinFlagValue or r.flag > MaxFlagValue:
      violations.add("a flag outside [0, MAX_FLAG_VALUE]")
    if r.bid < 0: violations.add("a negative bid")
    if r.kind != rtEnlightenmentCenter and r.bid != 0:
      violations.add("a non-Center holds a bid")
  for t in 0 .. 2:
    if counted[t] != w.robotCount[t]:
      violations.add("the robot count for team " & $t & " drifted")

block:
  ## ONE pass over the six games answers (b), (c) and (d): the per-round audit,
  ## the "the scaffold acts" counters, and the head-to-head record. Playing
  ## them three times over would triple this shard's CI minutes and prove
  ## nothing extra — every game here is deterministic.
  var violations: seq[string]
  var rounds = 0
  var built = 0
  var bids = 0
  var moves = 0
  var survived = 0
  var wins = 0
  for name in GateMaps:
    for seed in GateSeeds:
      let sa = sideAslotFor(seed, 0)
      proc onRound(w: World, round: int) {.closure.} =
        inc rounds
        if round mod 25 == 0 or round < 5:
          auditRound(w, violations)
      let (w, o) = playGame(loadMap(name), [crollSheet(), scaffoldSheet()],
        [ckCaliforniaRoll, ckExamplefuncsplayer21], 0, sa, 1500, 0, onRound)
      built += o.unitsBuilt[1]
      bids += o.bidsPlaced[1]
      moves += w.stats.moves[(if sa == 0: 1 else: 0)]
      if o.unitsAlive[1] > 0: inc survived
      if o.winnerSlot == 0: inc wins

  # --- (b) legality and the DecisionOps budget ------------------------------
  check("six full games were audited", rounds >= 6 * 1500)
  checkEq("no legality or budget violation in any audited round",
    violations.join("; "), "")

  # --- (c) examplefuncsplayer21 ACTS, but need not survive ------------------
  check("the scaffold built units", built >= 6)
  check("the scaffold placed bids", bids >= 6)
  check("the scaffold moved", moves >= 6)
  ## It is the deliberate weak floor and the oracle's other side: it may not
  ## gain behaviour, and it is NOT required to survive.
  check("and whether it survived is not asserted either way",
    survived >= 0 and survived <= 6)

  # --- (d) california-roll beats examplefuncsplayer21 6/6 -------------------
  checkEq("california-roll beats examplefuncsplayer21 on all six", wins, 6)

block:
  ## The budget is ENFORCED BY THE SIM: a robot's `opsLeft` is reset at the
  ## start of its turn and can never go below zero.
  for kind in [rtEnlightenmentCenter, rtPolitician, rtSlanderer, rtMuckraker]:
    check($kind & " has a positive DecisionOps budget",
      RobotSpecs[kind].decisionOps > 0)
    checkEq($kind & " budget is one tenth of the Java bytecode limit",
      RobotSpecs[kind].decisionOps, RobotSpecs[kind].bytecodeLimit div 10)

finish("bc21 baselines")
