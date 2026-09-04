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
{"protocol":"cogame.battlecode.v1","game_version":"GV02","year":"bc26",
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
{"sheet":{"chassis":"awu","backstab_policy":"at_round_N","backstab_round":700,
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
| `GET /global` | phase, seat registration, and the results document once it exists |
| `GET /player?slot=N&token=…` | the seat websocket |
| `GET /client/global`, `/client/player` | a one-paragraph page saying the watchable artifact is the recorded replay |

There is deliberately **no `/client/replay` live viewer**: the replay is a
static file re-derived by the wasm bundle in the browser.
