#!/usr/bin/env python3
"""Replay `coworld certify`'s smoke-episode probes against a running game.

The certifier does not just run an episode: before and during it, it probes
the game container's HTTP and WebSocket surface, and ANY of those probes
failing fails the whole release with `game_contract_violation`. Finding them
one release dispatch at a time cost four (0.1.0 through 0.1.3), so they live
here instead.

This is lifted from coworld 0.1.43's `coworld/runner/runner.py` — the version
`.github/workflows/coworld-release.yml` pins in COWORLD_PKG — in the same
ORDER, with the same library, the same payloads and the same timeouts. A pass
here means the contract half of certification passes.

    # start the game with the certification fixture, then:
    python3 tools/ci/cert_probe.py 8080 /tmp/results.json coworld_manifest_template.json

The probes, in the runner's order:

  1. GET  /healthz                                  200   (_wait_for_health)
  2. GET  /client/player?slot=0&token=<good>         2xx   (_require_http_ok)
  3. WS   /player?slot=0&token=bad                   REFUSED
                                                 (_require_bad_player_rejected)
  4. GET  /client/global                             2xx   (_require_http_ok)
  5. WS   /global   Ping -> Pong ECHOING the payload, then a non-empty message
                              (_require_global_message with require_pong=True)
  6. the game exits 0                              (_wait_for_game_exit)
  7. results.json validates against the manifest's results_schema
                                                   (_validate_results_file)
"""
import asyncio
import json
import sys

import httpx
import jsonschema
import websockets
from websockets.exceptions import ConnectionClosed, InvalidHandshake, InvalidStatus

PORT = int(sys.argv[1])
RESULTS = sys.argv[2] if len(sys.argv) > 2 else None
MANIFEST = sys.argv[3] if len(sys.argv) > 3 else None
GOOD = "token-0"

failures = []


def ok(name):
    print(f"  PASS  {name}")


def bad(name, detail):
    print(f"  FAIL  {name}: {detail}")
    failures.append(name)


def require_http_ok(name, url, allow_redirect=False):
    try:
        r = httpx.get(url, timeout=5.0)
        if allow_redirect and 300 <= r.status_code < 400:
            return ok(name)
        r.raise_for_status()
        ok(f"{name} -> {r.status_code}")
    except httpx.HTTPError as exc:
        bad(name, exc)


async def require_bad_player_rejected(url):
    rejected = False
    try:
        async with websockets.connect(url, open_timeout=5) as ws:
            try:
                await asyncio.wait_for(ws.recv(), timeout=2.0)
            except ConnectionClosed:
                rejected = True
            except asyncio.TimeoutError:
                pass
    except InvalidStatus as exc:
        rejected = exc.response.status_code in {401, 403}
        if not rejected:
            return bad("bad player token", f"unexpected status {exc.response.status_code}")
    except (ConnectionClosed, InvalidHandshake):
        rejected = True
    except OSError as exc:
        return bad("bad player token", exc)
    if rejected:
        ok("bad player token is rejected")
    else:
        bad("bad player token", "was ACCEPTED")


async def require_global_message(url, require_pong=True):
    try:
        backpressure = {"max_queue": None} if require_pong else {}
        async with websockets.connect(url, open_timeout=5, max_size=None, **backpressure) as ws:
            if require_pong:
                try:
                    waiter = await ws.ping(b"coworld-certification-ping")
                    await asyncio.wait_for(waiter, timeout=2.0)
                    ok("global socket answers a Ping with a Pong")
                except (OSError, asyncio.TimeoutError, ConnectionClosed) as exc:
                    return bad("global Ping -> Pong", exc)
            message = await asyncio.wait_for(ws.recv(), timeout=10.0)
    except (OSError, asyncio.TimeoutError, ConnectionClosed, InvalidHandshake, InvalidStatus) as exc:
        return bad("global message", exc)
    if not message:
        return bad("global message", "empty")
    ok(f"global socket produced a {len(message)}B message")


print("smoke-episode probes, in the runner's order:")
require_http_ok("GET /healthz", f"http://127.0.0.1:{PORT}/healthz")
require_http_ok(
    "GET /client/player?slot=0&token=<good>",
    f"http://127.0.0.1:{PORT}/client/player?slot=0&token={GOOD}",
)
asyncio.run(require_bad_player_rejected(f"ws://127.0.0.1:{PORT}/player?slot=0&token=bad"))
require_http_ok("GET /client/global", f"http://127.0.0.1:{PORT}/client/global")
asyncio.run(require_global_message(f"ws://127.0.0.1:{PORT}/global", require_pong=True))

if RESULTS and MANIFEST:
    schema = json.load(open(MANIFEST))["game"]["results_schema"]
    try:
        results = json.load(open(RESULTS))
    except Exception as exc:
        bad("results.json parses", exc)
    else:
        try:
            jsonschema.validate(results, schema)
            ok("results.json validates against the manifest results_schema")
        except jsonschema.ValidationError as exc:
            bad("results_schema validation", exc.message)

print("FAILURES:", failures if failures else "none")
sys.exit(1 if failures else 0)
