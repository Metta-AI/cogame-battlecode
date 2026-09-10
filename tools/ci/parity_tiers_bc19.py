#!/usr/bin/env python3
"""Compare a bc19 Nim trace against the pinned 2019 engine's, tier by tier.

bc16's comparator, whose two comparator bugs are already fixed there and are
fixed here by construction:

  * **`itertools.zip_longest`, NEVER `zip`.** A one-line-longer oracle trace
    read as bit-exact under `zip`, which is the failure mode that makes a
    parity job green while it is comparing a prefix. `--self-test`
    constructs exactly that pair and asserts a divergence is reported.
  * **`normalize()` IS APPLIED TO BOTH SIDES BY ONE CODE PATH.** bc23's
    comparator stripped a field from the Java side only and every pair
    "diverged" at round 1 (LEARNINGS 2026-09-08). There is exactly one
    `normalize` in this file, both sides go through it, and it is called
    with the same arguments for both.

**THERE IS NO FLOAT ALLOWLIST, BECAUSE THERE ARE NO FLOATS.** Every value in
a bc19 trace is an integer: the 2019 rule set has no float state at all, and
its two non-integer operations are tabled at build time (D5). That is the
single biggest thing bc19 has going for it over its siblings, and it is why
`normalize` does only two things.

Usage:
    tools/ci/parity_tiers_bc19.py --oracle j.txt --nim n.txt \\
        --bot examplefuncsplayer19 --map seed-0043 \\
        --ledger tools/ci/parity_ledger_bc19.json [--strip-turn]
    tools/ci/parity_tiers_bc19.py --self-test

Exit codes:
    0  the pair is bit-exact, or it diverges exactly where the ledger says
    1  a usage error, or an unusable ledger entry
    2  THE PAIR DIVERGED. Either with no ledger entry, or EARLIER than its
       entry, or the entry no longer reproduces -- a stale excuse is as bad
       as a missing one.
"""

from __future__ import annotations

import argparse
import gzip
import io
import itertools
import json
import pathlib
import re
import sys

MAX_REPORTED = 200

# The three named checksum fields. They are printed as unsigned 64-bit
# integers on both sides -- `fnv1a64` in `years/bc19/world.nim` and the
# BigInt fold in `tools/oracle/bc19/bc19_trace.js` -- but a future change to
# either printer (a signed cast, a hex form, a leading `+`) would look like a
# rules divergence. Re-parsing and re-emitting canonically makes the
# comparison about the VALUE and not about the formatting.
CHECKSUM_FIELDS = ("shadowchk", "queuechk", "mt")
CHECKSUM_RE = re.compile(r"\b(" + "|".join(CHECKSUM_FIELDS) + r")=(-?[0-9]+)\b")
TURN_RE = re.compile(r" t=-?[0-9]+")
ROUND_RE = re.compile(r"^R (\d+) ")


def normalize(line: str, strip_turn: bool) -> str:
    """THE ONE NORMALISER, AND BOTH SIDES GO THROUGH IT.

    It does exactly two things:

      1. re-parses every named checksum field as an unsigned 64-bit integer
         and re-emits it canonically;
      2. strips the `t=` field -- the robot's own turn counter -- from BOTH
         traces, and ONLY when the caller asks, which is only for the
         Tier-B' headroom assertion.

    Nothing is normalised on one side only. Nothing else is normalised at
    all.
    """
    def fix(m: re.Match) -> str:
        return "%s=%d" % (m.group(1), int(m.group(2)) & 0xFFFFFFFFFFFFFFFF)
    out = CHECKSUM_RE.sub(fix, line)
    if strip_turn:
        out = TURN_RE.sub("", out)
    return out


def round_of(line: str) -> int:
    m = ROUND_RE.match(line)
    return int(m.group(1)) if m else -1


def compare(oracle_path: pathlib.Path, nim_path: pathlib.Path,
            strip_turn: bool):
    """Stream both traces and return (first_divergent_round, [reports]).

    STREAMING, never loaded whole: a 1000-round `examplefuncsplayer19` trace
    on a three-castle board is 40 000 lines and the job runs 54 of them.
    """
    reports: list[str] = []
    first_round = -1
    with oracle_path.open("r", encoding="utf-8") as fo, \
            nim_path.open("r", encoding="utf-8") as fn:
        for i, (a, b) in enumerate(
                itertools.zip_longest(fo, fn, fillvalue=None), start=1):
            # `zip_longest`, never `zip`: a trace that is one line longer
            # than the other MUST NOT read as bit-exact.
            if a is None:
                if first_round < 0:
                    first_round = round_of(normalize(b.rstrip("\n"), strip_turn))
                if len(reports) < MAX_REPORTED:
                    reports.append("line %d: oracle ENDED, nim has %r"
                                   % (i, b.rstrip("\n")))
                continue
            if b is None:
                if first_round < 0:
                    first_round = round_of(normalize(a.rstrip("\n"), strip_turn))
                if len(reports) < MAX_REPORTED:
                    reports.append("line %d: nim ENDED, oracle has %r"
                                   % (i, a.rstrip("\n")))
                continue
            na = normalize(a.rstrip("\n"), strip_turn)
            nb = normalize(b.rstrip("\n"), strip_turn)
            if na == nb:
                continue
            if first_round < 0:
                first_round = max(round_of(na), round_of(nb))
            if len(reports) < MAX_REPORTED:
                reports.append("line %d:\n  oracle %s\n  nim    %s"
                               % (i, na, nb))
    return first_round, reports


def load_ledger(path: pathlib.Path):
    if not path.exists():
        return []
    doc = json.loads(path.read_text())
    if not isinstance(doc, list):
        raise SystemExit("::error::%s is not a JSON array" % path)
    for entry in doc:
        for key in ("bot", "map", "first_divergent_round", "cause", "docs"):
            if key not in entry:
                raise SystemExit(
                    "::error::%s: a ledger entry is missing %r. Every entry "
                    "needs bot, map, first_divergent_round, cause and docs."
                    % (path, key))
        # ROOT-CAUSE-OR-FAIL IS THE STANDING RULE (the operator's ruling on
        # the bc26 run, Fleet card 1218171523823317). A cause of "unknown"
        # is NOT a cause and the schema rejects it.
        cause = str(entry["cause"]).strip().lower()
        if not cause or cause in ("unknown", "tbd", "?", "todo"):
            raise SystemExit(
                "::error::%s: the entry for %s/%s has no real cause (%r). An "
                "unexplained divergence is a FAIL, not a ledger line."
                % (path, entry["bot"], entry["map"], entry["cause"]))
    return doc


def self_test() -> int:
    """The comparator's own gate.

    Constructs the exact pair that `zip` reads as bit-exact -- one trace a
    line longer than the other -- and asserts a divergence IS reported; and
    constructs a pair that differs only in the SIGN of a checksum field and
    asserts it is NOT, because that is formatting and not a rule.
    """
    import tempfile
    ok = True
    with tempfile.TemporaryDirectory() as d:
        root = pathlib.Path(d)
        a = root / "a.txt"
        b = root / "b.txt"

        a.write_text("R 1 A 5 act=MOVE dx=1 dy=0\nR 1 W winner=RED wc=0\n")
        b.write_text("R 1 A 5 act=MOVE dx=1 dy=0\nR 1 W winner=RED wc=0\n"
                     "R 2 W winner=RED wc=0\n")
        rnd, rep = compare(a, b, False)
        if not rep or rnd != 2:
            print("::error::SELF-TEST FAILED: a one-line-longer trace read "
                  "as bit-exact. That is exactly the `zip` bug this "
                  "comparator exists not to have.")
            ok = False
        else:
            print("self-test: a one-line-longer trace diverges at round "
                  "%d, as it must" % rnd)

        # An identical value printed signed on one side and unsigned on the
        # other is FORMATTING, and both sides go through the same
        # normaliser.
        a.write_text("R 3 G shadowchk=18446744073709551615 queuechk=1 "
                     "mt=2 mti=3\n")
        b.write_text("R 3 G shadowchk=-1 queuechk=1 mt=2 mti=3\n")
        rnd, rep = compare(a, b, False)
        if rep:
            print("::error::SELF-TEST FAILED: the normaliser did not "
                  "canonicalise a checksum field on both sides: %s" % rep[0])
            ok = False
        else:
            print("self-test: the checksum normaliser is symmetric")

        # And a REAL divergence in the same line is still reported.
        b.write_text("R 3 G shadowchk=-2 queuechk=1 mt=2 mti=3\n")
        rnd, rep = compare(a, b, False)
        if not rep or rnd != 3:
            print("::error::SELF-TEST FAILED: a real checksum divergence "
                  "was swallowed by the normaliser.")
            ok = False
        else:
            print("self-test: a real checksum divergence is still reported")

        # `--strip-turn` strips from BOTH sides, never one.
        a.write_text("R 1 U 5 x=1 y=2 t=7 sig=0\n")
        b.write_text("R 1 U 5 x=1 y=2 t=9 sig=0\n")
        rnd, rep = compare(a, b, True)
        if rep:
            print("::error::SELF-TEST FAILED: --strip-turn did not strip "
                  "both sides: %s" % rep[0])
            ok = False
        else:
            print("self-test: --strip-turn is symmetric")
        rnd, rep = compare(a, b, False)
        if not rep:
            print("::error::SELF-TEST FAILED: without --strip-turn the turn "
                  "counter must still be compared.")
            ok = False
        else:
            print("self-test: without --strip-turn the turn counter is "
                  "compared")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--oracle", type=pathlib.Path)
    ap.add_argument("--nim", type=pathlib.Path)
    ap.add_argument("--bot", default="")
    ap.add_argument("--map", dest="map_name", default="")
    ap.add_argument("--ledger", type=pathlib.Path,
                    default=pathlib.Path("tools/ci/parity_ledger_bc19.json"))
    ap.add_argument("--digest", type=pathlib.Path, default=None,
                    help="write a gzipped digest of the divergences here")
    ap.add_argument("--strip-turn", action="store_true",
                    help="strip `t=` from BOTH traces (Tier B' headroom "
                         "assertion only)")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.oracle or not args.nim:
        ap.error("--oracle and --nim are required unless --self-test")
    for p in (args.oracle, args.nim):
        if not p.exists():
            print("::error::no trace at %s" % p)
            return 1

    ledger = load_ledger(args.ledger)
    first_round, reports = compare(args.oracle, args.nim, args.strip_turn)
    label = "%s/%s" % (args.bot, args.map_name)

    if not reports:
        print("BIT-EXACT %s (%s lines)"
              % (label, sum(1 for _ in args.oracle.open())))
        return 0

    if args.digest:
        buf = io.StringIO()
        buf.write("bot=%s map=%s first_divergent_round=%d\n"
                  % (args.bot, args.map_name, first_round))
        for r in reports:
            buf.write(r + "\n")
        with gzip.open(args.digest, "wt", encoding="utf-8") as fh:
            fh.write(buf.getvalue())

    entry = None
    for e in ledger:
        if e["bot"] == args.bot and e["map"] == args.map_name:
            entry = e
            break

    print("::group::%s diverges at round %d (%d reported)"
          % (label, first_round, len(reports)))
    for r in reports[:MAX_REPORTED]:
        print(r)
    print("::endgroup::")

    if entry is None:
        # TIER C, (a): a pair that diverges with NO ledger entry is a FAIL.
        print("::error::%s DIVERGED AT ROUND %d AND HAS NO LEDGER ENTRY. "
              "Root-cause-or-fail is the standing rule: an unexplained "
              "divergence is a FAIL, not a ledger line."
              % (label, first_round))
        return 2
    want = int(entry["first_divergent_round"])
    if first_round < want:
        # TIER C, (b): diverging EARLIER than the entry says is a FAIL.
        print("::error::%s diverged at round %d but its ledger entry claims "
              "round %d. Diverging EARLIER than the excuse is a regression."
              % (label, first_round, want))
        return 2
    if first_round > want:
        # TIER C, (c): a ledger entry that no longer reproduces is a FAIL --
        # a stale excuse is as bad as a missing one.
        print("::error::%s diverged at round %d but its ledger entry claims "
              "round %d. THE ENTRY NO LONGER REPRODUCES; a stale excuse is "
              "as bad as a missing one. Re-root-cause it or delete it."
              % (label, first_round, want))
        return 2
    print("LEDGERED %s at round %d: %s (%s)"
          % (label, first_round, entry["cause"], entry["docs"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
