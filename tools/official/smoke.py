"""Require complete official-engine matches for every selected archive in both seats."""

import argparse
from pathlib import Path

from runner import CATALOG, run_match


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jdk", type=Path, default=Path("/usr/bin"))
    args = parser.parse_args()
    for year in ("bc25", "bc26"):
        players = [player for player in CATALOG.players if player.year == year]
        map_name = "AlarmClock" if year == "bc25" else "DefaultSmall"
        # A directed cycle seats every archive on both sides, including neural
        # and generated-code players. Matches always run to the engine's end.
        for a, b in zip(players, players[1:] + players[:1], strict=True):
            output = args.output.resolve() / f"{a.id}--{b.id}"
            result = run_match(a, b, args.build.resolve(), output, args.jdk, map_name, 600)
            print(f"{a.id} / {b.id}: {result.model_dump_json()}", flush=True)


if __name__ == "__main__":
    main()
