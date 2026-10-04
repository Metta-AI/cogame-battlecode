"""Rename registered adaptations without creating replacement leaderboard identities."""

import argparse
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter

from softmax._http import observatory_client
from softmax.auth import DEFAULT_API_SERVER, load_user_token


class RegisteredPlayer(BaseModel):
    name: str
    player_id: str
    policy: str


class Receipt(BaseModel):
    players: list[RegisteredPlayer]


class OwnedPlayer(BaseModel):
    id: str
    name: str
    disabled_at: str | None = None


class Policy(BaseModel):
    model_config = ConfigDict(extra="allow")
    name: str
    player_name: str | None = None


class Rename(BaseModel):
    player_id: str
    name: str = Field(min_length=1, max_length=255)


def plan_renames(policies: list[Policy], registered: list[RegisteredPlayer], owned: list[OwnedPlayer]) -> list[Rename]:
    by_policy = {player.policy.rsplit(":", 1)[0]: player for player in registered}
    by_id = {player.id: player for player in owned}
    planned = []
    for policy in policies:
        if policy.name not in by_policy:
            continue
        historical = by_policy[policy.name]
        player = by_id[historical.player_id]
        if player.disabled_at is not None:
            raise ValueError(f"Registered contender is disabled: {player.id}")
        if policy.player_name is None:
            raise ValueError(f"Registered contender needs player_name: {policy.name}")
        if player.name not in (historical.name, policy.player_name):
            raise ValueError(f"Registered contender was renamed independently: {player.id}")
        if any(other.id != player.id and other.name == policy.player_name for other in owned):
            raise ValueError(f"Adaptation name is already owned by another player: {policy.player_name}")
        if player.name != policy.player_name:
            planned.append(Rename(player_id=player.id, name=policy.player_name))
    return planned


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policies", type=Path)
    args = parser.parse_args()
    policies = TypeAdapter(list[Policy]).validate_json(args.policies.read_text())
    registered = []
    for year in (25, 26):
        receipt = Receipt.model_validate_json(Path(f"docs/bc{year}-contender-registration.json").read_text())
        registered.extend(receipt.players)
    token = load_user_token(server=DEFAULT_API_SERVER)
    if token is None:
        raise RuntimeError("The release account must be logged in")
    with observatory_client(server=DEFAULT_API_SERVER, token=token) as client:
        response = client.get("/players")
        response.raise_for_status()
        owned = TypeAdapter(list[OwnedPlayer]).validate_json(response.content)
        # Validate the entire selected roster and ownership before the first write.
        for rename in plan_renames(policies, registered, owned):
            response = client.patch(f"/players/{rename.player_id}", json={"name": rename.name})
            response.raise_for_status()
            updated = OwnedPlayer.model_validate_json(response.content)
            if updated.id != rename.player_id or updated.name != rename.name:
                raise RuntimeError(f"Rename readback disagrees: {rename.player_id}")
            print(f"{updated.id}: {updated.name}")
        response = client.get("/players")
        response.raise_for_status()
        if plan_renames(policies, registered, TypeAdapter(list[OwnedPlayer]).validate_json(response.content)):
            raise RuntimeError("Player names did not persist")


if __name__ == "__main__":
    main()
