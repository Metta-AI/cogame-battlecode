import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import UUID

from coworld.api_client import PolicyVersionRow

import submit_registered_adaptations as submit


class SubmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "docs").mkdir()
        for year in (25, 26):
            (self.root / f"docs/bc{year}-contender-registration.json").write_text(
                json.dumps(
                    {
                        "league_id": f"league_{year}",
                        "players": [{"name": "Team", "player_id": f"ply_{year}", "policy": f"bot{year}:v1"}],
                    }
                )
            )
        (self.root / "policies.json").write_text(
            json.dumps([{"name": "bot25", "version": "v2", "player_id": "ply_25"}])
        )
        self.old = {
            "player": {"id": "ply_25", "name": "Team"},
            "policy_version": {
                "id": str(UUID(int=1)),
                "policy": {"id": str(UUID(int=3)), "name": "bot25"},
                "version": 1,
            },
        }
        self.new = {
            "player": self.old["player"],
            "policy_version": {**self.old["policy_version"], "id": str(UUID(int=2)), "version": 2},
        }
        self.client = MagicMock()
        self.client.__enter__.return_value = self.client
        self.client.get_league_locks.return_value = SimpleNamespace(submissions_locked=False)
        self.client.list_memberships.side_effect = [
            SimpleNamespace(entries=[self.old], next_cursor=None),
            SimpleNamespace(entries=[self.new], next_cursor=None),
        ]
        self.client.lookup_policy_version.return_value = PolicyVersionRow(id=UUID(int=2), name="bot25", version=2)
        self.client.list_submissions.return_value = SimpleNamespace(entries=[], next_cursor=None)
        self.client.submit_to_league.return_value = SimpleNamespace(id="sub_new")
        self.http = MagicMock()
        self.http.__enter__.return_value = self.http
        self.http.get.return_value.content = json.dumps([self.old["player"]]).encode()

    def run_main(self):
        original = Path.cwd()
        os.chdir(self.root)
        try:
            with (
                patch.object(submit, "CoworldApiClient", return_value=self.client),
                patch.object(submit, "observatory_client", return_value=self.http),
                patch.object(submit, "load_user_token", return_value="test-token"),
                patch("sys.argv", ["submit", str(self.root)]),
            ):
                submit.main()
        finally:
            os.chdir(original)

    def test_promotes_exact_version_under_registered_identity_and_records_ledger(self):
        self.run_main()
        self.client.submit_to_league.assert_called_once_with("league_25", UUID(int=2), player_id="ply_25")
        ledger = json.loads((self.root / "adaptation-submissions.json").read_text())
        self.assertEqual(ledger[0]["submission_ids"], ["sub_new"])

    def test_refuses_nonowned_or_independently_replaced_champion_before_writing(self):
        self.http.get.return_value.content = b"[]"
        with self.assertRaises(KeyError):
            self.run_main()
        self.client.submit_to_league.assert_not_called()
        self.http.get.return_value.content = json.dumps([self.old["player"]]).encode()
        self.old["policy_version"]["policy"]["name"] = "independent"
        self.client.list_memberships.side_effect = [SimpleNamespace(entries=[self.old], next_cursor=None)]
        with self.assertRaises(ValueError):
            self.run_main()
        self.client.submit_to_league.assert_not_called()

    def test_already_active_version_is_idempotent(self):
        self.client.list_memberships.side_effect = [
            SimpleNamespace(entries=[self.new], next_cursor=None),
            SimpleNamespace(entries=[self.new], next_cursor=None),
        ]
        self.run_main()
        self.client.submit_to_league.assert_not_called()

    def test_existing_submission_is_not_duplicated(self):
        self.client.list_submissions.return_value = SimpleNamespace(
            entries=[SimpleNamespace(id="sub_existing", status="placed")], next_cursor=None
        )
        self.run_main()
        self.client.submit_to_league.assert_not_called()
        ledger = json.loads((self.root / "adaptation-submissions.json").read_text())
        self.assertEqual(ledger[0]["submission_ids"], ["sub_existing"])


if __name__ == "__main__":
    unittest.main()
