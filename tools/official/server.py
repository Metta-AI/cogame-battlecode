"""Game-hosted Coworld that executes complete pinned archives on official engines."""

import asyncio
import hashlib
import json
import os
import shutil
from pathlib import Path
from typing import Literal
from urllib.parse import unquote, urlparse

from aiohttp import web
from pydantic import BaseModel, ConfigDict, Field
from runner import CATALOG, Frame, MatchResult, run_match


def local_path(uri: str) -> Path:
    parsed = urlparse(uri)
    if parsed.scheme != "file" or parsed.netloc:
        raise ValueError("Coworld artifacts must use local file URIs")
    return Path(unquote(parsed.path))


class Config(BaseModel):
    model_config = ConfigDict(extra="forbid")
    year: Literal["bc25", "bc26"]
    map: str = Field(pattern=r"^[A-Za-z0-9_]+$")
    num_agents: Literal[2] = 2
    tokens: list[str] = Field(min_length=2, max_length=2)


class ArchivePolicy(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)
    schema_id: Literal["battlecode-archive/1"] = Field(alias="schema")
    archive: str


class Seat(BaseModel):
    slot: Literal[0, 1]
    file_uri: str
    content_hash: str
    size_bytes: int
    log_uri: str


class Seats(BaseModel):
    schema_id: Literal["coworld-player-seats/1"] = Field(alias="schema")
    seats: list[Seat] = Field(min_length=2, max_length=2)


class Replay(BaseModel):
    schema_id: Literal["battlecode-official-replay/1"] = Field(alias="schema")
    year: Literal["bc25", "bc26"]
    map: str
    players: tuple[str, str]
    result: MatchResult
    frames: list[Frame]


async def serve() -> None:
    replay_uri = os.environ.get("COGAME_LOAD_REPLAY_URI")
    replay: Replay | None = None
    if replay_uri:
        replay = Replay.model_validate_json(local_path(replay_uri).read_text())

    async def health(request: web.Request) -> web.Response:
        return web.Response(text="ok\n")

    async def viewer(request: web.Request) -> web.StreamResponse:
        return web.FileResponse(Path(__file__).with_name("viewer.html"))

    async def replay_data(request: web.Request) -> web.StreamResponse:
        if web.WebSocketResponse().can_prepare(request).ok:
            return await global_view(request)
        if replay is None:
            return web.json_response({"phase": "running"}, status=425)
        return web.Response(text=replay.model_dump_json(by_alias=True), content_type="application/json")

    async def global_view(request: web.Request) -> web.StreamResponse:
        socket = web.WebSocketResponse(autoping=True)
        if not socket.can_prepare(request).ok:
            return web.json_response({"runtime": "official-archive", "phase": "complete" if replay else "running"})
        await socket.prepare(request)
        tick = 0
        read = asyncio.create_task(socket.receive())
        try:
            while not socket.closed:
                if read.done():
                    message = read.result()
                    if message.type in (web.WSMsgType.CLOSE, web.WSMsgType.CLOSED, web.WSMsgType.ERROR):
                        break
                    read = asyncio.create_task(socket.receive())
                if replay is None:
                    await socket.send_json({"runtime": "official-archive", "phase": "running", "tick": tick})
                else:
                    await socket.send_str(replay.frames[tick % len(replay.frames)].model_dump_json())
                tick += 1
                # The concurrent receive drives aiohttp's RFC 6455 Ping/Pong.
                await asyncio.sleep(0.08)
        finally:
            read.cancel()
        return socket

    app = web.Application()
    app.router.add_get("/healthz", health)
    app.router.add_get("/global", global_view)
    app.router.add_get("/replay", replay_data)
    app.router.add_get("/client/global", viewer)
    app.router.add_get("/client/replay", viewer)
    app.router.add_get("/client/player", viewer)
    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(
        runner, os.environ.get("COGAME_HOST", "0.0.0.0"), int(os.environ.get("COGAME_PORT", "8080"))
    ).start()
    try:
        if not replay_uri:
            config = Config.model_validate_json(local_path(os.environ["COGAME_CONFIG_URI"]).read_text())
            seats = Seats.model_validate_json(local_path(os.environ["COGAME_PLAYER_SEATS_URI"]).read_text())
            ordered = sorted(seats.seats, key=lambda seat: seat.slot)
            if [seat.slot for seat in ordered] != [0, 1]:
                raise ValueError("Expected exactly slots 0 and 1")
            players = []
            for seat in ordered:
                log = local_path(seat.log_uri)
                log.parent.mkdir(parents=True, exist_ok=True)
                log.write_text("")
                raw = local_path(seat.file_uri).read_bytes()
                if len(raw) > 1024 or len(raw) != seat.size_bytes:
                    raise ValueError("Archive selector length mismatch")
                if "sha256:" + hashlib.sha256(raw).hexdigest() != seat.content_hash:
                    raise ValueError("Archive selector hash mismatch")
                policy = ArchivePolicy.model_validate_json(raw)
                player = next(p for p in CATALOG.players if p.id == policy.archive and p.redistributable)
                if player.year != config.year:
                    raise ValueError("Archive belongs to another Battlecode year")
                players.append(player)
            build = Path(os.environ.get("BATTLECODE_OFFICIAL_BUILD", "/opt/official"))
            output = Path(os.environ.get("BATTLECODE_OFFICIAL_OUTPUT", "/tmp/official-match"))
            jdk = Path(os.environ.get("JAVA_HOME", "/opt/java/openjdk")) / "bin"
            result = await asyncio.to_thread(run_match, players[0], players[1], build, output, jdk, config.map, 600)
            frames = [Frame.model_validate_json(line) for line in (output / "frames.jsonl").read_text().splitlines()]
            replay = Replay(
                schema="battlecode-official-replay/1",
                year=config.year,
                map=config.map,
                players=(players[0].id, players[1].id),
                result=result,
                frames=frames,
            )
            for seat in ordered:
                shutil.copyfile(output / f"seat-{seat.slot}.log", local_path(seat.log_uri))
            # Public replay excludes private bot logs; only observer state is published.
            local_path(os.environ["COGAME_SAVE_REPLAY_URI"]).write_text(replay.model_dump_json(by_alias=True))
            scores = [1, 0] if result.winner == "A" else [0, 1]
            local_path(os.environ["COGAME_RESULTS_URI"]).write_text(
                json.dumps({"scores": scores, **result.model_dump()})
            )
        await asyncio.Event().wait()
    finally:
        await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(serve())
