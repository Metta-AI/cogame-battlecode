## `examplefuncsplayer19` — THE WEAK FLOOR, STATEMENT FOR STATEMENT.
##
## §Tests item 16. This bot is ONE SIDE OF THE DIFFERENTIAL PARITY ORACLE:
## `parity-oracle-bc19`'s Tier A" plays the patched engine's own copy of
## `coldbrew/bots/example_js/robot.js` against this port, bit-exact, on all
## nine parity pairs. **IT MAY NOT GAIN BEHAVIOUR**, and this file is the
## gate that says so: it pins the whole behaviour, the RNG call sequence and
## the branch order, so a "small improvement" to the weak floor turns this
## test red before it turns the oracle red.
##
## Its whole behaviour, after the two committed patch hunks:
##
##   1. a per-robot `step` counter starting at **-1**, incremented at the
##      top of every turn, so a robot's FIRST turn has `step == 0`;
##   2. a CASTLE: on every turn where `step % 10 == 0`,
##      `buildUnit(CRUSADER, 1, 1)`; otherwise nothing. **Patch hunk 2**
##      removes the stock `if (this.me.team == 1)` guard, so BOTH teams
##      build — the stock bot leaves RED completely inert;
##   3. a CRUSADER: `move(choice)` where `choice` is
##      `choices[floor(rng() * 8)]` over the engine's own
##      `[[0,-1],[1,-1],[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1]]` —
##      N, NE, E, SE, S, SW, W, NW. **Patch hunk 1** replaces the
##      wall-clock-seeded global `Math.random()` with one
##      `java.util.Random` SEEDED FROM THE ROBOT'S OWN ID;
##   4. a PILGRIM, a PROPHET, a PREACHER and a CHURCH do **nothing at all**.
##
## THE RNG IS ASSERTED THROUGH TWO INDEPENDENT ORACLES, not through the
## module under test:
##
##   * an INLINE `java.util.Random` written from the specification in this
##     file (a 48-bit LCG with the published multiplier, addend and mask),
##     which shares no code with `src/battlecode/rng.nim`;
##   * and that inline implementation is itself checked against
##     `tests/fixtures/java_random_vectors.json`, which
##     `tools/JavaRandomVectors.java` records under a real JDK.
##
## So the chain is: real JVM -> committed vectors -> this file's inline LCG
## -> the chassis's draws. A drift anywhere in it is a failure here.

import std/[json, os, strutils]
import harness
import bc19_fixture
import battlecode/years/bc19/chassis/examplefuncsplayer19

# ---------------------------------------------------------------------------
#  The inline oracle: java.util.Random, from the specification
# ---------------------------------------------------------------------------

type Lcg = object
  state: uint64
    ## `uint64`, not `int64`: Java's `seed * 0x5DEECE66D` WRAPS, and the same
    ## multiply in a Nim `int64` raises `OverflowDefect` in a debug build.
    ## The 48-bit mask makes the two identical.

const
  Mult = 0x5DEECE66D'u64
  Add = 0xB'u64
  Mask = (1'u64 shl 48) - 1

proc initLcg(seed: int): Lcg =
  Lcg(state: (cast[uint64](int64(seed)) xor Mult) and Mask)

proc next(g: var Lcg, bits: int): uint64 =
  g.state = (g.state * Mult + Add) and Mask
  g.state shr uint64(48 - bits)

proc nextDoubleLcg(g: var Lcg): float64 =
  ## `((next(26) << 27) + next(27)) * 2^-53`, the published definition. Both
  ## halves are non-negative here, so no sign extension is involved.
  let hi = g.next(26)
  let lo = g.next(27)
  float64((hi shl 27) + lo) * (1.0 / float64(1'u64 shl 53))

block:
  ## THE INLINE ORACLE IS ITSELF CHECKED, against the recorded JVM vectors.
  ## `next_double` is stored as the exact IEEE-754 bit pattern, because this
  ## port exists so two streams line up draw for draw and "close enough" is
  ## a silent, match-long divergence.
  let path = currentSourcePath().parentDir() / "fixtures" /
    "java_random_vectors.json"
  check("the recorded JVM vectors are present", fileExists(path))
  let doc = parseJson(readFile(path))
  var seedsChecked = 0
  for entry in doc["seeds"]:
    let seed = entry["seed"].getInt()
    var g = initLcg(seed)
    var i = 0
    var bad = 0
    for want in entry["next_double"]:
      let got = nextDoubleLcg(g)
      if cast[int64](got) != want.getBiggestInt(): inc bad
      inc i
      if i >= 200: break
    checkEq("this file's inline LCG matches the JVM for seed " & $seed,
      bad, 0)
    check("and it really compared draws", i >= 100)
    inc seedsChecked
  check("several seeds were checked", seedsChecked >= 4)

# ---------------------------------------------------------------------------
#  1. THE `step` COUNTER STARTS AT -1
# ---------------------------------------------------------------------------
block:
  var w = board("seed-0043")
  let castle = w.robots[0]
  checkEq("a fresh robot's `step` is -1", castle.step, -1)
  checkEq("and every robot's is", w.robots[w.robots.len - 1].step, -1)
  ## The first turn takes it to 0, which is why a castle builds IMMEDIATELY.
  let first = runExamplefuncsplayer19(w, castle)
  checkEq("the first turn takes `step` to 0", castle.step, 0)
  check("and `step % 10 == 0` fires on it", first.hasAction)
  checkEq("with a build", first.kind, akBuild)

# ---------------------------------------------------------------------------
#  2. THE CASTLE: a CRUSADER at (1,1), every tenth turn, ON BOTH TEAMS
# ---------------------------------------------------------------------------
block:
  for team in [tRed, tBlue]:
    var w = board("seed-0043")
    var castle: Robot = nil
    for r in w.robots:
      if r.team == team and r.unit == ukCastle: castle = r
    check("a " & (if team == tRed: "red" else: "blue") & " castle exists",
      not castle.isNil)
    var builtOn: seq[int]
    for turn in 0 ..< 35:
      let a = runExamplefuncsplayer19(w, castle)
      if a.hasAction:
        checkEq("the only action a castle ever takes is a build", a.kind,
          akBuild)
        checkEq("of a CRUSADER", a.buildUnit, ukCrusader)
        checkEq("at dx 1", a.dx, 1)
        checkEq("and dy 1", a.dy, 1)
        builtOn.add(castle.step)
      checkEq("and it never signals", a.signalRadius, 0)
      checkEq("nor sends castle talk", a.castleTalk, 0)
      checkEq("nor trades", a.kind == akTrade, false)
    checkEq("PATCH HUNK 2: " & (if team == tRed: "RED" else: "BLUE") &
      " builds on steps 0, 10, 20, 30", builtOn, @[0, 10, 20, 30])

# ---------------------------------------------------------------------------
#  3. THE CRUSADER'S DIRECTION DRAW
# ---------------------------------------------------------------------------
block:
  ## The list is the engine's own, verbatim and in order.
  checkEq("eight choices", Choices.len, 8)
  const Compass = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
  const Want: array[8, tuple[dx, dy: int]] = [
    (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
  for i in 0 ..< 8:
    checkEq("choice " & $i & " is " & Compass[i], Choices[i], Want[i])
  ## Every one is a legal `dx`/`dy` for a CRUSADER: non-zero, r^2 <= SPEED 9.
  for c in Choices:
    check("a choice is never (0,0)", c.dx != 0 or c.dy != 0)
    check("and is inside a crusader's SPEED",
      c.dx * c.dx + c.dy * c.dy <= speedOf(ukCrusader))

block:
  ## THE DRAW SEQUENCE, per robot, against the inline oracle. The RNG is
  ## created ONCE PER ROBOT and seeded from that robot's own id, exactly as
  ## the patched JavaScript creates it on the bot's first turn.
  var w = board("seed-0043")
  let castle = w.robots[0]
  ## Place three crusaders with distinct ids and drive each for 40 turns.
  var crusaders: seq[Robot]
  for dy in -1 .. 1:
    for dx in -1 .. 1:
      if dx == 0 and dy == 0: continue
      if crusaders.len >= 3: continue
      if w.isPassable(castle.x + dx, castle.y + dy) and
          w.shadowAt(castle.x + dx, castle.y + dy) == 0:
        crusaders.add w.createItem(castle.x + dx, castle.y + dy, castle.team,
                                   ukCrusader)
  checkEq("three crusaders were placed", crusaders.len, 3)
  var ids: seq[int]
  for c in crusaders: ids.add c.id
  check("with distinct ids", ids[0] != ids[1] and ids[1] != ids[2] and
    ids[0] != ids[2])
  for c in crusaders:
    var oracle = initLcg(c.id)
    for turn in 0 ..< 40:
      let want = Choices[int(nextDoubleLcg(oracle) * 8.0)]
      let a = runExamplefuncsplayer19(w, c)
      check("a crusader always acts", a.hasAction)
      checkEq("and it is always a MOVE", a.kind, akMove)
      checkEq("id " & $c.id & " turn " & $turn & " dx", a.dx, want.dx)
      checkEq("id " & $c.id & " turn " & $turn & " dy", a.dy, want.dy)
      checkEq("and it never signals", a.signalRadius, 0)
      checkEq("nor sends castle talk", a.castleTalk, 0)
  ## THE STREAMS ARE INDEPENDENT: the same id in a fresh world replays
  ## identically, and two different ids diverge.
  var w2 = board("seed-0043")
  let solo = w2.createItem(crusaders[0].x, crusaders[0].y, castle.team,
                           ukCrusader)
  solo.id = crusaders[0].id
  var replay: seq[int]
  var oracle2 = initLcg(solo.id)
  for turn in 0 ..< 20:
    let a = runExamplefuncsplayer19(w2, solo)
    replay.add(a.dx * 10 + a.dy)
    let want = Choices[int(nextDoubleLcg(oracle2) * 8.0)]
    checkEq("the replayed stream matches the oracle", (a.dx, a.dy),
      (want.dx, want.dy))
  ## And the eight directions are all reachable, so the draw is not stuck.
  var seen: array[8, bool]
  var w3 = board("seed-0043")
  var probe = w3.createItem(crusaders[0].x, crusaders[0].y, castle.team,
                            ukCrusader)
  for turn in 0 ..< 400:
    let a = runExamplefuncsplayer19(w3, probe)
    for i in 0 ..< 8:
      if (a.dx, a.dy) == (Choices[i].dx, Choices[i].dy): seen[i] = true
  var reached = 0
  for s in seen:
    if s: inc reached
  checkEq("all eight compass directions are drawn over 400 turns", reached, 8)

# ---------------------------------------------------------------------------
#  4. EVERY OTHER UNIT DOES NOTHING AT ALL
# ---------------------------------------------------------------------------
block:
  var w = board("seed-0043")
  let castle = w.robots[0]
  for unit in [ukPilgrim, ukProphet, ukPreacher, ukChurch]:
    var who: Robot = nil
    for dy in -2 .. 2:
      for dx in -2 .. 2:
        if not who.isNil: continue
        if dx == 0 and dy == 0: continue
        if w.isPassable(castle.x + dx, castle.y + dy) and
            w.shadowAt(castle.x + dx, castle.y + dy) == 0:
          who = w.createItem(castle.x + dx, castle.y + dy, castle.team, unit)
    check("a " & unitName(unit) & " was placed", not who.isNil)
    if who.isNil: continue
    for turn in 0 ..< 40:
      let a = runExamplefuncsplayer19(w, who)
      check("a " & unitName(unit) & " NEVER acts", not a.hasAction)
      checkEq("and its action is NOTHING", a.kind, akNothing)
      checkEq("it never signals", a.signalRadius, 0)
      checkEq("it never sends castle talk", a.castleTalk, 0)
      checkEq("and it never sets a signal value", a.signal, 0)
    ## Its `step` counter still advances, exactly as the bot's does.
    checkEq("but its `step` counter still advanced", who.step, 39)
    ## A PILGRIM in particular never mines, even standing on a depot.
    if unit == ukPilgrim:
      var onDepot: Robot = nil
      for y in 0 ..< w.height:
        for x in 0 ..< w.width:
          if not onDepot.isNil: continue
          if w.hasKarbonite(x, y) and w.shadowAt(x, y) == 0 and
              w.isPassable(x, y):
            onDepot = w.createItem(x, y, castle.team, ukPilgrim)
      check("a pilgrim was placed ON a karbonite depot", not onDepot.isNil)
      if not onDepot.isNil:
        for turn in 0 ..< 20:
          let a = runExamplefuncsplayer19(w, onDepot)
          check("and it STILL never mines", not a.hasAction)

# ---------------------------------------------------------------------------
#  5. IT MAY NOT GAIN BEHAVIOUR — the whole action vocabulary, over a real
#     game, is {NOTHING, MOVE, BUILD} and nothing else.
# ---------------------------------------------------------------------------
block:
  var w = board("seed-0045", 400)
  var kinds: array[ActionKind, int]
  var builds: array[UnitKind, int]
  var turns = 0
  for round in 1 .. 60:
    ## One sweep of the whole queue, driving every robot through the bot.
    var snapshot: seq[Robot]
    for r in w.robots: snapshot.add r
    for r in snapshot:
      if w.getItem(r.id).isNil: continue
      let a = runExamplefuncsplayer19(w, r)
      inc turns
      kinds[a.kind] += 1
      if a.kind == akBuild: builds[a.buildUnit] += 1
      checkEq("no signal, ever", a.signalRadius, 0)
      checkEq("no castle talk, ever", a.castleTalk, 0)
      checkEq("no give, ever", a.giveK + a.giveF, 0)
      checkEq("no trade, ever", a.tradeK + a.tradeF, 0)
      ## Enact only the builds, so the crusader census grows and the bot's
      ## own build path is really exercised.
      if a.kind == akBuild and w.isPassable(r.x + a.dx, r.y + a.dy) and
          w.shadowAt(r.x + a.dx, r.y + a.dy) == 0 and
          w.karbonite[ord(r.team)] >= buildKarboniteOf(a.buildUnit) and
          w.fuel[ord(r.team)] >= buildFuelOf(a.buildUnit):
        var rec = newRecord()
        rec.action = akBuild
        rec.dx = a.dx
        rec.dy = a.dy
        rec.buildUnit = a.buildUnit
        w.enact(r, rec)
  check("the sweep drove a real number of turns", turns >= 200)
  checkEq("it NEVER mines", kinds[akMine], 0)
  checkEq("it NEVER attacks", kinds[akAttack], 0)
  checkEq("it NEVER gives", kinds[akGive], 0)
  checkEq("it NEVER trades", kinds[akTrade], 0)
  check("it moves", kinds[akMove] > 0)
  check("it builds", kinds[akBuild] > 0)
  check("and it does nothing on most turns", kinds[akNothing] > 0)
  checkEq("the ONLY thing it ever builds is a CRUSADER",
    builds[ukCrusader], kinds[akBuild])
  for u in [ukCastle, ukChurch, ukPilgrim, ukProphet, ukPreacher]:
    checkEq("it never builds a " & unitName(u), builds[u], 0)

finish("test_bc19_examplefuncsplayer19")
