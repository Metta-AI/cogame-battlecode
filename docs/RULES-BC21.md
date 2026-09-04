# Battlecode 2021 "Campaign" — the `bc21` year module

The `bc21` variant of this coworld is a deterministic Nim port of the
Battlecode 2021 rule set, played by **doctrine**: each of the two cogs writes
one sealed JSON sheet of ten knobs at t=0 and the simulation plays the whole
best-of-three from those two sheets.

Everything below was read out of `github.com/battlecode/battlecode21` at commit
**`ed39c1a49574db57e5463d720736220506280294`** (release **2021.3.0.5**, the last
of the season), file by file. Where the spec's prose and the engine disagree,
**the engine wins** and the disagreement is recorded here.

The Java engine exists in this repository **only** as the `parity-oracle-bc21`
CI job. There is no JDK, no JRE, no Java and no Node in any image stage.

---

## The world

Two clans on a symmetric grid between 32×32 and 64×64. Four robot types:

| type | spawned by | conviction ratio | action cooldown | initial cooldown | action r² | sensor r² | detection r² | true sense | bytecode limit |
|---|---|---|---|---|---|---|---|---|---|
| `ENLIGHTENMENT_CENTER` | — (the map) | 1.0 | 2.0 | 0 | 2 | 40 | 40 | yes | 20 000 |
| `POLITICIAN` | EC | 1.0 | 1.0 | **10** | 9 | 25 | 25 | no | 15 000 |
| `SLANDERER` | EC | 1.0 | 2.0 | 0 | 0 | 20 | 20 | no | 7 500 |
| `MUCKRAKER` | EC | **0.7** | 1.5 | **10** | 12 | 30 | **40** | yes | 15 000 |

Game constants: `EMPOWER_TAX 10`, `EXPOSE_BUFF_FACTOR 0.001` (a `double`),
`EXPOSE_BUFF_NUM_ROUNDS 50`, `EMBEZZLE_NUM_ROUNDS 50`,
`EMBEZZLE_SCALE_FACTOR 0.03f`, `EMBEZZLE_DECAY_FACTOR 0.001f`,
`CAMOUFLAGE_NUM_ROUNDS 300`, `INITIAL_ENLIGHTENMENT_CENTER_INFLUENCE 150`,
`PASSIVE_INFLUENCE_RATIO_ENLIGHTENMENT_CENTER 0.2f`,
`ROBOT_INFLUENCE_LIMIT 100 000 000`, `MIN_FLAG_VALUE 0`,
`MAX_FLAG_VALUE 16 777 215`, `MAP_MIN/MAX_WIDTH/HEIGHT 32 / 64`,
**`GAME_MAX_NUMBER_OF_ROUNDS 1500`**. There is no `MAX_ROBOT_ID` in 2021: the
declaration is commented out in `GameConstants.java` because conversions mint
new ids. `src/battlecode/years/bc21/constants.nim` is **generated** from those
two files by `tools/gen_year_constants.py --year bc21` and byte-diffed in CI.

Derived:

```
convictionAtSpawn(type, C) = ceil(convictionRatio * C)
cooldownAdded(type, tile)  = actionCooldown / passability(tile)     # a double
ecPassive(t)               = ceil(0.2f * sqrt(t))
slandererPassive(x, alive) = alive <= 50 ? floor(x * (1/50 + 0.03f * e^(-0.001f x))) : 0
buff(team)                 = 1 + 0.001 * numBuffs(team)
```

### Which patch, and the 3000-round question

The spec's §Victory prose still says "at the conclusion of 3000 rounds". It is
**stale**. Patch **2021.2.3.0 (2021-01-13)** reduced the cap to 1500, and the
engine agrees: `GameConstants.GAME_MAX_NUMBER_OF_ROUNDS = 1500`,
`GameMapIO.Serial.deserialize` sets every map's `rounds` from that constant, and
`GameWorld.timeLimitReached()` is `currentRound >= gameMap.getRounds()`. **This
port plays 1500 rounds**, and round 1500 IS played.

The season's other pinned patch is **2021.3.0.0 (2021-01-22)**: the muckraker
buff became **linear** (`1 + 0.001·n`, not `1.01^n`), it no longer applies to
friendly Enlightenment Centers, and empowering is **taxed before** the buff is
applied. All three are in the pinned source and all three are implemented.

---

## The round loop

`src/battlecode/years/bc21/rules.nim`'s `runRound` mirrors `GameWorld.runRound`
step for step. **The step list IS the rules**: re-ordering any of it is a rules
change and bumps `GameVersion`.

1. **Beginning of round.** `currentRound += 1`; then buff expiry — every batch
   whose recorded expiry round is `<= currentRound` is subtracted from
   `numBuffs` and dropped (`TeamInfo.updateNumBuffs`); then every robot's
   `processBeginningOfRound`, a no-op in 2021, kept as a named step because the
   hash chain and the parity trace are taken around it.
2. **Turn order.** The robots in **spawn order**
   (`ObjectInfo.eachDynamicBodyByExecOrder`), over a **snapshot of the order
   taken once at the start of the sweep**. A robot spawned or converted during
   the sweep takes **no turn** that round; one destroyed during it is skipped.
   Map bodies are appended in the map file's own body-id order (`LiveMap`'s
   constructor sorts `initialBodies` by id).
3. **Beginning of turn.** `if cooldownTurns > 0: cooldownTurns = max(0, cooldownTurns - 1)`,
   and the robot's `DecisionOps` budget is reset.
4. **Run the controller.** A robot may take an **action** only while
   `cooldownTurns < 1`, and every action adds
   `actionCooldown / passability(the robot's CURRENT tile)` **before** the
   action's effect — for a move that means the cooldown is charged at the tile
   being left. The legal actions:
   1. **Move** (politician, slanderer, muckraker) — one of the 8 adjacent
      tiles, on the map, unoccupied, ready. No terrain blocks movement;
      passability only changes the cooldown.
   2. **Build** (EC → politician | slanderer | muckraker) — ready;
      `1 <= influence <= this EC's influence`; the target one of the 8 adjacent
      tiles, on the map, unoccupied. In order: charge the cooldown, deduct the
      influence, mint an id, spawn with `conviction = ceil(ratio × influence)`
      and `convictionCap = conviction`, append to the exec order, then
      `setCooldownTurns(initialCooldown)`.
   3. **Empower** (politician, `r² <= 9`) — see below.
   4. **Expose** (muckraker) — ready; the target on the map, within `r² <= 12`,
      an **enemy slanderer**. Charge the cooldown, add the slanderer's
      **influence** to this team's pending buffs, destroy the slanderer. A
      slanderer that has already camouflaged is a politician and cannot be
      exposed.
   5. **Bid** (EC, any number of times per turn) — **not an action**: no
      readiness check, no cooldown. The previous bid is refunded and the new one
      **deducted immediately**, so bidding reduces what the Center can build
      that same turn.
   6. **Set flag** (any robot) — **not an action**. `0 <= flag <= 16 777 215`.
   7. **Sense / detect / read flags** — free, charged only against
      `DecisionOps`. **Politicians and slanderers see slanderers as
      politicians**; only Centers and muckrakers true-sense. A muckraker's
      detection radius (40) exceeds its sensor radius (30). Flags are readable
      **across teams**, at any range for an Enlightenment Center in either
      direction.
5. **End of turn.** `roundsAlive += 1`.
6. **End of round.** In this order:
   1. **Collect bids and pay the economy.** One sweep over every robot: for a
      player-team Center record the bid and `resetBid()` (which refunds it);
      then that robot's `processEndOfRound` — passive influence into
      `parent ?: self` (nothing if the parent no longer exists, so **capturing
      a Center cuts off the income of every slanderer it built**), and
      camouflage at exactly `roundsAlive == 300`. The top bidder per team is the
      maximum under **(bid desc, `roundsAlive` asc, id asc)** — exactly
      `InternalRobot.compareTo`.
   2. **Settle the auction.** If one team's top bid is strictly higher and
      positive, that team wins the vote and its bidder pays in full. **Every
      team that did not win pays `(bid + 1) / 2` for nothing.** Equal top bids
      (including both zero) give the vote to **nobody** and charge both halves.
      Neutral Centers never bid.
   3. **Apply exposes.** `numBuffs += buffsToAdd`, recorded with expiry
      `currentRound + 1 + 50`. A buff therefore first affects speeches on
      `currentRound + 1` and is dropped at step 1 of round `currentRound + 51`.
   4. **End-of-match check**, first hit wins: **annihilation** (a double wipe
      awards the win to **B** — the engine tests A's count first), then, at
      `currentRound >= 1500`, **more votes** → **more Enlightenment Centers** →
      **higher total influence over all living non-neutral robots** → **coin
      flip**.
7. **Hash chain.** Per team: votes, `numBuffs`, Centers owned, total influence,
   living politicians, slanderers and muckrakers, and units built; plus the
   round number, the total robot count and the highest live robot id.

### Empower, in order

1. charge the cooldown;
2. collect every robot within `r²` in **map-scan order** — `x` ascending outer,
   `y` ascending inner, over the clamped bounding box of side
   `2·(ceil(√r²)+1)+1`, keeping tiles with `distanceSquared <= r²`. **This order
   is load-bearing**: it fixes the order conversions are queued and therefore
   the ids they are re-spawned with;
3. `numBots = |collected| - 1`. **If 0, nobody is affected — and the politician
   still dies**;
4. `convictionToGive = conviction - 10` as a `double`. **If `<= 0`, nobody is
   affected — and the politician still dies**;
5. `convictionPerBot = convictionToGive / numBots`; `buff` read **once**;
6. per target: a **friendly Center** takes the split **unbuffed**; **any other
   Center** takes `convictionPerBot × buff` if that is at or below
   `conviction / buff`, else `conviction + (convictionPerBot − conviction/buff)`
   — the buff applies only up to the point of conversion and the overflow
   crosses unbuffed; **everything else** takes `convictionPerBot × buff`;
7. `empowered(caller, (int) conv, ownTeam)` — **truncation toward zero**;
   negated for a robot not on the caller's team. A Center takes
   `addInfluenceAndConviction`; everything else takes `addConviction`, **capped
   at its conviction at spawn — healing above the cap is lost**. A negative
   result **converts** a politician or a Center (`newInfluence = |influence|`,
   `newConviction = -conviction`) and simply **destroys** a slanderer or a
   muckraker;
8. the queued conversions are spawned **in queue order**, on the empowering
   politician's team, each keeping the destroyed robot's **old parent pointer**,
   with a **new id** and **cooldown 0**.

### Deliberate non-rules

Verified absent from the 2021 engine and therefore absent here: no global
message board (flags are the only channel), no terrain that blocks movement, no
unit cap, no player-callable self-destruct (`disintegrate` is private in 2021),
no cows and no NPCs of any kind, no map symmetry field and no engine use of
symmetry, and no transaction-id RNG quirk —
`RobotControllerImpl`'s static `java.util.Random` is assigned on every
controller construction and then **never read**.

---

## The doctrine sheet — ten knobs, and no `chassis` key

Unknown key, wrong type or out-of-range value takes **that field's default** and
the repair is recorded. A sheet can never be rejected. **Every setting of every
knob drives the same competent chassis**: the chassis always builds, always
defends its own Centers, always paths and always ends its games.

| field | type / values | default | what it changes |
|---|---|---|---|
| `opening` | `muck_spam` \| `slanderer_turtle` \| `balanced` | `balanced` | the build order for rounds 1…150 |
| `slanderer_ratio` | int 0…100 | 45 | % of post-opening build influence to slanderers |
| `muck_ratio` | int 0…100 | 25 | % to muckrakers; politicians take the rest |
| `politician_size_curve` | `cheap` \| `ramp` \| `fat` | `ramp` | 18 flat / `clamp(18 + round/25, 18, 120)` / `clamp(40 + round/8, 40, 400)` |
| `bid_policy` | `never` \| `fixed` \| `proportional` \| `escalate_when_ahead` | `proportional` | the auction |
| `expansion` | `neutral_centers_first` \| `defend_home` | `neutral_centers_first` | what a capture politician aims at |
| `flank_policy` | `screen_home` \| `hunt_slanderers` \| `flank_wide` | `hunt_slanderers` | where the muckrakers go |
| `empower_threshold` | int 0…300 (percent) | 60 | when a politician speaks |
| `convert_over_kill` | bool | `true` | what a speech is FOR |
| `eco_exponential_round` | int 1…1500 | 700 | the round compounding stops |

If `slanderer_ratio + muck_ratio > 100` they are renormalised deterministically:
`s' = s·100 div (s+m)`, `m' = 100 − s'`, politicians 0.

`tests/test_bc21_knobs.nim` is a CI gate that proves each of the ten visibly
changes play, with a named signed delta per knob.

---

## The two chassis

* **`california-roll`** — the strong published doctrine and the champion
  chassis, ported from the **behaviour** of `StoneT2000/Battlecode2021`
  `src/maxecosushi/` with the muck-spam opening from
  `iliao2345/Battlecode2021` and the multi-Center flag protocol from
  `BSreenivas0713/Battlecode2021`, all parameterised by the ten knobs.
* **`examplefuncsplayer21`** — the deliberately weak floor and the parity
  oracle's other side, ported **statement for statement** from
  `example-bots/src/main/examplefuncsplayer/RobotPlayer.java`. **It may not gain
  behaviour.**

`PLAYER_SCRIPTED` resolves per year: on `bc21`, `awu` (or anything
unrecognised) is `california-roll` and `scaffold` is `examplefuncsplayer21`. The
manifest declares only the two ids the certification fixture seats.

### The flag word

One 24-bit word, `[kind:3][x:6][y:6][payload:9]`, with kinds `SILENT`,
`NEUTRAL_EC_HERE`, `ENEMY_EC_HERE`, `SLANDERER_SEEN`, `UNDER_ATTACK`,
`SCOUT_DONE`, `EC_INFLUENCE_HINT`, `NEED_DEFENCE`. **Shared by both teams**,
deliberately: it reproduces the year's flag-decoding metagame and it is what
lets the endcard decode both sides' traffic. A doctrine cannot redefine it.

---

## Scoring

```
survival[t]  = f32(alive[t])      / f32(max(1, alive[A] + alive[B]))
share_v[t]   = f32(votes[t])      / f32(max(1, votes[A] + votes[B]))
share_c[t]   = f32(centers[t])    / f32(max(1, centers[A] + centers[B]))
share_i[t]   = f32(influence[t])  / f32(max(1, influence[A] + influence[B]))
points[t]    = int(40*survival + 35*share_v + 15*share_c + 10*share_i)
results.scores[t] = 100 * (games won) + mean(points over games played)
```

Every share narrows through **float32** and the sum **truncates**, because the
same arithmetic runs natively on x86-64 and in wasm32 and must produce the same
integer. The four terms are the engine's four rungs in the engine's own priority
order. Higher is better; the 100-per-game win bonus dominates.

`results.games[].end_reason` is the engine's `DominationFactor` in snake_case —
`annihilated`, `more_votes`, `more_enlightenment_centers`, `more_influence`,
`coin_flip` — plus our own wall-clock `abandoned`.

---

## Maps

**18 of the 76 official maps** are converted by `tools/convert_maps_bc21.py`
from the pinned `.map21` flatbuffers and **committed**; CI re-converts and
diffs. `mixed` (12) is the `bc21` variant's pool, `small` (6) is what the parity
oracle and the docker smoke run on, `large` (6) is reserved.

**Two maps are excluded on purpose:**

* **`Cow`** — 80×50, which violates the spec's own `MAP_MAX_WIDTH/HEIGHT = 64`
  and which patch 2021.2.4.0 removed from scrimmages ("Exclude map Cow from
  scrimmages as it is too large");
* **`Misdirection`** — 50×50, but **two of its 2 500 tiles have passability
  exactly 0.0**. `actionCooldown / 0.0` is infinite, so a robot that steps onto
  one is frozen for the rest of the game. That is legal, it is reproduced
  (`tests/test_bc21_cooldown.nim`), and it is not a map anyone should be scored
  on.

The remaining 56 are simply not converted in v1; the converter handles any
`.map21`.

`Hourglass` and `Maze` are also **bc20** map names — different maps, different
years, different directories (`data/maps/bc21/` vs `data/maps/bc20/`), and
`tests/test_bc21_maps.nim` asserts the two are not confusable.

---

## §Divergences

Every difference between this port and the pinned engine, with its reason.

1. **No bytecode instrumentation.** `RobotType.bytecodeLimit` has no meaning
   outside the JVM instrumenter. It is replaced by a fixed per-robot
   **`DecisionOps`** budget at one tenth of the Java limit — Enlightenment
   Center 2 000, politician 1 500, muckraker 1 500, slanderer 750 — charged for
   each tile sensed or detected, robot examined, BFS node expanded, direction
   evaluated, flag read and empower radius scored, and **enforced by the sim,
   not by the bot**. When the budget reaches zero the robot's turn ends where it
   stands; it is **not** resumed mid-computation next turn, which is the one
   place this differs from the JVM. The `parity-oracle-bc21` job **measures**
   that boundary rather than asserting it away: `tools/oracle/bc21/Bc21Trace.java`
   carries each Java robot's `getBytecodesUsed()`, prints the peak use per map
   and prints the first round the JVM cut a robot off mid-turn
   (`BC21_FIRST_CUTOFF`), and `tools/ci/parity_tiers_bc21.py` makes
   `cutoff - 1` the Tier A bit-exact window — the engine's own answer to how
   long the comparison is defined for. On the pinned `examplefuncsplayer21`
   the boundary **is** reached: peak use is **102 %** of the limit on all five
   traced maps (the Center's out-of-influence `rc.bid(1)` throws and the
   uncaught exception's stack trace costs more than a whole turn's budget),
   with the first cut-off at rounds 27, 23, 33, 23 and 246. Everything after
   the window is governed by the Tier C ledger, not by this item;
   `docs/PARITY.md` accounts for it map by map.
2. **`setWinnerArbitrary`'s `Math.random()`** is wall-clock seeded and therefore
   not reproducible. It is replaced by a draw from the **world RNG**, which is
   seeded from the map's own `randomSeed`. Reachable only when votes, Center
   counts and total influence are all tied at round 1500.
3. **`Math.exp` in the embezzle formula** is a HotSpot intrinsic and is allowed
   to differ from the reference by 1 ulp; the platform libm this port would
   otherwise link is a different function natively and under emscripten. Three
   mechanisms: `src/battlecode/fdlibm.nim` is the reference `exp` bit for bit;
   `data/bc21/embezzle.json` commits the resulting integer income for every
   influence in `[1, 4096]` and the sim reads the table there; and the CI job
   regenerates both tables under JDK 8 and byte-diffs them, and compares Java
   against Nim for 4 096 log-spaced values in `(4096, 1e8]`.
4. **The end-of-round sweep is in ascending robot id**, not the engine's
   `TIntObjectHashMap` hash order, which is not reproducible outside the JVM.
   This is a **provable** non-divergence: the sweep does exactly four things and
   each is order-independent. (a) `resetBid` refunds a robot's own held
   influence. (b) Top-bidder selection is a maximum under the total order (bid
   desc, `roundsAlive` asc, id asc), and the engine's update predicate is
   exactly that maximum. (c) Passive influence is an addition into a parent's
   counter — commutative, **except** at the `ROBOT_INFLUENCE_LIMIT = 10⁸` clamp.
   (d) Camouflage depends only on the robot's own `roundsAlive`. Item (c) is the
   only exposure: `tests/test_bc21_economy.nim` asserts the clamp is never
   reached in any gate game, and `rules.nim` raises a `fault` if it ever is.
5. **The spec's stale "3000 rounds" prose** is superseded by the engine's
   `GAME_MAX_NUMBER_OF_ROUNDS = 1500` (patch 2021.2.3.0). Both readings are
   recorded above.
6. **Map origin offsets are recorded but inert.** The engine works in absolute
   coordinates offset by `minCorner`; this sim is 0-based. The `.map21` body
   coordinates are already origin-relative (`GameWorld`'s constructor is what
   translates them), so the two agree tile for tile. `origin` is carried in the
   converted JSON for provenance.
7. **No indicator dots or lines, no profiler, no crossplay, no `.bc21`
   output.** None of them exist in the port, and none of them can affect a
   simulation.
8. **The `deadline` wall-clock stop** is a coworld concept and not an engine
   one. It is recorded as ONE load-bearing record (`plan.abandonAfter[g]`)
   applied by the same proc on record and on playback.
9. **Both chassis are behaviour ports** parameterised by the doctrine sheet, not
   transcriptions — except `examplefuncsplayer21`, which is statement for
   statement and may not gain behaviour.
10. **18 of the 76 official maps** are converted, with `Cow` and `Misdirection`
    excluded for the reasons above.
11. **Two chassis behaviours that are ours, not the engine's**, both in
    `chassis/bids.nim`: a 0…2 influence **jitter** on every bid, taken from a
    multiplicative hash of the Center's id and the round
    (`(((id xor round·0x9E3779B1)·0x85EBCA6B) >> 13) mod 3` — a *sum* of id and
    round has a constant difference between two Centers, so ids congruent
    mod 3 would tie every round), and a **bid bank** of `15 + round/10`
    influence (capped at 150) held out of the build budget. A perfect mirror match on a
    symmetric map otherwise produces identical bids on both sides for hundreds
    of rounds, equal top bids give the vote to nobody, and the auction — the
    clock of the whole game — stops meaning anything. Both are deterministic in
    the Center's id and the round, and neither is a rule: they are how *this*
    chassis chooses to bid, exactly as `empower_threshold` is how it chooses to
    speak.
12. **The chassis steers by a symmetry the converter did not choose for it.**
    `tools/convert_maps_bc21.py` records every transform under which the
    passability array and the Centers agree, comparing type and influence but
    **not team** — which is right, because `Corridor` is 33 wide with both
    Centers on the centre column and mirrors vertically onto itself.
    `world.newWorld` then picks, for the chassis, the first recorded symmetry
    that maps an OWN Center onto an ENEMY one. The 2021 engine never uses
    symmetry for anything, so neither choice can affect a rule.
13. **`map_card.passability.swamp_pct`** is the percentage of tiles below
    passability 0.5. The 2021 engine has no terrain categories at all, only the
    passability number; the bucket is this coworld's, for the doctrine brief.
