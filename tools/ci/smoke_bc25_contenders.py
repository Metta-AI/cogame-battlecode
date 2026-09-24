"""Exercise each released contender through the real container registration path."""
import json
import shlex
import subprocess
import sys
from pathlib import Path


def main():
    receipt_dir, package = Path(sys.argv[1]), sys.argv[2]
    rows = json.loads((receipt_dir / "policies_input.json").read_text())
    contenders = {"confused", "just-woke-up", "om-nom", "spaark-2025"}
    for row in rows:
        selector = row.get("env", {}).get("PLAYER_SCRIPTED")
        if selector not in contenders:
            continue
        image = row["image"]
        architecture = subprocess.check_output(
            ["docker", "image", "inspect", image, "--format", "{{.Architecture}}"], text=True
        ).strip()
        if architecture != "amd64":
            raise RuntimeError(f"{image}: expected amd64, got {architecture}")
        output = receipt_dir / ("smoke-" + selector)
        argv = shlex.split(row["run"]) if isinstance(row["run"], str) else row["run"]
        command = ["uvx", "--from", package, "coworld", "run-episode",
                   "dist/coworld_manifest.json", image, "--variant", "bc25",
                   "--timeout-seconds", "600", "--output-dir", str(output)]
        for arg in argv:
            command.extend(["--run", arg])
        command.extend(["--secret-env", "PLAYER_SCRIPTED=" + selector,
                        "--secret-env", "PLAYER_POLICY_LABEL=" + row["env"]["PLAYER_POLICY_LABEL"]])
        subprocess.run(command, check=True)
        replay = json.loads((output / "replay").read_text())
        if replay.get("year") != "bc25" or len(replay.get("seats", [])) != 2:
            raise RuntimeError(f"{selector}: wrong year or missing seat registrations")
        if any(s.get("chassis") != selector for s in replay["seats"]):
            raise RuntimeError(f"{selector}: controller registration fell back")
        result = replay["result"]
        if result.get("reason") != "complete" or any(result.get("fallbacks", [1, 1])):
            raise RuntimeError(f"{selector}: episode incomplete or used fallback")
        if not result.get("games") or any(g["rounds_played"] <= 1 for g in result["games"]):
            raise RuntimeError(f"{selector}: episode never played")
        print(f"{selector}: amd64 image, both seats registered, complete bc25 episode", flush=True)


if __name__ == "__main__":
    main()
