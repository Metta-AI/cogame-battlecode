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

  GameVersion* = "GV04"
    ## PREPEND-ONLY CHANGELOG. Anything that changes what a policy sees, how a
    ## seat is scored, or how a round resolves bumps this in the SAME commit,
    ## and `tools/ci/check_gameversion.sh` compares the headline (not the
    ## digits) against the base branch — a number alone cannot detect two
    ## branches claiming the same version for different rules.
    ##
    ## GV04 — `chassis` is no longer a doctrine knob. It is gone from
    ##        `sheet.KnownKeys` and from the prompt preamble's knob list, so
    ##        an LLM doctrine ALWAYS runs the `awu` chassis and a reply that
    ##        still sends `chassis` is recorded in `sheet_unknown_fields`,
    ##        ignored and logged. `scaffold` is selectable only by
    ##        `PLAYER_SCRIPTED=scaffold`, which sets the chassis directly.
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

  ReplayCompatibleGameVersions* = [GameVersion]
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
