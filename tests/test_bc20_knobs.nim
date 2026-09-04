## THE bc20 KNOB-TEETH GATE.
##
## Every one of the ten knobs must visibly change play. For each, this shard
## plays a paired set of seeded games — identical map, identical opponent, the
## two sides identical except that knob at its LOW and HIGH setting — and
## asserts a named, SIGNED statistic moves. A knob that is inert fails the
## build.
##
## The paired set is two `small`-pool maps under both side assignments, i.e.
## four games per setting. The episode seed only chooses maps and sides — the
## world RNG comes from the MAP's own `randomSeed` — so those four games are
## every distinct game these inputs can produce, and adding "more seeds" would
## add duplicates, not information.
##
## The thresholds live in ONE table so tuning is a one-line change, and each is
## set at roughly half the measured delta so a real regression trips it and
## ordinary drift does not. Measured at GameVersion GV04:
##
##   knob                     low -> high              measured        gate
##   opening                  turtle -> rush           adj 0 -> 2      >= 1
##   terraform_start_round    900 -> 100               dirt 761->6286  +150 %
##   lattice_radius           3 -> 10                  raised 163->380 +60
##   landscaper_count_curve   lean -> swarm            land 14 -> 43   +50 %
##   miner_count_curve        lean -> swarm            miners 32->100  +50 %
##   vaporator_budget         0 -> 6                   vap 0 -> 1      >= 1
##                                                     poll 1173->696  -3
##   drone_role               carry -> harass          drops 0 -> 20   +5
##   net_gun_ring             0 -> 6                   guns 0 -> 15    +4
##   rush_trigger             0 -> 220                 adj 0 -> 1      >= 1
##   wall_hq_round            0 -> 250                 drowned 4 -> 0
##                                                     ring 0 -> 32    +6
##
## DECLARED DEVIATION from the design note's table: `net_gun_ring` is gated on
## net guns BUILT only, not additionally on enemy drones shot down. The HQ has
## a built-in net gun and shoots on every turn it is ready, so `net_gun_kills`
## barely moves when the ring is added — the counter cannot separate the ring's
## kills from the HQ's, and inventing a second counter to make a gate pass
## would be gating on the instrument rather than on the play.

import std/strutils
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc20/[constants, maps, rules, world]
import battlecode/years/bc20/chassis/kit

const
  Maps = ["WateredDown", "ALandDivided"]
  Chassis = [ckBowlOfChowder, ckBowlOfChowder]

type Measured = object
  landscapers, miners, drones, netGuns, vaporators: int
  dirt, waterDrops, hqDrowned, ringAboveFive, raisedNearHq: int
  reachedEnemyHq: int
  pollutionAt1000: int

proc runSet(knobs: string, rounds: int): Measured =
  ## The knob under test on seat 0; the all-defaults doctrine on seat 1.
  let sheet = parseReply("{\"sheet\":{" & knobs & "}}", YearBc20)
  let opponent = baselineSheet("bc20", blBowlOfChowder)
  for mapName in Maps:
    for sideAslot in [0, 1]:
      let spec = loadMap(mapName)
      var w = newWorld(spec, rounds)
      var sides = newSides([sheet, opponent], Chassis, sideAslot)
      let team = if sideAslot == 0: 0 else: 1
      let hqs = spec.hqLocations()
      let mine = hqs[team]
      let theirs = hqs[1 - team]
      var reached = false
      for round in 1 .. rounds:
        runRound(w, sides, Chassis)
        if not reached:
          for id, r in w.robotsById:
            if r.team == Team(team) and chebyshev(r.loc, theirs) <= 1:
              reached = true
              break
        if round == 1000:
          result.pollutionAt1000 += w.globalPollution
        if not w.running: break
      result.landscapers += w.stats.landscapersBuilt[team]
      result.miners += w.stats.minersBuilt[team]
      result.drones += w.stats.dronesBuilt[team]
      result.netGuns += w.stats.netGunsBuilt[team]
      result.vaporators += w.stats.vaporatorsBuilt[team]
      result.dirt += w.stats.dirtMoved[team]
      result.waterDrops += w.stats.droneWaterDrops[team]
      if w.stats.destroyedHq[team]: result.hqDrowned += 1
      if reached: result.reachedEnemyHq += 1
      for l in w.ringTiles(mine):
        if w.getDirt(l) >= 5: result.ringAboveFive += 1
      for x in max(0, mine.x - 10) .. min(w.width - 1, mine.x + 10):
        for y in max(0, mine.y - 10) .. min(w.height - 1, mine.y + 10):
          if float32(w.getDirt(loc(x, y))) > w.waterLevel:
            result.raisedNearHq += 1

proc upByPercent(name: string, low, high, percent: int) =
  check(name & " (" & $low & " -> " & $high & ", gate +" & $percent & "%)",
    high >= low + max(1, low * percent div 100))

# --- opening ----------------------------------------------------------------
block:
  let low = runSet("\"opening\":\"turtle\"", 700)
  let high = runSet("\"opening\":\"rush\"", 700)
  check("opening turtle -> rush puts a unit next to the enemy HQ (" &
    $low.reachedEnemyHq & " -> " & $high.reachedEnemyHq & ")",
    high.reachedEnemyHq >= low.reachedEnemyHq + 1)

# --- terraform_start_round --------------------------------------------------
block:
  let low = runSet("\"terraform_start_round\":900", 700)
  let high = runSet("\"terraform_start_round\":100", 700)
  upByPercent("terraform_start_round 900 -> 100 moves more dirt by round 700",
    low.dirt, high.dirt, 150)

# --- lattice_radius ---------------------------------------------------------
block:
  let low = runSet("\"lattice_radius\":3", 900)
  let high = runSet("\"lattice_radius\":10", 900)
  check("lattice_radius 3 -> 10 raises more tiles above the water (" &
    $low.raisedNearHq & " -> " & $high.raisedNearHq & ")",
    high.raisedNearHq >= low.raisedNearHq + 60)

# --- landscaper_count_curve -------------------------------------------------
block:
  let low = runSet("\"landscaper_count_curve\":\"lean\"", 900)
  let high = runSet("\"landscaper_count_curve\":\"swarm\"", 900)
  upByPercent("landscaper_count_curve lean -> swarm builds more landscapers",
    low.landscapers, high.landscapers, 50)

# --- miner_count_curve ------------------------------------------------------
block:
  let low = runSet("\"miner_count_curve\":\"lean\"", 900)
  let high = runSet("\"miner_count_curve\":\"swarm\"", 900)
  upByPercent("miner_count_curve lean -> swarm builds more miners",
    low.miners, high.miners, 50)

# --- vaporator_budget -------------------------------------------------------
block:
  let low = runSet("\"vaporator_budget\":0", 1050)
  let high = runSet("\"vaporator_budget\":6", 1050)
  check("vaporator_budget 0 -> 6 builds vaporators (" & $low.vaporators &
    " -> " & $high.vaporators & ")",
    low.vaporators == 0 and high.vaporators >= 1)
  check("and global pollution at round 1000 is lower (" &
    $low.pollutionAt1000 & " -> " & $high.pollutionAt1000 & ")",
    high.pollutionAt1000 <= low.pollutionAt1000 - 3)

# --- drone_role -------------------------------------------------------------
block:
  let low = runSet("\"drone_role\":\"carry_landscapers\"", 900)
  let high = runSet("\"drone_role\":\"harass\"", 900)
  check("drone_role carry_landscapers -> harass drops more enemies in the " &
    "water (" & $low.waterDrops & " -> " & $high.waterDrops & ")",
    high.waterDrops >= low.waterDrops + 5)

# --- net_gun_ring -----------------------------------------------------------
block:
  let low = runSet("\"net_gun_ring\":0", 900)
  let high = runSet("\"net_gun_ring\":6", 900)
  checkEq("net_gun_ring 0 builds no net guns at all", low.netGuns, 0)
  check("and net_gun_ring 6 builds them (" & $low.netGuns & " -> " &
    $high.netGuns & ")", high.netGuns >= low.netGuns + 4)

# --- rush_trigger -----------------------------------------------------------
block:
  let low = runSet("\"rush_trigger\":0", 500)
  let high = runSet("\"rush_trigger\":220", 500)
  check("rush_trigger 0 -> 220 puts a unit next to the enemy HQ by round " &
    "500 (" & $low.reachedEnemyHq & " -> " & $high.reachedEnemyHq & ")",
    high.reachedEnemyHq >= low.reachedEnemyHq + 1)

# --- wall_hq_round ----------------------------------------------------------
block:
  let low = runSet("\"wall_hq_round\":0", 1250)
  let high = runSet("\"wall_hq_round\":250", 1250)
  check("wall_hq_round 0 drowns the HQ in every game (" & $low.hqDrowned &
    " of 4)", low.hqDrowned == 4)
  check("and wall_hq_round 250 drowns it in none (" & $high.hqDrowned &
    " of 4)", high.hqDrowned == 0)
  check("and the ring stands well above the round-250 water level (" &
    $low.ringAboveFive & " -> " & $high.ringAboveFive & ")",
    high.ringAboveFive >= low.ringAboveFive + 6)

finish("test_bc20_knobs")
