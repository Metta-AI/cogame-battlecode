# cogame-battlecode

**Battlecode 2026 "Uneasy Alliances", played by doctrine.**

Two cogs each command a clan of robot rats on a symmetric grid. Neither cog
moves a rat. At t=0 each writes a **doctrine** — a sealed JSON sheet of named
knobs — and a deterministic Nim port of the official Battlecode 2026 rule set
then plays a best-of-three match from those two sheets while both cogs watch.

Both clans start in **COOPERATION** against neutral NPC cats, and the points
formula is cat-damage weighted. The moment either clan takes a hostile action
against the other — a bite, a ratnap, a throw, or the victim walking into your
rat trap — the world flips to **BACKSTAB** and the formula reweights toward
king survival. Losing every rat king loses the game outright.

That single bit — when, whether and how to betray an ally you still need — is
the whole game, and it is an LLM-legible strategic decision sitting on top of a
deep, genuinely watchable RTS.

```
cooperation: points = int(50 * cat-damage share + 30 * king share + 20 * cheese share)
backstab:    points = int(30 * cat-damage share + 50 * king share + 20 * cheese share)
score        = 100 * games won + mean(points over games played)
```

## A policy is just a prompt

Both champions are LLM policies on the same chassis, differing only in the
doctrine their prompt asks for:

| policy | doctrine |
| --- | --- |
| `battlecode-loyalist` | honour the alliance, hunt cats, never open hostilities |
| `battlecode-opportunist` | farm cats while the weights pay, then turn |

and two scripted baselines ship in the same image, env-switched:

```bash
coworld upload-policy cogame-battlecode:latest --name my-clan \
  --run /bin/battlecode-player \
  --secret-env PLAYER_PROMPT="Never betray. Hunt cats. Keep four kings."
```

`PLAYER_SCRIPTED=awu` is the strong distilled-awubot baseline;
`PLAYER_SCRIPTED=scaffold` is the ported `examplefuncsplayer`, deliberately
weak, and the bot the parity oracle runs.

## What is in here

| path | what |
| --- | --- |
| `src/battlecode/years/bc26/` | the ported rule set: `world.nim` (state, geometry, legality), `cats.nim` (the NPC state machine), `rules.nim` (the round loop), `chassis/` (the two bots and every doctrine knob's site) |
| `src/battlecode/rng.nim` | `java.util.Random` and `IDGenerator`, bit-exact |
| `src/battlecode/{sheet,decide,llm,baselines}.nim` | the doctrine schema, the one sealed parallel batch, the provider ladder, the scripted table |
| `src/battlecode/{replay,results,broadcast,render,server}.nim` | the JSON replay, the closed results document, the chrome channel, the sprite packets, the container |
| `replay-viewer/` | the **same sim module** compiled to wasm; the browser re-derives every round |
| `data/` | the committed sprite atlas and the converted maps |
| `tools/` | the CI-time generators: constants, maps, atlas, wire constants, and both halves of the parity oracle |

## Docs

* [`docs/RULES.md`](docs/RULES.md) — the rule set, the eleven doctrine knobs,
  and every deliberate divergence from the Java engine.
* [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — `cogame.battlecode.v1`: what a seat
  sends, what a cog sees, and what it never sees.
* [`docs/REPLAY.md`](docs/REPLAY.md) — the replay document and how the viewer
  re-derives a match from it.
* [`docs/PARITY.md`](docs/PARITY.md) — the Java engine as a CI-only oracle,
  the three tiers, and what each one proves.

## Licence

AGPL-3.0. The rule set, the constants, the maps and the sprite art derive from
[`battlecode/battlecode26`](https://github.com/battlecode/battlecode26) (AGPL-3.0,
tag `engine.1.2.5`) and the `awu` chassis distils the strategy of
[`awu7/battlecode-2026`](https://github.com/awu7/battlecode-2026) (AGPL-3.0,
branch `final`). See [`NOTICE`](NOTICE). **No upstream Java source, and no JVM,
runs in this image.**
