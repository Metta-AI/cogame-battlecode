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

export sim_types, sheet_common, knobs26, knobs20, knobs21, knobs24

const
  YearBc26* = "bc26"
  YearBc20* = "bc20"
  YearBc21* = "bc21"
  YearBc24* = "bc24"

type
  Sheet* = object
    year*: string
    doctrine*: knobs26.Doctrine       ## the bc26 knobs; defaults on a bc20 sheet
    doctrine20*: knobs20.Doctrine20   ## the bc20 knobs; defaults on another year
    doctrine21*: knobs21.Doctrine21   ## the bc21 knobs; defaults on another year
    doctrine24*: knobs24.Doctrine24   ## the bc24 knobs; defaults on another year
    notes*: string
    motto*: string
    defaultsApplied*: seq[string]
    unknownFields*: seq[string]
    submitted*: string   ## the raw sheet object as received, for the replay

proc knownKeysFor*(year: string): seq[string] =
  case year
  of YearBc20: @(knobs20.KnownKeys20)
  of YearBc21: @(knobs21.KnownKeys21)
  of YearBc24: @(knobs24.KnownKeys24)
  else: @(knobs26.KnownKeys)

proc defaultSheet*(year = YearBc26): Sheet =
  Sheet(year: year, doctrine: knobs26.defaultDoctrine(),
        doctrine20: knobs20.defaultDoctrine20(),
        doctrine21: knobs21.defaultDoctrine21(),
        doctrine24: knobs24.defaultDoctrine24(),
        notes: "", motto: "", submitted: "{}")

proc validate*(payload: JsonNode, year = YearBc26): Sheet =
  ## Turn one parsed reply into a legal `Sheet`. Never raises: every bounded
  ## field is repaired to its default and the repair is recorded, so a cog
  ## always ends the doctrine phase with a playable doctrine.
  result = defaultSheet(year)
  let known = knownKeysFor(year)
  if payload.isNil or payload.kind != JObject:
    result.defaultsApplied = known
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
  else: knobs26.toJson(sheet.doctrine)

proc plainWords*(sheet: Sheet): seq[string] =
  ## The endcard/doctrine-overlay readout: the sheet in words a spectator can
  ## read without knowing the schema.
  case sheet.year
  of YearBc20: knobs20.plainWords20(sheet.doctrine20)
  of YearBc21: knobs21.plainWords21(sheet.doctrine21)
  of YearBc24: knobs24.plainWords24(sheet.doctrine24)
  else: knobs26.plainWords(sheet.doctrine)
