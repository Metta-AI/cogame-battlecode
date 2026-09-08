#!/usr/bin/env python3
"""bc25 parity tiers: compare the Java and Nim traces and enforce the ledger.

CI-TIME ONLY, run by the `parity-oracle-bc25` job of
`.github/workflows/ci.yml`. It reads the trace pairs the job produced and
enforces:

  Tier A  (BLOCKING)  rounds 1..2000 BIT-EXACT, WHOLE GAMES, for
                      `examplefuncsplayer` against itself on six `small`
                      maps. The window is the whole game for one MEASURED
                      reason: the 2025 example bot never approaches its
                      bytecode limit (peak 14 % of 17 500 over eight full
                      games, zero mid-turn cut-offs), so the port's "no
                      mid-turn resumption" divergence is never exercised and
                      the comparison stays defined to the last round. THE JOB
                      DOES NOT ASSUME THAT: it reads the `bc=` column and
                      FAILS if any unit on any round exceeds the headroom
                      bound, naming the round and the unit.
  Tier A' (BLOCKING)  the three scenario packages, whole games, bit-exact.
                      Tier A's own measurement showed exactly what it cannot
                      cover, and this is the answer.
  Tier C  (BLOCKING)  the first divergent round of every pair, compared
                      against `tools/ci/parity_ledger_bc25.json`. It FAILS if
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

Tier B is not here: it is a byte-diff of `data/bc25/tables.json` against what
the jar's own classes emit, and it lives in its own workflow step because it
needs the JVM rather than the traces.

    tools/ci/parity_tiers_bc25.py --dir <traces> --maps ... --bots ...
        --ledger tools/ci/parity_ledger_bc25.json [--summary $GITHUB_STEP_SUMMARY]
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
# JVM's bytecode limit does. Measured: the example bot peaks at 14 % and the
# scenario bot at 35 %.
HEADROOM_PCT = 50

LIMITS = {"ROBOT": 17500, "TOWER": 20000}


def limit_for(unit_type: str) -> int:
    robot = unit_type in ("SOLDIER", "SPLASHER", "MOPPER")
    return LIMITS["ROBOT"] if robot else LIMITS["TOWER"]


def strip_bc(line: str) -> str:
    return BC_RE.sub("", line)


def first_divergence(java_path: pathlib.Path, nim_path: pathlib.Path):
    """(round, line number, java line, nim line) of the first differing
    record, or None.

    `itertools.zip_longest`, NEVER `zip`. `zip` pulls from `jf` first and
    DISCARDS the line it already holds when `nf` runs out, so a Java trace
    exactly ONE line longer than the Nim one read as bit-exact: the tail check
    below it then read the line AFTER the discarded one and found nothing.
    Lengths are now compared by the walk itself -- a missing line is a
    divergence at the line number where it is missing.

    `strip_bc` ON BOTH SIDES, for the same reason: stripping only the Java
    side compares a line against itself plus a suffix the moment the Nim
    emitter grows a `bc=` column of its own.

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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, type=pathlib.Path)
    ap.add_argument("--maps", nargs="+", required=True)
    ap.add_argument("--bots", nargs="+", required=True)
    ap.add_argument("--ledger", required=True, type=pathlib.Path)
    ap.add_argument("--summary", type=pathlib.Path)
    args = ap.parse_args()

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
                 f"with an EMPTY ledger.")
    table = "\n".join(lines)
    print(table)
    if args.summary:
        with args.summary.open("a") as fh:
            fh.write("### bc25 parity tiers\n\n" + table + "\n")

    for p in problems + failures:
        print(f"::error::{p}")
    if problems or failures:
        return 1
    print(f"bc25 parity: {len(rows)} pairs, all bit-exact for whole "
          f"2000-round games, ledger empty" if not entries else
          f"bc25 parity: {len(rows)} pairs compared against a "
          f"{len(entries)}-entry ledger")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
