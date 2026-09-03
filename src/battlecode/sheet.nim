## The doctrine sheet: what a cog may say, how a reply is parsed TOLERANTLY,
## and how an illegal field is repaired instead of rejected.
##
## Both policy kinds — an LLM reply and a scripted baseline — go through this
## same `validate`, which is what makes `tests/test_baselines.nim`'s
## bounded-orders check meaningful and what makes an LLM doctrine and a
## scripted one strictly comparable.
##
## A sheet can never be REJECTED. An unknown key is recorded and ignored; a
## mistyped or out-of-range value takes that field's default. A cog therefore
## cannot forfeit a match by answering badly, only by answering weakly.

import std/[json, strutils, tables, unicode]
import sim_types

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
    ## The 11 knobs, each with a named site in the chassis (docs/RULES.md
    ## §The doctrine sheet lists the site per knob).
    chassis*: Chassis
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

  Sheet* = object
    doctrine*: Doctrine
    notes*: string
    motto*: string
    defaultsApplied*: seq[string]
    unknownFields*: seq[string]
    submitted*: string   ## the raw sheet object as received, for the replay

const
  KnownKeys* = [
    "chassis", "backstab_policy", "backstab_round", "cat_engagement",
    "cat_trap_budget", "rat_trap_budget", "spawn_curve", "cheese_ferry_ratio",
    "king_count_target", "dirt_wall_policy", "throw_rats_to_feed_cats"
  ]

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

proc defaultSheet*(): Sheet =
  Sheet(doctrine: defaultDoctrine(), notes: "", motto: "", submitted: "{}")

proc normalizeKey(text: string): string =
  text.strip().toLowerAscii().replace("-", "_").replace(" ", "_")

proc enumFromText[T: enum](text: string, fallback: T): T =
  let key = normalizeKey(text)
  for value in T:
    if normalizeKey($value) == key:
      return value
  fallback

proc readNumber(node: JsonNode): tuple[ok: bool, value: float] =
  ## An int, a float, or a numeric string. Anything non-finite reports
  ## `ok = false` so the caller applies the field's default rather than
  ## inventing a value.
  if node.isNil: return (false, 0.0)
  case node.kind
  of JInt: (true, float(node.getBiggestInt()))
  of JFloat:
    let f = node.getFloat()
    if f != f or f > 1.0e9 or f < -1.0e9: (false, 0.0) else: (true, f)
  of JString:
    try: (true, parseFloat(node.getStr().strip()))
    except CatchableError: (false, 0.0)
  of JBool: (true, (if node.getBool(): 1.0 else: 0.0))
  else: (false, 0.0)

proc readBool(node: JsonNode): tuple[ok: bool, value: bool] =
  if node.isNil: return (false, false)
  case node.kind
  of JBool: (true, node.getBool())
  of JInt: (true, node.getBiggestInt() != 0)
  of JString:
    case normalizeKey(node.getStr())
    of "true", "yes", "1", "on": (true, true)
    of "false", "no", "0", "off": (true, false)
    else: (false, false)
  else: (false, false)

proc extractJsonObject*(text: string): JsonNode =
  ## The outermost balanced `{...}` in a model reply, tolerating markdown
  ## fences and any prose around it. Falls back to first-brace..last-brace,
  ## which recovers a reply whose braces sit inside a quoted string.
  var
    depth = 0
    start = -1
    inString = false
    escaped = false
  for i, ch in text:
    if inString:
      if escaped: escaped = false
      elif ch == '\\': escaped = true
      elif ch == '"': inString = false
      continue
    case ch
    of '"': inString = true
    of '{':
      if depth == 0: start = i
      inc depth
    of '}':
      if depth > 0:
        dec depth
        if depth == 0 and start >= 0:
          try:
            return parseJson(text[start .. i])
          except CatchableError:
            start = -1
    else: discard
  let
    first = text.find('{')
    last = text.rfind('}')
  if first < 0 or last <= first:
    raise newException(BattlecodeError,
      "no JSON object in reply: " & text.strip().truncateRunes(160).
        replace("\n", " "))
  parseJson(text[first .. last])

proc validate*(payload: JsonNode): Sheet =
  ## Turn one parsed reply into a legal `Sheet`. Never raises: every bounded
  ## field is repaired to its default and the repair is recorded, so a cog
  ## always ends the doctrine phase with a playable doctrine.
  result = defaultSheet()
  if payload.isNil or payload.kind != JObject:
    result.defaultsApplied = @KnownKeys
    return

  let sheetNode =
    if payload.hasKey("sheet") and payload["sheet"].kind == JObject:
      payload["sheet"]
    else:
      payload
  result.submitted = $sheetNode

  var seen = initTable[string, JsonNode]()
  var keyCount = 0
  for key, value in sheetNode:
    inc keyCount
    if keyCount > MaxSheetKeys:
      break
    let norm = normalizeKey(key)
    if norm in KnownKeys:
      seen[norm] = value
    elif result.unknownFields.len < MaxUnknownFields:
      result.unknownFields.add(key.truncateRunes(MaxUnknownFieldRunes))

  template repair(name: string) =
    result.defaultsApplied.add(name)

  # --- chassis -------------------------------------------------------------
  if "chassis" in seen and seen["chassis"].kind == JString:
    let text = normalizeKey(seen["chassis"].getStr())
    var found = false
    for value in Chassis:
      if $value == text:
        result.doctrine.chassis = value
        found = true
    if not found: repair("chassis")
  elif "chassis" in seen:
    repair("chassis")

  # --- backstab_policy / backstab_round ------------------------------------
  if "backstab_policy" in seen:
    if seen["backstab_policy"].kind == JString:
      let text = normalizeKey(seen["backstab_policy"].getStr())
      var found = false
      for value in BackstabPolicy:
        if normalizeKey($value) == text:
          result.doctrine.backstabPolicy = value
          found = true
      if not found: repair("backstab_policy")
    else:
      repair("backstab_policy")
  if "backstab_round" in seen:
    let n = readNumber(seen["backstab_round"])
    if n.ok and n.value >= 1.0 and n.value <= 2000.0:
      result.doctrine.backstabRound = int(n.value)
    else:
      repair("backstab_round")

  # --- cat_engagement ------------------------------------------------------
  if "cat_engagement" in seen:
    if seen["cat_engagement"].kind == JString:
      let text = normalizeKey(seen["cat_engagement"].getStr())
      var found = false
      for value in CatEngagement:
        if normalizeKey($value) == text:
          result.doctrine.catEngagement = value
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

  intKnob("cat_trap_budget", result.doctrine.catTrapBudget, 0, 200)
  intKnob("rat_trap_budget", result.doctrine.ratTrapBudget, 0, 200)
  intKnob("king_count_target", result.doctrine.kingCountTarget, 1, 5)

  # --- spawn_curve ---------------------------------------------------------
  if "spawn_curve" in seen:
    if seen["spawn_curve"].kind == JString:
      let text = normalizeKey(seen["spawn_curve"].getStr())
      var found = false
      for value in SpawnCurve:
        if normalizeKey($value) == text:
          result.doctrine.spawnCurve = value
          found = true
      if not found: repair("spawn_curve")
    else:
      repair("spawn_curve")

  # --- cheese_ferry_ratio --------------------------------------------------
  if "cheese_ferry_ratio" in seen:
    let n = readNumber(seen["cheese_ferry_ratio"])
    if n.ok and n.value >= 0.0 and n.value <= 1.0:
      result.doctrine.cheeseFerryRatio = n.value
    else:
      repair("cheese_ferry_ratio")

  # --- dirt_wall_policy ----------------------------------------------------
  if "dirt_wall_policy" in seen:
    if seen["dirt_wall_policy"].kind == JString:
      let text = normalizeKey(seen["dirt_wall_policy"].getStr())
      var found = false
      for value in DirtWallPolicy:
        if normalizeKey($value) == text:
          result.doctrine.dirtWallPolicy = value
          found = true
      if not found: repair("dirt_wall_policy")
    else:
      repair("dirt_wall_policy")

  # --- throw_rats_to_feed_cats ---------------------------------------------
  if "throw_rats_to_feed_cats" in seen:
    let b = readBool(seen["throw_rats_to_feed_cats"])
    if b.ok:
      result.doctrine.throwRatsToFeedCats = b.value
    else:
      repair("throw_rats_to_feed_cats")

  # --- free text -----------------------------------------------------------
  result.notes = sanitizeLine(payload{"notes"}.getStr(), MaxNoteRunes)
  result.motto = sanitizeLine(payload{"motto"}.getStr(), MaxMottoRunes)

proc parseReply*(text: string): Sheet =
  ## Tolerant end-to-end parse of one model reply. Raises only when there is
  ## no JSON object at all — the one condition the retry and then the
  ## scripted fallback exist for.
  let capped =
    if text.len > MaxReplyBytes: text.truncateRunes(MaxReplyBytes)
    else: text
  validate(extractJsonObject(capped))

proc toJson*(sheet: Sheet): JsonNode =
  %*{
    "chassis": $sheet.doctrine.chassis,
    "backstab_policy": $sheet.doctrine.backstabPolicy,
    "backstab_round": sheet.doctrine.backstabRound,
    "cat_engagement": $sheet.doctrine.catEngagement,
    "cat_trap_budget": sheet.doctrine.catTrapBudget,
    "rat_trap_budget": sheet.doctrine.ratTrapBudget,
    "spawn_curve": $sheet.doctrine.spawnCurve,
    "cheese_ferry_ratio": sheet.doctrine.cheeseFerryRatio,
    "king_count_target": sheet.doctrine.kingCountTarget,
    "dirt_wall_policy": $sheet.doctrine.dirtWallPolicy,
    "throw_rats_to_feed_cats": sheet.doctrine.throwRatsToFeedCats
  }

proc plainWords*(sheet: Sheet): seq[string] =
  ## The endcard/`#doctrines` readout: the sheet in words a spectator can
  ## read without knowing the schema.
  case sheet.doctrine.backstabPolicy
  of bpNever: result.add("never betrays")
  of bpRetaliateOnly: result.add("retaliates only")
  of bpWhenAhead: result.add("betrays when ahead")
  of bpAtRoundN: result.add("betrays at round " & $sheet.doctrine.backstabRound)
  of bpOnFirstContact: result.add("betrays on first contact")
  case sheet.doctrine.catEngagement
  of ceAvoid: result.add("avoids cats")
  of ceOpportunistic: result.add("fights cats when handy")
  of ceHunt: result.add("hunts cats")
  of ceFeed: result.add("feeds rats to cats")
  result.add($sheet.doctrine.spawnCurve & " spawning")
  result.add("keeps " & $sheet.doctrine.kingCountTarget & " kings")
  result.add($sheet.doctrine.ratTrapBudget & " rat traps")
  result.add($sheet.doctrine.catTrapBudget & " cat traps")
  result.add($int(sheet.doctrine.cheeseFerryRatio * 100) & "% ferrying")
  case sheet.doctrine.dirtWallPolicy
  of dwNone: result.add("no dirt work")
  of dwKingShell: result.add("walls its kings in")
  of dwChoke: result.add("walls the chokepoints")
  if sheet.doctrine.throwRatsToFeedCats:
    result.add("throws rats to cats")
