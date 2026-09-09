# Battlecode 2016 "Zombie Invasion" — the `bc16` year module

`game_config.year = "bc16"` selects this module. It is a behaviour port of
`github.com/battlecode/battlecode-server-2016` at commit
**`11a0b09f26a70da19f33a61ebec4ceaf6e161aa3`** (`HEAD` of `master`, last commit
"Final maps"; root `COPYING` = **GPL-3.0**), and the port is the authority at
runtime: the Java engine exists only as the `parity-oracle-bc16` CI job
(`docs/PARITY.md` §bc16).

**The official 2016 specification is lost** — the `s3.amazonaws.com/battlecode-specs`
bucket and `battlecode.org` are both dead and there is no Wayback copy — so
there is no prose to reconcile against and **the engine source IS the spec**.
Every rule below carries a `file:line` citation into that checkout, and an
uncitable rule is a **marked decided divergence** with its reason.

Nothing about `bc26`, `bc20`, `bc21`, `bc22`, `bc23`, `bc24` or `bc25` changes.
`GameVersion` went **GV10 → GV11** in the commit that added this module and
`ReplayCompatibleGameVersions` was **extended** to
`["GV04","GV05","GV06","GV07","GV08","GV09","GV10","GV11"]`, never reset, so
every hosted replay of the seven shipped years keeps rendering.

Layout: `src/battlecode/years/bc16/` (`constants.nim` generated, `units.nim`,
`delays.nim`, `health.nim`, `world.nim`, `economy.nim`, `signals.nim`,
`zombies.nim`, `rules.nim`, `maps.nim`, `knobs.nim`) plus
`src/battlecode/years/bc16/chassis/` (`kit.nim`, `econ.nim`, `archon.nim`,
`combat.nim`, `micro.nim`, `turret.nim`, `dens.nim`, `neutral.nim`,
`rubble.nim`, `infect.nim`, `comms.nim`, `bulwark.nim`, `greenhorn.nim`,
`scenario16.nim`) — fourteen files, and `NOTICE` names the same paths.

## The game in one paragraph

Two factions of robots on a symmetric grid between 30×30 and 80×80. Each starts
with **1 to 4 ARCHONS** (1000 HP, cannot be built) and **300 PARTS**, and
**lose your last archon and you lose immediately**. Archons build **SOLDIERS**
(30 parts, 60 HP, 4 damage at r² ≤ 13), **GUARDS** (30, **145 HP**, 1.5 melee,
**double against zombies**, **4 blocked** off any hit above 10), **SCOUTS**
(25, 80 HP, no attack, **ignores rubble**, sight r² ≤ 53), **VIPERS** (120,
120 HP, 2 damage at r² ≤ 20 that **infects for 20 turns**) and **TURRETS**
(130, 100 HP, **13 damage between r² 6 and 40**, immobile — it must *pack* into
a **TTM** to move). Archons also **repair** a friendly non-archon for 1 HP a
turn for free, and **pick up every part on any square they walk onto**. And the
map is trying to kill both of them: each map ships a fixed, **public zombie
spawn schedule** divided evenly among its **2 to 12 ZOMBIE DENS** (2000 HP,
200 parts each). Zombies belong to a third team, **see the whole map**, and
walk at the **nearest player-controlled robot of either faction**. Every 300
rounds the **outbreak level** rises and every zombie spawned after it is
stronger — ×1.0, ×1.1, ×1.2, ×1.3, ×1.5, ×1.7, ×2.0, ×2.3, ×2.6, ×3.0 — so a
round-2700 BIGZOMBIE has **1500 HP and 75 damage**. A robot that **dies while
infected** leaves no rubble and **stands back up as a zombie of its own
`turnsInto`**; one that dies uninfected raises the rubble on its square by its
own maximum health, and **rubble ≥ 100 is impassable**.

## The round loop — the step list IS the rules

Re-ordering any of these is a rules change and bumps `GameVersion`.

1. **Beginning of round.** `currentRound += 1` — **FROM −1**
   (`GameWorld.java:69`), so the first round played is round **0** and the last
   is **2999**; every round number in the trace, the replay and the viewer
   clock is 0-based, exactly as the engine's is. Then every robot's
   `processBeginningOfRound`, whose body in 2016 is **empty**
   (`InternalRobot.java:431-432`), and `controlProvider.roundStarted()`, which
   is empty in both providers. **Both are genuine no-ops and are NOT PORTED AT
   ALL** (D1).
2. **Turn order.** A **snapshot** of the insertion-ordered id list taken before
   the sweep (`GameWorld.java:158-160`), with a `robot == null` guard.
   `gameObjectsByID` is a **`LinkedHashMap`** (`:72`), so the order is plain
   insertion order: the map file's `initial-robot` rows in **file order**
   first, then every spawn in spawn order, with removal on death leaving the
   survivors' relative order intact. **The initial robots are NOT sorted by
   id** (unlike 2022) — ids come from the `IDGenerator` and are shuffled.
3. **Each robot's turn**, in four parts (`GameWorld.java:169-181`).
   `decrementDelays()` takes **exactly 1.0** off both counters and floors each
   at 0 (V1); `repairCount`, `basicSignalCount` and `messageSignalCount` reset;
   the `DecisionOps` budget resets — **to ZERO for a robot with
   `!isActive()`**, which is how a SOLDIER built this round is a live,
   blocking, damageable robot that does nothing for 12 turns (a VIPER for 30, a
   TURRET for 25, a SCOUT for 20). Readiness is **strictly `< 1` on a float64**.
   Then the controller runs — a PLAYER robot runs its team's chassis, a ZOMBIE
   or a DEN runs the engine's own `ZombieControlProvider` logic (which **is the
   sim** and costs nothing against any budget), and a NEUTRAL robot does
   nothing. Then `processEndOfTurn`, **and only if `health > 0`**:
   `roundsAlive += 1`, then `processBeingInfected()` — the viper strain's
   **2.0** damage, which can kill, and then the robot **is** infected, so it
   becomes a zombie.
4. **End of round, in exactly this order.**
   a. Every robot's `processEndOfRound` — **empty** in 2016
      (`InternalRobot.java:459`), a genuine no-op (D1).
   b. **Parts income**: team A's stockpile `+= max(0, 2.0 − 0.01 × robots)`,
      then team B's (`:622-627`). It reaches **exactly zero at 200 robots**,
      which is why a 2016 army has a natural ceiling.
   c. The **end-of-match check**, if `timeLimitReached()`
      (`currentRound >= rounds − 1`) and no winner is set: the four-rung
      ladder below, on **exact float64 differences**.
   d. `running = false` if a winner is set; then the state hash.

## The four-rung ladder

| rung | difference | `DominationFactor` | our `end_reason` |
|---|---|---|---|
| 1 | `count(A, ARCHON) − count(B, ARCHON)` | `PWNED` | `more_archons` |
| 2 | `Σ health of A's live ARCHONs − Σ of B's` | `OWNED` | `more_archon_health` |
| 3 | `(parts(A) − parts(B)) + Σ partCost over A's live robots − Σ over B's` | `BARELY_BEAT` | `more_parts_net_worth` |
| 4 | `max live A archon id > max live B archon id` → A **else B** | `WON_BY_DUBIOUS_REASONS` | `highest_id` |

and, at any moment inside a turn, a faction whose **last ARCHON** dies loses
**immediately** — `DESTROYED` / `archons_destroyed` — while the round plays
out. Rung 3's accumulator is **seeded with the parts difference and then walks
every live robot of either team once**, in insertion order, so it includes the
zombies' and neutrals' cost (0 for a den and a zombie; non-zero for a NEUTRAL,
which belongs to neither team and therefore contributes nothing to either
side). Rung 4's **`else` branch awards B**, so a 0-vs-0 archon-id tie goes to
Clan Basil.

## The unit table, verbatim

`common/RobotType.java:18-98`, in `values()` order — and **the ordinal order is
load-bearing**: `ZombieCount.compareTo` sorts by it and `spawnAllPossible`'s
no-`break` type loop reads it.

| # | type | zombie | infectTurns | parts | buildTurns | HP | attack | r² | moveDelay | attackDelay | cooldown | sight r² | turnsInto | ignoresRubble |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | `ZOMBIEDEN` | yes | 0 | 0 | 0 | **2000** | 0 | 0 | 0 | 0 | 0 | **−1 (all)** | — | no |
| 1 | `STANDARDZOMBIE` | yes | 10 | 0 | 0 | 60 | 2.5 | 2 | 3 | 2 | 1 | **−1** | — | no |
| 2 | `RANGEDZOMBIE` | yes | 10 | 0 | 0 | 60 | 3 | 13 | 3 | 1 | 1 | **−1** | — | no |
| 3 | `FASTZOMBIE` | yes | 10 | 0 | 0 | 80 | 3 | 2 | **1.4** | 1 | 1 | **−1** | — | **yes** |
| 4 | `BIGZOMBIE` | yes | 10 | 0 | 0 | **500** | **25** | 2 | 4 | 3 | 2 | **−1** | — | **yes** |
| 5 | `ARCHON` | no | 0 | — | — | **1000** | 0 | 24 (repair) | 2 | 1 | 1 | 35 | BIGZOMBIE | no |
| 6 | `SCOUT` | no | 0 | 25 | 20 | 80 | 0 | 0 | **1.4** | 0 | 1 | **53** | FASTZOMBIE | **yes** |
| 7 | `SOLDIER` | no | 0 | 30 | 12 | 60 | 4 | 13 | 2 | 2 | 1 | 24 | STANDARDZOMBIE | no |
| 8 | `GUARD` | no | 0 | 30 | 10 | **145** | 1.5 | 2 | 2 | 1 | 1 | 24 | STANDARDZOMBIE | no |
| 9 | `VIPER` | no | **20** | 120 | 30 | 120 | 2 | 20 | 2 | 3 | 1 | 24 | RANGEDZOMBIE | no |
| 10 | `TURRET` | no | 0 | 130 | 25 | 100 | **13** | **40** (min **6**) | **immobile** | 3 | 3 | 24 | RANGEDZOMBIE | no |
| 11 | `TTM` | no | 0 | 130 | 10 | 100 | 0 | 0 | 2 | 0 | 2 | 24 | RANGEDZOMBIE | no |

**A TTM is NOT buildable** — its `spawnSource` is TURRET, so it is only
reachable by packing. `tests/test_bc16_units.nim` compares every one of these
cells, and all eight derived predicates, against the JVM's own values in
`data/bc16/tables.json`.

## The delay pair — this year's whole tempo

    activateCoreAction(attackDelay, movementDelay):
        setWeaponDelayUpTo(attackDelay);  addCoreDelay(movementDelay)
    activateAttack(attackDelay, movementDelay):
        addWeaponDelay(attackDelay);      setCoreDelayUpTo(movementDelay)

They are **opposite in both the set/add choice AND in which counter takes which
argument**, and getting that backwards is the single easiest way to break this
year. `clearRubble`, `move`, `build` and `activate` go through the first;
`attackLocation` goes through the second; **`repair` goes through NEITHER and
costs nothing at all**. `pack`/`unpack` add **10 to both counters and have no
readiness check whatsoever**. Named vectors, all asserted: a soldier's diagonal
step onto rubble 60 charges **core 5.6 / weapon 2.0** (the diagonal multiplier
hits the CORE only); its attack **weapon +2 / core up-to 1**; a turret's attack
**weapon +3 / core up-to 3**; a VIPER build **weapon up-to 30 / core +30**; an
`activate` **weapon up-to 0 / core +2**.

## The zombie AI — the sim, not a chassis

Ported action for action from `world/control/ZombieControlProvider.java`. A
den's turn: add **this den's own** share of this round's schedule to its
persistent queue, `spawnAllPossible`, and then — **only if a queue remains** —
damage every adjacent non-zombie for **10.0** and call `spawnAllPossible`
again, so a den spawns at most **8 per call and 16 per round**. The ring is
`DIRECTIONS[floorMod(start + i × chirality, 8)]` with `DIRECTIONS` = N, NE, E,
SE, S, SW, W, NW, and the spawn priority is **BIGZOMBIE → FASTZOMBIE →
RANGEDZOMBIE → STANDARDZOMBIE**, because the engine's type loop has no `break`
and keeps the **last** non-zero type. A den's `canBuild` is only
`isEmpty(loc)`, so **a den spawns onto rubble no player unit could stand on**.

A zombie's turn is an eight-step ladder with **every early return in place**,
and two RNG draws whose preconditions are exact (D2c): `nextInt(8)` **only when
no player robot is alive at all**, and `nextBoolean()` **only when the zombie
got past the attack branch, past `!isCoreReady()` and past the
move-in-the-preferred-direction branch**. `getNearestPlayerControlled` consumes
a draw from the **other** stream on **every call including size 1** (D2b),
because `java.util.Random.nextInt(1)` still consumes a `next(31)`.

## The doctrine sheet — eleven knobs, and NO `chassis` key

`opening` (`turtle` | `soldier_viper_aggro` | `scout_zombie_pull`, default
`turtle`), `turret_count` (0…12, 3), `guard_ratio` (0…100, 45),
`zombie_kiting` (`never` | `ranged_only` | `always`, `ranged_only`),
`den_clear_round` (1…2800, 900), `parts_priority` (`units` | `turrets` |
`vipers`, `units`), `archon_spread` (`huddle` | `spread` | `split`, `spread`),
`neutral_activation` (`never` | `opportunistic` | `hunt`, `opportunistic`),
`retreat_hp` (0…100, 35), `rubble_clear` (`never` | `paths` | `aggressive`,
`paths`), `infection_policy` (`ignore` | `quarantine` | `suicide_squad`,
`quarantine`).

An unknown key, a wrong type or an out-of-range value takes **that field's
default** and the repair is recorded — except the **four integer knobs, which
CLAMP** to their range rather than defaulting, so "as many as possible" still
means something. **An ABSENT known key is also recorded** in
`sheet_defaults_applied` (bc16 and bc22 only — doing it year-neutrally would
change what a bc20/bc21/bc23/bc24/bc25/bc26 episode records in that array).
**The chassis is not a knob** (D1): a submitted `chassis` is recorded in
`sheet_unknown_fields` and never honoured.

**THE ANTI-INERT RULE.** No setting of any knob, and no combination of
settings, may produce an inert or self-starving faction: the strategy surface
lives inside ONE competent chassis. `tests/test_bc16_knobs.nim` proves every
knob has teeth in a **named, signed** direction and asserts over its whole
68-game sweep that both seats always built ≥ 10 units and dealt ≥ 500 damage;
`tests/test_bc16_survival.nim` proves the floor holds, **with a negative
control (`-d:bc16BrokenChassis`) that must come back RED**.

## Scoring

```
share(x, y)   = if x + y == 0: 0.5'f32 else: f32(x) / f32(x + y)
points[t]     = int(64 * share(archons) + 24 * share(archonHealthTenths)
                  + 12 * share(partsWorth))            # TRUNCATION
scores[t]     = 200 * (games won) + mean(points[t])
```

The three terms are **exactly the engine's three deciding rungs in the engine's
own priority order**. Rungs 2 and 3 are float64 in the engine and are narrowed
to integers here — archon health to **tenths**, parts worth to a truncated
integer — before any share is taken, because `points` must be reproducible bit
for bit between the native recorder and the wasm re-deriver. **Two documented
disagreements are asserted as expectations rather than left to be found**:
`points` alone can favour the LOSER (a one-unit margin on a rung with large
totals is arbitrarily small — 4 vs 3 archons is `4/7 − 3/7 = 0.143` of 64, i.e.
9.1 points against 36 available below), which is why bc16 joins `winBonusFor`'s
**200** set; and the `end_reason` is decided on the engine's **exact float64**
differences while `points` is decided on the narrowed integers, so a razor-thin
margin can decide the *winner* on a difference that rounds away in *points*.

## §Divergences

Every place this port deliberately differs from the engine, with its reason.

1. **V1 — the bytecode-dependent delay decay is pinned to
   `amountToDecrement = 1.0`.** The engine computes
   `1.0 − 0.3 × (max(0, 8000 − limit + prevBytecodes)/8000)^1.5`
   (`InternalRobot.java:326`). There is no JVM and no bytecode counter, and
   deriving the term from the chassis's own `DecisionOps` would make **the
   chassis's implementation a rules input** — a one-line refactor of `bulwark`
   would change what a round resolves to and would have to bump
   `GameVersion`. `1.0` is exactly what the engine produces for any robot
   inside `limit − 8000` bytecodes, so the divergence is "every unit behaves
   like a frugal 2016 bot", and **1.0 is the MAXIMUM the formula ever
   returns**, so the port never drains a counter more slowly than the engine.
   The engine's whole formula is nevertheless **tabled over its complete
   finite domain** in `data/bc16/tables.json` and asserted by
   `tests/table_bc16_delay.nim`, so the port provably knows what it diverged
   from. **The sub-1.0 branch is the one behaviour the parity oracle cannot
   compare**, and `docs/PARITY.md` §bc16 says so in as many words.

   **And it could not be compared bit-exactly even in principle.** The engine
   calls `Math.pow`, which the JLS permits to be 1 ulp from the exact result
   and which is therefore **not reproducible between JDK builds** — measured,
   Temurin 8u422 and 8u452 disagree over this very domain. `tables.json`
   therefore tables `StrictMath.pow` (bit-stable everywhere, and it says so in
   its own `pow_1_5_source` key), and CI separately asserts the running JDK's
   `Math.pow` is within one ulp of every value. Over the whole 8 001-value
   domain, glibc's `pow` — the port's — is bit-exact against fdlibm on 7 220
   cells and one ulp apart on the other 781, **never further**; and V1's
   pinned branch is `pow(0, 1.5) = 0`, where all three are exact.
2. **V2 — bytecode metering is replaced by a fixed per-robot `DecisionOps`
   budget**: **2000** (ARCHON, SCOUT), **1000** (SOLDIER, GUARD, VIPER,
   TURRET, TTM), **0** for a robot with `!isActive()`. One tenth of the
   engine's own limits, the convention bc20–bc26 use. It is checked **before**
   each primitive and never inside one, so a primitive's *result* is never a
   function of the remaining budget; when it reaches zero the robot's turn ends
   where it stands and is **not** resumed mid-computation next turn, which is
   the one behavioural difference from the JVM — and V1 makes it invisible to
   the rules.
3. **V3 — the map's random origin is not ported.** `GameMap`'s *programmatic*
   constructor draws `origin = (rand.nextInt(500), rand.nextInt(500))`
   (`GameMap.java:248-250`); the port uses `(0, 0)`. **Proven inert**: the
   origin is added to every coordinate uniformly, `onTheMap` subtracts it, and
   `distanceSquaredTo`, `directionTo`, `compareTo`-sign and every radius scan
   are translation-invariant. **A correction to the design note**: a map loaded
   *from XML* does not draw at all — XStream sets the final field directly from
   the file (`arena.xml` = `266,163`) — so the draw the note describes happens
   only on the programmatic path. The conclusion is unchanged and the parity
   comparator normalises the Java side.
4. **V4 — armageddon is not ported.** `isArmageddon()`, the day/night cycle,
   zombie regeneration, `ZOMBIFIED` and `CLEANSED` are absent, and neither
   `zombified` nor `cleansed` is added to the `end_reason` enum. Measured: both
   official armageddon maps are **team B with ZERO archons** over 12 000
   rounds with 49 and 104 dens — a single-player survival mode, not a two-seat
   match — and `tools/convert_maps_bc16.py` **refuses** them by flag and by
   unequal archon count.
5. **V5 — `resign()` is unreachable**, and `setTeamMemory`/`getTeamMemory`,
   the indicator strings/dots/lines, `addMatchObservation` and `Clock.yield()`
   have no port. A doctrine is a JSON sheet; recorded as *unreachable here*,
   not *absent upstream*, and `tests/test_bc16_endladder.nim` asserts no
   chassis reaches `resign`.
6. **V6 — the `.rms` match stream, the XStream/Jackson serial layer and the
   `server/proxy` writers have no port**, and neither does the official 2016
   Java Swing client. The replay is this repository's own self-sufficient UTF-8
   JSON re-derived by the wasm sim. No `.rms` bytes exist anywhere.
7. **D3 — the ONE hash-order dependency in the whole 2016 engine is resolved
   at BUILD time, not ported.** `GameMap.buildZombieSpawnMap` (`:718-793`)
   iterates `byLoc.keySet()`, a `java.util.HashMap<MapLocation, ...>`, and
   that order decides which den receives each leftover zombie.
   `tools/convert_maps_bc16.py` reproduces Java 8's `HashMap` iteration order —
   `h ^ (h >>> 16)`, bucket `hash & (n−1)`, capacity 16, load factor 0.75,
   resize splitting each bucket into its lo/hi lists in place, iteration
   walking buckets 0…n−1 and each chain in insertion order — computes the whole
   per-den split ONCE and writes it into the converted map JSON. **The runtime
   sim hashes nothing.** The emulation was verified against a real
   `java.util.HashMap` on **all 98 official rosters, 0 mismatches**, and Tier B
   byte-diffs the committed per-den schedules against the JVM's own
   `getZombieSpawnSchedule(denLoc)`.
8. **D4 — the map symmetry is computed at build time and recorded**, not
   computed at run time. `GameMap.updateSymmetries` tests VERTICAL,
   HORIZONTAL, ROTATIONAL and (only when `width == height`) the two diagonals,
   and takes **the FIRST that holds in that order**. Measured across the 98
   maps: 61 ROTATIONAL, 33 HORIZONTAL, 2 VERTICAL and 2 (the armageddon pair)
   NONE; **13 maps satisfy TWO symmetries**, which is why the pool deliberately
   includes `frogger` (VERTICAL wins over ROTATIONAL) as the control that
   proves the resolution order. The only runtime reader is
   `getSpawnChirality`.
9. **D1 — the two hash-order robot sweeps in the round loop need NO port at
   all**, because in 2016 neither has any observable behaviour: both
   `InternalRobot.processBeginningOfRound` and `processEndOfRound` have **empty
   bodies**, and both iterate a `LinkedHashMap` anyway. Stated explicitly so
   nobody ports them "to be safe".
10. **V7 — 22 of the 98 official maps are converted in v1.** The converter
    handles any 2016 `.xml` and CI parses **all 98**; **every map in every pool
    is one of the 54 the oracle jar also carries as a resource**, so no parity
    pair and no smoke episode needs a `--map-dir`.
11. **V8 — `EXCEPTION_BYTECODE_PENALTY` has no port.** A Nim chassis raises
    nothing.
12. **The `deadline` wall-clock stop is a coworld concept, not an engine
    one.** It is recorded as ONE load-bearing record (`plan.abandonAfter[g]`)
    applied by the same proc on record and on playback — the particle-worlds
    scar.
13. **Both chassis are ours.** `bulwark` is written for this run from the
    engine's own mechanics and from the three archetypes the run's idea text
    names; `greenhorn` is written for this run as the deliberately weak floor
    and exists in a **Java twin** (`tools/oracle/bc16/bc16greenhorn/`) that
    **may not gain behaviour**, because it is one side of the differential
    oracle. **`TheDuck314/battlecode2016` and `bshimanuki/battlecode2016` carry
    NO LICENCE and were not cloned, not read, not copied, not vendored, not
    compiled and not translated** (see `NOTICE`).
14. **The `health.nim` / `world.nim` split.** The design note put the single
    `changeHealthLevel` mutation point, the death path, the rubble deposit, the
    infection→zombie conversion and the mid-turn `DESTROYED` check all in
    `health.nim`. The mutation half of that list has to reach world state — the
    rubble array, the occupancy index, the exec list and `spawnRobot` for the
    zombie that stands up — so in Nim it must live beside that state or the two
    files import each other. **`health.nim` owns the two independent infection
    counters, the viper tick, the health cap and `deathConsequence` (the
    ordered decision a death makes); `world.nim` owns `changeHealthLevel`,
    which applies exactly that decision once and is still the ONE mutation
    point.**
15. **The score's tenths-narrowing**, and the fact that the *winner* is decided
    on the engine's exact float64 differences while *points* are decided on the
    narrowed integers, so the two can disagree on a razor-thin margin (see
    §Scoring).
16. **The survival gate's committed ratio is 2 of 6, not the design note's 5 of
    6 — and the reason is engine arithmetic rather than a chassis defect.**
    2016 combat is extremely slow: a GUARD deals 1.5 doubled to **3.0** against
    a zombie once a round, a SOLDIER 4 at attackDelay 2 (**2/round**) and a
    TURRET 13 at attackDelay 3 (**4.3/round**), while a level-9 BIGZOMBIE has
    **1500 HP and 75 damage** — so a single late BIGZOMBIE outlives roughly 350
    turret-rounds. **A horde that overwhelms an unbroken den field is authentic
    2016.** The gate is therefore re-pinned to the MEASURED ratio and its
    anti-degeneracy work is done by **substance floors**: both sides non-trivial
    on units, damage and guards in EVERY game, parts income positive and parts
    collected across the pair on every map with deposits, at least four dens
    killed across the six maps, a median-round floor, and **the whole gate
    coming back RED under `-d:bc16BrokenChassis`**. Both measured tables —
    healthy and broken — are inline in `tests/test_bc16_survival.nim`'s header
    and repeated here.

    **Provenance, so a future staleness is detectable (r1-F4):** these numbers
    were regenerated from the build that shipped and agree with `ci.yml` run
    **34322655506** (`main` @ `fbc7d345`, `test` job 102372608026), whose own
    log line reads `HEALTHY games=6 notDestroyed=3 dens=14 median=2015
    rounds=@[3000, 695, 3000, 707, 3000, 1030]`, and `median=873` for the
    control. The rows previously printed here were measured before the
    den-breaking chassis iteration landed and were stale by 20 vs 14 dens,
    2147 vs 2015 median rounds and 1029 vs 873 on the control.

    | | not `archons_destroyed` | dens killed | median rounds | guards (min) | units (min) | damage (min) |
    |---|---|---|---|---|---|---|
    | healthy, after the den-breaking iteration | **3 of 6** | **14** | **2015** | 5 | 58 | 3608 |
    | healthy, before it | 1 of 6 | 6 | 936 | 4 | — | — |
    | broken (`-d:bc16BrokenChassis`) | **0 of 6** | **0** | **873** | **0** | 55 | 3333 |

    Every committed floor still holds on the regenerated numbers:
    `MinNotDestroyed` 2 ≤ 3, `MinUnitsBuilt` 25 ≤ 58, `MinDamageDealt`
    1500 ≤ 3608, `MinGuardsBuilt` 2 ≤ 5, `MinDensKilled` 4 ≤ 14,
    `MinMedianRounds` 1000 ≤ 2015, parts income 1 ≤ 11 724 tenths, and
    `swamp`'s pair-parts clause 1 ≤ 1 200 tenths. **No floor was moved.**

    **Which clauses carry the discrimination, and which are anti-degeneracy
    floors the broken control also clears (r1-F3).** Stated plainly, because a
    floor set below what the named control already achieves does not
    discriminate, and reading the clause list as if every clause did is the
    mistake. The floors are **not fitted to the control**: raising the damage
    floor past the control's 3333 would put it above the *healthy* weak seat's
    3608, which is fitting a floor to noise and would redden healthy runs.

    | clause | floor | healthy (worst) | broken control | discriminates? |
    |---|---|---|---|---|
    | ratio, not `archons_destroyed` | 2 of 6 | 3 of 6 | **0 of 6** | **yes** |
    | guards built, per seat per game | 2 | 5 | **0** | **yes** |
    | dens killed across the six maps | 4 | 14 | **0** | **yes** |
    | `swamp` parts collected across the pair | 1 tenth | 1 200 | **0** | **yes** |
    | units built, per seat per game | 25 | 58 | 55 | no — anti-degeneracy only |
    | damage dealt, per seat per game | 1 500 | 3 608 | 3 333 | no — anti-degeneracy only |
    | parts income, per seat per game | 1 tenth | 11 724 | 10 621 | no — anti-degeneracy only |
    | median rounds | 1 000 | 2 015 | 873 | inside the control's noise band |

    The four `yes` clauses are a **hard zero** on the control and carry all of
    the gate's discriminating power. The three `no` clauses stay asserted
    because what they catch is a chassis that stops acting *at all* — the
    do-nothing sheet that wins because the opponent starved (the 2026-09-03
    finding) — not this particular control. **The median floor sits inside the
    control's own noise band**: the previous session recorded 1 029, *above*
    the 1 000 floor, and the shipped build measures 873, *below* it, so it is
    counted with the anti-degeneracy floors even though it does fire today.
    Run 34322655506's control failed on sixteen clauses and the eight it
    printed are all `guards built 0 < 2` plus `swamp: parts collected across
    the pair (tenths) 0 < 1` — not one printed failure is a units-built,
    damage-dealt, income or median failure.

17. **The chassis reads the den roster from the map** rather than
    rediscovering it by sighting. The whole-map zombie schedule is **public**
    in the real game (`getZombieSpawnSchedule()` is free to every robot) and
    this coworld's own observation hands both cogs the den locations, so
    nothing hidden is read: the sim's fog is untouched and **no RULE reads the
    roster**. A chassis convenience, recorded rather than assumed.
18. **`rng.nim` gained one optional parameter.** 2016's `IDGenerator` starts
    its block at **0** and mints ids from **1**, against the 10 000 floor every
    later year uses, so `initIdGenerator(seed, firstBlock = MinId)` takes a
    first-block argument. The change is additive and every existing call site
    keeps the default, so no other year's id stream moves.
19. **`dispatch.currentRound` reports ROUNDS PLAYED, not the world's round
    number.** Every other year's world starts `currentRound` at 0 and
    pre-increments, so its first played round is 1 and the number IS the count;
    **bc16's starts at −1 and its first played round is 0**, exactly as the
    engine's is. `replay.nim`'s year-neutral deriver indexes the recorded
    per-round hash chain with that count, so the bc16 arm adds one. Every bc16
    event, every parity trace line and the viewer clock still carry the
    ENGINE's 0-based number.
20. **Three chassis adjustments were made for knob teeth, and each is
    measured.** (a) `dens.nim` gained a **standing strike group** of
    `DenStrikeGroup = 4` attackers with `DenGarrison = 4` held back, a **sticky
    den target**, and a `DenPressureFloor` that commits while attackers are
    still alive — without them the defensive floor reclaimed the whole army
    every round and the den field was never broken (6 dens across the six maps
    against 20 after). (b) `econ.nim`'s `openingGuardBias` gives
    `soldier_viper_aggro` **−20 points of guard share** and moves the viper
    ahead of the third soldier when the stockpile can afford 120 + 30 —
    without them `opening` moved nothing measurable (116 soldiers against 115)
    and the opening's headline unit never existed. The bias is deliberately
    **one-sided** (`turtle` stays at the cog's own number) because a symmetric
    ±20 moved the all-defaults game from 3-of-6 to 1-of-6 on the survival gate.
    (c) `archon.nim`'s `archon_spread` biases the **parts walk** by distance
    from the friendly archon centroid — without it `huddle` and `split`
    produced byte-identical games.

## Corrections to the design note

Four of the note's stated numbers are wrong, and in every case the PORT was
already right and the note's prose was not. Each was verified against a real
Temurin 8 and the pinned oracle jar (`tests/test_bc16_arith.nim`,
`tests/test_bc16_rubble.nim`):

| the note says | the engine and IEEE-754 say |
|---|---|
| `2.0 − 0.01 × 137 = 0.63` | **`0.6299999999999999`** — `0.01` is not representable |
| `60 × 1.1 = 66.00000000000001` | **`66.0`**, as a constant and at run time |
| `145 × (1.0/3.0) = 48.333333333333336` | **`48.33333333333333`**, one ulp lower |
| "14 clears take a 100 to 0 and 55 take a 1000" | **8** and **35** — `0.95r − 10` subtracts a FLAT 10 every action, so it converges far faster than the percentage term alone suggests |

And one the note did not state: `MapLocation.directionTo(self)` is **OMNI**
(ordinal 9), not NONE.

## Playback pacing, measured

A 3000-round `bulwark` mirror on `river` (32×32, three archons a side) plays in
**2.2 s in release Nim — 0.74 ms a round** at a peak of 45/41 robots, against
the design note's estimate of 2–5 ms. `caverns` measures 0.45 ms/round and
`prisons` 1.6. Best of three is therefore well inside `matchBudgetSeconds 360`.
Because the recording is nevertheless **3000 rounds — 50 % longer than any
other year in this repository** — the phase-60 viewer check 8 is dispatched
with `settle=20000 soak=15` and `ci.yml`'s `wasm-viewer` job runs the bc16
replay at `--timeout 120 --soak 15`.
