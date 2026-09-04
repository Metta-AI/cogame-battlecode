## The two published scripted baselines.
##
## Both answer the doctrine request from a TABLE — no model, no network — and
## both replies go through the SAME `sheet.validate()` the LLM path uses,
## which is what makes `tests/test_baselines.nim`'s bounded-orders check
## meaningful and an LLM doctrine and a scripted one strictly comparable.

import std/strutils
import sheet

type
  Baseline* = enum
    blAwu = "awu"
    blScaffold = "scaffold"

proc parseBaseline*(text: string): Baseline =
  ## `PLAYER_SCRIPTED` values. Anything unrecognised is `awu`: a seat that
  ## says nothing useful still plays the published default rather than the
  ## deliberately weak floor.
  case text.strip().toLowerAscii()
  of "scaffold", "examplefuncsplayer", "example": blScaffold
  else: blAwu

proc chassisFor*(kind: Baseline): Chassis =
  ## The filler path's chassis selection, and the ONLY one there is. It is not
  ## a sheet key: an LLM doctrine cannot reach it (see `sheet.KnownKeys`), so
  ## `scaffold` is selectable only by `PLAYER_SCRIPTED=scaffold`.
  case kind
  of blAwu: chAwu
  of blScaffold: chScaffold

proc baselineReply*(kind: Baseline): string =
  ## The exact JSON a scripted seat "answers" with. Emitted as text and then
  ## parsed by the same tolerant validator, so a scripted seat is
  ## indistinguishable from an LLM seat downstream — which is why it carries
  ## only keys the LLM surface also has, and never `chassis`.
  case kind
  of blAwu:
    """{"sheet":{},"notes":"default awu doctrine",
        "motto":"Cheese first."}"""
  of blScaffold:
    """{"sheet":{},"notes":"scaffold baseline",
        "motto":"Forward."}"""

proc baselineSheet*(kind: Baseline): Sheet =
  result = parseReply(baselineReply(kind))
  result.doctrine.chassis = chassisFor(kind)
