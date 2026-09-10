## THE INTEGER-FIDELITY SHARD. This year's headline claim is that its
## arithmetic is INTEGER END TO END, and this file is what makes that a gate
## rather than a sentence.
##
## Exactly TWO non-integer operations exist on any gameplay path
## (`docs/PARITY.md` §bc19, D5):
##
##   (i)  `Math.ceil(Math.sqrt(signal_radius))` over the integers 0 … 7938
##        (`game.js:834`, `action_record.js:329`);
##   (ii) `Math.floor(a / rad_to_attacker)` in the reclaim
##        (`action_record.js:305-306`), over the ten reachable divisors
##        `{0, 1, 2, 4, 5, 8, 9, 10, 13, 16}` and a doubled numerator
##        0 … 550.
##
## Both are TABLED AT BUILD TIME into `data/bc19/tables.json` from the pinned
## engine under the pinned Node, and `parity-oracle-bc19` regenerates and
## byte-diffs that file. This shard asserts every value in it against an
## independent integer recomputation, and then GREPS THE SOURCE to prove no
## bc19 module imports `fdlibm` or calls `sqrt`, `pow` or `exp` — so the "no
## runtime transcendental" claim is enforced, not asserted.

import std/[json, os, strutils]
import harness
import battlecode/years/bc19/rules

proc tablesPath(): string =
  ## `dataRoot()` is what the sim itself reads, so the shard and the sim can
  ## never disagree about which file is under test.
  dataRoot() / "bc19" / "tables.json"

let doc = parseJson(readFile(tablesPath()))

block:
  ## THE FILE'S OWN PROVENANCE, so a hand edit is visible.
  checkEq("the table records the pinned engine commit",
    doc["engine_commit"].getStr(),
    "80cf1cc535ec5a30559274aa1b49807ad4859925")
  check("and the pinned Node major version",
    doc["node_version"].getStr().startsWith("v22."))
  check("with a do-not-edit note", doc["note"].len >= 3)
  var noteText = ""
  for line in doc["note"]: noteText.add line.getStr() & " "
  check("that says GENERATED", "GENERATED" in noteText)
  check("and names the generator",
    "tools/JsBc19Tables.mjs" in noteText)

block:
  ## (i) `ceil(sqrt(r^2))` FOR ALL 7 939 VALUES, against an integer
  ## recomputation that uses no floating point at all: `ceil(sqrt(n))` is the
  ## least `k >= 0` with `k*k >= n`.
  let arr = doc["ceil_sqrt"]
  checkEq("the table has 7 939 entries", arr.len, MaxSignalRadius + 1)
  checkEq("and MAX_SIGNAL_RADIUS is 2*(MAX_BOARD_SIZE-1)^2",
    MaxSignalRadius, 2 * (MaxBoardSize - 1) * (MaxBoardSize - 1))
  var k = 0
  var bad = 0
  var mismatched = 0
  for n in 0 .. MaxSignalRadius:
    while k * k < n: inc k
    let want = k
    if arr[n].getInt() != want: inc bad
    if signalCost(n) != want: inc mismatched
  checkEq("every tabled ceil(sqrt(n)) equals the integer recomputation",
    bad, 0)
  checkEq("and `signalCost` returns it for every one of the 7 939", 
    mismatched, 0)
  ## The joints, named, so a failure says which one.
  checkEq("ceil(sqrt(0)) == 0", signalCost(0), 0)
  checkEq("ceil(sqrt(1)) == 1", signalCost(1), 1)
  checkEq("ceil(sqrt(2)) == 2", signalCost(2), 2)
  checkEq("ceil(sqrt(4)) == 2", signalCost(4), 2)
  checkEq("ceil(sqrt(5)) == 3", signalCost(5), 3)
  checkEq("ceil(sqrt(7921)) == 89 (89^2 exactly)", signalCost(7921), 89)
  checkEq("ceil(sqrt(7922)) == 90", signalCost(7922), 90)
  checkEq("ceil(sqrt(7938)) == 90", signalCost(7938), 90)
  ## Monotone non-decreasing, and every step is exactly +1 at a perfect
  ## square boundary and 0 elsewhere.
  var monotone = true
  var badStep = 0
  for n in 1 .. MaxSignalRadius:
    let a = signalCost(n - 1)
    let b = signalCost(n)
    if b < a: monotone = false
    if b - a notin [0, 1]: inc badStep
  check("the table is monotone non-decreasing", monotone)
  checkEq("and never steps by more than 1", badStep, 0)
  ## Every perfect square is its own root, and one past it is root + 1.
  for root in 0 .. 89:
    checkEq("ceil(sqrt(" & $(root * root) & ")) == " & $root,
      signalCost(root * root), root)
    if root * root + 1 <= MaxSignalRadius:
      checkEq("and one past it is " & $(root + 1),
        signalCost(root * root + 1), root + 1)

block:
  ## (ii) THE RECLAIM DIVISION over its WHOLE reachable domain, against
  ## integer division. The table is keyed by TWICE the numerator because
  ## `CONSTRUCTION_KARBONITE / 2` is a HALF-INTEGER for a PROPHET (15/2) and
  ## a PREACHER (25/2).
  let divisors = doc["reclaim_divisors"]
  checkEq("ten divisors are tabled", divisors.len, ReclaimDivisors.len)
  for i, d in ReclaimDivisors:
    checkEq("divisor " & $i & " is " & $d, divisors[i].getInt(), d)
  let maxNum = doc["max_doubled_numerator"].getInt()
  checkEq("the doubled numerator domain is 0 .. 550", maxNum, 550)
  ## 550 really does cover the domain: the largest doubled karbonite
  ## numerator is `2 * 20 + 50` (a full pilgrim's cap plus a CHURCH's
  ## construction karbonite) and the largest doubled fuel numerator is
  ## `2 * 100`.
  var worst = 0
  for u in [ukCastle, ukChurch, ukPilgrim, ukCrusader, ukProphet,
            ukPreacher]:
    worst = max(worst, 2 * karboniteCapacityOf(ukPilgrim) +
                buildKarboniteOf(u))
    worst = max(worst, 2 * fuelCapacityOf(ukPilgrim))
  check("and the reachable worst case is inside it", worst <= maxNum)
  let half = doc["floor_half_div"]
  var badDiv = 0
  var badPort = 0
  for d in ReclaimDivisors:
    let col = half[$d]
    checkEq("divisor " & $d & " has the full column", col.len, maxNum + 1)
    for n in 0 .. maxNum:
      let got = col[n].getInt()
      if d == 0:
        ## JavaScript: `floor(0/0)` is NaN (recorded -2), `floor(n/0)` is
        ## Infinity (recorded -1), and BOTH reach the caller as
        ## `Math.min(held + x, capacity)` -> the CAPACITY. The port pins both.
        let want = (if n == 0: -2 else: -1)
        if got != want: inc badDiv
        if reclaimDivDoubled(n, d) >= 0: inc badPort
      else:
        if got != n div (2 * d): inc badDiv
        if reclaimDivDoubled(n, d) != n div (2 * d): inc badPort
  checkEq("every tabled floor(a/rad) equals integer division", badDiv, 0)
  checkEq("and the port reads the table for every one of them", badPort, 0)
  ## The half-integer cases, named.
  checkEq("(0 + 15/2) / 1 == 7", reclaimDivDoubled(15, 1), 7)
  checkEq("(0 + 25/2) / 1 == 12", reclaimDivDoubled(25, 1), 12)
  checkEq("(0 + 15/2) / 2 == 3", reclaimDivDoubled(15, 2), 3)
  checkEq("(20 + 25/2) / 4 == 8", reclaimDivDoubled(2 * 20 + 25, 4), 8)
  checkEq("(20 + 5) / 2 == 12", reclaimDivDoubled(2 * 20 + 10, 2), 12)
  check("divisor 0 is the CAPACITY CLAMP, both branches",
    reclaimDivDoubled(0, 0) < 0 and reclaimDivDoubled(35, 0) < 0)

block:
  ## THE SPECS BLOCK: every scalar the sim uses, straight out of
  ## `coldbrew/specs.json`, asserted against the generated constants. If the
  ## generator and the constants ever disagree this is where it shows.
  let specs = doc["specs"]
  checkEq("COMMUNICATION_BITS", specs["COMMUNICATION_BITS"].getInt(),
    CommunicationBits)
  checkEq("CASTLE_TALK_BITS", specs["CASTLE_TALK_BITS"].getInt(),
    CastleTalkBits)
  checkEq("MAX_ROUNDS", specs["MAX_ROUNDS"].getInt(), MaxRounds)
  checkEq("TRICKLE_FUEL", specs["TRICKLE_FUEL"].getInt(), TrickleFuel)
  checkEq("INITIAL_KARBONITE", specs["INITIAL_KARBONITE"].getInt(),
    InitialKarbonite)
  checkEq("INITIAL_FUEL", specs["INITIAL_FUEL"].getInt(), InitialFuel)
  checkEq("MINE_FUEL_COST", specs["MINE_FUEL_COST"].getInt(), MineFuelCost)
  checkEq("KARBONITE_YIELD", specs["KARBONITE_YIELD"].getInt(),
    KarboniteYield)
  checkEq("FUEL_YIELD", specs["FUEL_YIELD"].getInt(), FuelYield)
  checkEq("MAX_TRADE", specs["MAX_TRADE"].getInt(), MaxTrade)
  checkEq("MAX_BOARD_SIZE", specs["MAX_BOARD_SIZE"].getInt(), MaxBoardSize)
  checkEq("MAX_ID", specs["MAX_ID"].getInt(), MaxId)
  ## And EVERY value in the specs block is an integer, which is the claim.
  var nonInteger = 0
  for key, node in specs:
    if node.kind == JInt: continue
    if node.kind == JNull: continue
    if node.kind == JArray or node.kind == JObject: continue
    inc nonInteger
  checkEq("no scalar in the specs block is a float", nonInteger, 0)

block:
  ## EVERY value in the whole table file is an integer or a string. A float
  ## anywhere in it would mean a transcendental leaked into the build-time
  ## generator's output.
  var floats = 0
  var walked = 0
  proc walk(n: JsonNode) =
    inc walked
    case n.kind
    of JFloat: inc floats
    of JArray:
      for c in n: walk(c)
    of JObject:
      for _, c in n: walk(c)
    else: discard
  walk(doc)
  check("the walk visited the whole document", walked > 8000)
  checkEq("and found NO floating-point value anywhere", floats, 0)

block:
  ## NO RUNTIME TRANSCENDENTAL, ENFORCED BY GREP over
  ## `src/battlecode/years/bc19/**`. The point of the tables is that nothing
  ## at run time computes them, so this walks the source and fails on a
  ## `sqrt`, a `pow`, an `exp` or an `fdlibm` import.
  var scanned = 0
  var offenders: seq[string]
  let root = "src/battlecode/years/bc19"
  check("the bc19 source tree is where the shard expects it",
    dirExists(root))
  proc code(raw: string): string =
    ## The CODE of one line: the comment stripped, and every double-quoted
    ## string literal blanked. Both matter here, because the module's own
    ## docstrings and its "there is no sqrt on any runtime path" error
    ## message both contain the very substrings this scan looks for.
    var inStr = false
    for i, ch in raw:
      if ch == '"' and (i == 0 or raw[i - 1] != '\\'):
        inStr = not inStr
        continue
      if inStr: continue
      if ch == '#': break
      result.add ch
  for path in walkDirRec(root):
    if not path.endsWith(".nim"): continue
    inc scanned
    var lineNo = 0
    for raw in readFile(path).splitLines():
      inc lineNo
      let line = code(raw)
      if line.len == 0: continue
      for bad in ["sqrt(", "pow(", "exp(", "fdlibm", "std/math"]:
        if bad in line:
          offenders.add path & ":" & $lineNo & ": " & bad & " -> " &
            line.strip()
  check("the scan read the whole module", scanned >= 20)
  if offenders.len > 0:
    for o in offenders: echo "  OFFENDER ", o
  checkEq("NO bc19 module calls sqrt, pow or exp, or imports fdlibm",
    offenders.len, 0)
  ## The scan is not vacuous, and it is not over-eager either.
  check("a planted `sqrt(` in code IS caught",
    "sqrt(" in code("  let x = sqrt(2.0)  ## a comment"))
  check("one inside a STRING LITERAL is not",
    "sqrt(" notin code("  raise newException(E, " & '"' & "no sqrt( here" &
      '"' & ")"))
  check("nor one inside a COMMENT", "sqrt(" notin code("  ## sqrt( here"))

block:
  ## THE ONE PLACE A FLOAT IS DELIBERATE, fenced off: `share()` in the score
  ## is `float32` by design (the engine's own `points` arithmetic), and it is
  ## in `rules.nim`, not on a gameplay path. Assert it is float32 and that
  ## its output is truncated to an integer before anything reads it.
  checkEq("share(1, 1) is the float32 half", share(1, 1), 0.5'f32)
  checkEq("share(1, 2) is the float32 third", share(1, 2),
    1.0'f32 / 3.0'f32)
  checkEq("share(1, 3) is a float32 quarter", share(1, 3), 0.25'f32)
  checkEq("and a 0-0 total is 0.5, NOT 0", share(0, 0), 0.5'f32)
  ## `gamePoints` returns `array[2, int]`, so the truncation is in the type.
  var w = newWorld(loadMap("seed-0009"), 1)
  let pts = w.gamePoints()
  check("gamePoints returns integers", pts[0] >= 0 and pts[1] >= 0)

block:
  ## THE UNIT TABLE IS INTEGER, every field, every row -- the sixth row of
  ## the claim. `null` is represented by an explicit flag, never by a float
  ## sentinel.
  for u in [ukCastle, ukChurch, ukPilgrim, ukCrusader, ukProphet,
            ukPreacher]:
    let n = unitName(u)
    check(n & " starting HP is a positive integer", startingHpOf(u) > 0)
    check(n & " vision radius is a positive integer", visionRadiusOf(u) > 0)
    check(n & " speed is a non-negative integer", speedOf(u) >= 0)
    check(n & " attack damage is non-negative", attackDamageOf(u) >= 0)
    check(n & " attack fuel is non-negative", attackFuelOf(u) >= 0)
    check(n & " damage spread is non-negative", damageSpreadOf(u) >= 0)
    check(n & " karbonite capacity is non-negative",
      karboniteCapacityOf(u) >= 0)
    check(n & " fuel capacity is non-negative", fuelCapacityOf(u) >= 0)
    check(n & " build karbonite is non-negative", buildKarboniteOf(u) >= 0)
    check(n & " build fuel is non-negative", buildFuelOf(u) >= 0)

finish("test_bc19_arith")
