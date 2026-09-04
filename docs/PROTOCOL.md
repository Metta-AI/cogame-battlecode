# `cogame.battlecode.v1`

## The player container

`/bin/battlecode-player` reads `COWORLD_PLAYER_WS_URL` (legacy alias
`COGAMES_ENGINE_WS_URL`), dials its seat with a bounded retry
(240 × 500 ms), sends **one** registration blob and then only receives until
the socket closes, then exits **0** — a dead socket must exit 0, not raise.

```json
{"type":"register","slot":0,"prompt":"<PLAYER_PROMPT or empty>",
 "scripted":"awu"|"scaffold"|null,"policy":"<PLAYER_POLICY_LABEL>"}
```

sent as a Sprite v1 chat blob — a **binary** frame. The server does **not**
filter non-text frames, and it keeps its `Ping → Pong` branch. `slot` rides in
the blob, read by the player from its own socket URL, so the server never has
to derive a seat from connection order.

A seat that sets neither env var is `awu`. A seat whose registration never
arrives is logged loudly, reported to `COGAME_PLAYER_FAILURE_URI`, and plays
the scripted doctrine.

## The doctrine exchange (server-side)

Every decision happens inside the **game** container, because that is the only
container the platform injects the `anthropic_api_key` coworld secret into,
and because keeping the control layer server-side is what makes a recorded
doctrine reproducible with no network in the loop.

There is exactly **one decision turn per episode**, and both seats' provider
calls are issued as **ONE parallel batch** (`curly.makeRequests`) with the same
deadline. Seats are never queried one after another.

The "observation" is the brief the server composes per seat:

```json
{"protocol":"cogame.battlecode.v1","game_version":"GV03","year":"bc26",
 "slot":0,"alias":"Clan Ash","opponent_alias":"Clan Basil","team":"A",
 "seed":871345,
 "games":[{"map":"DefaultSmall","width":30,"height":30,"symmetry":"rotational",
           "cheese_mines":4,"cats":2,"rounds":2000,"you_are":"A"}, …],
 "scoring":{"cooperation":{"cat_damage":0.5,"kings":0.3,"cheese":0.2},
            "backstab":{"cat_damage":0.3,"kings":0.5,"cheese":0.2},
            "win_bonus_per_game":100,"games":3,
            "note":"shares are float32; points truncate to an integer"},
 "budget":{"attempt1_ms":20000,"retry_ms":12000,"one_shot":true}}
```

**Visible:** everything above — own alias and side, all the map cards, the
seed, both weight sets, the full knob surface with defaults (in the system
preamble), the deadlines.

**Hidden:** the opponent's doctrine, sheet, notes and motto (sealed and
simultaneous — never sent, in either direction, at any time); the opponent's
real player name (only the alias); every in-match state (a cog receives **no**
per-round observation — one sealed doctrine, then the war); the other seat's
fallback status. The only cross-clan channel in the match is the sim's own
squeaks and positions between robots.

## Reply schema and caps

```json
{"sheet":{"backstab_policy":"at_round_N","backstab_round":700,
          "cat_engagement":"hunt","cat_trap_budget":60,"rat_trap_budget":80,
          "spawn_curve":"swarm","cheese_ferry_ratio":0.4,"king_count_target":4,
          "dirt_wall_policy":"king_shell","throw_rats_to_feed_cats":false},
 "notes":"Farm cats to 700, then take their kings.",
 "motto":"Trust, briefly."}
```

| field | cap | on violation |
| --- | --- | --- |
| whole reply | 16 KB | unparseable → retry once → scripted doctrine |
| `sheet` | ≤ 32 keys, each value type- and range-checked | bad field → that field's default |
| `notes` | **280 runes** | truncated |
| `motto` | **48 runes** | truncated |
| unknown sheet keys recorded | ≤ 16 keys, each ≤ 40 runes | truncated |
| provider error text stored in the replay | **200 runes** | truncated |

The assistant turn is **prefilled with `{`** and the prefix re-attached before
parsing.

## Degrade, never hang

| failure | response |
| --- | --- |
| no reply within `attempt1Ms` (20 000) | one retry with `retryMs` (12 000), logged `will retry` |
| second failure, unparseable JSON, or a throttle with no other candidate model | that seat plays its **scripted doctrine**, `results.fallbacks[seat] = 1`, a `doctrine_fallback` event names the cause, the log says `falling back` |
| the phase exceeds `doctrineBudgetMs` | whatever is unresolved takes the scripted doctrine; the match starts anyway |
| a sheet field is unknown, mistyped or out of range | that field alone takes its default |
| a seat never registers | it plays the scripted doctrine, is reported to `COGAME_PLAYER_FAILURE_URI`, and the server logs **loudly** |
| a game exceeds `perGameBudgetSeconds`, or the match exceeds `matchBudgetSeconds` | the running game is abandoned, finished games are scored, `results.reason = deadline` |
| the match finishes early (a side takes 2 games) | the episode settles immediately — no padding |
| no credentials at all | the LLM client disables itself at construction; both seats are scripted and the episode completes in seconds |

## Budget

`episodeTimeoutSeconds = 1200`; 60 % = 720 s. The container enforces its own
caps and the worst case is **435 s**:

```
container start, map load, seat connect              <=  30 s
doctrine: ONE parallel batch of 2 LLM calls          <=  45 s
match: 3 games x 2000 rounds                         <= 330 s
score + replay write + shutdown grace                <=  30 s
                                                       ------
                                                        435 s  <= 720 s
```

## HTTP surface

| route | what |
| --- | --- |
| `GET /healthz`, `GET /health` | liveness; keeps answering for a ~20 s shutdown grace after the artifacts are written |
| `GET /global` | phase, seat registration, and the results document once it exists. **Also upgrades**: a spectator that opens it as a WebSocket gets that same JSON as a text frame and as a Sprite v1 chat blob, immediately on connect and then every 500 ms, so a socket opened mid-episode is never silent. A `/global` upgrade carrying `slot` or `token` is refused 403 — a spectator does not use a seat's credentials. |
| `GET /player?slot=N&token=…` | the seat websocket. The token is a **credential**: the runner injects one per seat into `game_config.tokens`, and a wrong, missing or out-of-range one is refused **403 before the upgrade** so the dialler sees a failed handshake. A config that declares no tokens at all is a local run and is left open. |
| `GET /client/global`, `/client/player` | a one-paragraph page saying the watchable artifact is the recorded replay |

There is deliberately **no `/client/replay` live viewer**: the replay is a
static file re-derived by the wasm bundle in the browser.

---

## bc20

The protocol id is **unchanged** — `cogame.battlecode.v1`. The wire shape is
identical; only the year-dependent *payload* differs. A new protocol id would
force every existing consumer to re-register for no change in the contract.

The registration blob gains two `scripted` values,
`"bowl-of-chowder"` and `"examplefuncsplayer"`. A seat that sets neither env
var takes the ACTIVE YEAR's default baseline: `awu` on bc26,
`bowl-of-chowder` on bc20 — the strong published doctrine, never the weak
floor.

### The bc20 observation

One sealed, simultaneous doctrine request per episode, exactly as bc26. The
payload differs in three places:

```jsonc
{"protocol":"cogame.battlecode.v1","game_version":"GV05","year":"bc20",
 "slot":0,"alias":"Clan Ash","opponent_alias":"Clan Basil","seed":871345,
 "games":[{"map":"CentralLake","width":41,"height":41,"symmetry":"rotational",
           "you_are":"A","hq_elevation":4,"hq_separation":34,
           "soup_tiles":50,"soup_total":24800,"soup_near_hq":3100,
           "cows":4,"initially_flooded_tiles":118,"rounds":1500}, …],
 "flood_table":{"1":256,"2":464,"3":677,"4":931,"5":1210,"6":1413,"7":1501},
 "scoring":{"weights":{"hq_survival":60,"unit_share":25,"net_worth_share":15},
            "win_bonus_per_game":100,"games":3,
            "note":"shares are float32; points truncate to an integer"},
 "budget":{"attempt1_ms":20000,"retry_ms":12000,"one_shot":true}}
```

* **the map cards** carry the seat's own HQ starting elevation and the HQ
  separation, which is what a doctrine has to plan the wall against;
* **`flood_table`** says which round each integer elevation floods at — the
  single most important fact in the year. Elevation 7 reports `1501` because
  the water never reaches it inside the 1500-round cap;
* **`scoring`** carries bc20's three weights instead of bc26's two weight sets.

**No `rules_digest` and no `sheet_schema` key.** The design note's sample
payload shows both inside the per-seat observation. They ship instead in the
**system preamble** (`decide.nim`'s `Bc20Preamble`), which every seat receives
as the system message and which the replay records once, at document level, as
`prompt_preamble` — the condensed rule set and the full knob surface with every
range and default are there in full, verbatim, for both years. The content a
doctrine sees is the same; only the layout differs. A consumer that wants the
knob surface off a replay reads `prompt_preamble`, not `seats[].prompt`.

**Hidden**, as ever: the opponent's doctrine, sheet, notes, motto, real name
and fallback status; every in-match state (a cog receives **no** per-round
observation). The only cross-team channel inside a match is the sim's own
blockchain and what a robot can see.

### The bc20 reply

```json
{"sheet":{"opening":"rush","terraform_start_round":420,"lattice_radius":3,
          "landscaper_count_curve":"swarm","miner_count_curve":"lean",
          "vaporator_budget":0,"drone_role":"harass","net_gun_ring":1,
          "rush_trigger":240,"wall_hq_round":300},
 "notes":"Bury them by 400; if it stalls, wall at 300 and lattice out.",
 "motto":"Soup is for the patient."}
```

Ten knobs, and **no `chassis`** (D1). The caps are the year-neutral ones: 16 KB
of bytes for the whole reply, ≤ 32 sheet keys, 280 runes of `notes`, 48 of
`motto`, ≤ 16 unknown keys recorded at ≤ 40 runes each — every one cut on a
rune boundary.
