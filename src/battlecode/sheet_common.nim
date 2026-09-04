## Year-neutral doctrine-sheet plumbing, extracted UNCHANGED from `sheet.nim`
## when the second year module landed.
##
## `normalizeKey`, `readNumber`, `readBool` and `extractJsonObject` are the
## tolerant-parsing primitives every year's knob table repairs values with;
## the rune and byte caps and `sanitizeLine` live in `sim_types` and are
## re-exported here so a `years/<year>/knobs.nim` needs exactly one import.
##
## Nothing here knows what a knob is. A year's knob table lives in
## `years/<year>/knobs.nim`, and `sheet.nim` is the envelope that dispatches
## into it.

import std/[json, strutils]
import sim_types

export sim_types

proc normalizeKey*(text: string): string =
  text.strip().toLowerAscii().replace("-", "_").replace(" ", "_")

proc enumFromText*[T: enum](text: string, fallback: T): T =
  let key = normalizeKey(text)
  for value in T:
    if normalizeKey($value) == key:
      return value
  fallback

proc readNumber*(node: JsonNode): tuple[ok: bool, value: float] =
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

proc readBool*(node: JsonNode): tuple[ok: bool, value: bool] =
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
