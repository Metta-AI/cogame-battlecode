## The bc16 parts economy: the income formula, the map's parts, the den bounty
## and the net-worth sums the end ladder and the score read.
##
## Ported from `world/GameWorld.java:533-547` (`takeParts`,
## `adjustResources`), `:622-627` (the income) and `:745-796` (the den bounty,
## which is paid inside `visitAttackSignal` and therefore lives in
## `world.nim`) at commit `11a0b09f26a70da19f33a61ebec4ceaf6e161aa3`.
##
## **THE WHOLE ECONOMY IS THREE THINGS AND THIS FILE IS ALL OF THEM:**
##
## 1. `PARTS_INITIAL_AMOUNT = 300.0` per team, credited ONCE by the world's
##    constructor (`world.nim`);
## 2. `max(0.0, 2.0 - 0.01 * getRobotCount(team))` per team per round, added
##    A FIRST AND THEN B at the end of every round — so income falls linearly
##    with army size and REACHES EXACTLY ZERO AT 200 ROBOTS. That is why a
##    2016 army has a natural ceiling, and it is why the survival gate keys on
##    archons rather than on starvation;
## 3. the map's parts squares, which are ALL-OR-NOTHING and ARCHON-ONLY
##    (`takeParts`, in `world.nim`, called from exactly two places), plus
##    `DEN_PART_REWARD = 200.0` for whoever lands the killing blow on a den.
##
## Parts are never created after round 0 except by den bounties and never
## regenerate. There is no upkeep and no supply: the `bytecodeLimit` comment
## about "halved if the robot does not have sufficient supply upkeep" is a
## leftover from 2015 and no supply code exists in this engine.

import std/os
import world

export world

proc dataRoot*(): string =
  ## `/data` is where emscripten mounts the preloaded directory in the wasm
  ## bundle; `data` is the repo layout the container and the tests use.
  ##
  ## `getAppDir()` is DELIBERATELY not a candidate: under emscripten it walks
  ## `os.getApplAux`, whose `readlink("/proc/self/exe")` returns -1 and whose
  ## next line is a `Natural` conversion that raises before anything is opened.
  for candidate in ["data", "/data", "/workspace/battlecode/data"]:
    if dirExists(candidate / "maps" / "bc16"):
      return candidate
  "data"

func incomeFor*(w: World, t: Team): float64 =
  ## `Math.max(0.0, ARCHON_PART_INCOME - PART_INCOME_UNIT_PENALTY *
  ## getRobotCount(team))`, written in the engine's own order. Named float64
  ## vector: at 137 robots this is `0.6299999999999999`, NOT `0.63` -- `0.01`
  ## is not representable, `0.01 * 137` rounds a hair above `1.37`, and the
  ## JVM's own table (`data/bc16/tables.json`, `parts_income[137]`) says the
  ## same. The design note's rounded prose was wrong and the ENGINE is the
  ## authority (`tests/test_bc16_arith.nim`).
  max(0.0, ArchonPartIncome -
    PartIncomeUnitPenalty * float64(w.robotCountOf(t)))

proc addPartsIncome*(w: World) =
  ## Rule 4.2, in the engine's order: TEAM A'S STOCKPILE FIRST, then team B's.
  ## The order is unobservable today (the two are independent) and is kept
  ## anyway, because a future rule that reads one while writing the other
  ## would make it observable.
  for t in [teamA, teamB]:
    let gain = w.incomeFor(t)
    w.resources[ord(t)] += gain
    w.stats.partsIncomeTenths[ord(t)] += int(gain * 10.0)

func partsSquares*(w: World): int =
  for v in w.partsAt:
    if v > 0.0: result += 1

func rubbleMeanTenths*(w: World): int =
  if w.map.rubble.len == 0: return 0
  var total = 0.0
  for v in w.map.rubble: total += v
  int((total / float64(w.map.rubble.len)) * 10.0)
