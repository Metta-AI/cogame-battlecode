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
