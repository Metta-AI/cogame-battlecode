# One Coworld, one league per year

All ten year variants belong to the `battlecode` Coworld. Each year has an
independent league key, default variant, entrants, and standings. Never rotate a
single ladder across years: their rules, doctrines, and scores differ.

Generate the proposed setup from the current manifest and engine registry:

```sh
nim c --hints:off --path:src --out:/tmp/battlecode-league-plan tools/league_plan.nim
/tmp/battlecode-league-plan > /tmp/battlecode-year-leagues.json
```

Run from the repository root. The program only prints JSON; it has no credentials,
network calls, deployment command, or automatic activation. It rejects missing,
duplicate, unknown, or mismatched year variants.

Each entry contains two API payloads:

- `seed_request`: for `POST /v2/coworld-league-seeds`. Every entry names Coworld
  `battlecode`; its `league_key` and `default_variant_id` both equal the year ID
  (`bc16`, `bc17`, or `bc19` through `bc26`). It explicitly selects the platform
  commissioner. The enabled seed can materialize a league; it does not configure
  an active ladder.
- `settings_request`: for `POST /v2/leagues/{league_id}/settings` after resolving
  that year's actual league ID. Its ladder is paused and has no division IDs.
  `scheduler.variant_rotation` contains exactly the same year ID, so scheduling
  cannot select another year's manifest variant. This is a fresh-league scaffold,
  not an update payload for an existing league.

These payloads follow Metta's `V2CreateCoworldLeagueSeedRequest` and
`LeagueSettings` schemas. The manifest contains no commissioner image; use the
platform scheduler rather than inventing a container commissioner.

## Reviewed activation sequence

1. Inspect existing Battlecode league seeds and bindings. Reuse an existing
   matching year league; do not create duplicate leagues or rebind existing
   entrants and standings implicitly. Do not pause or reconfigure a matching
   live league as a side effect of setup.
2. Review the generated seed payload for each missing year before applying it.
   Resolve the returned seed's materialized league ID; a seed alone does not
   prove the league is ready.
3. Declare a competition division through the platform division API. Populate
   `ladder.divisions` with that year's returned division ID and name. Choose the
   cadence, ranking settings, and participation budget with the league owner.
4. For a new league, apply the paused settings. Updating an existing league
   requires reading its current settings first and preserving unrelated fields:
   the settings POST replaces the full document. Review any changes to a live
   league separately. Read back both the default variant and singleton
   rotation. Do not override `game_config.year` in separate runtime settings.
5. Verify the intended year with its bundled players, completed results and
   replay. Enable that ladder only after the owner reviews this proof.

The generated payloads are for reviewed setup, not a migration of live leagues.
They do not upload a Coworld, create leagues, activate scheduling, move entrants,
or rewrite existing standings.

## Player compatibility

For four independent 2025 contender entries, see
[2025 contender players](PLAYERS-BC25.md). Each requires its own player identity,
policy upload under that identity, and champion membership in `bc25`; four
policy names uploaded under one identity do not produce four standings rows.

These remain doctrine-sheet leagues running the Nim rule ports. Their policies
submit the year-specific JSON strategy sheet. In particular, the `awu` baseline
is a distilled strategy; it does not execute the original Java winning bot.
Original Battlecode submissions require a separately implemented official-engine
runtime and artifact contract. Creating a 2026 league does not provide that runtime.

## Checks

`tests/test_league_plan.nim` covers every registered year, unique league keys,
year-specific defaults, paused scheduling, singleton rotations, and rejection of
manifest drift. It runs in the existing native debug/release CI test loop.
