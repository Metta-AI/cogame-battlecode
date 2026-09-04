## The bc20 baselines: bounded, legal orders, and the D2 SURVIVAL GATE.
##
## D2 (sibling review finding, 2026-09-03): the scripted baseline has to PLAY.
## `bowl-of-chowder` walls its HQ, guns the air and terraforms, and this gate
## reads survival and positive play counters, not a win alone. A baseline that
## idled to a win fails (a) through (c).

import std/[sequtils, strutils]
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc20/[constants, maps, rules, world]
import battlecode/years/bc20/chassis/kit

const GateMaps = ["WateredDown", "ALandDivided"]
  ## Two `small`-pool maps. The episode seed only chooses maps and side
  ## assignment — the world RNG comes from the MAP's own `randomSeed` — so the
  ## six games are the two maps under three seeds' worth of side assignment,
  ## which is every distinct game those inputs can produce.
const GateSeeds = [1, 2, 3]

proc bocSheet(): Sheet = baselineSheet("bc20", blBowlOfChowder)
proc scaffoldSheet(): Sheet = baselineSheet("bc20", blExamplefuncsplayer)

# --- (a) both replies pass the SAME validate the LLM path uses --------------
block:
  for kind in [blBowlOfChowder, blExamplefuncsplayer]:
    let s = baselineSheet("bc20", kind)
    checkEq($kind & " applies no defaults", s.defaultsApplied.len, 0)
    checkEq($kind & " has no unknown fields", s.unknownFields.len, 0)
    check($kind & " names no chassis", "chassis" notin s.unknownFields)
    check($kind & "'s notes are under cap", s.notes.len > 0)
    check($kind & "'s motto is under cap", s.motto.len > 0)
    ## Every knob is in range by construction — `validate` would have recorded
    ## a repair otherwise, which the first check above forbids.
    let d = s.doctrine20
    check($kind & " terraform_start_round in range",
      d.terraformStartRound >= 1 and d.terraformStartRound <= 1500)
    check($kind & " lattice_radius in range",
      d.latticeRadius >= 2 and d.latticeRadius <= 12)
    check($kind & " vaporator_budget in range",
      d.vaporatorBudget >= 0 and d.vaporatorBudget <= 6)
    check($kind & " net_gun_ring in range",
      d.netGunRing >= 0 and d.netGunRing <= 6)
  checkEq("an unrecognised PLAYER_SCRIPTED takes the STRONG baseline",
    baselineFor("bc20", "nonsense"), blBowlOfChowder)
  checkEq("and `examplefuncsplayer` takes the weak floor",
    baselineFor("bc20", "examplefuncsplayer"), blExamplefuncsplayer)
  checkEq("the chassis follows the name, not the sheet",
    baselineChassis(blExamplefuncsplayer), parseChassisKind("examplefuncsplayer"))

# --- (b) every emitted action is legal, and the budget is never exceeded ----
proc assertInvariants(w: World, label: string) =
  ## Every state a legal action can leave the world in. An illegal `move`
  ## would put a ground unit in the water or two robots on one tile; an
  ## illegal `digDirt` would push a landscaper past its carry limit; an
  ## over-budget turn would leave `opsLeft` negative.
  var occupied: seq[int]
  for id, r in w.robotsById:
    check(label & ": " & $id & " is on the map", w.onTheMap(r.loc))
    check(label & ": " & $id & " never went below zero cooldown",
      r.cooldownTurns >= 0.0'f32)
    check(label & ": " & $id & " respected its DecisionOps budget",
      r.opsLeft >= 0 and r.opsLeft <= RobotSpecs[r.kind].decisionOps)
    check(label & ": " & $id & " is inside its carry limits",
      r.soupCarrying <= RobotSpecs[r.kind].soupLimit and
      (r.dirtCarrying <= RobotSpecs[r.kind].dirtLimit or
       r.kind.isBuilding()))
    if not r.blocked:
      check(label & ": " & $id & " is the occupant of its own tile",
        w.getRobot(r.loc) == r)
      let i = w.idx(r.loc)
      check(label & ": no two robots share a tile", i notin occupied)
      occupied.add(i)
      if not r.kind.canFly():
        check(label & ": " & $id & " is not standing in water",
          not w.isFlooded(r.loc))
    check(label & ": " & $id & " has a non-negative soup carry",
      r.soupCarrying >= 0 and r.dirtCarrying >= 0)
  for t in 0 .. 1:
    check(label & ": team " & $t & "'s pool never went negative",
      w.stats.soup[t] >= 0)
  for tx in w.txPool:
    check(label & ": every pooled transaction cost is positive", tx.cost > 0)
    checkEq(label & ": and carries exactly seven ints", tx.message.len, 7)

block:
  ## A real match, invariants checked every fifty rounds.
  let spec = loadMap("WateredDown")
  var w = newWorld(spec, 1500)
  var sides = newSides([bocSheet(), scaffoldSheet()],
    [parseChassisKind("bowl-of-chowder"), parseChassisKind("examplefuncsplayer")], 0)
  let chassis = [parseChassisKind("bowl-of-chowder"),
                 parseChassisKind("examplefuncsplayer")]
  for round in 1 .. 466:
    runRound(w, sides, chassis)
    if round mod 50 == 0:
      w.assertInvariants("round " & $round)
    if not w.running: break

# --- (c) THE SURVIVAL GATE --------------------------------------------------
var games = 0
var wins = 0
for seed in GateSeeds:
  for mapName in GateMaps:
    let sideAslot = ((seed shr 8) and 1) xor (games and 1)
    let spec = loadMap(mapName)
    let sheets = [bocSheet(), scaffoldSheet()]
    let chassis = [parseChassisKind("bowl-of-chowder"),
                   parseChassisKind("examplefuncsplayer")]
    let (w, o) = playGame(spec, sheets, chassis, 0, sideAslot, 1500, 0)
    let tag = mapName & "/seed" & $seed
    ## `GameOutcome20`'s arrays are re-indexed BY SEAT in `harvest`; the raw
    ## `TeamStats` and the event stream are BY TEAM, and which team seat 0
    ## drives alternates with `sideAslot`.
    let bocTeam = if sideAslot == 0: 0 else: 1
    inc games
    if o.winnerSlot == 0: inc wins

    ## Bowl of Chowder: it survives, and it survives BY PLAYING.
    check(tag & ": bowl-of-chowder's HQ is alive at the end", o.hqAlive[0])
    checkEq(tag & ": and it won", o.winnerSlot, 0)
    check(tag & ": it built at least six miners", o.minersBuilt[0] >= 6)
    check(tag & ": at least three landscapers", o.landscapersBuilt[0] >= 3)
    check(tag & ": at least one design school",
      w.stats.designSchoolsBuilt[bocTeam] >= 1)
    check(tag & ": at least one refinery or fulfillment center",
      w.stats.refineriesBuilt[bocTeam] +
      w.stats.fulfillmentBuilt[bocTeam] >= 1)
    check(tag & ": at least two net guns", o.netGunsBuilt[0] >= 2)
    check(tag & ": it moved at least ninety dirt", o.dirtMoved[0] >= 90)
    var wallClosed = false
    for e in w.events:
      if e.kind == "wall_closed" and e.a == bocTeam: wallClosed = true
    check(tag & ": and it emitted wall_closed", wallClosed)

    ## The scaffold ACTS — it is the deliberate weak floor and the oracle's
    ## other side, and it may not gain behaviour.
    check(tag & ": the scaffold built at least one miner",
      o.minersBuilt[1] >= 1)
    check(tag & ": and mined at least once", o.soupMined[1] >= 1)
    ## AND IT NEVER BROADCASTS. `examplefuncsplayer.tryBlockchain` builds
    ## `new int[10]`, and `assertCanSubmitTransaction` refuses anything whose
    ## length is not `BLOCKCHAIN_TRANSACTION_LENGTH = 7`. The design note asks
    ## for "a 7x123 transaction"; the upstream file sends ten ints and the
    ## engine throws them away, so this port reproduces the refusal rather
    ## than correcting the bot. Fixing it here would break the parity oracle,
    ## whose Java side is that same file.
    checkEq(tag & ": and never mints a transaction, exactly as upstream",
      o.transactionsMinted[1], 0)

checkEq("six games were played", games, 6)
checkEq("and bowl-of-chowder won every one", wins, 6)

# --- the long game: both HQs alive at round 1499 ----------------------------
block:
  ## The gate above ends when the scaffold drowns. A full-length game needs
  ## two survivors, so it is played bowl-of-chowder against itself: both HQs
  ## must still stand at the cap.
  let spec = loadMap("ALandDivided")
  let sheets = [bocSheet(), bocSheet()]
  let chassis = [parseChassisKind("bowl-of-chowder"),
                 parseChassisKind("bowl-of-chowder")]
  let (w, o) = playGame(spec, sheets, chassis, 0, 0, 1500, 0)
  checkEq("a bowl-of-chowder mirror runs to the cap", o.roundsPlayed, 1499)
  check("and both HQs are alive at round 1499", o.hqAlive[0] and o.hqAlive[1])
  check("both sides walled", (block:
    var closed: seq[int]
    for e in w.events:
      if e.kind == "wall_closed": closed.add(e.a)
    0 in closed and 1 in closed))
  w.assertInvariants("the mirror at the cap")

finish("test_bc20_baselines")
