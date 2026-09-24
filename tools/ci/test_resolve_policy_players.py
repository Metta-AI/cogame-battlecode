import unittest

from resolve_policy_players import resolve_players
from prepare_contender_players import required_allowance


class PlayerIdentityTests(unittest.TestCase):
    def test_four_distinct_ids_and_idempotent_release(self):
        rows = [{"name": f"bot-{i}", "player_name": f"entrant-{i}"} for i in range(4)]
        created = []

        def create(name):
            player = {"id": f"ply_{len(created)}", "name": name}
            created.append(player)
            return player

        first = resolve_players(rows, [], create)
        second = resolve_players(rows, created, lambda _: self.fail("created a duplicate"))
        self.assertEqual(first, second)
        self.assertEqual(len({r["player"] for r in first}), 4)
        self.assertTrue(all("player_name" in r for r in rows))

    def test_allowance_preserves_existing_players_and_larger_overrides(self):
        rows = [{"player_name": f"entrant-{i}"} for i in range(4)]
        players = [{"name": "existing-a"}, {"name": "existing-b"}]
        self.assertEqual(required_allowance(rows, players, None, 2), 6)
        self.assertEqual(required_allowance(rows, players, 20, 2), 20)
        self.assertEqual(required_allowance(rows, players + [{"name": r["player_name"]} for r in rows], 6, 2), 6)

    def test_legacy_rows_unchanged(self):
        rows = [{"name": "default"}, {"name": "other", "player": "ply_existing"}]
        self.assertEqual(resolve_players(rows, [], lambda _: self.fail()), rows)

    def test_ambiguous_disabled_and_duplicate_names_fail_before_creation(self):
        row = {"name": "bot", "player_name": "entrant"}
        player = {"id": "ply_existing", "name": "entrant"}
        for rows, players in [
            ([row], [player, player]),
            ([row], [{**player, "disabled_at": "2026-01-01"}]),
            ([row, row], []),
            ([{**row, "player": "ply_existing"}], []),
            ([{**row, "player_name": ""}], []),
        ]:
            with self.subTest(rows=rows, players=players), self.assertRaises(ValueError):
                resolve_players(rows, players, lambda _: self.fail("unexpected creation"))

    def test_wrong_create_response_rejected(self):
        with self.assertRaises(ValueError):
            resolve_players([{"player_name": "expected"}], [],
                            lambda _: {"name": "wrong", "id": "ply_1"})


if __name__ == "__main__":
    unittest.main()
