"""Explicit team-only provisioning for an independently owned contender roster.

Run in the pinned coworld environment. Raises (never lowers) the release
account's league allowance to hold every existing and requested player.
"""
import argparse
import json
from pathlib import Path

from softmax import auth
from softmax._http import observatory_client

from resolve_policy_players import resolve_players


def required_allowance(rows, players, override, default):
    existing_names = {p["name"] for p in players}
    missing = {r["player_name"] for r in rows if "player_name" in r} - existing_names
    return max(override or default, len(players) + len(missing))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policies", type=Path)
    args = parser.parse_args()
    rows = json.loads(args.policies.read_text())
    server = auth.DEFAULT_API_SERVER
    token = auth.load_user_token(server=server)
    if not token:
        raise SystemExit("A user credential is required")
    with observatory_client(server=server, token=token) as client:
        client.headers["X-Use-Elevated-Privileges"] = "true"

        def request(method, path, **kwargs):
            response = client.request(method, path, **kwargs)
            if not response.is_success:
                raise RuntimeError(f"{method} {path}: HTTP {response.status_code}: {response.text[:1500]}")
            return response.json()

        principal = request("GET", "/whoami")
        if not principal.get("is_softmax_team_member"):
            raise SystemExit("The release credential does not have elevated team privileges")
        user_id = principal.get("owner_user_id") or principal.get("subject_id")
        if not user_id:
            raise SystemExit("Could not identify the release account")
        players = request("GET", "/players")
        # Validate all names/identities before any mutation, using placeholders
        # for missing players. resolve_players performs the same checks again
        # on the actual API responses.
        resolve_players(rows, players, lambda name: {"name": name, "id": f"ply_pending_{name}"})
        detail = request("GET", f"/admin/users/{user_id}")["user"]
        override = detail["max_players_per_league_override"]
        default = detail["default_max_players_per_league"]
        needed = required_allowance(rows, players, override, default)
        if needed > (override or default):
            request("PATCH", f"/admin/users/{user_id}/player-limit",
                    json={"max_players_per_league_override": needed})
        verified = request("GET", f"/admin/users/{user_id}")["user"]
        if (verified["max_players_per_league_override"] or default) < needed:
            raise RuntimeError("Player allowance readback did not match")
        print(f"Release account {user_id}: league player allowance {override or default} -> {needed}")
        resolved = resolve_players(rows, players, lambda name: request("POST", "/players", json={"name": name}))
        current_ids = {p["id"] for p in request("GET", "/players")}
        if any(r["player"] not in current_ids for r in resolved if r.get("player")):
            raise RuntimeError("Created player missing from owned-player readback")
        args.policies.write_text(json.dumps(resolved, indent=2) + "\n")
        for original, row in zip(rows, resolved):
            print(f"{original.get('player_name', row['name'])}: {row.get('player', 'default')}")


if __name__ == "__main__":
    main()
