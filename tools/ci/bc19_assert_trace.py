#!/usr/bin/env python3
"""Assert, OFF THE ORACLE TRACE, that a bc19 parity tier really did what it
claims.

A bit-exact comparison of two traces of nothing is a bit-exact comparison of
nothing, which is the exact "green oracle proving nothing" trap. These
checks read the ENGINE's own trace -- never the port's -- so they cannot be
satisfied by a port that agrees with a broken oracle.

    tools/ci/bc19_assert_trace.py trickle <trace> [--ids 4]
    tools/ci/bc19_assert_trace.py barter  <trace>
"""

from __future__ import annotations

import re
import sys

TEAM_RE = re.compile(r"^R (\d+) T (RED|BLUE) karb=(\d+) fuel=(\d+) ")


def team_rows(path):
    rows = {"RED": [], "BLUE": []}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = TEAM_RE.match(line)
            if m:
                rows[m.group(2)].append(
                    (int(m.group(1)), int(m.group(3)), int(m.group(4))))
    return rows


def trickle(path: str) -> int:
    """TIER A. In an idle game the ONLY thing that moves a store is the flat
    25-fuel-per-team-per-round trickle -- karbonite has no passive income at
    all -- so every round must add exactly 25 fuel and exactly 0 karbonite.
    """
    rows = team_rows(path)
    bad = 0
    for team, seq in rows.items():
        if len(seq) < 2:
            print(f"::error::{team} has {len(seq)} round rows in {path}")
            return 1
        for i in range(1, len(seq)):
            r0, k0, f0 = seq[i - 1]
            r1, k1, f1 = seq[i]
            if k1 != k0:
                print(f"::error::karbonite moved in an IDLE game: {team} "
                      f"round {r1}, {k0} -> {k1}. Karbonite has NO passive "
                      f"income in this year.")
                bad += 1
                break
            if f1 - f0 != 25:
                print(f"::error::fuel did not rise by exactly 25: {team} "
                      f"round {r1}, {f0} -> {f1}. TRICKLE_FUEL is FLAT and "
                      f"does NOT scale with castles or churches.")
                bad += 1
                break
        else:
            print(f"{team}: fuel rose by exactly 25 a round for "
                  f"{len(seq)} rounds and karbonite never moved")
    return 1 if bad else 0


def barter(path: str) -> int:
    """TIER A'. The matched, payable offer must move THE TWO TEAMS' STORES
    IN OPPOSITE DIRECTIONS in the same round -- which is the only externally
    visible proof that `enactTrade` executed rather than merely recording an
    offer.
    """
    rows = team_rows(path)
    red = rows["RED"]
    blue = rows["BLUE"]
    if not red or not blue:
        print(f"::error::{path} has no team rows at all")
        return 1
    moved = 0
    for i in range(1, min(len(red), len(blue))):
        dk = red[i][1] - red[i - 1][1]
        df = red[i][2] - red[i - 1][2]
        bk = blue[i][1] - blue[i - 1][1]
        bf = blue[i][2] - blue[i - 1][2]
        # The trickle adds 25 to both sides' fuel every round, so the fuel
        # test is on the DELTA ABOVE THE TRICKLE.
        if dk != 0 and bk == -dk:
            moved += 1
            print(f"round {red[i][0]}: karbonite moved {dk:+d} RED and "
                  f"{bk:+d} BLUE, fuel {df - 25:+d} / {bf - 25:+d} above the "
                  f"trickle -- THE BARTER EXECUTED")
    if moved == 0:
        print("::error::no round moved the two teams' karbonite in OPPOSITE "
              "directions, so the matched payable offer never executed. A "
              "scripted path the bot does not reach must be DROPPED from "
              "the bot and added to docs/PARITY.md section 'What is NOT "
              "compared' with the reason -- never left in silently.")
        return 1
    return 0


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    what, path = sys.argv[1], sys.argv[2]
    if what == "trickle":
        return trickle(path)
    if what == "barter":
        return barter(path)
    print(f"::error::unknown check {what!r}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
