"""Resolve explicitly named policy owners before uploading leaderboard entrants.

Player identity, not policy name, is the leaderboard key. Reuse an exact active
owned name on subsequent releases, and fail on ambiguity rather than silently
uploading a contender as the token owner. No league settings are changed here.
"""

import argparse
import json
import subprocess
from pathlib import Path


def resolve_players(rows, players, create):
    names = [r["player_name"] for r in rows if "player_name" in r]
    if any(not isinstance(n, str) or not n.strip() for n in names):
        raise ValueError("player_name must be a nonempty string")
    if len(names) != len(set(names)):
        raise ValueError("named leaderboard entrants must have distinct player names")
    resolved = []
    # Validate the entire roster before creating any missing identity.
    for row in rows:
        if "player_name" not in row:
            continue
        if row.get("player"):
            raise ValueError("use player or player_name, not both")
        matches = [p for p in players if p["name"] == row["player_name"]]
        if len(matches) > 1 or any(p.get("disabled_at") for p in matches):
            raise ValueError(f"ambiguous or disabled player: {row['player_name']}")
    for row in rows:
        row = dict(row)
        name = row.pop("player_name", None)
        if name is not None:
            matches = [p for p in players if p["name"] == name]
            player = matches[0] if matches else create(name)
            if player.get("name") != name or not player.get("id", "").startswith("ply_"):
                raise ValueError(f"unexpected player response for {name}")
            row["player"] = player["id"]
        resolved.append(row)
    ids = [r["player"] for r in resolved if r.get("player")]
    named_ids = [r["player"] for original, r in zip(rows, resolved) if "player_name" in original]
    if any(ids.count(pid) > 1 for pid in named_ids):
        raise ValueError("leaderboard entrants resolved to the same player")
    return resolved


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policies", type=Path)
    parser.add_argument("--package", required=True)
    args = parser.parse_args()
    rows = json.loads(args.policies.read_text())
    if not any("player_name" in row for row in rows):
        return

    def command(*argv):
        completed = subprocess.run(
            ["uvx", "--from", args.package, "coworld", "player", *argv, "--json"],
            check=True, capture_output=True, text=True,
        )
        return json.loads(completed.stdout)

    resolved = resolve_players(rows, command("list"), lambda name: command("create", name))
    args.policies.write_text(json.dumps(resolved, indent=2) + "\n")
    for original, row in zip(rows, resolved):
        if "player_name" in original:
            print(f"{row['name']}: {original['player_name']} ({row['player']})")


if __name__ == "__main__":
    main()
