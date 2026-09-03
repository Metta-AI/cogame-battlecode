#!/usr/bin/env python3
"""Read a Java-engine `.bc26` match and emit the parity trace.

CI-TIME ONLY (`parity-oracle`), never in an image. `tools/parity_trace.nim`
emits the SAME text from the Nim sim and the job diffs the two — see
docs/PARITY.md for what each tier proves.

Trace format, one line per record, deterministic and diffable:

    R <round> T <team> chz=<cheeseTransferred> cat=<catDamage> \
        kpk=<kings+10*teamCheese> rats=<babyRats> dirt=<n> rt=<n> ct=<n>
    R <round> U <robotId> hp=<n> chz=<n> mc=<n> tc=<n> ac=<n> \
        x=<n> y=<n> dir=<NAME> coop=<0|1>

`kpk` is the engine's packed `kings + 10 * teamCheese` stat
(`GameWorld.java:1013`); the scoring code decodes it `% 10` / `// 10`.
"""

from __future__ import annotations

import argparse
import gzip
import pathlib
import sys

# FlatHelpers.getOrdinalFromDirection, inverted.
DIR_BY_ORDINAL = ["CENTER", "WEST", "SOUTHWEST", "SOUTH", "SOUTHEAST",
                  "EAST", "NORTHEAST", "NORTH", "NORTHWEST"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--replay", required=True, type=pathlib.Path)
    ap.add_argument("--schema", required=True, type=pathlib.Path,
                    help="battlecode26 schema/python directory")
    ap.add_argument("--rounds", type=int, default=50)
    ap.add_argument("--out", type=pathlib.Path)
    args = ap.parse_args()

    sys.path.insert(0, str(args.schema))
    from battlecode.schema.GameWrapper import GameWrapper
    from battlecode.schema.Event import Event
    from battlecode.schema.Round import Round

    # The server gzips its save file (`Server.java`); a raw buffer is also
    # accepted so a hand-produced fixture still reads.
    raw = args.replay.read_bytes()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    wrapper = GameWrapper.GetRootAs(bytearray(raw), 0)
    lines: list[str] = []
    for i in range(wrapper.EventsLength()):
        wrapped = wrapper.Events(i)
        if wrapped.EType() != Event.Round:
            continue
        table = wrapped.E()
        rnd = Round()
        rnd.Init(table.Bytes, table.Pos)
        round_id = rnd.RoundId()
        if round_id > args.rounds:
            break
        for t in range(rnd.TeamIdsLength()):
            # TeamMapping: id 1 -> A, 2 -> B.
            team = "A" if rnd.TeamIds(t) == 1 else "B"
            lines.append(
                f"R {round_id} T {team} chz={rnd.TeamCheeseTransferred(t)} "
                f"cat={rnd.TeamCatDamage(t)} kpk={rnd.TeamAliveRatKings(t)} "
                f"rats={rnd.TeamAliveBabyRats(t)} "
                f"dirt={rnd.TeamDirtAmounts(t)} "
                f"rt={rnd.TeamRatTrapCount(t)} ct={rnd.TeamCatTrapCount(t)}")
        for j in range(rnd.TurnsLength()):
            turn = rnd.Turns(j)
            lines.append(
                f"R {round_id} U {turn.RobotId()} hp={turn.Health()} "
                f"chz={turn.Cheese()} mc={turn.MoveCooldown()} "
                f"tc={turn.TurningCooldown()} ac={turn.ActionCooldown()} "
                f"x={turn.X()} y={turn.Y()} "
                f"dir={DIR_BY_ORDINAL[turn.Dir()]} "
                f"coop={1 if turn.IsCooperation() else 0}")

    text = "\n".join(lines) + "\n"
    if args.out:
        args.out.write_text(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
