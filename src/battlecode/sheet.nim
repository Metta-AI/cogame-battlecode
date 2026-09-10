## The doctrine sheet ENVELOPE: what a cog may say, how a reply is parsed
## TOLERANTLY, and how an illegal field is repaired instead of rejected.
##
## Year-neutral. The knob TABLE for a year — its types, its defaults, its
## ranges, its repair order and its plain-words readout — lives in
## `years/<year>/knobs.nim`; this file owns `notes`, `motto`,
## `defaultsApplied`, `unknownFields`, `submitted` and the dispatch into the
## year. The tolerant-parsing primitives live in `sheet_common.nim`.
##
## Both policy kinds — an LLM reply and a scripted baseline — go through this
## same `validate`, which is what makes `tests/test_baselines.nim`'s
## bounded-orders check meaningful and what makes an LLM doctrine and a
## scripted one strictly comparable.
##
## A sheet can never be REJECTED. An unknown key is recorded and ignored; a
## mistyped or out-of-range value takes that field's default. A cog therefore
## cannot forfeit a match by answering badly, only by answering weakly.
##
## `chassis` is NOT a knob in either year (D1). bc26 keeps the field on its
## `Doctrine` because the scripted filler path sets it directly and the replay
## records it; bc20 has no such field at all — its chassis is a `ChassisKind`
## the operator picks, carried on the seat record.

import std/[json, tables]
import sim_types, sheet_common
import years/bc26/knobs as knobs26
import years/bc20/knobs as knobs20
import years/bc21/knobs as knobs21
import years/bc24/knobs as knobs24
import years/bc25/knobs as knobs25
import years/bc23/knobs as knobs23
import years/bc22/knobs as knobs22
import years/bc16/knobs as knobs16
import years/bc19/knobs as knobs19

export sim_types, sheet_common, knobs26, knobs20, knobs21, knobs24,
  knobs25, knobs23, knobs22, knobs16, knobs19

const
  YearBc26* = "bc26"
  YearBc20* = "bc20"
  YearBc21* = "bc21"
  YearBc24* = "bc24"
  YearBc25* = "bc25"
  YearBc23* = "bc23"
  YearBc22* = "bc22"
  YearBc16* = "bc16"
  YearBc19* = "bc19"

type
  Sheet* = object
    year*: string
    doctrine*: knobs26.Doctrine       ## the bc26 knobs; defaults on a bc20 sheet
    doctrine20*: knobs20.Doctrine20   ## the bc20 knobs; defaults on another year
    doctrine21*: knobs21.Doctrine21   ## the bc21 knobs; defaults on another year
    doctrine24*: knobs24.Doctrine24   ## the bc24 knobs; defaults on another year
    doctrine25*: knobs25.Doctrine25   ## the bc25 knobs; defaults on another year
    doctrine23*: knobs23.Doctrine23   ## the bc23 knobs; defaults on another year
    doctrine22*: knobs22.Doctrine22   ## the bc22 knobs; defaults on another year
    doctrine16*: knobs16.Doctrine16   ## the bc16 knobs; defaults on another year
    doctrine19*: knobs19.Doctrine19   ## the bc19 knobs; defaults on another year
    notes*: string
    motto*: string
    defaultsApplied*: seq[string]
    unknownFields*: seq[string]
    submitted*: string   ## the raw sheet object as received, for the replay
    envelope*: string
      ## WHICH ENVELOPE RULE FIRED, or `""` when the payload itself was the
      ## sheet. Recorded in the replay as `seats[].sheet_envelope` and in the
      ## results document as the year-neutral optional `sheet_envelope`, so the
      ## LEARNINGS 2026-09-08 finding is machine-visible and not only drawn.

proc knownKeysFor*(year: string): seq[string] =
  case year
  of YearBc20: @(knobs20.KnownKeys20)
  of YearBc21: @(knobs21.KnownKeys21)
  of YearBc24: @(knobs24.KnownKeys24)
  of YearBc25: @(knobs25.KnownKeys25)
  of YearBc23: @(knobs23.KnownKeys23)
  of YearBc22: @(knobs22.KnownKeys22)
  of YearBc16: @(knobs16.KnownKeys16)
  of YearBc19: @(knobs19.KnownKeys19)
  else: @(knobs26.KnownKeys)

proc defaultSheet*(year = YearBc26): Sheet =
  Sheet(year: year, doctrine: knobs26.defaultDoctrine(),
        doctrine20: knobs20.defaultDoctrine20(),
        doctrine21: knobs21.defaultDoctrine21(),
        doctrine24: knobs24.defaultDoctrine24(),
        doctrine25: knobs25.defaultDoctrine25(),
        doctrine23: knobs23.defaultDoctrine23(),
        doctrine22: knobs22.defaultDoctrine22(),
        doctrine16: knobs16.defaultDoctrine16(),
        doctrine19: knobs19.defaultDoctrine19(),
        notes: "", motto: "", submitted: "{}", envelope: "")

proc validate*(payload: JsonNode, year = YearBc26): Sheet =
  ## Turn one parsed reply into a legal `Sheet`. Never raises: every bounded
  ## field is repaired to its default and the repair is recorded, so a cog
  ## always ends the doctrine phase with a playable doctrine.
  result = defaultSheet(year)
  let known = knownKeysFor(year)
  if payload.isNil or payload.kind != JObject:
    result.defaultsApplied = known
    return

  ## --- THE ENVELOPE RESOLVER (LEARNINGS 2026-09-08) ------------------------
  ## LLM champions sometimes wrap the sheet in a protocol envelope
  ## (`{"protocol": ..., "doctrine": {...}}`). This used to unwrap a key named
  ## `"sheet"` AND ONLY THAT ONE, so all the knobs landed in
  ## `sheet_unknown_fields`, the seat played the schema-default sheet, and
  ## `sheet_defaults_applied` stayed EMPTY because the keys were ABSENT rather
  ## than malformed. It happened in 2 of the first 3 bc23 league rounds and one
  ## champion won on defaults.
  ##
  ## The resolution order, YEAR-NEUTRAL, with the rule that fired recorded in
  ## `Sheet.envelope`:
  ##   1. `""`         — the payload itself carries at least one KNOWN knob key
  ##                     for this year (today's behaviour, unchanged);
  ##   2. `"sheet"`    — `payload["sheet"]` is a `JObject` (unchanged);
  ##   3. `"doctrine"` — `payload["doctrine"]` is a `JObject` (NEW);
  ##   4. `"<key>"`    — the payload has EXACTLY ONE key whose value is a
  ##                     `JObject` and no known knob name of its own (NEW, and
  ##                     it is what catches `{"battlecode_2022_doctrine": ...}`);
  ##   5. `""`         — otherwise the payload is used as today.
  ## Key names are matched through `normalizeKey`, so `"Doctrine"` and
  ## `"my-sheet"` resolve. NESTING IS UNWRAPPED AT MOST ONCE — a deliberate
  ## bound, so a malicious 500-deep reply cannot cost anything.
  ##
  ## THIS CANNOT CHANGE HOW ANY RECORDING RE-DERIVES: `replay.nim` re-validates
  ## the recorded APPLIED sheet wrapped in `{"sheet": ...}`, and an applied
  ## sheet is always a flat object of known keys.
  var sheetNode = payload
  var envelope = ""
  var hasKnownKey = false
  for key, _ in payload:
    if normalizeKey(key) in known:
      hasKnownKey = true
      break
  if not hasKnownKey:
    var sheetKey = ""
    var doctrineKey = ""
    var objectKeys: seq[string]
    for key, value in payload:
      if value.kind != JObject: continue
      objectKeys.add(key)
      let norm = normalizeKey(key)
      if norm == "sheet" and sheetKey.len == 0: sheetKey = key
      elif norm == "doctrine" and doctrineKey.len == 0: doctrineKey = key
    if sheetKey.len > 0:
      sheetNode = payload[sheetKey]
      envelope = "sheet"
    elif doctrineKey.len > 0:
      sheetNode = payload[doctrineKey]
      envelope = "doctrine"
    elif objectKeys.len == 1:
      sheetNode = payload[objectKeys[0]]
      envelope = normalizeKey(objectKeys[0])
  result.envelope = envelope
  result.submitted = $sheetNode

  var seen = initTable[string, JsonNode]()
  var keyCount = 0
  for key, value in sheetNode:
    inc keyCount
    if keyCount > MaxSheetKeys:
      break
    let norm = normalizeKey(key)
    if norm in known:
      seen[norm] = value
    elif result.unknownFields.len < MaxUnknownFields:
      ## This is where a submitted `chassis` lands, in EITHER year (D1):
      ## recorded, never honoured.
      result.unknownFields.add(key.truncateRunes(MaxUnknownFieldRunes))

  case year
  of YearBc20:
    result.doctrine20 = knobs20.applyKnobs20(seen, result.defaultsApplied)
  of YearBc21:
    result.doctrine21 = knobs21.applyKnobs21(seen, result.defaultsApplied)
  of YearBc24:
    result.doctrine24 = knobs24.applyKnobs24(seen, result.defaultsApplied)
  of YearBc25:
    result.doctrine25 = knobs25.applyKnobs25(seen, result.defaultsApplied)
  of YearBc23:
    result.doctrine23 = knobs23.applyKnobs23(seen, result.defaultsApplied)
  of YearBc22:
    ## bc22, bc16 and bc19 ALONE count an ABSENT known key in
    ## `defaultsApplied` (the envelope pin, item 2). Doing it year-neutrally
    ## would change what a bc26/bc20/bc21/bc23/bc24/bc25 episode records in
    ## that array, which "prior years' semantics unchanged" forbids.
    result.doctrine22 = knobs22.applyKnobs22(seen, result.defaultsApplied)
  of YearBc16:
    result.doctrine16 = knobs16.applyKnobs16(seen, result.defaultsApplied)
  of YearBc19:
    ## bc19 joins bc22 and bc16 in counting an ABSENT known key.
    result.doctrine19 = knobs19.applyKnobs19(seen, result.defaultsApplied)
  else:
    result.doctrine = knobs26.applyKnobs(seen, result.defaultsApplied)

  # --- free text -----------------------------------------------------------
  result.notes = sanitizeLine(payload{"notes"}.getStr(), MaxNoteRunes)
  result.motto = sanitizeLine(payload{"motto"}.getStr(), MaxMottoRunes)

proc parseReply*(text: string, year = YearBc26): Sheet =
  ## Tolerant end-to-end parse of one model reply. Raises only when there is
  ## no JSON object at all — the one condition the retry and then the
  ## scripted fallback exist for.
  ## MaxReplyBytes is BYTES (the note's cap table says 16 KB), cut on a rune
  ## boundary — `truncateRunes` here kept 16384 runes, i.e. up to 64 KB.
  let capped = text.truncateBytes(MaxReplyBytes)
  validate(extractJsonObject(capped), year)

proc toJson*(sheet: Sheet): JsonNode =
  case sheet.year
  of YearBc20: knobs20.toJson20(sheet.doctrine20)
  of YearBc21: knobs21.toJson21(sheet.doctrine21)
  of YearBc24: knobs24.toJson24(sheet.doctrine24)
  of YearBc25: knobs25.toJson25(sheet.doctrine25)
  of YearBc23: knobs23.toJson23(sheet.doctrine23)
  of YearBc22: knobs22.toJson22(sheet.doctrine22)
  of YearBc16: knobs16.toJson16(sheet.doctrine16)
  of YearBc19: knobs19.toJson19(sheet.doctrine19)
  else: knobs26.toJson(sheet.doctrine)

proc plainWords*(sheet: Sheet): seq[string] =
  ## The endcard/doctrine-overlay readout: the sheet in words a spectator can
  ## read without knowing the schema.
  case sheet.year
  of YearBc20: knobs20.plainWords20(sheet.doctrine20)
  of YearBc21: knobs21.plainWords21(sheet.doctrine21)
  of YearBc24: knobs24.plainWords24(sheet.doctrine24)
  of YearBc25: knobs25.plainWords25(sheet.doctrine25)
  of YearBc23: knobs23.plainWords23(sheet.doctrine23)
  of YearBc22: knobs22.plainWords22(sheet.doctrine22)
  of YearBc16: knobs16.plainWords16(sheet.doctrine16)
  of YearBc19: knobs19.plainWords19(sheet.doctrine19)
  else: knobs26.plainWords(sheet.doctrine)
