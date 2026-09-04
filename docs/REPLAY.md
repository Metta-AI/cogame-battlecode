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
at most six; `first_build` fires once per team per unit kind. `hq_buried` and
`hq_drowned` are derived from the recorded per-game statistics rather than
from a sim event, so the same two facts drive the endcard, the scrubber and
`results.games[]`.
