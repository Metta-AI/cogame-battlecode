## The Battlecode 2026 knob table: the ten `Doctrine` knobs, its defaults, its
## per-field repair and its plain-words readout — plus the chassis selector,
## which is NOT one of them.
##
## MOVED VERBATIM out of `sheet.nim` when the bc20 year module landed, at the
## post-D1 state: no bc26 semantics change, the type, the defaults, the ranges
## and the repair order are the ones on `main`, and `tests/test_sheet.nim` is
## unchanged. `sheet.nim` is now the year-neutral envelope that dispatches in
## here.

import std/[json, tables]
import ../../sheet_common

export sheet_common

type
  Chassis* = enum
    chAwu = "awu"
    chScaffold = "scaffold"

  BackstabPolicy* = enum
    bpNever = "never"
    bpWhenAhead = "when_ahead"
    bpAtRoundN = "at_round_N"
    bpOnFirstContact = "on_first_contact"
    bpRetaliateOnly = "retaliate_only"

  CatEngagement* = enum
    ceAvoid = "avoid"
    ceOpportunistic = "opportunistic"
    ceHunt = "hunt"
    ceFeed = "feed"

  SpawnCurve* = enum
    scLean = "lean"
    scSteady = "steady"
    scSwarm = "swarm"

  DirtWallPolicy* = enum
    dwNone = "none"
    dwKingShell = "king_shell"
    dwChoke = "choke"

  Doctrine* = object
    ## The 10 doctrine knobs, each with a named site in the chassis
    ## (docs/RULES.md §The doctrine sheet lists the site per knob), plus the
    ## chassis selector, which is NOT one of them.
    chassis*: Chassis
      ## NOT A KNOB. An LLM doctrine always runs `awu`: `chassis` is absent
      ## from `KnownKeys` and from the prompt's knob list, so a reply that
      ## names it is recorded in `unknownFields` and ignored. The only way to
      ## select `scaffold` is the scripted filler path
      ## (`PLAYER_SCRIPTED=scaffold` → `baselines.baselineSheet`), which sets
      ## this field directly rather than through the sheet.
    backstabPolicy*: BackstabPolicy
    backstabRound*: int
    catEngagement*: CatEngagement
    catTrapBudget*: int
    ratTrapBudget*: int
    spawnCurve*: SpawnCurve
    cheeseFerryRatio*: float
    kingCountTarget*: int
    dirtWallPolicy*: DirtWallPolicy
    throwRatsToFeedCats*: bool

const
  KnownKeys* = [
    "backstab_policy", "backstab_round", "cat_engagement",
    "cat_trap_budget", "rat_trap_budget", "spawn_curve", "cheese_ferry_ratio",
    "king_count_target", "dirt_wall_policy", "throw_rats_to_feed_cats"
  ]
    ## THE LLM-VISIBLE KNOB SURFACE, and the same list the prompt preamble
    ## prints. `chassis` is deliberately not in it: which bot drives the clan
    ## is not a strategic choice a cog gets to make, it is which policy the
    ## operator ran. A reply that sends `chassis` is treated as any other
    ## unknown key — recorded, ignored, and the clan plays `awu`.

proc defaultDoctrine*(): Doctrine =
  Doctrine(
    chassis: chAwu,
    backstabPolicy: bpRetaliateOnly,
    backstabRound: 600,
    catEngagement: ceOpportunistic,
    catTrapBudget: 40,
    ratTrapBudget: 60,
    spawnCurve: scSteady,
    cheeseFerryRatio: 0.5,
    kingCountTarget: 3,
    dirtWallPolicy: dwKingShell,
    throwRatsToFeedCats: false
  )

proc parseChassis*(text: string): Chassis =
  ## The RECORDED chassis, read back on playback. `validate` never reads
  ## `chassis` — it is not a knob — so the replay's applied sheet is the only
  ## place the deriver can learn which bot actually drove a clan. Anything
  ## unrecognised is `awu`, the chassis every LLM doctrine runs.
  let key = normalizeKey(text)
  for value in Chassis:
    if $value == key:
      return value
  chAwu

proc applyKnobs*(seen: Table[string, JsonNode],
                 defaultsApplied: var seq[string]): Doctrine =
  ## Repair every bounded field to its default and RECORD the repair, so a cog
  ## always ends the doctrine phase with a playable doctrine.
  ##
  ## `chassis` is NOT read here. It is not in `KnownKeys`, so the envelope has
  ## already recorded it in `unknownFields`; the returned doctrine keeps
  ## `defaultDoctrine()`'s `awu`, and `decide.nim` logs the seat that tried.
  result = defaultDoctrine()

  template repair(name: string) =
    defaultsApplied.add(name)

  # --- chassis is NOT read here --------------------------------------------
  # It is not in `KnownKeys`, so the loop above has already recorded it in
  # `unknownFields`; `result.chassis` keeps `defaultDoctrine()`'s
  # `awu`. `decide.nim` logs the seat that tried.

  # --- backstab_policy / backstab_round ------------------------------------
  if "backstab_policy" in seen:
    if seen["backstab_policy"].kind == JString:
      let text = normalizeKey(seen["backstab_policy"].getStr())
      var found = false
      for value in BackstabPolicy:
        if normalizeKey($value) == text:
          result.backstabPolicy = value
          found = true
      if not found: repair("backstab_policy")
    else:
      repair("backstab_policy")
  if "backstab_round" in seen:
    let n = readNumber(seen["backstab_round"])
    if n.ok and n.value >= 1.0 and n.value <= 2000.0:
      result.backstabRound = int(n.value)
    else:
      repair("backstab_round")

  # --- cat_engagement ------------------------------------------------------
  if "cat_engagement" in seen:
    if seen["cat_engagement"].kind == JString:
      let text = normalizeKey(seen["cat_engagement"].getStr())
      var found = false
      for value in CatEngagement:
        if normalizeKey($value) == text:
          result.catEngagement = value
          found = true
      if not found: repair("cat_engagement")
    else:
      repair("cat_engagement")

  # --- integer budgets -----------------------------------------------------
  template intKnob(name: string, field: untyped, lo, hi: int) =
    if name in seen:
      let n = readNumber(seen[name])
      if n.ok and n.value >= float(lo) and n.value <= float(hi):
        field = int(n.value)
      else:
        repair(name)

  intKnob("cat_trap_budget", result.catTrapBudget, 0, 200)
  intKnob("rat_trap_budget", result.ratTrapBudget, 0, 200)
  intKnob("king_count_target", result.kingCountTarget, 1, 5)

  # --- spawn_curve ---------------------------------------------------------
  if "spawn_curve" in seen:
    if seen["spawn_curve"].kind == JString:
      let text = normalizeKey(seen["spawn_curve"].getStr())
      var found = false
      for value in SpawnCurve:
        if normalizeKey($value) == text:
          result.spawnCurve = value
          found = true
      if not found: repair("spawn_curve")
    else:
      repair("spawn_curve")

  # --- cheese_ferry_ratio --------------------------------------------------
  if "cheese_ferry_ratio" in seen:
    let n = readNumber(seen["cheese_ferry_ratio"])
    if n.ok and n.value >= 0.0 and n.value <= 1.0:
      result.cheeseFerryRatio = n.value
    else:
      repair("cheese_ferry_ratio")

  # --- dirt_wall_policy ----------------------------------------------------
  if "dirt_wall_policy" in seen:
    if seen["dirt_wall_policy"].kind == JString:
      let text = normalizeKey(seen["dirt_wall_policy"].getStr())
      var found = false
      for value in DirtWallPolicy:
        if normalizeKey($value) == text:
          result.dirtWallPolicy = value
          found = true
      if not found: repair("dirt_wall_policy")
    else:
      repair("dirt_wall_policy")

  # --- throw_rats_to_feed_cats ---------------------------------------------
  if "throw_rats_to_feed_cats" in seen:
    let b = readBool(seen["throw_rats_to_feed_cats"])
    if b.ok:
      result.throwRatsToFeedCats = b.value
    else:
      repair("throw_rats_to_feed_cats")

proc toJson*(d: Doctrine): JsonNode =
  %*{
    "chassis": $d.chassis,
    "backstab_policy": $d.backstabPolicy,
    "backstab_round": d.backstabRound,
    "cat_engagement": $d.catEngagement,
    "cat_trap_budget": d.catTrapBudget,
    "rat_trap_budget": d.ratTrapBudget,
    "spawn_curve": $d.spawnCurve,
    "cheese_ferry_ratio": d.cheeseFerryRatio,
    "king_count_target": d.kingCountTarget,
    "dirt_wall_policy": $d.dirtWallPolicy,
    "throw_rats_to_feed_cats": d.throwRatsToFeedCats
  }

proc plainWords*(d: Doctrine): seq[string] =
  ## The endcard/`#doctrines` readout: the sheet in words a spectator can
  ## read without knowing the schema.
  case d.backstabPolicy
  of bpNever: result.add("never betrays")
  of bpRetaliateOnly: result.add("retaliates only")
  of bpWhenAhead: result.add("betrays when ahead")
  of bpAtRoundN: result.add("betrays at round " & $d.backstabRound)
  of bpOnFirstContact: result.add("betrays on first contact")
  case d.catEngagement
  of ceAvoid: result.add("avoids cats")
  of ceOpportunistic: result.add("fights cats when handy")
  of ceHunt: result.add("hunts cats")
  of ceFeed: result.add("feeds rats to cats")
  result.add($d.spawnCurve & " spawning")
  result.add("keeps " & $d.kingCountTarget & " kings")
  result.add($d.ratTrapBudget & " rat traps")
  result.add($d.catTrapBudget & " cat traps")
  result.add($int(d.cheeseFerryRatio * 100) & "% ferrying")
  case d.dirtWallPolicy
  of dwNone: result.add("no dirt work")
  of dwKingShell: result.add("walls its kings in")
  of dwChoke: result.add("walls the chokepoints")
  if d.throwRatsToFeedCats:
    result.add("throws rats to cats")
