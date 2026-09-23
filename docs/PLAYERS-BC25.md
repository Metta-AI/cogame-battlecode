# 2025 contender entries

Four named native strategy adaptations can be registered as independent players
in the **Battlecode 2025 — Chromatic Conflict** league. Each has a separate
controller ID, policy name and player identity. They are not four versions of
one player: standings are keyed by player identity, and each player's champion
must refer to that player's own immutable policy version.

| Display name | `PLAYER_SCRIPTED` | Policy name |
| --- | --- | --- |
| BC25 confused (Nim) | `confused` | `battlecode-bc25-confused` |
| BC25 Just Woke Up (Nim) | `just-woke-up` | `battlecode-bc25-just-woke-up` |
| BC25 Om Nom (Nim) | `om-nom` | `battlecode-bc25-om-nom` |
| BC25 SPAARK (Nim) | `spaark-2025` | `battlecode-bc25-spaark-2025` |

The existing `spaark` controller remains the doctrine-driven hybrid used by LLM
seats and old replays. `spaark-2025` is a new controller with the archived team's
production accounting. Unknown names and names used in another year retain
their existing fallback behavior.

## Source custody

All four archives carry AGPL-3.0 licenses. Their source commits are pinned below;
these links identify the code examined, not an assertion of tournament parity.

| Team | Archived revision | Source directory |
| --- | --- | --- |
| confused | [`bb21870`](https://github.com/battlecode-archive/2025-confused/tree/bb21870cec74c9991c6a880cead3b24e5c0c7ac9/java/src/finals) | `java/src/finals` (identified by upstream README) |
| Just Woke Up | [`ba5976b`](https://github.com/battlecode-archive/2025-Just-Woke-Up/tree/ba5976b09bd230d43b8c87efc4c34a1680592202/java/src/v57_Optimaler) | `java/src/v57_Optimaler` (latest numbered archive; exact finals artifact not independently verified) |
| Om Nom | [`bc2f945`](https://github.com/battlecode-archive/2025-Om-Nom/tree/bc2f945b13c78cfaf8331f59fabcd7e16d53c71f/templates) | `templates/*.java.jinja2`, the source of generated `current` |
| SPAARK | [`63165da`](https://github.com/battlecode-archive/2025-SPAARK/tree/63165da768ad1e087e3f8e4f6ee84e1a51d3a014/src/SPAARK) | `src/SPAARK` |

## Implemented differences

- **confused:** `Tower.getNextToSpawn`'s small-map splasher opening, production
  transitions at rounds 100/250, per-tower counters, early chip reserve and
  defensive mopper branch. Soldiers consider immediate tower attacks before
  refill/build work. The tower chooses the lowest-health enemy after its area shot.
- **Just Woke Up:** `Tower.turn`'s opening soldier/soldier/splasher cycle, later
  soldier/mopper/splasher cycle, local crowding gate, emergency moppers,
  paint-tower upgrades and soldier-first tower fire. Soldiers enter refill at
  25% paint and stay in that state until 75%, and avoid choosing defense towers
  for their health-gated combat branch. Resource patterns require four towers
  and no locally visible enemies.
- **Om Nom:** `Tower.java.jinja2`'s independent paint/money tower build cycles,
  reselection every 200 rounds, remembered per-plan cursors, 30-round defensive
  mopper interval, money-tower skip behavior when short of paint, paint-tower
  upgrades, and splasher/soldier/other targeting order that ignores zero-paint
  enemies. Soldiers consider immediate combat before economy.
- **SPAARK:** `Tower.run`'s accumulated fractional production targets with
  soldier weight `1.5 - 0.05 * towers`, mopper weight `1.2`, and splasher weight
  `0.2 + 0.3 * known paint towers`. Targets advance only on a successful spawn.
  It preserves the three-soldier opening override, 900-chip reserve, later
  spacing/crowding gate, and prefers the largest killable target after area fire.

## Fidelity boundary

These are **strategy adaptations, not functional-equivalence-certified ports**.
They do not execute Java. In particular, movement, exploration, tower-pattern
selection/filling, resource-pattern placement, mopper and splasher micro,
information sharing, and message encoding use this repository's native chassis.
The scalar doctrine values map the strategies onto native mechanics; they are
not upstream constants. Native shared team memory differs from the originals'
per-robot memory and communications. Tower demolition/rebuild farming, the full
upstream state machines, bytecode interruption, generated navigation, exact
spawn locations/tie order, and several emergency branches are not reproduced.

Consequently, neither game outcomes nor tournament strength are claimed to
match the originals. Full functional duplication remains further work requiring
per-robot ports and differential action traces against pinned Java controllers.
The `(Nim)` display suffix and policy notes identify these as adaptations.

## Release and registration

`tools/ci/bc25-contender-policies.json` contains the four candidate release rows.
They are intentionally excluded from the general release catalog until the
game-owned identity/upload path is available. The `player_name` field is resolved
by `tools/ci/resolve_policy_players.py` before building or uploading. It
reuses exact owned names, creates missing identities, rejects ambiguous or
disabled names, and assigns four distinct `player` IDs. The release job then
switches identity before each upload and clears it afterwards. Releasing again
updates each existing player's policy rather than creating another player.

Build/certify the game and player image together: this game's player container
only registers a controller name, so an old game image would silently fall back
to legacy `spaark`. Use the Coworld release workflow with only the four rows as
its `policies` input, certification enabled, and `put_secret=false` for a
scripted-only release. Wait for its canonical-version readback. The release
artifact records the exact `name:vN` and owning player ID.

Registration is currently blocked. The release attempt on 2026-09-23 passed
certification and four complete container episodes, but player creation returned
HTTP 409: `Users are limited to 2 active players`. No contender policies or new
game version were uploaded, and none of these players are on the leaderboard.
The diagnostic retry failed before building, with the same account limit.

The platform supports Coworld-owned player and policy ownership, but the current
CLI creates/selects personal players. Simply lifting the creation limit is not
sufficient: the league also limits active personal players per user, which can
bench other entries. Permanent built-in baselines need a supported creation,
upload and update path for four Coworld-owned identities. Do not submit these
four as personal players or change league limits to work around this constraint.

Once that path is available, resolve the live league whose Coworld is
`battlecode` and default variant is `bc25`. Submit each exact immutable version
with its matching game-owned identity, then read back submissions, active
memberships and champion flags. A source change or successful policy upload
alone does not establish a leaderboard entry.

## Validation

`tests/test_bc25_contenders.nim` checks distinct registration/replay mappings,
source-derived production transitions and attack priorities, isolated per-game
memory, legal complete games from both seats, and deterministic distinct game
trajectories. `tools/ci/test_resolve_policy_players.py` checks separate identities,
idempotent name resolution and failure on ambiguous/disabled owners.

These tests establish native operation and distinct strategies; they do not
establish behavioral equivalence with the Java originals.
