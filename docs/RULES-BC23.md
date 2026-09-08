# Battlecode 2023 "Tempest" — the `bc23` year module

`game_config.year = "bc23"` selects this module. It is a behaviour port of
`github.com/battlecode/battlecode23` at commit
**`af42086ecd09709dc603b2aaa9e9b98312c9ef79`** (`master`, last commit
2023-02-05), and the port is the authority at runtime: the Java engine exists
only as the `parity-oracle-bc23` CI job (`docs/PARITY.md` §bc23).

Nothing about `bc26`, `bc20`, `bc21`, `bc24` or `bc25` changes.
`GameVersion` went **GV08 → GV09** in the commit that added this module and
`ReplayCompatibleGameVersions` was **extended** to
`["GV04","GV05","GV06","GV07","GV08","GV09"]`, never reset, so every hosted
replay of the five shipped years keeps rendering.

Layout: `src/battlecode/years/bc23/`
(`constants.nim` generated, `units.nim`, `tempo.nim`, `wells.nim`,
`islands.nim`, `world.nim`, `currents.nim`, `comms.nim`, `rules.nim`,
`maps.nim`, `knobs.nim`) plus
`src/battlecode/years/bc23/chassis/`
(`kit.nim`, `econ.nim`, `hq.nim`, `carrier.nim`, `launcher.nim`, `micro.nim`,
`anchors.nim`, `elixir.nim`, `amplifier.nim`, `comms.nim`, `lemonade.nim`,
`scaffold23.nim`, `scenario23.nim`).

## The game in one paragraph

Two factions of robots on a symmetric grid between 20×20 and 60×60. Each
starts with 1 to 4 **indestructible headquarters**, each with its own
stockpile. **Carriers** (50 Ad, 150 HP, capacity 40) mine 1 kg per action
from a well they stand on or beside, walk it home and hand it to a
headquarters; their movement cooldown is `floor(5 + 3m/8)` in their own cargo
weight, so a full carrier is a quarter the speed of an empty one, and they can
**throw** their whole cargo for `floor(5m/4)` damage — up to 50 — losing it
whether they hit or not. **Launchers** (45 Mn, 200 HP) hit one square within
r² ≤ 16 for 20 damage, *even a robot they cannot see*, and are the only unit
in the game that deals real damage. **Amplifiers** (30 Ad + 15 Mn) are what
let an ordinary robot *write* the faction's 64-slot shared array. Pour
**600 kg of the OPPOSITE resource** into a well and it becomes an **elixir
well**; elixir buys **destabilizers** (200), **boosters** (150) and
**accelerating anchors** (300). You win by conquering **75 % of the sky
islands**: a headquarters builds an anchor, an **empty** carrier ferries it —
an anchor weighs the carrier's whole capacity — and plants it while standing
on the island; every round the anchor's health moves by
`(% of island tiles you occupy) − (% they occupy)`, so holding one is a
garrison problem. Nobody conquering by round 2000 means a five-rung ladder:
islands held, anchors ever placed, elixir, mana, adamantium, coin flip.
**There is no elimination condition at all.**

## The round loop

`rules.nim runRound` mirrors `GameWorld.runRound` /
`processBeginningOfRound` / `updateDynamicBodies` / `processEndOfRound` step
for step. THE STEP LIST IS THE RULES: a re-ordering is a rules change and
bumps `GameVersion`.

1. **Beginning of round.** `currentRound += 1`; then
   `processBeginningOfRound` on every robot, which **clears the indicator
   string and nothing else** — this port has no indicator strings, so step 1b
   has no observable effect and no code. Then, **on round 1 only**, walk the
   exec order and give **each** headquarters `+200` adamantium and `+200`
   mana, into that headquarters' own stockpile *and* the team total. A map
   with three headquarters a side therefore starts at 600/600. The engine
   throws if any round-1 body is not a headquarters; so does the port.
2. **Turn order.** `ObjectInfo.dynamicBodyExecOrder`: append on spawn,
   **by-value removal** on death preserving the survivors' order, and the
   array iterated is a **snapshot taken before the sweep**, so a robot built
   this round takes no turn this round and a robot destroyed mid-sweep is
   skipped by the `existsRobot` guard. The initial headquarters are in
   **ascending id**, because `LiveMap`'s constructor sorts them.
3. **Each robot's turn.** Both cooldowns decay by 10 and floor at 0; the
   `DecisionOps` budget resets; the chassis runs; `roundsAlive += 1`; a robot
   that disintegrated is destroyed at the end of its own turn. Both cooldowns
   start a robot's life at 10, so a robot built this round can neither move
   nor act on its first turn even after the decrement. **A HEADQUARTERS ACTS
   FIVE TIMES IN ONE TURN** (cooldown 2 against a limit of 10, and
   `isActionReady` is `< 10`), which is a load-bearing rule and not a
   curiosity.
4. **End of round**, in exactly this order:
   1. every island advances a turn, in **ascending island id**;
   2. boosts and destabilisations expire, over the **whole map** in the
      engine's own location order (x ascending outer, y ascending inner),
      **team A then team B**, and each expiring destabilisation deals 50 to
      whatever robot **of that team** stands on the tile;
   3. every robot's end of round — for a **headquarters only**: 4 damage to
      every enemy within r² ≤ 9, and every fifth round +6 adamantium and +6
      mana;
   4. currents apply (`round % CURRENT_STRENGTH == 0`, i.e. **always**);
   5. the end-of-match ladder;
   6. `running = false` if a winner is set; then the per-round state hash.

### The charge order is NOT uniform, and it matters

* `move` charges **after** the move, at the **destination** tile — so a robot
  stepping into a cloud pays the cloud's 20 % on the very step that enters it;
* `buildRobot`, `buildAnchor`, `attack`, `collectResource` and
  `transferResource` charge **before** their effect;
* `boost`, `destabilize`, `takeAnchor`, `returnAnchor` and `placeAnchor`
  charge **after** it — so a booster's own 140 is discounted by the boost it
  just cast, and a destabilizer's 70 is not (it slows the *enemy*).

## The twelve doctrine knobs

`knobs.nim` owns the table and `decide.nim` puts it in the prompt.

| field | type / values | default |
|---|---|---|
| `opening` | `launcher_rush` \| `carrier_eco` \| `balanced` | `balanced` |
| `launcher_ratio` | int 20…80 | 45 |
| `well_priority` | `adamantium` \| `mana` \| `balanced` | `balanced` |
| `elixir_tech` | `never` \| `mid` \| `early` | `mid` |
| `elixir_spend` | `accelerating_anchors` \| `boosters` \| `destabilizers` | `accelerating_anchors` |
| `anchor_round` | int 1…1800 | 400 |
| `anchor_budget` | int 0…100 | 35 |
| `island_priority` | `nearest` \| `contested` \| `safe` | `nearest` |
| `amplifier_use` | `never` \| `one` \| `escort` | `one` |
| `destabilizer_use` | `hold` \| `defend` \| `siege` | `defend` |
| `retreat_on_launcher_loss` | `never` \| `regroup` \| `home` | `regroup` |
| `carrier_throw` | int 0…100 | 25 |

**There is no `chassis` key (D1).** A submitted `chassis` is recorded in
`sheet_unknown_fields` and never honoured. The four integer knobs **clamp**
to their range rather than defaulting; a non-integer defaults. `well_priority`
deliberately has **no `elixir` value**: no official map contains an elixir
well at round 0 (measured across all 103), so `elixir_tech` already owns that
decision.

**The anti-inert rule.** Independently of every knob the chassis always keeps
at least three carriers per headquarters mining **and depositing**, builds a
launcher whenever mana allows and the census is short of two, spends a
headquarters' spare actions, answers an enemy launcher sensed near one of its
own headquarters, steps a loaded carrier off a current that would carry it
away from home, and takes a lethal carrier throw inside r² ≤ 9 at every
setting. `tests/test_bc23_knobs.nim` proves each knob has teeth and
`tests/test_bc23_survival.nim` proves the floor holds — **with a negative
control behind `-d:bc23BrokenChassis` that must come back red.**

## Scoring

```
share(x, y)   = if x + y == 0: 0.5'f32 else: f32(x) / f32(x + y)
points[t]     = int(60 * share(islands) + 22 * share(anchors ever placed)
                  + 10 * share(elixir) + 5 * share(mana)
                  +  3 * share(adamantium))          # TRUNCATION
results.scores[t] = 200 * (games t won) + mean(points[t] over games played)
```

The five terms are the engine's five deciding rungs in the engine's own
priority order, and **the weights are strictly super-increasing from the
bottom** (`22 > 10+5+3`, `10 > 5+3`, `5 > 3`, `60 > 40`), which makes the
tiebreak property provable: a win on any rung always comes with the winner's
`points` strictly above the loser's. A `conquest` win can legitimately carry
**fewer** points than the loser — `points` measures the *shape* of the game —
which is why `results.scores` carries the 200-per-game win bonus and is what
the league ranks.

## Divergences

Every one of these is a place the port deliberately does not match something,
with the reason. Nothing here is a bug list.

1. **No bytecode instrumentation.** The engine's per-robot bytecode limits
   (`HEADQUARTERS` 20 000, `CARRIER` 12 500, everything else 10 000) have no
   meaning outside the JVM instrumenter and are replaced by a fixed per-robot
   **`DecisionOps` budget of 2 000 / 1 250 / 1 000** — one tenth of the Java
   limits, the same convention bc20, bc21, bc24 and bc25 use. The budget is
   checked **before** each primitive and never inside one, so a primitive's
   *result* is never a function of the remaining budget; when it runs out the
   robot's turn ends where it stands and is **not resumed mid-computation
   next turn**, which is the one place this differs from the JVM. **Measured
   in this sandbox over three full 2000-round Java games** (`DefaultMap`
   32×32, `AllElements` 30×30, `Eyelands` 50×30): the peak bytecode use of
   any robot on any round was **823–856 — 6.6–6.9 % of the carrier's 12 500 —
   with zero mid-turn cut-offs**, so the divergence is never exercised by the
   oracle, and the parity job **asserts** that rather than assuming it (it
   fails if any robot ever exceeds 50 % of its limit).
2. **`setWinnerArbitrary`'s `Math.random()`** is wall-clock seeded and
   therefore not reproducible; it is replaced by a draw from a world RNG
   seeded from the map's `randomSeed` (**D4**). Reachable only when islands,
   anchors, elixir, mana **and** adamantium are all tied at round 2000.
3. **`ObjectInfo.eachRobot` is a trove hash-order sweep; the port sweeps in
   ascending id (D1).** Two sites use it. `processBeginningOfRound` only
   clears the indicator string, which this port does not have, so that site
   is a **no-op** and order cannot matter. `processEndOfRound` does two things
   per headquarters: deal 4 to every enemy within r² ≤ 9, and every fifth
   round add +6/+6 to its own stockpile and the team total. Resource addition
   is commutative. The damage is order-independent **in outcome**: each
   headquarters deals its 4 to each enemy in range exactly once, a robot on
   `4k` HP with `k` headquarters in range dies under every order, and the
   resource loss of a destroyed carrier is likewise commutative.
4. **`islandIdToIsland.values()` is a HashMap sweep; the port iterates
   ascending island id (D2).** `Island.advanceTurn` reads only its own tiles
   and writes only its own anchor state, and its healing is
   `min(max, health + amount)` applied to robots, which commutes because the
   cap is the same value regardless of order and healing cannot kill.
   `numIslandsOccupied` and the ladder's island count are order-free sums.
5. **`applyCurrents`'s `HashMap`/`HashSet` iteration is replaced by a
   deterministic worklist (D3).** The blocked set is the transitive closure of
   "forecast onto a tile whose occupant is not moving", and because at most
   one robot occupies a tile the engine's `visited`-by-location guard makes
   the closure a well-defined fixed point independent of iteration order. The
   port computes it with a FIFO worklist over robot ids ascending, and
   `tests/test_bc23_currents.nim` asserts the result equals a reference fixed
   point over 500 random layouts. **Measured over all 103 official maps:** no
   current flows into a wall or off the map and no two currents share a
   target, so the only real driver of blocking is robots blocking robots.
6. **Six places where the spec's PROSE and the engine disagree — the engine
   wins:**
   1. **currents fire at the end of the ROUND, not "at the end of the turn"**:
      `processEndOfRound` calls `applyCurrents()` once, after every robot has
      taken its turn;
   2. **a destabilizer's damage lands at the end of round `cast + 4`, not
      `cast + 5`**: `addDestabilize` stores `round + 5` and the sweep fires on
      `entry <= round' + 1`. Boosts, symmetrically, cover rounds
      `cast … cast + 9` inclusive, which *is* the prose's ten turns;
   3. **time-bending effects are ADDITIVE on a per-tile per-team multiplier**,
      quantised to two decimals after every change, and applied as
      `(int) Math.round(base × multiplier)` — not a multiplication of the
      previous value;
   4. **a destabiliser's detonation hits at most ONE robot per tile** — the
      one standing there when that tile's entry expires — and only of the
      destabilised team;
   5. **the stack guards are asymmetric and the port keeps them**: `addBoost`
      adjusts the multiplier only when the tile's list is **shorter than** the
      cap, while the expiry sweep adjusts it when the list is **at most** the
      cap, each evaluated against the list size at that moment. Over the life
      of a tile the two balance; a clamped counter would drift on a tile that
      ever exceeded the cap;
   6. **a headquarters on a current would be pushed by it.** The prose
      guarantees "a headquarter cannot be located on a current";
      `applyCurrents` iterates *every* robot, headquarters included.
      **Measured over all 103 official maps: zero headquarters sits on a
      current**, so the path is unreachable on shipped maps; the port keeps
      the engine's behaviour and `tests/test_bc23_currents.nim` asserts the
      unreachability on every committed map.
7. **`resign()` is reachable in the engine and unreachable here.**
   `rc.resign()` destroys every robot of the resigning team and sets
   `RESIGNATION`; a doctrine is a JSON sheet and neither chassis can call it,
   so the port has no `resign` at all and `RESIGNATION` is not in
   `Domination`. `end_reason` therefore has no `resignation` value — and no
   `destroy_all_units` either, because **there is no elimination condition in
   this year's rule set at all**.
8. **The map file's `symmetry` field is read and never used at runtime**,
   exactly as the engine does. The chassis steers by it and the map card
   reports it; no rule consults it.
9. **`GameWorld.rand`, `RobotControllerImpl.random`,
   `INDICATOR_STRING_MAX_LENGTH`, `EXCEPTION_BYTECODE_PENALTY`, the profiler
   and the indicator dots/lines** are dead or absent here. The two RNGs are
   constructed from the map seed and never read by the 2023 engine, so the
   port does not create them (except the one world RNG divergence 2 needs);
   `MAX_DISTANCE_BETWEEN_WELLS`, `MIN_NEAREST_AD_DISTANCE` and
   `MAX_MAP_PERCENT_WELLS` are map-generation guarantees, not runtime rules,
   and are not ported.
10. **The `deadline` wall-clock stop is a coworld concept, not an engine
    one.** It is recorded as ONE load-bearing record (`plan.abandonAfter[g]`)
    applied by the same proc on record and on playback, and
    `tests/test_bc23_replay.nim` covers it.
11. **22 of the 103 official maps are converted.** Everything above 1 800
    tiles is out of the *played* pools for wall-clock reasons (six are
    converted anyway, under `large`); `Marsh` (1 218 cloud tiles of 3 000,
    40.6 %) and `BuildSite` (71.2 % walls) are converted for neither pool
    because a map where most of the board blinds or blocks the fight makes
    every doctrine look the same; the remaining 81 are simply not converted in
    v1 and `tools/convert_maps_bc23.py --parse-all` reads all 103 in CI.
    Three of the 103 (`Frog`, `Orbit`, `Rewind`) carry an **over-long**
    per-tile vector; `GameMapIO.deserialize` reads exactly `width × height`
    entries and ignores the rest, and the converter reproduces that.
12. **The released 3.0.15 jar's `GameConstants.SPEC_VERSION` is the literal
    `"3.0.14"`** — the same string the pinned `master` sources carry —
    measured, so it is useless as a version pin. The oracle jar is pinned by
    **sha256** in `tools/oracle/bc23/jar.lock`
    (`5d4e42a51946cc1c2149426485bda8096ff1c088c77e3ed075c06ce5968ed72a`,
    16 982 927 bytes) and Tier B cross-checks the constants instead. There is
    **no version-string assertion anywhere.**
13. **Both chassis are behaviour ports parameterised by the doctrine sheet**,
    and one gate of `vrangr1`'s elixir producer is deliberately dropped:
    `ElixirProducer.shouldProduceElixir` additionally requires
    `MAP_SIZE > 1000`, and the `small` pool's maps are 400 tiles, so keeping
    it would make `elixir_tech` and `elixir_spend` dead knobs on a third of
    the map set — which the anti-inert rule forbids.
14. **The chassis and sim file layout, against the design note's file
    table.** The note's table puts `advanceTurn` in `islands.nim`, the
    boost/destabilise sweep in `tempo.nim` and `collect`/`transfer` in
    `wells.nim`. Nim's import graph makes that impossible without a cycle:
    `world.nim` must hold the `World` type, and the sweeps need the robot
    table. So `units.nim`, `tempo.nim`, `wells.nim` and `islands.nim` are
    **pure** — value types plus the arithmetic that needs no world — and the
    world-level halves (`islandAdvanceTurn` and its healing sweep,
    `expireTempo`'s detonations, `doCollectResource`/`doTransferResource`)
    live in `world.nim` and `rules.nim` beside the state they change.
    `currents.nim` and `comms.nim` do import `world.nim` and hold their whole
    behaviour, as the note has them. `NOTICE` and `knobs.nim`'s doc comments
    point at the paths that actually exist.
15. **A STANDARD anchor placed over our own ACCELERATING anchor leaves the
    accelerating anchor's −0.15 cooldown boost registered on those tiles for
    ever**, because `Island.advanceTurn`'s removal path only fires for an
    anchor that is still `ACCELERATING`. Engine behaviour, ported literally
    and pinned by `tests/test_bc23_islands.nim` rather than "fixed".
16. **The design note's own float64 example is wrong and the engine is
    right.** §Sim module claims `base = 5, hundredths = 70` gives a float64
    product of 3.4999999999999996 that Java rounds to 3. Measured against
    Temurin 8: `5 * (70/100.0)` is **exactly 3.5** in float64 (the true
    product is the tie between 3.4999999999999996 and 3.5, and ties round to
    even), so `Math.round` gives **4**. The note's *point* stands and the port
    keeps the float64 form: the integer `(base*h + 50) div 100` really does
    disagree with Java, at **base 45 × 0.70 → 31 versus 32** and at
    **base 50 × 1.15 → 57 versus 58**. Measured over the whole reachable
    domain (bases `{2, 10, 15, 20, 25, 70, 140}` ∪ 5…20 × the sixteen
    reachable multipliers), the two forms **agree**, so the float64
    reproduction is defensive rather than load-bearing — which is a more
    honest statement than the note's, and `tests/test_bc23_tempo.nim` carries
    both vectors.
17. **`transferResource` to an ENEMY headquarters is legal in the engine for
    a positive amount.** `assertCanTransferResource` checks the team only on a
    *negative* (withdrawing) amount; a positive transfer needs only "a well or
    a headquarter". The port reproduces that. Neither chassis does it.
18. **The `first_action` event's field is `action`, not the design note's
    `kind`.** `MatchEvent` flattens `fields` into the same JSON object as the
    event's own `kind` key, so a field called `kind` SILENTLY OVERWRITES THE
    EVENT KIND and the replay comes back carrying events of kind `"move"` and
    `"spawn"` — the beat vocabulary check and every `beatsFor` arm then look
    at the wrong string. bc24 and bc25 already emit `action` for the same
    reason. The reason is stated at the emitter
    (`src/battlecode/match.nim:236-241`), the reader agrees
    (`src/battlecode/broadcast.nim:233-237` reads `e.fields{"action"}`), and
    the vocabulary itself is the note's fifteen names
    (`src/battlecode/years/dispatch.nim:138-142`). Recorded here rather than
    "fixed", because fixing it would break the replay format.

## What this year measures, for the next one

* **`sim_seconds / rounds`, measured in phase 20:** a full 2000-round game on
  `IslandHopping` (60×30, the largest map in the played pool) with both seats
  on the maximum-unit-count doctrine takes **2.9–5.9 s in release**, i.e.
  **1.45–2.95 ms/round**, with **207–451 robots alive at the end**. That is
  well above the 1 ms/round threshold the bc21 learning names, which is why
  the phase-60 viewer check 8 is dispatched with `settle=20000 soak=15` and
  `ci.yml`'s `wasm-viewer` job runs the bc23 replay at
  `--timeout 120 --soak 15`. **bc23 is the heaviest year module in this
  repo.**
* **The Java mirror, measured in this sandbox:** the official example bot
  against itself over three full 2000-round games peaks at **121–157 robots**
  on the board (mean 97–124), takes **26.5–31.1 s of instrumented JVM** per
  game, and produces **210 577–264 676 trace lines (18–22 MB)**. Every game
  ended on `MORE_MANA_NET_WORTH` at round 2000 with islands **0–0** and
  anchors **0–0** — the whole anchor, island, elixir, tempo and comms
  subsystem untouched, which is exactly why the parity job carries a scenario
  bot (`docs/PARITY.md` §bc23, Tier A′).
* **The `lemonade` mirror ends by CONQUEST at round 800–1100 on five of the
  six `small` maps.** The design note assumed a 2000-round game "has room
  for" the 600 kg elixir transformation under `elixir_tech: mid`; it usually
  does not, because the game is over first. Recorded in
  `tests/test_bc23_survival.nim`'s header as the one measured deviation from
  the note's competence floor.
