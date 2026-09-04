#!/usr/bin/env python3
"""The bc21 parity tiers, over the traces the job has already emitted.

CI-TIME ONLY, called by `.github/workflows/ci.yml`'s `parity-oracle-bc21` job.
Split out of the workflow so the tier logic can be read, and so a change to it
shows up as a diff on a file rather than as a diff on a YAML block.

    tools/ci/parity_tiers_bc21.py --dir /tmp/oracle \\
        --maps maptestsmall Arena Bog Smile Star \\
        --ledger tools/ci/parity_ledger_bc21.json

For each map the job has produced, in `--dir`:
    <map>.java     the Java trace (with the `bc=` column)
    <map>.nim      the Nim trace  (without it)
    <map>.cutoff   the round the JVM first cut a robot off mid-turn, or -1

TIER A (BLOCKING) - rounds 1 .. `cutoff - 1` BIT-EXACT on every pair, every
field including ids and the %.9f cooldown. The window is the engine's OWN
answer to "how long is this comparison defined for", read out of its bytecode
counter rather than guessed: past the first mid-turn cut-off the Java bot has
consumed one fewer RNG draw than a port that has no bytecode counter by design
(docs/RULES-BC21.md section Divergences item 1). A floor of 20 rounds stops a
regression that breaks round 2 from silently shrinking the window to nothing.

TIER C (BLOCKING AGAINST THE LEDGER) - the first divergent round of the whole
1500-round game, per map, against `tools/ci/parity_ledger_bc21.json`. Fails if
a map diverges with no entry, diverges EARLIER than its entry, or an entry no
longer reproduces.

(Tier B is the two JDK-only arithmetic steps, which live in the workflow
because they need a JVM and no trace: see the job.)
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

TIER_A_FLOOR = 20


def round_of(line: str) -> int:
    parts = line.split(" ", 2)
    try:
        return int(parts[1])
    except (IndexError, ValueError):
        return -1


def strip_bytecodes(line: str) -> str:
    at = line.rfind(" bc=")
    return line[:at] if at >= 0 else line


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
    ap.add_argument("--ledger", required=True, type=pathlib.Path)
    ap.add_argument("--summary", type=pathlib.Path, default=None)
    args = ap.parse_args()

    ledger = json.loads(args.ledger.read_text())
    entries = {e["map"]: e for e in ledger["entries"]}

    failures: list[str] = []
    rows: list[str] = []

    for name in args.maps:
        java_path = args.dir / f"{name}.java"
        nim_path = args.dir / f"{name}.nim"
        cutoff_path = args.dir / f"{name}.cutoff"
        for path in (java_path, nim_path, cutoff_path):
            if not path.exists():
                failures.append(f"{name}: {path} is missing")
        if failures and failures[-1].startswith(name):
            continue

        java = [strip_bytecodes(l) for l in
                java_path.read_text().splitlines()]
        nim = nim_path.read_text().splitlines()
        cutoff = int(cutoff_path.read_text().strip() or "-1")

        # --- Tier A ------------------------------------------------------
        window = (cutoff - 1) if cutoff > 0 else max(round_of(l) for l in java)
        if window < TIER_A_FLOOR:
            failures.append(
                f"TIER A {name}: the comparison window is only {window} "
                f"rounds (the JVM cut a robot off at round {cutoff}); "
                f"a window under {TIER_A_FLOOR} rounds proves nothing")
            continue
        jw = [l for l in java if 0 < round_of(l) <= window]
        nw = [l for l in nim if 0 < round_of(l) <= window]
        if jw != nw:
            bad = first_divergent(jw, nw)
            for i in range(min(len(jw), len(nw))):
                if jw[i] != nw[i]:
                    failures.append(
                        f"TIER A {name}: diverged at round {bad}, inside the "
                        f"defined window 1..{window}\n"
                        f"    java: {jw[i]}\n    nim : {nw[i]}")
                    break
            else:
                failures.append(
                    f"TIER A {name}: the two traces have different lengths "
                    f"inside the window ({len(jw)} vs {len(nw)})")
            continue

        # --- Tier C ------------------------------------------------------
        divergent = first_divergent(java, nim)
        entry = entries.get(name)
        if divergent < 0:
            if entry is not None:
                failures.append(
                    f"TIER C {name}: the ledger claims a divergence at round "
                    f"{entry['first_divergent_round']} and there is none. "
                    f"Delete the entry - a stale excuse is as bad as a "
                    f"missing one.")
            rows.append(f"| `{name}` | 1..{window} | none (identical) | - |")
            continue
        if entry is None:
            failures.append(
                f"TIER C {name}: diverges at round {divergent} and has NO "
                f"ledger entry. Root-cause it and add it to "
                f"tools/ci/parity_ledger_bc21.json with round, map and cause.")
            continue
        if divergent < entry["first_divergent_round"]:
            failures.append(
                f"TIER C {name}: diverges at round {divergent}, EARLIER than "
                f"the ledger's {entry['first_divergent_round']}. That is a "
                f"regression, not an accepted divergence.")
            continue
        if cutoff != entry.get("first_cutoff_round"):
            failures.append(
                f"TIER C {name}: the JVM's first mid-turn cut-off moved from "
                f"round {entry.get('first_cutoff_round')} to {cutoff}; the "
                f"ledger entry no longer reproduces.")
            continue
        rows.append(f"| `{name}` | 1..{window} | {divergent} | "
                    f"{entry['first_divergent_round']} (ledger) |")

    report = ["## bc21 parity", "",
              "| map | Tier A window (bit-exact) | first divergent round | "
              "accepted |", "| --- | --- | --- | --- |"] + rows
    text = "\n".join(report) + "\n"
    print(text)
    if args.summary:
        with args.summary.open("a") as handle:
            handle.write(text)

    if failures:
        for failure in failures:
            print(f"::error::{failure}")
        return 1
    print(f"bc21 parity: Tier A bit-exact and Tier C within the ledger on "
          f"{len(args.maps)} pairs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
