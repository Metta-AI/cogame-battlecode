## Year-neutral types shared by every module: the `GameVersion` stamp and its
## changelog, the resolved `GameConfig`, and the rune caps every recorded
## string is measured against.
##
## RUNE DISCIPLINE (inherited from `coworld-ctf/src/ctf/directives.nim`):
## every cap below is a count of Unicode codepoints and every truncation
## lands on a rune boundary. Byte-slicing a multi-byte character renders fine
## in a browser and then fails a strict UTF-8 parser, which is exactly what
## makes a replay unreadable to everything except one lenient viewer.

import std/[strutils, unicode]

const
  GameName* = "battlecode"

  GameVersion* = "GV11"
    ## PREPEND-ONLY CHANGELOG. Anything that changes what a policy sees, how a
    ## seat is scored, or how a round resolves bumps this in the SAME commit,
    ## and `tools/ci/check_gameversion.sh` compares the headline (not the
    ## digits) against the base branch — a number alone cannot detect two
    ## branches claiming the same version for different rules.
    ##
    ## GV11 — the `bc16` year module: Battlecode 2016 "Zombie Invasion"
    ##        ported from battlecode-server-2016 at commit 11a0b09f (oracle
    ##        jar 2016.0.2.2; THE OFFICIAL 2016 SPEC IS LOST and this year's
    ##        `GameConstants` has no `SPEC_VERSION` at all, so the jar is
    ##        pinned by sha256 AND size and the ENGINE SOURCE IS THE SPEC):
    ##        the four-step round loop over an INSERTION-ordered exec list
    ##        with by-value removal and a pre-sweep snapshot, ROUNDS NUMBERED
    ##        FROM ZERO (`currentRound` starts at -1, so the last round is
    ##        2999), the twelve robot types with their float64 core/weapon
    ##        delay pair and its ASYMMETRIC set-up-to/add-to charging
    ##        (`activateCoreAction` sets the weapon and adds the core;
    ##        `activateAttack` adds the weapon and sets the core), the rubble
    ##        economy (impassable at 100, double cost at 50, `0.95r - 10` per
    ##        clear, and every UNINFECTED corpse adding its own max health,
    ##        a third of it on a turret kill), parts income
    ##        `max(0, 2 - 0.01 * robots)` with ARCHON-ONLY whole-square
    ##        pickup, the public per-den zombie spawn schedule with its
    ##        BUILD-TIME symmetric split, the outbreak ladder applied at the
    ##        moment a zombie spawns, the verbatim zombie AI over THREE
    ##        independent `Random(mapSeed)` streams, infection with its
    ##        10/20-turn counters and its die-and-turn conversion, free
    ##        neutral activation, and the four-rung round-2999 tiebreak
    ##        ladder, behind `game_config.year`. The bytecode-dependent delay
    ##        decay is PINNED TO 1.0 (a documented divergence, V1).
    ##        bc20, bc21, bc22, bc23, bc24, bc25 AND bc26 SEMANTICS ARE
    ##        UNCHANGED: no GV04..GV10 recording carries a byte whose meaning
    ##        changed — this run makes no year-neutral behaviour change at all
    ##        — which is why `ReplayCompatibleGameVersions` is EXTENDED rather
    ##        than reset and every hosted replay keeps rendering.
    ##
    ## GV10 — the `bc22` year module: Battlecode 2022 "Mutation" ported
    ##        from battlecode22 at commit 6ed05b67 (oracle jar 2.2.1, whose
    ##        own `SPEC_VERSION` really is "2.2.1", so the string is a second
    ##        pin beside the sha256): the four-step round loop over a DYNAMIC
    ##        append-ordered exec list whose INITIAL archons are id-ascending
    ##        (the map files carry ids below the 10 000 IDGenerator floor, so
    ##        A and B alternate in the opening order), BOTH COOLDOWNS STARTING
    ##        A ROBOT'S LIFE AT ZERO, the seven robot types with their exact
    ##        actions, the FLOAT64 TRUNCATING rubble cooldown multiplier read
    ##        at the square the charge is made on (the DESTINATION for a move),
    ##        the PROTOTYPE/TURRET/PORTABLE modes with the transform's SINGLE
    ##        cooldown counter and the mutation's double one, the lead economy
    ##        with its +2 passive BEFORE the anomaly and its +5-only-on-a-
    ##        non-empty-square regeneration AFTER it, the laboratory's tabled
    ##        `20 - 18*exp(-k*n)` transmutation curve, the four anomalies with
    ##        their measured float32 truncations (CHARGE kills nobody under
    ##        twenty droids and ranks BOTH teams together in trove hash order,
    ##        ABYSS spares a square holding nine or fewer, FURY spares
    ##        PORTABLE and PROTOTYPE and skips the archon rung, VORTEX draws
    ##        from a live `Random(mapSeed)`), and the round-2000 Singularity
    ##        ladder, behind `game_config.year`. bc26, bc20, bc21, bc23, bc24
    ##        AND bc25 SEMANTICS ARE UNCHANGED: nothing a GV04..GV09 recording
    ##        carries changed meaning. The one year-neutral behaviour change
    ##        this version makes — the TOLERANT DOCTRINE-SHEET ENVELOPE UNWRAP
    ##        in `sheet.nim`, which now also accepts a `doctrine` key and a
    ##        single object-valued key — CANNOT REACH A RECORDING, because
    ##        `replay.nim` re-validates the recorded APPLIED sheet wrapped in
    ##        `{"sheet": ...}` and an applied sheet is always a flat object of
    ##        known keys. That is why `ReplayCompatibleGameVersions` is
    ##        EXTENDED rather than reset and every hosted bc26, bc20, bc21,
    ##        bc23, bc24 and bc25 replay keeps rendering.
    ##
    ## GV09 — the `bc23` year module: Battlecode 2023 "Tempest" ported from
    ##        battlecode23 at commit af42086e (oracle jar 3.0.15, pinned by
    ##        sha256 because BOTH the pinned sources and the released jar
    ##        report the useless literal `SPEC_VERSION = "3.0.14"`): the
    ##        four-step round loop over a DYNAMIC append-ordered exec list
    ##        with by-value removal and a pre-sweep snapshot, the round-1
    ##        +200/+200 per HEADQUARTERS, the six robot types and their exact
    ##        actions with the engine's NON-UNIFORM charge order (move charges
    ##        after the move at the DESTINATION; boost, destabilize and the
    ##        three anchor verbs charge after their effect; everything else
    ##        before), the five-action headquarters, the carrier's
    ##        weight-driven movement cooldown and its inventory-emptying
    ##        throw, wells with the 600 kg elixir transformation and the
    ##        1400 kg rate upgrade, sky islands with the truncating occupancy
    ##        formula, the mid-turn float32 conquest check and the anchor
    ##        healing sweep, the additive per-tile per-team tempo multiplier
    ##        in integer hundredths with the engine's asymmetric stack guards
    ##        and the `cast + 4` destabiliser detonation, clouds that blind
    ##        BOTH WAYS, currents as a deterministic worklist, the two 64-slot
    ##        shared arrays with their write windows, and the six-rung end
    ##        ladder, behind `game_config.year`. bc26, bc20, bc21, bc24 AND
    ##        bc25 SEMANTICS ARE UNCHANGED: nothing a GV04, GV05, GV06, GV07
    ##        or GV08 recording carries changed meaning — the sheet envelope,
    ##        the results document and the replay all gained year-neutral
    ##        shape without moving a byte an older recording holds — which is
    ##        why `ReplayCompatibleGameVersions` is EXTENDED rather than reset
    ##        and every hosted bc26, bc20, bc21, bc24 and bc25 replay keeps
    ##        rendering.
    ##
    ## GV08 — the `bc25` year module: Battlecode 2025 "Chromatic Conflict"
    ##        ported from battlecode25 at commit 28975a48 (oracle jar 3.1.0,
    ##        pinned by sha256 because its `SPEC_VERSION` is the useless
    ##        literal "1"): the six-step round loop over a DYNAMIC
    ##        append-ordered exec list with by-value removal, the 0..4 paint
    ##        alphabet with its live square count and its MID-ACTION 70 %
    ##        win check, the three robots and their exact attacks (the
    ##        splasher's two radii, the mopper's six swing offsets), the
    ##        four hard-coded 5x5 patterns and the mark/fill/complete tower
    ##        build, tower upgrades with the damage carry and the defense
    ##        damage ledger, Special Resource Patterns with the fifty-round
    ##        delay and the reset-on-break, the paint-connectivity message
    ##        gate and the tower broadcast, the low-paint cooldown surcharge
    ##        and the end-of-turn paint bill (crowding counts TOWERS), and
    ##        the six-rung end ladder, behind `game_config.year`. bc26, bc20,
    ##        bc21 AND bc24 SEMANTICS ARE UNCHANGED: nothing a GV04, GV05,
    ##        GV06 or GV07 recording carries changed meaning — the sheet
    ##        envelope, the results document and the replay all gained
    ##        year-neutral shape without moving a byte an older recording
    ##        holds — which is why `ReplayCompatibleGameVersions` is EXTENDED
    ##        rather than reset and every hosted bc26, bc20, bc21 and bc24
    ##        replay keeps rendering.
    ##
    ## GV07 — the `bc24` year module: Battlecode 2024 "Breadwars" ported from
    ##        battlecode24 at commit 166c79bb (spec 3.0.5/3.0.6, oracle jar
    ##        3.0.5): the eight-step round loop over a FIXED hundred-duck exec
    ##        order, the setup phase and the dam, flag carry/drop/return with
    ##        the object-identity start-location test and the round-200
    ##        confirmation, the three trap types with their enter/interact
    ##        split, specialisation with the level-4 mastery freeze and the
    ##        jail penalty, the two rounding regimes (float32 for damage and
    ##        heal, float64 for every cooldown and crumb cost), the 64-slot
    ##        shared array, the flag broadcast, the three global upgrades and
    ##        the four-rung end ladder, behind `game_config.year`. bc26, bc20
    ##        AND bc21 SEMANTICS ARE UNCHANGED: nothing a GV04, GV05 or GV06
    ##        recording carries changed meaning — the sheet envelope, the
    ##        results document and the replay all gained year-neutral shape
    ##        without moving a byte an older recording holds — which is why
    ##        `ReplayCompatibleGameVersions` is EXTENDED rather than reset and
    ##        every hosted bc26, bc20 and bc21 replay keeps rendering.
    ##
    ## GV06 — the `bc21` year module: Battlecode 2021 "Campaign" ported from
    ##        battlecode21 at commit ed39c1a4 (release 2021.3.0.5): the
    ##        seven-step round loop, the empower/convert/heal arithmetic with
    ##        the 2021.3.0.0 LINEAR buff, expose and the buff ledger, the
    ##        slanderer embezzle curve and camouflage, the every-round vote
    ##        auction with its half-bid, flags, the four-rung end ladder and a
    ##        1500-round cap, behind `game_config.year`. bc26 AND bc20
    ##        SEMANTICS ARE UNCHANGED: nothing a GV04 or GV05 recording carries
    ##        changed meaning — the sheet envelope, the results document and
    ##        the replay all gained year-neutral shape without moving a byte an
    ##        older recording holds — which is why
    ##        `ReplayCompatibleGameVersions` is EXTENDED rather than reset and
    ##        every hosted bc26 and bc20 replay keeps rendering. The one
    ##        year-neutral type change, `ScriptedChassis`, replaces a bc20 enum
    ##        that was leaking through `years/dispatch.nim`; the STRINGS a
    ##        replay records for it are unchanged.
    ##
    ## GV05 — the `bc20` year module: Battlecode 2020 "Soup" ported from
    ##        battlecode20 at commit 7618f6b (round loop, flood, soup and
    ##        refining, the seven build types, dig/dump, drone carry and
    ##        drop-in-water, net guns, pollution, the 64-int blockchain and
    ##        its cost model, the six-rung tiebreak ladder), behind
    ##        `game_config.year`. bc26 SEMANTICS ARE UNCHANGED: nothing a GV04
    ##        recording carries changed meaning — the sheet envelope, the
    ##        results document and the replay all gained year-neutral shape
    ##        without moving a byte a bc26 recording holds — which is why
    ##        `ReplayCompatibleGameVersions` keeps GV04 and every hosted bc26
    ##        replay from that version keeps rendering. GV03 stays out: the D2
    ##        chassis change in GV04 means a GV03 recording is not re-derivable
    ##        under either.
    ##
    ## GV04 — `chassis` is no longer a doctrine knob. It is gone from
    ##        `sheet.KnownKeys` and from the prompt preamble's knob list, so
    ##        an LLM doctrine ALWAYS runs the `awu` chassis and a reply that
    ##        still sends `chassis` is recorded in `sheet_unknown_fields`,
    ##        ignored and logged. `scaffold` is selectable only by
    ##        `PLAYER_SCRIPTED=scaffold`, which sets the chassis directly.
    ##        The same version carries the `awu` cat-defence and economy fix
    ##        (r2-D2): the chassis digs a buried king out, puts the whole
    ##        roster on the cheese in famine, remembers and camps the mines,
    ##        paths with the world's BFS and digs through dirt, refuses a
    ##        crown the income cannot feed, stops the dirt shell eating the
    ##        crowns' food, stops the king squeaking cats onto itself and
    ##        rings a threatened crown with cat traps. Every one of those
    ##        changes what a round resolves to, so a GV03 recording is not
    ##        re-derivable here — which is what the version stamp is for.
    ##
    ## GV03 — `backstab_policy: never` no longer opens hostilities after the
    ##        alliance breaks. `never` and `retaliate_only` both fought back
    ##        once the world flipped, which made two of the five sheet values
    ##        behaviourally identical; `never` now never takes an enemy rat
    ##        as a target and `retaliate_only` is the one that finishes what
    ##        the other clan started.
    ##
    ## GV02 — the per-round hash chain folds all SEVEN per-team round stats
    ##        the round loop records (dirt and both trap counts were missing,
    ##        so a re-derivation that diverged only in dirt or in traps
    ##        standing reproduced the chain), and the replay records the chain
    ##        AFTER EACH ROUND (`games[].hash_chain_rounds`) so the viewer
    ##        compares every round and names the FIRST divergent one.
    ##
    ## GV01 — Battlecode 2026 ("Uneasy Alliances") ported from engine.1.2.5:
    ##        round loop, cheese, kings, combat, ratnap/throw, traps, dirt,
    ##        formation, squeaks, cats, backstab, float32-narrowed scoring.

  ReplayCompatibleGameVersions* = ["GV04", "GV05", "GV06", "GV07", "GV08",
                                   "GV09", "GV10", GameVersion]
    ## Versions whose recordings this build can still re-derive. A replay
    ## carrying anything else is refused with a readable message rather than
    ## silently re-simulated under different rules.

  ReplayFormat* = "cogame-battlecode-replay"
  ReplayFormatVersion* = 1
  ProtocolId* = "cogame.battlecode.v1"

  MaxNoteRunes* = 280
  MaxMottoRunes* = 48
  MaxUnknownFieldRunes* = 40
  MaxUnknownFields* = 16
  MaxSheetKeys* = 32
  MaxFallbackDetailRunes* = 200
  MaxPromptRunes* = 4000
  MaxPolicyLabelRunes* = 48
  MaxReplyBytes* = 16 * 1024

  AliasA* = "Clan Ash"
  AliasB* = "Clan Basil"

type
  ScriptedChassis* = enum
    ## The YEAR-NEUTRAL chassis vocabulary. `years/dispatch.nim` used to hand
    ## `array[2, rules20.ChassisKind]` around, which leaked a bc20 type through
    ## the year-neutral layer and made a third year impossible to add without
    ## renaming bc20's enum. Each year's `newSides` maps a value here into its
    ## own kind and falls back to THAT YEAR'S STRONG CHASSIS for a name
    ## belonging to another year, so a bc20 name on a bc21 game plays
    ## california-roll rather than nothing.
    ##
    ## The strings are exactly the ones a replay's `seats[].chassis` already
    ## records, so no recording changes meaning.
    scAwu = "awu"
    scScaffold = "scaffold"
    scBowlOfChowder = "bowl-of-chowder"
    scExamplefuncsplayer = "examplefuncsplayer"
    scCaliforniaRoll = "california-roll"
    scExamplefuncsplayer21 = "examplefuncsplayer21"
    scGoneSharkin = "gone-sharkin"
    scExamplefuncsplayer24 = "examplefuncsplayer24"
    scSpaark = "spaark"
    scExamplefuncsplayer25 = "examplefuncsplayer25"
    scLemonade = "lemonade"
    scExamplefuncsplayer23 = "examplefuncsplayer23"
    scWololo = "wololo"
    scExamplefuncsplayer22 = "examplefuncsplayer22"
    scBulwark = "bulwark"
    scGreenhorn = "greenhorn"

  ConfigError* = object of CatchableError
    ## An unusable `game_config`. The container exits 2 on this, per ctf.

  BattlecodeError* = object of CatchableError

  EndReason* = enum
    ## Per GAME. `results.games[].end_reason`.
    erKingsDestroyed = "kings_destroyed"
    erCatsCleared = "cats_cleared"
    erRoundLimit = "round_limit"
    erAbandoned = "abandoned"

  EpisodeReason* = enum
    ## Per EPISODE. The closed enum the platform reads from
    ## `results.reason`; `docker_smoke.sh` asserts the key set and this value.
    epComplete = "complete"
    epDeadline = "deadline"
    epFault = "fault"

  GameConfig* = object
    ## The resolved episode config. Everything the manifest variant and the
    ## certification fixture may set, with the defaults a bare config gets.
    year*: string
    pool*: string
    seed*: int
    gamesPerMatch*: int
    maxRounds*: int
    numAgents*: int
    playerNames*: seq[string]
    tokens*: seq[string]
      ## The runner's per-seat connection tokens, injected into every
      ## episode's `game_config`. They are a CREDENTIAL: a seat that dials
      ## with the wrong one is refused the upgrade, which the certifier
      ## probes for directly (`Bad player token was accepted`).
    attempt1Ms*: int
    retryMs*: int
    doctrineBudgetMs*: int
    perGameBudgetSeconds*: int
    matchBudgetSeconds*: int
    connectTimeoutMs*: int
    model*: string
    maxOutputTokens*: int

proc defaultGameConfig*(): GameConfig =
  GameConfig(
    year: "bc26",
    pool: "mixed",
    seed: 0,
    gamesPerMatch: 3,
    maxRounds: 2000,
    numAgents: 2,
    playerNames: @[AliasA, AliasB],
    attempt1Ms: 20_000,
    retryMs: 12_000,
    doctrineBudgetMs: 45_000,
    perGameBudgetSeconds: 90,
    matchBudgetSeconds: 330,
    connectTimeoutMs: 25_000,
    model: "claude-haiku-4-5-20251001",
    maxOutputTokens: 1200
  )

proc truncateRunes*(text: string, limit: int): string =
  ## Cuts `text` to at most `limit` RUNES, on a rune boundary. The single
  ## place any recorded string is shortened.
  if limit <= 0:
    return ""
  if text.runeLen <= limit:
    return text
  text.runeSubStr(0, limit)

proc truncateBytes*(text: string, limit: int): string =
  ## Cuts `text` to at most `limit` BYTES, still on a rune boundary. The
  ## whole-reply cap is the one cap the note states in KB rather than in
  ## runes, and `truncateRunes(text, 16384)` keeps 16384 RUNES — up to 64 KB
  ## of astral-plane text, four times the cap it was meant to enforce.
  if limit <= 0:
    return ""
  if text.len <= limit:
    return text
  var used = 0
  for r in text.runes:
    let size = r.size
    if used + size > limit:
      break
    used += size
  text[0 ..< used]

proc sanitizeLine*(text: string, limit: int): string =
  ## A recorded free-text line: newlines collapsed so one record stays one
  ## line, then truncated on a rune boundary.
  text.replace("\n", " ").replace("\r", " ").strip().truncateRunes(limit)

proc aliasFor*(slot: int): string =
  if slot == 0: AliasA else: AliasB
