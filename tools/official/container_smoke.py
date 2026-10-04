"""Seat every archive through the real game-hosted Coworld file contract."""

import subprocess
from pathlib import Path

from pydantic import BaseModel
from runner import CATALOG, Frame, MatchResult


class ReplayProof(BaseModel):
    year: str
    players: tuple[str, str]
    result: MatchResult
    frames: list[Frame]


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    project = root / "official-coworld"
    for year in ("bc25", "bc26"):
        players = [player for player in CATALOG.players if player.year == year and player.redistributable]
        for a, b in zip(players, players[1:] + players[:1], strict=True):
            output = project / "smoke" / f"{a.id}--{b.id}"
            subprocess.run(
                [
                    "uvx",
                    "--from",
                    "coworld[auth]==0.1.53",
                    "coworld",
                    "run-episode",
                    str(project / year / "dist/coworld_manifest.json"),
                    str(project / "players" / f"{a.id}.json"),
                    str(project / "players" / f"{b.id}.json"),
                    "--variant",
                    year,
                    "--timeout-seconds",
                    "600",
                    "--output-dir",
                    str(output),
                ],
                check=True,
                cwd=root,
            )
            replay = ReplayProof.model_validate_json((output / "replay").read_text())
            if replay.players != (a.id, b.id) or replay.year != year:
                raise RuntimeError("Archive seat provenance differs from requested file policies")
            if replay.result.rounds <= 1 or min(replay.result.bytecodes) <= 0:
                raise RuntimeError("Archived player code did not execute")
            print(f"{a.id} / {b.id}: complete official-engine file-policy episode", flush=True)


if __name__ == "__main__":
    main()
