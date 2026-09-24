import std/[json, sets]
import harness, bc25_fixture
import battlecode/[baselines, sim_types]
import battlecode/years/dispatch
import battlecode/years/bc25/chassis/contenders25

const Baselines = [blConfused25, blJustWokeUp25, blOmNom25, blSpaark2025]
const Kinds = [ckConfused25, ckJustWokeUp25, ckOmNom25, ckSpaark2025]

block registration:
  var selected = initHashSet[string]()
  for i, b in Baselines:
    let name = ContenderNames25[i]
    checkEq(name & " baseline", baselineFor("bc25", name), b)
    checkEq(name & " year mapping", chassisKindFor(baselineChassis(b)), Kinds[i])
    checkEq(name & " replay roundtrip", parseScriptedChassis($baselineChassis(b)), baselineChassis(b))
    checkEq(name & " CLI mapping", parseChassisKind25(name), Kinds[i])
    let s = baselineSheet("bc25", b)
    checkEq(name & " valid sheet", s.defaultsApplied.len + s.unknownFields.len, 0)
    checkEq(name & " isolated to 2025", baselineFor("bc24", name), blGoneSharkin)
    selected.incl($baselineChassis(b))
  checkEq("four distinct controllers", selected.len, 4)
  checkEq("legacy spaark remains selectable", baselineFor("bc25", "spaark"), blSpaark)
  checkEq("legacy fallback unchanged", defaultBaselineFor("bc25"), blSpaark)
  let roster = parseJson(readFile("tools/ci/bc25-contender-policies.json"))
  checkEq("release contains four contenders", roster.len, 4)
  var owners = initHashSet[string]()
  for row in roster:
    owners.incl(row["player_name"].getStr())
    let name = row["env"]["PLAYER_SCRIPTED"].getStr()
    check("release selector resolves to a contender", baselineFor("bc25", name) in Baselines)
  checkEq("release requests four separate leaderboard identities", owners.len, 4)

block confusedPhases:
  let w = bare()
  let tower = w.getRobot(loc(3, 3))
  let m = ContenderTowerMemory()
  w.stats.money[0] = 3000
  w.currentRound = 50
  checkEq("confused small-map opening splasher", confusedBuild(w, tower, m), utSplasher)
  m.splashers = 1
  checkEq("confused opening soldiers after first splasher", confusedBuild(w, tower, m), utSoldier)
  w.currentRound = 150
  m.soldiers = 3
  m.moppers = 2
  w.stats.towers[0] = 7
  checkEq("confused mid-game 3:1:2 tie selects splasher", confusedBuild(w, tower, m), utSplasher)
  w.stats.towers[0] = 6
  checkEq("confused gates mid-game splashers on >6 towers", confusedBuild(w, tower, m), utMopper)
  w.currentRound = 250
  checkEq("confused late splashers no tower-count gate", confusedBuild(w, tower, m), utSplasher)

block omNomPlans:
  let w = bare()
  let tower = w.getRobot(loc(3, 3))
  let m = ContenderTowerMemory(plan: -1)
  w.currentRound = 1
  w.stats.money[0] = 3000
  checkEq("Om Nom begins with soldiers", omNomBuild(w, tower, m), utSoldier)
  m.planCursors[0] = 4
  checkEq("Om Nom fifth paint-tower spawn is mopper", omNomBuild(w, tower, m), utMopper)
  w.currentRound = 199
  checkEq("Om Nom plan stays until boundary", omNomBuild(w, tower, m), utMopper)
  w.currentRound = 200
  checkEq("Om Nom late paint plan starts with splasher", omNomBuild(w, tower, m), utSplasher)
  m.planCursors[1] = 1
  checkEq("Om Nom late paint plan second splasher", omNomBuild(w, tower, m), utSplasher)

block spaarkAccounting:
  let w = bare()
  let tower = w.getRobot(loc(3, 3))
  let m = ContenderTowerMemory()
  let weights = spaarkWeights(2, 1)
  w.currentRound = 1
  checkEq("SPAARK initial soldier override", spaarkBuild(w, tower, m, weights), utSoldier)
  w.currentRound = 100
  m.spawned = 3
  m.soldiers = 3
  checkEq("SPAARK compensates opening with mopper", spaarkBuild(w, tower, m, weights), utMopper)
  check("SPAARK splash weight grows with paint towers", spaarkWeights(10, 4)[2] > weights[2])
  let a = newSides25(defaultSheets(), 0)
  let b = newSides25(defaultSheets(), 0)
  towerMemory(a[0], tower, 1).spawned = 9
  checkEq("per-game memory is isolated", towerMemory(b[0], tower, 1).spawned, 0)

block targetPriorities:
  for kind in [ctConfused, ctJustWokeUp, ctOmNom]:
    let w = bare()
    w.currentRound = 20
    w.stats.money[0] = 0
    let tower = w.getRobot(loc(3, 3))
    tower.opsLeft = DecisionOpsRobot
    let mop = w.place(teamB, utMopper, loc(4, 3))
    let sol = w.place(teamB, utSoldier, loc(4, 4))
    let spl = w.place(teamB, utSplasher, loc(3, 4))
    mop.health = 40
    sol.health = 70
    spl.health = 110
    for bot in [mop, sol, spl]: bot.paint = 50
    let sides = newSides25(defaultSheets(), 0)
    runContenderTower(w, sides[0], tower, kind)
    let losses = [40 - mop.health, 70 - sol.health, 110 - spl.health]
    let expected = if kind == ctConfused: 0 elif kind == ctJustWokeUp: 1 else: 2
    for i in 0 .. 2:
      if i != expected:
        check($kind & " correct single-shot priority", losses[expected] > losses[i])
    checkEq($kind & " no refused attack", w.refusedActions, 0)

block games:
  var hashes = initHashSet[string]()
  for i, b in Baselines:
    let s = [baselineSheet("bc25", b), baselineSheet("bc25", blExamplefuncsplayer25)]
    for seat in 0 .. 1:
      let (w, o) = playGame(loadMap("DefaultSmall"), s,
        [Kinds[i], ckExamplefuncsplayer25], 0, seat, 2000, 0)
      let label = $b & " seat " & $seat
      checkEq(label & " legal actions", w.refusedActions, 0)
      check(label & " operation budget", w.opsUsedPeak <= DecisionOpsRobot)
      check(label & " built units", o.robotsBuilt[0] > 0)
      check(label & " painted territory", o.tilesPainted[0] > 0)
      check(label & " full game", o.roundsPlayed == 2000 or
        o.endReason in ["paint_enough_area", "destroy_all_units"])
      echo label, ": winner=", o.winnerSlot, " rounds=", o.roundsPlayed,
        " builds=", o.robotsBuilt[0], " towers=", o.towersBuilt[0],
        " srps=", o.srpCompleted[0]
      if seat == 0: hashes.incl(o.hashChain)
    let a = playGame(loadMap("Filter"), s, [Kinds[i], ckExamplefuncsplayer25], 0, 0, 120, 0)[1]
    let c = playGame(loadMap("Filter"), s, [Kinds[i], ckExamplefuncsplayer25], 0, 0, 120, 0)[1]
    checkEq($b & " deterministic", a.hashChain, c.hashChain)
  checkEq("four distinct game trajectories", hashes.len, 4)

finish("test_bc25_contenders")
