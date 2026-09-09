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
## **PROVENANCE, so a future staleness is detectable (r1-F4).** Every number
## below was regenerated from the build that shipped and agrees, digit for
## digit, with `ci.yml` run **34322655506** (`main` @ `fbc7d345`, `test` job
## 102372608026), which printed
##
##   `HEALTHY games=6 notDestroyed=3 dens=14 median=2015 rounds=@[3000, 695,`
##   `3000, 707, 3000, 1030]`
##
## and, for the negative control, `median=873`. The per-map rows were re-read
## from the same six games in `-d:release`. **If the summary line this shard
## echoes ever stops matching the tables below, the tables are stale — that is
## the check.** The previous tables were measured before the den-breaking
## chassis iteration landed and were stale by 20 vs 14 dens, 2147 vs 2015
## median rounds and 1029 vs 873 on the control.
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
##   | zigzag   |    695 | archons_destroyed     |   58/63 |    5/8 |  0/0 |  3200/ 4100 |  8641/ 5188  |
##   | swamp    |   3000 | more_parts_net_worth  | 182/185 |  32/35 |  2/2 |     0/ 1200 | 13520/13204  |
##   | river    |    707 | archons_destroyed     |   65/67 |   7/16 |  0/0 |  6400/ 5400 | 12162/ 3608  |
##   | prisons  |   3000 | more_archons          | 212/177 |   17/9 |  0/2 |  4000/11000 |  8552/25724  |
##   | frogger  |   1030 | archons_destroyed     | 115/130 |  32/31 |  2/2 | 12700/16600 | 23628/13530  |
##   **3 of 6 end other than `archons_destroyed`; 14 dens killed; median 2015
##   rounds; weakest seat 58 units, 5 guards, 3608 damage.**
##
## HEALTHY, **before** the iteration (the previous session's measurement, kept
## here so the delta is on the record): 1 of 6, 6 dens killed, median 936.
##
## BROKEN (`-d:bc16BrokenChassis`, the same six maps): archons never build a
## GUARD and never repair, units ignore `infection_policy` entirely so every
## infected loss stands up inside the home ring, and the faction never commits
## to a den.
##
##   | map      | rounds | end reason        | units   | guards | dens | coll(10ths) | dmg          |
##   |----------|--------|-------------------|---------|--------|------|-------------|--------------|
##   | checkers |   1063 | archons_destroyed |   83/90 |    0/0 |  0/0 |  8000/12000 |  4149/11322  |
##   | zigzag   |    661 | archons_destroyed |   62/55 |    0/0 |  0/0 |  5100/ 3300 |  4411/ 5726  |
##   | swamp    |   1445 | archons_destroyed |   89/87 |    0/0 |  0/0 |     0/    0 |  8949/10257  |
##   | river    |    684 | archons_destroyed |   62/67 |    0/0 |  0/0 |  5000/ 6400 |  3333/ 7133  |
##   | prisons  |   1610 | archons_destroyed | 113/133 |    0/0 |  0/0 |  3000/10000 | 10388/15195  |
##   | frogger  |    602 | archons_destroyed |   88/78 |    0/0 |  0/0 | 13900/11100 |  6538/ 4746  |
##   **0 of 6; 0 dens killed; 0 guards; median 873 rounds; weakest seat 55
##   units and 3333 damage; and `swamp` collects NOTHING at all.**
##
## **Every committed floor still holds on these regenerated numbers**:
## `MinNotDestroyed` 2 <= 3, `MinUnitsBuilt` 25 <= 58, `MinDamageDealt`
## 1500 <= 3608, `MinGuardsBuilt` 2 <= 5, `MinDensKilled` 4 <= 14,
## `MinMedianRounds` 1000 <= 2015, parts income 1 <= 11724 tenths, and
## `swamp`'s pair-parts clause 1 <= 1200 tenths. No floor was moved to make
## that true.
##
## ============================================================================
##  WHICH CLAUSES DISCRIMINATE, AND WHICH ARE ANTI-DEGENERACY FLOORS (r1-F3)
## ============================================================================
##
## **Said plainly, because a floor set below what the named broken control
## already achieves does not discriminate, and reading the clause list as if
## every clause did is the mistake.** The floors are NOT fitted to the
## control: raising `MinDamageDealt` above the broken column's 3333 would put
## it above the HEALTHY weak seat's 3608, which is fitting a floor to noise
## and would redden healthy runs. So no floor moves and no clause is dropped —
## the LABELLING is corrected instead.
##
##   | clause | floor | healthy (worst) | broken control | discriminates? |
##   |---|---|---|---|---|
##   | ratio, not `archons_destroyed` | 2 of 6 | 3 of 6  | **0 of 6** | **YES** |
##   | guards built, seat/game          | 2      | 5       | **0**      | **YES** |
##   | dens killed, six maps            | 4      | 14      | **0**      | **YES** |
##   | `swamp` parts, across the pair   | 1 tenth| 1200    | **0**      | **YES** |
##   | units built, seat/game           | 25     | 58      | 55         | no      |
##   | damage dealt, seat/game          | 1500   | 3608    | 3333       | no      |
##   | parts income, seat/game          | 1 tenth| 11724   | 10621      | no      |
##   | median rounds                    | 1000   | 2015    | 873        | NOISE   |
##
## **The four YES clauses carry all of this gate's discriminating power**, and
## each is a HARD ZERO on the control: the broken chassis never builds a
## guard, never breaks a den, never ends a game other than
## `archons_destroyed`, and never walks an archon onto `swamp`'s far deposits.
##
## **The three `no` clauses are PURE ANTI-DEGENERACY FLOORS that the named
## broken control clears** — 55 units against a floor of 25, 3333 damage
## against 1500, 10 621 tenths of income against 1. They stay asserted,
## because what they catch is a chassis that stops acting AT ALL (the
## do-nothing sheet that wins because the opponent starved, the 2026-09-03
## finding), not this particular control. Calling them discriminating would be
## false.
##
## **The median floor sits INSIDE the control's own noise band, and that is
## stated rather than banked as coverage.** The previous session recorded the
## control's median as 1029, ABOVE the 1000 floor; the shipped build measures
## 873, BELOW it. A clause that lands on either side of its floor between two
## measurements of the same control is not discriminating, so it is counted
## here with the anti-degeneracy floors even though it does fire today.
##
## CI's own run says the same thing. Run 34322655506's control failed on
## SIXTEEN clauses; the eight it printed are all `guards built 0 < 2` plus
## `swamp: parts collected across the pair (tenths) 0 < 1`. **Not one printed
## failure is a units-built, damage-dealt, income or median failure.**
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
## part that keeps it honest. Which of them carry the discrimination and which
## are anti-degeneracy floors the control also clears is set out above — do
## not read the list as if every clause did both jobs (r1-F3).

import std/[algorithm, os, osproc, strutils]
import harness
import bc16_fixture

const
  ## Clause 1 — the MEASURED ratio, `max(1, 3 - 1)`.
  ## DISCRIMINATES: the broken control is 0 of 6.
  MinNotDestroyed = 2
  ## Clause 2 — substance, per seat, in EVERY game. Roughly half the weak
  ## seat's measured value, the bc23 r1-F21/F22 rule.
  ##
  ## Two of these three are ANTI-DEGENERACY FLOORS ONLY: the named broken
  ## control clears both, and they are not lowered or raised for it (see the
  ## header's "which clauses discriminate" table — raising the damage floor
  ## past the control's 3333 would put it above the healthy weak seat's 3608).
  MinUnitsBuilt = 25          ## anti-degeneracy: healthy 58, BROKEN 55 (passes)
  MinDamageDealt = 1500       ## anti-degeneracy: healthy 3608, BROKEN 3333 (passes)
  MinGuardsBuilt = 2          ## DISCRIMINATES: healthy 5, and BROKEN IS ZERO
  ## Clause 3 — den-breaking demonstrated, the axis `den_clear_round` exists
  ## for. The ruling's floor is 1; the measured healthy total is 14 and the
  ## broken control is ZERO, so 4 is three and a half times inside the
  ## measurement and still four times above the floor.
  ## DISCRIMINATES.
  MinDensKilled = 4
  ## Clause 4 — the measured median floor. Healthy 2015; the control measured
  ## 873 on the shipped build and 1029 on the previous session's, i.e. **this
  ## floor sits INSIDE the control's own noise band** and is counted as an
  ## anti-degeneracy floor, not as discrimination. Clauses 1 and 3, the guard
  ## clause and `swamp`'s pair-parts clause are what discriminate.
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
      "maps (measured 14; the broken control kills ZERO)",
      r.densKilled >= MinDensKilled)
    ## CLAUSE 4 — the measured median floor.
    check("the median game reaches at least " & $MinMedianRounds &
      " rounds (measured 2015)", r.medianRounds() >= MinMedianRounds)

  block:
    ## CLAUSE 5 — THE INVERTED CONTROL, and it is the part that keeps the gate
    ## honest. `-d:bc16BrokenChassis` makes the archons never build a GUARD
    ## and never repair, makes every unit ignore `infection_policy` so each
    ## infected loss stands up inside the home ring, and stops the faction ever
    ## committing to a den. It is EXACTLY the failure a "did it build units?"
    ## check would pass — the broken control still builds 55-133 units a side
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
