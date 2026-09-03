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

## The tiers

| tier | what | gate |
| --- | --- | --- |
| **A** | rounds 1–50 are **bit-exact** on all five pairs: every field above, every robot, every round, including ids | **blocking** |
| **B** | at round 200, every field still agrees exactly — cumulative cat damage, cheese transferred, king counts and the cooperation flag included | **blocking** |
| **C** | the first divergent round over a full 2000-round game, printed and written to the job summary against a committed baseline | reported, trended |

Tiers A and B are the phase-30 gate.

## The Tier C baseline

Measured at `GameVersion` GV01 against `engine.1.2.5`:

| map | first divergent round (2000-round game) |
| --- | --- |
| `DefaultSmall` | none — identical for all 2000 rounds |
| `closeup` | none — identical |
| `toomuchcheese` | none — identical |
| `cheesefarm` | none — identical |
| `arrows` | 915 |
| `dirtfulcat` | 453 |

Four of six maps re-derive an entire 2000-round game bit for bit. The two that
drift do so inside the cat state machine, hundreds of rounds in, and the
divergence is a single cat choosing a different facing on one round. That is
what Tier C exists to trend: a regression that moves any of these numbers
DOWN is visible in the job summary even though it does not fail the build.

Every accepted divergence is listed in `docs/RULES.md` §Divergences with its
reason.
