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
  single most important fact in the year. Levels 1–6 are the real curve
  (256 / 464 / 677 / 931 / 1210 / 1413). Elevation 7 reports **1501**, which is
  not a round the water arrives at but the sentinel `WaterTableMaxRound + 1`
  that `flood.roundWaterReaches` returns when the committed table — rounds
  0…1500, the whole of the capped game — never rises above that level. On the
  uncapped curve elevation 7 floods at round **1546** (§Divergences item 4 in
  `docs/RULES-BC20.md`, and the design note's own payload); the sim cannot
  reach it, so the table does not carry it. Either number tells a doctrine the
  same thing: elevation 7 is dry for the whole match;
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

---

## bc21

The protocol id is **unchanged** — `cogame.battlecode.v1`. The wire shape is
identical; only the year-dependent *payload* differs.

The registration blob gains two `scripted` values, `"california-roll"` and
`"examplefuncsplayer21"`. A seat that sets neither env var takes the ACTIVE
YEAR's default baseline: `awu` on bc26, `bowl-of-chowder` on bc20,
`california-roll` on bc21 — the strong published doctrine, never the weak
floor. `PLAYER_SCRIPTED=awu` and `PLAYER_SCRIPTED=scaffold` — the only two ids
the manifest declares, because they are the only two the certification fixture
seats — resolve per year, to `california-roll` and `examplefuncsplayer21` on
bc21.

### The bc21 observation

One sealed, simultaneous doctrine request per episode, exactly as bc26 and
bc20. The payload differs in three places:

```jsonc
{"protocol":"cogame.battlecode.v1","game_version":"GV06","year":"bc21",
 "slot":0,"alias":"Clan Ash","opponent_alias":"Clan Basil","seed":871345,
 "games":[{"map":"PaperWindmill","width":48,"height":48,
           "symmetry":"rotational","symmetries":["rotational"],
           "you_are":"A","rounds":1500,
           "your_centers":[{"x":11,"y":36,"influence":150}, …],
           "enemy_centers":2,
           "neutral_centers":[{"x":24,"y":24,"influence":400}, …],
           "center_separation":21,
           "passability":{"min":0.1,"mean":0.806,"swamp_pct":16.8}}, …],
 "economy":{"center_passive":"ceil(0.2*sqrt(round)) per center per round; 8507 total over 1500 rounds",
            "center_start_influence":150,
            "slanderer_breakpoints":[21,41,63,85,107,130, …],
            "slanderer_payments":51,"camouflage_round":300,
            "expose_buff":"+0.001 x slanderer influence, for 50 rounds",
            "empower_tax":10,"votes_on_offer":1500,
            "losing_bid_cost":"ceil(bid/2)"},
 "sheet_schema":{ …all ten knobs, their values, ranges and defaults… },
 "scoring":{"weights":{"survival":40,"vote_share":35,"center_share":15,
                       "influence_share":10},
            "win_bonus_per_game":100,"games":3,
            "note":"shares are float32; points truncate to an integer"},
 "budget":{"attempt1_ms":20000,"retry_ms":12000,"one_shot":true}}
```

* **the map cards** carry the seat's OWN Enlightenment Centres with their
  influence, how many the enemy has, every neutral Centre with its position and
  influence, the Centre separation, and a passability summary. Because every
  map is symmetric the two seats' cards are mirror images and numerically
  identical in every aggregate; the only asymmetry is `you_are` and which of
  the two mirrored coordinate sets is labelled "yours".
  `passability.swamp_pct` is the percentage of tiles below passability 0.5 —
  this coworld's bucket, not the engine's, which has no terrain categories at
  all (`docs/RULES-BC21.md` §Divergences item 13);
* **`economy`** carries the two curves a 2021 doctrine has to plan around: the
  Centre's passive income and the slanderer breakpoints, read from the
  committed JDK-generated table rather than re-typed;
* **`sheet_schema`** is generated from the knob table itself, so a knob cannot
  exist in the sim and be missing from the brief;
* **`scoring`** carries bc21's four weights.

The condensed rule set ships in the **system preamble**
(`decide.nim`'s `Bc21Preamble`), which every seat receives as the system
message and which the replay records once, at document level, as
`prompt_preamble` — exactly as for bc20.

**Hidden**, as ever: the opponent's doctrine, sheet, notes, motto, real name
and fallback status; every in-match state (a cog receives **no** per-round
observation). The only cross-team channel inside a match is what a robot can
sense and the flags it can read.

### The bc21 reply

```json
{"sheet":{"opening":"muck_spam","slanderer_ratio":10,"muck_ratio":70,
          "politician_size_curve":"cheap","bid_policy":"fixed",
          "expansion":"neutral_centers_first","flank_policy":"flank_wide",
          "empower_threshold":20,"convert_over_kill":false,
          "eco_exponential_round":250},
 "notes":"Kill their slanderers before round 200; buff-mucks carry the politicians in.",
 "motto":"No lies survive daylight."}
```

Ten knobs, and **no `chassis`** (D1). The caps are the year-neutral ones: 16 KB
of bytes for the whole reply, ≤ 32 sheet keys, 280 runes of `notes`, 48 of
`motto`, ≤ 16 unknown keys recorded at ≤ 40 runes each — every one cut on a
rune boundary.

## bc24

The wire shape is identical — same protocol id, same registration blob, same
one-shot sealed doctrine. Only the year-dependent *payload* differs.

### The bc24 observation

`year: "bc24"`, the three map cards, and these year blocks:

```jsonc
"economy": {"start_crumbs": 400, "passive_per_round": 10,
            "kill_reward_in_enemy_territory": 30,
            "dig_cost": 20, "fill_cost": 30,
            "trap_costs": {"explosive": 200, "stun": 100, "water": 100},
            "trap_effects": {...},
            "flag_return_rounds": 4,
            "flag_return_rounds_with_enemy_capture_upgrade": 25},
"units":    {"per_team": 50, "hp": 1000, "vision_r2": 20, "attack_r2": 4,
             "heal_r2": 4, "interact_r2": 2, "jail_rounds": 25,
             "damage_by_attack_level": [150,158,161,165,195,203,240],
             "heal_by_heal_level": [80,82,84,86,88,92,100],
             "xp_to_level": {...},
             "mastery": "at level 4 in one skill the other two freeze at 3"},
"upgrades": {"rounds": [600, 1200, 1800], "attack": "...", "heal": "...",
             "capture": "..."},
"sheet_schema": { ...all ten knobs, their values, ranges and defaults... },
"scoring":  {"weights": {"flag_share": 60, "level_share": 25,
                         "crumb_share": 15},
             "win_bonus_per_game": 100, "games": 3,
             "note": "shares are float32; points truncate to an integer"}
```

Each map card carries `map`, `width`, `height`, `symmetry`, `you_are`,
`setup_rounds`, `your_spawn_centers`, `enemy_spawn_centers`,
`min_spawn_separation`, `terrain` (`walls` / `water` / `dam` /
`passable_pct`) and `crumbs` (`piles` / `total` / `nearest_pile_to_you`).
Because every map is symmetric the two seats' cards are numerically identical
in every aggregate; the only asymmetry is `you_are` and which mirrored
coordinate set is labelled "yours".

**Two things the design note describes that this build does NOT send**, both
for the same reason bc20 did not: `rules_digest` is the ~6 KB condensed spec,
and it is in the system PREAMBLE (`Bc24Preamble` in `src/battlecode/
decide.nim`) rather than in the per-seat JSON, because the preamble is where a
model reads prose and the observation is where it reads numbers. Nothing is
withheld from a seat.

**Hidden**, always: the opponent's doctrine, sheet, notes and motto (sealed and
simultaneous — never sent, in either direction, at any time); the opponent's
real player name; every in-match state (a cog receives **no** per-round
observation — one sealed doctrine, then the war); the other seat's fallback
status.

### The bc24 reply

```json
{"sheet":{"specialisation_split":"attack","flag_rush_round":260,
          "trap_budget":10,"trap_placement":"choke","trap_mix":"stun",
          "heal_priority":"carrier_first","water_dig_policy":"fill_paths",
          "upgrade_order":["capture","attack","heal"],
          "retreat_hp":250,"flag_carry_escort":5},
 "notes":"Their south flag is 9 tiles from the dam; take it before round 300.",
 "motto":"Quack once, run twice."}
```

Caps are the year-neutral ones: 16 KB of BYTES on the whole reply (cut on a
rune boundary), ≤ 32 sheet keys, 280 runes of `notes`, 48 runes of `motto`,
≤ 16 unknown keys at ≤ 40 runes each, 200 runes of provider error text.
`upgrade_order` must be exactly three DISTINCT strings from the enum; any
malformation takes the whole default array and is recorded ONCE. A submitted
`chassis` is recorded as an unknown field and never honoured (D1).
