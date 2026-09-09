## THE ECONOMIC-SURVIVAL GATE, with an inverted control that MUST FAIL.
##
## §Tests item 18, the LEARNINGS 2026-09-03 pin, and the coordinator ruling of
## 2026-09-09 that re-pinned it to what the 2016 engine can actually deliver.
##
## **THE KEY DESIGN POINT, and it is bc16-specific: in this year a faction
## does not starve, IT GETS EATEN.** Parts income is unconditional (2 a round
## minus the army penalty) but the zombie schedule escalates by x3 and every
## unit lost uninfected becomes a wall while every unit lost infected becomes
## an enemy. So the gate keys on ARCHON SURVIVAL, ARMY COMPOSITION, DEN
## PROGRESS and INFECTION HYGIENE — and the `-d:bc16BrokenChassis` control
## proves it can go red.
##
## ============================================================================
##  THE MEASURED TABLES. Both, inline, as the ruling requires.
## ============================================================================
##
## `bulwark` vs `bulwark`, the all-defaults sheet, 3000 rounds, the six `small`
## maps, release Nim.
##
## HEALTHY, **after** the bounded den-breaking chassis iteration
## (`dens.nim`'s standing strike group of `DenStrikeGroup = 4` with
## `DenGarrison = 4` held back, the sticky den target, and the
## `DenPressureFloor` that commits while attackers are still alive):
##
##   | map      | rounds | end reason            | units   | guards | dens | coll(10ths) | dmg          |
##   |----------|--------|-----------------------|---------|--------|------|-------------|--------------|
##   | checkers |   3000 | more_archons          | 190/196 |  15/28 |  4/0 | 10000/10000 | 27864/11000  |
##   | zigzag   |    605 | archons_destroyed     |   57/53 |    5/9 |  0/0 |  5100/ 2900 |  5652/ 3675  |
##   | swamp    |   3000 | more_parts_net_worth  | 182/185 |  32/35 |  2/2 |     0/ 1200 | 13520/13204  |
##   | river    |    707 | archons_destroyed     |   65/67 |   7/16 |  0/0 |  6400/ 5400 | 12162/ 3608  |
##   | prisons  |   3000 | more_archons          | 212/177 |   17/9 |  0/2 |  4000/11000 |  8552/25724  |
##   | frogger  |   1294 | archons_destroyed     | 144/153 |  31/25 |  4/6 | 15200/16500 | 19969/28470  |
##   **3 of 6 end other than `archons_destroyed`; 20 dens killed; median 2147
##   rounds; weakest seat 53 units, 5 guards, 3608 damage.**
##
## HEALTHY, **before** the iteration (the previous session's measurement, kept
## here so the delta is on the record): 1 of 6, 6 dens killed, median 936.
##
## BROKEN (`-d:bc16BrokenChassis`, the same six maps): archons never build a
## GUARD and never repair, units ignore `infection_policy` entirely so every
## infected loss stands up inside the home ring, and the faction never commits
## to a den.
##
##   | map      | rounds | end reason        | units   | guards | dens | coll(10ths) |
##   |----------|--------|-------------------|---------|--------|------|-------------|
##   | checkers |   1063 | archons_destroyed |   83/90 |    0/0 |  0/0 |  8000/12000 |
##   | zigzag   |    996 | archons_destroyed |   82/79 |    0/0 |  0/0 |  4300/ 4700 |
##   | swamp    |   1445 | archons_destroyed |   89/87 |    0/0 |  0/0 |     0/    0 |
##   | river    |    684 | archons_destroyed |   62/67 |    0/0 |  0/0 |  5000/ 6400 |
##   | prisons  |   1610 | archons_destroyed |  113/133 |   0/0 |  0/0 |  3000/10000 |
##   | frogger  |    594 | archons_destroyed |   89/76 |    0/0 |  0/0 | 14400/12300 |
##   **0 of 6; 0 dens killed; 0 guards; median 1029 rounds; and `swamp`
##   collects NOTHING at all.**
##
## ============================================================================
##  WHY THE RATIO IS 2 OF 6 AND NOT THE NOTE'S 5 OF 6
## ============================================================================
##
## The design note asked that >= 5 of 6 mirror games end other than
## `archons_destroyed`. **That is not reachable on this engine's arithmetic,
## and the reason is not a chassis defect.** 2016 combat is extremely slow — a
## GUARD deals 1.5 doubled to 3.0 against a zombie once a round, a SOLDIER 4 at
## attackDelay 2 (2 a round), a TURRET 13 at attackDelay 3 (4.3 a round) —
## while a level-9 BIGZOMBIE has 1500 HP and 75 damage, so a single late
## BIGZOMBIE outlives roughly 350 turret-rounds. **A horde that overwhelms an
## unbroken den field is authentic 2016.**
##
## So the committed ratio is the MEASURED one, per the coordinator's ruling:
## `>= max(1, measuredHealthy - 1) = 2` of 6. **And the gate's anti-degeneracy
## work is done by substance floors rather than by the ratio**, which is the
## direct answer to the 2026-09-03 finding that mechanical episode checks pass
## degenerate matches: a champion once sheet-picked a do-nothing chassis and
## won because the opponent starved. All five clauses below are asserted, and
## **the whole gate comes back RED under `-d:bc16BrokenChassis`**, which is the
## part that keeps it honest.

import std/[algorithm, os, osproc, strutils]
import harness
import bc16_fixture

const
  ## Clause 1 — the MEASURED ratio, `max(1, 3 - 1)`.
  MinNotDestroyed = 2
  ## Clause 2 — substance, per seat, in EVERY game. Roughly half the weak
  ## seat's measured value, the bc23 r1-F21/F22 rule.
  MinUnitsBuilt = 25          ## measured weak seat 53 (broken 62)
  MinDamageDealt = 1500       ## measured weak seat 3608 (broken 3333)
  MinGuardsBuilt = 2          ## measured weak seat 5, and BROKEN IS ZERO
  ## Clause 3 — den-breaking demonstrated, the axis `den_clear_round` exists
  ## for. The ruling's floor is 1; the measured healthy total is 20 and the
  ## broken control is ZERO, so 4 is five times inside the measurement and
  ## still four times above the floor.
  MinDensKilled = 4
  ## Clause 4 — the measured median floor. Healthy 2147, broken 1029; 1000 is
  ## a pure anti-degeneracy floor with 2.1x headroom, and clauses 1-3 are what
  ## discriminate.
  MinMedianRounds = 1000

type GateResult = object
  games: int
  notDestroyed: int
  densKilled: int
  rounds: seq[int]
  failures: seq[string]

proc runGate(): GateResult =
  ## The six `small` maps, one mirror game each, all-defaults sheets, to the
  ## engine's own 3000-round cap.
  ##
  ## `perGameBudgetSeconds` is passed as ZERO **here and only here**, because
  ## `rules.playGame` treats 0 as UNBOUNDED. The convention the repo has been
  ## bitten by is about `match.nim:480`, which clamps
  ## `perGameBudgetSeconds` to `max(1, min(field, remaining))` ONE LEVEL UP —
  ## this shard never goes through `match.nim`.
  for mapName in poolNames("small"):
    let (w, o) = playGame(loadMap(mapName), defaultSheets(),
                          [ckBulwark, ckBulwark], 0, 0, 3000, 0)
    inc result.games
    result.rounds.add(o.roundsPlayed)
    result.densKilled += o.densDestroyed[0] + o.densDestroyed[1]
    if o.endReason != "archons_destroyed": inc result.notDestroyed
    let tag = mapName
    template want(name: string, got, floorAmount: int) =
      if got < floorAmount:
        result.failures.add(tag & ": " & name & " " & $got & " < " &
          $floorAmount)
    for slot in 0 .. 1:
      template wantSeat(name: string, got, floorAmount: int) =
        if got < floorAmount:
          result.failures.add(tag & " seat " & $slot & ": " & name & " " &
            $got & " < " & $floorAmount)
      wantSeat("units built", o.unitsBuilt[slot], MinUnitsBuilt)
      wantSeat("damage dealt", o.damageDealt[slot], MinDamageDealt)
      wantSeat("guards built", o.guardsBuilt[slot], MinGuardsBuilt)
      ## Parts income is the unconditional half of this year's economy: a
      ## faction with a live robot earns, so a zero here means the faction was
      ## annihilated outright.
      wantSeat("parts income (tenths)", o.partsIncomeTenths[slot], 1)
    ## Across the pair, on every map that HAS deposits: somebody walked an
    ## archon over one. `swamp` is why this is a pair assertion rather than a
    ## per-seat one — its 1 680 parts sit far from one side's opening square —
    ## and the BROKEN control collects nothing there at all.
    if o.partsOnMapStart > 0:
      want("parts collected across the pair (tenths)",
        o.partsCollectedTenths[0] + o.partsCollectedTenths[1], 1)
    ## Somebody has to still be holding an archon when the game ends.
    want("archons alive at the end across the pair",
      o.archonsEnd[0] + o.archonsEnd[1], 1)
    ## And the legality audit: neither chassis may emit an illegal order, at
    ## any knob setting, in any of the six games.
    if w.refusedActions != 0:
      result.failures.add(tag & ": " & $w.refusedActions &
        " refused (illegal) orders")

proc medianRounds(r: GateResult): int =
  var sorted = r.rounds
  sorted.sort()
  if sorted.len == 0: 0
  elif sorted.len mod 2 == 1: sorted[sorted.len div 2]
  else: (sorted[sorted.len div 2 - 1] + sorted[sorted.len div 2]) div 2

when defined(bc16BrokenChassis):
  ## THE NEGATIVE CONTROL, run as a SUBPROCESS by the healthy build below. It
  ## prints its verdict and exits NON-ZERO when the gate PASSES, because a
  ## gate that cannot fail is not a gate.
  when isMainModule:
    let r = runGate()
    var reasons: seq[string] = r.failures
    if r.notDestroyed < MinNotDestroyed:
      reasons.add("not-destroyed " & $r.notDestroyed & " < " &
        $MinNotDestroyed)
    if r.densKilled < MinDensKilled:
      reasons.add("dens killed " & $r.densKilled & " < " & $MinDensKilled)
    if r.medianRounds() < MinMedianRounds:
      reasons.add("median rounds " & $r.medianRounds() & " < " &
        $MinMedianRounds)
    echo "BROKEN-CONTROL games=", r.games, " notDestroyed=", r.notDestroyed,
      " dens=", r.densKilled, " median=", r.medianRounds(),
      " failures=", reasons.len
    for f in reasons[0 .. min(7, reasons.high)]:
      echo "  ", f
    if reasons.len == 0:
      quit("the broken chassis PASSED the survival gate; the gate is dead", 1)
    echo "BROKEN-CONTROL: correctly red"
else:
  let r = runGate()
  echo "HEALTHY games=", r.games, " notDestroyed=", r.notDestroyed,
    " dens=", r.densKilled, " median=", r.medianRounds(),
    " rounds=", r.rounds

  block:
    ## Clause 0 — the build really is the healthy one. A negative control that
    ## silently ran as the healthy chassis would prove nothing.
    let w = bare()
    check("this build is NOT the broken chassis", not w.brokenChassis)

  block:
    checkEq("six mirror games were played", r.games, 6)
    ## CLAUSE 1 — the MEASURED ratio, never the assumed one.
    check("at least " & $MinNotDestroyed & " of the 6 end other than " &
      "`archons_destroyed` (measured 3; the design note's 5 is not " &
      "reachable on this engine's arithmetic — see the header)",
      r.notDestroyed >= MinNotDestroyed)
    ## CLAUSE 2 — substance, in every game, on both sides.
    if r.failures.len > 0:
      for f in r.failures: echo "  GATE: ", f
    checkEq("both sides are non-trivial on units, damage, guards, income " &
      "and parts in every game, and neither emits an illegal order",
      r.failures.len, 0)
    ## CLAUSE 3 — den-breaking demonstrated.
    check("at least " & $MinDensKilled & " dens are killed across the six " &
      "maps (measured 20; the broken control kills ZERO)",
      r.densKilled >= MinDensKilled)
    ## CLAUSE 4 — the measured median floor.
    check("the median game reaches at least " & $MinMedianRounds &
      " rounds (measured 2147)", r.medianRounds() >= MinMedianRounds)

  block:
    ## CLAUSE 5 — THE INVERTED CONTROL, and it is the part that keeps the gate
    ## honest. `-d:bc16BrokenChassis` makes the archons never build a GUARD
    ## and never repair, makes every unit ignore `infection_policy` so each
    ## infected loss stands up inside the home ring, and stops the faction ever
    ## committing to a den. It is EXACTLY the failure a "did it build units?"
    ## check would pass — the broken control still builds 62-133 units a side
    ## — and it is the failure this year's two added knobs exist to prevent.
    ##
    ## CI runs it; a bare `nim r` of this file without a Nim on PATH skips it
    ## LOUDLY rather than reporting a pass it did not earn.
    let nim = findExe("nim")
    if nim.len == 0:
      echo "SKIP: no `nim` on PATH, so the negative control did not run"
      check("the negative control needs a Nim compiler", false)
    else:
      let out0 = getTempDir() / "bc16_broken_control"
      let cmd = nim & " c -d:release -d:bc16BrokenChassis --hints:off " &
        "--warnings:off --path:src --path:tests -o:" & out0 &
        " tests/test_bc16_survival.nim"
      let (buildLog, buildCode) = execCmdEx(cmd)
      checkEq("the broken control BUILDS", buildCode, 0)
      if buildCode != 0:
        echo buildLog
      else:
        let (runLog, runCode) = execCmdEx(out0)
        echo runLog.strip()
        checkEq("and it comes back RED against the gate", runCode, 0)
        check("having actually failed clauses", "failures=0" notin runLog)
        check("and it never built a guard or broke a den",
          "guards built" in runLog or "dens killed" in runLog)
        check("and it never reached the ratio",
          "notDestroyed=0" in runLog or "not-destroyed" in runLog)

  finish("test_bc16_survival")
