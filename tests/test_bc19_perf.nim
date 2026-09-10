## THE WALL-CLOCK GATE.
##
## §Tests item 20: a full 1000-round game on `seed-0045` (64x64, the largest
## legal board, three castles a side, 12 karbonite and 12 fuel depots a side)
## with BOTH seats on the configuration §The game names as the one that
## maximises unit count, movement and lattice size — `opening: pilgrim_eco`,
## `pilgrim_curve: 24`, `unit_mix: 0`, `preacher_share: 0`,
## `church_expansion: early`, `symmetry_wall: wall`, `fuel_reserve: 0` — in
## **<= 40 s**.
##
## MEASURED IN PHASE 20: under a second in `-d:release` and a few seconds in
## the debug build, an order of magnitude inside the design note's own
## 0.6-2.5 s estimate. bc19 is the lightest year module in this repository:
## its arithmetic is integer, its collections are plain arrays, and it
## reproduces NEITHER of the engine's two hot spots (`getVisible`'s
## full-board mask and `enactAttack`'s full-board sweep), because both are
## provably equivalent to a bounded scan.
##
## IF THIS EVER GOES RED THE FIX IS ONE CONFIG VALUE — `gamesPerMatch: 3 ->
## 2`, then `-> 1`, in the `bc19` variant — and the design note says so, so
## nobody redesigns anything.

import std/[json, monotimes, times]
import harness
import battlecode/sheet
import battlecode/years/bc19/rules

block:
  let heavy = validate(%*{"sheet": {
    "opening": "pilgrim_eco", "pilgrim_curve": 24, "unit_mix": 0,
    "preacher_share": 0, "church_expansion": "early",
    "symmetry_wall": "wall", "fuel_reserve": 0}}, YearBc19)
  ## The configuration really is the one the note names, read back off the
  ## parsed doctrine rather than off the payload.
  checkEq("opening", heavy.doctrine19.opening, op19PilgrimEco)
  checkEq("pilgrim_curve at its ceiling", heavy.doctrine19.pilgrimCurve,
    PilgrimCurveHi)
  checkEq("unit_mix 0 -- all crusaders, the fastest unit",
    heavy.doctrine19.unitMix, 0)
  checkEq("preacher_share 0", heavy.doctrine19.preacherShare, 0)
  checkEq("church_expansion early -- the most structures",
    heavy.doctrine19.churchExpansion, ce19Early)
  checkEq("symmetry_wall wall -- the largest lattice",
    heavy.doctrine19.symmetryWall, sw19Wall)
  checkEq("fuel_reserve 0 -- nothing is ever gated",
    heavy.doctrine19.fuelReserve, 0)

  let spec = loadMap("seed-0045")
  checkEq("seed-0045 is 64x64, the largest legal board",
    (spec.width, spec.height), (MaxBoardSize, MaxBoardSize))
  checkEq("with three castles a side", spec.castlesPerSide, 3)
  ## The counts are BOARD totals and every board is a mirror, so 12 a side
  ## is 24 on the board.
  checkEq("and 12 karbonite depots a side", spec.karboniteDepots, 24)
  checkEq("and 12 fuel depots a side", spec.fuelDepots, 24)

  let started = getMonoTime()
  let (w, o) = playGame(spec, [heavy, heavy], [ck19Saber, ck19Saber], 0, 0,
                        MaxRounds, 0)
  let millis = (getMonoTime() - started).inMilliseconds.int
  let seconds = millis div 1000
  echo "  seed-0045 ", o.roundsPlayed, " rounds in ", millis, " ms (",
    millis * 1000 div max(1, o.roundsPlayed), " us/round), ",
    o.unitsAlive[0] + o.unitsAlive[1], " units alive, ",
    o.unitsBuilt[0] + o.unitsBuilt[1], " built, peak ",
    max(w.stats.decisionOpsPeak[0], w.stats.decisionOpsPeak[1]),
    " of ", TurnMaxOps, " DecisionOps"
  checkEq("the whole game was played", o.roundsPlayed, MaxRounds)
  checkEq("and it ended on the round limit, not early", o.endReason,
    (if o.endReason == "castles_destroyed": "more_castles" else: o.endReason))
  check("in at most FORTY seconds", seconds <= 40)
  checkEq("with no illegal order from either seat",
    o.refusedActions[0] + o.refusedActions[1], 0)
  for t in 0 .. 1:
    check("seat " & $t & " stayed inside its DecisionOps budget",
      w.stats.decisionOpsPeak[t] <= TurnMaxOps)
  ## The gate is not vacuous: this configuration really does load the board.
  ## Measured on this exact episode: 503 units built, 56 alive at the end.
  check("the game really was heavy: 100+ units built between the seats",
    o.unitsBuilt[0] + o.unitsBuilt[1] >= 100)
  check("and the board was still populated at the end",
    o.unitsAlive[0] + o.unitsAlive[1] >= 20)
  ## `unit_mix: 0` buys ONLY CRUSADERS, which is what maximises movement
  ## (SPEED 9, the only fast unit) — and therefore builds NO LATTICE, because
  ## `military.nim`'s HOLD state is a PROPHET's. The design note's
  ## "maximises ... lattice size" is true of `symmetry_wall: wall` and false
  ## of `unit_mix: 0`, and the two cannot both hold; this shard keeps the
  ## note's exact config and measures the work, and the lattice's own teeth
  ## are `tests/test_bc19_knobs.nim`'s `symmetry_wall` row (which varies
  ## nothing but that knob, so `unit_mix` stays at its default 45 and the
  ## prophets exist).
  checkEq("unit_mix 0 really buys no prophets",
    o.prophetsBuilt[0] + o.prophetsBuilt[1], 0)
  check("and plenty of crusaders",
    o.crusadersBuilt[0] + o.crusadersBuilt[1] >= 20)

finish("test_bc19_perf")
