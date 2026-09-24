import std/[sets, json]
import harness
import battlecode/[baselines, sheet, sim_types]
import battlecode/years/bc26/[contenders, rules, maps, world]
import battlecode/years/bc26/chassis/contenders26

let kinds = [blProofOfConcept, blSpaark2026, blGravy, blPowerpuffGirls,
             blComplexMerlin, blTspaark, blOldButGold]
var owners = initHashSet[string]()
var selectors = initHashSet[string]()
for row in parseJson(readFile("tools/ci/bc26-contender-policies.json")):
  owners.incl(row["player_name"].getStr())
  selectors.incl(row["env"]["PLAYER_SCRIPTED"].getStr())
checkEq("seven distinct leaderboard identities", owners.len, 7)
checkEq("seven distinct selectors", selectors.len, 7)
for i, kind in kinds:
  let s = baselineSheet("bc26", kind)
  checkEq("selector resolves " & $kind, baselineFor("bc26", ContenderNames26[i]), kind)
  checkEq("no repaired fields " & $kind, s.defaultsApplied.len, 0)
  checkEq("no unknown fields " & $kind, s.unknownFields.len, 0)
  checkEq("recorded chassis " & $kind, $s.doctrine.chassis, ContenderNames26[i])
  checkEq("seat chassis " & $kind, $baselineChassis(kind), ContenderNames26[i])
  checkEq("2026 name does not enter 2025 " & $kind,
          baselineFor("bc25", ContenderNames26[i]), blSpaark)
checkEq("2025 name does not enter 2026", baselineFor("bc26", "confused"), blAwu)

# Boundary fixtures from pinned Java production rules, independent of game traces.
check("Gravy cheap rat, empty reserve", gravySpawn(100, 20, 20))
check("Gravy early cost ceiling", not gravySpawn(150, 40, 2000))
check("Gravy phase transition", gravySpawn(151, 40, 1000))
check("Gravy late survival reserve", not gravySpawn(1900, 50, 449))
check("Gravy late reserve reached", gravySpawn(1900, 50, 450))
check("Merlin opening exception", merlinSpawn(20, 100, 100, 0))
check("Merlin absolute cost cap", not merlinSpawn(20, 110, 5000, 20))
check("Merlin early reserve", not merlinSpawn(30, 40, 199, 0))
check("Merlin reserve reached", merlinSpawn(30, 40, 200, 0))
check("Merlin mine gate", not merlinSpawn(1000, 80, 2000, 4))
check("Merlin mine gate reached", merlinSpawn(1000, 80, 2000, 5))
check("Old Gold strict cheap threshold", not oldGoldSpawn(1, 30, 150, 4))
check("Old Gold cheap threshold reached", oldGoldSpawn(1, 30, 151, 4))
check("Old Gold reserve decays with round", oldGoldSpawn(1000, 50, 1350, 4))
check("Old Gold earlier reserve holds", not oldGoldSpawn(999, 50, 1350, 4))
checkEq("TSPAARK opening", tspaarkTarget(49, 200, 1, 0), 12)
checkEq("TSPAARK low bank", tspaarkTarget(50, 200, 1, 0), 8)
checkEq("TSPAARK extra kings", tspaarkTarget(50, 200, 3, 0), 24)
check("Powerpuff opening inclusive cap", powerpuffSpawn(100, 16, 50, 100, 1, 10.0))
check("Powerpuff poor bank", not powerpuffSpawn(101, 16, 50, 100, 1, 0.0))
check("Powerpuff strong income holds production", not powerpuffSpawn(101, 8, 30, 1000, 1, 4.0))
check("Powerpuff weak income recruits", powerpuffSpawn(101, 8, 30, 1000, 1, 3.0))
checkEq("SPAARK early ceiling", spaarkCostLimit(100, 30, 5000, 1, 100.0, false), 30)
checkEq("SPAARK nearby threat bonus", spaarkCostLimit(100, 30, 5000, 1, 100.0, true), 40)

# Complete games in both seats, legality and deterministic distinct traces.
var traces = initHashSet[string]()
for kind in kinds:
  let sheets = [baselineSheet(kind), baselineSheet(blScaffold)]
  for seat in 0 .. 1:
    let (w, outcome) = playGame(loadMap("DefaultSmall"), sheets, 0, seat, 2000, 0)
    check("complete game " & $kind & " seat " & $seat, not outcome.aborted and not w.running)
    check("recruited rats " & $kind, outcome.ratsBuilt[0] > 0)
    for r in w.liveRobots:
      check("legal body " & $kind, w.onTheMap(r.loc) and r.health > 0 and
            r.health <= UnitSpecs[r.unit].health and r.actionCooldown >= 0 and
            r.movementCooldown >= 0 and r.turningCooldown >= 0)
    if seat == 0: traces.incl(outcome.hashChain)
    echo $kind, " seat ", seat, ": rounds=", outcome.roundsPlayed,
      " winner=", outcome.winnerSlot, " rats=", outcome.ratsBuilt[0],
      " cheese=", outcome.cheeseTransferred[0], " catDamage=", outcome.catDamage[0]
  let (_, a) = playGame(loadMap("DefaultSmall"), sheets, 0, 0, 120, 0)
  let (_, b) = playGame(loadMap("DefaultSmall"), sheets, 0, 0, 120, 0)
  checkEq("fresh-game deterministic memory " & $kind, a.hashChain, b.hashChain)
checkEq("seven distinct complete trajectories", traces.len, 7)
finish("test_bc26_contenders")
