# Rules, knobs and deliberate divergences

The rule set is a behaviour-for-behaviour port of `battlecode/battlecode26` at
tag **`engine.1.2.5`**. The port is the authority at runtime; the Java engine
survives only as the CI-only parity oracle (see [PARITY.md](PARITY.md)).

## The round loop — the exact resolution order

`src/battlecode/years/bc26/rules.nim` mirrors `GameWorld.runRound`. **A
re-ordering is a rules change and bumps `GameVersion`.**

1. `round += 1`.
2. Every robot's *beginning of round*: expire messages older than
   `MESSAGE_ROUND_DURATION`.
3. Iterate the dynamic bodies **in spawn order** (`dynamicBodyExecOrder` —
   append on spawn, remove on death; **not** id order), skipping bodies that
   died earlier this round.
4. *Beginning of turn*: **the first body of the round runs every cheese mine**
   (cheese therefore spawns inside the first robot's turn, not at round
   start), then carried-rat bookkeeping, throw travel, trap stun, and cooldown
   decay by `COOLDOWNS_PER_TURN`.
5. The body's controller: nothing for a cat, the clan chassis under that
   clan's doctrine for a rat, spending at most its decision budget.
6. *End of turn*: king cheese consumption and starvation damage, then the cat
   state machine.
7. *End of round*: the seven per-team stats the engine reports
   (`GameWorld.processEndOfRound` → `matchMaker.addTeamInfo`: cheese
   transferred, damage to cats, the packed `kings + 10 × cheese`, baby rats,
   dirt, rat traps, cat traps) go into the hash chain.
8. **End-of-match check**, in the engine's own order: (a) either team has zero
   rat kings → the other wins outright; (b) all cats dead while still in
   cooperation → decide by points, then total cheese, then living rats, then a
   seeded coin flip; (c) round 2000 → the same ladder.

### Where this order differs from the design note's prose

The design note (`docs/plans/2026-09-03-battlecode-design.md` §Round loop)
puts king cheese consumption in step 4, the cat state machine in step 5, and
the whole end-of-match check in step 8. **The engine does none of those**, and
the port follows the engine, because the parity oracle diffs the two row for
row and Tiers A and B are blocking:

| the note says | `engine.1.2.5` does | the port does |
| --- | --- | --- |
| king cheese consumption at *beginning of turn* | `InternalRobot.processEndOfTurn` (`InternalRobot.java:1176-1189`) | `rules.endOfTurnFor` (`rules.nim:70-75`) |
| cat state machine as the body's *controller* | `InternalRobot.processEndOfTurn` (`InternalRobot.java:1191`) | `rules.endOfTurnFor` → `runCatTurn` (`rules.nim:77-79`) |
| zero-kings / all-cats-dead checked at *end of round* | `GameWorld.destroyRobot` → `checkWin` (`GameWorld.java:1178-1180`); only the round-limit ladder is in `processEndOfRound` (`GameWorld.java:1021`) | `world.destroyRobot` → `checkWin` (`world.nim:792-795`); `processEndOfRound` → `checkEndOfMatch` |

There is also no separate commit/apply phase: engine actions mutate the world
as they are taken and deaths resolve inside `addHealth`/`destroyRobot`, which
is what the port does too.

## Scoring

```
share_cat  = f32(catDamage[t])          / f32(catDamage[A] + catDamage[B])
share_king = f32(kings[t])              / f32(kings[A] + kings[B])
share_chz  = f32(cheeseTransferred[t])  / f32(cheeseTransferred[A] + cheeseTransferred[B])
w = (0.5, 0.3, 0.2) if cooperation_at_end else (0.3, 0.5, 0.2)
points[t] = int(w0*100*share_cat + w1*100*share_king + w2*100*share_chz)
```

Three details are load-bearing and are pinned by `tests/test_scoring.nim`:

* the shares are **narrowed through float32** before the weighted sum (the
  engine computes them as Java `float`), and only then **truncated** by the
  `(int)` cast — not rounded;
* `kings[t]` is the king **count**, and in the oracle trace it arrives packed
  as `kings + 10 * teamCheese` — decode `% 10` and `// 10`;
* **`cooperation_at_end` comes from the per-round cooperation flag**, never
  from the win type: `WinType` and `DominationFactor` disagree, and a
  kill-all-kings win *after* a backstab still records `RATKING_DESTROYED`.

Per seat: `results.scores[t] = 100 * gamesWon + mean(points over games played)`.
Higher is better. Points are in `[0, 100]` and the two seats' points sum to
about 100, so the 100-per-game win bonus dominates — which is exactly "losing
every rat king loses the game outright".

## End conditions

Per game (`results.games[].end_reason`): `kings_destroyed`, `cats_cleared`,
`round_limit`, `abandoned`. Per episode (`results.reason`):

| `results.reason` | when | scores |
| --- | --- | --- |
| `complete` | the match played out | as above |
| `deadline` | the wall-clock guard fired mid-game: the unfinished game is **discarded** and the finished games are scored | partial, honest |
| `fault` | a sim invariant tripped: a partial replay and `[0, 0]` are still written | `[0, 0]` |

## The doctrine sheet

Ten knobs. Unknown key, wrong type or out-of-range value → **that field's
default**, recorded in `sheet_defaults_applied` / `sheet_unknown_fields`. A
sheet can never be rejected, so a cog can never forfeit.

**`chassis` is not one of them.** Which bot drives a clan is not a strategic
choice a doctrine gets to make: every LLM doctrine runs the `awu` chassis,
`chassis` is absent from `sheet.KnownKeys` and from the prompt's knob list, and
a reply that sends it has the key recorded in `sheet_unknown_fields`, ignored
and logged. The weak `scaffold` bot is reachable only through the scripted
filler path, `PLAYER_SCRIPTED=scaffold`, which sets the chassis directly
(`baselines.chassisFor`).

| field | type / values | default | site in the chassis |
| --- | --- | --- | --- |
| `backstab_policy` | `never` \| `when_ahead` \| `at_round_N` \| `on_first_contact` \| `retaliate_only` | `retaliate_only` | `kit.hostilitiesOpen` gates the enemy target list in `targets.nim` |
| `backstab_round` | 1…2000 (read only for `at_round_N`) | 600 | same |
| `cat_engagement` | `avoid` \| `opportunistic` \| `hunt` \| `feed` | `opportunistic` | `targets.catWeight` / `targets.catsAreTargets` |
| `cat_trap_budget` | 0…200 | 40 | `traps.wantsCatTrap` |
| `rat_trap_budget` | 0…200 | 60 | `traps.wantsRatTrap` |
| `spawn_curve` | `lean` \| `steady` \| `swarm` | `steady` | `king.ratCap` + `king.spawnThreshold` |
| `cheese_ferry_ratio` | 0.0…1.0 | 0.5 | `kit.brainFor` role assignment |
| `king_count_target` | 1…5 | 3 | `formation.wantsMoreKings` |
| `dirt_wall_policy` | `none` \| `king_shell` \| `choke` | `king_shell` | `dirt.tryDirt` |
| `throw_rats_to_feed_cats` | bool | `false` | `combat.feedArmed` |

What each `backstab_policy` value means at `kit.hostilitiesOpen`, since two
of them read alike: **`never`** never takes an enemy rat as a target, not even
after the alliance breaks — it keeps hunting cats and takes the beating;
**`retaliate_only`** opens hostilities the moment the world flips, whoever
flipped it; **`on_first_contact`** opens them immediately; **`at_round_N`**
at `backstab_round`; **`when_ahead`** from round 200, while this clan leads on
cat damage and is not behind on kings. With hostilities closed the enemy is
not a candidate for bite, ratnap, throw **or rat trap**.

**Every knob has teeth.** `tests/test_knob_sensitivity.nim` is a CI gate that
plays a paired set of seeded games for each of the nine non-`backstab_policy`
knobs — and for the chassis selection the filler path makes — and asserts a
named, signed statistic moves. The thresholds live in one table in that file
so tuning is a one-line change.

Free-text caps: `notes` 280 runes, `motto` 48 runes, unknown keys 16 of at most
40 runes each, provider error text 200 runes. **Every cap is measured in RUNES
and every truncation lands on a rune boundary.**

## §Divergences

Everything below is a deliberate, listed departure from the Java engine. The
parity oracle's Tier C trend is where they show up.

1. **The decision budget replaces the bytecode limit.** The engine meters a
   robot's turn in JVM bytecodes through an instrumenting class loader; there
   is no JVM here. Each robot instead gets `DecisionOps` credits —
   `BABY_RAT 1500`, `RAT_KING 2500`, `CAT 800` — charged by the chassis for
   primitive steps (a sense, a BFS expansion, a candidate evaluation) and
   enforced by the sim, not by the bot. A robot that runs out ends its turn
   where it stands. Bounded, machine-independent and deterministic.
2. **No `.class` instrumentation** and therefore no bytecode accounting in the
   replay.
3. **No indicator strings, timeline markers, profiler or `speedscope`.**
4. **No crossplay** (Python bots).
5. **The arbitrary-winner coin flip is seeded.** `setWinnerArbitrary` calls
   `Math.random()` in Java; here it draws from the world RNG so a match stays
   reproducible. Reachable only on an exact three-way tie.
6. **A robot that dies inside its own beginning-of-turn ends its turn.** The
   engine keeps calling into it; here the turn simply stops. Unreachable for
   the parity bot (`scaffold` never throws a rat), and it cannot resurrect a
   dead body either way.
7. **Cats are 4 000 HP, not 10 000.** The idea card says 10 000; the pinned
   engine says 4 000, and the engine wins.
8. **BFS is materialised lazily.** The engine precomputes a direction map from
   every tile to every tile at world construction (26 MB and ~830 M operations
   on a 60x60 map). The result is a pure function of the wall layout, which
   never changes, so computing a target's map on first use is identical and
   pays only for the handful of targets cats ask about.
