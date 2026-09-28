"""Compile pinned archived bots and execute their full code on published Battlecode engines."""

import argparse
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict

HERE = Path(__file__).resolve().parent


class Engine(BaseModel):
    url: str
    version: str
    sha256: str


class Player(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str
    year: Literal["bc25", "bc26"]
    repository: str
    revision: str
    source: str
    package: str
    generate: bool
    redistributable: bool
    license_file: str


class Catalog(BaseModel):
    engines: dict[str, Engine]
    players: list[Player]


class MatchResult(BaseModel):
    winner: Literal["A", "B"]
    rounds: int
    reason: str
    width: int
    height: int
    bytecodes: tuple[int, int]


CATALOG = Catalog.model_validate_json((HERE / "sources.json").read_text())


def build_player(player: Player, output: Path, jdk: Path, checkout: Path) -> None:
    engine = CATALOG.engines[player.year]
    jar = output / f"{player.year}.jar"
    if not jar.exists():
        urllib.request.urlretrieve(engine.url, jar)
    if hashlib.sha256(jar.read_bytes()).hexdigest() != engine.sha256:
        raise ValueError(f"Published engine digest mismatch: {jar}")
    if not checkout.exists():
        subprocess.run(["git", "clone", "--no-checkout", player.repository, str(checkout)], check=True)
        subprocess.run(["git", "-C", str(checkout), "checkout", "--detach", player.revision], check=True)
    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if revision != player.revision:
        raise ValueError(f"Archive revision mismatch for {player.id}: {revision}")
    dirty = subprocess.check_output(
        ["git", "-C", str(checkout), "status", "--porcelain", "--untracked-files=all"], text=True
    )
    if dirty:
        raise ValueError(f"Archive has modified or untracked files: {checkout}")
    source = checkout / player.source
    if player.generate:
        source = output / "generated" / player.id
        source.mkdir(parents=True, exist_ok=True)
        for template in sorted((checkout / player.source).glob("*.java.jinja2")):
            subprocess.run(
                [
                    sys.executable,
                    str(checkout / "jinja.py"),
                    "--input",
                    str(template.relative_to(checkout)),
                    "--output",
                    str(source / template.name.removesuffix(".jinja2")),
                    "--prod",
                    "True",
                ],
                cwd=checkout,
                check=True,
                stdout=subprocess.DEVNULL,
            )
    classes = output / "players" / player.id
    classes.mkdir(parents=True, exist_ok=True)
    java_sources = sorted(source.rglob("*.java"))
    if not java_sources:
        raise ValueError(f"No Java sources for {player.id}")
    subprocess.run(
        [str(jdk / "javac"), "-encoding", "UTF-8", "-cp", str(jar), "-d", str(classes), *map(str, java_sources)],
        check=True,
    )
    driver_classes = output / "drivers" / player.year
    driver_classes.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            str(jdk / "javac"),
            "-cp",
            str(jar),
            "-d",
            str(driver_classes),
            str(HERE / "OfficialMatch.java"),
            str(HERE / f"OfficialMatch{player.year[2:]}.java"),
        ],
        check=True,
    )
    hashes = {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in java_sources}
    (classes / "provenance.json").write_text(
        json.dumps({"player": player.model_dump(), "engine": engine.model_dump(), "source_sha256": hashes}, indent=2)
        + "\n"
    )


def run_match(a: Player, b: Player, build: Path, output: Path, jdk: Path, map_name: str, timeout: int) -> MatchResult:
    if a.year != b.year:
        raise ValueError("Players must use the same year")
    output.mkdir(parents=True, exist_ok=False)
    jar = build / f"{a.year}.jar"
    if hashlib.sha256(jar.read_bytes()).hexdigest() != CATALOG.engines[a.year].sha256:
        raise ValueError("Engine digest mismatch")
    for player in (a, b):
        provenance = json.loads((build / "players" / player.id / "provenance.json").read_text())
        if Player.model_validate(provenance["player"]) != player:
            raise ValueError(f"Compiled source provenance mismatch: {player.id}")
    with (output / "engine.log").open("w") as log:
        subprocess.run(
            [
                str(jdk / "java"),
                "-Xmx2g",
                "-XX:+UseSerialGC",
                "--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED",
                "--add-opens=java.base/jdk.internal.math=ALL-UNNAMED",
                "--add-opens=java.base/jdk.internal.util=ALL-UNNAMED",
                "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED",
                "--add-opens=java.base/sun.security.action=ALL-UNNAMED",
                "-Dbc.server.robot-player-to-system-out=false",
                "-Dbc.server.robot-player-replay-file-per-team-limit-bytes=10485760",
                "-cp",
                str(jar) + ":" + str(build / "drivers" / a.year),
                f"battlecode.world.OfficialMatch{a.year[2:]}",
                map_name,
                a.package,
                str(build / "players" / a.id),
                b.package,
                str(build / "players" / b.id),
                str(output),
                a.year[2:],
            ],
            check=True,
            timeout=timeout,
            stdout=log,
            stderr=log,
        )
    result = MatchResult.model_validate_json((output / "result.json").read_text())
    (output / "provenance.json").write_text(
        json.dumps(
            {"a": a.model_dump(), "b": b.model_dump(), "map": map_name, "engine": CATALOG.engines[a.year].model_dump()},
            indent=2,
        )
        + "\n"
    )
    # Validate the actual public telemetry surface, not merely process success.
    for line in (output / "frames.jsonl").read_text().splitlines():
        Frame.model_validate_json(line)
    return result


class Frame(BaseModel):
    round: int
    robots: list[tuple[int, Literal["A", "B", "NEUTRAL"], str, int, int, int]]
    economy: list[list[int]]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["build", "match"])
    parser.add_argument("players", nargs="+", choices=[p.id for p in CATALOG.players])
    parser.add_argument("--build", type=Path, default=Path("dist/official"))
    parser.add_argument(
        "--jdk", type=Path, default=Path("/usr/bin"), help="Directory containing Java 21 java and javac"
    )
    parser.add_argument("--checkout", type=Path, help="Use an existing unmodified pinned source checkout (one player)")
    parser.add_argument("--map", dest="map_name")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    build = args.build.resolve()
    build.mkdir(parents=True, exist_ok=True)
    players = [next(p for p in CATALOG.players if p.id == name) for name in args.players]
    if args.operation == "build":
        if args.checkout is not None and len(players) != 1:
            parser.error("--checkout requires exactly one player")
        for player in players:
            checkout = args.checkout.resolve() if args.checkout is not None else build / "archives" / player.id
            build_player(player, build, args.jdk, checkout)
    else:
        if len(players) != 2 or args.map_name is None or args.output is None:
            parser.error("match needs exactly two players, --map, and --output")
        print(
            run_match(
                players[0], players[1], build, args.output.resolve(), args.jdk, args.map_name, args.timeout
            ).model_dump_json()
        )


if __name__ == "__main__":
    main()
