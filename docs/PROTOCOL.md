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
| model output cap sent as `max_tokens` | `maxOutputTokens` (1 200; bc19 **3 000**) | the reply stops mid-structure and reads as unparseable JSON |
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
| no reply within `attempt1Ms` (20 000; bc19 40 000) | one retry with `retryMs` (12 000; bc19 24 000), logged `will retry` |
| second failure, unparseable JSON, or a throttle with no other candidate model | that seat plays its **scripted doctrine**, `results.fallbacks[seat] = 1`, a `doctrine_fallback` event names the cause, the log says `falling back` |
| the phase exceeds `doctrineBudgetMs` (45 000; bc19 75 000) | whatever is unresolved takes the scripted doctrine; the match starts anyway |
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

**bc19 is the one year with raised doctrine deadlines** — `attempt1Ms` 40 000,
`retryMs` 24 000, `doctrineBudgetMs` 75 000. They were raised in 0.9.1 because
both doctrine attempts for one seat timed out against the bedrock sidecar in
league rounds 1 and 2 while the provider answered `200 OK` to every request.
Its worst case is 30 + 75 + 200 (`matchBudgetSeconds`) + 30 = 335 s, still
inside 720 s.

**bc19 is also the one year with a raised reply cap** — `maxOutputTokens`
3 000, where every other year inherits `defaultGameConfig()`'s 1 200. It was
raised in 0.11.2 because both doctrine attempts for one seat returned *inside*
their deadlines but were long pretty-printed replies that stopped
mid-structure (`input(40, 40) Error: ] expected`, then
`input(40, 5) Error: } expected`, against a successful sheet's single line of
~245 characters), and a truncated reply cannot be detected by the existing
`max_tokens` guard because the assistant turn is prefilled with `{`, so the
guard's `'{' notin result` condition is never true and the truncation surfaces
as an ordinary parse error instead.

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

## bc25

The wire shape is identical — same protocol id, same registration blob, same
one-shot sealed doctrine. Only the year-dependent *payload* differs.

### The bc25 observation

`year: "bc25"`, the three map cards, and these year blocks:

```jsonc
"economy": {"start_chips": 2500, "tower_costs": [1000, 2500, 5000],
            "money_tower_per_turn": [20, 30, 40],
            "paint_tower_per_turn": [5, 10, 15],
            "defense_tower_chips_per_hit": [20, 30, 40],
            "srp": {"chip_cost": 200, "paint_cost_to_mark": 25, "tiles": 25,
                    "rounds_undisturbed_to_activate": 50,
                    "bonus": "+3 per turn to EVERY mining tower you own"},
            "max_towers": 25},
"units": {"soldier": {...}, "splasher": {...}, "mopper": {...}},
"paint_rules": {"vision_r2": 20, "end_turn_cost": "...", "low_paint": "...",
                "zero_paint": "cannot move, cannot act, loses 20 HP a turn"},
"towers": {"how_built": "...", "patterns": {"money": [...], "paint": [...],
           "defense": [...], "srp": [...], "legend": "..."},
           "hp": {...}, "attacks": "..."},
"win": {"instant": "paint 70% of (width*height - walls), or destroy every "
                   "enemy robot AND tower",
        "at_round_2000": ["more squares painted", "more towers alive",
                          "more chips", "more paint in units",
                          "more robots alive", "coin flip"]},
"sheet_schema": { ...all ten knobs, their values, ranges and defaults... },
"scoring": {"weights": {"area_share": 55, "tower_share": 20, "chip_share": 10,
                        "paint_share": 10, "robot_share": 5},
            "win_bonus_per_game": 200, "games": 3,
            "note": "shares are float32; points truncate to an integer"}
```

Each map card carries `your_start_towers` and `enemy_start_towers` — they are
**public**: every map is symmetric and the engine's own map file puts them
there — plus `terrain.area_without_walls` (the engine's own 70 % denominator),
`terrain.truly_paintable` beside it so the cog can see the gap that divergence
creates, `terrain.tiles_to_win`, `terrain.ruins`, `terrain.pre_painted` and
`chokes`.

**Hidden**, as in every year: the opponent's doctrine, sheet, notes, motto and
real player name; every in-match state (a cog receives **no** per-round
observation — one sealed doctrine, then the war); the other seat's fallback
status. Inside a match the fog is the robots': vision r² ≤ 20, and the enemy's
**markers** are never sensible.

### The bc25 reply

```json
{"sheet":{"opening":"tower_rush",
          "unit_mix":{"soldier":40,"mopper":20,"splasher":40},
          "srp_priority":10,"tower_type_order":["money","defense","paint"],
          "ruin_claim_radius":6,"defense_tower_chokes":"early",
          "paint_reserve_floor":20,"mop_enemy_paint":15,
          "splash_targets":"towers","upgrade_policy":"defense_first"},
 "notes":"Their money tower at (26,9) is 6 tiles from the middle choke; three splashers break it before round 600.",
 "motto":"Two colours, one map."}
```

Caps are the year-neutral ones: 16 KB of BYTES on the whole reply (cut on a
rune boundary), ≤ 32 sheet keys, 280 runes of `notes`, 48 runes of `motto`,
≤ 16 unknown keys at ≤ 40 runes each, 200 runes of provider error text.
`unit_mix` must be an object of exactly the three integer keys and
`tower_type_order` exactly three DISTINCT strings from the enum; any
malformation takes the whole default and is recorded ONCE. A submitted
`chassis` is recorded as an unknown field and never honoured (D1).

## bc23

`game_config.year = "bc23"` selects Battlecode 2023 "Tempest". The protocol
id is **unchanged** (`cogame.battlecode.v1`): the wire shape is identical and
only the year-dependent *payload* differs, so every existing bc26, bc20,
bc21, bc24 and bc25 consumer keeps working without re-registering.

### The bc23 observation

One sealed one-shot brief per seat, recorded verbatim in the replay. There is
**no per-round observation of any kind**: one doctrine, then the war.

On top of the year-neutral envelope (`protocol`, `game_version`, `year`,
`slot`, `alias`, `opponent_alias`, `team`, `seed`, `games`, `budget`) a bc23
brief carries:

| key | what it says |
|---|---|
| `games[].islands` / `islands_to_win` / `island_tiles` / `island_sizes` | the sky islands, and **the exact number a conquest needs** under the float32 75 % test |
| `games[].your_headquarters` / `enemy_headquarters` | both factions' headquarters. They are PUBLIC: every map is symmetric and the engine's own map file puts them there |
| `games[].start_separation` | the shortest Euclidean distance between an A headquarters and a B one — how far a launcher rush has to run |
| `games[].terrain` | impassable tiles and percentage, clouds and percentage, currents, and the adamantium / mana / **elixir** well counts (every official map has zero elixir wells) |
| `games[].nearest_well_to_you` / `nearest_island_to_you` | the walking distance, in Chebyshev steps, a carrier actually pays |
| `economy` | 200/200 per headquarters at round 1, +6/+6 per headquarters every five rounds, well rate 1 and 3, the 1400 kg upgrade, the 600 kg elixir transformation, capacity 40 — and the note that a resource thrown into a well leaves your team total for good |
| `units` | all six types with their exact costs, cooldowns, radii and what they do, including the carrier's `floor(5 + 3*cargo/8)` movement and the launcher's blind r² ≤ 16 |
| `anchors` | both anchors' costs, health and healing, how one is built, ferried and planted, the occupancy formula that holds it, and the fact that overriding your OWN anchor does not count as a new one placed |
| `tempo` | the cloud's 20 % and its **two-way** vision collapse, the ADDITIVE per-tile per-team stacking, and `round(base × multiplier)` read at the tile you end up on |
| `comms` | 64 slots, 0…65535, the three write windows, reading always legal, no cooldown and no cost |
| `win` | the 75 % conquest, the five-rung ladder, and the note that **there is NO elimination** |
| `sheet_schema` | the twelve knobs, their values, ranges and defaults, generated from `knobs.nim` |
| `scoring` | the 60/22/10/5/3 weights, the 200-per-game win bonus, and the note that the league ranks by `scores` |

**Hidden**, always: the opponent's doctrine, sheet, notes and motto (sealed and
simultaneous — never sent, in either direction, at any time); the opponent's
real player name; every in-match state; the other seat's fallback status.

### The bc23 reply

The same envelope every year uses — `{"sheet": {...}, "notes": "...",
"motto": "..."}` — with the twelve knobs of `docs/RULES-BC23.md`. Unknown key,
wrong type or out-of-range value takes that field's default and is recorded;
the four INTEGER knobs (`launcher_ratio`, `anchor_round`, `anchor_budget`,
`carrier_throw`) **clamp** to their range instead, so "as much as possible"
still means something. A sheet can never be rejected. **There is no `chassis`
key**: a submitted one is recorded in `sheet_unknown_fields` and never
honoured.

## bc22

`game_config.year = "bc22"` selects Battlecode 2022 "Mutation". The protocol
id is **unchanged** (`cogame.battlecode.v1`): the wire shape is identical and
only the year-dependent *payload* differs, so every existing bc26, bc20, bc21,
bc23, bc24 and bc25 consumer keeps working without re-registering. The
`game_version` in the envelope is **`GV10`**; `GV09` and every earlier value
stay in `ReplayCompatibleGameVersions`, so an older replay still loads.

### The bc22 observation

One sealed one-shot brief per seat, recorded verbatim in the replay. There is
**no per-round observation of any kind**: one doctrine, then the war.

On top of the year-neutral envelope (`protocol`, `game_version`, `year`,
`slot`, `alias`, `opponent_alias`, `team`, `seed`, `games`, `budget`) a bc22
brief carries:

| key | what it says |
|---|---|
| `games[].you_are` / `your_archons` / `enemy_archons` | which side this seat plays and both factions' archon spawns. They are PUBLIC: every map is symmetric and the engine's own map file puts them there |
| `games[].start_separation` | the shortest Euclidean distance between an A archon and a B one — how far a soldier rush has to run |
| `games[].terrain` | `rubble_mean`, `rubble_median`, `rubble_max` and `squares_over_50_rubble_pct`, because rubble is this year's whole tempo term |
| `games[].lead` | the lead squares, their total, the richest square, the nearest one to this seat and how many sit inside an archon's vision at round 1 |
| `games[].gold` | zero squares and zero total on every official map, with the note that a laboratory or a death drop is the only source |
| `games[].anomaly_schedule` | **the full schedule, round by round and kind by kind.** It is public to every robot at all times in the real game, so it is public here |
| `games[].singularity_round` | 2000 on every official map (`GameMapIO` hard-codes it; the field is not even in the map file) |
| `rubble` | `floor((1 + rubble/10) * base)` and the note that rubble 60 is seven times the cost of bare ground |
| `economy` | 200 lead per faction at round 1, +2 per archon per round, the **+5 every 20 rounds to every square that still holds at least 1**, the miner's five-mines-a-turn rate, the laboratory's `floor(20 - 18*exp(-k*n))` price and the 20 % reclaim drop |
| `units` | all seven types with their exact costs, cooldowns, radii, per-level health, damage, healing and mutation prices |
| `buildings` | the PROTOTYPE rule (80 % health, can neither act nor move; ten repairs to finish a laboratory, fifteen a watchtower), the TURRET/PORTABLE transform and its 100 cooldown, and the level-2/level-3 mutation ladder |
| `anomalies` | all four global bodies with their **exact truncated arithmetic** — ABYSS's rounded-down 10 %, CHARGE's top 5 % of *all* droids by friends-visible over *both* teams (and its zero at 19 droids or fewer), FURY's TURRET-only 5 %, VORTEX's rubble permutation — plus the three sage versions and the fact that VORTEX is not one of them |
| `comms` | 64 slots, 0…65535, and the note that a write is legal for **any robot, any time, no cooldown, no range test and no cost** (which is *not* true in 2023) |
| `win` | destroy the last enemy archon, then the four-rung Singularity ladder, and the note that there is **no elimination** for losing droids |
| `sheet_schema` | the eleven knobs, their values, ranges and defaults, generated from `knobs.nim` |
| `scoring` | the 64/24/12 weights, the 200-per-game win bonus, and the note that the league ranks by `scores` |

**Hidden**, always: the opponent's doctrine, sheet, notes and motto (sealed and
simultaneous — never sent, in either direction, at any time); the opponent's
real player name; every in-match state; the other seat's fallback status.

### The bc22 reply

The same envelope every year uses — `{"sheet": {...}, "notes": "...",
"motto": "..."}` — with the eleven knobs of `docs/RULES-BC22.md`. Unknown key,
wrong type or out-of-range value takes that field's default and is recorded;
the five INTEGER knobs (`soldier_sage_ratio`, `lab_round`, `lab_solitude`,
`mine_floor`, `retreat_hp`) **clamp** to their range instead, so "as much as
possible" still means something. A sheet can never be rejected. **There is no
`chassis` key**: a submitted one is recorded in `sheet_unknown_fields` and
never honoured.

### `sheet_envelope`

Every year's `results.games[]`/replay now carries a `sheet_envelope` object —
the year-neutral resolver in `src/battlecode/sheet.nim` — recording, per seat,
how the reply was obtained (`llm`, `fallback`, `scripted`), how many fields
were defaulted, how many clamped and how many were unknown. It is in the bc22
manifest's `required` list and in `tools/ci/docker_smoke.sh`'s `CLOSED_KEYS`,
so a year that stops emitting it fails the smoke.

## bc16

`game_config.year = "bc16"` selects Battlecode 2016 "Zombie Invasion". The
protocol id is **unchanged** (`cogame.battlecode.v1`): the wire shape is
identical and only the year-dependent *payload* differs, so every existing
bc20, bc21, bc22, bc23, bc24, bc25 and bc26 consumer keeps working without
re-registering. The `game_version` in the envelope is **`GV11`**; `GV10` and
every earlier value stay in `ReplayCompatibleGameVersions`, so an older replay
still loads.

### The bc16 observation

One sealed one-shot brief per seat, recorded verbatim in the replay. There is
**no per-round observation of any kind**: one doctrine, then the invasion.

On top of the year-neutral envelope (`protocol`, `game_version`, `year`,
`slot`, `alias`, `opponent_alias`, `team`, `seed`, `games`, `budget`) a bc16
brief carries:

| key | what it says |
|---|---|
| `games[].you_are` / `your_archons` / `enemy_archons` | which side this seat plays and both factions' archon spawns. They are PUBLIC: every map is symmetric and the engine's own map file puts them there |
| `games[].symmetry` | `rotational`, `horizontal` or `vertical` (20, 1 and 1 of the 22 maps respectively) — the engine's own `GameMap.getSymmetry()`, computed at build time and cross-checked against the JVM in `parity-oracle-bc16` |
| `games[].rounds_are_zero_based` | **`true`.** 2016 counts rounds from 0 and the tiebreak fires at the end of round 2999, not 3000. Stated in as many words because every other year in this repo counts from 1 |
| `games[].start_separation` | the shortest Euclidean distance between an A archon and a B one |
| `games[].terrain` | `rubble_mean`, `rubble_max`, `impassable_squares`, `total_squares`, `squares_over_50_rubble_pct`, and the note that rubble ≥ 100 is impassable *except* to SCOUT, FASTZOMBIE and BIGZOMBIE, and rubble ≥ 50 doubles every delay charge |
| `games[].parts` | the parts squares, their total, the richest one, the nearest to this seat, and the note that **only an ARCHON collects**, whole-square, and it never regenerates |
| `games[].dens` | `count`, `per_side`, `health_each` (2000), `bounty_each` (200), every den's location, and `zombies_queued_each_over_the_game` |
| `games[].zombie_schedule` | **the full public schedule, round by round and type by type.** `RobotController.getZombieSpawnSchedule()` is public to every robot at all times in the real game, so it is public here |
| `games[].schedule_note` | that those are WHOLE-MAP counts split as evenly as possible among the dens, that a den spawns at most 8 per attempt and 16 per round, and that a den with a stuck queue damages every adjacent non-zombie for 10 first |
| `games[].neutrals` | the neutral total, the roster by type, the nearest one, and that an ARCHON activates within r² ≤ 2 for **zero parts** and 2 core delay — and that a neutral ARCHON is a whole extra tiebreak rung |
| `games[].tiebreak_round` | 2999 |
| `economy` | 300 parts at round 0, `max(0, 2 − 0.01 × your live robot count)` per round — **zero income at 200 robots** — the 200-parts den bounty, and that map parts are archon-collected only |
| `units` | all seven player types with exact parts cost, build turns, health, attack, radii, both delays, and **`turns_into`**: what each becomes if it dies infected. The ARCHON entry states the free once-a-turn 1 hp repair within r² ≤ 24 and that it is FROZEN for the whole of a unit's build |
| `zombies` | the HORDE as a third team that never wins and never scores; that **every zombie, every turn, walks at the nearest player robot of EITHER team and sees the whole map**; all four zombie types; the ten-step outbreak multiplier ladder every 300 rounds; and the den's spawn ring |
| `infection` | 10 turns and no damage from a zombie bite, 20 turns at 2 damage from a VIPER, and the conversion rule: an infected robot leaves **no rubble**, stands back up as a zombie of its own `turns_into` at the current outbreak multiplier, and hunts whoever is nearest |
| `rubble` | impassable at 100, doubles at 50, a corpse deposits its own **max health** (a third of that if a TURRET landed the killing blow), and `max(0, 0.95r − 10)` per clear |
| `signals` | 5 basic and 20 message signals a turn, MESSAGE senders are **ARCHON and SCOUT only**, 0.05 delay on both counters inside twice your sight radius plus 0.03 per unit beyond it, a 1000-deep queue — and that **there is no shared array in 2016 and every signal is heard by the enemy too** |
| `win` | destroy the enemy's last ARCHON, then the four-rung round-2999 ladder, and the note that **there is no elimination for losing your army** |
| `sheet_schema` | the eleven knobs, their values, ranges and defaults, generated from `knobs.nim` |
| `scoring` | the 64/24/12 weights, the **200**-per-game win bonus, and the note that the league ranks by ELO |

**Hidden**, always: the opponent's doctrine, sheet, notes and motto (sealed and
simultaneous — never sent, in either direction, at any time); the opponent's
real player name; every in-match state; the other seat's fallback status.

### The bc16 reply

The same envelope every year uses — `{"sheet": {...}, "notes": "...",
"motto": "..."}` — with the eleven knobs of `docs/RULES-BC16.md`. Unknown key,
wrong type or out-of-range value takes that field's default and is recorded;
the four INTEGER knobs (`turret_count`, `guard_ratio`, `den_clear_round`,
`retreat_hp`) **clamp** to their range instead, so "as many as possible" still
means something. A sheet can never be rejected. **There is no `chassis` key**:
a submitted one is recorded in `sheet_unknown_fields` and never honoured.

bc16 joins bc22 as the second — and only other — year that also records an
**absent** known key in `sheet_defaults_applied`. Doing that year-neutrally
would change what a bc20/bc21/bc23/bc24/bc25/bc26 episode records in that
array, so it is per-year by construction and `tests/test_sheet.nim` asserts
both halves.


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
