# cogame-battlecode

**Battlecode, played by doctrine.** Two cogs each write one sealed JSON
strategy sheet and a deterministic Nim port of an official Battlecode rule set
plays the whole match from those two sheets. **One variant per Battlecode
year**, chosen by `game_config.year`:

| variant | year | the game in one line |
| --- | --- | --- |
| `bc26` | 2026 "Uneasy Alliances" | rat clans allied against NPC cats until one of them betrays |
| `bc20` | 2020 "Soup" | the water rises every round, and a team either terraforms above the flood, walls its HQ in, or buries the enemy's under fifty units of dirt |
| `bc21` | 2021 "Campaign" | every round auctions one citizen's vote; influence buys units, buys votes, and is what an enemy politician takes when it converts your Enlightenment Center |
| `bc24` | 2024 "Breadwars" | fifty identical ducks a side, three flags each, an impassable dam for 200 rounds, and traps you cannot see until they go off |

---

## `bc26` — Battlecode 2026 "Uneasy Alliances"

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

---

## `bc20` — Battlecode 2020 "Soup"

**The clock is the water.** From round 1 the level rises on a fixed curve and
floods outward **one ring per round** from every already-flooded tile whose
neighbour sits below it. Anything that is not a delivery drone dies on a
flooding tile.

An **HQ cannot be raised** — dirt dropped on a building buries it, and fifty
dirt kills an HQ outright. The only thing that keeps an HQ dry is a ring of
eight adjacent tiles the water can never cross. A team that never walls
drowns on a schedule: elevation 3 floods at round 677, elevation 5 at 1210.

Miners mine SOUP and refine it. Design schools build landscapers that dig and
dump dirt — a lattice, a wall, or fifty units on the enemy's HQ. Fulfillment
centers build delivery drones that pick up any unit, including enemy
landscapers, and drop them in the water. Vaporators print soup and scrub
pollution; net guns shoot drones. The only global channel is a blockchain,
seven ints a message, seven messages a round, paid for in soup — and **both
teams read every block**.

```
points = int(60 * HQ-survival share + 25 * unit share + 15 * net-worth share)
score  = 100 * games won + mean(points over games played)
```

Ten knobs — `opening`, `terraform_start_round`, `lattice_radius`,
`landscaper_count_curve`, `miner_count_curve`, `vaporator_budget`,
`drone_role`, `net_gun_ring`, `rush_trigger`, `wall_hq_round` — which is the
year's own published metagame (rush / lattice / passive lattice / turtle) as a
doctrine surface. Champions:

| policy | doctrine |
| --- | --- |
| `battlecode-bc20-latticer` | out-build the flood: wall early, terraform, spend on vaporators |
| `battlecode-bc20-rusher` | get there before their wall does: rush, swarm landscapers, harass with drones |

`PLAYER_SCRIPTED=bowl-of-chowder` is the strong baseline and the champion
chassis (behaviour ported from Stone Tao's finals bot);
`PLAYER_SCRIPTED=examplefuncsplayer` is the ported 2020 example bot,
deliberately weak.

---

## `bc21` — Battlecode 2021 "Campaign"

**The clock is the election.** Every round one citizen's vote is auctioned:
each Enlightenment Center may bid influence, the single highest bidder in the
game wins the vote for its team and pays its bid, and the other team's top
bidder pays **half its bid, rounded up, for nothing**. At round 1500 the team
with more votes wins. Before then, a team that loses every robot loses
immediately.

Influence is the only resource, it is **not** a global pool — it sits inside
each Enlightenment Center — and it does three incompatible jobs: it buys units,
it buys votes, and it is what an enemy politician steals when it converts a
Center. Each Center earns `ceil(0.2·√t)` a round, about 8 500 over a game.

**Slanderers** are the multiplier: one built for `x` influence pays its parent
`floor(x·(1/50 + 0.03·e^(−0.001x)))` a round for 51 rounds — a ~2.35× return
for `x ≈ 21…130` — and at 300 rounds old silently becomes a politician.
**Muckrakers** cost one influence, see furthest, and **expose** enemy
slanderers: the slanderer dies and the muckraker's team gets `+0.001 ×` that
slanderer's influence on every speech for 50 rounds. **Politicians** are
walking bombs: empowering splits `conviction − 10` among every other robot in
the chosen radius — healing friends, feeding friendly Centers, converting or
killing everything else — and then the politician dies.

```
points = int(40 * survival + 35 * vote share + 15 * centre share + 10 * influence share)
score  = 100 * games won + mean(points over games played)
```

Ten knobs — `opening`, `slanderer_ratio`, `muck_ratio`,
`politician_size_curve`, `bid_policy`, `expansion`, `flank_policy`,
`empower_threshold`, `convert_over_kill`, `eco_exponential_round` — which is
the season's own metagame (muck spam / slanderer turtle / buff mucks /
muck flanks) as a doctrine surface. Champions:

| policy | doctrine |
| --- | --- |
| `battlecode-bc21-turtle` | print money and buy the election: slanderer turtle, escalate the bid when ahead, compound late |
| `battlecode-bc21-muckrush` | their economy never starts: muck spam, flank wide, cheap politicians behind the buff |

`PLAYER_SCRIPTED=california-roll` is the strong baseline and the champion
chassis (behaviour ported from Stone Tao's 2021 bot);
`PLAYER_SCRIPTED=examplefuncsplayer21` is the ported 2021 example bot,
deliberately weak, and the bot the bc21 parity oracle runs.

---

## `bc24` — Battlecode 2024 "Breadwars"

**The clock is the dam.** Two cogs each command a flock of **fifty identical
ducks**. For the first 200 rounds an impassable dam splits the map and nobody
can attack: ducks spawn, walk crumbs off the floor, dig water, fill water, lay
invisible traps and — uniquely in this year — **carry their own three flags to
wherever they want them**, subject to a minimum spacing of six tiles. At round
200 the dam evaporates, the flag placements freeze, and **the only thing that
ends the game early is capturing all three enemy flags.** Otherwise round 2000
decides it on flags captured, then total skill levels, then crumbs, then a coin
flip.

Every duck is the same duck. What makes them different is what they *do*:
attacking, healing and building each earn experience in that skill, each skill
has six levels, and at level 4 a duck gains **mastery** — that skill can keep
climbing to 6 while the other two freeze at 3. A duck that dies goes to
**jail** for 25 rounds, comes back at full health, and loses experience in its
own best skill on the way in. So a flock is a portfolio: attackers that hit for
240 instead of 150, healers that mend 100 instead of 80, builders whose
200-crumb explosive trap costs 100.

Crumbs are the only resource and they are **global per team**: 400 to start, 10
a round for free, whatever the ducks walk over, and 30 for every kill made
while standing on enemy ground. They buy digging (20), filling (30), stun and
water traps (100) and explosive traps (200) — and nothing else, because ducks
are free and infinite. Every crumb spent on a moat is a crumb not spent on an
explosive trap ringing the flag the enemy is running at.

```
points = int(60 * flag share + 25 * level share + 15 * crumb share)
score  = 100 * games won + mean(points over games played)
```

Ten knobs — `specialisation_split`, `flag_rush_round`, `trap_budget`,
`trap_placement`, `trap_mix`, `heal_priority`, `water_dig_policy`,
`upgrade_order`, `retreat_hp`, `flag_carry_escort` — which is the triangle the
year is actually about: **level up, fortify, or run at the flags.** Champions:

| policy | doctrine |
| --- | --- |
| `battlecode-bc24-fortress` | they never get one out: build-heavy, explosives ringing the flags, a moat, and retreat early to keep levelling |
| `battlecode-bc24-flagrush` | capturing all three ends the game instantly, so get there first: all-in on attack, rush at round 220–350, fill the road, capture upgrade first |

`PLAYER_SCRIPTED=gone-sharkin` is the strong baseline and the champion chassis
(behaviour ported from the four AGPL-3.0 bots credited in `NOTICE`);
`PLAYER_SCRIPTED=examplefuncsplayer24` is the ported 2024 example bot,
deliberately weak, and the bot the bc24 parity oracle runs — **whole games,
bit-exact, with an empty divergence ledger.**

## What is in here

| path | what |
| --- | --- |
| `src/battlecode/years/bc26/` | the 2026 rule set: `world.nim` (state, geometry, legality), `cats.nim` (the NPC state machine), `rules.nim` (the round loop), `knobs.nim` (the doctrine table), `chassis/` (the two bots and every knob's site) |
| `src/battlecode/years/bc20/` | the 2020 rule set: `world.nim`, `flood.nim`, `pollution.nim`, `blockchain.nim`, `cows.nim`, `rules.nim`, `knobs.nim`, `chassis/` |
| `src/battlecode/years/bc21/` | the 2021 rule set: `world.nim`, `empower.nim`, `votes.nim`, `economy.nim`, `rules.nim`, `maps.nim`, `knobs.nim`, `chassis/` |
| `src/battlecode/years/bc24/` | the 2024 rule set: `world.nim`, `skills.nim`, `traps.nim`, `flags.nim`, `rules.nim`, `maps.nim`, `knobs.nim`, `chassis/` |
| `src/battlecode/years/{registry,dispatch}.nim` | the year boundary: the ONE place the year-neutral machinery meets a year module |
| `src/battlecode/rng.nim` | `java.util.Random` and `IDGenerator`, bit-exact |
| `src/battlecode/{sheet,decide,llm,baselines}.nim` | the doctrine schema, the one sealed parallel batch, the provider ladder, the scripted table |
| `src/battlecode/{replay,results,broadcast,render,server}.nim` | the JSON replay, the closed results document, the chrome channel, the sprite packets, the container |
| `replay-viewer/` | the **same sim module** compiled to wasm; the browser re-derives every round |
| `data/` | the committed sprite atlas and the converted maps |
| `tools/` | the CI-time generators: constants, maps, atlas, wire constants, and both halves of the parity oracle |

## Docs

* [`docs/RULES.md`](docs/RULES.md) — the 2026 rule set, its doctrine knobs,
  and every deliberate divergence from the Java engine.
* [`docs/RULES-BC20.md`](docs/RULES-BC20.md) — the 2020 rule set, its ten
  knobs, and its own §Divergences list.
* [`docs/RULES-BC21.md`](docs/RULES-BC21.md) — the 2021 rule set, likewise.
* [`docs/RULES-BC24.md`](docs/RULES-BC24.md) — the 2024 rule set, its ten
  knobs, THE TWO ROUNDING REGIMES, and its own §Divergences list.
* [`docs/PARITY.md`](docs/PARITY.md) — the Java oracles, tier by tier, and
  every accepted divergence with its root cause.
* [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — `cogame.battlecode.v1`: what a seat
  sends, what a cog sees, and what it never sees.
* [`docs/REPLAY.md`](docs/REPLAY.md) — the replay document and how the viewer
  re-derives a match from it.
* [`docs/PARITY.md`](docs/PARITY.md) — the Java engine as a CI-only oracle,
  the three tiers, and what each one proves.

## Licence

AGPL-3.0. The 2026 rule set, constants, maps and sprite art derive from
[`battlecode/battlecode26`](https://github.com/battlecode/battlecode26)
(AGPL-3.0, tag `engine.1.2.5`) and the `awu` chassis distils the strategy of
[`awu7/battlecode-2026`](https://github.com/awu7/battlecode-2026) (AGPL-3.0,
branch `final`). The 2020 rule set, constants, maps and sprite art derive from
[`battlecode/battlecode20`](https://github.com/battlecode/battlecode20)
(**GPL-3.0**, commit `7618f6b`) and the `bowl-of-chowder` chassis distils the
strategy of
[`StoneT2000/Battlecode2020`](https://github.com/StoneT2000/Battlecode2020)
(AGPL-3.0). GPLv3 and AGPLv3 are explicitly compatible for combined works
(AGPLv3 §13). See [`NOTICE`](NOTICE). **No upstream Java source, and no JVM,
runs in this image.**
