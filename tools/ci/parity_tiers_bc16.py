#!/usr/bin/env python3
"""bc16 parity tiers: compare the Java and Nim traces and enforce the ledger.

CI-TIME ONLY, run by the `parity-oracle-bc16` job of
`.github/workflows/ci.yml`. It reads the trace pairs the job produced and
enforces:

  Tier A  (BLOCKING)  BIT-EXACT WHOLE GAMES -- round 0 to the engine's own
                      `isRunning() == false` -- for `bc16idle`
                      against itself on NINE maps. **This is a real and LARGE
                      tier, not a trivial one, and that is the single most
                      important thing to understand about bc16 parity**: the
                      zombie half of this game is ENGINE-SIDE, so an idle
                      player still exercises the den schedules and their
                      per-den split, the spawn ring's direction and chirality,
                      `spawnAllPossible` and its proximity-damage fallback,
                      the whole eight-step zombie movement ladder, ALL THREE
                      `java.util.Random` STREAMS, infection and the
                      die-and-turn conversion, the corpse-rubble deposit,
                      `clearRubble` by digging zombies, the parts income
                      curve, both factions' archons being eaten, the mid-turn
                      DESTROYED check and the round-2999 ladder. The job
                      asserts off the JAVA trace that all of that really
                      happened -- a tier that agrees bit for bit while nothing
                      happens proves nothing.
  Tier A" (BLOCKING)  `bc16greenhorn` against itself on the same nine maps and
                      the same whole-game window. `greenhorn` is the one
                      bot with a live `java.util.Random(2016)` PER ROBOT, so
                      this tier is what proves the port's `rng.nim` reproduces
                      a FOURTH independent stream call for call alongside the
                      engine's three -- and it is also the tier that exercises
                      the PLAYER side: build, move and attack, with
                      `senseHostileRobots()[0]` resolved in insertion order.
  Tier C  (BLOCKING)  the first divergent round of every pair, compared
                      against `tools/ci/parity_ledger_bc16.json`. It FAILS if
                      (a) a pair diverges and has no ledger entry, (b) a pair
                      diverges EARLIER than its entry, (c) a ledger entry no
                      longer reproduces -- a stale excuse is as bad as a
                      missing one -- or (d) ANY divergence occurs while the
                      traced bytecode peak is still under the headroom bound,
                      which on this year's evidence means always, and
                      therefore means a real rules bug rather than an
                      instrumentation artefact.

ROOT-CAUSE-OR-FAIL IS THE STANDING RULE and it is the operator's ruling on
the bc26 run (Fleet card 1218171523823317), not this script's preference. An
unexplained divergence is a FAIL, not a ledger line: every entry must name a
round, a map and a ROOT CAUSE, and a cause of "unknown" is rejected by the
schema check below.

THIS IS bc22'S SCRIPT -- whose three comparator bugs are already fixed there --
PLUS THE ORIGIN NORMALISATION (V3) AND A FLOAT ALLOWLIST:

  1. `bc=` is stripped from BOTH traces, by one `normalize()` applied to each
     side. Stripping only the Java side compares a line against itself plus a
     suffix and "diverges" at round 1 on otherwise-identical lines (LEARNINGS
     2026-09-08, bc23).
  2. `itertools.zip_longest`, NEVER `zip`. `zip` stops at the shorter file and
     DISCARDS the tail, so a Java trace one line longer than the Nim trace
     reads bit-exact. `selftest()` constructs exactly that pair, in both
     directions, and asserts the comparator reports a divergence.
  3. HEX FOLDS ARE CANONICALISED ON BOTH SIDES through an explicit allowlist,
     because `hp=99` is a valid hex string and is not a checksum.
  4. **NEW FOR bc16: NAMED FLOAT FIELDS ARE RE-PARSED AND RE-EMITTED.**
     `parts`, `hp`, `cd` and `wd` are printed `%.6f` by both sides, and
     `String.format` rounds HALF-UP where C's `printf` -- which is what Nim's
     `formatFloat` calls -- rounds HALF-TO-EVEN. Re-parsing through `float()`
     and re-emitting canonically means neither emitter's formatting can create
     or hide a divergence. (The two 900-term SUMS are printed as raw IEEE-754
     bit patterns by both sides for the same reason, and land in the hex
     allowlist rather than the float one -- see `Bc16Trace.java`'s header for
     the measurement that forced it.)
  5. **NEW FOR bc16: THE ORIGIN IS ALREADY NORMALISED IN BOTH EMITTERS.** The
     map's random origin is not ported (V3, proven inert) and the Java driver
     subtracts `map.getOrigin()` from every coordinate it prints, so both
     traces are origin-free before this script sees them. Asserted here rather
     than assumed: any `x=` or `y=` above 200 in a Java trace means the
     subtraction was dropped, and this script says so.

Tier B is not here: it is a byte-diff of `data/bc16/tables.json` and of the 22
committed maps' symmetry and per-den split against what the jar's own classes
emit, and it lives in its own workflow step because it needs the JVM rather
than the traces. `tests/test_bc16_units.nim`, `tests/test_bc16_arith.nim` and
`tests/table_bc16_delay.nim` assert the NIM side against the same committed
bytes on every test run, so a rounding regression is caught by the `test` job
too.
"""

import argparse
import itertools
import json
import pathlib
import re
import sys

BC_RE = re.compile(r" bc=-?\d+")
BC_VALUE_RE = re.compile(
    r"^R (\d+) U (\d+) team=\S+ ty=(\S+) .* bc=(-?\d+)$")

# Rule 5's tripwire: bc16 coordinates are ORIGIN-RELATIVE on both sides, and
# every committed map is at most 80 wide. A coordinate above this in a JAVA
# trace means `map.getOrigin()` was not subtracted.
COORD_RE = re.compile(r"\b[xy]=(-?\d+)\b")
MAX_COORD = 200

# BUG 3's allowlist. Every field here carries a 64-bit fold printed by
# `Long.toHexString` on one side and by `javaHex(toHex(...))` on the other.
# Nothing else in the trace is hex, and nothing else may be added without a
# reason: `hp=99` parses as hex too.
HEX_FIELDS = ("rubblechk", "partschk", "rubblesum", "partssum",
              "world", "zombie", "idgen")

# BUG 4's allowlist. Every field here is a float64 printed `%.6f` by both
# sides. `String.format` rounds HALF-UP and C's `printf` HALF-TO-EVEN, so the
# two emitters can print the same double differently at the last digit; both
# sides are re-parsed and re-emitted here. Nothing else in the trace is a
# float, and nothing else may be added without a reason.
FLOAT_FIELDS = ("parts", "hp", "cd", "wd")
FLOAT_RE = re.compile(
    r"\b(" + "|".join(FLOAT_FIELDS) + r")=(-?\d+\.\d+)\b")
HEX_RE = re.compile(
    r"\b(" + "|".join(HEX_FIELDS) + r")=([0-9a-fA-F]+)\b")

# The headroom bound for the EXAMPLE bot. Past this point the comparison stops
# being defined, because the port's DecisionOps budget has no mid-turn
# resumption and the JVM's bytecode limit does. Measured over the eight
# whole-game pairs: the example bot peaks at 680-760 bytecodes, always a MINER,
# i.e. 6-7 % of the 10 000 limit, and never once cuts a turn off.
# THE HEADROOM BOUND. Past this point the comparison stops being defined,
# because the port's DecisionOps budget has no mid-turn resumption and the
# JVM's bytecode limit does -- AND, in bc16 specifically, because the engine's
# `amountToDecrement` leaves its 1.0 branch at `limit - 8000` and V1 pins the
# port to 1.0 (docs/RULES-BC16.md section Divergences item 1). Measured over
# nine whole games a side: `bc16idle` peaks at ONE bytecode and
# `bc16greenhorn` at well under a hundred, i.e. 0 % of every limit, so neither
# bot ever leaves the 1.0 branch and the comparison is defined to the last
# round. THE JOB DOES NOT ASSUME THAT: it reads the `bc=` column and FAILS if
# any robot on any round exceeds the bound, naming the round and the robot.
#
# 20 % of a 10 000-bytecode limit is 2 000, which IS `limit - 8000` for every
# non-archon type -- so this bound is not a taste, it is exactly the knee of
# `decrementDelays`.
HEADROOM_PCT = 20

SCENARIO_HEADROOM_PCT = 20

SCENARIO_BOTS = ()

# `RobotType`'s own `BL` column, battlecode22 2.2.1. A type that is not here
# is a trace the emitters and this script disagree about, and guessing a limit
# would silently move the headroom bound.
LIMITS = {
    "ZOMBIEDEN": 10000,
    "STANDARDZOMBIE": 10000,
    "RANGEDZOMBIE": 10000,
    "FASTZOMBIE": 10000,
    "BIGZOMBIE": 10000,
    "ARCHON": 20000,
    "SCOUT": 20000,
    "SOLDIER": 10000,
    "GUARD": 10000,
    "VIPER": 10000,
    "TURRET": 10000,
    "TTM": 10000,
}


def limit_for(unit_type: str) -> int:
    if unit_type not in LIMITS:
        raise SystemExit(
            f"::error::unknown bc16 robot type {unit_type!r} in the Java "
            f"trace: tools/ci/parity_tiers_bc16.py has no bytecode limit for "
            f"it, so the headroom bound cannot be computed.")
    return LIMITS[unit_type]


def _canon_float(m: "re.Match[str]") -> str:
    return f"{m.group(1)}={float(m.group(2)):.6f}"


def _canon_hex(m: "re.Match[str]") -> str:
    return f"{m.group(1)}={format(int(m.group(2), 16) & 0xFFFFFFFFFFFFFFFF, 'x')}"


def normalize(line: str) -> str:
    """The ONE normalisation, applied identically to BOTH sides.

    Bug 1: the `bc=` column goes, whichever side carries it.
    Bug 3: every named checksum field is re-parsed and re-emitted canonically.
    Bug 4: so is every named FLOAT field, because `String.format` rounds
    HALF-UP and C's `printf` HALF-TO-EVEN.
    """
    return FLOAT_RE.sub(
        _canon_float, HEX_RE.sub(_canon_hex, BC_RE.sub("", line)))


def origin_leak(java_path: pathlib.Path):
    """Rule 5: a Java coordinate above `MAX_COORD` means `map.getOrigin()`
    was not subtracted, and every line of the trace would then differ for a
    reason that has nothing to do with the rules (V3)."""
    with java_path.open() as jf:
        for lineno, line in enumerate(jf, start=1):
            for value in COORD_RE.findall(line):
                if abs(int(value)) > MAX_COORD:
                    return (lineno, line.rstrip("\n"))
            if lineno > 4000:
                break
    return None


def first_divergence(java_path: pathlib.Path, nim_path: pathlib.Path):
    """(round, line number, java line, nim line) of the first differing
    record, or None.

    `zip_longest`, NOT `zip` (bug 2). `zip` pulls from `jf` first and DISCARDS
    the line it already holds when `nf` runs out, so a Java trace exactly ONE
    line longer than the Nim one reads as bit-exact. Lengths are compared by
    the walk itself: a missing line is a divergence at the line number where
    it is missing.

    Streamed: a bc16 trace runs 0.9-16 MB a side (measured) and eighteen
    pairs would be a gigabyte held at once otherwise.
    """
    ended = "<the trace ends here>"
    with java_path.open() as jf, nim_path.open() as nf:
        for lineno, (jl, nl) in enumerate(
                itertools.zip_longest(jf, nf), start=1):
            j = ended if jl is None else normalize(jl.rstrip("\n"))
            n = ended if nl is None else normalize(nl.rstrip("\n"))
            if j != n:
                round_no = -1
                m = re.match(r"^R (\d+) ", j) or re.match(r"^R (\d+) ", n)
                if m:
                    round_no = int(m.group(1))
                return (round_no, lineno, j, n)
    return None


def peak_bytecode(java_path: pathlib.Path):
    """(peak percentage, round, id) over the whole Java trace."""
    best_pct = 0
    best = (0, -1, -1)
    with java_path.open() as jf:
        for line in jf:
            m = BC_VALUE_RE.match(line.rstrip("\n"))
            if not m:
                continue
            used = int(m.group(4))
            pct = used * 100 // limit_for(m.group(3))
            if pct > best_pct:
                best_pct = pct
                best = (pct, int(m.group(1)), int(m.group(2)))
    return best


def check_ledger_schema(entries) -> list[str]:
    problems = []
    for e in entries:
        for key in ("bot", "map", "first_divergent_round", "cause", "docs"):
            if key not in e:
                problems.append(f"ledger entry {e} is missing `{key}`")
        cause = str(e.get("cause", "")).strip().lower()
        if cause in ("", "unknown", "unclear", "tbd", "?"):
            problems.append(
                f"ledger entry for {e.get('bot')}/{e.get('map')} has no ROOT "
                f"CAUSE ({e.get('cause')!r}). Root-cause-or-fail is the "
                f"standing rule: a cause of 'unknown' is not a cause.")
    return problems


def selftest() -> int:
    """Prove the comparator can fail. A gate that cannot fail is not a gate.

    One case per bug:
      * bug 1 -- a pair that differs ONLY in the `bc=` column must read as
        bit-exact whichever side carries the column;
      * bug 2 -- a trace exactly ONE line longer than the other must be a
        divergence, in BOTH directions;
      * bug 3 -- `leadchk=00000000cafe` and `leadchk=cafe` are the same fold
        and must read as bit-exact, while `hp=0099` and `hp=99` are NOT a
        checksum field and must still read as a divergence.
    """
    import tempfile
    U = "R {r} U 1 team=A ty=SOLDIER x=1 y={r} hp=60.000000 cd=0.000000 wd=0.000000 zi=0 vi=0 ra=1 bd=0"
    same = [U.format(r=1), U.format(r=2), U.format(r=3)]
    tail = U.format(r=4)
    cases = [
        ("bug 1: equal but for the bc= column", same, same, None),
        ("bug 2: java one line longer", same + [tail], same, 4),
        ("bug 2: nim one line longer", same, same + [tail], 4),
        ("a mid-trace difference is still found", same,
         [same[0], U.format(r=2).replace("x=1", "x=9"), same[2]], 2),
        ("bug 3: a zero-padded checksum is the same checksum",
         ["R 1 G rubblechk=cafe partschk=0 rubblesum=ff partssum=0"],
         ["R 1 G rubblechk=000000000000cafe partschk=0000000000000000 "
          "rubblesum=00000000000000ff partssum=0000000000000000"], None),
        ("bug 3: a DIFFERENT checksum is still a divergence",
         ["R 1 G rubblechk=cafe partschk=0 rubblesum=ff partssum=0"],
         ["R 1 G rubblechk=000000000000caff partschk=0000000000000000 "
          "rubblesum=00000000000000ff partssum=0000000000000000"], 1),
        ("bug 3: ra is NOT a checksum field and is not canonicalised",
         [U.format(r=1)], [U.format(r=1).replace("ra=1", "ra=01")], 1),
        ("bug 4: a HALF-UP/HALF-TO-EVEN float tie reads as the same double",
         ["R 1 T A parts=361.970000 ar=3 sc=0 so=0 gu=0 vi=0 tu=0 tt=0"],
         ["R 1 T A parts=361.97 ar=3 sc=0 so=0 gu=0 vi=0 tu=0 tt=0"], None),
        ("bug 4: a DIFFERENT float is still a divergence",
         ["R 1 T A parts=361.970000 ar=3 sc=0 so=0 gu=0 vi=0 tu=0 tt=0"],
         ["R 1 T A parts=361.980000 ar=3 sc=0 so=0 gu=0 vi=0 tu=0 tt=0"], 1),
        ("bug 4: an INTEGER field named like a float is untouched",
         ["R 1 X world=1 zombie=2 idgen=3"],
         ["R 1 X world=1 zombie=2 idgen=3"], None),
    ]
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        d = pathlib.Path(tmp)
        for name, java, nim, want in cases:
            # `bc=` on the Java side only, as the real traces carry it.
            (d / "j").write_text("".join(f"{l} bc=100\n" for l in java))
            (d / "n").write_text("".join(f"{l} bc=0\n" for l in nim))
            got = first_divergence(d / "j", d / "n")
            round_no = None if got is None else got[0]
            if round_no != want:
                bad.append(f"{name}: first_divergence reported {got!r}, "
                           f"expected first divergent round {want!r}")
    for b in bad:
        print(f"::error::{b}")
    if bad:
        return 1
    # Rule 5's own self-test: an un-normalised origin must be caught.
    with tempfile.TemporaryDirectory() as tmp:
        d = pathlib.Path(tmp)
        (d / "leak").write_text(
            "R 0 U 1 team=A ty=ARCHON x=266 y=163 hp=1000.000000 cd=0.000000 "
            "wd=0.000000 zi=0 vi=0 ra=1 bd=0 bc=0\n")
        if origin_leak(d / "leak") is None:
            print("::error::the origin tripwire did not fire on a trace whose "
                  "coordinates are clearly map-origin-shifted")
            return 1
        (d / "ok").write_text(
            "R 0 U 1 team=A ty=ARCHON x=3 y=17 hp=1000.000000 cd=0.000000 "
            "wd=0.000000 zi=0 vi=0 ra=1 bd=0 bc=0\n")
        if origin_leak(d / "ok") is not None:
            print("::error::the origin tripwire fired on an origin-free trace")
            return 1
    print(f"parity_tiers_bc16 selftest: {len(cases)} cases, all four known "
          f"comparator bugs plus the origin tripwire covered")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true",
                    help="check normalize/first_divergence against known "
                         "trace pairs and exit; takes no other argument")
    ap.add_argument("--dir", type=pathlib.Path)
    ap.add_argument("--maps", nargs="+")
    ap.add_argument("--bots", nargs="+")
    ap.add_argument("--ledger", type=pathlib.Path)
    ap.add_argument("--summary", type=pathlib.Path)
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    for name in ("dir", "maps", "bots", "ledger"):
        if getattr(args, name) is None:
            ap.error(f"--{name} is required unless --selftest is given")
    ledger = json.loads(args.ledger.read_text())
    entries = ledger if isinstance(ledger, list) else ledger.get("entries", [])
    problems = check_ledger_schema(entries)
    by_pair = {(e["bot"], e["map"]): e for e in entries
               if "bot" in e and "map" in e}
    unused = set(by_pair)

    rows = []
    failures = []
    for bot in args.bots:
        bound = SCENARIO_HEADROOM_PCT if bot in SCENARIO_BOTS \
            else HEADROOM_PCT
        for map_name in args.maps:
            java_path = args.dir / f"{bot}.{map_name}.java"
            nim_path = args.dir / f"{bot}.{map_name}.nim"
            if not java_path.exists() or not nim_path.exists():
                failures.append(f"missing trace pair for {bot}/{map_name}")
                continue
            leak = origin_leak(java_path)
            if leak is not None:
                failures.append(
                    f"{bot}/{map_name}: the JAVA trace carries a coordinate "
                    f"above {MAX_COORD} at line {leak[0]} -- "
                    f"`map.getOrigin()` was not subtracted, so every line "
                    f"would differ for a reason that has nothing to do with "
                    f"the rules (V3). Line: {leak[1]}")
            pct, pround, pid = peak_bytecode(java_path)
            div = first_divergence(java_path, nim_path)
            entry = by_pair.get((bot, map_name))
            if entry is not None:
                unused.discard((bot, map_name))

            if pct > bound:
                failures.append(
                    f"{bot}/{map_name}: robot {pid} used {pct} % of its "
                    f"bytecode limit on round {pround}, above the "
                    f"{bound} % headroom bound. Past that point the "
                    f"comparison is no longer defined, because the port's "
                    f"DecisionOps budget has no mid-turn resumption and the "
                    f"JVM's limit does. The Tier A window has to shrink, and "
                    f"this job would rather be wrong loudly than green "
                    f"quietly.")

            if div is None:
                rows.append((bot, map_name, "bit-exact", pct, ""))
                if entry is not None:
                    failures.append(
                        f"{bot}/{map_name}: the ledger claims a divergence at "
                        f"round {entry['first_divergent_round']} and there is "
                        f"none. A stale excuse is as bad as a missing one -- "
                        f"delete the entry.")
                continue

            round_no, lineno, jl, nl = div
            rows.append((bot, map_name, f"diverges at round {round_no}", pct,
                         f"line {lineno}"))
            print(f"::group::{bot}/{map_name} first divergence")
            print(f"  round {round_no}, trace line {lineno}")
            print(f"  java: {jl}")
            print(f"  nim : {nl}")
            print("::endgroup::")

            if entry is None:
                failures.append(
                    f"{bot}/{map_name}: DIVERGES at round {round_no} and has "
                    f"no ledger entry. Root-cause-or-fail: an unexplained "
                    f"divergence is a FAIL, not a PARITY.md line.")
            elif round_no < entry["first_divergent_round"]:
                failures.append(
                    f"{bot}/{map_name}: diverges at round {round_no}, EARLIER "
                    f"than the ledger's {entry['first_divergent_round']}.")

            if pct <= bound:
                failures.append(
                    f"{bot}/{map_name}: diverges at round {round_no} while "
                    f"the traced bytecode peak is only {pct} % of the limit. "
                    f"That is a real rules bug, not an instrumentation "
                    f"artefact.")

    for pair in sorted(unused):
        failures.append(
            f"{pair[0]}/{pair[1]}: the ledger has an entry for a pair this run "
            f"did not compare. Remove it or restore the pair.")

    lines = ["| bot | map | tier A/A' | peak bytecode | note |",
             "|---|---|---|---|---|"]
    for bot, map_name, verdict, pct, note in rows:
        lines.append(
            f"| `{bot}` | `{map_name}` | {verdict} | {pct} % | {note} |")
    lines.append("")
    lines.append(f"Ledger: {len(entries)} accepted divergence(s). "
                 f"The phase-30 exit condition is Tiers A, A' and B passing "
                 f"with an EMPTY ledger (see docs/PARITY.md section bc16).")
    table = "\n".join(lines)
    print(table)
    if args.summary:
        with args.summary.open("a") as fh:
            fh.write("### bc16 parity tiers\n\n" + table + "\n")

    for p in problems + failures:
        print(f"::error::{p}")
    if problems or failures:
        return 1
    print(f"bc16 parity: {len(rows)} pairs, all bit-exact for whole "
          f"games, ledger empty" if not entries else
          f"bc16 parity: {len(rows)} pairs compared against a "
          f"{len(entries)}-entry ledger")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
