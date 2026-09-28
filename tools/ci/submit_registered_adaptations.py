"""Promote released adaptations while preserving the existing league player roster."""

import argparse
import time
from pathlib import Path
from uuid import UUID

from coworld.api_client import CoworldApiClient, PolicyVersionPublic, PolicyVersionRow
from pydantic import BaseModel, TypeAdapter
from softmax._http import observatory_client
from softmax.auth import DEFAULT_API_SERVER, load_user_token

from relabel_contenders import OwnedPlayer, Receipt


class LeagueReceipt(Receipt):
    league_id: str


class UploadedPolicy(BaseModel):
    name: str
    version: str
    player_id: str


class Champion(BaseModel):
    player: OwnedPlayer
    policy_version: PolicyVersionPublic


class Submission(BaseModel):
    league_id: str
    player_id: str
    policy_version_id: UUID
    policy: str
    submission_ids: list[str] = []


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release_directory", type=Path)
    args = parser.parse_args()
    uploaded = TypeAdapter(list[UploadedPolicy]).validate_json((args.release_directory / "policies.json").read_text())
    receipts = [
        LeagueReceipt.model_validate_json(Path(f"docs/bc{year}-contender-registration.json").read_text())
        for year in (25, 26)
    ]
    registered = {
        p.policy.rsplit(":", 1)[0]: (receipt.league_id, p.player_id) for receipt in receipts for p in receipt.players
    }
    token = load_user_token(server=DEFAULT_API_SERVER)
    with observatory_client(server=DEFAULT_API_SERVER, token=token) as http:
        response = http.get("/players")
        response.raise_for_status()
        owned = {p.id: p for p in TypeAdapter(list[OwnedPlayer]).validate_json(response.content)}
    adapter = TypeAdapter(list[Champion])
    baseline: dict[str, dict[str, Champion]] = {}
    plan = []
    with CoworldApiClient(server_url=DEFAULT_API_SERVER, token=token) as client:
        for league_id in {registered[p.name][0] for p in uploaded}:
            locks = client.get_league_locks(league_id)
            if locks.submissions_locked:
                raise ValueError(f"League submissions are locked: {league_id}")
            page = client.list_memberships(league_id=league_id, active_only=True, champions_only=True, limit=100)
            if page.next_cursor is not None:
                raise ValueError("Adaptation roster exceeds the complete preflight page")
            baseline[league_id] = {m.player.id: m for m in adapter.validate_python(page.entries, from_attributes=True)}
        # Preflight every identity, existing champion, and exact uploaded version before writing.
        for policy in uploaded:
            league_id, player_id = registered[policy.name]
            if policy.player_id != player_id or owned[player_id].disabled_at is not None:
                raise ValueError(f"Uploaded policy identity differs from the registered active owner: {policy.name}")
            current = baseline[league_id][player_id].policy_version
            version = PolicyVersionRow.model_validate(
                client.lookup_policy_version(name=policy.name, version=int(policy.version.removeprefix("v")))
            )
            if current.policy.name != policy.name or current.version > version.version:
                raise ValueError(f"Existing champion was independently replaced: {player_id}")
            if current.id != version.id:
                plan.append(
                    Submission(
                        league_id=league_id,
                        player_id=player_id,
                        policy_version_id=version.id,
                        policy=f"{version.name}:v{version.version}",
                    )
                )
        ledger = args.release_directory / "adaptation-submissions.json"
        ledger.write_text(TypeAdapter(list[Submission]).dump_json(plan, indent=2).decode() + "\n")
        for item in plan:
            existing = client.list_submissions(
                league_id=item.league_id, player_id=item.player_id, policy_version_id=item.policy_version_id, limit=100
            )
            if existing.next_cursor is not None or any(s.status == "failed" for s in existing.entries):
                raise ValueError(f"Submission history needs inspection: {item.policy}")
            if existing.entries:
                item.submission_ids = [s.id for s in existing.entries]
            else:
                submission = client.submit_to_league(item.league_id, item.policy_version_id, player_id=item.player_id)
                item.submission_ids = [submission.id]
            ledger.write_text(TypeAdapter(list[Submission]).dump_json(plan, indent=2).decode() + "\n")
            print(f"{item.player_id}: submitted {item.policy}", flush=True)
        deadline = time.monotonic() + 900
        while True:
            pending = []
            for league_id, before in baseline.items():
                page = client.list_memberships(league_id=league_id, active_only=True, champions_only=True, limit=100)
                if page.next_cursor is not None:
                    raise ValueError("Readback roster exceeds the complete page")
                after = {m.player.id: m for m in adapter.validate_python(page.entries, from_attributes=True)}
                if set(before) != set(after):
                    raise RuntimeError(f"League player roster changed: {league_id}")
                selected = {p.player_id: p.policy_version_id for p in plan if p.league_id == league_id}
                for player_id, champion in after.items():
                    if player_id in selected:
                        if champion.policy_version.id != selected[player_id]:
                            pending.append(player_id)
                    elif champion.policy_version.id != before[player_id].policy_version.id:
                        raise RuntimeError(f"An unrelated champion changed: {player_id}")
            if not pending:
                print(
                    "All released adaptations are active; both league player rosters and unrelated champions are preserved."
                )
                break
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Adaptation placement did not complete: {pending}")
            print(f"Waiting for {len(pending)} adaptation placements", flush=True)
            time.sleep(15)


if __name__ == "__main__":
    main()
