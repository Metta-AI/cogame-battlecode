#!/usr/bin/env python3
"""bc23 parity tiers: compare the Java and Nim traces and enforce the ledger.

CI-TIME ONLY, run by the `parity-oracle-bc23` job of
`.github/workflows/ci.yml`. It reads the trace pairs the job produced and
enforces:

  Tier A  (BLOCKING)  rounds 1..2000 BIT-EXACT, WHOLE GAMES, for
                      `examplefuncsplayer23` against itself on six `small`
                      maps. The window is the whole game for one MEASURED
                      reason: the 2023 example bot never approaches its
                      bytecode limit (peak 745-893 bytecodes over six full
                      games -- 4-9 % of whichever type's limit that was --
                      and zero mid-turn cut-offs), so the port's "no
                      mid-turn resumption" divergence is never exercised and
                      the comparison stays defined to the last round. THE JOB
                      DOES NOT ASSUME THAT: it reads the `bc=` column and
                      FAILS if any unit on any round exceeds the headroom
                      bound, naming the round and the unit.
  Tier A' (NOT SHIPPED IN THIS LANDING) the scenario packages. Tier A's own
                      measurement showed exactly what it cannot cover -- over
                      six full games the example bot never took an anchor,
                      never placed one, never captured an island, never built
                      an amplifier, a destabilizer or a booster, never
                      transferred a resource to a headquarters, never
                      upgraded or transformed a well and never wrote the
                      shared array -- and the Nim half of the answer is
                      committed (`chassis/scenario23.nim`, behind
                      `-d:bc23Scenario`). Its bit-exact Java twin is a
                      phase-30 item and `docs/PARITY.md` section bc23 says so
                      in those words. This script compares whatever `--bots`
                      it is given, so adding the twin is a one-line change to
                      the workflow.
  Tier C  (BLOCKING)  the first divergent round of every pair, compared
                      against `tools/ci/parity_ledger_bc23.json`. It FAILS if
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

Tier B is not here: it is a byte-diff of `data/bc23/tables.json` against what
the jar's own classes emit, and it lives in its own workflow step because it
needs the JVM rather than the traces. `tests/test_bc23_tempo.nim` asserts the
NIM side against the same committed bytes on every test run, so a rounding
regression is caught by the `test` job too.

    tools/ci/parity_tiers_bc23.py --dir <traces> --maps ... --bots ...
        --ledger tools/ci/parity_ledger_bc23.json [--summary $GITHUB_STEP_SUMMARY]
"""

from __future__ import annotations

import argparse
import itertools
import json
import pathlib
import re
import sys

BC_RE = re.compile(r" bc=\d+")
BC_VALUE_RE = re.compile(r"^R (\d+) U (\d+) team=\S+ ty=(\S+) .* bc=(\d+)$")

# The headroom bound. Past this point the comparison stops being defined,
# because the port's DecisionOps budget has no mid-turn resumption and the
# JVM's bytecode limit does. Measured over the six whole-game pairs: the
# example bot peaks at 745-893 bytecodes, which is 4-9 % of whichever type's
# limit it was, and never once cuts a turn off.
HEADROOM_PCT = 50

# `RobotType`'s own `BL` column, engine23 @ af42086. A type that is not here
# is a trace the emitters and this script disagree about, and guessing a
# limit would silently move the headroom bound.
LIMITS = {
    "HEADQUARTERS": 20000,
    "CARRIER": 12500,
    "LAUNCHER": 10000,
    "DESTABILIZER": 10000,
    "BOOSTER": 10000,
    "AMPLIFIER": 10000,
}


def limit_for(unit_type: str) -> int:
    if unit_type not in LIMITS:
        raise SystemExit(
            f"::error::unknown bc23 unit type {unit_type!r} in the Java "
            f"trace: tools/ci/parity_tiers_bc23.py has no bytecode limit for "
            f"it, so the headroom bound cannot be computed.")
    return LIMITS[unit_type]


def strip_bc(line: str) -> str:
    return BC_RE.sub("", line)


def first_divergence(java_path: pathlib.Path, nim_path: pathlib.Path):
    """(round, java line, nim line) of the first differing record, or None.

    `bc=` is stripped from BOTH sides: the Java column is the real bytecode
    counter and the Nim column is a constant 0, because the port has no
    counter to report. Stripping only one side compares a line against itself
    plus a suffix and fails on the first robot record of round 1.

    `zip_longest`, NOT `zip`. `zip` pulls from `jf` first and DISCARDS the
    line it already holds when `nf` runs out, so a Java trace exactly ONE
    line longer than the Nim one read as bit-exact: the tail check then read
    the line AFTER the discarded one and found nothing (r1-F26). Lengths are
    now compared by the walk itself -- a missing line is a divergence at the
    line number where it is missing.

    Streamed: a 2000-round trace is 3-4 MB a side and eighteen pairs would be
    seventy megabytes held at once otherwise.
    """
    ended = "<the trace ends here>"
    with java_path.open() as jf, nim_path.open() as nf:
        for lineno, (jl, nl) in enumerate(
                itertools.zip_longest(jf, nf), start=1):
            j = ended if jl is None else strip_bc(jl.rstrip("\n"))
            n = ended if nl is None else strip_bc(nl.rstrip("\n"))
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
    """Prove `first_divergence` can see a length mismatch in either direction.

    The r1-F26 case is the one this exists for: a Java trace exactly ONE line
    longer than the Nim trace. The old `zip`-based walk reported `None` for
    it, i.e. "bit-exact", which is the worst possible way for a parity gate to
    be wrong. A gate that cannot fail is not a gate.
    """
    import tempfile
    same = ["R 1 id=1 t=HEADQUARTERS x=1 y=1 hp=1",
            "R 2 id=1 t=HEADQUARTERS x=1 y=2 hp=1",
            "R 3 id=1 t=HEADQUARTERS x=1 y=3 hp=1"]
    tail = "R 4 id=1 t=HEADQUARTERS x=1 y=4 hp=1"
    cases = [
        ("equal traces", same, same, None),
        ("java one line longer", same + [tail], same, 4),
        ("nim one line longer", same, same + [tail], 4),
        ("a mid-trace difference", same,
         [same[0], "R 2 id=1 t=HEADQUARTERS x=9 y=2 hp=1", same[2]], 2),
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
    print(f"parity_tiers_bc23 selftest: {len(cases)} cases, "
          f"length mismatches detected on both sides")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true",
                    help="check first_divergence against known trace pairs "
                         "and exit; takes no other argument")
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

            if pct > HEADROOM_PCT:
                failures.append(
                    f"{bot}/{map_name}: unit {pid} used {pct} % of its "
                    f"bytecode limit on round {pround}, above the "
                    f"{HEADROOM_PCT} % headroom bound. Past that point the "
                    f"comparison is no longer defined, because the port's "
                    f"DecisionOps budget has no mid-turn resumption and the "
                    f"JVM's limit does. The Tier A window has to shrink, and "
                    f"this note would rather be wrong loudly than green "
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

            if pct <= HEADROOM_PCT:
                failures.append(
                    f"{bot}/{map_name}: diverges at round {round_no} while the "
                    f"traced bytecode peak is only {pct} % of the limit. That "
                    f"is a real rules bug, not an instrumentation artefact.")

    for pair in sorted(unused):
        failures.append(
            f"{pair[0]}/{pair[1]}: the ledger has an entry for a pair this run "
            f"did not compare. Remove it or restore the pair.")

    lines = ["| bot | map | tier A/A' | peak bytecode | note |",
             "|---|---|---|---|---|"]
    for bot, map_name, verdict, pct, note in rows:
        lines.append(f"| `{bot}` | `{map_name}` | {verdict} | {pct} % | {note} |")
    lines.append("")
    lines.append(f"Ledger: {len(entries)} accepted divergence(s). "
                 f"The phase-30 exit condition is Tiers A, A' and B passing "
                 f"with an EMPTY ledger; Tier A' is not shipped in this "
                 f"landing (see docs/PARITY.md section bc23).")
    table = "\n".join(lines)
    print(table)
    if args.summary:
        with args.summary.open("a") as fh:
            fh.write("### bc23 parity tiers\n\n" + table + "\n")

    for p in problems + failures:
        print(f"::error::{p}")
    if problems or failures:
        return 1
    print(f"bc23 parity: {len(rows)} pairs, all bit-exact for whole "
          f"2000-round games, ledger empty" if not entries else
          f"bc23 parity: {len(rows)} pairs compared against a "
          f"{len(entries)}-entry ledger")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
