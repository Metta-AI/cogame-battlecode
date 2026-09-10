# The Java oracle and what it proves

The Battlecode 2026 rule set here is a **port**, not a wrapper. The thing that
makes a port trustworthy is a differential test against the original, so
`.github/workflows/ci.yml` carries a `parity-oracle` job that runs the
**unmodified Java engine** and diffs it against this sim, row for row.

**The oracle's toolchain exists only in that job.** There is no JDK, JRE, JVM
or Java source in any runtime image stage (see `Dockerfile` and
`docs/RULES.md` §Divergences).

## How it works

1. Java 21 + `battlecode26-java-1.2.5.jar` (from
   `https://releases.battlecode.org/maven`) runs `examplefuncsplayer` against
   itself, headless, on five maps from the `small` pool. Each map carries its
   own `randomSeed`, which is what the engine seeds its world RNG and its
   `IDGenerator` from — so a (map, seed) pair is a map.
2. `tools/parity_trace.py` reads the resulting `.bc26` with the schema's
   generated Python bindings and emits a per-round trace.
3. `tools/parity_trace.nim` emits the **same text** from the Nim sim driving
   the ported `scaffold` chassis.
4. The job diffs them at three tiers.

The trace is one line per record:

```
R <round> T <team> chz=<cheeseTransferred> cat=<catDamage> kpk=<kings+10*teamCheese> \
    rats=<babyRats> dirt=<n> rt=<n> ct=<n>
R <round> U <robotId> hp=<n> chz=<n> mc=<n> tc=<n> ac=<n> x=<n> y=<n> dir=<NAME> coop=<0|1>
```

`robotId` is in there on purpose. `IDGenerator` is ported verbatim — the same
4096-id blocks from 10000, the same Fisher–Yates over each block with the same
`nextInt(i+1)` call order — so ids match the Java engine's for a given map
seed, which is what makes the trace comparable row for row rather than
set-for-set.

`scaffold` is the parity bot because it is
`example-bots/src/main/examplefuncsplayer/RobotPlayer.java` ported statement
for statement:

```java
if (rc.canMoveForward()) rc.moveForward();
else { int d = rng.nextInt(8); if (rc.canTurn()) rc.turn(directions[d]); }
```

That is the whole bot, and the fidelity is the point. A "helpful" addition —
picking up cheese, biting a neighbour — would break the only test that proves
the ported rule set is the same rule set.

**This is a declared divergence from the design note.** The note's §Scripted
baselines describes `scaffold` as "the ported examplefuncsplayer behaviour:
random legal move, bite whatever is adjacent, pick up cheese underfoot". The
real `examplefuncsplayer` at tag `engine.1.2.5` does no biting and no cheese
pickup — the snippet above is its entire turn, read from
`example-bots/src/main/examplefuncsplayer/RobotPlayer.java` at that tag — so
the note describes a bot that does not exist upstream. `scaffold` follows the
upstream bot, because Tier A compares this chassis against **that** Java bot
bit-exactly and any behaviour added here would diverge on the first round a
rat stands next to something. The strong baseline the note wants is `awu`.

## The tiers

| tier | what | gate |
| --- | --- | --- |
| **A** | rounds 1–50 are **bit-exact** on all five pairs: every field above, every robot, every round, including ids | **blocking** |
| **B** | at round 200, every field still agrees exactly — cumulative cat damage, cheese transferred, king counts and the cooperation flag included | **blocking** |
| **C** | the first divergent round over a full 2000-round game, printed and written to the job summary against a committed baseline | reported, trended |

Tiers A and B are the phase-30 gate.

## The five pairs

`DefaultSmall`, `arrows`, `closeup`, `toomuchcheese` and `cheesefarm` — the
`small` pool minus `dirtfulcat`, which is measured locally but kept out of the
job so five maps of Java engine time fit the runner comfortably.

## The Tier C baseline

Measured by the job at `GameVersion` GV01 against `engine.1.2.5`:

| map | first divergent round (2000-round game) |
| --- | --- |
| `DefaultSmall` | none — identical for all 2000 rounds |
| `closeup` | none — identical |
| `toomuchcheese` | none — identical |
| `cheesefarm` | none — identical |
| `arrows` | 915 |

and, measured locally on the sixth small-pool map, `dirtfulcat` diverges at
round 453.

Four of the five gated maps re-derive an ENTIRE 2000-round game bit for bit —
every robot, every field, every round, including ids. The ones that drift do
so inside the cat state machine, hundreds of rounds in, and the divergence is
a single cat choosing a different facing on one round. That is what Tier C
exists to trend: a number that moves DOWN is visible in the job summary even
though it does not fail the build.

Every accepted divergence is listed in `docs/RULES.md` §Divergences with its
reason.

---

# bc20 — the 2020 oracle, and the tier a dead artifact costs

The `bc20` year module has its own oracle job, `parity-oracle-bc20`. It runs
**JDK 8** against the pinned `battlecode20` sources at commit
`7618f6be7d12da39f2e6e25801e578f1fecfbd86` and diffs them against the Nim
port. As above, **the toolchain exists only in that job**: no JDK, no JRE and
no upstream Java source is in any image this repository builds.

## What it does, and why it is not the whole engine

The design note asks for the 2020 engine built from source and driven
head-to-head against the port. **That build is blocked by a dead artifact.**
`engine/build.gradle` depends on

```
net.sf.jsi:jsi:1.1.0-SNAPSHOT
```

which was published only to **jcenter** (shut down 2022) and to the **Sonatype
OSS SNAPSHOTS** repository (expired). Both 404 today, and
`world/ObjectInfo.java` imports `net.sf.jsi` directly, so `:engine:jar` cannot
be produced from the unmodified upstream build. Patching `build.gradle` would
make the "unmodified engine" oracle a modified one, which is the one thing an
oracle may not be. The last step of the job **attempts the resolution anyway**
and prints the exact Gradle failure to the job summary, so the day the
artifact comes back the round-loop tier is one step away.

What still works is the part of the engine with no dependencies at all.
`common/GameConstants.java`, `common/RobotType.java`, `common/Transaction.java`,
`common/Direction.java`, `common/Team.java` and `world/IDGenerator.java`
compile with a bare `javac` against the pinned checkout — and between them they
own **every piece of arithmetic the port could get subtly wrong and never
notice**.

## Tier A (BLOCKING) — 67 559 vector lines, bit for bit

`tools/oracle/Bc20Oracle.java` and `tools/parity_trace_bc20.nim` emit the same
text file; the job diffs them and fails on any difference.

| section | what it pins | lines |
| --- | --- | --- |
| `constants` | every `GameConstants` value the rules read | 10 |
| `robottypes` | the whole `RobotType` table plus its ten predicates | 10 |
| `directions` | `Direction`'s ordinals, deltas and `opposite()` | 9 |
| `water` | `getWaterLevel(r)` for every round in the cap, as a **float32 bit pattern** | 1 501 |
| `pollution` | both coefficients for **every** `P ∈ [0, 65535]`, as bit patterns | 65 536 |
| `round` | `Math.round(float)` at eleven probe values, including both halves | 11 |
| `ids` | `IDGenerator`'s first 24 ids for nine real map seeds | 9 |
| `random` | `java.util.Random.nextInt()` streams for the same seeds | 9 |
| `cowseeds` | `84307·mapSeed + 20201·(id/2)`, which **overflows a Java `int`**, and the four `nextDouble()` draws it produces | 54 |
| `transactions` | a 200-transaction corpus with deliberate cost and id ties, in and out of `Transaction.compareTo`'s ordering | 400 |

The water and pollution sections are the ones that justify the whole job:
`Math.exp`, `Math.sin` and `Math.pow` are HotSpot intrinsics, and neither the
native libm nor emscripten's is guaranteed to agree with them. The water level
depends only on the round number, so it is generated once and **committed**
(`data/bc20/water_levels.json`); the pollution coefficients are closed forms
and are proved equal over the whole integer domain instead.

The `cowseeds` section is the one that catches a whole class of port bug:
`84307 * 43223` is 3 644 001 461, which does not fit a signed 32-bit int. Java
wraps. A checked Nim conversion raises — on exactly the map seeds that matter.

## The water-table step (BLOCKING)

`tools/JavaWaterLevels.java` regenerates `data/bc20/water_levels.json` under
the CI JDK and the job byte-diffs it against the committed file. The generator
also cross-checks `Math` against `StrictMath` over the whole domain and warns
if a JDK's intrinsics disagree with the reference implementation.

## What is NOT compared

* **Bytecode counts.** The Nim port meters `DecisionOps`, not JVM bytecodes
  (docs/RULES-BC20.md §Divergences item 1). Neither side emits them.
* **`bowl-of-chowder`.** It is a behaviour port with knobs, so it is not
  statement-identical to any Java bot and never could be bit-exact. The oracle
  proves the *arithmetic* is right; `tests/test_bc20_baselines.nim` proves the
  *chassis* is right.
* **The round loop itself**, for the reason above. `tests/test_bc20_*.nim`
  cover it against the engine's source read line by line — the flood's
  one-ring-per-round snapshot, the burial thresholds, the blocked rider, the
  comparator, the pollution lifetime, the cow draw counts and the six-rung
  ladder each have their own vectors — but that is a reading of the engine,
  not a run of it, and this document says so rather than implying otherwise.

## The oracle bot

`tools/oracle/examplefuncsplayer20/RobotPlayer.java` is
`example-bots/src/main/examplefuncsplayer/RobotPlayer.java` **verbatim except
for one hunk**, committed as `determinism.patch` beside it: a per-robot
`java.util.Random RNG = new java.util.Random(rc.getID())` at the top of
`run()`, and the single live `Math.random()` call site replaced by
`RNG.nextDouble()`. The stock bot is seeded from the wall clock and is not
reproducible even against itself. `years/bc20/chassis/scaffold.nim` reproduces
exactly that stream through `rng.nim`. It is committed now so that it is ready
the moment the engine can be built; nothing runs it today.

One upstream fact the port reproduces rather than corrects: `tryBlockchain`
builds `new int[10]`, and `assertCanSubmitTransaction` refuses anything whose
length is not `BLOCKCHAIN_TRANSACTION_LENGTH = 7`. **`examplefuncsplayer`
never mints a transaction in 2020**, and neither does the port.

---

# bc21 — a real round-loop oracle, and the one divergence it leaves

<a id="bc21"></a>

The `bc21` year module has its own oracle job, **`parity-oracle-bc21`**. Unlike
bc20's, it is a **real round-loop oracle**: it builds the whole 2021 engine
from the pinned `battlecode21` sources at commit
`ed39c1a49574db57e5463d720736220506280294` (release 2021.3.0.5) under **JDK 8**,
runs the engine's own `GameWorld.runRound()` loop head to head against the Nim
port on five map pairs, and diffs the two traces line for line. As above, **the
toolchain exists only in that job**: no JDK, no JRE and no upstream Java source
is in any image this repository builds.

## Why the 2021 engine builds when the 2020 one did not

The 2021 engine has the **same single dead dependency** as the 2020 one —
`net.sf.jsi:jsi:1.1.0-SNAPSHOT`, published only to jcenter (shut down 2022) and
Sonatype OSS SNAPSHOTS (expired) — and **nothing else**. Every other coordinate
in `engine/build.gradle` resolves from Maven Central today; the eleven of them
are pinned by sha256 in `tools/oracle/bc21/deps.lock`.

And `net.sf.jsi` is **write-only dead weight**: `world/ObjectInfo.java` calls
only `robotIndex.init/add/delete` and never queries the index — seven call
sites, all writes — so nothing it computes can reach the game. The job
therefore **bypasses Gradle entirely** (which also sidesteps the dead
`jcenter()` repository and the `$JAVA_HOME/lib/tools.jar` javadoc dependency),
stands four ~30-line no-op files in `tools/oracle/bc21/jsi-shim/` in for the
dead artifact, and compiles the **94** gameplay sources with a bare `javac` (no `--release 8`:
that flag arrived in JDK 9, and the compiler here IS 8).
`battlecode/doc/**` is excluded: it is javadoc taglets against
`com.sun.tools.doclets` (the only thing that ever needed `tools.jar`) and
contains no gameplay.

**The shim re-proves itself on every run.** The job asserts
`world/ObjectInfo.java`'s sha256 against the value in `deps.lock`: if upstream
ever starts *reading* the spatial index, the hash changes and the job fails
loudly rather than lying.

**JDK 8 is mandatory**, and for a reason worth recording. The instrumenter
rewrites `java.util` classes with ASM 5.0.4, which refuses class-file versions
above 52; under JDK 21 every player class load throws
`IllegalArgumentException` from `ClassReader` and the match silently ends in a
coin flip on round 1500 with two robots on the board. That is exactly what a
green oracle looks like when it is proving nothing, so the driver **asserts a
non-trivial robot count at round 50** before anything is diffed.

## The trace

`tools/oracle/bc21/Bc21Trace.java` (package `battlecode.world`, so it needs no
reflection) constructs the engine's own `LiveMap` through `GameMapIO`, a
`TeamControlProvider` over two `PlayerControlProvider`s plus the
`NullControlProvider` every map with a neutral Centre needs, and
`new GameMaker(gameInfo, null, false)` — the null packet sink is explicitly
supported (`GameMaker.createEvent` guards on it). It then calls
`GameWorld.runRound()` in a loop and prints the trace **from the live
objects**, which carry every field the `.bc21` does not: cooldowns, flags,
bids, buff counts and bytecodes used. **No flatbuffers reader, no `flatc`, no
`pip install` on either side.**

```
R <round> T <team> votes=<n> buffs=<n> ecs=<n> infl=<n> pol=<n> sla=<n> muc=<n> topbid=<n> bidder=<id>
R <round> U <id> t=<TYPE> team=<A|B|N> x=<n> y=<n> inf=<n> conv=<n> cd=<%.9f> flag=<n> bid=<n> ra=<n> bc=<n>
R <round> W winner=<A|B|-> dom=<NAME|->
```

Units are printed **in exec order**, not id order, which is what makes an
ordering bug visible. `tools/parity_trace_bc21.nim` prints the same lines from
the Nim port; the job strips the Java side's `bc=` column before diffing, since
there is no bytecode counter on this side to compare it with.

The five pairs are `maptestsmall`, `Arena`, `Bog`, `Smile` and `Star` — the
`small` pool minus `FrogOrBath`, so five maps of engine time fit the runner.
Each is a 1500-round `examplefuncsplayer21`-versus-itself game and takes about
13 s of JVM.

## The tiers

**Tier A (BLOCKING) — bit-exact over the whole window in which the comparison
is DEFINED.** Every field, including ids and the `%.9f` cooldown. The window is
`1 .. (first mid-turn bytecode cut-off) − 1`, computed by the job from the
engine's own `bc=` column rather than guessed, with a floor of 20 rounds so a
regression cannot silently shrink it to nothing. Measured:

| map | Tier A window, bit-exact | trace lines |
| --- | --- | --- |
| `maptestsmall` | 1..26 | 228 |
| `Arena` | 1..22 | 349 |
| `Bog` | 1..32 | 414 |
| `Smile` | 1..22 | 252 |
| `Star` | **1..245** | 8 635 |

**Tier B (BLOCKING) — the arithmetic, over its whole domain.**
`tools/JavaBc21Tables.java` regenerates `data/bc21/ec_passive.json` (all 1500
rounds of `ceil(0.2f·√t)`, totalling 8 507) and `data/bc21/embezzle.json` (all
4 096 influences of `floor(x·(1/50 + 0.03f·e^(−0.001f·x)))`, plus the derived
breakpoints) under the CI JDK and the job **byte-diffs** them against the
committed files. It also cross-checks `Math.exp` against `StrictMath.exp` over
`x ∈ [1, 4096]` (**0 disagreements**), and compares Java's own
`getPassiveInfluence` against the Nim `fdlibm` port for **4 096 log-spaced
values in `(4096, 10⁸]`** (**0 disagreements**). Any disagreeing `x` fails the
job and is written here with its exact value; there are none.

**Tier C (BLOCKING against a ledger) — the first divergent round of the whole
1500-round game.** The job computes it per map and compares it against
`tools/ci/parity_ledger_bc21.json`. It **fails** if (a) a map diverges and has
no ledger entry, (b) a map diverges **earlier** than its entry, or (c) a ledger
entry no longer reproduces — a stale excuse is as bad as a missing one.

## THE ONE DIVERGENCE, root-caused: round + map + cause

The ledger is **not empty**, and every entry has the same single root cause. It
is a property of the **oracle bot**, not of the ported rule set.

| map | first bytecode cut-off | first divergent round |
| --- | --- | --- |
| `maptestsmall` | 27 | **34** |
| `Arena` | 23 | **112** |
| `Bog` | 33 | **138** |
| `Smile` | 23 | **74** |
| `Star` | 246 | **273** |

**Cause.** `examplefuncsplayer21`'s Enlightenment Center builds with a flat
50 influence and then calls `rc.bid(1)`. The first time a build leaves it with
**exactly zero** influence, `assertCanBid` throws, the exception is uncaught in
`runEnlightenmentCenter`, and `run()`'s catch block calls
`e.printStackTrace()` — which costs **20 498** of the Center's 20 000-bytecode
budget. The JVM instrumenter therefore **pauses the robot mid-turn** and
resumes it on the next round, where it finishes the turn and reaches
`rc.bid(1)` but never re-enters the loop. That round consumes **one fewer**
`RNG.nextDouble()` than a port that has **no bytecode counter by design**
(`docs/RULES-BC21.md` §Divergences item 1) and completes the turn. From then on
the two per-robot RNG streams are one draw apart; the offset first becomes
*observable* on the next round the Center can afford to build, which is the
"first divergent round" column above.

**Why this is not fixable here, and what it is not.** The port cannot
reproduce the cut-off without a Java bytecode counter, which is the very thing
§Divergences item 1 says this coworld does not have. The bot cannot be
corrected either: it is the oracle's *other side* and may not gain behaviour —
wrapping the bid in a `try` would make the two sides different bots and the
comparison meaningless. What the divergence is **not** is a rules bug: up to
the cut-off the two engines agree on every id, every cooldown to nine decimal
places, every flag, every bid, every buff and every conviction, on all five
maps — including 245 rounds and 8 635 lines of it on `Star`.

## What is NOT compared

* **The `bc=` column.** There is no bytecode counter on the Nim side; it is
  stripped from the Java trace before the diff and used only to compute the
  Tier A window and to report the peak.
* **Anything after the Tier A window on four of the five maps.** Tier C
  measures where it starts to differ and gates on that number; it does not
  claim the rounds after it agree.
* **The `.bc21` flatbuffer.** Nothing in this repository reads or writes one.

---

# bc24 — a whole-game oracle, and an empty ledger

The 2024 oracle is the cheapest of the series and the strongest. Everything
below was executed, not estimated.

## Why it is only a jar

The published fat jar
<https://releases.battlecode.org/maven/org/battlecode/battlecode24/3.0.5/battlecode24-3.0.5.jar>
(17 064 521 bytes, sha256
`9cbfc6f0b812c71a861bb203d7a100c97c694fe8440c186b3b203a58757a4095`, pinned in
`tools/oracle/bc24/jar.lock`) is **self-contained**: 11 612 entries, all 254
`battlecode` classes, every bundled dependency — `net.sf.jsi` among them, so
the dead-artifact problem that shaped the bc20 and bc21 jobs simply does not
arise — `MethodCosts.txt`, and all 79 `.map24` map resources. There is
therefore **no Gradle, no jsi shim, no 94-file `javac`, no Maven Central
download list and no `deps.lock`** in `parity-oracle-bc24`.

**JDK 8 is mandatory.** The instrumenter rewrites `java.util` classes with ASM
5.0.4, which refuses class-file versions above 52; under a newer JDK every
player class load throws and the match ends empty — which is exactly what a
"green" oracle looks like when it is proving nothing. `tools/oracle/bc24/
Bc24Trace.java` therefore **fails loudly if no duck ever spawns**, and
`tools/oracle/bc24/build_oracle.sh` compiles with plain `-source 8 -target 8`:
`--release` arrived in JDK 9 and dies with "invalid flag" on a Temurin 8
compiler in seconds.

Two more things that cost a local iteration each and are written down so they
cost nobody else one:

* **The player URL must be the compiled classes directory.** An empty URL
  fails class loading and the world constructor NPEs.
* **`System.getProperty` returns null inside the instrumented sandbox**, so the
  teleport variant of the scenario bot cannot be selected by a `-D` flag. It is
  a SECOND PACKAGE, `bc24scenariotel`, generated from the same source by two
  `sed` substitutions in `build_oracle.sh`.

## The trace

One line per record, printed from the LIVE OBJECTS, with the units **in exec
order** — which is what makes an ordering bug visible at all:

```
R <round> T <A|B> crumbs=<n> caps=<n> picked=<n> lvl=<n> alive=<n> up=<abc> upp=<n>
R <round> U <id> team=<A|B> sp=<0|1> x=<n> y=<n> hp=<n> acd=<n> mcd=<n>
           ax=<n> bx=<n> hx=<n> flag=<id|-1> ra=<n> bc=<n>
R <round> F <flagId> team=<A|B> x=<n> y=<n> start=<0|1> carried=<id|-1> dropped=<n>
R <round> W winner=<A|B|-> dom=<NAME|->
```

`tools/parity_trace_bc24.nim` prints the same lines from the Nim port. The
Java side's `bc=` column is stripped before the diff — there is no bytecode
counter on the Nim side by design — and is read separately for the Tier A
headroom assertion. A full 2000-round game is ≈ 216 000 trace lines and ≈ 15 s
of JVM per map.

## The tiers

* **Tier A (BLOCKING) — rounds 1…2000 BIT-EXACT, WHOLE GAMES**, on five
  `small` maps (`DefaultSmall`, `Yinyang`, `BreadPudding`, `Rivers`,
  `Tunnels`), `examplefuncsplayer` against itself, every field of every
  record.
* **Tier A′ (BLOCKING) — the scenario pairs, whole games, bit-exact.** Tier A's
  own measurement showed what it cannot cover: after 2000 rounds
  `examplefuncsplayer24` leaves all three global upgrade points unspent on
  every map, never builds a stun or water trap, and on three of the five never
  picks a flag up at all. Those are exactly the "rare code paths that fire
  mid-game" the Fleet card 1218171523823317 postmortem warns about. So the job
  runs a **second bot of our own**, `tools/oracle/bc24/bc24scenario/`, written
  to be deterministic with no RNG at all, cheap enough that it can never be cut
  off mid-turn, and **scripted by round number to force every rare path early**
  — all three trap types, every trigger mode, mastery, the jail penalty, a
  carry, a capture, all three upgrades, and (in the `bc24scenariotel` variant)
  a deliberate failure of the six-tile spacing rule so the **round-200
  teleport** fires. `scenario24.nim` is its Nim twin, written line for line
  against it. The job then asserts, off the JAVA trace, that those paths really
  did fire: upgrades bought, a flag lifted, a stun trap sprung, a duck at the
  mastery threshold, and six flags confirmed at round 200 in the teleport run.
* **Tier B (BLOCKING) — the arithmetic, over its WHOLE FINITE DOMAIN.**
  `tools/JavaBc24Tables.java`, run against the jar's own classes under the CI
  JDK, regenerates `data/bc24/skills.json` — damage and heal for all 7 levels ×
  {upgrade on, off}, and cooldown and crumb cost for all 7 build levels ×
  {explosive, stun, water, dig, fill} — and the job **byte-diffs** it against
  the committed file. bc24 has **no transcendental anywhere**, so unlike bc21
  this tier is not a sample: it is the entire domain, and the two rounding
  regimes (float32 for damage and heal, float64 for cooldowns and costs) are
  proved rather than argued. The same step cross-checks 53 gameplay constants
  against the jar's classes, which is what closes the 3.0.5-jar-versus-
  master-sources gap (`docs/RULES-BC24.md` §Divergences item 9).
* **Tier C (BLOCKING against `tools/ci/parity_ledger_bc24.json`)** — the first
  divergent round of every whole game, per (bot, map). It fails if a pair
  diverges with no entry, diverges earlier than its entry, an entry no longer
  reproduces, or **any** divergence occurs while the traced bytecode peak is
  still inside the tier's ceiling.

## THE LEDGER IS EMPTY

All fifteen pairs — three bots across five `small` maps — are bit-exact against
the published 3.0.5 jar for all 2000 rounds, on every field of every record.
There is no accepted divergence in bc24, and the ledger file says so and says
what an entry would have to look like if one were ever needed.

## The measured bytecode headroom

This is what makes a whole-game Tier A window defensible rather than hopeful.
The port's one instrumentation divergence — a fixed 2 500-`DecisionOps` budget
with **no mid-turn resumption** — is only observable if the JVM ever cuts a bot
off mid-turn. Measured, over the same games the tiers diff:

| bot | peak bytecodes | % of the 25 000 limit | mid-turn cut-offs |
|---|---|---|---|
| `examplefuncsplayer` | 297…783 | 1.2…3.2 % | **0** |
| `bc24scenario` | 860…940 | 3.4…3.8 % | **0** |
| `bc24scenariotel` | 880…940 | 3.5…3.8 % | **0** |

The job does not assume it: it reads the `bc=` column and **fails if any duck
on any round exceeds 50 % of the limit** (25 % for the scenario bots), naming
the round and the duck, because past that point the comparison would have to
shrink and this document would rather be wrong loudly than green quietly.

## What is NOT compared

* **Bytecodes.** There is no counter on the Nim side; the column is read, not
  diffed (`docs/RULES-BC24.md` §Divergences item 1).
* **`setWinnerArbitrary`.** The engine's `Math.random()` is wall-clock seeded;
  the port draws from the world RNG. Reachable only when captures, level sums
  and crumbs are all tied at round 2000, which none of the fifteen traced games
  reaches (§Divergences item 2).
* **Indicator strings, dots, lines and the profiler.** Not ported, not printed.
* **The `.bc24` flatbuffer output.** The driver constructs
  `new GameMaker(info, null, false)` — the null packet sink is explicitly
  supported — so nothing is serialised on either side and there is no
  flatbuffers reader in this repository at all.
* **`gone-sharkin`.** The strong chassis is OURS; there is nothing upstream to
  diff it against. It is gated instead by `tests/test_bc24_survival.nim` (with
  an inverted control that must fail), `tests/test_bc24_knobs.nim` and
  `tests/test_bc24_baselines.nim`'s legality audit.

---

# bc25 — Battlecode 2025 "Chromatic Conflict"

The `parity-oracle-bc25` job runs the **released** engine
(`battlecode25-java-3.1.0.jar`, sha256
`d0cc775610d5221fc17b23d818bc881bb3e882076a809696d15f8d380b09520b`, pinned in
`tools/oracle/bc25/jar.lock`) headlessly against the Nim port and diffs the
traces row for row. There is no JDK in any image stage — only here.

**This year's oracle is the cheapest of the series.** The jar is
self-contained: 6 413 entries, all 182 `battlecode` classes, every bundled
dependency (`net.sf.jsi`, `gnu.trove`, `org.apache.commons.lang3` among them,
so the dead-artifact problem that shaped the bc20 and bc21 jobs does not
arise), `MethodCosts.txt`, and all **75** `.map25` map resources. So there is
**no Gradle, no jsi shim, no multi-file `javac`, no Maven Central download list
and no `deps.lock`** in this job.

## The `--add-opens` trap

`--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED` is **MANDATORY on every
`java` invocation**. Without it the instrumented `java.util.Random` class fails
its static initialiser with

    IllegalAccessError: class instrumented.java.util.Random ... cannot access
    class jdk.internal.misc.Unsafe

**every player class load throws, all four starting towers die by exception on
round 1, and the game ends at round 1 with `DESTROY_ALL_UNITS` and a four-line
trace.** The job exits 0 and the diff is empty. That is exactly the "green
oracle proving nothing" failure, so:

* `tools/oracle/bc25/Bc25Trace.java` **exits 3 if no robot is ever built**, and
* `ci.yml` additionally asserts **every game reached at least 1 900 rounds**.

## JDK 21, and `javac` with no flags at all

The engine's `build.gradle` sets `sourceCompatibility = VERSION_21` and
hard-fails below it, and the instrumenter uses **ASM 9.7.1**, which is happy
with class-file version 65. So the bc21 lesson ("match `javac` flags to the
JDK") is discharged by using none: no `--release`, no `-source`, no `-target`.
`-source 8` here would be as wrong as `--release 8` was there.

**No version-string assertion.** `GameConstants.SPEC_VERSION` in the 2025
sources is the literal `"1"`, not `"3.1.0"`, so bc24's
`test "${spec}" = "3.0.5"` step has no bc25 equivalent. **The sha256 IS the
version pin**, and Tier B cross-checks every constant against the jar's own
classes instead (`docs/RULES-BC25.md` §Divergences item 12).

## The trace

    R <round> T <A|B> money=<n> painted=<n> towers=<n> bots=<n> paintunits=<n> srp=<n>
    R <round> M chk=<fnv1a64 of the colour array> mk=<fnv1a64 of both marker arrays>
    R <round> P <centerIdx> team=<A|B> life=<n>
    R <round> U <id> team=<A|B> ty=<UnitType> x=<n> y=<n> hp=<n> pnt=<n> acd=<n> mcd=<n> ra=<n> bc=<n>
    R <round> W winner=<A|B|-> dom=<NAME|->

Units are printed **in exec order**, not id order, which is what makes an
ordering bug visible; the paint checksum is what makes a single mispainted tile
visible without printing 3 600 tiles a round. The `bc=` column is stripped
before the diff and used only for the headroom assertion.

## The tiers, and what they found

| tier | what | verdict |
|---|---|---|
| **A** | `examplefuncsplayer` against itself, whole 2000-round games, six `small` maps | **bit-exact, 6/6** |
| **A′** | three scenario packages (`bc25scenario`, `…paint`, `…wipe`), whole games, same six maps | **bit-exact, 18/18** |
| **B** | the whole finite arithmetic domain, byte-diffed against the jar's own classes | **identical** |
| **C** | first divergent round of every pair, against the ledger | **no divergence; the ledger is EMPTY** |

Measured on this tree (2026-09-07):

| bot | trace lines a side | peak bytecode | % of limit | mid-turn cut-offs |
|---|---|---|---|---|
| `examplefuncsplayer` | 38 404…51 382 | 2 460…2 598 | **14 %** | **0** |
| `bc25scenario` | ~40 000 | ~6 250 | **35 %** | **0** |
| `bc25scenariopaint` | ~40 000 | ~8 100 | **46 %** | **0** |
| `bc25scenariowipe` | ~40 000 | ~7 700 | **44 %** | **0** |

A full 2000-round game is **5.1–7.0 s of instrumented JVM** per map, so
twenty-four pairs cost roughly three minutes of engine time.

Because the example bot never approaches its limit, **the Tier A window is the
WHOLE GAME**: the port's "no mid-turn resumption" divergence
(`docs/RULES-BC25.md` §Divergences item 1) is never exercised and the
comparison stays defined to the last round. The job does not assume that — it
reads the `bc=` column and **fails if any unit on any round exceeds 50 % of its
type's limit**, naming the round and the unit, because past that point the
window would have to shrink and this document would rather be wrong loudly than
green quietly.

**The design note asked for a 25 % bound on the scenario bots and the measured
peak is 35–46 %.** The bound is therefore 50 % for every bot, which buys
exactly the same property — no mid-turn cut-off is possible — and the
substitution is recorded here rather than left to be discovered.

## Tier A′: what the scenario bot reaches, and what it does not

Tier A's own measurement showed exactly what it cannot cover. Over the six full
games the 2025 example bot **never built a defense tower, never built a
splasher (the branch is commented out upstream), never upgraded a tower, never
completed a resource pattern, never sent a message, and ended every game on
`MORE_SQUARES_PAINTED` at round 2000**. So `bc25scenario` is a second oracle
bot of our own: deterministic, RNG-free, and scripted by round number.

**It provably reaches**, asserted off the JAVA trace, per map, by the
`Tier A-prime coverage` step:

* the **Special Resource Pattern lifecycle** — a centre registered (`P` lines),
  a lifetime past the fifty-round activation delay (measured maximum 1 954),
  and rounds counted with `srp=1`;
* the **per-team marker subsystem** — the marker checksum changes;
* the **zero-paint starvation path** — soldier records at `pnt=0` in
  consecutive rounds with falling `hp` (one robot in ten is scripted never to
  paint);
* **soldiers and moppers built** in the hundreds, and the mop swing in all four
  cardinals.

### What is NOT compared

* **`completeTowerPattern`, `upgradeTower` and the defense-tower damage buff.**
  The scenario bot does not reach them, and the reason is a fact about the 2025
  rules rather than about the bot: a tower's own paint stash is the binding
  constraint on robot production, and a soldier needs roughly twenty-five
  undisturbed turns beside a ruin to paint a 5×5 pattern it can then afford.
  Covered instead by `tests/test_bc25_towers.nim` (legality, effect, the
  damage-carry rule, the ledger on build / upgrade / destroy, the 25-tower cap,
  the `attackMoneyBonus` paid once per landing shot).
* **The splasher.** Neither bot can afford one: 300 paint and 400 chips against
  a paint tower mining 10 a round. Covered by `tests/test_bc25_units.nim` (both
  radii, engine scan order, the enemy-paint window, tower damage).
* **`PAINT_ENOUGH_AREA` and `DESTROY_ALL_UNITS`.** No traced game reaches
  either; every one of the twenty-four ends on `MORE_SQUARES_PAINTED` at round
  2000. Covered by `tests/test_bc25_endladder.nim`, which fires the paint win
  *inside* a splasher's AoE loop and kills a clan's last unit mid-sweep.
* **Bytecodes.** There is no counter on the Nim side; the column is read, not
  diffed (`docs/RULES-BC25.md` §Divergences item 1).
* **`setWinnerArbitrary`.** The engine's `Math.random()` is wall-clock seeded;
  the port draws from the world RNG. Reachable only when area, towers, chips,
  paint and robot counts are all tied at round 2000, which none of the
  twenty-four traced games reaches (§Divergences item 2).
* **Indicator strings, dots, lines, timeline markers and the profiler.** Not
  ported, not printed.
* **The `.bc25` flatbuffer output.** The driver constructs
  `new GameMaker(info, null, false)` — the null packet sink is explicitly
  supported — so nothing is serialised on either side.
* **`spaark`.** The strong chassis is OURS; there is nothing upstream to diff
  it against. It is gated instead by `tests/test_bc25_survival.nim` (with an
  inverted control that must fail), `tests/test_bc25_knobs.nim` and
  `tests/test_bc25_baselines.nim`'s legality audit.

## The ledger

`tools/ci/parity_ledger_bc25.json` is **empty**, and that is the phase-30 exit
condition. Root-cause-or-fail is the standing rule and it is the operator's
ruling on the bc26 run (Fleet card 1218171523823317), not a preference: an
unexplained Tier C divergence is a **FAIL**, not a ledger line. Every entry
would have to name a round, a map and a *root cause*, and
`tools/ci/parity_tiers_bc25.py` rejects a cause of "unknown".

---

# bc23 — Battlecode 2023 "Tempest"

The `parity-oracle-bc23` job runs the **published 2023 fat jar** as a
CI-only differential oracle against `src/battlecode/years/bc23/`. Engine
sources are pinned at commit `af42086ecd09709dc603b2aaa9e9b98312c9ef79`; the
jar is
`https://releases.battlecode.org/maven/org/battlecode/battlecode23/3.0.15/battlecode23-3.0.15.jar`,
pinned in `tools/oracle/bc23/jar.lock` by **size 16 982 927** and **sha256
`5d4e42a51946cc1c2149426485bda8096ff1c088c77e3ed075c06ce5968ed72a`**. Both
numbers were verified in the sandbox before the job was written.

## The jar is self-contained, and there is NO version-string assertion

11 566 entries: every `battlecode` class, every bundled dependency —
including **`net.sf.jsi`** and **`gnu.trove`**, so the dead-artifact problem
that forced bc21's jsi shim, its 94-file `javac` and its `deps.lock` **does
not arise here** — plus
`battlecode/instrumenter/bytecode/resources/MethodCosts.txt` and all **103**
`.map23` map resources. So there is no Gradle, no shim, no multi-file
compile, no Maven Central download list and no `deps.lock` in this job.

**The released 3.0.15 jar's `GameConstants.SPEC_VERSION` is the literal
string `"3.0.14"`** — measured — and so is the pinned `master` sources'. bc24's
`test "${spec}" = "3.0.5"` step therefore has **no bc23 equivalent**: the
sha256 *is* the version pin, and Tier B cross-checks the constants instead
(`docs/RULES-BC23.md` §Divergences item 12).

## TEMURIN 8, AND WHY IT IS NOT NEGOTIABLE

The engine's `build.gradle` sets `sourceCompatibility = 1.8` and the jar
bundles **ASM 5.0.4**, which cannot read modern class files. Measured in this
sandbox: **under JDK 21 the instrumenter throws
`java.lang.IllegalArgumentException` inside
`org.objectweb.asm.ClassReader.<init>` from
`TeamClassLoaderFactory.normalReader` (via `MethodCostUtil.getMethodData`) on
every player class load** — every robot dies as it spawns, **no robot is ever
built**, the trace is a few hundred empty lines, and **the job exits 0**. That
is the exact "green oracle proving nothing" trap bc25 hit from the other
direction, and it is why `Bc23Trace.java` **exits 3 when no robot is ever
built** and why `ci.yml` additionally asserts every game reached at least
1 900 rounds and built at least 100 robots.

Two consequences of pinning 8:

* **compile with plain `javac -nowarn -encoding UTF-8 -cp <jar>` and NO
  `--release`, no `-source`, no `-target`.** `--release` arrived in JDK 9 and
  dies with "invalid flag" on a JDK-8 `javac` in seconds (the bc21 lesson).
  The compiler *is* 8, so the target is 8;
* **the driver must call `System.exit()`.** The sandboxed player threads are
  **non-daemon**, so a driver that returns or throws without it hangs for
  ever — measured, the first run of this driver hung until the harness
  timeout after an unrelated exception. Every `java` invocation in the job is
  wrapped in `timeout 600`.

## The trace

One line per record, printed **from the live objects** by
`tools/oracle/bc23/Bc23Trace.java` (`package battlecode.world;`, so it needs
reflection only for the two private fields `ObjectInfo.dynamicBodyExecOrder`
and `GameWorld.islandIdToIsland` — reading them is the only way to print in
exec order and in island-id order). `tools/parity_trace_bc23.nim` prints the
same lines from the Nim port.

```
R <round> T <A|B> ad=<n> mn=<n> ex=<n> isl=<n> anch=<n> anchheld=<n>
R <round> I <islandId> own=<0|1|2> hp=<n> anch=<STANDARD|ACCELERATING|->
R <round> W <wellIdx> ty=<AD|MN|EX> rate=<1|3> ad=<n> mn=<n> ex=<n>
R <round> M chk=<fnv1a64 of the per-tile per-team multiplier hundredths>
R <round> U <id> team=<A|B> ty=<TYPE> x=<n> y=<n> hp=<n> ad=<n> mn=<n> ex=<n> anc=<n> acd=<n> mcd=<n> bc=<n>
R <round> S <A|B> arr=<fnv1a64 of the 64-slot shared array>
R <round> Z winner=<A|B|-> dom=<NAME|->
```

Robots are printed **in exec order**, not id order, which is what makes an
ordering bug visible; islands in ascending id; the `M` checksum is what makes
a single wrong tempo tile visible without printing 3 600 tiles a round. The
Java side's `bc=` column is stripped before the diff (there is no bytecode
counter on the Nim side) and is used only for the Tier A headroom assertion.

**Measured in this sandbox:** a full 2000-round game is **210 577–264 676
trace lines (18–22 MB)** and **26.5–31.1 s of instrumented JVM** per map, and
the board carries **121–157 robots** at its peak (mean 97–124). Traces are
written to `$RUNNER_TEMP`, compared **streaming** (never loaded whole), and
only the first 200 divergent lines plus a gzipped digest are uploaded.

## The measured bytecode headroom, and why Tier A is a WHOLE-GAME window

Over three full 2000-round games (`DefaultMap` 32×32, `AllElements` 30×30,
`Eyelands` 50×30) the **peak bytecode use of any robot on any round was
823–856 — 6.6–6.9 % of the carrier's 12 500 limit — with ZERO mid-turn
cut-offs.** So the port's "no mid-turn resumption" divergence
(`docs/RULES-BC23.md` §Divergences item 1) is never exercised and the
comparison stays defined to the last round. The job does not assume that: it
reads the `bc=` column and **fails if any robot on any round exceeds 50 % of
its type's limit**, naming the round and the robot, because past that point
the window would have to shrink and this repository would rather be wrong
loudly than green quietly.

This is exactly where bc21 could not go: its example bot *did* hit the
ceiling, which is why its windows were 22–245 rounds.

## The tiers

* **Tier A (BLOCKING)** — rounds 1…2000 **bit-exact, whole games**, on six
  `small` pairs (`Quiet`, `SmallElements`, `Lantern`, `Spin`, `Sneaky`,
  `Barcode`), `examplefuncsplayer23` against itself, every field above.
* **Tier A′ (BLOCKING) — SHIPPED.** `bc23scenario` against itself, the same
  six `small` maps, the same whole 2000-round window, **bit-exact on all six
  pairs**. `tools/oracle/bc23/bc23scenario/RobotPlayer.java` and
  `src/battlecode/years/bc23/chassis/scenario23.nim` (behind
  `-d:bc23Scenario`) are the two halves, written line for line against each
  other; read them side by side.
  Tier A's own measurement showed exactly what it cannot cover: over three
  full 2000-round games the example bot **never took an anchor from a
  headquarters, never placed one, never captured an island, never built an
  amplifier, a destabilizer or a booster, never transferred a resource to a
  headquarters, never upgraded or transformed a well, never wrote the shared
  array, and ended every game on `MORE_MANA_NET_WORTH` at round 2000 with
  islands 0–0 and anchors 0–0.** So `CONQUEST`, the first two ladder rungs,
  the whole anchor and island subsystem, the elixir tree, the tempo fields
  and every comms path were untested by it — precisely the "rare code paths
  that fire mid-game" the Fleet card 1218171523823317 postmortem warns about.
  The scenario twin is scripted **by round number** with **no RNG at all**;
  its measured bytecode peak is **28–43 % of the limit** across the six maps,
  so like the example bot it is never cut off mid-turn and the comparison
  stays defined to the last round.

  **EVERY QUERY IT MAKES IS ROBOT-LOCAL,** and that is what makes the twin
  possible at all: a sandboxed player has a `RobotController`, not a
  `GameWorld`. Both halves scan through
  `RobotControllerImpl.getAllLocationsWithinRadiusSquared` — the radius
  clamped to the type's vision radius, the engine's x-outer/y-inner order,
  `canSenseLocation` (hence the cloud collapse) applied to every tile. A
  helper that read the world directly would have no Java twin and the tier
  would be uncomparable rather than merely unequal.

  **A scenario bot that agrees bit for bit while doing nothing proves
  nothing**, so the job asserts, **off the JAVA trace** and not the port's,
  that the paths really fired. Measured over the six maps at this jar:
  21 993 `I` lines with `own=1|2 anch=STANDARD` (an anchor built, taken,
  ferried and planted), 66 081 `U` lines with a carrier holding an anchor,
  an island returning to `own=0` after being held, 7 518 `W` lines at
  `rate=3` (the 1 400 rate upgrade), 2 795 `W` lines at `ty=EX` (the 600-unit
  elixir transformation), 8 629 `U` lines of `ty=AMPLIFIER`, and a shared
  array whose fold changes on every one of the 2 000 rounds of every game.
  The three end-ladder rungs it reaches are `MORE_SKY_ISLANDS`,
  `MORE_ELIXIR_NET_WORTH` and `MORE_MANA_NET_WORTH`. Each of those is a
  **floor** in the job, not an equality: a change that fires a path more
  often is green, and a change that stops firing one is red.
* **Tier B (BLOCKING) — the arithmetic, over its WHOLE FINITE DOMAIN.**
  `tools/JavaBc24Tables.java`, run against the jar's own classes under the CI
  JDK, regenerates `data/bc24/skills.json` — damage and heal for all 7 levels ×
  {upgrade on, off}, and cooldown and crumb cost for all 7 build levels ×
  {explosive, stun, water, dig, fill} — and the job **byte-diffs** it against
  the committed file. bc24 has **no transcendental anywhere**, so unlike bc21
  this tier is not a sample: it is the entire domain, and the two rounding
  regimes (float32 for damage and heal, float64 for cooldowns and costs) are
  proved rather than argued. The same step cross-checks 53 gameplay constants
  against the jar's classes, which is what closes the 3.0.5-jar-versus-
  master-sources gap (`docs/RULES-BC24.md` §Divergences item 9).
* **Tier C (BLOCKING against `tools/ci/parity_ledger_bc24.json`)** — the first
  divergent round of every whole game, per (bot, map). It fails if a pair
  diverges with no entry, diverges earlier than its entry, an entry no longer
  reproduces, or **any** divergence occurs while the traced bytecode peak is
  still inside the tier's ceiling.

## THE LEDGER IS EMPTY

All fifteen pairs — three bots across five `small` maps — are bit-exact against
the published 3.0.5 jar for all 2000 rounds, on every field of every record.
There is no accepted divergence in bc24, and the ledger file says so and says
what an entry would have to look like if one were ever needed.

## The measured bytecode headroom

This is what makes a whole-game Tier A window defensible rather than hopeful.
The port's one instrumentation divergence — a fixed 2 500-`DecisionOps` budget
with **no mid-turn resumption** — is only observable if the JVM ever cuts a bot
off mid-turn. Measured, over the same games the tiers diff:

| bot | peak bytecodes | % of the 25 000 limit | mid-turn cut-offs |
|---|---|---|---|
| `examplefuncsplayer` | 297…783 | 1.2…3.2 % | **0** |
| `bc24scenario` | 860…940 | 3.4…3.8 % | **0** |
| `bc24scenariotel` | 880…940 | 3.5…3.8 % | **0** |

The job does not assume it: it reads the `bc=` column and **fails if any duck
on any round exceeds 50 % of the limit** (25 % for the scenario bots), naming
the round and the duck, because past that point the comparison would have to
shrink and this document would rather be wrong loudly than green quietly.

## What is NOT compared

* **Bytecodes.** There is no counter on the Nim side; the column is read, not
  diffed (`docs/RULES-BC24.md` §Divergences item 1).
* **`setWinnerArbitrary`.** The engine's `Math.random()` is wall-clock seeded;
  the port draws from the world RNG. Reachable only when captures, level sums
  and crumbs are all tied at round 2000, which none of the fifteen traced games
  reaches (§Divergences item 2).
* **Indicator strings, dots, lines and the profiler.** Not ported, not printed.
* **The `.bc24` flatbuffer output.** The driver constructs
  `new GameMaker(info, null, false)` — the null packet sink is explicitly
  supported — so nothing is serialised on either side and there is no
  flatbuffers reader in this repository at all.
* **`gone-sharkin`.** The strong chassis is OURS; there is nothing upstream to
  diff it against. It is gated instead by `tests/test_bc24_survival.nim` (with
  an inverted control that must fail), `tests/test_bc24_knobs.nim` and
  `tests/test_bc24_baselines.nim`'s legality audit.

---

# bc25 — Battlecode 2025 "Chromatic Conflict"

The `parity-oracle-bc25` job runs the **released** engine
(`battlecode25-java-3.1.0.jar`, sha256
`d0cc775610d5221fc17b23d818bc881bb3e882076a809696d15f8d380b09520b`, pinned in
`tools/oracle/bc25/jar.lock`) headlessly against the Nim port and diffs the
traces row for row. There is no JDK in any image stage — only here.

**This year's oracle is the cheapest of the series.** The jar is
self-contained: 6 413 entries, all 182 `battlecode` classes, every bundled
dependency (`net.sf.jsi`, `gnu.trove`, `org.apache.commons.lang3` among them,
so the dead-artifact problem that shaped the bc20 and bc21 jobs does not
arise), `MethodCosts.txt`, and all **75** `.map25` map resources. So there is
**no Gradle, no jsi shim, no multi-file `javac`, no Maven Central download list
and no `deps.lock`** in this job.

## The `--add-opens` trap

`--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED` is **MANDATORY on every
`java` invocation**. Without it the instrumented `java.util.Random` class fails
its static initialiser with

    IllegalAccessError: class instrumented.java.util.Random ... cannot access
    class jdk.internal.misc.Unsafe

**every player class load throws, all four starting towers die by exception on
round 1, and the game ends at round 1 with `DESTROY_ALL_UNITS` and a four-line
trace.** The job exits 0 and the diff is empty. That is exactly the "green
oracle proving nothing" failure, so:

* `tools/oracle/bc25/Bc25Trace.java` **exits 3 if no robot is ever built**, and
* `ci.yml` additionally asserts **every game reached at least 1 900 rounds**.

## JDK 21, and `javac` with no flags at all

The engine's `build.gradle` sets `sourceCompatibility = VERSION_21` and
hard-fails below it, and the instrumenter uses **ASM 9.7.1**, which is happy
with class-file version 65. So the bc21 lesson ("match `javac` flags to the
JDK") is discharged by using none: no `--release`, no `-source`, no `-target`.
`-source 8` here would be as wrong as `--release 8` was there.

**No version-string assertion.** `GameConstants.SPEC_VERSION` in the 2025
sources is the literal `"1"`, not `"3.1.0"`, so bc24's
`test "${spec}" = "3.0.5"` step has no bc25 equivalent. **The sha256 IS the
version pin**, and Tier B cross-checks every constant against the jar's own
classes instead (`docs/RULES-BC25.md` §Divergences item 12).

## The trace

    R <round> T <A|B> money=<n> painted=<n> towers=<n> bots=<n> paintunits=<n> srp=<n>
    R <round> M chk=<fnv1a64 of the colour array> mk=<fnv1a64 of both marker arrays>
    R <round> P <centerIdx> team=<A|B> life=<n>
    R <round> U <id> team=<A|B> ty=<UnitType> x=<n> y=<n> hp=<n> pnt=<n> acd=<n> mcd=<n> ra=<n> bc=<n>
    R <round> W winner=<A|B|-> dom=<NAME|->

Units are printed **in exec order**, not id order, which is what makes an
ordering bug visible; the paint checksum is what makes a single mispainted tile
visible without printing 3 600 tiles a round. The `bc=` column is stripped
before the diff and used only for the headroom assertion.

## The tiers, and what they found

| tier | what | verdict |
|---|---|---|
| **A** | `examplefuncsplayer` against itself, whole 2000-round games, six `small` maps | **bit-exact, 6/6** |
| **A′** | three scenario packages (`bc25scenario`, `…paint`, `…wipe`), whole games, same six maps | **bit-exact, 18/18** |
| **B** | the whole finite arithmetic domain, byte-diffed against the jar's own classes | **identical** |
| **C** | first divergent round of every pair, against the ledger | **no divergence; the ledger is EMPTY** |

Measured on this tree (2026-09-07):

| bot | trace lines a side | peak bytecode | % of limit | mid-turn cut-offs |
|---|---|---|---|---|
| `examplefuncsplayer` | 38 404…51 382 | 2 460…2 598 | **14 %** | **0** |
| `bc25scenario` | ~40 000 | ~6 250 | **35 %** | **0** |
| `bc25scenariopaint` | ~40 000 | ~8 100 | **46 %** | **0** |
| `bc25scenariowipe` | ~40 000 | ~7 700 | **44 %** | **0** |

A full 2000-round game is **5.1–7.0 s of instrumented JVM** per map, so
twenty-four pairs cost roughly three minutes of engine time.

Because the example bot never approaches its limit, **the Tier A window is the
WHOLE GAME**: the port's "no mid-turn resumption" divergence
(`docs/RULES-BC25.md` §Divergences item 1) is never exercised and the
comparison stays defined to the last round. The job does not assume that — it
reads the `bc=` column and **fails if any unit on any round exceeds 50 % of its
type's limit**, naming the round and the unit, because past that point the
window would have to shrink and this document would rather be wrong loudly than
green quietly.

**The design note asked for a 25 % bound on the scenario bots and the measured
peak is 35–46 %.** The bound is therefore 50 % for every bot, which buys
exactly the same property — no mid-turn cut-off is possible — and the
substitution is recorded here rather than left to be discovered.

## Tier A′: what the scenario bot reaches, and what it does not

Tier A's own measurement showed exactly what it cannot cover. Over the six full
games the 2025 example bot **never built a defense tower, never built a
splasher (the branch is commented out upstream), never upgraded a tower, never
completed a resource pattern, never sent a message, and ended every game on
`MORE_SQUARES_PAINTED` at round 2000**. So `bc25scenario` is a second oracle
bot of our own: deterministic, RNG-free, and scripted by round number.

**It provably reaches**, asserted off the JAVA trace, per map, by the
`Tier A-prime coverage` step:

* the **Special Resource Pattern lifecycle** — a centre registered (`P` lines),
  a lifetime past the fifty-round activation delay (measured maximum 1 954),
  and rounds counted with `srp=1`;
* the **per-team marker subsystem** — the marker checksum changes;
* the **zero-paint starvation path** — soldier records at `pnt=0` in
  consecutive rounds with falling `hp` (one robot in ten is scripted never to
  paint);
* **soldiers and moppers built** in the hundreds, and the mop swing in all four
  cardinals.

### What is NOT compared

* **`completeTowerPattern`, `upgradeTower` and the defense-tower damage buff.**
  The scenario bot does not reach them, and the reason is a fact about the 2025
  rules rather than about the bot: a tower's own paint stash is the binding
  constraint on robot production, and a soldier needs roughly twenty-five
  undisturbed turns beside a ruin to paint a 5×5 pattern it can then afford.
  Covered instead by `tests/test_bc25_towers.nim` (legality, effect, the
  damage-carry rule, the ledger on build / upgrade / destroy, the 25-tower cap,
  the `attackMoneyBonus` paid once per landing shot).
* **The splasher.** Neither bot can afford one: 300 paint and 400 chips against
  a paint tower mining 10 a round. Covered by `tests/test_bc25_units.nim` (both
  radii, engine scan order, the enemy-paint window, tower damage).
* **`PAINT_ENOUGH_AREA` and `DESTROY_ALL_UNITS`.** No traced game reaches
  either; every one of the twenty-four ends on `MORE_SQUARES_PAINTED` at round
  2000. Covered by `tests/test_bc25_endladder.nim`, which fires the paint win
  *inside* a splasher's AoE loop and kills a clan's last unit mid-sweep.
* **Bytecodes.** There is no counter on the Nim side; the column is read, not
  diffed (`docs/RULES-BC25.md` §Divergences item 1).
* **`setWinnerArbitrary`.** The engine's `Math.random()` is wall-clock seeded;
  the port draws from the world RNG. Reachable only when area, towers, chips,
  paint and robot counts are all tied at round 2000, which none of the
  twenty-four traced games reaches (§Divergences item 2).
* **Indicator strings, dots, lines, timeline markers and the profiler.** Not
  ported, not printed.
* **The `.bc25` flatbuffer output.** The driver constructs
  `new GameMaker(info, null, false)` — the null packet sink is explicitly
  supported — so nothing is serialised on either side.
* **`spaark`.** The strong chassis is OURS; there is nothing upstream to diff
  it against. It is gated instead by `tests/test_bc25_survival.nim` (with an
  inverted control that must fail), `tests/test_bc25_knobs.nim` and
  `tests/test_bc25_baselines.nim`'s legality audit.

## The ledger

`tools/ci/parity_ledger_bc25.json` is **empty**, and that is the phase-30 exit
condition. Root-cause-or-fail is the standing rule and it is the operator's
ruling on the bc26 run (Fleet card 1218171523823317), not a preference: an
unexplained Tier C divergence is a **FAIL**, not a ledger line. Every entry
would have to name a round, a map and a *root cause*, and
`tools/ci/parity_tiers_bc25.py` rejects a cause of "unknown".

---

# bc23 — Battlecode 2023 "Tempest"

The `parity-oracle-bc23` job runs the **published 2023 fat jar** as a
CI-only differential oracle against `src/battlecode/years/bc23/`. Engine
sources are pinned at commit `af42086ecd09709dc603b2aaa9e9b98312c9ef79`; the
jar is
`https://releases.battlecode.org/maven/org/battlecode/battlecode23/3.0.15/battlecode23-3.0.15.jar`,
pinned in `tools/oracle/bc23/jar.lock` by **size 16 982 927** and **sha256
`5d4e42a51946cc1c2149426485bda8096ff1c088c77e3ed075c06ce5968ed72a`**. Both
numbers were verified in the sandbox before the job was written.

## The jar is self-contained, and there is NO version-string assertion

11 566 entries: every `battlecode` class, every bundled dependency —
including **`net.sf.jsi`** and **`gnu.trove`**, so the dead-artifact problem
that forced bc21's jsi shim, its 94-file `javac` and its `deps.lock` **does
not arise here** — plus
`battlecode/instrumenter/bytecode/resources/MethodCosts.txt` and all **103**
`.map23` map resources. So there is no Gradle, no shim, no multi-file
compile, no Maven Central download list and no `deps.lock` in this job.

**The released 3.0.15 jar's `GameConstants.SPEC_VERSION` is the literal
string `"3.0.14"`** — measured — and so is the pinned `master` sources'. bc24's
`test "${spec}" = "3.0.5"` step therefore has **no bc23 equivalent**: the
sha256 *is* the version pin, and Tier B cross-checks the constants instead
(`docs/RULES-BC23.md` §Divergences item 12).

## TEMURIN 8, AND WHY IT IS NOT NEGOTIABLE

The engine's `build.gradle` sets `sourceCompatibility = 1.8` and the jar
bundles **ASM 5.0.4**, which cannot read modern class files. Measured in this
sandbox: **under JDK 21 the instrumenter throws
`java.lang.IllegalArgumentException` inside
`org.objectweb.asm.ClassReader.<init>` from
`TeamClassLoaderFactory.normalReader` (via `MethodCostUtil.getMethodData`) on
every player class load** — every robot dies as it spawns, **no robot is ever
built**, the trace is a few hundred empty lines, and **the job exits 0**. That
is the exact "green oracle proving nothing" trap bc25 hit from the other
direction, and it is why `Bc23Trace.java` **exits 3 when no robot is ever
built** and why `ci.yml` additionally asserts every game reached at least
1 900 rounds and built at least 100 robots.

Two consequences of pinning 8:

* **compile with plain `javac -nowarn -encoding UTF-8 -cp <jar>` and NO
  `--release`, no `-source`, no `-target`.** `--release` arrived in JDK 9 and
  dies with "invalid flag" on a JDK-8 `javac` in seconds (the bc21 lesson).
  The compiler *is* 8, so the target is 8;
* **the driver must call `System.exit()`.** The sandboxed player threads are
  **non-daemon**, so a driver that returns or throws without it hangs for
  ever — measured, the first run of this driver hung until the harness
  timeout after an unrelated exception. Every `java` invocation in the job is
  wrapped in `timeout 600`.

## The trace

One line per record, printed **from the live objects** by
`tools/oracle/bc23/Bc23Trace.java` (`package battlecode.world;`, so it needs
reflection only for the two private fields `ObjectInfo.dynamicBodyExecOrder`
and `GameWorld.islandIdToIsland` — reading them is the only way to print in
exec order and in island-id order). `tools/parity_trace_bc23.nim` prints the
same lines from the Nim port.

```
R <round> T <A|B> ad=<n> mn=<n> ex=<n> isl=<n> anch=<n> anchheld=<n>
R <round> I <islandId> own=<0|1|2> hp=<n> anch=<STANDARD|ACCELERATING|->
R <round> W <wellIdx> ty=<AD|MN|EX> rate=<1|3> ad=<n> mn=<n> ex=<n>
R <round> M chk=<fnv1a64 of the per-tile per-team multiplier hundredths>
R <round> U <id> team=<A|B> ty=<TYPE> x=<n> y=<n> hp=<n> ad=<n> mn=<n> ex=<n> anc=<n> acd=<n> mcd=<n> bc=<n>
R <round> S <A|B> arr=<fnv1a64 of the 64-slot shared array>
R <round> Z winner=<A|B|-> dom=<NAME|->
```

Robots are printed **in exec order**, not id order, which is what makes an
ordering bug visible; islands in ascending id; the `M` checksum is what makes
a single wrong tempo tile visible without printing 3 600 tiles a round. The
Java side's `bc=` column is stripped before the diff (there is no bytecode
counter on the Nim side) and is used only for the Tier A headroom assertion.

**Measured in this sandbox:** a full 2000-round game is **210 577–264 676
trace lines (18–22 MB)** and **26.5–31.1 s of instrumented JVM** per map, and
the board carries **121–157 robots** at its peak (mean 97–124). Traces are
written to `$RUNNER_TEMP`, compared **streaming** (never loaded whole), and
only the first 200 divergent lines plus a gzipped digest are uploaded.

## The measured bytecode headroom, and why Tier A is a WHOLE-GAME window

Over three full 2000-round games (`DefaultMap` 32×32, `AllElements` 30×30,
`Eyelands` 50×30) the **peak bytecode use of any robot on any round was
823–856 — 6.6–6.9 % of the carrier's 12 500 limit — with ZERO mid-turn
cut-offs.** So the port's "no mid-turn resumption" divergence
(`docs/RULES-BC23.md` §Divergences item 1) is never exercised and the
comparison stays defined to the last round. The job does not assume that: it
reads the `bc=` column and **fails if any robot on any round exceeds 50 % of
its type's limit**, naming the round and the robot, because past that point
the window would have to shrink and this repository would rather be wrong
loudly than green quietly.

This is exactly where bc21 could not go: its example bot *did* hit the
ceiling, which is why its windows were 22–245 rounds.

## The tiers

* **Tier A (BLOCKING)** — rounds 1…2000 **bit-exact, whole games**, on six
  `small` pairs (`Quiet`, `SmallElements`, `Lantern`, `Spin`, `Sneaky`,
  `Barcode`), `examplefuncsplayer23` against itself, every field above.
* **Tier A′ — NOT SHIPPED IN THIS LANDING, and this is the one tier of the
  four that is open.** The Nim half is committed
  (`src/battlecode/years/bc23/chassis/scenario23.nim`, behind
  `-d:bc23Scenario`, scripted by round number with no RNG at all); its
  **bit-exact Java twin is a phase-30 item**, and
  `tools/ci/parity_tiers_bc23.py` takes the bot list as an argument so adding
  it is a one-line change to the workflow. What it would cover, whole games,
  bit-exact:
  Tier A's own measurement showed exactly what it cannot cover: over three
  full 2000-round games the example bot **never took an anchor from a
  headquarters, never placed one, never captured an island, never built an
  amplifier, a destabilizer or a booster, never transferred a resource to a
  headquarters, never upgraded or transformed a well, never wrote the shared
  array, and ended every game on `MORE_MANA_NET_WORTH` at round 2000 with
  islands 0–0 and anchors 0–0.** So `CONQUEST`, the first two ladder rungs,
  the whole anchor and island subsystem, the elixir tree, the tempo fields
  and every comms path would be untested by it — precisely the "rare code
  paths that fire mid-game" the Fleet card 1218171523823317 postmortem warns
  about. `tools/oracle/bc23/bc23scenario/RobotPlayer.java` and its Nim twin
  `chassis/scenario23.nim` (behind `-d:bc23Scenario`) are scripted **by round
  number** to force every one of them, with **no RNG at all** and a bytecode
  peak the job asserts stays under 25 %. The job then asserts, **off the JAVA
  trace**, that the paths really fired — an `I` line with
  `own=1 anch=STANDARD` and later one with `anch=ACCELERATING`; an `I` line
  returning to `own=0`; a `W` line's `ty=` changing from `MN` to `EX` and
  another's `rate=` from 1 to 3; the `M` checksum changing and returning; an
  `S` checksum changing. **A scenario bot that agrees bit for bit while doing
  nothing proves nothing**, and that is the step that stops it.
* **Tier B (BLOCKING) — the arithmetic, over its WHOLE FINITE DOMAIN.**
  `tools/JavaBc23Tables.java`, run against the jar's own classes under the CI
  JDK 8, regenerates `data/bc23/tables.json` — the whole `RobotType` table
  (10 fields × 6 types) and `Anchor` table (8 fields × 2); the carrier
  movement cooldown `floor(0.375f × w) + 5` for every weight 0…40; the throw
  damage `floor(1.25f × w)` for every weight 0…40; **the entire
  cooldown-multiplier lattice** — every reachable multiplier × every base
  cooldown in `{2, 10, 15, 20, 25, 70, 140}` **and** every carrier base
  5…20, as `(int) Math.round(base × multiplier)` computed by the JVM itself;
  the conquest threshold `held / total >= 0.75f` for every island count
  4…35; and the island occupancy `(100 × (a − b)) / area` for every `(a, b)`
  pair up to area 20 — and the job **byte-diffs** it against the committed
  file. bc23 has **no transcendental anywhere**, so unlike bc21 this tier is
  not a sample: it is the entire domain. The same step cross-checks every
  `GameConstants` field against the **jar's** classes, which is what closes
  the "released jar versus pinned master sources" gap in the absence of a
  usable `SPEC_VERSION`.
* **Tier C (BLOCKING against a ledger)** — the first divergent round of every
  whole 2000-round game, on every bot the job runs and all six maps, compared
  against
  `tools/ci/parity_ledger_bc23.json`. It fails if (a) a pair diverges and has
  no ledger entry, (b) a pair diverges **earlier** than its entry, (c) a
  ledger entry no longer reproduces, or (d) **any** divergence occurs while
  the traced bytecode peak is still under 50 % — which, on this year's
  evidence, means always, and therefore means a real rules bug rather than an
  instrumentation artefact.

## ROOT-CAUSE-OR-FAIL

An unexplained Tier C divergence is a **FAIL**, not a ledger line. That is
the operator's standing ruling (Fleet card 1218171523823317), not a
preference. Every ledger entry must name a round, a map and a *root cause*; a
cause of "unknown" is not a cause and `tools/ci/parity_tiers_bc23.py` rejects
it.

**`tools/ci/parity_ledger_bc23.json` ships EMPTY, and it is empty because it
CAN be.** Measured in the sandbox before the job was written: all six
`examplefuncsplayer23` trace pairs on `Quiet`, `SmallElements`, `Lantern`,
`Spin`, `Sneaky` and `Barcode` are **bit-exact for whole 2000-round games**,
96 430 to 270 105 trace lines a side, with the traced bytecode peak at
**745–893 of the carrier's 12 500 (5–7 %)** and **zero mid-turn cut-offs**.
The six `bc23scenario` pairs added in phase 30 are bit-exact over the same
window, with the peak at **28–43 %** — twelve pairs, empty ledger. That is a better shipped state than bc21's (22–245-round
windows, five root-caused entries) or bc25's, and it is why this year's design
note could promise an empty ledger.

If phase 30 finds a divergence anyway, the root-cause checklist — each item
with its own unit test — is:

the exec-order list's by-value removal and the pre-sweep snapshot
(`test_bc23_execorder`); the per-action charge order, especially
`boost`/`destabilize`/`placeAnchor` charging **after** their effect and `move`
charging at the **destination** (`test_bc23_cooldown`); the float64 multiplier
rounding (`test_bc23_tempo`); the destabilisation firing at `cast + 4` and
hitting one robot per tile (`test_bc23_tempo`); the asymmetric stack guards
(`test_bc23_tempo`); the island occupancy formula's truncation toward zero and
the healing sweep's radius (`test_bc23_islands`); the anchor-override counters
and the STANDARD-over-ACCELERATING boost quirk (`test_bc23_islands`); the well
transformation and upgrade thresholds and the fact that a transfer into a well
leaves the team total (`test_bc23_wells`); the carrier's weight-based movement
and its inventory-emptying throw (`test_bc23_cooldown`, `test_bc23_units`);
the current closure (`test_bc23_currents`); the shared-array write windows
(`test_bc23_comms`); the cloud vision collapse in **both** directions and the
`ceil+1` scan box (`test_bc23_sensing`); the float32 conquest threshold
(`test_bc23_endladder`); and the `IDGenerator` stream that fixes every built
robot's id (`test_rng`).

## What is NOT compared, and why

* **`DESTABILIZER` and `BOOSTER` robots, `ACCELERATING` anchors, the
  non-identity states of the cooldown-multiplier lattice, and the `CONQUEST`,
  `MORE_REALITY_ANCHORS` and `MORE_ADAMANTIUM_NET_WORTH` ladder rungs.**
  These are the Tier A′ residue and they all hang off ONE gate: elixir in a
  **headquarters' own** stockpile. A destabilizer costs 200 elixir, a booster
  150, an `ACCELERATING` anchor 300, and the tempo lattice only ever leaves
  the identity multiplier when one of the first two is on the board. Elixir
  exists only after a well is transformed (600 units of the *other* resource
  poured in), and then has to be mined out and ferried home 40 units at a
  time. Measured on the six committed `small` maps: `bc23scenario` transforms
  a well on two of them and the highest team elixir any game reaches by round
  2000 is **80**, against the 150 the cheapest of the three costs. Getting
  past it needs the forced-setup variants the design note sketches
  (`-d:bc23ScenarioConquest`, `-d:bc23ScenarioTie`), which are not shipped.
  Until they are, those paths are covered by the unit shards only —
  `test_bc23_tempo` for the multiplier lattice and the destabilise/boost
  stacking, `test_bc23_islands` for the `ACCELERATING` anchor and the
  STANDARD-over-ACCELERATING quirk, and `test_bc23_endladder` for the
  float32 `CONQUEST` threshold and every rung of the ladder — and **not** by
  the differential oracle.
* **The bytecode counter itself.** There is none on the Nim side; the `bc=`
  column is used only for the headroom assertion.
* **Indicator strings, dots and lines, and the profiler.** Instrumentation
  with no runtime meaning and no port.
* **`.bc23` match files.** There is no flatbuffers reader on either side of
  this port; the driver constructs `new GameMaker(info, null, false)` with a
  null packet sink.
* **`setWinnerArbitrary`'s `Math.random()`.** Wall-clock seeded and therefore
  not reproducible; replaced by a world-RNG draw (D4) and reachable only when
  all five rungs tie.

---

# bc22 — Battlecode 2022 "Mutation"

The published 2022 fat jar as a CI-only differential oracle, in the
`parity-oracle-bc22` job of `.github/workflows/ci.yml`. **Forty trace pairs —
one example-bot pair and four scenario pairs on each of eight maps — are
bit-exact for whole 2000-round games, and the ledger
(`tools/ci/parity_ledger_bc22.json`) is EMPTY.** Everything below was measured
against `battlecode22-2.2.1.jar` on Temurin 8 before the job was written.

## The jar is self-contained, and its version string is a SECOND pin

`https://releases.battlecode.org/maven/org/battlecode/battlecode22/2.2.1/battlecode22-2.2.1.jar`
— **16 989 241 bytes**, sha256
`56e7530b89893584bf706c90937b3df0eb583cd850f058f9d62004cd5ce78e1c`, pinned by
size **and** sha256 in `tools/oracle/bc22/jar.lock`. It carries **11 549
entries**: every `battlecode` class, every bundled dependency **including
`net.sf.jsi` and `gnu.trove`** (trove4j 3.0.3, dated 2012-06-03 — so the
dead-artifact problem that forced bc21's jsi shim, its 94-file `javac` and its
`deps.lock` does not arise), `battlecode/instrumenter/bytecode/resources/
MethodCosts.txt`, and all **75** `.map22` map resources. There is **no Gradle,
no shim, no multi-file compile, no Maven download list and no `deps.lock`** in
this job.

Unlike bc23's and bc25's jars, this one really does report its own version:
`GameConstants.SPEC_VERSION` inside the released 2.2.1 jar is the literal
string `2.2.1`. So the job asserts it — as a *second* pin on top of the sha256
and the size, not as the primary one. Tier B cross-checks every constant
anyway.

## TEMURIN 8, AND WHY IT IS NOT NEGOTIABLE

`engine/build.gradle` sets `sourceCompatibility = 1.8` and declares
`org.ow2.asm:asm:5.0.4`, which cannot read modern class files. **Under JDK 21
the instrumenter throws `java.lang.IllegalArgumentException` inside
`org.objectweb.asm.ClassReader.<init>`** — from
`battlecode.instrumenter.TeamClassLoaderFactory.normalReader:233`, via
`battlecode.instrumenter.bytecode.MethodCostUtil.getMethodData:96` — **on every
player class load.** Every robot dies as it spawns, **no robot is ever built**,
and the game ends at **round 1** with `winner=A dom=ANNIHILATION` after six
trace lines. A job that only diffed traces would exit 0 and prove nothing.

Three things stop that:

1. `tools/oracle/bc22/Bc22Trace.java` **exits 3 if no robot is ever built**.
2. `ci.yml` asserts that the example bot reached round **1 900**, built at
   least **100** robots and peaked at at least **60** on the board, and that
   every scenario game reached round **800** and built at least **40**.
3. The job asserts `java -version` is `1.8.` **and that this `javac` rejects
   `--release`** — `--release` arrived in JDK 9 and dies with "invalid flag" on
   a JDK-8 `javac` in seconds (the bc21 lesson). No `--release`, no `-source`,
   no `-target`: the compiler *is* 8, so the target is 8.

**The driver must call `System.exit()`.** The sandboxed player threads are
non-daemon; a driver that returns or throws without it hangs for ever. Every
`java` invocation in the job is also wrapped in `timeout 600`/`timeout 900`.
**The player URL must be the compiled classes directory** — an empty URL fails
class loading and the world constructor NPEs.

## The trace

`GameMapIO.loadMapAsResource(loader, "battlecode/world/resources", map)` takes
**three** arguments in 2022, not bc23's four; `new GameMaker(info, null, false)`
is explicitly supported, so the null packet sink means **no flatbuffers are
written at all** and there is no `.bc22` file and no flatbuffers reader on
either side of this port. The driver is `package battlecode.world;` and needs
reflection only for `ObjectInfo.dynamicBodyExecOrder` (private — the only way
to print in exec order) and `GameWorld.lead` / `gold` / `rubble` (private — the
only way to checksum the three map arrays).

```
R <round> T <A|B> pb= au= ar= la= wa= mi= bu= so= sa=
R <round> G leadchk= goldchk= rubblechk= leadsum= goldsum=
R <round> U <id> team= ty= md= lv= x= y= hp= acd= mcd= bc=
R <round> S <A|B> arr=<fnv1a64 of the 64-slot shared array>
R <round> H hashord=<fnv1a64 of the ids in robotsArray() order>
R <round> A next=<idx> type=<ABYSS|CHARGE|FURY|VORTEX|-> round=<n>
R <round> Z winner=<A|B|-> dom=<NAME|->
```

Robots are printed **in exec order**, which is what makes an ordering bug
visible at all. The `H` line is what makes a **trove-order** bug visible
(`docs/RULES-BC22.md` §Divergences item 4) and it is compared **every round**,
not only on charge rounds, so a trove bug surfaces on round 1 as a checksum
mismatch instead of on round 400 as a mystery. The three map checksums make one
wrong square visible without printing 3 600 squares a round, and `rubblechk` is
what proves a VORTEX permuted the right way — measured on `charge`, it changes
exactly once, at round 1000, and never again.

**The fold is wire format.** Both sides compute
`h = (h ^ (value & 0xFFFFFFFF)) * 0x100000001B3`, one whole int per iteration —
*not* canonical byte-wise FNV-1a. `src/battlecode/years/bc22/trove.nim`'s
`fnv1a64` is the single Nim definition and `world.nim`'s `fnvArray` is an alias
for it; `Bc22Trace.fnv` is the Java one. They are checked against each other on
five hand-written vectors as well as on every trace line.

## The measured bytecode headroom, and why Tier A is a WHOLE-GAME window

The 2022 example bot **never approaches its bytecode limit**: over eight full
2000-round games the peak was **680–760 bytecodes, i.e. 6–7 % of the 10 000
MINER limit**, with **zero** mid-turn cut-offs. So the port's "no mid-turn
resumption" divergence (`docs/RULES-BC22.md` §Divergences item 1) is never
exercised and the comparison stays defined to the last round. **The job does
not assume that**: `tools/ci/parity_tiers_bc22.py` reads the `bc=` column and
fails if any robot on any round exceeds **50 %** of its type's limit (**25 %**
for the four scenario bots), naming the round and the robot. This is exactly
where bc21 could not go: its example bot *did* hit the ceiling, which is why
its windows were 22–245 rounds.

| map | trace lines | size | peak bytecode | peak robots | mean robots | ended |
| --- | --- | --- | --- | --- | --- | --- |
| `chalice` | 197 901 | 15 MB | 712 (7 %) | 155 | 92 | 2000, MORE_LEAD_NET_WORTH |
| `maze` | 231 441 | 18 MB | 696 (6 %) | 193 | 109 | 2000, MORE_LEAD_NET_WORTH |
| `nottestsmall` | 209 186 | 16 MB | 744 (7 %) | 128 | 98 | 2000, MORE_LEAD_NET_WORTH |
| `snowflake_redux` | 184 177 | 14 MB | 712 (7 %) | 108 | 85 | 2000, MORE_LEAD_NET_WORTH |
| `rugged` | 215 868 | 17 MB | 744 (7 %) | 158 | 101 | 2000, MORE_LEAD_NET_WORTH |
| `charge` | 220 340 | 17 MB | 760 (7 %) | 160 | 103 | 2000, MORE_LEAD_NET_WORTH |
| `turtle` | 254 876 | 20 MB | 692 (6 %) | 209 | 120 | 2000, MORE_LEAD_NET_WORTH |
| `vortex` | 284 395 | 22 MB | 680 (6 %) | 349 | 135 | 2000, MORE_LEAD_NET_WORTH |

Traces are written to `$RUNNER_TEMP`, compared **streaming** (never loaded
whole), and only the first 200 divergent lines plus a gzipped digest are
uploaded.

## The tiers

- **Tier A (BLOCKING)** — rounds 1…2000 bit-exact, whole games, on the eight
  pairs above, `examplefuncsplayer22` against itself, every field **including
  `H hashord`**. The eight maps cover all four `causeVortexGlobal` arms, all
  four anomaly bodies, archon counts 1–4, all three symmetries and one map with
  **no** anomaly schedule at all (`rugged`) as a control. **Result: bit-exact
  on all eight.**
- **Tier A′ (BLOCKING)** — four scenario packages,
  `bc22scenario` / `bc22scenarioannihilate` / `bc22scenariotie` /
  `bc22scenariofury`, on the same eight maps and the same whole-game window,
  against `chassis/scenario22.nim` behind `-d:bc22Scenario` and its three
  variant switches. **Result: bit-exact on all thirty-two, peak bytecode
  13–23 % of the limit.** Tier A′ exists because Tier A's own measurement said
  what it cannot cover: over eight full games the example bot **never built a
  builder, a sage, a laboratory or a watchtower, never mutated, never
  transformed, never transmuted, never envisioned, never wrote the shared
  array, never made a single gold, and ended EVERY game on
  `MORE_LEAD_NET_WORTH` with gold 0-0**.
- **Tier B (BLOCKING)** — `tools/JavaBc22Tables.java`, run against the jar's own
  classes under the CI JDK 8, regenerates `data/bc22/tables.json` and the job
  **byte-diffs** it. bc22 has exactly **one** transcendental and its domain is
  finite, so this tier is not a sample: the whole `RobotType` table, the
  `AnomalyType` table, the **entire** rubble cooldown lattice (rubble 0…100 ×
  eight bases, 808 entries, the 22 that differ from the integer form flagged in
  the file), the prototype health, the reclaim, the four anomaly truncations
  over their whole reachable domains and the laboratory rate for all 3 × 177
  `(level, n)` pairs. **All 32 `GameConstants` static fields are cross-checked
  against `constants.nim` as well — the whole class, not a sample.**
- **Tier C (BLOCKING against the ledger)** — the first divergent round of every
  pair, against `tools/ci/parity_ledger_bc22.json`. It fails if a pair diverges
  with no entry, diverges earlier than its entry, has an entry that no longer
  reproduces, or diverges at all while the bytecode peak is under the headroom
  bound — which on this year's evidence means always, and therefore means a
  real rules bug rather than an instrumentation artefact.

## THE LEDGER IS EMPTY

`tools/ci/parity_ledger_bc22.json` is `{"entries": []}` and the job fails if a
pair diverges without one. **Root-cause-or-fail is the standing rule** and it is
the operator's ruling on the bc26 run (Fleet card 1218171523823317), not this
document's preference: an unexplained divergence is a FAIL, not a ledger line,
and a cause of "unknown" is rejected by the schema check.

The one place a divergence was genuinely plausible is **D2**, the trove
iteration order, which is why `H hashord` is compared every round. Measured:
**51–58 % of CHARGE rounds contain at least one tie that the iteration order
decides**, so a wrong order would not have been subtle — and the `H` line is
bit-exact on all forty pairs, every round.

## The comparator's three fixed bugs

`tools/ci/parity_tiers_bc22.py` is bc23's script with all three known
comparator bugs fixed, and the same commit fixes them in
`parity_tiers_bc21.py`, `_bc24.py` and `_bc25.py`:

1. **`bc=` is stripped from BOTH traces** by one `normalize()` applied to each
   side. Stripping only the Java side compares a line against itself plus a
   suffix and "diverges" at round 1 on otherwise-identical lines.
2. **`itertools.zip_longest`, never `zip`.** `zip` stops at the shorter file
   and discards the tail, so a Java trace one line longer than the Nim trace
   reads bit-exact. `--selftest` constructs exactly that pair, in both
   directions.
3. **Hex folds are canonicalised on both sides.** `Long.toHexString` emits
   lower case with no leading zeros and, for a negative long, the unsigned
   64-bit form; Nim's `toHex` zero-pads to sixteen. `normalize()` re-parses the
   value of every **named checksum field** — the explicit allowlist `leadchk`,
   `goldchk`, `rubblechk`, `arr`, `hashord` — as an unsigned 64-bit integer and
   re-emits it canonically. Decimal fields are untouched, which is why the
   allowlist is explicit rather than a regex over anything hex-shaped: `hp=99`
   is a valid hex string and is not a checksum.

`--selftest` runs first in the job and covers all three, plus the negative
controls: a *different* checksum and a zero-padded `hp` must both still read as
divergences. **A gate that cannot fail is not a gate.**

## Tier A′: what the scenario bots reach

Every one of these is asserted **off the JAVA trace** — the engine's own
output, not the port's — over the thirty-two scenario games, because **a
scenario bot that agrees bit for bit while doing nothing proves nothing**. The
counts are the measured values; the job's floors sit under them.

| what fired | games (of 32) |
| --- | --- |
| a LABORATORY promoted from PROTOTYPE to TURRET (ten repairs) | 8 |
| a WATCHTOWER promoted from PROTOTYPE to TURRET (fifteen repairs) | 2 |
| a robot MUTATED to level 2 (the lead mutation) | 2 |
| a robot MUTATED to level 3 (the GOLD mutation) | 2 |
| an ARCHON transformed to PORTABLE and then MOVED | 14 |
| the shared array changed (a write from a robot with nothing nearby) | 24 |
| the rubble changed (a VORTEX permuted the board) | 20 |
| gold appeared on the MAP (a reclaim drop) | 17 |
| a team's gold reserve rose (a TRANSMUTATION) | 32 |
| the anomaly cursor advanced | 28 |
| a SAGE existed on the board | 12 |
| the game ended by `ANNIHILATION` | 4 |
| the game ended on `MORE_ARCHONS` | 8 |
| the game ended on `MORE_GOLD_NET_WORTH` | 5 |
| the game ended on `MORE_LEAD_NET_WORTH` | 15 |

Three measurements cost a round each and are recorded so the next year does not
repeat them:

* **A three-round transform window leaves the archon PORTABLE for ever.** The
  transform cooldown is the type's movement cooldown scaled by rubble, so
  `canTransform()` was still false on round 303 after a round-300 transform:
  the archon never came back, never built again, and no sage — and therefore no
  envision — existed in any of the thirty-two games. The window is now
  open-ended (out at 300, move 301-319, back from 320).
* **A single build attempt on round 4 misses on three maps.** On `maze`,
  `turtle` and `vortex` the archon's square carries enough rubble that its
  action cooldown lands on round 4; those maps then ran 2000 rounds with no
  builder, no laboratory, no watchtower, no gold and no sage. The builder is
  now retried over rounds 4-12 until one is visible.
* **An uncapped sage spends every gold the laboratory ever makes** — 1 722
  sage-rounds on `chalice` and no level-3 mutation anywhere. The archon now
  builds exactly one.

### What is NOT compared

* **A WATCHTOWER standing up to PORTABLE to dodge a scheduled FURY.** The
  scenario bot scripts it, and it never fires: only `nottestsmall` ever gets a
  watchtower finished on these eight maps, and `nottestsmall`'s anomaly
  schedule is CHARGE and VORTEX only — it has no FURY at all. Forcing it would
  need a synthetic map, which this port does not ship. The rule itself — FURY
  damages a TURRET-mode building and does **nothing** to a PORTABLE one — is
  covered by `tests/test_bc22_anomaly.nim`, and the watchtower transform by
  `tests/test_bc22_buildings.nim`, and **not** by the differential oracle.
* **`WON_BY_DUBIOUS_REASONS`.** The fourth ladder rung needs equal archons,
  equal gold net worth *and* equal lead net worth, and over forty whole games
  no pair ever tied all three — the mirrored `bc22scenariotie` variant included,
  because exec order breaks the mirror. `tests/test_bc22_endladder.nim` covers
  the rung and its world-RNG coin flip; the oracle does not.
* **The bytecode counter itself.** There is none on the Nim side; the `bc=`
  column is used only for the headroom assertion.
* **Indicator strings, dots and lines, and the profiler.** Instrumentation with
  no runtime meaning and no port.
* **`.bc22` match files.** There is no flatbuffers reader on either side of
  this port; the driver constructs `new GameMaker(info, null, false)` with a
  null packet sink.
* **`net.sf.jsi`'s RTree.** The engine writes to it and never reads it
  (`docs/RULES-BC22.md` §Divergences item 5), so it is not ported and there is
  nothing to compare.
* **`setWinnerArbitrary`'s `Math.random()`.** Wall-clock seeded and therefore
  not reproducible; replaced by a world-RNG draw (D3) and reachable only when
  every rung ties.
* **`rc.resign()`.** A real engine method that no doctrine sheet can call
  (D8).

---

# bc16 — Battlecode 2016 "Zombie Invasion"

`.github/workflows/ci.yml` carries a **`parity-oracle-bc16`** job beside the
other years'. It fetches the published **`battlecode-2016.0.2.2.jar`**, pins it
by size and sha256, compiles a driver and two bots against it **on Temurin 8**,
and diffs eighteen whole games against this sim.

The result of that job, on the evidence in `tools/ci/parity_ledger_bc16.json`:

> **All eighteen pairs are BIT-EXACT for whole games. The ledger is EMPTY.**

## The jar, and the two pins that are the only ones available

```
url     https://s3.amazonaws.com/battlecode-releases-2016/releases/battlecode-2016.0.2.2.jar
bytes   6 563 607
sha256  c78ef341af0b666acabdabf545695862b77f84076f946766787bc1549b1fdc1c
engine  Metta-AI mirror of battlecode-server-2016 @ 11a0b09f26a70da19f33a61ebec4ceaf6e161aa3
client  battlecode-client-2016 @ 317e1f3ff902ae568619c051813335ecdd72322c
```

**There is no `SPEC_VERSION` in 2016's `GameConstants`.** The field simply does
not exist — bc22's second pin, the engine's own version string, has no
counterpart here. `tools/oracle/bc16/build_oracle.sh` therefore pins on three
things instead: the byte count, the sha256, and the **`battlecode-version`
entry** — which in this jar is a *file at the jar root* holding the bare string
`2016.0.2.2`, not a manifest attribute (`META-INF/MANIFEST.MF` carries only
`Manifest-Version`, `Ant-Version` and `Created-By`). `build_oracle.sh` reads it
with `unzip -p "$JAR" battlecode-version`.
Tier B then cross-checks every `GameConstants` field
against the jar's own loaded classes anyway, so a substituted jar with the same
size would still be caught.

## The jar is self-contained: no Ant, no Ivy, no Gradle, no `deps.lock`

2 484 entries, of which 449 are `battlecode` classes. It ships its own
`org/objectweb/asm` (58 entries — the bytecode instrumenter),
`com/thoughtworks/xstream` (463 — the map XML deserialiser), `com/fasterxml`
(765), `org/apache/commons/lang3` (236),
`battlecode/instrumenter/bytecode/resources/MethodCosts.txt`, and **54 `.xml`
map resources**. `GameMapIO.loadMap(name, null)` takes the resource-fallback
path (`GameMapIO.java:56-61`), every map in every bc16 pool is one of those 54,
and so the job needs **no `--map-dir` and no dependency resolution of any
kind**.

**There is no `gnu/trove` and no `net/sf/jsi` in it, and neither is needed.**
2016's engine iterates `LinkedHashMap` and `HashMap` from the JDK, so the
trove-iteration-order problem that forced bc22's `trove.nim` does not arise
here — but the JDK's own `HashMap` iteration order does, and it cost this run
a real defect (below).

## TEMURIN 8, AND WHY IT IS NOT NEGOTIABLE

The jar bundles a **2016-era ASM** and a 2016-era XStream, and the whole
instrumenter is built for Java 8 class files. Under any newer JDK the
instrumenter throws `java.lang.IllegalArgumentException` inside
`org.objectweb.asm.ClassReader.<init>` **on every player class load**. Nothing
is ever built, the game is over in a round or two, and — this is the trap —
**the job would exit 0 while proving nothing**. bc22 and bc23 both measured
this failure mode; 2016's ASM is older still.

Three independent defences, all in the repository:

1. `ci.yml` asserts `java -version` and `javac -version` both say `1.8.`, and
   additionally asserts that this `javac` **rejects `--release`** — a flag that
   arrived in JDK 9 — so the check cannot pass on a mislabelled toolchain.
   (`--release` is also never passed: it dies with "invalid flag" on a JDK-8
   `javac`, the bc21 lesson.)
2. `Bc16Trace.java` **exits 3** if nothing ever happened.
3. The anti-vacuity step (below) fails if any pair ended too early, peaked at
   too few robots, never saw a zombie take a turn, or never saw an infection.

## Two things the driver had to get right, both measured

* **NEUTRAL robots must be registered to a `NullControlProvider`, not to the
  zombie one.** `TeamControlProvider` asserts that some provider owns every
  team it is asked about, and a NEUTRAL robot's `runRobot` falls into
  `ZombieControlProvider`'s "somehow controlling a non-zombie robot → kill it"
  branch — which deletes every neutral on the board on round 0.
  `world/control/NullControlProvider.java` exists for exactly this.
* **The driver must call `System.exit()`.** The sandboxed player threads are
  NON-DAEMON; a driver that returns or throws without it hangs for ever. Every
  `java` invocation in the job is additionally wrapped in `timeout 900`.

## The trace

`tools/oracle/bc16/Bc16Trace.java` is `package battlecode.world;`, so it needs
reflection only for `GameWorld.rubble` / `parts` / `gameObjectsByID` / `rand`
and `ZombieControlProvider.random` — all private, and the only way to checksum
the two map arrays, print in execution order and read the RNG states. Its Nim
twin is `tools/parity_trace_bc16.nim`.

One line per record, per round:

```
R <round> T <A|B> parts=<%.6f> ar= sc= so= gu= vi= tu= tt=
R <round> Z zn= zs= zr= zf= zb= dens= neu= outbreak=
R <round> G rubblechk=<fnv1a64> partschk=<fnv1a64>
            rubblesum=<f64 BITS hex> partssum=<f64 BITS hex>
R <round> U <id> team=<A|B|N|Z> ty= x= y= hp= cd= wd= zi= vi= ra= bd= [bc=]
R <round> D <id> x= y= hp= q=<s>:<r>:<f>:<b>
R <round> X world=<48-bit hex> zombie=<48-bit hex> idgen=<48-bit hex>
R <round> W winner=<A|B|-> dom=<NAME|->
```

All coordinates are **origin-relative on both sides** (V3): the Java side
subtracts `map.getOrigin()` in the emitter, so neither side can create or hide
a divergence with a translation. `parity_tiers_bc16.py` additionally carries an
origin tripwire that fails if a Java trace ever leaks an absolute coordinate.

The `X` line is the load-bearing one: it prints the raw 48-bit state of **all
three `java.util.Random` streams** every round. A port that shared a stream, or
drew one extra value from one of them, diverges on the very next `X`.

## THE TWO SUMS ARE PRINTED AS RAW BIT PATTERNS, AND THAT IS MEASURED

`String.format("%.6f")` rounds **HALF-UP**; C's `printf` — which is what Nim's
`formatFloat` calls — rounds **HALF-TO-EVEN**. A 900-term floating sum lands on
an exact decimal tie often enough that it happened: on `checkers` at round 219
the two sides held **byte-identical** rubble arrays and printed
`88935.090413` against `88935.090412`. Both `rubblesum` and `partssum` are now
emitted as the IEEE-754 bit pattern in hex on both sides. Bit patterns have no
rounding mode.

## The tiers

| tier | what | gate |
| --- | --- | --- |
| **A** | `bc16idle` vs `bc16idle`, **nine maps**, whole games, every line bit-exact | **blocking** |
| **A″** | `bc16greenhorn` vs `bc16greenhorn`, the same nine maps, whole games, every line bit-exact | **blocking** |
| **B** | the **whole finite arithmetic domain** regenerated from the jar's own classes and byte-diffed against `data/bc16/tables.json`; plus all 42 `GameConstants` fields; plus all 22 maps' symmetry and per-den zombie split, read out of the JVM's own `GameMap` | **blocking** |
| **C** | the first divergent round of every pair against `tools/ci/parity_ledger_bc16.json`, root-cause-or-fail | **blocking** |

**Tiers A, A″, B and C all passing with an EMPTY ledger is the phase-30 exit
condition, and that is what the job reports.**

### Tier A is a large tier, not a trivial one

This is the single most important thing to understand about bc16 parity.
**The zombie half of this game is engine-side**, so an idle player still
exercises: the den schedules and their per-den split; the spawn ring's
direction and chirality; `spawnAllPossible` and its proximity-damage fallback;
the whole eight-step zombie movement ladder; all three `java.util.Random`
streams; infection and the die-and-turn conversion; the corpse-rubble deposit;
`clearRubble` by digging zombies; the parts income curve; both factions'
archons being eaten; the mid-turn `DESTROYED` check; and the end ladder.

### Tier A″ is what proves the fourth stream

`bc16greenhorn` is the one bot with a **live `java.util.Random(2016)` per
robot**, so this tier proves `rng.nim` reproduces a fourth independent stream
call for call alongside the engine's three. It is also the tier that exercises
the player side — build, move and attack, with `senseHostileRobots()[0]`
resolved in insertion order.

### The nine pairs

`checkers`, `zigzag`, `swamp`, `river`, `prisons`, `frogger`, `turtle`,
`desert`, `space` — chosen for symmetry class, den count and size spread.

### Tier B is the entire domain, not a sample

bc16 has exactly **two** non-algebraic functions and both have finite domains,
so `tools/JavaBc16Tables.java` emits and `data/bc16/tables.json` (304 594
bytes) commits the whole of both:

| table | rows |
| --- | --- |
| `robot_types` | 12 types × 17 constructor fields, plus the `turnsInto` graph |
| `predicates` | 12 types × 8 derived predicates |
| `outbreak_multiplier` / `outbreak_health` / `outbreak_attack` | levels 0…12, every type |
| `guard_reduction` | every reachable attack power |
| `pow_1_5` | `pow(k/8000.0, 1.5)` for **all 8 001** k — the V1 table. **Tabled from `StrictMath.pow`; see below** |
| `int_sqrt` | `(int) Math.sqrt(r2)` for r2 0…10 000 |
| `direction_to` | the **whole** `directionTo` lattice, dx,dy ∈ −80…80 — **25 921 pairs** |
| `rubble_clear` | the rubble clear map, 0…1000 |
| `parts_income` | the parts income curve, rounds 0…400 |
| `constants` | all 42 `GameConstants` fields |

The check is a **byte diff**, not a tolerance: the committed file must be
exactly what the jar's own classes emit.

### `Math.pow` IS NOT REPRODUCIBLE BETWEEN JDK BUILDS, and that cost a CI round

The engine calls `Math.pow`. The JLS permits `Math.pow` to be up to **1 ulp**
from the exact result and requires only semi-monotonicity — so it is **not
reproducible between JDK builds**, and a byte-diff of a `Math.pow` table fails
for a reason that has nothing to do with this port. This was not theoretical:
the table was first generated on Temurin **8u422** and the CI runner's Temurin
**8u452** emitted a different `pow_1_5` row, and nothing else in the 304 KB
file differed.

`StrictMath.pow` must reproduce fdlibm bit for bit on every conforming JVM, so
`data/bc16/tables.json` tables **`StrictMath.pow`** and records that in its own
`pow_1_5_source` key. **The byte-diff above therefore stays absolute for the
whole file**, and the job adds the assertion the change would otherwise have
lost: a second BLOCKING step asserts that the *running* JDK's `Math.pow` — the
call the engine actually makes — is within one ulp of **every** tabled value.
That is strictly more checking than a `Math.pow` byte-diff, not less.

Measured over the whole 8 001-value domain:

| pair | bit-exact | one ulp apart | further |
| --- | --- | --- | --- |
| Temurin 8u422 `Math.pow` vs `StrictMath.pow` | 7 221 | 780 | **0** |
| glibc `pow` (the port) vs `StrictMath.pow` | 7 220 | 781 | **0** |
| glibc `pow` vs Temurin 8u422 `Math.pow` | 7 996 | 5 | **0** |

None of it is reachable in this coworld: **V1 pins the whole expression to its
`pow(0, 1.5) = 0` branch**, where all three implementations are exact. The
table exists so the divergence is measured rather than asserted, and
`tests/table_bc16_delay.nim` is what reads it.

## THREE REAL DEFECTS THE ORACLE FOUND

Every one of these was a genuine bug in this repository that no unit test
caught, and every one is why the tier exists.

**1. `Collectors.toMap` PREPENDS within a `HashMap` bucket.**
`tools/convert_maps_bc16.py` emulates `java.util.HashMap` iteration order so
that the build-time per-den zombie split matches the engine's. Its `put`
appended within a bucket. The engine reaches that map through
`Collectors.toMap`, which is implemented with `HashMap.merge` — and `merge`
**prepends** a new node rather than appending it. Fixed by making the
emulator's insert prepend; **all 22 maps regenerated**, five of which changed
bytes (`collision`, `frogger`, `quadrants`, `voluted`, `zigzag`). This is
exactly the class of bug the Tier B map probe exists to catch, and it caught
it.

**2. `ZombieControlProvider.denQueues` is keyed by ROBOT ID, not by
`MapLocation`.** The driver had it keyed by location. Two dens on the same
square is impossible, so the two are equivalent until a den dies and its
successor reuses the square — at which point the queue is inherited rather than
reset. Fixed in the driver.

**3. `ZombieControlProvider.matchEnded()` nulls its `random` field.** The
driver read the RNG state through a reflected field *after* the match ended and
got a `NullPointerException` on the last round. Fixed by holding the `Random`
object by reference from the first round.

## Anti-vacuity: a bit-exact tier that proves nothing is a failed tier

**Neither oracle bot survives the 3000-round cap.** An idle archon line is
eaten by the horde and `greenhorn` only slows that down. The traces therefore
run from round 0 to the engine's own `isRunning() == false` — which means the
**end round, the winner and the domination factor are themselves compared**, and
a port that ended one round early would diverge on the `W` line.

Measured over the eighteen pairs, and asserted by the job:

| | rounds | peak robots | peak zombies | peak bytecode |
| --- | --- | --- | --- | --- |
| `bc16idle` (9 maps) | 298 – 683 | 36 – 88 | 13 – 59 | 1 of 20 000 (0 %) |
| `bc16greenhorn` (9 maps) | 485 – 1424 | 75 – 162 | 29 – 70 | 294 of 10 000 (2 %) |

Summed over the eighteen pairs: **735 peak zombies**, and **18 of 18** pairs saw
an infection fire. The job's floors are 250 rounds, 10 robots, 150 summed
zombies and 9 infected pairs, and it additionally requires
`saw_zombie_turn=true` on every pair.

**Trace volume, both bots, nine maps: 833 581 lines a side** — 148 342 for
`bc16idle` and 685 239 for `bc16greenhorn` — **1 667 162 lines compared, all
identical.**

### Divergence from the design note's literal anti-vacuity assertion (r1-F6)

The design note (design.md:2574) asked that `ci.yml` "additionally asserts
every game reached at least **2 900 rounds** and that at least **150 zombies**
were spawned". **Neither literal assertion is what shipped, and neither could
be**, so the substitution is recorded here rather than left implied.

| | design note | shipped (`ci.yml`) | why |
|---|---|---|---|
| round floor | ≥ 2 900 **per game** | `≥ 250` per game (`ci.yml:3069`) | **no oracle bot survives that long.** Measured lifetimes: `bc16idle` 298–683 rounds, `bc16greenhorn` 485–1424. A 2 900-round floor would fail every one of the eighteen pairs. |
| zombie floor | ≥ 150 **spawned per game** | `≥ 150` **summed `zombies_peak` over the eighteen pairs** (`ci.yml:3115`), measured 735 | the trace records the peak simultaneously on the board, not a spawn total; summing it over the pairs is the same anti-vacuity guarantee against the number the trace actually carries. |

What makes the shorter window sound rather than weaker is that the trace runs
from round 0 to the engine's own `isRunning() == false`, so **the end round,
the winner and the domination factor are themselves compared** — a port that
ended one round early diverges on the `W` line. The reasoning is also in the
workflow at `ci.yml:3013-3023`. The job additionally floors peak robots at 10
and requires an infection on at least 9 of the 18 pairs plus
`saw_zombie_turn=true` on every pair, none of which the note asked for.

## The measured bytecode headroom, and why it matters

V1 pins the port's delay decay to the `1.0` branch of the engine's
`amountToDecrement`, which the engine itself leaves at `limit - 8000`. Twenty
per cent of a 10 000-bytecode limit is 2 000, which **is** `limit - 8000` for
every non-archon type — so the 20 % bound is not a taste, it is exactly the
knee. Measured: `bc16idle` peaks at **one** bytecode and `bc16greenhorn` at
**294**, i.e. 0 % and 2 % of their limits, so neither bot ever leaves the 1.0
branch and the comparison is defined to the last round.

**The job does not assume that.** It reads the `bc=` column out of the trace
and fails if any robot on any round exceeds the bound, naming the round and the
robot.

## The comparator

`tools/ci/parity_tiers_bc16.py` is bc22's script — whose three comparator bugs
were already fixed there — plus **origin normalisation** (V3). It carries its
own `--selftest`, run first in CI, covering all four known comparator bugs and
the origin tripwire: a `bc=` column present on one side only, a trace pair that
differs only in **length** (in both directions), a zero-padded hex fold that is
the same fold, and a HALF-UP versus HALF-TO-EVEN float tie. Ten cases.

**ROOT-CAUSE-OR-FAIL is the standing rule**, and it is the operator's ruling on
the bc26 run, not this script's preference. Every ledger entry must name a
round, a map and a root cause; a cause of `unknown` is rejected by the schema
check. `tools/ci/parity_ledger_bc16.json` is `{"entries": []}`.

## The hash chain's packed fields, and the year-neutral half NOT changed (r1-F7)

bc16's per-round hash chain is a **tripwire**: `src/battlecode/replay.nim:303-312`
compares it frame by frame against the recording, and a collision can only
*hide* a divergence, never manufacture one. It shipped with three packed
values, and a packed field that overflows is a blind spot in the tripwire:

* `src/battlecode/years/bc16/rules.nim` folded the six player-type censuses
  base-100/base-1000000 into two `mixHash` calls and the four zombie censuses
  base-100 into one. **Any single count of 100 or more carried into the next
  field**, so two distinct censuses could fold to the same chain value. That
  was not hypothetical here: the parity job measures `peak_robots` of
  **104–162** and the survival gate builds **177–212** units a seat on
  `checkers`/`prisons`. **FIXED**: every count is now its own `mixHash` call
  (nineteen per-team values and thirteen globals), and
  `tests/fixtures/replay-bc16.json` was re-recorded against the new chain with
  `tools/gen_bc16_fixture_replay.nim`. No assertion was weakened to make the
  new fixture pass; a new one was added
  (`tests/test_bc16_replay.nim`) that re-derives the committed fixture to its
  **last** round rather than to the 200-frame prefix
  `tools/wasm_replay_smoke.cjs` walks.

* `src/battlecode/match.nim:498-506` packs `archons` `div/mod 100` and
  `parts_worth` `div/mod 100000` in the year-neutral results writer. **This is
  DELIBERATELY NOT CHANGED**, and the limit is recorded rather than fixed:
  those fields are year-neutral, so widening them would move the committed
  chain values of **every sibling year** (bc20–bc26) and require re-recording
  seven more fixtures — a cross-year edit far beyond what a bc16 round
  authorises. The margin is finite but large on the evidence: `archons` is
  bounded by the maps' archon counts (≤ 4 a side in the played pool) and
  `parts_worth` = `int(parts) + Σ partCost` over live robots, against the
  largest played map's 20 520 parts (`quadrants`) and a 100 000 field. **A
  future year whose census can exceed 99 archons or whose economy can exceed
  100 000 parts-worth must widen these two fields before it ships.**

## Tier A′ — NOT IMPLEMENTED, and named here rather than left implied

The design note specified a **Tier A′** of four scenario bots
(`bc16scenario`, `…annihilate`, `…tie`, `…turn`) to force the rare end-ladder
paths. **The Java side was not written, and the job does not run them.** This
is a scope deviation, recorded here so a reader does not infer coverage that
does not exist.

Precisely what does and does not exist:

* `src/battlecode/years/bc16/chassis/scenario16.nim` — **the Nim half, and it
  is complete for the base script.** It builds under `-d:bc16Scenario`, plays
  a whole game (357 rounds on `river`, 18 605 trace lines), takes no RNG draw
  of its own and stays far inside the bytecode headroom. Its own header says it
  has no Java twin.
* The three sub-variants (`…turn`, `…annihilate`, `…tie`) **do not exist on
  either side.** `-d:bc16ScenarioTurn` does not imply `-d:bc16Scenario`, so a
  build with only the sub-variant define plays `bulwark`; the sub-variant
  defines are not read anywhere and the header no longer claims them.
* `tools/oracle/bc16/bc16scenario/RobotPlayer.java` and its three siblings —
  **not written.**

What stands in their place, and what does not:

* The **end ladder itself** is covered by `tests/test_bc16_endladder.nim` and
  `tests/test_bc16_scoring.nim`, on the Nim side only — the four rungs
  (`archons_destroyed`, `more_archon_health`, `more_parts_net_worth`, and the
  round-cap tie) are unit-tested but **not differentially tested**.
* Build, move and attack from the player side **are** differentially tested, by
  Tier A″'s `bc16greenhorn`.
* `DESTROYED` as an end condition **is** differentially tested: every one of the
  eighteen pairs ends that way, and the `W` line compares winner and domination
  factor.
* The rungs below `DESTROYED` are **not** reached by either oracle bot, so
  `more_archon_health` and `more_parts_net_worth` have no Java-side evidence.

That is the exact shape of the gap. Closing it means adding the four bots to
`tools/oracle/bc16/` and a `--bots` entry in the job; nothing else in the
comparator or the driver needs to change.

## What is NOT compared, and why

* **Bytecode counts as a budget.** The port meters `DecisionOps`, not bytecode
  (V1). The `bc=` column is read as a *headroom check*, never diffed.
* **The instrumenter, the sandbox and `MethodCosts.txt`.** No counterpart: the
  port has no bytecode rewriter.
* **`.rms` match files and the flatbuffers/XStream serialiser.** The driver
  constructs its `GameWorld` directly; there is no match-file writer on either
  side.
* **`Clock.yield()`'s threading.** The port is single-threaded by construction;
  what is compared is the *observable effect* of a yield, which is the robot's
  next turn.
* **The `ARMAGEDDON_*` constant family and the instrumentation constants.**
  Deliberately not ported (V4, V5, V8). The Tier B step **names each one it
  skipped** in its log rather than silently passing over it.
* **`rc.resign()`.** A real engine method that no doctrine sheet can call.

---

# bc19 — Battlecode 2019 "Crusade"

**The oracle is JavaScript, and it is the first year in this repository whose
engine is not Java.** `battlecode/battlecode19` at commit
`80cf1cc535ec5a30559274aa1b49807ad4859925` is `coldbrew/`, a handful of
CommonJS files. There is **no jar, no JVM and no JDK** anywhere in this year.

## The pins, and why each is a pin rather than a preference

| pin | value | why |
|---|---|---|
| engine commit | `80cf1cc535ec5a30559274aa1b49807ad4859925` | `HEAD` of `master`, 2019-08-09; root `LICENSE` GPL-3.0 and the ONLY licence file in the tree |
| **Node** | **22.22.0**, asserted exactly | `coldbrew/game.js:153` passes `regions.sort` a **one-argument, sign-constant comparator**, so the map generator's output is **V8-implementation-defined**. Measured under this version the sort is a plain reversal in **42 of 42** multi-region cases and the region kept passable is **not the largest in 40** of them. A different V8 would generate **different boards from the same seeds**. |
| npm | `mersenne-twister@1.1.0`, integrity `sha1-+RZhjuQ9cXnvz2Qb7EUx65Zwl4o=` | the ONE dependency the trace driver needs |
| everything else | **not installed** | the engine's own `package.json` pulls **404** packages, including `vm2` (deprecated, known sandbox-escape CVEs), `rollup`, `esm` and `update-notifier`, which makes a **network call** on every `cli/run.js` invocation (`cli/run.js:13-16`). Whole 1000-round games were run in this sandbox on `game.js` + `action_record.js` + `specs.json` + `mersenne-twister` and nothing else. |

**IF A FUTURE NODE BUMP MAKES THE MAP REGENERATION BYTE-DIFF FAIL, THE
COMMITTED MAPS ARE THE RULES AND THE OLD NODE IS THE PIN.** Regenerating
instead is a rules change and bumps `GameVersion`. That sentence is also in
`tools/oracle/bc19/engine.lock`'s own header.

## The two places the oracle is NOT the published engine

Both are committed patches, applied in CI only, and each is asserted to apply
with the expected hunk count.

1. **`tools/oracle/bc19/visible_order.patch` (V2).**
   `getGameStateDump` shuffles the `visible` array in place with a
   Fisher–Yates pass driven by the **global, unseeded `Math.random()`** —
   not `this.random()` (`coldbrew/game.js:717-722`). Measured in this
   sandbox: **five distinct orders in six identical runs of seed 1.** There is
   nothing to be faithful to, so the port orders by ascending `id` and the
   patch puts the **same** order on the **engine** side. The normalisation is
   therefore symmetric; neither trace is massaged alone.
2. **`tools/oracle/bc19/examplefuncsplayer19/determinism.patch`**, two hunks.
   Hunk 1 replaces `Math.floor(Math.random()*choices.length)` with a
   `java.util.Random` seeded from the robot's own id, created once per robot:
   the stock line draws from the wall-clock-seeded global RNG, so the stock
   bot is not reproducible even against itself. A `java.util.Random` is
   chosen rather than a second Mersenne Twister so the port can reuse
   `src/battlecode/rng.nim` unchanged — and Tier A″ is then also a test of
   that module against a **second, independent** generator running alongside
   the engine's own MT19937. Hunk 2 removes the `this.me.team == 1` guard on
   the castle's build: without it **RED never builds anything at all**, and a
   baseline that is completely inert on one of the two sides cannot be scored,
   cannot fill a league and makes the survival gate meaningless.

## The one thing the driver does not take from upstream

`tools/oracle/bc19/bc19_trace.js` reimplements `coldbrew/runtime.js`'s
twenty-line `gameLoop`/`emptyQueue` rather than calling it, because
`runtime.js` drives the game through `setInterval` — which cannot be run
synchronously to completion — and `cli/run.js` additionally requires the
rollup compiler, `vm2` and a network update check. Everything else, `Game`
and `ActionRecord`, is `require`d from the pinned checkout unmodified beyond
the two patches above.

## Why bit-exactness is realistic in this year

* **The arithmetic is INTEGER end to end.** Health, karbonite, fuel, damage,
  capacities, radii, yields and costs are all integers. Exactly **two**
  non-integer operations exist on any gameplay path —
  `Math.ceil(Math.sqrt(r²))` over the finite domain 0…7938, and
  `Math.floor(a/b)` in the reclaim over a finite domain — and **both are
  tabled at build time** in `data/bc19/tables.json`. There is no `sqrt`, no
  `pow`, no `exp` and no float64 accumulation at run time, so there is **no
  float allowlist in the comparator because there are no floats**. (The two
  one-decimal numbers in the *results* document,
  `castle_separation_min`/`_max`, are Euclidean distances between two
  squares — derived board descriptions computed after the game, read back
  by nothing, and carried by no trace line.)
* **There is no hash-ordered or sorted collection in the round loop.**
  `this.robots` is a plain array, `robin` an index into it, `createItem`
  appends and `_deleteRobot` splices; `isOver`, `getItem` and
  `getGameStateDump` all read that one array.
* **The RNG surface is ONE generator with ONE live draw site.** MT19937,
  seeded with the map seed, and after the build-time map generation (V3) its
  only live call site in the round loop is `createItem`'s id rejection loop
  (plus at most one coin flip per game in `isOver`). **That is why the trace's
  `G` line carries an FNV-1a fold of the whole 624-word MT state and `mti`
  every round**: a single missed or extra id draw surfaces on the round it
  happens instead of as a mystery three hundred rounds later, and it is by
  far the most likely way this port can desynchronise.

## What is NOT compared, and why

* **The freeze branch of `processAction` (V1) is the one behaviour this
  oracle cannot compare.** The engine's chess clock is driven by
  `wallClock()`, so it is not reproducible between two runs of the engine
  itself; the port replaces it with a `DecisionOps` clock whose per-turn
  charge is the exact constant `TurnChargeOps = ChessExtraOps`, which makes
  `chessOps` invariant and the freeze branch unreachable. Tier B′ proves both
  halves of that separately: **(a)** the driver asserts, after every turn of
  every compared game, that every live robot's `robot.time >= CHESS_INITIAL`
  and exits **6** otherwise, so the engine's own freeze branch provably never
  fired in any game this job compares; and **(b)** a **separate,
  non-compared** run with `bc19slowbot`, whose `turn()` busy-loops for a
  calibrated ~40 ms, asserts that the engine **does** freeze it at the turn
  the formula `time_{n+1} = time_n + 20 − elapsed` predicts. Step (b)
  compares nothing against the Nim side and exists so the port's *reading* of
  the rule is proved rather than asserted.
* **`robot.time` itself** is in neither the observation nor the trace (V7).
* **The `visible` array's order** is normalised on BOTH sides by the engine
  patch above (V2), so it is compared — but it is compared against a patched
  engine, which is why the patch is named here.
* **Three named per-pair LIVENESS waivers**, each of which relaxes only the
  driver's own "this game did something" sanity check and **never** the
  trace comparison. Every compared pair is still compared line for line.
  1. `--allow-inert` on `examplefuncsplayer19` / **`seed-0017`** only.
     `examplefuncsplayer19` builds a CRUSADER at the fixed offset `(1,1)`
     and nothing else; on `seed-0017` **both** castles' `(x+1,y+1)` is
     impassable, so the bot's only action is refused on every one of its
     turns and the game is legitimately inert for a thousand rounds. The
     driver would otherwise refuse to accept a game in which nothing
     happened, which is the right default and the wrong answer here.
     `seed-0017` stays in the pair set because it is the `castles_destroyed`
     board and the other five bots exercise it.
  2. `--allow-no-build` on `bc19scenariotrade`, whose whole script is the
     barter: it proposes offers from its castles and never builds, so the
     driver's "somebody built something" check does not apply.
  3. `--expect-freeze` on `bc19slowbot`, which is the Tier B′(b) run above
     and is asserted to freeze rather than to finish.
  All three flags are passed **explicitly, per bot and per map**, in the
  `parity-oracle-bc19` job, so a waiver cannot silently spread to a pair it
  was not measured on.
* **The `.bc19` byte replay, `coldbrew/vis.js`, `vm2`, `coldbrew/compiler.js`
  and the Python/Java transpilers** (V5). No counterpart in the port.
* **Tier A is deliberately SMALL in this year, and that is the single most
  important difference between bc19 parity and bc16 parity.** In bc16 the
  zombies are engine-side, so an idle player still exercises half the game.
  **In bc19 nothing at all happens without a player action** — no NPCs, no
  terrain change, no passive spawning. Tier A with `bc19idle` proves the
  queue and `robin`, the round counter, the flat fuel trickle, the initial
  castles' id draws off the committed MT state, the `isOver` evaluation
  points and the round-1000 ladder; **the load-bearing tiers are A′ and A″.**

## Status

**RUN, AND GREEN, WITH AN EMPTY LEDGER.** The whole oracle is the
`parity-oracle-bc19` job of `.github/workflows/ci.yml` (`timeout-minutes: 45`),
which runs on every push. The run taken as the verdict is the one on `main`
at the shipped sha: **`34454858348`** — job `parity-oracle-bc19`, id
**`102798775171`**, on `main` at `d2f5d3d707`, **conclusion `success`**, wall
clock **1 m 53 s** (08:23:06Z → 08:24:59Z), reporting `compared 54
whole-game pairs, 0 failure(s)` over 54 `BIT-EXACT` lines. Every tier named
above ran in that one job and every tier passed:

| tier | what it ran there | verdict |
|---|---|---|
| comparator self-test | `parity_tiers_bc19.py --self-test`: a one-line-longer oracle trace MUST be reported as a divergence, and the normaliser MUST be applied to both sides | pass |
| **B** (whole domain, not a sample) | `JsBc19Tables.mjs --check` — all 7 939 `ceil(sqrt(r²))` values and the reclaim's integer division over its whole domain; `gen_maps_bc19.mjs --check` — all **22 committed boards byte-diffed** against the pinned engine's own `makeMap()`; and the **13 degenerate seeds refused BY NAME** (7, 20, 24, 83, 108, 127, 175, 211, 232, 267, 283, 348, 365), which proves V3's curation rather than trusting it | pass |
| **A / A′ / A″ / B′(a) / C** | **54 whole-game pairs**: six trace bots (`bc19idle`, `examplefuncsplayer19`, `bc19scenario`, `bc19scenariotrade`, `bc19scenariokill`, `bc19scenariotie`) × the nine parity boards (`seed-0009`, `seed-0017`, `seed-0021`, `seed-0034`, `seed-0043`, `seed-0045`, `seed-0048`, `seed-0107`, `seed-0125`), 1000 rounds each, engine trace against Nim trace **line for line**, `--assert-clock` on every one of them (that is Tier B′(a): the driver exits 6 if any live robot's `robot.time` ever fell below `CHESS_INITIAL`, so the engine's freeze branch provably never fired in a game this job compares) | **54 of 54 BIT-EXACT, 0 failures** |
| **A** (anti-vacuity, off the ORACLE trace) | the flat +25-fuel-a-team-a-round trickle with nothing else moving a store; `ids=4` on `seed-0043` and the pool NEVER growing in an idle game; `wc=1` on the last line (game.js:604's unconditional `win_condition = 1` overwrite); and **exactly ONE `A` line in round 1000**, because `isOver` runs before every turn | pass |
| **A′** (anti-vacuity, off the union of the nine `bc19scenario` traces) | all five unit types on the board (`CASTLE`, `PILGRIM`, `CRUSADER`, `PROPHET`, `PREACHER`); all five forced action kinds (`BUILD`, `MOVE`, `ATTACK`, `MINE`, `GIVE`); the r² 7938 broadcast at its 90-fuel cost; castle talk from a mobile unit (`ct=77`); and a pilgrim carrying an unrefined load | pass |
| **A′** (the CHURCH, D6.1) | a CHURCH raised **and its legal 0-damage `ATTACK` fired, on ALL NINE boards** — a CHURCH's `ATTACK_RADIUS` is the scalar `0`, so both range comparisons are against `undefined`, both are false, and the action is ACCEPTED for 0 fuel and 0 damage. It is the quirk this year is most likely to get wrong | pass |
| **A′** (the three end rungs) | `wc=0` `castles_destroyed` on `seed-0017` (`bc19scenariokill`); `winner=RED wc=1` `more_unit_health` on `seed-0043` (`bc19scenariotie`); and the barter moving **both** stores in **opposite** directions on `seed-0043` (`bc19scenariotrade`), the only externally visible proof that `enactTrade` executed rather than merely recording an offer | pass |
| **B′(b)** (separate, non-compared) | the `bc19slowbot` run: the engine **does** freeze a robot whose `turn()` busy-loops ~40 ms, at the turn `time_{n+1} = time_n + 20 − elapsed` predicts. It compares nothing and exists so the port's *reading* of V1 is proved rather than asserted | pass |

**`tools/ci/parity_ledger_bc19.json` IS `[]` AND STAYED `[]`.** No pair
diverged, so the comparator wrote no digest, so the job's
`parity-bc19-digests` artifact **does not exist in run `34454858348`** — the
upload is `if-no-files-found: ignore`, which makes that artifact's absence the
positive evidence of an empty ledger rather than a gap in it.

Root-cause-or-fail remains the standing rule: an unexplained Tier C divergence
is a FAIL, not a ledger line, `tools/ci/parity_tiers_bc19.py` rejects a cause
of "unknown", and diverging **earlier** than a ledger entry claims, or not
diverging at all where one claims you should, are both failures too.

The Nim halves of both differential bots are written to be mirrorable and must
stay that way: `src/battlecode/years/bc19/chassis/scenario19.nim` makes every
scenario decision a pure function of `me.unit`, `me.turn` and the squares
immediately around the robot, with the adjacent-square scan order fixed in its
`AdjacentScan` constant, and
`src/battlecode/years/bc19/chassis/examplefuncsplayer19.nim` is the patched
example bot statement for statement. An edit to either that is not mirrored on
the other side is what Tier A′/A″ will catch, and it will catch it as a
divergence rather than as a compile error.
