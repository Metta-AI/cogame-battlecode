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

proc baselineReply*(kind: Baseline): string =
  ## The exact JSON a scripted seat "answers" with. Emitted as text and then
  ## parsed by the same tolerant validator, so a scripted seat is
  ## indistinguishable from an LLM seat downstream.
  case kind
  of blAwu:
    """{"sheet":{"chassis":"awu"},"notes":"default awu doctrine",
        "motto":"Cheese first."}"""
  of blScaffold:
    """{"sheet":{"chassis":"scaffold"},"notes":"scaffold baseline",
        "motto":"Forward."}"""

proc baselineSheet*(kind: Baseline): Sheet =
  result = parseReply(baselineReply(kind))
