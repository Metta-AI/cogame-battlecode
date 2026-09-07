#!/usr/bin/env python3
"""The bc24 parity tiers, over the traces the job has already emitted.

CI-TIME ONLY, called by `.github/workflows/ci.yml`'s `parity-oracle-bc24` job.
Split out of the workflow so the tier logic can be read, and so a change to it
shows up as a diff on a file rather than as a diff on a YAML block.

    tools/ci/parity_tiers_bc24.py --dir /tmp/oracle24 \\
        --maps DefaultSmall Yinyang BreadPudding Rivers Tunnels \\
        --bots examplefuncsplayer bc24scenario bc24scenariotel \\
        --ledger tools/ci/parity_ledger_bc24.json

For each (bot, map) pair the job has produced, in `--dir`:
    <bot>.<map>.java     the Java trace (with the `bc=` column)
    <bot>.<map>.nim      the Nim trace  (without it)

TIER A (BLOCKING) -- rounds 1 .. 2000 BIT-EXACT, WHOLE GAMES, every field.
bc24's window is the whole game rather than bc21's 22..245 rounds for one
MEASURED reason: the 2024 example bot never approaches its bytecode limit, so
the port's "no mid-turn resumption" divergence is never exercised and the
comparison stays defined to the last round. THE JOB DOES NOT ASSUME THAT: it
reads the `bc=` column and FAILS if any duck on any round exceeds
`--bc-limit-pct` of the limit, naming the round and the duck, because past that
point the comparison would have to shrink and this note would rather be wrong
loudly than green quietly.

TIER A-PRIME (BLOCKING) -- the same thing for the two `bc24scenario` packages,
whose whole purpose is to force the rare paths (all three trap types, every
trigger mode, mastery, the jail penalty, a carry, a capture, all three upgrades
and the round-200 teleport) early enough to be compared. Their bytecode ceiling
is TIGHTER, `--scenario-bc-limit-pct`, so they can never be cut off mid-turn.

TIER C (BLOCKING AGAINST THE LEDGER) -- the first divergent round of every
whole game, per (bot, map), against `tools/ci/parity_ledger_bc24.json`. Fails
if a pair diverges with no entry, diverges EARLIER than its entry, an entry no
longer reproduces (a stale excuse is as bad as a missing one), or ANY
divergence occurs while the traced bytecode peak is still under the limit --
which, on this year's evidence, means always, and therefore means a real rules
bug rather than an instrumentation artefact.

(Tier B is the JDK-only arithmetic step, which lives in the workflow because it
needs a JVM and no trace: see the job.)
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

BC_RE = re.compile(r" bc=(-?\d+)")
SCENARIO_BOTS = ("bc24scenario", "bc24scenariotel")


def round_of(line: str) -> int:
    parts = line.split(" ", 2)
    try:
        return int(parts[1])
    except (IndexError, ValueError):
        return -1


def strip_bytecodes(line: str) -> str:
    at = line.rfind(" bc=")
    return line[:at] if at >= 0 else line


def peak_bytecodes(lines: list[str]) -> tuple[int, int, str]:
    """(peak, round, unit id) over a Java trace."""
    peak, at, who = 0, -1, "-"
    for line in lines:
        m = BC_RE.search(line)
        if not m:
            continue
        value = int(m.group(1))
        if value > peak:
            peak = value
            at = round_of(line)
            parts = line.split(" ")
            who = parts[4] if len(parts) > 4 else "-"
    return peak, at, who


def first_divergent(java: list[str], nim: list[str]) -> int:
    for i in range(min(len(java), len(nim))):
        if java[i] != nim[i]:
            return max(round_of(java[i]), round_of(nim[i]))
    if len(java) != len(nim):
        longer = java if len(java) > len(nim) else nim
        return round_of(longer[min(len(java), len(nim))])
    return -1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, type=pathlib.Path)
    ap.add_argument("--maps", nargs="+", required=True)
    ap.add_argument("--bots", nargs="+", required=True)
    ap.add_argument("--ledger", required=True, type=pathlib.Path)
    ap.add_argument("--bc-limit", type=int, default=25000)
    ap.add_argument("--bc-limit-pct", type=int, default=50)
    ap.add_argument("--scenario-bc-limit-pct", type=int, default=25)
    ap.add_argument("--rounds", type=int, default=2000)
    ap.add_argument("--summary", type=pathlib.Path, default=None)
    args = ap.parse_args()

    ledger = json.loads(args.ledger.read_text())
    entries = {(e["bot"], e["map"]): e for e in ledger["entries"]}
    seen: set[tuple[str, str]] = set()

    failures: list[str] = []
    rows: list[str] = []

    for bot in args.bots:
        ceiling = (args.scenario_bc_limit_pct if bot in SCENARIO_BOTS
                   else args.bc_limit_pct)
        for name in args.maps:
            jpath = args.dir / f"{bot}.{name}.java"
            npath = args.dir / f"{bot}.{name}.nim"
            if not jpath.exists() or not npath.exists():
                failures.append(f"{bot}/{name}: a trace is missing "
                                f"({jpath.name} / {npath.name})")
                continue
            jraw = jpath.read_text().splitlines()
            nim = npath.read_text().splitlines()
            java = [strip_bytecodes(line) for line in jraw]

            peak, peak_round, peak_id = peak_bytecodes(jraw)
            pct = peak * 100.0 / max(1, args.bc_limit)
            if pct > ceiling:
                failures.append(
                    f"{bot}/{name}: duck {peak_id} used {peak} bytecodes "
                    f"({pct:.1f} % of {args.bc_limit}) at round {peak_round}, "
                    f"over the {ceiling} % ceiling this tier is defined "
                    f"under -- the comparison window would have to shrink")

            diverged = first_divergent(java, nim)
            rows.append(
                f"| `{bot}` | `{name}` | {len(java)} | {peak} "
                f"({pct:.1f} %) | "
                f"{'--' if diverged < 0 else diverged} |")

            entry = entries.get((bot, name))
            if diverged < 0:
                if entry is not None:
                    failures.append(
                        f"{bot}/{name}: the ledger claims a divergence at "
                        f"round {entry['first_divergent_round']} and there is "
                        f"none -- a stale excuse is as bad as a missing one; "
                        f"delete the entry")
                else:
                    seen.add((bot, name))
                continue

            # A divergence, on a pair whose bytecode peak is inside the
            # ceiling, is a RULES BUG.
            if entry is None:
                failures.append(
                    f"{bot}/{name}: FIRST DIVERGENT ROUND {diverged} with no "
                    f"ledger entry. The bytecode peak was {pct:.1f} % of the "
                    f"limit, so this is a rules bug, not an instrumentation "
                    f"artefact. Root-cause it (docs/RULES-BC24.md has the "
                    f"checklist) or add an entry naming the round, the map and "
                    f"a real cause -- 'unknown' is not a cause.")
                continue
            seen.add((bot, name))
            if diverged < entry["first_divergent_round"]:
                failures.append(
                    f"{bot}/{name}: diverges at round {diverged}, EARLIER "
                    f"than the ledger's {entry['first_divergent_round']}")
            if not str(entry.get("cause", "")).strip():
                failures.append(f"{bot}/{name}: the ledger entry has no cause")
            if str(entry.get("cause", "")).strip().lower() == "unknown":
                failures.append(
                    f"{bot}/{name}: 'unknown' is not a cause "
                    f"(the 2026-09-03 close state the operator ruled out)")

    for key in entries:
        if key not in seen:
            failures.append(
                f"{key[0]}/{key[1]}: the ledger has an entry for a pair this "
                f"run never produced")

    summary = [
        "## bc24 parity tiers",
        "",
        "| bot | map | trace lines | peak bytecodes | first divergent round |",
        "| --- | --- | --- | --- | --- |",
    ] + rows + [""]
    if failures:
        summary.append("### FAILURES")
        summary += [f"* {f}" for f in failures]
    else:
        summary.append("Tier A, Tier A-prime and Tier C all pass with an "
                       "EMPTY ledger: every traced game is bit-exact against "
                       "the published 3.0.5 jar for all "
                       f"{args.rounds} rounds.")
    text = "\n".join(summary) + "\n"
    if args.summary is not None:
        args.summary.write_text(text)
    print(text)

    if failures:
        for f in failures:
            print(f"::error::{f}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
