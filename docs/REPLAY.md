# The replay format

One UTF-8 JSON document at `COGAME_SAVE_REPLAY_URI`, self-sufficient **by
re-derivation, not by bulk**.

```jsonc
{"format":"cogame-battlecode-replay","version":1,
 "protocol":"cogame.battlecode.v1","game_version":"GV01","year":"bc26",
 "config":{ /* the resolved game config, tokens EXCLUDED */ },
 "seed":871345,
 "aliases":["Clan Ash","Clan Basil"],
 "names":["daveey","daveey-1"],       // spectator-side only; agents never see these
 "seats":[{"slot":0,"alias":"Clan Ash","name":"daveey","policy":"llm",
           "sheet":{…as applied…},"sheet_submitted":"{…as received…}",
           "sheet_defaults_applied":["cat_trap_budget"],
           "sheet_unknown_fields":["swarm_mode"],
           "notes":"…","motto":"…","decision_ms":8123,"fallback":null}, …],
 "games":[{"index":0,"map":"DefaultSmall","map_json_sha256":"…",
           "sides":["A","B"],"side_a_slot":0,"rounds":451,
           "hash_chain_sha256":"…"}],
 "plan":{"maps":[…],"side_a_slots":[…],"abandon_after":[…],"max_rounds":2000},
 "events":[ … ],
 "result":{ /* identical to COGAME_RESULTS_URI */ }}
```

## Why this is enough

Names, config, seed, the map identity (with a sha256 of the committed
converted map the bundle also ships), both doctrine sheets and the event list
are all in the file, and **the wasm sim replays every round from them**. No
engine bytes, no per-round state dump, no server contacted except S3 for the
`.replay` file.

The per-game hash chain lets the viewer prove its re-derivation matches the
recording: on reaching a game's last round the deriver compares its own chain
against `hash_chain_sha256` and exposes the first mismatching round through
`bc_mismatch_round`, which `static_replay.js` writes onto `<html>` as
`data-replay-mismatch-round` and the page shows in `#mmwarn`.

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
