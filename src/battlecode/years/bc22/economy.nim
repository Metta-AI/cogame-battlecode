## The bc22 lead-and-gold economy: mining, the passive `+2`, the every-20-rounds
## `+5` regeneration, and the laboratory's transmutation.
##
## THE ONE RULE THAT DECIDES THIS YEAR'S WHOLE ECONOMY is in
## `regenerateMapLead`: the map adds `ADD_LEAD = 5` every `ADD_LEAD_EVERY_ROUNDS
## = 20` rounds **only to a square whose value is `> 0`**. A miner that takes a
## square to zero has destroyed that deposit for the rest of the game — which is
## what makes `mine_floor` (§Decisions) a real economic knob rather than a
## nicety, and what the `-d:bc22BrokenChassis` negative control exists to prove
## (measured on the real engine: the example-bot mirror ran the whole `charge`
## map to zero lead at round **934**).
##
## THE ONE TRANSCENDENTAL IN THE YEAR is the laboratory rate,
## `(int)(20.0 - 18.0 * Math.exp(-k * n))` with `k` 0.02 / 0.01 / 0.005 by level
## and `n` the friendly robots inside the lab's r2 <= 53 (so `n` in 0..176). It
## is TABLED whole into `data/bc22/tables.json` by `tools/JavaBc22Tables.java`
## under the CI JDK 8 and read at run time, so the runtime path evaluates no
## `exp` at all. `fdlibmExp` — `StrictMath.exp` bit for bit, already in the tree
## for bc21's embezzle curve — regenerates the same table in
## `tests/test_bc22_economy.nim` and the test asserts the two agree, which is
## what keeps the committed file honest without putting a transcendental on the
## hot path.
##
## Measured level-1 rates: n=0 -> 2, n=3 -> 3, n=6 -> 4, n=10 -> 5, n=13 -> 6,
## n=21 -> 8, n=30 -> 10, n=40 -> 11, n=176 -> 19. **Alchemists prefer
## solitude.**

import std/[json, os]
import ../../sim_types, ../../fdlibm
import world

export world

const TransmuteMaxFriends* = 176
  ## The 177 squares inside r2 <= 53, minus the lab itself.

proc computeTransmuteRate*(level, n: int): int =
  ## The engine's own expression, evaluated through `fdlibmExp` (StrictMath's
  ## `exp`, bit for bit). USED ONLY TO BUILD THE TABLE — never on the hot path.
  let k = case level
    of 1: AlchemistLonelinessKL1
    of 2: AlchemistLonelinessKL2
    of 3: AlchemistLonelinessKL3
    else: return 0
  int(AlchemistLonelinessA - AlchemistLonelinessB * fdlibmExp(-k * float64(n)))

proc dataRoot*(): string =
  ## `/data` is where emscripten mounts the preloaded directory in the wasm
  ## bundle; `data` is the repo layout the container and the tests use.
  ##
  ## `getAppDir()` is DELIBERATELY not a candidate: under emscripten it walks
  ## `os.getApplAux`, whose `readlink("/proc/self/exe")` returns -1 and whose
  ## next line is a `Natural` conversion that raises before anything is opened.
  for candidate in ["data", "/data", "/workspace/battlecode/data"]:
    if dirExists(candidate / "maps" / "bc22"):
      return candidate
  "data"

proc loadTransmuteTable*(w: World) =
  ## Read `data/bc22/tables.json`'s `transmute_rate`. If the file is missing —
  ## which cannot happen in the image or the wasm bundle, both of which carry
  ## `data/` whole — the table is rebuilt from `fdlibmExp` rather than left at
  ## zero, because a rate of 0 would make gold free and that is a rules change,
  ## not a degradation.
  var loaded = false
  let path = dataRoot() / "bc22" / "tables.json"
  if fileExists(path):
    try:
      let doc = parseJson(readFile(path))
      let node = doc{"transmute_rate"}
      if node != nil and node.kind == JObject:
        for level in 1 .. 3:
          let row = node{$level}
          if row == nil or row.kind != JArray or
             row.len <= TransmuteMaxFriends:
            loaded = false
            break
          for n in 0 .. TransmuteMaxFriends:
            w.transmuteTable[level - 1][n] = row[n].getInt()
          loaded = true
    except CatchableError:
      loaded = false
  if not loaded:
    for level in 1 .. 3:
      for n in 0 .. TransmuteMaxFriends:
        w.transmuteTable[level - 1][n] = computeTransmuteRate(level, n)

func transmutationRateFor*(w: World, level, n: int): int =
  if level < 1 or level > 3: return 0
  w.transmuteTable[level - 1][max(0, min(n, TransmuteMaxFriends))]

proc transmutationRate*(w: World, r: Robot): int =
  ## `RobotControllerImpl.getTransmutationRate()`: `n` is
  ## `getNumVisibleFriendlyRobots(true)` — RECOMPUTED ON THE SPOT, not cached.
  if r.kind != rtLaboratory: return 0
  let n = w.updateNumVisibleFriendlyRobots(r)
  w.transmutationRateFor(r.level, n)

proc peekTransmutationRate*(w: World, r: Robot): int =
  ## The same rate WITHOUT touching the cached `numVisibleFriendlyRobots`. The
  ## viewer reads it once a frame and a readout must never mutate the sim: the
  ## cached counter is what the global CHARGE sorts on, and a render that
  ## refreshed it would change who dies.
  if r.kind != rtLaboratory: return 0
  var n = 0
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[r.kind].visionRadiusSquared):
    let other = w.getRobot(l)
    if other != nil and other.id != r.id and other.team == r.team:
      n += 1
  w.transmutationRateFor(r.level, n)

# ---------------------------------------------------------------------------
#  Mining
# ---------------------------------------------------------------------------

func canMineLead*(w: World, r: Robot, l: Loc): bool =
  ## `assertCanMineLead`: r2 <= 2 (the miner's own square and all eight
  ## neighbours — a diagonal neighbour is at r2 = 2) and on the map,
  ## action-ready, the type can mine, and the square holds AT LEAST 1.
  if not w.canActLocation(r, l): return false
  if not r.canActCooldown(): return false
  if not canMineType(r.kind): return false
  w.getLead(l) >= 1

func canMineGold*(w: World, r: Robot, l: Loc): bool =
  if not w.canActLocation(r, l): return false
  if not r.canActCooldown(): return false
  if not canMineType(r.kind): return false
  w.getGold(l) >= 1

proc doMineLead*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  ## Charge, then move EXACTLY ONE unit from the square to the team's reserve.
  ## A miner's action cooldown is 2 against a limit of 10, so on rubble-free
  ## ground this can happen FIVE TIMES in one turn.
  if not w.canMineLead(r, l):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  let before = w.getLead(l)
  w.setLead(l, before - 1)
  w.addLead(r.team, 1)
  let t = ord(r.team)
  w.stats.leadMined[t] += 1
  if before == 1: w.stats.squaresMinedDry[t] += 1
  r.minedThisTurn = true
  w.noteFirstAction(r, Bc22ActionMineLead)
  true

proc doMineGold*(w: World, r: Robot, l: Loc): bool {.discardable.} =
  if not w.canMineGold(r, l):
    w.refusedActions += 1
    return false
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  w.setGold(l, w.getGold(l) - 1)
  w.addGold(r.team, 1)
  w.stats.goldMined[ord(r.team)] += 1
  r.minedThisTurn = true
  w.noteFirstAction(r, Bc22ActionMineGold)
  true

# ---------------------------------------------------------------------------
#  Transmutation
# ---------------------------------------------------------------------------

proc canTransmute*(w: World, r: Robot): bool =
  if not r.canActCooldown(): return false
  if not canTransmuteType(r.kind): return false
  w.teamLead(r.team) >= w.transmutationRate(r)

proc doTransmute*(w: World, r: Robot): bool {.discardable.} =
  ## Charge the lab's own action cooldown through its square's rubble, deduct
  ## the rate in lead, add EXACTLY ONE gold. THE ONLY SOURCE OF GOLD IN THE GAME
  ## other than a reclaim drop.
  if not w.canTransmute(r):
    w.refusedActions += 1
    return false
  let rate = w.transmutationRate(r)
  w.addActionCooldownTurns(r, RobotSpecs[r.kind].actionCooldown)
  w.addLead(r.team, -rate)
  w.addGold(r.team, 1)
  let t = ord(r.team)
  w.stats.transmutes[t] += 1
  w.stats.goldTransmuted[t] += 1
  w.stats.leadSpentTransmuting[t] += rate
  if w.stats.goldTransmuted[t] == 1 or w.stats.goldTransmuted[t] mod 20 == 0:
    discard w.beat(BeatGoldMilestone, "gold_milestone", t,
                   w.stats.goldTransmuted[t], rate)
  w.noteFirstAction(r, Bc22ActionTransmute)
  true

# ---------------------------------------------------------------------------
#  The end-of-round economy
# ---------------------------------------------------------------------------

proc addPassiveLead*(w: World) =
  ## Rule 4a: `+2` to team A's reserve, THEN `+2` to team B's — the FIRST
  ## statement of `processEndOfRound`, i.e. BEFORE the anomaly. So an ABYSS on
  ## round *r* eats 10 % of a reserve that already includes that round's `+2`.
  w.addLead(teamA, PassiveLeadIncrease)
  w.addLead(teamB, PassiveLeadIncrease)

proc regenerateMapLead*(w: World) =
  ## Rule 4d: if `currentRound % 20 == 0`, add `+5` to every index of the lead
  ## array whose value is `> 0`. AFTER the anomaly. A square mined to zero is
  ## dead for the rest of the game.
  if w.currentRound mod AddLeadEveryRounds != 0: return
  for i in 0 ..< w.leadAt.len:
    if w.leadAt[i] > 0:
      w.leadAt[i] += AddLead
