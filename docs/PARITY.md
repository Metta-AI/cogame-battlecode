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
