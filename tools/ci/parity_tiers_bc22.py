#!/usr/bin/env python3
"""bc22 parity tiers: compare the Java and Nim traces and enforce the ledger.

CI-TIME ONLY, run by the `parity-oracle-bc22` job of
`.github/workflows/ci.yml`. It reads the trace pairs the job produced and
enforces:

  Tier A  (BLOCKING)  rounds 1..2000 BIT-EXACT, WHOLE GAMES, for
                      `examplefuncsplayer22` against itself on eight maps.
                      The window is the whole game for one MEASURED reason:
                      the 2022 example bot never approaches its bytecode limit
                      (peak 680-760 bytecodes over eight full games -- 6-7 %
                      of the 10 000 MINER limit -- and zero mid-turn
                      cut-offs), so the port's "no mid-turn resumption"
                      divergence is never exercised and the comparison stays
                      defined to the last round. THE JOB DOES NOT ASSUME THAT:
                      it reads the `bc=` column and FAILS if any robot on any
                      round exceeds the headroom bound, naming the round and
                      the robot.
  Tier A' (BLOCKING)  the FOUR SCENARIO PACKAGES -- `bc22scenario`,
                      `bc22scenarioannihilate`, `bc22scenariotie` and
                      `bc22scenariofury` -- on the same eight maps and the
                      same whole 2000-round window. Tier A's own measurement
                      showed exactly what it cannot cover: over eight full
                      games the example bot never built a builder, a sage, a
                      laboratory or a watchtower, never mutated, never
                      transformed, never transmuted, never envisioned, never
                      wrote the shared array, never made a single gold, and
                      ended EVERY game at round 2000 on MORE_LEAD_NET_WORTH
                      with gold 0-0. `tools/oracle/bc22/bc22scenario/
                      RobotPlayer.java` and `chassis/scenario22.nim` (behind
                      `-d:bc22Scenario` and its three variant switches) are
                      the two halves of the twin, written line for line
                      against each other, RNG-free and scripted by round
                      number. Their headroom bound is TIGHTER -- 25 % -- so
                      they can never be cut off mid-turn.
  Tier C  (BLOCKING)  the first divergent round of every pair, compared
                      against `tools/ci/parity_ledger_bc22.json`. It FAILS if
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

THIS IS bc23'S SCRIPT WITH ALL THREE KNOWN COMPARATOR BUGS FIXED, and the same
commit fixes them in `parity_tiers_bc21.py`, `_bc24.py` and `_bc25.py`:

  1. `bc=` is stripped from BOTH traces, by one `normalize()` applied to each
     side. Stripping only the Java side compares a line against itself plus a
     suffix and "diverges" at round 1 on otherwise-identical lines.
  2. `itertools.zip_longest`, NEVER `zip`. `zip` stops at the shorter file and
     DISCARDS the tail, so a Java trace one line longer than the Nim trace
     reads bit-exact. `selftest()` constructs exactly that pair, in both
     directions, and asserts the comparator reports a divergence.
  3. HEX FOLDS ARE CANONICALISED ON BOTH SIDES. `java.lang.Long.toHexString`
     emits lower case with NO leading zeros and, for a negative long, the
     unsigned 64-bit form; Nim's `toHex` zero-pads to sixteen. `normalize()`
     re-parses the value of every NAMED CHECKSUM FIELD -- the explicit
     allowlist `HEX_FIELDS` below -- as an unsigned 64-bit integer and re-emits
     it canonically, so neither emitter's formatting can create or hide a
     divergence. Decimal fields (`x`, `y`, `hp`, ...) are untouched, which is
     why the allowlist is explicit rather than a regex over anything
     hex-shaped: `hp=99` is a valid hex string and is not a checksum.

Tier B is not here: it is a byte-diff of `data/bc22/tables.json` against what
the jar's own classes emit, and it lives in its own workflow step because it
needs the JVM rather than the traces. `tests/test_bc22_economy.nim` and
`tests/test_bc22_units.nim` assert the NIM side against the same committed
bytes on every test run, so a rounding regression is caught by the `test` job
too.

    tools/ci/parity_tiers_bc22.py --dir <traces> --maps ... --bots ...
        --ledger tools/ci/parity_ledger_bc22.json [--summary $GITHUB_STEP_SUMMARY]
"""

from __future__ import annotations

import argparse
import itertools
import json
import pathlib
import re
import sys

BC_RE = re.compile(r" bc=-?\d+")
BC_VALUE_RE = re.compile(
    r"^R (\d+) U (\d+) team=\S+ ty=(\S+) .* bc=(-?\d+)$")

# BUG 3's allowlist. Every field here carries a 64-bit fold printed by
# `Long.toHexString` on one side and by `javaHex(toHex(...))` on the other.
# Nothing else in the trace is hex, and nothing else may be added without a
# reason: `hp=99` parses as hex too.
HEX_FIELDS = ("leadchk", "goldchk", "rubblechk", "arr", "hashord")
HEX_RE = re.compile(
    r"\b(" + "|".join(HEX_FIELDS) + r")=([0-9a-fA-F]+)\b")

# The headroom bound for the EXAMPLE bot. Past this point the comparison stops
# being defined, because the port's DecisionOps budget has no mid-turn
# resumption and the JVM's bytecode limit does. Measured over the eight
# whole-game pairs: the example bot peaks at 680-760 bytecodes, always a MINER,
# i.e. 6-7 % of the 10 000 limit, and never once cuts a turn off.
HEADROOM_PCT = 50

# The TIGHTER bound for the four scenario packages. They are our own bots and
# they are written to be cheap; measured peak is 19 % of the BUILDER's 7 500.
SCENARIO_HEADROOM_PCT = 25

SCENARIO_BOTS = ("bc22scenario", "bc22scenarioannihilate",
                 "bc22scenariotie", "bc22scenariofury")

# `RobotType`'s own `BL` column, battlecode22 2.2.1. A type that is not here
# is a trace the emitters and this script disagree about, and guessing a limit
# would silently move the headroom bound.
LIMITS = {
    "ARCHON": 20000,
    "LABORATORY": 5000,
    "WATCHTOWER": 10000,
    "MINER": 10000,
    "BUILDER": 7500,
    "SOLDIER": 10000,
    "SAGE": 10000,
}


def limit_for(unit_type: str) -> int:
    if unit_type not in LIMITS:
        raise SystemExit(
            f"::error::unknown bc22 robot type {unit_type!r} in the Java "
            f"trace: tools/ci/parity_tiers_bc22.py has no bytecode limit for "
            f"it, so the headroom bound cannot be computed.")
    return LIMITS[unit_type]


def _canon_hex(m: "re.Match[str]") -> str:
    return f"{m.group(1)}={format(int(m.group(2), 16) & 0xFFFFFFFFFFFFFFFF, 'x')}"


def normalize(line: str) -> str:
    """The ONE normalisation, applied identically to BOTH sides.

    Bug 1: the `bc=` column goes, whichever side carries it.
    Bug 3: every named checksum field is re-parsed and re-emitted canonically.
    """
    return HEX_RE.sub(_canon_hex, BC_RE.sub("", line))


def first_divergence(java_path: pathlib.Path, nim_path: pathlib.Path):
    """(round, line number, java line, nim line) of the first differing
    record, or None.

    `zip_longest`, NOT `zip` (bug 2). `zip` pulls from `jf` first and DISCARDS
    the line it already holds when `nf` runs out, so a Java trace exactly ONE
    line longer than the Nim one reads as bit-exact. Lengths are compared by
    the walk itself: a missing line is a divergence at the line number where
    it is missing.

    Streamed: a 2000-round bc22 trace is 18-27 MB a side and forty pairs would
    be a gigabyte held at once otherwise.
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
    same = ["R 1 U 1 team=A ty=MINER md=DROID lv=1 x=1 y=1 hp=40 acd=0 mcd=0",
            "R 2 U 1 team=A ty=MINER md=DROID lv=1 x=1 y=2 hp=40 acd=0 mcd=0",
            "R 3 U 1 team=A ty=MINER md=DROID lv=1 x=1 y=3 hp=40 acd=0 mcd=0"]
    tail = "R 4 U 1 team=A ty=MINER md=DROID lv=1 x=1 y=4 hp=40 acd=0 mcd=0"
    cases = [
        ("bug 1: equal but for the bc= column", same, same, None),
        ("bug 2: java one line longer", same + [tail], same, 4),
        ("bug 2: nim one line longer", same, same + [tail], 4),
        ("a mid-trace difference is still found", same,
         [same[0],
          "R 2 U 1 team=A ty=MINER md=DROID lv=1 x=9 y=2 hp=40 acd=0 mcd=0",
          same[2]], 2),
        ("bug 3: a zero-padded checksum is the same checksum",
         ["R 1 G leadchk=cafe goldchk=0 rubblechk=ff leadsum=1 goldsum=0"],
         ["R 1 G leadchk=000000000000cafe goldchk=0000000000000000 "
          "rubblechk=00000000000000ff leadsum=1 goldsum=0"], None),
        ("bug 3: a DIFFERENT checksum is still a divergence",
         ["R 1 G leadchk=cafe goldchk=0 rubblechk=ff leadsum=1 goldsum=0"],
         ["R 1 G leadchk=000000000000caff goldchk=0000000000000000 "
          "rubblechk=00000000000000ff leadsum=1 goldsum=0"], 1),
        ("bug 3: hp is NOT a checksum field and is not canonicalised",
         ["R 1 U 1 team=A ty=MINER md=DROID lv=1 x=1 y=1 hp=40 acd=0 mcd=0"],
         ["R 1 U 1 team=A ty=MINER md=DROID lv=1 x=1 y=1 hp=040 acd=0 mcd=0"],
         1),
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
    print(f"parity_tiers_bc22 selftest: {len(cases)} cases, all three known "
          f"comparator bugs covered")
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
                 f"with an EMPTY ledger (see docs/PARITY.md section bc22).")
    table = "\n".join(lines)
    print(table)
    if args.summary:
        with args.summary.open("a") as fh:
            fh.write("### bc22 parity tiers\n\n" + table + "\n")

    for p in problems + failures:
        print(f"::error::{p}")
    if problems or failures:
        return 1
    print(f"bc22 parity: {len(rows)} pairs, all bit-exact for whole "
          f"2000-round games, ledger empty" if not entries else
          f"bc22 parity: {len(rows)} pairs compared against a "
          f"{len(entries)}-entry ledger")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
