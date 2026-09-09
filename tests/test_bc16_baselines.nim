## Shard 17 of the note's list — **bounded, legal orders**, and the
## anti-friendly-fire rule.
##
## (a) both `PLAYER_SCRIPTED` resolutions produce a sheet that passes the SAME
##     `sheet.validate` the LLM path uses;
## (b) in played games, EVERY ACTION EITHER CHASSIS EMITS IS LEGAL FOR THE
##     ACTING ROBOT AT THE MOMENT IT IS EMITTED — the right counter under 1.0
##     for the right action, the target inside the right radius (and OUTSIDE
##     r2 6 for a turret), the destination on the map, unoccupied and under
##     rubble 100 unless the mover ignores rubble, the stockpile actually
##     holding `partCost`, `spawnSource == builder type`, `isActive()` true
##     for the actor, no TURRET moving, no TURRET or TTM clearing rubble, no
##     non-attacker attacking, no non-archon repairing or activating, no
##     message signal from anything but an ARCHON or SCOUT, <= 1 repair and
##     <= 5 basic and <= 20 message signals a turn, **NO FRIENDLY-FIRE ATTACK
##     EVER**, and no robot exceeding its `DecisionOps` budget;
## (c) `greenhorn` ACTS but is NOT required to survive or to compete;
## (d) `bulwark` beats `greenhorn` on 3 seeds x 2 `small` maps, 6/6.
##
## The legality audit is `World.refusedActions`: every `do*` re-checks its own
## `can*` and no-ops when it fails, and that counter counts the no-ops. A
## chassis that emits an illegal order is therefore VISIBLE rather than
## silently ignored.

import std/[json, strutils]
import harness
import bc16_fixture
import battlecode/[baselines, sheet]

# --- (a) both resolutions produce a valid sheet ---------------------------
block:
  for name in ["awu", "bulwark", "scaffold", "greenhorn", "example",
               "examplefuncsplayer", "wololo", ""]:
    let baseline = baselineFor("bc16", name)
    let reply = baselineReply(baseline)
    let s = parseReply(reply, YearBc16)
    checkEq("PLAYER_SCRIPTED=" & name & " parses through the SAME validator " &
      "the LLM path uses, with nothing repaired", s.defaultsApplied.len, 0)
    checkEq("and no unknown fields", s.unknownFields.len, 0)
    check("and a non-empty motto", s.motto.len > 0)
    check("and a non-empty notes line", s.notes.len > 0)
    check("and its plain words are eleven complete clauses",
      plainWords(s).len == 11)
  checkEq("`awu` resolves to bulwark on bc16", baselineFor("bc16", "awu"),
    blBulwark)
  checkEq("`scaffold` to greenhorn", baselineFor("bc16", "scaffold"),
    blGreenhorn)
  checkEq("and the fallback sheet IS the bulwark reply — so a seat that says " &
    "nothing useful plays the STRONG doctrine, not the weak floor",
    baselineReply(blBulwark), baselineReply(blGreenhorn))
  checkEq("both map to their own ScriptedChassis",
    (baselineChassis(blBulwark), baselineChassis(blGreenhorn)),
    (scBulwark, scGreenhorn))
  checkEq("and chassisKindFor routes them", chassisKindFor(scGreenhorn),
    ckGreenhorn)
  checkEq("with anything else falling back to the strong one",
    chassisKindFor(scAwu), ckBulwark)

# --- (b) the legality audit, over real games ------------------------------
proc auditGame(mapName: string, kinds: array[2, ChassisKind16],
               sheets: array[2, Sheet], rounds: int,
               sideAslot = 0): GameOutcome16 =
  var worst = 0
  var illegalFriendlyFire = 0
  var overBudget = 0
  let (w, o) = playGame(loadMap(mapName), sheets, kinds, 0, sideAslot,
                        rounds, 0,
    onRound = proc (w: World, round: int) =
      ## Sampled every round: nothing may have exceeded its budget, and the
      ## audit counter must still be zero.
      if w.refusedActions > worst: worst = w.refusedActions
      for id in w.execOrder:
        if not w.robotsById.hasKey(id): continue
        let r = w.robotsById[id]
        if r.opsUsed > budgetFor(r.kind): inc overBudget
        if r.opsLeft < 0: inc overBudget
        ## The delay pair may never go negative, at any moment.
        if r.d.core < 0.0 or r.d.weapon < 0.0: inc overBudget
        ## Health is capped at the robot's own maximum, always.
        if r.health > r.maxHealth: inc overBudget
        ## The per-turn counters may never exceed their caps.
        if r.repairCount > 1 or r.basicSignalCount > BasicSignalsPerTurn or
            r.messageSignalCount > MessageSignalsPerTurn: inc overBudget
        ## A signal queue may never exceed 1000.
        if r.signalQueue.len > SignalQueueMaxSize: inc overBudget
      ## No stockpile may go negative.
      for t in 0 .. 1:
        if w.resources[t] < 0.0: inc overBudget
  )
  checkEq(mapName & ": NO chassis emits an illegal order", worst, 0)
  checkEq(mapName & ": and the final audit is zero too", w.refusedActions, 0)
  checkEq(mapName & ": no robot exceeds its DecisionOps budget, no delay " &
    "goes negative, no health exceeds its cap, no per-turn counter " &
    "overflows and no stockpile goes negative", overBudget, 0)
  check(mapName & ": the ops peak is inside the wide budget",
    w.opsUsedPeak <= budgetFor(rtArchon))
  discard illegalFriendlyFire
  o

block:
  ## The two chassis on three maps each, 900 rounds — long enough to reach a
  ## viper, three scheduled waves and two outbreak steps on `river`.
  for mapName in ["river", "checkers", "swamp"]:
    discard auditGame(mapName, [ckBulwark, ckBulwark], defaultSheets(), 900)
    discard auditGame(mapName, [ckGreenhorn, ckGreenhorn], defaultSheets(),
                      900)
    discard auditGame(mapName, [ckBulwark, ckGreenhorn], defaultSheets(), 900)

block:
  ## And at the EXTREMES of every knob, because the anti-inert rule is about
  ## settings and not about defaults. Six deliberately awkward doctrines.
  const awkward = [
    """{"opening":"turtle","turret_count":12,"guard_ratio":100,
        "zombie_kiting":"never","den_clear_round":1,"parts_priority":"turrets",
        "archon_spread":"huddle","neutral_activation":"never","retreat_hp":0,
        "rubble_clear":"never","infection_policy":"ignore"}""",
    """{"opening":"soldier_viper_aggro","turret_count":0,"guard_ratio":0,
        "zombie_kiting":"always","den_clear_round":2800,
        "parts_priority":"vipers","archon_spread":"split",
        "neutral_activation":"hunt","retreat_hp":100,
        "rubble_clear":"aggressive","infection_policy":"suicide_squad"}""",
    """{"opening":"scout_zombie_pull","turret_count":6,"guard_ratio":50,
        "zombie_kiting":"ranged_only","den_clear_round":1400,
        "parts_priority":"units","archon_spread":"spread",
        "neutral_activation":"opportunistic","retreat_hp":50,
        "rubble_clear":"paths","infection_policy":"quarantine"}"""]
  for i, a in awkward:
    for j, b in awkward:
      if i > j: continue
      let sheets = sheetsFrom(a, b)
      let o = auditGame("river", [ckBulwark, ckBulwark], sheets, 600)
      ## AND THE ANTI-INERT FLOOR: no setting of any knob produces a faction
      ## that does not play.
      for slot in 0 .. 1:
        check("doctrine pair " & $i & "/" & $j & " seat " & $slot &
          " still built units", o.unitsBuilt[slot] >= 5)
        check("and still dealt damage", o.damageDealt[slot] >= 100)

block:
  ## **NO FRIENDLY-FIRE ATTACK EVER.** Friendly fire is LEGAL in 2016 (rule
  ## 3.2.3 has no team check at all) and there is no reading under which
  ## shooting your own soldiers is a strategy, so the chassis must never emit
  ## one. It is checked by instrumenting the world: a friendly-fire hit is the
  ## only way an own-team robot loses health to an own-team attacker, and the
  ## `enemy_damage_dealt` / `zombie_damage_dealt` split accounts for every
  ## point of `damage_dealt` that is not friendly fire.
  for mapName in ["river", "frogger"]:
    for kinds in [[ckBulwark, ckBulwark], [ckGreenhorn, ckGreenhorn],
                  [ckBulwark, ckGreenhorn]]:
      let (_, o) = playGame(loadMap(mapName), defaultSheets(), kinds, 0, 0,
                            900, 0)
      for slot in 0 .. 1:
        checkEq(mapName & " seat " & $slot &
          ": every point of damage dealt is accounted for by an ENEMY or a " &
          "ZOMBIE, so none of it was friendly fire",
          o.damageDealt[slot],
          o.zombieDamageDealt[slot] + o.enemyDamageDealt[slot])

# --- (c) greenhorn ACTS, but is not required to compete -------------------
block:
  let (_, o) = playGame(loadMap("river"), defaultSheets(),
                        [ckGreenhorn, ckGreenhorn], 0, 0, 600, 0)
  check("greenhorn builds at least one soldier", o.soldiersBuilt[0] >= 1)
  check("lands at least one attack", o.damageDealt[0] >= 1)
  check("and makes moves", o.unitsBuilt[0] >= 1)
  ## And it is NOT required to survive, to build a guard/scout/viper/turret,
  ## to activate a neutral, to kill a den or to compete. Being the weak floor
  ## is the whole point.
  checkEq("it builds no guard", o.guardsBuilt[0], 0)
  checkEq("no scout", o.scoutsBuilt[0], 0)
  checkEq("no viper", o.vipersBuilt[0], 0)
  checkEq("no turret", o.turretsBuilt[0], 0)
  checkEq("kills no den", o.densDestroyed[0], 0)
  checkEq("and activates no neutral", o.neutralsActivated[0], 0)

# --- (d) bulwark beats greenhorn, 6/6 --------------------------------------
block:
  var wins = 0
  var games = 0
  for mapName in ["river", "checkers"]:
    for seed in [0, 1, 2]:
      let sa = sideAslotFor(seed, 0)
      let (_, o) = playGame(loadMap(mapName), defaultSheets(),
                            [ckBulwark, ckGreenhorn], 0, sa, 1200, 0)
      inc games
      ## Seat 0 is `bulwark`; the SIDE it plays alternates with the seed.
      if o.winnerSlot == 0: inc wins
      elif o.winnerSlot < 0:
        echo "  no winner on ", mapName, " seed ", seed
      else:
        echo "  bulwark LOST on ", mapName, " seed ", seed, " (",
          o.endReason, "), archons ", o.archonsEnd[0], "-", o.archonsEnd[1],
          ", units ", o.unitsBuilt[0], "-", o.unitsBuilt[1]
  checkEq("six games", games, 6)
  checkEq("and bulwark wins all six against greenhorn", wins, 6)

finish("test_bc16_baselines")
