## Shard 11 of the note's list — **the end ladder**.
##
## `archons_destroyed` fires MID-TURN inside the death path and the round
## still finishes; both factions annihilated in one round resolves to the one
## whose last archon died SECOND (the `winner == null` guard), by exec order;
## `timeLimitReached()` is `currentRound >= rounds - 1`, so **round 2999 IS
## PLAYED**; the four rungs fire in the engine's order on EXACT float64
## differences; rung 4 awards **B on a 0-0 archon-id tie**; a faction with one
## archon and no other robot plays on to the last round and still earns parts;
## and `resign()` is provably unreachable from any chassis.

import std/strutils
import harness
import bc16_fixture

# --- archons_destroyed fires MID-TURN and the round still finishes --------
block:
  let w = bare(rounds = 60, maxRounds = 60)
  let a = w.at(3, 15)
  let survivor = w.put(rtSoldier, loc(20, 20), teamA)
  check("the world is running", w.running)
  w.changeHealthLevel(a, -5000.0, dcNormal)
  check("a winner is set the instant the last archon dies", w.hasWinner)
  checkEq("and it is the opponent", w.winner, teamB)
  checkEq("with DESTROYED", w.domination, dfDestroyed)
  checkEq("which this repo spells archons_destroyed", $dfDestroyed,
    "archons_destroyed")
  check("but `running` is STILL TRUE — the round plays out", w.running)
  ## Every robot after the killer in the exec order still takes its turn.
  survivor.d.weapon = 0.0
  check("and a survivor can still act", w.doAttack(survivor, loc(21, 20)))

block:
  ## `visitDeathSignal` returns immediately if `!running`: once the round has
  ## ended, deaths stop being processed.
  let w = bare()
  let a = w.at(3, 15)
  w.running = false
  let victim = w.put(rtGuard, loc(10, 10), teamA)
  w.visitDeathSignal(victim, dcNormal)
  check("a death after the game ended leaves the board alone",
    w.getRobot(loc(10, 10)) != nil)
  discard a

# --- both factions annihilated in one round -------------------------------
block:
  ## The second `setWinner` is guarded by `winner == null`, so THE FIRST
  ## FACTION TO LOSE ITS LAST ARCHON LOSES, and the other wins even if it dies
  ## later in the same round. Ordering follows the exec order.
  let w = bare()
  let a = w.at(3, 15)
  let b = w.at(26, 15)
  w.changeHealthLevel(a, -5000.0, dcNormal)
  checkEq("A died first, so B wins", w.winner, teamB)
  w.running = true                 ## the round is still playing out
  w.changeHealthLevel(b, -5000.0, dcNormal)
  checkEq("and B dying later in the same round does NOT flip it", w.winner,
    teamB)
  checkEq("both are gone", w.archonsAlive(teamA) + w.archonsAlive(teamB), 0)

# --- the round limit -------------------------------------------------------
block:
  ## `timeLimitReached()` is `currentRound >= rounds - 1`, and rounds are
  ## 0-BASED: the first round played is 0 and the last is `rounds - 1`.
  let w = bare(rounds = 3000, maxRounds = 3000)
  checkEq("currentRound starts at -1", w.currentRound, -1)
  w.currentRound = 2998
  check("round 2998 has not reached the limit", not w.timeLimitReached())
  w.currentRound = 2999
  check("round 2999 HAS — so round 2999 is played and then judged",
    w.timeLimitReached())

# --- the four rungs, in the engine's order --------------------------------
proc ladderWorld(archonsA, archonsB: int): World =
  ## One soldier a side always, so `robots` is never empty (an empty list
  ## makes the fixture fall back to its default archon pair) and so rungs 3
  ## and 4 are level by construction.
  var robots = @[
    (x: 10, y: 20, kind: ord(rtSoldier), team: ord(teamA)),
    (x: 19, y: 20, kind: ord(rtSoldier), team: ord(teamB))]
  for i in 0 ..< archonsA:
    robots.add((x: 3, y: 5 + i * 3, kind: ord(rtArchon), team: ord(teamA)))
  for i in 0 ..< archonsB:
    robots.add((x: 26, y: 5 + i * 3, kind: ord(rtArchon), team: ord(teamB)))
  result = bare(robots = robots, rounds = 100, maxRounds = 100)
  result.currentRound = 99

block:
  ## Rung 1: more ARCHONs -> PWNED -> `more_archons`.
  let w = ladderWorld(2, 1)
  w.checkEndOfMatch()
  checkEq("more archons wins on rung 1", w.winner, teamA)
  checkEq("with PWNED", w.domination, dfPwned)
  checkEq("spelled more_archons", $dfPwned, "more_archons")
  checkEq("and the game stops", w.running, false)
  checkEq("and the rung is recorded", w.tiebreakRung, ord(dfPwned))

block:
  ## Rung 2: archons level, greater TOTAL LIVE-ARCHON HEALTH -> OWNED.
  let w = ladderWorld(1, 1)
  w.at(26, 5).health = 500.0
  w.checkEndOfMatch()
  checkEq("more archon health wins on rung 2", w.winner, teamA)
  checkEq("with OWNED", w.domination, dfOwned)
  checkEq("spelled more_archon_health", $dfOwned, "more_archon_health")

block:
  ## Rung 3: health level, greater `parts + sum(partCost)` -> BARELY_BEAT.
  let w = ladderWorld(1, 1)
  discard w.put(rtViper, loc(10, 10), teamA)
  w.checkEndOfMatch()
  checkEq("more parts net worth wins on rung 3", w.winner, teamA)
  checkEq("with BARELY_BEAT", w.domination, dfBarelyBeat)
  checkEq("spelled more_parts_net_worth", $dfBarelyBeat,
    "more_parts_net_worth")

block:
  ## Rung 3 is an EXACT float64 difference: a 0.1-part edge decides it, and
  ## that is the case where the WINNER and the tenths-narrowed POINTS can
  ## legitimately disagree.
  let w = ladderWorld(1, 1)
  w.adjustResources(teamA, 0.1)
  w.checkEndOfMatch()
  checkEq("a 0.1-part edge decides rung 3 on an exact float64 difference",
    w.winner, teamA)
  checkEq("with BARELY_BEAT", w.domination, dfBarelyBeat)

block:
  ## Rung 4: everything level -> higher MAXIMUM LIVE ARCHON ID -> dubious.
  let w = ladderWorld(1, 1)
  w.checkEndOfMatch()
  checkEq("everything level falls to rung 4", w.domination, dfDubious)
  checkEq("spelled highest_id", $dfDubious, "highest_id")
  let idA = w.highestArchonId(teamA)
  let idB = w.highestArchonId(teamB)
  checkEq("and the higher id took it",
    w.winner, (if idA > idB: teamA else: teamB))

block:
  ## Rung 4's `else` branch awards **B** — so a 0-vs-0 archon-id tie (both
  ## teams archon-less) goes to Clan Basil. Reachable only if both were
  ## annihilated in the same round without a winner having been set.
  let w = ladderWorld(0, 0)
  checkEq("neither team has an archon", w.highestArchonId(teamA), 0)
  checkEq("nor the other", w.highestArchonId(teamB), 0)
  w.checkEndOfMatch()
  checkEq("and a 0-0 id tie goes to B", w.winner, teamB)
  checkEq("with the dubious factor", w.domination, dfDubious)

# --- a lone archon plays on -----------------------------------------------
block:
  ## There is NO elimination for losing your army: a faction with one archon
  ## and nothing else plays on to the last round earning parts.
  let w = bare(rounds = 40, maxRounds = 40)
  let sheets = defaultSheets()
  let sides = newSides16(sheets, 0)
  let before = w.teamParts(teamA)
  for i in 0 ..< 10:
    runRound(w, sides, [ckGreenhorn, ckGreenhorn])
  check("A still has an archon", w.archonsAlive(teamA) >= 1)
  check("and it kept earning parts",
    w.teamParts(teamA) + 500.0 > before)      ## it also SPENDS them
  check("and the game is still running", w.running)

# --- resign() is unreachable from any chassis -----------------------------
block:
  ## `rc.resign()` is a real engine method and it is UNREACHABLE HERE, not
  ## absent upstream (V5). A doctrine is a JSON sheet; the sheet has eleven
  ## knobs and none of them is an action; and neither chassis source contains
  ## the word.
  let known = KnownKeys16
  checkEq("the sheet has exactly eleven knobs", known.len, 11)
  check("and none of them is `resign`", "resign" notin @known)
  for path in ["src/battlecode/years/bc16/chassis/bulwark.nim",
               "src/battlecode/years/bc16/chassis/greenhorn.nim",
               "src/battlecode/years/bc16/chassis/combat.nim",
               "src/battlecode/years/bc16/chassis/archon.nim",
               "src/battlecode/years/bc16/chassis/micro.nim"]:
    check(path & " contains no resign call",
      "resign" notin readFile(path).toLowerAscii())
  check("and the world exposes no resign primitive at all",
    "proc doResign" notin readFile("src/battlecode/years/bc16/world.nim"))
  ## And the end-reason vocabulary has no `resignation` value.
  var reasons: seq[string]
  for d in Domination: reasons.add($d)
  check("`resignation` is not an end reason", "resignation" notin reasons)
  check("and neither is `zombified` (armageddon-only, V4)",
    "zombified" notin reasons)
  check("nor `cleansed`", "cleansed" notin reasons)

# --- `dfNone` FAULTS, it does not get relabelled --------------------------
block:
  ## `dfNone` is "no winner at all" and it is unreachable in the shipped
  ## configuration — `checkEndOfMatch` always sets a winner and
  ## `config_schema.maxRounds.minimum` is 50. It used to be rendered as
  ## `$dfPwned` (`more_archons`), i.e. an impossible state reporting a
  ## plausible answer into a shipped replay (r1-F8). It now faults.
  let w = bare(rounds = 60, maxRounds = 60)
  checkEq("a fresh world has no domination factor yet", w.domination, dfNone)
  check("and `endReasonFor` REFUSES to name one", (block:
    var raised = false
    try:
      discard w.endReasonFor()
    except Defect:
      raised = true
    raised))
  ## And a real winner still round-trips through the same proc.
  w.setWinner(teamB, dfBarelyBeat)
  checkEq("while a decided game reports its own rung",
    w.endReasonFor(), "more_parts_net_worth")
  check("which is never `more_archons` by accident",
    w.endReasonFor() != $dfPwned)

finish("test_bc16_endladder")
