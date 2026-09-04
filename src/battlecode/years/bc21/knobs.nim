## The Battlecode 2021 "Campaign" knob table: TEN knobs, and NO `chassis` key.
##
## D1 (sibling review finding, 2026-09-03): the chassis is not an
## LLM-selectable knob. The chassis a seat drives comes from `PLAYER_SCRIPTED`
## (scripted seats) or is the fixed champion chassis (LLM seats). A submitted
## `chassis` is therefore recorded as an UNKNOWN FIELD and never honoured, and
## `tests/test_bc21_sheet.nim` asserts exactly that — the test fails if anyone
## re-adds the knob.
##
## Unknown key, wrong type or out-of-range value takes THAT FIELD'S DEFAULT and
## the repair is recorded. A sheet can never be rejected, so a cog can never
## forfeit a match by answering badly — only by answering weakly. EVERY setting
## of every knob drives the same competent chassis: no knob value selects a
## different, weaker bot. The chassis always builds, always defends its own
## Centers, always paths, and always ends its games; the knobs move *how much
## of what, when* — never *whether it plays*.

import std/[json, tables]
import ../../sheet_common

export sheet_common

type
  Opening21* = enum
    ## `ec.nim openingPlan()` — the build order for rounds 1...150.
    opMuckSpam = "muck_spam"
    opSlandererTurtle = "slanderer_turtle"
    opBalanced = "balanced"

  PoliticianCurve* = enum
    ## `ec.nim politicianInfluence(round)`.
    pcCheap = "cheap"
    pcRamp = "ramp"
    pcFat = "fat"

  BidPolicy* = enum
    ## `bids.nim`.
    bpNever = "never"
    bpFixed = "fixed"
    bpProportional = "proportional"
    bpEscalateWhenAhead = "escalate_when_ahead"

  Expansion* = enum
    ## `ec.nim targetPolicy()`.
    exNeutralCentersFirst = "neutral_centers_first"
    exDefendHome = "defend_home"

  FlankPolicy* = enum
    ## `muckraker.nim roam()`.
    fpScreenHome = "screen_home"
    fpHuntSlanderers = "hunt_slanderers"
    fpFlankWide = "flank_wide"

  Doctrine21* = object
    opening*: Opening21
    slandererRatio*: int
    muckRatio*: int
    politicianSizeCurve*: PoliticianCurve
    bidPolicy*: BidPolicy
    expansion*: Expansion
    flankPolicy*: FlankPolicy
    empowerThreshold*: int
    convertOverKill*: bool
    ecoExponentialRound*: int

const
  KnownKeys21* = [
    "opening", "slanderer_ratio", "muck_ratio", "politician_size_curve",
    "bid_policy", "expansion", "flank_policy", "empower_threshold",
    "convert_over_kill", "eco_exponential_round"
  ]
    ## Exactly ten. `chassis` is deliberately NOT here (D1).

proc defaultDoctrine21*(): Doctrine21 =
  Doctrine21(
    opening: opBalanced,
    slandererRatio: 45,
    muckRatio: 25,
    politicianSizeCurve: pcRamp,
    bidPolicy: bpProportional,
    expansion: exNeutralCentersFirst,
    flankPolicy: fpHuntSlanderers,
    empowerThreshold: 60,
    convertOverKill: true,
    ecoExponentialRound: 700
  )

proc applyKnobs21*(seen: Table[string, JsonNode],
                   defaultsApplied: var seq[string]): Doctrine21 =
  result = defaultDoctrine21()

  template repair(name: string) =
    defaultsApplied.add(name)

  template enumKnob(name: string, field: untyped, T: typedesc) =
    if name in seen:
      if seen[name].kind == JString:
        let text = normalizeKey(seen[name].getStr())
        var found = false
        for value in T:
          if normalizeKey($value) == text:
            field = value
            found = true
        if not found: repair(name)
      else:
        repair(name)

  template intKnob(name: string, field: untyped, lo, hi: int) =
    if name in seen:
      let n = readNumber(seen[name])
      if n.ok and n.value >= float(lo) and n.value <= float(hi):
        field = int(n.value)
      else:
        repair(name)

  template boolKnob(name: string, field: untyped) =
    if name in seen:
      let b = readBool(seen[name])
      if b.ok: field = b.value
      else: repair(name)

  enumKnob("opening", result.opening, Opening21)
  intKnob("slanderer_ratio", result.slandererRatio, 0, 100)
  intKnob("muck_ratio", result.muckRatio, 0, 100)
  enumKnob("politician_size_curve", result.politicianSizeCurve,
           PoliticianCurve)
  enumKnob("bid_policy", result.bidPolicy, BidPolicy)
  enumKnob("expansion", result.expansion, Expansion)
  enumKnob("flank_policy", result.flankPolicy, FlankPolicy)
  intKnob("empower_threshold", result.empowerThreshold, 0, 300)
  boolKnob("convert_over_kill", result.convertOverKill)
  intKnob("eco_exponential_round", result.ecoExponentialRound, 1, 1500)

proc toJson21*(d: Doctrine21): JsonNode =
  %*{
    "opening": $d.opening,
    "slanderer_ratio": d.slandererRatio,
    "muck_ratio": d.muckRatio,
    "politician_size_curve": $d.politicianSizeCurve,
    "bid_policy": $d.bidPolicy,
    "expansion": $d.expansion,
    "flank_policy": $d.flankPolicy,
    "empower_threshold": d.empowerThreshold,
    "convert_over_kill": d.convertOverKill,
    "eco_exponential_round": d.ecoExponentialRound
  }

# ---------------------------------------------------------------------------
#  Derived quantities the chassis reads. Kept here so the knob and the
#  behaviour it drives are one file apart at most.
# ---------------------------------------------------------------------------

proc spendMix*(d: Doctrine21): tuple[slanderer, muck, politician: int] =
  ## The post-opening build split. When `slanderer_ratio + muck_ratio > 100`
  ## they are renormalised DETERMINISTICALLY — `s' = s*100 div (s+m)`,
  ## `m' = 100 - s'`, politicians 0 — rather than one of them silently winning.
  var s = d.slandererRatio
  var m = d.muckRatio
  if s + m > 100:
    let total = s + m
    s = s * 100 div total
    m = 100 - s
    return (s, m, 0)
  (s, m, 100 - s - m)

proc politicianInfluence*(d: Doctrine21, round: int): int =
  case d.politicianSizeCurve
  of pcCheap: 18
  of pcRamp: clamp(18 + round div 25, 18, 120)
  of pcFat: clamp(40 + round div 8, 40, 400)

proc compounding*(d: Doctrine21, round: int): bool =
  ## `ec.nim phase()`: before `eco_exponential_round` every Center reinvests
  ## and `slanderer_ratio` applies at full weight; from it, slanderer
  ## production stops entirely and the share is redistributed.
  round < d.ecoExponentialRound

proc bc21SheetSchema*(): JsonNode =
  ## The knob surface as the doctrine prompt carries it: every knob, its
  ## values or range, and its default. Generated from THIS table rather than
  ## re-typed, so a knob cannot exist in the sim and be missing from the brief.
  let d = defaultDoctrine21()
  var opening = newJArray()
  for v in Opening21: opening.add(%($v))
  var curve = newJArray()
  for v in PoliticianCurve: curve.add(%($v))
  var bidp = newJArray()
  for v in BidPolicy: bidp.add(%($v))
  var expansion = newJArray()
  for v in Expansion: expansion.add(%($v))
  var flank = newJArray()
  for v in FlankPolicy: flank.add(%($v))
  %*{
    "opening": {"values": opening, "default": $d.opening},
    "slanderer_ratio": {"range": [0, 100], "default": d.slandererRatio},
    "muck_ratio": {"range": [0, 100], "default": d.muckRatio},
    "politician_size_curve": {"values": curve,
                              "default": $d.politicianSizeCurve},
    "bid_policy": {"values": bidp, "default": $d.bidPolicy},
    "expansion": {"values": expansion, "default": $d.expansion},
    "flank_policy": {"values": flank, "default": $d.flankPolicy},
    "empower_threshold": {"range": [0, 300], "default": d.empowerThreshold},
    "convert_over_kill": {"values": [true, false],
                          "default": d.convertOverKill},
    "eco_exponential_round": {"range": [1, 1500],
                              "default": d.ecoExponentialRound}
  }

proc plainWords21*(d: Doctrine21): seq[string] =
  ## The endcard / `#bc21-doctrines` readout: the sheet in words a spectator
  ## can read without knowing the schema.
  case d.opening
  of opMuckSpam: result.add("spams muckrakers")
  of opSlandererTurtle: result.add("turtles and prints money")
  of opBalanced: result.add("opens balanced")
  result.add($d.slandererRatio & " % of spend on slanderers")
  result.add($d.muckRatio & " % of spend on muckrakers")
  case d.politicianSizeCurve
  of pcCheap: result.add("cheap politicians")
  of pcRamp: result.add("politicians ramp with the round")
  of pcFat: result.add("fat politicians")
  case d.bidPolicy
  of bpNever: result.add("never bids")
  of bpFixed: result.add("bids a flat 2")
  of bpProportional: result.add("bids proportionally")
  of bpEscalateWhenAhead: result.add("escalates the bid when ahead")
  case d.expansion
  of exNeutralCentersFirst: result.add("takes the neutral centres first")
  of exDefendHome: result.add("defends home")
  case d.flankPolicy
  of fpScreenHome: result.add("screens home")
  of fpHuntSlanderers: result.add("hunts slanderers")
  of fpFlankWide: result.add("flanks wide")
  if d.empowerThreshold == 0:
    result.add("empowers on contact")
  else:
    result.add("empowers at " & $d.empowerThreshold & " %")
  if d.convertOverKill:
    result.add("converts rather than kills")
  else:
    result.add("kills rather than converts")
  result.add("stops compounding at round " & $d.ecoExponentialRound)
