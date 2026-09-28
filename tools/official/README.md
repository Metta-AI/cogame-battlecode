# Execute complete archived Battlecode bots

This runner executes the complete selected Java implementations, rather than
translating strategies into the native doctrine controller. It does not change
the existing doctrine Coworld's player protocol or standings.

`sources.json` pins eleven archive revisions, source directories, package
entrypoints, published engine URLs, and SHA-256 hashes. Build provenance records
the digest of every Java source compiled. Archive checkouts must match the pinned
revision and have no modified tracked files. The runner never pushes to them.

Requirements: Java 21, Python 3.12+, `pydantic`, and `jinja2`. Om Nom's templates
are rendered with the archive's own generator in production mode. All eleven
selected implementations retain their original robot logic, including the
ProofOfConcept neural networks.

```bash
uv run --no-project --with pydantic --with jinja2 python tools/official/runner.py \
  build bc25-confused bc25-om-nom

uv run --no-project --with pydantic --with jinja2 python tools/official/runner.py \
  match bc25-confused bc25-om-nom --map AlarmClock --output /tmp/bc25-originals
```

Use `--jdk /path/to/jdk-21/bin` when Java 21 is not the default. Use `--checkout`
with a single build target to verify and compile an existing pinned checkout.
Builds live under `dist/official`; output match directories must not already exist.

Match artifacts:

- `result.json`: the official winner, termination reason, rounds, map dimensions,
  and observed bytecode usage for both teams.
- `official.bc25` or `official.bc26`: the official engine's replay, viewable in
  the corresponding Battlecode client.
- `frames.jsonl`: validated per-round public robot state and team economy.
- `seat-0.log` and `seat-1.log`: separate original robot logs.
- `engine.log`: engine diagnostics.
- `provenance.json`: selected source revisions, map, and engine hash.

The observer uses the upstream `GameWorld`, `PlayerControlProvider`, and
`GameMaker`. It does not change rules, action ordering, robot observations,
communications, or winner selection. Java receives all five module-opening flags
from the official runners, including `jdk.internal.misc` and `sun.security.action`.
Missing meaningful
execution fails instead of reporting an empty match as a successful comparison.

The process has a 600-second default deadline and a 2 GiB Java heap. Run only
the pinned archives in this tool. Source execution does not establish that a selected archive is the
exact final tournament artifact; see [the fidelity audit](../../docs/FIDELITY-AUDIT.md).

## Separate hosted archive Coworlds

`official-coworld/bc25/` and `official-coworld/bc26/` package separate
**battlecode-2025-archives** and **battlecode-2026-archives** Coworlds. Each
executes the complete pinned archive implementations using these same engines.
It accepts only a small JSON file selecting one built-in archive:

```json
{"schema":"battlecode-archive/1","archive":"bc25-om-nom"}
```

Use variant `bc25` or `bc26` with a selector from that year. Selectors are
limited to 1 KiB, reject extra fields, and must match the staged size and digest.
Unknown archives and wrong-year selections fail the episode. This release does
not accept arbitrary source, jars, scripts, paths, or executable player files.
Complete selected source directories, generator inputs, and license files are
retained inside the game image. Git history and unrelated source trees are excluded.

The published image includes nine licensed archives. SPAARK 2026 and Old But
Gold have no license files at their pinned revisions, so their full source and
bytecode remain excluded from that image. They remain available to the local
audit runner; their existing native adaptations retain explicit adaptation labels.

This is game-hosted execution: there are no player pods or per-robot WebSockets.
Java uses the official instrumented per-robot memory and bytecode model. The
game allocation is 4 GiB and two CPUs, with a 600-second match deadline. Bots
have no external model credentials; the ProofOfConcept network executes its
archived generated Java weights. No runtime compilation occurs.

Each seat gets its own required log. Logs close before results are published.
The public replay contains only observed per-round robots and economy, not bot
stdout or private logs. This initial observer viewer draws unit positions and
supports automatic playback, looping, pause, and seeking. It does not display
all terrain, paint, traps, or action animations available in the official client.
The local tool retains the complete official replay for the official client.

The game serves `/healthz`, `/global` with RFC 6455 Ping/Pong, `/client/global`,
`/client/replay`, and `/replay`. Replay mode loads both local file URIs and
hosted HTTP/HTTPS artifacts. Scores are `[1,0]` or `[0,1]`, directly from the
official winner. Default maps are `AlarmClock` (2025) and `DefaultSmall` (2026);
`game_config.map` can select other maps bundled in the pinned official engine.
This is execution infrastructure, not a recreation of the original tournament
map distribution or a strength evaluation against Softmax's doctrine entries.

```bash
for year in bc25 bc26; do
  coworld build --version 0.1.1 --project "official-coworld/$year" --compose compose.yaml \
    --template coworld_manifest_template.json --output dist/coworld_manifest.json
  coworld certify "official-coworld/$year/dist/coworld_manifest.json" --timeout-seconds 600 --no-open-report
done
python tools/official/container_smoke.py
```

Each manifest bundles two certification players for its two seats. All nine
licensed selectors are available under `official-coworld/players/`; use them
as file players for the corresponding year's game.

The separate release workflow certifies both games, seats every archive in both positions,
pins documentation URLs to the release commit, then publishes and waits for
hosted certification. It does not change the existing doctrine leagues.

Both games are hosted at certified canonical version **0.1.1**. See the
[live verification receipt](../../docs/fidelity-release-verification.json).
