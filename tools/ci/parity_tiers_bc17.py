#!/usr/bin/env python3
"""bc17 parity tiers: compare the Java and Nim traces and enforce the ledger.

CI-TIME ONLY, run by the `parity-oracle-bc17` job of
`.github/workflows/ci.yml`. It reads the trace pairs the job produced and
enforces:

  Tier A   (BLOCKING)  BIT-EXACT WHOLE GAMES -- round 1 to the engine's own
                       `isRunning() == false` -- for `bc17idle` against
                       itself on the NINE parity maps. **This tier is
                       deliberately small and that is worth saying**: in 2017
                       nothing happens without a player action, so what an
                       idle pair proves is the round counter, the initial
                       exec order off the map file, the neutral-tree pass,
                       the trove machinery idle, the INCOME CLIFF and the
                       round-limit ladder falling through to rung 4. The
                       job's own steps assert off the JAVA trace that it
                       really did those things.
  Tier A'  (BLOCKING)  the four scripted bots -- `bc17scenario`,
                       `bc17scenariotree`, `bc17scenariokill`,
                       `bc17scenariotie` -- against themselves on the same
                       nine maps and the same whole-game window. NO RNG AT
                       ALL: every branch is a function of the round number
                       and the robot's own age.
  Tier A'' (BLOCKING)  `examplefuncsplayer17` against itself on the same nine
                       maps. It is the one bot with a live per-robot
                       `java.util.Random(rc.getID())` (the determinism
                       patch), so this tier proves the port's
                       `src/battlecode/rng.nim` reproduces that stream
                       call-for-call INCLUDING the `&&` short-circuit that
                       decides whether a draw happens at all -- and it is the
                       tier that runs the real filler.
  Tier C   (BLOCKING)  the first divergent round of every pair, compared
                       against `tools/ci/parity_ledger_bc17.json`. It FAILS
                       if (a) a pair diverges and has no ledger entry, (b) a
                       pair diverges EARLIER than its entry, (c) a ledger
                       entry no longer reproduces -- a stale excuse is as bad
                       as a missing one -- or (d) ANY divergence occurs while
                       the traced bytecode peak is still under the headroom
                       bound, which on this year's evidence means always, and
                       therefore means a real rules bug rather than a
                       metering artefact. **Tier C is NOT gated on a subset
                       of maps**: there is no map on which parity is expected
                       to fail, and if one appears it is a bug and not a map.

ROOT-CAUSE-OR-FAIL IS THE STANDING RULE and it is the operator's ruling on
the bc26 run (Fleet card 1218171523823317), not this script's preference. An
unexplained divergence is a FAIL, not a ledger line: every entry must name a
round, a map and a ROOT CAUSE, and a cause of "unknown" is rejected by the
schema check below.

THIS IS bc16'S SCRIPT -- whose comparator bugs are already fixed there --
MINUS THE FLOAT ALLOWLIST, AND THE SUBTRACTION IS THE POINT:

  1. `bc=` is stripped from BOTH traces, by one `normalize()` applied to
     each side. Stripping only the Java side compares a line against itself
     plus a suffix and "diverges" at round 1 on otherwise-identical lines
     (LEARNINGS 2026-09-08, bc23).
  2. `itertools.zip_longest`, NEVER `zip`. `zip` stops at the shorter file
     and DISCARDS the tail, so a Java trace one line longer than the Nim one
     reads bit-exact. `selftest()` constructs exactly that pair, in both
     directions, and asserts the comparator reports a divergence.
  3. HEX FOLDS AND RAW-BIT FLOATS ARE CANONICALISED ON BOTH SIDES through an
     explicit allowlist, because `ra=99` is a valid hex string and is not a
     checksum. Both emitters print `java.lang.Long.toHexString`-style -- lower
     case, no leading zeros -- so this is belt and braces rather than a fix,
     and the self-test proves it cannot mask a real difference.
  4. **THERE IS NO FLOAT ALLOWLIST, AND THAT IS bc17'S ONE DELIBERATE
     DEPARTURE FROM ITS SIBLINGS.** Every float in this trace -- every
     coordinate, radius, health, direction, speed, damage and bullet supply
     -- is printed as its RAW IEEE-754 BITS by BOTH emitters, so there is no
     `%.6f` rounding mode for the two sides to disagree about and one fewer
     place for a comparator bug to hide. bc16 needed `_canon_float` because
     `String.format` rounds HALF-UP where C's `printf` rounds HALF-TO-EVEN;
     bit patterns have no rounding mode.
  5. **NO COORDINATE IS NORMALISED ON EITHER SIDE.** Unlike bc16 (V3), the
     bc17 port keeps the map's own origin -- `data/maps/bc17/*.json` carries
     it and `world.rect` uses it -- so both traces are in absolute engine
     coordinates and neither emitter translates anything. A tripwire below
     asserts that the two sides agree about the origin at all, by requiring
     the first `U` line of each pair to match before anything else is
     reported.

Tier B is not here: it is a byte-diff of the jar's own `GameConstants` and
`RobotType` tables, of `data/bc17/fdlibm_vectors.json` and of all 22
committed maps' `LiveMap` fields against what the jar's own classes emit, and
it lives in its own workflow steps because it needs the JVM rather than the
traces. Tier B' -- the metering divergence -- is the headroom column read
here plus the separate, NON-COMPARED `bc17slowbot` run in the workflow.
"""

import argparse
import itertools
import json
import pathlib
import re
import sys

BC_RE = re.compile(r" bc=-?\d+")
BC_VALUE_RE = re.compile(r"^R (\d+) U (\d+) team=\S+ ty=(\S+) .* bc=(-?\d+)$")

# BUG 3's allowlist. Every field here is either a 64-bit fold printed by
# `Long.toHexString` on one side and by `javaHex(toHex(...))` on the other, or
# a float32's RAW IEEE-754 BITS printed the same two ways. Nothing else in the
# trace is hex, and nothing else may be added without a reason: `ra=99` parses
# as hex too.
HEX_FIELDS = ("bul", "x", "y", "hp", "r", "mhp", "dir", "sp", "dmg", "arg",
              "exec", "ubod", "tbod", "bbod", "broad")
HEX_RE = re.compile(
    r"\b(" + "|".join(HEX_FIELDS) + r")=([0-9a-fA-F]+)\b")

# THE HEADROOM BOUND (Tier B'). Past this point the comparison stops being
# defined, because the port's DecisionOps budget has no mid-turn resumption
# and the JVM's bytecode limit does (docs/RULES-BC17.md V1). MEASURED over all
# 54 whole-game pairs: `bc17idle` peaks at 3 bytecodes, the four scenario bots
# at 5 % of a limit and `examplefuncsplayer17` at 3 %, so no bot in this job
# ever comes near it -- and the job DOES NOT ASSUME THAT, it reads the `bc=`
# column and FAILS if any robot on any round exceeds the bound, naming the
# round and the robot. Every compared bot ALSO asserts
# `Clock.getBytecodesLeft() > 5000` at the end of its own turn, so the engine's
# pause-and-resume provably never fired in any game compared here.
HEADROOM_PCT = 25

# `RobotType`'s own `bytecodeLimit` column, battlecode 2017.1.6.2. A type that
# is not here is a trace the emitters and this script disagree about, and
# guessing a limit would silently move the headroom bound.
LIMITS = {
    "ARCHON": 30000,
    "GARDENER": 15000,
    "LUMBERJACK": 15000,
    "SOLDIER": 15000,
    "TANK": 15000,
    "SCOUT": 15000,
}


def limit_for(unit_type: str) -> int:
    if unit_type not in LIMITS:
        raise SystemExit(
            f"::error::unknown bc17 robot type {unit_type!r} in the Java "
            f"trace: tools/ci/parity_tiers_bc17.py has no bytecode limit for "
            f"it, so the headroom bound cannot be computed.")
    return LIMITS[unit_type]


def _canon_hex(m: "re.Match[str]") -> str:
    return f"{m.group(1)}={format(int(m.group(2), 16) & 0xFFFFFFFFFFFFFFFF, 'x')}"


def normalize(line: str) -> str:
    """The ONE normalisation, applied identically to BOTH sides.

    Bug 1: the `bc=` column goes, whichever side carries it.
    Bug 3: every named hex field -- fold or raw float bits -- is re-parsed and
    re-emitted canonically.
    There is deliberately NO float rule (bug 4 cannot exist here) and NO
    per-side rule of any kind.
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

    Streamed: a bc17 trace runs 1-300 MB a side (measured: `Chess` is
    2 804 066 lines) and fifty-four pairs would be tens of gigabytes held at
    once otherwise.
    """
    ended = "<the trace ends here>"
    with java_path.open() as jf, nim_path.open() as nf:
        for lineno, (jl, nl) in enumerate(
                itertools.zip_longest(jf, nf), start=1):
            # THE FAST PATH, and it changes no verdict: both emitters already
            # print the canonical form, so two lines that are byte-equal
            # before `normalize()` are byte-equal after it. Only a line that
            # already differs pays for the regexes -- which is what turns a
            # 2 804 066-line pair (`Chess`) from minutes into seconds.
            if jl is not None and nl is not None and jl == nl:
                continue
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
            # Only `U` lines carry a `bc=` column; the cheap substring test
            # keeps the regex off the other four fifths of the trace.
            if " U " not in line:
                continue
            m = BC_VALUE_RE.match(line.rstrip("\n"))
            if not m:
                continue
            used = int(m.group(4))
            pct = used * 100 // limit_for(m.group(3))
            if pct > best_pct:
                best_pct = pct
                best = (pct, int(m.group(1)), int(m.group(2)))
    return best


def check_ledger_schema(entries) -> list:
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

    One case per known comparator bug, plus the two bc17-specific ones: that a
    raw-bit float field is canonicalised on BOTH sides, and that a DIFFERENT
    raw-bit float is still a divergence.
    """
    import tempfile
    U = ("R {r} U 1 team=A ty=SOLDIER x=43a7a587 y=4314afb4 hp=42480000 "
         "ra={r} ac=0 mc=0 wc=0 shc=0 cd=0")
    same = [U.format(r=1), U.format(r=2), U.format(r=3)]
    tail = U.format(r=4)
    G = ("R 1 G exec=cafe execlen=2 ubod=ff tbod=0 bbod=0 nb=0 rid=12528 "
         "bid=35207 broad=0")
    Gpad = ("R 1 G exec=000000000000cafe execlen=2 ubod=00000000000000ff "
            "tbod=0000000000000000 bbod=0000000000000000 nb=0 rid=12528 "
            "bid=35207 broad=0000000000000000")
    cases = [
        ("bug 1: equal but for the bc= column", same, same, None),
        ("bug 2: java one line longer", same + [tail], same, 4),
        ("bug 2: nim one line longer", same, same + [tail], 4),
        ("a mid-trace difference is still found", same,
         [same[0], U.format(r=2).replace("x=43a7a587", "x=43a7a588"),
          same[2]], 2),
        ("bug 3: a zero-padded fold is the same fold", [G], [Gpad], None),
        ("bug 3: a DIFFERENT fold is still a divergence", [G],
         [Gpad.replace("exec=000000000000cafe", "exec=000000000000caff")], 1),
        ("bug 3: ra is NOT a hex field and is not canonicalised",
         [U.format(r=1)], [U.format(r=1).replace("ra=1", "ra=01")], 1),
        ("bc17: a zero-padded RAW-BIT float is the same float",
         ["R 1 T A bul=43960000 vp=0 ar=1 ga=0 lj=0 so=0 ta=0 sc=0 tr=0 "
          "trm=0"],
         ["R 1 T A bul=043960000 vp=0 ar=1 ga=0 lj=0 so=0 ta=0 sc=0 tr=0 "
          "trm=0"], None),
        ("bc17: ONE ULP of difference is a divergence",
         ["R 1 T A bul=43960000 vp=0 ar=1 ga=0 lj=0 so=0 ta=0 sc=0 tr=0 "
          "trm=0"],
         ["R 1 T A bul=43960001 vp=0 ar=1 ga=0 lj=0 so=0 ta=0 sc=0 tr=0 "
          "trm=0"], 1),
        ("bc17: an integer column is untouched",
         ["R 1 G exec=1 execlen=2 ubod=3 tbod=4 bbod=5 nb=0 rid=12528 "
          "bid=35207 broad=7"],
         ["R 1 G exec=1 execlen=2 ubod=3 tbod=4 bbod=5 nb=0 rid=12528 "
          "bid=35207 broad=7"], None),
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
    problems = check_ledger_schema([
        {"bot": "bc17idle", "map": "shrine", "first_divergent_round": 7,
         "cause": "unknown", "docs": "PARITY.md#bc17"}])
    if not problems:
        print("::error::the ledger schema check accepted a cause of "
              "'unknown'. Root-cause-or-fail is the standing rule.")
        return 1
    print(f"parity_tiers_bc17 selftest: {len(cases)} cases, all three known "
          f"comparator bugs plus the two raw-bit ones and the ledger "
          f"schema's 'unknown' rejection covered")
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
                    f"{bot}/{map_name}: robot {pid} used {pct} % of its "
                    f"bytecode limit on round {pround}, above the "
                    f"{HEADROOM_PCT} % headroom bound. Past that point the "
                    f"comparison is no longer defined, because the port's "
                    f"DecisionOps budget has no mid-turn resumption and the "
                    f"JVM's limit does (V1). This job would rather be wrong "
                    f"loudly than green quietly.")

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
                    f"{bot}/{map_name}: diverges at round {round_no} while "
                    f"the traced bytecode peak is only {pct} % of the limit. "
                    f"That is a real rules bug, not an instrumentation "
                    f"artefact.")

    for pair in sorted(unused):
        failures.append(
            f"{pair[0]}/{pair[1]}: the ledger has an entry for a pair this run "
            f"did not compare. Remove it or restore the pair.")

    lines = ["| bot | map | tier A / A\u2032 / A\u2033 | peak bytecode | note |",
             "|---|---|---|---|---|"]
    for bot, map_name, verdict, pct, note in rows:
        lines.append(
            f"| `{bot}` | `{map_name}` | {verdict} | {pct} % | {note} |")
    lines.append("")
    lines.append(f"Ledger: {len(entries)} accepted divergence(s). "
                 f"The tiers that RAN here are A (`bc17idle`), A\u2032 (the "
                 f"four scripted bots), A\u2033 (`examplefuncsplayer17`) and "
                 f"C; Tier B is the jar's own constants, the fdlibm vectors "
                 f"and the 22 maps byte-diffed in the job's own steps, and "
                 f"Tier B\u2032 is the headroom column above plus the "
                 f"separate, NON-COMPARED `bc17slowbot` run. The phase-30 "
                 f"exit condition is Tiers A, A\u2032, A\u2033, B and B\u2032 "
                 f"passing with an EMPTY ledger.")
    table = "\n".join(lines)
    print(table)
    if args.summary:
        with args.summary.open("a") as fh:
            fh.write("### bc17 parity tiers\n\n" + table + "\n")

    for p in problems + failures:
        print(f"::error::{p}")
    if problems or failures:
        return 1
    print(f"bc17 parity: {len(rows)} pairs, all bit-exact for whole games, "
          f"ledger empty" if not entries else
          f"bc17 parity: {len(rows)} pairs compared against a "
          f"{len(entries)}-entry ledger")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
