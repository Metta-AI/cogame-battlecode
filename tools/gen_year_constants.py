#!/usr/bin/env python3
"""Generate src/battlecode/years/<year>/constants.nim from the pinned engine.

CI-TIME ONLY (Python and a Java *source* checkout; no JVM is involved, and
neither exists in any runtime image stage). The Battlecode 2026 rule set has
69 numeric constants plus two enum tables, and hand-transcribing them is the
kind of work that goes wrong once and stays wrong for a season -- so they are
read straight out of the engine sources at tag engine.1.2.5 and emitted
mechanically. `tests/test_constants.nim` re-runs this and byte-diffs, so a
hand-edited constant fails the build.

    tools/gen_year_constants.py --engine /path/to/battlecode26-engine.1.2.5 \
        --out src/battlecode/years/bc26/constants.nim
    tools/gen_year_constants.py --engine ... --check   # diff, exit 1 on drift

`--year bc20`, `--year bc21`, `--year bc22`, `--year bc23`, `--year bc24` and
`--year bc25` do the same job
for the other year modules against a checkout of the matching engine at its
pinned commit. bc20 and bc21 read `common/GameConstants.java` and
`common/RobotType.java`; bc24 reads `common/GameConstants.java`,
`common/SkillType.java`, `common/TrapType.java` and `common/GlobalUpgrade.java`;
bc25 reads `common/GameConstants.java` and `common/UnitType.java`; bc23 reads
`common/GameConstants.java`, `common/RobotType.java` and `common/Anchor.java`;
bc22 reads `common/GameConstants.java`, `common/RobotType.java` and
`common/AnomalyType.java`:

    tools/gen_year_constants.py --year bc20 --engine /path/to/battlecode20 \
        --out src/battlecode/years/bc20/constants.nim

The engine checkout is fetched by CI:
    curl -fsSL https://github.com/battlecode/battlecode26/archive/refs/tags/engine.1.2.5.tar.gz
"""

from __future__ import annotations

import argparse
import pathlib
import re
import struct
import sys

TAG = "engine.1.2.5"

CONST_RE = re.compile(
    r"public\s+static\s+final\s+(int|long|float|double|String)\s+"
    r"([A-Z0-9_]+)\s*=\s*([^;]+);"
)
UNIT_RE = re.compile(
    r"^\s*(BABY_RAT|RAT_KING|CAT)\((.*?)\)\s*[,;]\s*$", re.M
)
TRAP_RE = re.compile(
    r"^\s*(RAT_TRAP|CAT_TRAP|NONE)\((.*?)\)\s*[,;]\s*$", re.M
)

def nim_literal(java_type: str, raw: str) -> tuple[str, str]:
    """(nim type, nim literal) for one Java constant initialiser.

    The WIDTHS are load-bearing, not cosmetic. `CHEESE_MINE_SPAWN_PROBABILITY`
    is a Java `float`, so `1 - it` is 0.00999999977..., not 0.01, and the
    cheese-mine spawn test lands differently for a mine that has been quiet
    for a few hundred rounds. `MAX_TEAM_EXECUTION_TIME` is a `long` that does
    not fit the 32-bit `int` a wasm32 build gets.
    """
    text = raw.strip()
    if java_type == "String":
        return "string", text
    # The 2020 rule set names one constant by a Java expression rather than a
    # literal: MIN_WATER_ELEVATION = Integer.MIN_VALUE/2. Evaluate the handful
    # of forms that actually occur rather than hand-typing the value.
    JAVA_EXPRESSIONS = {
        "Integer.MIN_VALUE/2": "-1073741824",
        "Integer.MAX_VALUE/2": "1073741823",
        # 2024's MAX_SHARED_ARRAY_VALUE, written as a shift.
        "(1<<16)-1": "65535",
    }
    text = JAVA_EXPRESSIONS.get(text.replace(" ", ""), text)
    if re.fullmatch(r"[-+0-9._eE]+[LlFfDd]?", text):
        text = text.rstrip("LlFfDd")
    if java_type == "int":
        return "int", str(int(text, 0))
    if java_type == "long":
        return "int64", str(int(text, 0))
    if java_type == "float":
        return "float32", repr(float(text))
    return "float64", repr(float(text))


def read_constants_from(path: pathlib.Path,
                        strip_comments: bool = False) -> list[tuple[str, str, str]]:
    src = path.read_text()
    if strip_comments:
        # 2021 keeps MAX_ROBOT_ID as a COMMENTED-OUT declaration ("Cannot be
        # guaranteed in Battlecode 2021", because conversions mint new ids).
        # A regex over the raw text picks it up as a live constant, which is
        # exactly the sort of thing a generator is supposed to prevent.
        src = re.sub(r"//[^\n]*", "", src)
    out = []
    seen: dict[str, str] = {}
    for java_type, name, raw in CONST_RE.findall(src):
        # 2023 declares `ANCHOR_WEIGHT = CARRIER_CAPACITY`: an initialiser that
        # names an earlier constant in the same file. Resolve it from what has
        # already been read rather than hand-typing the value here, which is
        # the whole point of a generator.
        key = raw.strip()
        if key in seen:
            raw = seen[key]
        nim_type, literal = nim_literal(java_type, raw)
        seen[name] = raw
        out.append((name, nim_type, literal))
    return out


def read_constants(engine: pathlib.Path) -> list[tuple[str, str, str]]:
    return read_constants_from(
        engine / "engine/src/main/battlecode/common/GameConstants.java")


def read_units(engine: pathlib.Path) -> list[tuple[str, list[str]]]:
    src = (engine / "engine/src/main/battlecode/common/UnitType.java").read_text()
    return [(name, [v.strip() for v in args.split(",")])
            for name, args in UNIT_RE.findall(src)]


def read_traps(engine: pathlib.Path) -> list[tuple[str, list[str]]]:
    src = (engine / "engine/src/main/battlecode/common/TrapType.java").read_text()
    return [(name, [v.strip() for v in args.split(",")])
            for name, args in TRAP_RE.findall(src)]


def camel(name: str) -> str:
    parts = name.split("_")
    return parts[0].capitalize() + "".join(p.capitalize() for p in parts[1:])


def render(engine: pathlib.Path) -> str:
    consts = read_constants(engine)
    units = read_units(engine)
    traps = read_traps(engine)

    lines: list[str] = []
    add = lines.append
    add("## Battlecode 2026 gameplay constants -- GENERATED, do not edit.")
    add("##")
    add(f"## Source: github.com/battlecode/battlecode26 at tag `{TAG}`,")
    add("## files `common/GameConstants.java`, `common/UnitType.java` and")
    add("## `common/TrapType.java`, read by `tools/gen_year_constants.py`.")
    add("## `tests/test_constants.nim` regenerates this file and byte-diffs it,")
    add("## so an edit here fails the build instead of quietly changing the")
    add("## rules under a `GameVersion` that no longer describes them.")
    add("")
    add(f"const EngineTag* = \"{TAG}\"")
    add("")
    add("type")
    add("  UnitType* = enum")
    for name, _ in units:
        add(f"    ut{camel(name)} = \"{name}\"")
    add("")
    add("  TrapType* = enum")
    for name, _ in traps:
        add(f"    tt{camel(name)} = \"{name}\"")
    add("")
    add("  UnitSpec* = object")
    add("    ## `common/UnitType.java`'s constructor arguments, verbatim.")
    add("    health*, size*, visionConeRadiusSquared*, visionConeAngle*: int")
    add("    actionCooldown*, movementCooldown*, bytecodeLimit*: int")
    add("")
    add("  TrapSpec* = object")
    add("    ## `common/TrapType.java`'s constructor arguments, verbatim.")
    add("    buildCost*, damage*, stunTime*: int")
    add("    actionCooldown*, maxCount*, triggerRadiusSquared*: int")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add("  UnitSpecs*: array[UnitType, UnitSpec] = [")
    for name, args in units:
        add(f"    ut{camel(name)}: UnitSpec(health: {args[0]}, size: {args[1]}, "
            f"visionConeRadiusSquared: {args[2]},")
        add(f"      visionConeAngle: {args[3]}, actionCooldown: {args[4]}, "
            f"movementCooldown: {args[5]},")
        add(f"      bytecodeLimit: {args[6]}),")
    add("  ]")
    add("")
    add("  TrapSpecs*: array[TrapType, TrapSpec] = [")
    for name, args in traps:
        add(f"    tt{camel(name)}: TrapSpec(buildCost: {args[0]}, damage: {args[1]}, "
            f"stunTime: {args[2]},")
        add(f"      actionCooldown: {args[3]}, maxCount: {args[4]}, "
            f"triggerRadiusSquared: {args[5]}),")
    add("  ]")
    add("")
    add("  # The per-robot DECISION BUDGET that replaces the engine's JVM")
    add("  # bytecode limit. Hand-authored, not generated: it is this port's")
    add("  # own rule, listed in docs/RULES.md §Divergences.")
    add("  DecisionOpsBabyRat* = 1500")
    add("  DecisionOpsRatKing* = 2500")
    add("  DecisionOpsCat* = 800")
    add("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
#  bc20 — Battlecode 2020 "Soup"
# ---------------------------------------------------------------------------

BC20_COMMIT = "7618f6be7d12da39f2e6e25801e578f1fecfbd86"

# `common/RobotType.java`'s enum entries, one per line, with the constructor
# arguments in declaration order:
#   spawnSource, cost, dirtLimit, soupLimit, actionCooldown,
#   sensorRadiusSquared, pollutionRadiusSquared, localPollutionAdditiveEffect,
#   localPollutionMultiplicativeEffect, globalPollutionAmount,
#   maxSoupProduced, bytecodeLimit
BC20_ROBOT_RE = re.compile(
    r"^\s{4}([A-Z_]+)\s*\(([^)]*)\),\s*$", re.M
)

# The per-robot DECISION BUDGET that replaces the JVM bytecode limit, at one
# tenth of the Java limit. Hand-authored, not generated: it is this port's own
# rule (docs/RULES-BC20.md §Divergences).
BC20_DECISION_OPS = {
    "HQ": 2000,
    "MINER": 1000,
    "LANDSCAPER": 1000,
    "DELIVERY_DRONE": 1000,
    "NET_GUN": 700,
    "REFINERY": 500,
    "VAPORATOR": 500,
    "DESIGN_SCHOOL": 500,
    "FULFILLMENT_CENTER": 500,
    "COW": 0,
}


def read_bc20_robots(engine: pathlib.Path) -> list[tuple[str, list[str]]]:
    src = (engine / "engine/src/main/battlecode/common/RobotType.java").read_text()
    # Cut at the constructor so the field declarations below the enum body are
    # not mistaken for entries.
    body = src.split("RobotType(RobotType spawnSource", 1)[0]
    out = []
    for name, args in BC20_ROBOT_RE.findall(body):
        parts = [v.strip() for v in args.split(",")]
        if len(parts) != 12:
            continue
        out.append((name, parts))
    return out


def bc20_num(text: str) -> str:
    return text.rstrip("LlFfDd")


def render_bc20(engine: pathlib.Path) -> str:
    consts = read_constants_from(
        engine / "engine/src/main/battlecode/common/GameConstants.java")
    robots = read_bc20_robots(engine)
    if len(robots) != 10:
        raise SystemExit(f"::error::expected 10 RobotType entries, saw {len(robots)}")

    lines: list[str] = []
    add = lines.append
    add('## Battlecode 2020 "Soup" gameplay constants -- GENERATED, do not edit.')
    add("##")
    add(f"## Source: github.com/battlecode/battlecode20 at commit `{BC20_COMMIT}`,")
    add("## files `common/GameConstants.java` and `common/RobotType.java`, read by")
    add("## `tools/gen_year_constants.py --year bc20`. The `test` job of")
    add("## `.github/workflows/ci.yml` re-runs that generator with `--check`,")
    add("## which byte-diffs this file, so an edit here fails the build instead")
    add("## of quietly changing the rules under a `GameVersion` that no longer")
    add("## describes them.")
    add("##")
    add("## The two derived functions `getWaterLevel`, `getSensorRadiusPollutionCoefficient`")
    add("## and `getCooldownPollutionCoefficient` are NOT constants and live in")
    add("## `flood.nim` and `pollution.nim`.")
    add("")
    add(f'const EngineCommit* = "{BC20_COMMIT}"')
    add("")
    add("type")
    add("  RobotKind* = enum")
    for name, _ in robots:
        add(f'    rt{camel(name)} = "{name}"')
    add("")
    add("  RobotSpec* = object")
    add("    ## `common/RobotType.java`'s constructor arguments, verbatim.")
    add("    cost*, dirtLimit*, soupLimit*: int")
    add("    actionCooldown*: float32")
    add("    sensorRadiusSquared*, pollutionRadiusSquared*: int")
    add("    localPollutionAdditiveEffect*: int")
    add("    localPollutionMultiplicativeEffect*: float32")
    add("    globalPollutionAmount*, maxSoupProduced*, bytecodeLimit*: int")
    add("    decisionOps*: int")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add("  RobotSpecs*: array[RobotKind, RobotSpec] = [")
    for name, a in robots:
        add(f"    rt{camel(name)}: RobotSpec(cost: {bc20_num(a[1])}, "
            f"dirtLimit: {bc20_num(a[2])}, soupLimit: {bc20_num(a[3])},")
        add(f"      actionCooldown: {bc20_num(a[4])}'f32, "
            f"sensorRadiusSquared: {bc20_num(a[5])},")
        add(f"      pollutionRadiusSquared: {bc20_num(a[6])}, "
            f"localPollutionAdditiveEffect: {bc20_num(a[7])},")
        add(f"      localPollutionMultiplicativeEffect: {bc20_num(a[8])}'f32,")
        add(f"      globalPollutionAmount: {bc20_num(a[9])}, "
            f"maxSoupProduced: {bc20_num(a[10])},")
        add(f"      bytecodeLimit: {bc20_num(a[11])}, "
            f"decisionOps: {BC20_DECISION_OPS[name]}),")
    add("  ]")
    add("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
#  bc21 — Battlecode 2021 "Campaign"
# ---------------------------------------------------------------------------

BC21_COMMIT = "ed39c1a49574db57e5463d720736220506280294"

# `common/RobotType.java`'s enum entries. Unlike 2020 the 2021 entries carry a
# javadoc block each, so they are matched by name and argument list rather than
# by indentation, and the arguments are:
#   spawnSource, convictionRatio, actionCooldown, initialCooldown,
#   actionRadiusSquared, sensorRadiusSquared, detectionRadiusSquared,
#   bytecodeLimit
BC21_ROBOT_RE = re.compile(
    r"^\s{4}(ENLIGHTENMENT_CENTER|POLITICIAN|SLANDERER|MUCKRAKER)"
    r"\s*\(([^)]*)\)\s*,\s*$", re.M
)

# The per-robot DECISION BUDGET that replaces the JVM bytecode limit, at one
# tenth of the Java limit. Hand-authored, not generated: it is this port's own
# rule (docs/RULES-BC21.md §Divergences item 1).
BC21_DECISION_OPS = {
    "ENLIGHTENMENT_CENTER": 2000,
    "POLITICIAN": 1500,
    "SLANDERER": 750,
    "MUCKRAKER": 1500,
}


def f32_literal(text: str) -> str:
    """The EXACT value a Java `float` literal holds, as a Nim float literal.

    Nim keeps a `const` of type `float32` at its COMPILE-TIME double value, so
    `float64(SomeFloat32Const)` yields the double nearest the decimal source
    rather than the float32 the Java constant actually is. `0.2f` is
    0.20000000298023224, and `ceil(0.2f * sqrt(25))` is 2 in Java and 1 under
    the naive transcription — a real, silent, once-every-25-rounds divergence
    that the `ec_passive` table caught. Emitting the widened float32 value
    makes the two identical whichever way Nim folds it.
    """
    value = struct.unpack("<f", struct.pack("<f", float(text)))[0]
    return repr(value)


def read_bc21_robots(engine: pathlib.Path):
    src = (engine / "engine/src/main/battlecode/common/RobotType.java").read_text()
    body = src.split("RobotType(RobotType spawnSource", 1)[0]
    out = []
    for name, args in BC21_ROBOT_RE.findall(body):
        parts = [v.strip() for v in args.split(",")]
        if len(parts) != 8:
            continue
        out.append((name, parts))
    return out


def render_bc21(engine: pathlib.Path) -> str:
    consts = read_constants_from(
        engine / "engine/src/main/battlecode/common/GameConstants.java",
        strip_comments=True)
    robots = read_bc21_robots(engine)
    if len(robots) != 4:
        raise SystemExit(
            f"::error::expected 4 RobotType entries, saw {len(robots)}")

    lines: list[str] = []
    add = lines.append
    add('## Battlecode 2021 "Campaign" gameplay constants -- GENERATED, do not edit.')
    add("##")
    add(f"## Source: github.com/battlecode/battlecode21 at commit `{BC21_COMMIT}`")
    add("## (release 2021.3.0.5), files `common/GameConstants.java` and")
    add("## `common/RobotType.java`, read by")
    add("## `tools/gen_year_constants.py --year bc21`. The `test` job of")
    add("## `.github/workflows/ci.yml` re-runs that generator with `--check`,")
    add("## which byte-diffs this file, so an edit here fails the build instead")
    add("## of quietly changing the rules under a `GameVersion` that no longer")
    add("## describes them.")
    add("##")
    add("## `RobotType.getPassiveInfluence` is NOT a constant: the Enlightenment")
    add("## Center curve and the slanderer embezzle formula live in")
    add("## `economy.nim`, backed by the committed JDK-generated tables in")
    add("## `data/bc21/`.")
    add("")
    add(f'const EngineCommit* = "{BC21_COMMIT}"')
    add('const EngineRelease* = "2021.3.0.5"')
    add("")
    add("type")
    add("  RobotKind* = enum")
    for name, _ in robots:
        add(f'    rt{camel(name)} = "{name}"')
    add("")
    add("  RobotSpec* = object")
    add("    ## `common/RobotType.java`'s constructor arguments, verbatim.")
    add("    ## `convictionRatio`, `actionCooldown` and `initialCooldown` are")
    add("    ## Java `float`s; widening them changes which round a robot is")
    add("    ## ready, so they stay float32 here.")
    add("    convictionRatio*, actionCooldown*, initialCooldown*: float32")
    add("    actionRadiusSquared*, sensorRadiusSquared*: int")
    add("    detectionRadiusSquared*, bytecodeLimit*: int")
    add("    decisionOps*: int")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        if nim_type == "float32":
            literal = f32_literal(literal)
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add("  RobotSpecs*: array[RobotKind, RobotSpec] = [")
    for name, a in robots:
        add(f"    rt{camel(name)}: RobotSpec("
            f"convictionRatio: {f32_literal(bc20_num(a[1]))}'f32,")
        add(f"      actionCooldown: {f32_literal(bc20_num(a[2]))}'f32, "
            f"initialCooldown: {f32_literal(bc20_num(a[3]))}'f32,")
        add(f"      actionRadiusSquared: {bc20_num(a[4])}, "
            f"sensorRadiusSquared: {bc20_num(a[5])},")
        add(f"      detectionRadiusSquared: {bc20_num(a[6])}, "
            f"bytecodeLimit: {bc20_num(a[7])},")
        add(f"      decisionOps: {BC21_DECISION_OPS[name]}),")
    add("  ]")
    add("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
#  Battlecode 2024 "Breadwars"
# ---------------------------------------------------------------------------

BC24_COMMIT = "166c79bbf4156c866caf434062cb1f403c01695f"

BC24_SKILL_RE = re.compile(r"^\s*(ATTACK|BUILD|HEAL)\((.*?)\)\s*[,;]\s*$", re.M)
BC24_TRAP_RE = re.compile(
    r"^\s*(EXPLOSIVE|WATER|STUN|NONE)\s*\((.*?)\)\s*[,;]\s*$", re.M)
BC24_UPGRADE_RE = re.compile(
    r"^\s*(ATTACK|HEALING|CAPTURING|ACTION)\((.*?)\)\s*[,;]\s*$", re.M)
BC24_TABLE_RE = re.compile(r"int\[\]\s+(\w+)\s*=\s*\{([^}]*)\}\s*;")

BC24_DECISION_OPS = 2500
    ## The per-robot budget that replaces the JVM's 25 000-bytecode limit.
    ## One tenth of the Java limit, the same convention bc20 and bc21 use;
    ## docs/RULES-BC24.md §Divergences item 1 and §Tests Tier A carry the
    ## measurement that makes it harmless in this year.


def bc24_tables(src: str) -> dict[str, list[int]]:
    out: dict[str, list[int]] = {}
    for name, body in BC24_TABLE_RE.findall(src):
        out[name] = [int(v.strip()) for v in body.split(",") if v.strip()]
    return out


def render_bc24(engine: pathlib.Path) -> str:
    common = engine / "engine/src/main/battlecode/common"
    consts = read_constants_from(common / "GameConstants.java",
                                 strip_comments=True)
    skill_src = (common / "SkillType.java").read_text()
    trap_src = (common / "TrapType.java").read_text()
    upgrade_src = (common / "GlobalUpgrade.java").read_text()

    skills = [(n, [v.strip() for v in a.split(",")])
              for n, a in BC24_SKILL_RE.findall(skill_src)]
    if len(skills) != 3:
        raise SystemExit(f"::error::expected 3 SkillType entries, saw {len(skills)}")
    tables = bc24_tables(skill_src)
    for needed in ("attackExperience", "buildExperience", "healExperience",
                   "attackCooldown", "buildCooldown", "healCooldown",
                   "attackSkill", "buildSkill", "healSkill",
                   "attackPenalty", "buildPenalty", "healPenalty"):
        if needed not in tables or len(tables[needed]) != 7:
            raise SystemExit(f"::error::SkillType.{needed} is not a 7-entry table")

    traps = [(n, [v.strip() for v in a.split(",")])
             for n, a in BC24_TRAP_RE.findall(trap_src)
             if len([v for v in a.split(",")]) == 10]
    if len(traps) != 4:
        raise SystemExit(f"::error::expected 4 TrapType entries, saw {len(traps)}")

    upgrades = [(n, [v.strip() for v in a.split(",")])
                for n, a in BC24_UPGRADE_RE.findall(upgrade_src)
                if len(a.split(",")) == 4]
    if len(upgrades) != 4:
        raise SystemExit(
            f"::error::expected 4 GlobalUpgrade entries, saw {len(upgrades)}")

    def row(name: str) -> str:
        return "[" + ", ".join(str(v) for v in tables[name]) + "]"

    lines: list[str] = []
    add = lines.append
    add('## Battlecode 2024 "Breadwars" gameplay constants -- GENERATED, do not edit.')
    add("##")
    add(f"## Source: github.com/battlecode/battlecode24 at commit `{BC24_COMMIT}`,")
    add("## files `common/GameConstants.java`, `common/SkillType.java`,")
    add("## `common/TrapType.java` and `common/GlobalUpgrade.java`, read by")
    add("## `tools/gen_year_constants.py --year bc24`. The `test` job of")
    add("## `.github/workflows/ci.yml` re-runs that generator with `--check`,")
    add("## which byte-diffs this file, so an edit here fails the build instead")
    add("## of quietly changing the rules under a `GameVersion` that no longer")
    add("## describes them.")
    add("##")
    add("## `SpecVersion` here is MASTER's string. The released oracle jar is")
    add("## 3.0.5 and every gameplay constant in it is identical; the")
    add("## `parity-oracle-bc24` job proves that rather than assuming it")
    add("## (docs/RULES-BC24.md §Divergences item 9).")
    add("##")
    add("## THE TWO ROUNDING REGIMES are not in this file — they are in")
    add("## `skills.nim`, which is the only place that multiplies these tables")
    add("## out: damage and heal are a Java FLOAT32 product through")
    add("## `Math.round(float)`, and every cooldown and every crumb cost is a")
    add("## FLOAT64 product through `Math.round(double)`.")
    add("")
    add(f'const EngineCommit* = "{BC24_COMMIT}"')
    add('const OracleJarVersion* = "3.0.5"')
    add("")
    add("type")
    add("  SkillKind* = enum")
    for name, _ in skills:
        add(f'    sk{camel(name)} = "{name}"')
    add("")
    add("  TrapKind* = enum")
    for name, _ in traps:
        add(f'    tk{camel(name)} = "{name}"')
    add("")
    add("  UpgradeKind* = enum")
    for name, _ in upgrades:
        add(f'    ug{camel(name)} = "{name}"')
    add("")
    add("  SkillSpec* = object")
    add("    ## `common/SkillType.java`'s constructor arguments plus its four")
    add("    ## seven-entry tables, indexed by LEVEL 0..6.")
    add("    skillEffect*, cooldown*: int")
    add("    experience*: array[7, int]")
    add("    cooldownDelta*: array[7, int]")
    add("    effectDelta*: array[7, int]")
    add("    penalty*: array[7, int]")
    add("")
    add("  TrapSpec* = object")
    add("    ## `common/TrapType.java`'s constructor arguments, verbatim.")
    add("    buildCost*, triggerRadius*, enterRadius*, interactRadius*: int")
    add("    enterDamage*, interactDamage*: int")
    add("    doesDig*: bool")
    add("    actionCooldownIncrease*: int")
    add("    isInvisible*: bool")
    add("    opponentCooldown*: int")
    add("")
    add("  UpgradeSpec* = object")
    add("    ## `common/GlobalUpgrade.java`'s constructor arguments, verbatim.")
    add("    baseAttackChange*, baseHealChange*: int")
    add("    flagReturnDelayChange*, movementDelayChange*: int")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        if nim_type == "float32":
            literal = f32_literal(literal)
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add(f"  DecisionOps*: int = {BC24_DECISION_OPS}")
    add("    ## Replaces `BytecodeLimit` outside the JVM: no mid-turn")
    add("    ## resumption, enforced by the sim rather than by the bot.")
    add("")
    add("  SkillSpecs*: array[SkillKind, SkillSpec] = [")
    prefix = {"ATTACK": "attack", "BUILD": "build", "HEAL": "heal"}
    for name, a in skills:
        p = prefix[name]
        add(f"    sk{camel(name)}: SkillSpec(skillEffect: {bc20_num(a[0])}, "
            f"cooldown: {bc20_num(a[1])},")
        add(f"      experience: {row(p + 'Experience')},")
        add(f"      cooldownDelta: {row(p + 'Cooldown')},")
        add(f"      effectDelta: {row(p + 'Skill')},")
        add(f"      penalty: {row(p + 'Penalty')}),")
    add("  ]")
    add("")
    add("  TrapSpecs*: array[TrapKind, TrapSpec] = [")
    for name, a in traps:
        add(f"    tk{camel(name)}: TrapSpec(buildCost: {a[0]}, "
            f"triggerRadius: {a[1]}, enterRadius: {a[2]},")
        add(f"      interactRadius: {a[3]}, enterDamage: {a[4]}, "
            f"interactDamage: {a[5]},")
        add(f"      doesDig: {a[6]}, actionCooldownIncrease: {a[7]}, "
            f"isInvisible: {a[8]},")
        add(f"      opponentCooldown: {a[9]}),")
    add("  ]")
    add("")
    add("  UpgradeSpecs*: array[UpgradeKind, UpgradeSpec] = [")
    for name, a in upgrades:
        add(f"    ug{camel(name)}: UpgradeSpec(baseAttackChange: {a[0]}, "
            f"baseHealChange: {a[1]},")
        add(f"      flagReturnDelayChange: {a[2]}, "
            f"movementDelayChange: {a[3]}),")
    add("  ]")
    add("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
#  bc25 -- Battlecode 2025 "Chromatic Conflict"
# ---------------------------------------------------------------------------

BC25_COMMIT = "28975a487c1a30ed2b5bed644fe6ecd2c3dd1482"

BC25_UNIT_RE = re.compile(
    r"^\s*(SOLDIER|SPLASHER|MOPPER|LEVEL_(?:ONE|TWO|THREE)_"
    r"(?:PAINT|MONEY|DEFENSE)_TOWER)\((.*?)\)\s*[,;]\s*$", re.M)

BC25_DECISION_OPS_ROBOT = 1750
BC25_DECISION_OPS_TOWER = 2000
    # One tenth of ROBOT_BYTECODE_LIMIT / TOWER_BYTECODE_LIMIT, the same
    # convention bc20, bc21 and bc24 use. docs/RULES-BC25.md §Divergences
    # item 1 carries the measurement that makes it harmless in this year:
    # the 2025 example bot peaks at 14.1-15.0 % of its limit.


def render_bc25(engine: pathlib.Path) -> str:
    common = engine / "engine/src/main/battlecode/common"
    consts = read_constants_from(common / "GameConstants.java",
                                 strip_comments=True)
    unit_src = (common / "UnitType.java").read_text()
    units = [(n, [v.strip() for v in a.split(",")])
             for n, a in BC25_UNIT_RE.findall(unit_src)]
    if len(units) != 12:
        raise SystemExit(
            f"::error::expected 12 UnitType entries, saw {len(units)}")
    for name, a in units:
        if len(a) != 13:
            raise SystemExit(
                f"::error::UnitType.{name} has {len(a)} arguments, expected 13")

    lines: list[str] = []
    add = lines.append
    add('## Battlecode 2025 "Chromatic Conflict" gameplay constants '
        "-- GENERATED, do not edit.")
    add("##")
    add(f"## Source: github.com/battlecode/battlecode25 at commit "
        f"`{BC25_COMMIT}`,")
    add("## files `common/GameConstants.java` and `common/UnitType.java`, read")
    add("## by `tools/gen_year_constants.py --year bc25`. The `test` job of")
    add("## `.github/workflows/ci.yml` re-runs that generator with `--check`,")
    add("## which byte-diffs this file, so an edit here fails the build instead")
    add("## of quietly changing the rules under a `GameVersion` that no longer")
    add("## describes them.")
    add("##")
    add('## `SpecVersion` is the literal string "1" in the 2025 sources, which')
    add("## is useless as a version pin -- so the ORACLE JAR is pinned by")
    add("## sha256 in `tools/oracle/bc25/jar.lock` instead, and Tier B")
    add("## cross-checks every constant here against the jar's own classes")
    add("## (docs/RULES-BC25.md §Divergences item 12).")
    add("##")
    add("## THERE IS NO FLOAT32 ANYWHERE IN BC25 and no transcendental in the")
    add("## round loop: the only floating point is `Math.round(double)` in four")
    add("## places, which is why this year's arithmetic tier is provable over")
    add("## its whole finite domain rather than sampled.")
    add("")
    add(f'const EngineCommit* = "{BC25_COMMIT}"')
    add('const OracleJarVersion* = "3.1.0"')
    add("")
    add("type")
    add("  UnitType* = enum")
    for name, _ in units:
        add(f'    ut{camel(name)} = "{name}"')
    add("")
    add("  UnitSpec* = object")
    add("    ## `common/UnitType.java`'s thirteen constructor arguments, in the")
    add("    ## file's own order. `-1` means the field has no meaning for that")
    add("    ## type and is carried rather than normalised, because the engine")
    add("    ## carries it.")
    add("    paintCost*, moneyCost*, attackCost*, health*, level*: int")
    add("    paintCapacity*, actionCooldown*, actionRadiusSquared*: int")
    add("    attackStrength*, aoeAttackStrength*: int")
    add("    paintPerTurn*, moneyPerTurn*, attackMoneyBonus*: int")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        if nim_type == "float32":
            literal = f32_literal(literal)
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add(f"  DecisionOpsRobot*: int = {BC25_DECISION_OPS_ROBOT}")
    add(f"  DecisionOpsTower*: int = {BC25_DECISION_OPS_TOWER}")
    add("    ## Replace `RobotBytecodeLimit` / `TowerBytecodeLimit` outside the")
    add("    ## JVM: no mid-turn resumption, no mid-primitive cut, enforced by")
    add("    ## the sim rather than by the bot.")
    add("")
    add("  UnitSpecs*: array[UnitType, UnitSpec] = [")
    for name, a in units:
        add(f"    ut{camel(name)}: UnitSpec(paintCost: {a[0]}, "
            f"moneyCost: {a[1]}, attackCost: {a[2]},")
        add(f"      health: {a[3]}, level: {a[4]}, paintCapacity: {a[5]},")
        add(f"      actionCooldown: {a[6]}, actionRadiusSquared: {a[7]},")
        add(f"      attackStrength: {a[8]}, aoeAttackStrength: {a[9]},")
        add(f"      paintPerTurn: {a[10]}, moneyPerTurn: {a[11]},")
        add(f"      attackMoneyBonus: {a[12]}),")
    add("  ]")
    add("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
#  bc23 -- Battlecode 2023 "Tempest"
# ---------------------------------------------------------------------------

BC23_COMMIT = "af42086ecd09709dc603b2aaa9e9b98312c9ef79"

BC23_ROBOT_RE = re.compile(
    r"^\s*(HEADQUARTERS|CARRIER|LAUNCHER|DESTABILIZER|BOOSTER|AMPLIFIER)"
    r"\s*\((.*?)\)\s*[,;]?\s*$", re.M)
BC23_ANCHOR_RE = re.compile(
    r"^\s*(STANDARD|ACCELERATING)\s*\((.*?)\)\s*[,;]\s*$", re.M)

BC23_DECISION_OPS_HQ = 2000
BC23_DECISION_OPS_CARRIER = 1250
BC23_DECISION_OPS_OTHER = 1000
    # One tenth of HEADQUARTERS 20000 / CARRIER 12500 / everything else 10000,
    # the same convention bc20, bc21, bc24 and bc25 use. docs/RULES-BC23.md
    # §Divergences item 1 carries the measurement that makes it harmless in
    # this year: the 2023 example bot peaks at 6.6-6.9 % of its limit with
    # ZERO mid-turn cut-offs over three full 2000-round games.


def render_bc23(engine: pathlib.Path) -> str:
    common = engine / "engine/src/main/battlecode/common"
    consts = read_constants_from(common / "GameConstants.java",
                                 strip_comments=True)
    robot_src = (common / "RobotType.java").read_text()
    robot_src = re.sub(r"//[^\n]*", "", robot_src)
    robot_src = re.sub(r"/\*.*?\*/", "", robot_src, flags=re.S)
    robots = [(n, [v.strip() for v in a.split(",")])
              for n, a in BC23_ROBOT_RE.findall(robot_src)]
    if len(robots) != 6:
        raise SystemExit(
            f"::error::expected 6 RobotType entries, saw {len(robots)}")
    for name, a in robots:
        if len(a) != 10:
            raise SystemExit(
                f"::error::RobotType.{name} has {len(a)} arguments, expected 10")

    anchor_src = (common / "Anchor.java").read_text()
    anchor_src = re.sub(r"//[^\n]*", "", anchor_src)
    anchor_src = re.sub(r"/\*.*?\*/", "", anchor_src, flags=re.S)
    anchors = [(n, [v.strip() for v in a.split(",")])
               for n, a in BC23_ANCHOR_RE.findall(anchor_src)]
    if len(anchors) != 2:
        raise SystemExit(
            f"::error::expected 2 Anchor entries, saw {len(anchors)}")
    for name, a in anchors:
        if len(a) != 8:
            raise SystemExit(
                f"::error::Anchor.{name} has {len(a)} arguments, expected 8")

    lines: list[str] = []
    add = lines.append
    add('## Battlecode 2023 "Tempest" gameplay constants '
        "-- GENERATED, do not edit.")
    add("##")
    add(f"## Source: github.com/battlecode/battlecode23 at commit "
        f"`{BC23_COMMIT}`,")
    add("## files `common/GameConstants.java`, `common/RobotType.java` and")
    add("## `common/Anchor.java`, read by `tools/gen_year_constants.py --year")
    add("## bc23`. The `test` job of `.github/workflows/ci.yml` re-runs that")
    add("## generator with `--check`, which byte-diffs this file, so an edit")
    add("## here fails the build instead of quietly changing the rules under a")
    add("## `GameVersion` that no longer describes them.")
    add("##")
    add('## `SPEC_VERSION` below is the literal string "3.0.14" -- and so is')
    add("## the one inside the RELEASED 3.0.15 jar, which makes it useless as a")
    add("## version pin. The ORACLE JAR is therefore pinned by sha256 in")
    add("## `tools/oracle/bc23/jar.lock` instead, and Tier B cross-checks every")
    add("## constant here against the jar's own classes")
    add("## (docs/RULES-BC23.md §Divergences item 12).")
    add("##")
    add("## THE ONLY FLOAT32 IN BC23 is the conquest threshold 0.75f, the")
    add("## carrier's 1.25f damage factor and 0.375f movement slope, and the")
    add("## accelerating anchor's -0.15f; there is NO TRANSCENDENTAL ANYWHERE,")
    add("## which is why this year's arithmetic tier is provable over its whole")
    add("## finite domain rather than sampled.")
    add("")
    add(f'const EngineCommit* = "{BC23_COMMIT}"')
    add('const OracleJarVersion* = "3.0.15"')
    add("")
    add("type")
    add("  RobotType* = enum")
    for name, _ in robots:
        add(f'    rt{camel(name)} = "{name}"')
    add("")
    add("  AnchorType* = enum")
    add('    anNone = "-"')
    for name, _ in anchors:
        add(f'    an{camel(name)} = "{name}"')
    add("")
    add("  RobotSpec* = object")
    add("    ## `common/RobotType.java`'s ten constructor arguments, in the")
    add("    ## file's own order. `-1` means the field has no meaning for that")
    add("    ## type and is carried rather than normalised, because the engine")
    add("    ## carries it: HEADQUARTERS cannot move, BOOSTER and AMPLIFIER")
    add("    ## have no action radius, AMPLIFIER has no action cooldown.")
    add("    buildCostAdamantium*, buildCostMana*, buildCostElixir*: int")
    add("    actionCooldown*, movementCooldown*, health*, damage*: int")
    add("    actionRadiusSquared*, visionRadiusSquared*, bytecodeLimit*: int")
    add("")
    add("  AnchorSpec* = object")
    add("    ## `common/Anchor.java`'s eight constructor arguments, in the")
    add("    ## file's own order.")
    add("    totalHealth*, unitsAffected*: int")
    add("    accelerationFactor*: float32")
    add("    healingFrequency*, healingAmount*: int")
    add("    manaCost*, adamantiumCost*, elixirCost*: int")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        if nim_type == "float32":
            literal = f32_literal(literal)
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add(f"  DecisionOpsHeadquarters*: int = {BC23_DECISION_OPS_HQ}")
    add(f"  DecisionOpsCarrier*: int = {BC23_DECISION_OPS_CARRIER}")
    add(f"  DecisionOpsOther*: int = {BC23_DECISION_OPS_OTHER}")
    add("    ## Replace `RobotType.bytecodeLimit` outside the JVM: no mid-turn")
    add("    ## resumption, no mid-primitive cut, enforced by the sim rather")
    add("    ## than by the bot.")
    add("")
    add("  RobotSpecs*: array[RobotType, RobotSpec] = [")
    for name, a in robots:
        add(f"    rt{camel(name)}: RobotSpec(buildCostAdamantium: {a[0]},")
        add(f"      buildCostMana: {a[1]}, buildCostElixir: {a[2]},")
        add(f"      actionCooldown: {a[3]}, movementCooldown: {a[4]},")
        add(f"      health: {a[5]}, damage: {a[6]},")
        add(f"      actionRadiusSquared: {a[7]}, visionRadiusSquared: {a[8]},")
        add(f"      bytecodeLimit: {a[9]}),")
    add("  ]")
    add("")
    add("  AnchorSpecs*: array[AnchorType, AnchorSpec] = [")
    add("    anNone: AnchorSpec(totalHealth: 0, unitsAffected: 0,")
    add("      accelerationFactor: 0.0'f32, healingFrequency: 0,")
    add("      healingAmount: 0, manaCost: 0, adamantiumCost: 0,")
    add("      elixirCost: 0),")
    for name, a in anchors:
        add(f"    an{camel(name)}: AnchorSpec(totalHealth: {a[0]},")
        add(f"      unitsAffected: {a[1]},")
        add(f"      accelerationFactor: {f32_literal(a[2].rstrip('fF'))}'f32,")
        add(f"      healingFrequency: {a[3]}, healingAmount: {a[4]},")
        add(f"      manaCost: {a[5]}, adamantiumCost: {a[6]},")
        add(f"      elixirCost: {a[7]}),")
    add("  ]")
    add("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
#  bc22 -- Battlecode 2022 "Mutation"
# ---------------------------------------------------------------------------

BC22_COMMIT = "6ed05b679c0822e9bbe332812ff5655812dd023e"

BC22_ROBOT_RE = re.compile(
    r"^\s*(ARCHON|LABORATORY|WATCHTOWER|MINER|BUILDER|SOLDIER|SAGE)"
    r"\s*\((.*?)\)\s*[,;]?\s*$", re.M)
BC22_ANOMALY_RE = re.compile(
    r"^\s*(ABYSS|CHARGE|FURY|VORTEX)\s*\((.*?)\)\s*[,;]\s*$", re.M)

BC22_DECISION_OPS_ARCHON = 2000
BC22_DECISION_OPS_STANDARD = 1250
BC22_DECISION_OPS_BUILDER = 750
BC22_DECISION_OPS_LABORATORY = 500
    # The same convention bc20, bc21, bc23, bc24 and bc25 use: a tenth of
    # ARCHON 20000, BUILDER 7500 and LABORATORY 5000. The four types on the
    # 10000 limit get 1250 rather than 1000, deliberately -- a bc22 miner's
    # nine-square scan plus its mine-move-mine turn is the busiest primitive
    # sequence in the year (docs/RULES-BC22.md Divergences item 1). docs/RULES-BC22.md §Divergences item 1 carries the
    # measurement that makes it harmless in this year: the 2022 example bot
    # peaks at 6-7 % of its limit with ZERO mid-turn cut-offs over eight full
    # 2000-round games.


def render_bc22(engine: pathlib.Path) -> str:
    common = engine / "engine/src/main/battlecode/common"
    consts = read_constants_from(common / "GameConstants.java",
                                 strip_comments=True)
    robot_src = (common / "RobotType.java").read_text()
    robot_src = re.sub(r"//[^\n]*", "", robot_src)
    robot_src = re.sub(r"/\*.*?\*/", "", robot_src, flags=re.S)
    robots = [(n, [v.strip() for v in a.split(",")])
              for n, a in BC22_ROBOT_RE.findall(robot_src)]
    if len(robots) != 7:
        raise SystemExit(
            f"::error::expected 7 RobotType entries, saw {len(robots)}")
    for name, a in robots:
        if len(a) != 9:
            raise SystemExit(
                f"::error::RobotType.{name} has {len(a)} arguments, expected 9")

    anomaly_src = (common / "AnomalyType.java").read_text()
    anomaly_src = re.sub(r"//[^\n]*", "", anomaly_src)
    anomaly_src = re.sub(r"/\*.*?\*/", "", anomaly_src, flags=re.S)
    anomalies = [(n, [v.strip() for v in a.split(",")])
                 for n, a in BC22_ANOMALY_RE.findall(anomaly_src)]
    if len(anomalies) != 4:
        raise SystemExit(
            f"::error::expected 4 AnomalyType entries, saw {len(anomalies)}")
    for name, a in anomalies:
        if len(a) != 4:
            raise SystemExit(
                f"::error::AnomalyType.{name} has {len(a)} arguments, "
                "expected 4")

    lines: list[str] = []
    add = lines.append
    add('## Battlecode 2022 "Mutation" gameplay constants '
        "-- GENERATED, do not edit.")
    add("##")
    add(f"## Source: github.com/battlecode/battlecode22 at commit "
        f"`{BC22_COMMIT}`,")
    add("## files `common/GameConstants.java`, `common/RobotType.java` and")
    add("## `common/AnomalyType.java`, read by `tools/gen_year_constants.py")
    add("## --year bc22`. The `test` job of `.github/workflows/ci.yml` re-runs")
    add("## that generator with `--check`, which byte-diffs this file, so an")
    add("## edit here fails the build instead of quietly changing the rules")
    add("## under a `GameVersion` that no longer describes them.")
    add("##")
    add('## `SPEC_VERSION` below is "2.2.1" and -- unlike bc23\'s and bc25\'s')
    add("## -- it MATCHES the released jar's own version, so the oracle job")
    add("## asserts the string as well as the sha256 pinned in")
    add("## `tools/oracle/bc22/jar.lock`.")
    add("##")
    add("## THE ONE TRANSCENDENTAL IN BC22 is the laboratory's transmutation")
    add("## rate, `(int)(20.0 - 18.0 * exp(-k*n))`, whose domain is finite")
    add("## (3 levels x n in 0..176) and is therefore TABLED whole into")
    add("## `data/bc22/tables.json` rather than evaluated at run time. Every")
    add("## other non-integer expression -- the float64 rubble multiplier and")
    add("## the float32 prototype, reclaim and anomaly truncations -- is")
    add("## likewise tabled over its whole reachable domain.")
    add("")
    add(f'const EngineCommit* = "{BC22_COMMIT}"')
    add('const OracleJarVersion* = "2.2.1"')
    add("")
    add("type")
    add("  RobotType* = enum")
    for name, _ in robots:
        add(f'    rt{camel(name)} = "{name}"')
    add("")
    add("  AnomalyKind* = enum")
    for name, _ in anomalies:
        add(f'    an{camel(name)} = "{name}"')
    add("")
    add("  RobotSpec* = object")
    add("    ## `common/RobotType.java`'s nine constructor arguments, in the")
    add("    ## file's own order. `damage` is NEGATIVE for a repairer (ARCHON")
    add("    ## -2, BUILDER -2) and `getHealing` is its negation, exactly as")
    add("    ## the engine carries it.")
    add("    buildCostLead*, buildCostGold*: int")
    add("    actionCooldown*, movementCooldown*, health*, damage*: int")
    add("    actionRadiusSquared*, visionRadiusSquared*, bytecodeLimit*: int")
    add("")
    add("  AnomalySpec* = object")
    add("    ## `common/AnomalyType.java`'s four constructor arguments.")
    add("    isGlobalAnomaly*, isSageAnomaly*: bool")
    add("    globalPercentage*, sagePercentage*: float32")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        if nim_type == "float32":
            literal = f32_literal(literal)
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add(f"  DecisionOpsArchon*: int = {BC22_DECISION_OPS_ARCHON}")
    add(f"  DecisionOpsStandard*: int = {BC22_DECISION_OPS_STANDARD}")
    add(f"  DecisionOpsBuilder*: int = {BC22_DECISION_OPS_BUILDER}")
    add(f"  DecisionOpsLaboratory*: int = {BC22_DECISION_OPS_LABORATORY}")
    add("    ## Replace `RobotType.bytecodeLimit` outside the JVM: no mid-turn")
    add("    ## resumption, no mid-primitive cut, enforced by the sim rather")
    add("    ## than by the bot.")
    add("")
    add("  RobotSpecs*: array[RobotType, RobotSpec] = [")
    for name, a in robots:
        add(f"    rt{camel(name)}: RobotSpec(buildCostLead: {a[0]},")
        add(f"      buildCostGold: {a[1]},")
        add(f"      actionCooldown: {a[2]}, movementCooldown: {a[3]},")
        add(f"      health: {a[4]}, damage: {a[5]},")
        add(f"      actionRadiusSquared: {a[6]}, visionRadiusSquared: {a[7]},")
        add(f"      bytecodeLimit: {a[8]}),")
    add("  ]")
    add("")
    add("  AnomalySpecs*: array[AnomalyKind, AnomalySpec] = [")
    for name, a in anomalies:
        add(f"    an{camel(name)}: AnomalySpec("
            f"isGlobalAnomaly: {a[0]}, isSageAnomaly: {a[1]},")
        add(f"      globalPercentage: {f32_literal(a[2].rstrip('fF'))}'f32,")
        add(f"      sagePercentage: {f32_literal(a[3].rstrip('fF'))}'f32),")
    add("  ]")
    add("")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--year", default="bc26",
                    choices=["bc26", "bc20", "bc21", "bc22", "bc23", "bc24",
                             "bc25"])
    ap.add_argument("--engine", required=True, type=pathlib.Path)
    ap.add_argument("--out", type=pathlib.Path, default=None)
    ap.add_argument("--check", action="store_true",
                    help="diff against the committed file; exit 1 on drift")
    args = ap.parse_args()

    out = args.out or pathlib.Path(
        f"src/battlecode/years/{args.year}/constants.nim")
    label = {"bc26": TAG, "bc20": BC20_COMMIT, "bc21": BC21_COMMIT,
             "bc22": BC22_COMMIT,
             "bc23": BC23_COMMIT, "bc24": BC24_COMMIT,
             "bc25": BC25_COMMIT}[args.year]
    text = {"bc26": render, "bc20": render_bc20,
            "bc21": render_bc21, "bc22": render_bc22,
            "bc23": render_bc23,
            "bc24": render_bc24,
            "bc25": render_bc25}[args.year](args.engine)
    if args.check:
        current = out.read_text() if out.exists() else ""
        if current != text:
            sys.stderr.write(
                f"{out} differs from a fresh generation against {label}.\n"
                "Re-run tools/gen_year_constants.py and commit the result.\n")
            return 1
        print(f"{out} matches {label}")
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
