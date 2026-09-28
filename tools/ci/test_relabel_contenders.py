import unittest

from relabel_contenders import OwnedPlayer, Policy, RegisteredPlayer, plan_renames


class RelabelTests(unittest.TestCase):
    def setUp(self):
        self.policy = Policy(name="bot", player_name="BC25 Team (strategy adaptation)")
        self.receipt = RegisteredPlayer(name="BC25 Team (Nim)", player_id="ply_original", policy="bot:v1")
        self.player = OwnedPlayer(id="ply_original", name=self.receipt.name)

    def test_preserves_identity_and_is_idempotent(self):
        renames = plan_renames([self.policy], [self.receipt], [self.player])
        self.assertEqual([(r.player_id, r.name) for r in renames], [(self.player.id, self.policy.player_name)])
        self.player.name = self.policy.player_name
        self.assertEqual(plan_renames([self.policy], [self.receipt], [self.player]), [])

    def test_refuses_nonowned_disabled_changed_or_colliding_players(self):
        with self.assertRaises(KeyError):
            plan_renames([self.policy], [self.receipt], [])
        for players in (
            [self.player.model_copy(update={"disabled_at": "2026-09-28"})],
            [self.player.model_copy(update={"name": "independently renamed"})],
            [self.player, OwnedPlayer(id="ply_other", name=self.policy.player_name)],
        ):
            with self.subTest(players=players), self.assertRaises(ValueError):
                plan_renames([self.policy], [self.receipt], players)

    def test_other_release_rows_do_not_rename_contenders(self):
        self.assertEqual(plan_renames([Policy(name="unrelated")], [self.receipt], []), [])


if __name__ == "__main__":
    unittest.main()
