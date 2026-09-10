# The replay format

One UTF-8 JSON document at `COGAME_SAVE_REPLAY_URI`, self-sufficient **by
re-derivation, not by bulk**.

```jsonc
{"format":"cogame-battlecode-replay","version":1,
 "protocol":"cogame.battlecode.v1","game_version":"GV03","year":"bc26",
 "config":{ /* the resolved game config, tokens EXCLUDED */ },
 "seed":871345,
 "aliases":["Clan Ash","Clan Basil"],
 "names":["daveey","daveey-1"],       // spectator-side only; agents never see these
 "seats":[{"slot":0,"alias":"Clan Ash","name":"daveey","policy":"llm",
           "sheet":{…as applied…},"sheet_submitted":"{…as received…}",
           "sheet_defaults_applied":["cat_trap_budget"],
           "sheet_unknown_fields":["swarm_mode"],
           "notes":"…","motto":"…","decision_ms":8123,
           "prompt":{ /* THE OBSERVATION: the payload composed for this seat */ },
           "fallback":null,"fallback_detail":null}, …],
 "prompt_preamble":"…",                 // the system half, identical per seat
 "games":[{"index":0,"map":"DefaultSmall","map_json_sha256":"…",
           "sides":["A","B"],"side_a_slot":0,"rounds":451,
           "hash_chain_sha256":"…",        // the chain after the LAST round
           "hash_chain_rounds":"…"}],      // 16 hex digits per round, in order
 "plan":{"maps":[…],"side_a_slots":[…],"abandon_after":[…],"max_rounds":2000},
 "events":[ … ],
 "result":{ /* identical to COGAME_RESULTS_URI */ }}
```

Decisions are taken server-side, so a seat's **observation** is the prompt
payload the server composed for it: `seats[].prompt` is that object verbatim
and `prompt_preamble` is the system half both seats received (recorded once —
it is the same string). A seat that never called the provider records
`null`. When a seat falls back, `fallback` names the cause in one word and
`fallback_detail` carries the provider's own last words, cut to
`MaxFallbackDetailRunes` (200) on a rune boundary.

## Why this is enough

Names, config, seed, the map identity (with a sha256 of the committed
converted map the bundle also ships), both doctrine sheets and the event list
are all in the file, and **the wasm sim replays every round from them**. No
engine bytes, no per-round state dump, no server contacted except S3 for the
`.replay` file.

The hash chain lets the viewer prove its re-derivation matches the recording.
`hash_chain_rounds` carries the chain as it stood at the end of **every**
round (16 hex digits each, in round order), so the deriver compares one round
at a time and `bc_mismatch_round` names the **first** divergent round — not
merely the game's last, which is all a single per-game value can say.
`hash_chain_sha256` is the last round's value and is checked on its own, so a
recording whose two records disagree is caught as well. `static_replay.js`
writes the round onto `<html>` as `data-replay-mismatch-round` and the page
shows it in `#mmwarn`.

Seven per-team stats enter the chain each round: cheese transferred, damage to
cats, the packed `kings + 10 × team cheese`, baby rats, dirt (carried and
placed), rat traps standing and cat traps standing.

The wall-clock `deadline` stop is recorded as **one load-bearing record**
(`plan.abandon_after[g]`) applied by the same code on record and on playback,
so a replay never re-derives to a different length than it was recorded at.

## Event vocabulary

Pre-match events carry `ms`; in-match events carry `game` and `round`.

| `kind` | fields | drawn as |
| --- | --- | --- |
| `episode_start` | `seed`, `year`, `maps`, `aliases` | feed line |
| `doctrine_requested` | `slot`, `attempt`, `deadline_ms` | feed line |
| `doctrine_received` | `slot`, `attempt`, `latency_ms`, `defaults_applied`, `unknown_fields` | feed line |
| `doctrine_retry` | `slot`, `cause` (`timeout` \| `parse` \| `throttled` \| `transport`) | feed line (amber) |
| `doctrine_fallback` | `slot`, `cause` | feed line (red) |
| `game_start` | `game`, `map`, `sides` | beat `game` |
| `king_built` | `game`, `round`, `alias`, `kings_now` | beat `king` |
| `backstab` | `game`, `round`, `by_alias`, `trigger` (`bite` \| `ratnap` \| `throw` \| `trap`) | **chapter marker**: beat `backstab`, the scorebug flips COOPERATION → BACKSTAB |
| `cat_fed` | `game`, `round`, `alias` | beat `cat` |
| `game_end` | `game`, `round`, `winner_alias`, `end_reason`, `points` | beat `end` |
| `game_abandoned` | `game`, `round`, `map` | beat `end` |
| `episode_end` | `reason` | endcard |

## The viewer

`"replay_viewer": {"bundle": "static-replay-viewer"}` — a static bundle, never
a pod. `tools/build_replay_viewer.sh` compiles **the same sim module** to wasm
(`replay-viewer/bc_replay.nim`, emscripten) and bundles it with the starter's
`chrome_common.js` and `broadcast_core.js` (byte for byte) and the sprite
atlas. One frame is one round: the browser steps `runRound` and emits bitworld
sprite packets, so the viewer never re-implements a rule.

Load signalling: `static_replay.js` sets `data-replay-loaded="true"` on
`<html>` on the **first drawn frame** (the worker's `loaded` message after the
first board frame is composited), and the `coworld-replay` bridge posts `ready`
from a callback fired **after** that attribute is set. On any failure it sets
`data-replay-error="<message>"` and shows the failure card.

---

## bc20

A `bc20` recording is the same document with `"year": "bc20"`. Everything the
format promises holds unchanged — self-sufficient by re-derivation, no
per-round state dump, no engine bytes — and three things are worth naming.

**No `.bc20` bytes, and no blockchain dump.** The chain is a pure function of
the sim, so the browser re-derives every block from the events, the config and
the seed, and `#bc20-chain` on the endcard reads the re-derived blocks. There
is no `match_b64` field and there never was one.

**The chassis rides on the seat, not in the sheet.** `chassis` is not a
doctrine knob in either year (D1). bc26 keeps a `chassis` field inside its
applied sheet because its filler path sets it there; bc20 records it as a
sibling of `policy` on the seat:

```jsonc
 "seats":[{"slot":0,"alias":"Clan Ash","name":"daveey","policy":"llm",
           "chassis":"bowl-of-chowder",
           "sheet":{"opening":"lattice", …the ten knobs…},
           "sheet_unknown_fields":["chassis"],   // if a reply sent one
           …}]
```

The deriver reads it back, because it has to run the bot the recording ran or
every round mismatches.

**`results.games[]` carries the year's own statistics.** The five keys
`map`, `side`, `rounds_played`, `winner` and `end_reason` are required and
year-neutral; each year's statistics are optional siblings and the two sets do
not collide. `end_reason`'s enum is the union of both years' `DominationFactor`
renderings plus our own wall-clock `abandoned`. This is deliberately **not** a
nested `stats` object: nesting would change the bytes every shipped bc26
replay's `result` block carries.

bc20's optional keys, each a 2-array in **seat** order unless marked scalar:
`hq_alive`, `hq_lost_round` (−1 if alive), `hq_lost_cause`
(`buried` | `drowned` | `none`), `soup_mined`, `soup_refined`, `net_worth`,
`units_alive`, `units_built`, `miners_built`, `landscapers_built`,
`drones_built`, `vaporators_built`, `net_guns_built`, `dirt_moved`,
`drone_pickups`, `drone_water_drops`, `net_gun_kills`, `transactions_sent`,
`transactions_minted`, `blockchain_soup_spent`; scalars
`global_pollution_peak`, `flooded_tiles_end`, `water_level_end`.

### The bc20 event vocabulary

Ten beat kinds, and **every one has CSS** in `client/replay_broadcast.html`.

| `kind` | fields | beat |
| --- | --- | --- |
| `episode_start` | `seed`, `year`, `maps`, `aliases` | — |
| `doctrine_requested` / `_received` / `_retry` / `_fallback` | `slot`, `attempt`, `cause`… | `doctrine` |
| `game_start` | `game`, `map`, `width`, `height`, `sides` | `game` |
| `flood_stage` | `level` (1…7), `flooded_tiles` | `flood` |
| `first_build` | `alias`, `unit` | `build` |
| `wall_closed` | `alias`, `min_ring_elevation` | `wall` |
| `rush_launched` | `alias`, `units` | `rush` |
| `drone_water_drop` | `alias`, `victim_alias`, `victim_unit` | `drop` |
| `hq_buried` | `alias` (victim), `by_alias`, `dirt` | `bury` (chapter marker) |
| `hq_drowned` | `alias` (victim), `water_level` | `drown` (chapter marker) |
| `game_end` / `game_abandoned` | `winner_alias`, `end_reason`, `points` | `end` |
| `episode_end` | `reason` | — |

`flood_stage` fires once per integer level reached, so a 1499-round game emits
at most six; `first_build` fires once per team per unit kind.

`first_build.unit` is spelled with the engine's own `RobotType` names, which is
why the drone is `delivery_drone` and not `drone`: `miner`, `refinery`,
`vaporator`, `design_school`, `fulfillment_center`, `landscaper`,
`delivery_drone`, `net_gun`. (`hq` and `cow` complete the type list and are
never built by anyone, so they never appear.) The design note's shorter list —
six kinds, with `drone` for the drone — is the subset it expected the chassis
to put up; the chassis also builds miners and a refinery (§Divergences item 16
in `docs/RULES-BC20.md`), and naming a beat after anything but the type that
was built would make the feed line disagree with the sim. Every one of them
draws as the `build` beat, which has CSS.

`hq_buried` and `hq_drowned` are derived from the recorded per-game statistics
rather than from a sim event, so the same two facts drive the endcard, the
scrubber and `results.games[]`.

---

## bc21

A `bc21` recording is the same document with `"year": "bc21"` and
`"game_version": "GV06"`. Everything the year-neutral reader looks at is in the
same place; the differences are the sheet, the per-game statistics and the
event vocabulary.

**No `.bc21` bytes, no per-round state dump, and no flag or bid dump.** Flags
and the auction are pure functions of the sim, so the browser re-derives them
from events + config + seed: `#bc21-votes` and `#bc21-bids` read the
re-derived tally, and `tests/test_bc21_replay.nim` asserts that nothing about
either is stored. There is no `match_b64` field.

`seats[].chassis` records the year-neutral `ScriptedChassis` string —
`california-roll` or `examplefuncsplayer21` on bc21 — beside the policy kind,
because bc21 has no `chassis` field on its doctrine (D1).

bc21's optional per-game keys, each a 2-array in **seat** order unless marked
scalar: `centers_owned`, `centers_captured`, `centers_lost`,
`neutrals_captured`, `votes`, `bids_placed`, `bid_influence_spent`, `top_bid`,
`influence_spent`, `influence_end`, `income_end`, `units_built`,
`politicians_built`, `slanderers_built`, `muckrakers_built`, `units_alive`,
`politicians_alive`, `slanderers_alive`, `muckrakers_alive`, `empowers`,
`empower_conviction`, `conversions`, `exposes`, `buff_peak`, `camouflaged`,
`robots_lost`; scalars `votes_tied` and `rounds_no_bid`. `units_built` and
`units_alive` are **reused** from bc20 with the same meaning and type.

`end_reason` gains the 2021 `DominationFactor` values in snake_case:
`annihilated`, `more_votes`, `more_enlightenment_centers`, `more_influence`.
`coin_flip` and `abandoned` were already there.

### The bc21 event vocabulary

Every kind is **bounded per game** — a 1500-round match with hundreds of robots
cannot be allowed to emit an event per empower — and every one has CSS in the
appended bc21 game block. `tests/test_bc21_replay.nim` asserts each bound
against a real 1500-round match.

| kind | bound / game | beat |
| --- | --- | --- |
| `game_start` | 1 | `game` |
| `first_build` | 6 | `build` |
| `center_taken` | 24 | `capture` |
| `vote_lead` (only when the lead changes hands) | 40 | `votes` |
| `bid_spike` (the largest bid per 100-round window per team) | 30 | `bid` |
| `expose_wave` (each 5 % step of the speech buff) | 20 | `expose` |
| `empower_big` (converts a Centre, or removes ≥ 200 enemy conviction) | 40 | `empower` |
| `annihilated` | 1 | `wipe` (chapter marker) |
| `game_end` | 1 | `end` |
| `game_abandoned` | 1 | `end` |

The pre-match `doctrine_*` events and `episode_start` / `episode_end` are
year-neutral and unchanged.

## bc24

`year: "bc24"`, `game_version: "GV07"`, everything else the same shape. The
replay stores the events, the config, the seed, both doctrine sheets, the
chassis each seat drove and the per-round hash chain — and **nothing else**.
Traps, water, crumb piles, skill levels, flag positions and the jail rail are
pure functions of the sim, so the browser re-derives them and the endcard
reads the re-derived totals. There are **no `.map24` bytes, no per-round state
dump, no per-duck dump and no trap dump** anywhere in the document, and
`tests/test_bc24_replay.nim` asserts each of those absences by string.

### The bc24 event vocabulary

Every kind is bounded PER GAME — a 2000-round match with a hundred ducks
cannot be allowed to emit an event per attack — and every one has CSS in the
appended bc24 game block.

| `kind` | fields | bound | beat |
|---|---|---|---|
| `game_start` | `map`, `width`, `height`, `sides` | 1/game | `game` |
| `setup_end` | `traps` (per clan), `teleported` | 2/game | `setup` |
| `first_action` | `alias`, **`action`** | 4/game | `build` |
| `flag_taken` | `alias`, `flag`, `x`, `y` | ≤ 24/game | `steal` |
| `flag_dropped` | `alias`, `flag`, `x`, `y`, `cause` | ≤ 24/game | `return` |
| `flag_returned` | `alias`, `flag` | ≤ 24/game | `return` |
| `flag_captured` | `alias`, `flag`, `total` | ≤ 6/game | `capture` |
| `trap_wave` | `alias`, `triggered_total`, `damage_total` | ≤ 20/game | `trap` |
| `upgrade` | `alias`, `upgrade` | ≤ 6/game | `upgrade` |
| `mastery` | `alias`, `skill`, `level` | ≤ 9/game | `level` |
| `rout` | `alias`, `jailed` | ≤ 20/game | `rout` |
| `game_end` | `winner_alias`, `winner_slot`, `end_reason`, `points` | 1/game | `end` |
| `game_abandoned` | `map` | ≤ 1/game | `end` |

**`first_action`'s field is `action`, not the design note's `kind`.**
`MatchEvent.toJson` flattens `fields` into the same object as the event's own
`kind` key, so a field called `kind` SILENTLY OVERWRITES THE EVENT KIND and the
replay comes back carrying events of kind `move` and `spawn`. bc20 and bc21
avoided it by calling their field `unit`; bc24 calls its field `action`, and
`tests/test_bc24_replay.nim` asserts that no `first_action` event carries a
field called `kind`.

`action` takes its value from `Bc24ActionNames` (`spawn`, `move`, `attack`,
`heal`, `build`, `dig`, `fill`, `pickup`, `drop`, `upgrade`), `upgrade` from
`Bc24UpgradeNames` (`attack`, `capture`, `heal` — `TeamInfo`'s own slot order)
and `mastery.skill` from `Bc24SkillNames` (`attack`, `build`, `heal`).

---

## bc16

`year: "bc16"`, `game_version: "GV11"`, everything else the same shape. The
replay stores the events, the config, the seed, both doctrine sheets, the
chassis each seat drove and the per-round hash chain — and **nothing else**.
Rubble, parts, the zombie horde, infection timers, delays, den queues and the
tiebreak ladder are pure functions of the sim, so the browser re-derives them
and the endcard reads the re-derived totals. There are **no map bytes, no
per-round state dump, no per-robot dump and no rubble grid** anywhere in the
document, and `tests/test_bc16_replay.nim` asserts each of those absences by
string.

**Rounds are ZERO-BASED in bc16.** The engine counts from round 0 and the
tiebreak fires at the end of round 2999, not 3000 — the only year in this
repository that does. `years/dispatch.nim`'s `currentRound` arm therefore
returns `world.currentRound + 1` so that the replay's chain index stays
1-based like every other year's; the *events* carry the engine's own
zero-based round.

### The bc16 event vocabulary

Every kind is bounded PER GAME — a 3000-round match with a hundred robots and
a horde cannot be allowed to emit an event per bite — and every one has CSS in
the appended bc16 game block.

| `kind` | fields | bound | beat |
|---|---|---|---|
| `game_start` | `map`, `width`, `height`, `sides`, `archons`, `dens`, `parts_on_map`, `neutrals`, `schedule_rounds` | 1/game | `game` |
| `first_action` | `alias`, **`action`** | 2/game | `build` |
| `unit_milestone` | `alias`, `unit`, `total` | ≤ 10/game | `build` |
| `zombie_wave` | `counts` (4-array), `total`, `dens_spawning`, `outbreak_level` | ≤ 30/game | `wave` |
| `outbreak` | `level`, `multiplier_permille` | ≤ 10/game | `outbreak` |
| `den_destroyed` | `alias`, `x`, `y`, `dens_left`, `bounty`, `queue_deleted` | ≤ 12/game | `den` |
| `neutral_activated` | `alias`, `unit`, `x`, `y`, `total` | ≤ 20/game | `activate` |
| `infection` | `alias`, `victim_unit`, `source`, `turns` | ≤ 20/game | `infect` |
| `turned` | `alias`, `unit`, `became`, `x`, `y`, `outbreak_level` | ≤ 24/game | `turned` |
| `archon_lost` | `alias`, `archons_left`, `cause` | ≤ 8/game | `archon` |
| `rout` | `alias`, `lost` | ≤ 20/game | `rout` |
| `duel` | `lost` (2-array) | ≤ 20/game | `duel` |
| `tiebreak` | `rung`, `archons` (2), `archon_health_tenths` (2), `parts_worth` (2) | ≤ 1/game | `end` |
| `game_end` | `winner_alias`, `winner_slot`, `end_reason`, `points`, `archons` | 1/game | `end` |
| `game_abandoned` | `map` | ≤ 1/game | `end` |

**`first_action`'s field is `action`, not `kind`.** `MatchEvent.toJson`
flattens `fields` into the same object as the event's own `kind` key, so a
field called `kind` SILENTLY OVERWRITES THE EVENT KIND — the bc24 scar. bc16
follows bc24 and calls it `action`.

`action` takes its value from `Bc16ActionNames` (`clear_rubble`, `move`,
`attack`, `broadcast`, `broadcast_message`, `build`, `activate`, `repair`,
`pack`, `unpack`, `disintegrate` — eleven, because bc16 has twelve unit types
and naming the unit would say less than naming the act), `unit` / `victim_unit`
/ `became` from `Bc16UnitNames` (`RobotType`'s own ordinals: `zombieden`,
`standardzombie`, `rangedzombie`, `fastzombie`, `bigzombie`, `archon`, `scout`,
`soldier`, `guard`, `viper`, `turret`, `ttm`) and `tiebreak.rung` from
`Bc16RungNames` (`Domination`'s own ordinals: `-`, `archons_destroyed`,
`more_archons`, `more_archon_health`, `more_parts_net_worth`, `highest_id`).

### Four names bc16 shares with other years

`first_action`, `rout`, `duel` and **`archon_lost`** are spelled the same by
bc22, bc23 and bc25. Three of them carry the same shape; `archon_lost` does
not — **bc22 carries `gold_dropped` and bc16 carries `cause`** — so
`broadcast.nim`'s *label* switch tests the replay header's year there, and only
there. The beat *kind* is `archon` for both, and the CSS that colours it is
scoped per year (`html[data-year="bc16"] .beat-marker.archon`).

### `outbreak` and `zombie_wave` travel as integers

The outbreak multiplier is an integer **per-mille** (1000, 1100, … 3000) rather
than a float, so the replay document stays float-free and re-derives bit for
bit in wasm. The viewer renders it as `1.1x`. This is also the field that cost
a defect: the label originally read `multiplier`, which does not exist, and a
missing key in a `JsonNode` `{}` lookup reads back as zero — so the spectator
was shown `0 zombies from 0 dens`. `tests/test_bc16_beats.nim` now asserts each
label against the value in the event that produced it, not just against the
words.

### The thirteen beats

`doctrine`, `game`, `build`, `wave`, `outbreak`, `den`, `activate`, `infect`,
`turned`, `archon`, `rout`, `duel`, `end` — and **all thirteen are emitted by
the committed fixture** `tests/fixtures/replay-bc16.json`, so
`tests/test_bc16_beats.nim` proves emission, label and CSS together rather than
inventorying a hand-written list.


---

## The bc19 payload

`game_config.year = "bc19"` selects Battlecode 2019 "Crusade". The protocol id
is **unchanged** (`cogame.battlecode.v1`): the wire shape is identical and only
the year-dependent payload differs.

**The observation is a SEALED ONE-SHOT brief and there is no per-round
observation of any kind.** It carries, per game: `map`, `map_seed`, `width`,
`height`, `you_are` (`RED` or `BLUE`), `rounds`, `rounds_are_one_based`,
`symmetry` and a `symmetry_note` saying which midline the board is mirrored
across, `passable_squares` / `total_squares` / `passable_pct`,
**both orders' castle positions**, `castle_separation_min` and `_max`, and a
`karbonite_depots` / `fuel_depots` block with the total, the per-side count,
the nearest one to you in steps, and a note saying what a pilgrim standing on
one actually does. Both orders' castle positions are given because **they are
not secret**: every robot is handed the complete terrain, karbonite and fuel
maps on its first turn (`coldbrew/game.js:728-730`) and the board is a mirror,
so the enemy castles are derivable in a few operations on turn 1.

Beside the map cards the brief carries the economy block (the flat 25-fuel
trickle, the mining yields and capacities, the reclaim formula and the
barter), the six unit types with their exact costs, health, ranges — including
**the PROPHET's r² 16 MINIMUM** and **the PREACHER's nine-square team-blind
blast** — speeds, fuel per r² and vision, the combat rules (no vision test, no
team check, no path check), the two comms channels, a **HOW A GAME ENDS**
block, the eleven-knob `sheet_schema` with every default and range, the
scoring weights and the deadlines.

**Hidden**: the opponent's doctrine, sheet, notes and motto (sealed and
simultaneous, never sent in either direction at any time); the opponent's real
player name; every in-match state; the other seat's fallback status; and
**`robot.time`**, which is wall-clock derived and would make the prompt
non-reproducible (divergence V7).

`results.games[]` carries bc19's optional statistics beside the five
year-neutral required keys; `end_reason` is one of `castles_destroyed`,
`more_castles`, `more_unit_health`, `coin_flip` or `abandoned`, and
`win_condition` carries **the engine's own integer** beside it, so a replay
always traces back to a branch of `isOver` — including the round-1000
all-square case, which the engine records as `1` while the winner really is a
coin flip (`docs/RULES-BC19.md`).
