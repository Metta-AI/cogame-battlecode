"""Run real game/player processes and verify terminal missing-seat attribution."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    game, player = map(str, map(Path.resolve, map(Path, sys.argv[1:])))
    for seat_count in (1, 2):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            failure = output / "failure.json"
            results = output / "results.json"
            replay = output / "replay.json"
            config = {"year": "bc26", "pool": "small", "seed": 1,
                      "num_agents": 2, "gamesPerMatch": 1, "maxRounds": 20,
                      "connectTimeoutMs": 3000, "doctrineBudgetMs": 1000,
                      "matchBudgetSeconds": 10, "perGameBudgetSeconds": 5}
            environment = {**os.environ, "COGAME_PLAYER_FAILURE_URI": failure.as_uri(),
                           "BATTLECODE_SHUTDOWN_GRACE_MS": "500"}
            processes = []
            with (output / "game.log").open("w+") as log:
                server = subprocess.Popen(
                    [game, "--port:18971", "--config:" + json.dumps(config),
                     "--results:" + str(results), "--save-replay:" + str(replay)],
                    env=environment, stdout=log, stderr=subprocess.STDOUT)
                try:
                    for slot in range(seat_count):
                        processes.append(subprocess.Popen(
                            [player], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT,
                            env={**os.environ, "PLAYER_SCRIPTED": "awu",
                                 "COWORLD_PLAYER_WS_URL": f"ws://127.0.0.1:18971/player?slot={slot}"}))
                    status = server.wait(timeout=30)
                    log.flush()
                    assert status == 0, f"game exited {status}:\n{(output / 'game.log').read_text()}"
                    if seat_count == 1:
                        assert json.loads(failure.read_text()) == {
                            "failed_policy_index": 1, "message": "seat never registered"}
                        assert not results.exists() and not replay.exists()
                    else:
                        assert not failure.exists()
                        result = json.loads(results.read_text())
                        assert len(result["scores"]) == 2
                        recorded = json.loads(replay.read_text())
                        assert recorded["result"]["reason"] == "complete"
                        assert recorded["result"]["fallbacks"] == [0, 0]
                    print(f"{seat_count} registered seats: passed")
                finally:
                    for process in [server, *processes]:
                        if process.poll() is None:
                            process.terminate()
                        process.wait(timeout=10)


if __name__ == "__main__":
    main()
